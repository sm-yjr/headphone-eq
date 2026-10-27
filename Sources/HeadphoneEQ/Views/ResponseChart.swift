// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import HeadphoneEQCore

struct ResponseChart:View {
    let bands:[EQBand]
    var sampleRate:Double=48000
    var body:some View {
        let values=(0...400).map { i in bands.reduce(0) { $0+$1.response(at:20*pow(1000,Double(i)/400),sampleRate:sampleRate) } }
        let limit=max(12,ceil((values.map(abs).max() ?? 0)/6)*6)
        Canvas { context,size in
            func x(_ f:Double)->Double { log(f/20)/log(1000)*size.width }
            func y(_ db:Double)->Double { size.height*(0.5-db/(limit*2)) }
            for db in [-limit,-limit/2,0,limit/2,limit] {
                var line=Path();line.move(to:CGPoint(x:0,y:y(db)));line.addLine(to:CGPoint(x:size.width,y:y(db)))
                context.stroke(line,with:.color(.secondary.opacity(db==0 ? 0.4 : 0.15)),lineWidth:db==0 ? 1 : 0.5)
            }
            for f in [20.0,100,1000,10000,20000] {
                var line=Path();line.move(to:CGPoint(x:x(f),y:0));line.addLine(to:CGPoint(x:x(f),y:size.height))
                context.stroke(line,with:.color(.secondary.opacity(0.15)),lineWidth:0.5)
            }
            var curve=Path()
            for (i,db) in values.enumerated() {
                let point=CGPoint(x:Double(i)/400*size.width,y:y(db))
                if i==0 { curve.move(to:point) } else { curve.addLine(to:point) }
            }
            var fill=curve
            fill.addLine(to:CGPoint(x:size.width,y:y(0)));fill.addLine(to:CGPoint(x:0,y:y(0)));fill.closeSubpath()
            context.fill(fill,with:.color(.accentColor.opacity(0.08)))
            context.stroke(curve,with:.color(.accentColor),style:StrokeStyle(lineWidth:2.2,lineJoin:.round))
        }
        .clipped()
        .accessibilityLabel("均衡器计算响应，范围正负 \(Int(limit)) dB")
        .overlay(alignment:.topLeading) { Text("+\(Int(limit)) dB").font(.system(size:9)).foregroundStyle(.secondary).padding(3) }
        .overlay(alignment:.bottomLeading) { Text("−\(Int(limit)) dB").font(.system(size:9)).foregroundStyle(.secondary).padding(3) }
    }
}
