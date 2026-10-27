// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import HeadphoneEQCore

struct ContentView: View {
    @ObservedObject var store:AppStore
    var body:some View {
        HStack(spacing:0) {
            sidebar.frame(width:224)
            Divider()
            VStack(spacing:0) {
                ScrollView {
                    VStack(alignment:.leading,spacing:22) {
                        header
                        output
                        comparison
                        chart
                        preamp
                        parameters
                        if !store.selected.notes.isEmpty { Text(store.selected.notes).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        if let message=store.message {
                            Label(message,systemImage:"info.circle").font(.callout).foregroundStyle(.secondary)
                                .padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:10))
                        }
                    }.padding(24)
                }
                Divider()
                footer.padding(.horizontal,24).padding(.vertical,16)
            }
        }
        .frame(minWidth:960,minHeight:700)
        .sheet(isPresented:$store.showImport) { importSheet }
        .sheet(isPresented:$store.showHelp) { helpSheet }
        .alert("允许本机音频处理",isPresented:$store.showPermissionInfo) {
            Button("继续") { store.start() }
            Button("取消",role:.cancel) {}
        } message:{ Text("macOS 首次会询问系统音频录制权限。Headphone EQ 只在本机内存中均衡声音，不保存或上传音频。暂停或退出后恢复系统直通，音量可能随之前级衰减而变化。") }
        .alert("删除这个预设？",isPresented:$store.showDelete) {
            Button("删除",role:.destructive) { store.deleteSelected() }
            Button("取消",role:.cancel) {}
        } message:{ Text("删除 \(store.selected.name)。如果需要保留，请先导出备份。") }
    }
    private var sidebar:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"waveform.path").font(.title2.weight(.medium)).foregroundStyle(.tint)
                VStack(alignment:.leading,spacing:2) {
                    Text("Headphone EQ").font(.headline)
                    Text("把声音调到喜欢的位置").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(18).padding(.top,8)
            HStack { Text("预设库").font(.caption.weight(.semibold)).foregroundStyle(.secondary);Spacer();Text("\(store.presets.count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary) }.padding(.horizontal,18).padding(.vertical,10)
            List {
                ForEach(store.presets) { preset in
                    Button { store.select(preset.id) } label: {
                        HStack(spacing:10) {
                            Image(systemName:preset.bands.isEmpty ? "waveform" : "slider.horizontal.3").foregroundStyle(store.selectedID==preset.id ? Color.accentColor : .secondary)
                            VStack(alignment:.leading,spacing:3) {
                                Text(preset.name).font(.system(size:12,weight:store.selectedID==preset.id ? .semibold : .regular)).lineLimit(2)
                                Text("\(preset.bands.count) 段参数 EQ").font(.system(size:10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength:0)
                        }.padding(.vertical,6).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(preset.name)
                    .listRowBackground(store.selectedID==preset.id ? Color.accentColor.opacity(0.13) : Color.clear)
                    .accessibilityIdentifier("preset-\(preset.id.uuidString)")
                }
            }.listStyle(.sidebar)
            Divider()
            HStack {
                Button { store.newPreset() } label:{ Label("新建",systemImage:"plus") }
                Spacer()
                Menu { Button("从文件导入…") { store.chooseImportFile() };Button("粘贴参数…") { store.showImport=true } } label:{ Image(systemName:"square.and.arrow.down") }.menuStyle(.borderlessButton).fixedSize().help("导入预设")
                Button { store.showHelp=true } label:{ Image(systemName:"questionmark.circle") }.buttonStyle(.plain).help("使用帮助")
            }.padding(16)
        }.background(.bar)
    }
    private var header:some View {
        HStack(alignment:.top) {
            VStack(alignment:.leading,spacing:6) {
                TextField("预设名称",text:Binding(get:{store.selected.name},set:{value in store.update{$0.name=value}}))
                    .textFieldStyle(.plain).font(.system(size:26,weight:.semibold,design:.rounded))
                    .accessibilityLabel("预设名称").accessibilityIdentifier("preset-name")
                Text(store.selected.author.isEmpty ? "个人预设 · 自动保存在这台 Mac" : store.selected.author).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength:16)
            Menu {
                Button("复制预设") { store.duplicate() }
                Button("复制 JSON 参数") { store.copyPreset(json:true) }
                Button("复制 APO 参数") { store.copyPreset(json:false) }
                Button("导出 JSON…") { store.exportPreset(json:true) }
                Button("导出 Equalizer APO…") { store.exportPreset(json:false) }
                Divider()
                Button("删除预设…",role:.destructive) { store.showDelete=true }
            } label:{ Image(systemName:"ellipsis.circle").font(.title3) }.menuStyle(.borderlessButton).fixedSize().help("预设操作")
        }
    }
    private var output:some View {
        HStack(spacing:12) {
            Image(systemName:"headphones").font(.title2).foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:3) {
                Text(store.outputName).font(.subheadline.weight(.medium))
                Text(String(format:"跟随系统输出 · %g kHz · 双声道",store.sampleRate/1000)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("声音设置") { store.openSoundSettings() }.controlSize(.small)
        }.padding(14).background(.quaternary.opacity(0.5),in:RoundedRectangle(cornerRadius:12))
    }
    private var comparison:some View {
        HStack(spacing:10) {
            modeButton("原声对照",key:"⌘1",selected:store.bypass) { store.setBypass(true) }.accessibilityIdentifier("mode-original")
            modeButton("预设调音",key:"⌘2",selected:!store.bypass) { store.setBypass(false) }.accessibilityIdentifier("mode-eq")
            Spacer()
            Text("保留相同前级，方便比较").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func modeButton(_ name:String,key:String,selected:Bool,action:@escaping()->Void)->some View {
        Button(action:action) {
            HStack(spacing:12) { Text(name).fontWeight(.medium);Text(key).font(.caption).foregroundStyle(.secondary) }
                .padding(.horizontal,14).padding(.vertical,10)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05),in:RoundedRectangle(cornerRadius:9))
                .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.15)))
        }.buttonStyle(.plain).accessibilityValue(selected ? "已选中" : "未选中")
    }
    private var chart:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text("频响调整").font(.subheadline.weight(.semibold));Spacer();Text(store.bypass ? "原声对照中" : "\(store.selected.bands.filter(\.enabled).count) 段已开启").font(.caption).foregroundStyle(.secondary) }
            ResponseChart(bands:store.bypass ? [] : store.selected.bands,sampleRate:store.sampleRate).frame(height:180)
            GeometryReader { geometry in
                ZStack(alignment:.leading) {
                    ForEach([20.0,100,1000,10000,20000],id:\.self) { frequency in
                        Text(frequency<1000 ? "\(Int(frequency)) Hz" : "\(Int(frequency/1000)) kHz")
                            .position(x:min(geometry.size.width-24,max(20,log(frequency/20)/log(1000)*geometry.size.width)),y:6)
                    }
                }
            }.font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).frame(height:12)
            Text("显示 EQ 的计算响应；不是耳机实测频响。").font(.caption2).foregroundStyle(.tertiary)
        }
    }
    private var preamp:some View {
        HStack(spacing:14) {
            VStack(alignment:.leading,spacing:3) { Text("前级余量").font(.subheadline.weight(.medium));Text("根据曲线自动增加必要衰减").font(.caption2).foregroundStyle(.secondary) }.frame(width:180,alignment:.leading)
            Slider(value:Binding(get:{store.selected.preamp},set:{value in store.update{$0.preamp=value}}),in:-60...0,step:0.1).accessibilityLabel("预设前级")
            Text(String(format:"%.1f dB",store.effectivePreamp)).monospacedDigit().font(.callout).frame(width:76,alignment:.trailing)
        }
    }
    private var parameters:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Button { store.showParameters.toggle() } label:{ Label(store.showParameters ? "收起参数" : "编辑参数",systemImage:store.showParameters ? "chevron.up" : "slider.horizontal.3") }.buttonStyle(.plain).font(.subheadline.weight(.medium))
                Spacer()
                if store.showParameters { Button { store.addBand() } label:{ Label("添加滤波器",systemImage:"plus") }.controlSize(.small).disabled(store.selected.bands.count>=16) }
            }
            if store.showParameters {
                HStack { Text("开").frame(width:28);Text("类型").frame(width:110,alignment:.leading);Text("频率 Hz").frame(width:88);Text("增益 dB").frame(width:78);Text("Q").frame(width:70);Spacer() }.font(.caption).foregroundStyle(.secondary)
                ForEach(store.selected.bands) { band in
                    HStack(spacing:10) {
                        Toggle("第 \(band.id) 段",isOn:Binding(get:{band.enabled},set:{_ in store.toggleBand(band.id)})).labelsHidden().toggleStyle(.checkbox).frame(width:28)
                        Picker("类型",selection:Binding(get:{band.kind},set:{store.setBandKind(band.id,$0)})) { ForEach(FilterKind.allCases,id:\.self) { Text($0.label).tag($0) } }.labelsHidden().frame(width:110)
                        bandField(band,\.frequency,label:"频率",width:88)
                        bandField(band,\.gain,label:"增益",width:78)
                        bandField(band,\.q,label:"Q",width:70)
                        Spacer(minLength:0)
                        Button { store.removeBand(band.id) } label:{ Image(systemName:"minus.circle") }.buttonStyle(.plain).foregroundStyle(.secondary).help("删除第 \(band.id) 段")
                    }.opacity(band.enabled ? 1 : 0.5)
                }
                if store.selected.bands.isEmpty { Text("还没有滤波器。添加一段，或导入已有参数。").font(.caption).foregroundStyle(.secondary).padding(.vertical,8) }
            }
        }
    }
    private func bandField(_ band:EQBand,_ path:WritableKeyPath<EQBand,Double>,label:String,width:CGFloat)->some View {
        TextField(label,value:Binding(get:{band[keyPath:path]},set:{store.editBand(band.id,path,$0)}),format:.number.precision(.fractionLength(0...2)))
            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width:width)
            .accessibilityLabel("第 \(band.id) 段\(label)")
    }
    private var footer:some View {
        HStack(spacing:12) {
            Circle().fill(store.isRunning ? Color.green : Color.secondary.opacity(0.5)).frame(width:7,height:7)
            VStack(alignment:.leading,spacing:4) {
                Text(store.statusText).font(.caption.weight(.medium))
                Text(store.clipped>0 ? "检测到数字削波，请降低前级或输出增益。" : "本机实时处理 · 不保存或上传音频").font(.caption2).foregroundStyle(store.clipped>0 ? Color.orange : Color.secondary)
            }
            Spacer(minLength:8)
            if store.isRunning {
                ProgressView(value:min(1,Double(store.outputPeak))).frame(width:50).help("数字输出峰值")
                Button { store.testRoute() } label:{ Image(systemName:store.diagnosticActive ? "speaker.wave.2" : "stethoscope") }.help(store.diagnosticActive ? "立即恢复音量" : "最多降低 30 dB 验证链路，10 秒后恢复").accessibilityIdentifier("test-route")
            }
            Button(store.isRunning ? "暂停处理" : "开启 EQ") {
                store.toggleProcessing()
            }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("engine-toggle")
        }
    }
    private var importSheet:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("导入预设").font(.title2.weight(.semibold))
            Text("粘贴 Equalizer APO 参数（Preamp、PK、LSC、HSC），或使用文件导入。第三方预设遵循其作者的许可。").font(.callout).foregroundStyle(.secondary)
            TextField("预设名称",text:$store.importName).textFieldStyle(.roundedBorder)
            TextEditor(text:$store.importText).font(.system(.body,design:.monospaced)).frame(height:220).border(.quaternary)
            if let error=store.importError { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Button("选择文件…") { store.chooseImportFile() };Spacer();Button("取消") { store.showImport=false;store.importError=nil };Button("导入") { store.importPastedText() }.buttonStyle(.borderedProminent).disabled(store.importText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width:580)
    }
    private var helpSheet:some View {
        VStack(alignment:.leading,spacing:18) {
            Label("Headphone EQ",systemImage:"waveform.path").font(.title2.weight(.semibold))
            Text("1. 在系统声音设置中选择实际播放设备。\n2. 导入你的参数预设，或编辑最多 16 段滤波器。\n3. 开启 EQ，并按 macOS 提示允许系统音频录制。\n4. ⌘1 对照原声，⌘2 回到调音，⌘E 暂停／开启。")
            Text("原声对照保留相同前级，但不等于严格的感知响度匹配。暂停或退出会恢复系统直通。输出变化或睡眠后会暂停，请确认设备并重新开启。").font(.callout).foregroundStyle(.secondary)
            Text("全部音频在本机内存处理。没有联网请求、账号、遥测上传或音频录制。预设与诊断状态只保存在本机。").font(.callout).foregroundStyle(.secondary)
            HStack { Button("系统音频权限") { store.openPermissions() };Button("声音设置") { store.openSoundSettings() };Spacer();Button("知道了") { store.showHelp=false }.keyboardShortcut(.defaultAction) }
            Text("GPL-3.0-only · 0.3.0 测试版 · macOS 14.4+").font(.caption).foregroundStyle(.tertiary)
        }.padding(26).frame(width:560)
    }
}
