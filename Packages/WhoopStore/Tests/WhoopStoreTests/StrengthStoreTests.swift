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
