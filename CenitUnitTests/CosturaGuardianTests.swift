import XCTest
import StrandAnalytics
import StrandDesign
import CenitStore
@testable import Cenit

// MARK: - La costura del guardián, bajo revisión adversarial (FER-81)
//
// Cada test fija un hallazgo de la revisión: son las mentiras que el dibujo YA cometió una vez.

final class CosturaGuardianTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c
    }
    private var now: Date {
        var c = DateComponents(); c.year = 2026; c.month = 8; c.day = 5; c.hour = 12
        return cal.date(from: c)!
    }
    private func dayKey(_ off: Int) -> String {
        let d = cal.date(byAdding: .day, value: off, to: cal.startOfDay(for: now))!
        let f = DateFormatter(); f.calendar = cal; f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
    private func metric(_ day: String, temp: Double?, resp: Double?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 430, efficiency: 0.9, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: 55, avgHrv: 45, recovery: nil,
                    strain: nil, exerciseCount: nil, skinTempDevC: temp, respRateBpm: resp, steps: 6000)
    }
    private func noche(_ day: String, tempOut: Bool = false, respOut: Bool = false,
                       tempMissing: Bool = false, respMissing: Bool = false,
                       respJudged: Bool = true) -> Preparedness.SentinelNight {
        .init(day: day, tempOut: tempOut, respOut: respOut, tempMissing: tempMissing,
              respMissing: respMissing, respJudged: respJudged, gapBefore: false)
    }
    private func prep(_ historia: [Preparedness.SentinelNight],
                      sentinel: Preparedness.SentinelRead? = nil) -> Preparedness.Read {
        Preparedness.Read(verdict: .full,
                          drivers: [.init(axis: .autonomic, state: .inRange, orientedZ: 0.2),
                                    .init(axis: .sleep, state: .inRange, orientedZ: nil)],
                          signalsPresent: 3, signalsTotal: 4, maturity: .trusted,
                          autonomicNights: 30, trend: nil,
                          sentinel: sentinel, sentinelHistory: historia)
    }
    private func costura(dias: [DailyMetric], historia: [Preparedness.SentinelNight],
                         sentinel: Preparedness.SentinelRead? = nil) -> [MatrizCostura.Noche] {
        let m = LiquidHoyBuilder.matriz(.init(prep: prep(historia, sentinel: sentinel),
                                              diasRecientes: dias, stressTrend: [], carga: nil,
                                              stepsEstimados: [], locale: Locale(identifier: "en_US"),
                                              calendar: cal, now: now))
        for b in m.bandas {
            if case .full(let s) = b, s.id == "guardian", case .costura(let n) = s.chart { return n }
        }
        XCTFail("el guardián debe dibujar la costura"); return []
    }

    /// ADVERSARIAL C1 · Una noche FRÍA no es una noche fuera. El centinela marca temperatura
    /// ALTA (y respiración ALTA); con `abs()` el dibujo abría la boca igual para −0.9 °C que
    /// para +0.9 °C, afirmando un «te saliste» que el motor jamás dijo.
    func test_C1_elLadoBuenoNoAbreLaBoca() {
        let dias = (-19...0).map { metric(dayKey($0), temp: $0 == 0 ? -0.9 : 0.05, resp: 14) }
        let historia = (-19...0).map { noche(dayKey($0)) }        // el motor: nada fuera
        let n = costura(dias: dias, historia: historia)
        let hoy = n.last!
        XCTAssertEqual(hoy.temp ?? 0, 0, accuracy: 0.001,
                       "una noche fría se queda junto al eje: el motor no la marcó")
        XCTAssertFalse(hoy.parFuera)
    }

    /// ADVERSARIAL C2 · Lo que no se midió no puede verse como lo perfecto.
    func test_C2_sinLecturaSeMarcaComoSinLectura() {
        let dias = (-19...0).map { metric(dayKey($0), temp: nil, resp: 14) }
        let n = costura(dias: dias, historia: (-19...0).map { noche(dayKey($0), tempMissing: true) })
        XCTAssertTrue(n.allSatisfy { $0.tempSinLectura }, "la temperatura nunca se leyó")
        XCTAssertTrue(n.allSatisfy { $0.temp == nil })
        XCTAssertTrue(n.allSatisfy { !$0.respSinLectura })
    }

    /// ADVERSARIAL P-1 · El dibujo se somete al JUICIO del motor: una noche que el motor marcó
    /// fuera se dibuja al menos en el filo, aunque la escala aproximada dijera otra cosa.
    func test_P1_laRespiracionMarcadaFueraSiempreLlegaAlFilo() {
        // 19 noches a 14 rpm y una a 14.4: la escala sola la vería «dentro», pero el motor la marcó.
        var dias = (-19...0).map { metric(dayKey($0), temp: 0.1, resp: 14) }
        dias[dias.count - 1] = metric(dayKey(0), temp: 0.1, resp: 14.4)
        var historia = (-19 ... -1).map { noche(dayKey($0)) }
        historia.append(noche(dayKey(0), respOut: true))
        let n = costura(dias: dias, historia: historia)
        XCTAssertGreaterThanOrEqual(n.last?.resp ?? 0, 1.0,
                                    "el motor la marcó fuera: el dibujo no puede contradecirlo")
    }

    /// ADVERSARIAL C3 · La base de la respiración no se contamina con las noches que el motor
    /// marcó fuera: si lo hiciera, diez noches enfermas correrían el centro y se volverían normales.
    func test_C3_lasNochesFueraNoMuevenLaBase() {
        let dias = (-19...0).map { off in metric(dayKey(off), temp: 0.1, resp: off >= -9 ? 17 : 14) }
        var historia = (-19 ... -10).map { noche(dayKey($0)) }
        historia += (-9...0).map { noche(dayKey($0), respOut: true) }
        let n = costura(dias: dias, historia: historia)
        let enfermas = n.suffix(10).compactMap { $0.resp }
        XCTAssertEqual(enfermas.count, 10)
        XCTAssertTrue(enfermas.allSatisfy { $0 >= 1.0 },
                      "las diez noches marcadas se dibujan fuera, no diluidas")
    }

    /// ADVERSARIAL C5 · «Solo una señal» solo cuando falta UNA. Sin ninguna, se dice eso.
    func test_C5_sinNingunaLecturaNoSeDiceSoloUnaSenal() {
        let sinNada = LiquidHoyBuilder.chipGuardianModelo(nil, noche: noche(dayKey(0), tempMissing: true,
                                                                            respMissing: true,
                                                                            respJudged: false),
                                                          hayLecturaHoy: false)
        XCTAssertEqual(sinNada?.texto, String(localized: "No readings yet"))
        let unaSola = LiquidHoyBuilder.chipGuardianModelo(nil, noche: noche(dayKey(0), respMissing: true,
                                                                            respJudged: false),
                                                          hayLecturaHoy: true)
        XCTAssertEqual(unaSola?.texto, String(localized: "Only one signal"))
    }

    /// ADVERSARIAL C4 · El par conserva su forma con una sola señal, para que cada número siga
    /// pintándose con el color de SU señal.
    func test_C4_elParConservaSuForma() {
        let dias = (-19...0).map { metric(dayKey($0), temp: nil, resp: 14.4) }
        let m = LiquidHoyBuilder.matriz(.init(prep: prep((-19...0).map { noche(dayKey($0), tempMissing: true) }),
                                              diasRecientes: dias, stressTrend: [], carga: nil,
                                              stepsEstimados: [], locale: Locale(identifier: "en_US"),
                                              calendar: cal, now: now))
        var valor = ""
        for b in m.bandas { if case .full(let s) = b, s.id == "guardian" { valor = s.valor } }
        XCTAssertEqual(valor, "— · 14.4", "el hueco ocupa el lugar de la señal que faltó")
    }
}
