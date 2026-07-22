import Foundation
import CenitStore
import StrandImport
import StrandAnalytics
import StrandModels

/// Maps a parsed + aggregated Apple Health export into the on-device store under its own
/// source id ("apple-health"), so it sits BESIDE Whoop for the per-source pages and cross-source
/// consensus. Populates appleDaily, dailyMetric, the generic metricSeries, and workouts.
enum AppleHealthImport {

    @discardableResult
    static func importExport(
        url: URL,
        into store: CenitStore,
        deviceId: String,
        maxHR: Double? = nil,
        sex: String = "male",
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

        // CARGA VIVA: XML export has no per-workout HR, so classify only ever returns rest/missing
        // here (never .load). A later HealthKitBridge.sync with real workout HR upgrades those days
        // to .load via the same upsert key (deviceId, day).
        // Day keys must match `d.day` (built with each record's own tzOffsetMin), not device TimeZone.current.
        let workoutDays: Set<String> = Set(result.workouts.map {
            AppleHealthAggregator.localDay($0.start, tzOffsetMin: $0.tzOffsetMin)
        })
        // Persist strain only for completed days — same gate as HealthKitBridge (see isCompletedDay).
        let todayKey = DayKey.local(Date())
        let dm = daily.map { d in
            let activity = AppleLoadEstimator.DayActivity(
                workoutHR: [], steps: d.steps.map { Int($0) }, activeKcal: d.activeKcal,
                hasWorkout: workoutDays.contains(d.day))
            let dayLoad = AppleLoadEstimator.classify(activity, maxHR: maxHR,
                restingHR: d.restingHr ?? StrainScorer.defaultRestingHR, sex: sex)
            let strainValue: Double? = {
                guard AppleLoadEstimator.isCompletedDay(d.day, today: todayKey) else { return nil }
                switch dayLoad {
                case .rest:        return 0
                case .load(let s): return s
                case .missing:     return nil
                }
            }()
            return DailyMetric(day: d.day,
                        totalSleepMin: d.asleepMin, efficiency: nil,
                        deepMin: d.deepMin, remMin: d.remMin, lightMin: d.coreMin,
                        disturbances: nil,
                        restingHr: d.restingHr.map { Int($0.rounded()) },
                        avgHrv: d.hrvSDNN, recovery: nil, strain: strainValue, exerciseCount: nil,
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
