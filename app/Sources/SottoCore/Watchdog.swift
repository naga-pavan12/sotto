import Foundation

/// Health state of the audio engine, surfaced to the UI.
public enum WatchdogState: Equatable {
    case ok, overloadSoft, overloadHard, noFrames, silent
}

/// Watches per-frame processing time and capture health, and decides when to
/// bypass the denoiser (so an overloaded machine keeps the call alive rather than
/// dropping out). Pure logic: driven by `recordHopTime`, `recordCapture`, `tick`.
public final class Watchdog {
    // Thresholds (fractions of a 10 ms frame).
    private let softSec = 0.00375   // 37.5%
    private let hardSec = 0.0075    // 75%
    private let hardSustainedFrames = 20
    private let cooldownSec = 30.0
    private let noFramesSec = 3.0
    private let silentSec = 5.0
    private let window = 50

    private var hopTimes: [Double] = []
    private var hardStreak = 0
    private var bypassing = false
    private var bypassStartedAt = 0.0
    private var lastHopAt: Double? = nil
    private var zerosSince: Double? = nil
    private var lastEnergyWasZero = false

    public init() {}

    public private(set) var state: WatchdogState = .ok
    public var shouldBypass: Bool { bypassing }

    /// Record one hop's processing duration in seconds.
    public func recordHopTime(_ seconds: Double) {
        hopTimes.append(seconds)
        if hopTimes.count > window { hopTimes.removeFirst(hopTimes.count - window) }
        hopCounter += 1
    }

    /// Record the captured energy of one frame (sum of squares).
    public func recordCapture(energy: Float) {
        lastEnergyWasZero = energy <= 1e-8
    }

    private func movingAvg() -> Double {
        guard !hopTimes.isEmpty else { return 0 }
        return hopTimes.reduce(0, +) / Double(hopTimes.count)
    }

    /// Advance time; recomputes state and the bypass decision. `now` is monotonic seconds.
    public func tick(now: Double) {
        updateFrameClock(now: now)
        updateZeroClock(now: now)
        updateOverload(now: now)

        // Decide state by precedence: missing frames and silence dominate overload.
        if let last = lastHopAt, now - last > noFramesSec {
            state = .noFrames
        } else if let z = zerosSince, now - z > silentSec {
            state = .silent
        } else if bypassing {
            state = .overloadHard
        } else if movingAvg() > softSec {
            state = .overloadSoft
        } else {
            state = .ok
        }
    }

    // Monotonic count of hops recorded; a tick that sees it advance marks "a frame arrived now".
    private var hopCounter = 0
    private var lastSeenHopCounter = 0

    private func updateFrameClock(now: Double) {
        if hopCounter != lastSeenHopCounter {
            lastHopAt = now
            lastSeenHopCounter = hopCounter
        }
    }

    private func updateZeroClock(now: Double) {
        if lastEnergyWasZero {
            if zerosSince == nil { zerosSince = now }
        } else {
            zerosSince = nil
        }
    }

    private func updateOverload(now: Double) {
        let avg = movingAvg()
        if avg > hardSec {
            hardStreak += 1
        } else {
            hardStreak = 0
        }
        if !bypassing && hardStreak >= hardSustainedFrames {
            bypassing = true
            bypassStartedAt = now
        } else if bypassing {
            if now - bypassStartedAt >= cooldownSec && avg < softSec {
                bypassing = false
                hardStreak = 0
            }
        }
    }
}
