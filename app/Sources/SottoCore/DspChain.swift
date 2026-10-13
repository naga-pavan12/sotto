/// Per-hop processing: denoise unless bypassed, and always fail open (pass the
/// input through) if the model errors, so a call never drops to silence.
public final class DspChain {
    private let denoiser: DenoiseProcessing
    public var bypass = false

    public init(denoiser: DenoiseProcessing) { self.denoiser = denoiser }

    /// Map strength 0..100 to the denoiser's attenuation limit in dB.
    /// 100 => unlimited (full reduction); 0 => no reduction.
    public func setStrength(_ strength: Int) {
        let s = max(0, min(100, strength))
        denoiser.setAttenLimitDb(s >= 100 ? 100.0 : Float(s) * 0.4)
    }

    public func processHop(_ input: [Float]) -> [Float] {
        if bypass { return input }
        return denoiser.process(input) ?? input
    }
}
