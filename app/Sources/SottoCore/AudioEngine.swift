import AudioToolbox
import CoreAudio
import Foundation
import SottoRT

/// Captures the chosen physical mic, denoises each 10 ms hop on a real-time
/// thread, and writes the result into the hidden "Sotto Bridge" output device;
/// the driver then presents it as "Sotto Microphone" to call apps.
public final class AudioEngine {
    public enum EngineError: Error { case deviceNotFound, ioProcFailed, denoiserFailed }

    private let hop = 480                 // 10 ms at 48 kHz
    private let sr = 48000.0
    private let bridgeUID = "SottoBridge"

    private let chain: DspChain
    private let denoiser: DFNDenoiser
    private var ringIn: OpaquePointer?    // mic -> DSP
    private var ringOut: OpaquePointer?   // DSP -> bridge
    private var resampler: OpaquePointer?

    private var micID = AudioDeviceID(0)
    private var bridgeID = AudioDeviceID(0)
    private var micProc: AudioDeviceIOProcID?
    private var bridgeProc: AudioDeviceIOProcID?

    private var dspThread: Thread?
    private let sem = DispatchSemaphore(value: 0)
    private var running = false
    private var micRate = 48000.0
    private var micChannels: UInt32 = 1

    public var strength: Int = 80 { didSet { chain.setStrength(strength) } }
    public var bypass: Bool = false { didSet { chain.bypass = bypass } }

    public init?() {
        guard let d = DFNDenoiser() else { return nil }
        denoiser = d
        chain = DspChain(denoiser: d)
        chain.setStrength(strength)
    }

    public func start(micUID: String) throws {
        guard let mic = Self.deviceID(uid: micUID), let bridge = Self.deviceID(uid: bridgeUID) else {
            throw EngineError.deviceNotFound
        }
        micID = mic
        bridgeID = bridge
        (micRate, micChannels) = Self.inputFormat(mic)

        ringIn = spsc_create(UInt32(hop * 16))
        ringOut = spsc_create(UInt32(hop * 16))
        if micRate != sr { resampler = rs_create(micRate, sr) }

        running = true
        let t = Thread { [weak self] in self?.dspLoop() }
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
        running = false
        sem.signal()
        if micProc != nil { AudioDeviceStop(micID, micProc); AudioDeviceDestroyIOProcID(micID, micProc!); micProc = nil }
        if bridgeProc != nil { AudioDeviceStop(bridgeID, bridgeProc); AudioDeviceDestroyIOProcID(bridgeID, bridgeProc!); bridgeProc = nil }
        if let r = ringIn { spsc_destroy(r); ringIn = nil }
        if let r = ringOut { spsc_destroy(r); ringOut = nil }
        if let r = resampler { rs_destroy(r); resampler = nil }
    }

    // MARK: - Real-time IO

    private func installMicProc() throws {
        let rc = AudioDeviceCreateIOProcIDWithBlock(&micProc, micID, nil) { [weak self] _, inData, _, _, _ in
            guard let self, let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData)).first,
                  let data = abl.mData else { return }
            let totalSamples = Int(abl.mDataByteSize) / MemoryLayout<Float>.size
            let ch = Int(self.micChannels)
            let frames = ch > 0 ? totalSamples / ch : totalSamples
            let ptr = data.assumingMemoryBound(to: Float.self)
            // Downmix to mono.
            var mono = [Float](repeating: 0, count: frames)
            if ch == 1 {
                for i in 0..<frames { mono[i] = ptr[i] }
            } else {
                for i in 0..<frames {
                    var acc: Float = 0
                    for c in 0..<ch { acc += ptr[i * ch + c] }
                    mono[i] = acc / Float(ch)
                }
            }
            // Resample to 48 kHz if needed.
            if let rs = self.resampler {
                var out = [Float](repeating: 0, count: frames * 2 + 16)
                let n = mono.withUnsafeBufferPointer { ip in
                    out.withUnsafeMutableBufferPointer { op in
                        rs_process(rs, ip.baseAddress, UInt32(frames), op.baseAddress, UInt32(op.count))
                    }
                }
                _ = out.withUnsafeBufferPointer { spsc_write(self.ringIn, $0.baseAddress, n) }
            } else {
                _ = mono.withUnsafeBufferPointer { spsc_write(self.ringIn, $0.baseAddress, UInt32(frames)) }
            }
            self.sem.signal()
        }
        if rc != noErr { throw EngineError.ioProcFailed }
    }

    private func installBridgeProc() throws {
        let hop = self.hop
        let rc = AudioDeviceCreateIOProcIDWithBlock(&bridgeProc, bridgeID, nil) { [weak self] _, _, _, outData, _ in
            guard let self,
                  let abl = UnsafeMutableAudioBufferListPointer(outData).first,
                  let data = abl.mData else { return }
            let frames = Int(abl.mDataByteSize) / MemoryLayout<Float>.size
            let ptr = data.assumingMemoryBound(to: Float.self)
            let got = spsc_read(self.ringOut, ptr, UInt32(frames))
            if Int(got) < frames {  // underrun -> fill the rest with silence
                for i in Int(got)..<frames { ptr[i] = 0 }
            }
            _ = hop
        }
        if rc != noErr { throw EngineError.ioProcFailed }
    }

    private func dspLoop() {
        var inBuf = [Float](repeating: 0, count: hop)
        while running {
            sem.wait()
            while running, spsc_fill(ringIn) >= UInt32(hop) {
                let n = inBuf.withUnsafeMutableBufferPointer { spsc_read(ringIn, $0.baseAddress, UInt32(hop)) }
                if n < UInt32(hop) { break }
                let out = chain.processHop(inBuf)
                _ = out.withUnsafeBufferPointer { spsc_write(ringOut, $0.baseAddress, UInt32(hop)) }
            }
        }
    }

    // MARK: - Device helpers

    static func deviceID(uid: String) -> AudioDeviceID? {
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

    static func inputFormat(_ dev: AudioDeviceID) -> (Double, UInt32) {
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &asbd) == noErr {
            return (asbd.mSampleRate, max(1, asbd.mChannelsPerFrame))
        }
        return (48000.0, 1)
    }
}
