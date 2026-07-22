import XCTest
import BiometricStreams
@testable import CenitStore

final class ReadTests: XCTestCase {
    private func seeded() async throws -> CenitStore {
        let store = try await CenitStore.inMemory()
        let s = Streams(
            hr: [HRSample(ts: 100, bpm: 60), HRSample(ts: 200, bpm: 61),
                 HRSample(ts: 300, bpm: 62)],
            rr: [RRInterval(ts: 100, rrMs: 800), RRInterval(ts: 100, rrMs: 820)])
        _ = try await store.insert(s, deviceId: "dev1")
        // Decoy on another device — must never appear in dev1 reads.
        _ = try await store.insert(Streams(hr: [HRSample(ts: 200, bpm: 99)]), deviceId: "other")
        return store
    }

    func testHrSamplesRangeOrderLimitAndDeviceScope() async throws {
        let store = try await seeded()
        let all = try await store.hrSamples(deviceId: "dev1", from: 0, to: 1000, limit: 100)
        XCTAssertEqual(all, [HRSample(ts: 100, bpm: 60), HRSample(ts: 200, bpm: 61),
                             HRSample(ts: 300, bpm: 62)])
        let windowed = try await store.hrSamples(deviceId: "dev1", from: 150, to: 250, limit: 100)
        XCTAssertEqual(windowed, [HRSample(ts: 200, bpm: 61)])     // inclusive range
        let limited = try await store.hrSamples(deviceId: "dev1", from: 0, to: 1000, limit: 2)
        XCTAssertEqual(limited.count, 2)                            // ascending, first 2
        XCTAssertEqual(limited.first?.ts, 100)
    }

    func testHrBucketsAveragePerBucketOrderedAndDeviceScoped() async throws {
        let store = try await seeded()
        // 200s buckets over dev1's ts 100/200/300 (bpm 60/61/62):
        //   ts100 → bucket 0   → mean 60
        //   ts200, ts300 → bucket 200 → mean (61+62)/2 = 61.5
        let buckets = try await store.hrBuckets(deviceId: "dev1", from: 0, to: 1000, bucketSeconds: 200)
        XCTAssertEqual(buckets, [HRBucket(ts: 0, bpm: 60), HRBucket(ts: 200, bpm: 61.5)])
        // The decoy on "other" (ts200, bpm99) must never bleed into dev1's bucket.
        let other = try await store.hrBuckets(deviceId: "other", from: 0, to: 1000, bucketSeconds: 200)
        XCTAssertEqual(other, [HRBucket(ts: 200, bpm: 99)])
    }

    func testRrIntervalsReturnsBothTiedRows() async throws {
        let store = try await seeded()
        let rr = try await store.rrIntervals(deviceId: "dev1", from: 0, to: 1000, limit: 100)
        XCTAssertEqual(rr, [RRInterval(ts: 100, rrMs: 800), RRInterval(ts: 100, rrMs: 820)])
    }
}
