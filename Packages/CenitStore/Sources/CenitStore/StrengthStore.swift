import Foundation
import GRDB
import StrandTraining

// MARK: - v13 strength tracker persistence (FER-345)
//
// CRUD for the relational, user-authored strength data (custom exercises, routines,
// sessions, sets, PRs). Mirrors the repo idiom: Codable value types from `StrandTraining`,
// raw-SQL `INSERT … ON CONFLICT(id) DO UPDATE` upserts, and `Row.fetchAll` reads mapped by
// hand. Array fields (muscles, cues, warm-up percents) are stored as explicit JSON strings
// (same approach as `workout.zonesJSON`), so GRDB's record API is not relied on. All work runs
// via the actor's `syncWrite`/`syncRead` (off the main thread). The seed catalog is NOT here —
// it's a bundled resource in `StrandTraining`.

private func encodeJSON<T: Encodable>(_ value: T) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let s = String(data: data, encoding: .utf8) else { return "[]" }
    return s
}

private func decodeJSON<T: Decodable>(_ s: String?, as type: T.Type, default def: T) -> T {
    guard let s, let data = s.data(using: .utf8),
          let v = try? JSONDecoder().decode(T.self, from: data) else { return def }
    return v
}

extension CenitStore {

    // MARK: - Custom exercises (user-created; the bundled catalog lives in StrandTraining)

    public func saveCustomExercise(_ e: Exercise) async throws {
        try syncWrite { db in
            // The `cues` column (v13) is reused to store `instructions` (FER-779 renamed the field;
            // the column name stays for append-only migration hygiene). `bodyParts`/`gifUrl` are v27.
            let args: [DatabaseValueConvertible?] = [
                e.id, e.name, e.type.rawValue, e.equipment,
                encodeJSON(e.primaryMuscles), encodeJSON(e.secondaryMuscles), encodeJSON(e.instructions),
                encodeJSON(e.bodyParts), e.gifUrl
            ]
            try db.execute(sql: """
                INSERT INTO customExercise (id, name, type, equipment, primaryMuscles, secondaryMuscles, cues, bodyParts, gifUrl)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name, type = excluded.type, equipment = excluded.equipment,
                    primaryMuscles = excluded.primaryMuscles, secondaryMuscles = excluded.secondaryMuscles,
                    cues = excluded.cues, bodyParts = excluded.bodyParts, gifUrl = excluded.gifUrl
                """, arguments: StatementArguments(args))
        }
    }

    public func customExercises() async throws -> [Exercise] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM customExercise ORDER BY name ASC").map(Self.exercise)
        }
    }

    /// Just the ids of the user-created exercises — the library only needs to know *which* rows are
    /// its own, and this skips decoding every custom exercise's JSON blobs to answer that (FER-995).
    public func customExerciseIds() async throws -> Set<String> {
        try syncRead { db in
            Set(try String.fetchAll(db, sql: "SELECT id FROM customExercise"))
        }
    }

    public func deleteCustomExercise(id: String) async throws {
        try syncWrite { db in try db.execute(sql: "DELETE FROM customExercise WHERE id = ?", arguments: [id]) }
    }

    // MARK: - Exercise type overrides (FER-541)

    /// Override an exercise's measurement type (catalog or custom). Idempotent upsert on `exerciseId`.
    public func setExerciseTypeOverride(_ exerciseId: String, type: ExerciseType, ts: Int) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO exerciseTypeOverride (exerciseId, type, ts) VALUES (?, ?, ?)
                ON CONFLICT(exerciseId) DO UPDATE SET type = excluded.type, ts = excluded.ts
                """, arguments: [exerciseId, type.rawValue, ts])
        }
    }

    /// Remove an exercise's type override → it reverts to its catalog/custom default.
    public func clearExerciseTypeOverride(_ exerciseId: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM exerciseTypeOverride WHERE exerciseId = ?", arguments: [exerciseId])
        }
    }

    /// All user type overrides, keyed by exercise id. The single source the resolver folds in.
    public func exerciseTypeOverrides() async throws -> [String: ExerciseType] {
        try syncRead { db in
            var out: [String: ExerciseType] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT exerciseId, type FROM exerciseTypeOverride") {
                if let t = ExerciseType(rawValue: r["type"]) { out[r["exerciseId"]] = t }
            }
            return out
        }
    }

    private static func exercise(_ r: Row) -> Exercise {
        Exercise(id: r["id"], name: r["name"],
                 type: ExerciseType(rawValue: r["type"]) ?? .weightReps,
                 equipment: r["equipment"],
                 bodyParts: decodeJSON(r["bodyParts"], as: [String].self, default: []),
                 primaryMuscles: decodeJSON(r["primaryMuscles"], as: [String].self, default: []),
                 secondaryMuscles: decodeJSON(r["secondaryMuscles"], as: [String].self, default: []),
                 instructions: decodeJSON(r["cues"], as: [String].self, default: []),
                 gifUrl: r["gifUrl"])
    }

    // MARK: - Learned exercise aliases (FER-523)

    /// Remember that an imported exercise name maps to a catalog/custom exercise — so the next import of
    /// that name resolves on its own. `name` is the NORMALIZED imported name (the caller normalizes with
    /// the reconciler's rule). Re-mapping the same name overwrites.
    public func saveLearnedExerciseAlias(name: String, exerciseId: String, ts: Int) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO learnedExerciseAlias (name, exerciseId, ts) VALUES (?, ?, ?)
                ON CONFLICT(name) DO UPDATE SET exerciseId = excluded.exerciseId, ts = excluded.ts
                """, arguments: [name, exerciseId, ts])
        }
    }

    /// Every learned alias as normalized-name → exerciseId, for the import reconciler to consult.
    public func learnedExerciseAliases() async throws -> [String: String] {
        try syncRead { db in
            let rows = try Row.fetchAll(db, sql: "SELECT name, exerciseId FROM learnedExerciseAlias")
            return Dictionary(rows.map { ($0["name"] as String, $0["exerciseId"] as String) },
                              uniquingKeysWith: { first, _ in first })
        }
    }

    // MARK: - Routines

    /// Save a routine and replace its ordered exercise list in one transaction.
    public func saveRoutine(_ routine: Routine, exercises: [RoutineExercise]) async throws {
        try syncWrite { db in
            let rArgs: [DatabaseValueConvertible?] = [
                routine.id, routine.name, routine.tag, routine.folderId,
                routine.createdTs, routine.updatedTs, routine.sortOrder
            ]
            try db.execute(sql: """
                INSERT INTO routine (id, name, tag, folderId, createdTs, updatedTs, sortOrder)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name, tag = excluded.tag, folderId = excluded.folderId,
                    updatedTs = excluded.updatedTs, sortOrder = excluded.sortOrder
                """, arguments: StatementArguments(rArgs))

            // Replace this routine's exercises and their per-set rows in the same transaction. The
            // routineSet delete is keyed off the routine's current routineExercise ids, so it must run
            // before the routineExercise delete.
            try db.execute(sql: """
                DELETE FROM routineSet WHERE routineExerciseId IN
                    (SELECT id FROM routineExercise WHERE routineId = ?)
                """, arguments: [routine.id])
            try db.execute(sql: "DELETE FROM routineExercise WHERE routineId = ?", arguments: [routine.id])
            for re in exercises {
                // `sets` is the source of truth; the legacy target* columns are derived from the work
                // sets so any legacy reader stays coherent. `plannedSets` normalizes the slot (real sets,
                // or a 1:1 expansion of target* for a legacy/template slot with none).
                let planned = re.plannedSets
                let work = planned.filter { $0.kind == .work }
                let derivedSets = max(work.count, 1)
                let derivedReps = work.first?.reps
                let derivedWeight = work.first?.weightKg
                let args: [DatabaseValueConvertible?] = [
                    re.id, re.routineId, re.exerciseId, re.position, derivedSets, derivedReps,
                    derivedWeight, encodeJSON(re.warmupPercents), re.restMode.rawValue, re.restSeconds,
                    re.supersetGroup, re.hrRestReference.rawValue, re.hrRestValue,
                    re.progressionEnabled, re.progressionSessions, re.progressionIncrementKg,
                    re.progressionDeload.rawValue, re.progressionIgnoreRecovery
                ]
                try db.execute(sql: """
                    INSERT INTO routineExercise
                        (id, routineId, exerciseId, position, targetSets, targetReps, targetWeightKg,
                         warmupPercents, restMode, restSeconds, supersetGroup, hrRestReference, hrRestValue,
                         progressionEnabled, progressionSessions, progressionIncrementKg, progressionDeload,
                         progressionIgnoreRecovery)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: StatementArguments(args))
                for (idx, s) in planned.enumerated() {
                    // The four rest columns are written together (FER-715): a non-nil override writes
                    // all four, a nil `rest` writes four NULLs = "inherit the exercise" on read-back.
                    // `repsRangeTop` (E13/FER-94) is a single nullable column: nil = no range, today's
                    // behavior.
                    let sArgs: [DatabaseValueConvertible?] = [
                        s.id, re.id, idx, s.kind.rawValue, s.reps, s.weightKg,
                        s.rest?.mode.rawValue, s.rest?.seconds,
                        s.rest?.hrReference.rawValue, s.rest?.hrValue, s.repsRangeTop
                    ]
                    try db.execute(sql: """
                        INSERT INTO routineSet
                            (id, routineExerciseId, position, kind, reps, weightKg,
                             restMode, restSeconds, hrRestReference, hrRestValue, repsRangeTop)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, arguments: StatementArguments(sArgs))
                }
            }
        }
    }

    public func routines() async throws -> [Routine] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM routine ORDER BY sortOrder ASC, updatedTs DESC").map {
                Routine(id: $0["id"], name: $0["name"], tag: $0["tag"], folderId: $0["folderId"],
                        createdTs: $0["createdTs"], updatedTs: $0["updatedTs"], sortOrder: $0["sortOrder"])
            }
        }
    }

    // MARK: - Routine folders (FER-494)

    public func routineFolders() async throws -> [RoutineFolder] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM routineFolder ORDER BY sortOrder ASC, name ASC").map {
                RoutineFolder(id: $0["id"], name: $0["name"], sortOrder: $0["sortOrder"])
            }
        }
    }

    /// Upsert a folder — covers both create and rename.
    public func saveFolder(_ f: RoutineFolder) async throws {
        try syncWrite { db in
            let args: [DatabaseValueConvertible?] = [f.id, f.name, f.sortOrder]
            try db.execute(sql: """
                INSERT INTO routineFolder (id, name, sortOrder)
                VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, sortOrder = excluded.sortOrder
                """, arguments: StatementArguments(args))
        }
    }

    /// Delete a folder WITHOUT deleting its routines: they fall back to «Sin carpeta» (folderId NULL).
    /// The UPDATE runs before the DELETE inside one transaction.
    public func deleteFolder(id: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "UPDATE routine SET folderId = NULL WHERE folderId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM routineFolder WHERE id = ?", arguments: [id])
        }
    }

    /// Move one routine into a folder (or out, with `folderId == nil`), landing it at the end of the
    /// global order (`sortOrder = MAX+1`) so a drop drops it last in its new group (FER-526). A pinpoint
    /// UPDATE — it does not touch the routine's exercises/sets, unlike `saveRoutine` which rewrites them.
    public func setRoutineFolder(routineId: String, folderId: String?) async throws {
        try syncWrite { db in
            let maxOrder = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM routine") ?? -1
            try db.execute(sql: "UPDATE routine SET folderId = ?, sortOrder = ? WHERE id = ?",
                           arguments: [folderId, maxOrder + 1, routineId])
        }
    }

    /// Pinpoint-update one routine exercise's rest config, editable mid-session (FER-540). Touches that
    /// row's four rest columns + cascades the same values onto ALL its `routineSet` rows (FER-715) + the
    /// routine's `updatedTs` — it does NOT rewrite the routine's other exercises' sets (unlike
    /// `saveRoutine`). The cascade is required post-v26: since every set now carries a materialized rest,
    /// an exercise-scope edit must overwrite them all or the next session would read the stale per-set copy.
    public func updateRoutineExerciseRest(routineExerciseId reId: String, routineId: String,
                                          mode: RestMode, seconds: Int,
                                          reference: HRRestReference, value: Double, updatedTs: Int) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                UPDATE routineExercise
                   SET restMode = ?, restSeconds = ?, hrRestReference = ?, hrRestValue = ?
                 WHERE id = ?
                """, arguments: [mode.rawValue, seconds, reference.rawValue, value, reId])
            try db.execute(sql: """
                UPDATE routineSet
                   SET restMode = ?, restSeconds = ?, hrRestReference = ?, hrRestValue = ?
                 WHERE routineExerciseId = ?
                """, arguments: [mode.rawValue, seconds, reference.rawValue, value, reId])
            try db.execute(sql: "UPDATE routine SET updatedTs = ? WHERE id = ?",
                           arguments: [updatedTs, routineId])
        }
    }

    /// Pinpoint-update one set's rest override (FER-715). `rest == nil` clears the override (four NULLs =
    /// the set goes back to inheriting the exercise). Touches only that `routineSet` row + the routine's
    /// `updatedTs`; the exercise default and sibling sets are untouched (scope `.set`).
    public func updateRoutineSetRest(routineSetId: String, routineId: String,
                                     rest: RestConfig?, updatedTs: Int) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                UPDATE routineSet
                   SET restMode = ?, restSeconds = ?, hrRestReference = ?, hrRestValue = ?
                 WHERE id = ?
                """, arguments: [rest?.mode.rawValue, rest?.seconds,
                                 rest?.hrReference.rawValue, rest?.hrValue, routineSetId])
            try db.execute(sql: "UPDATE routine SET updatedTs = ? WHERE id = ?",
                           arguments: [updatedTs, routineId])
        }
    }

    /// Persist a new folder order: `sortOrder = index` per id (FER-526). One UPDATE per id in a
    /// transaction; touches nothing else.
    public func reorderFolders(_ idsInOrder: [String]) async throws {
        try syncWrite { db in
            for (idx, id) in idsInOrder.enumerated() {
                try db.execute(sql: "UPDATE routineFolder SET sortOrder = ? WHERE id = ?", arguments: [idx, id])
            }
        }
    }

    /// Persist a new routine order: `sortOrder = global index` per id (FER-526). `idsInOrder` is the full
    /// displayed order (folders in order → each folder's routines → «Sin carpeta» last). The display groups
    /// by folderId, so a global index is enough — it only has to be monotonic within each group. Only
    /// touches `routine.sortOrder` — never folderId, routineExercise or routineSet.
    public func reorderRoutines(_ idsInOrder: [String]) async throws {
        try syncWrite { db in
            for (idx, id) in idsInOrder.enumerated() {
                try db.execute(sql: "UPDATE routine SET sortOrder = ? WHERE id = ?", arguments: [idx, id])
            }
        }
    }

    // MARK: - Weekly split (FER-531)

    /// The full weekly split: every assigned day → its routine. A weekday with no row is a rest day.
    public func routineSchedule() async throws -> [RoutineSchedule] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM routineSchedule ORDER BY weekday ASC").map {
                RoutineSchedule(weekday: $0["weekday"], routineId: $0["routineId"])
            }
        }
    }

    /// Assign a routine to a weekday (1…7) — an idempotent upsert keyed on `weekday`, so re-assigning a
    /// day overwrites rather than duplicating.
    public func setRoutineSchedule(weekday: Int, routineId: String) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO routineSchedule (weekday, routineId)
                VALUES (?, ?)
                ON CONFLICT(weekday) DO UPDATE SET routineId = excluded.routineId
                """, arguments: [weekday, routineId])
        }
    }

    /// Clear a weekday back to a rest day (no routine planned).
    public func clearRoutineSchedule(weekday: Int) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM routineSchedule WHERE weekday = ?", arguments: [weekday])
        }
    }

    public func routineExercises(routineId: String) async throws -> [RoutineExercise] {
        try syncRead { db in
            var result = try Row.fetchAll(db, sql:
                "SELECT * FROM routineExercise WHERE routineId = ? ORDER BY position ASC",
                arguments: [routineId]).map(Self.routineExercise)
            let ids = result.map { $0.id }
            guard !ids.isEmpty else { return result }
            // One read for every slot's sets, not a query per slot.
            let placeholders = databaseQuestionMarks(count: ids.count)
            let setRows = try Row.fetchAll(db, sql:
                "SELECT * FROM routineSet WHERE routineExerciseId IN (\(placeholders)) ORDER BY position ASC",
                arguments: StatementArguments(ids))
            var byRe: [String: [RoutineSet]] = [:]
            for r in setRows {
                let reId: String = r["routineExerciseId"]
                byRe[reId, default: []].append(Self.routineSet(r))
            }
            for i in result.indices {
                // Post-v17 every slot has rows; for a slot with none (a path that skipped routineSet)
                // `plannedSets` synthesizes from target* so `sets` is never empty.
                let s = byRe[result[i].id] ?? []
                result[i].sets = s.isEmpty ? result[i].plannedSets : s
            }
            return result
        }
    }

    public func deleteRoutine(id: String) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                DELETE FROM routineSet WHERE routineExerciseId IN
                    (SELECT id FROM routineExercise WHERE routineId = ?)
                """, arguments: [id])
            try db.execute(sql: "DELETE FROM routineExercise WHERE routineId = ?", arguments: [id])
            // Clear any weekly-split rows pointing at this routine, so a deleted routine leaves no
            // dangling day in the split (FER-531). Same transaction as the routine delete.
            try db.execute(sql: "DELETE FROM routineSchedule WHERE routineId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM routine WHERE id = ?", arguments: [id])
        }
    }

    private static func routineExercise(_ r: Row) -> RoutineExercise {
        RoutineExercise(id: r["id"], routineId: r["routineId"], exerciseId: r["exerciseId"],
                        position: r["position"], targetSets: r["targetSets"],
                        targetReps: r["targetReps"], targetWeightKg: r["targetWeightKg"],
                        warmupPercents: decodeJSON(r["warmupPercents"], as: [Double].self, default: []),
                        restMode: RestMode(rawValue: r["restMode"]) ?? .heartRate,
                        restSeconds: r["restSeconds"], supersetGroup: r["supersetGroup"],
                        hrRestReference: HRRestReference(rawValue: r["hrRestReference"]) ?? .restingMargin,
                        hrRestValue: r["hrRestValue"],
                        progressionEnabled: r["progressionEnabled"] ?? false,
                        progressionSessions: r["progressionSessions"] ?? 2,
                        progressionIncrementKg: r["progressionIncrementKg"],
                        progressionDeload: DeloadPolicy(rawValue: r["progressionDeload"] ?? "propose") ?? .propose,
                        progressionIgnoreRecovery: r["progressionIgnoreRecovery"] ?? false)
    }

    private static func routineSet(_ r: Row) -> RoutineSet {
        // The rest override reads back only when all four columns are present (FER-715): `restMode`
        // NOT NULL is the flag — a NULL restMode (a set that inherits) yields `rest == nil`.
        let rest: RestConfig? = (r["restMode"] as String?).map {
            RestConfig(mode: RestMode(rawValue: $0) ?? .heartRate,
                       seconds: r["restSeconds"] ?? 90,
                       hrReference: HRRestReference(rawValue: r["hrRestReference"] ?? "") ?? .restingMargin,
                       hrValue: r["hrRestValue"] ?? 0)
        }
        return RoutineSet(id: r["id"], position: r["position"],
                          kind: SetKind(rawValue: r["kind"]) ?? .work,
                          reps: r["reps"], weightKg: r["weightKg"], repsRangeTop: r["repsRangeTop"],
                          rest: rest)
    }

    // MARK: - Sessions + sets (+ PR derivation, transactional)

    /// Save a session and replace its sets in one transaction, then update PRs from the work sets.
    /// `progressionOptOuts` are the exercise ids whose raise was reverted with «Volver a X» this
    /// session (FER-835): persisted so the progression cycle treats the session as neither hit nor miss.
    public func saveSession(_ session: StrengthSession, sets: [SetEntry],
                            progressionOptOuts: Set<String> = [],
                            notes: [ExerciseNote] = []) async throws {
        try syncWrite { db in
            let sArgs: [DatabaseValueConvertible?] = [
                session.id, session.routineId, session.startTs, session.endTs,
                session.deviceId, session.strain, session.avgHr, session.notes,
                session.energyKcal, session.energySource?.rawValue
            ]
            try db.execute(sql: """
                INSERT INTO strengthSession
                    (id, routineId, startTs, endTs, deviceId, strain, avgHr, notes, energyKcal, energySource)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    routineId = excluded.routineId, endTs = excluded.endTs, deviceId = excluded.deviceId,
                    strain = excluded.strain, avgHr = excluded.avgHr, notes = excluded.notes,
                    energyKcal = excluded.energyKcal, energySource = excluded.energySource
                """, arguments: StatementArguments(sArgs))

            try db.execute(sql: "DELETE FROM setEntry WHERE sessionId = ?", arguments: [session.id])
            for s in sets {
                let args: [DatabaseValueConvertible?] = [
                    s.id, s.sessionId, s.exerciseId, s.position, s.kind.rawValue,
                    s.weightKg, s.reps, s.timeS, s.distanceM, s.done ? 1 : 0, s.ts, s.rpe
                ]
                try db.execute(sql: """
                    INSERT INTO setEntry
                        (id, sessionId, exerciseId, position, kind, weightKg, reps, timeS, distanceM, done, ts, rpe)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: StatementArguments(args))
            }
            // Replace this session's opt-out rows (delete-first keeps a re-save idempotent, like setEntry).
            try db.execute(sql: "DELETE FROM progressionOptOut WHERE sessionId = ?", arguments: [session.id])
            for exerciseId in progressionOptOuts.sorted() {
                try db.execute(sql: "INSERT INTO progressionOptOut (sessionId, exerciseId) VALUES (?, ?)",
                               arguments: [session.id, exerciseId])
            }
            // Replace this session's exercise notes (delete-first keeps a re-save idempotent, like setEntry).
            // Only non-empty text is stored — a cleared note simply doesn't come back.
            try db.execute(sql: "DELETE FROM strengthExerciseNote WHERE sessionId = ?", arguments: [session.id])
            for n in notes where !n.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try db.execute(sql: """
                    INSERT INTO strengthExerciseNote (id, sessionId, exerciseId, setPosition, text, ts)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [n.id, n.sessionId, n.exerciseId, n.setPosition, n.text, n.ts])
            }
            try Self.updatePersonalRecords(db, sets: sets)
        }
    }

    /// Edit a saved session: replace its row + sets, then recompute PRs *exactly* for every exercise
    /// touched — the ones in the old sets ∪ the ones in the new sets (FER-556). All in one transaction.
    /// Unlike `saveSession` (whose `updatePersonalRecords` only *upgrades* a record), editing can LOWER a
    /// value (a corrected weight) or REASSIGN an exercise, so the affected PRs must be recomputed from
    /// scratch over what remains — exactly like the delete path — or they'd keep a record the edit erased.
    /// The session's `strain`/`avgHr`/`deviceId` (the strap's captured truth) ride through unchanged: the
    /// edit UI never sends different values, and the upsert writes whatever the passed `session` carries.
    public func updateSession(_ session: StrengthSession, sets: [SetEntry]) async throws {
        try syncWrite { db in
            // The exercises that had sets BEFORE the edit — they may lose a record (a set removed or
            // reassigned away), so they must be recomputed even if no new set mentions them.
            let oldExercises = try String.fetchAll(db, sql:
                "SELECT DISTINCT exerciseId FROM setEntry WHERE sessionId = ?", arguments: [session.id])

            let sArgs: [DatabaseValueConvertible?] = [
                session.id, session.routineId, session.startTs, session.endTs,
                session.deviceId, session.strain, session.avgHr, session.notes,
                session.energyKcal, session.energySource?.rawValue
            ]
            try db.execute(sql: """
                INSERT INTO strengthSession
                    (id, routineId, startTs, endTs, deviceId, strain, avgHr, notes, energyKcal, energySource)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    routineId = excluded.routineId, startTs = excluded.startTs, endTs = excluded.endTs,
                    deviceId = excluded.deviceId, strain = excluded.strain, avgHr = excluded.avgHr,
                    notes = excluded.notes, energyKcal = excluded.energyKcal,
                    energySource = excluded.energySource
                """, arguments: StatementArguments(sArgs))

            try db.execute(sql: "DELETE FROM setEntry WHERE sessionId = ?", arguments: [session.id])
            for s in sets {
                let args: [DatabaseValueConvertible?] = [
                    s.id, s.sessionId, s.exerciseId, s.position, s.kind.rawValue,
                    s.weightKg, s.reps, s.timeS, s.distanceM, s.done ? 1 : 0, s.ts, s.rpe
                ]
                try db.execute(sql: """
                    INSERT INTO setEntry
                        (id, sessionId, exerciseId, position, kind, weightKg, reps, timeS, distanceM, done, ts, rpe)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: StatementArguments(args))
            }

            let affected = Set(oldExercises).union(sets.map(\.exerciseId))
            for exerciseId in affected { try Self.recomputePR(db, exerciseId: exerciseId) }
        }
    }

    /// Delete a session and its sets, then recompute the affected exercises' PRs from what remains
    /// (FER-527). All in one transaction. A record can DROP to the second-best (or be removed if it was
    /// the only session for that exercise) — the PR stays honest. Touches no routine/routineExercise.
    public func deleteSession(id: String) async throws {
        try syncWrite { db in
            let affected = try String.fetchAll(db, sql:
                "SELECT DISTINCT exerciseId FROM setEntry WHERE sessionId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM setEntry WHERE sessionId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM progressionOptOut WHERE sessionId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM strengthExerciseNote WHERE sessionId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM strengthSession WHERE id = ?", arguments: [id])
            for exerciseId in affected { try Self.recomputePR(db, exerciseId: exerciseId) }
        }
    }

    /// This session's own exercise notes (all scopes), for re-seeding the edit sheet. Not filtered by
    /// exercise — the caller groups by `exerciseId` if needed.
    public func sessionNotes(sessionId: String) async throws -> [ExerciseNote] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM strengthExerciseNote WHERE sessionId = ?",
                             arguments: [sessionId]).map(Self.exerciseNote)
        }
    }

    /// Prior notes for one exercise, across other sessions — the «NOTAS ANTERIORES» history in the
    /// note sheet (FER-932). Excludes the session currently being edited/logged (`excludingSession`) so
    /// a note just typed this session doesn't show up as its own "history". Newest session first.
    public func exerciseNotes(exerciseId: String, excludingSession: String,
                              limit: Int = 20) async throws -> [ExerciseNote] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT n.* FROM strengthExerciseNote n
                JOIN strengthSession s ON n.sessionId = s.id
                WHERE n.exerciseId = ? AND n.sessionId <> ?
                ORDER BY s.startTs DESC
                LIMIT ?
                """, arguments: [exerciseId, excludingSession, limit]).map(Self.exerciseNote)
        }
    }

    private static func exerciseNote(_ r: Row) -> ExerciseNote {
        ExerciseNote(id: r["id"], sessionId: r["sessionId"], exerciseId: r["exerciseId"],
                     setPosition: r["setPosition"], text: r["text"], ts: r["ts"])
    }

    public func recentSessions(limit: Int = 200) async throws -> [StrengthSession] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM strengthSession ORDER BY startTs DESC LIMIT ?",
                             arguments: [limit]).map(Self.session)
        }
    }

    /// One session by id — the full row (incl. notes/deviceId/routineId the list route doesn't carry),
    /// for the edit sheet to seed its working copy (FER-556). nil when the id is unknown.
    public func session(id: String) async throws -> StrengthSession? {
        try syncRead { db in
            try Row.fetchOne(db, sql: "SELECT * FROM strengthSession WHERE id = ?",
                             arguments: [id]).map(Self.session)
        }
    }

    public func setEntries(sessionId: String) async throws -> [SetEntry] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM setEntry WHERE sessionId = ? ORDER BY position ASC",
                             arguments: [sessionId]).map(Self.setEntry)
        }
    }

    /// Per-session work volume (Σ weight×reps) and completed-work-set count for the «Mis entrenamientos»
    /// list (FER-504) — one GROUP BY, not a read per session. Only done work sets with both weight and
    /// reps contribute to volume; the count is every done work set (a bodyweight set still counts).
    public func sessionVolumes() async throws -> [String: (volumeKg: Double, setCount: Int)] {
        try syncRead { db in
            var out: [String: (volumeKg: Double, setCount: Int)] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT sessionId AS sid,
                       COALESCE(SUM(CASE WHEN weightKg IS NOT NULL AND reps IS NOT NULL
                                         THEN weightKg * reps ELSE 0 END), 0) AS vol,
                       COUNT(*) AS cnt
                FROM setEntry
                WHERE kind = 'work' AND done = 1
                GROUP BY sessionId
                """)
            for r in rows {
                let sid: String = r["sid"]
                out[sid] = (volumeKg: r["vol"], setCount: r["cnt"])
            }
            return out
        }
    }

    /// The most recent *work* sets for an exercise, newest first — powers "la última vez" pre-fill.
    public func lastWorkSets(exerciseId: String, limit: Int = 12) async throws -> [SetEntry] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM setEntry WHERE exerciseId = ? AND kind = 'work' AND done = 1
                ORDER BY ts DESC LIMIT ?
                """, arguments: [exerciseId, limit]).map(Self.setEntry)
        }
    }

    /// Completed work sets for an exercise with their session's start time, oldest→newest — one JOIN
    /// (`setEntry` × `strengthSession`), not a query per session. The raw material the detail screen
    /// buckets by day into the estimated-1RM trend; only weight×reps sets count (1RM needs both).
    /// `optedOut` reports the session's «Volver a X» mark for this exercise (FER-835), via LEFT JOIN
    /// on `progressionOptOut` — the progression classifier skips those sessions entirely.
    public func workSetHistory(exerciseId: String, limit: Int = 600) async throws
        -> [(startTs: Int, weightKg: Double, reps: Int, optedOut: Bool)] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT s.startTs AS startTs, e.weightKg AS weightKg, e.reps AS reps,
                       (o.exerciseId IS NOT NULL) AS optedOut
                FROM setEntry e JOIN strengthSession s ON e.sessionId = s.id
                LEFT JOIN progressionOptOut o ON o.sessionId = e.sessionId AND o.exerciseId = e.exerciseId
                WHERE e.exerciseId = ? AND e.kind = 'work' AND e.done = 1
                  AND e.weightKg IS NOT NULL AND e.reps IS NOT NULL
                ORDER BY s.startTs ASC
                LIMIT ?
                """, arguments: [exerciseId, limit]).map { (row: Row) -> (startTs: Int, weightKg: Double, reps: Int, optedOut: Bool) in
                    let startTs: Int = row["startTs"]
                    let weightKg: Double = row["weightKg"]
                    let reps: Int = row["reps"]
                    let optedOut: Bool = row["optedOut"]
                    return (startTs: startTs, weightKg: weightKg, reps: reps, optedOut: optedOut)
                }
        }
    }

    /// Every completed *work* set since `sinceTs` (epoch seconds) with its exercise id and the session's
    /// start time, newest first — one JOIN (`setEntry` × `strengthSession`), not a query per session.
    /// The raw material for the muscle-fatigue map (FER-350), which counts involvement-weighted *series*
    /// per muscle, so weight/reps are NOT required (a bodyweight pull-up set still loads the lats).
    public func workSetsSince(_ sinceTs: Int, limit: Int = 5000) async throws
        -> [(exerciseId: String, startTs: Int)] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT e.exerciseId AS exerciseId, s.startTs AS startTs
                FROM setEntry e JOIN strengthSession s ON e.sessionId = s.id
                WHERE e.kind = 'work' AND e.done = 1 AND s.startTs >= ?
                ORDER BY s.startTs DESC
                LIMIT ?
                """, arguments: [sinceTs, limit]).map {
                    (exerciseId: $0["exerciseId"], startTs: $0["startTs"])
                }
        }
    }

    public func personalRecords(exerciseId: String) async throws -> [PersonalRecord] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM personalRecord WHERE exerciseId = ?",
                             arguments: [exerciseId]).map(Self.personalRecord)
        }
    }

    private static func session(_ r: Row) -> StrengthSession {
        StrengthSession(id: r["id"], routineId: r["routineId"], startTs: r["startTs"], endTs: r["endTs"],
                        deviceId: r["deviceId"], strain: r["strain"], avgHr: r["avgHr"], notes: r["notes"],
                        energyKcal: r["energyKcal"],
                        energySource: (r["energySource"] as String?).flatMap(EnergySource.init(rawValue:)))
    }

    private static func setEntry(_ r: Row) -> SetEntry {
        SetEntry(id: r["id"], sessionId: r["sessionId"], exerciseId: r["exerciseId"], position: r["position"],
                 kind: SetKind(rawValue: r["kind"]) ?? .work, weightKg: r["weightKg"], reps: r["reps"],
                 timeS: r["timeS"], distanceM: r["distanceM"], done: (r["done"] as Int) != 0, ts: r["ts"],
                 rpe: r["rpe"])
    }

    private static func personalRecord(_ r: Row) -> PersonalRecord {
        var pr = PersonalRecord(exerciseId: r["exerciseId"],
                                metric: PRMetric(rawValue: r["metric"]) ?? .maxWeight,
                                valueKg: r["valueKg"], reps: r["reps"], ts: r["ts"])
        pr.id = r["id"]
        return pr
    }

    // MARK: - PR derivation

    /// The 3 candidate PRs (best weight / reps / volume) from a set of *done work* sets for one exercise;
    /// each is nil when no set qualifies. The single source of "what counts as a record" — shared by the
    /// save path (`updatePersonalRecords`, upgrade-only) and the delete path (`recomputePR`, write-exact).
    private static func bestPRs(_ work: [SetEntry], exerciseId: String)
        -> (maxWeight: PersonalRecord?, maxReps: PersonalRecord?, maxVolume: PersonalRecord?) {
        let maxWeight = work.compactMap { s in s.weightKg.map { (v: $0, ts: s.ts) } }.max { $0.v < $1.v }
            .map { PersonalRecord(exerciseId: exerciseId, metric: .maxWeight, valueKg: $0.v, ts: $0.ts) }
        let maxReps = work.compactMap { s in s.reps.map { (v: $0, ts: s.ts) } }.max { $0.v < $1.v }
            .map { PersonalRecord(exerciseId: exerciseId, metric: .maxReps, reps: $0.v, ts: $0.ts) }
        let maxVolume = work.compactMap { s -> (vol: Double, w: Double, reps: Int, ts: Int)? in
                guard let w = s.weightKg, let r = s.reps else { return nil }
                return (w * Double(r), w, r, s.ts)
            }.max { $0.vol < $1.vol }
            .map { PersonalRecord(exerciseId: exerciseId, metric: .maxVolume, valueKg: $0.w, reps: $0.reps, ts: $0.ts) }
        return (maxWeight, maxReps, maxVolume)
    }

    /// Update best-per-exercise PRs from a session's *done work* sets. Only upgrades an existing PR;
    /// never downgrades. (Estimated-1RM is FER-349's analytics, not stored here.)
    private static func updatePersonalRecords(_ db: Database, sets: [SetEntry]) throws {
        let work = sets.filter { $0.kind == .work && $0.done }
        for (exerciseId, exSets) in Dictionary(grouping: work, by: \.exerciseId) {
            let best = bestPRs(exSets, exerciseId: exerciseId)
            for pr in [best.maxWeight, best.maxReps, best.maxVolume].compactMap({ $0 }) {
                try upsertPR(db, pr)
            }
        }
    }

    /// Recompute the 3 PRs for one exercise from scratch over ALL its remaining done work sets (FER-527).
    /// Unlike `upsertPR` (which only upgrades), this writes the exact recomputed best — even if it is now
    /// LOWER — or deletes the PR row when no set qualifies. Used after a session is deleted, so the record
    /// reflects only what's left.
    private static func recomputePR(_ db: Database, exerciseId: String) throws {
        let work = try Row.fetchAll(db, sql:
            "SELECT * FROM setEntry WHERE exerciseId = ? AND kind = 'work' AND done = 1",
            arguments: [exerciseId]).map(setEntry)
        let best = bestPRs(work, exerciseId: exerciseId)

        func writeOrDelete(_ metric: PRMetric, _ pr: PersonalRecord?) throws {
            guard let pr else {
                // The id format lives in PersonalRecord; derive it rather than hardcoding the string.
                let id = PersonalRecord(exerciseId: exerciseId, metric: metric, ts: 0).id
                try db.execute(sql: "DELETE FROM personalRecord WHERE id = ?", arguments: [id])
                return
            }
            let args: [DatabaseValueConvertible?] = [pr.id, pr.exerciseId, pr.metric.rawValue,
                                                     pr.valueKg, pr.reps, pr.ts]
            try db.execute(sql: """
                INSERT INTO personalRecord (id, exerciseId, metric, valueKg, reps, ts)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET valueKg = excluded.valueKg, reps = excluded.reps, ts = excluded.ts
                """, arguments: StatementArguments(args))
        }

        try writeOrDelete(.maxWeight, best.maxWeight)
        try writeOrDelete(.maxReps, best.maxReps)
        try writeOrDelete(.maxVolume, best.maxVolume)
    }

    private static func upsertPR(_ db: Database, _ pr: PersonalRecord) throws {
        let existing = try Row.fetchOne(db, sql: "SELECT * FROM personalRecord WHERE id = ?",
                                        arguments: [pr.id]).map(personalRecord)
        if let existing {
            let isBetter: Bool
            switch pr.metric {
            case .maxWeight:
                isBetter = (pr.valueKg ?? 0) > (existing.valueKg ?? 0)
            case .maxReps:
                isBetter = (pr.reps ?? 0) > (existing.reps ?? 0)
            case .maxVolume:
                let newVolume: Double = (pr.valueKg ?? 0) * Double(pr.reps ?? 0)
                let oldVolume: Double = (existing.valueKg ?? 0) * Double(existing.reps ?? 0)
                isBetter = newVolume > oldVolume
            }
            guard isBetter else { return }
        }
        let args: [DatabaseValueConvertible?] = [pr.id, pr.exerciseId, pr.metric.rawValue,
                                                 pr.valueKg, pr.reps, pr.ts]
        try db.execute(sql: """
            INSERT INTO personalRecord (id, exerciseId, metric, valueKg, reps, ts)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                valueKg = excluded.valueKg, reps = excluded.reps, ts = excluded.ts
            """, arguments: StatementArguments(args))
    }
}

/// The single rule for an exercise's effective measurement type (FER-541): a **user override** wins,
/// then a **custom** exercise's own type, then the **bundled catalog**'s. Pure so the precedence is
/// unit-tested without a store; the app's resolver (`Repository`) loads the three inputs and applies it.
public enum ExerciseTypeResolver {
    public static func effectiveType(override: ExerciseType?, custom: ExerciseType?, catalog: ExerciseType?) -> ExerciseType? {
        override ?? custom ?? catalog
    }
}
