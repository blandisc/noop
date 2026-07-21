import XCTest
import CenitStore
import StrandAnalytics
@testable import Cenit

/// FER-884 / F6 — Apple-only illness detection. The resting-HR term scores Apple's own RHR against the
/// user's OWN Apple baseline: a WITHIN-SOURCE z-score, valid despite Apple's awake-sedentary RHR offset
/// (~10–13 bpm above a band's sleep-nadir; Fenland Study, Gonzales et al. 2023, PLoS One 18(5):e0285272)
/// because it compares Apple to the Apple norm, never mixing sources. Every night is Apple, so the
/// history is used as-is (no source masking). Pins that a real Apple RHR rise is detectable.
final class IllnessWatchSourceTests: XCTestCase {

    private func dm(_ day: String, rhr: Int?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: nil, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    /// The illness RHR term's baseline sample, replicated verbatim from `evaluateIllness`.
    private func rhrBase(_ src: [DailyMetric]) -> [Double] {
        Array(src.suffix(31).dropLast(3)).compactMap { $0.restingHr.map(Double.init) }
    }

    /// A stable Apple RHR baseline (~72 bpm awake sedentary); a real +8 bpm rise fires the anomaly
    /// against the user's own Apple norm — the history is used as-is (every night is Apple).
    func testAppleRhrRiseFiresWithinSource() {
        var days: [DailyMetric] = []
        let cycle = [71, 72, 73]
        for i in 0..<33 {
            days.append(dm(String(format: "2026-06-%02d", i + 1), rhr: cycle[i % 3]))
        }
        let base = rhrBase(days)
        XCTAssertFalse(base.isEmpty, "the Apple baseline carries Apple's own RHR (used as-is)")
        XCTAssertTrue(
            IllnessWatch.isAnomaly(recentMean: 80.0, base: base, higherIsWorse: true),
            "against the Apple baseline, +8 bpm is several σ → the RHR anomaly fires in Apple-only mode")
    }
}
