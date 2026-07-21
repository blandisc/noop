import XCTest
import BiometricStreams
@testable import CenitStore

final class InsertTests: XCTestCase {
    private func sampleStreams() -> Streams {
        Streams(
            hr: [HRSample(ts: 1000, bpm: 60), HRSample(ts: 1001, bpm: 61)],
            rr: [RRInterval(ts: 1000, rrMs: 800), RRInterval(ts: 1000, rrMs: 820)])
    }

    func testInsertReturnsRowCounts() async throws {
        let store = try await CenitStore.inMemory()
        let n = try await store.insert(sampleStreams(), deviceId: "dev1")
        XCTAssertEqual(n.hr, 2)
        XCTAssertEqual(n.rr, 2)
    }

    func testInsertIsIdempotentByNaturalKey() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(sampleStreams(), deviceId: "dev1")
        let second = try await store.insert(sampleStreams(), deviceId: "dev1")
        // Same natural keys → nothing new inserted the second time.
        XCTAssertEqual(second.hr, 0)
        XCTAssertEqual(second.rr, 0)
        let stats = try await store.sampleCounts()
        XCTAssertEqual(stats.hr, 2)
        XCTAssertEqual(stats.rr, 2)
    }

    func testTwoDevicesAreIndependent() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(sampleStreams(), deviceId: "a")
        let nb = try await store.insert(sampleStreams(), deviceId: "b")
        XCTAssertEqual(nb.hr, 2)   // same ts/bpm but different deviceId → not a conflict
    }
}
