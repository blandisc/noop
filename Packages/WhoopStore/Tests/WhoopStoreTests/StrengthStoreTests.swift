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
