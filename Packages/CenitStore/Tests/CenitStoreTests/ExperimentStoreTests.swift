import XCTest
import GRDB
@testable import CenitStore

final class ExperimentStoreTests: XCTestCase {

    private func running(id: String, behavior: String = "Meditación",
                         outcome: String = "Recuperación", createdAt: Int) -> ExperimentRow {
        ExperimentRow(id: id, behavior: behavior, outcome: outcome, expectedSign: 1,
                      startDay: "2026-06-10", windowDays: 7, status: .running, createdAt: createdAt)
    }

    func testInsertAndReadRoundtrip() async throws {
        let store = try await CenitStore.inMemory()
        let row = running(id: "e1", createdAt: 1000)
        try await store.upsertExperiment(row, deviceId: "devA")

        let active = try await store.activeExperiment(deviceId: "devA")
        XCTAssertEqual(active, row)

        let all = try await store.experiments(deviceId: "devA")
        XCTAssertEqual(all, [row])
    }

    func testUpsertWritesBackVerdictOnCompletion() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertExperiment(running(id: "e1", createdAt: 1000), deviceId: "devA")

        let completed = ExperimentRow(
            id: "e1", behavior: "Meditación", outcome: "Recuperación", expectedSign: 1,
            startDay: "2026-06-10", windowDays: 7, status: .completed, result: "sustained",
            effectDelta: 6.2, effectSize: 0.8, pValue: 0.01, nWith: 6, nWithout: 40,
            createdAt: 1000, decidedAt: 2000)
        try await store.upsertExperiment(completed, deviceId: "devA")

        // Same id ⇒ one row, now completed; no longer the active running experiment.
        let all = try await store.experiments(deviceId: "devA")
        XCTAssertEqual(all, [completed])
        let active = try await store.activeExperiment(deviceId: "devA")
        XCTAssertNil(active)
    }

    func testActiveReturnsMostRecentRunningAndIsSourceScoped() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertExperiment(running(id: "old", createdAt: 1000), deviceId: "devA")
        try await store.upsertExperiment(running(id: "new", createdAt: 2000), deviceId: "devA")
        try await store.upsertExperiment(running(id: "other", createdAt: 3000), deviceId: "devB")

        let active = try await store.activeExperiment(deviceId: "devA")
        XCTAssertEqual(active?.id, "new")
        // devB's experiment never leaks into devA.
        let idsA = try await store.experiments(deviceId: "devA").map(\.id)
        XCTAssertEqual(idsA, ["new", "old"])
    }

    func testNoActiveWhenEmpty() async throws {
        let store = try await CenitStore.inMemory()
        let active = try await store.activeExperiment(deviceId: "devA")
        XCTAssertNil(active)
    }
}
