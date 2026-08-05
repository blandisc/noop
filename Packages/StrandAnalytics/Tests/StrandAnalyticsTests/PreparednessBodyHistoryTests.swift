import XCTest
import StrandModels
@testable import StrandAnalytics

/// FER-51 · Lane 0 — `Read.bodyHistory` + `Read.thermalAdjustedDevC`: accesores de LECTURA sobre
/// el pase forward que el veredicto ya corre. El contrato que estas pruebas fijan es PARIDAD, no
/// matemática nueva: cada noche queda juzgada con la base de SU propio día y jamás se repinta al
/// crecer la historia; el dev térmico expuesto es el mismo número que juzgó `thermalDriver`
/// (con el descuento lúteo asOf, solo del lado alto); y el voto no se mueve ni un pelo.
final class PreparednessBodyHistoryTests: XCTestCase {

    // MARK: Fixtures (misma forma que PreparednessSentinelHistoryTests)

    private func dm(_ day: String, hrv: Double? = 55, rhr: Int? = 55, resp: Double? = 14,
                    sleep: Double? = 450, eff: Double? = nil, temp: Double? = 0.0) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: eff, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: nil, skinTempDevC: temp, respRateBpm: resp)
    }

    private func baseline(_ count: Int = 20) -> [DailyMetric] {
        (1...count).map { i in
            dm(String(format: "2026-06-%02d", i),
               hrv: 52 + Double(i % 5), rhr: 54 + i % 3, resp: 13 + Double(i % 3))
        }
    }

    private func read(_ days: [DailyMetric], asOf: String,
                      cyclePhase: CyclePhaseEngine.Phase? = nil) -> Preparedness.Read {
        Preparedness.evaluate(.init(days: days, strainByDay: [:], trend: nil, asOf: asOf,
                                    nocturnalRestingHr: [:], cyclePhase: cyclePhase,
                                    nocturnalRmssd: nil))
    }

    // MARK: (a) Cada noche se juzga con la base de SU día — jamás se repinta

    func testHistoriaNoSeRepintaAlCrecerLaBase() throws {
        // Día X con FC disparada vs la base que existía ESE día → fuera. Después llegan días con
        // FC alta sostenida: si la historia se re-juzgara con la base de HOY (que ya subió), el
        // día X dejaría de verse fuera. El contrato es que NO se re-aplica.
        let spike = dm("2026-06-21", rhr: 75)
        let asOfX = read(baseline() + [spike], asOf: "2026-06-21")
        let nochesX = asOfX.bodyHistory
        let entradaX = try XCTUnwrap(nochesX.last)
        XCTAssertEqual(entradaX.day, "2026-06-21")
        XCTAssertTrue(entradaX.autonomicOut, "75 lpm vs base ~55 debe quedar fuera con los priors de ese día")

        // Ahora la base de hoy sería mucho más alta (FC 74–76 durante días).
        let after = (22...28).map { i in dm(String(format: "2026-06-%02d", i), rhr: 74 + i % 3) }
        let asOfLater = read(baseline() + [spike] + after, asOf: "2026-06-28")
        let entradaXLater = try XCTUnwrap(asOfLater.bodyHistory.first(where: { $0.day == "2026-06-21" }))
        XCTAssertEqual(entradaXLater, entradaX,
                       "la noche del 21 debe ser BIT-IDÉNTICA aunque la base de hoy haya cambiado: la historia no se re-aplica")
    }

    func testBaseCentroEsLaDeSuPropioDia() throws {
        // El centro de base acarreado por cada noche es el fold de los días ANTERIORES a ella —
        // por eso dos noches distintas de la misma serie llevan centros distintos si la serie se movió.
        let after = (22...28).map { i in dm(String(format: "2026-06-%02d", i), rhr: 75) }
        let r = read(baseline() + after, asOf: "2026-06-28")
        let temprano = try XCTUnwrap(r.bodyHistory.first(where: { $0.day == "2026-06-20" }))
        let tardio = try XCTUnwrap(r.bodyHistory.last)
        let cTemprano = try XCTUnwrap(temprano.rhrBaseCenter)
        let cTardio = try XCTUnwrap(tardio.rhrBaseCenter)
        XCTAssertLessThan(cTemprano, cTardio,
                          "tras una semana a 75 lpm el centro de base del día 28 debe ser mayor que el del 20")
        XCTAssertEqual(cTemprano, 55, accuracy: 2.0, "el centro temprano refleja la base ~55 de sus priors")
    }

    // MARK: (b) autonomicOut / sleepOut coinciden con los cortes del veredicto del propio día

    func testAutonomicOutCoincideConElEjeDelVeredicto() throws {
        let r = read(baseline() + [dm("2026-06-21", rhr: 75)], asOf: "2026-06-21")
        let eje = try XCTUnwrap(r.drivers.first(where: { $0.axis == .autonomic }))
        let noche = try XCTUnwrap(r.bodyHistory.last)
        XCTAssertTrue(eje.state.isOut)
        XCTAssertEqual(noche.autonomicOut, eje.state.isOut)
        XCTAssertEqual(try XCTUnwrap(noche.autonomicOrientedZ), try XCTUnwrap(eje.orientedZ), accuracy: 1e-12,
                       "el z acarreado es EL MISMO compuesto que votó, no una re-derivación")
    }

    func testAutonomicEnRangoCoincide() throws {
        let r = read(baseline() + [dm("2026-06-21", rhr: 55)], asOf: "2026-06-21")
        let eje = try XCTUnwrap(r.drivers.first(where: { $0.axis == .autonomic }))
        let noche = try XCTUnwrap(r.bodyHistory.last)
        XCTAssertFalse(eje.state.isOut)
        XCTAssertFalse(noche.autonomicOut)
    }

    func testSleepOutCoincideConElEjeSueno_duracion() throws {
        // 300 min < 420 − 45: el eje sueño del veredicto marca fuera; la noche también.
        let r = read(baseline() + [dm("2026-06-21", sleep: 300)], asOf: "2026-06-21")
        let eje = try XCTUnwrap(r.drivers.first(where: { $0.axis == .sleep }))
        let noche = try XCTUnwrap(r.bodyHistory.last)
        XCTAssertTrue(eje.state.isOut)
        XCTAssertTrue(noche.sleepOut)
    }

    func testSleepOutCoincideConElEjeSueno_eficiencia() throws {
        // 480 min con eficiencia 0.72 < 0.80: fuera por el brazo de eficiencia.
        let r = read(baseline() + [dm("2026-06-21", sleep: 480, eff: 0.72)], asOf: "2026-06-21")
        let eje = try XCTUnwrap(r.drivers.first(where: { $0.axis == .sleep }))
        let noche = try XCTUnwrap(r.bodyHistory.last)
        XCTAssertTrue(eje.state.isOut)
        XCTAssertTrue(noche.sleepOut)
    }

    func testSleepEnRangoCoincide() throws {
        let r = read(baseline() + [dm("2026-06-21", sleep: 450)], asOf: "2026-06-21")
        let noche = try XCTUnwrap(r.bodyHistory.last)
        XCTAssertFalse(noche.sleepOut)
    }

    // MARK: (c) thermalAdjustedDevC — descuento lúteo solo asOf y solo lado alto

    func testThermalAdjustedAplicaDescuentoLutealAsOf() throws {
        let r = read(baseline() + [dm("2026-06-21", temp: 0.9)], asOf: "2026-06-21",
                     cyclePhase: .lutealLean)
        XCTAssertEqual(try XCTUnwrap(r.thermalAdjustedDevC), 0.6, accuracy: 1e-12,
                       "0.9 − 0.3 de descuento lúteo: el MISMO número que juzgó thermalDriver")
        // Y coincide con el juicio del eje: 0.6 < 0.8 → en rango.
        let eje = try XCTUnwrap(r.drivers.first(where: { $0.axis == .thermal }))
        XCTAssertEqual(eje.state, .inRange)
    }

    func testThermalSinFaseNoDescuenta() throws {
        let r = read(baseline() + [dm("2026-06-21", temp: 0.9)], asOf: "2026-06-21")
        XCTAssertEqual(try XCTUnwrap(r.thermalAdjustedDevC), 0.9, accuracy: 1e-12)
        let eje = try XCTUnwrap(r.drivers.first(where: { $0.axis == .thermal }))
        XCTAssertEqual(eje.state, .high)
    }

    func testThermalLadoFrioNoSeDescuenta() throws {
        let r = read(baseline() + [dm("2026-06-21", temp: -0.5)], asOf: "2026-06-21",
                     cyclePhase: .lutealLean)
        XCTAssertEqual(try XCTUnwrap(r.thermalAdjustedDevC), -0.5, accuracy: 1e-12,
                       "el descuento lúteo jamás toca el lado frío")
    }

    func testThermalSinLecturaEsNil() {
        let r = read(baseline() + [dm("2026-06-21", temp: nil)], asOf: "2026-06-21")
        XCTAssertNil(r.thermalAdjustedDevC)
    }

    // MARK: Ventana, orden y cap

    func testCapVeinteNochesViejoANuevo() {
        let after = (21...28).map { i in dm(String(format: "2026-06-%02d", i)) }
        let days = baseline() + after   // 28 noches
        let r = read(days, asOf: "2026-06-28")
        XCTAssertEqual(r.bodyHistory.count, Preparedness.bodyHistoryWindow)
        XCTAssertEqual(r.bodyHistory.map(\.day), days.suffix(20).map(\.day),
                       "las últimas 20 terminando en asOf, viejo → nuevo")
    }

    func testRutaLowSignalSinFilaDevuelveVacia() {
        // Sin fila de asOf: el composer regresa antes de computar raws → historia vacía y dev nil.
        let r = read(baseline(), asOf: "2026-07-15")
        XCTAssertEqual(r.verdict, .lowSignal)
        XCTAssertTrue(r.bodyHistory.isEmpty)
        XCTAssertNil(r.thermalAdjustedDevC)
    }

    func testRhrResolvedEsLaSerieResuelta() throws {
        // Sin nocturna y con suavizado N=1 (default), la FC resuelta de una noche es su restingHr.
        let r = read(baseline() + [dm("2026-06-21", rhr: 61)], asOf: "2026-06-21")
        XCTAssertEqual(try XCTUnwrap(r.bodyHistory.last?.rhrResolved), 61)
    }

    func testHrvBaseCenterEnUnidadesNaturales() throws {
        // La base SDNN vive en log-dominio: el centro expuesto debe venir ya en ms (exp), no en ln.
        let r = read(baseline() + [dm("2026-06-21")], asOf: "2026-06-21")
        let c = try XCTUnwrap(r.bodyHistory.last?.hrvBaseCenter)
        XCTAssertEqual(c, 54, accuracy: 4.0, "≈ media geométrica de 52–56 ms, no ~4 (ln)")
    }

    // MARK: La adición es inerte para el voto y para los inits existentes

    func testExponerLaHistoriaNoMueveElVeredicto() {
        let days = baseline() + [dm("2026-06-21", rhr: 75)]
        let r1 = read(days, asOf: "2026-06-21")
        let r2 = read(days, asOf: "2026-06-21")
        XCTAssertEqual(r1.verdict, r2.verdict)
        XCTAssertFalse(r1.bodyHistory.isEmpty)
    }

    func testInitExistenteCompilaConDefaults() {
        // El init pre-FER-51 (sin bodyHistory/thermalAdjustedDevC) sigue compilando tal cual.
        let r = Preparedness.Read(verdict: .full, drivers: [], signalsPresent: 3, signalsTotal: 3,
                                  maturity: .trusted, autonomicNights: 30, trend: nil)
        XCTAssertTrue(r.bodyHistory.isEmpty)
        XCTAssertNil(r.thermalAdjustedDevC)
    }
}
