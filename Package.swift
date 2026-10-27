// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeadphoneEQ",
    platforms: [.macOS("14.4")],
    products: [.executable(name: "HeadphoneEQ", targets: ["HeadphoneEQ"])],
    targets: [
        .target(name: "AudioDSP", publicHeadersPath: "include", linkerSettings: [.linkedFramework("CoreAudio")]),
        .target(name: "HeadphoneEQCore", dependencies: ["AudioDSP"]),
        .executableTarget(name: "HeadphoneEQ", dependencies: ["HeadphoneEQCore", "AudioDSP"],
                          linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("AudioToolbox")]),
        .executableTarget(name: "EQVerify", dependencies: ["HeadphoneEQCore", "AudioDSP"], path: "Tests/HeadphoneEQCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
