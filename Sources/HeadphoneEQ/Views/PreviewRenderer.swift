// SPDX-License-Identifier: GPL-3.0-only
#if DEBUG
import AppKit
import SwiftUI

/// Renders this project's own view offscreen. No desktop capture, audio or user data.
@MainActor enum PreviewRenderer {
    static func render(to path:String) -> Never {
        NSApplication.shared.appearance=NSAppearance(named:.aqua)
        let store=AppStore(preview:true)
        let view=NSHostingView(rootView:ContentView(store:store).environment(\.colorScheme,.light).background(Color.white))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:840),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=view
        view.frame=NSRect(x:0,y:0,width:1000,height:840)
        view.layoutSubtreeIfNeeded()
        // Let SwiftUI's offscreen layout and Canvas finish; no visible window is opened.
        RunLoop.main.run(until:Date().addingTimeInterval(0.8))
        guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { exit(1) }
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let png=bitmap.representation(using:.png,properties:[:]) else { exit(1) }
        do { try png.write(to:URL(fileURLWithPath:path));exit(0) } catch { exit(1) }
    }
}
#endif
