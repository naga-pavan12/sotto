import AudioToolbox
import CoreAudio
import Foundation
import os
import SottoRT

/// Captures the chosen physical mic, denoises each 10 ms hop on a real-time
/// thread, and writes the result into the hidden "Sotto Bridge" output device;
/// the driver then presents it as "Sotto Microphone" to call apps.
///
/// Teardown is ordered to avoid use-after-free: stop() destroys the IO procs
/// (which drains any in-flight callback), waits for the DSP thread to exit, and
/// only then frees the rings/resampler/scratch. Control changes (strength, reset,
/// bypass) are routed to the DSP thread via DspChain, so the native denoiser
/// handle is only ever touched from that one thread.
public final class AudioEngine {
    public enum EngineError: Error { case deviceNotFound, ioProcFailed, hopMismatch }

    private let hop = 480
    private let sr = 48000.0
    private let bridgeUID = "SottoBridge"

    private let chain: DspChain
    private let denoiser: DFNDenoiser

    // Owned RT resources; freed only after IO procs are destroyed and DSP exits.
    private var ringIn: OpaquePointer?
    private var ringOut: OpaquePointer?
    private var resampler: OpaquePointer?
    private var monoScratch: UnsafeMutableBufferPointer<Float>?
    private var rsScratch: UnsafeMutableBufferPointer<Float>?
    private var dspScratch: UnsafeMutableBufferPointer<Float>?

    private var micID = AudioDeviceID(0)
    private var bridgeID = AudioDeviceID(0)
    private var micProc: AudioDeviceIOProcID?
    private var bridgeProc: AudioDeviceIOProcID?

    private var dspThread: Thread?
    private let wake = DispatchSemaphore(value: 0)
    private let dspExited = DispatchSemaphore(value: 0)
    private let runningFlag = OSAllocatedUnfairLock(initialState: false)
    private var micChannels = 1
    private var micRate = 48000.0

    public var strength: Int = 90 { didSet { chain.requestStrength(strength) } }
    public var bypass: Bool = false { didSet { chain.setBypass(bypass) } }

    public init?() {
        guard let d = DFNDenoiser() else { return nil }
        denoiser = d
        chain = DspChain(denoiser: d)
        chain.requestStrength(strength)
    }

    deinit { stop() }

    public func start(micUID: String) throws {
        guard denoiser.hopSize == hop else { throw EngineError.hopMismatch }
        guard let mic = Self.deviceID(uid: micUID), let bridge = Self.deviceID(uid: bridgeUID) else {
            throw EngineError.deviceNotFound
        }
        micID = mic
        bridgeID = bridge
        (micRate, micChannels) = Self.inputFormat(mic)

        ringIn = spsc_create(UInt32(hop * 16))
        ringOut = spsc_create(UInt32(hop * 16))
        if micRate != sr { resampler = rs_create(micRate, sr) }

        // Preallocate per-callback scratch so the RT threads never malloc.
        let maxCapture = 8192
        let rsCap = Int((Double(maxCapture) * sr / micRate).rounded(.up)) + 64
        monoScratch = .allocate(capacity: maxCapture); monoScratch!.initialize(repeating: 0)
        rsScratch = .allocate(capacity: rsCap); rsScratch!.initialize(repeating: 0)
        dspScratch = .allocate(capacity: hop); dspScratch!.initialize(repeating: 0)

        runningFlag.withLock { $0 = true }
        let t = Thread { [unowned self] in self.dspLoop() }
        t.name = "ai.sotto.dsp"
        t.qualityOfService = .userInteractive
        t.start()
        dspThread = t

        try installMicProc()
        try installBridgeProc()
        AudioDeviceStart(bridgeID, bridgeProc)
        AudioDeviceStart(micID, micProc)
    }

    public func stop() {
        let wasRunning = runningFlag.withLock { r -> Bool in defer { r = false }; return r }
        guard wasRunning else { return }

        // 1) Destroy IO procs first; DestroyIOProcID drains any in-flight callback,
        //    so no audio thread touches the rings after this returns.
        if let p = micProc { AudioDeviceStop(micID, p); AudioDeviceDestroyIOProcID(micID, p); micProc = nil }
        if let p = bridgeProc { AudioDeviceStop(bridgeID, p); AudioDeviceDestroyIOProcID(bridgeID, p); bridgeProc = nil }

        // 2) Wake the DSP thread and wait for it to exit.
        wake.signal()
        dspExited.wait()
        dspThread = nil

        // 3) Now nothing can touch the RT resources; free them.
        if let r = ringIn { spsc_destroy(r); ringIn = nil }
        if let r = ringOut { spsc_destroy(r); ringOut = nil }
        if let r = resampler { rs_destroy(r); resampler = nil }
        monoScratch?.deallocate(); monoScratch = nil
        rsScratch?.deallocate(); rsScratch = nil
        dspScratch?.deallocate(); dspScratch = nil
    }

    public func setBypass(_ on: Bool) { chain.setBypass(on) }

    // MARK: - Real-time IO (no allocation, no locks beyond the lock-free rings)

    private func installMicProc() throws {
        let ring = ringIn!
        let rs = resampler
        let mono = monoScratch!
        let rsOut = rsScratch!
        let ch = micChannels
        let wake = self.wake
        let rc = AudioDeviceCreateIOProcIDWithBlock(&micProc, micID, nil) { _, inData, _, _, _ in
            guard let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData)).first,
                  let data = abl.mData else { return }
            let totalSamples = Int(abl.mDataByteSize) / MemoryLayout<Float>.size
            let frames = ch > 0 ? totalSamples / ch : totalSamples
            if frames > mono.count { return }
            let ptr = data.assumingMemoryBound(to: Float.self)
            if ch == 1 {
                for i in 0..<frames { mono[i] = ptr[i] }
            } else {
                for i in 0..<frames {
                    var acc: Float = 0
                    for c in 0..<ch { acc += ptr[i * ch + c] }
                    mono[i] = acc / Float(ch)
                }
            }
            if let rs {
                let n = rs_process(rs, mono.baseAddress, UInt32(frames), rsOut.baseAddress, UInt32(rsOut.count))
                _ = spsc_write(ring, rsOut.baseAddress, n)
            } else {
                _ = spsc_write(ring, mono.baseAddress, UInt32(frames))
            }
            wake.signal()
        }
        if rc != noErr { throw EngineError.ioProcFailed }
    }

    private func installBridgeProc() throws {
        let ring = ringOut!
        let rc = AudioDeviceCreateIOProcIDWithBlock(&bridgeProc, bridgeID, nil) { _, _, _, outData, _ in
            guard let abl = UnsafeMutableAudioBufferListPointer(outData).first,
                  let data = abl.mData else { return }
            let frames = Int(abl.mDataByteSize) / MemoryLayout<Float>.size
            let ptr = data.assumingMemoryBound(to: Float.self)
            let got = spsc_read(ring, ptr, UInt32(frames))
            if Int(got) < frames { for i in Int(got)..<frames { ptr[i] = 0 } }
        }
        if rc != noErr { throw EngineError.ioProcFailed }
    }

    private func dspLoop() {
        let ring = ringIn!
        let outRing = ringOut!
        let scratch = dspScratch!
        while runningFlag.withLock({ $0 }) {
            wake.wait()
            while runningFlag.withLock({ $0 }), spsc_fill(ring) >= UInt32(hop) {
                let n = spsc_read(ring, scratch.baseAddress, UInt32(hop))
                if n < UInt32(hop) { break }
                let input = Array(UnsafeBufferPointer(start: scratch.baseAddress, count: hop))
                let out = chain.processHop(input)
                _ = out.withUnsafeBufferPointer { spsc_write(outRing, $0.baseAddress, UInt32(hop)) }
            }
        }
        dspExited.signal()
    }

    // MARK: - Device helpers

    public static func deviceID(uid: String) -> AudioDeviceID? {
        var cf = uid as CFString
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let st = withUnsafeMutablePointer(to: &cf) { p in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                       UInt32(MemoryLayout<CFString>.size), p, &size, &dev)
        }
        return (st == noErr && dev != 0) ? dev : nil
    }

    static func inputFormat(_ dev: AudioDeviceID) -> (Double, Int) {
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &asbd) == noErr {
            return (asbd.mSampleRate, max(1, Int(asbd.mChannelsPerFrame)))
        }
        return (48000.0, 1)
    }
}
