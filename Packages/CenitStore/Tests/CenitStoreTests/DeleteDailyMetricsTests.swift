import XCTest
@testable import CenitStore

/// FER-226: the one-time day-key re-bucket prunes rows orphaned when their `day` was re-dated
/// UTC→local (e.g. the spurious future-in-local row) via `deleteDailyMetrics(deviceId:days:)`.
final class DeleteDailyMetricsTests: XCTestCase {
    private func day(_ d: String, recovery: Double) -> DailyMetric {
        DailyMetric(day: d, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil,
                    recovery: recovery, strain: nil, exerciseCount: nil, spo2Pct: nil,
                    skinTempDevC: nil, respRateBpm: nil, steps: nil, activeKcalEst: nil)
    }

    func testDeleteDailyMetricsRemovesOnlyNamedDaysForThatDevice() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        try await store.upsertDevice(id: "other", mac: nil, name: nil)
        // Three computed days; "2026-06-18" is the spurious future-in-local orphan to prune.
        _ = try await store.upsertDailyMetrics(
            [day("2026-06-16", recovery: 60), day("2026-06-17", recovery: 61), day("2026-06-18", recovery: 62)],
            deviceId: "dev1")
        // A same-day row on another device must survive — the delete is device-scoped.
        _ = try await store.upsertDailyMetrics([day("2026-06-18", recovery: 99)], deviceId: "other")

        let deleted = try await store.deleteDailyMetrics(deviceId: "dev1", days: ["2026-06-18"])
        XCTAssertEqual(deleted, 1)

        let dev1 = try await store.dailyMetrics(deviceId: "dev1", from: "2026-01-01", to: "2026-12-31")
        XCTAssertEqual(dev1.map(\.day), ["2026-06-16", "2026-06-17"])   // orphan gone, the rest intact
        let other = try await store.dailyMetrics(deviceId: "other", from: "2026-01-01", to: "2026-12-31")
        XCTAssertEqual(other.map(\.day), ["2026-06-18"])                // untouched on the other device
    }

    func testDeleteDailyMetricsEmptyListIsNoOp() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        _ = try await store.upsertDailyMetrics([day("2026-06-17", recovery: 61)], deviceId: "dev1")
        let deleted = try await store.deleteDailyMetrics(deviceId: "dev1", days: [])
        XCTAssertEqual(deleted, 0)
        let rows = try await store.dailyMetrics(deviceId: "dev1", from: "2026-01-01", to: "2026-12-31")
        XCTAssertEqual(rows.count, 1)
    }
}
