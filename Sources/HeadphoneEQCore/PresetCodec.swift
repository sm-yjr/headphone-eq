// SPDX-License-Identifier: GPL-3.0-only
import Foundation

public enum PresetCodec {
    public static let maximumBytes=1_048_576
    public static func decode(_ data:Data,name:String) throws -> EQPreset {
        guard data.count<=maximumBytes else { throw PresetError.invalid("文件超过 1 MB，请导入单个 EQ 预设。") }
        if let first=data.first(where:{ ![9,10,13,32].contains($0) }),first==123 {
            let preset:EQPreset
            do { preset=try JSONDecoder().decode(EQPreset.self,from:data) }
            catch { throw PresetError.invalid("JSON 格式无效，请使用 Headphone EQ 导出的单个预设。") }
            try preset.validate();return preset
        }
        guard let text=String(data:data,encoding:.utf8) else { throw PresetError.invalid("请选择 UTF-8 文本或 JSON 预设。") }
        return try parseAPO(text,name:name)
    }
    public static func parseAPO(_ text:String,name:String) throws -> EQPreset {
        let number="([-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+))"
        let preamp=try NSRegularExpression(pattern:"^Preamp:\\s*"+number+"\\s*dB$",options:.caseInsensitive)
        let filter=try NSRegularExpression(pattern:"^Filter\\s+([0-9]+):\\s*(ON|OFF)\\s+(PK|PEQ|LSC|HSC)\\s+Fc\\s+"+number+"\\s*Hz\\s+Gain\\s+"+number+"\\s*dB\\s+Q\\s+"+number+"$",options:.caseInsensitive)
        var preset=EQPreset(name:name);var sawPreamp=false;var recognized=false
        for (index,raw) in text.components(separatedBy:.newlines).enumerated() {
            let line=raw.components(separatedBy:"#")[0].trimmingCharacters(in:.whitespaces)
            if line.isEmpty { continue }
            let range=NSRange(line.startIndex...,in:line)
            func group(_ match:NSTextCheckingResult,_ i:Int)->String { String(line[Range(match.range(at:i),in:line)!]) }
            if let m=preamp.firstMatch(in:line,range:range) {
                guard !sawPreamp,let value=Double(group(m,1)) else { throw PresetError.invalid("前级重复或无效。") }
                preset.preamp=value;sawPreamp=true;recognized=true
            } else if let m=filter.firstMatch(in:line,range:range) {
                let type=group(m,3).uppercased(),kind:FilterKind
                switch type { case "PK","PEQ":kind = .peak;case "LSC":kind = .lowShelf;default:kind = .highShelf }
                guard let id=Int(group(m,1)),let frequency=Double(group(m,4)),let gain=Double(group(m,5)),let q=Double(group(m,6)) else { throw PresetError.invalid("第 \(index+1) 行的数字超出范围。") }
                guard preset.bands.count<16 else { throw PresetError.invalid("最多支持 16 段。") }
                preset.bands.append(.init(id,kind,frequency,gain,q,enabled:group(m,2).uppercased()=="ON"));recognized=true
            } else { throw PresetError.invalid("第 \(index+1) 行不支持。支持 Preamp 与 PK / LSC / HSC（含 Q）；GraphicEQ、卷积和声道指令暂不支持。") }
        }
        guard recognized else { throw PresetError.invalid("文件里没有找到可用 EQ 参数。") }
        try preset.validate();return preset
    }
    public static func encodeJSON(_ preset:EQPreset) throws -> Data {
        try preset.validate();let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];return try encoder.encode(preset)
    }
    public static func encodeAPO(_ preset:EQPreset) throws -> String {
        try preset.validate()
        func number(_ value:Double)->String { String(format:"%.6g",locale:Locale(identifier:"en_US_POSIX"),value) }
        return (["# \(preset.name.components(separatedBy:.newlines).joined(separator:" "))","# Exported by Headphone EQ","Preamp: \(number(preset.preamp)) dB"] + preset.bands.map { "Filter \($0.id): \($0.enabled ? "ON" : "OFF") \($0.kind.apo) Fc \(number($0.frequency)) Hz Gain \(number($0.gain)) dB Q \(number($0.q))" }).joined(separator:"\n")+"\n"
    }
}
