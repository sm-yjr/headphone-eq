// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreAudio
import AudioToolbox

struct OutputDevice: Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let sampleRate: Double
    let transport: UInt32
    var isBluetooth: Bool { transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE }
}

enum AudioFailure: LocalizedError {
    case operation(String, OSStatus)
    case message(String)
    var errorDescription: String? {
        switch self {
        case let .operation(step,code): return "\(step)失败（\(code)）。请检查系统音频权限后重试。"
        case let .message(text): return text
        }
    }
}

enum Hardware {
    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw AudioFailure.operation(operation,status) }
    }
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector:selector,mScope:scope,mElement:kAudioObjectPropertyElementMain)
    }
    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var a=address(selector), value: Unmanaged<CFString>?
        var size=UInt32(MemoryLayout<CFString>.size)
        try check(AudioObjectGetPropertyData(id,&a,0,nil,&size,&value),"读取设备名称")
        guard let value else { throw AudioFailure.message("设备名称为空。") }
        return value.takeRetainedValue() as String
    }
    static func sampleRate(_ id: AudioObjectID) throws -> Double {
        var a=address(kAudioDevicePropertyNominalSampleRate), value=Double(0)
        var size=UInt32(MemoryLayout<Double>.size)
        try check(AudioObjectGetPropertyData(id,&a,0,nil,&size,&value),"读取采样率")
        return value
    }
    static func transport(_ id: AudioObjectID) throws -> UInt32 {
        var a=address(kAudioDevicePropertyTransportType),value=UInt32(0)
        var size=UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(id,&a,0,nil,&size,&value),"读取音频连接类型")
        return value
    }
    static func defaultOutput() throws -> OutputDevice {
        var a=address(kAudioHardwarePropertyDefaultOutputDevice), id=AudioObjectID(0)
        var size=UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size,&id),"读取当前输出")
        guard id != 0 else { throw AudioFailure.message("未找到音频输出设备。") }
        return try OutputDevice(id:id,uid:string(id,kAudioDevicePropertyDeviceUID),name:string(id,kAudioObjectPropertyName),sampleRate:sampleRate(id),transport:transport(id))
    }
    static func processObject() throws -> AudioObjectID {
        var a=address(kAudioHardwarePropertyTranslatePIDToProcessObject), pid=getpid(), value=AudioObjectID(0)
        var size=UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,UInt32(MemoryLayout<pid_t>.size),&pid,&size,&value),"隔离自身音频")
        guard value != 0 else { throw AudioFailure.message("无法隔离应用自身音频，已停止启用以避免回授。") }
        return value
    }
    static func streamFormats(_ device: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [AudioStreamBasicDescription] {
        var a=address(kAudioDevicePropertyStreams,scope:scope),size=UInt32(0)
        try check(AudioObjectGetPropertyDataSize(device,&a,0,nil,&size),"读取音频流列表")
        guard size > 0 else { return [] }
        var streams=[AudioStreamID](repeating:0,count:Int(size)/MemoryLayout<AudioStreamID>.size)
        let result=streams.withUnsafeMutableBytes { AudioObjectGetPropertyData(device,&a,0,nil,&size,$0.baseAddress!) }
        try check(result,"读取音频流")
        return try streams.map { stream in
            var address=Self.address(kAudioStreamPropertyVirtualFormat),format=AudioStreamBasicDescription()
            var bytes=UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(stream,&address,0,nil,&bytes,&format),"读取处理格式")
            return format
        }
    }
    static func tapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var a=address(kAudioTapPropertyFormat), value=AudioStreamBasicDescription()
        var size=UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tap,&a,0,nil,&size,&value),"读取捕获格式")
        return value
    }
}
