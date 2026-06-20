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
                routine.id, routine.name, routine.tag, routine.createdTs, routine.updatedTs, routine.sortOrder
            ]
            try db.execute(sql: """
                INSERT INTO routine (id, name, tag, createdTs, updatedTs, sortOrder)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name, tag = excluded.tag,
                    updatedTs = excluded.updatedTs, sortOrder = excluded.sortOrder
                """, arguments: StatementArguments(rArgs))

            try db.execute(sql: "DELETE FROM routineExercise WHERE routineId = ?", arguments: [routine.id])
            for re in exercises {
                let args: [DatabaseValueConvertible?] = [
                    re.id, re.routineId, re.exerciseId, re.position, re.targetSets, re.targetReps,
                    re.targetWeightKg, encodeJSON(re.warmupPercents), re.restMode.rawValue, re.restSeconds
                ]
                try db.execute(sql: """
                    INSERT INTO routineExercise
                        (id, routineId, exerciseId, position, targetSets, targetReps, targetWeightKg,
                         warmupPercents, restMode, restSeconds)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: StatementArguments(args))
            }
        }
    }

    public func routines() async throws -> [Routine] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "SELECT * FROM routine ORDER BY sortOrder ASC, updatedTs DESC").map {
                Routine(id: $0["id"], name: $0["name"], tag: $0["tag"],
                        createdTs: $0["createdTs"], updatedTs: $0["updatedTs"], sortOrder: $0["sortOrder"])
            }
        }
    }

    public func routineExercises(routineId: String) async throws -> [RoutineExercise] {
        try syncRead { db in
            try Row.fetchAll(db, sql:
                "SELECT * FROM routineExercise WHERE routineId = ? ORDER BY position ASC",
                arguments: [routineId]).map {
                    RoutineExercise(id: $0["id"], routineId: $0["routineId"], exerciseId: $0["exerciseId"],
                                    position: $0["position"], targetSets: $0["targetSets"],
                                    targetReps: $0["targetReps"], targetWeightKg: $0["targetWeightKg"],
                                    warmupPercents: decodeJSON($0["warmupPercents"], as: [Double].self, default: []),
                                    restMode: RestMode(rawValue: $0["restMode"]) ?? .heartRate,
                                    restSeconds: $0["restSeconds"])
                }
        }
    }

    public func deleteRoutine(id: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM routineExercise WHERE routineId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM routine WHERE id = ?", arguments: [id])
        }
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

    /// The most recent *work* sets for an exercise, newest first — powers "la última vez" pre-fill.
    public func lastWorkSets(exerciseId: String, limit: Int = 12) async throws -> [SetEntry] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM setEntry WHERE exerciseId = ? AND kind = 'work' AND done = 1
                ORDER BY ts DESC LIMIT ?
                """, arguments: [exerciseId, limit]).map(Self.setEntry)
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
                isBetter = (pr.valueKg ?? 0) * Double(pr.reps ?? 0)
                         > (existing.valueKg ?? 0) * Double(existing.reps ?? 0)
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
