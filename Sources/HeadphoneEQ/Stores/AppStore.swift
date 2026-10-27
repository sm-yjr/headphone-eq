// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import Combine
import UniformTypeIdentifiers
import AudioDSP
import HeadphoneEQCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var presets:[EQPreset]=[]
    @Published private(set) var selectedID:UUID?
    @Published private(set) var isRunning=false
    @Published private(set) var outputName="读取输出…"
    @Published private(set) var sampleRate=48000.0
    @Published private(set) var inputPeak=Float(0)
    @Published private(set) var outputPeak=Float(0)
    @Published private(set) var frames:UInt64=0
    @Published private(set) var clipped:UInt64=0
    @Published private(set) var invalidSamples:UInt64=0
    @Published private(set) var diagnosticActive=false
    @Published private(set) var bypass=false
    @Published var message:String?
    @Published var showImport=false
    @Published var showParameters=false
    @Published var showPermissionInfo=false
    @Published var showDelete=false
    @Published var importText=""
    @Published var importName="我的 EQ"
    @Published var importError:String?
    @Published var showHelp=false
    private let engine=NativeAudioEngine()
    private var timer:Timer?
    private var sleepObserver:NSObjectProtocol?
    private var diagnosticEnd:Date?
    private var tickCount=0
    private var observedUID:String?
    private var runningUID:String?
    private var startTime=Date()
    private var bindings:[String:String]=[:]
    private let storage:URL
    private var persistenceFailed=false

    var selected:EQPreset { presets.first(where:{$0.id==selectedID}) ?? EQPreset.factory[0] }
    @Published private(set) var effectivePreamp:Double = -0.8
    var statusText:String {
        if !isRunning { return "已暂停 · 系统直通" }
        if diagnosticActive { return "链路验证中 · 降低 30 dB，10 秒后恢复" }
        if frames==0 { return "等待音频输入" }
        if inputPeak<0.00001 { return "已就绪 · 请播放音乐" }
        return bypass ? "原声对照 · 保留相同前级" : "正在处理 · EQ 开启"
    }
    var eqMacRunning:Bool { NSWorkspace.shared.runningApplications.contains{$0.bundleIdentifier=="com.bitgapp.eqmac"} }

    init(preview:Bool=false) {
        let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("HeadphoneEQ")
        storage=folder.appendingPathComponent("presets.json")
        if preview {
            presets=EQPreset.factory;selectedID=presets[1].id;outputName="Stereo headphones";showParameters=true
            effectivePreamp=selected.effectivePreamp(sampleRate:sampleRate);return
        }
        do {
            if FileManager.default.fileExists(atPath:storage.path) {
                let library=try JSONDecoder().decode(PresetLibrary.self,from:Data(contentsOf:storage));try library.validate()
                presets=library.presets
            } else { presets=EQPreset.factory }
        } catch {
            // Never overwrite a library that could not be read.
            persistenceFailed=true;presets=EQPreset.factory
            message="预设库无法读取，原文件已保留。请从备份恢复后重新打开应用。"
        }
        if presets.isEmpty { presets=EQPreset.factory }
        let savedID=UUID(uuidString:UserDefaults.standard.string(forKey:"library.selected.v1") ?? "")
        selectedID=presets.first(where:{$0.id==savedID})?.id ?? presets.first?.id
        bindings=UserDefaults.standard.dictionary(forKey:"library.outputBindings.v1") as? [String:String] ?? [:]
        refreshOutput()
        effectivePreamp=selected.effectivePreamp(sampleRate:sampleRate)
        timer=Timer(timeInterval:0.2,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        RunLoop.main.add(timer!,forMode:.common)
        sleepObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.stop();self?.message="Mac 已睡眠。唤醒后确认输出，再重新开启。" }
        }
    }
    func select(_ id:UUID) {
        guard presets.contains(where:{$0.id==id}) else { return }
        selectedID=id;bypass=false
        if let observedUID { bindings[observedUID]=id.uuidString }
        persist();apply()
    }
    func setBypass(_ value:Bool) { bypass=value;apply() }
    func update(_ mutation:(inout EQPreset)->Void) {
        guard let i=presets.firstIndex(where:{$0.id==selectedID}) else { return }
        var candidate=presets[i];mutation(&candidate)
        do { try candidate.validate();presets[i]=candidate;persist();apply() }
        catch { message=error.localizedDescription }
    }
    func editBand(_ id:Int,_ path:WritableKeyPath<EQBand,Double>,_ value:Double) {
        update { preset in if let index=preset.bands.firstIndex(where:{$0.id==id}) { preset.bands[index][keyPath:path]=value } }
    }
    func setBandKind(_ id:Int,_ kind:FilterKind) { update { p in if let i=p.bands.firstIndex(where:{$0.id==id}) { p.bands[i].kind=kind } } }
    func toggleBand(_ id:Int) { update { p in if let i=p.bands.firstIndex(where:{$0.id==id}) { p.bands[i].enabled.toggle() } } }
    func removeBand(_ id:Int) { update { $0.bands.removeAll(where:{$0.id==id}) } }
    func addBand() {
        guard selected.bands.count<16 else { return }
        update { $0.bands.append(.init(($0.bands.map(\.id).max() ?? 0)+1,.peak,1000,0,1)) }
    }
    func duplicate() {
        guard presets.count<200 else { message="预设库已达到 200 个上限。";return }
        var copy=selected;copy.id=UUID();copy.name=String((copy.name+" · 副本").prefix(120));presets.append(copy);select(copy.id)
    }
    func newPreset() { guard presets.count<200 else { message="预设库已达到 200 个上限。";return };let p=EQPreset(name:"自定义 EQ");presets.append(p);select(p.id);showParameters=true }
    func deleteSelected() {
        guard let id=selectedID else { return }
        presets.removeAll(where:{$0.id==id});bindings=bindings.filter{$0.value != id.uuidString}
        if presets.isEmpty { presets=[EQPreset.factory[0]] }
        selectedID=presets.first?.id;bypass=false;persist();apply()
    }
    private func persist() {
        UserDefaults.standard.set(selectedID?.uuidString,forKey:"library.selected.v1")
        UserDefaults.standard.set(bindings,forKey:"library.outputBindings.v1")
        guard !persistenceFailed else { return }
        do {
            let library=PresetLibrary(presets:presets);try library.validate()
            try FileManager.default.createDirectory(at:storage.deletingLastPathComponent(),withIntermediateDirectories:true)
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(library).write(to:storage,options:.atomic)
        } catch { message="无法保存预设：\(error.localizedDescription)" }
    }
    private func apply() {
        effectivePreamp=selected.effectivePreamp(sampleRate:sampleRate)
        do { try engine.update(selected,bypass:bypass,attenuationDB:diagnosticActive ? -30 : 0) }
        catch { stop();message=error.localizedDescription }
        writeStatus()
    }
    func importPreset(_ data:Data,name:String) {
        do {
            var p=try PresetCodec.decode(data,name:name);p.id=UUID()
            guard presets.count<200 else { throw PresetError.invalid("预设库已达到 200 个上限。") }
            presets.append(p);select(p.id);message="已导入 \(p.name)";importError=nil;showImport=false
        } catch { importError=error.localizedDescription;message=error.localizedDescription }
    }
    func importPastedText() { importPreset(Data(importText.utf8),name:importName) }
    func chooseImportFile() {
        let panel=NSOpenPanel();panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
        panel.allowedContentTypes=[.plainText,.json,UTType(filenameExtension:"cfg") ?? .plainText]
        panel.message="导入 Equalizer APO 参数文本或 Headphone EQ JSON。"
        present(panel) { [weak self] result in Task { @MainActor in
            guard result == .OK,let url=panel.url,let self else { return }
            let access=url.startAccessingSecurityScopedResource();defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let values=try url.resourceValues(forKeys:[.fileSizeKey])
                guard (values.fileSize ?? 0)<=PresetCodec.maximumBytes else { throw PresetError.invalid("文件超过 1 MB。") }
                self.importPreset(try Data(contentsOf:url),name:url.deletingPathExtension().lastPathComponent)
            } catch { self.message=error.localizedDescription }
        } }
    }
    private func present(_ panel:NSSavePanel,completion:@escaping(NSApplication.ModalResponse)->Void) {
        if let window=NSApp.windows.first(where:{$0.identifier?.rawValue=="main"}) ?? NSApp.mainWindow {
            panel.beginSheetModal(for:window,completionHandler:completion)
        } else { panel.begin(completionHandler:completion) }
    }
    func copyPreset(json:Bool) {
        do {
            let text=json ? String(decoding:try PresetCodec.encodeJSON(selected),as:UTF8.self) : try PresetCodec.encodeAPO(selected)
            NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)
            message=json ? "JSON 已复制到剪贴板。" : "Equalizer APO 参数已复制到剪贴板。"
        } catch { message=error.localizedDescription }
    }
    func exportPreset(json:Bool) {
        let preset=selected,panel=NSSavePanel()
        panel.nameFieldStringValue=preset.name.replacingOccurrences(of:"/",with:"-")+(json ? ".json" : ".txt")
        panel.allowedContentTypes=json ? [.json] : [.plainText]
        panel.allowsOtherFileTypes=true;panel.isExtensionHidden=false;panel.canCreateDirectories=true
        panel.directoryURL=FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first
        present(panel) { [weak self] result in Task { @MainActor in
            guard result == .OK,let url=panel.url else { return }
            do {
                let data=json ? try PresetCodec.encodeJSON(preset) : Data(try PresetCodec.encodeAPO(preset).utf8)
                try data.write(to:url,options:.atomic);self?.message="已导出 \(url.lastPathComponent)"
            } catch { self?.message=error.localizedDescription }
        } }
    }
    func toggleProcessing() {
        if isRunning { stop() }
        else if !UserDefaults.standard.bool(forKey:"audioConsentExplained") {
            UserDefaults.standard.set(true,forKey:"audioConsentExplained");showPermissionInfo=true
        } else { start() }
    }
    func start() {
        guard !eqMacRunning else { message="请先退出 eqMac，避免叠加两套系统 EQ。";return }
        do {
            try engine.start(settings:selected,bypass:bypass)
            isRunning=true;frames=0;clipped=0;invalidSamples=0;message=nil;startTime=Date();runningUID=engine.output?.uid
            writeStatus()
        } catch { isRunning=false;message=error.localizedDescription;writeStatus() }
    }
    func stop() { diagnosticEnd=nil;diagnosticActive=false;engine.stop();isRunning=false;inputPeak=0;outputPeak=0;writeStatus() }
    func testRoute() {
        guard isRunning else { return }
        diagnosticActive.toggle();diagnosticEnd=diagnosticActive ? Date().addingTimeInterval(10) : nil;apply()
    }
    func shutdown() { stop();persist();timer?.invalidate() }
    func openSoundSettings() { if let url=URL(string:"x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(url) } }
    func openPermissions() { if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") { NSWorkspace.shared.open(url) } }
    private func refreshOutput() {
        guard let output=try? Hardware.defaultOutput() else { outputName="未找到输出设备";return }
        let changedRate=sampleRate != output.sampleRate
        outputName=output.name;sampleRate=output.sampleRate
        if changedRate { effectivePreamp=selected.effectivePreamp(sampleRate:sampleRate) }
        if observedUID != output.uid {
            observedUID=output.uid
            if let id=bindings[output.uid].flatMap(UUID.init(uuidString:)),presets.contains(where:{$0.id==id}) { selectedID=id;bypass=false }
            else {
                let flat=EQPreset.factory[0]
                if !presets.contains(where:{$0.id==flat.id}),presets.count<200 { presets.insert(flat,at:0) }
                selectedID=presets.first(where:{$0.id==flat.id})?.id ?? presets.first?.id;bypass=false
            }
            effectivePreamp=selected.effectivePreamp(sampleRate:sampleRate)
        }
    }
    private func tick() {
        tickCount+=1
        if let end=diagnosticEnd,Date()>=end { diagnosticEnd=nil;diagnosticActive=false;apply() }
        if let m=engine.meters() { inputPeak=m.inputPeak;outputPeak=m.outputPeak;frames=m.frames;clipped=m.clipped;invalidSamples=m.invalidSamples }
        guard tickCount%5==0 else { return }
        if isRunning {
            if let output=try? Hardware.defaultOutput() {
                if output.uid != runningUID || abs(output.sampleRate-sampleRate)>1 { stop();message="输出或采样率已变化。请确认预设，再重新开启。" }
            } else { stop();message="输出设备已断开。" }
        }
        refreshOutput()
        if isRunning,frames==0,Date().timeIntervalSince(startTime)>8 { message="尚未收到音频。请播放音乐，并检查系统音频录制权限。" }
        else if frames>0,message?.hasPrefix("尚未收到音频") == true { message=nil }
        writeStatus()
    }
    private func writeStatus() {
        let status:[String:Any]=["running":isRunning,"preset":selected.name,"bypass":bypass,"output":outputName,"sampleRate":sampleRate,"processingSampleRate":engine.processingSampleRate,"captureSampleRate":engine.captureSampleRate,"frames":frames,"inputPeak":inputPeak,"outputPeak":outputPeak,"clippedSamples":clipped,"invalidSamples":invalidSamples,"diagnosticAttenuationDB":diagnosticActive ? -30 : 0,"preampDB":effectivePreamp,"message":message ?? "","updated":Date().timeIntervalSince1970]
        if let data=try? JSONSerialization.data(withJSONObject:status,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:storage.deletingLastPathComponent().appendingPathComponent("status.json"),options:.atomic) }
    }
}
