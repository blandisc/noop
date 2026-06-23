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

extension WhoopStore {

    // MARK: - Custom exercises (user-created; the bundled catalog lives in StrandTraining)

    public func saveCustomExercise(_ e: Exercise) async throws {
        try syncWrite { db in
            let args: [DatabaseValueConvertible?] = [
                e.id, e.name, e.type.rawValue, e.equipment,
                encodeJSON(e.primaryMuscles), encodeJSON(e.secondaryMuscles), encodeJSON(e.cues)
            ]
            try db.execute(sql: """
                INSERT INTO customExercise (id, name, type, equipment, primaryMuscles, secondaryMuscles, cues)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name, type = excluded.type, equipment = excluded.equipment,
                    primaryMuscles = excluded.primaryMuscles, secondaryMuscles = excluded.secondaryMuscles,
                    cues = excluded.cues
                """, arguments: StatementArguments(args))
        }
    }

    public func customExercises() async throws -> [Exercise] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM customExercise ORDER BY name ASC").map(Self.exercise)
        }
    }

    public func deleteCustomExercise(id: String) async throws {
        try syncWrite { db in try db.execute(sql: "DELETE FROM customExercise WHERE id = ?", arguments: [id]) }
    }

    private static func exercise(_ r: Row) -> Exercise {
        Exercise(id: r["id"], name: r["name"],
                 type: ExerciseType(rawValue: r["type"]) ?? .weightReps,
                 equipment: r["equipment"],
                 primaryMuscles: decodeJSON(r["primaryMuscles"], as: [String].self, default: []),
                 secondaryMuscles: decodeJSON(r["secondaryMuscles"], as: [String].self, default: []),
                 cues: decodeJSON(r["cues"], as: [String].self, default: []))
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
                    re.supersetGroup, re.hrRestReference.rawValue, re.hrRestValue
                ]
                try db.execute(sql: """
                    INSERT INTO routineExercise
                        (id, routineId, exerciseId, position, targetSets, targetReps, targetWeightKg,
                         warmupPercents, restMode, restSeconds, supersetGroup, hrRestReference, hrRestValue)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: StatementArguments(args))
                for (idx, s) in planned.enumerated() {
                    let sArgs: [DatabaseValueConvertible?] = [
                        s.id, re.id, idx, s.kind.rawValue, s.reps, s.weightKg
                    ]
                    try db.execute(sql: """
                        INSERT INTO routineSet (id, routineExerciseId, position, kind, reps, weightKg)
                        VALUES (?, ?, ?, ?, ?, ?)
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
                        hrRestValue: r["hrRestValue"])
    }

    private static func routineSet(_ r: Row) -> RoutineSet {
        RoutineSet(id: r["id"], position: r["position"],
                   kind: SetKind(rawValue: r["kind"]) ?? .work,
                   reps: r["reps"], weightKg: r["weightKg"])
    }

    // MARK: - Sessions + sets (+ PR derivation, transactional)

    /// Save a session and replace its sets in one transaction, then update PRs from the work sets.
    public func saveSession(_ session: StrengthSession, sets: [SetEntry]) async throws {
        try syncWrite { db in
            let sArgs: [DatabaseValueConvertible?] = [
                session.id, session.routineId, session.startTs, session.endTs,
                session.deviceId, session.strain, session.avgHr, session.notes
            ]
            try db.execute(sql: """
                INSERT INTO strengthSession (id, routineId, startTs, endTs, deviceId, strain, avgHr, notes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    routineId = excluded.routineId, endTs = excluded.endTs, deviceId = excluded.deviceId,
                    strain = excluded.strain, avgHr = excluded.avgHr, notes = excluded.notes
                """, arguments: StatementArguments(sArgs))

            try db.execute(sql: "DELETE FROM setEntry WHERE sessionId = ?", arguments: [session.id])
            for s in sets {
                let args: [DatabaseValueConvertible?] = [
                    s.id, s.sessionId, s.exerciseId, s.position, s.kind.rawValue,
                    s.weightKg, s.reps, s.timeS, s.distanceM, s.done ? 1 : 0, s.ts
                ]
                try db.execute(sql: """
                    INSERT INTO setEntry
                        (id, sessionId, exerciseId, position, kind, weightKg, reps, timeS, distanceM, done, ts)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: StatementArguments(args))
            }
            try Self.updatePersonalRecords(db, sets: sets)
        }
    }

    public func recentSessions(limit: Int = 200) async throws -> [StrengthSession] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM strengthSession ORDER BY startTs DESC LIMIT ?",
                             arguments: [limit]).map(Self.session)
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
    public func workSetHistory(exerciseId: String, limit: Int = 600) async throws
        -> [(startTs: Int, weightKg: Double, reps: Int)] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT s.startTs AS startTs, e.weightKg AS weightKg, e.reps AS reps
                FROM setEntry e JOIN strengthSession s ON e.sessionId = s.id
                WHERE e.exerciseId = ? AND e.kind = 'work' AND e.done = 1
                  AND e.weightKg IS NOT NULL AND e.reps IS NOT NULL
                ORDER BY s.startTs ASC
                LIMIT ?
                """, arguments: [exerciseId, limit]).map {
                    (startTs: $0["startTs"], weightKg: $0["weightKg"], reps: $0["reps"])
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
                        deviceId: r["deviceId"], strain: r["strain"], avgHr: r["avgHr"], notes: r["notes"])
    }

    private static func setEntry(_ r: Row) -> SetEntry {
        SetEntry(id: r["id"], sessionId: r["sessionId"], exerciseId: r["exerciseId"], position: r["position"],
                 kind: SetKind(rawValue: r["kind"]) ?? .work, weightKg: r["weightKg"], reps: r["reps"],
                 timeS: r["timeS"], distanceM: r["distanceM"], done: (r["done"] as Int) != 0, ts: r["ts"])
    }

    private static func personalRecord(_ r: Row) -> PersonalRecord {
        var pr = PersonalRecord(exerciseId: r["exerciseId"],
                                metric: PRMetric(rawValue: r["metric"]) ?? .maxWeight,
                                valueKg: r["valueKg"], reps: r["reps"], ts: r["ts"])
        pr.id = r["id"]
        return pr
    }

    // MARK: - PR derivation

    /// Update best-per-exercise PRs from a session's *done work* sets. Only upgrades an existing PR;
    /// never downgrades. (Estimated-1RM is FER-349's analytics, not stored here.)
    private static func updatePersonalRecords(_ db: Database, sets: [SetEntry]) throws {
        let work = sets.filter { $0.kind == .work && $0.done }
        let byExercise = Dictionary(grouping: work, by: \.exerciseId)
        for (exerciseId, exSets) in byExercise {
            // maxWeight: heaviest single set
            if let best = exSets.compactMap({ s in s.weightKg.map { ($0, s.ts) } }).max(by: { $0.0 < $1.0 }) {
                try upsertPR(db, PersonalRecord(exerciseId: exerciseId, metric: .maxWeight,
                                                valueKg: best.0, ts: best.1))
            }
            // maxReps: most reps at any load
            if let best = exSets.compactMap({ s in s.reps.map { ($0, s.ts) } }).max(by: { $0.0 < $1.0 }) {
                try upsertPR(db, PersonalRecord(exerciseId: exerciseId, metric: .maxReps,
                                                reps: best.0, ts: best.1))
            }
            // maxVolume: best weight×reps in one set
            if let best = exSets.compactMap({ s -> (Double, Double, Int, Int)? in
                guard let w = s.weightKg, let reps = s.reps else { return nil }
                return (w * Double(reps), w, reps, s.ts)
            }).max(by: { $0.0 < $1.0 }) {
                try upsertPR(db, PersonalRecord(exerciseId: exerciseId, metric: .maxVolume,
                                                valueKg: best.1, reps: best.2, ts: best.3))
            }
        }
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
