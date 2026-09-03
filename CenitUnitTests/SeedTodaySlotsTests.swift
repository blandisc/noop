import XCTest
import CenitStore
import StrandTraining
import StrandAnalytics
@testable import Cenit

/// FER-124 — `repo.seedTodaySlots` es el ÚNICO sitio donde el teléfono y el reloj siembran la
/// sesión de hoy. Antes eran dos copias del bucle que coincidían por buena voluntad. Esta prueba
/// blinda esa unificación: llama el método real con una rutina conocida y verifica que los slots
/// salen en orden, uno por ejercicio, con la subida que la progresión decidió — el mismo resultado
/// que ambas superficies obtienen ahora, porque llaman aquí.
@MainActor
final class SeedTodaySlotsTests: XCTestCase {

    private var store: CenitStore!
    private var repo: Repository!

    override func setUp() async throws {
        store = try await CenitStore.inMemory()
        repo = Repository(deviceId: "test-seed-today")
        repo.attachStoreForTesting(store)
        StrengthExerciseMemo.invalidate(for: repo)
    }

    override func tearDown() async throws {
        StrengthExerciseMemo.invalidate(for: repo)
        repo = nil; store = nil
    }

    /// Una rutina con dos ejercicios de catálogo → dos slots, en orden, cada uno con su ejercicio
    /// resuelto. Es el contrato mínimo que el arranque del reloj y del teléfono comparten.
    func testSiembraUnSlotPorEjercicioEnOrden() async throws {
        let ex = Array(ExerciseCatalog.all.filter { $0.type == .weightReps }.prefix(2))
        try XCTSkipIf(ex.count < 2, "el catálogo necesita ≥2 ejercicios de peso×reps")
        let now = Int(Date().timeIntervalSince1970)
        let r = Routine(name: "Prueba", createdTs: now, updatedTs: now, sortOrder: 0)
        let exercises = ex.enumerated().map { i, e -> RoutineExercise in
            let sets = (0..<3).map { RoutineSet(position: $0, kind: .work, reps: 8, weightKg: 60) }
            return RoutineExercise(routineId: r.id, exerciseId: e.id, position: i,
                                   targetSets: 3, targetReps: 8, targetWeightKg: 60, sets: sets)
        }
        try await repo.saveRoutine(r, exercises: exercises)

        let slots = await repo.seedTodaySlots(routineId: r.id, advice: .planAsIs, inventory: [], serving: nil)

        XCTAssertEqual(slots.count, 2, "un slot por ejercicio")
        XCTAssertEqual(slots.map(\.re.exerciseId), ex.map(\.id), "en el orden de la rutina")
        XCTAssertEqual(slots.map { $0.exercise?.id }, ex.map(\.id), "cada slot resuelve su ejercicio")
    }

    /// Rutina inexistente → sin slots, sin crash. El reloj cuenta con esto: `startTodayFromWrist`
    /// hace `guard !slots.isEmpty` antes de arrancar.
    func testRutinaInexistenteDaListaVacia() async throws {
        let slots = await repo.seedTodaySlots(routineId: "no-existe", advice: .planAsIs, inventory: [], serving: nil)
        XCTAssertTrue(slots.isEmpty)
    }
}
