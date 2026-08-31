import XCTest
import StrandTraining
import StrandAnalytics
@testable import Cenit

/// Pins the guided strength session logic (FER-347): prefill from «la última vez», register/advance,
/// add/skip set, skip/reorder exercise, and the save build. Pure model — no UI, no DB.
@MainActor
final class StrengthSessionModelTests: XCTestCase {

    private func re(_ id: String, exerciseId: String, sets: Int, reps: Int? = nil,
                    weight: Double? = nil, rest: Int = 90, superset: Int? = nil) -> RoutineExercise {
        RoutineExercise(id: id, routineId: "rt", exerciseId: exerciseId, position: 0,
                        targetSets: sets, targetReps: reps, targetWeightKg: weight,
                        restMode: .fixed, restSeconds: rest, supersetGroup: superset)
    }

    private func ex(_ id: String, _ name: String, type: ExerciseType = .weightReps) -> Exercise {
        Exercise(id: id, name: name, type: type, equipment: nil,
                 primaryMuscles: [], secondaryMuscles: [], instructions: [])
    }

    private func lastSet(_ exId: String, weight: Double, reps: Int) -> SetEntry {
        SetEntry(id: UUID().uuidString, sessionId: "s", exerciseId: exId, position: 0,
                 kind: .work, weightKg: weight, reps: reps, done: true, ts: 1000)
    }

    private func make(_ slots: [StrengthSessionModel.PlanSlot]) -> StrengthSessionModel {
        StrengthSessionModel.make(routineId: "rt", routineName: "Push", slots: slots, startTs: 100)
    }

    // MARK: Prefill

    func testPrefillFromLastTime() {
        let slot = StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 3),
                                                 exercise: ex("bench", "Bench"),
                                                 lastSets: [lastSet("bench", weight: 80, reps: 8)])
        let s = make([slot])
        XCTAssertEqual(s.runs.first?.sets.count, 3, "one row per target set")
        XCTAssertEqual(s.currentSet?.weightKg, 80, "prefilled from last time's weight")
        XCTAssertEqual(s.currentSet?.reps, 8, "prefilled from last time's reps")
        XCTAssertEqual(s.runs.first?.lastWeightKg, 80)
    }

    /// FER-167 ronda 2 (R12): «la última vez» también trae el RPE, para el playhead ANT «· Q» —
    /// GAP cerrado (ronda 1 lo declaró fuera de alcance por tocar el modelo; autorizado aquí).
    func testPrefillSeedsLastRPE() {
        var last = lastSet("bench", weight: 80, reps: 8)
        last.rpe = 8
        let slot = StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 3),
                                                 exercise: ex("bench", "Bench"), lastSets: [last])
        let s = make([slot])
        XCTAssertEqual(s.runs.first?.lastRPE, 8, "seeded from the last session's top set RPE")
    }

    /// Sin RPE capturado la última vez, el playhead se queda sin Q — nunca se inventa.
    func testPrefillLastRPENilWhenNeverCaptured() {
        let slot = StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 3),
                                                 exercise: ex("bench", "Bench"),
                                                 lastSets: [lastSet("bench", weight: 80, reps: 8)])
        let s = make([slot])
        XCTAssertNil(s.runs.first?.lastRPE, "no RPE last time → nil, not a fabricated default")
    }

    func testFirstTimeUsesTargetsThenDefaults() {
        let withTarget = StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "sq", sets: 2, reps: 5, weight: 100),
                                                       exercise: ex("sq", "Squat"), lastSets: [])
        let s = make([withTarget])
        XCTAssertEqual(s.currentSet?.weightKg, 100, "target weight when no history")
        XCTAssertEqual(s.currentSet?.reps, 5)
        XCTAssertNil(s.runs.first?.lastWeightKg, "no «la última vez» first time")

        let bare = StrengthSessionModel.PlanSlot(re: re("b", exerciseId: "ohp", sets: 1),
                                                 exercise: ex("ohp", "Press"), lastSets: [])
        let s2 = make([bare])
        XCTAssertEqual(s2.currentSet?.reps, 8, "default reps when nothing specified")
        XCTAssertEqual(s2.currentSet?.weightKg, 0)
    }

    /// A `RoutineExercise` with an explicit per-set plan (unlike `re`, which synthesizes rows from
    /// target*), needed to exercise `repsRangeTop` seeding (E13/FER-94).
    private func reWithSets(_ id: String, exerciseId: String, sets: [RoutineSet]) -> RoutineExercise {
        RoutineExercise(id: id, routineId: "rt", exerciseId: exerciseId, position: 0,
                        targetSets: sets.count, restMode: .fixed, restSeconds: 90, sets: sets)
    }

    // MARK: Reps range seeding (E13/FER-94)

    /// No «última vez»: the cell seeds at the range's TOP, not the floor.
    func testPrefillSeedsAtRepsRangeTopWhenNoLastTime() {
        let plan = [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 80, repsRangeTop: 12)]
        let slot = StrengthSessionModel.PlanSlot(re: reWithSets("a", exerciseId: "bench", sets: plan),
                                                 exercise: ex("bench", "Bench"), lastSets: [])
        let s = make([slot])
        XCTAssertEqual(s.currentSet?.reps, 12, "seeds at the range top, not the floor")
    }

    /// Regla fantasma (FER-952) con techo: «la última vez» sigue ganando siempre, incluso cuando el
    /// plan trae un rango — el techo solo entra como fallback del plan, nunca por encima de lo hecho.
    func testGhostRuleBeatsRepsRangeTopWhenLastTimeExists() {
        let plan = [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 80, repsRangeTop: 12)]
        let slot = StrengthSessionModel.PlanSlot(re: reWithSets("a", exerciseId: "bench", sets: plan),
                                                 exercise: ex("bench", "Bench"),
                                                 lastSets: [lastSet("bench", weight: 80, reps: 9)])
        let s = make([slot])
        XCTAssertEqual(s.currentSet?.reps, 9, "«la última vez» wins over the range top")
    }

    /// Sin rango (`repsRangeTop == nil`, comportamiento de hoy): idéntico a antes de E13 — regresión.
    func testPrefillWithoutRepsRangeTopUsesFloorAsBefore() {
        let plan = [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 80)]
        let slot = StrengthSessionModel.PlanSlot(re: reWithSets("a", exerciseId: "bench", sets: plan),
                                                 exercise: ex("bench", "Bench"), lastSets: [])
        let s = make([slot])
        XCTAssertEqual(s.currentSet?.reps, 8, "no range = seeds at the floor, regression")
    }

    // MARK: Register + advance + rest

    func testRegisterAdvancesAndStartsRest() {
        let s = make([StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 3, rest: 120),
                                                    exercise: ex("bench", "Bench"), lastSets: [])])
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))
        XCTAssertTrue(s.runs[0].sets[0].done, "first set marked done")
        XCTAssertEqual(s.runs[0].currentSet, 1, "advanced to the second set")
        XCTAssertEqual(s.phase, .resting)
        // Fixed rest of 120s from the routine: the countdown ends ~120s after the register moment.
        XCTAssertEqual(s.restEndsAt?.timeIntervalSince1970 ?? 0, 5000 + 120, accuracy: 0.5)
    }

    // MARK: Per-set rest (FER-715)

    func testRegisterRespectsPerSetRestOverride() {
        // Exercise default = fixed 90s; set 0 overrides to fixed 200s, sets 1-2 inherit.
        // TRES sets a propósito: con dos, registrar el segundo CIERRA la sesión y la regla r9 del dueño
        // («tras el último set del último ejercicio no hay nada que descansar») limpia el descanso, así
        // que la herencia de los 90 s quedaba imposible de observar. La fixture original tenía dos.
        let override = RestConfig(mode: .fixed, seconds: 200)
        let re = RoutineExercise(id: "a", routineId: "rt", exerciseId: "bench", position: 0, targetSets: 3,
                                 restMode: .fixed, restSeconds: 90,
                                 sets: [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 60, rest: override),
                                        RoutineSet(position: 1, kind: .work, reps: 8, weightKg: 60),
                                        RoutineSet(position: 2, kind: .work, reps: 8, weightKg: 60)])
        let s = make([StrengthSessionModel.PlanSlot(re: re, exercise: ex("bench", "Bench"), lastSets: [])])

        // Registering set 0 uses its OWN 200s rest, not the exercise's 90s.
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(s.restEndsAt?.timeIntervalSince1970 ?? 0, 5000 + 200, accuracy: 0.5,
                       "the active set's own rest wins")
        // Registering set 1 (no override) falls back to the exercise's 90s.
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 6000))
        XCTAssertEqual(s.restEndsAt?.timeIntervalSince1970 ?? 0, 6000 + 90, accuracy: 0.5,
                       "a set with no override inherits the exercise rest")
        // Y el ÚLTIMO set no deja descanso colgando: la sesión queda completa (regla r9).
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 7000))
        XCTAssertTrue(s.isComplete, "tres sets registrados = sesión completa")
        XCTAssertNil(s.restEndsAt, "tras el último set del último ejercicio no hay nada que descansar")
    }

    func testUpdateRestExerciseScopeClearsPerSetOverrides() {
        let override = RestConfig(mode: .fixed, seconds: 200)
        let re = RoutineExercise(id: "a", routineId: "rt", exerciseId: "bench", position: 0, targetSets: 2,
                                 restMode: .fixed, restSeconds: 90,
                                 sets: [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 60, rest: override),
                                        RoutineSet(position: 1, kind: .work, reps: 8, weightKg: 60)])
        let s = make([StrengthSessionModel.PlanSlot(re: re, exercise: ex("bench", "Bench"), lastSets: [])])

        // An exercise-scope edit clears the per-set override, so set 0's next rest follows the new default.
        s.updateRest(exercise: 0, mode: .fixed, seconds: 45, reference: .restingMargin, value: 0)
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(s.restEndsAt?.timeIntervalSince1970 ?? 0, 5000 + 45, accuracy: 0.5,
                       "exercise-scope edit overrides the set's old per-set rest")
    }

    func testRegisterCrossesToNextExercise() {
        let s = make([
            StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 1), exercise: ex("bench", "Bench"), lastSets: []),
            StrengthSessionModel.PlanSlot(re: re("b", exerciseId: "row", sets: 1), exercise: ex("row", "Row"), lastSets: [])
        ])
        s.registerCurrentSet()
        XCTAssertEqual(s.currentIndex, 1, "moved to the next exercise once the first finished")
        XCTAssertEqual(s.current?.exerciseId, "row")
    }

    // MARK: Real rest per set (FER-167)

    /// Registering the NEXT set while the previous rest is still counting down closes it right there,
    /// onto the OWNER set (the one that opened it) — not the just-completed one.
    func testRegisterClosesPreviousRestOntoOwnerSet() {
        let s = make([StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 3, rest: 90),
                                                    exercise: ex("bench", "Bench"), lastSets: [])])
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))   // set 0 done, rest opens for set 0
        XCTAssertNil(s.runs[0].sets[0].restTakenS, "not measured yet — the rest is still open")
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5030))   // set 1 done, closes set 0's rest first
        XCTAssertEqual(s.runs[0].sets[0].restTakenS, 30, "set 0's rest measured 30s, onto set 0 (the owner)")
        XCTAssertNil(s.runs[0].sets[1].restTakenS, "set 1's own rest is still open, not yet closed")
    }

    /// Skipping the rest (tap «saltar», and the auto-cierre of a fixed countdown that runs out on its
    /// own, LiveStrengthSheet ~1387) records exactly the elapsed time — the number the user saw.
    func testSkipRestRecordsElapsed() {
        let s = make([StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 2, rest: 90),
                                                    exercise: ex("bench", "Bench"), lastSets: [])])
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))
        s.skipRest(now: Date(timeIntervalSince1970: 5045))
        XCTAssertEqual(s.runs[0].sets[0].restTakenS, 45, "skip early → the short elapsed is what's saved")
        XCTAssertNil(s.restEndsAt)
        XCTAssertEqual(s.phase, .capturing)
    }

    /// The intra-round jump between superset members (A1 → A2, same round) never starts a rest, so the
    /// member that was just finished never gets a measured rest — by construction, not by a special case.
    func testSupersetIntraRoundLeavesNil() {
        let s = supersetSession()
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))   // A1 round 0 → jumps to A2, no rest
        XCTAssertEqual(s.phase, .capturing, "no rest card between A1 and A2")
        XCTAssertNil(s.runs[0].sets[0].restTakenS, "A1's round never had a rest that could be measured")
    }

    /// A pause mid-rest freezes the clock (FER-823): the paused interval must not count as rest. Resume
    /// shifts `restStartedAt` forward by the paused delta, so `closeOpenRest` naturally excludes it.
    func testPauseExcludedFromMeasuredRest() {
        let s = make([StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 2, rest: 90),
                                                    exercise: ex("bench", "Bench"), lastSets: [])])
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))   // rest opens at 5000
        s.pause(now: Date(timeIntervalSince1970: 5010))                // 10s in
        s.resume(now: Date(timeIntervalSince1970: 5070))               // 60s paused
        s.skipRest(now: Date(timeIntervalSince1970: 5100))
        // Wall clock 5000→5100 = 100s, minus the 60s paused = 40s measured.
        XCTAssertEqual(s.runs[0].sets[0].restTakenS, 40, "the paused interval is excluded from the measurement")
    }

    /// FER-167 ronda 2 (R15): an OPEN pause (never resumed) at the moment the rest closes must clamp
    /// to `pausedAt`, not the real wall-clock — the saved number is what the user saw frozen. Distinct
    /// from `testPauseExcludedFromMeasuredRest`, which covers a pause already CLOSED by `resume()`.
    func testCloseOpenRestClampsToOpenPause() {
        let s = make([StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 2, rest: 90),
                                                    exercise: ex("bench", "Bench"), lastSets: [])])
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))   // rest opens at 5000
        s.pause(now: Date(timeIntervalSince1970: 5010))                // frozen 10s in — never resumed
        s.skipRest(now: Date(timeIntervalSince1970: 5200))             // real wall-clock is 200s later
        XCTAssertEqual(s.runs[0].sets[0].restTakenS, 10,
                       "clamped to pausedAt (10s), not the 200s wall-clock gap")
    }

    /// Ending the session while a rest is still open (the last-tapped set's rest never got skipped or
    /// closed by another register) must NOT retroactively record it — `buildForSave` only persists what
    /// `closeOpenRest` already wrote, and an open rest at save time wrote nothing.
    func testSessionEndDiscardsOpenRest() {
        let s = make([
            StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 1), exercise: ex("bench", "Bench"), lastSets: []),
            StrengthSessionModel.PlanSlot(re: re("b", exerciseId: "row", sets: 1), exercise: ex("row", "Row"), lastSets: [])
        ])
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))   // bench done, its rest is open
        XCTAssertEqual(s.phase, .resting, "a rest is genuinely open — row is still pending")
        let (_, sets, _, _) = s.buildForSave(deviceId: nil, endTs: 9000)
        XCTAssertEqual(sets.first { $0.exerciseId == "bench" }?.restTakenS, nil,
                       "an open, never-closed rest is discarded — not retroactively recorded at save")
    }

    // MARK: Add / skip set

    func testAddSet() {
        let s = make([StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 2, weight: 60),
                                                    exercise: ex("bench", "Bench"), lastSets: [])])
        s.addSet()
        XCTAssertEqual(s.runs[0].sets.count, 3, "a set was appended")
        XCTAssertEqual(s.runs[0].currentSet, 2, "focus moved to the new set")
        XCTAssertEqual(s.currentSet?.weightKg, 60, "copies the previous load")
    }

    func testSkipSetDropsPendingRow() {
        let s = make([StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 3),
                                                    exercise: ex("bench", "Bench"), lastSets: [])])
        s.skipCurrentSet()
        XCTAssertEqual(s.runs[0].sets.count, 2, "a pending set was dropped")
    }

    func testSkipDoesNotDropDoneSet() {
        let s = make([StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 2),
                                                    exercise: ex("bench", "Bench"), lastSets: [])])
        s.registerCurrentSet()          // set 0 done, focus on set 1
        s.select(exerciseIndex: 0, setIndex: 0)
        s.skipCurrentSet()              // try to skip the done one
        XCTAssertEqual(s.runs[0].sets.count, 2, "a done set is never dropped by skip")
    }

    // MARK: Exercise navigator

    func testSkipExerciseAdvancesOffIt() {
        let s = make([
            StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 1), exercise: ex("bench", "Bench"), lastSets: []),
            StrengthSessionModel.PlanSlot(re: re("b", exerciseId: "row", sets: 1), exercise: ex("row", "Row"), lastSets: [])
        ])
        s.skipExercise(0)
        XCTAssertTrue(s.runs[0].skipped)
        XCTAssertEqual(s.currentIndex, 1, "focus moved off the skipped exercise")
        XCTAssertEqual(s.activeExercises.count, 1, "skipped exercise dropped from the navigator")
    }

    func testSkippingLastActiveExerciseNeverLeavesFocusOnSkipped() {
        // D2: skip the only/last active exercise mid-session — focus must not rest on a skipped run.
        let s = make([
            StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 2), exercise: ex("bench", "Bench"), lastSets: [])
        ])
        s.skipExercise(0)
        XCTAssertNil(s.current, "no active exercise left → current is nil (a «complete» state), not a skipped run")
        XCTAssertTrue(s.isComplete, "nothing pending once the last exercise is skipped")
    }

    func testMoveExerciseEarlierKeepsFocus() {
        let s = make([
            StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 1), exercise: ex("bench", "Bench"), lastSets: []),
            StrengthSessionModel.PlanSlot(re: re("b", exerciseId: "row", sets: 1), exercise: ex("row", "Row"), lastSets: [])
        ])
        s.goToExercise(1)               // focus the second
        s.moveExerciseEarlier(1)        // move it up
        XCTAssertEqual(s.runs[0].exerciseId, "row", "row is now first")
        XCTAssertEqual(s.current?.exerciseId, "row", "focus stayed on the moved exercise")
    }

    // MARK: Save build

    func testBuildForSaveKeepsOnlyDoneWorkSets() {
        let s = make([
            StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 2, reps: 8, weight: 80), exercise: ex("bench", "Bench"), lastSets: []),
            StrengthSessionModel.PlanSlot(re: re("b", exerciseId: "row", sets: 1), exercise: ex("row", "Row"), lastSets: [])
        ])
        s.registerCurrentSet()          // bench set 0 done
        // leave the rest pending
        let (record, sets, _, _) = s.buildForSave(deviceId: "strap", endTs: 9000)
        XCTAssertEqual(record.id, s.id)
        XCTAssertEqual(record.routineId, "rt")
        XCTAssertEqual(record.endTs, 9000)
        XCTAssertEqual(sets.count, 1, "only the one logged set is saved")
        XCTAssertEqual(sets.first?.exerciseId, "bench")
        XCTAssertEqual(sets.first?.weightKg, 80)
        XCTAssertTrue(sets.first?.done ?? false)
    }

    func testSkippedExerciseExcludedFromSave() {
        let s = make([
            StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 1, reps: 8, weight: 80), exercise: ex("bench", "Bench"), lastSets: [])
        ])
        s.registerCurrentSet()
        s.skipExercise(0)
        let (_, sets, _, _) = s.buildForSave(deviceId: nil, endTs: 9000)
        XCTAssertTrue(sets.isEmpty, "a skipped exercise's sets don't persist")
    }

    // MARK: Foco variants by exercise type (FER-351)

    private func slot(_ exId: String, type: ExerciseType, sets: Int = 1, reps: Int? = nil) -> StrengthSessionModel.PlanSlot {
        StrengthSessionModel.PlanSlot(re: re("re-\(exId)", exerciseId: exId, sets: sets, reps: reps),
                                      exercise: ex(exId, exId.capitalized, type: type), lastSets: [])
    }

    func testWeightRepsPersistsOnlyWeightAndReps() {
        let s = make([StrengthSessionModel.PlanSlot(
            re: re("a", exerciseId: "bench", sets: 1, reps: 8, weight: 80),
            exercise: ex("bench", "Bench"), lastSets: [])])
        s.registerCurrentSet()
        let set = s.buildForSave(deviceId: nil, endTs: 1).1.first
        XCTAssertEqual(set?.weightKg, 80)
        XCTAssertEqual(set?.reps, 8)
        XCTAssertNil(set?.timeS)
        XCTAssertNil(set?.distanceM)
    }

    func testBodyweightPersistsRepsAndOptionalLastre() {
        let s = make([slot("pull", type: .bodyweight, reps: 8)])
        XCTAssertEqual(s.currentSet?.reps, 8, "reps seed the bodyweight set")
        s.bumpWeight(byKg: 10)                      // add lastre
        s.registerCurrentSet()
        let set = s.buildForSave(deviceId: nil, endTs: 1).1.first
        XCTAssertEqual(set?.reps, 8)
        XCTAssertEqual(set?.weightKg, 10, "the optional lastre persists")
        XCTAssertNil(set?.timeS)
    }

    func testBodyweightWithoutLastrePersistsNoWeight() {
        let s = make([slot("push", type: .bodyweight, reps: 12)])
        s.registerCurrentSet()
        let set = s.buildForSave(deviceId: nil, endTs: 1).1.first
        XCTAssertEqual(set?.reps, 12)
        XCTAssertNil(set?.weightKg, "bodyweight only → no weight stored")
    }

    func testTimeSetRegistersElapsedAndNoReps() {
        let s = make([slot("plank", type: .time)])
        XCTAssertEqual(s.currentSet?.reps, 0, "time sets carry no reps")
        s.startSetTimer(now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(s.timerElapsed(now: Date(timeIntervalSince1970: 1042)), 42)
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 1042))   // register = stop & save
        XCTAssertNil(s.timerStart, "the stopwatch is cleared after register")
        let set = s.buildForSave(deviceId: nil, endTs: 1).1.first
        XCTAssertEqual(set?.timeS, 42)
        XCTAssertNil(set?.reps, "a time set persists no reps")
        XCTAssertNil(set?.weightKg)
    }

    func testStopTimerAccumulates() {
        let s = make([slot("plank", type: .time)])
        s.startSetTimer(now: Date(timeIntervalSince1970: 0))
        s.stopSetTimer(now: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(s.runs[0].sets[0].timeS, 20)
        s.startSetTimer(now: Date(timeIntervalSince1970: 100))
        s.stopSetTimer(now: Date(timeIntervalSince1970: 110))
        XCTAssertEqual(s.runs[0].sets[0].timeS, 30, "a second run accumulates onto the prior elapsed")
    }

    func testDistanceSetPersistsDistanceAndTime() {
        let s = make([slot("run", type: .distance)])
        s.bumpDistance(byMeters: 2400)
        s.startSetTimer(now: Date(timeIntervalSince1970: 0))
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 750))   // 12:30
        let set = s.buildForSave(deviceId: nil, endTs: 1).1.first
        XCTAssertEqual(set?.distanceM, 2400)
        XCTAssertEqual(set?.timeS, 750)
        XCTAssertNil(set?.reps, "a distance set persists no reps")
    }

    func testTimerResetsWhenSelectingAnotherSet() {
        let s = make([slot("plank", type: .time, sets: 2)])
        s.startSetTimer(now: Date(timeIntervalSince1970: 0))
        s.select(exerciseIndex: 0, setIndex: 1)
        XCTAssertNil(s.timerStart, "switching sets cancels a running stopwatch")
    }

    // MARK: Inline-table edits (the Hevy-style logging surface, FER-497)

    private func twoExercises() -> StrengthSessionModel {
        make([slot("bench", type: .weightReps, sets: 2),
              slot("row", type: .weightReps, sets: 2)])
    }

    func testToggleDoneIsAToggleAndStartsNoRest() {
        let s = twoExercises()
        XCTAssertFalse(s.runs[0].sets[0].done)
        s.toggleDone(exercise: 0, set: 0, now: Date(timeIntervalSince1970: 5))
        XCTAssertTrue(s.runs[0].sets[0].done, "the ✓ marks the set done")
        XCTAssertEqual(s.runs[0].sets[0].doneTs, 5, "stamps when it was done")
        XCTAssertNil(s.restEndsAt, "the inline ✓ never starts a rest (that's the Foco's job)")
        XCTAssertEqual(s.phase, .capturing)
        s.toggleDone(exercise: 0, set: 0)
        XCTAssertFalse(s.runs[0].sets[0].done, "tapping again un-marks it")
        XCTAssertNil(s.runs[0].sets[0].doneTs, "and clears the timestamp")
    }

    func testInlineEditsAnyRowOfAnyExercise() {
        let s = twoExercises()
        s.setWeight(exercise: 1, set: 1, kg: 72.5)
        s.setReps(exercise: 1, set: 1, reps: 9)
        XCTAssertEqual(s.runs[1].sets[1].weightKg, 72.5)
        XCTAssertEqual(s.runs[1].sets[1].reps, 9)
        XCTAssertEqual(s.currentIndex, 0, "editing a cell does not move focus by itself")
    }

    func testInlineEditsClampAtZero() {
        let s = twoExercises()
        s.setWeight(exercise: 0, set: 0, kg: -5)
        s.setReps(exercise: 0, set: 0, reps: -3)
        XCTAssertEqual(s.runs[0].sets[0].weightKg, 0)
        XCTAssertEqual(s.runs[0].sets[0].reps, 0)
    }

    func testAddSetForSpecificExerciseCopiesLastLoad() {
        let s = twoExercises()
        s.setWeight(exercise: 1, set: 1, kg: 60)
        s.setReps(exercise: 1, set: 1, reps: 12)
        s.addSet(exercise: 1)
        XCTAssertEqual(s.runs[1].sets.count, 3, "appends to the right exercise")
        XCTAssertEqual(s.runs[1].sets.last?.weightKg, 60, "copies the last row's load")
        XCTAssertEqual(s.runs[1].sets.last?.reps, 12)
        XCTAssertFalse(s.runs[1].sets.last?.done ?? true, "the new set starts pending")
        XCTAssertEqual(s.runs[0].sets.count, 2, "other exercises are untouched")
    }

    func testRemoveSetReclampsCurrent() {
        let s = make([slot("bench", type: .weightReps, sets: 3)])
        s.select(exerciseIndex: 0, setIndex: 2)
        s.removeSet(exercise: 0, set: 2)
        XCTAssertEqual(s.runs[0].sets.count, 2)
        XCTAssertEqual(s.runs[0].currentSet, 1, "currentSet reclamps inside the new bounds")
    }

    func testPrefillPreviousCopiesLastTimeIntoARow() {
        let slot = StrengthSessionModel.PlanSlot(
            re: re("a", exerciseId: "bench", sets: 2),
            exercise: ex("bench", "Bench"),
            lastSets: [lastSet("bench", weight: 85, reps: 5)])
        let s = make([slot])
        s.setWeight(exercise: 0, set: 1, kg: 0)
        s.setReps(exercise: 0, set: 1, reps: 0)
        s.prefillPrevious(exercise: 0, set: 1)
        XCTAssertEqual(s.runs[0].sets[1].weightKg, 85, "tap-PREVIOUS copies last time's weight")
        XCTAssertEqual(s.runs[0].sets[1].reps, 5, "and reps")
    }

    func testLastTimeAndDistanceFlowIntoTheRun() {
        let prev = SetEntry(id: "p", sessionId: "s", exerciseId: "run", position: 0, kind: .work,
                            timeS: 750, distanceM: 2400, done: true, ts: 1000)
        let slot = StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "run", sets: 1),
                                                 exercise: ex("run", "Run", type: .distance),
                                                 lastSets: [prev])
        let s = make([slot])
        XCTAssertEqual(s.runs[0].lastTimeS, 750, "last time's seconds are kept for the PREVIOUS cell")
        XCTAssertEqual(s.runs[0].lastDistanceM, 2400)
    }

    // MARK: Ad-hoc «Rápido de fuerza» (FER-762) — adding exercises mid-session with no routine

    private func emptyAdHoc() -> StrengthSessionModel {
        StrengthSessionModel(routineId: nil, routineName: "Quick strength", startTs: 100, runs: [])
    }

    func testAddExerciseWithHistorySeedsLastWeightAndReps() {
        let s = emptyAdHoc()
        s.addExercise(ex("bench", "Bench"), lastWeightKg: 80, lastReps: 8)
        XCTAssertEqual(s.runs.count, 1)
        XCTAssertEqual(s.runs[0].sets.count, 1, "one starter set")
        XCTAssertEqual(s.runs[0].sets[0].weightKg, 80, "seeded from last time's weight")
        XCTAssertEqual(s.runs[0].sets[0].reps, 8)
        XCTAssertEqual(s.runs[0].lastWeightKg, 80, "kept for the PREVIOUS cell")
        XCTAssertEqual(s.runs[0].restSeconds, StrengthSessionModel.adHocRestSeconds, "2-minute default rest")
        XCTAssertEqual(s.runs[0].restMode, .fixed, "fixed countdown — no HR baseline to anchor to")
    }

    func testAddExerciseWithNoHistoryUsesStarterDefaults() {
        let s = emptyAdHoc()
        s.addExercise(ex("squat", "Squat"))
        XCTAssertEqual(s.runs[0].sets[0].weightKg, 0)
        XCTAssertEqual(s.runs[0].sets[0].reps, 8, "default reps when there's no history")
        XCTAssertNil(s.runs[0].lastWeightKg, "no «la última vez» first time")
    }

    func testAddExerciseOnBodyweightTypeSeedsRepsNotWeight() {
        let s = emptyAdHoc()
        s.addExercise(ex("pushup", "Push-up", type: .bodyweight), lastWeightKg: 5, lastReps: 12)
        XCTAssertEqual(s.runs[0].sets[0].reps, 12)
        XCTAssertEqual(s.runs[0].sets[0].weightKg, 5, "optional lastre carried through")
    }

    func testAddExerciseOnTimeTypeSeedsNoReps() {
        let s = emptyAdHoc()
        s.addExercise(ex("plank", "Plank", type: .time))
        XCTAssertEqual(s.runs[0].sets[0].reps, 0, "time-based sets don't seed reps")
    }

    func testAddingSecondExerciseFocusesItAndKeepsTheFirst() {
        let s = emptyAdHoc()
        s.addExercise(ex("bench", "Bench"))
        s.addExercise(ex("row", "Row"))
        XCTAssertEqual(s.runs.count, 2)
        XCTAssertEqual(s.currentIndex, 1, "focus moves to the just-added exercise")
        XCTAssertEqual(s.runs[0].exerciseId, "bench", "the first exercise is untouched")
    }

    // MARK: Pause / resume (FER-823)

    private func oneSlot() -> StrengthSessionModel {
        make([StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 3),
                                            exercise: ex("bench", "Bench"), lastSets: [])])
    }

    /// FER-930: RPE is written by its own setter, independent of marking a set, and is optional:
    /// registering a set never fills it (it stays nil until the user picks a value).
    func testSetRPEWritesAndClears() {
        let s = oneSlot()
        let run = s.runs[0].id
        let set = s.runs[0].sets[0].id
        s.setRPE(exercise: run, set: set, rpe: 8)
        XCTAssertEqual(s.runs[0].sets[0].rpe, 8, "RPE written to the set")
        s.setRPE(exercise: run, set: set, rpe: nil)
        XCTAssertNil(s.runs[0].sets[0].rpe, "RPE cleared")
    }

    func testMarkingSetLeavesRPENil() {
        let s = oneSlot()
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))
        XCTAssertTrue(s.runs[0].sets[0].done)
        XCTAssertNil(s.runs[0].sets[0].rpe, "marking a set never fills RPE; it stays optional")
    }

    // MARK: Exercise note (FER-932)

    /// The exercise-scope note is written by its own setter, independent of the set table, and the
    /// «con nota» chip state (`hasNote`) reflects it.
    func testSetExerciseNoteWritesAndReflectsInHasNote() {
        let s = oneSlot()
        let run = s.runs[0].id
        XCTAssertFalse(s.runs[0].hasNote, "no note yet")
        s.setExerciseNote(exercise: run, text: "Buena técnica hoy")
        XCTAssertEqual(s.runs[0].note, "Buena técnica hoy")
        XCTAssertTrue(s.runs[0].hasNote, "chip reflects the exercise-scope note")
        s.setExerciseNote(exercise: run, text: nil)
        XCTAssertFalse(s.runs[0].hasNote, "cleared note drops the chip state")
    }

    /// A set-scope note («Guardar en: Solo la serie N») also flips `hasNote` on the run, even with no
    /// exercise-scope note set.
    func testSetSetNoteReflectsInRunHasNote() {
        let s = oneSlot()
        let run = s.runs[0].id
        let set = s.runs[0].sets[1].id
        s.setSetNote(exercise: run, set: set, text: "Falló al final de esta serie")
        XCTAssertEqual(s.runs[0].sets[1].note, "Falló al final de esta serie")
        XCTAssertTrue(s.runs[0].hasNote, "a set-scope note also marks the exercise as having a note")
    }

    /// `buildForSave` assembles `ExerciseNote` rows for both scopes, skipping empty text, and never
    /// requires the set to be `done` (a note can be written on a set not yet logged).
    func testBuildForSaveAssemblesNotesBothScopes() {
        let s = oneSlot()
        let run = s.runs[0].id
        s.setExerciseNote(exercise: run, text: "Nota del ejercicio")
        s.setSetNote(exercise: run, set: s.runs[0].sets[0].id, text: "Nota de la serie 1")
        let (_, _, _, notes) = s.buildForSave(deviceId: nil, endTs: 9000)
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.contains { $0.setPosition == nil && $0.text == "Nota del ejercicio" })
        XCTAssertTrue(notes.contains { $0.setPosition == 0 && $0.text == "Nota de la serie 1" })
    }

    // MARK: Fixed exercise note seed (FER-166)

    /// `make` seeds the run's live `note` AND `seededNote` from the routine's fixed note; an untouched
    /// seed never becomes an `ExerciseNote` row in the acta (only a note the user actually typed/edited
    /// this session does) — and the invariant survives a crash→restore.
    func testMakeSeedsNoteFromRoutineAndBuildForSaveSkipsSeed() {
        let seeded = StrengthSessionModel.PlanSlot(
            re: RoutineExercise(id: "a", routineId: "rt", exerciseId: "bench", position: 0,
                                targetSets: 1, restMode: .fixed, restSeconds: 90,
                                note: "Cadera atrás, no rodillas"),
            exercise: ex("bench", "Bench"), lastSets: [])
        let s = make([seeded])

        // The seed rides both the live note and the memory of what was seeded.
        XCTAssertEqual(s.runs[0].note, "Cadera atrás, no rodillas")
        XCTAssertEqual(s.runs[0].seededNote, "Cadera atrás, no rodillas")
        XCTAssertTrue(s.runs[0].hasNote, "the seeded note lights the chip")

        s.registerCurrentSet()   // log something so buildForSave has a session worth saving
        let (_, _, _, untouchedNotes) = s.buildForSave(deviceId: nil, endTs: 9000)
        XCTAssertTrue(untouchedNotes.isEmpty, "an intact seed must NOT be copied to the session's acta")

        // The user edits the note THIS session — now it must be saved as history.
        let run = s.runs[0].id
        s.setExerciseNote(exercise: run, text: "Bajar más despacio")
        let (_, _, _, editedNotes) = s.buildForSave(deviceId: nil, endTs: 9000)
        XCTAssertEqual(editedNotes.count, 1, "an edited note IS copied to the acta")
        XCTAssertEqual(editedNotes.first?.text, "Bajar más despacio")

        // Crash-safe: snapshot → restore keeps the invariant — the seed's memory isn't lost.
        let restored = StrengthSessionModel.restore(from: s.snapshot(now: 200))
        XCTAssertEqual(restored.runs[0].seededNote, "Cadera atrás, no rodillas")
        let (_, _, _, restoredNotes) = restored.buildForSave(deviceId: nil, endTs: 9000)
        XCTAssertEqual(restoredNotes.count, 1, "restore keeps the edited-vs-seed distinction")
    }

    func testElapsedFreezesWhilePaused() {
        let s = oneSlot()   // startTs = 100
        XCTAssertEqual(s.elapsedSeconds(now: Date(timeIntervalSince1970: 200)), 100)
        s.pause(now: Date(timeIntervalSince1970: 200))
        XCTAssertTrue(s.paused)
        // Time keeps passing, but active elapsed stays put.
        XCTAssertEqual(s.elapsedSeconds(now: Date(timeIntervalSince1970: 260)), 100, "clock frozen while paused")
        XCTAssertEqual(s.elapsedSeconds(now: Date(timeIntervalSince1970: 500)), 100)
    }

    func testResumeExcludesPausedTimeFromElapsed() {
        let s = oneSlot()
        s.pause(now: Date(timeIntervalSince1970: 200))
        s.resume(now: Date(timeIntervalSince1970: 260))   // 60 s paused
        XCTAssertFalse(s.paused)
        XCTAssertEqual(s.pausedSeconds(at: Date(timeIntervalSince1970: 300)), 60)
        XCTAssertEqual(s.elapsedSeconds(now: Date(timeIntervalSince1970: 300)), 140, "300-100-60")
    }

    func testResumeShiftsRestAndStopwatchByPausedDelta() {
        let s = oneSlot()
        s.restStartedAt = Date(timeIntervalSince1970: 190)
        s.restEndsAt = Date(timeIntervalSince1970: 280)
        s.timerStart = Date(timeIntervalSince1970: 195)
        s.pause(now: Date(timeIntervalSince1970: 200))
        s.resume(now: Date(timeIntervalSince1970: 260))   // delta 60
        XCTAssertEqual(s.restEndsAt, Date(timeIntervalSince1970: 340), "remaining rest preserved")
        XCTAssertEqual(s.restStartedAt, Date(timeIntervalSince1970: 250))
        XCTAssertEqual(s.timerStart, Date(timeIntervalSince1970: 255))
    }

    func testPauseAndResumeAreIdempotent() {
        let s = oneSlot()
        s.pause(now: Date(timeIntervalSince1970: 200))
        s.pause(now: Date(timeIntervalSince1970: 220))   // second pause is a no-op
        s.resume(now: Date(timeIntervalSince1970: 260))
        XCTAssertEqual(s.pausedSeconds(at: Date(timeIntervalSince1970: 300)), 60, "only the first pause counts")
        s.resume(now: Date(timeIntervalSince1970: 300))  // resume when not paused is a no-op
        XCTAssertEqual(s.pausedSeconds(at: Date(timeIntervalSince1970: 300)), 60)
    }

    func testCannotPauseOnceReceiptShown() {
        let s = oneSlot()
        s.summary = StrengthSummary(routineName: "Push", endTs: 0, durationS: 0, volumeKg: 0,
                                    setCount: 0, prs: [], muscles: [], isFirstTime: false, exercises: [])
        s.pause()
        XCTAssertFalse(s.paused, "a finished session (receipt up) can't be paused")
    }

    func testAccumulatesAcrossMultiplePauses() {
        let s = oneSlot()
        s.pause(now: Date(timeIntervalSince1970: 200)); s.resume(now: Date(timeIntervalSince1970: 230))  // 30
        s.pause(now: Date(timeIntervalSince1970: 300)); s.resume(now: Date(timeIntervalSince1970: 320))  // 20
        XCTAssertEqual(s.pausedSeconds(at: Date(timeIntervalSince1970: 400)), 50)
        XCTAssertEqual(s.elapsedSeconds(now: Date(timeIntervalSince1970: 400)), 250, "400-100-50")
    }

    // MARK: Superset auto-advance (FER-931)

    /// Two exercises in the same routine superset (2 work sets each), plus a standalone third exercise —
    /// the fixture every FER-931 test below builds on.
    private func supersetSession(rounds: Int = 2) -> StrengthSessionModel {
        make([
            StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: rounds, superset: 1),
                                          exercise: ex("bench", "Bench"), lastSets: []),
            StrengthSessionModel.PlanSlot(re: re("b", exerciseId: "row", sets: rounds, superset: 1),
                                          exercise: ex("row", "Row"), lastSets: []),
            StrengthSessionModel.PlanSlot(re: re("c", exerciseId: "curl", sets: 1),
                                          exercise: ex("curl", "Curl"), lastSets: [])
        ])
    }

    func testMakeCopiesSupersetGroupFromRoutine() {
        let s = supersetSession()
        XCTAssertEqual(s.runs[0].supersetGroup, 1, "A1 carries the routine's group")
        XCTAssertEqual(s.runs[1].supersetGroup, 1, "A2 carries the same group")
        XCTAssertNil(s.runs[2].supersetGroup, "the standalone exercise is ungrouped")
    }

    /// Finishing A1's round moves straight to A2's SAME round with no rest: `phase == .capturing`,
    /// `restEndsAt == nil`, and focus lands on the second member (the design's central invariant).
    func testSupersetAdvancesToNextMemberWithoutRest() {
        let s = supersetSession()
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))   // A1, round 0
        XCTAssertTrue(s.runs[0].sets[0].done)
        XCTAssertEqual(s.currentIndex, 1, "focus jumped straight to A2")
        XCTAssertEqual(s.runs[1].currentSet, 0, "same round (0) on A2")
        XCTAssertEqual(s.phase, .capturing, "no rest card between A1 and A2")
        XCTAssertNil(s.restEndsAt, "no countdown started between group members")
    }

    /// Finishing the group's LAST member's round starts rest as normal, and the focus that
    /// `advanceToNextPending` already parked (rest runs concurrently, not blocking) is the FIRST
    /// member's next round — not a continuation of the last member.
    func testSupersetRestsAfterLastMemberAndReturnsToFirstForNextRound() {
        let s = supersetSession()
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))   // A1 round 0 → jumps to A2 round 0
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5010))   // A2 round 0 → group's round done
        XCTAssertTrue(s.runs[1].sets[0].done)
        XCTAssertEqual(s.phase, .resting, "rest after the group's last member")
        XCTAssertNotNil(s.restEndsAt)
        XCTAssertEqual(s.currentIndex, 0, "focus returned to A1 (the group's first member)")
        XCTAssertEqual(s.runs[0].currentSet, 1, "for the NEXT round (1), not stuck on round 0")
    }

    /// Once every round of every member is done, the group has nothing left — focus moves on to the
    /// next exercise in the plan (the standalone one), same as a normal exercise-to-exercise crossing.
    func testSupersetCompleteMovesToNextExercise() {
        let s = supersetSession(rounds: 1)
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))   // A1 round 0 → A2 round 0
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5010))   // A2 round 0 → group complete
        XCTAssertEqual(s.currentIndex, 2, "moved past the finished superset to the standalone exercise")
        XCTAssertEqual(s.current?.exerciseId, "curl")
    }

    /// A skipped group member must not steal focus: registering A1 when A2 is skipped falls back to a
    /// normal rest (A2's sets are never `.done`, so without the `!skipped` guard the round-robin would
    /// park focus on a skipped exercise). FER-931 D1.
    func testSupersetSkippedMemberDoesNotStealFocus() {
        let s = supersetSession()
        s.runs[1].skipped = true   // A2 skipped mid-session
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))   // A1 round 0
        XCTAssertTrue(s.runs[0].sets[0].done)
        XCTAssertNotEqual(s.currentIndex, 1, "focus must not jump to a skipped superset member")
        XCTAssertEqual(s.phase, .resting, "a skipped next member falls back to a normal rest")
        XCTAssertNotNil(s.restEndsAt)
    }

    /// The superset logic must not perturb a plain, ungrouped exercise's register/rest/advance path —
    /// byte-for-byte the pre-931 behavior (mirrors `testRegisterAdvancesAndStartsRest`), even sharing a
    /// session with a superset elsewhere in the plan.
    func testStandaloneExerciseAdvanceIsUnaffectedBySupersetElsewhere() {
        let s = supersetSession(rounds: 1)
        s.goToExercise(2)   // focus the standalone "curl" exercise directly
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))
        XCTAssertTrue(s.runs[2].sets[0].done)
        XCTAssertEqual(s.phase, .resting, "a standalone exercise still rests normally")
        XCTAssertNotNil(s.restEndsAt)
    }

    // MARK: - closedSupersetRounds (FER-170 · F5, ronda 2 del gate · R7)
    //
    // El núcleo de «HECHO en Foco solo al cerrar ronda» (`HojaSesionViva.registerFromFoco`, D3):
    // cuenta rondas CERRADAS (todos los miembros con esa ronda `.done`) desde el inicio, se detiene
    // en la primera abierta, y no deja que un miembro con MENOS series bloquee el conteo de otro con
    // más — pura, sin motor de round-robin de por medio (se muta `.done` directo, como el resto de
    // este archivo).

    /// Cero cuando nadie ha registrado nada — nunca inventa una ronda cerrada de la nada.
    func testClosedSupersetRoundsZeroWhenNothingDone() {
        let s = supersetSession(rounds: 2)
        let members = s.supersetMembers(at: 0)
        XCTAssertEqual(s.closedSupersetRounds(members: members), 0)
    }

    /// Cuenta ronda a ronda: cerrar SOLO la ronda 0 de los dos miembros cuenta 1; cerrar también la
    /// ronda 1 cuenta 2 — nunca antes de que el miembro faltante también la marque.
    func testClosedSupersetRoundsCountsRoundByRound() {
        let s = supersetSession(rounds: 2)
        let members = s.supersetMembers(at: 0)
        s.runs[0].sets[0].done = true; s.runs[1].sets[0].done = true   // ronda 0: A y B
        XCTAssertEqual(s.closedSupersetRounds(members: members), 1)
        s.runs[0].sets[1].done = true; s.runs[1].sets[1].done = true   // ronda 1: A y B
        XCTAssertEqual(s.closedSupersetRounds(members: members), 2)
    }

    /// Se DETIENE en la primera ronda abierta: A cerró su ronda 0, pero B todavía no la suya — la
    /// ronda 0 del BLOQUE sigue abierta, así que el conteo es 0, aunque A ya tenga su parte hecha.
    func testClosedSupersetRoundsStopsAtFirstOpenRound() {
        let s = supersetSession(rounds: 2)
        let members = s.supersetMembers(at: 0)
        s.runs[0].sets[0].done = true   // solo A cerró su ronda 0 — B sigue pendiente
        XCTAssertEqual(s.closedSupersetRounds(members: members), 0)
    }

    /// Tolera miembros con distinto número de series (rampa heredada de antes de agrupar, N3): A con
    /// 3 rondas, B con solo 2 — cerradas las dos que B SÍ tiene y la 3.ª (solo de A), el conteo llega
    /// a 3 sin que la falta de una 3.ª fila en B lo bloquee (B «no aporta fila en esa ronda» — no
    /// cuenta como abierta).
    func testClosedSupersetRoundsToleratesUnevenMemberCounts() {
        let s = make([
            StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 3, superset: 1),
                                          exercise: ex("bench", "Bench"), lastSets: []),
            StrengthSessionModel.PlanSlot(re: re("b", exerciseId: "row", sets: 2, superset: 1),
                                          exercise: ex("row", "Row"), lastSets: [])
        ])
        let members = s.supersetMembers(at: 0)
        for i in 0..<3 { s.runs[0].sets[i].done = true }   // A: las 3 rondas
        for i in 0..<2 { s.runs[1].sets[i].done = true }   // B: sus 2 rondas (todas las que tiene)
        XCTAssertEqual(s.closedSupersetRounds(members: members), 3, "B no tener 3.ª fila no bloquea la cuenta de A")
    }

    /// `addExercise` (ad-hoc, FER-762) and `replaceExercise` (swap mid-session, FER-894) both always seed
    /// `supersetGroup = nil` — neither auto-joins a superset it wasn't authored into.
    func testAddExerciseAndReplaceExerciseLeaveSupersetGroupNil() {
        let s = supersetSession()
        s.addExercise(ex("deadlift", "Deadlift"))
        XCTAssertNil(s.runs.last?.supersetGroup, "an ad-hoc exercise is never auto-grouped")

        XCTAssertEqual(s.runs[0].supersetGroup, 1, "A1 starts grouped")
        s.replaceExercise(at: 0, with: ex("incline", "Incline bench"))
        XCTAssertNil(s.runs[0].supersetGroup, "swapping the exercise breaks its superset membership")
    }

    // MARK: - removeExercise leaves an orphaned superset dissolved (FER-188)
    //
    // Pre-existing bug found in F3: `removeExercise` isn't group-aware. Removing one of a 2-member
    // superset left the survivor with a `supersetGroup` pointing at a group of ONE — behaviorally
    // inert (paints loose) but dirty state that can confuse the superset logic downstream. Fix reuses
    // the same criterion `breakSupersetBlock` (RoutineSheetLiveLogic) uses to dissolve a block: set
    // `supersetGroup = nil` on whoever's left, only when that leaves fewer than 2 members.

    /// [A,B] superset → remove A → B must NOT keep a group-of-one; it becomes standalone (nil).
    func testRemoveExerciseDissolvesGroupOfTwoDownToOne() {
        let s = supersetSession()   // a(bench)+b(row) grouped as 1; c(curl) standalone
        XCTAssertEqual(s.runs[0].supersetGroup, 1, "sanity: a starts grouped")
        XCTAssertEqual(s.runs[1].supersetGroup, 1, "sanity: b starts grouped")
        s.removeExercise(at: 0)   // remove "bench" (a)
        XCTAssertEqual(s.runs.first?.exerciseId, "row", "b took a's old slot")
        XCTAssertNil(s.runs.first?.supersetGroup, "b left alone must not carry a dead group-of-one")
    }

    /// [A,B,C] superset → remove A → B and C stay grouped (2 members is still a real superset).
    func testRemoveExerciseKeepsGroupOfThreeDownToTwo() {
        let s = make([
            StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 1, superset: 1),
                                          exercise: ex("bench", "Bench"), lastSets: []),
            StrengthSessionModel.PlanSlot(re: re("b", exerciseId: "row", sets: 1, superset: 1),
                                          exercise: ex("row", "Row"), lastSets: []),
            StrengthSessionModel.PlanSlot(re: re("c", exerciseId: "curl", sets: 1, superset: 1),
                                          exercise: ex("curl", "Curl"), lastSets: [])
        ])
        s.removeExercise(at: 0)   // remove "bench" (a); b, c remain
        XCTAssertEqual(s.runs.count, 2)
        XCTAssertEqual(s.runs[0].exerciseId, "row")
        XCTAssertEqual(s.runs[0].supersetGroup, 1, "b stays grouped — 2 members is still a real superset")
        XCTAssertEqual(s.runs[1].supersetGroup, 1, "c stays grouped too")
    }

    /// Removing a run with NO group (standalone) never touches anyone else's grouping.
    func testRemoveStandaloneExerciseLeavesOtherGroupsUntouched() {
        let s = supersetSession()   // a+b grouped as 1; c standalone
        s.removeExercise(at: 2)     // remove "curl" (c, standalone)
        XCTAssertEqual(s.runs.count, 2)
        XCTAssertEqual(s.runs[0].supersetGroup, 1, "a's group is untouched")
        XCTAssertEqual(s.runs[1].supersetGroup, 1, "b's group is untouched")
    }

    // MARK: - The deload pill survives a crash-restore (FER-189)
    //
    // Bug found in F4: `ExerciseRun.deloadState` (the B7 deload proposal) wasn't part of
    // `snapshot`/`restore`, unlike `proposedRaise`/`heldRaise` which are preserved deliberately. A
    // crash mid-session dropped an un-actioned deload proposal (it gets recomputed next session, but
    // this one vanishes for the rest of THIS session). An already-APPLIED deload survives regardless
    // (it's baked into the cell weights the snapshot already carries) — this is only about the offer.

    func testDeloadProposalSurvivesSnapshotRestore() {
        let slot = StrengthSessionModel.PlanSlot(re: re("a", exerciseId: "bench", sets: 1),
                                                 exercise: ex("bench", "Bench"), lastSets: [],
                                                 progressionState: .deloading(fromKg: 100, toKg: 92.5))
        let s = make([slot])
        XCTAssertEqual(s.runs[0].deloadState, .deloading(fromKg: 100, toKg: 92.5), "sanity: seeded")

        let restored = StrengthSessionModel.restore(from: s.snapshot(now: 200))
        XCTAssertEqual(restored.runs[0].deloadState, .deloading(fromKg: 100, toKg: 92.5),
                       "the un-actioned deload proposal must survive a crash-restore")
    }

    // MARK: Descanso sin reloj vivo (FER-250)

    private func hrEx(_ id: String, exerciseId: String, sets: Int, restSeconds: Int) -> RoutineExercise {
        RoutineExercise(id: id, routineId: "rt", exerciseId: exerciseId, position: 0,
                        targetSets: sets, restMode: .heartRate, restSeconds: restSeconds)
    }

    func testHeartRateRestDegradesToRoutineSecondsWithoutLivePulse() {
        // Rutina pide descanso por FC (120 s de objetivo). Sin pulso vivo → temporizador fijo de 120 s,
        // no un descanso por FC que nunca suelta ni un cronómetro en 0.
        let s = make([StrengthSessionModel.PlanSlot(re: hrEx("a", exerciseId: "bench", sets: 3, restSeconds: 120),
                                                    exercise: ex("bench", "Bench"), lastSets: [])])
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000), restingHR: 60, hasLivePulse: false)
        XCTAssertEqual(s.currentRestMode, .fixed, "sin pulso vivo, el descanso por FC cae a fijo")
        XCTAssertEqual(s.restEndsAt?.timeIntervalSince1970 ?? 0, 5000 + 120, accuracy: 0.5,
                       "usa el objetivo de la rutina (120 s), no el respaldo")
    }

    func testHeartRateRestWithoutSecondsFallsBackTo90WithoutLivePulse() {
        // Rutina por FC sin segundos definidos + sin reloj → respaldo de 90 s (no un cronómetro en 0).
        let s = make([StrengthSessionModel.PlanSlot(re: hrEx("a", exerciseId: "bench", sets: 3, restSeconds: 0),
                                                    exercise: ex("bench", "Bench"), lastSets: [])])
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000), restingHR: 60, hasLivePulse: false)
        XCTAssertEqual(s.currentRestMode, .fixed)
        XCTAssertEqual(s.restEndsAt?.timeIntervalSince1970 ?? 0, 5000 + 90, accuracy: 0.5,
                       "sin objetivo de rutina, el respaldo son 90 s")
    }

    func testHeartRateRestPreservedWithLivePulse() {
        // No-regresión: con pulso vivo y baseline, el descanso por FC se conserva.
        let s = make([StrengthSessionModel.PlanSlot(re: hrEx("a", exerciseId: "bench", sets: 3, restSeconds: 120),
                                                    exercise: ex("bench", "Bench"), lastSets: [])])
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000), restingHR: 60, hasLivePulse: true)
        XCTAssertEqual(s.currentRestMode, .heartRate, "con pulso vivo, el descanso por FC se preserva")
    }

    /// FER-257 D4: contrato del espejo del Watch — debe pasar `hasLivePulse: watchBpm != nil`.
    /// Contra el default viejo (`true`), un registro sin pulso vivo dejaría `.heartRate` colgado.
    func testMirrorContractHeartRateRestDegradesWithoutExplicitLivePulse() {
        let s = make([StrengthSessionModel.PlanSlot(re: hrEx("a", exerciseId: "bench", sets: 3, restSeconds: 120),
                                                    exercise: ex("bench", "Bench"), lastSets: [])])
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000), restingHR: 60, hasLivePulse: false)
        XCTAssertEqual(s.currentRestMode, .fixed,
                       "espejo sin watchBpm debe degradar a fijo (no asumir hasLivePulse: true)")
    }
}
