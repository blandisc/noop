import XCTest
import StrandTraining
@testable import Cenit

/// Pins the guided strength session logic (FER-347): prefill from «la última vez», register/advance,
/// add/skip set, skip/reorder exercise, and the save build. Pure model — no UI, no DB.
@MainActor
final class StrengthSessionModelTests: XCTestCase {

    private func re(_ id: String, exerciseId: String, sets: Int, reps: Int? = nil,
                    weight: Double? = nil, rest: Int = 90) -> RoutineExercise {
        RoutineExercise(id: id, routineId: "rt", exerciseId: exerciseId, position: 0,
                        targetSets: sets, targetReps: reps, targetWeightKg: weight,
                        restMode: .fixed, restSeconds: rest)
    }

    private func ex(_ id: String, _ name: String, type: ExerciseType = .weightReps) -> Exercise {
        Exercise(id: id, name: name, type: type, equipment: nil,
                 primaryMuscles: [], secondaryMuscles: [], cues: [])
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
        let (record, sets) = s.buildForSave(deviceId: "my-whoop", endTs: 9000)
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
        let (_, sets) = s.buildForSave(deviceId: nil, endTs: 9000)
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
}
