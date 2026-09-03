import Foundation
import GRDB
import StrandTraining
import BiometricStreams

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

/// One completed work set from `workSetHistory`, joined with its session — FER-147. `sessionId` is the
/// grouping key for per-session facts (e.g. FER-149's best-volume-in-a-session); `rpe` (v34) feeds the
/// «QUEDABAN» read; `routineName` is nil for a free session or a since-deleted routine.
public struct WorkSetHistoryRow: Sendable, Equatable {
    public var sessionId: String
    public var startTs: Int
    public var weightKg: Double
    public var reps: Int
    public var optedOut: Bool
    public var rpe: Double?
    public var routineName: String?
    /// Cómo se hizo la serie (ola 1 · FER-327). El SQL ya excluye los drops de esta consulta (no
    /// alimentan progresión ni 1RM), así que aquí solo llegan `.standard` y `.amrap` — se proyecta de
    /// todas formas para que quien lea la historia pueda distinguir un «las que puedas» de una serie
    /// fija sin volver a la base.
    public var mode: SetMode

    public init(sessionId: String, startTs: Int, weightKg: Double, reps: Int, optedOut: Bool = false,
                rpe: Double? = nil, routineName: String? = nil, mode: SetMode = .standard) {
        self.sessionId = sessionId
        self.startTs = startTs
        self.weightKg = weightKg
        self.reps = reps
        self.optedOut = optedOut
        self.rpe = rpe
        self.routineName = routineName
        self.mode = mode
    }
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
                // FER-166: normalize here (trim; blank → NULL) so the "note or NULL, never ''" invariant
                // doesn't depend on the discipline of whichever UI wrote it — same contract `saveSession`
                // already uses for `strengthExerciseNote`.
                let noteText = re.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                let args: [DatabaseValueConvertible?] = [
                    re.id, re.routineId, re.exerciseId, re.position, derivedSets, derivedReps,
                    derivedWeight, encodeJSON(re.warmupPercents), re.restMode.rawValue, re.restSeconds,
                    re.supersetGroup, re.hrRestReference.rawValue, re.hrRestValue,
                    re.progressionEnabled, re.progressionSessions, re.progressionIncrementKg,
                    re.progressionDeload.rawValue, re.progressionIgnoreRecovery,
                    (noteText?.isEmpty == false) ? noteText : nil,
                    re.progressionUseRPE
                ]
                try db.execute(sql: """
                    INSERT INTO routineExercise
                        (id, routineId, exerciseId, position, targetSets, targetReps, targetWeightKg,
                         warmupPercents, restMode, restSeconds, supersetGroup, hrRestReference, hrRestValue,
                         progressionEnabled, progressionSessions, progressionIncrementKg, progressionDeload,
                         progressionIgnoreRecovery, note, progressionUseRPE)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: StatementArguments(args))
                for (idx, s) in planned.enumerated() {
                    // The four rest columns are written together (FER-715): a non-nil override writes
                    // all four, a nil `rest` writes four NULLs = "inherit the exercise" on read-back.
                    // `repsRangeTop` (E13/FER-94) is a single nullable column: nil = no range, today's
                    // behavior.
                    let sArgs: [DatabaseValueConvertible?] = [
                        s.id, re.id, idx, s.kind.rawValue, s.reps, s.weightKg,
                        s.rest?.mode.rawValue, s.rest?.seconds,
                        s.rest?.hrReference.rawValue, s.rest?.hrValue, s.repsRangeTop,
                        s.mode == .standard ? nil : s.mode.rawValue
                    ]
                    try db.execute(sql: """
                        INSERT INTO routineSet
                            (id, routineExerciseId, position, kind, reps, weightKg,
                             restMode, restSeconds, hrRestReference, hrRestValue, repsRangeTop, mode)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                        progressionIgnoreRecovery: r["progressionIgnoreRecovery"] ?? false,
                        note: r["note"],
                        progressionUseRPE: r["progressionUseRPE"] ?? false)
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
                          rest: rest,
                          mode: (r["mode"] as String?).flatMap(SetMode.init(rawValue:)) ?? .standard)
    }

    // MARK: - Sessions + sets (+ PR derivation, transactional)

    /// Save a session and replace its sets in one transaction, then update PRs from the work sets.
    /// `progressionOptOuts` are the exercise ids whose raise was reverted with «Volver a X» this
    /// session (FER-835): persisted so the progression cycle treats the session as neither hit nor miss.
    public func saveSession(_ session: StrengthSession, sets: [SetEntry],
                            progressionOptOuts: Set<String> = [],
                            notes: [ExerciseNote] = []) async throws {
        try syncWrite { db in
            try Self.persistSession(db, session: session, sets: sets,
                                    progressionOptOuts: progressionOptOuts, notes: notes)
        }
    }

    /// Batch upsert for CSV import (FER-328 · E8): one `syncWrite` / one BEGIN for N sessions.
    /// Re-importing the same ids is idempotent (`ON CONFLICT` + replace sets). Each session still
    /// runs `updatePersonalRecords` with the set's original `ts` so a 2022 PR is not celebrated as new.
    public func saveSessions(_ batch: [(session: StrengthSession, sets: [SetEntry])]) async throws {
        guard !batch.isEmpty else { return }
        try syncWrite { db in
            for item in batch {
                try Self.persistSession(db, session: item.session, sets: item.sets)
            }
        }
    }

    /// Which of `ids` already exist in `strengthSession` — the «Ya estaban» set for re-import.
    public func existingSessionIds(_ ids: [String]) async throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        return try syncRead { db in
            // Chunk to stay under SQLite's variable limit on very large re-imports.
            var found = Set<String>()
            let chunkSize = 400
            var start = ids.startIndex
            while start < ids.endIndex {
                let end = ids.index(start, offsetBy: chunkSize, limitedBy: ids.endIndex) ?? ids.endIndex
                let chunk = Array(ids[start..<end])
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                let rows = try String.fetchAll(
                    db, sql: "SELECT id FROM strengthSession WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(chunk))
                found.formUnion(rows)
                start = end
            }
            return found
        }
    }

    /// Compact provenance for «Posibles duplicados» (±30 min across origins).
    public func sessionSummariesForImportOverlap() async throws -> [(id: String, source: String?, title: String?, startTs: Int)] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT id, source, title, startTs FROM strengthSession")
                .map { (id: $0["id"], source: $0["source"], title: $0["title"], startTs: $0["startTs"]) }
        }
    }

    /// Shared body of `saveSession` / `saveSessions` — one session inside an open write transaction.
    private static func persistSession(_ db: Database, session: StrengthSession, sets: [SetEntry],
                                       progressionOptOuts: Set<String> = [],
                                       notes: [ExerciseNote] = []) throws {
        let sArgs: [DatabaseValueConvertible?] = [
            session.id, session.routineId, session.startTs, session.endTs,
            session.deviceId, session.strain, session.avgHr, session.notes,
            session.energyKcal, session.energySource?.rawValue,
            session.strainSource?.rawValue, session.sessionRpe, session.sessionRpeSource?.rawValue,
            session.trimpPerAU, session.source, session.title, session.programWeek,
            session.deload.map { $0 ? 1 : 0 }
        ]
        try db.execute(sql: """
            INSERT INTO strengthSession
                (id, routineId, startTs, endTs, deviceId, strain, avgHr, notes, energyKcal, energySource,
                 strainSource, sessionRpe, sessionRpeSource, trimpPerAU, source, title, programWeek, deload)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                routineId = excluded.routineId, endTs = excluded.endTs, deviceId = excluded.deviceId,
                strain = excluded.strain, avgHr = excluded.avgHr, notes = excluded.notes,
                energyKcal = excluded.energyKcal, energySource = excluded.energySource,
                strainSource = excluded.strainSource, sessionRpe = excluded.sessionRpe,
                sessionRpeSource = excluded.sessionRpeSource, trimpPerAU = excluded.trimpPerAU,
                source = excluded.source, title = excluded.title,
                programWeek = excluded.programWeek, deload = excluded.deload
            """, arguments: StatementArguments(sArgs))

        try db.execute(sql: "DELETE FROM setEntry WHERE sessionId = ?", arguments: [session.id])
        // Ola 1 · FER-327: los drops se escriben pegados a su madre (ver `enforcingDropAdjacency`).
        for s in enforcingDropAdjacency(sets) {
            let args: [DatabaseValueConvertible?] = [
                s.id, s.sessionId, s.exerciseId, s.position, s.kind.rawValue,
                s.weightKg, s.reps, s.timeS, s.distanceM, s.done ? 1 : 0, s.ts, s.rpe, s.restTakenS,
                s.mode == .standard ? nil : s.mode.rawValue
            ]
            try db.execute(sql: """
                INSERT INTO setEntry
                    (id, sessionId, exerciseId, position, kind, weightKg, reps, timeS, distanceM, done, ts, rpe, restTakenS, mode)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: StatementArguments(args))
        }
        try db.execute(sql: "DELETE FROM progressionOptOut WHERE sessionId = ?", arguments: [session.id])
        for exerciseId in progressionOptOuts.sorted() {
            try db.execute(sql: "INSERT INTO progressionOptOut (sessionId, exerciseId) VALUES (?, ?)",
                           arguments: [session.id, exerciseId])
        }
        try db.execute(sql: "DELETE FROM strengthExerciseNote WHERE sessionId = ?", arguments: [session.id])
        for n in notes where !n.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try db.execute(sql: """
                INSERT INTO strengthExerciseNote (id, sessionId, exerciseId, setPosition, text, ts)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [n.id, n.sessionId, n.exerciseId, n.setPosition, n.text, n.ts])
        }
        try updatePersonalRecords(db, sets: sets)
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
                session.energyKcal, session.energySource?.rawValue,
                session.strainSource?.rawValue, session.sessionRpe, session.sessionRpeSource?.rawValue,
                session.trimpPerAU, session.source, session.title, session.programWeek,
                session.deload.map { $0 ? 1 : 0 }
            ]
            try db.execute(sql: """
                INSERT INTO strengthSession
                    (id, routineId, startTs, endTs, deviceId, strain, avgHr, notes, energyKcal, energySource,
                     strainSource, sessionRpe, sessionRpeSource, trimpPerAU, source, title, programWeek, deload)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    routineId = excluded.routineId, startTs = excluded.startTs, endTs = excluded.endTs,
                    deviceId = excluded.deviceId, strain = excluded.strain, avgHr = excluded.avgHr,
                    notes = excluded.notes, energyKcal = excluded.energyKcal,
                    energySource = excluded.energySource,
                    strainSource = excluded.strainSource, sessionRpe = excluded.sessionRpe,
                    sessionRpeSource = excluded.sessionRpeSource, trimpPerAU = excluded.trimpPerAU,
                    source = excluded.source, title = excluded.title,
                    programWeek = excluded.programWeek, deload = excluded.deload
                """, arguments: StatementArguments(sArgs))

            try db.execute(sql: "DELETE FROM setEntry WHERE sessionId = ?", arguments: [session.id])
            // Ola 1 · FER-327: los drops se escriben pegados a su madre (ver `enforcingDropAdjacency`).
            for s in Self.enforcingDropAdjacency(sets) {
                let args: [DatabaseValueConvertible?] = [
                    s.id, s.sessionId, s.exerciseId, s.position, s.kind.rawValue,
                    s.weightKg, s.reps, s.timeS, s.distanceM, s.done ? 1 : 0, s.ts, s.rpe, s.restTakenS,
                    s.mode == .standard ? nil : s.mode.rawValue
                ]
                try db.execute(sql: """
                    INSERT INTO setEntry
                        (id, sessionId, exerciseId, position, kind, weightKg, reps, timeS, distanceM, done, ts, rpe, restTakenS, mode)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            try db.execute(sql: "DELETE FROM strengthHrSample WHERE sessionId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM strengthSession WHERE id = ?", arguments: [id])
            for exerciseId in affected { try Self.recomputePR(db, exerciseId: exerciseId) }
        }
    }

    // MARK: - Live-session HR capture (FER-226)
    //
    // Revives the FC capturer killed by FER-1003's band amputation: raw watch-pulse samples land here
    // during a live strength session (`AppModel.ingestWatchPulse`), keyed by (sessionId, ts) so a
    // retried flush after a failed write is a no-op, not a duplicate.

    /// Idempotent insert of raw HR samples captured during a live session. Returns the number of rows
    /// ACTUALLY inserted (0 for samples that already existed — same ts already flushed).
    @discardableResult
    public func appendStrengthHR(sessionId: String, samples: [HRSample]) async throws -> Int {
        guard !samples.isEmpty else { return 0 }
        return try syncWrite { db in
            let stmt = try db.cachedStatement(sql: """
                INSERT INTO strengthHrSample (sessionId, ts, bpm) VALUES (?, ?, ?)
                ON CONFLICT(sessionId, ts) DO NOTHING
                """)
            var inserted = 0
            for s in samples {
                try stmt.execute(arguments: [sessionId, s.ts, s.bpm])
                inserted += db.changesCount
            }
            return inserted
        }
    }

    /// All HR samples captured for a session, oldest first.
    public func strengthHRSamples(sessionId: String) async throws -> [HRSample] {
        try syncRead { db in
            try Row.fetchAll(db, sql:
                "SELECT ts, bpm FROM strengthHrSample WHERE sessionId = ? ORDER BY ts ASC",
                arguments: [sessionId]
            ).map { HRSample(ts: $0["ts"], bpm: $0["bpm"]) }
        }
    }

    // MARK: - Session-effort calibration (ola 1 · E2)

    /// One session that can serve as a CALIBRATION PAIR for the session-effort scale: it carries a
    /// rating AND a pulse series. Whether the pulse is good enough (`HRCoverage`) and what TRIMP it
    /// adds up to is decided by the caller — that math lives in StrandAnalytics, which this package
    /// deliberately does not depend on.
    public struct StrengthCalibrationCandidate: Sendable, Equatable {
        public var sessionId: String
        public var startTs: Int
        public var endTs: Int
        public var sessionRpe: Double
        public var hrSamples: [HRSample]
        public init(sessionId: String, startTs: Int, endTs: Int, sessionRpe: Double,
                    hrSamples: [HRSample]) {
            self.sessionId = sessionId; self.startTs = startTs; self.endTs = endTs
            self.sessionRpe = sessionRpe; self.hrSamples = hrSamples
        }
    }

    /// The most recent sessions that can calibrate the session-effort scale, newest first: a finished
    /// session with a rating AND at least one stored HR sample. Sessions without a rating (never
    /// answered) or without any pulse can never form a pair, so they are filtered in SQL rather than
    /// carried into memory. The 0.8-coverage gate is applied by the caller over `hrSamples` — the
    /// pulse is returned WITH each candidate so a single read serves the whole fit.
    ///
    /// `limit` bounds the samples pulled into memory (each session is at most a few thousand rows)
    /// AND ends the refit ladder: the count the caller gates on can never exceed it, so with 40 the
    /// scale is refitted at 5 → 10 → 20 → 40 pairs and then stays — it has matured (gate
    /// /estadistico FER-325 #1, 2026-09-02).
    public func strengthCalibrationPairs(limit: Int = 40) async throws -> [StrengthCalibrationCandidate] {
        try syncRead { db in
            let heads = try Row.fetchAll(db, sql: """
                SELECT id, startTs, endTs, sessionRpe FROM strengthSession
                WHERE endTs IS NOT NULL AND sessionRpe IS NOT NULL
                  AND EXISTS (SELECT 1 FROM strengthHrSample WHERE sessionId = strengthSession.id)
                ORDER BY startTs DESC LIMIT ?
                """, arguments: [limit])
            return try heads.map { r in
                let id: String = r["id"]
                let samples = try Row.fetchAll(db, sql:
                    "SELECT ts, bpm FROM strengthHrSample WHERE sessionId = ? ORDER BY ts ASC",
                    arguments: [id]).map { HRSample(ts: $0["ts"], bpm: $0["bpm"]) }
                return StrengthCalibrationCandidate(sessionId: id, startTs: r["startTs"],
                                                    endTs: r["endTs"], sessionRpe: r["sessionRpe"],
                                                    hrSamples: samples)
            }
        }
    }

    /// Re-scale every ESTIMATED session onto a new `trimpPerAU`, in ONE write. Only rows whose load
    /// came from the rating (`strainSource == 'rpe'`) are touched — a measured session is a
    /// measurement and never moves. `strain` is supplied by the caller (the map lives in
    /// StrandAnalytics); a `nil` from it leaves that row alone. Returns the number of rows rewritten.
    ///
    /// Why persist at all: the receipt, the history and Tendencias must all show the same number for
    /// the same session, so a recalibration rewrites the stored value instead of being applied on read.
    @discardableResult
    public func recomputeEstimatedStrain(
        trimpPerAU: Double,
        strain: @Sendable (_ durationS: Int, _ rpe: Double) -> Double?
    ) async throws -> Int {
        try syncWrite { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, startTs, endTs, sessionRpe FROM strengthSession
                WHERE strainSource = 'rpe' AND endTs IS NOT NULL AND sessionRpe IS NOT NULL
                """)
            var rewritten = 0
            for r in rows {
                let startTs: Int = r["startTs"], endTs: Int = r["endTs"]
                let rpe: Double = r["sessionRpe"]
                guard let value = strain(endTs - startTs, rpe) else { continue }
                try db.execute(sql:
                    "UPDATE strengthSession SET strain = ?, trimpPerAU = ? WHERE id = ?",
                    arguments: [value, trimpPerAU, r["id"] as String])
                rewritten += 1
            }
            return rewritten
        }
    }

    /// Deletes all HR samples for a session (discard path — the session row itself is dropped
    /// separately, or by `deleteSession`, which also clears this table).
    public func deleteStrengthHR(sessionId: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM strengthHrSample WHERE sessionId = ?", arguments: [sessionId])
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
    ///
    /// Ola 1 · FER-327: excluye los DROPS, con el mismo filtro que la progresión (`modesCounting`), y
    /// por la misma razón: esta consulta es la semilla del peso de la próxima sesión. Un drop es el
    /// escalón de −20 % que se hizo cuando la serie ya no daba; si contara, la siguiente sesión abriría
    /// −20 % abajo y el ciclo leería una bajada que nadie decidió.
    public func lastWorkSets(exerciseId: String, limit: Int = 12) async throws -> [SetEntry] {
        try syncRead { db in
            // FER-169 · B10: a confirmed-absurd capture (the athlete answered «SÍ, 825») is still
            // saved as-is — the acta doesn't lie — but must never resurface as tomorrow's starting
            // weight. Fetch a wider buffer than `limit` so `excludingAbsurdCaptures` can drop it
            // before truncating: without the buffer, a single 8× row within the requested window
            // would just shrink the returned count instead of being replaced by the real Nth-most-
            // recent legitimate set.
            let buffered = try Row.fetchAll(db, sql: """
                SELECT * FROM setEntry WHERE exerciseId = ? AND kind = 'work' AND done = 1
                  AND \(Self.modesCounting(for: .progression))
                ORDER BY ts DESC LIMIT ?
                """, arguments: [exerciseId, limit + Self.absurdGuardBuffer]).map(Self.setEntry)
            let priorMaxKg = try Self.existingMaxWeightPR(db, exerciseId: exerciseId)
            let eligible = Self.excludingAbsurdCaptures(buffered, priorMaxKg: priorMaxKg)  // oldest→newest
            return Array(eligible.suffix(limit).reversed())  // back to newest-first, same contract as before
        }
    }

    /// Completed work sets for an exercise with their session's start time, oldest→newest — one JOIN
    /// (`setEntry` × `strengthSession`), not a query per session. The raw material the detail screen
    /// buckets by day into the estimated-1RM trend; only weight×reps sets count (1RM needs both).
    /// `optedOut` reports the session's «Volver a X» mark for this exercise (FER-835), via LEFT JOIN
    /// on `progressionOptOut` — the progression classifier skips those sessions entirely. `rpe` (v34)
    /// feeds the «QUEDABAN» read (10 − RPE); `nil` means the set never captured effort. `routineName`
    /// (LEFT JOIN `routine`) is nil for a free session or one whose routine was later deleted.
    ///
    /// The LIMIT keeps the MOST RECENT sets, not the oldest: `ORDER BY … ASC LIMIT ?` on its own would
    /// truncate a long history from the wrong end, silently dropping everything since the cap and
    /// keeping ancient sets instead (a real bug this fixed — a 601st set pushed out the newest row,
    /// not the oldest one). The subquery orders DESC to pick the newest `limit` rows, then the outer
    /// query re-sorts them ASC so every caller still sees oldest→newest.
    public func workSetHistory(exerciseId: String, limit: Int = 600) async throws -> [WorkSetHistoryRow] {
        try syncRead { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM (
                    SELECT s.id AS sessionId, s.startTs AS startTs, e.weightKg AS weightKg, e.reps AS reps,
                           (o.exerciseId IS NOT NULL) AS optedOut, e.rpe AS rpe, r.name AS routineName,
                           e.mode AS mode
                    FROM setEntry e JOIN strengthSession s ON e.sessionId = s.id
                    LEFT JOIN progressionOptOut o ON o.sessionId = e.sessionId AND o.exerciseId = e.exerciseId
                    LEFT JOIN routine r ON s.routineId = r.id
                    WHERE e.exerciseId = ? AND e.kind = 'work' AND e.done = 1
                      AND e.weightKg IS NOT NULL AND e.reps IS NOT NULL
                      AND \(Self.modesCounting(for: .progression, column: "e.mode"))
                    ORDER BY s.startTs DESC
                    LIMIT ?
                ) ORDER BY startTs ASC
                """, arguments: [exerciseId, limit]).map { (row: Row) -> WorkSetHistoryRow in
                    WorkSetHistoryRow(sessionId: row["sessionId"], startTs: row["startTs"],
                                      weightKg: row["weightKg"], reps: row["reps"],
                                      optedOut: row["optedOut"], rpe: row["rpe"],
                                      routineName: row["routineName"],
                                      mode: (row["mode"] as String?).flatMap(SetMode.init(rawValue:)) ?? .standard)
                }
            // FER-169 · B10: this feeds `ProgressionPlanner.evaluate` (via `sessionSeed`) — the "siembra"
            // consumer of the guard. Already oldest→newest, so the fold runs straight over it.
            let priorMaxKg = try Self.existingMaxWeightPR(db, exerciseId: exerciseId)
            return Self.excludingAbsurd(rows, weightKg: { $0.weightKg }, priorMaxKg: priorMaxKg)
        }
    }

    /// Descansos reales (s) de las series de trabajo hechas en las últimas `sessionLimit` sesiones de
    /// una rutina — el insumo de la tile «DESCANSO REAL» (FER-167). Plano; el promedio/el corte de
    /// interrupciones es de `RestStats` (StrandTraining), no de SQL. El LIMIT es por SESIÓN, no por
    /// fila: la subquery elige las `sessionLimit` sesiones más recientes de la rutina, y solo entonces
    /// se filtran sus `setEntry` — así una sesión antigua con muchas series no le roba cupo a una
    /// reciente con pocas. `strengthSession` no tiene índice por `routineId`; la tabla es de cientos de
    /// filas — un scan del LIMIT es barato; no se agrega índice.
    public func realRestSeconds(routineId: String, sessionLimit: Int = 10) async throws -> [Int] {
        try syncRead { db in
            try Int.fetchAll(db, sql: """
                SELECT e.restTakenS FROM setEntry e
                JOIN (SELECT id FROM strengthSession WHERE routineId = ?
                      ORDER BY startTs DESC LIMIT ?) s ON e.sessionId = s.id
                WHERE e.restTakenS IS NOT NULL AND e.kind = 'work' AND e.done = 1
                """, arguments: [routineId, sessionLimit])
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

    // MARK: - Consultas del hub v18 (FER-171 · Parte A) — SIN columnas nuevas, solo SELECTs.

    /// El PR más reciente de todo el historial (cualquier ejercicio/métrica), por `ts`. `nil` si
    /// no hay ninguno todavía.
    public func latestPersonalRecord() async throws -> PersonalRecord? {
        try syncRead { db in
            try Row.fetchOne(db, sql: "SELECT * FROM personalRecord ORDER BY ts DESC LIMIT 1")
                .map(Self.personalRecord)
        }
    }

    /// Cuántos PRs tienen `ts >= sinceTs` — «Marcas · 3 en ago».
    public func personalRecordCount(sinceTs: Double) async throws -> Int {
        try syncRead { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM personalRecord WHERE ts >= ?",
                             arguments: [Int(sinceTs)]) ?? 0
        }
    }

    /// El PR ANTERIOR del mismo ejercicio+métrica, con `ts < beforeTs` («antes 100.0 · hace 2
    /// días»). `personalRecord` guarda solo el mejor VIGENTE (una fila por ejercicio+métrica, PK
    /// compuesta) — no hay historial ahí, así que "el de antes" se re-deriva de los sets crudos
    /// (`setEntry`, done + work) anteriores a `beforeTs`, reusando `bestPRs`: el mismo criterio de
    /// "qué cuenta como marca" que ya usan el guardado (`updatePersonalRecords`) y el borrado
    /// (`recomputePR`) — nunca un segundo criterio inventado aquí. `nil` si no hay ninguno.
    public func previousPersonalRecord(exerciseId: String, metric: PRMetric,
                                       beforeTs: Double) async throws -> PersonalRecord? {
        try syncRead { db in
            let work = try Row.fetchAll(db, sql: """
                SELECT * FROM setEntry
                WHERE exerciseId = ? AND kind = 'work' AND done = 1 AND ts < ?
                """, arguments: [exerciseId, Int(beforeTs)]).map(Self.setEntry)
            // FER-169 · B10: same absurd-capture exclusion as the save/delete paths — "el de antes"
            // must never be an 8× typo either.
            let best = Self.bestPRs(work, exerciseId: exerciseId)
            switch metric {
            case .maxWeight: return best.maxWeight
            case .maxReps:   return best.maxReps
            case .maxVolume: return best.maxVolume
            }
        }
    }

    private static func session(_ r: Row) -> StrengthSession {
        StrengthSession(id: r["id"], routineId: r["routineId"], startTs: r["startTs"], endTs: r["endTs"],
                        deviceId: r["deviceId"], strain: r["strain"], avgHr: r["avgHr"], notes: r["notes"],
                        energyKcal: r["energyKcal"],
                        energySource: (r["energySource"] as String?).flatMap(EnergySource.init(rawValue:)),
                        strainSource: (r["strainSource"] as String?).flatMap(StrainSource.init(rawValue:)),
                        sessionRpe: r["sessionRpe"],
                        sessionRpeSource: (r["sessionRpeSource"] as String?).flatMap(SessionRpeSource.init(rawValue:)),
                        trimpPerAU: r["trimpPerAU"], source: r["source"], title: r["title"],
                        programWeek: r["programWeek"],
                        deload: (r["deload"] as Int?).map { $0 != 0 })
    }

    private static func setEntry(_ r: Row) -> SetEntry {
        SetEntry(id: r["id"], sessionId: r["sessionId"], exerciseId: r["exerciseId"], position: r["position"],
                 kind: SetKind(rawValue: r["kind"]) ?? .work, weightKg: r["weightKg"], reps: r["reps"],
                 timeS: r["timeS"], distanceM: r["distanceM"], done: (r["done"] as Int) != 0, ts: r["ts"],
                 rpe: r["rpe"], restTakenS: r["restTakenS"],
                 mode: (r["mode"] as String?).flatMap(SetMode.init(rawValue:)) ?? .standard)
    }

    private static func personalRecord(_ r: Row) -> PersonalRecord {
        var pr = PersonalRecord(exerciseId: r["exerciseId"],
                                metric: PRMetric(rawValue: r["metric"]) ?? .maxWeight,
                                valueKg: r["valueKg"], reps: r["reps"], ts: r["ts"])
        pr.id = r["id"]
        return pr
    }

    // MARK: - PR derivation

    // MARK: - `SetMode` en SQL y la invariante de adyacencia del drop (ola 1 · FER-327)

    /// El fragmento SQL que deja pasar solo los modos que SÍ alimentan `rule` — **derivado de
    /// `SetMode.counts(for:)`, no escrito a mano**. Es lo que mantiene UN solo oráculo cuando la regla
    /// tiene que aplicarse dentro de la consulta (por el LIMIT: filtrar en Swift después de truncar
    /// devolvería menos filas de las pedidas). Si mañana un modo nuevo deja de contar para progresión,
    /// el SQL cambia solo. `NULL` = `.standard` (la convención de la columna desde v42).
    ///
    /// Interpolar aquí es seguro y no es una inyección: los valores salen de `SetMode.allCases`, un
    /// enum del código, nunca de datos del usuario.
    static func modesCounting(for rule: SetRule, column: String = "mode") -> String {
        let excluded = SetMode.allCases.filter { !$0.counts(for: rule) }
        guard !excluded.isEmpty else { return "1" }
        let list = excluded.map { "'\($0.rawValue)'" }.joined(separator: ", ")
        return "(\(column) IS NULL OR \(column) NOT IN (\(list)))"
    }

    /// La invariante de adyacencia del drop, aplicada AL GUARDAR (FER-327 · E6).
    ///
    /// Un drop no tiene FK a su madre: la relación es el ORDEN — «pertenece a la serie no-drop
    /// inmediatamente anterior del mismo ejercicio». Para que esa relación no pueda mentir, el store
    /// normaliza el orden antes de escribir: cada drop queda pegado a su madre (detrás de los escalones
    /// que ya colgaban de ella), y las posiciones se renumeran 0…n−1 en ese orden final.
    ///
    /// Tres cosas que esta función NO hace, a propósito (v3 · N4):
    /// - **No promueve huérfanos.** Un drop sin ninguna no-drop antes en su ejercicio (quedó en la
    ///   posición 0 porque su madre se borró) CONSERVA `mode = .drop`: cuenta solo para volumen y se
    ///   pinta «↳». Convertirlo en serie de trabajo lo metería al ciclo y a los récords a un peso que
    ///   nunca fue de trabajo — exactamente lo que el modo existe para evitar.
    /// - **No borra nada.** Ninguna fila se pierde por estar mal ordenada.
    /// - **No toca una sesión sin drops.** Sin un solo `.drop` devuelve la entrada TAL CUAL (misma
    ///   identidad de orden y de posiciones), así que ninguna sesión anterior a la ola 1 cambia.
    static func enforcingDropAdjacency(_ sets: [SetEntry]) -> [SetEntry] {
        guard sets.contains(where: { $0.mode == .drop }) else { return sets }
        // Orden estable por posición (los empates conservan el orden de entrada).
        let ordered = sets.enumerated()
            .sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }
            .map(\.element)

        // Por ejercicio: a qué madre (id de la no-drop anterior) cuelga cada drop. nil = huérfano.
        var motherOfDrop: [String: String] = [:]          // id del drop → id de la madre
        var dropsOfMother: [String: [SetEntry]] = [:]      // id de la madre → sus escalones, en orden
        var lastNonDropPerExercise: [String: String] = [:]
        for set in ordered {
            guard set.mode == .drop else {
                lastNonDropPerExercise[set.exerciseId] = set.id
                continue
            }
            if let mother = lastNonDropPerExercise[set.exerciseId] {
                motherOfDrop[set.id] = mother
                dropsOfMother[mother, default: []].append(set)
            }
            // Sin madre: huérfano. Se queda donde está, con su modo intacto.
        }

        var out: [SetEntry] = []
        for set in ordered {
            if set.mode == .drop, motherOfDrop[set.id] != nil { continue }   // sale con su madre
            out.append(set)
            for drop in dropsOfMother[set.id] ?? [] { out.append(drop) }
        }
        for i in out.indices { out[i].position = i }
        return out
    }

    /// FER-169 · B10 — how many EXTRA rows `lastWorkSets` fetches beyond `limit` so an absurd capture
    /// within the window can be dropped and still leave `limit` real rows to return. Absurd captures
    /// are rare (one fat-finger event, not a pattern), so a small fixed cushion is plenty.
    private static let absurdGuardBuffer = 8

    /// The exercise's current maxWeight `PersonalRecord`, or nil with none yet — the reference the
    /// guard folds from when there's no earlier row in the batch being judged itself (FER-169 · B10).
    private static func existingMaxWeightPR(_ db: Database, exerciseId: String) throws -> Double? {
        let id = PersonalRecord(exerciseId: exerciseId, metric: .maxWeight, ts: 0).id
        return try Row.fetchOne(db, sql: "SELECT * FROM personalRecord WHERE id = ?", arguments: [id])
            .map(personalRecord)?.valueKg
    }

    /// FER-169 · B10 — the one fold every "what's the best/most-recent weight" reader defers to:
    /// walking `itemsAscending` (oldest→newest) left to right, an item is dropped when its weight is
    /// `CaptureGuard.isAbsurd` against the best weight already ACCEPTED so far (seeded with
    /// `priorMaxKg`, typically the exercise's existing PR) — never seen, never counted toward later
    /// comparisons, and never able to poison anything after it. No persisted flag: the same recompute
    /// runs independently wherever history is read.
    private static func excludingAbsurd<T>(_ itemsAscending: [T], weightKg: (T) -> Double?,
                                           priorMaxKg: Double?) -> [T] {
        var bestKg = priorMaxKg ?? 0
        return itemsAscending.filter { item in
            guard let w = weightKg(item) else { return true }   // time/distance — the guard doesn't apply
            guard !CaptureGuard.isAbsurd(weightKg: w, referenceKg: bestKg) else { return false }
            bestKg = max(bestKg, w)
            return true
        }
    }

    /// `excludingAbsurd` specialized to `SetEntry`, sorting by `ts` first (callers don't have to).
    private static func excludingAbsurdCaptures(_ sets: [SetEntry], priorMaxKg: Double? = nil) -> [SetEntry] {
        excludingAbsurd(sets.sorted { $0.ts < $1.ts }, weightKg: \.weightKg, priorMaxKg: priorMaxKg)
    }

    /// The 3 candidate PRs (best weight / reps / volume) from a set of *done work* sets for one exercise;
    /// each is nil when no set qualifies. The single source of "what counts as a record" — shared by the
    /// save path (`updatePersonalRecords`, upgrade-only), the delete path (`recomputePR`, write-exact)
    /// and `previousPersonalRecord`. `priorMaxKg` (FER-169 · B10) seeds the absurd-capture fold with the
    /// exercise's PR BEFORE `work` — needed by `updatePersonalRecords`, which only ever sees one
    /// session's own new sets, not the history an 8× capture there needs to be judged against. The
    /// full-history callers (`recomputePR`, `previousPersonalRecord`) pass nil: their own `work` already
    /// spans every session, so the chronological fold alone is a complete reference.
    private static func bestPRs(_ work: [SetEntry], exerciseId: String, priorMaxKg: Double? = nil)
        -> (maxWeight: PersonalRecord?, maxReps: PersonalRecord?, maxVolume: PersonalRecord?) {
        // Ola 1 · FER-327: el ÚNICO punto donde se decide qué serie puede ser récord — los tres call
        // sites (guardar, recomputar tras un borrado, «el de antes») pasan por aquí, así que la regla
        // se escribe una vez. `counts(for: .records)` ya incluye `kind == .work && done`, de modo que
        // los filtros que los llamadores ya traían siguen intactos (redundantes, no editados): un drop
        // es trabajo de verdad, pero a un peso que el cuerpo ya no aguantaba — no es un récord.
        let eligible = excludingAbsurdCaptures(work.filter { $0.counts(for: .records) },
                                               priorMaxKg: priorMaxKg)
        let maxWeight = eligible.compactMap { s in s.weightKg.map { (v: $0, ts: s.ts) } }.max { $0.v < $1.v }
            .map { PersonalRecord(exerciseId: exerciseId, metric: .maxWeight, valueKg: $0.v, ts: $0.ts) }
        let maxReps = eligible.compactMap { s in s.reps.map { (v: $0, ts: s.ts) } }.max { $0.v < $1.v }
            .map { PersonalRecord(exerciseId: exerciseId, metric: .maxReps, reps: $0.v, ts: $0.ts) }
        let maxVolume = eligible.compactMap { s -> (vol: Double, w: Double, reps: Int, ts: Int)? in
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
            // FER-169 · B10: this exercise's PR BEFORE today's sets — the reference an 8× capture in
            // `exSets` (which only holds THIS session's own new rows) must be judged against.
            let priorMaxKg = try existingMaxWeightPR(db, exerciseId: exerciseId)
            let best = bestPRs(exSets, exerciseId: exerciseId, priorMaxKg: priorMaxKg)
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
