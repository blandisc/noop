import XCTest
import StrandTraining
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
        // Exercise default = fixed 90s; set 0 overrides to fixed 200s, set 1 inherits.
        let override = RestConfig(mode: .fixed, seconds: 200)
        let re = RoutineExercise(id: "a", routineId: "rt", exerciseId: "bench", position: 0, targetSets: 2,
                                 restMode: .fixed, restSeconds: 90,
                                 sets: [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 60, rest: override),
                                        RoutineSet(position: 1, kind: .work, reps: 8, weightKg: 60)])
        let s = make([StrengthSessionModel.PlanSlot(re: re, exercise: ex("bench", "Bench"), lastSets: [])])

        // Registering set 0 uses its OWN 200s rest, not the exercise's 90s.
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(s.restEndsAt?.timeIntervalSince1970 ?? 0, 5000 + 200, accuracy: 0.5,
                       "the active set's own rest wins")
        // Registering set 1 (no override) falls back to the exercise's 90s.
        s.registerCurrentSet(now: Date(timeIntervalSince1970: 6000))
        XCTAssertEqual(s.restEndsAt?.timeIntervalSince1970 ?? 0, 6000 + 90, accuracy: 0.5,
                       "a set with no override inherits the exercise rest")
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
}
