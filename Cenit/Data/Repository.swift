import Foundation
import Combine
import WhoopStore
import WhoopProtocol
import StrandAnalytics

/// Per-day sleep figures the WHOOP export carried verbatim (metricSeries rows written by
/// WhoopImporter under the imported deviceId). The Detalle de Sueño prefers these over its on-device
/// APPROXIMATE recomputations.
struct ImportedSleepFigures: Equatable {
    var performancePct: Double?   // "sleep_performance", 0–100
    var consistencyPct: Double?   // "sleep_consistency", 0–100
    var needMin: Double?          // "sleep_need_min", minutes
    var debtMin: Double?          // "sleep_debt_min", minutes
}

/// Read model over the on-device WhoopStore. Opens its own handle (WAL + busy-timeout makes the
/// two-handle BLEManager+Repository pattern safe) and publishes the dashboard caches the screens bind to.
@MainActor
final class Repository: ObservableObject {
    let deviceId: String
    /// Source id for on-device computed scores (recovery/strain/sleep derived from the raw strap
    /// streams by IntelligenceEngine). Merged UNDER the imported `deviceId` rows at read time, so a
    /// real WHOOP import always wins and the strap-only user still gets a populated dashboard.
    private var computedDeviceId: String { deviceId + "-noop" }
    private var store: WhoopStore?
    /// In-flight store creation, memoized so concurrent first-callers (the launch refresh and
    /// TodayView's parallel queries) share ONE open+migrate instead of racing `ensureStore`'s
    /// await window and opening the DB several times. @MainActor makes the set-before-await safe.
    private var storeInit: Task<WhoopStore?, Never>?

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
        /// these so a partial-connection day shows Apple's HRV instead of a gap; `days` stays strap-only.
        var displayDays: [DailyMetric] = []
        var sleeps: [CachedSleepSession] = []
        var importedSleep: [String: ImportedSleepFigures] = [:]
        /// Days whose surfaced daily row came from Apple Health (no strap coverage), so Trends/Sleep
        /// can badge the source without `DailyMetric` carrying a source column. (FER-62)
        var appleHealthDays: Set<String> = []
        var loaded = false
        var seq = 0
    }
    @Published private(set) var dashboard = DashboardData()

    /// Daily metrics (recovery/strain/sleep/HRV/RHR…), oldest→newest. Strap-only HRV/RHR — the
    /// recovery baseline and `ownNights` read this, so Apple Health never leaks into the calibration.
    var days: [DailyMetric] { dashboard.days }
    /// Display-only daily rows: `days`, but strap-covered days with nil measured fields back-fill from
    /// Apple Health (FER-149). The dashboard sparklines/trends read these; analytics read `days`.
    var displayDays: [DailyMetric] { dashboard.displayDays }
    /// Cached sleep sessions, oldest→newest.
    var sleeps: [CachedSleepSession] { dashboard.sleeps }
    /// Imported (export-verbatim) sleep figures by day. Empty until a WHOOP import lands.
    var importedSleep: [String: ImportedSleepFigures] { dashboard.importedSleep }
    var loaded: Bool { dashboard.loaded }
    /// Monotonic counter bumped on every successful `refresh()`. Intraday-updating views key their
    /// data load on this so they reload when fresh strap data lands — `today?.day` alone is a stable
    /// date string within a day and would freeze e.g. the Today HR trend until the date rolls over.
    var refreshSeq: Int { dashboard.seq }
    /// Days surfaced from Apple Health (strap-uncovered) — Trends/Sleep badge these as "Apple Health". (FER-62)
    var appleHealthDays: Set<String> { dashboard.appleHealthDays }

    init(deviceId: String) { self.deviceId = deviceId }

    /// Today's row, by the device's ACTUAL local calendar date — NOT just the newest stored row, which
    /// after a historical import was months-old data shown as today's hero (issue #23). nil if no row
    /// for today yet (the dashboard then shows its empty/pending state).
    var today: DailyMetric? {
        let key = Repository.localDayKey(Date())
        return days.last(where: { $0.day == key })
    }
    /// The trailing 7 CALENDAR days ending today (for the week strip), oldest→newest — not the last 7
    /// stored rows, which on a stale import were old data. ISO yyyy-MM-dd compares chronologically.
    var week: [DailyMetric] {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        return days.filter { $0.day >= cutoff }
    }

    /// `yyyy-MM-dd` in the device's local zone, matching how `DailyMetric.day` is stored.
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    static func localDayKey(_ date: Date) -> String { dayKeyFormatter.string(from: date) }

    /// Parse a stored `yyyy-MM-dd` day key back to a Date in UTC (en_US_POSIX). Charts parse keys in
    /// UTC for DST-stable positions — distinct from `localDayKey` (which WRITES keys in local zone).
    /// The single shared inverse of the day-key contract (FER-325).
    nonisolated private static let dayKeyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    nonisolated static func parseDayKey(_ s: String) -> Date? { dayKeyParser.date(from: s) }

    private func ensureStore() async -> WhoopStore? {
        if let store { return store }
        if let storeInit { return await storeInit.value }   // a creation is already in flight — join it
        let task = Task { () -> WhoopStore? in
            guard let path = try? StorePaths.defaultDatabasePath() else { return nil }
            let s = try? await WhoopStore(path: path)
            if let s { try? await s.upsertDevice(id: deviceId, mac: nil, name: "WHOOP") }
            return s
        }
        storeInit = task              // published synchronously (still on @MainActor) before the await below
        let s = await task.value
        store = s
        storeInit = nil
        return s
    }

    /// Expose the shared store handle (used by the importer to persist mapped rows).
    func storeHandle() async -> WhoopStore? { await ensureStore() }

    /// One-shot snapshot for the Today "data receipt": stored raw-sample counts + the latest stored
    /// HR sample time (proof the strap's streams are landing and current). nil if no store yet.
    func dataReceipt() async -> (counts: (hr: Int, rr: Int, spo2: Int, skinTemp: Int, resp: Int, gravity: Int), latestHRTs: Int?)? {
        guard let store = await ensureStore() else { return nil }
        guard let counts = try? await store.sampleCounts() else { return nil }
        let latest = (try? await store.latestHRSampleTs(deviceId: deviceId)) ?? nil
        return (counts, latest)
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

    /// Reload the dashboard caches over the last `nDays`, merging imported history with the
    /// on-device computed scores so a strap-only user still gets a populated dashboard.
    func refresh(days nDays: Int = 4000) async {
        guard let store = await ensureStore() else { return }
        let now = Date()
        let (fromDay, toDay) = Self.dayWindow(days: nDays, now: now)
        let nowTs = Int(now.timeIntervalSince1970)
        let lo = nowTs - nDays * 86_400, hi = nowTs + 86_400

        let imported = (try? await store.dailyMetrics(deviceId: deviceId, from: fromDay, to: toDay)) ?? []
        let computed = (try? await store.dailyMetrics(deviceId: computedDeviceId, from: fromDay, to: toDay)) ?? []
        // FER-62: Apple Health daily rows — the lowest-precedence fallback layer for the dashboard,
        // so a strap-uncovered user still sees HRV / resting HR / sleep-stage trends.
        let apple = (try? await store.dailyMetrics(deviceId: "apple-health", from: fromDay, to: toDay)) ?? []
        let impSleep = (try? await store.sleepSessions(deviceId: deviceId, from: lo, to: hi, limit: 4000)) ?? []
        let compSleep = (try? await store.sleepSessions(deviceId: computedDeviceId, from: lo, to: hi, limit: 4000)) ?? []

        // Export-verbatim sleep figures (long-format metricSeries rows from WhoopImporter).
        // The Detalle de Sueño prefers these per day over its APPROXIMATE recomputations.
        let perf = (try? await store.metricSeries(deviceId: deviceId, key: "sleep_performance", from: fromDay, to: toDay)) ?? []
        let cons = (try? await store.metricSeries(deviceId: deviceId, key: "sleep_consistency", from: fromDay, to: toDay)) ?? []
        let need = (try? await store.metricSeries(deviceId: deviceId, key: "sleep_need_min", from: fromDay, to: toDay)) ?? []
        let debt = (try? await store.metricSeries(deviceId: deviceId, key: "sleep_debt_min", from: fromDay, to: toDay)) ?? []
        var fig: [String: ImportedSleepFigures] = [:]
        for p in perf { fig[p.day, default: ImportedSleepFigures()].performancePct = p.value }
        for p in cons { fig[p.day, default: ImportedSleepFigures()].consistencyPct = p.value }
        for p in need { fig[p.day, default: ImportedSleepFigures()].needMin = p.value }
        for p in debt { fig[p.day, default: ImportedSleepFigures()].debtMin = p.value }

        // One assignment → one objectWillChange for the whole refresh (was four).
        let merged = Self.mergeDaily(imported: imported, computed: computed, apple: apple)
        self.dashboard = DashboardData(
            days: merged.days,
            displayDays: merged.displayDays,
            sleeps: Self.mergeSleep(imported: impSleep, computed: compSleep),
            importedSleep: fig,
            appleHealthDays: merged.appleDays,
            loaded: true,
            seq: dashboard.seq + 1
        )
    }

    /// Seed the dashboard with pre-built rows in a single publish — for SwiftUI previews, which have
    /// no store to `refresh()` from. `refresh()` is the production path.
    func setDashboard(days: [DailyMetric] = [],
                      sleeps: [CachedSleepSession] = [],
                      importedSleep: [String: ImportedSleepFigures] = [:],
                      appleHealthDays: Set<String> = [],
                      loaded: Bool = true) {
        dashboard = DashboardData(days: days, displayDays: days, sleeps: sleeps, importedSleep: importedSleep,
                                  appleHealthDays: appleHealthDays, loaded: loaded, seq: dashboard.seq + 1)
    }

    /// Layered precedence (FER-62): Apple Health rows are the base, on-device computed rows fill the
    /// days they don't cover, and imported strap rows win over everything — so the strap always beats
    /// Apple Health. Also returns the days whose surfaced row stayed Apple Health (strap-uncovered),
    /// for source badging.
    ///
    /// `displayDays` (FER-149) is a display-only twin of `days`: a strap-covered day whose measured
    /// fields are nil (a partial-connection day — IntelligenceEngine wrote a `daily` with HRV/recovery
    /// nil) back-fills those nils from the Apple Health row this merge overwrote, so the HRV
    /// sparkline/trend shows Apple's value instead of a gap. `days` and `appleDays` stay strap-only and
    /// byte-for-byte unchanged: `ownNights` and the recovery baseline read `repo.days`/`appleHealthDays`,
    /// so Apple HRV never leaks into the calibration (it's folded separately and capped in
    /// IntelligenceEngine). The strap value always wins when present — only genuine gaps fill.
    static func mergeDaily(imported: [DailyMetric], computed: [DailyMetric],
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

    /// Same precedence for sleep sessions, keyed by the day the night ends on.
    private static func mergeSleep(imported: [CachedSleepSession], computed: [CachedSleepSession]) -> [CachedSleepSession] {
        func endDay(_ s: CachedSleepSession) -> String {
            dayString(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
        }
        var byDay: [String: CachedSleepSession] = [:]
        for s in computed { byDay[endDay(s)] = s }
        for s in imported { byDay[endDay(s)] = s }
        return byDay.values.sorted { $0.startTs < $1.startTs }
    }

    // MARK: - Detail passthroughs

    func dailyMetrics(fromDay: String, toDay: String) async -> [DailyMetric] {
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

    /// Downsampled HR (mean bpm per `bucketSeconds`) for the strap, for a Today/24h trend chart.
    /// Aggregated in SQL so a full day never loads the raw ~1 Hz rows.
    func hrBuckets(from: Int, to: Int, bucketSeconds: Int = 300) async -> [HRBucket] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.hrBuckets(deviceId: deviceId, from: from, to: to, bucketSeconds: bucketSeconds)) ?? []
    }

    func sleepSessions(from: Int, to: Int, limit: Int = 100) async -> [CachedSleepSession] {
        guard let store = await ensureStore() else { return [] }
        return (try? await store.sleepSessions(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []
    }

    // MARK: - Metric explorer reads (generic substrate)

    /// Daily series for any metric key from a given source ("my-whoop" / "apple-health").
    func series(key: String, source: String, days: Int = 4000) async -> [(day: String, value: Double)] {
        guard let store = await ensureStore() else { return [] }
        let (from, to) = Self.dayWindow(days: days)
        let pts = (try? await store.metricSeries(deviceId: source, key: key, from: from, to: to)) ?? []
        return pts.map { ($0.day, $0.value) }
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

    /// Start a 7-day experiment on a candidate lever. No-op (returns nil) if one already runs.
    @discardableResult
    func startExperiment(behavior: String, outcome: String, expectedSign: Int,
                         windowDays: Int = 7) async -> ExperimentRow? {
        guard let store = await ensureStore() else { return nil }
        if let existing = try? await store.activeExperiment(deviceId: Self.journalDeviceId),
           existing != nil { return nil }   // one at a time
        let now = Int(Date().timeIntervalSince1970)
        let row = ExperimentRow(id: UUID().uuidString, behavior: behavior, outcome: outcome,
                                expectedSign: expectedSign, startDay: Self.localDayKey(Date()),
                                windowDays: windowDays, status: .running, createdAt: now)
        try? await store.upsertExperiment(row, deviceId: Self.journalDeviceId)
        return row
    }

    /// Count of distinct days in [from, to] the native journal logged `behavior` as «yes» — the
    /// adherence a running experiment shows ("cumpliste 3 de 4 días").
    func nativeAdherence(behavior: String, from: String, to: String) async -> Int {
        guard let store = await ensureStore() else { return 0 }
        let entries = (try? await store.journalEntries(deviceId: Self.journalDeviceId,
                                                       from: from, to: to)) ?? []
        return Set(entries.filter { $0.question == behavior && $0.answeredYes }.map(\.day)).count
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
    func saveDietAdherence(day: String, mealId: String, status: DietMealStatus, plannedMeals: Int) async -> Int? {
        guard let store = await ensureStore() else { return nil }
        _ = try? await store.upsertDietAdherence(
            DietAdherenceRow(day: day, mealId: mealId, status: status), deviceId: Self.journalDeviceId)
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

    /// End a running experiment early, with no verdict.
    func cancelExperiment(_ row: ExperimentRow) async {
        guard let store = await ensureStore() else { return }
        let canceled = Self.experimentRow(row, status: .canceled,
                                          decidedAt: Int(Date().timeIntervalSince1970))
        try? await store.upsertExperiment(canceled, deviceId: Self.journalDeviceId)
    }

    /// If a running experiment's window has elapsed (today ≥ startDay + windowDays), compute its
    /// verdict and persist it (`completed`). Idempotent: a `running` experiment whose window isn't up
    /// yet, or no experiment at all, is left untouched. Call before reading the experiment for display.
    func closeDueExperiment(today: String) async {
        guard let store = await ensureStore(),
              let exp = (try? await store.activeExperiment(deviceId: Self.journalDeviceId)) ?? nil,
              let endKey = Self.experimentEndDay(exp) else { return }
        guard today >= endKey else { return }   // window still open

        let series = InsightEngine.outcomeSeries(days, metric: exp.outcome)
        let entries = (try? await store.journalEntries(deviceId: Self.journalDeviceId,
                                                       from: exp.startDay, to: endKey)) ?? []
        var adherent = Set<String>()
        for e in entries where e.question == exp.behavior && e.answeredYes && e.day < endKey {
            adherent.insert(e.day)
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
        try? await store.upsertExperiment(completed, deviceId: Self.journalDeviceId)
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
    func workoutRows(days: Int = 4000) async -> [WorkoutRow] {
        guard let store = await ensureStore() else { return [] }
        let now = Int(Date().timeIntervalSince1970)
        let lo = now - days * 86_400, hi = now + 86_400
        var rows = (try? await store.workouts(deviceId: deviceId, from: lo, to: hi, limit: 5000)) ?? []
        rows += (try? await store.workouts(deviceId: "apple-health", from: lo, to: hi, limit: 5000)) ?? []
        rows += (try? await store.workouts(deviceId: computedDeviceId, from: lo, to: hi, limit: 5000)) ?? []
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
    func appleDailyRows(days: Int = 4000) async -> [AppleDaily] {
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
        DailyMetric(
            day: day,
            totalSleepMin: totalSleepMin ?? other.totalSleepMin,
            efficiency: efficiency ?? other.efficiency,
            deepMin: deepMin ?? other.deepMin,
            remMin: remMin ?? other.remMin,
            lightMin: lightMin ?? other.lightMin,
            disturbances: disturbances ?? other.disturbances,
            restingHr: restingHr ?? other.restingHr,
            avgHrv: avgHrv ?? other.avgHrv,
            recovery: recovery ?? other.recovery,
            strain: strain ?? other.strain,
            exerciseCount: exerciseCount ?? other.exerciseCount,
            spo2Pct: spo2Pct ?? other.spo2Pct,
            skinTempDevC: skinTempDevC ?? other.skinTempDevC,
            respRateBpm: respRateBpm ?? other.respRateBpm,
            steps: steps ?? other.steps,
            activeKcalEst: activeKcalEst ?? other.activeKcalEst)
    }
}
