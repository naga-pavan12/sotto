import os

/// Per-hop processing: denoise unless bypassed, and always fail open (pass the
/// input through) if the model errors, so a call never drops to silence.
///
/// The denoiser handle must be mutated only from the DSP thread. Callers on other
/// threads use `requestStrength` / `requestReset` / `setBypass`, which store intent
/// behind a lock; `processHop` (DSP thread) applies it before each hop. This keeps
/// a single owner of the native handle and avoids concurrent `&mut` across the FFI.
public final class DspChain {
    private let denoiser: DenoiseProcessing
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var pendingStrength: Int? = nil
        var pendingReset = false
        var bypass = false
    }

    public init(denoiser: DenoiseProcessing) { self.denoiser = denoiser }

    /// Thread-safe: request a strength change (applied on the next DSP tick).
    public func requestStrength(_ strength: Int) {
        state.withLock { $0.pendingStrength = max(0, min(100, strength)) }
    }

    /// Thread-safe: request a model reset (applied on the next DSP tick).
    public func requestReset() { state.withLock { $0.pendingReset = true } }

    /// Thread-safe: enable/disable bypass.
    public func setBypass(_ on: Bool) { state.withLock { $0.bypass = on } }

    /// DSP thread only. Applies any pending control changes, then denoises (or
    /// passes through on bypass / model error).
    public func processHop(_ input: [Float]) -> [Float] {
        let (strength, reset, bypass): (Int?, Bool, Bool) = state.withLock {
            let s = $0.pendingStrength; $0.pendingStrength = nil
            let r = $0.pendingReset; $0.pendingReset = false
            return (s, r, $0.bypass)
        }
        if let s = strength { denoiser.setAttenLimitDb(s >= 100 ? 100.0 : Float(s) * 0.4) }
        if reset { denoiser.reset() }
        if bypass { return input }
        return denoiser.process(input) ?? input
    }
}
