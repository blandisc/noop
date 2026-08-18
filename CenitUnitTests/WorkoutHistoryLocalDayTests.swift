import XCTest
import StrandTraining
@testable import Cenit

/// FER-90 · E9 — el calendario del historial y la Constancia migrada resuelven cada día por
/// `WorkoutHistoryScreen.latestSessionByLocalDay(_:)`: la sesión más reciente de un día LOCAL, nunca
/// UTC (memoria del repo: «fila fantasma UTC vs local»), y descartando cualquier sesión sin cerrar.
/// Antes de esta extracción la reducción vivía inline en un computed var `private` de la vista — no
/// se podía probar sin instanciar `WorkoutHistoryScreen` completa. Estas pruebas fallan si alguien:
/// (a) vuelve a «gana la primera del arreglo» en vez de comparar `startTs`, (b) deja de filtrar
/// sesiones con `endTs == nil`, o (c) reintroduce un cálculo por UTC en vez de `Calendar.current`.
final class WorkoutHistoryLocalDayTests: XCTestCase {

    private let cal = Calendar.current

    /// Medianoche local de hoy, como base para construir timestamps del día sin depender de la zona
    /// horaria de la máquina que corre la prueba.
    private var todayStart: Int { Int(cal.startOfDay(for: Date()).timeIntervalSince1970) }

    /// Dos sesiones el MISMO día local: la de `startTs` mayor gana, sin importar el orden del arreglo
    /// — un código viejo que hiciera «la primera que aparece en el bucle gana» (sin comparar `startTs`)
    /// tronaría aquí en cuanto se invirtiera el orden de entrada.
    func testGanaLaSesionMasRecienteDelMismoDiaLocalSinImportarElOrden() {
        let morning = StrengthSession(id: "morning", startTs: todayStart + 8 * 3600,
                                      endTs: todayStart + 8 * 3600 + 1800)
        let evening = StrengthSession(id: "evening", startTs: todayStart + 19 * 3600,
                                      endTs: todayStart + 19 * 3600 + 1800)

        let inOrder = WorkoutHistoryScreen.latestSessionByLocalDay([morning, evening])
        let reversed = WorkoutHistoryScreen.latestSessionByLocalDay([evening, morning])

        XCTAssertEqual(inOrder.count, 1, "las dos sesiones caen el mismo día local — un solo cubo")
        XCTAssertEqual(inOrder.values.first?.id, "evening", "debía ganar el startTs mayor, no el primero del arreglo")
        XCTAssertEqual(reversed.values.first?.id, "evening", "el orden de entrada no debe cambiar quién gana")
    }

    /// Dos sesiones en días LOCALES distintos quedan en cubos distintos — el calendario no debe
    /// fusionarlas ni perder una por colisión de clave.
    func testDiasLocalesDistintosQuedanEnCubosDistintos() {
        let today = StrengthSession(id: "today", startTs: todayStart + 3600, endTs: todayStart + 3600 + 1800)
        let threeDaysAgo = StrengthSession(
            id: "hace3d",
            startTs: Int(cal.date(byAdding: .day, value: -3, to: Date(timeIntervalSince1970: TimeInterval(todayStart + 3600)))!.timeIntervalSince1970),
            endTs: nil
        )
        // La de hace 3 días necesita su propio cierre para no caer en el filtro de abajo.
        var closedThreeDaysAgo = threeDaysAgo
        closedThreeDaysAgo.endTs = threeDaysAgo.startTs + 1800

        let byDay = WorkoutHistoryScreen.latestSessionByLocalDay([today, closedThreeDaysAgo])

        XCTAssertEqual(byDay.count, 2, "dos días locales distintos deben producir dos cubos")
        XCTAssertTrue(byDay.values.contains { $0.id == "today" })
        XCTAssertTrue(byDay.values.contains { $0.id == "hace3d" })
    }

    /// Una sesión sin `endTs` (viva / sin cerrar) queda excluida — no aparece en el historial hasta que
    /// se guarda (mismo criterio ya documentado en «Estados → Sesión viva»).
    func testSesionSinEndTsQuedaExcluida() {
        let live = StrengthSession(id: "viva", startTs: todayStart + 3600, endTs: nil)
        let closed = StrengthSession(id: "cerrada", startTs: todayStart + 2 * 3600, endTs: todayStart + 2 * 3600 + 1800)

        let byDay = WorkoutHistoryScreen.latestSessionByLocalDay([live, closed])

        XCTAssertEqual(byDay.count, 1, "solo la sesión cerrada debía sobrevivir al filtro")
        XCTAssertEqual(byDay.values.first?.id, "cerrada")
    }

    /// Un arreglo vacío no truena y no produce cubos — el estado «sin datos» del calendario (91/63
    /// celdas `.empty`) depende de que esto regrese `[:]`, no de un valor centinela.
    func testArregloVacioNoProduceCubos() {
        XCTAssertTrue(WorkoutHistoryScreen.latestSessionByLocalDay([]).isEmpty)
    }
}
