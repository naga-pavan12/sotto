// Driver loopback integration test (local-only; requires the driver installed).
//
// Writes a 1 kHz sine into "Sotto Bridge" and records "Sotto Microphone" at the
// same time. Asserts the recording correlates with the sine at a lag of ~480
// frames (one 10 ms frame of driver delay) and that the amplitude is preserved.
//
// Run after `make driver && make install`:  swift driver/tests/loopback_test.swift

import AVFoundation
import CoreAudio

let sampleRate = 48000.0
let sineHz = 1000.0
let seconds = 2.0
let frameDelayExpected = 480
let delayTolerance = 48

func deviceID(uid: String) -> AudioDeviceID? {
    var size = UInt32(0)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
    for id in ids {
        var uidRef: CFString? = nil
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(id, &uidAddr, 0, nil, &uidSize, &uidRef) == noErr,
           let got = uidRef as String?, got == uid {
            return id
        }
    }
    return nil
}

guard let mic = deviceID(uid: "SottoMicrophone"), let bridge = deviceID(uid: "SottoBridge") else {
    print("FAIL: Sotto devices not found. Install the driver first (make install).")
    exit(1)
}

let totalFrames = Int(sampleRate * seconds)
var sine = [Float](repeating: 0, count: totalFrames)
for i in 0..<totalFrames {
    sine[i] = Float(sin(2.0 * Double.pi * sineHz * Double(i) / sampleRate)) * 0.5
}

let engine = AVAudioEngine()
let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

// Play the sine into the bridge via an AVAudioPlayerNode routed to the bridge device.
// (Device routing of AVAudioEngine is coarse; this test uses raw HAL IOProcs.)
var recorded = [Float]()
recorded.reserveCapacity(totalFrames * 2)
let recLock = NSLock()

var micProcID: AudioDeviceIOProcID?
AudioDeviceCreateIOProcIDWithBlock(&micProcID, mic, nil) { _, inData, _, _, _ in
    let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
    guard let buf = abl.first, let data = buf.mData else { return }
    let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
    let ptr = data.assumingMemoryBound(to: Float.self)
    recLock.lock()
    for i in 0..<n { recorded.append(ptr[i]) }
    recLock.unlock()
}

var writeIndex = 0
var bridgeProcID: AudioDeviceIOProcID?
AudioDeviceCreateIOProcIDWithBlock(&bridgeProcID, bridge, nil) { _, _, _, outData, _ in
    let abl = UnsafeMutableAudioBufferListPointer(outData)
    guard let buf = abl.first, let data = buf.mData else { return }
    let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
    let ptr = data.assumingMemoryBound(to: Float.self)
    for i in 0..<n {
        ptr[i] = writeIndex < sine.count ? sine[writeIndex] : 0
        writeIndex += 1
    }
}

AudioDeviceStart(bridge, bridgeProcID)
AudioDeviceStart(mic, micProcID)
Thread.sleep(forTimeInterval: seconds + 0.3)
AudioDeviceStop(bridge, bridgeProcID)
AudioDeviceStop(mic, micProcID)

recLock.lock(); let rec = recorded; recLock.unlock()
if rec.count < totalFrames / 2 {
    print("FAIL: recorded too few frames (\(rec.count)).")
    exit(1)
}

// Cross-correlate a mid window of the recording against the sine to find the lag.
func bestLag() -> (lag: Int, corr: Float) {
    let win = 4096
    let start = rec.count / 2
    var best = (lag: 0, corr: -Float.infinity)
    for lag in 0...1024 {
        var c: Float = 0
        for i in 0..<win {
            let r = start + i
            let s = start + i - lag
            if s >= 0 && s < sine.count && r < rec.count { c += rec[r] * sine[s] }
        }
        if c > best.corr { best = (lag, c) }
    }
    return best
}

let (lag, _) = bestLag()
let micRMS = sqrt(rec.suffix(totalFrames / 2).map { $0 * $0 }.reduce(0, +) / Float(totalFrames / 2))
let sineRMS = Float(0.5 / sqrt(2.0))

print("measured delay: \(lag) frames; mic RMS \(micRMS) vs sine RMS \(sineRMS)")
if abs(lag - frameDelayExpected) <= delayTolerance && micRMS > sineRMS * 0.8 && micRMS < sineRMS * 1.2 {
    print("loopback_test PASS")
    exit(0)
} else {
    print("loopback_test FAIL (delay or amplitude out of range)")
    exit(1)
}
