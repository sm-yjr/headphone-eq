// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreAudio
import AudioDSP
import HeadphoneEQCore

// Standalone verification runner: works with Command Line Tools, without XCTest.
private func check(_ condition: @autoclosure () -> Bool, _ message:String = "Verification failed", file:StaticString = #file,line:UInt = #line) {
    precondition(condition(),message,file:file,line:line)
}
private func near(_ actual:Double,_ expected:Double,_ tolerance:Double=0.02) { check(abs(actual-expected)<=tolerance,"\(actual) != \(expected)") }
private func rejects(_ operation:() throws -> Void) { do { try operation();preconditionFailure("Invalid input was accepted") } catch {} }

@main struct AudioTests {
    static func main() throws {
        try codecs()
        responses()
        callbacks()
        print("PASS: strict preset import, JSON/APO round trips, headroom, DSP response at 44.1/48/96 kHz, stereo isolation, planar/interleaved callbacks, switching, diagnostic restoration, clipping and non-finite protection")
    }
    static var synthetic:EQPreset {
        EQPreset(name:"Synthetic verification fixture",bands:[.init(1,.lowShelf,85,4,0.71),.init(2,.peak,1700,-3,1.1),.init(3,.highShelf,6500,2,0.71),.init(4,.peak,4500,9,20,enabled:false)],preamp:-6)
    }
    static func codecs() throws {
        for preset in EQPreset.factory+[synthetic] {
            try preset.validate()
            let decoded=try PresetCodec.decode(PresetCodec.encodeJSON(preset),name:"ignored");check(decoded==preset)
            let text=try PresetCodec.encodeAPO(preset)
            let restored=try PresetCodec.decode(Data(text.utf8),name:preset.name)
            check(restored.bands==preset.bands);near(restored.preamp,preset.preamp)
        }
        for text in ["", "GraphicEQ: 20 0; 1000 2", "Preamp: 0 dB\nPreamp: -2 dB", "Preamp: 1 dB", "Filter 1: ON PK Fc 1 Hz Gain 2 dB Q 1", "Filter 999999999999999999999999999999: ON PK Fc 1000 Hz Gain 2 dB Q 1", "Filter 1: ON PK Fc 1000 Hz Gain 2 dB Q 0", "Filter 1: ON LS Fc 100 Hz Gain 2 dB Q 1", "Filter 1: ON PK Fc 1000 Hz Gain 2 dB Q 1\nFilter 1: OFF PK Fc 2000 Hz Gain 0 dB Q 1", "{broken}"] {
            rejects { _=try PresetCodec.decode(Data(text.utf8),name:"Invalid") }
        }
        rejects { _=try PresetCodec.decode(Data(repeating:65,count:PresetCodec.maximumBytes+1),name:"Large") }
        let duplicate=synthetic;rejects { try PresetLibrary(presets:[duplicate,duplicate]).validate() }
        var broken=synthetic;broken.bands[0].gain = .nan;rejects { try broken.validate() }
        var tooMany=synthetic;tooMany.bands=(0..<17).map { .init($0,.peak,1000,0,1) };rejects { try tooMany.validate() }
        let commented=try PresetCodec.parseAPO("# comment\r\nPreamp: -3 dB # note\r\nFilter 7: OFF PK Fc 1000 Hz Gain 2 dB Q 1",name:"Disabled")
        check(!commented.bands[0].enabled);near(commented.response(at:1000),0)
    }
    static func responses() {
        near(EQBand(1,.peak,1000,6,1.4).response(at:1000),6,1e-7)
        near(EQBand(1,.lowShelf,100,4,0.71).response(at:1),4,0.001)
        near(EQBand(1,.highShelf,6000,3,0.71).response(at:23999),3,0.001)
        let stress=EQPreset(name:"High Q / near Nyquist",bands:[.init(1,.peak,20000,18,20),.init(2,.lowShelf,20,12,20)])
        for rate in [44100.0,48000,96000] {
            for preset in EQPreset.factory+[synthetic,stress] {
                let preamp=preset.effectivePreamp(sampleRate:rate)
                for i in 0...8192 {
                    let f=pow(rate*0.499,Double(i)/8192)
                    let db=preset.response(at:f,sampleRate:rate)+preamp
                    check(db.isFinite && db<0,"Headroom failed at \(f) Hz")
                }
            }
            for preset in EQPreset.factory+[synthetic] {
                for frequency in [30.0,100,1000,3000,12000] {
                    let dsp=HECreate(rate)!;defer { HEDestroy(dsp) }
                    let n=Int(rate),filters=preset.bands.map(\.native),base=preset.effectivePreamp(sampleRate:rate)
                    var input=[Float](repeating:0,count:n*2),output=input
                    for i in 0..<n { input[2*i]=Float(0.1*sin(2*Double.pi*frequency*Double(i)/rate)) }
                    for attenuation in [0.0,-30,0] {
                        filters.withUnsafeBufferPointer { HESetFilters(dsp,$0.baseAddress,UInt32($0.count),base+attenuation) }
                        input.withUnsafeBufferPointer { a in output.withUnsafeMutableBufferPointer { b in HEProcessStereo(dsp,a.baseAddress!,b.baseAddress!,UInt32(n)) } }
                        let a=(n/2..<n).reduce(0.0) { $0+Double(input[2*$1])*Double(input[2*$1]) }
                        let b=(n/2..<n).reduce(0.0) { $0+Double(output[2*$1])*Double(output[2*$1]) }
                        near(10*log10(b/a),preset.response(at:frequency,sampleRate:rate)+base+attenuation)
                        check(stride(from:1,to:n*2,by:2).allSatisfy { output[$0]==0 })
                        check(HEGetMeters(dsp).clipped==0 && HEGetMeters(dsp).invalidSamples==0)
                    }
                    // Reference removes filters while retaining the very same preamp.
                    HESetFilters(dsp,nil,0,base)
                    input.withUnsafeBufferPointer { a in output.withUnsafeMutableBufferPointer { b in HEProcessStereo(dsp,a.baseAddress!,b.baseAddress!,UInt32(n)) } }
                    let a=(n/2..<n).reduce(0.0) { $0+Double(input[2*$1])*Double(input[2*$1]) }
                    let b=(n/2..<n).reduce(0.0) { $0+Double(output[2*$1])*Double(output[2*$1]) }
                    near(10*log10(b/a),base)
                }
            }
        }
    }
    static func callbacks() {
        let dsp=HECreate(48000)!;defer { HEDestroy(dsp) }
        HESetFilters(dsp,nil,0,-6)
        let n=4096
        let left=UnsafeMutablePointer<Float>.allocate(capacity:n),right=UnsafeMutablePointer<Float>.allocate(capacity:n)
        let output=UnsafeMutablePointer<Float>.allocate(capacity:n*2)
        defer { left.deallocate();right.deallocate();output.deallocate() }
        left.initialize(repeating:0.2,count:n);right.initialize(repeating:-0.1,count:n);output.initialize(repeating:99,count:n*2)
        let listMemory=UnsafeMutableRawPointer.allocate(byteCount:MemoryLayout<AudioBufferList>.size+MemoryLayout<AudioBuffer>.stride,alignment:MemoryLayout<AudioBufferList>.alignment)
        defer { listMemory.deallocate() }
        let listPointer=listMemory.bindMemory(to:AudioBufferList.self,capacity:1)
        listPointer.initialize(to:AudioBufferList(mNumberBuffers:2,mBuffers:AudioBuffer()))
        let inputList=UnsafeMutableAudioBufferListPointer(listPointer)
        inputList[0]=AudioBuffer(mNumberChannels:1,mDataByteSize:UInt32(n*4),mData:left)
        inputList[1]=AudioBuffer(mNumberChannels:1,mDataByteSize:UInt32(n*4),mData:right)
        var outputList=AudioBufferList(mNumberBuffers:1,mBuffers:AudioBuffer(mNumberChannels:2,mDataByteSize:UInt32(n*8),mData:output))
        var stamp=AudioTimeStamp()
        withUnsafePointer(to:&stamp) { t in _=HEAudioCallback(0,t,inputList.unsafePointer,t,&outputList,t,UnsafeMutableRawPointer(dsp)) }
        near(Double(output[2*(n-1)]),0.2*pow(10,-6/20),1e-6)
        near(Double(output[2*(n-1)+1]),-0.1*pow(10,-6/20),1e-6)
        check(HEGetMeters(dsp).frames==n)
        // Rapid edits must remain finite; the latest control state is eventually applied.
        var samples=[Float](repeating:0.1,count:512),result=samples
        for i in 0..<100 {
            var f=HEFilter(frequency:Double(50+i*100),gain:Double(i%8)-4,q:1,type:HEPeak)
            HESetFilters(dsp,&f,1,-12)
            samples.withUnsafeBufferPointer { a in result.withUnsafeMutableBufferPointer { b in HEProcessStereo(dsp,a.baseAddress!,b.baseAddress!,256) } }
            check(result.allSatisfy(\.isFinite))
        }
        HESetFilters(dsp,nil,0,-6)
        for _ in 0..<20 { samples.withUnsafeBufferPointer { a in result.withUnsafeMutableBufferPointer { b in HEProcessStereo(dsp,a.baseAddress!,b.baseAddress!,256) } } }
        near(Double(result.last!),0.1*pow(10,-6/20),1e-6)
        samples=[.nan,.infinity,0,0];result=[0,0,0,0]
        samples.withUnsafeBufferPointer { a in result.withUnsafeMutableBufferPointer { b in HEProcessStereo(dsp,a.baseAddress!,b.baseAddress!,2) } }
        check(result.allSatisfy(\.isFinite));check(HEGetMeters(dsp).invalidSamples==2)
        samples=[Float](repeating:10,count:4096);result=samples
        samples.withUnsafeBufferPointer { a in result.withUnsafeMutableBufferPointer { b in HEProcessStereo(dsp,a.baseAddress!,b.baseAddress!,2048) } }
        check(result.allSatisfy { abs($0)<=1 });check(HEGetMeters(dsp).clipped>0)
        check(HECreate(100)==nil)
    }
}
