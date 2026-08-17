import XCTest
import CenitStore
import StrandAnalytics
@testable import Cenit

// FER-115 — la puerta del «Historial de FA» solo se abre cuando NO hay evidencia de que las series
// de latidos ya lleguen. La evidencia son las dos claves que escribe `HealthKitBridge`
// (`apple_rmssd_night` / `apple_rr_clean_night`) en la partición `apple-health-noop`.
final class HistorialFAPuertaTests: XCTestCase {

    private func clean(_ n: Double, day: String = "2026-08-16") -> MetricPoint {
        MetricPoint(day: day, key: "apple_rr_clean_night", value: n)
    }

    private func pairs(_ n: Double, day: String = "2026-08-16") -> MetricPoint {
        MetricPoint(day: day, key: "apple_rr_pairs_night", value: n)
    }

    /// Una noche que cumple los DOS pisos del motor (`NocturnalHRV.night`: `nClean ≥ 60` y
    /// `nPairs ≥ 30`), que es lo único que significa «ya llegan series densas».
    private func nocheDensa(day: String = "2026-08-15") -> [MetricPoint] {
        [clean(Double(NocturnalHRV.minCleanBeats), day: day),
         pairs(Double(NocturnalHRV.minSuccessivePairs), day: day)]
    }

    func test_sinFilas_ofrece() {
        XCTAssertEqual(HistorialFAPuerta.estado(filas: []), .noLleganSeries)
    }

    /// Un goteo de latidos no es «ya llegan series»: por debajo del piso del propio motor la noche
    /// nunca cuenta, así que la puerta sigue teniendo algo que informar.
    func test_latidosPorDebajoDelPiso_ofrece() {
        let filas = [clean(3), pairs(1),
                     clean(Double(NocturnalHRV.minCleanBeats) - 1, day: "2026-08-15"),
                     pairs(Double(NocturnalHRV.minSuccessivePairs) - 1, day: "2026-08-15")]
        XCTAssertEqual(HistorialFAPuerta.estado(filas: filas), .noLleganSeries)
    }

    func test_nocheEnLosDosPisosDeDensidad_seCalla() {
        XCTAssertEqual(HistorialFAPuerta.estado(filas: [clean(3)] + nocheDensa()), .yaLleganSeries)
    }

    /// EL defecto que este gate tenía: una noche RALA de muñeca puede pasar los 60 latidos limpios
    /// y quedarse muy corta de pares sucesivos —lo documenta `NocturnalHRV`—, y el motor entonces
    /// NO emite RMSSD. Con solo el piso de limpios, esa única noche callaba la sección para siempre
    /// justo a quien nunca va a recibir el co-voto.
    func test_muchosLatidosPeroPocosPares_sigueOfreciendo() {
        let filas = [clean(120), pairs(Double(NocturnalHRV.minSuccessivePairs) - 1)]
        XCTAssertEqual(HistorialFAPuerta.estado(filas: filas), .noLleganSeries)
    }

    /// Sin la fila de pares no hay evidencia de densidad: no se supone que la hubo.
    func test_latidosSinFilaDePares_sigueOfreciendo() {
        XCTAssertEqual(HistorialFAPuerta.estado(filas: [clean(120)]), .noLleganSeries)
    }

    /// Los dos pisos tienen que caer en LA MISMA noche: 60 limpios de una y 30 pares de otra son
    /// dos noches ralas, no una densa.
    func test_pisosEnNochesDistintas_sigueOfreciendo() {
        let filas = [clean(Double(NocturnalHRV.minCleanBeats), day: "2026-08-15"),
                     pairs(Double(NocturnalHRV.minSuccessivePairs), day: "2026-08-14")]
        XCTAssertEqual(HistorialFAPuerta.estado(filas: filas), .noLleganSeries)
    }

    /// Una noche que el motor ya contó (emitió RMSSD) es evidencia suficiente por sí sola: ese
    /// número ES el veredicto de densidad del motor, y solo sale cuando los dos pisos se cumplieron.
    func test_nocheDensaConRmssd_seCalla() {
        let filas = [MetricPoint(day: "2026-08-16", key: "apple_rmssd_night", value: 42)]
        XCTAssertEqual(HistorialFAPuerta.estado(filas: filas), .yaLleganSeries)
    }
}
