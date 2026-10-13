import Testing
@testable import SottoCore

// The denoiser handle must only be mutated from the DSP thread. DspChain owns the
// denoiser; strength changes are applied by the chain (DSP-thread side), never by
// callers touching the denoiser directly. This pins that the chain, not the engine,
// is the single owner that calls setAttenLimitDb.
private final class RecordingDenoiser: DenoiseProcessing {
    let hopSize = 480
    var attenCalls: [Float] = []
    func setAttenLimitDb(_ db: Float) { attenCalls.append(db) }
    func process(_ input: [Float]) -> [Float]? { input }
    func reset() {}
}

@Test func pendingStrengthAppliedOnDspTick() {
    let d = RecordingDenoiser()
    let chain = DspChain(denoiser: d)
    chain.requestStrength(30)          // called from any thread (stores pending)
    #expect(d.attenCalls.isEmpty)      // not applied yet
    _ = chain.processHop([Float](repeating: 0, count: 480))  // DSP tick applies it
    #expect(d.attenCalls == [12.0])    // 30 * 0.4, applied exactly once on the DSP thread
}
