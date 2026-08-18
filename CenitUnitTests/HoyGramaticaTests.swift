import XCTest
import StrandAnalytics
@testable import Cenit

// HoyGramaticaTests.swift — FER-51 · F1.
//
// Fija el vocabulario puro compartido de las caras de Hoy contra los criterios del REQ
// «Cosmos y Matriz»: mapeos p del medidor (criterios 5 y 30), VFC jamás cálida (6), carga
// 1.48/1.55/0.6 (7), sueño por eficiencia (8), calibrando jamás alerta (9), la máquina del
// chip del guardián (10), alarma solo par con racha ≥ 2 (13) y el formateo «—» vs «0».
final class HoyGramaticaTests: XCTestCase {

    // MARK: Fixtures

    private func driver(_ axis: Preparedness.Axis, _ state: Preparedness.AxisState,
                        z: Double? = nil) -> Preparedness.Driver {
        Preparedness.Driver(axis: axis, state: state, orientedZ: z)
    }

    private func read(autonomic: Preparedness.AxisState = .inRange,
                      sleep: Preparedness.AxisState = .inRange,
                      sentinel: Preparedness.SentinelRead? = nil) -> Preparedness.Read {
        Preparedness.Read(verdict: .full,
                          drivers: [driver(.autonomic, autonomic), driver(.sleep, sleep),
                                    driver(.thermal, .inRange), driver(.load, .noData)],
                          signalsPresent: 3, signalsTotal: 3,
                          maturity: .trusted, autonomicNights: 30, trend: nil,
                          sentinel: sentinel)
    }

    private func centinela(_ state: Preparedness.SentinelState, racha: Int,
                           señal: Preparedness.SentinelSignal? = nil) -> Preparedness.SentinelRead {
        Preparedness.SentinelRead(state: state, streakNights: racha, watchingSignal: señal,
                                  tempOut: state == .corroborated || señal == .temp,
                                  respOut: state == .corroborated || señal == .resp)
    }

    // MARK: Criterio 5 — «peor» siempre a la derecha; en rango, dentro del arco

    func testDesviacionEnRangoQuedaDentroDelArco() {
        // z_mal 0 (en tu base) cae al centro exacto; el arco de desviación es p 25–75.
        XCTAssertEqual(HoyGramatica.pDesviacion(zMal: 0, zUmbral: HoyGramatica.zUmbralFC), 50)
        // A medio camino del umbral sigue dentro.
        XCTAssertEqual(HoyGramatica.pDesviacion(zMal: 0.5, zUmbral: 1.0), 62.5)
    }

    func testCruzarElBordeDerechoEquivaleACruzarSuUmbral() {
        // En el umbral exacto de cada señal, p = 75 (el borde derecho del arco) — la
        // equivalencia formal del §6, por señal con SU umbral.
        XCTAssertEqual(HoyGramatica.pDesviacion(zMal: HoyGramatica.zUmbralFC,
                                                zUmbral: HoyGramatica.zUmbralFC,
                                                pisoIzquierdo: HoyGramatica.pisoFC), 75)
        XCTAssertEqual(HoyGramatica.pDesviacion(zMal: HoyGramatica.zUmbralResp,
                                                zUmbral: HoyGramatica.zUmbralResp), 75)
        XCTAssertEqual(HoyGramatica.pDesviacion(zMal: 1.0, zUmbral: HoyGramatica.zUmbralTempEquiv), 75)
        // Peor que el umbral: MÁS a la derecha (p > 75), jamás a la izquierda.
        XCTAssertGreaterThan(HoyGramatica.pDesviacion(zMal: 1.2, zUmbral: 1.0), 75)
    }

    func testSuenoEnRangoNoCruzaElBordeDerecho() throws {
        // 7:30 con buena eficiencia: en rango — nunca del lado malo.
        let r = try XCTUnwrap(HoyGramatica.pSueno(durMin: 450, eficiencia: 0.92))
        XCTAssertFalse(r.porEficiencia)
        XCTAssertLessThan(r.p, 75)
        XCTAssertGreaterThanOrEqual(r.p, 25)
        // En el umbral real del eje (375 min = 420 − 45): el borde exacto.
        XCTAssertEqual(try XCTUnwrap(HoyGramatica.pSueno(durMin: 375, eficiencia: nil)).p, 75)
        // Peor (más corto): a la derecha del borde.
        XCTAssertGreaterThan(try XCTUnwrap(HoyGramatica.pSueno(durMin: 330, eficiencia: nil)).p, 75)
    }

    // MARK: Criterio 6 — VFC jamás cálida, ante ningún dato

    func testVFCJamasAlerta() {
        // Fixture extremo: TODO fuera, centinela corroborado con racha larga — y aun así VFC ninguna.
        let peor = read(autonomic: .low, sleep: .low,
                        sentinel: centinela(.corroborated, racha: 5))
        for prep in [nil, read(), peor] {
            XCTAssertEqual(HoyGramatica.severidad(senal: .hrv, prep: prep, razonCarga: 1.9),
                           .ninguna, "VFC no vota y JAMÁS alerta (§4)")
        }
    }

    func testBitacoraJamasAlerta() {
        let peor = read(autonomic: .low, sleep: .low, sentinel: centinela(.corroborated, racha: 3))
        for senal in [HoyGramatica.SenalID.strain, .steps, .stress] {
            XCTAssertEqual(HoyGramatica.severidad(senal: senal, prep: peor, razonCarga: 1.9),
                           .ninguna, "\(senal) no tiene valencia en Hoy")
        }
    }

    // MARK: Criterio 7 — carga 1.48 / 1.55 / 0.6

    func testCarga148FueraDelArcoSinAlerta() {
        let p = HoyGramatica.pCarga(razon: 1.48)
        XCTAssertEqual(p, 74, accuracy: 1e-9)
        XCTAssertFalse(HoyGramatica.arcoCarga.contains(p), "fuera de la zona dulce (p 40–65)")
        XCTAssertLessThan(p, 75, "pero antes del umbral de alerta (p 75)")
        XCTAssertEqual(HoyGramatica.severidad(senal: .carga, prep: read(), razonCarga: 1.48), .ninguna)
        XCTAssertEqual(HoyGramatica.estadoCarga(razon: 1.48), "carga.subiendo")
    }

    func testCarga155Ambar() {
        XCTAssertEqual(HoyGramatica.severidad(senal: .carga, prep: read(), razonCarga: 1.55), .atencion)
        XCTAssertEqual(HoyGramatica.estadoCarga(razon: 1.55), "carga.pico")
        // El umbral exacto (1.5) ya alerta y cae en p 75.
        XCTAssertEqual(HoyGramatica.severidad(senal: .carga, prep: read(), razonCarga: 1.5), .atencion)
        XCTAssertEqual(HoyGramatica.pCarga(razon: 1.5), 75)
    }

    func testCarga06DescargandoSinAlerta() {
        XCTAssertEqual(HoyGramatica.severidad(senal: .carga, prep: read(), razonCarga: 0.6), .ninguna,
                       "el lado bajo NUNCA alerta (§13.4)")
        XCTAssertEqual(HoyGramatica.estadoCarga(razon: 0.6), "carga.descargando")
    }

    func testCargaZonaDulceEstable() {
        XCTAssertEqual(HoyGramatica.estadoCarga(razon: 1.12), "carga.estable")
        XCTAssertTrue(HoyGramatica.arcoCarga.contains(HoyGramatica.pCarga(razon: 1.12)))
        XCTAssertEqual(HoyGramatica.estadoCarga(razon: nil), "carga.calibrando")
    }

    // MARK: Criterio 8 — sueño 8 h con eficiencia 72 %

    func testSuenoLargoConEficienciaPobre() throws {
        // 480 min es duración de sobra, pero eficiencia 0.72 < 0.80: lunita FIJA en p 80,
        // marcada como alerta por eficiencia (el sublabel «eficiencia 72 %» sale de este flag).
        let r = try XCTUnwrap(HoyGramatica.pSueno(durMin: 480, eficiencia: 0.72))
        XCTAssertEqual(r.p, 80)
        XCTAssertTrue(r.porEficiencia)
    }

    func testSuenoCortoNoUsaLaRamaDeEficiencia() throws {
        // Noche corta (300 < 375): manda la duración aunque la eficiencia también sea pobre.
        let r = try XCTUnwrap(HoyGramatica.pSueno(durMin: 300, eficiencia: 0.72))
        XCTAssertFalse(r.porEficiencia)
        XCTAssertGreaterThan(r.p, 75)
    }

    func testSuenoEficienciaJustoEnElPisoNoAlerta() throws {
        let r = try XCTUnwrap(HoyGramatica.pSueno(durMin: 480, eficiencia: 0.80))
        XCTAssertFalse(r.porEficiencia, "0.80 es el piso: solo POR DEBAJO alerta")
    }

    // MARK: Criterio 9 — calibrando / sin dato: jamás alerta

    func testSinDatoNoHayLunita() {
        XCTAssertNil(HoyGramatica.pSueno(durMin: nil, eficiencia: 0.9))
    }

    func testCalibrandoJamasAlerta() {
        // Sin Read (motor aún sin veredicto) o con ejes noData: ninguna señal alerta.
        for senal in HoyGramatica.SenalID.allCases {
            XCTAssertEqual(HoyGramatica.severidad(senal: senal, prep: nil, razonCarga: nil), .ninguna)
        }
        let sinDatos = read(autonomic: .noData, sleep: .noData, sentinel: nil)
        for senal in HoyGramatica.SenalID.allCases {
            XCTAssertEqual(HoyGramatica.severidad(senal: senal, prep: sinDatos, razonCarga: nil),
                           .ninguna, "\(senal): noData no es «fuera»")
        }
        XCTAssertNil(HoyGramatica.chipGuardian(sentinel: nil),
                     "sin lectura del par no se afirma calma")
    }

    // MARK: Criterio 10 — la máquina del chip del guardián, completa (5 estados)

    func testChipCalma() {
        XCTAssertEqual(HoyGramatica.chipGuardian(sentinel: centinela(.quiet, racha: 0)), .calma)
    }

    func testChipVigilandoUnaSenal() {
        XCTAssertEqual(HoyGramatica.chipGuardian(sentinel: centinela(.watchingOneSignal, racha: 1, señal: .temp)),
                       .vigilandoTemp)
        XCTAssertEqual(HoyGramatica.chipGuardian(sentinel: centinela(.watchingOneSignal, racha: 3, señal: .resp)),
                       .vigilandoResp, "una sola señal fuera es INFORMATIVO aunque lleve noches")
    }

    func testChipAmbasPrimeraNoche() {
        XCTAssertEqual(HoyGramatica.chipGuardian(sentinel: centinela(.corroborated, racha: 1)),
                       .ambasPrimeraNoche)
    }

    func testChipRachaConOrdinalReal() {
        XCTAssertEqual(HoyGramatica.chipGuardian(sentinel: centinela(.corroborated, racha: 2)),
                       .racha(noches: 2))
        XCTAssertEqual(HoyGramatica.chipGuardian(sentinel: centinela(.corroborated, racha: 4)),
                       .racha(noches: 4), "el ordinal es el REAL del centinela, jamás fijo")
    }

    // MARK: Criterio 13 — alarma SOLO el par con racha ≥ 2

    func testAlarmaSoloParConRacha() {
        let racha2 = read(sentinel: centinela(.corroborated, racha: 2))
        XCTAssertEqual(HoyGramatica.severidad(senal: .skintemp, prep: racha2, razonCarga: nil), .alarma)
        XCTAssertEqual(HoyGramatica.severidad(senal: .resp, prep: racha2, razonCarga: nil), .alarma)
        // 1.ª noche: atención, no alarma.
        let noche1 = read(sentinel: centinela(.corroborated, racha: 1))
        XCTAssertEqual(HoyGramatica.severidad(senal: .skintemp, prep: noche1, razonCarga: nil), .atencion)
        // Una sola señal fuera: ninguna (jamás sola, §4).
        let sola = read(sentinel: centinela(.watchingOneSignal, racha: 3, señal: .temp))
        XCTAssertEqual(HoyGramatica.severidad(senal: .skintemp, prep: sola, razonCarga: nil), .ninguna)
    }

    func testNingunaOtraSenalProduceAlarmaJamas() {
        // Fixture lo peor posible en todas las dimensiones: la única alarma sale del par.
        let peor = read(autonomic: .low, sleep: .low, sentinel: centinela(.corroborated, racha: 9))
        for senal in HoyGramatica.SenalID.allCases where senal != .skintemp && senal != .resp {
            XCTAssertNotEqual(HoyGramatica.severidad(senal: senal, prep: peor, razonCarga: 3.0),
                              .alarma, "\(senal) no puede producir alarma (§8: tabla exhaustiva)")
        }
    }

    func testSenalesQueVotanAlertanAtencion() {
        let r = read(autonomic: .low, sleep: .low)
        XCTAssertEqual(HoyGramatica.severidad(senal: .sleep, prep: r, razonCarga: nil), .atencion)
        XCTAssertEqual(HoyGramatica.severidad(senal: .rhr, prep: r, razonCarga: nil), .atencion)
    }

    // MARK: Criterio 30 — bordes p = 0 / 100 alcanzables por señal, según su piso documentado

    func testBordesDesviacionAlcanzables() {
        // Resp/temp/VFC: clamp estándar [0, 100] — ambos bordes alcanzables.
        XCTAssertEqual(HoyGramatica.pDesviacion(zMal: -4, zUmbral: 1.5), 0)
        XCTAssertEqual(HoyGramatica.pDesviacion(zMal: 4, zUmbral: 1.5), 100)
        // FC: piso izquierdo en p 25 («inusualmente bajo» se ESTACIONA en el borde del arco,
        // sin premio) — p 0 NO es alcanzable, por diseño documentado; p 100 sí.
        XCTAssertEqual(HoyGramatica.pDesviacion(zMal: -10, zUmbral: HoyGramatica.zUmbralFC,
                                                pisoIzquierdo: HoyGramatica.pisoFC), 25)
        XCTAssertEqual(HoyGramatica.pDesviacion(zMal: 10, zUmbral: HoyGramatica.zUmbralFC,
                                                pisoIzquierdo: HoyGramatica.pisoFC), 100)
    }

    func testBordesSuenoAlcanzables() throws {
        // Clamp [25, 100]: dormir de más nunca baja de 25; una noche brutalmente corta llega a 100.
        XCTAssertEqual(try XCTUnwrap(HoyGramatica.pSueno(durMin: 600, eficiencia: nil)).p, 25)
        XCTAssertEqual(try XCTUnwrap(HoyGramatica.pSueno(durMin: 0, eficiencia: nil)).p, 100)
        // Anclas exactas del §6.
        XCTAssertEqual(try XCTUnwrap(HoyGramatica.pSueno(durMin: 420, eficiencia: nil)).p, 50)
        XCTAssertEqual(try XCTUnwrap(HoyGramatica.pSueno(durMin: 375, eficiencia: nil)).p, 75)
    }

    func testBordesCargaAlcanzables() {
        XCTAssertEqual(HoyGramatica.pCarga(razon: 0), 0)
        XCTAssertEqual(HoyGramatica.pCarga(razon: 2.0), 100)
        XCTAssertEqual(HoyGramatica.pCarga(razon: 3.5), 100, "clamp arriba")
        // La zona dulce en espacio p sale de los cortes públicos (0.8 → 40, 1.3 → 65).
        XCTAssertEqual(HoyGramatica.arcoCarga.lowerBound, 40)
        XCTAssertEqual(HoyGramatica.arcoCarga.upperBound, 65)
    }

    // MARK: Formateo — «7:42», «+0.2° · 14.2», «—» vs «0», «8 432»

    func testFormatoDuracion() {
        XCTAssertEqual(HoyGramatica.formatoDuracion(462), "7:42")
        XCTAssertEqual(HoyGramatica.formatoDuracion(480), "8:00")
        XCTAssertEqual(HoyGramatica.formatoDuracion(65), "1:05")
        XCTAssertEqual(HoyGramatica.formatoDuracion(0), "0:00")
    }

    func testFormatoDeltaTempSiempreConSigno() {
        XCTAssertEqual(HoyGramatica.formatoDeltaTemp(0.2), "+0.2°")
        XCTAssertEqual(HoyGramatica.formatoDeltaTemp(0.9), "+0.9°")
        // FER-73 · H15: el negativo usa el MENOS tipográfico (U+2212), como el resto de la
        // pantalla, no el guion ASCII; y un delta que redondea a cero se escribe «0.0°», nunca
        // «-0.0°» (un cero con signo negativo se lee como «bajaste» sin haber bajado).
        XCTAssertEqual(HoyGramatica.formatoDeltaTemp(-0.4), "\u{2212}0.4°")
        XCTAssertEqual(HoyGramatica.formatoDeltaTemp(0.0), "0.0°")
        XCTAssertEqual(HoyGramatica.formatoDeltaTemp(-0.02), "0.0°")
        XCTAssertEqual(HoyGramatica.formatoDeltaTemp(0.04), "0.0°")
    }

    func testFormatoParGuardian() {
        XCTAssertEqual(HoyGramatica.formatoParGuardian(deltaTemp: 0.2, resp: 14.2), "+0.2° · 14.2")
        XCTAssertEqual(HoyGramatica.formatoParGuardian(deltaTemp: 0.9, resp: 17.0), "+0.9° · 17.0")
    }

    func testFormatoMilesConEspacioFino() {
        XCTAssertEqual(HoyGramatica.formatoMiles(8432), "8\u{202F}432")
        XCTAssertEqual(HoyGramatica.formatoMiles(12345), "12\u{202F}345")
        XCTAssertEqual(HoyGramatica.formatoMiles(1234567), "1\u{202F}234\u{202F}567")
        XCTAssertEqual(HoyGramatica.formatoMiles(432), "432", "sin agrupar bajo mil")
        // FER-125: los pasos de la Matriz se leen en miles con un decimal (la unidad la pone el módulo).
        XCTAssertEqual(HoyGramatica.formatoMilesK(6200, locale: Locale(identifier: "es_MX")), "6,2")
        XCTAssertEqual(HoyGramatica.formatoMilesK(6249, locale: Locale(identifier: "en_US")), "6.2")
        XCTAssertEqual(HoyGramatica.formatoMilesK(850, locale: Locale(identifier: "es_MX")), "0,9")
        XCTAssertEqual(HoyGramatica.formatoMilesK(12345, locale: Locale(identifier: "es_MX")), "12,3")
        XCTAssertEqual(HoyGramatica.formatoMiles(0), "0")
    }

    func testDashVsCeroReal() {
        // «—» = sin dato; «0» = dato real cero. La distinción del §4, sagrada en esfuerzo/pasos.
        XCTAssertEqual(HoyGramatica.valorODash(nil, formato: HoyGramatica.formatoMiles), "—")
        XCTAssertEqual(HoyGramatica.valorODash(0, formato: HoyGramatica.formatoMiles), "0")
        XCTAssertEqual(HoyGramatica.valorODash(8432, formato: HoyGramatica.formatoMiles), "8\u{202F}432")
    }
}
