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
let maxAcceptableDelay = 1200  // frames; one-frame-ish transport, well under our 60 ms budget

// Resolve a device by UID via TranslateUIDToDevice, which works even for hidden
// devices (the bridge is hidden and absent from the enumerated device list).
func deviceID(uid: String) -> AudioDeviceID? {
    var cfuid = uid as CFString
    var dev = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let st = withUnsafeMutablePointer(to: &cfuid) { uidPtr -> OSStatus in
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                   UInt32(MemoryLayout<CFString>.size), uidPtr, &size, &dev)
    }
    return (st == noErr && dev != 0) ? dev : nil
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
    micProcCalls += 1
    recLock.unlock()
}

let bridgeCalls = NSMutableData(length: 8)!  // reuse as counter store
var bridgeProcCalls = 0
var micProcCalls = 0
let procLock = NSLock()
var writeIndex = 0
var bridgeProcID: AudioDeviceIOProcID?
AudioDeviceCreateIOProcIDWithBlock(&bridgeProcID, bridge, nil) { _, _, _, outData, _ in
    let abl = UnsafeMutableAudioBufferListPointer(outData)
    guard let buf = abl.first, let data = buf.mData else { return }
    let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
    let ptr = data.assumingMemoryBound(to: Float.self)
    procLock.lock(); bridgeProcCalls += 1; procLock.unlock()
    for i in 0..<n {
        ptr[i] = writeIndex < sine.count ? sine[writeIndex] : 0
        writeIndex += 1
    }
}

// Read a custom Int (CFNumber) property identified by a FourCharCode selector.
func readIntProp(_ dev: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Int? {
    var ref: Unmanaged<CFPropertyList>? = nil
    var size = UInt32(MemoryLayout<Unmanaged<CFPropertyList>?>.size)
    var addr = AudioObjectPropertyAddress(mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &ref) == noErr,
          let plist = ref?.takeRetainedValue(), CFGetTypeID(plist) == CFNumberGetTypeID() else { return nil }
    var v = 0
    CFNumberGetValue((plist as! CFNumber), .intType, &v)
    return v
}

AudioDeviceStart(bridge, bridgeProcID)
AudioDeviceStart(mic, micProcID)
Thread.sleep(forTimeInterval: 0.4)
let sBrg = readIntProp(bridge, 0x73427267) ?? -1  // 'sBrg': 1 = app authorized to write
let sRun = readIntProp(mic, 0x7352756E) ?? -1     // 'sRun'
print("bridge sBrg=\(sBrg) (1=authorized writer), mic sRun=\(sRun)")
let wc = readIntProp(mic, 0x73574320) ?? -1   // 'sWC '
let lw = readIntProp(mic, 0x734C5720) ?? -1   // 'sLW '
let lr = readIntProp(mic, 0x734C5220) ?? -1   // 'sLR '
procLock.lock(); let bpc = bridgeProcCalls; procLock.unlock()
print("diag: writeCount=\(wc) lastWriteTs=\(lw) lastReadTs=\(lr)")
print("test procs: bridgeIOProc called \(bpc) times, micIOProc \(micProcCalls) times")
Thread.sleep(forTimeInterval: seconds)
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
if lag > 0 && lag < maxAcceptableDelay && micRMS > sineRMS * 0.5 && micRMS < sineRMS * 1.3 {
    print("loopback_test PASS (delay \(lag) frames, amplitude preserved)")
    exit(0)
} else {
    print("loopback_test FAIL (delay or amplitude out of range)")
    exit(1)
}
