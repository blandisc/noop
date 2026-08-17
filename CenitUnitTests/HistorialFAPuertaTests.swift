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

    func test_sinFilas_ofrece() {
        XCTAssertEqual(HistorialFAPuerta.estado(filas: []), .noLleganSeries)
    }

    /// Un goteo de latidos no es «ya llegan series»: por debajo del piso del propio motor la noche
    /// nunca cuenta, así que la puerta sigue teniendo algo que informar.
    func test_latidosPorDebajoDelPiso_ofrece() {
        let filas = [clean(3), clean(Double(NocturnalHRV.minCleanBeats) - 1, day: "2026-08-15")]
        XCTAssertEqual(HistorialFAPuerta.estado(filas: filas), .noLleganSeries)
    }

    func test_nocheEnElPisoDeDensidad_seCalla() {
        let filas = [clean(3), clean(Double(NocturnalHRV.minCleanBeats), day: "2026-08-15")]
        XCTAssertEqual(HistorialFAPuerta.estado(filas: filas), .yaLleganSeries)
    }

    /// Una noche que el motor ya contó (emitió RMSSD) es evidencia suficiente por sí sola.
    func test_nocheDensaConRmssd_seCalla() {
        let filas = [MetricPoint(day: "2026-08-16", key: "apple_rmssd_night", value: 42)]
        XCTAssertEqual(HistorialFAPuerta.estado(filas: filas), .yaLleganSeries)
    }
}
