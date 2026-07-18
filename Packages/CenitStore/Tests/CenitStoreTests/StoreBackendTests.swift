import XCTest
import BiometricStreams
@testable import CenitStore

/// FER-970 (R-04) — the Repository handle opens a `DatabasePool`; the default `.queue` backend
/// stays byte-identical. These pin: pool opens+migrates, pool == queue field-by-field on the
/// dashboard read, the WAL checkpoint barrier works on a pool, and — the point of the change —
/// a snapshot read on the pool does NOT wait for a long write holding the actor's executor.
final class StoreBackendTests: XCTestCase {

    private func tmpPath(_ tag: String) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("whoop-backend-\(tag)-\(UUID().uuidString).sqlite").path
    }

    private func seed(_ store: CenitStore) async throws {
        _ = try await store.upsertDailyMetrics([
            DailyMetric(day: "2026-06-01", totalSleepMin: 400, efficiency: 88, deepMin: 70,
                        remMin: 90, lightMin: 200, disturbances: 2, restingHr: 55, avgHrv: 40,
                        recovery: 60, strain: 9.5, exerciseCount: 1, spo2Pct: 96, respRateBpm: 14),
        ], deviceId: "my-whoop")
        _ = try await store.upsertSleepSessions([
            CachedSleepSession(startTs: 1_780_272_000, endTs: 1_780_300_800, efficiency: 90,
                               restingHr: 52, avgHrv: 45, stagesJSON: "[]"),
        ], deviceId: "my-whoop")
    }

    private func request() -> DashboardReadRequest {
        DashboardReadRequest(strapDeviceId: "my-whoop", computedDeviceId: "my-whoop-noop",
                             appleDeviceId: "apple-health", fromDay: "2026-05-30", toDay: "2026-06-03",
                             fromTs: 1_780_185_600, toTs: 1_780_531_200,
                             sleepLimit: 4000, includeApple: true, includeWhoopSeries: true)
    }

    func testPoolInitRunsMigrations() async throws {
        let path = tmpPath("pool-init")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try await CenitStore(path: path, backend: .pool(maxReaders: 2))
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("dailyMetric"))
        XCTAssertTrue(tables.contains("hrSample"))
        try await seed(store)
        let days = try await store.dailyMetrics(deviceId: "my-whoop", from: "2026-06-01", to: "2026-06-01")
        XCTAssertEqual(days.count, 1)
    }

    func testPoolBackendMatchesQueueBackendFieldByField() async throws {
        let queuePath = tmpPath("q"), poolPath = tmpPath("p")
        defer {
            try? FileManager.default.removeItem(atPath: queuePath)
            try? FileManager.default.removeItem(atPath: poolPath)
        }
        let queueStore = try await CenitStore(path: queuePath)                       // default .queue
        let poolStore = try await CenitStore(path: poolPath, backend: .pool(maxReaders: 2))
        try await seed(queueStore)
        try await seed(poolStore)
        let a = try await queueStore.dashboardSnapshot(request())
        let b = try await poolStore.dashboardSnapshot(request())
        XCTAssertEqual(a.importedDays, b.importedDays)
        XCTAssertEqual(a.importedSleeps, b.importedSleeps)
        XCTAssertEqual(a.computedDays, b.computedDays)
        XCTAssertEqual(a.appleDays, b.appleDays)
        XCTAssertFalse(a.importedDays.isEmpty)
    }

    func testCheckpointWALSucceedsOnPool() async throws {
        let path = tmpPath("ckpt")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try await CenitStore(path: path, backend: .pool(maxReaders: 2))
        try await seed(store)
        _ = try await store.dashboardSnapshot(request())   // a reader existed and is closed
        try await store.checkpointWAL()
    }

    /// The point of R-04: while a long write holds the actor's executor (and, on a queue, the
    /// single connection), the pool's snapshot read is served by a reader connection and returns
    /// with the pre-write data well before the write finishes. Generous margins for CI.
    func testSnapshotReadDoesNotWaitForLongWriteOnPool() async throws {
        let path = tmpPath("concurrent")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try await CenitStore(path: path, backend: .pool(maxReaders: 2))
        try await seed(store)

        let writer = Task {
            try await store.syncWrite { db in
                try db.execute(sql: "INSERT INTO dailyMetric (deviceId, day) VALUES ('slow', '2026-06-09')")
                Thread.sleep(forTimeInterval: 1.0)   // hold the write transaction open
            }
        }
        try await Task.sleep(nanoseconds: 100_000_000)   // let the write start

        let t0 = Date()
        let snap = try await store.dashboardSnapshot(request())
        let elapsed = Date().timeIntervalSince(t0)

        XCTAssertLessThan(elapsed, 0.5,
                          "a pool read must not queue behind the long write (took \(elapsed)s)")
        XCTAssertEqual(snap.importedDays.count, 1, "the reader sees the pre-write snapshot")
        _ = try await writer.value
    }
}
