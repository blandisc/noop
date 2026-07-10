import XCTest
@testable import StrandAnalytics

/// FER-B — double-progression classifier. Table-driven entrada→salida, mirroring `MetricLevels` tests.
final class ProgressionStateTests: XCTestCase {
    typealias Past = ProgressionMath.PastSession

    /// A 4×8 plan at 2.5 kg steps, default 2 sessions to advance, deload proposed.
    private func input(_ history: [Past], sessionsToAdvance: Int = 2,
                       warnOnly: Bool = false,
                       recovery: TrainingRegulation.Reason? = nil) -> ProgressionMath.ProgressionInput {
        ProgressionMath.ProgressionInput(history: history, targetReps: 8, targetSets: 4,
                                         sessionsToAdvance: sessionsToAdvance, incrementKg: 2.5,
                                         deloadWarnOnly: warnOnly, recoveryReason: recovery)
    }

    private func hit(_ kg: Double) -> Past { Past(workingKg: kg, workSetReps: [8, 8, 8, 8]) }
    private func miss(_ kg: Double) -> Past { Past(workingKg: kg, workSetReps: [8, 7, 6, 5]) }

    func testMeetsGoalTwoSessionsRunning_advances() {
        let s = ProgressionMath.classify(input([hit(100), hit(100)]))
        XCTAssertEqual(s, .readyToAdvance(newKg: 102.5))
    }

    func testOneOfTwoMet_inCycle() {
        let s = ProgressionMath.classify(input([miss(100), hit(100)]))
        XCTAssertEqual(s, .inCycle(done: 1, of: 2))
    }

    func testEmptyHistory_inCycleZero() {
        XCTAssertEqual(ProgressionMath.classify(input([])), .inCycle(done: 0, of: 2))
    }

    func testWeightChangeResetsCycle() {
        // Met once at 100 then jumped to 102.5 and met once: only 1 session at the CURRENT weight.
        let s = ProgressionMath.classify(input([hit(100), hit(102.5)]))
        XCTAssertEqual(s, .inCycle(done: 1, of: 2))
    }

    func testThreeMissesProposeDeload() {
        let s = ProgressionMath.classify(input([miss(100), miss(100), miss(100)]))
        XCTAssertEqual(s, .deloading(fromKg: 100, toKg: 92.5)) // 100·0.925 = 92.5, snapped to 2.5
    }

    func testThreeMissesWarnOnly_stalled() {
        let s = ProgressionMath.classify(input([miss(100), miss(100), miss(100)], warnOnly: true))
        XCTAssertEqual(s, .stalled(sessions: 3))
    }

    func testTwoMisses_stalledBelowThreshold() {
        let s = ProgressionMath.classify(input([miss(100), miss(100)]))
        XCTAssertEqual(s, .stalled(sessions: 2))
    }

    func testRecoveryLowDefersEarnedRaise() {
        let s = ProgressionMath.classify(input([hit(100), hit(100)], recovery: .recoveryLow))
        XCTAssertEqual(s, .deferred(newKg: 102.5), "low recovery holds the raise for next session")
    }

    func testRecoveryHighDoesNotDefer() {
        let s = ProgressionMath.classify(input([hit(100), hit(100)], recovery: .recoveryHigh))
        XCTAssertEqual(s, .readyToAdvance(newKg: 102.5))
    }

    func testOptOutSessionIgnored_progressPreserved() {
        // Met, then a session the user opted out of ("Volver a X"): it must not count as a miss, and the
        // earned raise still stands (two real hits either side of the ignored session).
        let optOut = Past(workingKg: 100, workSetReps: [8, 8, 8, 8], optedOut: true)
        let s = ProgressionMath.classify(input([hit(100), optOut, hit(100)]))
        XCTAssertEqual(s, .readyToAdvance(newKg: 102.5))
    }

    func testDeloadRoundsToIncrement() {
        // 102.5·0.925 = 94.8125 → snaps to 95 on 2.5 kg steps.
        let s = ProgressionMath.classify(input([miss(102.5), miss(102.5), miss(102.5)]))
        XCTAssertEqual(s, .deloading(fromKg: 102.5, toKg: 95))
    }

    func testMissingSetsCountAsNotMet() {
        // Hit target reps but only 3 of 4 work sets logged → goal not met.
        let short = Past(workingKg: 100, workSetReps: [8, 8, 8])
        let s = ProgressionMath.classify(input([hit(100), short]))
        XCTAssertEqual(s, .stalled(sessions: 1))
    }
}
