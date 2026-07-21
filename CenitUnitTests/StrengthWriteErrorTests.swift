import XCTest
import CenitStore
import StrandTraining

/// Pins the happy path of the strength write contract that now throws (L2-A1c):
/// `setExerciseTypeOverride` + re-read round-trips on a real store in tmp.
final class StrengthWriteErrorTests: XCTestCase {

    private var dir: URL!
    private var store: CenitStore!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("strength-write-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("test.sqlite").path
        store = try await CenitStore(path: path)
    }

    override func tearDown() async throws {
        store = nil
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    /// Happy-path pin of the throws write contract: set an override, re-read it, clear it.
    func testSetExerciseTypeOverrideRoundTrip() async throws {
        try await store.setExerciseTypeOverride("Plank", type: .time, ts: 1)
        let afterSet = try await store.exerciseTypeOverrides()
        XCTAssertEqual(afterSet["Plank"], .time)

        try await store.setExerciseTypeOverride("Plank", type: .bodyweight, ts: 2)
        let afterUpsert = try await store.exerciseTypeOverrides()
        XCTAssertEqual(afterUpsert.count, 1)
        XCTAssertEqual(afterUpsert["Plank"], .bodyweight)

        try await store.clearExerciseTypeOverride("Plank")
        let afterClear = try await store.exerciseTypeOverrides()
        XCTAssertTrue(afterClear.isEmpty)
    }
}
