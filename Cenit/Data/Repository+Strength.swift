import Foundation
import StrandTraining
import WhoopStore

// Repository+Strength.swift — read/write pass-throughs to the strength tracker (FER-346).
//
// Thin async wrappers over the `WhoopStore` strength API (FER-345), mirroring `Repository+Goal`:
// no logic here, just `storeHandle()` + a clean call. The strength screens (builder / library /
// detail) talk to the store only through these, so they never hold a `WhoopStore` of their own.
// All return empty/no-op when the store can't be opened (same contract as the rest of Repository).

extension Repository {

    // MARK: - Routines

    func routines() async -> [Routine] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.routines()) ?? []
    }

    func routineExercises(routineId: String) async -> [RoutineExercise] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.routineExercises(routineId: routineId)) ?? []
    }

    func saveRoutine(_ routine: Routine, exercises: [RoutineExercise]) async throws {
        guard let store = await storeHandle() else { return }
        try await store.saveRoutine(routine, exercises: exercises)
    }

    func deleteRoutine(id: String) async throws {
        guard let store = await storeHandle() else { return }
        try await store.deleteRoutine(id: id)
    }

    // MARK: - Exercises (bundled catalog + user-created)

    /// The full exercise list a library screen browses: the bundled seed catalog merged with the
    /// user's own exercises, sorted by name. The catalog is read-only; custom ones are editable.
    func allExercises() async -> [Exercise] {
        guard let store = await storeHandle() else { return ExerciseCatalog.all }
        let custom = (try? await store.customExercises()) ?? []
        return (ExerciseCatalog.all + custom).sorted { $0.name < $1.name }
    }

    func saveCustomExercise(_ e: Exercise) async throws {
        guard let store = await storeHandle() else { return }
        try await store.saveCustomExercise(e)
    }

    // MARK: - History (per exercise)

    /// Completed work sets for one exercise with their session start time, oldest→newest — the raw
    /// material the detail screen buckets by day into the estimated-1RM trend. One JOIN in the store.
    func exerciseHistory(exerciseId: String) async -> [(startTs: Int, weightKg: Double, reps: Int)] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.workSetHistory(exerciseId: exerciseId)) ?? []
    }
}
