import XCTest
import StrandAnalytics
import CenitDesign
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
                      sentinel: Preparedness.SentinelRead? = nil,
                      ajusteTermico: Double? = nil) -> Preparedness.Read {
        Preparedness.Read(verdict: .full,
                          drivers: [.init(axis: .autonomic, state: .inRange, orientedZ: 0.2),
                                    .init(axis: .sleep, state: .inRange, orientedZ: nil)],
                          signalsPresent: 3, signalsTotal: 4, maturity: .trusted,
                          autonomicNights: 30, trend: nil,
                          sentinel: sentinel, sentinelHistory: historia,
                          thermalAdjustedDevC: ajusteTermico)
    }
    private func costura(dias: [DailyMetric], historia: [Preparedness.SentinelNight],
                         sentinel: Preparedness.SentinelRead? = nil,
                         ajusteTermico: Double? = nil) -> [MatrizCostura.Noche] {
        let m = LiquidHoyBuilder.matriz(.init(prep: prep(historia, sentinel: sentinel,
                                                         ajusteTermico: ajusteTermico),
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
        // Segunda vuelta (COS-4): el contrato ya no es «vale 0» —recortar a 0 aplanaba media
        // serie sobre el eje y afirmaba «justo en tu centro»— sino «es negativo», que es lo que
        // el dibujo aprieta contra el eje sin que llegue nunca a parecer que te saliste.
        XCTAssertLessThan(hoy.temp ?? 0, 0, "una noche fría es negativa, no cero")
        XCTAssertLessThan(MatrizCostura.fraccionFilo(hoy.temp!), MatrizCostura.fraccionFilo(1) / 2,
                          "el lado bajo jamás puede leerse tan lejos como el filo de tu banda")
        XCTAssertFalse(hoy.parFuera)
    }

    /// ADVERSARIAL COS-4 · Dos noches BAJAS distintas no pueden dibujarse al mismo alto. El
    /// `max(0, …)` de la primera vuelta las mandaba a las dos al eje mientras el scrub anunciaba
    /// «−0.4°» y «−0.1°» sobre puntos idénticos.
    func test_COS4_dosNochesBajasNoCaenEnElMismoPixel() {
        var dias = (-19...0).map { metric(dayKey($0), temp: -0.1, resp: 14) }
        dias[0] = metric(dayKey(-19), temp: -0.5, resp: 14)
        let n = costura(dias: dias, historia: (-19...0).map { noche(dayKey($0)) })
        let baja = MatrizCostura.fraccionFilo(n[0].temp!)
        let leve = MatrizCostura.fraccionFilo(n[1].temp!)
        XCTAssertGreaterThan(baja, leve + 0.02, "−0.5 °C y −0.1 °C tienen que distinguirse")
    }

    /// ADVERSARIAL COS-2 · Con lectura pero SIN escala (menos de 3 noches de respiración) la
    /// orilla se callaba… y aun así se dibujaba pegada al eje con la joya de HOY encima, que es
    /// exactamente la mentira que C2 decía haber matado.
    func test_COS2_conLecturaPeroSinEscalaLaOrillaSeCalla() {
        // Solo 2 noches con respiración: no hay mediana ni MAD que sostengan una escala.
        let dias = (-19...0).map { d in metric(dayKey(d), temp: 0.1, resp: d >= -1 ? 14 : nil) }
        let n = costura(dias: dias, historia: (-19...0).map { noche(dayKey($0), respMissing: true,
                                                                   respJudged: false) })
        XCTAssertTrue(n.allSatisfy { $0.resp == nil }, "sin escala no hay dónde poner la noche")
        XCTAssertTrue(n.allSatisfy { $0.respSinLectura },
                      "y si no hay dónde ponerla, la orilla se interrumpe: nada de joya de HOY")
    }

    /// ADVERSARIAL COS-1 (tercera vuelta) · El ÁMBAR es el juicio del motor y no puede
    /// depender de que el dibujo tenga con qué pintar la boca: sin escala de respiración, la
    /// orilla azul se calla —correcto— pero la noche en que el par votó tiene que seguir
    /// marcada, o el sello se pone ámbar y la gráfica no lo respalda.
    func test_COS1_elAmbarSobreviveAunqueLaOrillaSeCalle() {
        // Respiración solo en 2 noches: no hay escala. Y el motor marcó el par fuera HOY.
        let dias = (-19...0).map { d in metric(dayKey(d), temp: 0.9, resp: d >= -1 ? 15 : nil) }
        var historia = (-19 ... -1).map { noche(dayKey($0), respMissing: true, respJudged: false) }
        historia.append(noche(dayKey(0), tempOut: true, respOut: true))
        let n = costura(dias: dias, historia: historia)
        XCTAssertTrue(n.last?.parFuera ?? false,
                      "el par votó: el dibujo tiene que saberlo aunque no pueda colocar la orilla")
        XCTAssertTrue(n.last?.respSinLectura ?? false, "…y aun así la orilla azul se calla")
    }

    /// ADVERSARIAL A1/A3 (motor) · H6 selló el héroe pero no la Matriz: pasada la medianoche la
    /// última casilla es el día NUEVO, y plantar ahí el ajuste térmico de anteanoche hacía que
    /// el guardián mostrara una temperatura que el héroe ya no muestra.
    func test_A3_elAjusteTermicoNoSePlantaEnUnDiaQueElMotorNoJuzgo() {
        // El motor juzgó AYER (su historia termina en −1); hoy todavía no tiene fila.
        let dias = (-19 ... -1).map { metric(dayKey($0), temp: 0.05, resp: 14) }
        let historia = (-19 ... -1).map { noche(dayKey($0)) }
        let n = costura(dias: dias, historia: historia, ajusteTermico: 0.9)
        XCTAssertTrue(n.last?.tempSinLectura ?? false,
                      "la casilla de hoy no tiene lectura: el ajuste de anoche no puede ocuparla")
    }

    /// ADVERSARIAL A-2 · La temperatura también se ancla: si el motor la marcó alta, el labio
    /// llega al filo aunque la cifra cruda del día se quede corta (p. ej. porque el ajuste de
    /// fase movió el número que se juzgó).
    func test_A2_laTemperaturaMarcadaFueraSiempreLlegaAlFilo() {
        let dias = (-19...0).map { metric(dayKey($0), temp: $0 == 0 ? 0.5 : 0.05, resp: 14) }
        var historia = (-19 ... -1).map { noche(dayKey($0)) }
        historia.append(noche(dayKey(0), tempOut: true))
        let n = costura(dias: dias, historia: historia)
        XCTAssertGreaterThanOrEqual(n.last?.temp ?? 0, 1.0)
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

    /// ADVERSARIAL COSTURA-1 (tercera vuelta) · El ÁMBAR es el juicio del motor y no puede
    /// depender de que el dibujo tenga con qué pintar la boca. Con respiración leída pero sin
    /// escala usable, el arreglo hermano (COS-2) dejaba las 20 noches sin orilla azul ⇒ boca
    /// vacía ⇒ el ámbar se recortaba contra la nada, mientras el sello del guardián seguía en
    /// ámbar y el chip seguía diciendo que el par votó.
    func test_COSTURA1_elParFueraSobreviveAunqueLaRespiracionNoTengaEscala() {
        // Respiración solo en 2 noches: no hay mediana ni MAD ⇒ sin escala.
        let dias = (-19...0).map { d in metric(dayKey(d), temp: d == 0 ? 1.2 : 0.05,
                                               resp: d >= -1 ? 17 : nil) }
        var historia = (-19 ... -1).map { noche(dayKey($0)) }
        historia.append(noche(dayKey(0), tempOut: true, respOut: true))
        let n = costura(dias: dias, historia: historia)
        XCTAssertTrue(n.last?.parFuera ?? false,
                      "el día que el guardián empuja tu día no puede desaparecer del dibujo")
        XCTAssertTrue(n.allSatisfy { $0.respSinLectura }, "sin escala, la orilla azul se calla")
    }

    /// ADVERSARIAL COS4-A1 (cuarta vuelta) · El invariante del hueco vale para TODAS las
    /// noches, no solo para las juzgadas. El ancla se condicionaba a `respJudged`, o sea que se
    /// apagaba sola justo cuando el motor no tiene opinión — y entonces la escala aproximada
    /// podía mandar una noche SIN JUICIO más lejos del eje que una que el guardián sí marcó,
    /// cruzando entero el hueco que existe para impedirlo. Le pasa a todo usuario en sus
    /// primeras cuatro noches.
    func test_COSTURA_A1_unaNocheSinJuicioJamasCruzaElHueco() {
        // 6 noches: una de 17.8 rpm entre puras de ~14, y el motor sin juicio en ninguna.
        var dias = (-5...0).map { metric(dayKey($0), temp: 0.05, resp: 14.1) }
        dias[1] = metric(dayKey(-4), temp: 0.05, resp: 17.8)
        let historia = (-5...0).map { noche(dayKey($0), respJudged: false) }
        let n = costura(dias: dias, historia: historia)
        let sospechosa = n[1].resp ?? 0
        XCTAssertLessThanOrEqual(sospechosa, 0.98,
                                 "sin juicio del motor, ninguna noche puede pasar del filo")
        XCTAssertLessThan(MatrizCostura.fraccionFilo(sospechosa),
                          MatrizCostura.fraccionFilo(1.02),
                          "y jamás puede dibujarse más lejos que una noche que el motor SÍ marcó")
    }

    /// ADVERSARIAL L3-1 (quinta vuelta) · La noche que el motor no pudo juzgar se CALLA. El
    /// arreglo de la cuarta vuelta la apretaba a ≤0.98, o sea que la dibujaba DENTRO de tu
    /// banda: cambiaba una mentira por su espejo, y encima afirmativa —con orilla, boca y joya—
    /// mientras el chip decía «Conociéndote» y la hoja del guardián la dibujaba «sin dato».
    func test_L3_1_laNocheSinJuicioNoSeDibujaNiFueraNiDentro() {
        var dias = (-5...0).map { metric(dayKey($0), temp: 0.05, resp: 14.1) }
        dias[1] = metric(dayKey(-4), temp: 0.05, resp: 17.8)
        let n = costura(dias: dias, historia: (-5...0).map { noche(dayKey($0), respJudged: false) })
        XCTAssertTrue(n.allSatisfy { $0.resp == nil },
                      "sin juicio del motor no hay dónde poner la noche: la orilla se interrumpe")
        XCTAssertTrue(n.allSatisfy { $0.respSinLectura })
        // La TEMPERATURA sí se dibuja: su corte es público y absoluto (±0.8 °C) sobre una
        // desviación ya normalizada contra tu base, así que su posición significa lo mismo con
        // o sin veredicto del centinela. Es la asimetría que justifica tratarlas distinto.
        XCTAssertTrue(n.contains { $0.temp != nil })
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
