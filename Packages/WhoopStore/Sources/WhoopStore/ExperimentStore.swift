import Foundation
import GRDB

// MARK: - v12 cache: N-of-1 experiments (FER-307)
// One row per experiment, natural key `id` (UUID). An experiment runs a candidate lever — a logged
// behavior × an outcome metric — for a fixed window, then a verdict (computed in StrandAnalytics over
// the existing journal/dailyMetric data) may promote the lever candidate→proven. Mirrors the
// JournalWorkoutAppleCache pattern: a Codable struct, an idempotent upsert keyed by natural key, and
// range/active reads, all via the actor's syncWrite/syncRead helpers (off the main thread).
//
// MVP is one experiment at a time — that invariant is enforced by the app (it won't create a new
// `running` row while one exists), not the schema; the table keeps the full history of past
// experiments so the record is never lost.

/// The lifecycle state of an experiment.
public enum ExperimentStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case running     // window open, no verdict yet
    case completed   // window elapsed, verdict computed
    case canceled    // ended early by the user, no verdict
}

/// One N-of-1 experiment. Natural key `id`. Result columns are nil until a verdict is computed.
/// `result` is the raw string of StrandAnalytics' `Verdict` (kept as a String so WhoopStore stays
/// free of an analytics dependency).
public struct ExperimentRow: Equatable, Codable, Sendable {
    public let id: String
    public let behavior: String          // lever: journal question
    public let outcome: String           // target metric label (es-MX)
    public let expectedSign: Int         // +1/-1: sign of the candidate's observed effect
    public let startDay: String          // YYYY-MM-DD (local civil day)
    public let windowDays: Int           // experiment length (MVP default 7)
    public let status: ExperimentStatus
    public let result: String?           // Verdict.rawValue when completed
    public let effectDelta: Double?      // verdict: meanWith − meanWithout
    public let effectSize: Double?       // verdict: Cohen's d
    public let pValue: Double?           // verdict: Welch p
    public let nWith: Int?               // adherent-day count
    public let nWithout: Int?            // baseline-day count
    public let createdAt: Int            // unix seconds
    public let decidedAt: Int?           // unix seconds (verdict time)

    public init(id: String, behavior: String, outcome: String, expectedSign: Int,
                startDay: String, windowDays: Int, status: ExperimentStatus,
                result: String? = nil, effectDelta: Double? = nil, effectSize: Double? = nil,
                pValue: Double? = nil, nWith: Int? = nil, nWithout: Int? = nil,
                createdAt: Int, decidedAt: Int? = nil) {
        self.id = id; self.behavior = behavior; self.outcome = outcome
        self.expectedSign = expectedSign; self.startDay = startDay; self.windowDays = windowDays
        self.status = status; self.result = result; self.effectDelta = effectDelta
        self.effectSize = effectSize; self.pValue = pValue; self.nWith = nWith
        self.nWithout = nWithout; self.createdAt = createdAt; self.decidedAt = decidedAt
    }
}

extension WhoopStore {

    // MARK: - Upsert (idempotent by id; latest value wins on conflict)

    /// Insert or update one experiment by its `id`. Used both to create a `running` experiment and to
    /// write back the verdict on completion / cancel. Returns rows changed.
    @discardableResult
    public func upsertExperiment(_ r: ExperimentRow, deviceId: String) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO experiment
                    (id, deviceId, behavior, outcome, expectedSign, startDay, windowDays, status,
                     result, effectDelta, effectSize, pValue, nWith, nWithout, createdAt, decidedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    behavior = excluded.behavior,
                    outcome = excluded.outcome,
                    expectedSign = excluded.expectedSign,
                    startDay = excluded.startDay,
                    windowDays = excluded.windowDays,
                    status = excluded.status,
                    result = excluded.result,
                    effectDelta = excluded.effectDelta,
                    effectSize = excluded.effectSize,
                    pValue = excluded.pValue,
                    nWith = excluded.nWith,
                    nWithout = excluded.nWithout,
                    decidedAt = excluded.decidedAt
                """, arguments: [r.id, deviceId, r.behavior, r.outcome, r.expectedSign, r.startDay,
                                 r.windowDays, r.status.rawValue, r.result, r.effectDelta, r.effectSize,
                                 r.pValue, r.nWith, r.nWithout, r.createdAt, r.decidedAt])
            return db.changesCount
        }
    }

    // MARK: - Reads

    /// The current `running` experiment for `deviceId` (the most recently created one, if several
    /// somehow exist). nil when there is no experiment in flight. MVP is one at a time.
    public func activeExperiment(deviceId: String) async throws -> ExperimentRow? {
        try syncRead { db in
            try Row.fetchOne(db, sql: """
                SELECT \(Self.experimentColumns) FROM experiment
                WHERE deviceId = ? AND status = 'running'
                ORDER BY createdAt DESC LIMIT 1
                """, arguments: [deviceId]).map(Self.experimentRow)
        }
    }

    /// All experiments for `deviceId`, newest first. The app derives the set of proven levers from the
    /// `completed` + `sustained` rows and renders the experiment history.
    public func experiments(deviceId: String) async throws -> [ExperimentRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT \(Self.experimentColumns) FROM experiment
                WHERE deviceId = ?
                ORDER BY createdAt DESC
                """, arguments: [deviceId]).map(Self.experimentRow)
        }
    }

    // MARK: - Row mapping

    private static let experimentColumns = """
        id, behavior, outcome, expectedSign, startDay, windowDays, status, result,
        effectDelta, effectSize, pValue, nWith, nWithout, createdAt, decidedAt
        """

    private static func experimentRow(_ row: Row) -> ExperimentRow {
        ExperimentRow(
            id: row["id"], behavior: row["behavior"], outcome: row["outcome"],
            expectedSign: row["expectedSign"], startDay: row["startDay"], windowDays: row["windowDays"],
            status: ExperimentStatus(rawValue: row["status"]) ?? .running,
            result: row["result"], effectDelta: row["effectDelta"], effectSize: row["effectSize"],
            pValue: row["pValue"], nWith: row["nWith"], nWithout: row["nWithout"],
            createdAt: row["createdAt"], decidedAt: row["decidedAt"])
    }
}
