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
///
/// FER-868 — the pass is INCREMENTAL and OFF-MAIN: dirtiness is detected per night by a COUNT-per-
/// local-day signature over the raw streams (`WhoopStore.streamDayCounts` + `AnalysisScheduler`), so
/// only the days with genuinely new (or trimmed) data re-run `analyzeDay`; the heavy body runs as a
/// `nonisolated static` on a `.utility` detached task (pattern: `Repository.assembleDashboard`),
/// keeping the main thread free while the band is connected. Pass 2 (baseline seed + recovery
/// re-score) still runs over ALL cached+fresh nights, so the published scores are identical to a
/// full pass. The cache is in-memory only: relaunching the app costs one full first pass, as before.
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

    /// The incremental pass's in-memory night cache (FER-868). NOT persisted — a relaunch starts
    /// empty and the first pass recomputes everything, exactly like the pre-incremental engine.
    private var cache = AnalysisCache()

    #if DEBUG
    /// Nights that actually ran `analyzeDay` in the last pass — on-device verification hook for the
    /// incremental skip (a steady-state 15-min tick should read 1, a fresh launch `maxDays`).
    private(set) var lastPassAnalyzedDays: Int = 0
    #endif

    struct Computed: Identifiable, Sendable {
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

    // MARK: - Incremental-pass value types (FER-868)

    /// One night's pass-1 output — the tuple `analyzeDay` hands back, named so it can live in the
    /// cache. Everything here except recovery is baseline-INDEPENDENT (pass 2 re-scores only the
    /// cheap recovery composite), so a cached night can be replayed under a moved baseline safely.
    struct NightResult: Sendable {
        let daily: DailyMetric
        let strain: Double?
        let cachedSleep: [CachedSleepSession]
        let workouts: [ExerciseSession]
        let nightlySkin: Double?
        let spectral: HRVFreqDomain.Bands?
        /// Whether this night was scored with strain over its own civil day only (FER-341) — true only
        /// for the in-progress day (offset 0). A past day must use the full ~42h window, so a night
        /// cached as in-progress can't be replayed once it becomes yesterday (FER-868 D1).
        let strainCivilDayOnly: Bool
    }

    /// The engine's per-session memory between passes. Value type: `analyzeRecent` hands a copy into
    /// the detached body and adopts the returned copy on the main actor — no shared mutable state.
    struct AnalysisCache: Sendable {
        /// Pass-1 results by day key, replayed for clean days.
        var nights: [String: NightResult] = [:]
        /// The count signature each cached day was analyzed under.
        var signatures: [String: AnalysisScheduler.NightSignature] = [:]
        /// Days seen with hr.count < 200 — "no night here" is cached too, so a data-less day costs
        /// zero reads on the next pass.
        var skippedDays: Set<String> = []
        /// Everything that invalidates ALL cached nights when it changes (profile, tz, mode, …).
        var contextKey: String = ""
        /// Gravity count per local epoch-day — the motion block's own dirtiness signature.
        var motionSignature: [Int: Int] = [:]
    }

    /// Everything the heavy body consumes, snapshotted ON the main actor BEFORE the hop (the
    /// `hist`/`appleOnlyDays`/`mode` trio in one contiguous read — FER-177/519). All value types.
    struct AnalysisInputs: Sendable {
        let hist: [DailyMetric]
        let appleOnlyDays: Set<String>
        let mode: DataSourceMode
        let profile: UserProfile
        let maxHR: Double?
        let baselineEpoch: String?
        let now: Int
        let tzOffset: Int
        let deviceId: String
        let family: DeviceFamily
        let skinTempOffsetC: Double
        let maxDays: Int
        let force: Bool
        let stepsManualCoefficient: Double
    }

    /// Everything the main actor publishes/applies after the body returns.
    struct AnalysisOutput: Sendable {
        let computed: [Computed]
        let writtenDays: Set<String>
        let hadDailies: Bool
        /// FER-881: true iff the computed daily rows this pass produced DIFFER from what was already
        /// stored. The caller gates `repo.refresh()` on this so a recurring-user relaunch (which
        /// recomputes byte-identical scores the launch full-refresh already surfaced) doesn't trigger a
        /// redundant dashboard rebuild. `false` on the empty/early paths (hadDailies gates them out anyway).
        let changed: Bool
        /// A successful steps-calibration fit to mirror into ProfileStore, or…
        let stepsCalibration: StepsEstimateEngine.Calibration?
        /// …the usable-day count while still collecting (nil when the steps block didn't run).
        let stepsProgressDays: Int?
        let cache: AnalysisCache
        /// Nights that actually ran `analyzeDay` this pass (DEBUG instrumentation).
        let analyzedDays: Int
    }

    /// FER-881: whether the freshly computed daily rows differ from what's already stored. Compares only
    /// the days `fresh` writes — a stale prior-only day the engine no longer scores stays put and is not
    /// a "change" (so it never forces a refresh). Any new day, or any changed value on an existing day,
    /// returns true. Pure (testable seam); a lossy store round-trip could only over-report (harmless
    /// extra refresh), never hide a real change.
    nonisolated static func computedDailiesChanged(_ fresh: [DailyMetric], vsStored stored: [DailyMetric]) -> Bool {
        let byDay = Dictionary(stored.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        return fresh.contains { byDay[$0.day] != $0 }
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
        // Two-pass launch refresh: `repo.days` below is the baseline input, and until the FULL pass
        // publishes it may hold only the ~90-day first-paint window — folding baselines over that
        // truncated history would skew every score. Skip silently: every caller has a backstop (the
        // 15-min loop, the debounced post-backfill recompute, the immediate morning pass — all run
        // after `refresh()` completes).
        guard repo.fullyLoaded else { return [] }
        guard let store = await repo.storeHandle() else { note = String(localized: "No on-device store yet."); return [] }

        // ── Snapshot ALL repo-derived inputs ONCE, up front, before any heavy await. `repo.days` is a
        // value type (copy-on-write), so a concurrent `repo.refresh()` (e.g. a backfill completing
        // mid-run) can't mutate this array out from under the pass — every night is scored against
        // the SAME baseline the run started with, so the scores can't drift. (FER-177 / #78)
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
        // last successful run, re-reading the window would recompute identical scores — skip entirely.
        let frontier = (try? await store.latestHRSampleTs(deviceId: deviceId)) ?? nil
        let histKey = "\(hist.count)|\(hist.first?.day ?? "")|\(hist.last?.day ?? "")"
        if !force, frontier != nil, frontier == lastAnalyzedHRFrontier, histKey == lastAnalyzedHistKey {
            return []
        }

        computing = true
        defer { computing = false }

        let up = UserProfile(weightKg: profile.weightKg, heightCm: profile.heightCm,
                             age: Double(profile.age), sex: profile.sex,
                             stepTicksPerStep: profile.stepTicksPerStep)
        let maxHR = profile.hrMaxOverride > 0 ? Double(profile.hrMaxOverride) : nil
        // Device wall-clock offset (seconds east of UTC) for the sleep detector's daytime
        // false-sleep guard (#90): the stager places each window's center on the LOCAL clock
        // so only genuinely-daytime windows face the stricter nap bar. (Computed once; a DST
        // boundary inside the window is a negligible edge case for an hour-of-day band.)
        let inputs = AnalysisInputs(
            hist: hist, appleOnlyDays: appleOnlyDays, mode: mode, profile: up, maxHR: maxHR,
            // FER-677: the baseline cut day-key («Recalibrar recuperación»), captured up-front with
            // the other profile inputs. nil = no cut; the folds drop nights < epoch.
            baselineEpoch: profile.baselineEpochOrNil,
            now: Int(Date().timeIntervalSince1970),
            tzOffset: TimeZone.current.secondsFromGMT(),
            deviceId: deviceId, family: family, skinTempOffsetC: skinTempOffsetC,
            maxDays: maxDays, force: force,
            stepsManualCoefficient: profile.stepsManualCoefficient)

        // ── Off-main hop: the WHOLE heavy body (reads + analyzeDay + folds + upserts) runs at
        // .utility off the main actor; only publication/ProfileStore/watermarks come back here.
        let cacheIn = cache
        let out = await Task.detached(priority: .utility) {
            await Self.runAnalysis(inputs, cache: cacheIn, store: store)
        }.value

        results = out.computed
        note = out.computed.isEmpty
            ? String(localized: "No scored nights yet. Wear the strap with Cénit connected overnight and the engine will score your recovery, strain and sleep itself, no WHOOP cloud required.")
            : nil

        // Mirror the steps-calibration fit (or its progress) into ProfileStore, on the main actor.
        if let cal = out.stepsCalibration {
            profile.stepsCalibrationCoefficient = cal.coefficient
            profile.stepsCalibrationSampleDays = cal.sampleDays
            profile.stepsCalibrationConfidence = cal.confidence
            profile.stepsCalibrationManual = cal.manual
        } else if let have = out.stepsProgressDays {
            // Not yet calibrated (too few overlapping phone-counted days, no manual override).
            // Persist the PROGRESS so Settings/the tile can say how many more days are needed
            // instead of going silently blank. Coefficient stays 0 (the "not calibrated" gate the
            // UI keys off); sampleDays carries the usable-day count for the "need N more" copy.
            profile.stepsCalibrationCoefficient = 0
            profile.stepsCalibrationSampleDays = have
            profile.stepsCalibrationConfidence = 0
            profile.stepsCalibrationManual = false
        }

        // Reload the dashboard caches so the freshly computed scores show up immediately — but only when
        // the computed rows actually CHANGED (FER-881), so a recurring-user relaunch that recomputes
        // byte-identical scores (which the launch full-refresh already surfaced) doesn't fire a redundant
        // rebuild. `force` (the FER-226 re-bucket) always refreshes: it re-dates rows and pairs with a
        // prune whose effect must surface.
        if out.hadDailies && (out.changed || force) { await repo.refresh() }

        // Record the watermarks for the idempotent skip. The frontier is read from the START of the run
        // (analysis writes daily-metrics/sleep/workouts, never hrSample, so it's still current); the
        // history key is read AFTER the refresh so the next run's up-front snapshot — which sees these
        // just-persisted computed days — matches and short-circuits when no new raw data arrived.
        lastAnalyzedHRFrontier = frontier
        lastAnalyzedHistKey = "\(repo.days.count)|\(repo.days.first?.day ?? "")|\(repo.days.last?.day ?? "")"
        cache = out.cache
        #if DEBUG
        lastPassAnalyzedDays = out.analyzedDays
        #endif

        // The day-keys (re)written under the computed source this run — the FER-226 re-bucket prunes
        // any computed row in its window NOT in this set (the UTC orphans left by the old dating).
        return out.writtenDays
    }

    // MARK: - The heavy body (off-main, FER-868)

    /// The whole analysis pass, `nonisolated static` so it runs wherever the caller's detached task
    /// lands (pattern: `Repository.assembleDashboard`). Pure function of (inputs, cache, store): no
    /// engine state is touched — the caller adopts the returned cache/output on the main actor.
    private nonisolated static func runAnalysis(_ inputs: AnalysisInputs, cache cacheIn: AnalysisCache,
                                                store: WhoopStore) async -> AnalysisOutput {
        var cache = cacheIn
        let emptyOut = { (c: AnalysisCache) in
            AnalysisOutput(computed: [], writtenDays: [], hadDailies: false, changed: false,
                           stepsCalibration: nil,
                           stepsProgressDays: nil, cache: c, analyzedDays: 0)
        }
        guard let hrvCfg = Baselines.metricCfg["hrv"],
              let rhrCfg = Baselines.metricCfg["resting_hr"],
              let respCfg = Baselines.metricCfg["resp"],
              let skinCfg = Baselines.metricCfg["skin_temp"] else { return emptyOut(cache) }

        let now = inputs.now
        let tzOffset = inputs.tzOffset
        let deviceId = inputs.deviceId
        let maxDays = inputs.maxDays
        let mode = inputs.mode
        let up = inputs.profile
        let skinOffset = inputs.skinTempOffsetC
        let baselineEpoch = inputs.baselineEpoch

        // ── Context key: any of these moving means every cached night was computed under different
        // assumptions — start over (`force` does the same, that's the manual "re-analyze" contract).
        let contextKey = [
            "\(up.weightKg)", "\(up.heightCm)", "\(up.age)", up.sex, "\(up.stepTicksPerStep)",
            "\(inputs.maxHR ?? -1)", baselineEpoch ?? "", "\(tzOffset)", mode.rawValue,
            "\(skinOffset)", "\(maxDays)", inputs.family.rawValue,
            "\(inputs.stepsManualCoefficient)",
        ].joined(separator: "|")
        if inputs.force || contextKey != cache.contextKey {
            cache = AnalysisCache()
            cache.contextKey = contextKey
        }

        // ── ONE count query per pass covers every night window AND the motion window: the dirtiness
        // signature for both the per-night loop and the motion block below.
        let motionWindowDays = inputs.family.estimatesSteps ? 60 : 14   // 60 = steps calibration, 14 = circadian
        let nightsFrom = now - (maxDays - 1) * 86_400 - 30 * 3_600
        let motionFrom = AnalyticsEngine.localMidnight(now - (motionWindowDays - 1) * 86_400, tzOffsetSeconds: tzOffset)
        var dayCounts: [String: [Int: Int]] = [:]
        do {
            dayCounts = try await store.streamDayCounts(deviceId: deviceId, from: min(nightsFrom, motionFrom),
                                                        tzOffsetSeconds: tzOffset)
        } catch {
            // No signature ⇒ can't prove anything clean: fall back to a full pass (correctness first).
            cache.nights = [:]; cache.signatures = [:]; cache.skippedDays = []; cache.motionSignature = [:]
        }

        // ── Pass 1: analyse each offloaded night against the IMPORTED-ONLY baseline. For a BLE-only
        // user `repo.days` (imported) is empty, so the HRV baseline isn't usable yet and recovery is
        // null here — but each night's avgHrv/restingHr are computed baseline-INDEPENDENTLY, so we
        // harvest them to SEED the baseline and re-score in pass 2. foldHistory winsorizes outliers;
        // repo.days is published oldest→newest, so the replay order is already chronological. `hist` is
        // the up-front snapshot taken on the main actor (so a concurrent refresh can't drift the
        // baseline). (#78)
        // FER-519: fold the STRAP-ONLY slice — Apple-only nights carry SDNN, not the band's RMSSD, so they
        // must not enter the HRV/RHR/resp baselines (the capped `foldApplePrior` below is the only Apple
        // path, and — FER-634 — for respiration only). `filter` preserves chronological order.
        let strapHist = Self.strapOnlyHistory(inputs.hist, appleHealthDays: inputs.appleOnlyDays)
        let hrvBase1 = Baselines.foldHistory(strapHist.map { (day: $0.day, value: $0.avgHrv) }, epoch: baselineEpoch, cfg: hrvCfg)
        let rhrBase1 = Baselines.foldHistory(strapHist.map { (day: $0.day, value: $0.restingHr.map(Double.init)) }, epoch: baselineEpoch, cfg: rhrCfg)
        let baselines1 = AnalyticsEngine.ProfileBaselines(hrv: hrvBase1, restingHR: rhrBase1)

        // Each night keeps its small result (daily metrics + sessions), NOT the raw streams — every
        // field except recovery is baseline-independent, so pass 2 only re-scores the cheap recovery
        // composite. The hr/rr/resp/gravity arrays go out of scope each iteration (memory stays
        // bounded). FER-868: a CLEAN night (count signature unchanged, not today) replays its cached
        // NightResult without touching the store; only dirty nights pay the 8 reads + analyzeDay.
        var scoredNights: [NightResult] = []
        var newSignatures: [String: AnalysisScheduler.NightSignature] = [:]
        var windowDayKeys: Set<String> = []
        var analyzedDays = 0

        for offset in 0..<maxDays {
            let dayStart = now - offset * 86_400
            let day = AnalyticsEngine.dayString(dayStart, tzOffsetSeconds: tzOffset)
            windowDayKeys.insert(day)
            let epochDays = AnalysisScheduler.windowEpochDays(now: now, offset: offset, tzOffsetSeconds: tzOffset)
            let sig = AnalysisScheduler.signature(dayCounts: dayCounts, epochDays: epochDays)
            newSignatures[day] = sig
            if !AnalysisScheduler.isDirty(cached: cache.signatures[day], current: sig, isToday: offset == 0) {
                // Clean: replay the cached night, or the cached "no night here" (skippedDays).
                if let night = cache.nights[day] {
                    // FER-868 D1: un día cacheado como en-progreso (civil-day-only) debe recomputarse una
                    // vez al volverse pasado (ventana completa) — el flag lo detecta aunque la firma de
                    // conteo no cambie.
                    if night.strainCivilDayOnly == (offset == 0) {
                        scoredNights.append(night)
                        continue
                    }
                    // Flag mismatch (today→yesterday transition): fall through to recompute this night.
                } else {
                    // Cached "no night here" (skippedDays) — nothing to replay, stay clean.
                    continue
                }
            }

            // Read a generous window around the night that ends on `day`; the stager finds the span.
            let from = dayStart - 30 * 3_600
            let to = dayStart + 12 * 3_600

            let hr = (try? await store.hrSamples(deviceId: deviceId, from: from, to: to, limit: 200_000)) ?? []
            guard hr.count >= 200 else {   // need real raw data, not a stray sample
                cache.nights[day] = nil
                cache.skippedDays.insert(day)
                continue
            }
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

            // Already off-main at .utility (FER-868) — analyzeDay runs inline, no per-day detach.
            let res = AnalyticsEngine.analyzeDay(day: day, hr: hr, rr: rr, resp: resp, gravity: grav,
                                                 steps: steps, dayHr: dayHr, daySteps: daySteps,
                                                 skinTemp: skin, skinTempOffsetC: skinOffset,
                                                 profile: up, baselines: baselines1, maxHROverride: inputs.maxHR,
                                                 tzOffsetSeconds: tzOffset,
                                                 // The in-progress day (offset 0) scores strain over its own
                                                 // civil day, not the ~42h window that's all of yesterday just
                                                 // after midnight (FER-341).
                                                 strainCivilDayOnly: offset == 0)
            analyzedDays += 1
            let night = NightResult(daily: res.daily, strain: res.strain, cachedSleep: res.cachedSleep,
                                    workouts: res.workouts, nightlySkin: res.nightlySkinTempC,
                                    spectral: res.spectralBands, strainCivilDayOnly: offset == 0)
            scoredNights.append(night)
            cache.nights[day] = night
            cache.skippedDays.remove(day)
            await Task.yield()
        }
        // Adopt the fresh signatures and drop cache entries that slid out of the window.
        cache.signatures = newSignatures
        cache.nights = cache.nights.filter { windowDayKeys.contains($0.key) }
        cache.skippedDays.formIntersection(windowDayKeys)

        // Nightly values harvested from pass 1 (cached or fresh), keyed by day, to seed the pass-2
        // baseline. On-device RSA respiration + wear-gated skin-temp means (baseline-independent)
        // seed resp/skin-temp baselines the same way avgHrv seeds the HRV baseline.
        var nightlyHrvByDay: [String: Double?] = [:]
        var nightlyRhrByDay: [String: Double?] = [:]
        var nightlyRespByDay: [String: Double?] = [:]
        var nightlySkinByDay: [String: Double?] = [:]
        var nightlyEffByDay: [String: Double?] = [:]
        for night in scoredNights {
            nightlyHrvByDay[night.daily.day] = night.daily.avgHrv
            nightlyRhrByDay[night.daily.day] = night.daily.restingHr.map(Double.init)
            nightlyRespByDay[night.daily.day] = night.daily.respRateBpm
            nightlySkinByDay[night.daily.day] = night.nightlySkin
            nightlyEffByDay[night.daily.day] = night.daily.efficiency
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

        // ── FER-60 / FER-519 / FER-634: Apple Health prior — the LOWEST-precedence seed, for RESPIRATION
        // ONLY. A brand-new strap user has no imported history and a handful of on-device nightlies isn't
        // enough to clear Baselines.minNightsSeed, so recovery stays null for the first nights. Folding
        // Apple's respiration UNDER both strap layers (same `== nil` idiom: fill only days NEITHER strap
        // source covered) seeds that baseline, capped to applePriorMaxNights so the seed lands PROVISIONAL,
        // not trusted. Respiration IS the same physical metric across sources — both are breaths/min
        // measured DURING SLEEP (WHOOP via RSA, Apple via the accelerometer) — so this is an honest
        // cold-start prior. Strap ALWAYS wins.
        // FER-634: RHR is NO LONGER seeded from Apple. WHOOP reads RHR from the sleep nadir (deep-sleep-
        // weighted night average); Apple estimates it from awake sedentary samples and EXCLUDES sleep, so
        // Apple RHR runs systematically ~10–13 bpm higher (Fenland Study, Gonzales et al. 2023, PLoS One
        // 18(5):e0285272: sleep 56.9 vs seated 67.6 bpm). The gap varies per person, so there's no fixed
        // offset to subtract — seeding it would bias the cold-start RHR baseline high. RHR now takes the
        // same honest cold-start as HRV: empty until the band accrues its own nights.
        // FER-519: HRV is NOT seeded from Apple either. Apple's HRV is SDNN; the band's is RMSSD — different
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
        var appleRespByDay: [String: Double?] = [:]
        for r in appleRows {
            appleRespByDay[r.day] = r.respRateBpm
        }
        // FER-519: no foldApplePrior for HRV — Apple SDNN never seeds the RMSSD baseline.
        // FER-634: no foldApplePrior for RHR either — band (sleep nadir) and Apple (awake) RHR differ
        // ~10–13 bpm; RHR takes the honest cold-start. Only respiration keeps the Apple prior.
        histRespByDay = Self.foldApplePrior(into: histRespByDay, apple: appleRespByDay, priorDays: priorDays)

        // FER-677: fold each nightly baseline over its chronological (day, value) sequence through the
        // epoch overload, so «Recalibrar recuperación» drops nights < baselineEpoch from ALL of them.
        // With no epoch this is byte-identical to the previous `.keys.sorted().map { dict[$0]! }` fold.
        func seq(_ dict: [String: Double?]) -> [(day: String, value: Double?)] {
            dict.keys.sorted().map { (day: $0, value: dict[$0]!) }
        }
        // Resp baseline gated on `usable`: RecoveryScorer includes the resp term whenever a
        // baseline object is present — a CALIBRATING (<4-night) baseline would let one noisy
        // RSA night move recovery (mirrors the skin-temp use-site gate; honest cold-start).
        let respFold = Baselines.foldHistory(seq(histRespByDay), epoch: baselineEpoch, cfg: respCfg)
        // Personal sleep-efficiency baseline (gated on `usable` at the recovery call site, like
        // resp/skin-temp): the recovery sleep term is measured against the user's own normal once
        // enough nights exist, else falls back to the fixed population center (honest cold-start).
        let effCfg = Baselines.metricCfg["efficiency"]!
        let effFold = Baselines.foldHistory(seq(histEffByDay), epoch: baselineEpoch, cfg: effCfg)
        let baselines2 = AnalyticsEngine.ProfileBaselines(
            hrv: Baselines.foldHistory(seq(histHrvByDay), epoch: baselineEpoch, cfg: hrvCfg),
            restingHR: Baselines.foldHistory(seq(histRhrByDay), epoch: baselineEpoch, cfg: rhrCfg),
            resp: respFold.usable ? respFold : nil,
            // Skin-temp baseline is on-device-only (imported rows carry skinTempDevC, not the raw mean),
            // so fold purely over the pass-1 nightly means in chronological order.
            skinTemp: Baselines.foldHistory(seq(nightlySkinByDay), epoch: baselineEpoch, cfg: skinCfg))

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
        // FER-868: pass 2 runs over ALL nights (cached + fresh) UNCHANGED — that is the guarantee the
        // incremental pass publishes scores identical to a full pass.
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
        // FER-868: the upserts intentionally still write the FULL set (not just dirty nights) —
        // the workout prune below deletes-and-reinserts the whole window and must stay paired
        // with a full re-insert, and full-set upserts keep every run self-healing.
        // FER-881: before writing, note whether these computed daily rows DIFFER from what's already
        // stored — the caller gates the dashboard rebuild on it. Compares only the days this pass writes
        // (a stale prior-only day the engine no longer scores stays put and is not a "change"); a
        // recurring-user relaunch with no new raw data recomputes byte-identical rows ⇒ `false` ⇒ the
        // redundant refresh the launch full-pass already covered is skipped. Read is cheap (bounded
        // window, indexed by (deviceId, day)); a lossy round-trip could only over-report a change (a
        // harmless extra refresh), never hide a real one.
        var dailiesChanged = false
        if !dailies.isEmpty {
            let keys = dailies.map(\.day)
            let prior = (try? await store.dailyMetrics(deviceId: computedId,
                                                       from: keys.min() ?? "", to: keys.max() ?? "")) ?? []
            dailiesChanged = Self.computedDailiesChanged(dailies, vsStored: prior)
            _ = try? await store.upsertDailyMetrics(dailies, deviceId: computedId)
        }
        if !cachedSleep.isEmpty { _ = try? await store.upsertSleepSessions(cachedSleep, deviceId: computedId) }
        // Make re-detection idempotent across runs: clear the prior computed detected workouts in the
        // scored window (a bout's startTs can drift as more HR arrives, which would otherwise orphan
        // stale rows under the (deviceId,startTs,sport) key), then re-insert.
        _ = try? await store.deleteWorkouts(deviceId: computedId, sport: "detected",
                                            from: windowStart, to: now)
        if !workoutRows.isEmpty { _ = try? await store.upsertWorkouts(workoutRows, deviceId: computedId) }

        // ── Frequency-domain HRV (FER-702, ADDITIVE) — persist the nightly band powers as scalars ─────
        // analyzeDay computed a spectral `Bands` (LF/HF/total, ms²) over the same in-bed R-R as avgHrv.
        // Persist the three powers to the generic `metricSeries` cache under the "-noop" source (same
        // substrate as steps_est), so the HRV detail can read them + build a per-band "your normal"
        // baseline without recomputing the O(0.6s/night) Lomb-Scargle on screen open. Idempotent
        // (re-upserts the same (computedId, day, key) rows). `hrv_lf` is omitted when the span was too
        // short for the LF band (nil); the three are omitted entirely on a night with no spectrum.
        var spectralPts: [MetricPoint] = []
        for night in scoredNights {
            guard let b = night.spectral else { continue }
            if let lf = b.lf { spectralPts.append(MetricPoint(day: night.daily.day, key: "hrv_lf", value: lf)) }
            spectralPts.append(MetricPoint(day: night.daily.day, key: "hrv_hf", value: b.hf))
            spectralPts.append(MetricPoint(day: night.daily.day, key: "hrv_totalpower", value: b.totalPower))
        }
        if !spectralPts.isEmpty { _ = try? await store.upsertMetricSeries(spectralPts, deviceId: computedId) }

        // ── Daily motion (FER-868) — computed ONCE per dirty day, persisted, serving TWO consumers ───
        // For every civil day in the motion window whose gravity count moved (or that is today, or
        // that has rows but no persisted scalar yet), ONE gravitySamples read yields BOTH the daily
        // motion scalar (`motion_intensity`, the steps-estimate input) AND the hourly profile
        // (`act_h00`…`act_h23`, the circadian input). Both persist to `metricSeries` under the
        // "-noop" source, so clean days cost zero gravity reads on subsequent passes AND survive an
        // app relaunch. Profile semantics preserved from `activityBins` (FER-712): an hour row exists
        // iff the hour had samples (even at 0.0); an absent hour = no row.
        let todayKey = AnalyticsEngine.dayString(now, tzOffsetSeconds: tzOffset)
        let motionFromKey = AnalyticsEngine.dayString(motionFrom, tzOffsetSeconds: tzOffset)
        let persistedMotionDays = Set(((try? await store.metricSeries(
            deviceId: computedId, key: "motion_intensity",
            from: motionFromKey, to: todayKey)) ?? []).map(\.day))
        let gravityCounts = dayCounts["gravity"] ?? [:]
        var newMotionSignature: [Int: Int] = [:]
        var motionPts: [MetricPoint] = []
        var actPts: [MetricPoint] = []
        for off in 0..<motionWindowDays {
            let dayMid = AnalyticsEngine.localMidnight(now - off * 86_400, tzOffsetSeconds: tzOffset)
            let dayKey = AnalyticsEngine.dayString(dayMid, tzOffsetSeconds: tzOffset)
            let ed = AnalysisScheduler.epochDay(dayMid, tzOffsetSeconds: tzOffset)
            let count = gravityCounts[ed] ?? 0
            let dirty = off == 0 || cache.motionSignature[ed] != count
                || (count > 0 && !persistedMotionDays.contains(dayKey))
            newMotionSignature[ed] = count
            guard dirty, count > 0 else { continue }   // a day with no gravity rows has nothing to persist
            let grav = (try? await store.gravitySamples(deviceId: deviceId, from: dayMid,
                                                        to: dayMid + 86_400 - 1, limit: 200_000)) ?? []
            // The steps scalar keys to the civil day of localMidnight (FER-226) with the pass's tz.
            let m = StepsEstimateEngine.dayMotionIntensity(grav)
            if m > 0 { motionPts.append(MetricPoint(day: dayKey, key: "motion_intensity", value: m)) }
            // The hourly profile resolves the tz AS OF that day, so a DST change inside the window
            // doesn't shift the local-hour binning of the affected days by an hour (FER-712).
            let dayTz = TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(dayMid)))
            let prof = CircadianEngine.hourlyMotionProfile(grav, tzOffsetSeconds: dayTz)
            for h in 0..<24 {
                if let v = prof[h] {
                    actPts.append(MetricPoint(day: dayKey, key: String(format: "act_h%02d", h), value: v))
                }
            }
        }
        cache.motionSignature = newMotionSignature
        if !motionPts.isEmpty { _ = try? await store.upsertMetricSeries(motionPts, deviceId: computedId) }
        if !actPts.isEmpty { _ = try? await store.upsertMetricSeries(actPts, deviceId: computedId) }

        // ── Steps ESTIMATE (WHOOP 4.0 only, FER-663) — daily, keyed to each strap day ───────────────
        // A WHOOP 4.0 sends no step counter over BLE (the @57 counter is 5/MG-only), so we ESTIMATE
        // steps from the strap's daily motion volume, calibrated per-user against the phone's step
        // count (Apple Health) on days both exist. Engine = StepsEstimateEngine (StrandAnalytics,
        // unit-tested); this block is pure orchestration — gather points, fit, upsert `steps_est`
        // under the computed "-noop" source, mirror the fit into ProfileStore for Settings/the tile.
        // Idempotent (re-upserts the same (computedId, day, "steps_est") rows). Inert until there's a
        // calibration — a user with no phone steps sees no estimate until they set a manual `k`.
        // Days the phone DID count keep their real value (the tile prefers real over estimate); on a
        // 5/MG the block never runs — the native counter is authoritative (no estimate needed).
        // FER-868: motionByDay now comes from the PERSISTED `motion_intensity` series (+ the fresh
        // points just computed) instead of 60 raw gravity reads per pass.
        var stepsCalibration: StepsEstimateEngine.Calibration?
        var stepsProgressDays: Int?
        if inputs.family.estimatesSteps {
            // Calibration window: a generous 60 days (not the 21 the scoring loop uses) so enough
            // both-have days accumulate to fit. Reference steps = the apple-health daily `steps`
            // (the same source the dashboard's steps tile reads); motion = the [localMidnight, +24h)
            // gravity volume — the same calendar-day window the daily totals use (FER-226).
            let calRows = mode.usesAppleHealth
                ? ((try? await store.dailyMetrics(
                        deviceId: "apple-health",
                        from: motionFromKey,
                        to: todayKey)) ?? [])
                : []
            var refStepsByDay: [String: Double] = [:]
            for r in calRows where (r.steps ?? 0) > 0 { refStepsByDay[r.day] = Double(r.steps!) }
            // Persisted scalars first, then this pass's fresh values on top (fresh wins for dirty days).
            var motionByDay: [String: Double] = [:]
            for p in (try? await store.metricSeries(deviceId: computedId, key: "motion_intensity",
                                                    from: motionFromKey, to: todayKey)) ?? [] {
                motionByDay[p.day] = p.value
            }
            for p in motionPts { motionByDay[p.day] = p.value }
            let manualK: Double? = inputs.stepsManualCoefficient > 0 ? inputs.stepsManualCoefficient : nil
            let calPoints = motionByDay.compactMap { (day, motion) -> StepsEstimateEngine.CalibrationPoint? in
                guard let s = refStepsByDay[day] else { return nil }
                return StepsEstimateEngine.CalibrationPoint(motion: motion, steps: s)
            }
            if let cal = StepsEstimateEngine.calibrate(calPoints, manualOverride: manualK) {
                // Estimate + upsert every motion day WITHOUT a real phone count (a real count wins; the
                // estimate only fills the gaps). The whole 60-day window re-upserts so the history keeps
                // improving as the calibration converges.
                var estPts: [MetricPoint] = []
                for (day, motion) in motionByDay where refStepsByDay[day] == nil {
                    guard let est = StepsEstimateEngine.estimate(motion: motion, calibration: cal) else { continue }
                    estPts.append(MetricPoint(day: day, key: "steps_est", value: Double(est)))
                }
                if !estPts.isEmpty { _ = try? await store.upsertMetricSeries(estPts, deviceId: computedId) }
                stepsCalibration = cal
            } else if case let .needsMoreDays(have, _) = StepsEstimateEngine.status(calPoints, manualOverride: manualK) {
                stepsProgressDays = have
            }
        }

        // ── Body-clock PHASE (FER-712) — CircadianEngine cosinor over the trailing hourly activity ────
        // Estimate the user's circadian phase from ~14 days of the band's accelerometer rest-activity
        // rhythm and persist ONE record per day for the experimental "Tu reloj corporal" surface. Pure
        // orchestration: read the persisted hourly profiles (`act_hNN`, freshly upserted above for the
        // dirty days) → pool with `activityBins(hourlyProfiles:)` → estimatePhase → upsert. The phase
        // signal is the band's motion, so gate to `usesWhoop`; skip when there's no recent sleep
        // session to read a habitual wake from (the surface then shows "hard to read"). Idempotent
        // (re-upserts today's row for `computedId`).
        if mode.usesWhoop,
           let wake = SleepWindowClock.recent(scoredNights.flatMap { $0.cachedSleep },
                                              now: Date(timeIntervalSince1970: TimeInterval(now)))?.wake {
            let phaseDays = 14
            let phaseFromKey = AnalyticsEngine.dayString(
                AnalyticsEngine.localMidnight(now - (phaseDays - 1) * 86_400, tzOffsetSeconds: tzOffset),
                tzOffsetSeconds: tzOffset)
            let actKeys = (0..<24).map { String(format: "act_h%02d", $0) }
            let actRows = (try? await store.metricSeries(deviceId: computedId, keys: actKeys,
                                                         from: phaseFromKey, to: todayKey)) ?? []
            var profilesByDay: [String: [Double?]] = [:]
            for r in actRows {
                guard let h = Int(r.key.suffix(2)), (0..<24).contains(h) else { continue }
                profilesByDay[r.day, default: [Double?](repeating: nil, count: 24)][h] = r.value
            }
            let (bins, daysObserved) = CircadianEngine.activityBins(hourlyProfiles: Array(profilesByDay.values))
            if let phase = CircadianEngine.estimatePhase(bins: bins, daysObserved: daysObserved,
                                                         habitualWakeHour: wake) {
                let rec = CircadianPhaseRow(
                    day: todayKey,
                    tempMinHour: phase.tempMinHour, acrophaseHours: phase.acrophaseHours,
                    offsetMinutes: phase.offsetVsScheduleMinutes,
                    confidence: phase.confidence.rawValue, daysObserved: daysObserved,
                    bedtimeHour: CircadianEngine.suggestedBedtime(tempMinHour: phase.tempMinHour),
                    wakeHour: wake, computedAt: now)
                _ = try? await store.upsertCircadianPhase(rec, deviceId: computedId)
            }
        }

        return AnalysisOutput(computed: out, writtenDays: Set(dailies.map(\.day)),
                              hadDailies: !dailies.isEmpty, changed: dailiesChanged,
                              stepsCalibration: stepsCalibration, stepsProgressDays: stepsProgressDays,
                              cache: cache, analyzedDays: analyzedDays)
    }

    /// Re-score ONLY the recovery composite for a day against a (re-seeded) baseline. Every other field
    /// in `daily` is baseline-independent and already final from pass 1. Returns nil until the HRV
    /// baseline is usable (RecoveryScorer gates on `hrvBaseline.usable`, i.e. ≥ minNightsSeed valid
    /// nights) — so the honest null-until-4-nights cold-start is free. Mirrors AnalyticsEngine's own
    /// recovery call + Android IntelligenceEngine.recomputeRecovery. (#78)
    private nonisolated static func recomputeRecovery(_ daily: DailyMetric, _ baselines: AnalyticsEngine.ProfileBaselines,
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
    private nonisolated static func recomputeSkinTempDev(_ nightly: Double?, _ base: BaselineState?) -> Double? {
        guard let v = nightly, let b = base, b.usable else { return nil }
        return (Baselines.deviation(v, state: b).delta * 100.0).rounded() / 100.0
    }

    // MARK: - Baseline source filter (FER-519)

    /// The strap-only slice of the merged daily history — the rows that feed the recovery baseline,
    /// EXCLUDING Apple-only days (band-less nights whose `avgHrv` is Apple SDNN, not the band's RMSSD).
    /// Folding Apple SDNN into the RMSSD baseline mixes two different HRV constructs with no published
    /// conversion (Shaffer & Ginsberg 2017, Front Public Health 5:258; Task Force 1996, Circulation
    /// 93:1043); the capped `foldApplePrior` is the only sanctioned Apple→baseline path, and only for
    /// respiration (breaths/min during sleep — the same physical metric across sources). RHR is NOT the
    /// same across sources (band sleep-nadir vs Apple awake-sedentary, ~10–13 bpm gap) so it's no longer
    /// seeded from Apple either (FER-634). `appleHealthDays` is the set
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
    nonisolated static let applePriorMaxNights = 7

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
