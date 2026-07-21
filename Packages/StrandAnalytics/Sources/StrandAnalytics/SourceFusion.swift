// Multi-source fusion (pure). Extracted from Repository (plan 2026-07-20)
// so package tests cover the single policy copy in CI.
// Bodies are verbatim; Repository keeps one-line forwarders only.

import Foundation
import StrandModels
import BiometricStreams

/// Pure multi-source fusion for daily metrics, sleep sessions, strain estimates, and autonomic trend.
/// Single copy of the policy — Repository methods forward here so call sites stay stable.
public enum SourceFusion {

    /// Pure wrapper over the StrandAnalytics engine, kept pure so the refresh can call it
    /// off the main actor and so tests pin the seam without a store. `nights` are the
    /// dense `apple_rmssd_night` rows (oldest→newest); `asOf`/`recentCutoff` are local day keys.
    public static func autonomicTrend(nights: [(day: String, rmssdMs: Double)],
                                      asOf: String, recentCutoff: String) -> AutonomicTrend.Read {
        AutonomicTrend.evaluate(nights: nights, asOf: asOf, recentCutoff: recentCutoff)
    }

    /// FER-970 (R-01): the days whose MERGED strain is nil — the only days Apple workout-HR can
    /// serve (the estimated-strain path). A pure pre-pass over rows performRefresh has already
    /// read, so the HR read can be skipped outright when this comes back empty. Reuses the very
    /// same `mergeDaily` the assembler runs — eligibility cannot drift from it.
    public static func strainEstimateEligibleDays(imported: [DailyMetric], computed: [DailyMetric],
                                                  apple: [DailyMetric]) -> Set<String> {
        Set(mergeDaily(imported: imported, computed: computed, apple: apple)
            .days.filter { $0.strain == nil }.map(\.day))
    }

    public static func mergeDaily(imported: [DailyMetric], computed: [DailyMetric],
                                  apple: [DailyMetric]) -> (days: [DailyMetric], appleDays: Set<String>,
                                                            displayDays: [DailyMetric]) {
        var byDay: [String: DailyMetric] = [:]
        var appleByDay: [String: DailyMetric] = [:]
        var appleDays = Set<String>()
        for d in apple    { byDay[d.day] = d; appleByDay[d.day] = d; appleDays.insert(d.day) }  // base layer (lowest precedence)
        for d in computed { byDay[d.day] = d; appleDays.remove(d.day) }   // on-device strap overwrites Apple
        for d in imported { byDay[d.day] = d; appleDays.remove(d.day) }   // imported strap wins over all
        let days = byDay.values.sorted { $0.day < $1.day }
        let displayDays = days.map { row in
            appleByDay[row.day].map { row.fillingNils(from: $0) } ?? row
        }
        return (days, appleDays, displayDays)
    }

    /// FER-883: per-day cardiovascular-load estimate from Apple workout HR, for days whose MEASURED
    /// strain is nil (band-less day in Apple/Combined mode). Pure + static (RepositoryMergeTests pins it),
    /// NEVER folded into `days`/`displayDays`, surfaced only via `repo.today`/`estimatedStrain`/
    /// `isStrainEstimated`. `hrByDay` is apple-health HR samples (workout-only — HealthKitBridge only
    /// persists HR during HKWorkouts) grouped by LOCAL day (`CenitStore.DayKey.local`). Reuses
    /// `StrainScorer.strain` (Edwards TRIMP) — no new math. `maxHR`/`sex` come from the user's `Profile`
    /// (`hrMaxOverride ?? Tanaka(age)`), threaded via the Repository props by `AppModel` — the SAME HRmax
    /// the strap live-strain path uses, so the estimate never jumps band↔Apple (FER-883 /cso). nil
    /// `maxHR` still falls back to the StrainScorer default.
    public static func appleStrainEstimates(hrByDay: [String: [HRSample]], eligibleDays: Set<String>,
                                            restingHRByDay: [String: Double] = [:],
                                            maxHR: Double? = nil, sex: String = "male")
        -> [String: Double] {
        guard !hrByDay.isEmpty else { return [:] }
        var out: [String: Double] = [:]
        for day in eligibleDays {
            guard let samples = hrByDay[day], !samples.isEmpty else { continue }
            let restingHR = restingHRByDay[day] ?? StrainScorer.defaultRestingHR
            if let s = StrainScorer.strain(samples, maxHR: maxHR, restingHR: restingHR, sex: sex) {
                out[day] = s
            }
        }
        return out
    }

    /// FER-670: build the per-day single-construct fusion map from the mode-filtered per-source rows.
    /// Three metrics only — steps, sleep total, active kcal (`MetricArbitrationPolicy` refuses the rest):
    ///   • "steps"           — Apple's pedometer count (`appleAgg.steps`) vs the strap's on-device figure
    ///                         (the 5.0/MG counter in `computed.steps`, else the 4.0 `steps_est` estimate —
    ///                         real counter wins, mirroring FER-663).
    ///   • "sleep_total_min" — imported / computed / Apple `totalSleepMin` (duration IS cross-source
    ///                         comparable — same split `SourceLens.crossSourceMasked` draws; stages never
    ///                         enter).
    ///   • "active_kcal"     — Apple's aggregate (`appleAgg.activeKcal`) vs each strap row's HR-only
    ///                         estimate (`activeKcalEst`).
    /// Only days where ≥2 sources reported a metric produce an entry — a `.single` day has nothing to
    /// cross-check and nothing to show. Pure + static so a unit test can pin it.
    public static func fusionByDay(imported: [DailyMetric], computed: [DailyMetric], apple: [DailyMetric],
                                   appleAgg: [AppleDaily], stepsEst: [String: Double])
        -> [String: [String: FusedMetricPoint]] {
        var impByDay: [String: DailyMetric] = [:]
        var compByDay: [String: DailyMetric] = [:]
        var appByDay: [String: DailyMetric] = [:]
        var aggByDay: [String: AppleDaily] = [:]
        for d in imported { impByDay[d.day] = d }
        for d in computed { compByDay[d.day] = d }
        for d in apple    { appByDay[d.day] = d }
        for d in appleAgg { aggByDay[d.day] = d }

        var out: [String: [String: FusedMetricPoint]] = [:]
        let allDays = Set(impByDay.keys).union(compByDay.keys).union(appByDay.keys)
            .union(aggByDay.keys).union(stepsEst.keys)
        for day in allDays {
            var points: [String: FusedMetricPoint] = [:]

            var steps: [FusionInput] = []
            if let s = aggByDay[day]?.steps { steps.append(FusionInput(source: .appleHealth, value: Double(s))) }
            if let s = compByDay[day]?.steps.map(Double.init) ?? stepsEst[day] {
                steps.append(FusionInput(source: .noopComputed, value: s))
            }

            var sleep: [FusionInput] = []
            if let m = impByDay[day]?.totalSleepMin  { sleep.append(FusionInput(source: .whoopImport, value: m)) }
            if let m = compByDay[day]?.totalSleepMin { sleep.append(FusionInput(source: .noopComputed, value: m)) }
            if let m = appByDay[day]?.totalSleepMin  { sleep.append(FusionInput(source: .appleHealth, value: m)) }

            var kcal: [FusionInput] = []
            if let k = aggByDay[day]?.activeKcal          { kcal.append(FusionInput(source: .appleHealth, value: k)) }
            if let k = impByDay[day]?.activeKcalEst       { kcal.append(FusionInput(source: .whoopImport, value: k)) }
            if let k = compByDay[day]?.activeKcalEst      { kcal.append(FusionInput(source: .noopComputed, value: k)) }

            for (key, inputs) in [("steps", steps), ("sleep_total_min", sleep), ("active_kcal", kcal)]
            where inputs.count >= 2 {
                if let p = FusionResolver.resolve(metricKey: key, inputs: inputs) { points[key] = p }
            }
            if !points.isEmpty { out[day] = points }
        }
        return out
    }

    /// Same precedence for sleep sessions, keyed by the day the night ends on.
    public static func mergeSleep(imported: [CachedSleepSession], computed: [CachedSleepSession]) -> [CachedSleepSession] {
        func endDay(_ s: CachedSleepSession) -> String {
            DayKey.local(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
        }
        var byDay: [String: CachedSleepSession] = [:]
        for s in computed { byDay[endDay(s)] = s }
        for s in imported { byDay[endDay(s)] = s }
        return byDay.values.sorted { $0.startTs < $1.startTs }
    }

    /// Merge sleep sessions across sources. Strap is the base — imported (real export) wins over the
    /// on-device computed row on the same `startTs`. An Apple Health session is added ONLY if no strap
    /// session overlaps its `[startTs, endTs]` span: the band wins PER NIGHT (FER-486), because a strap
    /// night and Apple's session for the same sleep have different `startTs` (so a startTs dedup can't
    /// catch them). Pure + static so `SleepSessionMergeTests` can pin it; with `apple == []` it is the
    /// prior strap-only merge byte-for-byte (regression zero).
    public static func mergeSleepSessions(imported: [CachedSleepSession], computed: [CachedSleepSession],
                                          apple: [CachedSleepSession]) -> [CachedSleepSession] {
        var byStart: [Int: CachedSleepSession] = [:]
        for s in computed { byStart[s.startTs] = s }
        for s in imported { byStart[s.startTs] = s }   // imported (real export) wins on the same start
        let strap = Array(byStart.values)
        func overlapsStrap(_ a: CachedSleepSession) -> Bool {
            strap.contains { $0.startTs <= a.endTs && $0.endTs >= a.startTs }
        }
        let merged = strap + apple.filter { !overlapsStrap($0) }
        return merged.sorted { $0.startTs < $1.startTs }
    }

    /// Apple Health sleep sessions to surface in the Detalle when the band didn't cover that night — the
    /// band wins per night, so an Apple session overlapping ANY strap session's span is dropped (FER-486).
    /// (Strap and Apple have different startTs for the same sleep, so this is interval-overlap, not startTs.)
    public static func appleSleepsNotCoveredByStrap(apple: [CachedSleepSession], strap: [CachedSleepSession]) -> [CachedSleepSession] {
        apple.filter { a in !strap.contains { $0.startTs <= a.endTs && $0.endTs >= a.startTs } }
             .sorted { $0.startTs < $1.startTs }
    }
}

private extension DailyMetric {
    /// Display back-fill (FER-149): a copy where each nil field takes the value from `other` (the Apple
    /// Health row for the same day). Strap-present fields always win — only the gaps Apple can fill
    /// change. recovery/strain stay strap-only in practice because Apple rows carry them as nil. This is
    /// display-only and is never fed to the recovery baseline (`repo.days` keeps the un-filled row).
    func fillingNils(from other: DailyMetric) -> DailyMetric {
        with(
            totalSleepMin: .set(totalSleepMin ?? other.totalSleepMin),
            efficiency: .set(efficiency ?? other.efficiency),
            deepMin: .set(deepMin ?? other.deepMin),
            remMin: .set(remMin ?? other.remMin),
            lightMin: .set(lightMin ?? other.lightMin),
            disturbances: .set(disturbances ?? other.disturbances),
            restingHr: .set(restingHr ?? other.restingHr),
            avgHrv: .set(avgHrv ?? other.avgHrv),
            recovery: .set(recovery ?? other.recovery),
            strain: .set(strain ?? other.strain),
            exerciseCount: .set(exerciseCount ?? other.exerciseCount),
            spo2Pct: .set(spo2Pct ?? other.spo2Pct),
            skinTempDevC: .set(skinTempDevC ?? other.skinTempDevC),
            respRateBpm: .set(respRateBpm ?? other.respRateBpm),
            steps: .set(steps ?? other.steps),
            activeKcalEst: .set(activeKcalEst ?? other.activeKcalEst))
    }
}
