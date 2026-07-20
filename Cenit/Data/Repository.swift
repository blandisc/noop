import Foundation
import Combine
import CenitStore
import BiometricStreams
import StrandAnalytics

/// Per-day sleep figures the WHOOP export carried verbatim (metricSeries rows written by
/// the retired WHOOP CSV import under the imported deviceId). The Detalle de Sueño prefers these over its on-device
/// APPROXIMATE recomputations.
struct ImportedSleepFigures: Equatable {
    var performancePct: Double?   // "sleep_performance", 0–100
    var consistencyPct: Double?   // "sleep_consistency", 0–100
    var needMin: Double?          // "sleep_need_min", minutes
    var debtMin: Double?          // "sleep_debt_min", minutes
}

/// Read model over the on-device CenitStore. Opens its own handle (WAL + busy-timeout makes the
/// two-handle BLEManager+Repository pattern safe) and publishes the dashboard caches the screens bind to.
@MainActor
final class Repository: ObservableObject {
    let deviceId: String
    /// The data-source mode (FER-484): which sources feed the dashboard + baseline. Set by `AppModel`
    /// from `SourceModeStore`. `combined` (the default) reads every source exactly as before; capture is
    /// untouched — this only filters reads.
    var dataSourceMode: DataSourceMode = .combined
    /// The baseline cut day-key («Recalibrar recuperación», FER-677): "YYYY-MM-DD" or nil for no cut.
    /// Set by `AppModel` from `ProfileStore.baselineEpochOrNil`. The estimated-recovery path honors it
    /// so the Apple estimate re-anchors exactly like the strap baseline in `IntelligenceEngine`.
    var baselineEpoch: String? = nil
    /// FER-883: the user's effective HRmax + sex for the estimated «Carga del día», set by `AppModel`
    /// from `Profile` (`hrMaxOverride ?? Tanaka(age)`) so the Apple workout-HR estimate uses the SAME
    /// HRmax as the strap's live strain path — no band↔Apple discontinuity. nil ⇒ StrainScorer default.
    var strainHRmax: Double? = nil
    var strainSex: String = "male"
    /// Source id for on-device computed scores (recovery/strain/sleep derived from the raw strap
    /// streams by IntelligenceEngine). Merged UNDER the imported `deviceId` rows at read time, so a
    /// real WHOOP import always wins and the strap-only user still gets a populated dashboard.
    private var computedDeviceId: String { deviceId + "-noop" }
    /// The Apple-derived nocturnal-HRV partition (R2/R3, FER-1008): a SEPARATE metricSeries deviceId from
    /// the strap's `computedDeviceId` and from raw `apple-health`, so the Apple RMSSD-per-night base is
    /// never mixed with the band's or with SDNN. Fixed string (not derived from `deviceId`).
    static let appleComputedDeviceId = "apple-health-noop"
    private var store: CenitStore?
    /// In-flight store creation, memoized so concurrent first-callers (the launch refresh and
    /// TodayView's parallel queries) share ONE open+migrate instead of racing `ensureStore`'s
    /// await window and opening the DB several times. @MainActor makes the set-before-await safe.
    private var storeInit: Task<CenitStore?, Never>?
    private var receiptCache: (value: (counts: (hr: Int, rr: Int, spo2: Int, skinTemp: Int, resp: Int, gravity: Int), latestHRTs: Int?)?, at: Date)?

    /// The whole dashboard, republished as ONE value. Previously `days`/`sleeps`/`importedSleep`/
    /// `loaded`/`refreshSeq` were five separate `@Published`s, so a single `refresh()` fired up to
    /// four `objectWillChange`s — and every one of the ~22 views observing the Repository re-evaluated
    /// its body that many times per refresh. Folding them into one published value means a refresh is
    /// a single publish, hence a single re-render pass (FER-30). The per-field reads below forward to
    /// it, so every existing `repo.days` / `repo.sleeps` / … call site is unchanged.
    struct DashboardData {
        var days: [DailyMetric] = []
        /// Display-only twin of `days`: strap-covered days whose measured fields are nil back-fill from
        /// the Apple Health row the merge overwrote (FER-149). The dashboard sparklines/trends read
        /// these so a partial-connection day shows Apple's HRV instead of a gap; the recovery baseline
        /// reads `days` (excluding `appleHealthDays`, FER-519), not `displayDays`.
        var displayDays: [DailyMetric] = []
        var sleeps: [CachedSleepSession] = []
        var appleSleeps: [CachedSleepSession] = []   // FER-486: Apple Health sleep sessions with a real stage timeline (band-uncovered nights), for the Detalle de Sueño hypnogram
        var importedSleep: [String: ImportedSleepFigures] = [:]
        /// Days whose surfaced daily row came from Apple Health (no strap coverage), so Trends/Sleep
        /// can badge the source without `DailyMetric` carrying a source column. (FER-62)
        var appleHealthDays: Set<String> = []
        /// Days with a stored row per source, UNFILTERED by the data-source mode (FER-485): the diagnostic
        /// coverage reads these so it shows what's stored even in `whoopOnly`/`appleHealthOnly` — the proof
        /// of the «nothing is deleted» invariant. `storedAppleOnlyDays` excludes strap days, mirroring the
        /// merge precedence, so these are the always-Combined coverage counts.
        var storedStrapDays: Set<String> = []
        var storedAppleOnlyDays: Set<String> = []
        /// Count of stored strap sleep sessions, UNFILTERED by the mode (FER-485) — the import block's
        /// «… sleeps stored» line reads this so it stays honest in «Solo Apple Salud».
        var storedSleepsCount: Int = 0
        /// FER-153: the Apple-Health ESTIMATED recovery per band-less night (score + confidence), keyed by
        /// day. Surfaced for display ONLY via `repo.today` + `isRecoveryEstimated`/`recoveryConfidence`;
        /// it is deliberately NOT folded into `days`/`displayDays`, so every recovery statistic over
        /// history stays band-measured (the house rule). Empty unless Apple covers a band-less night.
        var recoveryEstimates: [String: AppleRecoveryEstimator.DayEstimate] = [:]
        /// FER-883: Apple workout-HR strain estimate per band-less day, keyed by day. Mirrors
        /// `recoveryEstimates` — surfaced ONLY via `repo.today`/`estimatedStrain`, never folded into
        /// `days`/`displayDays` or any baseline.
        var strainEstimates: [String: Double] = [:]
        /// FER-670: per-day single-construct fusion — day → metric key ("steps" / "sleep_total_min" /
        /// "active_kcal") → the fused point, ONLY for days where ≥2 sources reported that metric (a
        /// `.single` day has nothing to cross-check, so it's omitted and the dict stays small). Display
        /// transparency only ("coinciden / en conflicto"); it never feeds `days`/`displayDays` or any
        /// baseline. HRV/RHR/resp/stages never appear here — `FusionResolver` refuses them (SourceLens
        /// governs those, FER-629).
        var fusion: [String: [String: FusedMetricPoint]] = [:]
        /// R3 (FER-1008): the nocturnal autonomic trend (below/inBase/above vs the user's OWN settled
        /// baseline), computed ONLY from Apple's `apple-health-noop` RMSSD-per-night partition — never
        /// from the band, never folded into `days`/any baseline. nil in whoopOnly or before enough dense
        /// nights. Surfaced via `todayAutonomicTrend`; the screen (R4) reads it.
        var autonomicTrend: AutonomicTrend.Read? = nil
        var loaded = false
        /// True once a FULL refresh pass (whole stored history) has published. The launch first-paint
        /// pass (~90 days) publishes `loaded == true` with this still false. RULE: anything that
        /// PERSISTS a value derived from `days` — the engine's baselines (`analyzeRecent`), the
        /// experiment verdict (`closeDueExperiment`), the restore offer — must gate on this flag;
        /// pure display readers may see the short window transiently and self-correct on the full
        /// publish. Monotonic within a session: nothing resets it to false.
        var fullyLoaded = false
        var seq = 0
    }
    @Published private(set) var dashboard = DashboardData()

    /// Daily metrics (recovery/strain/sleep/HRV/RHR…), oldest→newest. Includes Apple-only rows (band-less
    /// nights surfaced from Apple Health). The recovery baseline reads this but EXCLUDES `appleHealthDays`
    /// before folding (FER-519, via `IntelligenceEngine.strapOnlyHistory`), so Apple's SDNN never enters
    /// the band's RMSSD baseline; only the capped `foldApplePrior` seeds resp (breaths/min during sleep —
    /// same metric; RHR is band sleep-nadir vs Apple awake, so it's no longer seeded either, FER-634).
    var days: [DailyMetric] { dashboard.days }
    /// Display-only daily rows: `days`, but strap-covered days with nil measured fields back-fill from
    /// Apple Health (FER-149). The dashboard sparklines/trends read these; analytics read `days`.
    var displayDays: [DailyMetric] { dashboard.displayDays }
    /// Cached sleep sessions, oldest→newest.
    var sleeps: [CachedSleepSession] { dashboard.sleeps }
    /// Apple Health sleep sessions carrying a real per-epoch stage timeline (FER-486), for nights the
    /// band didn't cover — the Detalle de Sueño draws a full hypnogram from these.
    var appleSleeps: [CachedSleepSession] { dashboard.appleSleeps }
    /// Imported (export-verbatim) sleep figures by day. Empty until a WHOOP import lands.
    var importedSleep: [String: ImportedSleepFigures] { dashboard.importedSleep }
    var loaded: Bool { dashboard.loaded }
    /// True once the FULL history is published (see `DashboardData.fullyLoaded` for the rule).
    var fullyLoaded: Bool { dashboard.fullyLoaded }
    /// Monotonic counter bumped on every successful `refresh()`. Intraday-updating views key their
    /// data load on this so they reload when fresh strap data lands — `today?.day` alone is a stable
    /// date string within a day and would freeze e.g. the Today HR trend until the date rolls over.
    var refreshSeq: Int { dashboard.seq }
    /// Days surfaced from Apple Health (strap-uncovered) — Trends/Sleep badge these as "Apple Health". (FER-62)
    var appleHealthDays: Set<String> { dashboard.appleHealthDays }
    /// FER-670: the fused single-construct point for a `(day, metric)` — nil unless ≥2 sources reported
    /// that metric on that day. The detail screens read this to show "coinciden / en conflicto" for the
    /// exact day they display; a nil simply shows nothing. `metric` may be any catalog series key — the
    /// policy folds aliases (`energy_kcal`, `asleep_min`) onto the map's canonical key, so no caller has
    /// to know the synonyms.
    func fusionPoint(day: String, metric: String) -> FusedMetricPoint? {
        dashboard.fusion[day]?[MetricArbitrationPolicy.canonicalKey(forKey: metric)]
    }
    /// FER-670: the whole per-day fusion map, for model builders that resolve their own day key
    /// (`SleepDetailModel.build`). Same content `fusionPoint` reads.
    var fusion: [String: [String: FusedMetricPoint]] { dashboard.fusion }
    /// Stored per-source day coverage, UNFILTERED by the mode — the diagnostic coverage on «Datos y
    /// fuentes» reads these so it stays honest in every mode (FER-485).
    var storedStrapDays: Set<String> { dashboard.storedStrapDays }
    var storedAppleOnlyDays: Set<String> { dashboard.storedAppleOnlyDays }
    var storedSleepsCount: Int { dashboard.storedSleepsCount }
    /// True when today's surfaced recovery is an Apple-Health estimate (band-less night, FER-153).
    func isRecoveryEstimated(_ day: String) -> Bool { dashboard.recoveryEstimates[day] != nil }
    /// Confidence grade for an estimated-recovery day; nil when the day isn't an Apple estimate.
    func recoveryConfidence(_ day: String) -> ScoreConfidence? { dashboard.recoveryEstimates[day]?.confidence }
    /// True when today's surfaced strain is an Apple workout-HR estimate (FER-883).
    func isStrainEstimated(_ day: String) -> Bool { dashboard.strainEstimates[day] != nil }
    /// The estimated strain (0–21) for a band-less day; nil unless it's an Apple estimate.
    func estimatedStrain(_ day: String) -> Double? { dashboard.strainEstimates[day] }
    /// How many of the 3 primary drivers (HRV, resting HR, sleep) backed an estimated-recovery day's
    /// score (FER-700); nil when the day isn't an Apple estimate. Lets the UI say WHY an estimate is
    /// conservative («N de 3 señales») rather than only showing the shrunk number.
    func recoveryPrimaryDrivers(_ day: String) -> Int? { dashboard.recoveryEstimates[day]?.presentPrimaryDrivers }
    /// The present primary drivers' directions vs the user's own Apple norm for an estimated-recovery day
    /// (HRV always first) — powers the estimated coverage-attribution block in the recovery Detalle. Empty
    /// when the day isn't an Apple estimate.
    func recoveryEstimateDirections(_ day: String) -> [AppleRecoveryEstimator.SignalDirection] {
        dashboard.recoveryEstimates[day]?.signalDirections ?? []
    }

    init(deviceId: String) { self.deviceId = deviceId }

    /// Today's row, by the device's ACTUAL local calendar date — NOT just the newest stored row, which
    /// after a historical import was months-old data shown as today's hero (issue #23). nil if no row
    /// for today yet (the dashboard then shows its empty/pending state).
    var today: DailyMetric? {
        let key = Repository.localDayKey(Date())
        guard let row = days.last(where: { $0.day == key }) else { return nil }
        // FER-153: a band-less night with an Apple estimate surfaces it HERE, on today's single row only —
        // so the ring / verdict / detail hero read a number instead of «—», while `days`/`displayDays`
        // stay band-measured (every recovery statistic over history is computed off those, never the estimate).
        if row.recovery == nil, let est = dashboard.recoveryEstimates[key] { return row.withRecovery(est.score) }
        return row
    }

    /// R3 (FER-1008): today's autonomic trend read (or nil while calibrating / in whoopOnly). Pure
    /// pass-through of the value `performRefresh` computed off the `apple-health-noop` nightly RMSSD.
    var todayAutonomicTrend: AutonomicTrend.Read? { dashboard.autonomicTrend }

    /// Pure wrapper over the StrandAnalytics engine, kept `nonisolated static` so the refresh can call it
    /// off the main actor and so tests pin the Repository→engine seam without a store. `nights` are the
    /// dense `apple_rmssd_night` rows (oldest→newest); `asOf`/`recentCutoff` are local day keys.
    nonisolated static func autonomicTrend(nights: [(day: String, rmssdMs: Double)],
                                           asOf: String, recentCutoff: String) -> AutonomicTrend.Read {
        AutonomicTrend.evaluate(nights: nights, asOf: asOf, recentCutoff: recentCutoff)
    }
    /// The trailing 7 CALENDAR days ending today (for the week strip), oldest→newest — not the last 7
    /// stored rows, which on a stale import were old data. ISO yyyy-MM-dd compares chronologically.
    var week: [DailyMetric] {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        return days.filter { $0.day >= cutoff }
    }

    /// `yyyy-MM-dd` in the device's local zone, matching how `DailyMetric.day` is stored.
    /// Canonical instance lives in `CenitStore.DayKey` (FER-754); this is the same object.
    private static let dayKeyFormatter = DayKey.localFormatter
    static func localDayKey(_ date: Date) -> String { dayKeyFormatter.string(from: date) }

    /// Parse a stored `yyyy-MM-dd` day key back to a Date in UTC (en_US_POSIX). Charts parse keys in
    /// UTC for DST-stable positions — distinct from `localDayKey` (which WRITES keys in local zone).
    /// The single shared inverse of the day-key contract (FER-325).
    /// Pure arithmetic, zero DateFormatter (FER-972 · M-04).
    nonisolated private static let dayKeyParser = DayKey.utcFormatter

    /// Days since 1970-01-01 for a civil date (Hinnant `days_from_civil`; valid for the app's range).
    /// `ComparisonEngine.epochDay` is package-internal, so this copy lives here for the app layer.
    private nonisolated static func epochDays(y: Int, m: Int, d: Int) -> Int {
        let yy = y - (m <= 2 ? 1 : 0)
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    nonisolated static func parseDayKey(_ s: String) -> Date? {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        return Date(timeIntervalSince1970: Double(epochDays(y: y, m: m, d: d)) * 86_400)
    }

    /// Format a chart date BACK to its `yyyy-MM-dd` key in UTC — the exact inverse of `parseDayKey`,
    /// for dates that were parsed/anchored in UTC (trend points). `localDayKey` on such a date shifts
    /// one day back west of UTC (a UTC-midnight 27th is still the 26th in CDMX) — that mislabeled the
    /// stress levels series a day behind its hero (FER-630).
    nonisolated static func utcDayKey(_ date: Date) -> String { dayKeyParser.string(from: date) }

    /// The `yyyy-MM-dd` key for the day BEFORE `s`, computed in UTC (one fixed 24 h step — UTC has no
    /// DST) so it stays on the same DST-stable footing as `parseDayKey`. Used to cap a "fall back to the
    /// most recent reading" at yesterday (FER-397).
    nonisolated static func previousDayKey(_ s: String) -> String? {
        guard let d = dayKeyParser.date(from: s) else { return nil }
        return dayKeyParser.string(from: d.addingTimeInterval(-86_400))
    }

    /// FER-969 (X-03): the store failed to open (wedged migration, corrupt file) — the UI shows an
    /// honest state with retry/restore instead of an eternally empty dashboard. Reset on success.
    @Published private(set) var storeOpenFailed = false

    /// «Reintentar» from the store-failure state: re-attempt the open and the launch refresh that
    /// never ran. `ensureStore` re-tries naturally once `store`/`storeInit` are nil. (FER-969, X-03)
    func retryStoreOpen() async {
        guard store == nil else { return }
        storeOpenFailed = false
        await refresh()
    }

    private func ensureStore() async -> CenitStore? {
        if let store { return store }
        if let storeInit { return await storeInit.value }   // a creation is already in flight — join it
        let task = Task { () -> CenitStore? in
            guard let path = try? StorePaths.defaultDatabasePath() else { return nil }
            // Don't mask a store-open/migration failure as a silent nil (FER-793). This offline app
            // degrades (returns nil) rather than crashing when the DB won't open, but the failure must
            // be observable — a swallowed `try?` here left a wedged migration undebuggable ("app se trabó"
            // with no error). Log the real error; callers still get nil and degrade.
            let s: CenitStore?
            do {
                // FER-970 (R-04): the Repository handle opens a WAL reader pool so the dashboard
                // snapshot read never waits behind a long engine/import write on this same handle.
                // The BLE handle keeps the default `.queue` backend.
                s = try await CenitStore(path: path, backend: .pool(maxReaders: 2))
            } catch {
                print("[FER-793] CenitStore failed to open at \(path): \(error)")
                s = nil
            }
            if let s { try? await s.upsertDevice(id: deviceId, mac: nil, name: "WHOOP") }
            return s
        }
        storeInit = task              // published synchronously (still on @MainActor) before the await below
        let s = await task.value
        store = s
        storeInit = nil
        storeOpenFailed = (s == nil)  // FER-969 (X-03): surface the failure; clears itself on success
        return s
    }

    /// Expose the shared store handle (used by the importer to persist mapped rows).
    func storeHandle() async -> CenitStore? { await ensureStore() }

    /// One-shot snapshot for the Today "data receipt": stored raw-sample counts + the latest stored
    /// HR sample time (proof the strap's streams are landing and current). nil if no store yet.
    func dataReceipt() async -> (counts: (hr: Int, rr: Int, spo2: Int, skinTemp: Int, resp: Int, gravity: Int), latestHRTs: Int?)? {
        if let cached = receiptCache, Date.now.timeIntervalSince(cached.at) < 120 {
            return cached.value
        }
        guard let store = await ensureStore() else { return nil }
        guard let counts = try? await store.sampleCounts() else { return nil }
        let latest = (try? await store.latestHRSampleTs(deviceId: deviceId)) ?? nil
        let value: (counts: (hr: Int, rr: Int, spo2: Int, skinTemp: Int, resp: Int, gravity: Int), latestHRTs: Int?)? = (counts, latest)
        receiptCache = (value, Date.now)
        return value
    }

    /// "Verify my data": run the store's integrity check. false on any failure (incl. no store yet),
    /// so the UI prompts a retry rather than silently doing nothing.
    func verifyIntegrity() async -> Bool {
        guard let store = await ensureStore() else { return false }
        return (try? await store.integrityCheck()) ?? false
    }

    /// Checkpoint the WAL into the main DB file if the store is already open, so a file-level
    /// backup captures everything. No-op (returns false) if no handle exists yet — the caller
    /// then copies the on-disk files as-is, which still includes the -wal sidecar.
    func checkpointForBackup() async -> Bool {
        guard let store else { return false }
        do { try await store.checkpointWAL(); return true } catch { return false }
    }

    /// First-paint pass of the launch refresh: reload only the trailing `firstPaintWindowDays` so
    /// «Hoy» renders in milliseconds instead of waiting for the full history (the window always
    /// contains today's row and every UI baseline ≤ 90 days). Publishes `loaded == true` but
    /// `fullyLoaded == false` — anything that PERSISTS a value derived from `days` (the engine's
    /// baselines, `closeDueExperiment`, the restore offer) must keep waiting for `fullyLoaded`.
    /// Never overwrites an already-full dashboard (`shouldPublish`).
    func refreshFirstPaint() async {
        await performRefresh(windowDays: Self.firstPaintWindowDays, full: false)
    }

    /// Reload the dashboard caches over the full stored history, merging imported history with the
    /// on-device computed scores so a strap-only user still gets a populated dashboard. Publishes
    /// `fullyLoaded == true`; the heavy merge work runs OFF the main actor (`assembleDashboard`).
    func refresh() async {
        await performRefresh(windowDays: 4000, full: true)
    }

    static let firstPaintWindowDays = 90

    /// Generation counter for in-flight refreshes: only the most recently STARTED refresh may
    /// publish, so a slow old pass (e.g. the launch full pass finishing after a pull-to-refresh)
    /// can never clobber a newer dashboard. @MainActor-confined, so no races.
    private var refreshGen = 0

    /// Whether a finished refresh pass may publish its dashboard. Pure so a unit test can pin the
    /// matrix: a stale generation never publishes; a first-paint pass never overwrites a dashboard
    /// that is already fully loaded (`fullyLoaded` is monotonic within a session).
    nonisolated static func shouldPublish(gen: Int, latestGen: Int,
                                          isFirstPaint: Bool, alreadyFull: Bool) -> Bool {
        gen == latestGen && !(isFirstPaint && alreadyFull)
    }

    private func performRefresh(windowDays nDays: Int, full: Bool) async {
        guard let store = await ensureStore() else { return }
        refreshGen += 1
        let gen = refreshGen
        let now = Date()
        let (fromDay, toDay) = Self.dayWindow(days: nDays, now: now)
        let nowTs = Int(now.timeIntervalSince1970)
        let lo = nowTs - nDays * 86_400, hi = nowTs + 86_400

        // FER-970 (R-03): everything below used to be ~13 sequential actor reads, each with its own
        // hop + read transaction + WAL snapshot (a write could land mid-list and mix two states into
        // one dashboard). `dashboardSnapshot` runs the SAME queries — shared row fetchers, identical
        // SQL — inside ONE transaction: one hop, one snapshot, cross-table consistent. The source-mode
        // query gating (FER-484/486) rides in the request; the in-memory gating below is unchanged.
        // (Unqualified type names: the ACTOR `CenitStore` shadows the module of the same name in
        // qualified lookup from the app layer — `CenitStore.DashboardReadRequest` doesn't resolve.)
        let snap = (try? await store.dashboardSnapshot(DashboardReadRequest(
            strapDeviceId: deviceId, computedDeviceId: computedDeviceId, appleDeviceId: "apple-health",
            fromDay: fromDay, toDay: toDay, fromTs: lo, toTs: hi, sleepLimit: 4000,
            includeApple: dataSourceMode.usesAppleHealth,
            includeWhoopSeries: dataSourceMode.usesWhoop))) ?? DashboardSnapshot()
        let importedRaw = snap.importedDays
        let computedRaw = snap.computedDays
        // FER-62: Apple Health daily rows — the lowest-precedence fallback layer for the dashboard,
        // so a strap-uncovered user still sees HRV / resting HR / sleep-stage trends. Read UNGATED
        // (they feed the FER-485 coverage diagnostic even when the mode hides the source).
        let appleRaw = snap.appleDays
        // FER-484: the mode filters which sources enter the merge/baseline. `combined` is the identity
        // (regression zero); `whoopOnly` drops Apple; `appleHealthOnly` drops the strap. The strap sleep
        // + verbatim figures below are strap-sourced, so they're gated on `usesWhoop` the same way.
        let (imported, computed, apple) = DataSourcePolicy.filter(dataSourceMode, imported: importedRaw, computed: computedRaw, apple: appleRaw)
        // FER-485: strap sleeps arrive UNFILTERED for the diagnostic stored-count, then gate for the dashboard.
        let impSleepRaw = snap.importedSleeps
        let compSleepRaw = snap.computedSleeps
        let impSleep = dataSourceMode.usesWhoop ? impSleepRaw : []
        let compSleep = dataSourceMode.usesWhoop ? compSleepRaw : []
        // FER-486: Apple Health sleep sessions (real per-epoch stage timeline), gated on the mode. The band
        // wins per night, so the appleSleeps surfaced to the Detalle drop any overlapping a strap session.
        let appleSleepRaw = snap.appleSleeps
        // FER-883: Apple workout-HR samples under apple-health (persisted by HealthKitBridge during
        // HKWorkouts only). Gated on usesAppleHealth so whoopOnly never reads them into the dashboard.
        // FER-970 (R-01): their ONLY consumer is the estimated-strain path for days whose MERGED
        // strain is nil — a band-covered history has none, so skip the ≤500k-row read (paid on
        // EVERY refresh) entirely instead of loading and grouping it for nothing. The pre-pass
        // reuses the same mergeDaily the assembler runs, so eligibility can't drift. Deliberately
        // OUTSIDE the snapshot: it's a skippable phase-B read, not dashboard state.
        let appleHrRaw: [HRSample]
        if dataSourceMode.usesAppleHealth,
           !Self.strainEstimateEligibleDays(imported: imported, computed: computed, apple: apple).isEmpty {
            appleHrRaw = (try? await store.hrSamples(deviceId: "apple-health", from: lo, to: hi, limit: 500_000)) ?? []
        } else {
            appleHrRaw = []
        }

        // Export-verbatim sleep figures (long-format metricSeries rows from the retired WHOOP CSV import).
        // The Detalle de Sueño prefers these per day over its APPROXIMATE recomputations.
        // FER-670: single-construct fusion inputs the daily rows above don't carry — Apple's step/energy
        // aggregates (appleDaily) and the WHOOP 4.0 on-device step estimate (steps_est). Gated on the
        // mode like every other read (in the snapshot request), so an excluded source can never appear
        // in a compare row.
        let appleAggRaw = snap.appleAgg
        let stepsEstRaw = snap.stepsEst

        let perf = snap.sleepPerformance
        let cons = snap.sleepConsistency
        let need = snap.sleepNeed
        let debt = snap.sleepDebt

        // The O(n) merge/fusion work over every row read runs OFF the main actor (`assembleDashboard`
        // is nonisolated) — on a years-deep DB the full pass builds the dashboard without stealing
        // frames from the UI the first-paint pass already put up.
        let assembled = await Self.assembleDashboard(RefreshInputs(
            importedRaw: importedRaw, computedRaw: computedRaw, appleRaw: appleRaw,
            imported: imported, computed: computed, apple: apple,
            impSleepRaw: impSleepRaw, compSleepRaw: compSleepRaw,
            impSleep: impSleep, compSleep: compSleep, appleSleepRaw: appleSleepRaw,
            appleHrRaw: appleHrRaw,
            appleAggRaw: appleAggRaw, stepsEstRaw: stepsEstRaw,
            perf: perf, cons: cons, need: need, debt: debt, baselineEpoch: baselineEpoch,
            strainHRmax: strainHRmax, strainSex: strainSex))

        // Back on the main actor: publish only if this is still the newest refresh, and never let a
        // first-paint pass overwrite a fully loaded dashboard.
        guard Self.shouldPublish(gen: gen, latestGen: refreshGen,
                                 isFirstPaint: !full, alreadyFull: dashboard.fullyLoaded) else { return }
        var next = assembled
        next.loaded = true
        next.fullyLoaded = full
        next.seq = dashboard.seq + 1
        // R3 (FER-1008): the nocturnal autonomic trend rides ONLY on Apple's `apple-health-noop`
        // RMSSD-per-night partition — computed here (needs `now` + the store) and injected into the
        // freshly-assembled dashboard. Band path stays bit-identical; in whoopOnly (no Apple) it's nil.
        if dataSourceMode.usesAppleHealth {
            let nightRows = (try? await store.metricSeries(deviceId: Self.appleComputedDeviceId,
                                                           key: "apple_rmssd_night", from: fromDay, to: toDay)) ?? []
            let asOf = Self.localDayKey(now)
            let recentCutoff = Self.localDayKey(Calendar.current.date(byAdding: .day, value: -6, to: now) ?? now)
            next.autonomicTrend = Self.autonomicTrend(nights: nightRows.map { (day: $0.day, rmssdMs: $0.value) },
                                                      asOf: asOf, recentCutoff: recentCutoff)
        }
        // One assignment → one objectWillChange for the whole refresh (was four).
        self.dashboard = next
        #if DEBUG
        let ms = Int(Date().timeIntervalSince(now) * 1000)
        print("[refresh] \(full ? "full" : "firstPaint") publicado en \(ms) ms · \(next.days.count) días")
        #endif
    }

    /// Every raw query result a refresh pass read, plus the already-mode-filtered variants (the
    /// gating happens at query time, exactly as before). Value types only, so the bundle can cross
    /// off the main actor into `assembleDashboard`.
    struct RefreshInputs {
        var importedRaw: [DailyMetric]; var computedRaw: [DailyMetric]; var appleRaw: [DailyMetric]
        var imported: [DailyMetric]; var computed: [DailyMetric]; var apple: [DailyMetric]
        var impSleepRaw: [CachedSleepSession]; var compSleepRaw: [CachedSleepSession]
        var impSleep: [CachedSleepSession]; var compSleep: [CachedSleepSession]
        var appleSleepRaw: [CachedSleepSession]
        /// FER-883: Apple workout-HR samples (deviceId `apple-health`), empty when whoopOnly.
        var appleHrRaw: [HRSample] = []
        var appleAggRaw: [AppleDaily]; var stepsEstRaw: [MetricPoint]
        var perf: [MetricPoint]; var cons: [MetricPoint]; var need: [MetricPoint]; var debt: [MetricPoint]
        /// Baseline cut day-key for the estimated-recovery path (FER-677); nil = no cut.
        var baselineEpoch: String? = nil
        /// FER-883: effective HRmax + sex for the estimated strain, threaded from the Repository props.
        var strainHRmax: Double? = nil
        var strainSex: String = "male"
    }

    /// Pure assembly of the dashboard from rows already read — the EXACT merge pipeline `refresh()`
    /// ran inline before the two-pass split, extracted verbatim so the merge/fusion tests keep
    /// pinning it. `nonisolated async` ⇒ runs on the global executor, not the main actor. Returns
    /// the dashboard with `loaded`/`fullyLoaded`/`seq` left at defaults — publication (and whether
    /// it happens at all) is the caller's @MainActor decision.
    nonisolated static func assembleDashboard(_ inputs: RefreshInputs) async -> DashboardData {
        let strapSleeps = Self.mergeSleep(imported: inputs.impSleep, computed: inputs.compSleep)
        let appleSleeps = Self.appleSleepsNotCoveredByStrap(apple: inputs.appleSleepRaw, strap: strapSleeps)

        var fig: [String: ImportedSleepFigures] = [:]
        for p in inputs.perf { fig[p.day, default: ImportedSleepFigures()].performancePct = p.value }
        for p in inputs.cons { fig[p.day, default: ImportedSleepFigures()].consistencyPct = p.value }
        for p in inputs.need { fig[p.day, default: ImportedSleepFigures()].needMin = p.value }
        for p in inputs.debt { fig[p.day, default: ImportedSleepFigures()].debtMin = p.value }

        let merged = Self.mergeDaily(imported: inputs.imported, computed: inputs.computed, apple: inputs.apple)
        // FER-153 (Capa 2) + FER-529 (F4b): the ESTIMATED recovery for any day whose MEASURED recovery is
        // nil — a band-less Apple night (FER-153) OR a cold-start night where the band is worn but its RMSSD
        // baseline isn't seeded yet (FER-529). Computed read-time (no migration/persistence). Eligibility
        // mirrors the `repo.today` selector EXACTLY (`recovery == nil`), so an estimate exists ⟺ it would be
        // surfaced — `isRecoveryEstimated` never lies, and the band wins the instant it can compute. It is
        // NOT folded into the merge — `days`/`displayDays` stay band-measured, so no recovery statistic over
        // history can mix in an estimate; it surfaces only via `repo.today` (single day). `whoopOnly` →
        // `apple == []` → empty. `mergeDaily` is the unchanged band/Apple merge.
        let daysNeedingEstimate = Set(merged.days.filter { $0.recovery == nil }.map(\.day))
        let estimates = Self.appleRecoveryEstimates(apple: inputs.apple, eligibleDays: daysNeedingEstimate,
                                                    epoch: inputs.baselineEpoch)
        // FER-883: ESTIMATED strain for days whose MEASURED strain is nil (band-less Apple day).
        // Mirrors recovery: never folded into days/displayDays; surfaced only via estimatedStrain.
        let daysNeedingStrainEstimate = Set(merged.days.filter { $0.strain == nil }.map(\.day))
        // FER-970 (R-01): group by LOCAL day with a day-window cache — one calendar/formatter
        // resolution per day actually crossed instead of a DateFormatter call PER SAMPLE (samples
        // arrive in workout-clustered runs), and only the days an estimate can serve are kept.
        var hrByDayApple: [String: [HRSample]] = [:]
        if !inputs.appleHrRaw.isEmpty, !daysNeedingStrainEstimate.isEmpty {
            let cal = Calendar.current
            var windowStart = Int.max, windowEnd = Int.min, windowDay = ""
            for s in inputs.appleHrRaw {
                if s.ts < windowStart || s.ts >= windowEnd {
                    let d = Date(timeIntervalSince1970: Double(s.ts))
                    let start = cal.startOfDay(for: d)
                    windowStart = Int(start.timeIntervalSince1970)
                    windowEnd = cal.date(byAdding: .day, value: 1, to: start)
                        .map { Int($0.timeIntervalSince1970) } ?? windowStart + 86_400
                    windowDay = DayKey.local(d)
                }
                if daysNeedingStrainEstimate.contains(windowDay) {
                    hrByDayApple[windowDay, default: []].append(s)
                }
            }
        }
        var restingHRByDayApple: [String: Double] = [:]
        for row in inputs.apple {
            if let rhr = row.restingHr { restingHRByDayApple[row.day] = Double(rhr) }
        }
        let strainEstimates = Self.appleStrainEstimates(hrByDay: hrByDayApple,
                                                        eligibleDays: daysNeedingStrainEstimate,
                                                        restingHRByDay: restingHRByDayApple,
                                                        maxHR: inputs.strainHRmax, sex: inputs.strainSex)
        // FER-485: stored per-source coverage from the UNFILTERED raws (the always-Combined truth), so the
        // diagnostic coverage shows what's stored even when the mode hides a source from the dashboard.
        let storedStrap = Set(inputs.importedRaw.map(\.day)).union(inputs.computedRaw.map(\.day))
        let storedAppleOnly = Set(inputs.appleRaw.map(\.day)).subtracting(storedStrap)
        let storedSleeps = Self.mergeSleep(imported: inputs.impSleepRaw, computed: inputs.compSleepRaw).count
        // FER-670: per-day single-construct fusion (steps / sleep total / active kcal) from the
        // mode-filtered arrays — display transparency only, never a baseline input.
        var stepsEstByDay: [String: Double] = [:]
        for p in inputs.stepsEstRaw { stepsEstByDay[p.day] = p.value }
        let fusion = Self.fusionByDay(imported: inputs.imported, computed: inputs.computed, apple: inputs.apple,
                                      appleAgg: inputs.appleAggRaw, stepsEst: stepsEstByDay)
        return DashboardData(
            days: merged.days,
            displayDays: merged.displayDays,
            sleeps: strapSleeps,
            appleSleeps: appleSleeps,
            importedSleep: fig,
            appleHealthDays: merged.appleDays,
            storedStrapDays: storedStrap,
            storedAppleOnlyDays: storedAppleOnly,
            storedSleepsCount: storedSleeps,
            recoveryEstimates: estimates,
            strainEstimates: strainEstimates,
            fusion: fusion
        )
    }

    /// Seed the dashboard with pre-built rows in a single publish — for SwiftUI previews, which have
    /// no store to `refresh()` from. `refresh()` is the production path.
    func setDashboard(days: [DailyMetric] = [],
                      sleeps: [CachedSleepSession] = [],
                      importedSleep: [String: ImportedSleepFigures] = [:],
                      appleHealthDays: Set<String> = [],
                      loaded: Bool = true,
                      fullyLoaded: Bool = true) {
        dashboard = DashboardData(days: days, displayDays: days, sleeps: sleeps, importedSleep: importedSleep,
                                  appleHealthDays: appleHealthDays, loaded: loaded, fullyLoaded: fullyLoaded,
                                  seq: dashboard.seq + 1)
    }

    /// Layered precedence (FER-62): Apple Health rows are the base, on-device computed rows fill the
    /// days they don't cover, and imported strap rows win over everything — so the strap always beats
    /// Apple Health. Also returns the days whose surfaced row stayed Apple Health (strap-uncovered),
    /// for source badging.
    ///
    /// `days` includes Apple-only rows (the base layer below): a band-less night surfaces Apple's
    /// HRV/sleep, and `appleDays` is the SET of those days. The recovery baseline reads `repo.days` but
    /// EXCLUDES `appleHealthDays` before folding HRV/RHR/resp (FER-519, `IntelligenceEngine.strapOnlyHistory`),
    /// so Apple's SDNN never enters the band's RMSSD baseline — only the capped `foldApplePrior` seeds
    /// resp (breaths/min during sleep — same metric; RHR is band sleep-nadir vs Apple awake, no longer
    /// seeded, FER-634). `displayDays` (FER-149) is a display-only twin of `days`: a
    /// strap-covered day whose measured fields are nil (a partial-connection day) back-fills those nils
    /// from the Apple Health row this merge overwrote, so the HRV sparkline/trend shows Apple's value
    /// instead of a gap. The strap value always wins when present — only genuine gaps fill.
    /// FER-970 (R-01): the days whose MERGED strain is nil — the only days Apple workout-HR can
    /// serve (the estimated-strain path). A pure pre-pass over rows performRefresh has already
    /// read, so the ≤500k-row HR read can be skipped outright when this comes back empty. Reuses
    /// the very same `mergeDaily` the assembler runs — eligibility cannot drift from it.
    nonisolated static func strainEstimateEligibleDays(imported: [DailyMetric], computed: [DailyMetric],
                                                       apple: [DailyMetric]) -> Set<String> {
        Set(mergeDaily(imported: imported, computed: computed, apple: apple)
            .days.filter { $0.strain == nil }.map(\.day))
    }

    nonisolated static func mergeDaily(imported: [DailyMetric], computed: [DailyMetric],
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

    /// FER-153 (Capa 2) + FER-529 (F4b): the ESTIMATED recovery for each day in `eligibleDays`, keyed by
    /// day. `eligibleDays` is exactly the set of days whose MEASURED recovery is nil (mirrors the
    /// `repo.today` selector) — a band-less Apple night, OR a cold-start night where the band is worn but
    /// its RMSSD baseline isn't seeded yet. The SDNN-vs-own-SDNN estimate is computed by the pure
    /// `AppleRecoveryEstimator` (separate baseline, never the strap's RMSSD). This **does NOT touch
    /// `days`/`displayDays`** — those stay band-MEASURED only so no recovery statistic over history can ever
    /// mix in an estimate. The estimate is surfaced for display ONLY through `repo.today` (single day) +
    /// `isRecoveryEstimated`/`recoveryConfidence`. Keying on `eligibleDays` (⟺ `recovery == nil`) keeps
    /// `isRecoveryEstimated` honest: an estimate exists only where it would actually be shown, so the band
    /// wins the instant it can compute. Pure + static so `RepositoryMergeTests` can pin it. `apple == []`
    /// (whoopOnly) → empty.
    nonisolated static func appleRecoveryEstimates(apple: [DailyMetric], eligibleDays: Set<String>,
                                                   epoch: String? = nil)
        -> [String: AppleRecoveryEstimator.DayEstimate] {
        guard !apple.isEmpty else { return [:] }
        let nights = apple.map {
            AppleRecoveryEstimator.Night(day: $0.day, hrvSDNN: $0.avgHrv,
                                         restingHr: $0.restingHr.map(Double.init), resp: $0.respRateBpm,
                                         sleepPerf: $0.efficiency, sleepMinutes: $0.totalSleepMin)
        }
        var out: [String: AppleRecoveryEstimator.DayEstimate] = [:]
        for e in AppleRecoveryEstimator.estimate(nights: nights, epoch: epoch) where eligibleDays.contains(e.day) {
            out[e.day] = e   // surfaced only where the measured recovery is nil (band-less OR cold-start)
        }
        return out
    }

    /// FER-883: per-day cardiovascular-load estimate from Apple workout HR, for days whose MEASURED
    /// strain is nil (band-less day in Apple/Combined mode). Mirrors `appleRecoveryEstimates`'s contract:
    /// pure + static (RepositoryMergeTests pins it), NEVER folded into `days`/`displayDays`, surfaced only
    /// via `repo.today`/`estimatedStrain`/`isStrainEstimated`. `hrByDay` is apple-health HR samples
    /// (workout-only — HealthKitBridge only persists HR during HKWorkouts) grouped by LOCAL day
    /// (`CenitStore.DayKey.local`). Reuses `StrainScorer.strain` (Edwards TRIMP) — no new math.
    /// `maxHR`/`sex` come from the user's `Profile` (`hrMaxOverride ?? Tanaka(age)`), threaded via the
    /// Repository props by `AppModel` — the SAME HRmax the strap live-strain path uses, so the estimate
    /// never jumps band↔Apple (FER-883 /cso). nil `maxHR` still falls back to the StrainScorer default.
    nonisolated static func appleStrainEstimates(hrByDay: [String: [HRSample]], eligibleDays: Set<String>,
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
    nonisolated static func fusionByDay(imported: [DailyMetric], computed: [DailyMetric], apple: [DailyMetric],
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
    nonisolated private static func mergeSleep(imported: [CachedSleepSession], computed: [CachedSleepSession]) -> [CachedSleepSession] {
        func endDay(_ s: CachedSleepSession) -> String {
            DayKey.local(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
        }
        var byDay: [String: CachedSleepSession] = [:]
        for s in computed { byDay[endDay(s)] = s }
        for s in imported { byDay[endDay(s)] = s }
        return byDay.values.sorted { $0.startTs < $1.startTs }
    }

    // MARK: - Detail passthroughs

    func dailyMetrics(fromDay: String, toDay: String) async -> [DailyMetric] {
        guard dataSourceMode.usesWhoop else { return [] }   // FER-484: appleHealthOnly excludes the strap
        guard let store = await ensureStore() else { return [] }
        return (try? await store.dailyMetrics(deviceId: deviceId, from: fromDay, to: toDay)) ?? []
    }

    func hrSamples(from: Int, to: Int, limit: Int = 8000) async -> [HRSample] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.hrSamples(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []
    }

    /// Beat-to-beat R-R intervals for the strap in `[from, to]`. Feeds the intraday stress engine
    /// (`StressEngine`), which derives RMSSD per window. Recomputed on the fly like `hrSamples`; the
    /// `rrInterval` table is index-covered by `(deviceId, ts)` so a multi-day read is a range scan. (FER-377)
    func rrIntervals(from: Int, to: Int, limit: Int = 200_000) async -> [RRInterval] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.rrIntervals(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []
    }

    /// Raw skin-temperature samples (`raw_adc`) for the strap in `[from, to]`. Range-scanned like
    /// `rrIntervals`. Feeds the nocturnal thermal-stability surface (FER-850). °C = raw/128 + offset.
    func skinTempSamples(from: Int, to: Int, limit: Int = 200_000) async -> [SkinTempSample] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.skinTempSamples(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []
    }

    /// FER-972 (P-05): day-keys (per scalar key) already attempted this app session whose night read
    /// unreadable/too-thin — don't re-read their raw samples on every sheet open. In-memory only:
    /// a relaunch (or the nightly pass re-scoring the night) retries naturally.
    private var nocturnalScalarAttempted: Set<String> = []

    /// Per-night distal warming magnitudes (°C, sleep-onset → nocturnal plateau) over the last `nights`
    /// strap nights, oldest → newest, for the thermal-stability read (FER-850). `nil` for a night with too
    /// little temp. FER-972 (P-05): reads the `night_warming_c` scalar the nightly pass persists next to
    /// `hrv_lf`; only nights the engine window didn't cover are computed here once (write-through), so a
    /// sheet open stops re-reading ~28 nights × raw samples. The math lives in
    /// `ThermalStabilityEngine.warmingMagnitudeC` (same body, moved to the package with its test).
    func nocturnalWarmingMagnitudes(nights: Int = 28) async -> [Double?] {
        guard dataSourceMode.usesWhoop else { return [] }
        let now = Int(Date().timeIntervalSince1970)
        let from = now - (nights + 2) * 86_400
        let sessions = (await sleepSessions(from: from, to: now)).suffix(nights)
        let stored = Dictionary((await computedSeries(key: "night_warming_c", days: nights + 3))
                                    .map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        var out: [Double?] = []
        for s in sessions where s.startTs < s.endTs {
            let day = DayKey.local(Date(timeIntervalSince1970: Double(s.endTs)))
            if let v = stored[day] { out.append(v); continue }
            let memo = "w|\(day)"
            if nocturnalScalarAttempted.contains(memo) { out.append(nil); continue }
            nocturnalScalarAttempted.insert(memo)
            let samples = (await skinTempSamples(from: s.startTs, to: s.endTs)).sorted { $0.ts < $1.ts }
            let v = ThermalStabilityEngine.warmingMagnitudeC(inBedRaw: samples)
            if let v, let store = await ensureStore() {
                _ = try? await store.upsertMetricSeries(
                    [MetricPoint(day: day, key: "night_warming_c", value: v)], deviceId: computedDeviceId)
            }
            out.append(v)
        }
        return out
    }

    /// Gravity (accelerometer) samples for the strap in `[from, to]`. Feeds the night-rhythm
    /// motion gate (`NightRhythmAssembler`), which needs per-window stillness to discard
    /// movement-contaminated windows. Range-scanned like `rrIntervals` over `(deviceId, ts)`. (FER-666)
    func gravitySamples(from: Int, to: Int, limit: Int = 200_000) async -> [GravitySample] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.gravitySamples(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []
    }

    /// The latest persisted body-clock phase (computed source), for the «Tu reloj corporal» surface
    /// (FER-712). nil until the nightly IntelligenceEngine pass has written one.
    func latestCircadianPhase() async -> CircadianPhaseRow? {
        guard let store = await ensureStore() else { return nil }
        return (try? await store.latestCircadianPhase(deviceId: computedDeviceId)) ?? nil
    }

    /// Downsampled HR (mean bpm per `bucketSeconds`) for the strap, for a Today/24h trend chart.
    /// Aggregated in SQL so a full day never loads the raw ~1 Hz rows.
    func hrBuckets(from: Int, to: Int, bucketSeconds: Int = 300) async -> [HRBucket] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.hrBuckets(deviceId: deviceId, from: from, to: to, bucketSeconds: bucketSeconds)) ?? []
    }

    /// Sleep sessions overlapping `[from, to]`, MERGED across the imported (raw `deviceId`) and on-device
    /// COMPUTED (`computedDeviceId`, "-noop") sources — a live strap user's nightly sleep is written by the
    /// IntelligenceEngine under "-noop", an import user's under the raw id. Reading only the raw id missed a
    /// BLE user's sleep entirely, so the intraday-stress exclusion never fired and the night read as waking
    /// (FER-451). Mirrors the dashboard's own sleep merge. Deduped by startTs (imported/export wins on a
    /// collision), oldest first.
    func sleepSessions(from: Int, to: Int, limit: Int = 100) async -> [CachedSleepSession] {
        guard let store = await ensureStore() else { return [] }
        // FER-484/486: the mode filters which sources are read. Strap (imported + on-device computed) is
        // gated on usesWhoop; Apple Health sleep sessions (FER-486, per-night stage timeline) on usesAppleHealth.
        let imported = dataSourceMode.usesWhoop ? ((try? await store.sleepSessions(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []) : []
        let computed = dataSourceMode.usesWhoop ? ((try? await store.sleepSessions(deviceId: computedDeviceId, from: from, to: to, limit: limit)) ?? []) : []
        let apple = dataSourceMode.usesAppleHealth ? ((try? await store.sleepSessions(deviceId: "apple-health", from: from, to: to, limit: limit)) ?? []) : []
        return Self.mergeSleepSessions(imported: imported, computed: computed, apple: apple)
    }

    /// Merge sleep sessions across sources. Strap is the base — imported (real export) wins over the
    /// on-device computed row on the same `startTs`. An Apple Health session is added ONLY if no strap
    /// session overlaps its `[startTs, endTs]` span: the band wins PER NIGHT (FER-486), because a strap
    /// night and Apple's session for the same sleep have different `startTs` (so a startTs dedup can't
    /// catch them). Pure + static so `SleepSessionMergeTests` can pin it; with `apple == []` it is the
    /// prior strap-only merge byte-for-byte (regression zero).
    static func mergeSleepSessions(imported: [CachedSleepSession], computed: [CachedSleepSession],
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
    nonisolated static func appleSleepsNotCoveredByStrap(apple: [CachedSleepSession], strap: [CachedSleepSession]) -> [CachedSleepSession] {
        apple.filter { a in !strap.contains { $0.startTs <= a.endTs && $0.endTs >= a.startTs } }
             .sorted { $0.startTs < $1.startTs }
    }

    // MARK: - Metric explorer reads (generic substrate)

    /// Daily series for any metric key from a given source ("strap" / "apple-health").
    func series(key: String, source: String, days: Int = 4000) async -> [(day: String, value: Double)] {
        guard let store = await ensureStore() else { return [] }
        let (from, to) = Self.dayWindow(days: days)
        let pts = (try? await store.metricSeries(deviceId: source, key: key, from: from, to: to)) ?? []
        return pts.map { ($0.day, $0.value) }
    }

    /// Daily series for a metric written under the ON-DEVICE COMPUTED source (`-noop`, the
    /// IntelligenceEngine outputs like `steps_est`). Derives `computedDeviceId` here so callers never
    /// reconstruct the `-noop` suffix by hand (FER-663).
    func computedSeries(key: String, days: Int = 4000) async -> [(day: String, value: Double)] {
        await series(key: key, source: computedDeviceId, days: days)
    }

    // MARK: - Intraday stress summaries (FER-378) — persisted in metricSeries, no new table

    private static let stressPartPrefix = "stress-part-"     // + PartOfDay.rawValue
    private static let stressPeakHourKey = "stress-peak-hour"
    private static let stressDayMeanKey = "stress-day-mean"

    /// Sleep spans (wall-clock seconds) overlapping `[from, to]`, to exclude from the waking reference.
    private func sleepSpans(from: Int, to: Int) async -> [ClosedRange<Int>] {
        (await sleepSessions(from: from, to: to)).compactMap { $0.startTs <= $0.endTs ? $0.startTs...$0.endTs : nil }
    }

    /// Median nocturnal Deceleration Capacity (ms) over the last `nights` strap nights, for the DC-trend
    /// baseline the «reserva para bajar de marcha» surface reads against (FER-849). One R-R read per night,
    /// so it's heavy — the caller runs it off the hot path (async loader). Each night's DC is computed over
    /// its sleep session span (same span the surface uses tonight, so the trend isn't biased by method).
    /// nil unless at least 3 recent nights read cleanly (an honest "no baseline yet" ⇒ no trend arrow).
    func nocturnalDCBaseline(nights: Int = 14) async -> Double? {
        guard dataSourceMode.usesWhoop else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let from = now - (nights + 2) * 86_400
        let sessions = await sleepSessions(from: from, to: now)
        // FER-972 (P-05): the nightly pass persists `night_dc_ms` per night (next to `hrv_lf`);
        // only nights it didn't cover are computed here once (write-through) — a sheet open stops
        // re-reading ~14 nights × R-R. Fallback math identical to before (NocturnalDC over the span).
        let stored = Dictionary((await computedSeries(key: "night_dc_ms", days: nights + 3))
                                    .map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        var dcs: [Double] = []
        for s in sessions.suffix(nights) where s.startTs < s.endTs {
            let day = DayKey.local(Date(timeIntervalSince1970: Double(s.endTs)))
            if let v = stored[day] { dcs.append(v); continue }
            let memo = "dc|\(day)"
            if nocturnalScalarAttempted.contains(memo) { continue }
            nocturnalScalarAttempted.insert(memo)
            let rr = (await rrIntervals(from: s.startTs, to: s.endTs)).map { Double($0.rrMs) }
            let r = NocturnalDC.compute(rawRR: rr)
            guard r.confidence != .unreadable else { continue }
            if let store = await ensureStore() {
                _ = try? await store.upsertMetricSeries(
                    [MetricPoint(day: day, key: "night_dc_ms", value: r.dcMs)], deviceId: computedDeviceId)
            }
            dcs.append(r.dcMs)
        }
        guard dcs.count >= 3 else { return nil }
        let sorted = dcs.sorted()
        return sorted[sorted.count / 2]
    }

    /// Per-day intraday-stress summaries (FER-378), reassembled from `metricSeries`, last `days` days.
    /// Only days with a stored day-mean appear. Read under the on-device computed device id.
    func stressDaySummaries(days: Int = 60) async -> [String: StressDaySummary] {
        guard let store = await ensureStore() else { return [:] }
        let (from, to) = Self.dayWindow(days: days)
        func points(_ key: String) async -> [MetricPoint] {
            (try? await store.metricSeries(deviceId: computedDeviceId, key: key, from: from, to: to)) ?? []
        }
        var parts: [String: [PartOfDay: Double]] = [:]
        for part in PartOfDay.allCases {
            for p in await points(Self.stressPartPrefix + part.rawValue) { parts[p.day, default: [:]][part] = p.value }
        }
        let peakByDay = Dictionary(await points(Self.stressPeakHourKey).map { ($0.day, Int($0.value)) }, uniquingKeysWith: { _, b in b })
        let meanByDay = Dictionary(await points(Self.stressDayMeanKey).map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        var out: [String: StressDaySummary] = [:]
        for (day, mean) in meanByDay {
            out[day] = StressDaySummary(partMeans: parts[day] ?? [:], peakHour: peakByDay[day], dayMean: mean)
        }
        return out
    }

    /// Compute + persist any MISSING per-day stress summaries over the last `days` days (FER-378).
    /// Idempotent — only days without a stored day-mean are computed. Builds ONE recent waking reference
    /// (sleep excluded) and applies it to all days (documented approximation; the pattern signal is
    /// relative). No-op without RR / a usable reference. Additive: does NOT touch IntelligenceEngine.
    /// FER-972 (P-03): day-keys already attempted this session that yielded no summary (no band
    /// worn that day) — permanent gaps must not re-trigger the reference build on every open.
    /// In-memory only; today (back == 0) is never memoized (its data keeps growing).
    private var stressBackfillAttempted: Set<String> = []

    func backfillStressSummaries(days: Int = 60, restingHR: Double, maxHR: Double) async {
        guard let store = await ensureStore() else { return }
        let existing = await stressDaySummaries(days: days)
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())

        // FER-972 (P-03): the 7-day waking reference (~700k RR rows + 7 sleep-span reads) was
        // built BEFORE checking whether any day needed it — every sheet open paid it even with
        // the whole window already summarized. Compute the pending set first and return early.
        var pending: [Int] = []
        for back in 0..<days {
            let dayStart = cal.date(byAdding: .day, value: -back, to: startOfToday)!
            let key = Repository.localDayKey(dayStart)
            if existing[key]?.dayMean != nil { continue }
            if back != 0, stressBackfillAttempted.contains(key) { continue }
            pending.append(back)
        }
        guard !pending.isEmpty else { return }

        var refDays: [[RRInterval]] = [], refExcluded: [[ClosedRange<Int>]] = []
        for back in 1...7 {
            let s = cal.date(byAdding: .day, value: -back, to: startOfToday)!
            let e = cal.date(byAdding: .day, value: 1, to: s)!
            let from = Int(s.timeIntervalSince1970), to = Int(e.timeIntervalSince1970)
            refDays.append(await rrIntervals(from: from, to: to))
            refExcluded.append(await sleepSpans(from: from, to: to))
        }
        guard let reference = StressEngine.wakingReference(daysRR: refDays, excludedPerDay: refExcluded,
                                                           restingHR: restingHR, maxHR: maxHR) else { return }

        var rows: [MetricPoint] = []
        for back in pending {
            let dayStart = cal.date(byAdding: .day, value: -back, to: startOfToday)!
            let key = Repository.localDayKey(dayStart)
            if back != 0 { stressBackfillAttempted.insert(key) }   // P-03: gaps don't retry this session
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            let from = Int(dayStart.timeIntervalSince1970), to = Int(dayEnd.timeIntervalSince1970)
            let rr = await rrIntervals(from: from, to: to)
            guard !rr.isEmpty else { continue }
            let curve = StressEngine.intradayStress(rr, reference: reference, excluded: await sleepSpans(from: from, to: to),
                                                    restingHR: restingHR, maxHR: maxHR)
            let sum = StressEngine.daySummary(curve)
            guard let mean = sum.dayMean else { continue }
            for (part, m) in sum.partMeans { rows.append(MetricPoint(day: key, key: Self.stressPartPrefix + part.rawValue, value: m)) }
            if let pk = sum.peakHour { rows.append(MetricPoint(day: key, key: Self.stressPeakHourKey, value: Double(pk))) }
            rows.append(MetricPoint(day: key, key: Self.stressDayMeanKey, value: mean))
        }
        if !rows.isEmpty { _ = try? await store.upsertMetricSeries(rows, deviceId: computedDeviceId) }
    }

    func availableKeys(source: String) async -> [String] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.metricKeys(deviceId: source)) ?? []
    }

    /// The set of metric keys that have at least one stored point, keyed by source. Each source is
    /// one index-only `DISTINCT key` query — the cheap way to answer "does this metric have any data?"
    /// for the whole catalog without fetching each metric's full series just to test `.isEmpty`
    /// (FER-27). Used by Explore to flag empty rows and to skip empty metrics before correlating.
    func availableKeySets(sources: [String]) async -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for src in Set(sources) {
            out[src] = Set(await availableKeys(source: src))
        }
        return out
    }

    /// Native journal answers live under this dedicated source id. The journal table has no
    /// `source` column (PK is (deviceId, day, question)), so writing native answers under the
    /// imported `deviceId` would let a CSV re-import silently overwrite them — and clears could
    /// then delete imported rows. A separate device id keeps the two streams independent.
    static let journalDeviceId = "noop-journal"

    /// Logged behaviours (imported WHOOP journal ∪ native noop-journal) for correlation insights.
    func journalEntries(days: Int = 4000) async -> [JournalEntry] {
        guard let store = await ensureStore() else { return [] }
        let (from, to) = Self.dayWindow(days: days)
        let imported = (try? await store.journalEntries(deviceId: deviceId, from: from, to: to)) ?? []
        let native = (try? await store.journalEntries(deviceId: Self.journalDeviceId,
                                                      from: from, to: to)) ?? []
        return Self.mergeJournal(imported: imported, native: native)
    }

    /// Imported journal rows only (used by the logging card to adopt the export's exact question
    /// strings into the catalog, so logged and imported days group under one behaviour).
    func importedJournalEntries(days: Int = 4000) async -> [JournalEntry] {
        guard let store = await ensureStore() else { return [] }
        let (from, to) = Self.dayWindow(days: days)
        return (try? await store.journalEntries(deviceId: deviceId, from: from, to: to)) ?? []
    }

    /// One day's native answers (question → answeredYes) for the logging card's chip state. A
    /// targeted read — the merged list carries no deviceId, so it can't distinguish native rows.
    func nativeJournalAnswers(day: String) async -> [String: Bool] {
        guard let store = await ensureStore() else { return [:] }
        let rows = (try? await store.journalEntries(deviceId: Self.journalDeviceId,
                                                    from: day, to: day)) ?? []
        return Dictionary(rows.map { ($0.question, $0.answeredYes) },
                          uniquingKeysWith: { _, last in last })
    }

    /// Union; the NATIVE row wins per (day, question) — the in-app answer is the user's most recent
    /// explicit action and stays editable, unlike the immutable imported history.
    static func mergeJournal(imported: [JournalEntry], native: [JournalEntry]) -> [JournalEntry] {
        var byKey: [String: JournalEntry] = [:]
        for e in imported { byKey[e.day + "\u{1F}" + e.question] = e }
        for e in native { byKey[e.day + "\u{1F}" + e.question] = e }
        return byKey.values.sorted { ($0.day, $0.question) < ($1.day, $1.question) }
    }

    /// Write one native answer (day per the importer's wake-day convention).
    func saveJournalAnswer(day: String, question: String, answeredYes: Bool, notes: String? = nil) async {
        guard let store = await ensureStore() else { return }
        _ = try? await store.upsertJournal(
            [JournalEntry(day: day, question: question, answeredYes: answeredYes, notes: notes)],
            deviceId: Self.journalDeviceId)
    }

    /// Clear one native answer (never touches imported rows — scoped to the dedicated source id).
    func clearJournalAnswer(day: String, question: String) async {
        guard let store = await ensureStore() else { return }
        _ = try? await store.deleteJournal(deviceId: Self.journalDeviceId, day: day, question: question)
    }

    // MARK: - N-of-1 experiments (FER-307)
    //
    // Experiments are native on-device records, partitioned under the same `journalDeviceId` source as
    // the journal they draw adherence from. The verdict reuses StrandAnalytics' `ExperimentVerdict`
    // (which reuses `BehaviorInsights`) over `days` (the same daily metrics the Bucle's levers come
    // from) and the native journal; no math lives here.

    /// The experiment currently in flight (`running`), or nil. MVP is one at a time.
    func activeExperiment() async -> ExperimentRow? {
        guard let store = await ensureStore() else { return nil }
        return (try? await store.activeExperiment(deviceId: Self.journalDeviceId)) ?? nil
    }

    /// Every experiment, newest first (for the verdict card + proven-lever derivation).
    func allExperiments() async -> [ExperimentRow] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.experiments(deviceId: Self.journalDeviceId)) ?? []
    }

    /// The levers an experiment has confirmed (`completed` + `sustained`) — fed to
    /// `InsightEngine.promoteProven` so "Lo que funciona en ti" shows them as «probado».
    func provenLevers() async -> Set<Lever> {
        let all = await allExperiments()
        var out = Set<Lever>()
        for e in all where e.status == .completed && e.result == Verdict.sustained.rawValue {
            out.insert(Lever(behavior: e.behavior, outcome: e.outcome))
        }
        return out
    }

    /// «Empezar de cero» (Patrones): wipe everything the user CONTRIBUTED — the native in-app journal
    /// and every experiment (with its verdicts, so the derived proven levers clear too). It never touches
    /// the imported WHOOP journal (a different source id) nor the biometric history the detected findings
    /// are recomputed from — those aren't stored records, so they regenerate on their own. Irreversible.
    func resetContributedPatrones() async {
        guard let store = await ensureStore() else { return }
        _ = try? await store.deleteAllJournal(deviceId: Self.journalDeviceId)
        _ = try? await store.deleteAllExperiments(deviceId: Self.journalDeviceId)
    }

    /// Start a 7-day experiment on a candidate lever. No-op (returns nil) if one already runs.
    @discardableResult
    func startExperiment(behavior: String, outcome: String, expectedSign: Int,
                         windowDays: Int = 7) async -> ExperimentRow? {
        guard let store = await ensureStore() else { return nil }
        if (try? await store.activeExperiment(deviceId: Self.journalDeviceId)) != nil { return nil }   // one at a time
        let now = Int(Date().timeIntervalSince1970)
        let row = ExperimentRow(id: UUID().uuidString, behavior: behavior, outcome: outcome,
                                expectedSign: expectedSign, startDay: Self.localDayKey(Date()),
                                windowDays: windowDays, status: .running, createdAt: now)
        _ = try? await store.upsertExperiment(row, deviceId: Self.journalDeviceId)
        return row
    }

    /// The distinct days in [from, to] the behavior was adhered to — the SET behind the streak/«arco»
    /// (FER-462). Diet (FER-385) counts days with adherence ≥ threshold from the `diet-adherence` series;
    /// every other behavior counts «yes» days from the native journal.
    func adherentDays(behavior: String, from: String, to: String) async -> Set<String> {
        if behavior == JournalCatalogStore.dietBehaviorKey {
            let byDay = await dietAdherenceByDay(from: from, to: to)
            return DietAdherence.adherentDays(percentByDay: byDay)
        }
        guard let store = await ensureStore() else { return [] }
        let entries = (try? await store.journalEntries(deviceId: Self.journalDeviceId,
                                                       from: from, to: to)) ?? []
        return Set(entries.filter { $0.question == behavior && $0.answeredYes }.map(\.day))
    }

    /// Count of distinct days in [from, to] the behavior was adhered to — the adherence a running
    /// experiment shows ("cumpliste 3 de 4 días").
    func nativeAdherence(behavior: String, from: String, to: String) async -> Int {
        await adherentDays(behavior: behavior, from: from, to: to).count
    }

    // MARK: - Diet plan (FER-371)
    //
    // The prescribed diet plan is native on-device user data, partitioned under the same
    // `journalDeviceId` source as the journal/experiments it will correlate with. MVP is one active
    // plan (the most recently saved); replacing it just saves a newer one.

    /// The active diet plan (most recent), or nil when none has been captured.
    func activeDietPlan() async -> DietPlanRow? {
        guard let store = await ensureStore() else { return nil }
        return (try? await store.activeDietPlan(deviceId: Self.journalDeviceId)) ?? nil
    }

    /// Persist a captured plan and make it the active one.
    func saveDietPlan(_ row: DietPlanRow) async {
        guard let store = await ensureStore() else { return }
        _ = try? await store.upsertDietPlan(row, deviceId: Self.journalDeviceId)
    }

    /// The metric-series key under which each day's diet-adherence % is stored — a standard metric
    /// point a future Coach/trends reader can pick up (today only the sparkline reads it back) (FER-372).
    static let dietAdherenceKey = "diet-adherence"

    /// A day's per-meal adherence marks (only meals the user has marked appear).
    func dietAdherence(day: String) async -> [DietAdherenceRow] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.dietAdherence(deviceId: Self.journalDeviceId, day: day)) ?? []
    }

    /// Record one meal's status, recompute the day's adherence %, persist it to `metricSeries`
    /// (key `diet-adherence`), and return the new % (nil if the plan has no meals). The metric point is
    /// written whenever at least one meal is marked — which it always is right after this upsert.
    @discardableResult
    func saveDietAdherence(day: String, mealId: String, status: DietMealStatus,
                           plannedMeals: Int, optionIndex: Int? = nil) async -> Int? {
        guard let store = await ensureStore() else { return nil }
        _ = try? await store.upsertDietAdherence(
            DietAdherenceRow(day: day, mealId: mealId, status: status, optionIndex: optionIndex),
            deviceId: Self.journalDeviceId)
        let rows = (try? await store.dietAdherence(deviceId: Self.journalDeviceId, day: day)) ?? []
        guard let pct = DietAdherence.dayPercent(statuses: rows.map(\.status), plannedMeals: plannedMeals) else { return nil }
        _ = try? await store.upsertMetricSeries(
            [MetricPoint(day: day, key: Self.dietAdherenceKey, value: Double(pct))], deviceId: Self.journalDeviceId)
        return pct
    }

    /// The recent diet-adherence trend (one value per logged day in [from, to], oldest first) — the
    /// sparkline behind today's apego.
    func dietAdherenceSeries(from: String, to: String) async -> [Double] {
        guard let store = await ensureStore() else { return [] }
        let pts = (try? await store.metricSeries(deviceId: Self.journalDeviceId,
                                                 key: Self.dietAdherenceKey, from: from, to: to)) ?? []
        return pts.map(\.value)
    }

    /// Day → adherence % for every logged day in [from, to] (FER-385). The Coach derives both the
    /// «Seguí mi dieta» day set (`DietAdherence.adherentDays`, ≥ threshold) and the eligible universe
    /// (all keys — the days the behavior is even measured on) from this; days with no record are absent,
    /// so they stay out of both the contrast and the experiment.
    func dietAdherenceByDay(from: String, to: String) async -> [String: Double] {
        guard let store = await ensureStore() else { return [:] }
        let pts = (try? await store.metricSeries(deviceId: Self.journalDeviceId,
                                                 key: Self.dietAdherenceKey, from: from, to: to)) ?? []
        return Dictionary(pts.map { ($0.day, $0.value) }, uniquingKeysWith: { _, latest in latest })
    }

    /// End a running experiment early, with no verdict.
    func cancelExperiment(_ row: ExperimentRow) async {
        guard let store = await ensureStore() else { return }
        let canceled = Self.experimentRow(row, status: .canceled,
                                          decidedAt: Int(Date().timeIntervalSince1970))
        _ = try? await store.upsertExperiment(canceled, deviceId: Self.journalDeviceId)
    }

    /// If a running experiment's window has elapsed (today ≥ startDay + windowDays), compute its
    /// verdict and persist it (`completed`). Idempotent: a `running` experiment whose window isn't up
    /// yet, or no experiment at all, is left untouched. Call before reading the experiment for display.
    func closeDueExperiment(today: String) async {
        // The verdict's "without" side reads the FULL history (`days` below) and the completed row is
        // persisted — never close over the first-paint window (~90 days) or the verdict could differ.
        // Idempotent: it simply closes on the next visit/refresh once the full pass has published.
        guard dashboard.fullyLoaded else { return }
        guard let store = await ensureStore(),
              let exp = (try? await store.activeExperiment(deviceId: Self.journalDeviceId)) ?? nil,
              let endKey = Self.experimentEndDay(exp) else { return }
        guard today >= endKey else { return }   // window still open

        let series = InsightEngine.outcomeSeries(days, metric: exp.outcome)
        // "With" = the window days the lever was adhered to; "without" = the rest (mostly baseline). The
        // experiment deliberately does NOT restrict to registered days the way the lever does — its short
        // window needs the full baseline on the "without" side, and an adherent diet day is, by
        // definition, a registered one (FER-385).
        var adherent = Set<String>()
        if exp.behavior == JournalCatalogStore.dietBehaviorKey {
            let byDay = await dietAdherenceByDay(from: exp.startDay, to: endKey)
            adherent = DietAdherence.adherentDays(percentByDay: byDay).filter { $0 < endKey }
        } else {
            let entries = (try? await store.journalEntries(deviceId: Self.journalDeviceId,
                                                           from: exp.startDay, to: endKey)) ?? []
            for e in entries where e.question == exp.behavior && e.answeredYes && e.day < endKey {
                adherent.insert(e.day)
            }
        }
        let result = ExperimentVerdict.evaluate(behavior: exp.behavior, outcome: exp.outcome,
                                                expectedSign: exp.expectedSign,
                                                adherentDays: adherent, outcomeByDay: series)
        let e = result.effect
        let completed = ExperimentRow(id: exp.id, behavior: exp.behavior, outcome: exp.outcome,
                                      expectedSign: exp.expectedSign, startDay: exp.startDay,
                                      windowDays: exp.windowDays, status: .completed,
                                      result: result.verdict.rawValue, effectDelta: e?.delta,
                                      effectSize: e?.cohensD, pValue: e?.pApprox, nWith: e?.nWith,
                                      nWithout: e?.nWithout, createdAt: exp.createdAt,
                                      decidedAt: Int(Date().timeIntervalSince1970))
        _ = try? await store.upsertExperiment(completed, deviceId: Self.journalDeviceId)
    }

    /// The day key on which an experiment's window closes (startDay + windowDays, exclusive).
    static func experimentEndDay(_ row: ExperimentRow, calendar: Calendar = .current) -> String? {
        guard let start = dayKeyFormatter.date(from: row.startDay),
              let end = calendar.date(byAdding: .day, value: row.windowDays, to: start) else { return nil }
        return localDayKey(end)
    }

    /// Copy an experiment row with a new status / decidedAt, preserving its result columns.
    private static func experimentRow(_ r: ExperimentRow, status: ExperimentStatus,
                                      decidedAt: Int?) -> ExperimentRow {
        ExperimentRow(id: r.id, behavior: r.behavior, outcome: r.outcome, expectedSign: r.expectedSign,
                      startDay: r.startDay, windowDays: r.windowDays, status: status, result: r.result,
                      effectDelta: r.effectDelta, effectSize: r.effectSize, pValue: r.pValue,
                      nWith: r.nWith, nWithout: r.nWithout, createdAt: r.createdAt, decidedAt: decidedAt)
    }

    /// All workouts (Whoop + Apple Health + on-device detected bouts), newest first.
    ///
    /// Detected bouts are surfaced with an honest "Detected" badge so the user can see — and
    /// dismiss or re-label — a duplicate the auto-detector created (#107). Dismissed detected spans
    /// are filtered HERE so every consumer (Workouts screen, Today, Coach context) agrees: the engine
    /// re-derives the detected rows each run, so a plain delete would resurrect them; the dismissed
    /// span list is the durable "not a workout" record.
    /// `respectingMode`: dashboard callers (Today/Cuerpo/Workouts/Coach) leave it `true` so the list
    /// honors the data-source mode; the diagnostic screens (Datos y fuentes / Apple Health coverage) pass
    /// `false` to show everything STORED regardless of mode (FER-485).
    func workoutRows(days: Int = 4000, respectingMode: Bool = true) async -> [WorkoutRow] {
        guard let store = await ensureStore() else { return [] }
        let now = Int(Date().timeIntervalSince1970)
        let lo = now - days * 86_400, hi = now + 86_400
        let useWhoop = !respectingMode || dataSourceMode.usesWhoop
        let useApple = !respectingMode || dataSourceMode.usesAppleHealth
        var rows: [WorkoutRow] = []
        if useWhoop {
            rows += (try? await store.workouts(deviceId: deviceId, from: lo, to: hi, limit: 5000)) ?? []
            rows += (try? await store.workouts(deviceId: computedDeviceId, from: lo, to: hi, limit: 5000)) ?? []
        }
        if useApple {
            rows += (try? await store.workouts(deviceId: "apple-health", from: lo, to: hi, limit: 5000)) ?? []
        }
        let spans = WorkoutSource.parseDismissedSpans(dismissedDetectedSpans)
        return rows.filter { !WorkoutSource.isDismissed($0, spans: spans) }
            .sorted { $0.startTs > $1.startTs }
    }

    /// "How you wake the morning after each sport" — per sport, how far below your rest-day Charge
    /// your next-morning Charge tends to sit, over your own history (FER-139). A descriptive
    /// ASSOCIATION, never a causal cost; the engine and its narrative are framed accordingly.
    ///
    /// Takes the already-loaded workout `rows` (the caller has them in hand — Cuerpo loads them once
    /// per refresh — so this never re-queries the store), builds the two engine inputs and runs
    /// `ActivityCostEngine`:
    ///  - Sessions: WHOOP + Apple Health + manual workouts. Auto-DETECTED bouts are excluded — they
    ///    carry no real sport, so they'd pool into one meaningless "Activity" bucket (FER-139 scope).
    ///  - Day-keying: each session's start maps to a day-key in the device's LOCAL zone — the same
    ///    calendar `DailyMetric.day` uses — so the engine's UTC D→D+1 string arithmetic stays aligned.
    ///  - Recovery: `days` (strap-derived on-device scores), NOT `displayDays`, so the rest-day
    ///    baseline never mixes in Apple-Health back-fill (house rule, matches the recovery baseline).
    ///    `days` is band-measured only — the FER-153 Apple estimate lives on `repo.today`, never in `days`.
    func activityCosts(from rows: [WorkoutRow]) -> [ActivityCost] {
        let sessions = rows
            .filter { WorkoutSource.classify($0.source) != .detected }
            .map { ActivityCostInputs.Session(startTs: $0.startTs,
                                              sport: WorkoutSource.displaySport($0.sport)) }
        let activityDaysBySport = ActivityCostInputs.activityDaysBySport(sessions, timeZone: .current)
        var recoveryByDay: [String: Double] = [:]
        for d in days { if let r = d.recovery { recoveryByDay[d.day] = r } }
        return ActivityCostEngine.evaluate(activityDaysBySport: activityDaysBySport,
                                           recoveryByDay: recoveryByDay)
    }

    // MARK: - Workout editing (manual add/edit · relabel · dismiss · delete)
    //
    // Manual workouts live under the strap source (deviceId == `deviceId`, source "manual") — the same
    // place v1.67's live-tracked sessions already land (AppModel.endWorkout). Detected bouts live under
    // the computed `computedDeviceId` with sport "detected" and are wiped + re-derived each engine run,
    // so the only durable way to keep one hidden after a re-detect is the dismissed-span list below.

    /// The persisted dismissed detected spans ("startTs:endTs"). Read straight off UserDefaults so the
    /// read path and the write path share one source of truth (the engine never sees this — it always
    /// re-derives; only the read filter and these mutators consult it).
    private var dismissedDetectedSpans: [String] {
        get { UserDefaults.standard.stringArray(forKey: WorkoutSource.dismissedDefaultsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: WorkoutSource.dismissedDefaultsKey) }
    }

    /// Persist a retroactive / edited manual workout under the strap source. `replacing` is the row the
    /// edit started from:
    ///  - editing a DETECTED bout ("Edit details…") replaces it with this manual row — the detected
    ///    original is dismissed durably so the re-detector doesn't bring it back (else both would show);
    ///  - editing a MANUAL row whose natural key (startTs/sport) changed deletes the stale strap row
    ///    first (the (deviceId, startTs, sport) PK upsert would otherwise orphan it);
    ///  - an IMPORTED row is never passed here as `replacing` (duplicating one is a pure add), so its
    ///    history is never touched.
    func saveManualWorkout(_ row: WorkoutRow, replacing old: WorkoutRow? = nil) async {
        guard let store = await ensureStore() else { return }
        if let old, WorkoutSource.classify(old.source) == .detected {
            await dismissDetected(old)
        } else if let old, old.startTs != row.startTs || old.sport != row.sport {
            _ = try? await store.deleteWorkouts(deviceId: deviceId, sport: old.sport,
                                                from: old.startTs, to: old.startTs)
        }
        _ = try? await store.upsertWorkouts([row], deviceId: deviceId)
    }

    /// Re-label a detected bout: copy it to a manual strap row with the chosen sport, then delete the
    /// detected original. This survives analyzeRecent — the engine wipes + re-derives only sport
    /// "detected" rows under the computed id AND skips any re-derived bout overlapping a real strap
    /// workout, which this copy now is — so the same session is never re-created as a duplicate. (#107)
    func relabelDetected(_ row: WorkoutRow, sport: String) async {
        guard let store = await ensureStore() else { return }
        let trimmed = sport.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let manual = WorkoutRow(startTs: row.startTs, endTs: row.endTs, sport: trimmed, source: "manual",
                                durationS: row.durationS, energyKcal: row.energyKcal,
                                avgHr: row.avgHr, maxHr: row.maxHr, strain: row.strain,
                                distanceM: row.distanceM, zonesJSON: row.zonesJSON, notes: row.notes)
        _ = try? await store.upsertWorkouts([manual], deviceId: deviceId)
        _ = try? await store.deleteWorkouts(deviceId: computedDeviceId, sport: "detected",
                                            from: row.startTs, to: row.startTs)
    }

    /// Dismiss a DETECTED bout the user says isn't a workout. Records its span in the durable dismissed
    /// list (so a re-detect that recreates the same span stays hidden) AND deletes the current row so it
    /// disappears immediately. Idempotent: a span already present isn't duplicated. (#107)
    func dismissDetected(_ row: WorkoutRow) async {
        guard WorkoutSource.classify(row.source) == .detected else { return }
        let token = WorkoutSource.dismissedToken(for: row)
        var spans = dismissedDetectedSpans
        if !spans.contains(token) { spans.append(token); dismissedDetectedSpans = spans }
        guard let store = await ensureStore() else { return }
        _ = try? await store.deleteWorkouts(deviceId: computedDeviceId, sport: row.sport,
                                            from: row.startTs, to: row.startTs)
    }

    /// Delete ONE workout by natural key. The read model has no deviceId, so reconstruct it from the
    /// source: detected rows live under the computed id (and also get their span dismissed so they don't
    /// come back); everything else the screen can delete (manual) lives under the strap id.
    func deleteWorkout(_ row: WorkoutRow) async {
        if WorkoutSource.classify(row.source) == .detected { await dismissDetected(row); return }
        guard let store = await ensureStore() else { return }
        _ = try? await store.deleteWorkouts(deviceId: deviceId, sport: row.sport,
                                            from: row.startTs, to: row.startTs)
    }

    /// Apple Health daily aggregates (steps/energy/vo2/hr).
    /// `respectingMode`: dashboard callers (Today/Cuerpo) leave it `true` so Apple is hidden in `whoopOnly`;
    /// the Apple Health diagnostic screen passes `false` to show what's STORED regardless of mode (FER-485).
    func appleDailyRows(days: Int = 4000, respectingMode: Bool = true) async -> [AppleDaily] {
        if respectingMode && !dataSourceMode.usesAppleHealth { return [] }
        guard let store = await ensureStore() else { return [] }
        let (from, to) = Self.dayWindow(days: days)
        return (try? await store.appleDaily(deviceId: "apple-health", from: from, to: to)) ?? []
    }

    /// Apple-Health `dailyMetric` rows (sleep / HRV / resting HR / SpO₂ / resp rate) read straight from
    /// the apple-health source — NOT the merged dashboard. `mergeDaily` replaces a day's Apple row
    /// wholesale when the strap also has that day, so a strap day with nil fields (e.g. a WHOOP 4.0 that
    /// didn't decode HRV/sleep) hides the value Apple Health does have; Today's Key Metrics falls back
    /// to these to fill that gap without disturbing the dashboard merge or the recovery baseline. (FER-98)
    func appleDailyMetricRows(days: Int = 4000) async -> [DailyMetric] {
        // FER-484: dashboard-only read (TodayView/CuerpoView Key-Metrics fall-back) — no diagnostic caller,
        // so it honors the mode directly: whoopOnly surfaces no Apple HRV/sleep into the dashboard.
        guard dataSourceMode.usesAppleHealth else { return [] }
        guard let store = await ensureStore() else { return [] }
        let (from, to) = Self.dayWindow(days: days)
        return (try? await store.dailyMetrics(deviceId: "apple-health", from: from, to: to)) ?? []
    }

    /// `yyyy-MM-dd` (local zone, en_US_POSIX) — same contract as `localDayKey`; both share the one
    /// `dayKeyFormatter` (was two byte-identical formatters, FER-328). Hot read path, so it's a single
    /// cached formatter; read-only use is thread-safe.
    static func dayString(_ d: Date) -> String { dayKeyFormatter.string(from: d) }

    /// The (from, to) `yyyy-MM-dd` window spanning the trailing `days` up to tomorrow — the shared
    /// date window every dashboard/series read derives the same way (FER-328). `now` is injectable so
    /// a caller that already sampled the clock (refresh) reuses it instead of reading `Date()` twice.
    private static func dayWindow(days: Int, now: Date = Date()) -> (from: String, to: String) {
        (dayString(now.addingTimeInterval(-Double(days) * 86_400)),
         dayString(now.addingTimeInterval(86_400)))
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

    /// A copy with `recovery` substituted (the struct has no `copy()`). Used by `repo.today` to surface the
    /// Apple-Health estimated recovery on today's single row when the band didn't cover the night (FER-153)
    /// — every other field is carried verbatim, so the row's HRV/sleep stay Apple's own.
    func withRecovery(_ r: Double?) -> DailyMetric {
        with(recovery: .set(r))
    }
}
