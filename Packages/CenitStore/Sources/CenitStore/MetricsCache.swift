import Foundation
import GRDB
import StrandModels

// MARK: - Local cache of on-device computed metrics
// DailyMetric and CachedSleepSession are durable local caches of values computed ON-DEVICE by
// StrandAnalytics (and import glue). Nothing is pulled from a remote service — History is the
// union of raw streams + these derived metric caches, all written and read on the phone.
// Value types live in StrandModels; re-exported here so existing CenitStore consumers are unchanged.

public typealias DailyMetric = StrandModels.DailyMetric
public typealias CachedSleepSession = StrandModels.CachedSleepSession

extension CenitStore {

    // MARK: - Upserts (idempotent by natural key; latest server value wins on conflict)

    /// Upsert cached sleep sessions. Natural key (deviceId, startTs). Returns rows changed.
    @discardableResult
    public func upsertSleepSessions(_ sessions: [CachedSleepSession], deviceId: String) async throws -> Int {
        try syncWrite { db in
            var n = 0
            for s in sessions {
                try db.execute(sql: """
                    INSERT INTO sleepSession
                        (deviceId, startTs, endTs, efficiency, restingHr, avgHrv, stagesJSON)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(deviceId, startTs) DO UPDATE SET
                        endTs = excluded.endTs,
                        efficiency = excluded.efficiency,
                        restingHr = excluded.restingHr,
                        avgHrv = excluded.avgHrv,
                        stagesJSON = excluded.stagesJSON
                    """, arguments: [deviceId, s.startTs, s.endTs, s.efficiency,
                                     s.restingHr, s.avgHrv, s.stagesJSON])
                n += db.changesCount
            }
            return n
        }
    }

    /// Upsert cached daily metrics. Natural key (deviceId, day). Returns rows changed.
    ///
    /// The on-conflict update is MONOTONIC (FER-407): each column is `COALESCE(excluded.X, X)`, so a
    /// `nil` in the incoming row PRESERVES the existing value instead of blanking it — a real new value
    /// still overwrites. This stops a partial recompute from regressing a complete row: the on-device
    /// engine re-scores every night in its window each pass, and a night whose sleep session isn't
    /// (yet) detected returns `totalSleepMin/avgHrv/recovery == nil`. Without COALESCE, such a pass would
    /// wipe a previously-good day back to NULL. To CLEAR a day, delete it (`deleteDailyMetrics`); no
    /// caller relies on a nil-upsert to clear, and rows from different sources never share a key.
    @discardableResult
    public func upsertDailyMetrics(_ days: [DailyMetric], deviceId: String) async throws -> Int {
        // Batch into multi-row INSERTs rather than one statement per day: 20 bound vars/row,
        // SQLite's limit is 999, so 49 rows/statement (980 vars) is a safe, large batch. Mirrors
        // `upsertMetricSeries`. One-INSERT-per-row meant a statement round-trip per day inside the
        // transaction — needless overhead on a multi-year import that spans thousands of days.
        try syncWrite { db in
            var n = 0
            let perRow = "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"   // 20 cols
            for chunk in stride(from: 0, to: days.count, by: 49).map({ Array(days[$0..<min($0 + 49, days.count)]) }) {
                let values = Array(repeating: perRow, count: chunk.count).joined(separator: ", ")
                var args: [DatabaseValueConvertible?] = []
                args.reserveCapacity(chunk.count * 20)
                for d in chunk {
                    args.append(contentsOf: [deviceId, d.day, d.totalSleepMin, d.efficiency, d.deepMin,
                                             d.remMin, d.lightMin, d.disturbances, d.restingHr, d.avgHrv,
                                             d.recovery, d.strain, d.exerciseCount,
                                             d.spo2Pct, d.skinTempDevC, d.respRateBpm,
                                             d.steps, d.activeKcalEst,
                                             d.effortConfidence, d.restConfidence] as [DatabaseValueConvertible?])
                }
                try db.execute(sql: """
                    INSERT INTO dailyMetric
                        (deviceId, day, totalSleepMin, efficiency, deepMin, remMin, lightMin,
                         disturbances, restingHr, avgHrv, recovery, strain, exerciseCount,
                         spo2Pct, skinTempDevC, respRateBpm, steps, activeKcalEst,
                         effortConfidence, restConfidence)
                    VALUES \(values)
                    ON CONFLICT(deviceId, day) DO UPDATE SET
                        totalSleepMin = COALESCE(excluded.totalSleepMin, totalSleepMin),
                        efficiency = COALESCE(excluded.efficiency, efficiency),
                        deepMin = COALESCE(excluded.deepMin, deepMin),
                        remMin = COALESCE(excluded.remMin, remMin),
                        lightMin = COALESCE(excluded.lightMin, lightMin),
                        disturbances = COALESCE(excluded.disturbances, disturbances),
                        restingHr = COALESCE(excluded.restingHr, restingHr),
                        avgHrv = COALESCE(excluded.avgHrv, avgHrv),
                        recovery = COALESCE(excluded.recovery, recovery),
                        -- CARGA VIVA: strain is monotonic in the "real load" direction. A scored
                        -- workout (excluded.strain > 0) always wins; a persisted load (strain > 0) is
                        -- NEVER regressed to a 0 (rest) or NULL (missing) by a later partial/degraded
                        -- resync (e.g. workout HR not yet delivered, or read permission revoked).
                        -- Only rest(0) and missing(NULL) may correct each other — so a false rest 0
                        -- written from incomplete data can still be walked back to NULL when the day
                        -- reclassifies missing. (Fable adversarial D1.)
                        strain = CASE
                            WHEN excluded.strain > 0 THEN excluded.strain
                            WHEN strain > 0 THEN strain
                            ELSE excluded.strain
                        END,
                        exerciseCount = COALESCE(excluded.exerciseCount, exerciseCount),
                        spo2Pct = COALESCE(excluded.spo2Pct, spo2Pct),
                        skinTempDevC = COALESCE(excluded.skinTempDevC, skinTempDevC),
                        respRateBpm = COALESCE(excluded.respRateBpm, respRateBpm),
                        steps = COALESCE(excluded.steps, steps),
                        activeKcalEst = COALESCE(excluded.activeKcalEst, activeKcalEst),
                        effortConfidence = COALESCE(excluded.effortConfidence, effortConfidence),
                        restConfidence = COALESCE(excluded.restConfidence, restConfidence)
                    """, arguments: StatementArguments(args))
                n += db.changesCount
            }
            return n
        }
    }

    /// Delete cached daily-metrics rows for specific `(deviceId, day)` keys. Used by the one-time
    /// day-key re-bucket (FER-226) to prune the rows orphaned when their `day` was re-dated UTC→local
    /// — e.g. the spurious future-in-local row this evening's data used to materialize in a UTC−
    /// zone. No-op on an empty list. Returns rows deleted.
    @discardableResult
    public func deleteDailyMetrics(deviceId: String, days: [String]) async throws -> Int {
        guard !days.isEmpty else { return 0 }
        return try syncWrite { db in
            let placeholders = Array(repeating: "?", count: days.count).joined(separator: ", ")
            try db.execute(sql: """
                DELETE FROM dailyMetric WHERE deviceId = ? AND day IN (\(placeholders))
                """, arguments: StatementArguments([deviceId] + days))
            return db.changesCount
        }
    }

    // MARK: - Reads

    /// Cached sleep sessions that OVERLAP `[from, to]`, oldest first. A session `[s, e]` overlaps the
    /// window iff `s <= to AND e >= from` — so a night that began before `from` (e.g. asleep before local
    /// midnight) but runs into the window is still returned. Filtering on `startTs` alone would drop it,
    /// leaving the post-midnight sleep un-excluded from the intraday stress curve (FER-448).
    public func sleepSessions(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [CachedSleepSession] {
        // FER-970 (R-03): row SQL/mapping shared with `dashboardSnapshot` via the fetch helper.
        try syncRead { db in
            try Self.fetchSleepSessions(db, deviceId: deviceId, from: from, to: to, limit: limit)
        }
    }

    /// Cached daily metrics for days in [from, to] (lexicographic YYYY-MM-DD compare), oldest first.
    public func dailyMetrics(deviceId: String, from: String, to: String) async throws -> [DailyMetric] {
        // FER-970 (R-03): row SQL/mapping shared with `dashboardSnapshot` via the fetch helper.
        try syncRead { db in
            try Self.fetchDailyMetrics(db, deviceId: deviceId, from: from, to: to)
        }
    }
}
