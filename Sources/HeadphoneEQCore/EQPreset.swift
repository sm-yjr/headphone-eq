// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AudioDSP

public enum FilterKind: String, Codable, CaseIterable, Sendable {
    case peak, lowShelf, highShelf
    public var label: String { switch self { case .peak: return "Peak"; case .lowShelf: return "Low shelf"; case .highShelf: return "High shelf" } }
    public var native: HEFilterType { switch self { case .peak: return HEPeak; case .lowShelf: return HELowShelf; case .highShelf: return HEHighShelf } }
    public var apo: String { switch self { case .peak: return "PK"; case .lowShelf: return "LSC"; case .highShelf: return "HSC" } }
}
public struct EQBand: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var kind: FilterKind
    public var frequency: Double
    public var gain: Double
    public var q: Double
    public var enabled: Bool
    public init(_ id: Int, _ kind: FilterKind, _ frequency: Double, _ gain: Double, _ q: Double, enabled: Bool = true) {
        self.id=id;self.kind=kind;self.frequency=frequency;self.gain=gain;self.q=q;self.enabled=enabled
    }
    public var native: HEFilter { HEFilter(frequency:frequency,gain:enabled ? gain : 0,q:q,type:kind.native) }
    public func response(at frequency: Double, sampleRate: Double = 48000) -> Double {
        enabled ? HEFilterResponse(native,sampleRate,frequency) : 0
    }
    public var isValid: Bool {
        (0...9999).contains(id) && frequency.isFinite && (20...20000).contains(frequency) && gain.isFinite && (-18...18).contains(gain) && q.isFinite && (0.1...20).contains(q)
    }
}
public struct EQPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var author: String
    public var sourceURL: String
    public var notes: String
    public var bands: [EQBand]
    public var preamp: Double
    public init(id: UUID = UUID(), name: String, bands: [EQBand] = [], preamp: Double = 0, author: String = "", sourceURL: String = "", notes: String = "") {
        self.id=id;self.name=name;self.bands=bands;self.preamp=preamp;self.author=author;self.sourceURL=sourceURL;self.notes=notes
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, name.count<=120 else { throw PresetError.invalid("预设名称需要 1–120 个字符。") }
        guard bands.count<=16, Set(bands.map(\.id)).count==bands.count else { throw PresetError.invalid("最多支持 16 段，每段编号必须唯一。") }
        guard preamp.isFinite, (-60...0).contains(preamp), bands.allSatisfy(\.isValid) else { throw PresetError.invalid("频率需在 20–20000 Hz，增益 ±18 dB，Q 为 0.1–20，前级为 −60–0 dB。") }
        guard author.count<=300,sourceURL.count<=2000,notes.count<=10000 else { throw PresetError.invalid("预设说明过长。") }
    }
    public func response(at frequency:Double,sampleRate:Double=48000) -> Double {
        bands.reduce(0) { $0+$1.response(at:frequency,sampleRate:sampleRate) }
    }
    /// Conservative frequency-domain headroom; does not claim a true-peak limiter.
    public func effectivePreamp(sampleRate:Double) -> Double {
        let ceiling=sampleRate*0.499
        guard ceiling>20 else { return -60 }
        var maximum=0.0
        for i in 0...4096 { maximum=max(maximum,response(at:pow(ceiling,Double(i)/4096),sampleRate:sampleRate)) }
        return min(preamp,-maximum-0.8)
    }
    public static var factory: [EQPreset] {
        [EQPreset(id:UUID(uuidString:"5E887AD0-BBE1-4C6C-A598-02B0D2553A01")!,name:"Flat · 原始频响",notes:"不改变频响。处理时保留数字余量。"),
         EQPreset(id:UUID(uuidString:"5E887AD0-BBE1-4C6C-A598-02B0D2553A02")!,name:"Warm · 柔和暖声",bands:[.init(1,.lowShelf,90,2,0.71),.init(2,.peak,3000,-1.2,0.8),.init(3,.highShelf,7000,-0.5,0.71)],preamp:-3,author:"Headphone EQ",notes:"通用音色示例，不是任何耳机的测量校正。")]
    }
}
public struct PresetLibrary: Codable, Sendable {
    public var version: Int = 1
    public var presets: [EQPreset]
    public init(presets:[EQPreset]) { self.presets=presets }
    public func validate() throws {
        guard version==1,presets.count<=200,Set(presets.map(\.id)).count==presets.count else { throw PresetError.invalid("不支持的预设库版本、过多预设或重复标识。") }
        for p in presets { try p.validate() }
    }
}
public enum PresetError: LocalizedError {
    case invalid(String)
    public var errorDescription:String? { if case let .invalid(message)=self { return message };return nil }
}
