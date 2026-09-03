import XCTest
@testable import CenitStore
import StrandTraining
import BiometricStreams

final class StrengthStoreTests: XCTestCase {

    func testV13CreatesStrengthTables() async throws {
        let store = try await CenitStore.inMemory()
        let tables = try await store.tableNames()
        for t in ["customExercise", "routine", "routineExercise",
                  "strengthSession", "setEntry", "personalRecord"] {
            XCTAssertTrue(tables.contains(t), "missing table \(t)")
        }
    }

    /// Append-only: v13 leaves prior tables (v8 `workout`, v12 `experiment`) in place.
    func testV13PreservesPriorTables() async throws {
        let store = try await CenitStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("workout"))
        XCTAssertTrue(tables.contains("experiment"))
    }

    /// FER-495: the per-exercise HR rest target round-trips; an unconfigured exercise reads back as the
    /// FER-348 default (`.restingMargin` / 0).
    func testHRRestConfigRoundTrip() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Pierna", createdTs: 0, updatedTs: 0)
        let exs = [
            RoutineExercise(id: "a", routineId: "rt1", exerciseId: "ex1", position: 0, targetSets: 3,
                            hrRestReference: .karvonenReserve, hrRestValue: 0.45),
            RoutineExercise(id: "b", routineId: "rt1", exerciseId: "ex2", position: 1, targetSets: 3,
                            hrRestReference: .peakDrop, hrRestValue: 0.30),
            RoutineExercise(id: "c", routineId: "rt1", exerciseId: "ex3", position: 2, targetSets: 3),  // default
        ]
        try await store.saveRoutine(r, exercises: exs)
        let back = try await store.routineExercises(routineId: "rt1")
        XCTAssertEqual(back.map(\.hrRestReference), [.karvonenReserve, .peakDrop, .restingMargin])
        XCTAssertEqual(back.map(\.hrRestValue), [0.45, 0.30, 0])
    }

    /// FER-A: the four load-progression fields round-trip through save/read; an exercise with progression
    /// left off reads back with the OFF defaults (enabled false, 2 sessions, nil increment, .propose).
    func testProgressionFieldsRoundTrip() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Pierna", createdTs: 0, updatedTs: 0)
        let exs = [
            RoutineExercise(id: "a", routineId: "rt1", exerciseId: "ex1", position: 0, targetSets: 4,
                            progressionEnabled: true, progressionSessions: 2,
                            progressionIncrementKg: 2.5, progressionDeload: .warn,
                            progressionIgnoreRecovery: true),
            RoutineExercise(id: "b", routineId: "rt1", exerciseId: "ex2", position: 1, targetSets: 3),  // default OFF
        ]
        try await store.saveRoutine(r, exercises: exs)
        let back = try await store.routineExercises(routineId: "rt1")
        let a = back.first { $0.id == "a" }!
        XCTAssertTrue(a.progressionEnabled)
        XCTAssertEqual(a.progressionSessions, 2)
        XCTAssertEqual(a.progressionIncrementKg, 2.5)
        XCTAssertEqual(a.progressionDeload, .warn)
        XCTAssertTrue(a.progressionIgnoreRecovery)
        let b = back.first { $0.id == "b" }!
        XCTAssertFalse(b.progressionEnabled)
        XCTAssertEqual(b.progressionSessions, 2)
        XCTAssertNil(b.progressionIncrementKg)
        XCTAssertEqual(b.progressionDeload, .propose)
        XCTAssertFalse(b.progressionIgnoreRecovery)
    }

    /// FER-540: editing rest mid-session pinpoint-updates one exercise's four rest fields and leaves its
    /// per-set prescription AND the other exercises untouched (unlike a full `saveRoutine` rewrite).
    func testUpdateRoutineExerciseRestPinpoint() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Pierna", createdTs: 0, updatedTs: 0)
        let exs = [
            RoutineExercise(id: "a", routineId: "rt1", exerciseId: "ex1", position: 0, targetSets: 2,
                            restMode: .fixed, restSeconds: 60,
                            sets: [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 60),
                                   RoutineSet(position: 1, kind: .work, reps: 6, weightKg: 70)]),
            RoutineExercise(id: "b", routineId: "rt1", exerciseId: "ex2", position: 1, targetSets: 3,
                            restMode: .fixed, restSeconds: 45),
        ]
        try await store.saveRoutine(r, exercises: exs)

        try await store.updateRoutineExerciseRest(routineExerciseId: "a", routineId: "rt1",
            mode: .heartRate, seconds: 120, reference: .peakDrop, value: 0.25, updatedTs: 999)

        let back = try await store.routineExercises(routineId: "rt1")
        let a = back.first { $0.id == "a" }!
        let b = back.first { $0.id == "b" }!
        // The edited exercise has the new rest config…
        XCTAssertEqual(a.restMode, .heartRate)
        XCTAssertEqual(a.restSeconds, 120)
        XCTAssertEqual(a.hrRestReference, .peakDrop)
        XCTAssertEqual(a.hrRestValue, 0.25)
        // …its per-set prescription is intact…
        XCTAssertEqual(a.sets.filter { $0.kind == .work }.map(\.reps), [8, 6])
        XCTAssertEqual(a.sets.filter { $0.kind == .work }.map(\.weightKg), [60, 70])
        // …and the other exercise is untouched.
        XCTAssertEqual(b.restMode, .fixed)
        XCTAssertEqual(b.restSeconds, 45)
        // The routine's updatedTs was bumped.
        let routine = try await store.routines().first { $0.id == "rt1" }
        XCTAssertEqual(routine?.updatedTs, 999)
    }

    // MARK: - Reps range top (E13/FER-94)

    /// A set's `repsRangeTop` round-trips through GRDB with a value, and a sibling written with `nil`
    /// reads back `nil` — a plain routine (no range) behaves identically to before this field existed.
    func testRepsRangeTopRoundTrip() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Pierna", createdTs: 0, updatedTs: 0)
        let exs = [
            RoutineExercise(id: "a", routineId: "rt1", exerciseId: "ex1", position: 0, targetSets: 2,
                            sets: [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 60, repsRangeTop: 12),
                                   RoutineSet(position: 1, kind: .work, reps: 6, weightKg: 70)]),
        ]
        try await store.saveRoutine(r, exercises: exs)

        let back = try await store.routineExercises(routineId: "rt1")
        let a = back.first { $0.id == "a" }!
        XCTAssertEqual(a.sets[0].repsRangeTop, 12, "the first set keeps its range top")
        XCTAssertNil(a.sets[1].repsRangeTop, "a set with no range reads back nil")
    }

    /// An «old» routine saved before v38 (no `repsRangeTop` value ever written) reads back `nil` for
    /// every set — regression: identical to today's behavior.
    func testOldRoutineWithoutRepsRangeTopReadsAsNil() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Pierna", createdTs: 0, updatedTs: 0)
        let exs = [
            RoutineExercise(id: "a", routineId: "rt1", exerciseId: "ex1", position: 0, targetSets: 3,
                            sets: [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 60)]),
        ]
        try await store.saveRoutine(r, exercises: exs)

        let back = try await store.routineExercises(routineId: "rt1")
        XCTAssertTrue(back.first { $0.id == "a" }!.sets.allSatisfy { $0.repsRangeTop == nil })
    }

    // MARK: - Per-set rest (FER-715)

    /// A set can carry a rest override distinct from its siblings, and it survives a round-trip through
    /// GRDB; a sibling with no override reads back `nil` (it inherits the exercise at runtime).
    func testPerSetRestOverrideRoundTrip() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Pierna", createdTs: 0, updatedTs: 0)
        let override = RestConfig(mode: .fixed, seconds: 200, hrReference: .fixedBpm, hrValue: 110)
        let exs = [
            RoutineExercise(id: "a", routineId: "rt1", exerciseId: "ex1", position: 0, targetSets: 2,
                            restMode: .heartRate, restSeconds: 90,
                            sets: [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 60, rest: override),
                                   RoutineSet(position: 1, kind: .work, reps: 6, weightKg: 70)]),
        ]
        try await store.saveRoutine(r, exercises: exs)

        let back = try await store.routineExercises(routineId: "rt1")
        let a = back.first { $0.id == "a" }!
        XCTAssertEqual(a.sets[0].rest, override, "the first set keeps its distinct override")
        XCTAssertNil(a.sets[1].rest, "a set with no override reads back nil = inherit")
        // effectiveRest applies the fallback rule: overridden set → its own; sibling → the exercise.
        XCTAssertEqual(a.effectiveRest(for: a.sets[0]), override)
        XCTAssertEqual(a.effectiveRest(for: a.sets[1]), a.restConfig)
    }

    /// `updateRoutineExerciseRest` (scope exercise) cascades the new rest onto ALL the exercise's sets, so
    /// the next session reads the fresh value from every set (no stale per-set copy) — the FER-540 → FER-715
    /// regression guard.
    func testUpdateRoutineExerciseRestCascadesToAllSets() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Pierna", createdTs: 0, updatedTs: 0)
        let exs = [
            RoutineExercise(id: "a", routineId: "rt1", exerciseId: "ex1", position: 0, targetSets: 3,
                            restMode: .fixed, restSeconds: 60,
                            sets: [RoutineSet(position: 0, kind: .work, reps: 8),
                                   RoutineSet(position: 1, kind: .work, reps: 8,
                                              rest: RestConfig(mode: .fixed, seconds: 30)),
                                   RoutineSet(position: 2, kind: .work, reps: 8)]),
        ]
        try await store.saveRoutine(r, exercises: exs)

        try await store.updateRoutineExerciseRest(routineExerciseId: "a", routineId: "rt1",
            mode: .heartRate, seconds: 150, reference: .peakDrop, value: 0.2, updatedTs: 42)

        let a = try await store.routineExercises(routineId: "rt1").first { $0.id == "a" }!
        let expected = RestConfig(mode: .heartRate, seconds: 150, hrReference: .peakDrop, hrValue: 0.2)
        XCTAssertEqual(a.restConfig, expected, "the exercise default updated")
        XCTAssertTrue(a.sets.allSatisfy { $0.rest == expected },
                      "every set (even the one that had its own override) now carries the cascaded rest")
    }

    /// `updateRoutineSetRest` (scope set) pinpoint-updates one set and clears back to inherit with nil,
    /// leaving its siblings and the exercise default untouched.
    func testUpdateRoutineSetRestPinpointAndClear() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Pierna", createdTs: 0, updatedTs: 0)
        let exs = [
            RoutineExercise(id: "a", routineId: "rt1", exerciseId: "ex1", position: 0, targetSets: 2,
                            restMode: .fixed, restSeconds: 60,
                            sets: [RoutineSet(id: "s0", position: 0, kind: .work, reps: 8),
                                   RoutineSet(id: "s1", position: 1, kind: .work, reps: 8)]),
        ]
        try await store.saveRoutine(r, exercises: exs)

        let newRest = RestConfig(mode: .heartRate, seconds: 100, hrReference: .karvonenReserve, hrValue: 0.5)
        try await store.updateRoutineSetRest(routineSetId: "s0", routineId: "rt1", rest: newRest, updatedTs: 7)

        var a = try await store.routineExercises(routineId: "rt1").first { $0.id == "a" }!
        XCTAssertEqual(a.sets.first { $0.id == "s0" }?.rest, newRest, "only s0 got the override")
        // s1 was saved with no override, so it stays nil (inherits the exercise) — untouched by the edit.
        XCTAssertNil(a.sets.first { $0.id == "s1" }?.rest, "the sibling is untouched (still inherits)")
        let routine = try await store.routines().first { $0.id == "rt1" }
        XCTAssertEqual(routine?.updatedTs, 7, "the routine's updatedTs was bumped")

        // Clearing the override with nil sends the set back to inheriting.
        try await store.updateRoutineSetRest(routineSetId: "s0", routineId: "rt1", rest: nil, updatedTs: 8)
        a = try await store.routineExercises(routineId: "rt1").first { $0.id == "a" }!
        XCTAssertNil(a.sets.first { $0.id == "s0" }?.rest, "nil clears the override = inherit")
    }

    // MARK: - Persisted session energy (FER-715)

    /// A session's energy (kcal + source) round-trips through save → read, via both the list read and the
    /// by-id read, and an editing `updateSession` preserves it (like strain/avgHr).
    func testSessionEnergyRoundTripAndSurvivesEdit() async throws {
        let store = try await CenitStore.inMemory()
        let withHR = StrengthSession(id: "s1", startTs: 1000, endTs: 2000,
                                     energyKcal: 412.5, energySource: .bandCalculated)
        try await store.saveSession(withHR, sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001)])
        let noHR = StrengthSession(id: "s2", startTs: 3000, endTs: 4000,
                                   energyKcal: 180, energySource: .estimated)
        try await store.saveSession(noHR, sets: [])

        let byId = try await store.session(id: "s1")
        XCTAssertEqual(byId?.energyKcal, 412.5)
        XCTAssertEqual(byId?.energySource, .bandCalculated)
        let recent = try await store.recentSessions()
        XCTAssertEqual(recent.first { $0.id == "s2" }?.energySource, .estimated)
        XCTAssertEqual(recent.first { $0.id == "s2" }?.energyKcal, 180)

        // An edit that carries the same energy (the edit UI seeds from session(id:)) preserves it.
        var edited = byId!
        edited.notes = "editada"
        try await store.updateSession(edited, sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 65, reps: 8, done: true, ts: 1001)])
        let after = try await store.session(id: "s1")
        XCTAssertEqual(after?.energyKcal, 412.5, "editing a session preserves its persisted energy")
        XCTAssertEqual(after?.energySource, .bandCalculated)
    }

    /// FER-541: the exercise type override round-trips, upserts (one row per id), and clears back to empty.
    func testExerciseTypeOverrideRoundTrip() async throws {
        let store = try await CenitStore.inMemory()
        let empty = try await store.exerciseTypeOverrides()
        XCTAssertTrue(empty.isEmpty)

        try await store.setExerciseTypeOverride("Plank", type: .time, ts: 1)
        let afterSet = try await store.exerciseTypeOverrides()
        XCTAssertEqual(afterSet["Plank"], .time)

        // Upsert: setting the same id again replaces, not duplicates.
        try await store.setExerciseTypeOverride("Plank", type: .bodyweight, ts: 2)
        let all = try await store.exerciseTypeOverrides()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all["Plank"], .bodyweight)

        // Clearing reverts to no override.
        try await store.clearExerciseTypeOverride("Plank")
        let afterClear = try await store.exerciseTypeOverrides()
        XCTAssertTrue(afterClear.isEmpty)
    }

    /// FER-541: the effective-type precedence is override > custom > catalog.
    func testEffectiveTypePrecedence() {
        // Override wins over everything.
        XCTAssertEqual(ExerciseTypeResolver.effectiveType(override: .time, custom: .weightReps, catalog: .bodyweight), .time)
        // No override → custom wins over catalog.
        XCTAssertEqual(ExerciseTypeResolver.effectiveType(override: nil, custom: .weightReps, catalog: .bodyweight), .weightReps)
        // No override, no custom → catalog.
        XCTAssertEqual(ExerciseTypeResolver.effectiveType(override: nil, custom: nil, catalog: .time), .time)
        // Nothing known → nil.
        XCTAssertNil(ExerciseTypeResolver.effectiveType(override: nil, custom: nil, catalog: nil))
    }

    // MARK: - Folders (FER-494)

    /// Create + rename a folder round-trips via the public API (rename is an upsert on the same id).
    func testFolderRoundTrip() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveFolder(RoutineFolder(id: "f1", name: "Empuje", sortOrder: 0))
        var got = try await store.routineFolders()
        XCTAssertEqual(got.map(\.name), ["Empuje"])
        try await store.saveFolder(RoutineFolder(id: "f1", name: "Push", sortOrder: 0))   // rename
        got = try await store.routineFolders()
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first?.name, "Push")
    }

    /// Moving a routine into/out of a folder is a pinpoint update — it persists and leaves the
    /// routine's exercises untouched.
    func testSetRoutineFolderMovesAndClears() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Pierna A", createdTs: 0, updatedTs: 0)
        let ex = [RoutineExercise(id: "re1", routineId: "rt1", exerciseId: "squat", position: 0, targetSets: 3)]
        try await store.saveRoutine(r, exercises: ex)
        try await store.saveFolder(RoutineFolder(id: "f1", name: "Pierna", sortOrder: 0))

        try await store.setRoutineFolder(routineId: "rt1", folderId: "f1")
        var back = try await store.routines()
        XCTAssertEqual(back.first?.folderId, "f1")
        let exCount = try await store.routineExercises(routineId: "rt1").count
        XCTAssertEqual(exCount, 1, "moving must not touch the routine's exercises")

        try await store.setRoutineFolder(routineId: "rt1", folderId: nil)
        back = try await store.routines()
        XCTAssertNil(back.first?.folderId)
    }

    /// **Invariant:** deleting a folder keeps its routines — they fall to «Sin carpeta» (folderId NULL).
    func testDeleteFolderKeepsRoutinesAsUnfiled() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveFolder(RoutineFolder(id: "f1", name: "Empuje", sortOrder: 0))
        for i in 0..<2 {
            let r = Routine(id: "rt\(i)", name: "R\(i)", folderId: "f1", createdTs: 0, updatedTs: 0)
            try await store.saveRoutine(r, exercises: [])
        }
        try await store.deleteFolder(id: "f1")

        let folders = try await store.routineFolders()
        XCTAssertTrue(folders.isEmpty, "folder is gone")
        let routines = try await store.routines()
        XCTAssertEqual(routines.count, 2, "routines must survive the folder deletion")
        XCTAssertTrue(routines.allSatisfy { $0.folderId == nil }, "they fall to «Sin carpeta»")
    }

    /// `saveRoutine` persists `folderId` (so editing a foldered routine keeps it in its folder).
    func testSaveRoutinePersistsFolderId() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveFolder(RoutineFolder(id: "f1", name: "Empuje", sortOrder: 0))
        let r = Routine(id: "rt1", name: "Banca", folderId: "f1", createdTs: 0, updatedTs: 0)
        try await store.saveRoutine(r, exercises: [])
        let back = try await store.routines()
        XCTAssertEqual(back.first?.folderId, "f1")
    }

    // MARK: - Weekly split (FER-531)

    /// The split round-trips, re-assigning a day overwrites (PK on `weekday`), and clearing a day
    /// removes it (back to a rest day).
    func testWeeklySplitRoundTripUpsertAndClear() async throws {
        let store = try await CenitStore.inMemory()
        let initial = try await store.routineSchedule()
        XCTAssertTrue(initial.isEmpty, "starts empty → «no plan yet»")

        try await store.setRoutineSchedule(weekday: 2, routineId: "push")    // Monday
        try await store.setRoutineSchedule(weekday: 5, routineId: "pull")    // Thursday
        var split = try await store.routineSchedule()
        XCTAssertEqual(split.map { [$0.weekday: $0.routineId] }, [[2: "push"], [5: "pull"]])

        // Re-assigning Monday overwrites, it does not duplicate (one routine per day).
        try await store.setRoutineSchedule(weekday: 2, routineId: "legs")
        split = try await store.routineSchedule()
        XCTAssertEqual(split.count, 2)
        XCTAssertEqual(split.first { $0.weekday == 2 }?.routineId, "legs")

        // Clearing a day drops it back to a rest day.
        try await store.clearRoutineSchedule(weekday: 5)
        split = try await store.routineSchedule()
        XCTAssertEqual(split.map(\.weekday), [2])
    }

    /// **Invariant:** deleting a routine clears any split rows pointing at it — no dangling day survives.
    func testDeleteRoutineClearsItsSchedule() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveRoutine(Routine(id: "push", name: "Empuje", createdTs: 0, updatedTs: 0), exercises: [])
        try await store.setRoutineSchedule(weekday: 2, routineId: "push")
        try await store.setRoutineSchedule(weekday: 5, routineId: "push")

        try await store.deleteRoutine(id: "push")
        let afterDelete = try await store.routineSchedule()
        XCTAssertTrue(afterDelete.isEmpty, "deleting the routine leaves no split row")
    }

    // MARK: - Reorder (FER-526)

    /// `reorderFolders` persists the given order (sortOrder = index), and `routineFolders()` returns it.
    func testReorderFoldersPersists() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveFolder(RoutineFolder(id: "a", name: "A", sortOrder: 0))
        try await store.saveFolder(RoutineFolder(id: "b", name: "B", sortOrder: 1))
        try await store.saveFolder(RoutineFolder(id: "c", name: "C", sortOrder: 2))
        try await store.reorderFolders(["c", "a", "b"])
        let back = try await store.routineFolders()
        XCTAssertEqual(back.map(\.id), ["c", "a", "b"])
    }

    /// `reorderRoutines` persists the global order and never rewrites the routines' exercises/sets (FER-492).
    func testReorderRoutinesPersistsAndKeepsExercises() async throws {
        let store = try await CenitStore.inMemory()
        for i in 0..<3 {
            let ex = [RoutineExercise(id: "re\(i)", routineId: "rt\(i)", exerciseId: "ex", position: 0,
                                      targetSets: 3, sets: [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 50)])]
            try await store.saveRoutine(Routine(id: "rt\(i)", name: "R\(i)", createdTs: 0, updatedTs: 0), exercises: ex)
        }
        try await store.reorderRoutines(["rt2", "rt0", "rt1"])
        let back = try await store.routines()
        XCTAssertEqual(back.map(\.id), ["rt2", "rt0", "rt1"])
        // The moved routine's per-set plan survives the reorder.
        let sets = try await store.routineExercises(routineId: "rt2").first?.sets
        XCTAssertEqual(sets?.count, 1)
        XCTAssertEqual(sets?.first?.reps, 8)
    }

    /// Moving a routine to a folder lands it at the end of the global order (sortOrder = max+1) and keeps
    /// its exercises.
    func testMoveToFolderLandsAtEndAndKeepsExercises() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveFolder(RoutineFolder(id: "f1", name: "Empuje", sortOrder: 0))
        for i in 0..<3 {
            let ex = [RoutineExercise(id: "re\(i)", routineId: "rt\(i)", exerciseId: "ex", position: 0, targetSets: 3)]
            try await store.saveRoutine(Routine(id: "rt\(i)", name: "R\(i)", createdTs: 0, updatedTs: 0), exercises: ex)
        }
        try await store.reorderRoutines(["rt0", "rt1", "rt2"])   // sortOrder 0,1,2
        try await store.setRoutineFolder(routineId: "rt0", folderId: "f1")
        let back = try await store.routines()
        XCTAssertEqual(back.first(where: { $0.id == "rt0" })?.folderId, "f1")
        XCTAssertEqual(back.last?.id, "rt0", "moved routine lands last in the global order")
        let exCount = try await store.routineExercises(routineId: "rt0").count
        XCTAssertEqual(exCount, 1)
    }

    func testRoutineRoundTrip() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Día de empuje", tag: "Empuje", createdTs: 100, updatedTs: 100)
        let exercises = [
            RoutineExercise(id: "re1", routineId: "rt1", exerciseId: "bench", position: 0,
                            targetSets: 4, targetReps: 8, targetWeightKg: 60,
                            warmupPercents: [0.4, 0.6, 0.8], restMode: .heartRate, restSeconds: 90),
            RoutineExercise(id: "re2", routineId: "rt1", exerciseId: "incline", position: 1,
                            targetSets: 3, targetReps: 10, targetWeightKg: 24,
                            warmupPercents: [], restMode: .fixed, restSeconds: 75),
        ]
        try await store.saveRoutine(r, exercises: exercises)

        let names = try await store.routines().map(\.name)
        XCTAssertEqual(names, ["Día de empuje"])
        let back = try await store.routineExercises(routineId: "rt1")
        XCTAssertEqual(back.map(\.exerciseId), ["bench", "incline"])   // ordered by position
        XCTAssertEqual(back.first?.warmupPercents, [0.4, 0.6, 0.8])    // JSON array round-trips
        XCTAssertEqual(back.first?.restMode, .heartRate)
        XCTAssertEqual(back.last?.restMode, .fixed)

        // Re-saving replaces the routine's exercise list.
        try await store.saveRoutine(r, exercises: [exercises[0]])
        let afterEdit = try await store.routineExercises(routineId: "rt1")
        XCTAssertEqual(afterEdit.count, 1)

        try await store.deleteRoutine(id: "rt1")
        let routinesLeft = try await store.routines()
        let exLeft = try await store.routineExercises(routineId: "rt1")
        XCTAssertTrue(routinesLeft.isEmpty)
        XCTAssertTrue(exLeft.isEmpty)
    }

    /// FER-492: heterogeneous per-set reps/weight round-trip in order, and the legacy target* columns
    /// are derived from the work sets (count + first work set) so old readers stay coherent.
    func testRoutineSetsRoundTripHeterogeneous() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Pierna A", createdTs: 0, updatedTs: 0)
        let sets = [
            RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 60),
            RoutineSet(position: 1, kind: .work, reps: 6, weightKg: 70),
            RoutineSet(position: 2, kind: .work, reps: 4, weightKg: 80),
        ]
        let re = RoutineExercise(id: "re1", routineId: "rt1", exerciseId: "squat", position: 0,
                                 targetSets: 1, targetReps: nil, targetWeightKg: nil, sets: sets)
        try await store.saveRoutine(r, exercises: [re])

        let back = try await store.routineExercises(routineId: "rt1")
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back.first?.sets.map(\.reps), [8, 6, 4])
        XCTAssertEqual(back.first?.sets.map(\.weightKg), [60, 70, 80])
        XCTAssertEqual(back.first?.sets.map(\.position), [0, 1, 2])
        // Derived compatibility columns reflect the work sets (count + first work set).
        XCTAssertEqual(back.first?.targetSets, 3)
        XCTAssertEqual(back.first?.targetReps, 8)
        XCTAssertEqual(back.first?.targetWeightKg, 60)
    }

    /// Re-saving with fewer sets deletes the removed set rows — no orphaned `routineSet` rows survive.
    func testRoutineSetReplaceDeletesOrphans() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Pierna A", createdTs: 0, updatedTs: 0)
        let three = (0..<3).map { RoutineSet(position: $0, kind: .work, reps: 8, weightKg: 50) }
        let re3 = RoutineExercise(id: "re1", routineId: "rt1", exerciseId: "squat", position: 0,
                                  targetSets: 3, sets: three)
        try await store.saveRoutine(r, exercises: [re3])
        let initial = try await store.routineExercises(routineId: "rt1").first?.sets.count
        XCTAssertEqual(initial, 3)

        var re2 = re3
        re2.sets = Array(three.prefix(2))
        try await store.saveRoutine(r, exercises: [re2])
        let back = try await store.routineExercises(routineId: "rt1")
        XCTAssertEqual(back.first?.sets.count, 2, "removed set must not leave an orphan row")
        XCTAssertEqual(back.first?.targetSets, 2)
    }

    /// A legacy in-memory slot with no `sets` (e.g. a starter template) still persists and reads back
    /// with sets synthesized 1:1 from its target* — `sets` is never empty.
    func testRoutineWithoutSetsSynthesizesFromTargets() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Plantilla", createdTs: 0, updatedTs: 0)
        let re = RoutineExercise(id: "re1", routineId: "rt1", exerciseId: "bench", position: 0,
                                 targetSets: 4, targetReps: 10, targetWeightKg: 40)   // sets defaults to []
        try await store.saveRoutine(r, exercises: [re])
        let back = try await store.routineExercises(routineId: "rt1").first
        XCTAssertEqual(back?.sets.count, 4)
        XCTAssertTrue(back?.sets.allSatisfy { $0.reps == 10 && $0.weightKg == 40 } ?? false)
    }

    // MARK: - Fixed exercise note (FER-166)

    /// A fixed per-exercise note round-trips through `saveRoutine`/`routineExercises()`; nil stays nil,
    /// and pure whitespace normalizes to nil (never a blank string) — the same "text or NULL" contract
    /// `saveSession` already uses for `strengthExerciseNote`. Re-saving the loaded routine (the autosave
    /// path) must not drop the note either.
    func testRoutineExerciseNoteRoundTripAndNormalizesEmpty() async throws {
        let store = try await CenitStore.inMemory()
        let r = Routine(id: "rt1", name: "Pierna", createdTs: 0, updatedTs: 0)
        let exs = [
            RoutineExercise(id: "a", routineId: "rt1", exerciseId: "ex1", position: 0, targetSets: 3,
                            note: "  Cadera atrás, no rodillas  "),
            RoutineExercise(id: "b", routineId: "rt1", exerciseId: "ex2", position: 1, targetSets: 3),  // nil
            RoutineExercise(id: "c", routineId: "rt1", exerciseId: "ex3", position: 2, targetSets: 3,
                            note: "   "),  // blank → NULL
        ]
        try await store.saveRoutine(r, exercises: exs)

        let back = try await store.routineExercises(routineId: "rt1")
        XCTAssertEqual(back.first { $0.id == "a" }?.note, "Cadera atrás, no rodillas", "trims but keeps text")
        XCTAssertNil(back.first { $0.id == "b" }?.note)
        XCTAssertNil(back.first { $0.id == "c" }?.note, "pure whitespace normalizes to NULL, never a blank string")

        // Re-saving the loaded routine (the autosave path) must not drop the note.
        try await store.saveRoutine(r, exercises: back)
        let again = try await store.routineExercises(routineId: "rt1")
        XCTAssertEqual(again.first { $0.id == "a" }?.note, "Cadera atrás, no rodillas")
    }

    func testSessionSetsAndPR() async throws {
        let store = try await CenitStore.inMemory()
        let session = StrengthSession(id: "s1", routineId: "rt1", startTs: 1000)
        let sets = [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .warmup,
                     weightKg: 24, reps: 10, done: true, ts: 1001),
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 1, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1002),
            SetEntry(id: "c", sessionId: "s1", exerciseId: "bench", position: 2, kind: .work,
                     weightKg: 62.5, reps: 8, done: true, ts: 1003),
        ]
        try await store.saveSession(session, sets: sets)

        let back = try await store.setEntries(sessionId: "s1")
        XCTAssertEqual(back.map(\.position), [0, 1, 2])
        XCTAssertEqual(back.first?.kind, .warmup)

        // maxWeight PR = best WORK set (62.5); the 24 kg warm-up is ignored.
        let prs = try await store.personalRecords(exerciseId: "bench")
        XCTAssertEqual(prs.first { $0.metric == .maxWeight }?.valueKg, 62.5)

        // "la última vez" = most recent done work set first.
        let last = try await store.lastWorkSets(exerciseId: "bench")
        XCTAssertEqual(last.first?.weightKg, 62.5)

        // A later, lighter session must NOT downgrade the PR.
        let lighter = StrengthSession(id: "s2", startTs: 2000)
        try await store.saveSession(lighter, sets: [
            SetEntry(id: "d", sessionId: "s2", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 50, reps: 5, done: true, ts: 2001)
        ])
        let prsAfter = try await store.personalRecords(exerciseId: "bench")
        XCTAssertEqual(prsAfter.first { $0.metric == .maxWeight }?.valueKg, 62.5)
    }

    // MARK: - B10 · el guard de captura absurda (FER-169)

    /// El criterio QA exacto del spec: palomear 825 (contra un PR de ~100) → «SÍ, 825» → el `SetEntry`
    /// SÍ se guarda (el acta no miente) PERO el PR queda intacto Y la siguiente sesión no vuelve a
    /// ofrecer 825 como semilla. Sin columna nueva: `bestPRs`/`lastWorkSets` recomputan el umbral
    /// (`CaptureGuard`, StrandTraining) contra el PR YA existente, no contra una bandera persistida.
    func testAbsurdCaptureConfirmedAsIsNeverMintsAPROrReseedsTheNextSession() async throws {
        let store = try await CenitStore.inMemory()

        // Sesión 1: establece un PR/semilla legítimo de 100 kg.
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 100, reps: 5, done: true, ts: 1001)
        ])
        let prBefore = try await store.personalRecords(exerciseId: "bench")
        XCTAssertEqual(prBefore.first { $0.metric == .maxWeight }?.valueKg, 100)

        // Sesión 2: el humano palomeó 825 (típo de 82.5) y respondió «SÍ, 825» — el `SetEntry` se
        // guarda TAL CUAL, sin bandera ni columna nueva.
        try await store.saveSession(StrengthSession(id: "s2", startTs: 2000), sets: [
            SetEntry(id: "b", sessionId: "s2", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 825, reps: 8, done: true, ts: 2001)
        ])
        let backRaw = try await store.setEntries(sessionId: "s2")
        XCTAssertEqual(backRaw.first?.weightKg, 825, "the acta doesn't lie — the raw capture is saved as-is")

        // El PR queda intacto — 825 NUNCA lo toca.
        let prAfter = try await store.personalRecords(exerciseId: "bench")
        XCTAssertEqual(prAfter.first { $0.metric == .maxWeight }?.valueKg, 100,
                       "an 8× capture must never mint or upgrade a personal record")

        // La siguiente sesión NO abre en 825 — «la última vez» sigue siendo el legítimo 100.
        let seed = try await store.lastWorkSets(exerciseId: "bench")
        XCTAssertEqual(seed.first?.weightKg, 100,
                       "an 8× capture must never resurface as the next session's seed")
        XCTAssertFalse(seed.contains { $0.weightKg == 825 })

        // Ídem para el historial que alimenta la evaluación de progresión (`sessionSeed`).
        let history = try await store.workSetHistory(exerciseId: "bench")
        XCTAssertFalse(history.contains { $0.weightKg == 825 },
                       "the progression classifier must never see the absurd capture either")
    }

    /// `recomputePR` (borrar/editar sesión) re-deriva el PR desde CERO sobre todos los sets que
    /// quedan — el mismo umbral debe seguir excluyendo el 825 incluso reconstruyendo desde crudo,
    /// sin ninguna referencia "PR ya calculado" a la mano (el chicken/egg que `recomputePR` sortea
    /// plegando cronológicamente).
    func testRecomputePRAfterDeleteStillExcludesTheAbsurdCapture() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 100, reps: 5, done: true, ts: 1001)
        ])
        try await store.saveSession(StrengthSession(id: "s2", startTs: 2000), sets: [
            SetEntry(id: "b", sessionId: "s2", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 825, reps: 8, done: true, ts: 2001)
        ])
        // Borra una sesión SIN relación (fuerza `recomputePR` a correr sobre "bench" con lo que queda).
        try await store.saveSession(StrengthSession(id: "s3", startTs: 3000), sets: [
            SetEntry(id: "c", sessionId: "s3", exerciseId: "squat", position: 0, kind: .work,
                     weightKg: 50, reps: 5, done: true, ts: 3001)
        ])
        try await store.deleteSession(id: "s3")

        let prAfter = try await store.personalRecords(exerciseId: "bench")
        XCTAssertEqual(prAfter.first { $0.metric == .maxWeight }?.valueKg, 100)
    }

    /// RPE (FER-930) round-trips through save → read, and is opt-in per set: a set with no RPE reads
    /// back nil, never 0.
    func testRPERoundTrip() async throws {
        let store = try await CenitStore.inMemory()
        let session = StrengthSession(id: "s1", routineId: "rt1", startTs: 1000)
        let sets = [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001, rpe: 8.5),
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 1, kind: .work,
                     weightKg: 62.5, reps: 6, done: true, ts: 1002, rpe: nil),
        ]
        try await store.saveSession(session, sets: sets)

        let back = try await store.setEntries(sessionId: "s1")
        XCTAssertEqual(back.first { $0.id == "a" }?.rpe, 8.5)
        XCTAssertNil(back.first { $0.id == "b" }?.rpe, "no RPE captured must read back nil, never 0")

        // updateSession (editing a saved session) preserves the rpe.
        try await store.updateSession(session, sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001, rpe: 9)
        ])
        let afterEdit = try await store.setEntries(sessionId: "s1")
        XCTAssertEqual(afterEdit.first { $0.id == "a" }?.rpe, 9)
    }

    // MARK: - Real rest per set (FER-167, v40)

    /// `restTakenS` round-trips through `saveSession`, reads back NULL (never 0) when no rest was
    /// measured, and `updateSession` (editing a saved session) preserves it just like `rpe` does.
    func testRestTakenSRoundTripAndSurvivesUpdateSession() async throws {
        let store = try await CenitStore.inMemory()
        let session = StrengthSession(id: "s1", routineId: "rt1", startTs: 1000)
        let sets = [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001, restTakenS: 95),
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 1, kind: .work,
                     weightKg: 62.5, reps: 6, done: true, ts: 1002, restTakenS: nil),
        ]
        try await store.saveSession(session, sets: sets)

        let back = try await store.setEntries(sessionId: "s1")
        XCTAssertEqual(back.first { $0.id == "a" }?.restTakenS, 95)
        XCTAssertNil(back.first { $0.id == "b" }?.restTakenS, "no rest measured must read back nil, never 0")

        // updateSession (editing a saved session) preserves restTakenS.
        try await store.updateSession(session, sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001, restTakenS: 130)
        ])
        let afterEdit = try await store.setEntries(sessionId: "s1")
        XCTAssertEqual(afterEdit.first { $0.id == "a" }?.restTakenS, 130)
    }

    /// `realRestSeconds(routineId:sessionLimit:)` — the insumo of the «DESCANSO REAL» tile — only
    /// counts done WORK sets with a measured rest, from the given routine's most recent sessions,
    /// scoped by session count (not row count).
    func testRealRestSecondsScopesRoutineWorkDoneAndLimit() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveRoutine(Routine(id: "r1", name: "Empuje", createdTs: 0, updatedTs: 0),
                                    exercises: [])
        try await store.saveRoutine(Routine(id: "r2", name: "Jalón", createdTs: 0, updatedTs: 0),
                                    exercises: [])

        // r1, session 1 (oldest): a measured work set, a warmup (excluded), and a not-done set (excluded).
        try await store.saveSession(StrengthSession(id: "s1", routineId: "r1", startTs: 1000), sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001, restTakenS: 90),
            SetEntry(id: "aw", sessionId: "s1", exerciseId: "bench", position: 1, kind: .warmup,
                     weightKg: 30, reps: 10, done: true, ts: 1001, restTakenS: 30),
            SetEntry(id: "and", sessionId: "s1", exerciseId: "bench", position: 2, kind: .work,
                     weightKg: 60, reps: 8, done: false, ts: 1001, restTakenS: 999),
        ])
        // r1, session 2: a work set with no measured rest (NULL, excluded) + one measured.
        try await store.saveSession(StrengthSession(id: "s2", routineId: "r1", startTs: 2000), sets: [
            SetEntry(id: "b", sessionId: "s2", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 2001, restTakenS: nil),
            SetEntry(id: "c", sessionId: "s2", exerciseId: "bench", position: 1, kind: .work,
                     weightKg: 60, reps: 6, done: true, ts: 2002, restTakenS: 110),
        ])
        // r1, session 3 (newest): one measured work set.
        try await store.saveSession(StrengthSession(id: "s3", routineId: "r1", startTs: 3000), sets: [
            SetEntry(id: "d", sessionId: "s3", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 3001, restTakenS: 100),
        ])
        // r2 (a different routine): must never show up in r1's results.
        try await store.saveSession(StrengthSession(id: "s4", routineId: "r2", startTs: 4000), sets: [
            SetEntry(id: "e", sessionId: "s4", exerciseId: "row", position: 0, kind: .work,
                     weightKg: 40, reps: 10, done: true, ts: 4001, restTakenS: 60),
        ])

        // Unbounded: every qualifying set from r1's 3 sessions, excluding s1's warmup/not-done and
        // s2's NULL — never r2's.
        let all = try await store.realRestSeconds(routineId: "r1", sessionLimit: 10)
        XCTAssertEqual(Set(all), [90, 110, 100])

        // LIMIT is by SESSION count, not row count: sessionLimit 2 keeps only s2 and s3 (the two
        // newest sessions), dropping s1's 90 entirely even though s1 alone has fewer rows than 2.
        let limited = try await store.realRestSeconds(routineId: "r1", sessionLimit: 2)
        XCTAssertEqual(Set(limited), [110, 100])
        XCTAssertFalse(limited.contains(90), "the oldest session falls outside the session-count limit")
    }

    // MARK: - Exercise notes (FER-932)

    /// Notes round-trip through save → read at both scopes: exercise-wide (`setPosition` nil) and
    /// one-set (`setPosition` non-nil). A re-save is idempotent (delete-first, no duplicates).
    func testExerciseNoteRoundTripBothScopes() async throws {
        let store = try await CenitStore.inMemory()
        let session = StrengthSession(id: "s1", startTs: 1000)
        let sets = [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001)
        ]
        let notes = [
            ExerciseNote(id: "n1", sessionId: "s1", exerciseId: "bench", setPosition: nil,
                        text: "Buena técnica hoy", ts: 1001),
            ExerciseNote(id: "n2", sessionId: "s1", exerciseId: "bench", setPosition: 0,
                        text: "Falló al final de esta serie", ts: 1002)
        ]
        try await store.saveSession(session, sets: sets, notes: notes)

        let back = try await store.sessionNotes(sessionId: "s1")
        XCTAssertEqual(back.count, 2)
        XCTAssertNil(back.first { $0.id == "n1" }?.setPosition, "exercise-scope note has no setPosition")
        XCTAssertEqual(back.first { $0.id == "n2" }?.setPosition, 0, "set-scope note keeps its position")

        // Re-saving the same session with the same notes must not duplicate rows (delete-first).
        try await store.saveSession(session, sets: sets, notes: notes)
        let backAgain = try await store.sessionNotes(sessionId: "s1")
        XCTAssertEqual(backAgain.count, 2, "re-save must be idempotent, not append duplicates")
    }

    /// Empty-text notes are dropped on save (never persisted as blank rows).
    func testExerciseNoteEmptyTextNotSaved() async throws {
        let store = try await CenitStore.inMemory()
        let session = StrengthSession(id: "s1", startTs: 1000)
        try await store.saveSession(session, sets: [], notes: [
            ExerciseNote(id: "n1", sessionId: "s1", exerciseId: "bench", text: "   ", ts: 1001)
        ])
        let back = try await store.sessionNotes(sessionId: "s1")
        XCTAssertTrue(back.isEmpty, "blank/whitespace-only note text must not be persisted")
    }

    /// «NOTAS ANTERIORES»: `exerciseNotes(excludingSession:)` returns prior sessions' notes for the same
    /// exercise, newest session first, and excludes the session currently being edited.
    func testExerciseNotesHistoryExcludesCurrentSessionOrderedNewestFirst() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [], notes: [
            ExerciseNote(id: "n1", sessionId: "s1", exerciseId: "bench", text: "Primera nota", ts: 1000)
        ])
        try await store.saveSession(StrengthSession(id: "s2", startTs: 2000), sets: [], notes: [
            ExerciseNote(id: "n2", sessionId: "s2", exerciseId: "bench", text: "Segunda nota", ts: 2000)
        ])
        try await store.saveSession(StrengthSession(id: "s3", startTs: 3000), sets: [], notes: [
            ExerciseNote(id: "n3", sessionId: "s3", exerciseId: "bench", text: "Nota de hoy", ts: 3000)
        ])

        let history = try await store.exerciseNotes(exerciseId: "bench", excludingSession: "s3")
        XCTAssertEqual(history.map(\.id), ["n2", "n1"], "excludes the current session, newest first")
    }

    /// Deleting a session cascades to its exercise notes.
    func testDeleteSessionCascadesExerciseNotes() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [], notes: [
            ExerciseNote(id: "n1", sessionId: "s1", exerciseId: "bench", text: "Nota", ts: 1000)
        ])
        try await store.deleteSession(id: "s1")
        let back = try await store.sessionNotes(sessionId: "s1")
        XCTAssertTrue(back.isEmpty, "deleteSession must cascade-delete its exercise notes")
    }

    // MARK: - Delete session + PR recompute (FER-527)

    /// Two bench sessions: s1 holds the 62.5 kg PR, s2 a lighter 50 kg. Deleting s1 drops the maxWeight PR
    /// to 50 (the second-best from what remains); deleting s2 too removes the PR entirely. The deleted
    /// session's sets are gone, the surviving session's sets intact.
    private func twoSessions(_ store: CenitStore) async throws {
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 62.5, reps: 8, done: true, ts: 1002)])
        try await store.saveSession(StrengthSession(id: "s2", startTs: 2000), sets: [
            SetEntry(id: "d", sessionId: "s2", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 50, reps: 5, done: true, ts: 2001)])
    }

    func testDeleteSessionRemovesItAndItsSets() async throws {
        let store = try await CenitStore.inMemory()
        try await twoSessions(store)
        try await store.deleteSession(id: "s1")
        let sessions = try await store.recentSessions()
        XCTAssertEqual(sessions.map(\.id), ["s2"])
        let deletedSets = try await store.setEntries(sessionId: "s1")
        XCTAssertTrue(deletedSets.isEmpty)
        let keptSets = try await store.setEntries(sessionId: "s2")
        XCTAssertEqual(keptSets.count, 1, "the other session's sets are untouched")
    }

    func testDeleteSessionDropsPRToSecondBest() async throws {
        let store = try await CenitStore.inMemory()
        try await twoSessions(store)
        var pr = try await store.personalRecords(exerciseId: "bench").first { $0.metric == .maxWeight }
        XCTAssertEqual(pr?.valueKg, 62.5)
        try await store.deleteSession(id: "s1")          // remove the session with the record
        pr = try await store.personalRecords(exerciseId: "bench").first { $0.metric == .maxWeight }
        XCTAssertEqual(pr?.valueKg, 50, "the record drops to the best of what remains")
    }

    func testDeleteOnlySessionRemovesPR() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [
            SetEntry(id: "b", sessionId: "s1", exerciseId: "squat", position: 0, kind: .work,
                     weightKg: 100, reps: 5, done: true, ts: 1002)])
        let before = try await store.personalRecords(exerciseId: "squat")
        XCTAssertFalse(before.isEmpty)
        try await store.deleteSession(id: "s1")
        let after = try await store.personalRecords(exerciseId: "squat")
        XCTAssertTrue(after.isEmpty, "no sessions left → the PR is removed, not left orphaned")
    }

    /// «Undo» = re-save the session; its PR comes back (saveSession re-derives records).
    func testUndoRestoresSessionAndPR() async throws {
        let store = try await CenitStore.inMemory()
        try await twoSessions(store)
        let restored = StrengthSession(id: "s1", startTs: 1000)
        let restoredSets = [SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                                     weightKg: 62.5, reps: 8, done: true, ts: 1002)]
        try await store.deleteSession(id: "s1")
        try await store.saveSession(restored, sets: restoredSets)   // undo
        let sessions = try await store.recentSessions().map(\.id).sorted()
        XCTAssertEqual(sessions, ["s1", "s2"])
        let pr = try await store.personalRecords(exerciseId: "bench").first { $0.metric == .maxWeight }
        XCTAssertEqual(pr?.valueKg, 62.5, "the record returns with the restored session")
    }

    /// After a delete-recompute, a surviving heavy WARM-UP set must not become the record — only work
    /// sets count (FER-527).
    func testRecomputeIgnoresWarmupSets() async throws {
        let store = try await CenitStore.inMemory()
        // s1: the record-holding work set (62.5). s2: a heavy warm-up (100) + a light work set (40).
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 62.5, reps: 8, done: true, ts: 1002)])
        try await store.saveSession(StrengthSession(id: "s2", startTs: 2000), sets: [
            SetEntry(id: "w", sessionId: "s2", exerciseId: "bench", position: 0, kind: .warmup,
                     weightKg: 100, reps: 3, done: true, ts: 2001),
            SetEntry(id: "d", sessionId: "s2", exerciseId: "bench", position: 1, kind: .work,
                     weightKg: 40, reps: 6, done: true, ts: 2002)])
        try await store.deleteSession(id: "s1")
        let pr = try await store.personalRecords(exerciseId: "bench").first { $0.metric == .maxWeight }
        XCTAssertEqual(pr?.valueKg, 40, "the 100 kg warm-up is ignored; the record is the remaining work set")
    }

    // MARK: - Edit session + exact PR recompute (FER-556)

    /// Lowering a set's weight in an edit must DROP the maxWeight PR (unlike a plain re-save, which only
    /// upgrades). Here the 62.5 kg record is corrected down to 55 kg → the PR follows down to 55.
    func testEditLoweringWeightDropsPR() async throws {
        let store = try await CenitStore.inMemory()
        let session = StrengthSession(id: "s1", startTs: 1000)
        try await store.saveSession(session, sets: [
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 62.5, reps: 8, done: true, ts: 1002)])
        let before = try await store.personalRecords(exerciseId: "bench").first { $0.metric == .maxWeight }
        XCTAssertEqual(before?.valueKg, 62.5)

        try await store.updateSession(session, sets: [
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 55, reps: 8, done: true, ts: 1002)])   // corrected down
        let after = try await store.personalRecords(exerciseId: "bench").first { $0.metric == .maxWeight }
        XCTAssertEqual(after?.valueKg, 55,
                       "editing a record down must lower the PR, not keep the stale higher one")
    }

    /// Reassigning a set to a different exercise must recompute BOTH exercises' PRs: the old one loses its
    /// record (no sets left → removed), the new one gains it.
    func testEditReassigningExerciseMovesPR() async throws {
        let store = try await CenitStore.inMemory()
        let session = StrengthSession(id: "s1", startTs: 1000)
        try await store.saveSession(session, sets: [
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 80, reps: 5, done: true, ts: 1002)])
        let benchBefore = try await store.personalRecords(exerciseId: "bench")
        XCTAssertFalse(benchBefore.isEmpty)

        // Same set id, reassigned from bench → incline.
        try await store.updateSession(session, sets: [
            SetEntry(id: "b", sessionId: "s1", exerciseId: "incline", position: 0, kind: .work,
                     weightKg: 80, reps: 5, done: true, ts: 1002)])

        let benchAfter = try await store.personalRecords(exerciseId: "bench")
        XCTAssertTrue(benchAfter.isEmpty,
                      "the old exercise loses its record when its only set is reassigned away")
        let inclinePR = try await store.personalRecords(exerciseId: "incline").first { $0.metric == .maxWeight }
        XCTAssertEqual(inclinePR?.valueKg, 80, "the new exercise gains the record")
    }

    /// Editing the date moves `startTs` (which `saveSession`'s upsert deliberately does NOT touch), and
    /// never alters the strap's captured `strain`/`avgHr` — those ride through unchanged.
    func testEditMovesDateAndPreservesCapturedHR() async throws {
        let store = try await CenitStore.inMemory()
        let original = StrengthSession(id: "s1", startTs: 1000, endTs: 4000,
                                       deviceId: "whoop", strain: 12.4, avgHr: 128)
        try await store.saveSession(original, sets: [
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1002)])

        // Shift the day forward by 1h, preserving duration; sets unchanged.
        var moved = original
        moved.startTs = 4600; moved.endTs = 7600
        try await store.updateSession(moved, sets: [
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1002)])

        let back = try await store.recentSessions().first { $0.id == "s1" }
        XCTAssertEqual(back?.startTs, 4600, "the edited start time persists")
        XCTAssertEqual(back?.endTs, 7600)
        XCTAssertEqual(back?.strain, 12.4, "captured strain is untouched by an edit")
        XCTAssertEqual(back?.avgHr, 128, "captured HR is untouched by an edit")
    }

    /// Removing a set in an edit deletes its row (no orphan) and the other session is never touched.
    func testEditRemovingSetDeletesRow() async throws {
        let store = try await CenitStore.inMemory()
        let session = StrengthSession(id: "s1", startTs: 1000)
        try await store.saveSession(session, sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001),
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 1, kind: .work,
                     weightKg: 62.5, reps: 6, done: true, ts: 1002)])

        try await store.updateSession(session, sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001)])   // dropped set "b"

        let back = try await store.setEntries(sessionId: "s1")
        XCTAssertEqual(back.map(\.id), ["a"], "the removed set leaves no orphan row")
        let pr = try await store.personalRecords(exerciseId: "bench").first { $0.metric == .maxWeight }
        XCTAssertEqual(pr?.valueKg, 60, "the PR recomputes to the best of what remains")
    }

    func testCustomExerciseRoundTrip() async throws {
        let store = try await CenitStore.inMemory()
        let e = Exercise(id: "ex-1", name: "Jalón neutro", type: .weightReps, equipment: "cable",
                         primaryMuscles: ["lats"], secondaryMuscles: ["biceps"],
                         instructions: ["Baja controlado", "Codos pegados"])
        try await store.saveCustomExercise(e)
        let all = try await store.customExercises()
        XCTAssertEqual(all, [e])  // arrays + enum round-trip via JSON
        try await store.deleteCustomExercise(id: "ex-1")
        let empty = try await store.customExercises()
        XCTAssertTrue(empty.isEmpty)
    }

    /// `workSetHistory` joins setEntry × strengthSession: carries each work set's SESSION start time,
    /// oldest→newest, and excludes warm-ups and sets missing weight/reps (1RM needs both).
    func testWorkSetHistoryJoinsSessionStart() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .warmup,
                     weightKg: 24, reps: 10, done: true, ts: 1001),                 // warm-up → excluded
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 1, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1002),
        ])
        try await store.saveSession(StrengthSession(id: "s2", startTs: 2000), sets: [
            SetEntry(id: "c", sessionId: "s2", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 65, reps: 5, done: true, ts: 2001),
            SetEntry(id: "d", sessionId: "s2", exerciseId: "bench", position: 1, kind: .work,
                     reps: 5, done: true, ts: 2002),                                // no weight → excluded
        ])
        let hist = try await store.workSetHistory(exerciseId: "bench")
        XCTAssertEqual(hist.map(\.startTs), [1000, 2000])     // session start, oldest→newest
        XCTAssertEqual(hist.map(\.weightKg), [60, 65])        // warm-up + weightless set dropped
        XCTAssertEqual(hist.map(\.optedOut), [false, false], "no «Volver a X» → no opt-out marks")
        XCTAssertEqual(hist.map(\.sessionId), ["s1", "s2"])
        XCTAssertNil(hist[0].routineName, "free session → no routine")
        XCTAssertNil(hist[0].rpe, "no rpe captured on this set")
    }

    /// FER-147: `rpe` (v34) rides along per set (nil when never captured), and `routineName` comes
    /// from a LEFT JOIN on `routine` — populated for a session logged against a routine, nil for a
    /// free session.
    func testWorkSetHistoryCarriesRPEAndRoutineName() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveRoutine(Routine(id: "r1", name: "Pierna A", createdTs: 0, updatedTs: 0),
                                    exercises: [])
        try await store.saveSession(StrengthSession(id: "s1", routineId: "r1", startTs: 1000), sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001, rpe: 8),
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 1, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1002),               // no rpe captured
        ])
        try await store.saveSession(StrengthSession(id: "s2", startTs: 2000), sets: [
            SetEntry(id: "c", sessionId: "s2", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 65, reps: 5, done: true, ts: 2001),
        ])
        let hist = try await store.workSetHistory(exerciseId: "bench")
        XCTAssertEqual(hist.map(\.rpe), [8, nil, nil])
        XCTAssertEqual(hist.filter { $0.sessionId == "s1" }.map(\.routineName), ["Pierna A", "Pierna A"])
        XCTAssertNil(hist.first { $0.sessionId == "s2" }?.routineName, "free session → nil")
    }

    /// FER-147: a session whose routine was later deleted keeps its history row — `routineName` reads
    /// nil (LEFT JOIN, no crash, no lost row), not a dangling id.
    func testWorkSetHistorySurvivesDeletedRoutine() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveRoutine(Routine(id: "r1", name: "Pierna A", createdTs: 0, updatedTs: 0),
                                    exercises: [])
        try await store.saveSession(StrengthSession(id: "s1", routineId: "r1", startTs: 1000), sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001),
        ])
        try await store.deleteRoutine(id: "r1")
        let hist = try await store.workSetHistory(exerciseId: "bench")
        XCTAssertEqual(hist.count, 1, "the session's history row is not lost")
        XCTAssertNil(hist[0].routineName, "the deleted routine's name reads nil, not a crash")
    }

    /// FER-147: the LIMIT keeps the MOST RECENT sets. A stale `ORDER BY startTs ASC LIMIT ?` would
    /// keep the 600 OLDEST and drop the newest — exactly backwards for a trend the user wants to see
    /// up to today. 601 sets, one per session: the oldest (ts 0) must fall off, the newest (ts 600)
    /// must survive, and the result still reads oldest→newest.
    func testWorkSetHistoryLimitKeepsMostRecent() async throws {
        let store = try await CenitStore.inMemory()
        for i in 0..<601 {
            try await store.saveSession(StrengthSession(id: "s\(i)", startTs: i), sets: [
                SetEntry(id: "e\(i)", sessionId: "s\(i)", exerciseId: "bench", position: 0, kind: .work,
                         weightKg: 60, reps: 8, done: true, ts: i),
            ])
        }
        let hist = try await store.workSetHistory(exerciseId: "bench", limit: 600)
        XCTAssertEqual(hist.count, 600)
        XCTAssertEqual(hist.first?.startTs, 1, "the oldest set (ts 0) fell off the cap")
        XCTAssertEqual(hist.last?.startTs, 600, "the newest set survives")
        XCTAssertEqual(hist.map(\.startTs), hist.map(\.startTs).sorted(), "still oldest→newest")
    }

    /// FER-835: the «Volver a X» opt-out persists per (session, exercise), surfaces only on that
    /// exercise's history rows, a re-save without it clears it (idempotent, like setEntry), and
    /// deleting the session leaves no orphan rows.
    func testProgressionOptOutPersistsPerSessionExercise() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001),
            SetEntry(id: "b", sessionId: "s1", exerciseId: "squat", position: 1, kind: .work,
                     weightKg: 100, reps: 5, done: true, ts: 1002),
        ], progressionOptOuts: ["bench"])

        let bench = try await store.workSetHistory(exerciseId: "bench")
        XCTAssertEqual(bench.map(\.optedOut), [true], "the reverted exercise's session is marked")
        let squat = try await store.workSetHistory(exerciseId: "squat")
        XCTAssertEqual(squat.map(\.optedOut), [false], "the mark is per exercise, not per session")

        // Re-save without the opt-out (an edit/duplicate-end path) replaces the session's rows.
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 60, reps: 8, done: true, ts: 1001),
        ])
        let cleared = try await store.workSetHistory(exerciseId: "bench")
        XCTAssertEqual(cleared.map(\.optedOut), [false], "re-save replaces the session's opt-out rows")

        // Delete leaves no orphan opt-out rows.
        try await store.saveSession(StrengthSession(id: "s2", startTs: 2000), sets: [
            SetEntry(id: "c", sessionId: "s2", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 62.5, reps: 8, done: true, ts: 2001),
        ], progressionOptOuts: ["bench"])
        try await store.deleteSession(id: "s2")
        let orphans = try await store.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM progressionOptOut") ?? 0
        }
        XCTAssertEqual(orphans, 0, "deleteSession removes the session's opt-out rows")
    }

    // MARK: - Live-session HR capture (FER-226)

    /// `appendStrengthHR` is idempotent by its (sessionId, ts) primary key: a fresh batch of three
    /// distinct timestamps all insert (returns 3); re-flushing the SAME batch (e.g. a retry after a
    /// write that actually succeeded but whose caller didn't know) inserts nothing (returns 0), and the
    /// stored row count stays at 3 — not 6.
    ///
    /// Note: the spec's illustrative example re-used ts=10 twice in ONE batch, which would collide with
    /// itself against the real (sessionId, ts) PK rather than demonstrate cross-flush idempotency. This
    /// test uses three distinct timestamps in the first flush (so all three land) and repeats that exact
    /// batch in the second flush (so all three collide) — the behavior the criterion is actually after.
    func testAppendStrengthHRIsIdempotentByPrimaryKey() async throws {
        let store = try await CenitStore.inMemory()
        let samples = [HRSample(ts: 10, bpm: 120), HRSample(ts: 11, bpm: 121), HRSample(ts: 12, bpm: 122)]
        let firstInsert = try await store.appendStrengthHR(sessionId: "s1", samples: samples)
        XCTAssertEqual(firstInsert, 3, "all three distinct timestamps insert on the first flush")

        let retryInsert = try await store.appendStrengthHR(sessionId: "s1", samples: samples)
        XCTAssertEqual(retryInsert, 0, "re-flushing the identical batch collides on the PK — no dupes")

        let stored = try await store.strengthHRSamples(sessionId: "s1")
        XCTAssertEqual(stored, samples, "exactly 3 rows stored, in ts order — not 6")
    }

    func testStrengthHRSamplesOrderedByTsAscending() async throws {
        let store = try await CenitStore.inMemory()
        try await store.appendStrengthHR(sessionId: "s1", samples: [
            HRSample(ts: 30, bpm: 140), HRSample(ts: 10, bpm: 120), HRSample(ts: 20, bpm: 130),
        ])
        let stored = try await store.strengthHRSamples(sessionId: "s1")
        XCTAssertEqual(stored.map(\.ts), [10, 20, 30])
    }

    func testDeleteStrengthHRRemovesOnlyThatSession() async throws {
        let store = try await CenitStore.inMemory()
        try await store.appendStrengthHR(sessionId: "s1", samples: [HRSample(ts: 1, bpm: 100)])
        try await store.appendStrengthHR(sessionId: "s2", samples: [HRSample(ts: 1, bpm: 110)])
        try await store.deleteStrengthHR(sessionId: "s1")
        let s1 = try await store.strengthHRSamples(sessionId: "s1")
        let s2 = try await store.strengthHRSamples(sessionId: "s2")
        XCTAssertTrue(s1.isEmpty)
        XCTAssertEqual(s2, [HRSample(ts: 1, bpm: 110)], "another session's samples are untouched")
    }

    /// `deleteSession` (the full session-discard path) also clears `strengthHrSample` for that session,
    /// leaving another session's HR rows intact — same contract as its other per-session cascades.
    func testDeleteSessionCascadesHRSamples() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [])
        try await store.saveSession(StrengthSession(id: "s2", startTs: 2000), sets: [])
        try await store.appendStrengthHR(sessionId: "s1", samples: [HRSample(ts: 1, bpm: 100)])
        try await store.appendStrengthHR(sessionId: "s2", samples: [HRSample(ts: 1, bpm: 110)])

        try await store.deleteSession(id: "s1")

        let s1 = try await store.strengthHRSamples(sessionId: "s1")
        let s2 = try await store.strengthHRSamples(sessionId: "s2")
        XCTAssertTrue(s1.isEmpty, "deleteSession must cascade-delete its HR samples")
        XCTAssertEqual(s2, [HRSample(ts: 1, bpm: 110)], "another session's HR samples survive")
    }
    // MARK: - Ola 1 · FER-327 — el drop no alimenta progresión, semilla, récords ni 1RM

    /// `workSetHistory` (progresión + 1RM) NO ve los drops: solo las series de trabajo al peso de
    /// trabajo. Si los viera, el ciclo leería una bajada de peso que nadie decidió.
    func testWorkSetHistoryExcludesDrop() async throws {
        let store = try await CenitStore.inMemory()
        let sets = [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0,
                     weightKg: 80, reps: 8, done: true, ts: 1100),
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 1,
                     weightKg: 64, reps: 12, done: true, ts: 1200, mode: .drop),
            SetEntry(id: "c", sessionId: "s1", exerciseId: "bench", position: 2,
                     weightKg: 80, reps: 11, done: true, ts: 1300, mode: .amrap),
        ]
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: sets)

        let history = try await store.workSetHistory(exerciseId: "bench")
        XCTAssertEqual(history.map(\.weightKg), [80, 80], "el drop de 64 kg no entra a la historia")
        XCTAssertEqual(history.map(\.reps), [8, 11])
        XCTAssertEqual(Set(history.map(\.mode)), [SetMode.standard, .amrap],
                       "el AMRAP sí entra, y se proyecta con su modo")
    }

    /// «La última vez» tampoco ve los drops: la próxima sesión abre al peso de TRABAJO, no al −20 %.
    func testLastWorkSetsSkipDrop() async throws {
        let store = try await CenitStore.inMemory()
        let sets = [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0,
                     weightKg: 80, reps: 8, done: true, ts: 1100),
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 1,
                     weightKg: 64, reps: 12, done: true, ts: 1200, mode: .drop),
        ]
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: sets)

        let last = try await store.lastWorkSets(exerciseId: "bench")
        XCTAssertEqual(last.map(\.id), ["a"])
        XCTAssertEqual(last.first?.weightKg, 80, "la semilla es el peso de trabajo, no el escalón")
    }

    /// Un drop MÁS PESADO que el récord vigente no lo mueve — ni al guardar (`updatePersonalRecords`)
    /// ni al recomputar tras un borrado (`recomputePR`). El drop movió kilos reales (suma volumen),
    /// pero no es una marca al peso de trabajo.
    func testPRsIgnoreDropHeavierThanRecord() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0,
                     weightKg: 80, reps: 8, done: true, ts: 1100),
        ])
        // Un drop de 100 kg (dato absurdo a propósito: si el modo no se leyera, sería récord nuevo).
        try await store.saveSession(StrengthSession(id: "s2", startTs: 2000), sets: [
            SetEntry(id: "b", sessionId: "s2", exerciseId: "bench", position: 0,
                     weightKg: 85, reps: 8, done: true, ts: 2100),
            SetEntry(id: "c", sessionId: "s2", exerciseId: "bench", position: 1,
                     weightKg: 100, reps: 20, done: true, ts: 2200, mode: .drop),
        ])

        let prs = try await store.personalRecords(exerciseId: "bench")
        XCTAssertEqual(prs.first(where: { $0.metric == .maxWeight })?.valueKg, 85)
        XCTAssertEqual(prs.first(where: { $0.metric == .maxReps })?.reps, 8, "20 reps de un drop no es marca")
        XCTAssertEqual(prs.first(where: { $0.metric == .maxVolume })?.valueKg, 85)

        // El camino de recomputar (borrar otra sesión) llega a la misma respuesta.
        try await store.deleteSession(id: "s1")
        let after = try await store.personalRecords(exerciseId: "bench")
        XCTAssertEqual(after.first(where: { $0.metric == .maxWeight })?.valueKg, 85)
        XCTAssertEqual(after.first(where: { $0.metric == .maxReps })?.reps, 8)
    }

    /// v3 · N4: un drop sin madre (la serie de la que colgaba se borró) NO se promueve a serie de
    /// trabajo. Conserva `mode = .drop`, se queda en su lugar y nada se borra.
    func testAdjacencyInvariantKeepsOrphanAsDrop() async throws {
        let store = try await CenitStore.inMemory()
        let sets = [
            SetEntry(id: "huerfano", sessionId: "s1", exerciseId: "bench", position: 0,
                     weightKg: 64, reps: 12, done: true, ts: 1100, mode: .drop),
            SetEntry(id: "trabajo", sessionId: "s1", exerciseId: "bench", position: 1,
                     weightKg: 80, reps: 8, done: true, ts: 1200),
        ]
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: sets)

        let back = try await store.setEntries(sessionId: "s1")
        XCTAssertEqual(back.map(\.id), ["huerfano", "trabajo"], "nada se borra ni se reordena")
        XCTAssertEqual(back.first?.mode, .drop, "el huérfano NUNCA se promueve a serie de trabajo")
        // Y sigue fuera de la progresión y de los récords: solo cuenta para volumen.
        let history = try await store.workSetHistory(exerciseId: "bench")
        XCTAssertEqual(history.map(\.weightKg), [80])
        let prs = try await store.personalRecords(exerciseId: "bench")
        XCTAssertEqual(prs.first(where: { $0.metric == .maxReps })?.reps, 8)
    }

    /// La relación drop→madre es el ORDEN (sin FK), así que al guardar el store la vuelve verdad: un
    /// drop separado de su madre por una serie de OTRO ejercicio se pega de vuelta a ella, con los
    /// escalones en su orden y las posiciones renumeradas.
    func testReorderMovesDropsWithMother() async throws {
        let store = try await CenitStore.inMemory()
        let sets = [
            SetEntry(id: "madre", sessionId: "s1", exerciseId: "bench", position: 0,
                     weightKg: 80, reps: 8, done: true, ts: 1100),
            SetEntry(id: "otro", sessionId: "s1", exerciseId: "row", position: 1,
                     weightKg: 60, reps: 10, done: true, ts: 1200),
            SetEntry(id: "drop1", sessionId: "s1", exerciseId: "bench", position: 2,
                     weightKg: 64, reps: 10, done: true, ts: 1300, mode: .drop),
            SetEntry(id: "drop2", sessionId: "s1", exerciseId: "bench", position: 3,
                     weightKg: 50, reps: 8, done: true, ts: 1400, mode: .drop),
        ]
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: sets)

        let back = try await store.setEntries(sessionId: "s1")
        XCTAssertEqual(back.map(\.id), ["madre", "drop1", "drop2", "otro"],
                       "los escalones viajan con su madre, en orden")
        XCTAssertEqual(back.map(\.position), [0, 1, 2, 3], "posiciones renumeradas 0…n−1")
    }

    /// La invariante es IDENTIDAD para toda sesión sin drops (o sea, todo lo grabado antes de ola 1):
    /// mismo orden, mismas posiciones, ni una fila movida.
    func testAdjacencyInvariantIsIdentityWithoutDrops() async throws {
        let store = try await CenitStore.inMemory()
        let sets = [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .warmup,
                     weightKg: 40, reps: 10, done: true, ts: 1100),
            SetEntry(id: "b", sessionId: "s1", exerciseId: "row", position: 7,
                     weightKg: 60, reps: 10, done: true, ts: 1200),
            SetEntry(id: "c", sessionId: "s1", exerciseId: "bench", position: 9,
                     weightKg: 80, reps: 8, done: true, ts: 1300),
        ]
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: sets)

        let back = try await store.setEntries(sessionId: "s1")
        XCTAssertEqual(back.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(back.map(\.position), [0, 7, 9], "sin drops no se renumera nada")
    }

    /// El drop SÍ suma volumen: es trabajo real, aunque no sea una marca ni gate del ciclo.
    func testDropStillCountsTowardVolume() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [
            SetEntry(id: "a", sessionId: "s1", exerciseId: "bench", position: 0,
                     weightKg: 80, reps: 8, done: true, ts: 1100),
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 1,
                     weightKg: 64, reps: 10, done: true, ts: 1200, mode: .drop),
        ])
        let volumes = try await store.sessionVolumes()
        XCTAssertEqual(volumes["s1"]?.volumeKg, 80 * 8 + 64 * 10)
        XCTAssertEqual(volumes["s1"]?.setCount, 2)

    // MARK: - Ola 1 · E2 · provenance + session-effort calibration

    /// The v42 provenance columns are written and read back as one piece — a session whose load came
    /// from the rating must never come back looking measured.
    func testSessionRoundTripsProvenanceColumns() async throws {
        let store = try await CenitStore.inMemory()
        let estimated = StrengthSession(id: "s1", startTs: 1000, endTs: 4120, strain: 10.95,
                                        strainSource: .rpe, sessionRpe: 8,
                                        sessionRpeSource: .prefill, trimpPerAU: 0.29)
        let measured = StrengthSession(id: "s2", startTs: 9000, endTs: 12000, strain: 9.2,
                                       strainSource: .hr, sessionRpe: 7, sessionRpeSource: .answered)
        try await store.saveSession(estimated, sets: [])
        try await store.saveSession(measured, sets: [])

        let back = try await store.recentSessions(limit: 10)
        let s1 = back.first { $0.id == "s1" }!
        XCTAssertEqual(s1.strainSource, .rpe)
        XCTAssertEqual(s1.sessionRpe, 8)
        XCTAssertEqual(s1.sessionRpeSource, .prefill)
        XCTAssertEqual(s1.trimpPerAU!, 0.29, accuracy: 1e-9)
        let s2 = back.first { $0.id == "s2" }!
        XCTAssertEqual(s2.strainSource, .hr)
        XCTAssertEqual(s2.sessionRpeSource, .answered)
        XCTAssertNil(s2.trimpPerAU)
    }

    /// A calibration pair needs BOTH halves: a rating and a pulse. Sessions missing either can never
    /// form one, so they don't even leave SQL; the 0.8-coverage gate is the caller's, over the
    /// samples returned here.
    func testCalibrationPairsRequireCoverageAndRpe() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveSession(StrengthSession(id: "ok", startTs: 1000, endTs: 4000,
                                                    strain: 10.9, strainSource: .rpe, sessionRpe: 8),
                                    sets: [])
        try await store.saveSession(StrengthSession(id: "noRpe", startTs: 5000, endTs: 8000,
                                                    strain: 9.2, strainSource: .hr), sets: [])
        try await store.saveSession(StrengthSession(id: "noHR", startTs: 9000, endTs: 12000,
                                                    strain: 10.0, strainSource: .rpe, sessionRpe: 9),
                                    sets: [])
        try await store.saveSession(StrengthSession(id: "open", startTs: 13000, sessionRpe: 9), sets: [])
        let pulse = (0...600).map { HRSample(ts: 1000 + $0, bpm: 130) }
        try await store.appendStrengthHR(sessionId: "ok", samples: pulse)
        try await store.appendStrengthHR(sessionId: "noRpe", samples: pulse)
        try await store.appendStrengthHR(sessionId: "open", samples: pulse)

        let pairs = try await store.strengthCalibrationPairs()
        XCTAssertEqual(pairs.map(\.sessionId), ["ok"])
        XCTAssertEqual(pairs[0].sessionRpe, 8)
        XCTAssertEqual(pairs[0].hrSamples.count, pulse.count, "the pulse rides along for the coverage gate")
        XCTAssertEqual(pairs[0].endTs - pairs[0].startTs, 3000)
    }

    /// A recalibration rewrites the ESTIMATED sessions onto the new scale, in one write. A measured
    /// session is a measurement: it never moves.
    func testRecomputeEstimatedStrainRewritesOnlyRpeSessions() async throws {
        let store = try await CenitStore.inMemory()
        try await store.saveSession(StrengthSession(id: "est", startTs: 0, endTs: 3000, strain: 10.9,
                                                    strainSource: .rpe, sessionRpe: 8,
                                                    trimpPerAU: 0.29), sets: [])
        try await store.saveSession(StrengthSession(id: "meas", startTs: 5000, endTs: 8000, strain: 9.2,
                                                    strainSource: .hr, sessionRpe: 8), sets: [])
        try await store.saveSession(StrengthSession(id: "legacy", startTs: 9000, endTs: 12000,
                                                    strain: 8.0), sets: [])

        let rewritten = try await store.recomputeEstimatedStrain(trimpPerAU: 0.20) { durationS, rpe in
            XCTAssertEqual(durationS, 3000)
            XCTAssertEqual(rpe, 8)
            return 9.5
        }
        XCTAssertEqual(rewritten, 1)

        let back = try await store.recentSessions(limit: 10)
        let est = back.first { $0.id == "est" }!
        XCTAssertEqual(est.strain!, 9.5, accuracy: 1e-9)
        XCTAssertEqual(est.trimpPerAU!, 0.20, accuracy: 1e-9)
        XCTAssertEqual(back.first { $0.id == "meas" }!.strain!, 9.2, accuracy: 1e-9)
        XCTAssertEqual(back.first { $0.id == "legacy" }!.strain!, 8.0, accuracy: 1e-9)
        XCTAssertNil(back.first { $0.id == "legacy" }!.trimpPerAU)
    }
}
