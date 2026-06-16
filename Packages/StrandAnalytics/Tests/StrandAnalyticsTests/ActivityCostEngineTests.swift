import XCTest
@testable import StrandAnalytics

/// ActivityCostEngine — "what each activity is associated with for your recovery".
///
/// These fixtures exercise the ADJUSTED method (FER-123), which deliberately departs from
/// the upstream NoopApp/noop engine after an expert review of the statistics:
///   • robust MEDIAN center (not the arithmetic mean),
///   • minSessions = 6 (was 4),
///   • barelyMovesPoints = 3.0 (was 1.0),
///   • daysToBaseline only surfaced for `.solid` results,
///   • narrative framed as ASSOCIATION, not a causal cost.
/// So the upstream's numeric oracle does NOT apply; every expected value here is recomputed
/// by hand for the adjusted method. (Re-syncing the Android oracle is FER-140.)
final class ActivityCostEngineTests: XCTestCase {

    // MARK: - Fixture helpers

    /// `count` session day-keys starting at `start`, `step` days apart (fixed UTC calendar).
    private func sessions(from start: String, count: Int, step: Int) -> Set<String> {
        Set((0..<count).map { CorrelationEngine.shiftDay(start, by: $0 * step)! })
    }

    /// Write a forward Charge profile (offset → value) onto `rec` for every session.
    private func addForward(_ rec: inout [String: Double], sessions: Set<String>, profile: [Int: Double]) {
        for s in sessions {
            for (k, v) in profile { rec[CorrelationEngine.shiftDay(s, by: k)!] = v }
        }
    }

    /// A clean rest block far before any session (untouched: not tagged, not in any window).
    private func restBlock(_ values: [Double], from start: String = "2026-01-01") -> [String: Double] {
        var rec: [String: Double] = [:]
        for (i, v) in values.enumerated() { rec[CorrelationEngine.shiftDay(start, by: i)!] = v }
        return rec
    }

    // MARK: - Median (not mean) is the center  [adjustment #2]

    func testMedianNotMeanForBaselineAndNextMorning() {
        // Rest block with a low outlier: {70,70,70,70,10}. median = 70, mean = 58.
        var rec = restBlock([70, 70, 70, 70, 10])
        // 6 sessions, every other day; five next-mornings at 50 and one sick morning at 0.
        // next-mornings {50,50,50,50,50,0}: median = 50, mean ≈ 41.67.
        let tagged = sessions(from: "2026-03-01", count: 6, step: 2) // Mar 01,03,05,07,09,11
        for (i, s) in tagged.sorted().enumerated() {
            rec[CorrelationEngine.shiftDay(s, by: 1)!] = (i == 5 ? 0 : 50)
        }

        let out = ActivityCostEngine.evaluate(activityDaysBySport: ["Running": tagged], recoveryByDay: rec)
        XCTAssertEqual(out.count, 1)
        let r = out[0]
        // Medians, not means — a mean center would give baseline 58 / nextMorning ≈ 41.67.
        XCTAssertEqual(r.baselineCenter, 70, accuracy: 1e-9)
        XCTAssertEqual(r.nextMorningCenter, 50, accuracy: 1e-9)
        XCTAssertEqual(r.delta, 20, accuracy: 1e-9)
        XCTAssertEqual(r.n, 6)
        XCTAssertEqual(r.confidence, .building)        // 6 ≤ n < 8
        XCTAssertNil(r.daysToBaseline)                 // not .solid → withheld
    }

    // MARK: - Baseline excludes the post-effect window

    func testBaselineExcludesPostEffectWindow() {
        // 6 sessions 10 days apart; each next-morning Charge is 50. Rest block is 60.
        // If the 50-valued window days leaked into the baseline it would drop to 50;
        // a baseline of 60 proves the D+1…D+7 window is excluded from "rest".
        var rec = restBlock([60, 60, 60, 60, 60])
        let tagged = sessions(from: "2026-01-10", count: 6, step: 10)
        addForward(&rec, sessions: tagged, profile: [1: 50])

        let r = ActivityCostEngine.evaluate(activityDaysBySport: ["Lifting": tagged], recoveryByDay: rec)[0]
        XCTAssertEqual(r.baselineCenter, 60, accuracy: 1e-9)
        XCTAssertEqual(r.nextMorningCenter, 50, accuracy: 1e-9)
        XCTAssertEqual(r.delta, 10, accuracy: 1e-9)
        XCTAssertEqual(r.n, 6)
        XCTAssertEqual(r.confidence, .building)
    }

    // MARK: - daysToBaseline only for .solid  [adjustment #4]

    func testSolidComputesMedianForwardDaysToBaseline() {
        // 8 sessions 10 days apart (windows never overlap) → .solid.
        // Forward profile per session: D+1=40, D+2=45, D+3…D+7=60. Rest block = 63.
        // traj[k] = median over sessions of Charge[D+k] = {40,45,60,60,…}.
        // target = baseline − tol = 63 − 3 = 60 → first k with traj[k] ≥ 60 is k = 3.
        var rec = restBlock([63, 63, 63, 63, 63])
        let tagged = sessions(from: "2026-01-10", count: 8, step: 10)
        addForward(&rec, sessions: tagged, profile: [1: 40, 2: 45, 3: 60, 4: 60, 5: 60, 6: 60, 7: 60])

        let r = ActivityCostEngine.evaluate(activityDaysBySport: ["Trail": tagged], recoveryByDay: rec)[0]
        XCTAssertEqual(r.n, 8)
        XCTAssertEqual(r.confidence, .solid)
        XCTAssertEqual(r.baselineCenter, 63, accuracy: 1e-9)
        XCTAssertEqual(r.nextMorningCenter, 40, accuracy: 1e-9)
        XCTAssertEqual(r.delta, 23, accuracy: 1e-9)
        XCTAssertEqual(r.daysToBaseline, 3)
    }

    // MARK: - Confidence bands + solid-but-never-recovers

    func testConfidenceBandsAndSolidWithoutRecovery() {
        // Three sports at n = 6, 7, 8; all next-mornings 50, rest block 70 → delta 20 each.
        var rec = restBlock([70, 70, 70, 70, 70])
        let s6 = sessions(from: "2026-04-01", count: 6, step: 2)
        let s7 = sessions(from: "2026-05-01", count: 7, step: 2)
        let s8 = sessions(from: "2026-06-01", count: 8, step: 2)
        for s in [s6, s7, s8] { addForward(&rec, sessions: s, profile: [1: 50]) }

        let out = ActivityCostEngine.evaluate(
            activityDaysBySport: ["S6": s6, "S7": s7, "S8": s8], recoveryByDay: rec)
        let by = Dictionary(uniqueKeysWithValues: out.map { ($0.sport, $0) })
        XCTAssertEqual(by["S6"]?.confidence, .building)   // 6
        XCTAssertEqual(by["S7"]?.confidence, .building)   // 7
        XCTAssertEqual(by["S8"]?.confidence, .solid)      // 8
        // .solid, but only D+1 has data (target 67 > 50) so the trajectory never recovers → nil.
        XCTAssertNil(by["S8"]?.daysToBaseline)
        // Ranking on a |delta| tie: .solid first, then .building by name asc.
        XCTAssertEqual(out.map(\.sport), ["S8", "S6", "S7"])
    }

    // MARK: - minSessions = 6 boundary  [adjustment #3]

    func testThinSportOmittedAtFiveIncludedAtSix() {
        var rec = restBlock([60, 60, 60, 60, 60])
        let thin = sessions(from: "2026-02-01", count: 5, step: 2)   // n = 5 → omitted
        let thick = sessions(from: "2026-03-01", count: 6, step: 2)  // n = 6 → reported
        addForward(&rec, sessions: thin, profile: [1: 50])
        addForward(&rec, sessions: thick, profile: [1: 40])

        let out = ActivityCostEngine.evaluate(
            activityDaysBySport: ["AThin": thin, "BThick": thick], recoveryByDay: rec)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].sport, "BThick")
        XCTAssertEqual(out[0].n, 6)
        XCTAssertEqual(out[0].delta, 20, accuracy: 1e-9)
    }

    // MARK: - Empty / no-baseline guards

    func testEmptyInputsReturnEmpty() {
        XCTAssertTrue(ActivityCostEngine.evaluate(activityDaysBySport: [:], recoveryByDay: [:]).isEmpty)
        XCTAssertTrue(ActivityCostEngine.evaluate(
            activityDaysBySport: ["Run": ["2026-01-01"]], recoveryByDay: [:]).isEmpty)
    }

    func testNoUntouchedRestDaysReturnEmpty() {
        // Every day with a Charge value sits inside a session's forward window → no baseline.
        var rec: [String: Double] = [:]
        let tagged = sessions(from: "2026-01-10", count: 6, step: 2)
        addForward(&rec, sessions: tagged, profile: [1: 50])   // only D+1 days, all affected
        XCTAssertTrue(ActivityCostEngine.evaluate(
            activityDaysBySport: ["Run": tagged], recoveryByDay: rec).isEmpty)
    }

    // MARK: - Ranking is deterministic

    func testRankingByAbsDeltaThenConfidenceThenName() {
        func mk(_ sport: String, _ delta: Double, _ c: ScoreConfidence) -> ActivityCost {
            ActivityCost(sport: sport, delta: delta, nextMorningCenter: 0, baselineCenter: 0,
                         daysToBaseline: nil, n: 6, confidence: c)
        }
        let ranked = ActivityCostEngine.rank([
            mk("Cfive", 5, .building),
            mk("ABuildTen", 10, .building),
            mk("Zfive", -5, .building),   // |−5| ties Cfive → name asc breaks it
            mk("BSolidTen", 10, .solid),  // ties ABuildTen on |10| → .solid wins
        ])
        XCTAssertEqual(ranked.map(\.sport), ["BSolidTen", "ABuildTen", "Cfive", "Zfive"])
    }

    // MARK: - Narrative framed as association (not causal)  [adjustments #1, #5]

    func testSentenceIsAssociationalAndRespectsBarelyMoves() {
        func ac(_ delta: Double, days: Int? = nil) -> ActivityCost {
            ActivityCost(sport: "X", delta: delta, nextMorningCenter: 0, baselineCenter: 0,
                         daysToBaseline: days, n: 6, confidence: .building)
        }
        // |delta| < 3.0 → "barely linked"; never a causal "cost".
        let barely = ac(2.0).sentence()
        XCTAssertTrue(barely.contains("barely linked"))
        XCTAssertFalse(barely.contains("typically"))

        // Boundary: exactly 3.0 is NOT barely (strict <) → reports a 3-point gap.
        let atThreshold = ac(3.0).sentence()
        XCTAssertTrue(atThreshold.contains("typically followed"))
        XCTAssertTrue(atThreshold.contains("3 points"))
        XCTAssertTrue(atThreshold.contains("lower"))

        // Negative delta → "higher" (you tend to wake above baseline).
        XCTAssertTrue(ac(-4.0).sentence().contains("higher"))

        // Bounce-back clause appears only with daysToBaseline; singular day.
        XCTAssertTrue(ac(5.0, days: 1).sentence().contains("climbing back in about 1 day"))

        // No causal language anywhere.
        for d in [2.0, 3.0, -4.0, 5.0] {
            XCTAssertFalse(ac(d).sentence().lowercased().contains("cost"))
        }
    }
}
