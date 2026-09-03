import XCTest
@testable import StrandAnalytics

/// Ola 1 · E4 — el ritmo «Según reps en reserva». Arrays are OLDEST → NEWEST, like `history`.
/// Gate /biomecanico #2 (the at-limit cap), #3 and #4; Helms 2016, Zourdos 2016, Steele 2017.
final class ProgressionRPETests: XCTestCase {
    typealias Past = ProgressionMath.PastSession

    private func input(_ history: [Past], useRPE: Bool = true, sessionsToAdvance: Int = 2,
                       warnOnly: Bool = false, deferRaise: Bool = false)
        -> ProgressionMath.ProgressionInput {
        ProgressionMath.ProgressionInput(history: history, targetReps: 8, targetSets: 4,
                                         sessionsToAdvance: sessionsToAdvance, incrementKg: 2.5,
                                         deloadWarnOnly: warnOnly, deferRaise: deferRaise,
                                         useRPE: useRPE)
    }

    /// Met the goal, rated `rpe` on every work set.
    private func hit(_ kg: Double, _ rpe: Double?) -> Past {
        Past(workingKg: kg, workSetReps: [8, 8, 8, 8], workSetRPE: [Double?](repeating: rpe, count: 4))
    }
    private func miss(_ kg: Double, _ rpe: Double?) -> Past {
        Past(workingKg: kg, workSetReps: [8, 7, 6, 5], workSetRPE: [Double?](repeating: rpe, count: 4))
    }

    // MARK: The rhythm off = the rule that shipped

    /// The whole existing suite, replayed with `useRPE == false` and ratings present: not one verdict
    /// may move. Every pre-existing routine carries `progressionUseRPE == false`.
    func testUseRPEFalseIsByteIdenticalOnExistingSuite() {
        let cases: [([Past], ProgressionState)] = [
            ([hit(100, 10), hit(100, 10)], .readyToAdvance(newKg: 102.5)),
            ([miss(100, 6), hit(100, 6)], .inCycle(done: 1, of: 2)),
            ([hit(100, 6)], .inCycle(done: 1, of: 2)),
            ([miss(100, 10), miss(100, 10), miss(100, 10)], .deloading(fromKg: 100, toKg: 92.5)),
            ([hit(100, 8), hit(102.5, 8)], .inCycle(done: 1, of: 2)),
        ]
        for (history, expected) in cases {
            XCTAssertEqual(ProgressionMath.classify(input(history, useRPE: false)), expected)
            // …and the same history WITHOUT any rating behaves identically with the rhythm ON.
            let unrated = history.map { Past(workingKg: $0.workingKg, workSetReps: $0.workSetReps) }
            XCTAssertEqual(ProgressionMath.classify(input(unrated)), expected)
        }
    }

    // MARK: (a) reps to spare → the raise comes now

    func testComfortableMetRaisesInOneSession() {
        // One session, met at RPE 8 (2 reps in reserve): Helms 2016's «able to complete sets with
        // more than [target] RIR» — the NSCA's 2-for-2, reached in one session instead of two.
        XCTAssertEqual(ProgressionMath.classify(input([hit(100, 8)])), .readyToAdvance(newKg: 102.5))
        // With the rhythm off, the same session is still mid-cycle.
        XCTAssertEqual(ProgressionMath.classify(input([hit(100, 8)], useRPE: false)),
                       .inCycle(done: 1, of: 2))
    }

    /// FER-85 is untouched: the early raise passes through the same verdict gate as any other.
    func testComfortableRaiseStillDeferredByVerdict() {
        XCTAssertEqual(ProgressionMath.classify(input([hit(100, 8)], deferRaise: true)),
                       .deferred(newKg: 102.5))
    }

    /// A non-positive increment can't raise, rhythm or no rhythm (QA D2).
    func testComfortableRaiseNeedsAnIncrement() {
        let i = ProgressionMath.ProgressionInput(history: [hit(100, 7)], targetReps: 8, targetSets: 4,
                                                 incrementKg: 0, useRPE: true)
        XCTAssertEqual(ProgressionMath.classify(i), .inCycle(done: 1, of: 2))
    }

    // MARK: (b) at the limit → invisible to the run, until the cap

    func testAtLimitMetIsInvisibleToMetRun() {
        // Oldest → newest: met at RPE 8, then met AT THE LIMIT. The at-limit session neither adds to
        // the run nor breaks it, and it is not a comfortable newest either → still mid-cycle at 1.
        XCTAssertEqual(ProgressionMath.classify(input([hit(100, 8), hit(100, 10)])),
                       .inCycle(done: 1, of: 2))
    }

    func testThreeAtLimitInARowCountAsStandard() {
        // Gate /biomecanico #2: «al límite» may freeze the raise for a while, never forever.
        XCTAssertEqual(ProgressionMath.classify(input([hit(100, 10), hit(100, 10), hit(100, 10)])),
                       .readyToAdvance(newKg: 102.5))
        // Two in a row are still invisible.
        XCTAssertEqual(ProgressionMath.classify(input([hit(100, 10), hit(100, 10)])),
                       .inCycle(done: 0, of: 2))
    }

    /// The counter the copy reads («N sesiones al límite»).
    func testAtLimitStreakCounts() {
        XCTAssertEqual(ProgressionMath.atLimitStreak(input([hit(100, 10), hit(100, 10)])), 2)
        XCTAssertEqual(ProgressionMath.atLimitStreak(input([hit(100, 10), hit(100, 8)])), 0)
        XCTAssertEqual(ProgressionMath.atLimitStreak(input([hit(100, 10), miss(100, 10)])), 0)
    }

    // MARK: (c) a miss is still a miss

    func testAtLimitMissStillCountsTowardDeload() {
        // Rating 10 on a session that did NOT reach the reps changes nothing: Helms 2016 only reduces
        // intensity when the reps were not completed, and that is exactly this branch.
        XCTAssertEqual(ProgressionMath.classify(input([miss(100, 10), miss(100, 10), miss(100, 10)])),
                       .deloading(fromKg: 100, toKg: 92.5))
        XCTAssertEqual(ProgressionMath.classify(input([miss(100, 10), miss(100, 10)])),
                       .stalled(sessions: 2))
    }

    // MARK: (d) no usable rating → today's behaviour

    func testMissingRPEBehavesLikeToday() {
        // A partially rated session is `.unknown`, never a guess.
        let partial = Past(workingKg: 100, workSetReps: [8, 8, 8, 8], workSetRPE: [8, 8, nil, 8])
        XCTAssertEqual(ProgressionMath.effort(partial), .unknown)
        XCTAssertEqual(ProgressionMath.classify(input([partial])), .inCycle(done: 1, of: 2))
        // …and one whose ratings don't cover the work sets, likewise.
        let short = Past(workingKg: 100, workSetReps: [8, 8, 8, 8], workSetRPE: [8, 8])
        XCTAssertEqual(ProgressionMath.effort(short), .unknown)
        XCTAssertEqual(ProgressionMath.classify(input([short, short])), .readyToAdvance(newKg: 102.5))
    }

    func testEffortBands() {
        XCTAssertEqual(ProgressionMath.effort(hit(100, 8)), .comfortable)
        XCTAssertEqual(ProgressionMath.effort(hit(100, 8.5)), .standard)
        XCTAssertEqual(ProgressionMath.effort(hit(100, 9)), .standard)
        XCTAssertEqual(ProgressionMath.effort(hit(100, 9.5)), .atLimit)
        XCTAssertEqual(ProgressionMath.effort(hit(100, 10)), .atLimit)
        // One set at the limit is enough to call the session at the limit.
        let mixed = Past(workingKg: 100, workSetReps: [8, 8], workSetRPE: [7, 10])
        XCTAssertEqual(ProgressionMath.effort(mixed), .atLimit)
    }

    func testThresholdsAreNamedConstants() {
        XCTAssertEqual(ProgressionMath.rpeComfortableMax, 8.0)
        XCTAssertEqual(ProgressionMath.rpeLimitMin, 9.5)
        XCTAssertEqual(ProgressionMath.atLimitStreakCap, ProgressionMath.deloadStallThreshold)
        XCTAssertEqual(ProgressionMath.atLimitStreakCap, 3)
    }
}
