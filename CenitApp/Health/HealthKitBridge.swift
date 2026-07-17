#if os(iOS)
import Foundation
import CryptoKit
import HealthKit
import StrandAnalytics
import StrandImport
import WhoopProtocol
import WhoopStore

/// Two-way Apple Health bridge for the iOS app.
///
/// iOS has HealthKit (macOS does not), so the iOS target can do far more than parse a static export:
/// it reads the user's own Health data live and maps it onto the **same** `WhoopStore` rows the
/// macOS importer produces (under the `apple-health` source id), and it writes NOOP-computed metrics
/// back into Apple Health. Everything stays on-device and strictly opt-in.
@MainActor
final class HealthKitBridge: ObservableObject {

    enum AuthState: Equatable { case unknown, unavailable, denied, authorized }

    /// Live progress of the running `sync`. `done/total` counts pipeline stages; `stageKey` names the
    /// current one ("hrv", "sleep", "saving", …) so the UI maps it to a localized "Importing HRV…"
    /// label. Nil whenever idle. (FER-70)
    struct SyncProgress: Equatable {
        let stageKey: String
        let done: Int
        let total: Int
    }

    /// Share (write-back) authorization for one metric we write into Health. HealthKit only exposes
    /// *write* status reliably — read permission is private — so this tracks the write-back metrics;
    /// the per-metric *read* result is inferred from `coverage` (whether days actually landed). (FER-70)
    struct WritePermission: Equatable, Identifiable {
        var id: String { key }
        let key: String                   // metric key, matching `coverage.daysByMetric` keys
        let status: HKAuthorizationStatus
    }

    @Published private(set) var auth: AuthState = .unknown
    @Published private(set) var lastSync: Date?
    @Published private(set) var syncing = false
    /// The most recent failure surfaced by `sync` / `writeBack`. Cleared on a successful run. UI binds
    /// here so an Apple Health auth revoke, quota hit, or invalid sample is visible instead of silent.
    @Published private(set) var lastError: String?
    /// Live stage of the running import (nil when idle), so the card shows real progress instead of a
    /// context-free spinner. (FER-70)
    @Published private(set) var syncProgress: SyncProgress?
    /// What actually landed in the store under the apple-health source: days per metric + overall
    /// span. Reloaded after every `sync` and on demand via `refreshStatus`. Powers the coverage
    /// summary and the per-metric status list. (FER-70)
    @Published private(set) var coverage: AppleHealthCoverage?
    /// Per-metric write-back authorization, refreshed alongside `coverage`. (FER-70)
    @Published private(set) var writePermissions: [WritePermission] = []

    private let store = HKHealthStore()
    private let repo: Repository
    /// Source id imported HealthKit data lands under (matches `AppModel.appleDeviceId`).
    private let appleDeviceId: String
    /// NOOP's own strap-derived source id, read back when writing into Health.
    private let noopDeviceId: String

    /// Persists "the user already connected Apple Health" across launches. HealthKit keeps the grant
    /// itself, but never reveals *read* authorization (it's private), so `authorizationStatus` can't
    /// tell us on launch whether we're connected. Without our own flag, `auth` reset to `.unknown`
    /// every launch and the scenePhase auto-sync silently no-op'd (its `guard auth == .authorized`),
    /// leaving Today's Key Metrics empty until a manual reconnect. (FER-94)
    private static let connectedDefaultsKey = "appleHealthConnected"

    /// Mirrors the Settings toggle (`@AppStorage`): write finished strength sessions to Apple Health
    /// as `HKWorkout`s (FER-390). Default off — opt-in, so we never write or prompt without consent.
    static let saveStrengthWorkoutsKey = "health.saveStrengthWorkouts"

    /// Why `sync` was called. `.foreground` is the automatic scenePhase-active trigger that fires on
    /// every launch/return; it opts into the FER-872 delta window + no-op refresh guard below. Every
    /// other caller (manual "Sync now", onboarding, the FER-226 re-bucket that reads the returned key
    /// set) is `.manual` and always does the caller's full window and a dashboard refresh.
    enum SyncTrigger { case manual, foreground }

    /// FER-872: extra days of back-margin a delta foreground sync reaches past `lastSync`, so a night
    /// Apple wrote late (or the overnight backfill) is re-pulled within the session (FER-406/407). The
    /// deep case — a Watch/iCloud dump of several STALE days that a lastSync window would step past
    /// forever — is caught by the first foreground sync of the NEXT session, which is always full.
    private static let deltaBackMarginDays = 3

    /// True once a foreground sync has completed this session. The first foreground sync stays full
    /// (this and `lastAppleWriteSignature` reset each launch); only subsequent ones go delta.
    private var didFullForegroundSyncThisSession = false

    /// Stable signature of the Apple rows written by the last sync THIS session, to skip a dashboard
    /// rebuild when a foreground re-pull produced identical data (FER-872). In-memory (per-session) for
    /// the delta comparison between subsequent foregrounds. A stale value can never cause a FALSE skip —
    /// it's recomputed from the freshly-pulled rows each run.
    private var lastAppleWriteSignature: String?

    /// FER-881: the stable signature persisted from the last session's FIRST-foreground (full 30-day)
    /// sync. The first foreground of a NEW session — which is always full — compares its fresh signature
    /// against this to skip the redundant cold-start rebuild when the Apple data is unchanged since last
    /// session (the launch full-refresh already surfaced it). Only full foreground syncs read/write it,
    /// so the window is always the same 30 days and the comparison is apples-to-apples.
    private static let lastFullSyncSigKey = "appleHealthLastFullSyncSig"
    /// FER-970 (R-05): fingerprint of the last successfully mirrored write-back payload — when the
    /// 14 d of «-noop» rows + sleep sessions are unchanged, the delete+rewrite into HealthKit is
    /// skipped entirely (every foreground re-sync used to re-save identical samples).
    private static let lastWriteBackSigKey = "appleHealthLastWriteBackSig"

    init(repo: Repository, appleDeviceId: String, noopDeviceId: String) {
        self.repo = repo
        self.appleDeviceId = appleDeviceId
        self.noopDeviceId = noopDeviceId
        if !HKHealthStore.isHealthDataAvailable() {
            auth = .unavailable
        } else if UserDefaults.standard.bool(forKey: Self.connectedDefaultsKey) {
            // Restore the prior connection so the launch auto-sync runs without forcing a reconnect.
            auth = .authorized
        }
    }

    // MARK: - Types

    private var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>()
        for id in HealthKitBridge.quantityReadIds { if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) } }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        s.insert(HKObjectType.workoutType())
        // Características del perfil para el auto-fill del onboarding (FER-361): sexo, fecha de
        // nacimiento (→ edad), peso y estatura. Se consumen en `readProfileCharacteristics()`.
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { s.insert(sex) }
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { s.insert(dob) }
        for id in [HKQuantityTypeIdentifier.bodyMass, .height] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) }
        }
        return s
    }

    private var writeTypes: Set<HKSampleType> {
        var s = Set<HKSampleType>()
        for id in HealthKitBridge.quantityWriteIds { if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) } }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        return s
    }

    /// Share types requested ONLY when the user opts into saving strength workouts (FER-390). Kept
    /// out of `writeTypes` on purpose: connecting Apple Health must never surface a workout-write
    /// prompt to someone who didn't ask for it (privacy; same discipline as FER-103).
    private var workoutShareTypes: Set<HKSampleType> {
        var s: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { s.insert(energy) }
        return s
    }

    // Every id here ends up in the HealthKit permission dialog. Only request what `sync` actually
    // aggregates into `DayAgg`; adding read scopes the app never consumes makes the consent prompt
    // noisier and surfaces a privacy ask we don't honour.
    private static let quantityReadIds: [HKQuantityTypeIdentifier] = [
        .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .oxygenSaturation,
        .respiratoryRate, .stepCount, .activeEnergyBurned,
        .basalEnergyBurned, .vo2Max,
        .appleSleepingWristTemperature
    ]
    private static let quantityWriteIds: [HKQuantityTypeIdentifier] = [
        .restingHeartRate, .heartRateVariabilitySDNN, .oxygenSaturation, .respiratoryRate
    ]

    // MARK: - Authorization

    /// Request read + write permission. HealthKit never reveals whether *read* was granted, so we
    /// treat a successful request as `.authorized` and let queries return empty if the user declined.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { auth = .unavailable; return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            auth = .authorized
            UserDefaults.standard.set(true, forKey: Self.connectedDefaultsKey)   // persist so the next launch's auto-sync runs (FER-94)
            await refreshStatus()   // surface granted write scopes + any prior coverage immediately
        } catch {
            auth = .denied
        }
    }

    /// Request share (write) permission for workouts + active energy — asked ONLY when the user turns
    /// on "Guardar entrenamientos en Apple Salud" (FER-390), so a workout-write prompt never reaches
    /// someone who didn't opt in. Read scopes and the main connection state are left untouched.
    func requestWorkoutShareAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: workoutShareTypes, read: [])
    }

    // MARK: - Profile characteristics (FER-361)

    /// Sexo / edad / peso / estatura de Apple Health para prellenar el Perfil del onboarding. Todo
    /// opcional: cada campo viene solo si Health lo tiene (auto-fill parcial, campo por campo).
    struct ProfileCharacteristics: Equatable {
        var sex: String?       // "male" | "female" | "nonbinary"
        var age: Int?
        var weightKg: Double?
        var heightCm: Double?
    }

    /// Lee las características del perfil de Apple Health. On-device; nada sale del dispositivo.
    func readProfileCharacteristics() async -> ProfileCharacteristics {
        guard HKHealthStore.isHealthDataAvailable() else { return ProfileCharacteristics() }
        var out = ProfileCharacteristics()
        if let bs = try? store.biologicalSex().biologicalSex {
            switch bs {
            case .male:   out.sex = "male"
            case .female: out.sex = "female"
            case .other:  out.sex = "nonbinary"
            default:      break
            }
        }
        if let comps = try? store.dateOfBirthComponents(),
           let dob = Calendar.current.date(from: comps),
           let years = Calendar.current.dateComponents([.year], from: dob, to: Date()).year,
           (13...120).contains(years) {
            out.age = years
        }
        out.weightKg = await mostRecentQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
        out.heightCm = await mostRecentQuantity(.height, unit: .meterUnit(with: .centi))
        return out
    }

    /// La muestra más reciente de un tipo de cantidad, en la unidad dada. `nil` si no hay ninguna.
    private func mostRecentQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    /// Reload what the status panel shows *without* running an import: write permissions (cheap,
    /// synchronous) and the coverage already stored. Call from the card's `.task` so opening it shows
    /// "X days imported" and the per-metric list right away. (FER-70)
    func refreshStatus() async {
        refreshPermissions()
        guard let store = await repo.storeHandle() else { return }
        coverage = try? await store.appleHealthCoverage(deviceId: appleDeviceId)
    }

    /// Snapshot write-back authorization per metric. HealthKit reports *write* (share) status
    /// faithfully; read status stays private, so the read side is inferred from `coverage`. (FER-70)
    private func refreshPermissions() {
        let types: [(String, HKObjectType?)] = [
            ("resting_hr", HKObjectType.quantityType(forIdentifier: .restingHeartRate)),
            ("hrv", HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)),
            ("spo2", HKObjectType.quantityType(forIdentifier: .oxygenSaturation)),
            ("resp_rate", HKObjectType.quantityType(forIdentifier: .respiratoryRate)),
            ("sleep", HKObjectType.categoryType(forIdentifier: .sleepAnalysis)),
        ]
        writePermissions = types.compactMap { key, type in
            type.map { WritePermission(key: key, status: store.authorizationStatus(for: $0)) }
        }
    }

    // MARK: - Read → store

    /// Pull the last `days` of Apple Health into the on-device store under the `apple-health` source,
    /// then write NOOP's own computed metrics back into Health. Safe to call repeatedly (idempotent
    /// upserts keyed by day). Returns the set of local `day` keys written this run — the FER-226
    /// re-bucket uses it to prune UTC orphans; empty on an early-out or a failed store write.
    @discardableResult
    func sync(days: Int = 30, trigger: SyncTrigger = .manual) async -> Set<String> {
        guard auth == .authorized, !syncing else { return [] }
        syncing = true
        defer { syncing = false; syncProgress = nil }
        guard let store = await repo.storeHandle() else { return [] }

        let cal = Calendar.current
        let end = Date()
        // FER-872: the scenePhase foreground trigger fires on every launch/return; re-pulling the full
        // 30-day window each time (13 HK stages + upserts + a dashboard rebuild) is wasted work when
        // nothing changed. The FIRST foreground sync of a session stays full — the delta state resets
        // each launch, so a Watch/iCloud backfill of several STALE days (which a lastSync window would
        // step past forever) is caught here — and subsequent foregrounds pull only a short delta window
        // from `lastSync` plus a few days of back-margin, so a late-arriving night / the overnight Apple
        // backfill is never missed (FER-406/407). Manual/onboarding/re-bucket keep the caller's window.
        let effectiveDays: Int = {
            guard trigger == .foreground, didFullForegroundSyncThisSession, let last = lastSync else { return days }
            let sinceLast = end.timeIntervalSince(last)
            guard sinceLast > 0, sinceLast < Double(days) * 86_400 else { return days }
            return min(days, Int(sinceLast / 86_400) + Self.deltaBackMarginDays)
        }()
        guard let start = cal.date(byAdding: .day, value: -effectiveDays, to: cal.startOfDay(for: end)) else { return [] }

        var byDay: [String: DayAgg] = [:]
        func agg(_ day: String) -> DayAgg { byDay[day] ?? DayAgg() }

        // 11 quantity collectors + sleep + workouts + workout HR (FER-883) + the store write = 15
        // pipeline stages. Publishing the stage *before* running it turns the silent background pull
        // into "Importing HRV… (4/15)" in the UI; `done` counts stages already finished. (FER-70)
        let total = 15
        func stage(_ done: Int, _ key: String) { syncProgress = SyncProgress(stageKey: key, done: done, total: total) }

        // Quantity aggregates per day.
        stage(0, "resting_hr")
        await collect(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.restingHr = v; byDay[day] = a
        }
        stage(1, "avg_hr")
        await collect(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.avgHr = v; byDay[day] = a
        }
        stage(2, "max_hr")
        await collect(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, op: .discreteMax) { day, v in
            var a = agg(day); a.maxHr = v; byDay[day] = a
        }
        stage(3, "hrv")
        await collect(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.hrv = v; byDay[day] = a
        }
        stage(4, "spo2")
        await collect(.oxygenSaturation, unit: .percent(), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.spo2 = v * 100; byDay[day] = a   // 0…1 → percent
        }
        stage(5, "resp_rate")
        await collect(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.respRate = v; byDay[day] = a
        }
        stage(6, "steps")
        await collect(.stepCount, unit: .count(), start: start, end: end, op: .cumulativeSum) { day, v in
            var a = agg(day); a.steps = v; byDay[day] = a
        }
        stage(7, "active_kcal")
        await collect(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end, op: .cumulativeSum) { day, v in
            var a = agg(day); a.activeKcal = v; byDay[day] = a
        }
        stage(8, "basal_kcal")
        await collect(.basalEnergyBurned, unit: .kilocalorie(), start: start, end: end, op: .cumulativeSum) { day, v in
            var a = agg(day); a.basalKcal = v; byDay[day] = a
        }
        stage(9, "vo2max")
        await collect(.vo2Max, unit: HKUnit(from: "ml/kg*min"), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.vo2max = v; byDay[day] = a
        }
        // FER-882: Apple's sleeping wrist temperature (absolute °C) → nightly mean; deviation vs
        // Apple's OWN rolling baseline is computed just before DailyMetric construction below.
        stage(10, "skin_temp")
        await collect(.appleSleepingWristTemperature, unit: .degreeCelsius(), start: start, end: end,
                      op: .discreteAverage) { day, v in
            var a = agg(day); a.skinTempC = v; byDay[day] = a
        }

        // Sleep minutes per day (asleep stages summed; attributed to wake day).
        stage(11, "sleep")
        await collectSleep(start: start, end: end) { day, asleepMin, deepMin, remMin, coreMin in
            var a = agg(day)
            a.asleepMin = asleepMin; a.deepMin = deepMin; a.remMin = remMin; a.coreMin = coreMin
            byDay[day] = a
        }

        // Workouts: fetched directly from HealthKit and stored alongside WHOOP sessions.
        stage(12, "workouts")
        let hkWorkouts = await collectHKWorkouts(start: start, end: end)
        let wkRows = Self.mapWorkouts(hkWorkouts)

        // FER-883: per-workout heart-rate samples (raw only — strain is scored at read time).
        // Skipped in whoopOnly so we never pull Apple HR into the store when the mode excludes Apple;
        // the stage is still published so the progress bar stays 15-step consistent.
        stage(13, "hr_apple_workouts")
        let workoutHrSamples: [HRSample]
        if repo.dataSourceMode == .whoopOnly {
            workoutHrSamples = []
        } else {
            workoutHrSamples = await collectWorkoutHeartRate(workouts: hkWorkouts)
        }

        // FER-486: per-night Apple sleep SESSIONS with a stage timeline (for the Detalle de Sueño
        // hypnogram), ALONGSIDE the daily totals from collectSleep above — F3 is additive. Pure decode
        // (SleepHKDecoder, StrandImport); the idempotent upsert below keeps a re-sync from duplicating.
        let appleSleepSessions = SleepHKDecoder.sessions(from: await collectSleepSamples(start: start, end: end))

        stage(14, "saving")

        // Build + upsert the store rows under the apple-health source.
        let appleRows = byDay.map { (day, a) in
            AppleDaily(day: day, steps: a.steps.map { Int($0) },
                       activeKcal: a.activeKcal, basalKcal: a.basalKcal, vo2max: a.vo2max,
                       avgHr: a.avgHr.map { Int($0.rounded()) }, maxHr: a.maxHr.map { Int($0.rounded()) },
                       walkingHr: nil, weightKg: nil)
        }
        // FER-882: Apple's OWN rolling skin-temp baseline over the sync window, then the same final
        // state's deviation applied to every night (mirrors IntelligenceEngine.recomputeSkinTempDev —
        // one fold, not a per-day incremental). Never mixed with the band's baseline.
        let skinCfg = Baselines.metricCfg["skin_temp"]!   // minVal 20 / maxVal 42 °C absolute
        let skinSeq: [(day: String, value: Double?)] = byDay.keys.sorted().map { (day: $0, value: byDay[$0]?.skinTempC) }
        let appleSkinBase = Baselines.foldHistory(skinSeq, epoch: nil, cfg: skinCfg)
        func appleSkinDev(_ v: Double?) -> Double? {
            guard let v, appleSkinBase.usable else { return nil }
            return (Baselines.deviation(v, state: appleSkinBase).delta * 100.0).rounded() / 100.0
        }
        let dmRows = byDay.map { (day, a) in
            DailyMetric(day: day, totalSleepMin: a.asleepMin, efficiency: nil,
                        deepMin: a.deepMin, remMin: a.remMin, lightMin: a.coreMin, disturbances: nil,
                        restingHr: a.restingHr.map { Int($0.rounded()) }, avgHrv: a.hrv,
                        recovery: nil, strain: nil, exerciseCount: nil,
                        spo2Pct: a.spo2, skinTempDevC: appleSkinDev(a.skinTempC), respRateBpm: a.respRate,
                        steps: a.steps.map { Int($0) })
        }
        // Generic metricSeries points. The per-source pages (Apple Health, Explore, Compare) and the
        // Today sparklines read from metricSeries, which the structured appleDaily/dailyMetric upserts
        // above do NOT populate — only the XML importer did, so a live sync left those screens empty.
        // Mirror the importer's keys (AppleHealthAggregator.metricPoints) so a live sync surfaces the
        // same way as an import; only non-nil values are emitted. (FER-97)
        let seriesRows: [MetricPoint] = byDay.flatMap { (day, a) -> [MetricPoint] in
            var pts: [MetricPoint] = []
            func add(_ key: String, _ value: Double?) { if let v = value { pts.append(MetricPoint(day: day, key: key, value: v)) } }
            add("resting_hr", a.restingHr)
            add("hrv", a.hrv)
            add("spo2", a.spo2)
            add("resp_rate", a.respRate)
            add("avg_hr", a.avgHr)
            add("max_hr", a.maxHr)
            add("steps", a.steps)
            add("active_kcal", a.activeKcal)
            add("basal_kcal", a.basalKcal)
            add("vo2max", a.vo2max)
            add("asleep_min", a.asleepMin)
            add("deep_min", a.deepMin)
            add("rem_min", a.remMin)
            add("core_min", a.coreMin)
            return pts
        }
        // The read→store upsert and the NOOP→Health write-back are one unit. If the store write
        // fails, do NOT advance lastSync (the next delta sync must re-attempt this window) and surface
        // the error instead of swallowing it with `try?` — a failed upsert used to be silent while
        // lastSync still moved forward, skipping the window and losing the data permanently.
        // FER-872/881: a stable fingerprint of the Apple rows this run would surface (every written array
        // derives from `byDay`, plus workouts + sleep sessions). A foreground re-pull of identical data
        // must not bump `refreshSeq` — which re-runs TodayView.loadAll + insights + live strain for nothing.
        let signature = Self.stableAppleSignature(byDay: byDay, workouts: wkRows, sleeps: appleSleepSessions)
        let isFullSync = (effectiveDays == days)
        do {
            try await store.upsertAppleDaily(appleRows, deviceId: appleDeviceId)
            try await store.upsertDailyMetrics(dmRows, deviceId: appleDeviceId)
            try await store.upsertMetricSeries(seriesRows, deviceId: appleDeviceId)
            try await store.upsertWorkouts(wkRows, deviceId: appleDeviceId)
            // FER-883: raw workout HR under apple-health — never fused into baselines; strain is
            // scored at read time via `Repository.appleStrainEstimates`. Empty is a no-op (idempotent).
            if !workoutHrSamples.isEmpty {
                try await store.insert(Streams(hr: workoutHrSamples), deviceId: appleDeviceId)
            }
            try await store.upsertSleepSessions(appleSleepSessions, deviceId: appleDeviceId)   // FER-486 (F3): per-night stage timeline
            try await writeBack(whoopStore: store)
            lastSync = Date()
            lastError = nil
            if trigger == .foreground { didFullForegroundSyncThisSession = true }
            // Only rebuild the dashboard when the Apple rows actually changed. A manual sync always
            // refreshes so the user sees an unmistakable response to tapping "Sync now" (FER-872).
            let changed: Bool
            if trigger != .foreground {
                changed = true
            } else if isFullSync {
                // FER-881: first foreground of the session (full 30d). Compare against the signature
                // persisted from the last session's full sync — equal ⇒ the store already holds this
                // exact Apple data (the launch full-refresh surfaced it) ⇒ skip the redundant cold-start
                // rebuild. This is the second of the two launch refreshes FER-881 removes (the other is
                // analyzeRecent's), taking a recurring Apple-Health user's cold start to ≤2.
                changed = (signature != UserDefaults.standard.string(forKey: Self.lastFullSyncSigKey))
                UserDefaults.standard.set(signature, forKey: Self.lastFullSyncSigKey)
            } else {
                // Subsequent delta foreground within the same session.
                changed = (signature != lastAppleWriteSignature)
            }
            lastAppleWriteSignature = signature
            if changed {
                await repo.refresh()   // surface the freshly-synced Apple Health days in the dashboard
            }
            coverage = try? await store.appleHealthCoverage(deviceId: appleDeviceId)
            refreshPermissions()   // a denied scope may have changed between runs
            return Set(byDay.keys)   // FER-226: the local days written this run (for the re-bucket prune)
        } catch {
            lastError = "Apple Health sync failed: \(error.localizedDescription)"
            return []   // nothing durably written → the re-bucket must NOT prune apple rows this run
        }
    }

    // MARK: - Write back (NOOP → Health)

    /// Write NOOP's strap-derived daily metrics (resting HR, HRV, SpO₂, respiratory rate) into Apple
    /// Health so they appear across the user's Health ecosystem.
    ///
    /// Dedup model: each emitted sample carries a deterministic `HKMetadataKeyExternalUUID` derived
    /// from `noopDeviceId + metric + day`. Before saving, we delete any of *our* prior samples that
    /// carry the same key (scoped to `HKSource.default()` so we never touch another app's data) and
    /// then save the fresh batch. HealthKit assigns a new UUID per save, so the previous strategy
    /// (no metadata, no delete) flooded Health with duplicates on every `sync()`.
    ///
    /// Throws on save failure so the caller can decide whether to advance `lastSync`.
    // MARK: - Strength session → Apple Health (FER-390)

    /// Write a finished guided strength session into Apple Health as an `HKWorkout`, but only when the
    /// user opted in. Best-effort and **non-throwing**: the session is already persisted in `WhoopStore`
    /// (the source of truth), so a Health failure must never throw to the caller or block the session.
    /// Idempotent by external UUID — re-saving the same session replaces its prior workout instead of
    /// duplicating it. The estimated active-energy sample inside `[start, end]` is what lets the iPhone's
    /// **Move ring** credit the session (no Apple Watch needed). Energy is a MET-based estimate
    /// (`Calories.estimateStrengthCalories`, Ainsworth 2011) — the session records no per-second HR.
    func saveStrengthWorkoutIfEnabled(sessionId: String, start: Date, end: Date, profile: UserProfile,
                                      hrSamples: [HRSample] = [], hrMax: Int? = nil) async {
        guard UserDefaults.standard.bool(forKey: Self.saveStrengthWorkoutsKey) else { return }
        guard HKHealthStore.isHealthDataAvailable(), end > start else { return }
        // Gate on the workout share grant directly (independent of the read connection): if the user
        // toggled on but the prompt wasn't granted, surface it honestly — never crash, never block.
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            lastError = "No pudimos guardar el entrenamiento en Apple Salud. Revisa los permisos en Ajustes."
            return
        }

        // Keytel when the session carried strap HR (FER-399), MET otherwise. Camino B: the HR only feeds
        // the estimate — it is NOT written to Apple Health as heart-rate samples.
        let kcal = Calories.estimateStrengthEnergy(hrSamples: hrSamples, durationSeconds: end.timeIntervalSince(start),
                                                   profile: profile, hrMax: hrMax.map(Double.init))
        let externalUUID = "noop:strength:\(sessionId)"
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining

        do {
            // Idempotency: delete our own prior workout for this session, then write a fresh one.
            // Scoped to this app's samples + this session's external UUID (mirrors `writeBack`).
            let bySource = HKQuery.predicateForObjects(from: HKSource.default())
            let byKey = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID,
                                                    allowedValues: [externalUUID])
            let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [bySource, byKey])
            _ = try? await store.deleteObjects(of: HKObjectType.workoutType(), predicate: pred)

            let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
            try await builder.beginCollection(at: start)
            if kcal > 0, let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
                let energy = HKQuantitySample(type: energyType,
                                              quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                              start: start, end: end)
                // `HKWorkoutBuilder.add(_:)` ships completion-only (no async bridge), so wrap it.
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    builder.add([energy]) { _, error in
                        if let error { cont.resume(throwing: error) } else { cont.resume() }
                    }
                }
            }
            try await builder.addMetadata([HKMetadataKeyExternalUUID: externalUUID])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func writeBack(whoopStore: WhoopStore, days: Int = 14) async throws {
        guard auth == .authorized else { return }
        let cal = Calendar.current
        let to = HealthKitBridge.dayString(Date())
        guard let fromDate = cal.date(byAdding: .day, value: -days, to: Date()) else { return }
        let from = HealthKitBridge.dayString(fromDate)
        guard let rows = try? await whoopStore.dailyMetrics(deviceId: noopDeviceId, from: from, to: to) else { return }
        // FER-970 (R-05): fetch the sleep payload up front too, fingerprint the WHOLE mirror, and
        // skip the delete+rewrite when it's identical to the last successful write-back (the same
        // gate idea FER-872/881 applied to the dashboard rebuild). The signature is persisted only
        // AFTER both writes succeed, so a failed save is retried on the next sync.
        let sleepFromTs = Int(fromDate.timeIntervalSince1970)
        let sleepSessions = (try? await whoopStore.sleepSessions(
            deviceId: noopDeviceId, from: sleepFromTs, to: Int(Date().timeIntervalSince1970),
            limit: 90)) ?? []
        let signature = Self.stableWriteBackSignature(rows: rows, sessions: sleepSessions)
        if signature == UserDefaults.standard.string(forKey: Self.lastWriteBackSigKey) { return }

        struct Candidate { let type: HKQuantityType; let key: String; let sample: HKQuantitySample }
        var candidates: [Candidate] = []
        func add(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double, _ day: String, _ at: Date) {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return }
            let key = "noop:\(noopDeviceId):\(id.rawValue):\(day)"
            let sample = HKQuantitySample(
                type: type,
                quantity: .init(unit: unit, doubleValue: value),
                start: at, end: at,
                metadata: [HKMetadataKeyExternalUUID: key]
            )
            candidates.append(Candidate(type: type, key: key, sample: sample))
        }

        for row in rows {
            guard let date = HealthKitBridge.date(from: row.day) else { continue }
            let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
            if let rhr = row.restingHr {
                add(.restingHeartRate, HKUnit.count().unitDivided(by: .minute()), Double(rhr), row.day, noon)
            }
            if let hrv = row.avgHrv {
                add(.heartRateVariabilitySDNN, .secondUnit(with: .milli), hrv, row.day, noon)
            }
            if let spo2 = row.spo2Pct {
                add(.oxygenSaturation, .percent(), spo2 / 100, row.day, noon)
            }
            if let rr = row.respRateBpm {
                add(.respiratoryRate, HKUnit.count().unitDivided(by: .minute()), rr, row.day, noon)
            }
        }
        // Quantity metrics: delete our prior samples, then write fresh ones.
        // Delete is non-fatal (nothing to delete on first run); only the save throws.
        if !candidates.isEmpty {
            let bySource = HKQuery.predicateForObjects(from: HKSource.default())
            let grouped = Dictionary(grouping: candidates, by: { $0.type })
            for (type, items) in grouped {
                let keys = Array(Set(items.map { $0.key }))
                let byKey = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID,
                                                        allowedValues: keys)
                let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [bySource, byKey])
                _ = try? await self.store.deleteObjects(of: type, predicate: pred)
            }
            try await self.store.save(candidates.map { $0.sample })
        }

        // Sleep stages: one HKCategorySample per WHOOP stage segment plus one .inBed per session.
        // Uses the same external-UUID dedup strategy as the quantity metrics above.
        try await writeSleepBack(sessions: sleepSessions)
        UserDefaults.standard.set(signature, forKey: Self.lastWriteBackSigKey)
    }

    /// FER-970 (R-05): deterministic fingerprint of everything `writeBack` mirrors — the four
    /// per-day quantities plus each sleep session's span and staged hypnogram. Same SHA-256
    /// technique as `stableAppleSignature` (stable across launches).
    private static func stableWriteBackSignature(rows: [DailyMetric],
                                                 sessions: [CachedSleepSession]) -> String {
        func f(_ d: Double?) -> String { d.map { String(format: "%.4f", $0) } ?? "-" }
        var s = ""
        for r in rows.sorted(by: { $0.day < $1.day }) {
            s += "\(r.day):\(r.restingHr.map(String.init) ?? "-"),\(f(r.avgHrv)),\(f(r.spo2Pct)),\(f(r.respRateBpm));"
        }
        s += "|S:"
        for sl in sessions.sorted(by: { ($0.startTs, $0.endTs) < ($1.startTs, $1.endTs) }) {
            s += "\(sl.startTs)-\(sl.endTs)-\(sl.stagesJSON ?? "-");"
        }
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Write WHOOP sleep sessions (staged hypnogram) into Apple Health.
    ///
    /// Each stage segment from `stagesJSON` maps to a `HKCategorySample` with the matching
    /// `HKCategoryValueSleepAnalysis` value. A single `.inBed` sample covers the full session span.
    /// The dedup key `"noop:<deviceId>:sleep:<sessionStart>:<segStart>"` prevents duplicates on
    /// repeated calls — we delete our own prior samples before saving the fresh batch.
    private func writeSleepBack(sessions: [CachedSleepSession]) async throws {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              store.authorizationStatus(for: sleepType) == .sharingAuthorized else { return }

        // FER-970 (R-05): the sessions arrive from `writeBack`, which already fetched them for the
        // write-back fingerprint — one read serves both the gate and the payload.
        let encoded = SleepHKEncoder.samples(from: sessions, deviceId: noopDeviceId)
        guard !encoded.isEmpty else { return }

        let hkSamples = encoded.map { enc in
            HKCategorySample(type: sleepType, value: enc.hkValue,
                             start: enc.start, end: enc.end,
                             metadata: [HKMetadataKeyExternalUUID: enc.dedupeKey])
        }
        let keys = encoded.map(\.dedupeKey)
        let bySource = HKQuery.predicateForObjects(from: HKSource.default())
        let byKey = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: keys)
        let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [bySource, byKey])
        _ = try? await self.store.deleteObjects(of: sleepType, predicate: pred)
        try await self.store.save(hkSamples)
    }

    private struct DayAgg {
        var restingHr: Double?; var avgHr: Double?; var maxHr: Double?; var hrv: Double?
        var spo2: Double?; var respRate: Double?; var steps: Double?
        var activeKcal: Double?; var basalKcal: Double?; var vo2max: Double?
        var asleepMin: Double?; var deepMin: Double?; var remMin: Double?; var coreMin: Double?
        var skinTempC: Double?   // FER-882: nightly mean absolute wrist temp (°C)
    }

    /// FER-872/881: a STABLE, order-independent fingerprint of the Apple rows a sync run would surface.
    /// `byDay` carries every daily/series/appleDaily value (they're all derived from it); workouts and
    /// sleep sessions fold in by their identifying fields. SHA-256 over a deterministic string (NOT the
    /// per-process `Hasher`, whose seed varies per launch) so it can be PERSISTED across launches and
    /// compared on the next session's first foreground sync (FER-881). Values are formatted at fixed
    /// precision so an exact re-pull hashes identically.
    private static func stableAppleSignature(byDay: [String: DayAgg],
                                             workouts: [WorkoutRow],
                                             sleeps: [CachedSleepSession]) -> String {
        func f(_ d: Double?) -> String { d.map { String(format: "%.4f", $0) } ?? "-" }
        var s = ""
        for key in byDay.keys.sorted() {
            let a = byDay[key]!
            s += "\(key):\(f(a.restingHr)),\(f(a.avgHr)),\(f(a.maxHr)),\(f(a.hrv)),\(f(a.spo2)),\(f(a.respRate)),\(f(a.steps)),\(f(a.activeKcal)),\(f(a.basalKcal)),\(f(a.vo2max)),\(f(a.asleepMin)),\(f(a.deepMin)),\(f(a.remMin)),\(f(a.coreMin)),\(f(a.skinTempC));"
        }
        s += "|W:"
        for w in workouts.sorted(by: { ($0.startTs, $0.endTs, $0.sport) < ($1.startTs, $1.endTs, $1.sport) }) {
            s += "\(w.startTs)-\(w.endTs)-\(w.sport)-\(f(w.durationS))-\(f(w.energyKcal));"
        }
        s += "|S:"
        for sl in sleeps.sorted(by: { ($0.startTs, $0.endTs) < ($1.startTs, $1.endTs) }) {
            s += "\(sl.startTs)-\(sl.endTs)-\(f(sl.efficiency))-\(sl.restingHr.map(String.init) ?? "-")-\(f(sl.avgHrv))-\(sl.stagesJSON ?? "-");"
        }
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func collect(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date,
                         op: HKStatisticsOptions, sink: @escaping (String, Double) -> Void) async {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return }
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                options: op, anchorDate: anchor,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, _ in
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let q: HKQuantity?
                    switch op {
                    case .cumulativeSum:    q = stats.sumQuantity()
                    case .discreteAverage:  q = stats.averageQuantity()
                    case .discreteMax:      q = stats.maximumQuantity()
                    default:                q = stats.averageQuantity()
                    }
                    if let q { sink(HealthKitBridge.dayString(stats.startDate), q.doubleValue(for: unit)) }
                }
                cont.resume()
            }
            store.execute(q)
        }
    }

    private func collectSleep(start: Date, end: Date,
                              sink: @escaping (String, Double?, Double?, Double?, Double?) -> Void) async {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                var asleep: [String: Double] = [:], deep: [String: Double] = [:]
                var rem: [String: Double] = [:], core: [String: Double] = [:]
                for case let s as HKCategorySample in samples ?? [] {
                    let mins = s.endDate.timeIntervalSince(s.startDate) / 60
                    let day = HealthKitBridge.dayString(s.endDate)
                    switch s.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deep[day, default: 0] += mins; asleep[day, default: 0] += mins
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        rem[day, default: 0] += mins; asleep[day, default: 0] += mins
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        core[day, default: 0] += mins; asleep[day, default: 0] += mins
                    default:
                        break
                    }
                }
                for day in Set(asleep.keys) {
                    sink(day, asleep[day], deep[day], rem[day], core[day])
                }
                cont.resume()
            }
            store.execute(q)
        }
    }

    /// FER-486: the raw `sleepAnalysis` samples as platform-agnostic descriptors, so the pure
    /// `SleepHKDecoder` (StrandImport) can group them into one per-night `CachedSleepSession` with a
    /// stage timeline for the Detalle de Sueño hypnogram. Runs ALONGSIDE `collectSleep` (which keeps
    /// producing the daily totals) — F3 is additive. No mapping/grouping here: this is the thin shell.
    private func collectSleepSamples(start: Date, end: Date) async -> [SleepHKSample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { (cont: CheckedContinuation<[SleepHKSample], Never>) in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let out: [SleepHKSample] = (samples ?? []).compactMap { s in
                    guard let c = s as? HKCategorySample else { return nil }
                    return SleepHKSample(hkValue: c.value, start: c.startDate, end: c.endDate, dedupeKey: "")
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    // MARK: - Workout helpers

    /// Raw `HKWorkout`s in [start, end] — shared by `mapWorkouts` and `collectWorkoutHeartRate`
    /// so we don't re-query HealthKit for the same window. (FER-883)
    private func collectHKWorkouts(start: Date, end: Date) async -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { (cont: CheckedContinuation<[HKWorkout], Never>) in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
    }

    /// Map raw `HKWorkout`s to store rows (same shape as pre-FER-883 `collectWorkouts`).
    private nonisolated static func mapWorkouts(_ workouts: [HKWorkout]) -> [WorkoutRow] {
        workouts.map { w in
            WorkoutRow(
                startTs: Int(w.startDate.timeIntervalSince1970),
                endTs:   Int(w.endDate.timeIntervalSince1970),
                sport:   Self.activityTypeName(w.workoutActivityType),
                source:  "apple-health",
                durationS:  w.duration > 0 ? w.duration : nil,
                energyKcal: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                avgHr: nil, maxHr: nil, strain: nil,
                distanceM: w.totalDistance?.doubleValue(for: .meter()),
                zonesJSON: nil, notes: nil
            )
        }
    }

    /// Heart-rate samples belonging to each workout, merged + sorted + deduped by `ts`.
    /// Scopes via `HKQuery.predicateForObjects(from:)` only — that already limits to the workout.
    /// Raw HR only; strain is scored at read time. (FER-883)
    private func collectWorkoutHeartRate(workouts: [HKWorkout]) async -> [HRSample] {
        guard !workouts.isEmpty,
              let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())
        var all: [HRSample] = []
        all.reserveCapacity(workouts.count * 600)
        for w in workouts {
            let samples = await withCheckedContinuation { (cont: CheckedContinuation<[HRSample], Never>) in
                let predicate = HKQuery.predicateForObjects(from: w)
                let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, raw, _ in
                    let unitLocal = unit
                    let out: [HRSample] = (raw as? [HKQuantitySample] ?? []).map { s in
                        HRSample(ts: Int(s.startDate.timeIntervalSince1970),
                                 bpm: Int(s.quantity.doubleValue(for: unitLocal).rounded()))
                    }
                    cont.resume(returning: out)
                }
                store.execute(q)
            }
            all.append(contentsOf: samples)
        }
        // Sort ascending by ts, then keep first occurrence of each ts (overlapping workouts).
        all.sort { $0.ts < $1.ts }
        var seen = Set<Int>()
        seen.reserveCapacity(all.count)
        return all.filter { seen.insert($0.ts).inserted }
    }

    /// Convert an HKWorkoutActivityType to the camelCase string that matches what the XML export
    /// importer stores (e.g. "TraditionalStrengthTraining"). displaySport() then inserts spaces.
    nonisolated static func activityTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .americanFootball:             return "AmericanFootball"
        case .archery:                      return "Archery"
        case .australianFootball:           return "AustralianFootball"
        case .badminton:                    return "Badminton"
        case .baseball:                     return "Baseball"
        case .basketball:                   return "Basketball"
        case .bowling:                      return "Bowling"
        case .boxing:                       return "Boxing"
        case .climbing:                     return "Climbing"
        case .crossTraining:                return "CrossTraining"
        case .curling:                      return "Curling"
        case .cycling:                      return "Cycling"
        case .dance:                        return "Dance"
        case .elliptical:                   return "Elliptical"
        case .equestrianSports:             return "EquestrianSports"
        case .fencing:                      return "Fencing"
        case .fishing:                      return "Fishing"
        case .functionalStrengthTraining:   return "FunctionalStrengthTraining"
        case .golf:                         return "Golf"
        case .gymnastics:                   return "Gymnastics"
        case .handball:                     return "Handball"
        case .hiking:                       return "Hiking"
        case .hockey:                       return "Hockey"
        case .lacrosse:                     return "Lacrosse"
        case .martialArts:                  return "MartialArts"
        case .mindAndBody:                  return "MindAndBody"
        case .paddleSports:                 return "PaddleSports"
        case .play:                         return "Play"
        case .preparationAndRecovery:       return "PreparationAndRecovery"
        case .racquetball:                  return "Racquetball"
        case .rowing:                       return "Rowing"
        case .rugby:                        return "Rugby"
        case .running:                      return "Running"
        case .sailing:                      return "Sailing"
        case .skatingSports:                return "SkatingSports"
        case .snowSports:                   return "SnowSports"
        case .soccer:                       return "Soccer"
        case .softball:                     return "Softball"
        case .squash:                       return "Squash"
        case .stairClimbing:                return "StairClimbing"
        case .surfingSports:                return "SurfingSports"
        case .swimming:                     return "Swimming"
        case .tableTennis:                  return "TableTennis"
        case .tennis:                       return "Tennis"
        case .trackAndField:                return "TrackAndField"
        case .traditionalStrengthTraining:  return "TraditionalStrengthTraining"
        case .volleyball:                   return "Volleyball"
        case .walking:                      return "Walking"
        case .waterFitness:                 return "WaterFitness"
        case .waterPolo:                    return "WaterPolo"
        case .waterSports:                  return "WaterSports"
        case .wrestling:                    return "Wrestling"
        case .yoga:                         return "Yoga"
        case .barre:                        return "Barre"
        case .coreTraining:                 return "CoreTraining"
        case .crossCountrySkiing:           return "CrossCountrySkiing"
        case .downhillSkiing:               return "DownhillSkiing"
        case .flexibility:                  return "Flexibility"
        case .highIntensityIntervalTraining: return "HighIntensityIntervalTraining"
        case .jumpRope:                     return "JumpRope"
        case .kickboxing:                   return "Kickboxing"
        case .pilates:                      return "Pilates"
        case .snowboarding:                 return "Snowboarding"
        case .stairs:                       return "Stairs"
        case .stepTraining:                 return "StepTraining"
        case .taiChi:                       return "TaiChi"
        case .mixedCardio:                  return "MixedCardio"
        case .handCycling:                  return "HandCycling"
        case .discSports:                   return "DiscSports"
        case .fitnessGaming:                return "FitnessGaming"
        case .cardioDance:                  return "CardioDance"
        case .socialDance:                  return "SocialDance"
        case .pickleball:                   return "Pickleball"
        case .cooldown:                     return "Cooldown"
        case .swimBikeRun:                  return "SwimBikeRun"
        case .transition:                   return "Transition"
        case .underwaterDiving:             return "UnderwaterDiving"
        default:                            return "Other"
        }
    }

    // MARK: - Date helpers

    // LOCAL civil day (FER-226): every source now keys `dailyMetric.day` by the device's local civil
    // day (same convention as Repository.localDayKey), so the evening's data counts for the correct day
    // in a UTC− zone instead of rolling into tomorrow. This REVERSES FER-32's UTC choice; the
    // cross-time-zone duplicate it guarded against is now handled by last-writer-wins on the
    // (deviceId, day) PK plus the one-time re-bucket's future-row prune — at most one defined seam on a
    // travel day, never silent duplicates. These helpers are `nonisolated` so they can run on
    // HealthKit's query-callback queue without hopping to the main actor (`HealthKitBridge` is
    // `@MainActor`); the formatter is an immutable, Sendable constant, safe to read from any context.
    // Device-local on purpose (HealthKit sample dates are civil-day concepts) — the canonical
    // WRITE-side formatter, matching how DailyMetric.day keys are minted (FER-754).
    nonisolated private static let dayFormatter = DayKey.localFormatter
    nonisolated private static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
    nonisolated private static func date(from day: String) -> Date? { dayFormatter.date(from: day) }
}
#endif
