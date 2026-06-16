import Foundation
import WhoopStore
import StrandImport

/// Maps a parsed + aggregated Apple Health export into the on-device store under its own
/// source id ("apple-health"), so it sits BESIDE Whoop for the per-source pages and cross-source
/// consensus. Populates appleDaily, dailyMetric, the generic metricSeries, and workouts.
enum AppleHealthImport {

    @discardableResult
    static func importExport(
        url: URL,
        into store: WhoopStore,
        deviceId: String,
        progress: AppleHealthImporter.ProgressHandler? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) async throws -> ImportSummary {
        // Parsing aggregates per-day on the fly (streaming) — `result.daily` is
        // already the merged per-day list, so no second aggregation pass. The parse polls
        // `isCancelled` and throws `CancellationError` if the user left mid-import (FER-33).
        let result = try ImportCoordinator().importAppleHealth(from: url, progress: progress, isCancelled: isCancelled)
        let daily = result.daily
        // Don't start the multi-table write if a cancel landed between parse end and here.
        try Task.checkCancellation()

        // Apple-specific daily aggregates (steps/energy/vo2/hr/weight).
        let appleRows = daily.map { d in
            AppleDaily(day: d.day,
                       steps: d.steps.map { Int($0) },
                       activeKcal: d.activeKcal, basalKcal: d.basalKcal, vo2max: d.vo2max,
                       avgHr: d.avgHr.map { Int($0.rounded()) },
                       maxHr: d.maxHr.map { Int($0.rounded()) },
                       walkingHr: d.walkingHr.map { Int($0.rounded()) },
                       weightKg: nil)
        }
        try await store.upsertAppleDaily(appleRows, deviceId: deviceId)

        // Recovery-relevant subset into dailyMetric (recovery/strain are nil — Apple doesn't compute them).
        let dm = daily.map { d in
            DailyMetric(day: d.day,
                        totalSleepMin: d.asleepMin, efficiency: nil,
                        deepMin: d.deepMin, remMin: d.remMin, lightMin: d.coreMin,
                        disturbances: nil,
                        restingHr: d.restingHr.map { Int($0.rounded()) },
                        avgHrv: d.hrvSDNN, recovery: nil, strain: nil, exerciseCount: nil,
                        spo2Pct: d.spo2Pct, skinTempDevC: nil, respRateBpm: d.respRate)
        }
        try await store.upsertDailyMetrics(dm, deviceId: deviceId)

        // Everything, generically, for the metric explorer.
        let points = AppleHealthAggregator.metricPoints(daily)
            .map { MetricPoint(day: $0.day, key: $0.key, value: $0.value) }
        try await store.upsertMetricSeries(points, deviceId: deviceId)

        // Workouts.
        let workouts = result.workouts.map { w in
            WorkoutRow(startTs: Int(w.start.timeIntervalSince1970),
                       endTs: Int(w.end.timeIntervalSince1970),
                       sport: w.activityType, source: "apple_health",
                       durationS: w.durationS, energyKcal: w.energyKcal,
                       avgHr: nil, maxHr: nil, strain: nil,
                       distanceM: w.distanceM, zonesJSON: nil, notes: nil)
        }
        try await store.upsertWorkouts(workouts, deviceId: deviceId)

        return result.summary
    }
}
