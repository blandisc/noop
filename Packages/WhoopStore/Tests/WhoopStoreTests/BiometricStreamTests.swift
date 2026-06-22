import XCTest
import GRDB
import WhoopProtocol
@testable import WhoopStore

/// Task A: persistence for the 4 type-47 biometric streams (spo2/skinTemp/resp/gravity).
/// Real V24 values used so the round-trip mirrors the on-device decode.
final class BiometricStreamTests: XCTestCase {
    private func bioStreams() -> Streams {
        Streams(
            hr: [HRSample(ts: 1700000000, bpm: 63)],
            spo2: [SpO2Sample(ts: 1700000000, red: 18000, ir: 17000)],
            skinTemp: [SkinTempSample(ts: 1700000000, raw: 900)],
            resp: [RespSample(ts: 1700000000, raw: 3000)],
            gravity: [GravitySample(ts: 1700000000, x: 0.05, y: 0.10, z: 0.993734)])
    }

    // MARK: - v3 migration

    func testV3CreatesBiometricTables() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        for t in ["spo2Sample", "skinTempSample", "respSample", "gravitySample"] {
            XCTAssertTrue(tables.contains(t), "missing table \(t)")
        }
    }

    func testV3PrimaryKeysAreDeviceIdTs() async throws {
        let store = try await WhoopStore.inMemory()
        for t in ["spo2Sample", "skinTempSample", "respSample", "gravitySample"] {
            let cols = try await store.primaryKeyColumns(t)
            XCTAssertEqual(cols, ["deviceId", "ts"], "PK mismatch for \(t)")
        }
    }

    func testV3AppliesOnTopOfV1V2() async throws {
        // Building from a fresh DB runs v1 → v2 → v3 in order; assert old + new coexist.
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        for t in ["device", "hrSample", "rrInterval", "event", "battery", "rawBatch",
                  "cursors", "spo2Sample", "skinTempSample", "respSample", "gravitySample"] {
            XCTAssertTrue(tables.contains(t), "missing table \(t)")
        }
    }

    // MARK: - insert

    func testInsertReturnsBiometricCounts() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        let n = try await store.insert(bioStreams(), deviceId: "dev1")
        XCTAssertEqual(n.hr, 1)
        XCTAssertEqual(n.spo2, 0)   // spo2 is no longer persisted (FER-511)
        XCTAssertEqual(n.skinTemp, 1)
        XCTAssertEqual(n.resp, 1)
        XCTAssertEqual(n.gravity, 1)
    }

    func testInsertBiometricIsIdempotent() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        _ = try await store.insert(bioStreams(), deviceId: "dev1")
        let second = try await store.insert(bioStreams(), deviceId: "dev1")
        XCTAssertEqual(second.spo2, 0)
        XCTAssertEqual(second.skinTemp, 0)
        XCTAssertEqual(second.resp, 0)
        XCTAssertEqual(second.gravity, 0)
    }

    func testBackwardCompatHrRrOnly() async throws {
        // A Streams with no biometric arrays still inserts cleanly; new counts are 0.
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        let n = try await store.insert(
            Streams(hr: [HRSample(ts: 100, bpm: 60)],
                    rr: [RRInterval(ts: 100, rrMs: 800)]),
            deviceId: "dev1")
        XCTAssertEqual(n.hr, 1)
        XCTAssertEqual(n.rr, 1)
        XCTAssertEqual(n.spo2, 0)
        XCTAssertEqual(n.skinTemp, 0)
        XCTAssertEqual(n.resp, 0)
        XCTAssertEqual(n.gravity, 0)
    }

    // MARK: - reads

    func testBiometricReadsRoundTrip() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        try await store.upsertDevice(id: "other", mac: nil, name: nil)
        _ = try await store.insert(bioStreams(), deviceId: "dev1")
        // Decoy on another device — must never appear in dev1 reads.
        _ = try await store.insert(bioStreams(), deviceId: "other")

        let from = 0, to = 2_000_000_000, lim = 100
        // spo2 is no longer persisted (FER-511) → the round-trip read comes back empty.
        let spo2 = try await store.spo2Samples(deviceId: "dev1", from: from, to: to, limit: lim)
        XCTAssertEqual(spo2, [])

        let skin = try await store.skinTempSamples(deviceId: "dev1", from: from, to: to, limit: lim)
        XCTAssertEqual(skin, [SkinTempSample(ts: 1700000000, raw: 900)])

        let resp = try await store.respSamples(deviceId: "dev1", from: from, to: to, limit: lim)
        XCTAssertEqual(resp, [RespSample(ts: 1700000000, raw: 3000)])

        let grav = try await store.gravitySamples(deviceId: "dev1", from: from, to: to, limit: lim)
        XCTAssertEqual(grav, [GravitySample(ts: 1700000000, x: 0.05, y: 0.10, z: 0.993734)])
    }

    func testBiometricReadsRespectRangeAndScope() async throws {
        // Uses gravity (still persisted) to cover windowing + limit; spo2 is no longer stored (FER-511).
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        _ = try await store.insert(
            Streams(gravity: [GravitySample(ts: 100, x: 1, y: 0, z: 0),
                              GravitySample(ts: 200, x: 3, y: 0, z: 0),
                              GravitySample(ts: 300, x: 5, y: 0, z: 0)]),
            deviceId: "dev1")
        let windowed = try await store.gravitySamples(deviceId: "dev1", from: 150, to: 250, limit: 100)
        XCTAssertEqual(windowed, [GravitySample(ts: 200, x: 3, y: 0, z: 0)])  // inclusive
        let limited = try await store.gravitySamples(deviceId: "dev1", from: 0, to: 1000, limit: 2)
        XCTAssertEqual(limited.count, 2)
        XCTAssertEqual(limited.first?.ts, 100)
    }

    /// FER-511: spo2 is decoded upstream but no longer stored. `insert()` reports 0 spo2 inserts, the
    /// table stays empty, and a windowed read comes back empty — while the other biometric streams in
    /// the SAME `Streams` are still persisted.
    func testSpo2IsNotPersisted() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "dev1", mac: nil, name: nil)
        let n = try await store.insert(bioStreams(), deviceId: "dev1")
        XCTAssertEqual(n.spo2, 0, "spo2 must not be inserted")
        XCTAssertEqual(n.skinTemp, 1, "the other biometric streams are still stored")
        let counts = try await store.sampleCounts()
        XCTAssertEqual(counts.spo2, 0, "the spo2Sample table stays empty")
        XCTAssertEqual(counts.skinTemp, 1)
        let read = try await store.spo2Samples(deviceId: "dev1", from: 0, to: 2_000_000_000, limit: 100)
        XCTAssertTrue(read.isEmpty, "spo2Samples reads back empty (table is never written)")
    }
}
