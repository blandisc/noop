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

    // MARK: - Reorder (FER-526)

    func reorderFolders(_ idsInOrder: [String]) async throws {
        guard let store = await storeHandle() else { return }
        try await store.reorderFolders(idsInOrder)
    }

    func reorderRoutines(_ idsInOrder: [String]) async throws {
        guard let store = await storeHandle() else { return }
        try await store.reorderRoutines(idsInOrder)
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

    // MARK: - Learned exercise aliases (import matching memory — FER-523)

    /// The user's learned import aliases (normalized name → exerciseId), for the import reconciler.
    func learnedExerciseAliases() async -> [String: String] {
        guard let store = await storeHandle() else { return [:] }
        return (try? await store.learnedExerciseAliases()) ?? [:]
    }

    /// Remember an import mapping so the same name resolves on its own next time.
    func saveLearnedExerciseAlias(name: String, exerciseId: String) async {
        guard let store = await storeHandle() else { return }
        try? await store.saveLearnedExerciseAlias(name: name, exerciseId: exerciseId,
                                                  ts: Int(Date().timeIntervalSince1970))
    }

    // MARK: - Sessions (the completed-workout history)

    /// Completed strength sessions, newest first — the «Mis entrenamientos» list (FER-504). Read-only.
    func recentSessions(limit: Int = 200) async -> [StrengthSession] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.recentSessions(limit: limit)) ?? []
    }

    /// The logged sets of one session, in position order — the per-session breakdown (FER-504).
    func sessionSets(sessionId: String) async -> [SetEntry] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.setEntries(sessionId: sessionId)) ?? []
    }

    /// Per-session work volume + completed-set count, keyed by session id — the numbers the history
    /// list shows per row (FER-504). One aggregate read in the store.
    func sessionVolumes() async -> [String: (volumeKg: Double, setCount: Int)] {
        guard let store = await storeHandle() else { return [:] }
        return (try? await store.sessionVolumes()) ?? [:]
    }

    /// Delete a completed session (+ its sets) and recompute the affected PRs (FER-527).
    func deleteSession(id: String) async throws {
        guard let store = await storeHandle() else { return }
        try await store.deleteSession(id: id)
    }

    /// Restore a session deleted by «Undo» — re-saving re-derives its PRs (FER-527).
    func saveSession(_ session: StrengthSession, sets: [SetEntry]) async throws {
        guard let store = await storeHandle() else { return }
        try await store.saveSession(session, sets: sets)
    }

    // MARK: - History (per exercise)

    /// Completed work sets for one exercise with their session start time, oldest→newest — the raw
    /// material the detail screen buckets by day into the estimated-1RM trend. One JOIN in the store.
    func exerciseHistory(exerciseId: String) async -> [(startTs: Int, weightKg: Double, reps: Int)] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.workSetHistory(exerciseId: exerciseId)) ?? []
    }

    /// Stored best-per-metric records for one exercise (maxWeight / maxReps / maxVolume) — the «Records
    /// personales» list (FER-505). Derived on save; read-only here.
    func personalRecords(exerciseId: String) async -> [PersonalRecord] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.personalRecords(exerciseId: exerciseId)) ?? []
    }

    /// Every completed work set since `sinceTs` (epoch seconds) with its exercise id and session start
    /// time — the raw material the muscle-fatigue map (FER-350) expands over `Exercise.muscleInvolvement`.
    func recentWorkSets(sinceTs: Int) async -> [(exerciseId: String, startTs: Int)] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.workSetsSince(sinceTs)) ?? []
    }
}
