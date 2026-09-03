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

    // MARK: - Strength load overlay (ola 1 · E2)

    /// One Cénit strength session, projected onto primitives the fusion can read. The app resolves
    /// `day` (`DayKey.local(startTs)`, so a session crossing midnight keys to the day it STARTED) —
    /// StrandAnalytics never imports StrandTraining.
    public struct StrengthDayLoad: Sendable, Equatable {
        public var day: String
        public var startTs: Int
        public var endTs: Int
        /// The session's load on the 0–21 scale, measured or estimated. `nil` = the user trained and
        /// we don't know how hard (no pulse, no rating) — that is a HOLD, never a zero.
        public var strain: Double?
        /// `true` when `strain` came from minutes × effort (`StrainSource.rpe`), so Tendencias can
        /// label the day «estimada».
        public var estimated: Bool
        public init(day: String, startTs: Int, endTs: Int, strain: Double?, estimated: Bool) {
            self.day = day; self.startTs = startTs; self.endTs = endTs
            self.strain = strain; self.estimated = estimated
        }
    }

    /// The wall-clock span of an Apple workout already folded into Apple's own day strain.
    public struct WorkoutInterval: Sendable, Equatable {
        public var startTs: Int
        public var endTs: Int
        public init(startTs: Int, endTs: Int) { self.startTs = startTs; self.endTs = endTs }
    }

    /// How far back a strength session may SYNTHESIZE a day row when there is no Apple/strap history
    /// at all to anchor it (days). See `overlayStrengthLoad` — H7.
    static let strengthOverlayFallbackWindowDays = 56

    /// Fold Cénit strength sessions into the daily strain series — IN READING, never persisted
    /// (`dailyMetric.strain` stays Apple's/the strap's). Without this a session logged without a
    /// watch is invisible to ACWR and monotony, and the day reads `.rest` = 0: a false zero that
    /// pulls the acute leg DOWN on a day the user actually trained.
    ///
    /// Rules, each with its reason:
    /// 1. **Closed days only** (`day < today`). Today still belongs to the live Apple estimate.
    /// 2. **TRIMP space.** Loads are added on the linear axis (`StrainScorer.strainToTrimp`) and
    ///    mapped back once — adding two 0–21 logs would be meaningless.
    /// 3. **Sum when disjoint, max when overlapping.** A session whose span overlaps an Apple workout
    ///    is probably the SAME training (the Watch recorded it), so the day takes the larger of the
    ///    two rather than double-counting; a session that overlaps nothing is extra work and adds
    ///    (gate estadístico H5 — `max` alone made a run + a lifting session read as just the run).
    /// 4. **Trained, load unknown → hold.** A day with a session but no usable load turns a base 0
    ///    into `nil`: the EWMA holds instead of folding a zero that says «rested» (H6).
    /// 5. **Synthesis floor.** A day with no base row gets a synthetic strain-only row ONLY from the
    ///    first day that HAS a base strain (or, with no base at all, inside the last
    ///    `strengthOverlayFallbackWindowDays`). In an imported era there are no rest zeros, so every
    ///    gap holds and the chronic leg would be seeded with per-session load instead of a daily
    ///    dose — a false «Easing off» for ~4 weeks after an import (H7).
    ///
    /// Returns the days (rows replaced/synthesized, ordered by day) and the days whose load an
    /// ESTIMATED session contributed to.
    public static func overlayStrengthLoad(days: [DailyMetric], loads: [StrengthDayLoad],
                                           workouts: [WorkoutInterval], today: String)
        -> (days: [DailyMetric], estimatedDays: Set<String>) {
        guard !loads.isEmpty else { return (days, []) }
        let floorDay = strengthOverlayFloor(days: days, today: today)
        var byDay: [String: DailyMetric] = [:]
        for d in days { byDay[d.day] = d }
        var grouped: [String: [StrengthDayLoad]] = [:]
        for l in loads where l.day < today && l.day >= floorDay { grouped[l.day, default: []].append(l) }
        guard !grouped.isEmpty else { return (days, []) }

        var estimatedDays = Set<String>()
        var changed = false
        for (day, sessions) in grouped {
            let base = byDay[day]?.strain
            let baseTrimp = StrainScorer.strainToTrimp(base ?? 0)
            var overlapTrimp = 0.0, disjointTrimp = 0.0
            var overlapEstimated = false, disjointEstimated = false
            var anyLoad = false
            for s in sessions {
                guard let st = s.strain, st > 0 else { continue }
                anyLoad = true
                let t = StrainScorer.strainToTrimp(st)
                if workouts.contains(where: { $0.startTs <= s.endTs && $0.endTs >= s.startTs }) {
                    overlapTrimp += t
                    if s.estimated { overlapEstimated = true }
                } else {
                    disjointTrimp += t
                    if s.estimated { disjointEstimated = true }
                }
            }
            guard anyLoad else {
                // Rule 4: trained, load unknown. A base zero becomes a hold; anything else is left
                // alone (a real measured day keeps its number, a missing day stays missing).
                if let row = byDay[day], let b = row.strain, b <= 0 {
                    byDay[day] = row.with(strain: .set(nil))
                    changed = true
                }
                continue
            }
            let combined = StrainScorer.trimpToStrain(max(baseTrimp, overlapTrimp) + disjointTrimp)
            if disjointEstimated || (overlapEstimated && overlapTrimp > baseTrimp) {
                estimatedDays.insert(day)
            }
            if let row = byDay[day] {
                byDay[day] = row.with(strain: .set(combined))
            } else {
                byDay[day] = DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil,
                                         remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil,
                                         avgHrv: nil, recovery: nil, strain: combined, exerciseCount: nil)
            }
            changed = true
        }
        guard changed else { return (days, estimatedDays) }
        return (byDay.values.sorted { $0.day < $1.day }, estimatedDays)
    }

    /// The earliest day the overlay may touch (rule 5): the first day that already carries a base
    /// strain, or — with no base history at all — `today − strengthOverlayFallbackWindowDays`.
    static func strengthOverlayFloor(days: [DailyMetric], today: String) -> String {
        if let first = days.lazy.filter({ $0.strain != nil }).map(\.day).min() { return first }
        guard let t = DayKey.parseUTC(today),
              let back = DayKey.utcCalendar.date(byAdding: .day,
                                                 value: -strengthOverlayFallbackWindowDays, to: t)
        else { return today }
        return DayKey.utc(back)
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
