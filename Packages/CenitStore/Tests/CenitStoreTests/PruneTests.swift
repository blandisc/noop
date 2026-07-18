import XCTest
import BiometricStreams
@testable import CenitStore

final class PruneTests: XCTestCase {
    private let frames: [[UInt8]] = [[0xAA, 0x00, 0x01, 0x02]]
    private func meta(_ id: String, capturedAt: Int, bytes: Int) -> RawBatchMeta {
        RawBatchMeta(batchId: id, deviceId: "dev1",
                     clockRef: ClockRef(device: 0, wall: 0),
                     capturedAt: capturedAt, startTs: 0, endTs: 0,
                     frameCount: frames.count, byteSize: bytes)
    }

    func testPrunesAgedSyncedBatches() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        // synced long ago → pruned; synced recently → kept; unsynced → kept.
        try await store.enqueueRawBatch(meta("aged", capturedAt: 10, bytes: 100), frames: frames)
        try await store.enqueueRawBatch(meta("fresh", capturedAt: 20, bytes: 100), frames: frames)
        try await store.enqueueRawBatch(meta("unsynced", capturedAt: 30, bytes: 100), frames: frames)
        try await store.markRawBatchSynced(batchId: "aged", at: 1000)
        try await store.markRawBatchSynced(batchId: "fresh", at: 9500)

        let pruned = try await store.pruneRaw(now: 10000, keepWindowSeconds: 1000,
                                              maxUnsyncedBytes: 1_000_000)
        XCTAssertEqual(pruned, 1)                                  // only "aged"
        let remaining = try await store.allBatchIdsForTest()
        XCTAssertEqual(remaining, ["fresh", "unsynced"])
    }

    func testUnsyncedBatchesRetainedEvenWhenOverByteCap() async throws {
        // Policy 2 (drop-oldest-unsynced) was removed: unsynced raw is the sole copy of
        // unknown bytes post-trim and must never be dropped, regardless of maxUnsyncedBytes.
        let store = try await CenitStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        try await store.enqueueRawBatch(meta("u1", capturedAt: 10, bytes: 500), frames: frames)
        try await store.enqueueRawBatch(meta("u2", capturedAt: 20, bytes: 500), frames: frames)
        try await store.enqueueRawBatch(meta("u3", capturedAt: 30, bytes: 500), frames: frames)
        // Even with a tiny cap (1000 < 1500 total), all unsynced batches must be kept.
        let pruned = try await store.pruneRaw(now: 100, keepWindowSeconds: 0, maxUnsyncedBytes: 1000)
        XCTAssertEqual(pruned, 0)
        let ids = try await store.allBatchIdsForTest()
        XCTAssertEqual(ids, ["u1", "u2", "u3"])
    }

    func testPruneNeverTouchesDecodedTables() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        _ = try await store.insert(Streams(hr: [HRSample(ts: 1, bpm: 60)]), deviceId: "dev1")
        try await store.enqueueRawBatch(meta("aged", capturedAt: 10, bytes: 100), frames: frames)
        try await store.markRawBatchSynced(batchId: "aged", at: 1)
        _ = try await store.pruneRaw(now: 100000, keepWindowSeconds: 10, maxUnsyncedBytes: 0)
        let rowCounts = try await store.storageStats_rowCountsForTest()
        XCTAssertEqual(rowCounts.hr, 1)   // decoded untouched
    }

    func testNothingToPruneReturnsZero() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        try await store.enqueueRawBatch(meta("u1", capturedAt: 10, bytes: 100), frames: frames)
        let pruned = try await store.pruneRaw(now: 100, keepWindowSeconds: 1000,
                                              maxUnsyncedBytes: 1_000_000)
        XCTAssertEqual(pruned, 0)
    }

    func testPruneNeverDropsUnsyncedEvenOverCap() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        for i in 0..<3 {
            let m = RawBatchMeta(batchId: "b\(i)", deviceId: "dev1",
                                 clockRef: ClockRef(device: 0, wall: 0),
                                 capturedAt: i, startTs: 0, endTs: 0,
                                 frameCount: 1, byteSize: 1000)
            try await store.enqueueRawBatch(m, frames: [[0xAA]])
        }
        _ = try await store.pruneRaw(now: 10_000, keepWindowSeconds: 0, maxUnsyncedBytes: 1)
        let ids = try await store.allBatchIdsForTest()
        XCTAssertEqual(ids.count, 3, "unsynced raw must never be pruned")
    }
}
