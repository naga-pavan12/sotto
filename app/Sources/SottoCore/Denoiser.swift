import CSottoDenoiser

/// Noise-cancellation processor over one hop of mono 48 kHz float samples.
/// Injectable so the DSP chain is testable without the native model.
public protocol DenoiseProcessing: AnyObject {
    var hopSize: Int { get }
    func setAttenLimitDb(_ db: Float)
    /// Returns an enhanced hop, or nil on error (caller passes the input through).
    func process(_ input: [Float]) -> [Float]?
    func reset()
}

/// DeepFilterNet3-backed denoiser (wraps the Rust C ABI).
public final class DFNDenoiser: DenoiseProcessing {
    private let handle: OpaquePointer?

    public init?() {
        guard let h = sotto_denoiser_new() else { return nil }
        handle = h
    }

    public var hopSize: Int { Int(sotto_denoiser_hop_size(handle)) }

    public func setAttenLimitDb(_ db: Float) { sotto_denoiser_set_atten_lim_db(handle, db) }

    public func process(_ input: [Float]) -> [Float]? {
        var out = [Float](repeating: 0, count: input.count)
        let rc = input.withUnsafeBufferPointer { ip in
            out.withUnsafeMutableBufferPointer { op in
                sotto_denoiser_process(handle, ip.baseAddress, op.baseAddress)
            }
        }
        return rc == 0 ? out : nil
    }

    public func reset() { sotto_denoiser_reset(handle) }

    deinit { sotto_denoiser_free(handle) }
}
