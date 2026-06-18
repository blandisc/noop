import Foundation
import WhoopProtocol
@preconcurrency import WhoopStore

// AnalyticsEngine.swift — orchestrator producing DailyMetric + sleep-session results.
//
// Mirrors the role of server/ingest/app/analysis/daily.py + sleep.daily_sleep_summary:
// given a day's raw streams + a user profile + personal baselines, it runs the
// individual analyzers and assembles a `DailyMetric` (WhoopStore shape) plus the
// detected `SleepSession`s (and their `CachedSleepSession` cache shapes).
//
// This is a PURE function over its inputs — it does NOT touch the database
// (persistence is wired elsewhere). All derived values are APPROXIMATE.

public enum AnalyticsEngine {

    /// Baselines passed in by the caller (built from prior nights via Baselines).
    public struct ProfileBaselines: Sendable {
        public let hrv: BaselineState?
        public let restingHR: BaselineState?
        public let resp: BaselineState?
        public let skinTemp: BaselineState?
        public init(hrv: BaselineState? = nil, restingHR: BaselineState? = nil,
                    resp: BaselineState? = nil, skinTemp: BaselineState? = nil) {
            self.hrv = hrv; self.restingHR = restingHR; self.resp = resp
            self.skinTemp = skinTemp
        }
    }

    /// The full analysis result for one day.
    ///
    /// NOTE: not `Sendable` — it embeds `DailyMetric` / `CachedSleepSession` from
    /// WhoopStore, which are not `Sendable` (and that package is out of scope to
    /// modify here). The individual analyzer result types in this package ARE
    /// `Sendable`.
    public struct DayResult {
        /// DailyMetric in the WhoopStore cache shape (recovery/strain/sleep rolled up).
        public let daily: DailyMetric
        /// Detected sleep sessions (rich, with stage segments).
        public let sleepSessions: [SleepSession]
        /// CachedSleepSession cache rows (one per detected session).
        public let cachedSleep: [CachedSleepSession]
        /// Detected workout/exercise sessions.
        public let workouts: [ExerciseSession]
        /// Recovery score [0,100] or nil (cold-start / no HRV baseline).
        public let recovery: Double?
        /// Day strain [0,21] or nil (insufficient HR samples / invalid HRR).
        public let strain: Double?
        /// Wear-gated mean in-bed skin temperature (°C) for this night, or nil when no worn
        /// in-bed samples were available. Baseline-INDEPENDENT (like avgHrv): the caller seeds
        /// a personal skin-temp baseline from these nightly means and re-derives
        /// `DailyMetric.skinTempDevC` in a second pass. APPROXIMATE.
        public let nightlySkinTempC: Double?

        public init(daily: DailyMetric, sleepSessions: [SleepSession],
                    cachedSleep: [CachedSleepSession], workouts: [ExerciseSession],
                    recovery: Double?, strain: Double?, nightlySkinTempC: Double? = nil) {
            self.daily = daily; self.sleepSessions = sleepSessions
            self.cachedSleep = cachedSleep; self.workouts = workouts
            self.recovery = recovery; self.strain = strain
            self.nightlySkinTempC = nightlySkinTempC
        }
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Format a unix-seconds timestamp as a `YYYY-MM-DD` day string in a wall-clock zone
    /// `tzOffsetSeconds` east of UTC. Default 0 = UTC, which keeps pure-function callers and tests on
    /// UTC. The device's LOCAL civil day is obtained by shifting the instant by the offset and
    /// formatting in UTC — the same trick `WhoopImporter` uses with `tzOffsetMin`, so day-keys stay
    /// deterministic and dedup-stable across sources. (FER-226: `dailyMetric.day` is the local civil day.)
    public static func dayString(_ ts: Int, tzOffsetSeconds: Int = 0) -> String {
        isoDay.string(from: Date(timeIntervalSince1970: TimeInterval(ts + tzOffsetSeconds)))
    }

    /// Unix-seconds instant of LOCAL midnight for the civil day `ts` falls on, in a wall-clock zone
    /// `tzOffsetSeconds` east of UTC. Used as the inclusive lower bound of the additive-totals window
    /// (steps + calories), replacing the old UTC-midnight floor. Pure; default 0 = UTC midnight. (FER-226)
    public static func localMidnight(_ ts: Int, tzOffsetSeconds: Int = 0) -> Int {
        let local = ts + tzOffsetSeconds
        let flooredLocal = local - ((local % 86_400) + 86_400) % 86_400
        return flooredLocal - tzOffsetSeconds
    }

    /// Which `stored` day-keys fall strictly AFTER `today` (the device's local civil day) and were NOT
    /// (re)written this run — the spurious "future-in-local" rows the one-time UTC→local re-bucket
    /// prunes (FER-226). Pure so the prune's selection is testable without the app/store. Past and
    /// today rows are never returned, so a day that couldn't be recomputed keeps its row (no data loss);
    /// `written` excludes a freshly-written future row defensively (the re-group never writes future).
    public static func futureLocalDaysToPrune(stored: [String], today: String,
                                              written: Set<String>) -> [String] {
        stored.filter { $0 > today && !written.contains($0) }
    }

    /// JSON-encode stage segments to the verbatim array shape CachedSleepSession stores.
    static func encodeStages(_ stages: [StageSegment]) -> String? {
        guard let data = try? JSONEncoder().encode(stages) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode a COMPUTED `stagesJSON` (the `[{start,end,stage}]` segment array `encodeStages` writes)
    /// back to `[StageSegment]`. Returns nil for the IMPORTED dict-of-totals form (no per-segment
    /// timeline) or empty/malformed input, so callers fall back to a coarse `[start,end]` interval.
    /// The counterpart of `encodeStages`; reused by SleepView and the SRI orchestration (FER-214).
    public static func decodeStages(_ json: String?) -> [StageSegment]? {
        guard let json, let data = json.data(using: .utf8),
              let segs = try? JSONDecoder().decode([StageSegment].self, from: data),
              !segs.isEmpty else { return nil }
        return segs
    }

    /// Analyze one day's streams into a `DayResult`.
    ///
    /// - Parameters:
    ///   - day: the calendar day this metric is for — the device's LOCAL civil day (the caller
    ///     formats it with the same `tzOffsetSeconds` passed here); a sleep session is attributed to
    ///     the day its `end` falls on (a night ending that morning).
    ///   - hr/rr/resp/gravity: the day's raw streams (the wider window around the
    ///     night may be passed; sleep detection finds the in-bed span itself).
    ///   - profile: user profile (age/sex/weight/height) for HRmax + calories.
    ///   - baselines: personal baselines for recovery normalization.
    ///   - maxHROverride: explicit HRmax (bpm) to use for strain/zones; nil →
    ///     Tanaka from profile.age.
    public static func analyzeDay(day: String,
                                  hr: [HRSample] = [],
                                  rr: [RRInterval] = [],
                                  resp: [RespSample] = [],
                                  gravity: [GravitySample] = [],
                                  steps: [StepSample] = [],
                                  // Calendar-day-scoped overrides for the ADDITIVE daily totals
                                  // (steps + activeKcalEst) ONLY. When nil, the totals fall back to
                                  // the same window the rest of the analysis uses (preserving the
                                  // pure-function contract). The caller (IntelligenceEngine) supplies
                                  // a full [localMidnight(day), localMidnight(day)+86400) read here so a
                                  // PAST day's late hours — which fall outside the ~42h
                                  // night-detection window when the current local time-of-day is before
                                  // noon — are still counted. Sleep / recovery / strain / workouts
                                  // keep using hr/rr/resp/gravity/steps.
                                  dayHr: [HRSample]? = nil,
                                  daySteps: [StepSample]? = nil,
                                  // Wear-gated nightly skin-temp mean is harvested here
                                  // (baseline-independent); IntelligenceEngine seeds a personal
                                  // baseline from these means across nights and re-derives
                                  // skinTempDevC in pass 2 (same two-pass shape as avgHrv→recovery).
                                  skinTemp: [SkinTempSample] = [],
                                  // Additive per-band skin-temp calibration (°C). Default 0 = the
                                  // 5.0's full AS6221 register; IntelligenceEngine passes +28.5 for a
                                  // 4.0 (whose v24 record drops the integer part). See
                                  // wornNightlySkinTempC. Default keeps pure-function callers/tests
                                  // and the 5.0 path unchanged.
                                  skinTempOffsetC: Double = 0,
                                  profile: UserProfile,
                                  baselines: ProfileBaselines = ProfileBaselines(),
                                  maxHROverride: Double? = nil,
                                  // Wall-clock UTC offset (seconds) for the sleep detector's daytime
                                  // false-sleep guard (#90). Default 0 keeps pure-function callers/tests
                                  // on UTC; IntelligenceEngine passes the device's real offset.
                                  tzOffsetSeconds: Int = 0) -> DayResult {

        // ── Sleep detection + staging ─────────────────────────────────────────
        let allSessions = SleepStager.detectSleep(hr: hr, rr: rr, resp: resp, gravity: gravity,
                                                  tzOffsetSeconds: tzOffsetSeconds)
        // Sessions attributed to `day` = those whose end falls on `day` (local civil day per tzOffsetSeconds).
        let matched = allSessions.filter { dayString($0.end, tzOffsetSeconds: tzOffsetSeconds) == day }

        // ── Daily sleep aggregates (AASM, in-bed weighted) ────────────────────
        var deepS = 0.0, remS = 0.0, lightS = 0.0, tstS = 0.0
        var inBedS = 0.0, effWeighted = 0.0
        var disturbances = 0
        for s in matched {
            let m = SleepStager.hypnogramMetrics(s)
            let inBed = Double(s.end - s.start)
            inBedS += inBed
            effWeighted += s.efficiency * inBed
            deepS += m.deepMin * 60.0
            remS += m.remMin * 60.0
            lightS += m.lightMin * 60.0
            tstS += m.tstS
            disturbances += m.disturbances
        }
        let efficiency = inBedS > 0 ? effWeighted / inBedS : 0.0

        // Daily resting HR = lowest per-session resting HR across matched sessions.
        let restingHRDaily = matched.compactMap { $0.restingHR }.min()
        // Daily avg HRV = in-bed-weighted mean of per-session avg HRV.
        let avgHRVDaily: Double? = {
            let pairs = matched.compactMap { s -> (Double, Double)? in
                s.avgHRV.map { ($0, Double(s.end - s.start)) }
            }
            guard !pairs.isEmpty else { return nil }
            let total = pairs.reduce(0.0) { $0 + $1.0 * $1.1 }
            let weight = pairs.reduce(0.0) { $0 + $1.1 }
            return weight > 0 ? total / weight : nil
        }()

        // Nightly APPROXIMATE respiratory rate (breaths/min) from the R-R stream via
        // RSA. WHOOP5 v18 carries no raw resp ADC, so this is an on-device estimate,
        // NOT a cloud/clinical respiration value. Per matched in-bed session, estimate
        // over [start, end]; the night's value = median of finite per-session
        // estimates; nil only when no session yields a finite estimate.
        let respRateDaily: Double? = {
            let perSession = matched
                .map { SleepStager.respRateFromRR(rr, start: $0.start, end: $0.end) }
                .filter { $0.isFinite }
            return perSession.isEmpty ? nil : HRVAnalyzer.median(perSession)
        }()

        let sleepStart = matched.map { $0.start }.min()
        let sleepEnd = matched.map { $0.end }.max()

        // ── Recovery ──────────────────────────────────────────────────────────
        var recovery: Double? = nil
        if let hrvVal = avgHRVDaily, let rhrVal = restingHRDaily, let hrvBase = baselines.hrv {
            // Sleep-performance proxy = in-bed-weighted efficiency (0..1).
            let sleepPerf = matched.isEmpty ? nil : efficiency
            recovery = RecoveryScorer.recovery(
                hrv: hrvVal,
                rhr: Double(rhrVal),
                resp: respRateDaily,       // term drops + renormalizes when nil / no baseline
                hrvBaseline: hrvBase,
                rhrBaseline: baselines.restingHR,
                respBaseline: baselines.resp,
                sleepPerf: sleepPerf)
        }

        // ── Strain (day cardiovascular load over the full HR window) ──────────
        let effMaxHR: Double? = maxHROverride ?? (profile.age > 0 ? StrainScorer.tanakaHRmax(age: profile.age) : nil)
        let restForStrain = restingHRDaily.map(Double.init) ?? StrainScorer.defaultRestingHR
        let strain = StrainScorer.strain(hr, maxHR: effMaxHR, restingHR: restForStrain,
                                         sex: profile.sex)

        // ── Workouts ──────────────────────────────────────────────────────────
        let workouts = WorkoutDetector.detect(
            hr: hr, gravity: gravity,
            restingHR: restingHRDaily.map(Double.init),
            maxHR: maxHROverride,
            age: profile.age > 0 ? profile.age : nil,
            profile: profile)

        // ── Steps (APPROXIMATE) ───────────────────────────────────────────────
        // step_motion_counter@57 is a CUMULATIVE u16 running counter. The daily total is the SUM of
        // positive consecutive deltas across the day's samples. u16 wraparound: a negative delta
        // means the counter rolled past 65535, so add 65536. The day's ~42h read window may include
        // adjacent-day samples, so filter to dayString(ts)==day first. ESTIMATE only — not
        // cloud/clinical parity.
        let stepsTotal: Int? = {
            // Prefer the full-calendar-day stream for the additive total; fall back to the
            // night-window stream when the caller didn't supply one (pure-function callers/tests).
            let sorted = (daySteps ?? steps).filter { dayString($0.ts, tzOffsetSeconds: tzOffsetSeconds) == day }.sorted { $0.ts < $1.ts }
            if sorted.count < 2 { return nil }
            // A firmware reboot resets the counter and is byte-indistinguishable from a u16 wrap.
            // A genuine wrap yields a SMALL corrected delta (the steps since the last record); a
            // reset-from-low yields a huge one. Cap each corrected delta so a reboot can't inject
            // tens of thousands of phantom steps. Heuristic — partial, since a reset from a HIGH
            // prior count still looks like a small wrap; tune once @57's cadence is validated.
            let maxStepDelta = 30_000
            var total = 0
            for i in 1..<sorted.count {
                var delta = sorted[i].counter - sorted[i - 1].counter
                if delta < 0 { delta += 65_536 }  // u16 wraparound
                if delta >= 1 && delta <= maxStepDelta { total += delta }  // drop resets
            }
            return total > 0 ? total : nil
        }()

        // ── Daily calories (APPROXIMATE, HR-only whole-day estimate) ──────────
        // Whole-day active+resting energy from the full HR window, using the same resting/active
        // per-second model the per-workout estimate uses (resting BMR below activeThreshold, Keytel
        // active above). effMaxHR + restingHRDaily are the same effective HRmax / resting baseline
        // strain uses. Nil when there is no HR. A heart-rate ESTIMATE — not cloud/clinical parity.
        // Whole-day additive totals (steps above, calories here) are summed over the full LOCAL
        // calendar day supplied by the caller (dayHr / daySteps), NOT the ~42h sleep-detection
        // window — which, anchored to the current time-of-day, would drop a past day's late hours
        // and double-count seconds shared with adjacent days. Fall back to the night-window hr for
        // pure-function callers that don't supply dayHr. Strain keeps the full window (bounded log).
        let dayHrFiltered = (dayHr ?? hr).filter { dayString($0.ts, tzOffsetSeconds: tzOffsetSeconds) == day }
        let activeKcalEst: Double? = dayHrFiltered.isEmpty ? nil : Calories.estimateDayCalories(
            dayHrFiltered, profile: profile, hrmax: effMaxHR,
            restingHR: restingHRDaily.map(Double.init))

        // ── Skin-temperature deviation (offline) ──────────────────────────────
        // Wear-gated in-bed mean (baseline-independent, harvested every pass) + the deviation
        // against the personal baseline. In pass 1 baselines.skinTemp is nil so the deviation is
        // nil and the mean is harvested; IntelligenceEngine seeds the baseline from those means
        // and re-derives the deviation in pass 2 (mirrors avgHrv→recovery). APPROXIMATE.
        let nightlySkinTempC = wornNightlySkinTempC(matched, hr: hr, skinTemp: skinTemp,
                                                    skinTempOffsetC: skinTempOffsetC)
        let skinTempDevC: Double? = nightlySkinTempC.flatMap { (v: Double) -> Double? in
            guard let b = baselines.skinTemp, b.usable else { return nil }
            return round2(Baselines.deviation(v, state: b).delta)
        }

        // ── Assemble DailyMetric ──────────────────────────────────────────────
        let daily = DailyMetric(
            day: day,
            totalSleepMin: matched.isEmpty ? nil : tstS / 60.0,
            efficiency: matched.isEmpty ? nil : efficiency,
            deepMin: matched.isEmpty ? nil : deepS / 60.0,
            remMin: matched.isEmpty ? nil : remS / 60.0,
            lightMin: matched.isEmpty ? nil : lightS / 60.0,
            disturbances: matched.isEmpty ? nil : disturbances,
            restingHr: restingHRDaily,
            avgHrv: avgHRVDaily,
            recovery: recovery,
            strain: strain,
            exerciseCount: workouts.count,
            spo2Pct: nil,
            skinTempDevC: skinTempDevC,
            respRateBpm: respRateDaily,
            steps: stepsTotal,
            activeKcalEst: activeKcalEst)
        _ = sleepStart; _ = sleepEnd  // available for callers wiring sleep_start/end columns

        // ── Cache rows ────────────────────────────────────────────────────────
        let cachedSleep = matched.map { s in
            CachedSleepSession(
                startTs: s.start, endTs: s.end,
                efficiency: s.efficiency,
                restingHr: s.restingHR,
                avgHrv: s.avgHRV,
                stagesJSON: encodeStages(s.stages))
        }

        return DayResult(daily: daily, sleepSessions: matched, cachedSleep: cachedSleep,
                         workouts: workouts, recovery: recovery, strain: strain,
                         nightlySkinTempC: nightlySkinTempC)
    }

    /// Round to 2 decimal places (matches the imported/demo skin-temp deviation precision).
    static func round2(_ v: Double) -> Double { (v * 100.0).rounded() / 100.0 }

    /// Min worn, in-bed skin-temp samples (1 Hz ⇒ seconds) before a nightly mean is trusted.
    /// ~5 min guards against a few stray samples fabricating a baseline value.
    static let minSkinTempSamples = 300

    /// Plausible worn skin-temperature range (°C). Off-wrist/charging samples drift to ambient
    /// and are excluded; the strap's own decode gate is the looser 5–45.
    static let skinTempMinC = 28.0
    static let skinTempMaxC = 42.0

    /// Wear-gated mean in-bed skin temperature (°C) for the night, or nil when too few worn
    /// samples. A sample counts when (a) its timestamp falls inside a detected in-bed `sessions`
    /// span, (b) a concurrent HR sample reads a worn, alive BPM (the strap streams HR only
    /// on-wrist), and (c) the value is in the plausible worn range — so an on-charger interval
    /// drifting to ambient can't poison the nightly mean. °C = raw/128 + `skinTempOffsetC` — the
    /// AS6221's native 7.8125 m°C/LSB scale (Interpreter.swift skin_temp_raw@73), NOT the /100 the
    /// Android decoder uses for the same register; using /100 here would put every real worn night
    /// (~33–35 °C) outside the 28–42 gate.
    ///
    /// `skinTempOffsetC` is an additive per-band calibration the caller supplies (default 0). The
    /// WHOOP 5.0 streams the full AS6221 register, so offset 0 lands a worn night at ~33–35 °C. The
    /// WHOOP 4.0's historical (v24) record drops the integer part of the register, so its raw is
    /// ~28 °C too low (raw≈652 → 5.1 °C) and every sample falls under the 28 °C gate; a +28.5 °C
    /// offset (anchored to a real 4.0 backup: worn night min 32.5 / mean 33.9 / max 35.7 °C) restores
    /// it. The offset is a documented physiological approximation, not a per-unit calibration — and
    /// because the UI shows the deviation against a personal baseline, a constant offset cancels, so
    /// its only job is to let the samples survive the gate. All values APPROXIMATE.
    static func wornNightlySkinTempC(_ sessions: [SleepSession],
                                     hr: [HRSample],
                                     skinTemp: [SkinTempSample],
                                     skinTempOffsetC: Double = 0,
                                     minSamples: Int = minSkinTempSamples) -> Double? {
        if sessions.isEmpty || skinTemp.isEmpty { return nil }
        var wornSeconds = Set<Int>(minimumCapacity: hr.count)
        for h in hr where (30...220).contains(h.bpm) { wornSeconds.insert(h.ts) }
        var sum = 0.0
        var n = 0
        for t in skinTemp {
            if !wornSeconds.contains(t.ts) { continue }
            if !sessions.contains(where: { t.ts >= $0.start && t.ts <= $0.end }) { continue }
            let c = Double(t.raw) / 128.0 + skinTempOffsetC
            if c < skinTempMinC || c > skinTempMaxC { continue }
            sum += c
            n += 1
        }
        return n >= minSamples ? sum / Double(n) : nil
    }
}
