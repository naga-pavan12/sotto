import Foundation
import SottoCore

// Minimal CLI to exercise AudioEngine live. Usage: SottoCLI <micUID> <seconds>
let args = CommandLine.arguments
let micUID = args.count > 1 ? args[1] : "BuiltInMicrophoneDevice"
let seconds = args.count > 2 ? Double(args[2]) ?? 5 : 5

guard let engine = AudioEngine() else {
    FileHandle.standardError.write("failed to load denoiser\n".data(using: .utf8)!)
    exit(1)
}
do {
    try engine.start(micUID: micUID)
    print("engine running: mic \(micUID) -> Sotto Microphone for \(seconds)s")
    Thread.sleep(forTimeInterval: seconds)
    engine.stop()
    print("stopped")
} catch {
    FileHandle.standardError.write("engine error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
