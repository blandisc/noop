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
        XCTAssertFalse(title.contains("h"), "jamás la hora de sueño: \(title)")
        XCTAssertTrue(title.localizedCaseInsensitiveContains("datos") ||
                      title.localizedCaseInsensitiveContains("data"), title)
        XCTAssertEqual(routeLow, .autonomic)

        // prep == nil → mismo estado honesto, mismo destino.
        let (heroNil, routeNil) = LiquidHoyBuilder.hero(prep: nil, sleepMin: nil, nights: 0)
        guard case .demotado(_, let titleNil, _) = heroNil else {
            return XCTFail("esperaba .demotado (sin datos)")
        }
        XCTAssertEqual(titleNil, title, "con o sin sueño grabado, el mismo copy honesto")
        XCTAssertEqual(routeNil, .autonomic)
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

    func test_senales_estadosYSinDatos() {
        let prep = read(verdict: .caution, drivers: [
            driver(.autonomic, .low, z: -1.2), driver(.sleep, .noData), driver(.thermal, .inRange),
        ])
        let senales = LiquidHoyBuilder.senales(prep: prep, thermalDeviation: nil)
        XCTAssertEqual(senales.map(\.id), ["autonomico", "sueno", "termico"])

        // Autonómico fuera → atención, posición del z.
        XCTAssertEqual(senales[0].state, .atencion)
        XCTAssertEqual(senales[0].progress ?? -1, 0.5 - 1.2 / 4, accuracy: 1e-9)
        // Sueño sin datos → sin progreso (el eje no vota).
        XCTAssertNil(senales[1].progress)
        // Térmico sin lectura → orbe «sin datos» (desviación documentada: no se oculta).
        XCTAssertNil(senales[2].progress)
    }

    func test_senales_termico_usaElCorteDelMotor() {
        let cut = Preparedness.Config.default.thermalOutC
        let alto = LiquidHoyBuilder.senales(prep: nil, thermalDeviation: cut + 0.01)
        XCTAssertEqual(alto[2].state, .atencion)
        XCTAssertEqual(alto[2].progress ?? -1, 0.8, accuracy: 1e-9)
        let normal = LiquidHoyBuilder.senales(prep: nil, thermalDeviation: 0)
        XCTAssertEqual(normal[2].state, .ok)
        XCTAssertEqual(normal[2].progress ?? -1, 0.5, accuracy: 1e-9)
    }

    // MARK: Carga — mismo mapeo que la franja

    func test_carga_mapeoACWR() {
        XCTAssertNil(LiquidHoyBuilder.carga(nil), "sin modelo sembrado → sin barra")

        guard case .calibrando = LiquidHoyBuilder.carga(
            TrainingLoadModel(acwr: nil, series: []))! else {
            return XCTFail("acwr nil → calibrando")
        }

        // El caso del ensamble: 1.03 → equilibrio, knob 51.5, ok.
        guard case .medida(let pos, let zone, _, let ratio, let state) = LiquidHoyBuilder.carga(
            TrainingLoadModel(acwr: 1.03, series: []))! else {
            return XCTFail("esperaba .medida")
        }
        XCTAssertEqual(pos, 51.5, accuracy: 1e-9)
        XCTAssertEqual(zone, 1)
        XCTAssertEqual(ratio, "1.03", "el ratio viaja separado del rótulo (pasada UI)")
        XCTAssertEqual(state, .ok)

        // Las zonas siguen al motor (el oráculo es `loadBand`), knob clampeado 0.05–0.95.
        for (ratio, expectedZone, okEsperado) in [(0.7, 0, false), (1.4, 2, false), (1.9, 3, false)] {
            guard case .medida(let p, let z, _, _, let s) = LiquidHoyBuilder.carga(
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
                     ("Take it easy", "hero.highlight.easy")]
        for lang in ["en", "es"] {
            for (titleKey, highlightKey) in pares {
                let title = try XCTUnwrap(value(titleKey, lang), "\(titleKey) [\(lang)]")
                let highlight = try XCTUnwrap(value(highlightKey, lang), "\(highlightKey) [\(lang)]")
                XCTAssertTrue(title.contains(highlight),
                              "[\(lang)] «\(highlight)» debe vivir dentro de «\(title)»")
            }
        }
    }
}
