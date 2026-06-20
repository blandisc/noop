import XCTest
import GRDB
@testable import WhoopStore

final class MigrationTests: XCTestCase {
    func testInMemoryRunsMigrations() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        for t in ["device", "hrSample", "rrInterval", "event", "battery", "rawBatch"] {
            XCTAssertTrue(tables.contains(t), "missing table \(t)")
        }
    }

    func testFileInitRunsMigrations() async throws {
        let path = NSTemporaryDirectory() + "whoopstore-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try await WhoopStore(path: path)
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("hrSample"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testHrSamplePrimaryKeyIsDeviceIdTs() async throws {
        let store = try await WhoopStore.inMemory()
        let cols = try await store.primaryKeyColumns("hrSample")
        XCTAssertEqual(cols, ["deviceId", "ts"])
    }

    func testRrIntervalPrimaryKeyIncludesRrMs() async throws {
        let store = try await WhoopStore.inMemory()
        let cols = try await store.primaryKeyColumns("rrInterval")
        XCTAssertEqual(cols, ["deviceId", "ts", "rrMs"])
    }

    /// v5 adds a `synced` column to all 8 decoded tables.
    func testV5AddsSyncedColumnToDecodedTables() async throws {
        let store = try await WhoopStore.inMemory()
        for table in ["hrSample", "rrInterval", "event", "battery",
                      "spo2Sample", "skinTempSample", "respSample", "gravitySample"] {
            let cols = try await store.columnNamesForTest(table: table)
            XCTAssertTrue(cols.contains("synced"), "\(table) missing synced column")
        }
        XCTAssertEqual(WhoopStoreInfo.schemaVersion, 14)
    }

    /// v12 (FER-307) creates the `experiment` table with `id` as the sole primary key.
    func testV12CreatesExperimentTable() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("experiment"), "missing experiment table")
        let pk = try await store.primaryKeyColumns("experiment")
        XCTAssertEqual(pk, ["id"])
        let cols = try await store.columnNamesForTest(table: "experiment")
        for expected in ["behavior", "outcome", "expectedSign", "startDay", "windowDays",
                         "status", "result", "createdAt"] {
            XCTAssertTrue(cols.contains(expected), "experiment missing column \(expected)")
        }
    }

    /// v14 (FER-370) creates `dietPlan` (PK `id`) and `dietAdherence` (PK `deviceId,day,mealId`).
    func testV14CreatesDietTables() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("dietPlan"), "missing dietPlan table")
        XCTAssertTrue(tables.contains("dietAdherence"), "missing dietAdherence table")

        let planPK = try await store.primaryKeyColumns("dietPlan")
        XCTAssertEqual(planPK, ["id"])
        let planCols = try await store.columnNamesForTest(table: "dietPlan")
        for expected in ["deviceId", "nombre", "idioma", "ciclo", "payloadJSON", "createdAt"] {
            XCTAssertTrue(planCols.contains(expected), "dietPlan missing column \(expected)")
        }

        let adherencePK = try await store.primaryKeyColumns("dietAdherence")
        XCTAssertEqual(adherencePK, ["deviceId", "day", "mealId"])
        let adherenceCols = try await store.columnNamesForTest(table: "dietAdherence")
        for expected in ["status", "note"] {
            XCTAssertTrue(adherenceCols.contains(expected), "dietAdherence missing column \(expected)")
        }
    }
}
