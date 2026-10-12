import Testing
@testable import SottoCore

@Test func sustainedOverloadBypassesThenRecovers() {
    var now = 0.0
    let w = Watchdog()
    // 25 hops at 8 ms each (> 7.5 ms hard threshold) across >20 frames.
    for _ in 0..<25 {
        w.recordHopTime(0.008)
        now += 0.01
        w.tick(now: now)
    }
    #expect(w.state == .overloadHard)
    #expect(w.shouldBypass == true)

    // After 30 s of fast hops, bypass clears.
    for _ in 0..<40 {
        w.recordHopTime(0.001)
        now += 1.0
        w.tick(now: now)
    }
    #expect(w.shouldBypass == false)
}

@Test func noFramesDetected() {
    let w = Watchdog()
    w.recordHopTime(0.001)
    w.tick(now: 1.0)
    w.tick(now: 5.0) // >3 s since last hop
    #expect(w.state == .noFrames)
}

@Test func allZerosDetected() {
    let w = Watchdog()
    for i in 0..<10 {
        w.recordHopTime(0.001)
        w.recordCapture(energy: 0.0)
        w.tick(now: Double(i) * 0.7) // spans >5 s
    }
    #expect(w.state == .silent)
}
