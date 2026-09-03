import XCTest
import CenitStore
import StrandAnalytics
import StrandTraining
@testable import Cenit

/// Ola 1 · E4 — the app-layer bridge: the per-set effort has to REACH the classifier, and an exercise
/// with the rhythm off has to behave exactly as it did before the rhythm existed.
final class ProgressionPlannerTests: XCTestCase {

    private func row(_ ts: Int, kg: Double, reps: Int, rpe: Double?) -> WorkSetHistoryRow {
        WorkSetHistoryRow(sessionId: "s\(ts)", startTs: ts, weightKg: kg, reps: reps, rpe: rpe)
    }

    private func exercise(useRPE: Bool) -> RoutineExercise {
        RoutineExercise(id: "re", routineId: "rt", exerciseId: "ex", position: 0, targetSets: 2,
                        targetReps: 8, progressionEnabled: true, progressionSessions: 2,
                        progressionIncrementKg: 2.5, progressionUseRPE: useRPE)
    }

    /// `pastSessions` carries the effort alongside the reps — same sets, same order — and only for the
    /// TOP work weight, exactly like the reps it pairs with.
    func testPastSessionsCarryRPE() {
        let rows = [row(100, kg: 100, reps: 8, rpe: 8), row(100, kg: 100, reps: 8, rpe: 9),
                    row(100, kg: 80, reps: 10, rpe: 6)]     // back-off set at a lighter load
        let sessions = ProgressionPlanner.pastSessions(from: rows)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].session.workSetReps, [8, 8])
        XCTAssertEqual(sessions[0].session.workSetRPE.map { $0 ?? -1 }, [8, 9])
        XCTAssertEqual(ProgressionMath.effort(sessions[0].session), .standard)
    }

    /// An unrated set makes the session `.unknown` — never a guess that would move the rule.
    func testPastSessionsKeepMissingRPEAsNil() {
        let rows = [row(100, kg: 100, reps: 8, rpe: 8), row(100, kg: 100, reps: 8, rpe: nil)]
        let session = ProgressionPlanner.pastSessions(from: rows)[0].session
        XCTAssertEqual(session.workSetRPE.count, 2)
        XCTAssertNil(session.workSetRPE[1])
        XCTAssertEqual(ProgressionMath.effort(session), .unknown)
    }

    /// The switch is off in every pre-existing routine: one met session at RPE 8 is still mid-cycle.
    func testEvaluateWithRPEOffIsUnchanged() {
        let history = [row(100, kg: 100, reps: 8, rpe: 8), row(100, kg: 100, reps: 8, rpe: 8)]
        let off = ProgressionPlanner.evaluate(re: exercise(useRPE: false), history: history,
                                              inventory: [], equipment: "barbell", advice: .planAsIs)
        XCTAssertEqual(off?.state, .inCycle(done: 1, of: 2))
        XCTAssertNil(off?.raise)

        // Turned on, the same log earns the raise now (Helms 2016: reps left in reserve).
        let on = ProgressionPlanner.evaluate(re: exercise(useRPE: true), history: history,
                                             inventory: [], equipment: "barbell", advice: .planAsIs)
        XCTAssertEqual(on?.state, .readyToAdvance(newKg: 102.5))
        XCTAssertEqual(on?.raise?.toKg, 102.5)
    }

    /// FER-85 stays on top of the rhythm: «Hoy ve leve» holds the earned raise, one tap away.
    func testEarlyRaiseIsStillHeldByTheVerdict() {
        let history = [row(100, kg: 100, reps: 8, rpe: 8), row(100, kg: 100, reps: 8, rpe: 8)]
        let held = ProgressionPlanner.evaluate(re: exercise(useRPE: true), history: history,
                                               inventory: [], equipment: "barbell", advice: .lighter)
        XCTAssertEqual(held?.state, .deferred(newKg: 102.5))
        XCTAssertEqual(held?.raise?.waiting, true)
    }
}
