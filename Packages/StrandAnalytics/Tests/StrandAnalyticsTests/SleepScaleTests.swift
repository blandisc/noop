import XCTest
import StrandModels
@testable import StrandAnalytics

/// FER-84 — la magnitud del sueño sale del MISMO sitio que su voto.
///
/// El punto de estas pruebas no es la aritmética (es una división), sino el amarre: si alguien mueve
/// el piso o la holgura en la config, el dibujo tiene que moverse con el voto. Una boleta que dibuja
/// un corte distinto del que vota es peor que una que no dibuja nada.
final class SleepScaleTests: XCTestCase {

    private func dm(_ day: String, sleep: Double?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: 0.9, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: 55, avgHrv: 55, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: nil, skinTempDevC: 0, respRateBpm: 14)
    }

    /// 20 noches de base + la noche de hoy.
    private func read(sleepMin: Double?, historial: Double = 450) -> Preparedness.Read {
        let base = (1...20).map { dm(String(format: "2026-07-%02d", $0), sleep: historial) }
        let hoy = dm("2026-08-01", sleep: sleepMin)
        return Preparedness.evaluate(.init(days: base + [hoy], strainByDay: [:], trend: nil,
                                           asOf: "2026-08-01", nocturnalRestingHr: [:],
                                           cyclePhase: nil, nocturnalRmssd: nil))
    }

    func testSinNocheNoHayMagnitud() {
        XCTAssertNil(read(sleepMin: nil).sleepScale)
    }

    /// La fracción es minutos entre el piso, y el corte es el que el motor usa para votar.
    func testLaFraccionYElCorteSalenDeLaConfig() {
        let cfg = Preparedness.Config()
        guard let sc = read(sleepMin: 420).sleepScale else { return XCTFail("esperaba magnitud") }
        XCTAssertEqual(sc.ratio, 1.0, accuracy: 0.0001, "420 min es exactamente el piso")
        XCTAssertEqual(sc.outRatio,
                       (cfg.sleepNeedFloorMin - cfg.sleepSlackMin) / cfg.sleepNeedFloorMin,
                       accuracy: 0.0001)
        XCTAssertEqual(sc.slackRatio, cfg.sleepSlackMin / cfg.sleepNeedFloorMin, accuracy: 0.0001)
    }

    /// El amarre que de verdad importa: la noche que el motor declara CORTA cae por debajo del
    /// corte de la magnitud, y la que declara suficiente cae por encima. Si esto se rompe, la
    /// boleta dibujaría la joya de un lado y la palabra diría el otro.
    func testElDibujoYElVotoNoSePuedenSeparar() {
        let cfg = Preparedness.Config()
        let corta = cfg.sleepNeedFloorMin - cfg.sleepSlackMin - 30   // 345 min: el motor vota fuera
        let suficiente = cfg.sleepNeedFloorMin - cfg.sleepSlackMin + 30 // 405 min: el motor la deja pasar

        guard let scCorta = read(sleepMin: corta).sleepScale,
              let scOk = read(sleepMin: suficiente).sleepScale else { return XCTFail("esperaba magnitud") }
        XCTAssertLessThan(scCorta.ratio, scCorta.outRatio, "una noche corta cae bajo el corte")
        XCTAssertGreaterThan(scOk.ratio, scOk.outRatio, "una noche suficiente cae sobre el corte")

        let estadoCorta = read(sleepMin: corta).drivers.first { $0.axis == .sleep }?.state
        let estadoOk = read(sleepMin: suficiente).drivers.first { $0.axis == .sleep }?.state
        XCTAssertEqual(estadoCorta, .low, "y el voto dice lo mismo")
        XCTAssertEqual(estadoOk, .inRange)
    }

    /// La magnitud NO es una z: no se compara contra el promedio del usuario. Dos historias con el
    /// mismo sueño de anoche dan la MISMA magnitud, aunque una venga de meses durmiendo poco.
    func testLaMagnitudNoSeAdaptaAlHistorial() {
        let dormilon = read(sleepMin: 300, historial: 520)
        let privado = read(sleepMin: 300, historial: 300)
        XCTAssertEqual(dormilon.sleepScale?.ratio, privado.sleepScale?.ratio,
                       "cinco horas son cinco horas para los dos: la vara es el piso recomendado")
    }
}
