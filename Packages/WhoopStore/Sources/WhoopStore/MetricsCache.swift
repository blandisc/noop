import Foundation
import GRDB

// MARK: - Offline cache of SERVER-computed metrics (Task 3.1 → M0.4)
// This file is purely a local cache of values computed by the server — the phone does NO metric
// computation here. DailyMetric and CachedSleepSession mirror the server's daily_metrics /
// sleep_sessions tables and are cached locally so History = union(phone-collected raw streams,
// server-computed derived metrics). ServerSync.pull() populates this cache; MetricsRepository
// reads it for the view layer.

/// One cached sleep session pulled from the server's /v1/sleep. Natural key (deviceId, startTs).
/// `stagesJSON` is the verbatim JSON array of stage segments ([{start,end,stage}]) — stored as a
/// string so the cache stays schema-agnostic about the staging shape.
public struct CachedSleepSession: Equatable, Codable {
    public let startTs: Int          // unix seconds
    public let endTs: Int            // unix seconds
    public let efficiency: Double?
    public let restingHr: Int?
    public let avgHrv: Double?
    public let stagesJSON: String?
    public init(startTs: Int, endTs: Int, efficiency: Double?, restingHr: Int?,
                avgHrv: Double?, stagesJSON: String?) {
        self.startTs = startTs; self.endTs = endTs
        self.efficiency = efficiency; self.restingHr = restingHr
        self.avgHrv = avgHrv; self.stagesJSON = stagesJSON
    }
}

/// One cached daily-metrics row pulled from the server's /v1/daily. Natural key (deviceId, day).
public struct DailyMetric: Equatable, Codable {
    public let day: String           // YYYY-MM-DD
    public let totalSleepMin: Double?
    public let efficiency: Double?
    public let deepMin: Double?
    public let remMin: Double?
    public let lightMin: Double?
    public let disturbances: Int?
    public let restingHr: Int?
    public let avgHrv: Double?
    public let recovery: Double?
    public let strain: Double?
    public let exerciseCount: Int?
    // In-sleep signal aggregates (v7 columns). All nullable; computed server-side.
    public let spo2Pct: Double?        // mean SpO2 (%) during sleep
    public let skinTempDevC: Double?   // skin-temperature deviation (°C) from baseline
    public let respRateBpm: Double?    // mean respiration rate (breaths/min) during sleep
    // On-device daily activity totals (v11 columns, APPROXIMATE estimates). Both nullable, so
    // imported/cloud rows that never carry them stay nil and old call sites are unaffected.
    public let steps: Int?             // daily step total from the cumulative @57 counter
    public let activeKcalEst: Double?  // whole-day HR-only calorie estimate (kcal)
    public init(day: String, totalSleepMin: Double?, efficiency: Double?, deepMin: Double?,
                remMin: Double?, lightMin: Double?, disturbances: Int?, restingHr: Int?,
                avgHrv: Double?, recovery: Double?, strain: Double?, exerciseCount: Int?,
                spo2Pct: Double? = nil, skinTempDevC: Double? = nil, respRateBpm: Double? = nil,
                steps: Int? = nil, activeKcalEst: Double? = nil) {
        self.day = day; self.totalSleepMin = totalSleepMin; self.efficiency = efficiency
        self.deepMin = deepMin; self.remMin = remMin; self.lightMin = lightMin
        self.disturbances = disturbances; self.restingHr = restingHr; self.avgHrv = avgHrv
        self.recovery = recovery; self.strain = strain; self.exerciseCount = exerciseCount
        self.spo2Pct = spo2Pct; self.skinTempDevC = skinTempDevC; self.respRateBpm = respRateBpm
        self.steps = steps; self.activeKcalEst = activeKcalEst
    }
}

public extension DailyMetric {
    /// A per-column update for `with(...)`: `.keep` carries the current value through untouched, `.set(x)`
    /// replaces it. This exists because most columns are themselves `Optional`, so a plain `nil`-default
    /// parameter can't distinguish "leave as-is" from "clear to nil" — the enum makes the two EXPLICIT at every
    /// call site (`.set(nil)` clears; omitting keeps). A literal `nil` won't even compile, which is the point:
    /// silent nilification is exactly the bug `with(...)` prevents.
    enum FieldUpdate<Value> {
        case keep
        case set(Value)
        fileprivate func resolve(_ current: Value) -> Value {
            switch self { case .keep: return current; case .set(let v): return v }
        }
    }

    /// Return a copy of this row with only the named columns changed; every omitted column is carried through
    /// verbatim. This is the SINGLE place the 17-field initializer is fanned out for a copy-with-change, so a
    /// column added to `DailyMetric` is carried here by default instead of being silently nilled at each of the
    /// hand-rolled reconstructors that used to rebuild the whole struct (`fillingNils`, `withRecovery`,
    /// `IntelligenceEngine.with(recovery:skinTempDevC:)`, `SourceLens.hrvMasked`/`crossSourceMasked`). Pass
    /// `.set(x)` to replace a column, including `.set(nil)` to clear a nullable one.
    func with(
        day: FieldUpdate<String> = .keep,
        totalSleepMin: FieldUpdate<Double?> = .keep,
        efficiency: FieldUpdate<Double?> = .keep,
        deepMin: FieldUpdate<Double?> = .keep,
        remMin: FieldUpdate<Double?> = .keep,
        lightMin: FieldUpdate<Double?> = .keep,
        disturbances: FieldUpdate<Int?> = .keep,
        restingHr: FieldUpdate<Int?> = .keep,
        avgHrv: FieldUpdate<Double?> = .keep,
        recovery: FieldUpdate<Double?> = .keep,
        strain: FieldUpdate<Double?> = .keep,
        exerciseCount: FieldUpdate<Int?> = .keep,
        spo2Pct: FieldUpdate<Double?> = .keep,
        skinTempDevC: FieldUpdate<Double?> = .keep,
        respRateBpm: FieldUpdate<Double?> = .keep,
        steps: FieldUpdate<Int?> = .keep,
        activeKcalEst: FieldUpdate<Double?> = .keep
    ) -> DailyMetric {
        DailyMetric(
            day: day.resolve(self.day),
            totalSleepMin: totalSleepMin.resolve(self.totalSleepMin),
            efficiency: efficiency.resolve(self.efficiency),
            deepMin: deepMin.resolve(self.deepMin),
            remMin: remMin.resolve(self.remMin),
            lightMin: lightMin.resolve(self.lightMin),
            disturbances: disturbances.resolve(self.disturbances),
            restingHr: restingHr.resolve(self.restingHr),
            avgHrv: avgHrv.resolve(self.avgHrv),
            recovery: recovery.resolve(self.recovery),
            strain: strain.resolve(self.strain),
            exerciseCount: exerciseCount.resolve(self.exerciseCount),
            spo2Pct: spo2Pct.resolve(self.spo2Pct),
            skinTempDevC: skinTempDevC.resolve(self.skinTempDevC),
            respRateBpm: respRateBpm.resolve(self.respRateBpm),
            steps: steps.resolve(self.steps),
            activeKcalEst: activeKcalEst.resolve(self.activeKcalEst))
    }
}

extension WhoopStore {

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
        // Batch into multi-row INSERTs rather than one statement per day: 18 bound vars/row,
        // SQLite's limit is 999, so 50 rows/statement (900 vars) is a safe, large batch. Mirrors
        // `upsertMetricSeries`. One-INSERT-per-row meant a statement round-trip per day inside the
        // transaction — needless overhead on a multi-year import that spans thousands of days.
        try syncWrite { db in
            var n = 0
            let perRow = "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"   // 18 cols
            for chunk in stride(from: 0, to: days.count, by: 50).map({ Array(days[$0..<min($0 + 50, days.count)]) }) {
                let values = Array(repeating: perRow, count: chunk.count).joined(separator: ", ")
                var args: [DatabaseValueConvertible?] = []
                args.reserveCapacity(chunk.count * 18)
                for d in chunk {
                    args.append(contentsOf: [deviceId, d.day, d.totalSleepMin, d.efficiency, d.deepMin,
                                             d.remMin, d.lightMin, d.disturbances, d.restingHr, d.avgHrv,
                                             d.recovery, d.strain, d.exerciseCount,
                                             d.spo2Pct, d.skinTempDevC, d.respRateBpm,
                                             d.steps, d.activeKcalEst] as [DatabaseValueConvertible?])
                }
                try db.execute(sql: """
                    INSERT INTO dailyMetric
                        (deviceId, day, totalSleepMin, efficiency, deepMin, remMin, lightMin,
                         disturbances, restingHr, avgHrv, recovery, strain, exerciseCount,
                         spo2Pct, skinTempDevC, respRateBpm, steps, activeKcalEst)
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
                        strain = COALESCE(excluded.strain, strain),
                        exerciseCount = COALESCE(excluded.exerciseCount, exerciseCount),
                        spo2Pct = COALESCE(excluded.spo2Pct, spo2Pct),
                        skinTempDevC = COALESCE(excluded.skinTempDevC, skinTempDevC),
                        respRateBpm = COALESCE(excluded.respRateBpm, respRateBpm),
                        steps = COALESCE(excluded.steps, steps),
                        activeKcalEst = COALESCE(excluded.activeKcalEst, activeKcalEst)
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
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT startTs, endTs, efficiency, restingHr, avgHrv, stagesJSON FROM sleepSession
                WHERE deviceId = ? AND endTs >= ? AND startTs <= ?
                ORDER BY startTs ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map {
                    CachedSleepSession(startTs: $0["startTs"], endTs: $0["endTs"],
                                       efficiency: $0["efficiency"], restingHr: $0["restingHr"],
                                       avgHrv: $0["avgHrv"], stagesJSON: $0["stagesJSON"])
                }
        }
    }

    /// Cached daily metrics for days in [from, to] (lexicographic YYYY-MM-DD compare), oldest first.
    public func dailyMetrics(deviceId: String, from: String, to: String) async throws -> [DailyMetric] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT day, totalSleepMin, efficiency, deepMin, remMin, lightMin, disturbances,
                       restingHr, avgHrv, recovery, strain, exerciseCount,
                       spo2Pct, skinTempDevC, respRateBpm, steps, activeKcalEst FROM dailyMetric
                WHERE deviceId = ? AND day >= ? AND day <= ?
                ORDER BY day ASC
                """, arguments: [deviceId, from, to])
                .map {
                    DailyMetric(day: $0["day"], totalSleepMin: $0["totalSleepMin"],
                                efficiency: $0["efficiency"], deepMin: $0["deepMin"],
                                remMin: $0["remMin"], lightMin: $0["lightMin"],
                                disturbances: $0["disturbances"], restingHr: $0["restingHr"],
                                avgHrv: $0["avgHrv"], recovery: $0["recovery"],
                                strain: $0["strain"], exerciseCount: $0["exerciseCount"],
                                spo2Pct: $0["spo2Pct"], skinTempDevC: $0["skinTempDevC"],
                                respRateBpm: $0["respRateBpm"],
                                steps: $0["steps"], activeKcalEst: $0["activeKcalEst"])
                }
        }
    }
}
