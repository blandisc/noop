import XCTest
@testable import StrandAnalytics
import StrandModels

/// FER-48 — la SUPERFICIE DE COLUMNAS de `InsightEngine`: qué puede leer y qué no.
///
/// Por qué existe: hasta FER-48, `InsightsProvider` pasaba los días por `SourceLens.clearBandColumns`,
/// que nilaba las etapas de sueño y `skinTempDevC` además de los vitales. Nadie leía esas columnas en
/// el motor, así que la máscara las protegía **por accidente**. Al abrir la lente a `clearBandHrv`
/// (para que la anomalía de FC en reposo pueda existir), ese accidente desaparece: si mañana alguien
/// agrega un `Outcome` de sueño profundo o de temperatura, entraría SIN gate.
///
/// Esta prueba es ese gate. No prohíbe agregar la columna: obliga a que quien lo haga vea este archivo
/// y defienda la decisión — porque la evidencia dice que no debería. El Apple Watch acierta el sueño
/// profundo en ~50.7% de las épocas y lo subestima ~25 min (κ 4-etapas = 0.53; Schyvens et al. 2025,
/// SLEEP Advances 6(2):zpaf021): correlacionar «minutos profundos» con algo es correlacionar el
/// clasificador, no la fisiología. La duración TOTAL sí sobrevive (sensibilidad 96%) y por eso
/// `totalSleepMin` sí es insumo legítimo.
final class InsightEngineColumnSurfaceTests: XCTestCase {

    private func day(_ i: Int, stages: Bool, skinTemp: Bool) -> DailyMetric {
        DailyMetric(day: String(format: "2026-06-%02d", i),
                    totalSleepMin: 420, efficiency: 0.9,
                    deepMin: stages ? 90 : nil,
                    remMin: stages ? 90 : nil,
                    lightMin: stages ? 240 : nil,
                    disturbances: 2, restingHr: 52, avgHrv: 50, recovery: 60,
                    strain: 10, exerciseCount: 1, spo2Pct: 97,
                    skinTempDevC: skinTemp ? 0.7 : nil,
                    respRateBpm: 14)
    }

    private func history(stages: Bool, skinTemp: Bool) -> [DailyMetric] {
        (1...30).map { day($0, stages: stages, skinTemp: skinTemp) }
    }

    /// Poblar las etapas de sueño y la temperatura de piel NO cambia ni un insight. Si esta prueba
    /// falla, alguien empezó a leer una columna que la evidencia no sostiene — o movió el contrato a
    /// propósito, y entonces le toca actualizar el comentario de arriba con su razón.
    func test_sleepStagesAndSkinTemp_areNotAnEngineInput() {
        let sin = InsightEngine.generate(.init(days: history(stages: false, skinTemp: false),
                                               referenceDay: "2026-06-30"))
        let con = InsightEngine.generate(.init(days: history(stages: true, skinTemp: true),
                                               referenceDay: "2026-06-30"))
        XCTAssertEqual(sin.map(\.title), con.map(\.title),
                       "las etapas de sueño y skinTempDevC no son insumo del motor de insights")
        XCTAssertEqual(sin.map(\.reading), con.map(\.reading))
    }

    /// El contrario, para que la prueba de arriba no sea un verde vacío: una columna que el motor SÍ
    /// lee (FC en reposo) cambia el resultado cuando cambia.
    func test_restingHR_isAnEngineInput() {
        var conSalto = history(stages: false, skinTemp: false)
        // El último día CERRADO (el motor ignora el de referencia por parcial) con un salto grande.
        conSalto[28] = DailyMetric(day: conSalto[28].day, totalSleepMin: 420, efficiency: 0.9,
                                   deepMin: nil, remMin: nil, lightMin: nil, disturbances: 2,
                                   restingHr: 70, avgHrv: 50, recovery: 60, strain: 10,
                                   exerciseCount: 1, spo2Pct: 97, skinTempDevC: nil, respRateBpm: 14)
        let base = InsightEngine.generate(.init(days: history(stages: false, skinTemp: false),
                                                referenceDay: "2026-06-30"))
        let salto = InsightEngine.generate(.init(days: conSalto, referenceDay: "2026-06-30"))
        XCTAssertNotEqual(base.map(\.title), salto.map(\.title),
                          "la FC en reposo SÍ es insumo: si esto no cambia, la prueba hermana no prueba nada")
    }
}
