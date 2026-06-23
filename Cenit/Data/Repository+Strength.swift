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

    /// Pinpoint-update one routine exercise's rest config (FER-540) — for editing rest mid-session
    /// without rewriting the whole routine. No-op when the store can't be opened.
    func updateRoutineExerciseRest(routineExerciseId reId: String, routineId: String,
                                   mode: RestMode, seconds: Int,
                                   reference: HRRestReference, value: Double) async {
        guard let store = await storeHandle() else { return }
        try? await store.updateRoutineExerciseRest(
            routineExerciseId: reId, routineId: routineId, mode: mode, seconds: seconds,
            reference: reference, value: value, updatedTs: Int(Date().timeIntervalSince1970))
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

    /// The full exercise list a library screen browses: the bundled seed catalog merged with the user's
    /// own exercises, sorted by name — each one re-typed by the user's measurement-type override (FER-541)
    /// so a catalog or custom override is respected everywhere this list feeds. Catalog stays read-only;
    /// the override is applied on read, not baked into the bundled data.
    func allExercises() async -> [Exercise] {
        guard let store = await storeHandle() else { return ExerciseCatalog.all }
        let custom = (try? await store.customExercises()) ?? []
        let overrides = (try? await store.exerciseTypeOverrides()) ?? [:]
        return (ExerciseCatalog.all + custom).map { $0.applying(overrides) }.sorted { $0.name < $1.name }
    }

    /// Resolve one exercise by id (catalog or custom) with its user type override applied — the single
    /// point every guided-session / builder / detail path uses, so no reader sees a non-overridden type.
    /// Precedence: override > custom > catalog (FER-541). nil if the id is unknown.
    func resolvedExercise(_ id: String) async -> Exercise? {
        let catalog = ExerciseCatalog.byID(id)
        var custom: Exercise?
        var override: ExerciseType?
        if let store = await storeHandle() {
            custom = (try? await store.customExercises())?.first { $0.id == id }
            override = (try? await store.exerciseTypeOverrides())?[id]
        }
        guard let base = custom ?? catalog else { return nil }
        let eff = ExerciseTypeResolver.effectiveType(override: override, custom: custom?.type, catalog: catalog?.type)
        return (eff != nil && eff != base.type) ? base.retyped(to: eff!) : base
    }

    func saveCustomExercise(_ e: Exercise) async throws {
        guard let store = await storeHandle() else { return }
        try await store.saveCustomExercise(e)
    }

    // MARK: - Exercise type overrides (FER-541)

    /// The user's current type override for an exercise (nil = none) — so the detail screen can offer
    /// «revert to default» only when there is one.
    func exerciseTypeOverride(_ exerciseId: String) async -> ExerciseType? {
        guard let store = await storeHandle() else { return nil }
        return (try? await store.exerciseTypeOverrides())?[exerciseId]
    }

    /// Override an exercise's measurement type (catalog or custom).
    func setExerciseTypeOverride(_ exerciseId: String, type: ExerciseType) async {
        guard let store = await storeHandle() else { return }
        try? await store.setExerciseTypeOverride(exerciseId, type: type, ts: Int(Date().timeIntervalSince1970))
    }

    /// Drop an exercise's type override → it reverts to its catalog/custom default.
    func clearExerciseTypeOverride(_ exerciseId: String) async {
        guard let store = await storeHandle() else { return }
        try? await store.clearExerciseTypeOverride(exerciseId)
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

    /// One full session row by id — for the edit sheet to seed every field (FER-556). nil if unknown.
    func session(id: String) async -> StrengthSession? {
        guard let store = await storeHandle() else { return nil }
        return (try? await store.session(id: id)) ?? nil
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

    /// Edit a saved session (sets / exercise / date / notes / routine) and recompute the affected PRs
    /// exactly — for the exercises in the old sets ∪ the new sets (FER-556). Never touches strain/avgHr.
    func updateSession(_ session: StrengthSession, sets: [SetEntry]) async throws {
        guard let store = await storeHandle() else { return }
        try await store.updateSession(session, sets: sets)
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

extension Exercise {
    /// Rebuild this exercise with a different measurement type, preserving every other field (FER-541).
    /// The id is kept, so PRs / history / matching stay linked; `Exercise` is an immutable value type.
    func retyped(to t: ExerciseType) -> Exercise {
        Exercise(id: id, name: name, nameES: nameES, type: t, equipment: equipment,
                 primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles, cues: cues, cuesES: cuesES)
    }

    /// Apply a user type-override map (FER-541): re-type if this exercise's id is overridden, else
    /// unchanged. The single fold every list-resolution path uses, so they can't diverge.
    func applying(_ overrides: [String: ExerciseType]) -> Exercise {
        overrides[id].map { retyped(to: $0) } ?? self
    }
}
