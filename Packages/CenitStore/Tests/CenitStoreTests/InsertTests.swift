import XCTest
import BiometricStreams
@testable import CenitStore

final class InsertTests: XCTestCase {
    private func sampleStreams() -> Streams {
        Streams(
            hr: [HRSample(ts: 1000, bpm: 60), HRSample(ts: 1001, bpm: 61)],
            rr: [RRInterval(ts: 1000, rrMs: 800), RRInterval(ts: 1000, rrMs: 820)],
            events: [StreamEvent(ts: 1736365593, kind: "BLE_CONNECTION_DOWN(12)",
                                payload: ["foo": .int(7), "bar": .string("x")])],
            battery: [BatterySample(ts: 1736365593, soc: 25.5, mv: nil)])
    }

    func testInsertReturnsRowCounts() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: "AA:BB", name: "Strap")
        let n = try await store.insert(sampleStreams(), deviceId: "dev1")
        XCTAssertEqual(n.hr, 2)
        XCTAssertEqual(n.rr, 2)
        XCTAssertEqual(n.events, 1)
        XCTAssertEqual(n.battery, 1)
    }

    func testInsertIsIdempotentByNaturalKey() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        _ = try await store.insert(sampleStreams(), deviceId: "dev1")
        let second = try await store.insert(sampleStreams(), deviceId: "dev1")
        // Same natural keys → nothing new inserted the second time.
        XCTAssertEqual(second.hr, 0)
        XCTAssertEqual(second.rr, 0)
        XCTAssertEqual(second.events, 0)
        XCTAssertEqual(second.battery, 0)
        let stats = try await store.storageStats_rowCountsForTest()
        XCTAssertEqual(stats.hr, 2)
        XCTAssertEqual(stats.rr, 2)
        XCTAssertEqual(stats.events, 1)
        XCTAssertEqual(stats.battery, 1)
        XCTAssertEqual(stats.spo2, 0)
        XCTAssertEqual(stats.skinTemp, 0)
        XCTAssertEqual(stats.resp, 0)
        XCTAssertEqual(stats.gravity, 0)
    }

    func testUpsertDeviceUpdatesFields() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: "AA", name: "first")
        try await store.upsertDevice(id: "dev1", mac: "BB", name: "second")
        let row = try await store.deviceRowForTest(id: "dev1")
        XCTAssertEqual(row?.mac, "BB")
        XCTAssertEqual(row?.name, "second")
    }

    func testTwoDevicesAreIndependent() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDevice(id: "a", mac: nil, name: nil)
        try await store.upsertDevice(id: "b", mac: nil, name: nil)
        _ = try await store.insert(sampleStreams(), deviceId: "a")
        let nb = try await store.insert(sampleStreams(), deviceId: "b")
        XCTAssertEqual(nb.hr, 2)   // same ts/bpm but different deviceId → not a conflict
    }
}
