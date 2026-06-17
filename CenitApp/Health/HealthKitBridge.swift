#if os(iOS)
import Foundation
import HealthKit
import StrandImport
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
        return s
    }

    private var writeTypes: Set<HKSampleType> {
        var s = Set<HKSampleType>()
        for id in HealthKitBridge.quantityWriteIds { if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) } }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        return s
    }

    // Every id here ends up in the HealthKit permission dialog. Only request what `sync` actually
    // aggregates into `DayAgg`; adding read scopes the app never consumes makes the consent prompt
    // noisier and surfaces a privacy ask we don't honour.
    private static let quantityReadIds: [HKQuantityTypeIdentifier] = [
        .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .oxygenSaturation,
        .respiratoryRate, .stepCount, .activeEnergyBurned,
        .basalEnergyBurned, .vo2Max
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
    /// upserts keyed by day).
    func sync(days: Int = 30) async {
        guard auth == .authorized, !syncing else { return }
        syncing = true
        defer { syncing = false; syncProgress = nil }
        guard let store = await repo.storeHandle() else { return }

        let cal = Calendar.current
        let end = Date()
        guard let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end)) else { return }

        var byDay: [String: DayAgg] = [:]
        func agg(_ day: String) -> DayAgg { byDay[day] ?? DayAgg() }

        // 10 quantity collectors + sleep + workouts + the store write = 13 pipeline stages. Publishing
        // the stage *before* running it turns the silent background pull into "Importing HRV… (4/13)"
        // in the UI; `done` counts stages already finished. (FER-70)
        let total = 13
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

        // Sleep minutes per day (asleep stages summed; attributed to wake day).
        stage(10, "sleep")
        await collectSleep(start: start, end: end) { day, asleepMin, deepMin, remMin, coreMin in
            var a = agg(day)
            a.asleepMin = asleepMin; a.deepMin = deepMin; a.remMin = remMin; a.coreMin = coreMin
            byDay[day] = a
        }

        // Workouts: fetched directly from HealthKit and stored alongside WHOOP sessions.
        stage(11, "workouts")
        let wkRows = await collectWorkouts(start: start, end: end)

        stage(12, "saving")

        // Build + upsert the store rows under the apple-health source.
        let appleRows = byDay.map { (day, a) in
            AppleDaily(day: day, steps: a.steps.map { Int($0) },
                       activeKcal: a.activeKcal, basalKcal: a.basalKcal, vo2max: a.vo2max,
                       avgHr: a.avgHr.map { Int($0.rounded()) }, maxHr: a.maxHr.map { Int($0.rounded()) },
                       walkingHr: nil, weightKg: nil)
        }
        let dmRows = byDay.map { (day, a) in
            DailyMetric(day: day, totalSleepMin: a.asleepMin, efficiency: nil,
                        deepMin: a.deepMin, remMin: a.remMin, lightMin: a.coreMin, disturbances: nil,
                        restingHr: a.restingHr.map { Int($0.rounded()) }, avgHrv: a.hrv,
                        recovery: nil, strain: nil, exerciseCount: nil,
                        spo2Pct: a.spo2, skinTempDevC: nil, respRateBpm: a.respRate)
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
        do {
            try await store.upsertAppleDaily(appleRows, deviceId: appleDeviceId)
            try await store.upsertDailyMetrics(dmRows, deviceId: appleDeviceId)
            try await store.upsertMetricSeries(seriesRows, deviceId: appleDeviceId)
            try await store.upsertWorkouts(wkRows, deviceId: appleDeviceId)
            try await writeBack(whoopStore: store)
            lastSync = Date()
            lastError = nil
            await repo.refresh()   // surface the freshly-synced Apple Health days in the dashboard
            coverage = try? await store.appleHealthCoverage(deviceId: appleDeviceId)
            refreshPermissions()   // a denied scope may have changed between runs
        } catch {
            lastError = "Apple Health sync failed: \(error.localizedDescription)"
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
    private func writeBack(whoopStore: WhoopStore, days: Int = 14) async throws {
        guard auth == .authorized else { return }
        let cal = Calendar.current
        let to = HealthKitBridge.dayString(Date())
        guard let fromDate = cal.date(byAdding: .day, value: -days, to: Date()) else { return }
        let from = HealthKitBridge.dayString(fromDate)
        guard let rows = try? await whoopStore.dailyMetrics(deviceId: noopDeviceId, from: from, to: to) else { return }

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
        try await writeSleepBack(whoopStore: whoopStore, fromDate: fromDate)
    }

    /// Write WHOOP sleep sessions (staged hypnogram) into Apple Health.
    ///
    /// Each stage segment from `stagesJSON` maps to a `HKCategorySample` with the matching
    /// `HKCategoryValueSleepAnalysis` value. A single `.inBed` sample covers the full session span.
    /// The dedup key `"noop:<deviceId>:sleep:<sessionStart>:<segStart>"` prevents duplicates on
    /// repeated calls — we delete our own prior samples before saving the fresh batch.
    private func writeSleepBack(whoopStore: WhoopStore, fromDate: Date) async throws {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              store.authorizationStatus(for: sleepType) == .sharingAuthorized else { return }

        let fromTs = Int(fromDate.timeIntervalSince1970)
        let toTs   = Int(Date().timeIntervalSince1970)
        guard let sessions = try? await whoopStore.sleepSessions(
            deviceId: noopDeviceId, from: fromTs, to: toTs, limit: 90) else { return }

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

    // MARK: - Workout helpers

    /// Fetch all HKWorkout samples in [start, end] and map them to WorkoutRow.
    private func collectWorkouts(start: Date, end: Date) async -> [WorkoutRow] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { (cont: CheckedContinuation<[WorkoutRow], Never>) in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
                let rows = (samples as? [HKWorkout] ?? []).map { w in
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
                cont.resume(returning: rows)
            }
            store.execute(q)
        }
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

    // UTC: the rest of the store keys days by UTC (Repository's compareDayParser, the
    // dailyMetric primary key). Using .current here would split the same physical day across
    // two `yyyy-MM-dd` keys when the user crosses a time zone, causing duplicate daily rows.
    // These helpers are `nonisolated` so they can run on HealthKit's query-callback queue without
    // hopping to the main actor (`HealthKitBridge` is `@MainActor`); the formatter is an immutable,
    // Sendable constant, safe to read from any context.
    nonisolated private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")!; return f
    }()
    nonisolated private static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
    nonisolated private static func date(from day: String) -> Date? { dayFormatter.date(from: day) }
}
#endif
