import XCTest
import StrandModels
@testable import StrandAnalytics

/// F6 («la banda nunca existió») — contrato del limpiado incondicional `clearBandColumns`/`clearBandHrv`.
///
/// F6 reemplazó la maquinaria multi-fuente de `SourceLens` (`maskForBaseline`/`maskHrv`/`keep:`) por dos
/// helpers INCONDICIONALES — greenfield Apple-only, cada fila es Apple. El gate de ciencia (CSO + CDO)
/// probó que la sustitución es numéricamente idéntica; estos tests fijan la semántica que sobrevive:
/// (a) el limpiado nila EXACTAMENTE las columnas cross-source y nada más, y (b) es LOAD-BEARING —
/// pasar `days` crudo (SDNN en `avgHrv`) a un motor band-domain reintroduciría el bug FER-519.
final class F6CollapseIdentityContractTests: XCTestCase {

    private func key(_ i: Int) -> String { String(format: "2026-06-%02d", i) }

    /// Fila Apple densa: avgHrv = SDNN, restingHr = RHR Apple, resp/skinTemp/stages presentes,
    /// + strain/steps/totalSleepMin (columnas single-source que DEBEN sobrevivir el limpiado).
    private func appleRow(_ day: String) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 420, efficiency: 0.9, deepMin: 90, remMin: 90,
                    lightMin: 240, disturbances: 2, restingHr: 48, avgHrv: 88, recovery: 61,
                    strain: 12, exerciseCount: 1, spo2Pct: 97, skinTempDevC: 0.2, respRateBpm: 14,
                    steps: 8000, activeKcalEst: 500)
    }

    private func history(_ n: Int) -> [DailyMetric] { (1...n).map { appleRow(key($0)) } }

    // MARK: clearBandColumns nila EXACTAMENTE las columnas cross-source, el resto intacto

    func test_clearBandColumns_nilsExactlyCrossSourceColumns() {
        let out = SourceLens.clearBandColumns(history(10))
        for row in out {
            XCTAssertNil(row.avgHrv);   XCTAssertNil(row.restingHr);  XCTAssertNil(row.respRateBpm)
            XCTAssertNil(row.deepMin);  XCTAssertNil(row.remMin);     XCTAssertNil(row.lightMin)
            XCTAssertNil(row.skinTempDevC)
            // single-source / cross-source-comparable columns survive
            XCTAssertEqual(row.totalSleepMin, 420); XCTAssertEqual(row.strain, 12)
            XCTAssertEqual(row.steps, 8000);        XCTAssertEqual(row.spo2Pct, 97)
        }
    }

    func test_clearBandHrv_nilsOnlyHrv() {
        let out = SourceLens.clearBandHrv(history(10))
        for row in out {
            XCTAssertNil(row.avgHrv)
            XCTAssertEqual(row.restingHr, 48); XCTAssertEqual(row.respRateBpm, 14)
            XCTAssertEqual(row.skinTempDevC, 0.2)
        }
    }

    // MARK: El limpiado es LOAD-BEARING (FER-519) — no es andamiaje muerto

    /// Pasar `days` CRUDO (SDNN en avgHrv) a `ReadinessEngine` puntúa una señal HRV band-domain de una
    /// fila Apple (el bug FER-519); el limpiado la borra. Prueba que quitar el limpiado cambia el veredicto.
    func test_rawAppleSDNNwouldScoreHRVsignal_clearedDoesNot_FER519() {
        let days = history(30)
        let today = days.last!.day
        let raw = ReadinessEngine.evaluate(days: days, today: today)
        let cleared = ReadinessEngine.evaluate(days: SourceLens.clearBandColumns(days), today: today)
        XCTAssertNotNil(raw.signals.first { $0.key == "hrv" },
                        "SDNN crudo HABRÍA puntuado una señal HRV (el bug FER-519)")
        XCTAssertNil(cleared.signals.first { $0.key == "hrv" },
                     "limpiado ⇒ sin señal HRV band-domain de una fila Apple")
    }
}
