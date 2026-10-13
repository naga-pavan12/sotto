// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sotto",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SottoRT", linkerSettings: [.linkedFramework("AudioToolbox"), .linkedFramework("CoreAudio")]),
        .testTarget(name: "SottoRTTests", dependencies: ["SottoRT"]),
        .target(name: "SottoCore", dependencies: ["SottoRT"]),
        .testTarget(name: "SottoCoreTests", dependencies: ["SottoCore", "SottoRT"]),
    ]
)
