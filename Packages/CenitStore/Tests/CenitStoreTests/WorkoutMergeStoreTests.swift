import XCTest
@testable import CenitStore

/// FER-34 — integration coverage for the storage contract behind the cross-source workout merge.
///
/// The app's `Repository.workoutRows()` unions workouts from THREE device buckets — the imported
/// strap (`my-whoop`), Apple Health (`apple-health`), and the on-device detector (`my-whoop-noop`) —
/// then filters dismissed detected spans and sorts. That union/filter glue lives in the app target
/// (no CI test host), but it rests entirely on this store contract: per-`deviceId` isolation, range
/// reads, and source-scoped deletes. These pin that contract end to end against a real store so a
/// regression that would silently break the merge is caught here.
final class WorkoutMergeStoreTests: XCTestCase {

    private let strap = "my-whoop"
    private let apple = "apple-health"
    private let detected = "my-whoop-noop"   // computedDeviceId == deviceId + "-noop"

    private func wk(_ start: Int, _ durMin: Int, sport: String, source: String) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: start + durMin * 60, sport: sport, source: source,
                   durationS: Double(durMin) * 60, energyKcal: nil, avgHr: nil, maxHr: nil,
                   strain: nil, distanceM: nil, zonesJSON: nil, notes: nil)
    }

    /// Read all three buckets over one window and combine, the way the app's merge does.
    private func union(_ store: CenitStore, from: Int, to: Int) async throws -> [WorkoutRow] {
        var rows = try await store.workouts(deviceId: strap, from: from, to: to, limit: 5000)
        rows += try await store.workouts(deviceId: apple, from: from, to: to, limit: 5000)
        rows += try await store.workouts(deviceId: detected, from: from, to: to, limit: 5000)
        return rows
    }

    func testThreeSourceBucketsCoexistAndUnionInOneWindow() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertWorkouts([wk(1_000, 40, sport: "Run", source: "whoop")], deviceId: strap)
        try await store.upsertWorkouts([wk(2_000, 30, sport: "Walk", source: "apple_health")], deviceId: apple)
        try await store.upsertWorkouts([wk(3_000, 20, sport: "detected", source: detected)], deviceId: detected)

        // Each bucket is independently readable (no cross-bleed)...
        let strapRows = try await store.workouts(deviceId: strap, from: 0, to: 100_000, limit: 100)
        let appleRows = try await store.workouts(deviceId: apple, from: 0, to: 100_000, limit: 100)
        let detectedRows = try await store.workouts(deviceId: detected, from: 0, to: 100_000, limit: 100)
        XCTAssertEqual(strapRows.map(\.sport), ["Run"])
        XCTAssertEqual(appleRows.map(\.sport), ["Walk"])
        XCTAssertEqual(detectedRows.map(\.sport), ["detected"])

        // ...and the union over the window holds all three (the merge's raw input set).
        let all = try await union(store, from: 0, to: 100_000)
        XCTAssertEqual(Set(all.map(\.sport)), ["Run", "Walk", "detected"])
        XCTAssertEqual(all.count, 3)
    }

    func testIdenticalStartTsAcrossSourcesAreDistinctRows() async throws {
        // A detected bout and an imported workout at the SAME start must NOT collapse — the PK is
        // (deviceId, startTs, sport), so different source buckets keep both (the merge shows each).
        let store = try await CenitStore.inMemory()
        try await store.upsertWorkouts([wk(5_000, 30, sport: "Run", source: "whoop")], deviceId: strap)
        try await store.upsertWorkouts([wk(5_000, 30, sport: "detected", source: detected)], deviceId: detected)
        let all = try await union(store, from: 0, to: 100_000)
        XCTAssertEqual(all.count, 2, "same startTs in different buckets are independent rows")
    }

    func testDeleteDetectedBucketLeavesStrapAndAppleUntouched() async throws {
        // dismiss/relabel deletes only the detected bucket's row for a span; the imported + Apple
        // rows overlapping that span must survive (the merge's source-scoped delete contract).
        let store = try await CenitStore.inMemory()
        try await store.upsertWorkouts([wk(8_000, 20, sport: "Run", source: "whoop")], deviceId: strap)
        try await store.upsertWorkouts([wk(8_000, 20, sport: "Activity", source: "apple_health")], deviceId: apple)
        try await store.upsertWorkouts([wk(8_000, 20, sport: "detected", source: detected)], deviceId: detected)

        let n = try await store.deleteWorkouts(deviceId: detected, sport: "detected", from: 8_000, to: 8_000)
        XCTAssertEqual(n, 1)
        let all = try await union(store, from: 0, to: 100_000)
        XCTAssertEqual(Set(all.map(\.sport)), ["Run", "Activity"], "only the detected row is gone")
    }

    func testWindowExcludesWorkoutsOutsideRange() async throws {
        // The merge reads a trailing window; rows outside it must not surface.
        let store = try await CenitStore.inMemory()
        try await store.upsertWorkouts([wk(1_000, 10, sport: "Old", source: "whoop"),
                                        wk(50_000, 10, sport: "Recent", source: "whoop")], deviceId: strap)
        let windowed = try await store.workouts(deviceId: strap, from: 40_000, to: 60_000, limit: 100)
        XCTAssertEqual(windowed.map(\.sport), ["Recent"])
    }
}
