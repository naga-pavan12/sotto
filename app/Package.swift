// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sotto",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SottoRT", linkerSettings: [.linkedFramework("AudioToolbox"), .linkedFramework("CoreAudio")]),
        .testTarget(name: "SottoRTTests", dependencies: ["SottoRT"]),
        .systemLibrary(name: "CSottoDenoiser"),
        .target(
            name: "SottoCore",
            dependencies: ["SottoRT", "CSottoDenoiser"],
            linkerSettings: [.unsafeFlags(["-L../denoiser/target/release"])]),
        .testTarget(name: "SottoCoreTests", dependencies: ["SottoCore", "SottoRT"]),
        .executableTarget(
            name: "SottoCLI",
            dependencies: ["SottoCore"],
            linkerSettings: [.unsafeFlags(["-L../denoiser/target/release"])]),
        .executableTarget(
            name: "Sotto",
            dependencies: ["SottoCore"],
            linkerSettings: [.unsafeFlags(["-L../denoiser/target/release"])]),
    ]
)
