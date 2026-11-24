// swift-tools-version:6.0
import PackageDescription
import Foundation

let denoiserArchive = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../denoiser/target/release/libsotto_denoiser.a").standardizedFileURL.path

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
            linkerSettings: [.unsafeFlags([denoiserArchive])]),
        .testTarget(name: "SottoCoreTests", dependencies: ["SottoCore", "SottoRT"]),
        .executableTarget(
            name: "SottoCLI",
            dependencies: ["SottoCore"]),
        .executableTarget(
            name: "Sotto",
            dependencies: ["SottoCore"]),
        .testTarget(name: "SottoTests", dependencies: ["Sotto"]),
    ]
)
