import XCTest
@testable import Cenit

/// FER-973 (T-04) — the file-level core of backup import (`DataBackup.swapIn`, FER-969 · X-04):
/// the live DB is never absent mid-import, a failure leaves the original (and its WAL) intact,
/// and the happy path swaps + drops the stale WAL/SHM and leaves a rollback sidecar.
final class DataBackupSwapTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-swap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, _ contents: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try contents.data(using: .utf8)!.write(to: url)
        return url
    }

    func testHappyPathSwapsAndLeavesRollbackSidecar() throws {
        let db = try write("whoop.sqlite", "OLD")
        _ = try write("whoop.sqlite-wal", "OLD-WAL")
        _ = try write("whoop.sqlite-shm", "OLD-SHM")
        let source = try write("backup.sqlite", "NEW")

        let sidecar = try DataBackup.swapIn(source: source, dbPath: db.path)

        XCTAssertEqual(try String(contentsOf: db, encoding: .utf8), "NEW")
        XCTAssertEqual(try String(contentsOf: sidecar, encoding: .utf8), "OLD",
                       "the rollback sidecar preserves the replaced DB")
        XCTAssertFalse(FileManager.default.fileExists(atPath: db.path + "-wal"),
                       "the stale WAL is dropped AFTER the swap")
        XCTAssertFalse(FileManager.default.fileExists(atPath: db.path + "-shm"))
    }

    func testFreshInstallMovesBackupIntoPlace() throws {
        let source = try write("backup.sqlite", "NEW")
        let dbPath = dir.appendingPathComponent("whoop.sqlite").path

        let sidecar = try DataBackup.swapIn(source: source, dbPath: dbPath)

        XCTAssertEqual(try String(contentsOfFile: dbPath, encoding: .utf8), "NEW")
        XCTAssertEqual(sidecar.path, dbPath, "fresh install: the placeholder sidecar is the live path")
    }

    func testFailureMidImportLeavesOriginalAndItsWALIntact() throws {
        let db = try write("whoop.sqlite", "OLD")
        _ = try write("whoop.sqlite-wal", "OLD-WAL")
        // A source that cannot be copied (doesn't exist) fails the import BEFORE any removal.
        let ghost = dir.appendingPathComponent("no-such-backup.sqlite")

        XCTAssertThrowsError(try DataBackup.swapIn(source: ghost, dbPath: db.path))

        XCTAssertEqual(try String(contentsOf: db, encoding: .utf8), "OLD",
                       "the live DB is untouched by a failed import")
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: db.path + "-wal"), encoding: .utf8),
                       "OLD-WAL", "recent WAL commits survive a failed import")
    }
}
