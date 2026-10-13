import Testing
@testable import SottoCore

private final class FailingDenoiser: DenoiseProcessing {
    let hopSize = 480
    var lastDb: Float = -1
    func setAttenLimitDb(_ db: Float) { lastDb = db }
    func process(_ input: [Float]) -> [Float]? { nil }   // always error
    func reset() {}
}

private final class GainDenoiser: DenoiseProcessing {
    let hopSize = 480
    func setAttenLimitDb(_ db: Float) {}
    func process(_ input: [Float]) -> [Float]? { input.map { $0 * 0.5 } }
    func reset() {}
}

@Test func failOpenPassesInputThrough() {
    let chain = DspChain(denoiser: FailingDenoiser())
    let input = (0..<480).map { Float($0) }
    #expect(chain.processHop(input) == input)  // model error => passthrough, never silence
}

@Test func bypassSkipsDenoiser() {
    let chain = DspChain(denoiser: GainDenoiser())
    chain.bypass = true
    let input = (0..<480).map { Float($0) }
    #expect(chain.processHop(input) == input)
}

@Test func strengthMapsToAttenLimit() {
    let d = FailingDenoiser()
    let chain = DspChain(denoiser: d)
    chain.setStrength(50)
    #expect(d.lastDb == 20.0)       // 50 * 0.4
    chain.setStrength(100)
    #expect(d.lastDb == 100.0)      // unlimited
    chain.setStrength(0)
    #expect(d.lastDb == 0.0)
}
