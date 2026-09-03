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

    /// Ola 1 · E10: tres fallos seguidos en semana ligera avisan el estancamiento sin proponer «bajar a».
    func testLightWeekTurnsTheReactiveDeloadIntoAWarning() {
        let history = [row(100, kg: 100, reps: 6, rpe: nil), row(200, kg: 100, reps: 6, rpe: nil),
                       row(300, kg: 100, reps: 6, rpe: nil)]
        let normal = ProgressionPlanner.evaluate(re: exercise(useRPE: false), history: history,
                                                 inventory: [], equipment: "barbell", advice: .planAsIs)
        guard case .deloading? = normal?.state else { return XCTFail("tres fallos → .deloading en semana normal") }
        let light = ProgressionPlanner.evaluate(re: exercise(useRPE: false), history: history,
                                                inventory: [], equipment: "barbell", advice: .planAsIs,
                                                isLightWeek: true)
        XCTAssertEqual(light?.state, .stalled(sessions: ProgressionMath.deloadStallThreshold))
        XCTAssertNil(light?.raise)
    }

    /// FER-85 stays on top of the rhythm: «Hoy ve leve» holds the earned raise, one tap away.
    func testEarlyRaiseIsStillHeldByTheVerdict() {
        let history = [row(100, kg: 100, reps: 8, rpe: 8), row(100, kg: 100, reps: 8, rpe: 8)]
        let held = ProgressionPlanner.evaluate(re: exercise(useRPE: true), history: history,
                                               inventory: [], equipment: "barbell", advice: .lighter)
        XCTAssertEqual(held?.state, .deferred(newKg: 102.5))
        XCTAssertEqual(held?.raise?.waiting, true)
    }

    // MARK: - RaiseRhythmNote (ola 1 · E5, gate QA FER-331)

    /// RPE 7 en las dos series de trabajo (todas ≤ `rpeComfortableMax`): la sesión cuenta como
    /// cómoda y sube en una sola sesión — la nota lleva `reserveReps = 10 − 7 = 3`.
    func testComfortableRhythmNoteCarriesReserveFromRPE() {
        let history = [row(100, kg: 100, reps: 8, rpe: 7), row(100, kg: 100, reps: 8, rpe: 7)]
        let result = ProgressionPlanner.evaluate(re: exercise(useRPE: true), history: history,
                                                 inventory: [], equipment: "barbell", advice: .planAsIs)
        XCTAssertEqual(result?.state, .readyToAdvance(newKg: 102.5))
        XCTAssertEqual(result?.rhythmNote, .comfortable(reserveReps: 3))
    }

    /// Una sola sesión cumplida AL FALLO (RPE 10 ≥ `rpeLimitMin`): invisible al ciclo (`.inCycle`,
    /// no rompe ni suma), y la nota trae el peso de esa MISMA sesión (`workingKg`) para la píldora
    /// ámbar del hub — gate QA FER-331 O2.
    func testAtLimitHoldWhenNewestSessionMetAtTheLimit() {
        let history = [row(100, kg: 100, reps: 8, rpe: 10), row(100, kg: 100, reps: 8, rpe: 10)]
        let result = ProgressionPlanner.evaluate(re: exercise(useRPE: true), history: history,
                                                 inventory: [], equipment: "barbell", advice: .planAsIs)
        XCTAssertEqual(result?.state, .inCycle(done: 0, of: 2))
        XCTAssertEqual(result?.rhythmNote, .atLimitHold(workingKg: 100))
    }

    /// Tres sesiones seguidas cumplidas al fallo alcanzan el tope (`atLimitStreakCap`): la racha
    /// entera cuenta como estándar y sube de todos modos — la nota es el tope, no lo cómodo.
    func testAtLimitCapAfterThreeSessionsAtTheLimit() {
        let history = (1...3).flatMap { i in
            [row(i * 100, kg: 100, reps: 8, rpe: 10), row(i * 100, kg: 100, reps: 8, rpe: 10)]
        }
        let result = ProgressionPlanner.evaluate(re: exercise(useRPE: true), history: history,
                                                 inventory: [], equipment: "barbell", advice: .planAsIs)
        XCTAssertEqual(result?.state, .readyToAdvance(newKg: 102.5))
        XCTAssertEqual(result?.rhythmNote, .atLimitCap)
    }

    /// La sesión más reciente NO cumplió las reps: sin importar el esfuerzo, no hay nota de ritmo
    /// que decir — `rhythmNote` solo describe sesiones que SÍ llegaron a la meta.
    func testNoRhythmNoteWhenNewestSessionMissedTheGoal() {
        let history = [row(100, kg: 100, reps: 5, rpe: 10), row(100, kg: 100, reps: 5, rpe: 10)]
        let result = ProgressionPlanner.evaluate(re: exercise(useRPE: true), history: history,
                                                 inventory: [], equipment: "barbell", advice: .planAsIs)
        XCTAssertNil(result?.rhythmNote)
    }
}
