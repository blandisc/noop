import XCTest
@testable import CenitStore

final class DietStoreTests: XCTestCase {

    private let dev = "dev-1"

    // MARK: - Plan

    func testUpsertAndReadActivePlanRoundTrips() async throws {
        let store = try await CenitStore.inMemory()
        let row = DietPlanRow(id: "p1", name: "Plan Dra. Pérez", language: "es", cycle: "diario",
                              payloadJSON: #"{"schema":"noop.diet.v1"}"#, createdAt: 1000)
        try await store.upsertDietPlan(row, deviceId: dev)

        let active = try await store.activeDietPlan(deviceId: dev)
        XCTAssertEqual(active, row)   // persists and reads back identical
    }

    func testActivePlanIsMostRecentByCreatedAt() async throws {
        let store = try await CenitStore.inMemory()
        let older = DietPlanRow(id: "p1", name: "Viejo", language: "es", cycle: "diario",
                                payloadJSON: "{}", createdAt: 1000)
        let newer = DietPlanRow(id: "p2", name: "Nuevo", language: "en", cycle: "diario",
                                payloadJSON: "{}", createdAt: 2000)
        try await store.upsertDietPlan(older, deviceId: dev)
        try await store.upsertDietPlan(newer, deviceId: dev)

        let activeId = try await store.activeDietPlan(deviceId: dev)?.id
        XCTAssertEqual(activeId, "p2")
    }

    func testUpsertPlanByIdIsIdempotent() async throws {
        let store = try await CenitStore.inMemory()
        let v1 = DietPlanRow(id: "p1", name: "A", language: "es", cycle: "diario",
                             payloadJSON: "{}", createdAt: 1000)
        let v2 = DietPlanRow(id: "p1", name: "B", language: "en", cycle: "diario",
                             payloadJSON: #"{"x":1}"#, createdAt: 1500)
        try await store.upsertDietPlan(v1, deviceId: dev)
        try await store.upsertDietPlan(v2, deviceId: dev)   // same id → update in place

        let active = try await store.activeDietPlan(deviceId: dev)
        XCTAssertEqual(active, v2)
        // Still a single row (active is the only plan).
        XCTAssertEqual(active?.name, "B")
    }

    func testActivePlanIsScopedByDevice() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDietPlan(
            DietPlanRow(id: "p1", name: "A", language: "es", cycle: "diario",
                        payloadJSON: "{}", createdAt: 1000), deviceId: dev)
        let other = try await store.activeDietPlan(deviceId: "other-device")
        XCTAssertNil(other)
    }

    // MARK: - Adherence

    func testUpsertAndReadAdherence() async throws {
        let store = try await CenitStore.inMemory()
        let day = "2026-06-20"
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: day, mealId: "desayuno", status: .cumpli), deviceId: dev)
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: day, mealId: "comida", status: .sustitui, note: "fruta por nuez"),
            deviceId: dev)

        let rows = try await store.dietAdherence(deviceId: dev, day: day)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.mealId), ["comida", "desayuno"])   // ordered by mealId
        XCTAssertEqual(rows.first(where: { $0.mealId == "comida" })?.status, .sustitui)
        XCTAssertEqual(rows.first(where: { $0.mealId == "comida" })?.note, "fruta por nuez")
    }

    func testAdherenceUpsertIsIdempotentByNaturalKey() async throws {
        let store = try await CenitStore.inMemory()
        let day = "2026-06-20"
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: day, mealId: "cena", status: .salte), deviceId: dev)
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: day, mealId: "cena", status: .cumpli), deviceId: dev)  // overwrite

        let rows = try await store.dietAdherence(deviceId: dev, day: day)
        XCTAssertEqual(rows.count, 1)                 // not duplicated
        XCTAssertEqual(rows.first?.status, .cumpli)   // latest wins
    }

    func testAdherenceIsScopedByDay() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: "2026-06-20", mealId: "desayuno", status: .cumpli), deviceId: dev)
        let nextDay = try await store.dietAdherence(deviceId: dev, day: "2026-06-21")
        XCTAssertTrue(nextDay.isEmpty)
    }

    // MARK: - Delete

    func testDeleteAllDietAdherenceClearsPartitionOnly() async throws {
        let store = try await CenitStore.inMemory()
        let dayA = "2026-06-20"
        let dayB = "2026-06-21"
        let other = "dev-other"

        // Target partition: multiple days/meals.
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: dayA, mealId: "desayuno", status: .cumpli), deviceId: dev)
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: dayA, mealId: "comida", status: .salte), deviceId: dev)
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: dayB, mealId: "cena", status: .sustitui), deviceId: dev)
        // Other partition must survive.
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: dayA, mealId: "desayuno", status: .cumpli), deviceId: other)

        try await store.deleteAllDietAdherence(deviceId: dev)

        let a1 = try await store.dietAdherence(deviceId: dev, day: dayA)
        let a2 = try await store.dietAdherence(deviceId: dev, day: dayB)
        XCTAssertTrue(a1.isEmpty, "all adherence for target device must be gone")
        XCTAssertTrue(a2.isEmpty, "all days for target device must be gone")

        let otherRows = try await store.dietAdherence(deviceId: other, day: dayA)
        XCTAssertEqual(otherRows.count, 1, "other device partition must not be touched")
        XCTAssertEqual(otherRows.first?.mealId, "desayuno")
    }
}
