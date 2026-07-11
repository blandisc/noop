import XCTest
import WhoopProtocol
@testable import WhoopStore

/// FER-868 — `streamDayCounts`, the per-local-day COUNT signature feeding the incremental engine.
final class StreamDayCountsTests: XCTestCase {

    /// CST (UTC−6): the tz the local-day bucketing must honor.
    private let tz = -6 * 3_600
    /// 2026-07-08 00:00:00 LOCAL (CST) as a unix ts.
    private let d0 = 1_782_885_600

    private func localDay(_ ts: Int) -> Int { (ts + tz) / 86_400 }

    private func seed(_ store: WhoopStore) async throws {
        // Three local days: hr on all three, gravity on day 0, steps on day 1.
        // Day 0 gets an hr sample at 23:30 LOCAL (05:30 UTC of the NEXT utc-day) — the case a
        // UTC bucketing would misfile.
        var streams = Streams()
        streams.hr = [
            HRSample(ts: d0 + 8 * 3_600, bpm: 60),
            HRSample(ts: d0 + 23 * 3_600 + 1_800, bpm: 58),      // 23:30 local, next day in UTC
            HRSample(ts: d0 + 86_400 + 3_600, bpm: 62),          // day 1
            HRSample(ts: d0 + 2 * 86_400 + 3_600, bpm: 64),      // day 2
        ]
        streams.gravity = [GravitySample(ts: d0 + 9 * 3_600, x: 0, y: 0, z: 1)]
        streams.steps = [StepSample(ts: d0 + 86_400 + 7_200, counter: 100)]
        _ = try await store.insert(streams, deviceId: "dev1")
    }

    func testCountsPerLocalDayWithNonZeroTz() async throws {
        let store = try await WhoopStore.inMemory()
        try await seed(store)
        let counts = try await store.streamDayCounts(deviceId: "dev1", from: 0, tzOffsetSeconds: tz)
        let day0 = localDay(d0), day1 = day0 + 1, day2 = day0 + 2
        XCTAssertEqual(counts["hr"], [day0: 2, day1: 1, day2: 1],
                       "the 23:30-local sample must land on its LOCAL day, not the UTC one")
        XCTAssertEqual(counts["gravity"], [day0: 1])
        XCTAssertEqual(counts["steps"], [day1: 1], "stepSample (TEXT deviceId) must be counted too")
        XCTAssertEqual(counts["rr"], [:])
        XCTAssertEqual(counts["resp"], [:])
        XCTAssertEqual(counts["skinTemp"], [:])
    }

    func testExactDuplicateDoesNotChangeCounts() async throws {
        let store = try await WhoopStore.inMemory()
        try await seed(store)
        let before = try await store.streamDayCounts(deviceId: "dev1", from: 0, tzOffsetSeconds: tz)
        try await seed(store)   // ON CONFLICT DO NOTHING → identical rows insert nothing
        let after = try await store.streamDayCounts(deviceId: "dev1", from: 0, tzOffsetSeconds: tz)
        XCTAssertEqual(before, after)
    }

    func testNewRowOnOldDayRaisesItsCount() async throws {
        let store = try await WhoopStore.inMemory()
        try await seed(store)
        // A backfill fills a GAP in day 0: new ts, same old day. MAX(ts) over the store is unmoved;
        // the count is not — this is exactly why the signature is COUNT-based.
        _ = try await store.insert(Streams(hr: [HRSample(ts: d0 + 12 * 3_600, bpm: 70)]), deviceId: "dev1")
        let counts = try await store.streamDayCounts(deviceId: "dev1", from: 0, tzOffsetSeconds: tz)
        XCTAssertEqual(counts["hr"]?[localDay(d0)], 3)
    }

    func testFromBoundExcludesOlderRows() async throws {
        let store = try await WhoopStore.inMemory()
        try await seed(store)
        let counts = try await store.streamDayCounts(deviceId: "dev1", from: d0 + 86_400,
                                                     tzOffsetSeconds: tz)
        XCTAssertNil(counts["hr"]?[localDay(d0)], "rows before `from` must not be counted")
        XCTAssertEqual(counts["hr"]?[localDay(d0) + 1], 1)
    }

    func testUnknownDeviceHasNoIntStreamCounts() async throws {
        let store = try await WhoopStore.inMemory()
        let counts = try await store.streamDayCounts(deviceId: "ghost", from: 0, tzOffsetSeconds: 0)
        XCTAssertNil(counts["hr"])
        XCTAssertEqual(counts["steps"], [:])
    }
}
