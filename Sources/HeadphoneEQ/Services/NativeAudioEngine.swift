// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreAudio
import AudioToolbox
import AudioDSP
import HeadphoneEQCore
import OSLog

@MainActor
final class NativeAudioEngine {
    private var tap=AudioObjectID(0)
    private var aggregate=AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var dsp: OpaquePointer?
    private(set) var output: OutputDevice?
    private(set) var running=false
    private(set) var processingSampleRate=0.0
    private(set) var captureSampleRate=0.0
    private let log=Logger(subsystem:"com.sm-yjr.headphone-eq",category:"audio")

    func start(settings: EQPreset, bypass: Bool = false) throws {
        stop()
        do {
            try settings.validate()
            let device=try Hardware.defaultOutput()
            guard !device.name.localizedCaseInsensitiveContains("eqMac") else {
                throw AudioFailure.message("请先退出其他系统 EQ，并在系统声音设置中选择实际播放设备。")
            }
            guard device.sampleRate >= 44100 else {
                throw AudioFailure.message("当前可能处于蓝牙通话模式。请将麦克风切回 Mac 或显示器，再启用音乐 EQ。")
            }
            let ownProcess=try Hardware.processObject()
            let description=CATapDescription(excludingProcesses:[ownProcess],deviceUID:device.uid,stream:0)
            description.uuid=UUID(); description.name="Headphone EQ · 系统音频"
            description.isPrivate=true
            description.muteBehavior = .mutedWhenTapped
            // Bind the tap to this output. A device change pauses the engine.
            description.deviceUID=device.uid
            try Hardware.check(AudioHardwareCreateProcessTap(description,&tap),"创建系统音频捕获")
            let format=try Hardware.tapFormat(tap)
            captureSampleRate=format.mSampleRate
            log.info("Capture format rate=\(format.mSampleRate) deviceRate=\(device.sampleRate) id=\(format.mFormatID) flags=\(format.mFormatFlags) bits=\(format.mBitsPerChannel) channels=\(format.mChannelsPerFrame)")
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, format.mChannelsPerFrame == 2 else {
                throw AudioFailure.message("当前输出格式暂不支持，请将音频输出设为双声道 44.1 或 48kHz 后重试。")
            }
            let properties:[String:Any]=[
                kAudioAggregateDeviceNameKey:"Headphone EQ Private",
                kAudioAggregateDeviceUIDKey:"com.sm-yjr.headphone-eq.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey:true,
                kAudioAggregateDeviceIsStackedKey:false,
                kAudioAggregateDeviceMainSubDeviceKey:device.uid,
                kAudioAggregateDeviceSubDeviceListKey:[[kAudioSubDeviceUIDKey:device.uid]],
                kAudioAggregateDeviceTapAutoStartKey:true,
                kAudioAggregateDeviceTapListKey:[[
                    kAudioSubTapUIDKey:description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey:true
                ]]
            ]
            try Hardware.check(AudioHardwareCreateAggregateDevice(properties as CFDictionary,&aggregate),"建立本地音频通道")
            // A device-stream tap follows the physical output format; a global mixdown can be fixed at 48 kHz.
            // Independently validate both IOProc stream formats before touching samples.
            let inputs=try Hardware.streamFormats(aggregate,scope:kAudioObjectPropertyScopeInput)
            let outputs=try Hardware.streamFormats(aggregate,scope:kAudioObjectPropertyScopeOutput)
            let ioFormats=inputs+outputs
            let rate=inputs.first?.mSampleRate ?? 0
            for f in ioFormats {
                log.info("IO format rate=\(f.mSampleRate) flags=\(f.mFormatFlags) bits=\(f.mBitsPerChannel) channels=\(f.mChannelsPerFrame)")
            }
            guard inputs.reduce(0,{$0+$1.mChannelsPerFrame}) == 2,
                  outputs.reduce(0,{$0+$1.mChannelsPerFrame}) == 2,
                  rate >= 44100, abs(format.mSampleRate-rate)<1,
                  ioFormats.allSatisfy({ $0.mFormatID == kAudioFormatLinearPCM && $0.mFormatFlags & kAudioFormatFlagIsFloat != 0 && $0.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 && $0.mBitsPerChannel == 32 && abs($0.mSampleRate-rate)<1 }) else {
                throw AudioFailure.message("当前蓝牙音频流无法以同一采样率处理。请关闭使用耳机麦克风的应用，重新连接耳机后再试。")
            }
            guard let processor=HECreate(rate) else { throw AudioFailure.message("无法建立音频处理器。") }
            processingSampleRate=rate;dsp=processor;try update(settings,bypass:bypass)
            try Hardware.check(AudioDeviceCreateIOProcID(aggregate,HEAudioCallback,UnsafeMutableRawPointer(processor),&ioProc),"连接音频处理器")
            try Hardware.check(AudioDeviceStart(aggregate,ioProc),"开始音频处理")
            output=device; running=true
            log.info("Started output=\(device.name, privacy:.private) rate=\(self.processingSampleRate) tap=\(self.tap) aggregate=\(self.aggregate)")
        } catch {
            stop(); throw error
        }
    }
    func update(_ preset: EQPreset, bypass: Bool = false, attenuationDB: Double = 0) throws {
        guard let dsp else { return }
        try preset.validate()
        let base=preset.effectivePreamp(sampleRate:processingSampleRate)
        guard base >= -60 else { throw AudioFailure.message("曲线叠加增益过高，所需前级低于 −60 dB。请减少滤波器增益后重试。") }
        var filters=(bypass ? [] : preset.bands.filter(\.enabled)).map(\.native)
        let preamp=max(-60,base + min(0,attenuationDB))
        filters.withUnsafeMutableBufferPointer { buffer in
            HESetFilters(dsp,buffer.baseAddress,UInt32(buffer.count),preamp)
        }
        log.info("Updated filters=\(filters.count) preamp=\(preamp)")
    }
    func meters() -> HEMeters? { dsp.map { HEGetMeters($0) } }
    func stop() {
        if aggregate != 0 {
            if let ioProc {
                AudioDeviceStop(aggregate,ioProc)
                AudioDeviceDestroyIOProcID(aggregate,ioProc)
            }
            self.ioProc=nil
            AudioHardwareDestroyAggregateDevice(aggregate); aggregate=0
        }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap);tap=0 }
        if let dsp { HEDestroy(dsp);self.dsp=nil }
        if running { log.info("Stopped; direct system audio restored") }
        running=false;output=nil;processingSampleRate=0;captureSampleRate=0
    }
}
