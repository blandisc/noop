import XCTest
@testable import StrandAnalytics

/// Invariants for the cycle-phase estimate. Pure math — no app, strap, or CoreBluetooth.
/// The hard product rules (never a date, never fertility, gate respected, states are the default)
/// are asserted here so a regression trips a red test, not a shipped claim.
final class CyclePhaseEngineTests: XCTestCase {

    private typealias Night = CyclePhaseEngine.NightSample

    /// Build `count` nights whose skin-temp deviation follows a 28-day cosine of amplitude `amp`
    /// (so the window genuinely oscillates), optionally with resting-HR / HRV series and per-night
    /// overrides for the final ("tonight") sample. Days are opaque ordered strings.
    private func nights(count: Int, amp: Double = 0.3,
                        withRHR: Bool = false, withHRV: Bool = false,
                        tonightTemp: Double? = nil, tonightHRV: Double?? = .none) -> (all: [Night], today: String) {
        var all: [Night] = []
        for i in 0..<count {
            let phase = 2.0 * Double.pi * Double(i) / 28.0
            let temp = amp * cos(phase)
            // RHR tracks temp (higher in luteal); HRV runs opposite (lower in luteal).
            let rhr: Double? = withRHR ? 55.0 + 3.0 * cos(phase) : nil
            let hrv: Double? = withHRV ? 65.0 - 8.0 * cos(phase) : nil
            all.append(Night(day: String(format: "d%03d", i),
                             skinTempDevC: temp, restingHr: rhr, avgHrv: hrv))
        }
        // Optionally override tonight (the last day) to a specific temperature / HRV.
        if let t = tonightTemp {
            let last = all.count - 1
            let base = all[last]
            let hrv: Double? = { if case let .some(v) = tonightHRV { return v } else { return base.avgHrv } }()
            all[last] = Night(day: base.day, skinTempDevC: t, restingHr: base.restingHr, avgHrv: hrv)
        }
        return (all, all.last!.day)
    }

    private func rank(_ c: CyclePhaseEngine.PhaseConfidence) -> Int {
        switch c { case .low: return 0; case .moderate: return 1; case .solid: return 2 }
    }

    // MARK: - Gate of nights (never a date; window-driven, not a single day)

    func testFewUsableNightsIsLearning() {
        let (all, today) = nights(count: 20)
        guard case let .learning(soFar, needed) = CyclePhaseEngine.estimate(all, asOf: today) else {
            return XCTFail("expected .learning")
        }
        XCTAssertEqual(soFar, 20)
        XCTAssertEqual(needed, CyclePhaseEngine.minUsableNights)
    }

    func testNilTempNightsDoNotCountTowardGate() {
        // 60 nights but only 30 carry a skin-temp reading → 30 usable < 42 → still learning at 30.
        var (all, today) = nights(count: 60)
        for i in stride(from: 0, to: 60, by: 2) {
            all[i] = Night(day: all[i].day, skinTempDevC: nil, restingHr: nil, avgHrv: nil)
        }
        guard case let .learning(soFar, _) = CyclePhaseEngine.estimate(all, asOf: today) else {
            return XCTFail("expected .learning")
        }
        XCTAssertEqual(soFar, 30)
    }

    func testNeverEstimatesBelowGateEvenWithStrongNight() {
        // A blatantly luteal final night must NOT produce an estimate while under the gate.
        let (all, today) = nights(count: 30, tonightTemp: 5.0)
        if case .estimated = CyclePhaseEngine.estimate(all, asOf: today) {
            XCTFail("must never estimate below the night gate")
        }
    }

    // MARK: - No clear pattern (flat / at-typical), designed default not error

    func testFlatSignalIsNoClearPattern() {
        // 56 nights of a constant deviation → robust σ ≈ 0 → no rhythm to read.
        let all = (0..<56).map { Night(day: String(format: "d%03d", $0), skinTempDevC: 0.1, restingHr: nil, avgHrv: nil) }
        XCTAssertEqual(CyclePhaseEngine.estimate(all, asOf: all.last!.day), .noClearPattern)
    }

    func testTonightAtTypicalLevelDeclinesToLean() {
        // Oscillating window, but tonight sits at the median (≈0) → decline to lean.
        let (all, today) = nights(count: 56, tonightTemp: 0.0)
        XCTAssertEqual(CyclePhaseEngine.estimate(all, asOf: today), .noClearPattern)
    }

    func testMissingTonightAnchorIsNoClearPattern() {
        let (all, _) = nights(count: 56)
        XCTAssertEqual(CyclePhaseEngine.estimate(all, asOf: "no-such-day"), .noClearPattern)
    }

    // MARK: - Estimated lean with hedge (phase, never a number to the user)

    func testClearLutealNightIsEstimatedLuteal() {
        let (all, today) = nights(count: 56, tonightTemp: 0.3)   // warm night → luteal-lean
        guard case let .estimated(phase, _, z) = CyclePhaseEngine.estimate(all, asOf: today) else {
            return XCTFail("expected .estimated")
        }
        XCTAssertEqual(phase, .lutealLean)
        XCTAssertGreaterThan(z, 0)
    }

    func testClearFollicularNightIsEstimatedFollicular() {
        let (all, today) = nights(count: 56, tonightTemp: -0.3)  // cool night → follicular-lean
        guard case let .estimated(phase, _, z) = CyclePhaseEngine.estimate(all, asOf: today) else {
            return XCTFail("expected .estimated")
        }
        XCTAssertEqual(phase, .follicularLean)
        XCTAssertLessThan(z, 0)
    }

    // MARK: - H1: HRV is conditional reinforcement, never a vote

    func testAgreeingHrvRaisesConfidence() {
        // 50 usable nights (< solidNights) so the temp-only ceiling is .moderate, leaving room to bump.
        // Run A: tonight HRV is low (drop = luteal-ward) → agrees with the luteal lean → bump.
        // Run B: tonight HRV absent → no bump.
        let a = nights(count: 50, amp: 0.3, withHRV: true, tonightTemp: 0.3, tonightHRV: .some(40.0))
        let b = nights(count: 50, amp: 0.3, withHRV: true, tonightTemp: 0.3, tonightHRV: .some(nil))
        guard case let .estimated(_, cA, _) = CyclePhaseEngine.estimate(a.all, asOf: a.today),
              case let .estimated(_, cB, _) = CyclePhaseEngine.estimate(b.all, asOf: b.today) else {
            return XCTFail("expected .estimated in both runs")
        }
        XCTAssertGreaterThan(rank(cA), rank(cB), "agreeing HRV must raise confidence")
    }

    func testDisagreeingHrvDoesNotChangePhase() {
        // Tonight is clearly luteal by temp, but HRV is HIGH (would argue follicular). Phase must stay
        // luteal — HRV never flips the lean; at most it withholds a confidence bump.
        let (all, today) = nights(count: 56, amp: 0.3, withHRV: true, tonightTemp: 0.3, tonightHRV: .some(90.0))
        guard case let .estimated(phase, _, _) = CyclePhaseEngine.estimate(all, asOf: today) else {
            return XCTFail("expected .estimated")
        }
        XCTAssertEqual(phase, .lutealLean)
    }

    // MARK: - Determinism & pinned calibration

    func testDeterministic() {
        let (all, today) = nights(count: 56, withRHR: true, withHRV: true, tonightTemp: 0.3)
        XCTAssertEqual(CyclePhaseEngine.estimate(all, asOf: today),
                       CyclePhaseEngine.estimate(all, asOf: today))
    }

    func testCalibrationConstantsPinned() {
        // These are product-calibration knobs (H2); this test is the single audit point.
        XCTAssertEqual(CyclePhaseEngine.minUsableNights, 42)
        XCTAssertEqual(CyclePhaseEngine.weightTemp, 0.75, accuracy: 1e-9)
        XCTAssertEqual(CyclePhaseEngine.weightRHR, 0.25, accuracy: 1e-9)
        XCTAssertEqual(CyclePhaseEngine.weightTemp + CyclePhaseEngine.weightRHR, 1.0, accuracy: 1e-9)
    }
}
