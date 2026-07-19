import Foundation
import GRDB

// DashboardSnapshot.swift — FER-970 (R-03). Everything `Repository.performRefresh` used to read in
// ~13 sequential actor round-trips (each with its own hop + read transaction + WAL snapshot) is
// read here in ONE transaction: one hop, one snapshot, cross-table consistent by construction.
// The row SQL/mapping is shared with the individual accessors via the `fetch…` helpers below —
// zero duplicated SQL, so the snapshot and the accessors cannot drift.
//
// Deliberate omission: Apple workout-HR samples are NOT part of the snapshot — R-01 reads them in
// a separate, skippable phase (only when some merged day still needs an estimated strain).

/// Parameters of the one-pass dashboard read. The two flags reproduce the source-mode gating
/// Repository does at query time — an excluded source is not read at all.
public struct DashboardReadRequest: Sendable {
    public var strapDeviceId: String        // "strap"
    public var computedDeviceId: String     // "strap-noop"
    public var appleDeviceId: String        // "apple-health"
    public var fromDay: String              // YYYY-MM-DD window (dailyMetrics / appleDaily / metricSeries)
    public var toDay: String
    public var fromTs: Int                  // unix window (sleepSessions)
    public var toTs: Int
    public var sleepLimit: Int
    public var includeApple: Bool           // dataSourceMode.usesAppleHealth
    public var includeWhoopSeries: Bool     // dataSourceMode.usesWhoop

    public init(strapDeviceId: String, computedDeviceId: String, appleDeviceId: String,
                fromDay: String, toDay: String, fromTs: Int, toTs: Int,
                sleepLimit: Int = 4000, includeApple: Bool, includeWhoopSeries: Bool) {
        self.strapDeviceId = strapDeviceId
        self.computedDeviceId = computedDeviceId
        self.appleDeviceId = appleDeviceId
        self.fromDay = fromDay
        self.toDay = toDay
        self.fromTs = fromTs
        self.toTs = toTs
        self.sleepLimit = sleepLimit
        self.includeApple = includeApple
        self.includeWhoopSeries = includeWhoopSeries
    }
}

/// Every raw result the dashboard refresh consumes, read in one transaction. Field-for-field the
/// same rows the individual accessors return with identical parameters.
///
/// ⚠️ `appleDays` is NEVER gated on `includeApple`: it feeds the stored-coverage diagnostic
/// (FER-485, «nothing is deleted») and `DataSourcePolicy` — the mode gating for the dashboard
/// itself happens in memory, in Repository. Same for the two raw strap sleep arrays.
public struct DashboardSnapshot: Sendable {
    public var importedDays: [DailyMetric] = []
    public var computedDays: [DailyMetric] = []
    public var appleDays: [DailyMetric] = []
    public var importedSleeps: [CachedSleepSession] = []
    public var computedSleeps: [CachedSleepSession] = []
    public var appleSleeps: [CachedSleepSession] = []
    public var appleAgg: [AppleDaily] = []
    public var stepsEst: [MetricPoint] = []
    public var sleepPerformance: [MetricPoint] = []
    public var sleepConsistency: [MetricPoint] = []
    public var sleepNeed: [MetricPoint] = []
    public var sleepDebt: [MetricPoint] = []

    public init() {}
}

extension CenitStore {

    /// ALL the dashboard reads in ONE read transaction (one WAL snapshot). `nonisolated`: touches
    /// no actor state — it reads `dbWriter` (a `let`) and resolves nothing through the actor's
    /// device-id cache; the apple surrogate isn't needed here (HR moved out, R-01). On the pool
    /// backend (R-04) this async read is served by a WAL reader connection, so it never queues
    /// behind a long write on the actor's executor.
    public nonisolated func dashboardSnapshot(_ req: DashboardReadRequest) async throws -> DashboardSnapshot {
        try await dbWriter.read { db in
            var snap = DashboardSnapshot()
            snap.importedDays = try Self.fetchDailyMetrics(db, deviceId: req.strapDeviceId,
                                                           from: req.fromDay, to: req.toDay)
            snap.computedDays = try Self.fetchDailyMetrics(db, deviceId: req.computedDeviceId,
                                                           from: req.fromDay, to: req.toDay)
            snap.appleDays = try Self.fetchDailyMetrics(db, deviceId: req.appleDeviceId,
                                                        from: req.fromDay, to: req.toDay)
            snap.importedSleeps = try Self.fetchSleepSessions(db, deviceId: req.strapDeviceId,
                                                              from: req.fromTs, to: req.toTs,
                                                              limit: req.sleepLimit)
            snap.computedSleeps = try Self.fetchSleepSessions(db, deviceId: req.computedDeviceId,
                                                              from: req.fromTs, to: req.toTs,
                                                              limit: req.sleepLimit)
            if req.includeApple {
                snap.appleSleeps = try Self.fetchSleepSessions(db, deviceId: req.appleDeviceId,
                                                               from: req.fromTs, to: req.toTs,
                                                               limit: req.sleepLimit)
                snap.appleAgg = try Self.fetchAppleDaily(db, deviceId: req.appleDeviceId,
                                                         from: req.fromDay, to: req.toDay)
            }
            if req.includeWhoopSeries {
                snap.stepsEst = try Self.fetchMetricSeries(db, deviceId: req.computedDeviceId,
                                                           key: "steps_est", from: req.fromDay, to: req.toDay)
                snap.sleepPerformance = try Self.fetchMetricSeries(db, deviceId: req.strapDeviceId,
                                                                   key: "sleep_performance",
                                                                   from: req.fromDay, to: req.toDay)
                snap.sleepConsistency = try Self.fetchMetricSeries(db, deviceId: req.strapDeviceId,
                                                                   key: "sleep_consistency",
                                                                   from: req.fromDay, to: req.toDay)
                snap.sleepNeed = try Self.fetchMetricSeries(db, deviceId: req.strapDeviceId,
                                                            key: "sleep_need_min",
                                                            from: req.fromDay, to: req.toDay)
                snap.sleepDebt = try Self.fetchMetricSeries(db, deviceId: req.strapDeviceId,
                                                            key: "sleep_debt_min",
                                                            from: req.fromDay, to: req.toDay)
            }
            return snap
        }
    }

    // MARK: - Shared row fetchers (one body serves the accessor AND the snapshot)

    static func fetchDailyMetrics(_ db: Database, deviceId: String,
                                  from: String, to: String) throws -> [DailyMetric] {
        try Row.fetchAll(db, sql: """
            SELECT day, totalSleepMin, efficiency, deepMin, remMin, lightMin, disturbances,
                   restingHr, avgHrv, recovery, strain, exerciseCount,
                   spo2Pct, skinTempDevC, respRateBpm, steps, activeKcalEst,
                   effortConfidence, restConfidence FROM dailyMetric
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
                            steps: $0["steps"], activeKcalEst: $0["activeKcalEst"],
                            effortConfidence: $0["effortConfidence"],
                            restConfidence: $0["restConfidence"])
            }
    }

    static func fetchSleepSessions(_ db: Database, deviceId: String,
                                   from: Int, to: Int, limit: Int) throws -> [CachedSleepSession] {
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

    static func fetchAppleDaily(_ db: Database, deviceId: String,
                                from: String, to: String) throws -> [AppleDaily] {
        try Row.fetchAll(db, sql: """
            SELECT day, steps, activeKcal, basalKcal, vo2max, avgHr, maxHr, walkingHr, weightKg
            FROM appleDaily
            WHERE deviceId = ? AND day >= ? AND day <= ?
            ORDER BY day ASC
            """, arguments: [deviceId, from, to])
            .map {
                AppleDaily(day: $0["day"], steps: $0["steps"], activeKcal: $0["activeKcal"],
                           basalKcal: $0["basalKcal"], vo2max: $0["vo2max"], avgHr: $0["avgHr"],
                           maxHr: $0["maxHr"], walkingHr: $0["walkingHr"], weightKg: $0["weightKg"])
            }
    }

    static func fetchMetricSeries(_ db: Database, deviceId: String, key: String,
                                  from: String, to: String) throws -> [MetricPoint] {
        try Row.fetchAll(db, sql: """
            SELECT day, key, value FROM metricSeries
            WHERE deviceId = ? AND key = ? AND day >= ? AND day <= ?
            ORDER BY day ASC
            """, arguments: [deviceId, key, from, to])
            .map { MetricPoint(day: $0["day"], key: $0["key"], value: $0["value"]) }
    }
}
