import XCTest
@testable import WhoopStore
import StrandTraining

final class StrengthStoreTests: XCTestCase {

    func testV13CreatesStrengthTables() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        for t in ["customExercise", "routine", "routineExercise",
                  "strengthSession", "setEntry", "personalRecord"] {
            XCTAssertTrue(tables.contains(t), "missing table \(t)")
        }
    }

    /// Append-only: v13 leaves prior tables (v8 `workout`, v12 `experiment`) in place.
    func testV13PreservesPriorTables() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("workout"))
        XCTAssertTrue(tables.contains("experiment"))
    }

    /// FER-495: the per-exercise HR rest target round-trips; an unconfigured exercise reads back as the
    /// FER-348 default (`.restingMargin` / 0).
    func testHRRestConfigRoundTrip() async throws {
        let store = try await WhoopStore.inMemory()
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

    /// FER-540: editing rest mid-session pinpoint-updates one exercise's four rest fields and leaves its
    /// per-set prescription AND the other exercises untouched (unlike a full `saveRoutine` rewrite).
    func testUpdateRoutineExerciseRestPinpoint() async throws {
        let store = try await WhoopStore.inMemory()
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

    /// FER-541: the exercise type override round-trips, upserts (one row per id), and clears back to empty.
    func testExerciseTypeOverrideRoundTrip() async throws {
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
        try await store.saveFolder(RoutineFolder(id: "a", name: "A", sortOrder: 0))
        try await store.saveFolder(RoutineFolder(id: "b", name: "B", sortOrder: 1))
        try await store.saveFolder(RoutineFolder(id: "c", name: "C", sortOrder: 2))
        try await store.reorderFolders(["c", "a", "b"])
        let back = try await store.routineFolders()
        XCTAssertEqual(back.map(\.id), ["c", "a", "b"])
    }

    /// `reorderRoutines` persists the global order and never rewrites the routines' exercises/sets (FER-492).
    func testReorderRoutinesPersistsAndKeepsExercises() async throws {
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
        let r = Routine(id: "rt1", name: "Plantilla", createdTs: 0, updatedTs: 0)
        let re = RoutineExercise(id: "re1", routineId: "rt1", exerciseId: "bench", position: 0,
                                 targetSets: 4, targetReps: 10, targetWeightKg: 40)   // sets defaults to []
        try await store.saveRoutine(r, exercises: [re])
        let back = try await store.routineExercises(routineId: "rt1").first
        XCTAssertEqual(back?.sets.count, 4)
        XCTAssertTrue(back?.sets.allSatisfy { $0.reps == 10 && $0.weightKg == 40 } ?? false)
    }

    func testSessionSetsAndPR() async throws {
        let store = try await WhoopStore.inMemory()
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

    // MARK: - Delete session + PR recompute (FER-527)

    /// Two bench sessions: s1 holds the 62.5 kg PR, s2 a lighter 50 kg. Deleting s1 drops the maxWeight PR
    /// to 50 (the second-best from what remains); deleting s2 too removes the PR entirely. The deleted
    /// session's sets are gone, the surviving session's sets intact.
    private func twoSessions(_ store: WhoopStore) async throws {
        try await store.saveSession(StrengthSession(id: "s1", startTs: 1000), sets: [
            SetEntry(id: "b", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 62.5, reps: 8, done: true, ts: 1002)])
        try await store.saveSession(StrengthSession(id: "s2", startTs: 2000), sets: [
            SetEntry(id: "d", sessionId: "s2", exerciseId: "bench", position: 0, kind: .work,
                     weightKg: 50, reps: 5, done: true, ts: 2001)])
    }

    func testDeleteSessionRemovesItAndItsSets() async throws {
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
        try await twoSessions(store)
        var pr = try await store.personalRecords(exerciseId: "bench").first { $0.metric == .maxWeight }
        XCTAssertEqual(pr?.valueKg, 62.5)
        try await store.deleteSession(id: "s1")          // remove the session with the record
        pr = try await store.personalRecords(exerciseId: "bench").first { $0.metric == .maxWeight }
        XCTAssertEqual(pr?.valueKg, 50, "the record drops to the best of what remains")
    }

    func testDeleteOnlySessionRemovesPR() async throws {
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
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
        let store = try await WhoopStore.inMemory()
        let e = Exercise(id: "ex-1", name: "Jalón neutro", type: .weightReps, equipment: "cable",
                         primaryMuscles: ["lats"], secondaryMuscles: ["biceps"],
                         cues: ["Baja controlado", "Codos pegados"])
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
        let store = try await WhoopStore.inMemory()
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
    }
}
