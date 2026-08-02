import XCTest
import SwiftUI
import StrandAnalytics
import StrandDesign
@testable import Cenit

// LiquidHoyBuilderTests.swift — FER-1045 «Hoy Liquid».
//
// El builder es la proyección PURA del estado ya derivado al modelo Liquid. Estos fixtures
// fijan la PARIDAD contra el código actual de TodayView: la tabla canónica del héroe (el
// if-chain de `heroBlock`), el port de `needles()` (posiciones idénticas), el mapeo ACWR de
// la franja (`TrainingLoadStrip`) y el contexto delta de los tiles (`tileContext`).

final class LiquidHoyBuilderTests: XCTestCase {

    // MARK: Fixtures

    private func read(verdict: Preparedness.Verdict,
                      drivers: [Preparedness.Driver],
                      nights: Int = 21,
                      maturity: BaselineStatus = .trusted) -> Preparedness.Read {
        Preparedness.Read(verdict: verdict, drivers: drivers, signalsPresent: 3,
                          signalsTotal: 4, maturity: maturity, autonomicNights: nights,
                          trend: nil)
    }

    private func driver(_ axis: Preparedness.Axis, _ state: Preparedness.AxisState,
                        z: Double? = nil) -> Preparedness.Driver {
        Preparedness.Driver(axis: axis, state: state, orientedZ: z)
    }

    private var nocheAnclada: [Preparedness.Driver] {
        [driver(.autonomic, .inRange, z: 0.2), driver(.sleep, .inRange), driver(.thermal, .inRange)]
    }

    // MARK: Héroe — tabla canónica (paridad con `TodayView.heroBlock`)

    func test_hero_full_nocturno_esVeredictoVerde() {
        let (hero, route) = LiquidHoyBuilder.hero(
            prep: read(verdict: .full, drivers: nocheAnclada), sleepMin: 440, nights: 21)
        guard case .veredicto(let title, let highlight, let tone, _, let confianza) = hero else {
            return XCTFail("esperaba .veredicto")
        }
        XCTAssertTrue(title.contains(highlight), "el resalte debe vivir dentro del título")
        XCTAssertEqual(tone, LiquidColor.verdePrimario)
        XCTAssertNil(confianza, "con 21 noches el tether se retira")
        XCTAssertEqual(route, .autonomic)
    }

    func test_hero_caution_ambar_y_easy_rojo() {
        // D1 resuelta por el dueño: caution = ámbar, easy = ROJO (como el clásico).
        for (verdict, esperado) in [(Preparedness.Verdict.caution, LiquidColor.atencion),
                                    (.easy, LiquidColor.negativo)] {
            let (hero, _) = LiquidHoyBuilder.hero(
                prep: read(verdict: verdict, drivers: nocheAnclada), sleepMin: nil, nights: 21)
            guard case .veredicto(let title, let highlight, let tone, _, _) = hero else {
                return XCTFail("esperaba .veredicto para \(verdict)")
            }
            XCTAssertTrue(title.contains(highlight), "\(verdict): resalte ⊆ título")
            XCTAssertEqual(tone, esperado, "\(verdict)")
        }
    }

    func test_ambiente_semantico() {
        XCTAssertEqual(LiquidHoyBuilder.ambiente(
            prep: read(verdict: .full, drivers: nocheAnclada)), .bien)
        XCTAssertEqual(LiquidHoyBuilder.ambiente(
            prep: read(verdict: .caution, drivers: nocheAnclada)), .atencion)
        XCTAssertEqual(LiquidHoyBuilder.ambiente(
            prep: read(verdict: .easy, drivers: nocheAnclada)), .alerta)
        XCTAssertEqual(LiquidHoyBuilder.ambiente(prep: nil), .neutro)
        XCTAssertEqual(LiquidHoyBuilder.ambiente(
            prep: read(verdict: .lowSignal, drivers: [], maturity: .calibrating)), .neutro)
    }

    func test_hero_confianza_soloBajo21Noches() {
        let (hero, _) = LiquidHoyBuilder.hero(
            prep: read(verdict: .full, drivers: nocheAnclada, nights: 12), sleepMin: nil, nights: 12)
        guard case .veredicto(_, _, _, _, let confianza) = hero else {
            return XCTFail("esperaba .veredicto")
        }
        XCTAssertNotNil(confianza)
        XCTAssertTrue(confianza?.contains("12") == true)
    }

    func test_hero_sinNocheGrabada_esLecturaDeDia() {
        // El eje de sueño sin datos → isNightAnchored == false → demotado, tap autonómico.
        let drivers = [driver(.autonomic, .inRange, z: 0.1), driver(.sleep, .noData),
                       driver(.thermal, .inRange)]
        let (hero, route) = LiquidHoyBuilder.hero(
            prep: read(verdict: .full, drivers: drivers), sleepMin: nil, nights: 21)
        guard case .demotado(let kicker, _, _) = hero else {
            return XCTFail("esperaba .demotado (lectura de día)")
        }
        XCTAssertNotNil(kicker)
        XCTAssertEqual(route, .autonomic)
    }

    func test_hero_lowSignal_yPrepNil_sonAunSinDatos_jamasSuenoNiBajaSenal() {
        // Decisión del dueño (sesión /inject 2026-07-22): sin veredicto NO hay héroe de
        // sueño — SIEMPRE «aún sin datos suficientes», aunque exista sueño grabado.
        let (heroLow, routeLow) = LiquidHoyBuilder.hero(
            prep: read(verdict: .lowSignal, drivers: [], maturity: .calibrating),
            sleepMin: 440, nights: 2)
        guard case .demotado(_, let title, _) = heroLow else {
            return XCTFail("esperaba .demotado (sin datos)")
        }
        // El copy pasó de «Aún sin datos suficientes» a «Aún no conozco tu base» (pasada
        // UX H4: decía «sin datos» encima de ocho tiles LLENOS de datos; lo que falta es
        // la base). Lo que el test protege es la INVARIANTE, no la redacción: jamás la
        // hora de sueño, y siempre un titular que hable de la base que falta.
        XCTAssertFalse(title.contains(":"), "jamás la hora de sueño: \(title)")
        XCTAssertTrue(title.localizedCaseInsensitiveContains("base") ||
                      title.localizedCaseInsensitiveContains("baseline"), title)
        XCTAssertEqual(routeLow, .autonomic)

        // prep == nil → mismo estado honesto, mismo destino.
        let (heroNil, routeNil) = LiquidHoyBuilder.hero(prep: nil, sleepMin: nil, nights: 0)
        guard case .demotado(_, let titleNil, _) = heroNil else {
            return XCTFail("esperaba .demotado (sin datos)")
        }
        XCTAssertEqual(titleNil, title, "con o sin sueño grabado, el mismo copy honesto")
        XCTAssertEqual(routeNil, .autonomic)
    }

    /// El veredicto solo se calcula en el pase COMPLETO (`Repository.performRefresh(full:)`), así que
    /// en el primer pintado llega `nil`. Sin distinguir ese caso, el héroe caía al fallback y le decía
    /// «Todavía no conozco tu base» a un usuario con AÑOS de historia, en CADA arranque en frío: una
    /// frase falsa. `verdictPending` separa «todavía no lo calculo» de «no tengo base».
    func test_hero_verdictPending_diceQueLeeNoQueNoTeConoce() {
        let (heroPending, routePending) = LiquidHoyBuilder.hero(
            prep: nil, sleepMin: 440, nights: 0, verdictPending: true)
        guard case .demotado(_, let titlePending, _) = heroPending else {
            return XCTFail("esperaba .demotado (leyendo)")
        }
        // La invariante, no la redacción: mientras calcula NO puede afirmar que no conoce tu base.
        XCTAssertFalse(titlePending.localizedCaseInsensitiveContains("base"),
                       "mientras calcula no puede decir que no conoce tu base: \(titlePending)")
        XCTAssertFalse(titlePending.localizedCaseInsensitiveContains("baseline"), titlePending)
        XCTAssertEqual(routePending, .autonomic)

        // Y el estado honesto de «sin base» sigue intacto cuando NO está pendiente: son distintos.
        let (heroNoBase, _) = LiquidHoyBuilder.hero(prep: nil, sleepMin: 440, nights: 0,
                                                    verdictPending: false)
        guard case .demotado(_, let titleNoBase, _) = heroNoBase else {
            return XCTFail("esperaba .demotado (sin base)")
        }
        XCTAssertNotEqual(titlePending, titleNoBase,
                          "«leyendo» y «no conozco tu base» son dos estados distintos")

        // Y un veredicto REAL le gana a `verdictPending`: la bandera solo aplica cuando no hay nada
        // que mostrar. Amarra el contrato de la función pura (en producción el llamador ya calcula
        // `prep == nil && !fullyLoaded`, pero aquí no dependemos de eso).
        let anclado = read(verdict: .full,
                           drivers: [.init(axis: .sleep, state: .inRange, orientedZ: nil)],
                           maturity: .trusted)
        let (heroReal, _) = LiquidHoyBuilder.hero(prep: anclado, sleepMin: 440, nights: 20,
                                                  verdictPending: true)
        if case .demotado = heroReal {
            XCTFail("con veredicto real no puede caer a «leyendo»: el dato gana a la bandera")
        }
    }

    // MARK: Señales — port literal de `needles()`

    func test_senales_posicionesIdenticasALasAgujas() {
        // positionFromZ: 0.5 + z/4, acotado 0.06–0.94.
        XCTAssertEqual(LiquidHoyBuilder.positionFromZ(0.8), 0.7, accuracy: 1e-9)
        XCTAssertEqual(LiquidHoyBuilder.positionFromZ(-3), 0.06, accuracy: 1e-9)
        XCTAssertEqual(LiquidHoyBuilder.positionFromZ(3), 0.94, accuracy: 1e-9)
        XCTAssertEqual(LiquidHoyBuilder.positionFromZ(nil), 0.5, accuracy: 1e-9)
        // positionFromState: categórico.
        XCTAssertEqual(LiquidHoyBuilder.positionFromState(.inRange), 0.5)
        XCTAssertEqual(LiquidHoyBuilder.positionFromState(.low), 0.2)
        XCTAssertEqual(LiquidHoyBuilder.positionFromState(.high), 0.8)
    }

    func test_senales_dosOrbes_sinTermico() {
        // FER-1047: la fila pasó de tres a DOS orbes; el térmico salió (vive en el guardián).
        let prep = read(verdict: .caution, drivers: [
            driver(.autonomic, .low, z: -1.2), driver(.sleep, .noData), driver(.thermal, .inRange),
        ])
        let senales = LiquidHoyBuilder.senales(prep: prep, valores: (rhr: "52 bpm", sueno: nil))
        XCTAssertEqual(senales.map(\.id), ["autonomico", "sueno"], "dos orbes, sin térmico")

        // Primer orbe = EN REPOSO con su dato (lpm), NUNCA «3 señales».
        XCTAssertEqual(senales[0].valor, "52 bpm")
        XCTAssertNotEqual(senales[0].caption, "3 SEÑALES")
        XCTAssertFalse(senales[0].caption.contains("3"))
        // Autonómico fuera → atención, posición del z.
        XCTAssertEqual(senales[0].state, .atencion)
        XCTAssertEqual(senales[0].progress ?? -1, 0.5 - 1.2 / 4, accuracy: 1e-9)
        // Sueño sin datos → sin progreso (el eje no vota).
        XCTAssertNil(senales[1].progress)
    }

    // MARK: Guardián (FER-1047) — vigila pero no vota; refleja los cortes del centinela

    /// Un `Read` con un SignalRead de respiración con la z orientada dada (+ = mejor que la base;
    /// una respiración ALTA/mala es z orientada NEGATIVA).
    private func readConResp(thermal: Preparedness.AxisState, respOrientedZ: Double?,
                             sentinel: Preparedness.SentinelRead? = nil)
        -> Preparedness.Read {
        let signals = [Preparedness.SignalRead(signal: .resp, orientedZ: respOrientedZ,
                                               share: 0, flaggedAlone: false)]
        return Preparedness.Read(
            verdict: .full,
            drivers: [driver(.autonomic, .inRange, z: 0.2), driver(.sleep, .inRange),
                      driver(.thermal, thermal)],
            signals: signals, signalsPresent: 3, signalsTotal: 4,
            maturity: .trusted, autonomicNights: 21, trend: nil, sentinel: sentinel)
    }

    func test_guardian_tranquilo_ceroColor() {
        let g = LiquidHoyBuilder.guardian(
            prep: readConResp(thermal: .inRange, respOrientedZ: 0.3),
            thermalDeviation: 0.1, resp: .init(14))
        XCTAssertEqual(g?.estado, .tranquilo)
        XCTAssertEqual(g?.temp, "+0.1°")
        XCTAssertEqual(g?.resp, "14 rpm")
    }

    func test_guardian_unaFuera_soloEsaSeTiñe_yVeredictoNoCambia() {
        // Temp alta (driver térmico .high) pero respiración en rango → solo temp fuera; el motor
        // NO deja votar al centinela con una sola señal (el veredicto se decide aparte).
        let soloTemp = LiquidHoyBuilder.guardian(
            prep: readConResp(thermal: .high, respOrientedZ: 0.0),
            thermalDeviation: 0.9, resp: .init(14))
        XCTAssertEqual(soloTemp?.estado, .tempFuera)

        // Respiración alta (z orientada ≤ −respBadZ) pero temp en rango → solo resp fuera.
        let badZ = Preparedness.Config.default.respBadZ
        let soloResp = LiquidHoyBuilder.guardian(
            prep: readConResp(thermal: .inRange, respOrientedZ: -badZ),
            thermalDeviation: 0.1, resp: .init(19))
        XCTAssertEqual(soloResp?.estado, .respFuera)
    }

    func test_guardian_juntas_franjaSeTiñe() {
        let badZ = Preparedness.Config.default.respBadZ
        let g = LiquidHoyBuilder.guardian(
            prep: readConResp(thermal: .high, respOrientedZ: -badZ - 0.1),
            thermalDeviation: 0.9, resp: .init(19))
        XCTAssertEqual(g?.estado, .juntas, "temp + resp fuera JUNTAS = el centinela del motor")
    }

    func test_guardian_juntas_racha_muestraNoches() {
        // FER-12: con la racha del centinela (>= 2 noches JUNTAS), el rótulo agrega el conteo
        // factual; con 1 noche se queda como hoy. La salience no cambia (no se testea color aquí).
        let badZ = Preparedness.Config.default.respBadZ
        func juntas(streak: Int) -> LiquidHoyModel.Guardian? {
            let s = Preparedness.SentinelRead(state: .corroborated, streakNights: streak,
                                              watchingSignal: nil, tempOut: true, respOut: true)
            return LiquidHoyBuilder.guardian(
                prep: readConResp(thermal: .high, respOrientedZ: -badZ - 0.1, sentinel: s),
                thermalDeviation: 0.9, resp: .init(19))
        }
        let g3 = juntas(streak: 3)
        XCTAssertEqual(g3?.estado, .juntas)
        XCTAssertTrue(g3?.label.contains("3") ?? false, "el rótulo debe incluir el conteo de noches")
        XCTAssertTrue(g3?.label.contains(String(localized: "nights")) ?? false)
        // 1 noche: sin conteo, como hoy.
        XCTAssertEqual(juntas(streak: 1)?.label, String(localized: "Together"))
    }

    func test_guardian_sinLecturas_noSeMuestra() {
        XCTAssertNil(LiquidHoyBuilder.guardian(prep: nil, thermalDeviation: nil, resp: nil))
        // Con al menos una lectura, se muestra (siempre visible).
        XCTAssertNotNil(LiquidHoyBuilder.guardian(prep: nil, thermalDeviation: 0.1, resp: nil))
    }

    // MARK: Carga — mismo mapeo que la franja

    func test_carga_mapeoACWR() {
        XCTAssertNil(LiquidHoyBuilder.carga(nil), "sin modelo sembrado → sin barra")

        guard case .calibrando = LiquidHoyBuilder.carga(
            TrainingLoadModel(acwr: nil, series: []))! else {
            return XCTFail("acwr nil → calibrando")
        }

        // El caso del ensamble: 1.03 → equilibrio, knob 51.5, ok.
        guard case .medida(let pos, let zone, _, let ratio, _, let state) = LiquidHoyBuilder.carga(
            TrainingLoadModel(acwr: 1.03, series: []))! else {
            return XCTFail("esperaba .medida")
        }
        XCTAssertEqual(pos, 51.5, accuracy: 1e-9)
        XCTAssertEqual(zone, 1)
        XCTAssertEqual(ratio, "1.03", "el ratio viaja separado del rótulo (pasada UI)")
        XCTAssertEqual(state, .ok)

        // Las zonas siguen al motor (el oráculo es `loadBand`), knob clampeado 0.05–0.95.
        for (ratio, expectedZone, okEsperado) in [(0.7, 0, false), (1.4, 2, false), (1.9, 3, false)] {
            guard case .medida(let p, let z, _, _, _, let s) = LiquidHoyBuilder.carga(
                TrainingLoadModel(acwr: ratio, series: []))! else {
                return XCTFail("esperaba .medida para \(ratio)")
            }
            XCTAssertEqual(z, expectedZone, "ratio \(ratio)")
            XCTAssertEqual(s == .ok, okEsperado, "ratio \(ratio)")
            XCTAssertEqual(p, min(max(ratio / 2, 0.05), 0.95) * 100, accuracy: 1e-9)
        }
    }

    // MARK: Contexto delta — port literal de `tileContext`

    func test_contexto_portDeTileContext() {
        // Sin valor de hoy → nil (sin pie).
        XCTAssertNil(LiquidHoyBuilder.contexto(today: nil, history: [1, 2, 3, 4, 5],
                                               betterHigher: true, deadband: 1) { "\($0)" })
        // <4 días de base → armando.
        XCTAssertEqual(LiquidHoyBuilder.contexto(today: 50, history: [48, 49, 50],
                                                 betterHigher: true, deadband: 1) { "\($0)" },
                       .building)
        // Dentro del deadband → «En tu base», neutro.
        guard case .ready(_, let toneBase) = LiquidHoyBuilder.contexto(
            today: 50.5, history: [50, 50, 50, 50], betterHigher: true, deadband: 1,
            format: { "\($0)" })! else { return XCTFail() }
        XCTAssertEqual(toneBase, .neutral)
        // Arriba y «más es mejor» → favorable (+).
        guard case .ready(let upText, let upTone) = LiquidHoyBuilder.contexto(
            today: 56, history: [50, 50, 50, 50], betterHigher: true, deadband: 1,
            format: { "\(Int($0)) ms" })! else { return XCTFail() }
        XCTAssertEqual(upTone, .up)
        XCTAssertTrue(upText.hasPrefix("+6 ms"))
        // Arriba y «más es PEOR» (FC en reposo) → desfavorable.
        guard case .ready(_, let downTone) = LiquidHoyBuilder.contexto(
            today: 56, history: [50, 50, 50, 50], betterHigher: false, deadband: 1,
            format: { "\(Int($0))" })! else { return XCTFail() }
        XCTAssertEqual(downTone, .down)
        // Sin valencia → neutro, con el signo −.
        guard case .ready(let nText, let nTone) = LiquidHoyBuilder.contexto(
            today: 44, history: [50, 50, 50, 50], betterHigher: nil, deadband: 1,
            format: { "\(Int($0))" })! else { return XCTFail() }
        XCTAssertEqual(nTone, .neutral)
        XCTAssertTrue(nText.hasPrefix("\u{2212}6"))
    }

    // MARK: Métricas — ids, tonos y formatos

    func test_metricas_idsOrdenYTonos() {
        var inputs = LiquidHoyBuilder.Inputs()
        inputs.sleep = .init(440)
        inputs.hrv = .init(56)
        inputs.rhr = .init(52)
        inputs.strain = 10.0
        inputs.steps = 8432
        inputs.skinTemp = .init(0.1)
        inputs.resp = .init(14.5)
        inputs.stress = 0.5
        let tiles = LiquidHoyBuilder.metricas(inputs)

        XCTAssertEqual(tiles.map(\.id),
                       ["sleep", "hrv", "rhr", "strain", "steps", "skintemp", "resp", "stress"])
        XCTAssertEqual(tiles[0].value, "7:20")
        XCTAssertEqual(tiles[0].tone, LiquidColor.indigo)
        XCTAssertEqual(tiles[1].tone, LiquidColor.cian)
        XCTAssertEqual(tiles[2].tone, LiquidColor.rosa)
        XCTAssertEqual(tiles[3].tone, LiquidColor.ambar)
        XCTAssertEqual(tiles[4].tone, LiquidColor.teal)
        XCTAssertEqual(tiles[5].tone, LiquidColor.ambar)
        XCTAssertEqual(tiles[5].value, "+0.1")
        XCTAssertEqual(tiles[6].tone, LiquidColor.azul)
        XCTAssertEqual(tiles[7].tone, LiquidColor.verdePrimario, "estrés bajo → verde")
    }

    func test_metricas_sinValor_yOrigenes() {
        var inputs = LiquidHoyBuilder.Inputs()
        inputs.steps = 4200
        inputs.stepsEstimated = true
        inputs.strain = 8.0
        inputs.strainEstimated = true
        let tiles = LiquidHoyBuilder.metricas(inputs)

        // Sin lectura → «—» apagado a tinta500.
        XCTAssertEqual(tiles[0].value, "—")
        XCTAssertEqual(tiles[0].tone, LiquidColor.tinta500)
        // Pasos estimados → origen calculado + «est.»; esfuerzo estimado (FER-883) → medido.
        XCTAssertEqual(tiles[4].origen, .calculado)
        XCTAssertFalse(tiles[4].unit.isEmpty)
        XCTAssertEqual(tiles[3].origen, .medido)
        // Estrés siempre calculado en tu teléfono.
        XCTAssertEqual(tiles[7].origen, .calculado)
    }

    func test_stressTone_bandas() {
        XCTAssertEqual(LiquidHoyBuilder.stressTone(0.5), LiquidColor.verdePrimario)
        XCTAssertEqual(LiquidHoyBuilder.stressTone(1.5), LiquidColor.atencion)
        XCTAssertEqual(LiquidHoyBuilder.stressTone(2.5), LiquidColor.negativo)
    }

    // MARK: Kicker y dial

    func test_kicker_esMX() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let date = DateComponents(calendar: cal, year: 2026, month: 7, day: 22, hour: 8).date!
        let kicker = LiquidHoyBuilder.kicker(now: date, calendar: cal,
                                             locale: Locale(identifier: "es_MX"))
        XCTAssertTrue(kicker.contains("22"), kicker)
        XCTAssertFalse(kicker.contains(","), "sin coma: \(kicker)")
        XCTAssertEqual(kicker, kicker.uppercased(with: Locale(identifier: "es_MX")))
    }

    func test_markerHour() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let date = DateComponents(calendar: cal, year: 2026, month: 7, day: 22,
                                  hour: 8, minute: 30).date!
        XCTAssertEqual(LiquidHoyBuilder.markerHour(now: date, calendar: cal), 8.5,
                       accuracy: 1e-9)
    }

    // MARK: i18n — el resalte vive dentro del título en TODOS los locales del catálogo

    func test_highlights_dentroDelTitulo_enCatalogo() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Cenit/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])

        func value(_ key: String, _ lang: String) -> String? {
            let entry = strings[key] as? [String: Any]
            let locs = entry?["localizations"] as? [String: Any]
            let unit = (locs?[lang] as? [String: Any])?["stringUnit"] as? [String: Any]
            return unit?["value"] as? String
        }

        let pares = [("Go all in", "hero.highlight.full"),
                     ("Good, one thing to watch", "hero.highlight.caution"),
                     ("Take it easy", "hero.highlight.easy"),
                     // La cláusula en negrita del acta vive dentro de su método —
                     // el párrafo que SÍ renderiza `LiquidHoyBuilder.acta` (v3, FER-5/FER-9:
                     // respiración salió del voto y «solo vigila»), no el copy anterior.
                     ("Your resting heart rate and your sleep are read as separate votes, so one rough night can't count against you twice. Your breathing and temperature only keep watch. They don't vote here.",
                      "acta.metodo.clave")]
        for lang in ["en", "es"] {
            for (titleKey, highlightKey) in pares {
                let title = try XCTUnwrap(value(titleKey, lang), "\(titleKey) [\(lang)]")
                let highlight = try XCTUnwrap(value(highlightKey, lang), "\(highlightKey) [\(lang)]")
                XCTAssertTrue(title.contains(highlight),
                              "[\(lang)] «\(highlight)» debe vivir dentro de «\(title)»")
            }
        }
    }

    // MARK: Acta del veredicto — «Cómo llegué a esto»

    /// El acta se SINTETIZA: en el `lowSignal` por falta de fila de hoy, `Preparedness`
    /// devuelve `drivers` VACÍO (:163-166). Una tabla derivada de `drivers` no existiría.
    func test_acta_sinDrivers_sintetizaLasDosFilas() {
        // FER-1047: el acta explica las DOS señales que votan (en reposo · sueño); el térmico
        // dejó de ser una fila (vive en el guardián).
        let acta = LiquidHoyBuilder.acta(
            prep: read(verdict: .lowSignal, drivers: [], maturity: .calibrating))
        XCTAssertEqual(acta.filas.count, 2)
        XCTAssertEqual(acta.filas.map(\.id), ["autonomic", "sleep"])
        XCTAssertTrue(acta.filas.allSatisfy { !$0.fuera }, "sin datos, nadie está fuera")
        XCTAssertNil(acta.nivel, "sin veredicto no hay palabra")
        XCTAssertNotNil(acta.sinLectura)
        XCTAssertEqual(acta.tono, LiquidColor.tinta500,
                       "sin veredicto la hoja no tiene una sola gota de color")

        // Y con `prep == nil` tampoco revienta ni inventa filas.
        XCTAssertEqual(LiquidHoyBuilder.acta(prep: nil).filas.count, 2)
    }

    /// El conteo habla de SEÑALES (lo que el usuario ve en los orbes), jamás de «ejes» ni «3».
    func test_acta_conteo_porSenalesNoPorEjes() {
        let combos = [
            LiquidHoyBuilder.conteoActa(fuera: 0, conLectura: 2),
            LiquidHoyBuilder.conteoActa(fuera: 1, conLectura: 2),
            LiquidHoyBuilder.conteoActa(fuera: 2, conLectura: 2),
            LiquidHoyBuilder.conteoActa(fuera: 0, conLectura: 1),
        ]
        for texto in combos {
            XCTAssertFalse(texto.localizedCaseInsensitiveContains("eje"),
                           "vocabulario de ingeniería en pantalla: \(texto)")
            XCTAssertFalse(texto.localizedCaseInsensitiveContains("axis"), texto)
            XCTAssertFalse(texto.contains("3"), "ninguna frase dice «3 señales»: \(texto)")
        }
        XCTAssertNotEqual(combos[0], combos[3], "cobertura parcial tiene su propia frase")
    }

    /// El acta NO publica un solo umbral del motor: la columna «contra qué base» es
    /// cualitativa (los cortes son knobs sin firmar por `/cso` y la allow-list de esta
    /// superficie prohíbe números).
    func test_acta_noPublicaUmbrales() {
        let acta = LiquidHoyBuilder.acta(
            prep: read(verdict: .caution,
                       drivers: [driver(.autonomic, .inRange, z: 0.1),
                                 driver(.sleep, .low), driver(.thermal, .inRange)]))
        for fila in acta.filas {
            XCTAssertNil(fila.base.rangeOfCharacter(from: .decimalDigits),
                         "la columna de base publica un número: «\(fila.base)»")
            XCTAssertNil(fila.dijo.rangeOfCharacter(from: .decimalDigits),
                         "«qué dijo» publica un número: «\(fila.dijo)»")
        }
    }

    /// Precedencia: `easy` + UNA señal fuera + tendencia abajo es el EMPUJÓN DE TENDENCIA
    /// (:214), no la histéresis (:300-312). Sin precedencia se pintaban los dos y la hoja
    /// se contradecía.
    func test_acta_precedencia_tendenciaGanaAHisteresis() {
        let prep = Preparedness.Read(
            verdict: .easy,
            drivers: [driver(.autonomic, .low, z: -1.4), driver(.sleep, .inRange),
                      driver(.thermal, .inRange), driver(.load, .noData)],
            signalsPresent: 3, signalsTotal: 3, maturity: .trusted,
            autonomicNights: 21, trend: .below)
        let ids = LiquidHoyBuilder.acta(prep: prep).notas.map(\.id)
        XCTAssertTrue(ids.contains("tendencia"))
        XCTAssertFalse(ids.contains("histeresis"), "no puede haber dos causas a la vez")
    }

    /// El veredicto MOSTRADO puede no ser la lectura de hoy (histéresis de 2 días). Cuando
    /// el acta y la palabra no cuadran, el aviso es OBLIGATORIO y va en la superficie.
    func test_acta_histeresis_avisaCuandoElConteoNoCuadra() {
        // Verde estable con una señal fuera hoy: el crudo nuevo aún no se repite.
        let prep = Preparedness.Read(
            verdict: .full,
            drivers: [driver(.autonomic, .inRange, z: 0.3), driver(.sleep, .low),
                      driver(.thermal, .inRange), driver(.load, .noData)],
            signalsPresent: 3, signalsTotal: 3, maturity: .trusted,
            autonomicNights: 21, trend: nil)
        let acta = LiquidHoyBuilder.acta(prep: prep)
        let aviso = acta.notas.first { $0.id == "histeresis" }
        XCTAssertNotNil(aviso, "sin este aviso la tarjeta miente en un caso real")
        XCTAssertTrue(aviso?.avisa == true, "el aviso va en tinta de atención, no como nota")
        // Y la fila que se salió NO se pinta del verde del veredicto.
        XCTAssertEqual(acta.tonoFilas, LiquidColor.atencion)
        XCTAssertEqual(acta.tono, LiquidColor.verdePrimario)

        XCTAssertTrue(LiquidHoyBuilder.desfaseDeHisteresis(verdict: .full, fuera: 1))
        XCTAssertFalse(LiquidHoyBuilder.desfaseDeHisteresis(verdict: .caution, fuera: 1))
        XCTAssertFalse(LiquidHoyBuilder.desfaseDeHisteresis(verdict: .easy, fuera: 2))
        XCTAssertTrue(LiquidHoyBuilder.desfaseDeHisteresis(verdict: .easy, fuera: 1))
    }

    /// La carga se mide y NUNCA vota (`loadAxis` :189-193): no entra al acta, baja a nota,
    /// y tiene copy en las DOS variantes (con y sin entrenamiento).
    func test_acta_cargaNuncaVota_conCopyEnLasDosVariantes() {
        func nota(hayWorkout: Bool) -> String? {
            let prep = Preparedness.Read(
                verdict: .full,
                drivers: nocheAnclada + [driver(.load, hayWorkout ? .inRange : .noData)],
                signalsPresent: 3, signalsTotal: 3, maturity: .trusted,
                autonomicNights: 21, trend: nil)
            let acta = LiquidHoyBuilder.acta(prep: prep)
            XCTAssertEqual(acta.filas.count, 2, "las dos señales que votan; la carga nunca es fila")
            XCTAssertFalse(acta.filas.contains { $0.id == "load" })
            XCTAssertFalse(acta.filas.contains { $0.id == "thermal" }, "el térmico bajó al guardián")
            return acta.notas.first { $0.id == "carga" }?.texto
        }
        let con = nota(hayWorkout: true)
        let sin = nota(hayWorkout: false)
        XCTAssertNotNil(con)
        XCTAssertNotNil(sin)
        XCTAssertNotEqual(con, sin, "las dos variantes tienen su propio copy")
    }

    /// Ningún número de noches en pantalla que no salga de `Baselines`, y
    /// `LiquidCalibracionCard` SOLO mientras de verdad calibra.
    func test_acta_confianza_soloDenominadoresDelMotor() {
        // Calibrando: tarjeta con barra, meta = minNightsSeed (4).
        let calibrando = LiquidHoyBuilder.acta(
            prep: read(verdict: .full, drivers: nocheAnclada, nights: 2,
                       maturity: .calibrating))
        guard case .calibrando(_, _, _, let necesarias)? = calibrando.confianza else {
            return XCTFail("esperaba la tarjeta de calibración")
        }
        XCTAssertEqual(necesarias, Baselines.minNightsSeed)

        // Base usable pero joven: prosa, SIN barra de progreso.
        let joven = LiquidHoyBuilder.acta(
            prep: read(verdict: .full, drivers: nocheAnclada, nights: 8,
                       maturity: .provisional))
        guard case .nota? = joven.confianza else {
            return XCTFail("con base usable no va la tarjeta «Calibrando tu base»")
        }

        // Base firme: no hay nada honesto que confesar.
        let firme = LiquidHoyBuilder.acta(
            prep: read(verdict: .full, drivers: nocheAnclada,
                       nights: Baselines.minNightsTrust, maturity: .trusted))
        XCTAssertNil(firme.confianza)
    }

    /// La afordancia es PERMANENTE: la pastilla bajo el veredicto ya no depende de un
    /// tether que desaparece con la base madura.
    func test_heroPuerta_siemprePresente() {
        XCTAssertNotNil(LiquidHoyBuilder.build(LiquidHoyBuilder.Inputs()).model.heroPuerta)
    }
}
