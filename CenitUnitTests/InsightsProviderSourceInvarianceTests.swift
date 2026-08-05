import XCTest
import CenitStore
import StrandAnalytics
@testable import Cenit

/// `InsightsProvider` (Patrones + «La conexión de hoy» del Daily Brief) pasa los días por
/// `SourceLens.clearBandColumns` antes de que `InsightEngine` doble cualquier base.
///
/// **Este archivo nació mintiendo** (FER-973, PR #1017): se escribió para el mundo FER-639, cuando el
/// limpiado era SELECTIVO por fuente (noches de banda vs noches de Apple) y su misión era que la base
/// de HRV no mezclara RMSSD de banda con SDNN de Apple. Ese mundo ya no existe: tras «la banda nunca
/// existió» toda fila es de Apple y el limpiado es INCONDICIONAL
/// (`SourceLens.swift` — nila `avgHrv`, `restingHr`, `respRateBpm`, las etapas de sueño y
/// `skinTempDevC` en TODAS las filas). Como el archivo nunca se ejecutó —el modo que lo corría estaba
/// roto y CI no cubre este target— nadie notó que una de sus pruebas fallaba y la otra pasaba VACÍA.
///
/// Lo que este archivo fija ahora es la consecuencia REAL, que es incómoda y por eso vale pinearla:
/// **ninguna anomalía nocturna de vital puede aflorar hoy**, porque el motor recibe esas columnas en
/// `nil`. Para HRV es deliberado y correcto (el SDNN de Apple no es comparable contra una base de
/// RMSSD). Para **FC en reposo y respiración** es más ancho de lo necesario: son de un solo
/// instrumento y sí serían comparables consigo mismas. Eso es una decisión de producto/ciencia
/// abierta, no un descuido que se parchee aquí: si alguien la resuelve (moviendo `rank` a
/// `SourceLens.clearBandHrv`), ESTAS pruebas son las que deben cambiar, y el diff dirá exactamente
/// qué empieza a mostrarse.
@MainActor
final class InsightsProviderSourceInvarianceTests: XCTestCase {

    private func key(_ i: Int) -> String { String(format: "2026-06-%02d", i) }

    private func dm(_ day: String, hrv: Double?, rhr: Int?, resp: Double? = 14,
                    recovery: Double? = 60) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 420, efficiency: 0.9, deepMin: 90, remMin: 90,
                    lightMin: 240, disturbances: 2, restingHr: rhr, avgHrv: hrv, recovery: recovery,
                    strain: 10, exerciseCount: 1, spo2Pct: 97, skinTempDevC: 0.1, respRateBpm: resp)
    }

    /// 30 noches estables + la de hoy, que es la que cada prueba decide.
    private func history() -> (days: [DailyMetric], todayKey: String) {
        var days: [DailyMetric] = []
        for i in 1...30 { days.append(dm(key(i), hrv: 50, rhr: 52)) }
        return (days, key(31))
    }

    private let vitals: Set<String> = ["HRV", "FC en reposo", "Respiración"]
    private func vitalAnomalies(_ xs: [Insight]) -> [Insight] {
        xs.filter { $0.kind == .nightAnomaly && vitals.contains($0.datum.metric) }
          .sorted { $0.datum.metric < $1.datum.metric }
    }

    private func rank(_ days: [DailyMetric], today: String) -> [Insight] {
        InsightsProvider.rank(days: days, appleDays: [], behaviors: [:],
                              eligibleDaysByBehavior: [:], proven: [], today: today)
    }

    // MARK: El limpiado silencia las anomalías de vitales — y hay que verlo, no suponerlo

    /// Un salto de FC en reposo que el motor SÍ marcaría con datos crudos no aflora por `InsightsProvider`.
    /// Las dos mitades importan: sin la segunda, la prueba pasaría igual con un motor que no detecta nada,
    /// y no estaría probando el limpiado sino la nada.
    func testClearingSilencesVitalNightAnomalies() {
        var (days, todayKey) = history()
        days.append(dm(todayKey, hrv: 50, rhr: 58))   // salto de FC en reposo: 58 contra una base de 52

        XCTAssertTrue(vitalAnomalies(rank(days, today: todayKey)).isEmpty,
                      "con las columnas cross-source en nil, el motor no tiene qué juzgar")

        // Carga de la prueba: con los días CRUDOS el mismo motor sí emite la anomalía. Si esto dejara de
        // ser cierto, lo de arriba se volvería un verde vacío.
        let crudo = InsightEngine.generate(.init(days: days, referenceDay: todayKey))
        XCTAssertFalse(vitalAnomalies(crudo).isEmpty,
                       "el motor SÍ ve el salto cuando le llegan las columnas: lo que las apaga es el limpiado")
    }

    /// El limpiado es incondicional: `appleDays` ya no selecciona nada (todo es Apple). Pasarle un
    /// conjunto lleno o vacío da el MISMO resultado — el parámetro sobrevive por firma, no por efecto.
    func testAppleDaysArgumentNoLongerChangesAnything() {
        var (days, todayKey) = history()
        days.append(dm(todayKey, hrv: 50, rhr: 58))

        let sinApple = rank(days, today: todayKey)
        let conApple = InsightsProvider.rank(days: days, appleDays: Set(days.map(\.day)), behaviors: [:],
                                             eligibleDaysByBehavior: [:], proven: [], today: todayKey)
        XCTAssertEqual(vitalAnomalies(sinApple), vitalAnomalies(conApple),
                       "el limpiado no mira la fuente: marcar todo como Apple no cambia nada")
    }

    /// Las columnas de una sola fuente NO se limpian: `InsightsProvider` sigue siendo capaz de emitir
    /// insights. Sin esto, las dos pruebas de arriba serían compatibles con un proveedor roto del todo.
    func testSingleSourceColumnsSurviveTheClearing() {
        let (days, todayKey) = history()
        let masked = SourceLens.clearBandColumns(days)
        XCTAssertNil(masked.last?.restingHr, "FC en reposo se limpia (cross-source)")
        XCTAssertNil(masked.last?.avgHrv, "HRV se limpia (cross-source)")
        XCTAssertEqual(masked.last?.totalSleepMin, 420, "el sueño total sobrevive (una sola fuente)")
        XCTAssertEqual(masked.last?.spo2Pct, 97, "SpO₂ sobrevive (una sola fuente)")
    }
}
