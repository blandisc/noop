import Foundation
import Combine
import WhoopProtocol
import WhoopStore
import StrandAnalytics

/// On-device "intelligence": computes recovery / day-strain / sleep from the raw strap streams using
/// NOOP's own WHOOP-like, HRV-dominant recovery composite — HRV vs personal baseline as the dominant
/// term, then resting HR, sleep and respiration, baseline-normalized (strain 0–21 from cardiovascular
/// load). The blend weights are NOOP's own product-calibration choice, NOT WHOOP's: WHOOP discloses
/// only the qualitative ordering, not its recovery weights (see docs/ANALYTICS.md). This is what makes
/// NOOP independent of WHOOP's cloud — for any day the strap collected raw data with NOOP connected,
/// NOOP scores it itself rather than relying on the values WHOOP computed in the imported CSV.
@MainActor
final class IntelligenceEngine: ObservableObject {
    private let repo: Repository
    private let profile: ProfileStore
    private let deviceId: String
    private let family: DeviceFamily

    /// Additive skin-temp calibration (°C) for this band, handed to `AnalyticsEngine.analyzeDay`.
    /// The 4.0's historical (v24) record drops the integer part of the AS6221 register, so its raw
    /// reads ~28 °C too low; +28.5 °C (anchored to a real 4.0 backup) restores a worn night to
    /// ~32–36 °C so it survives the analytics gate. The 5.0 streams the full register → offset 0.
    /// This is band-calibration knowledge (the app's), kept out of the pure analytics package.
    private var skinTempOffsetC: Double {
        switch family {
        case .whoop4: return 28.5
        case .whoop5: return 0
        }
    }

    @Published var results: [Computed] = []      // newest first
    @Published var computing = false
    @Published var note: String?

    // Idempotent-skip watermarks (FER-177): the periodic 15-min loop re-reads ~21 days × 8 streams
    // every tick. When nothing new has landed since the last successful run — the HR frontier hasn't
    // advanced and the imported history is unchanged — there is nothing to recompute, so the whole
    // heavy load is skipped. Live wear, a completed backfill and an import all move one of these, so a
    // genuinely-new tick still runs. The manual "re-analyze" button passes `force: true` to bypass it.
    private var lastAnalyzedHRFrontier: Int?
    private var lastAnalyzedHistKey: String?

    struct Computed: Identifiable {
        let day: String
        let recovery: Double?
        let strain: Double?
        let sleepMin: Double?
        let hrv: Double?
        let rhr: Int?
        var id: String { day }
    }

    init(repo: Repository, profile: ProfileStore, deviceId: String, family: DeviceFamily = .whoop4) {
        self.repo = repo; self.profile = profile; self.deviceId = deviceId; self.family = family
    }

    /// Compute on-device scores for each of the last `maxDays` that actually has raw HR data.
    /// Personal baselines (HRV / resting HR) are folded from the imported history, so even the first
    /// live night can be scored against your norm.
    /// Returns the set of `day` keys it (re)wrote under the computed source this run — the one-time
    /// day-key re-bucket (FER-226) uses it to prune the rows orphaned by the UTC→local re-dating.
    /// Empty when nothing was scored. (`@discardableResult` — the periodic loop ignores it.)
    @discardableResult
    func analyzeRecent(maxDays: Int = 21, force: Bool = false) async -> Set<String> {
        guard !computing else { return [] }
        guard let store = await repo.storeHandle() else { note = String(localized: "No on-device store yet."); return [] }
        guard let hrvCfg = Baselines.metricCfg["hrv"],
              let rhrCfg = Baselines.metricCfg["resting_hr"],
              let respCfg = Baselines.metricCfg["resp"],
              let skinCfg = Baselines.metricCfg["skin_temp"] else { return [] }

        // ── Snapshot ALL repo-derived inputs ONCE, up front, before any heavy await. `repo.days` is a
        // value type (copy-on-write), so a concurrent `repo.refresh()` (e.g. a backfill completing
        // mid-run) can't mutate this array out from under the ~21-await pass — every night is scored
        // against the SAME baseline the run started with, so the scores can't drift. (FER-177 / #78)
        let hist = repo.days
        // FER-519: snapshot the Apple-only day set CONTIGUOUSLY with `hist` (same published `dashboard`
        // value, no await in between) — the baseline fold excludes these days so Apple's SDNN never enters
        // the band's RMSSD histogram. Splitting this read across an await would reintroduce the FER-177 race.
        let appleOnlyDays = repo.appleHealthDays
        // FER-484: snapshot the mode alongside the other inputs. In appleHealthOnly the strap is excluded
        // from reads, so there are no strap nights to score — skip the pass (Apple-sourced recovery is F4).
        // Capture is untouched. In whoopOnly the pass runs but the Apple prior below is gated off.
        let mode = repo.dataSourceMode
        guard mode.usesWhoop else { if !results.isEmpty { results = [] }; return [] }

        // ── Idempotent skip: if neither the raw HR frontier nor the imported history changed since the
        // last successful run, re-reading 21 days would recompute identical scores — skip the balloon.
        let frontier = (try? await store.latestHRSampleTs(deviceId: deviceId)) ?? nil
        let histKey = "\(hist.count)|\(hist.first?.day ?? "")|\(hist.last?.day ?? "")"
        if !force, frontier != nil, frontier == lastAnalyzedHRFrontier, histKey == lastAnalyzedHistKey {
            return []
        }

        computing = true
        defer { computing = false }

        let up = UserProfile(weightKg: profile.weightKg, heightCm: profile.heightCm,
                             age: Double(profile.age), sex: profile.sex)

        let maxHR = profile.hrMaxOverride > 0 ? Double(profile.hrMaxOverride) : nil
        let now = Int(Date().timeIntervalSince1970)
        // Device wall-clock offset (seconds east of UTC) for the sleep detector's daytime
        // false-sleep guard (#90): the stager places each window's center on the LOCAL clock
        // so only genuinely-daytime windows face the stricter nap bar. (Computed once; a DST
        // boundary inside the window is a negligible edge case for an hour-of-day band.)
        let tzOffset = TimeZone.current.secondsFromGMT()

        // ── Pass 1: analyse each offloaded night against the IMPORTED-ONLY baseline. For a BLE-only
        // user `repo.days` (imported) is empty, so the HRV baseline isn't usable yet and recovery is
        // null here — but each night's avgHrv/restingHr are computed baseline-INDEPENDENTLY, so we
        // harvest them to SEED the baseline and re-score in pass 2. foldHistory winsorizes outliers;
        // repo.days is published oldest→newest, so the replay order is already chronological. `hist` is
        // the up-front snapshot taken above (so a concurrent refresh can't drift the baseline). (#78)
        // FER-519: fold the STRAP-ONLY slice — Apple-only nights carry SDNN, not the band's RMSSD, so they
        // must not enter the HRV/RHR/resp baselines (the capped `foldApplePrior` below is the only Apple
        // path, RHR/resp only). `filter` preserves chronological order.
        let strapHist = Self.strapOnlyHistory(hist, appleHealthDays: appleOnlyDays)
        let hrvBase1 = Baselines.foldHistory(strapHist.map { $0.avgHrv }, cfg: hrvCfg)
        let rhrBase1 = Baselines.foldHistory(strapHist.map { $0.restingHr.map(Double.init) }, cfg: rhrCfg)
        let baselines1 = AnalyticsEngine.ProfileBaselines(hrv: hrvBase1, restingHR: rhrBase1)
        let skinOffset = skinTempOffsetC  // captured as a value for the detached analyze task

        // Keep each night's small result (daily metrics + sessions), NOT the raw streams — every field
        // except recovery is baseline-independent, so pass 2 only re-scores the cheap recovery
        // composite. The hr/rr/resp/gravity arrays go out of scope each iteration (memory stays bounded).
        var scoredNights: [(daily: DailyMetric, strain: Double?, cachedSleep: [CachedSleepSession],
                            workouts: [ExerciseSession], nightlySkin: Double?)] = []
        // Nightly values harvested in pass 1, keyed by day, to seed the pass-2 baseline.
        var nightlyHrvByDay: [String: Double?] = [:]
        var nightlyRhrByDay: [String: Double?] = [:]
        // On-device RSA respiration + wear-gated skin-temp means (baseline-independent), harvested to
        // seed resp/skin-temp baselines the same way avgHrv seeds the HRV baseline.
        var nightlyRespByDay: [String: Double?] = [:]
        var nightlySkinByDay: [String: Double?] = [:]
        var nightlyEffByDay: [String: Double?] = [:]

        for offset in 0..<maxDays {
            let dayStart = now - offset * 86_400
            let day = AnalyticsEngine.dayString(dayStart, tzOffsetSeconds: tzOffset)
            // Read a generous window around the night that ends on `day`; the stager finds the span.
            let from = dayStart - 30 * 3_600
            let to = dayStart + 12 * 3_600

            let hr = (try? await store.hrSamples(deviceId: deviceId, from: from, to: to, limit: 200_000)) ?? []
            guard hr.count >= 200 else { continue }   // need real raw data, not a stray sample
            let rr = (try? await store.rrIntervals(deviceId: deviceId, from: from, to: to, limit: 200_000)) ?? []
            let resp = (try? await store.respSamples(deviceId: deviceId, from: from, to: to, limit: 200_000)) ?? []
            let grav = (try? await store.gravitySamples(deviceId: deviceId, from: from, to: to, limit: 200_000)) ?? []
            let steps = (try? await store.stepSamples(deviceId: deviceId, from: from, to: to, limit: 200_000)) ?? []
            let skin = (try? await store.skinTempSamples(deviceId: deviceId, from: from, to: to, limit: 200_000)) ?? []

            // Calendar-day window for the ADDITIVE daily totals (steps + calories). The night window
            // above is anchored to the current local time-of-day and ends at dayStart+12h, so for a PAST
            // day whose late hours sit after that bound those hours are never read and the totals
            // undercount. Read exactly [localMidnight(day), localMidnight(day)+86400) — the device's
            // LOCAL civil day (FER-226) — and hand it to analyzeDay's dayHr/daySteps, which use it ONLY
            // for those totals. (the store range is inclusive, so end at -1 s.)
            let dayMid = AnalyticsEngine.localMidnight(dayStart, tzOffsetSeconds: tzOffset)
            let dayEnd = dayMid + 86_400 - 1
            // These two reads cover EXACTLY one calendar day, which holds at most ~86_400 1 Hz samples,
            // so the 200k night-window ceiling is wasteful headroom here. Cap at a true day ceiling
            // (with the same ~33% margin the 42h night reads keep) — trims the per-iteration peak with
            // no truncation risk, since one day physically can't exceed it (FER-177).
            let dayHr = (try? await store.hrSamples(deviceId: deviceId, from: dayMid, to: dayEnd, limit: 120_000)) ?? []
            let daySteps = (try? await store.stepSamples(deviceId: deviceId, from: dayMid, to: dayEnd, limit: 120_000)) ?? []

            let res = await Task.detached(priority: .utility) {
                AnalyticsEngine.analyzeDay(day: day, hr: hr, rr: rr, resp: resp, gravity: grav,
                                           steps: steps, dayHr: dayHr, daySteps: daySteps,
                                           skinTemp: skin, skinTempOffsetC: skinOffset,
                                           profile: up, baselines: baselines1, maxHROverride: maxHR,
                                           tzOffsetSeconds: tzOffset,
                                           // The in-progress day (offset 0) scores strain over its own
                                           // civil day, not the ~42h window that's all of yesterday just
                                           // after midnight (FER-341).
                                           strainCivilDayOnly: offset == 0)
            }.value
            nightlyHrvByDay[res.daily.day] = res.daily.avgHrv
            nightlyRhrByDay[res.daily.day] = res.daily.restingHr.map(Double.init)
            nightlyRespByDay[res.daily.day] = res.daily.respRateBpm
            nightlySkinByDay[res.daily.day] = res.nightlySkinTempC
            nightlyEffByDay[res.daily.day] = res.daily.efficiency
            scoredNights.append((daily: res.daily, strain: res.strain, cachedSleep: res.cachedSleep,
                                 workouts: res.workouts, nightlySkin: res.nightlySkinTempC))
            await Task.yield()
        }

        // ── Seed the baseline from the UNION of imported nightly history + the values just computed.
        // THIS is the BLE-only recovery fix: the "-noop" nightly avgHrv/restingHr finally feed the
        // baseline so a strap-only user crosses Baselines.minNightsSeed and recovery lights up.
        // IMPORTED values win per day: write them first, then fill ONLY days the import doesn't cover
        // (Swift has no putIfAbsent — `dict[day] == nil` is true only when the KEY is absent, so a day
        // imported with a nil avgHrv stays imported, not overwritten by the computed value).
        var histHrvByDay: [String: Double?] = [:]
        var histRhrByDay: [String: Double?] = [:]
        var histRespByDay: [String: Double?] = [:]
        var histEffByDay: [String: Double?] = [:]
        for d in strapHist {   // FER-519: strap-only — Apple-only days are excluded from the baseline fold
            histHrvByDay[d.day] = d.avgHrv
            histRhrByDay[d.day] = d.restingHr.map(Double.init)
            histRespByDay[d.day] = d.respRateBpm
            histEffByDay[d.day] = d.efficiency
        }
        for (day, v) in nightlyHrvByDay where histHrvByDay[day] == nil { histHrvByDay[day] = v }
        for (day, v) in nightlyRhrByDay where histRhrByDay[day] == nil { histRhrByDay[day] = v }
        for (day, v) in nightlyRespByDay where histRespByDay[day] == nil { histRespByDay[day] = v }
        for (day, v) in nightlyEffByDay where histEffByDay[day] == nil { histEffByDay[day] = v }

        // ── FER-60 / FER-519: Apple Health prior — the LOWEST-precedence seed, for RESTING-HR and
        // RESPIRATION ONLY. A brand-new strap user has no imported history and a handful of on-device
        // nightlies isn't enough to clear Baselines.minNightsSeed, so recovery stays null for the first
        // nights. Folding Apple's resting-HR / respiration UNDER both strap layers (same `== nil` idiom:
        // fill only days NEITHER strap source covered) seeds those baselines, capped to applePriorMaxNights
        // so the seed lands PROVISIONAL, not trusted. RHR and respiration are the SAME physical quantity
        // across sources (bpm, breaths/min), so this is an honest cold-start prior. Strap ALWAYS wins.
        // FER-519: HRV is NOT seeded from Apple. Apple's HRV is SDNN; the band's is RMSSD — different
        // constructs with no published conversion and a scale gap of UNCERTAIN direction (Shaffer &
        // Ginsberg 2017; Task Force 1996), so SDNN must never enter the RMSSD baseline. Apple's HRV path
        // is the SEPARATE SDNN-vs-own-SDNN estimator (AppleRecoveryEstimator, FER-153), not this prior.
        // (efficiency/skin-temp are NOT seeded either: Apple writes efficiency = nil and carries no skin
        // temp, so those terms keep their honest population-center cold-start.)
        // FER-484: the Apple prior only applies when Apple Health is in use; whoopOnly gates it off.
        let appleRows = mode.usesAppleHealth ? ((try? await store.dailyMetrics(deviceId: "apple-health",
                                                       from: AnalyticsEngine.dayString(now - 90 * 86_400, tzOffsetSeconds: tzOffset),
                                                       to: AnalyticsEngine.dayString(now, tzOffsetSeconds: tzOffset))) ?? []) : []
        let priorDays = Self.applePriorDays(appleRows, maxNights: Self.applePriorMaxNights)
        var appleRhrByDay: [String: Double?] = [:]
        var appleRespByDay: [String: Double?] = [:]
        for r in appleRows {
            appleRhrByDay[r.day]  = r.restingHr.map(Double.init)
            appleRespByDay[r.day] = r.respRateBpm
        }
        // FER-519: no foldApplePrior for HRV — Apple SDNN never seeds the RMSSD baseline.
        histRhrByDay  = Self.foldApplePrior(into: histRhrByDay,  apple: appleRhrByDay,  priorDays: priorDays)
        histRespByDay = Self.foldApplePrior(into: histRespByDay, apple: appleRespByDay, priorDays: priorDays)

        let hrvSeq = histHrvByDay.keys.sorted().map { histHrvByDay[$0]! }   // chronological [Double?]
        let rhrSeq = histRhrByDay.keys.sorted().map { histRhrByDay[$0]! }
        let respSeq = histRespByDay.keys.sorted().map { histRespByDay[$0]! }
        let effSeq = histEffByDay.keys.sorted().map { histEffByDay[$0]! }
        // Skin-temp baseline is on-device-only (imported rows carry skinTempDevC, not the raw mean),
        // so fold purely over the pass-1 nightly means in chronological order.
        let skinSeq = nightlySkinByDay.keys.sorted().map { nightlySkinByDay[$0]! }
        // Resp baseline gated on `usable`: RecoveryScorer includes the resp term whenever a
        // baseline object is present — a CALIBRATING (<4-night) baseline would let one noisy
        // RSA night move recovery (mirrors the skin-temp use-site gate; honest cold-start).
        let respFold = Baselines.foldHistory(respSeq, cfg: respCfg)
        // Personal sleep-efficiency baseline (gated on `usable` at the recovery call site, like
        // resp/skin-temp): the recovery sleep term is measured against the user's own normal once
        // enough nights exist, else falls back to the fixed population center (honest cold-start).
        let effCfg = Baselines.metricCfg["efficiency"]!
        let effFold = Baselines.foldHistory(effSeq, cfg: effCfg)
        let baselines2 = AnalyticsEngine.ProfileBaselines(
            hrv: Baselines.foldHistory(hrvSeq, cfg: hrvCfg),
            restingHR: Baselines.foldHistory(rhrSeq, cfg: rhrCfg),
            resp: respFold.usable ? respFold : nil,
            skinTemp: Baselines.foldHistory(skinSeq, cfg: skinCfg))

        // Real (non-detected) workouts in the scored window, used to de-duplicate detected bouts so a
        // user who BOTH has real sessions AND wears the strap doesn't see the same session twice (the
        // per-day merge precedence does not cover the workout table). This covers BOTH directions of
        // the cross-source duplicate (#107): the strap source carries imported WHOOP rows AND manual /
        // re-labelled rows (both written under `deviceId`), and apple-health carries Health imports —
        // a detected bout overlapping ANY of them is skipped below. Port of the Android dedup block.
        let computedId = deviceId + "-noop"
        let windowStart = now - maxDays * 86_400 - 30 * 3_600
        var realWorkouts = (try? await store.workouts(deviceId: deviceId, from: windowStart,
                                                       to: now, limit: 100_000)) ?? []
        if mode.usesAppleHealth {
            realWorkouts += (try? await store.workouts(deviceId: "apple-health", from: windowStart,
                                                        to: now, limit: 100_000)) ?? []
        }

        // ── Pass 2: re-score ONLY recovery against the now-seeded baseline (cheap, baseline-dependent);
        // every other field was computed once in pass 1. Recovery stays nil until the HRV baseline is
        // usable (≥ minNightsSeed valid nights) — honest cold-start, via RecoveryScorer's usable gate.
        var out: [Computed] = []
        var dailies: [DailyMetric] = []
        var cachedSleep: [CachedSleepSession] = []
        var workoutRows: [WorkoutRow] = []
        for night in scoredNights {
            let recovery = recomputeRecovery(night.daily, baselines2, skinTemp: night.nightlySkin, sleepBaseline: effFold)
            let skinDev = recomputeSkinTempDev(night.nightlySkin, baselines2.skinTemp)
            out.append(Computed(day: night.daily.day, recovery: recovery, strain: night.strain,
                                sleepMin: night.daily.totalSleepMin, hrv: night.daily.avgHrv,
                                rhr: night.daily.restingHr))
            dailies.append(night.daily.with(recovery: recovery, skinTempDevC: skinDev))
            cachedSleep.append(contentsOf: night.cachedSleep)
            // Persist the detected workouts the pipeline already computes (previously discarded).
            // Skip any bout overlapping a real imported workout so import+wear users don't
            // double-count. sport = "detected"; energyKcal is the APPROXIMATE Keytel/BMR total.
            for s in night.workouts {
                if realWorkouts.contains(where: { s.start < $0.endTs && $0.startTs < s.end }) { continue }
                workoutRows.append(WorkoutRow(startTs: s.start, endTs: s.end,
                                              sport: "detected", source: computedId,
                                              durationS: s.durationS, energyKcal: s.caloriesKcal,
                                              avgHr: Int(s.avgHR), maxHr: s.peakHR,
                                              strain: s.strain, distanceM: nil,
                                              zonesJSON: nil, notes: nil))
            }
        }

        // Persist the computed scores under a dedicated "-noop" source so the WHOLE dashboard
        // (Today / Recovery / Strain / Sleep / Trends), not just this screen, reads them. The
        // Repository merges these UNDER any imported "my-whoop" rows, so a real WHOOP import
        // always wins; this only fills the days the strap collected but no import covered.
        if !dailies.isEmpty { _ = try? await store.upsertDailyMetrics(dailies, deviceId: computedId) }
        if !cachedSleep.isEmpty { _ = try? await store.upsertSleepSessions(cachedSleep, deviceId: computedId) }
        // Make re-detection idempotent across runs: clear the prior computed detected workouts in the
        // scored window (a bout's startTs can drift as more HR arrives, which would otherwise orphan
        // stale rows under the (deviceId,startTs,sport) key), then re-insert.
        _ = try? await store.deleteWorkouts(deviceId: computedId, sport: "detected",
                                            from: windowStart, to: now)
        if !workoutRows.isEmpty { _ = try? await store.upsertWorkouts(workoutRows, deviceId: computedId) }

        results = out
        note = out.isEmpty
            ? String(localized: "No scored nights yet. Wear the strap with Cénit connected overnight and the engine will score your recovery, strain and sleep itself, no WHOOP cloud required.")
            : nil

        // Reload the dashboard caches so the freshly computed scores show up immediately.
        if !dailies.isEmpty { await repo.refresh() }

        // Record the watermarks for the idempotent skip. The frontier is read from the START of the run
        // (analysis writes daily-metrics/sleep/workouts, never hrSample, so it's still current); the
        // history key is read AFTER the refresh so the next run's up-front snapshot — which sees these
        // just-persisted computed days — matches and short-circuits when no new raw data arrived.
        lastAnalyzedHRFrontier = frontier
        lastAnalyzedHistKey = "\(repo.days.count)|\(repo.days.first?.day ?? "")|\(repo.days.last?.day ?? "")"

        // The day-keys (re)written under the computed source this run — the FER-226 re-bucket prunes
        // any computed row in its window NOT in this set (the UTC orphans left by the old dating).
        return Set(dailies.map(\.day))
    }

    /// Re-score ONLY the recovery composite for a day against a (re-seeded) baseline. Every other field
    /// in `daily` is baseline-independent and already final from pass 1. Returns nil until the HRV
    /// baseline is usable (RecoveryScorer gates on `hrvBaseline.usable`, i.e. ≥ minNightsSeed valid
    /// nights) — so the honest null-until-4-nights cold-start is free. Mirrors AnalyticsEngine's own
    /// recovery call + Android IntelligenceEngine.recomputeRecovery. (#78)
    private func recomputeRecovery(_ daily: DailyMetric, _ baselines: AnalyticsEngine.ProfileBaselines,
                                   skinTemp: Double?, sleepBaseline: BaselineState?) -> Double? {
        guard let hrvVal = daily.avgHrv, let rhrVal = daily.restingHr, let hrvBase = baselines.hrv else { return nil }
        // Skin-temp + sleep-efficiency terms only once their baselines are usable (≥ seed nights) —
        // a calibrating baseline would let one noisy night move recovery (same honest cold-start as
        // resp). The sleep term falls back to the fixed population center until its baseline is ready.
        let tempBase = (baselines.skinTemp?.usable ?? false) ? baselines.skinTemp : nil
        let sleepBase = (sleepBaseline?.usable ?? false) ? sleepBaseline : nil
        return RecoveryScorer.recovery(hrv: hrvVal, rhr: Double(rhrVal), resp: daily.respRateBpm,
                                       hrvBaseline: hrvBase, rhrBaseline: baselines.restingHR,
                                       respBaseline: baselines.resp, sleepPerf: daily.efficiency,
                                       sleepPerfBaseline: sleepBase,
                                       skinTemp: tempBase != nil ? skinTemp : nil,
                                       skinTempBaseline: tempBase)
    }

    /// Re-derive the skin-temperature deviation (°C) for a night against the freshly-seeded personal
    /// baseline, mirroring the avgHrv→recovery re-score. Nil when the night had no wear-gated mean or
    /// the skin-temp baseline isn't usable yet (< minNightsSeed) — honest cold-start. Rounded to 2 dp
    /// to match the imported/demo precision. APPROXIMATE.
    private func recomputeSkinTempDev(_ nightly: Double?, _ base: BaselineState?) -> Double? {
        guard let v = nightly, let b = base, b.usable else { return nil }
        return (Baselines.deviation(v, state: b).delta * 100.0).rounded() / 100.0
    }

    // MARK: - Baseline source filter (FER-519)

    /// The strap-only slice of the merged daily history — the rows that feed the recovery baseline,
    /// EXCLUDING Apple-only days (band-less nights whose `avgHrv` is Apple SDNN, not the band's RMSSD).
    /// Folding Apple SDNN into the RMSSD baseline mixes two different HRV constructs with no published
    /// conversion (Shaffer & Ginsberg 2017, Front Public Health 5:258; Task Force 1996, Circulation
    /// 93:1043); the capped `foldApplePrior` is the only sanctioned Apple→baseline path, and only for
    /// resting-HR / respiration (same physical metric across sources). `appleHealthDays` is the set
    /// `mergeDaily` returns for the days surfaced from Apple Health. Pure (no store/actor state) for
    /// testing; `appleHealthDays == []` (e.g. whoopOnly, or a strap-only user) is the identity.
    ///
    /// Sibling: `SourceLens` (StrandAnalytics, FER-623 / FER-631) is the COLUMN variant. `maskHrv` nils only
    /// `avgHrv` and keeps RHR/resp, for consumers (verdict/brief σ, StressModel) that still want the Apple
    /// night's other signals; `maskForBaseline` nils EVERY cross-source column (avgHrv/RHR/resp/sleep stages)
    /// and — under the engine's skip-and-hold folds — yields the same baseline this whole-row drop does.
    nonisolated static func strapOnlyHistory(_ hist: [DailyMetric],
                                             appleHealthDays: Set<String>) -> [DailyMetric] {
        appleHealthDays.isEmpty ? hist : hist.filter { !appleHealthDays.contains($0.day) }
    }

    // MARK: - Apple Health baseline prior (FER-60)

    /// How many of the most-recent Apple Health nights seed the baseline as a prior. Chosen to clear
    /// `Baselines.minNightsSeed` (4) with headroom yet stay under `minNightsTrust` (14), so the seeded
    /// baseline lands PROVISIONAL — confidence-shrunk — not fully trusted. This is the lever for "how
    /// much to trust Apple Health before the strap has accrued its own nights".
    static let applePriorMaxNights = 7

    /// The capped set of most-recent Apple Health nights usable as a baseline prior: the nights that
    /// carry a usable HRV, newest `maxNights`. `store.dailyMetrics(...)` returns rows day-ascending, so
    /// the `suffix` is the most recent. Robust to gaps (counts nights-with-HRV, not calendar days).
    nonisolated static func applePriorDays(_ rows: [DailyMetric], maxNights: Int) -> Set<String> {
        Set(rows.filter { $0.avgHrv != nil }.suffix(maxNights).map { $0.day })
    }

    /// Fold an Apple Health prior UNDER the strap layers for one metric. `strap` already holds the
    /// imported + on-device values; a PRESENT key wins even when its value is nil (the same `== nil`
    /// idiom the pass-1/pass-2 merge uses — a key is "absent" only when truly unset). The prior fills
    /// ONLY days the strap never covered, and only those in `priorDays`. So the strap always wins and
    /// the prior just seeds the cold-start gap. Pure (no store/actor state) for testing.
    nonisolated static func foldApplePrior(into strap: [String: Double?], apple: [String: Double?],
                                           priorDays: Set<String>) -> [String: Double?] {
        var out = strap
        for (day, v) in apple where priorDays.contains(day) && out[day] == nil { out[day] = v }
        return out
    }
}

private extension DailyMetric {
    /// Rebuild the immutable DailyMetric with a substituted recovery + skin-temp deviation
    /// (the struct has no `copy()`). (#78)
    func with(recovery r: Double?, skinTempDevC sd: Double?) -> DailyMetric {
        with(recovery: .set(r), skinTempDevC: .set(sd))
    }
}
