# Headphone EQ

一款原生 macOS 参数均衡器。导入可信的耳机校正，微调参数，再用同一段音乐比较原声与调音。

[下载测试版](https://github.com/sm-yjr/headphone-eq/releases) · [English](../README.md) · [隐私说明](../PRIVACY.md)

![主界面渲染预览](preview.png)

*使用通用示例渲染的实际 SwiftUI 视图，详情见[验证记录](validation.md)。*

## 主要功能

- 最多 16 段参数 EQ，支持 Peak、Low shelf、High shelf，可调整频率、增益和 Q。
- 粘贴或导入 Equalizer APO 参数文本；导入、导出应用 JSON；导出 APO 文本。
- 新建、复制、编辑、删除预设，自动保存到本机，并记住每个输出设备选用的预设。
- ⌘1 原声对照、⌘2 预设调音、⌘E 开启／暂停；两种对照保留相同前级，但不保证感知响度相等。
- 根据曲线计算数字余量，参数变化进行 25 毫秒交叉淡化，并显示数字峰值和削波提示。
- 菜单栏控制与 10 秒降音量链路验证。切换输出、采样率变化或睡眠后暂停，确认设备再重新开启。

## 安装和使用

需要 macOS 14.4+。下载包同时支持 Apple 芯片与 Intel Mac。界面目前为简体中文。

1. 从 Releases 下载 ZIP，解压后将 HeadphoneEQ.app 放入“应用程序”。
2. 当前为 **Developer ID 已签名、Apple 未公证的测试版**，系统可能阻止打开。如果你需要 Apple 已公证的版本，请等待后续发布或自行从源码构建；本项目不要求关闭系统安全保护。
3. 在系统声音设置中选中实际耳机，打开软件，选择或导入预设，点击“开启 EQ”。
4. 按 macOS 提示允许“系统音频录制”。音频只在本机内存中处理，不落盘、不上传。
5. 播放音乐，切换“原声对照／预设调音”。用听诊器按钮可暂时降低最多 30 dB，10 秒后自动恢复，验证声音确实经过软件。

请从适中音量开始。**暂停或退出会恢复系统直通并取消前级衰减，声音可能变大。** 输出变化或睡眠触发的暂停同样如此。软件启动时保持暂停，不安装开机启动项。

## 预设和许可

随软件附带 Flat 与 Warm 两个原创通用示例。Warm 只改变音色，并不是任何耳机的测量校正。

oratory1990 等第三方作者的校正不随 GPL 源码分发，也不会被重新许可。请从[作者自己的目录](https://www.reddit.com/r/oratory1990/wiki/index/list_of_presets/)获取并遵循其使用条款，确认耳机型号、耳垫状态、蓝牙／有线和降噪模式。避免与耳机内置 EQ 或其他系统 EQ 重复叠加。

支持 `Preamp` 和带 Q 的 `PK` / `PEQ`、`LSC`、`HSC` 文本。PDF、GraphicEQ、卷积和其他指令不会被部分导入，会直接提示错误。[格式说明和示例](preset-format.md)。

## 构建

安装 Swift 6+ 的 Xcode 或 Command Line Tools 后：

```sh
git clone https://github.com/sm-yjr/headphone-eq.git
cd headphone-eq
./script/verify.sh
./script/build_and_run.sh
```

完整构建、架构、公证和限制请见[主说明](../README.md)与[验证记录](validation.md)。

音频接口只处理系统默认输出的双声道音乐流。蓝牙通话模式不支持；部分受保护媒体无法捕获。频响图是滤波器计算值，数字削波计数不能测量耳机的声学 THD 或共振，也不会凭空增加空间音效。

预设保存在 `~/Library/Application Support/HeadphoneEQ/presets.json`，状态文件在同一目录。软件没有账号、广告、联网请求和遥测上传。

代码、原创示例、文档与图标使用 **GPL-3.0-only**；导入的第三方预设仍遵循原作者许可。
