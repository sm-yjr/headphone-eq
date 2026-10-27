// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
let destination=CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:destination,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let image=NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    let s=Double(size),outer=NSRect(x:s*0.07,y:s*0.07,width:s*0.86,height:s*0.86)
    let tile=NSBezierPath(roundedRect:outer,xRadius:s*0.2,yRadius:s*0.2)
    NSGradient(starting:NSColor(srgbRed:0.08,green:0.49,blue:0.95,alpha:1),ending:NSColor(srgbRed:0.08,green:0.24,blue:0.72,alpha:1))!.draw(in:tile,angle:-70)
    NSColor.white.setFill()
    for (i,height) in [0.22,0.4,0.58,0.35,0.18].enumerated() {
        let width=s*0.065,x=s*(0.27+Double(i)*0.1),h=s*height
        NSBezierPath(roundedRect:NSRect(x:x,y:(s-h)/2,width:width,height:h),xRadius:width/2,yRadius:width/2).fill()
    }
    image.unlockFocus()
    let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
    let data=bitmap.representation(using:.png,properties:[:])!
    // iconutil requires paired 1x/2x names.
    if size<=512 { try data.write(to:URL(fileURLWithPath:destination+"/icon_\(size)x\(size).png")) }
    if size>=32 { let half=size/2;try data.write(to:URL(fileURLWithPath:destination+"/icon_\(half)x\(half)@2x.png")) }
}
