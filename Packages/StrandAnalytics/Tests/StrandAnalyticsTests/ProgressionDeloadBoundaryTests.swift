import XCTest
@testable import StrandAnalytics

/// Ola 1 · E10 (FER-329): la sesión servida en semana ligera (`PastSession.deload`) es FRONTERA —
/// no cuenta como acierto ni como fallo, no rompe la racha de aciertos, y sí corta la de estancamiento.
final class ProgressionDeloadBoundaryTests: XCTestCase {
    typealias Past = ProgressionMath.PastSession

    private func input(_ history: [Past], sessionsToAdvance: Int = 2) -> ProgressionMath.ProgressionInput {
        ProgressionMath.ProgressionInput(history: history, targetReps: 8, targetSets: 4,
                                         sessionsToAdvance: sessionsToAdvance, incrementKg: 2.5)
    }

    private func hit(_ kg: Double) -> Past { Past(workingKg: kg, workSetReps: [8, 8, 8, 8]) }
    private func miss(_ kg: Double) -> Past { Past(workingKg: kg, workSetReps: [8, 7, 6, 5]) }
    /// Una sesión ligera: la mitad de las series y (regla `volumeAndLoad`) menos peso.
    private func light(_ kg: Double) -> Past {
        Past(workingKg: kg, workSetReps: [8, 8], deload: true)
    }

    func testALightWeekBreaksTheStallCount() {
        // [miss, miss, ligera, miss]: solo el fallo POSTERIOR a la ligera cuenta.
        let s = ProgressionMath.classify(input([miss(100), miss(100), light(92.5), miss(100)]))
        XCTAssertEqual(s, .stalled(sessions: 1))
    }

    func testALightWeekIsInvisibleToTheMetRun() {
        // [met, ligera, met] con n = 2: la ligera ni suma ni rompe → dos aciertos → sube.
        let s = ProgressionMath.classify(input([hit(100), light(92.5), hit(100)]))
        XCTAssertEqual(s, .readyToAdvance(newKg: 102.5))
    }

    func testALightWeekDoesNotCountAsAMetSessionByItself() {
        // Un solo acierto real + la ligera: sigue siendo 1 de 2, no 2 de 2.
        let s = ProgressionMath.classify(input([light(92.5), hit(100)]))
        XCTAssertEqual(s, .inCycle(done: 1, of: 2))
    }

    func testTheNewestLightSessionIsNotTheCurrentOne() {
        // La ligera bajó el peso a 92,5. Si fuera «la actual», la subida saldría de 92,5 (→ 95) y el
        // ciclo leería un cambio de peso. La actual es la de 100: dos aciertos → 102,5.
        let s = ProgressionMath.classify(input([hit(100), hit(100), light(92.5)]))
        XCTAssertEqual(s, .readyToAdvance(newKg: 102.5))
    }

    func testAHistoryOfOnlyLightSessionsSaysNothing() {
        XCTAssertEqual(ProgressionMath.classify(input([light(92.5), light(92.5)])),
                       .inCycle(done: 0, of: 2))
    }

    func testTheReactiveDeloadStaysAliveInsideAProgram() {
        // Gate /biomecanico #1: estancarse en la semana 2 de 5 propone la descarga de −7,5 % HOY,
        // no «espera a la semana ligera».
        let s = ProgressionMath.classify(input([miss(100), miss(100), miss(100)]))
        XCTAssertEqual(s, .deloading(fromKg: 100, toKg: 92.5))
    }

    func testALightSessionDoesNotBreakNorFeedTheAtLimitStreak() {
        let atLimit = Past(workingKg: 100, workSetReps: [8, 8, 8, 8],
                           workSetRPE: [9.5, 9.5, 9.5, 9.5])
        let lightAtLimit = Past(workingKg: 92.5, workSetReps: [8, 8],
                                workSetRPE: [9.5, 9.5], deload: true)
        let streak = ProgressionMath.atLimitStreak(
            input([atLimit, lightAtLimit, atLimit]))
        XCTAssertEqual(streak, 2, "la ligera no suma al «al límite» ni corta la racha")
    }

    func testWithoutAnyLightSessionNothingChanges() {
        // La regla nueva no puede mover el comportamiento de un historial sin programa.
        XCTAssertEqual(ProgressionMath.classify(input([hit(100), hit(100)])),
                       .readyToAdvance(newKg: 102.5))
        XCTAssertEqual(ProgressionMath.classify(input([miss(100), hit(100)])),
                       .inCycle(done: 1, of: 2))
    }
}
