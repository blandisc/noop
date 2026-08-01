import XCTest
import StrandModels
@testable import Cenit

/// Fija la compuerta que decide CUÁNDO se publica el veredicto de «Preparación».
///
/// Por qué existe: el primer pintado no carga `nocturnalRestingHr`, así que si el veredicto se
/// evaluara ahí puntuaría la FC-reposo **despierta** de Apple y segundos después, ya en el pase
/// completo, la **nocturna** — el mismo héroe cambiando de constructo dentro de una misma mañana.
/// Una regresión aquí es INVISIBLE en pantalla (el veredicto simplemente sería otro), y costó una
/// auditoría escéptica encontrarla la primera vez. Por eso se fija con un test y no con un comentario.
final class PreparednessFullGateTests: XCTestCase {

    private func dm(_ day: String) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 450, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: 55, avgHrv: 55, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: nil, skinTempDevC: 0, respRateBpm: 14)
    }

    /// `RefreshInputs` con una historia mínima y todo lo demás vacío; solo varía `full`.
    private func inputs(full: Bool) -> Repository.RefreshInputs {
        let days = (1...6).map { dm(String(format: "2026-06-%02d", $0)) }
        return Repository.RefreshInputs(
            importedRaw: [], computedRaw: [], appleRaw: days,
            imported: [], computed: [], apple: days,
            impSleepRaw: [], compSleepRaw: [], impSleep: [], compSleep: [],
            appleSleepRaw: [],
            appleAggRaw: [], stepsEstRaw: [],
            perf: [], cons: [], need: [], debt: [],
            nightRows: [], asOf: "2026-06-06", full: full, recentCutoff: "2026-06-01")
    }

    /// Primer pintado (`full == false`): el veredicto NO se publica. La UI lo distingue de «no hay
    /// veredicto» vía `verdictPending` y dice que está leyendo, no que no conoce tu base.
    func testFirstPaintDoesNotPublishVerdict() async {
        let dash = await Repository.assembleDashboard(inputs(full: false))
        XCTAssertNil(dash.preparedness,
                     "el primer pintado no puede publicar veredicto: puntuaría la FC despierta")
    }

    /// Pase completo (`full == true`): el veredicto SÍ se publica. Aunque no haya base suficiente,
    /// `evaluate` devuelve un `Read` (`.lowSignal`) — nunca `nil`, que es el estado «todavía no lo sé».
    func testFullPassPublishesVerdict() async {
        let dash = await Repository.assembleDashboard(inputs(full: true))
        XCTAssertNotNil(dash.preparedness,
                        "el pase completo siempre publica un Read, aunque sea lowSignal")
    }
}
