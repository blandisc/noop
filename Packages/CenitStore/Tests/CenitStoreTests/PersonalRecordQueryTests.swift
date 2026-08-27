import XCTest
@testable import CenitStore
import StrandTraining

/// FER-171 · Parte A — las 3 consultas nuevas de `personalRecord` que el hub v18 necesita
/// («Marcas · N en mes» y «antes X · hace N días»). Sin tabla propia de historial de PRs
/// (`personalRecord` solo guarda el mejor VIGENTE por ejercicio+métrica), así que las pruebas
/// guardan sesiones reales vía `saveSession` — el mismo camino de producción que deriva los PRs —
/// en vez de insertar filas crudas que se saltarían esa lógica.
final class PersonalRecordQueryTests: XCTestCase {

    /// Una sesión de un solo set de trabajo hecho, para un ejercicio/peso/ts dados. `reps: nil`
    /// para que SOLO el candidato `maxWeight` nazca de ese set (ni `maxReps` ni `maxVolume`
    /// requieren reps) — así cada fixture produce exactamente el PR que la prueba necesita.
    private func saveWeightSet(_ store: CenitStore, sessionId: String, exerciseId: String,
                               weightKg: Double, ts: Int) async throws {
        let session = StrengthSession(id: sessionId, startTs: ts, endTs: ts + 60)
        let set = SetEntry(id: "\(sessionId)-set", sessionId: sessionId, exerciseId: exerciseId,
                           position: 0, kind: .work, weightKg: weightKg, reps: nil, done: true, ts: ts)
        try await store.saveSession(session, sets: [set])
    }

    // MARK: - latestPersonalRecord

    func testLatestPersonalRecordWithTwoPRsReturnsTheOneWithGreaterTs() async throws {
        let store = try await CenitStore.inMemory()
        try await saveWeightSet(store, sessionId: "s1", exerciseId: "squat", weightKg: 100, ts: 1_000)
        try await saveWeightSet(store, sessionId: "s2", exerciseId: "bench", weightKg: 80, ts: 2_000)

        let latest = try await store.latestPersonalRecord()
        XCTAssertEqual(latest?.exerciseId, "bench")
        XCTAssertEqual(latest?.ts, 2_000)
    }

    func testLatestPersonalRecordNilWhenEmpty() async throws {
        let store = try await CenitStore.inMemory()
        let latest = try await store.latestPersonalRecord()
        XCTAssertNil(latest)
    }

    // MARK: - personalRecordCount

    func testPersonalRecordCountRespectsSinceTs() async throws {
        let store = try await CenitStore.inMemory()
        try await saveWeightSet(store, sessionId: "s1", exerciseId: "squat", weightKg: 100, ts: 1_000)
        try await saveWeightSet(store, sessionId: "s2", exerciseId: "bench", weightKg: 80, ts: 2_000)
        try await saveWeightSet(store, sessionId: "s3", exerciseId: "deadlift", weightKg: 140, ts: 3_000)

        let fromZero = try await store.personalRecordCount(sinceTs: 0)
        let from1500 = try await store.personalRecordCount(sinceTs: 1_500)
        let from3000 = try await store.personalRecordCount(sinceTs: 3_000)
        let from3001 = try await store.personalRecordCount(sinceTs: 3_001)
        XCTAssertEqual(fromZero, 3)
        XCTAssertEqual(from1500, 2)
        XCTAssertEqual(from3000, 1, "el límite es inclusivo")
        XCTAssertEqual(from3001, 0)
    }

    // MARK: - previousPersonalRecord

    func testPreviousPersonalRecordFindsTheEarlierWeightBeforeTheCurrentPR() async throws {
        let store = try await CenitStore.inMemory()
        // «antes 100.0 · hace 2 días»: la marca vigente es 102.5 @ ts=2000; la anterior es 100.0 @ ts=1000.
        try await saveWeightSet(store, sessionId: "s1", exerciseId: "squat", weightKg: 100, ts: 1_000)
        try await saveWeightSet(store, sessionId: "s2", exerciseId: "squat", weightKg: 102.5, ts: 2_000)

        let current = try await store.personalRecords(exerciseId: "squat").first { $0.metric == .maxWeight }
        XCTAssertEqual(current?.valueKg, 102.5)
        XCTAssertEqual(current?.ts, 2_000)

        let previous = try await store.previousPersonalRecord(exerciseId: "squat", metric: .maxWeight,
                                                               beforeTs: Double(current!.ts))
        XCTAssertEqual(previous?.valueKg, 100)
        XCTAssertEqual(previous?.ts, 1_000)
    }

    func testPreviousPersonalRecordIgnoresOtherMetricAndOtherExercise() async throws {
        let store = try await CenitStore.inMemory()
        try await saveWeightSet(store, sessionId: "s1", exerciseId: "squat", weightKg: 100, ts: 1_000)
        try await saveWeightSet(store, sessionId: "s2", exerciseId: "squat", weightKg: 102.5, ts: 2_000)

        // Otro ejercicio con peso más alto y ts anterior: NO debe filtrarse dentro de "squat".
        try await saveWeightSet(store, sessionId: "s3", exerciseId: "bench", weightKg: 999, ts: 1_500)

        // Una serie de "squat" que solo aporta reps (candidata a maxReps, no a maxWeight): tampoco
        // debe filtrarse cuando se pide la métrica maxWeight.
        let repsSet = SetEntry(id: "s4-set", sessionId: "s4", exerciseId: "squat", position: 0,
                               kind: .work, weightKg: nil, reps: 20, done: true, ts: 1_800)
        try await store.saveSession(StrengthSession(id: "s4", startTs: 1_800, endTs: 1_860),
                                    sets: [repsSet])

        let previous = try await store.previousPersonalRecord(exerciseId: "squat", metric: .maxWeight,
                                                               beforeTs: 2_000)
        XCTAssertEqual(previous?.exerciseId, "squat")
        XCTAssertEqual(previous?.valueKg, 100, "ni el peso de \"bench\" ni la serie sin peso de \"squat\" cuentan")
        XCTAssertEqual(previous?.ts, 1_000)
    }

    func testPreviousPersonalRecordNilWhenNoneQualifies() async throws {
        let store = try await CenitStore.inMemory()
        try await saveWeightSet(store, sessionId: "s1", exerciseId: "squat", weightKg: 100, ts: 1_000)

        let previous = try await store.previousPersonalRecord(exerciseId: "squat", metric: .maxWeight,
                                                               beforeTs: 1_000)
        XCTAssertNil(previous, "ts < beforeTs es estricto: el único set tiene ts == beforeTs")
    }
}
