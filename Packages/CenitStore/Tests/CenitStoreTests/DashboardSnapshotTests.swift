import XCTest
import BiometricStreams
@testable import CenitStore

/// FER-970 (R-03) — `dashboardSnapshot` reads everything the dashboard refresh consumes in ONE
/// transaction. These tests pin (1) field-by-field equivalence with the individual accessors,
/// (2) the source-mode gating flags — with the load-bearing exception that `appleDays` and the
/// raw strap sleeps are NEVER gated (FER-485 coverage) — and (3) identical window bounds.
final class DashboardSnapshotTests: XCTestCase {

    private let strap = "my-whoop"
    private let comp = "my-whoop-noop"
    private let apple = "apple-health"
    /// 2026-06-01 00:00:00 UTC.
    private let t0 = 1_780_272_000

    private func dm(_ day: String, hrv: Double?, strain: Double?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 400, efficiency: 88, deepMin: 70, remMin: 90,
                    lightMin: 200, disturbances: 2, restingHr: 55, avgHrv: hrv,
                    recovery: 60, strain: strain, exerciseCount: 1, spo2Pct: 96, respRateBpm: 14)
    }

    private func seed(_ store: CenitStore) async throws {
        for (dev, hrv) in [(strap, 40.0), (comp, 41.0), (apple, 42.0)] {
            _ = try await store.upsertDailyMetrics([
                dm("2026-06-01", hrv: hrv, strain: 9.5),
                dm("2026-06-02", hrv: hrv + 1, strain: nil),
            ], deviceId: dev)
        }
        for (i, dev) in [strap, comp, apple].enumerated() {
            _ = try await store.upsertSleepSessions([
                CachedSleepSession(startTs: t0 + i * 60, endTs: t0 + 8 * 3600 + i * 60,
                                   efficiency: 90, restingHr: 52, avgHrv: 45,
                                   stagesJSON: "[{\"s\":\(i)}]"),
            ], deviceId: dev)
        }
        _ = try await store.upsertAppleDaily([
            AppleDaily(day: "2026-06-01", steps: 9000, activeKcal: 500, basalKcal: 1600, vo2max: 40,
                       avgHr: 62, maxHr: 150, walkingHr: 90, weightKg: 80),
        ], deviceId: apple)
        for key in ["steps_est"] {
            _ = try await store.upsertMetricSeries([MetricPoint(day: "2026-06-01", key: key, value: 8500)],
                                                   deviceId: comp)
        }
        for key in ["sleep_performance", "sleep_consistency", "sleep_need_min", "sleep_debt_min"] {
            _ = try await store.upsertMetricSeries([MetricPoint(day: "2026-06-01", key: key, value: 77)],
                                                   deviceId: strap)
        }
    }

    private func request(includeApple: Bool = true, includeWhoop: Bool = true,
                         fromDay: String = "2026-05-30", toDay: String = "2026-06-03",
                         fromTs: Int? = nil, toTs: Int? = nil) -> DashboardReadRequest {
        DashboardReadRequest(strapDeviceId: strap, computedDeviceId: comp, appleDeviceId: apple,
                             fromDay: fromDay, toDay: toDay,
                             fromTs: fromTs ?? (t0 - 86_400), toTs: toTs ?? (t0 + 3 * 86_400),
                             sleepLimit: 4000, includeApple: includeApple,
                             includeWhoopSeries: includeWhoop)
    }

    func testSnapshotMatchesIndividualAccessorsFieldByField() async throws {
        let store = try await CenitStore.inMemory()
        try await seed(store)
        let req = request()
        let snap = try await store.dashboardSnapshot(req)

        let importedDays = try await store.dailyMetrics(deviceId: strap, from: req.fromDay, to: req.toDay)
        let computedDays = try await store.dailyMetrics(deviceId: comp, from: req.fromDay, to: req.toDay)
        let appleDays = try await store.dailyMetrics(deviceId: apple, from: req.fromDay, to: req.toDay)
        XCTAssertEqual(snap.importedDays, importedDays)
        XCTAssertEqual(snap.computedDays, computedDays)
        XCTAssertEqual(snap.appleDays, appleDays)
        XCTAssertFalse(snap.importedDays.isEmpty)

        let impSleeps = try await store.sleepSessions(deviceId: strap, from: req.fromTs, to: req.toTs, limit: req.sleepLimit)
        let compSleeps = try await store.sleepSessions(deviceId: comp, from: req.fromTs, to: req.toTs, limit: req.sleepLimit)
        let appleSleeps = try await store.sleepSessions(deviceId: apple, from: req.fromTs, to: req.toTs, limit: req.sleepLimit)
        XCTAssertEqual(snap.importedSleeps, impSleeps)
        XCTAssertEqual(snap.computedSleeps, compSleeps)
        XCTAssertEqual(snap.appleSleeps, appleSleeps)
        XCTAssertFalse(snap.importedSleeps.isEmpty)

        let agg = try await store.appleDaily(deviceId: apple, from: req.fromDay, to: req.toDay)
        XCTAssertEqual(snap.appleAgg, agg)
        XCTAssertFalse(snap.appleAgg.isEmpty)

        let steps = try await store.metricSeries(deviceId: comp, key: "steps_est", from: req.fromDay, to: req.toDay)
        XCTAssertEqual(snap.stepsEst, steps)
        for (got, key) in [(snap.sleepPerformance, "sleep_performance"),
                           (snap.sleepConsistency, "sleep_consistency"),
                           (snap.sleepNeed, "sleep_need_min"),
                           (snap.sleepDebt, "sleep_debt_min")] {
            let expected = try await store.metricSeries(deviceId: strap, key: key, from: req.fromDay, to: req.toDay)
            XCTAssertEqual(got, expected)
            XCTAssertFalse(got.isEmpty, key)
        }
    }

    func testSnapshotGatesAppleAndWhoopSeries() async throws {
        let store = try await CenitStore.inMemory()
        try await seed(store)

        let noApple = try await store.dashboardSnapshot(request(includeApple: false))
        XCTAssertTrue(noApple.appleSleeps.isEmpty)
        XCTAssertTrue(noApple.appleAgg.isEmpty)
        XCTAssertFalse(noApple.appleDays.isEmpty,
                       "appleDays is NEVER gated — it feeds the FER-485 stored-coverage diagnostic")
        XCTAssertFalse(noApple.importedSleeps.isEmpty, "raw strap sleeps are never gated either")

        let noWhoop = try await store.dashboardSnapshot(request(includeWhoop: false))
        XCTAssertTrue(noWhoop.stepsEst.isEmpty)
        XCTAssertTrue(noWhoop.sleepPerformance.isEmpty)
        XCTAssertTrue(noWhoop.sleepConsistency.isEmpty)
        XCTAssertTrue(noWhoop.sleepNeed.isEmpty)
        XCTAssertTrue(noWhoop.sleepDebt.isEmpty)
        XCTAssertFalse(noWhoop.importedDays.isEmpty, "day rows themselves are not gated")
    }

    func testSnapshotWindowBoundsMatchAccessors() async throws {
        let store = try await CenitStore.inMemory()
        try await seed(store)
        // Day window clipped to exactly one day; ts window clipped so only sessions overlapping it land.
        let req = request(fromDay: "2026-06-02", toDay: "2026-06-02",
                          fromTs: t0 + 9 * 3600, toTs: t0 + 10 * 3600)
        let snap = try await store.dashboardSnapshot(req)
        let days = try await store.dailyMetrics(deviceId: strap, from: "2026-06-02", to: "2026-06-02")
        XCTAssertEqual(snap.importedDays, days)
        XCTAssertEqual(snap.importedDays.map(\.day), ["2026-06-02"])
        let sleeps = try await store.sleepSessions(deviceId: strap, from: req.fromTs, to: req.toTs, limit: 4000)
        XCTAssertEqual(snap.importedSleeps, sleeps,
                       "overlap semantics (s <= to AND e >= from) must match the accessor exactly")
    }
}
