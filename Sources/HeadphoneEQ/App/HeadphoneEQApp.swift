// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import HeadphoneEQCore

@MainActor
final class AppDelegate:NSObject,NSApplicationDelegate {
    var store:AppStore?
    func applicationDidFinishLaunching(_ notification:Notification) { NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true) }
    func applicationWillTerminate(_ notification:Notification) { store?.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
}
@main @MainActor
struct HeadphoneEQApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store=AppStore()
    init() {
        #if DEBUG
        if let path=ProcessInfo.processInfo.environment["HEADPHONE_EQ_RENDER_PREVIEW"] {
            PreviewRenderer.render(to:path)
        }
        #endif
    }
    var body:some Scene {
        Window("Headphone EQ",id:"main") { ContentView(store:store).onAppear{delegate.store=store} }
            .defaultSize(width:1000,height:760).windowResizability(.contentMinSize)
            .commands {
                CommandGroup(replacing:.newItem) {
                    Button("新建预设") { store.newPreset() }.keyboardShortcut("n")
                    Button("导入预设文件…") { store.chooseImportFile() }.keyboardShortcut("i",modifiers:[.command,.shift])
                    Button("粘贴参数…") { store.showImport=true }
                }
                CommandMenu("试听") {
                    Button("原声对照") { store.setBypass(true) }.keyboardShortcut("1")
                    Button("预设调音") { store.setBypass(false) }.keyboardShortcut("2")
                    Divider()
                    Button(store.isRunning ? "暂停处理" : "开启 EQ") { store.toggleProcessing() }.keyboardShortcut("e")
                }
                CommandGroup(replacing:.help) { Button("Headphone EQ 使用帮助") { store.showHelp=true } }
            }
        MenuBarExtra("Headphone EQ",systemImage:store.isRunning ? "headphones.circle.fill" : "headphones.circle") { MenuContent(store:store) }
    }
}
private struct MenuContent:View {
    @ObservedObject var store:AppStore
    @Environment(\.openWindow) private var openWindow
    var body:some View {
        Text(store.outputName);Text(store.selected.name)
        Divider()
        Button("原声对照") { store.setBypass(true) }
        Button("预设调音") { store.setBypass(false) }
        Menu("切换预设") { ForEach(store.presets) { preset in Button(preset.name){store.select(preset.id)} } }
        Divider()
        Button(store.isRunning ? "暂停处理" : "开启 EQ") { store.toggleProcessing() }
        Button("打开调音窗口") { openWindow(id:"main");NSApp.activate(ignoringOtherApps:true) }
        Divider()
        Button("退出 Headphone EQ") { store.shutdown();NSApp.terminate(nil) }
    }
}
