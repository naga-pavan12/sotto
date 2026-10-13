import Testing
import Foundation
import SottoRT

// A 44.1 kHz sine resampled to 48 kHz should keep its frequency and grow in
// length by ~48/44.1, confirming correct rate conversion (not pitch-shifting).
@Test func resamples44kTo48kPreservingTone() {
    let inRate = 44100.0, outRate = 48000.0, hz = 1000.0
    let nIn = 44100
    var input = [Float](repeating: 0, count: nIn)
    for i in 0..<nIn { input[i] = Float(sin(2 * Double.pi * hz * Double(i) / inRate)) }

    let r = rs_create(inRate, outRate)
    #expect(r != nil)
    var out = [Float](repeating: 0, count: nIn * 2)
    let n = rs_process(r, &input, UInt32(nIn), &out, UInt32(out.count))
    rs_destroy(r)

    // Length ratio ~ 48000/44100.
    let ratio = Double(n) / Double(nIn)
    #expect(abs(ratio - outRate / inRate) < 0.02)

    // Dominant frequency: count zero crossings over the valid region.
    let ni = Int(n); let valid = Array(out[(ni/4)..<(ni*3/4)])
    var crossings = 0
    for i in 1..<valid.count where (valid[i-1] < 0) != (valid[i] < 0) { crossings += 1 }
    let seconds = Double(valid.count) / outRate
    let measuredHz = Double(crossings) / 2.0 / seconds
    #expect(abs(measuredHz - hz) < 30.0)
}
