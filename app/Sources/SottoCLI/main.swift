import Foundation
import SottoCore

// Usage:
//   SottoCLI <micUID> <seconds>   run the engine live
//   SottoCLI stress <micUID>      rapid start/stop cycles (teardown safety check)
let args = CommandLine.arguments

if args.count > 1 && args[1] == "stress" {
    let mic = args.count > 2 ? args[2] : "BlackHole2ch_UID"
    for i in 1...20 {
        guard let e = AudioEngine() else { print("denoiser load failed"); exit(1) }
        do { try e.start(micUID: mic) } catch { print("start \(i) failed: \(error)"); exit(1) }
        Thread.sleep(forTimeInterval: 0.15)
        e.stop()
    }
    print("stress OK: 20 start/stop cycles, no crash")
    exit(0)
}

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
