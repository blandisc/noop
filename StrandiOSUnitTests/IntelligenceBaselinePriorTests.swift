import XCTest
import WhoopStore
import StrandAnalytics
@testable import NOOP

/// Pins the FER-60 Apple Health baseline prior: the pure helpers that fold Apple Health nights UNDER
/// the strap layers (lowest precedence, capped) so a brand-new strap user crosses
/// `Baselines.minNightsSeed` and recovery lights up from night 1 — without ever letting Apple Health
/// override the strap. Pure logic, mirroring the JournalLogicTests merge-precedence style.
final class IntelligenceBaselinePriorTests: XCTestCase {

    /// Minimal DailyMetric carrying just the fields the prior reads.
    private func dm(_ day: String, hrv: Double? = nil, rhr: Int? = nil, resp: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, respRateBpm: resp)
    }

    // MARK: - applePriorDays (the cap)

    func testApplePriorDaysSelectsMostRecentNightsWithHrv() {
        // 10 Apple nights, day-ascending (the store read order). The cap keeps the newest 7.
        let rows = (1...10).map { dm(String(format: "2026-06-%02d", $0), hrv: 50 + Double($0)) }
        let days = IntelligenceEngine.applePriorDays(rows, maxNights: 7)
        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days.contains("2026-06-10"))         // newest kept
        XCTAssertTrue(days.contains("2026-06-04"))         // boundary kept
        XCTAssertFalse(days.contains("2026-06-03"))        // older than the 7 most recent
        XCTAssertFalse(days.contains("2026-06-01"))
    }

    func testApplePriorDaysIgnoresNilHrvNights() {
        // Nights without a usable HRV don't count toward the cap (robust to gaps).
        let rows = [dm("2026-06-01", hrv: 55), dm("2026-06-02", hrv: nil), dm("2026-06-03", hrv: 60),
                    dm("2026-06-04", hrv: nil), dm("2026-06-05", hrv: 58)]
        let days = IntelligenceEngine.applePriorDays(rows, maxNights: 7)
        XCTAssertEqual(days, ["2026-06-01", "2026-06-03", "2026-06-05"])
    }

    func testApplePriorDaysCapNeverExceedsMaxNights() {
        let rows = (1...20).map { dm(String(format: "2026-06-%02d", $0), hrv: 55) }
        XCTAssertEqual(IntelligenceEngine.applePriorDays(rows, maxNights: 7).count, 7)
    }

    // MARK: - foldApplePrior (the precedence)

    func testStrapValueWinsOnCollision() {
        // Apple must never overwrite a day the strap already has.
        let strap: [String: Double?] = ["2026-06-10": 48.0]
        let apple: [String: Double?] = ["2026-06-10": 99.0, "2026-06-09": 60.0]
        let out = IntelligenceEngine.foldApplePrior(into: strap, apple: apple,
                                                    priorDays: ["2026-06-10", "2026-06-09"])
        XCTAssertEqual(out["2026-06-10"] ?? nil, 48.0)     // strap wins
        XCTAssertEqual(out["2026-06-09"] ?? nil, 60.0)     // apple fills the uncovered day
        XCTAssertEqual(out.count, 2)
    }

    func testApplePriorOnlyFillsDaysInPriorDays() {
        // A day outside the capped set is left out even when the strap doesn't cover it.
        let strap: [String: Double?] = [:]
        let apple: [String: Double?] = ["2026-06-09": 60.0, "2026-06-08": 58.0]
        let out = IntelligenceEngine.foldApplePrior(into: strap, apple: apple,
                                                    priorDays: ["2026-06-09"])
        XCTAssertEqual(out["2026-06-09"] ?? nil, 60.0)
        XCTAssertNil(out["2026-06-08"] ?? nil)             // not in priorDays → excluded
        XCTAssertEqual(out.count, 1)
    }

    func testPresentNilDayIsNotFilledByApple() {
        // The strap "owns" a night it recorded even if its HRV is nil — same `== nil` idiom as the
        // imported/computed merge: a present key (value nil) is NOT absent, so Apple must not fill it.
        var strap: [String: Double?] = [:]
        strap.updateValue(nil, forKey: "2026-06-10")       // key present, value nil
        let apple: [String: Double?] = ["2026-06-10": 55.0]
        let out = IntelligenceEngine.foldApplePrior(into: strap, apple: apple,
                                                    priorDays: ["2026-06-10"])
        XCTAssertEqual(out.count, 1)
        XCTAssertNil(out["2026-06-10"] ?? nil)             // still nil, not 55
    }

    // MARK: - End-to-end mechanism (pure): prior → provisional baseline → recovery scores

    func testApplePriorSeedsProvisionalUsableBaselineThatScores() {
        // One strap night alone can't clear minNightsSeed (4). A 6-night Apple prior seeds the gap.
        let strap: [String: Double?] = ["2026-06-13": 52.0]
        let apple: [String: Double?] = ["2026-06-07": 60, "2026-06-08": 58, "2026-06-09": 61,
                                        "2026-06-10": 59, "2026-06-11": 57, "2026-06-12": 62]
        let merged = IntelligenceEngine.foldApplePrior(into: strap, apple: apple,
                                                       priorDays: Set(apple.keys))
        XCTAssertEqual(merged.count, 7)

        // Fold chronologically (lexicographic ISO day == chronological) → baseline crosses the gate.
        let seq = merged.keys.sorted().map { merged[$0]! }
        let state = Baselines.foldHistory(seq, cfg: Baselines.hrvCfg)
        XCTAssertTrue(state.usable, "7 seeded nights must clear the seed gate")
        XCTAssertEqual(state.status, .provisional, "capped prior stays provisional, not trusted")

        // Recovery now lights up (was nil under 4 nights), shrunk by the provisional confidence.
        let score = RecoveryScorer.recovery(
            hrv: 52, rhr: 55, resp: nil,
            hrvBaseline: RecoveryScorer.DriverBaseline(state),
            rhrBaseline: nil, respBaseline: nil, sleepPerf: nil,
            hrvBaselineUsable: state.usable)
        XCTAssertNotNil(score, "recovery lights up once the baseline is seeded")
    }
}
