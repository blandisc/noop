import XCTest
import SwiftUI
import StrandAnalytics
import StrandDesign
import CenitStore
@testable import Cenit

// MARK: - HoyMatrizBuilderTests (FER-51 · Lane B)
//
// Criterios de aceptación: 10 (chip guardián), 11 (cero cálidos en día bueno),
// 15 (formas §7), 17 (historia juzgada con SU día), 18 (días fuera con aro),
// 19 (rejilla fantasma / sin HOY), 30 (datasets puros, ventanas fijas).
//
// No corren sin simulador (target CenitUnitTests); quedan correctos por lectura.

final class HoyMatrizBuilderTests: XCTestCase {

    // MARK: Fixtures

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private var now: Date {
        // 2026-08-05 12:00 UTC
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 5
        comps.hour = 12
        return cal.date(from: comps)!
    }

    private func dayKey(_ offset: Int) -> String {
        let d = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
        let f = DateFormatter()
        f.calendar = cal; f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func metric(day: String, sleepMin: Double? = 420, eff: Double? = 0.9,
                        rhr: Int? = 56, hrv: Double? = 45,
                        temp: Double? = 0.1, resp: Double? = 14.0,
                        strain: Double? = 10, steps: Int? = 7000) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleepMin, efficiency: eff,
                    deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                    restingHr: rhr, avgHrv: hrv, recovery: nil, strain: strain,
                    exerciseCount: nil, skinTempDevC: temp, respRateBpm: resp,
                    steps: steps)
    }

    private func bodyNight(day: String, rhr: Double? = 56, sleepOut: Bool = false,
                           autonomicOut: Bool = false,
                           rhrBase: Double? = 56, hrvBase: Double? = 45,
                           rhrBand: ClosedRange<Double>? = 53...59)
        -> Preparedness.BodyNight {
        .init(day: day, rhrResolved: rhr, autonomicOrientedZ: autonomicOut ? -1.2 : 0.2,
              autonomicOut: autonomicOut, sleepOut: sleepOut,
              rhrBaseCenter: rhrBase, hrvBaseCenter: hrvBase, rhrBand: rhrBand)
    }

    /// FER-73 · H3/H18: con `sentinel` el motor SIEMPRE trae la noche que juzgó
    /// (`sentinelHistory.last`); la Matriz ya no acepta un chip sin ese sello. Por defecto se
    /// siembra la noche de HOY con el par completo (que es lo que estos fixtures representan).
    private func prep(verdict: Preparedness.Verdict = .full,
                      sleepOut: Bool = false, autonomicOut: Bool = false,
                      sentinel: Preparedness.SentinelRead? = nil,
                      sentinelHistory: [Preparedness.SentinelNight]? = nil,
                      bodyHistory: [Preparedness.BodyNight] = [],
                      nights: Int = 21) -> Preparedness.Read {
        let drivers: [Preparedness.Driver] = [
            .init(axis: .autonomic, state: autonomicOut ? .high : .inRange,
                  orientedZ: autonomicOut ? -1.2 : 0.2),
            .init(axis: .sleep, state: sleepOut ? .low : .inRange, orientedZ: nil),
            .init(axis: .thermal, state: .inRange, orientedZ: nil),
        ]
        let historia: [Preparedness.SentinelNight] = sentinelHistory ?? (sentinel == nil ? [] : [
            .init(day: dayKey(0), tempOut: sentinel?.tempOut ?? false,
                  respOut: sentinel?.respOut ?? false, tempMissing: false, respMissing: false,
                  respJudged: true, gapBefore: false)
        ])
        return Preparedness.Read(
            verdict: verdict, drivers: drivers, signalsPresent: 3, signalsTotal: 4,
            maturity: .trusted, autonomicNights: nights, trend: nil,
            sentinel: sentinel, sentinelHistory: historia, bodyHistory: bodyHistory)
    }

    private func inputs(prep: Preparedness.Read?,
                        dias: [DailyMetric],
                        stress: [(day: String, value: Double)] = [],
                        carga: TrainingLoadModel? = nil,
                        steps: [(day: String, value: Double)] = [])
        -> LiquidHoyBuilder.MatrizInputs {
        .init(prep: prep, diasRecientes: dias, stressTrend: stress, carga: carga,
              stepsEstimados: steps, locale: Locale(identifier: "en_US"),
              calendar: cal, now: now)
    }

    private func seccion(_ model: MatrizHoyModel, id: String) -> MatrizSeccion? {
        for b in model.bandas {
            switch b {
            case .full(let s) where s.id == id: return s
            case .split(let izq, let der):
                if izq.id == id { return izq }
                if der.id == id { return der }
            default: break
            }
        }
        return nil
    }

    // MARK: 10 — Chip del guardián (máquina de 5 estados)

    private func sentinel(_ state: Preparedness.SentinelState, streak: Int = 0,
                          watching: Preparedness.SentinelSignal? = nil,
                          tempOut: Bool = false, respOut: Bool = false)
        -> Preparedness.SentinelRead {
        .init(state: state, streakNights: streak, watchingSignal: watching,
              tempOut: tempOut, respOut: respOut)
    }

    /// FER-73: la noche juzgada con el par COMPLETO (ambas señales leídas y la resp con base).
    private func nocheCompleta(day: String = "2026-08-05") -> Preparedness.SentinelNight {
        .init(day: day, tempOut: false, respOut: false, tempMissing: false, respMissing: false,
              respJudged: true, gapBefore: false)
    }

    /// Chip del motor para un `SentinelRead` con el par completo (atajo de los tests viejos).
    private func chipDe(_ s: Preparedness.SentinelRead?) -> HoyGramatica.ChipGuardian? {
        LiquidHoyBuilder.chipGuardianJuzgado(s, noche: nocheCompleta())
    }

    /// Texto resuelto y NO vacío en cada estado — un `""` (key sin valor) es el modo de falla
    /// que este guard cierra: «no hay literal inglés» pasaría con vacío; «no vacío» no. La
    /// cadena es-MX exacta se verifica en el simulador es-MX (CA7), no aquí (locale del test = en).
    private func assertTextoResuelto(_ chip: MatrizHoyModel.ChipGuardian?,
                                     _ ctx: String, file: StaticString = #filePath,
                                     line: UInt = #line) {
        XCTAssertNotNil(chip, ctx, file: file, line: line)
        XCTAssertFalse(chip?.texto.isEmpty ?? true, "\(ctx): el chip muestra una palabra, no vacío",
                       file: file, line: line)
    }

    func test_10_chip_calma() {
        let chip = LiquidHoyBuilder.chipGuardianModelo(chipDe(sentinel(.quiet)))
        XCTAssertEqual(chip?.tono, .calma)
        assertTextoResuelto(chip, "calma")
    }

    func test_10_chip_vigilando_temp_sin_calidos() {
        let chip = LiquidHoyBuilder.chipGuardianModelo(chipDe(sentinel(.watchingOneSignal, watching: .temp, tempOut: true)))
        XCTAssertEqual(chip?.tono, .terciario)
        XCTAssertNotEqual(chip?.tono, .atencion)
        XCTAssertNotEqual(chip?.tono, .alarma)
        assertTextoResuelto(chip, "vigilando temp")
    }

    func test_10_chip_vigilando_resp() {
        let chip = LiquidHoyBuilder.chipGuardianModelo(chipDe(sentinel(.watchingOneSignal, watching: .resp, respOut: true)))
        XCTAssertEqual(chip?.tono, .terciario)
        assertTextoResuelto(chip, "vigilando resp")
    }

    func test_10_chip_ambas_primera_noche_ambar() {
        let chip = LiquidHoyBuilder.chipGuardianModelo(chipDe(sentinel(.corroborated, streak: 1, tempOut: true, respOut: true)))
        XCTAssertEqual(chip?.tono, .atencion)
        assertTextoResuelto(chip, "ambas 1.ª noche")
    }

    func test_10_chip_racha_ordinal_real() {
        for n in [2, 3, 5, 11] {
            let chip = LiquidHoyBuilder.chipGuardianModelo(chipDe(sentinel(.corroborated, streak: n, tempOut: true, respOut: true)))
            XCTAssertEqual(chip?.tono, .alarma, "racha \(n)")
            // El ordinal REAL aparece en el texto (no un número fijo inventado).
            XCTAssertTrue(chip?.texto.contains("\(n)") == true,
                          "racha \(n) debe llevar el ordinal real: \(chip?.texto ?? "nil")")
        }
    }

    /// El ordinal de la racha se formatea POR locale (CA1): es-MX «N.ª» (femenino numérico),
    /// en irregular (2nd/3rd/21st). Antes concatenaba «2nd» crudo → es-MX veía «2nd noche»;
    /// esta rama no tenía cobertura (hallazgo Grok+DeepSeek en la revisión adversarial).
    func test_10_ordinal_marcador_por_locale() {
        let es = Locale(identifier: "es_MX"), en = Locale(identifier: "en_US")
        XCTAssertEqual(LiquidHoyBuilder.ordinalMarcador(2, locale: es), "2.ª")
        XCTAssertEqual(LiquidHoyBuilder.ordinalMarcador(3, locale: es), "3.ª")
        XCTAssertEqual(LiquidHoyBuilder.ordinalMarcador(11, locale: es), "11.ª")
        XCTAssertEqual(LiquidHoyBuilder.ordinalMarcador(2, locale: en), "2nd")
        XCTAssertEqual(LiquidHoyBuilder.ordinalMarcador(3, locale: en), "3rd")
        XCTAssertEqual(LiquidHoyBuilder.ordinalMarcador(11, locale: en), "11th")
        XCTAssertEqual(LiquidHoyBuilder.ordinalMarcador(21, locale: en), "21st")
        XCTAssertEqual(LiquidHoyBuilder.ordinalMarcador(4, locale: en), "4th")
    }

    /// 6.º camino (Grok): sin lectura del par, el chip NO queda en blanco ni afirma calma —
    /// un estado honesto en tinta terciaria (reusa la key «No readings yet» → «Aún no hay lecturas»).
    func test_10_chip_sin_sentinel_no_queda_en_blanco() {
        let chip = LiquidHoyBuilder.chipGuardianModelo(nil)
        XCTAssertEqual(chip?.tono, .terciario)
        XCTAssertNotEqual(chip?.tono, .calma, "sin dato jamás afirma calma (sería mentir)")
        assertTextoResuelto(chip, "sin sentinel")
    }

    /// FER-73 · H3: `.quiet` NO es calma si falta una señal o la respiración no tenía base —
    /// el motor no marcó lo que no pudo leer. Chip terciario que dice por qué; sello sin datos.
    func test_10_chip_quiet_sin_par_completo_no_afirma_calma() {
        let s = sentinel(.quiet)
        let faltaResp = Preparedness.SentinelNight(day: "2026-08-05", tempOut: false, respOut: false,
                                                    tempMissing: false, respMissing: true,
                                                    respJudged: false, gapBefore: false)
        let sinBase = Preparedness.SentinelNight(day: "2026-08-05", tempOut: false, respOut: false,
                                                  tempMissing: false, respMissing: false,
                                                  respJudged: false, gapBefore: false)
        XCTAssertNil(LiquidHoyBuilder.chipGuardianJuzgado(s, noche: faltaResp))
        XCTAssertNil(LiquidHoyBuilder.chipGuardianJuzgado(s, noche: sinBase))
        XCTAssertNotNil(LiquidHoyBuilder.chipGuardianJuzgado(s, noche: nocheCompleta()))
        let chipFalta = LiquidHoyBuilder.chipGuardianModelo(nil, noche: faltaResp, hayLecturaHoy: true)
        XCTAssertEqual(chipFalta?.tono, .terciario)
        XCTAssertEqual(chipFalta?.texto, String(localized: "Only one signal"))
        let chipCalibrando = LiquidHoyBuilder.chipGuardianModelo(nil, noche: nil, hayLecturaHoy: true,
                                                                 calibrando: true)
        XCTAssertEqual(chipCalibrando?.texto,
                       String(localized: "hero.title.calibrando", defaultValue: "Getting to know you"))
        XCTAssertEqual(LiquidHoyBuilder.chipGuardianModelo(nil, noche: nil, hayLecturaHoy: false)?.texto,
                       String(localized: "No readings yet"))
        XCTAssertEqual(LiquidHoyBuilder.selloGuardianEstado(
            LiquidHoyBuilder.chipGuardianJuzgado(s, noche: sinBase)), .sinDatos)
    }

    /// FER-73 · H5: durante la calibración (ruta lowSignal ⇒ sin `sentinel`), la Matriz NO
    /// afirma «within your band» / «typical for you» sobre valores que el motor no comparó.
    func test_10_calibrando_sin_juicio_no_afirma_banda() {
        let dias = (-19...0).map { metric(day: dayKey($0), rhr: 51, temp: 0.1, resp: 14.4) }
        // Ruta lowSignal del motor: sin `sentinel` ni `sentinelHistory` (el eje autonómico
        // todavía no tiene base) — exactamente lo que se ve durante la calibración.
        let p = Preparedness.Read(verdict: .lowSignal, drivers: [], signalsPresent: 0,
                                  signalsTotal: 3, maturity: .calibrating, autonomicNights: 2,
                                  trend: nil)
        let m = LiquidHoyBuilder.matriz(inputs(prep: p, dias: dias))
        let guardian = seccion(m, id: "guardian")
        XCTAssertNotNil(guardian)
        // FER-80: el par vive en UNA sola gráfica (la costura), sin renglones que puedan
        // afirmar «dentro de tu banda» sobre lecturas que el motor no comparó.
        XCTAssertNil(guardian?.renglones, "la costura sustituyó las dos filas")
        XCTAssertEqual(guardian?.valor, "+0.1° · 14.4", "los dos números, juntos")
        XCTAssertEqual(guardian?.chip?.tono, .terciario)
        XCTAssertNotEqual(guardian?.chip?.texto, String(localized: "No readings yet"),
                          "hay lecturas: el chip no puede decir que no las hay")
        XCTAssertEqual(guardian?.selloGuardian, .sinDatos)
        // Y sin juicio del motor, ninguna noche puede pintarse como «el par votó».
        if case .costura(let noches)? = guardian?.chart {
            XCTAssertFalse(noches.contains { $0.parFuera },
                           "sin centinela no se afirma que el par votó")
            XCTAssertTrue(noches.contains { $0.temp != nil }, "las lecturas sí se dibujan")
        } else {
            XCTFail("el guardián dibuja la costura")
        }
    }

    // MARK: 10b — El sello VIVO del guardián espeja el chip (Ola 3, nunca lo contradice)

    func test_10_sello_guardian_espeja_el_chip() {
        // Sin lectura del par → sin datos (nunca un falso «calma» verde).
        XCTAssertEqual(LiquidHoyBuilder.selloGuardianEstado(nil), .sinDatos)
        XCTAssertEqual(LiquidHoyBuilder.selloGuardianEstado(chipDe(sentinel(.quiet))), .calma)
        // Una sola fuera → vigila ESA, en frío (paridad con el chip terciario, sin alarma).
        XCTAssertEqual(LiquidHoyBuilder.selloGuardianEstado(chipDe(
            sentinel(.watchingOneSignal, watching: .temp, tempOut: true))), .vigilaTemp)
        XCTAssertEqual(LiquidHoyBuilder.selloGuardianEstado(chipDe(
            sentinel(.watchingOneSignal, watching: .resp, respOut: true))), .vigilaResp)
        // El par 1.ª noche → ámbar; el par en racha → rojo. Espeja atencion → alarma.
        XCTAssertEqual(LiquidHoyBuilder.selloGuardianEstado(chipDe(
            sentinel(.corroborated, streak: 1, tempOut: true, respOut: true))), .ambasAmbar)
        XCTAssertEqual(LiquidHoyBuilder.selloGuardianEstado(chipDe(
            sentinel(.corroborated, streak: 3, tempOut: true, respOut: true))), .ambasRoja)
    }

    // MARK: 11 — Cero cálidos en día bueno

    func test_11_dia_bueno_cero_alertas_hoy() {
        let keys = LiquidHoyBuilder.dayKeys(endingAt: now, calendar: cal, count: 20)
        let dias = keys.map { metric(day: $0) }
        let body = keys.map { bodyNight(day: $0) }
        let p = prep(sentinel: sentinel(.quiet), bodyHistory: body)
        let model = LiquidHoyBuilder.matriz(inputs(
            prep: p, dias: dias,
            carga: TrainingLoadModel(acwr: 1.0, series: keys.suffix(6).map { ($0, 1.0) })))

        // Héroe sin alertas en lunas.

        // Secciones: alertaHoy / noches sin atencion/alarma (salvo historia — aquí limpia).
        if case .columnas(let noches, _, _, _) = seccion(model, id: "sleep")?.chart {
            XCTAssertTrue(noches.allSatisfy { $0.alerta == .ninguna })
        } else { XCTFail("sueño") }

        if case .regla(_, _, _, let a) = seccion(model, id: "rhr")?.chart {
            XCTAssertEqual(a, .ninguna)
        } else { XCTFail("fc") }

        XCTAssertEqual(seccion(model, id: "guardian")?.chip?.tono, .calma)
    }

    // MARK: 15 — Formas §7 + sello + ventanas

    func test_15_formas_y_ventanas_fijas() {
        let keys = LiquidHoyBuilder.dayKeys(endingAt: now, calendar: cal, count: 20)
        let dias = keys.map { metric(day: $0) }
        let body = keys.map { bodyNight(day: $0) }
        let stress = Array(keys.suffix(7)).map { (day: $0, value: 0.5) }
        let steps = keys.map { (day: $0, value: 8000.0) }
        let series = keys.map { (day: $0, value: 1.0) }
        let model = LiquidHoyBuilder.matriz(inputs(
            prep: prep(bodyHistory: body), dias: dias, stress: stress,
            carga: TrainingLoadModel(acwr: 1.12, series: series), steps: steps))

        // Sueño: 14 columnas.
        if case .columnas(let n, let ref, let tag, _) = seccion(model, id: "sleep")?.chart {
            XCTAssertEqual(n.count, 14)
            XCTAssertEqual(ref, 7)
            XCTAssertEqual(tag, "7 h")
        } else { XCTFail("sleep chart") }

        // FC: 20 puntos en carriles (FER-55); VFC: línea rellena.
        if case .regla(let pts, _, _, _) = seccion(model, id: "rhr")?.chart {
            XCTAssertEqual(pts.count, 20)
        } else { XCTFail("rhr") }
        if case .lineaRellena(let pts, _, _, let alfa, _) = seccion(model, id: "hrv")?.chart {
            XCTAssertEqual(pts.count, 20)
            XCTAssertEqual(alfa, 0.6, accuracy: 0.001)
        } else { XCTFail("hrv") }

        // Carga: riel + estela ≤ 5.
        if case .colina(let p, let zona, let estela, _) = seccion(model, id: "carga")?.chart {
            XCTAssertEqual(p, 1.12)
            XCTAssertEqual(zona.lowerBound, ReadinessEngine.acwrSweetSpotLow)
            XCTAssertEqual(zona.upperBound, ReadinessEngine.acwrSweetSpotHigh)
            XCTAssertLessThanOrEqual(estela.count, 5)
            XCTAssertEqual(estela.count, 5) // 5 previas con datos
        } else { XCTFail("carga") }

        // Esfuerzo / pasos: 14 barras.
        if case .barrasMini(let v) = seccion(model, id: "strain")?.chart {
            XCTAssertEqual(v.count, 14)
        } else { XCTFail("strain") }
        if case .barrasMini(let v) = seccion(model, id: "steps")?.chart {
            XCTAssertEqual(v.count, 14)
        } else { XCTFail("steps") }

        // Estrés: 7 niveles.
        if case .escalerita(let n) = seccion(model, id: "stress")?.chart {
            XCTAssertEqual(n.count, 7)
        } else { XCTFail("stress") }

        // Identidad: hue + sello dibujado, uno por señal. Cuatro cambiaron de tono al
        // alinearlos con la tabla 1:1 de tokens (el teal era de PASOS, tinta700 es un tono
        // de TEXTO, verdePrimario es la voz de marca y también la zona «bajo» del medidor).
        XCTAssertEqual(seccion(model, id: "sleep")?.hue, LiquidColor.indigo)
        XCTAssertEqual(seccion(model, id: "rhr")?.hue, LiquidColor.rosa)
        XCTAssertEqual(seccion(model, id: "hrv")?.hue, LiquidColor.cian)
        XCTAssertEqual(seccion(model, id: "guardian")?.hue, LiquidColor.doradoTemp)
        XCTAssertEqual(seccion(model, id: "carga")?.hue, LiquidColor.verdeCarga)
        // Dueño 2026-08-15: Effort = ÁMBAR (su detalle «Day Strain» y la hoja de resumen
        // son ámbar — estaba cruzado con Steps) y Steps = TEAL (su color en la hoja de
        // resumen; era tinta700 gris). Fuente de verdad: LiquidMetricSheetView.tono.
        XCTAssertEqual(seccion(model, id: "strain")?.hue, LiquidColor.ambar)
        // FER-59: Estrés RECEDE — era tinta900 (gritaba siendo referencia que no vota),
        // ahora tinta500 (peso de las demás de contexto). Manda esta decisión sobre el
        // ámbar que proponía el contrato de tokens: el sello lo dice sin subir el peso.
        XCTAssertEqual(seccion(model, id: "stress")?.hue, LiquidColor.tinta500)
        XCTAssertEqual(seccion(model, id: "steps")?.hue, LiquidColor.teal)

        // Cada señal lleva SU glifo (FER-117: los sellos dibujados dieron paso a los símbolos
        // del sistema, mismo vocabulario que las hojas); el guardián no (su sello VIVE:
        // SelloGuardianVivo).
        XCTAssertEqual(seccion(model, id: "sleep")?.glifoSello, .luna)
        XCTAssertEqual(seccion(model, id: "rhr")?.glifoSello, .corazon)
        XCTAssertEqual(seccion(model, id: "hrv")?.glifoSello, .onda)
        XCTAssertEqual(seccion(model, id: "carga")?.glifoSello, .carga)
        XCTAssertEqual(seccion(model, id: "strain")?.glifoSello, .llama)
        XCTAssertEqual(seccion(model, id: "stress")?.glifoSello, .estres)
        XCTAssertEqual(seccion(model, id: "steps")?.glifoSello, .pasos)
        XCTAssertNil(seccion(model, id: "guardian")?.glifoSello)
        XCTAssertNotNil(seccion(model, id: "guardian")?.selloGuardian)

        // Los sellos de piel y respiración NO viven ya en Hoy: FER-80 fundió las dos filas
        // del guardián en la costura (ver arriba, `renglones` es nil). Siguen encabezando
        // sus hojas de resumen, y el andamiaje de `MatrizRenglon` los admite si vuelven.

        // Orden visual a11y.
        XCTAssertEqual(model.ordenA11y, [
            "sleep", "rhr", "guardian", "carga", "strain", "hrv", "stress", "steps",
        ])
    }

    // MARK: FER-55 · panel B — el sublabel de FC dice el JUICIO del motor, no la banda

    func test_fc_lado_bueno_fuera_de_banda_dice_en_rango() {
        let keys = LiquidHoyBuilder.dayKeys(endingAt: now, calendar: cal, count: 20)
        let dias = keys.map { metric(day: $0, rhr: 48) }
        // FC de HOY (48) por DEBAJO de la banda 53...59 — lado bueno: el motor NO
        // castiga (autonomicOut false) → el sublabel dice el juicio del motor con la
        // MISMA estructura que Sueño: «last night · in your range» (FER-56, simetría de
        // las gemelas: la FC en reposo también es lectura de anoche).
        let body = keys.map { bodyNight(day: $0, rhr: 48, autonomicOut: false) }
        let model = LiquidHoyBuilder.matriz(inputs(
            prep: prep(sentinel: sentinel(.quiet), bodyHistory: body), dias: dias))
        XCTAssertEqual(seccion(model, id: "rhr")?.sublabel, "last night · in your range")
        // Y la banda sí viaja al chart (geografía visible).
        if case .regla(_, let banda, _, _) = seccion(model, id: "rhr")?.chart {
            XCTAssertEqual(banda, 53...59)
        } else { XCTFail("carriles") }
        // El scrub de HOY dice lo mismo que el sublabel (misma voz).
        XCTAssertTrue(seccion(model, id: "rhr")?.scrubNoches?.last?.sublabel
            .contains("in your range") == true)
    }

    func test_fc_fuera_por_motor_dice_fuera_en_scrub() {
        let keys = LiquidHoyBuilder.dayKeys(endingAt: now, calendar: cal, count: 20)
        let outDay = keys[10]
        let dias = keys.map { metric(day: $0) }
        let body = keys.map { bodyNight(day: $0, autonomicOut: $0 == outDay) }
        let model = LiquidHoyBuilder.matriz(inputs(
            prep: prep(sentinel: sentinel(.quiet), bodyHistory: body), dias: dias))
        XCTAssertTrue(seccion(model, id: "rhr")?.scrubNoches?[10].sublabel
            .contains("out of your range") == true)
    }

    // MARK: 17 — Historia juzgada con SU día (no se repinta)

    func test_17_historia_no_se_repinta_al_cambiar_hoy() {
        let keys = LiquidHoyBuilder.dayKeys(endingAt: now, calendar: cal, count: 14)
        // Día -5 (índice 8 si 14 días) estuvo fuera de sueño.
        let outDay = keys[8]
        var body = keys.map { bodyNight(day: $0, sleepOut: $0 == outDay) }
        let dias = keys.map { metric(day: $0, sleepMin: $0 == outDay ? 300 : 420) }

        let bueno = LiquidHoyBuilder.matriz(inputs(
            prep: prep(sleepOut: false, bodyHistory: body), dias: dias))
        // Cambiar HOY a malo no debe mover el flag histórico del día outDay.
        body[body.count - 1] = bodyNight(day: keys.last!, sleepOut: true)
        let malo = LiquidHoyBuilder.matriz(inputs(
            prep: prep(sleepOut: true, bodyHistory: body),
            dias: dias.map { $0.day == keys.last! ? metric(day: $0.day, sleepMin: 280) : $0 }))

        guard case .columnas(let nBuenas, _, _, _) = seccion(bueno, id: "sleep")?.chart,
              case .columnas(let nMalas, _, _, _) = seccion(malo, id: "sleep")?.chart else {
            return XCTFail("charts")
        }
        // Índice del día histórico fuera: en la ventana de 14, keys[8] es el índice 8.
        XCTAssertEqual(nBuenas[8].alerta, .atencion)
        XCTAssertEqual(nMalas[8].alerta, .atencion, "el flag histórico no cambia con HOY")
        // HOY sí cambia.
        XCTAssertEqual(nBuenas[13].alerta, .ninguna)
        XCTAssertEqual(nMalas[13].alerta, .atencion)
    }

    // MARK: 18 — Días fuera con aro, hue intacto

    func test_18_dias_fuera_aro_hue_intacto() {
        let keys = LiquidHoyBuilder.dayKeys(endingAt: now, calendar: cal, count: 14)
        let outDay = keys[3]
        let body = keys.map { bodyNight(day: $0, sleepOut: $0 == outDay) }
        let dias = keys.map { metric(day: $0) }
        let model = LiquidHoyBuilder.matriz(inputs(
            prep: prep(bodyHistory: body), dias: dias))

        guard case .columnas(let noches, _, _, _) = seccion(model, id: "sleep")?.chart else {
            return XCTFail("sleep")
        }
        XCTAssertEqual(noches[3].alerta, .atencion)
        // Hue de la sección sigue siendo índigo (identidad intacta).
        XCTAssertEqual(seccion(model, id: "sleep")?.hue, LiquidColor.indigo)
        // Los demás días sin aro.
        for (i, n) in noches.enumerated() where i != 3 {
            XCTAssertEqual(n.alerta, .ninguna, "día \(i)")
        }
    }

    // MARK: 19 — Rejilla fantasma / sin HOY

    func test_19_sin_historia_valores_dash_y_puntos_nil() {
        let keys = LiquidHoyBuilder.dayKeys(endingAt: now, calendar: cal, count: 20)
        // Días vacíos (todo nil).
        let dias = keys.map {
            DailyMetric(day: $0, totalSleepMin: nil, efficiency: nil, deepMin: nil,
                        remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil,
                        avgHrv: nil, recovery: nil, strain: nil, exerciseCount: nil)
        }
        let model = LiquidHoyBuilder.matriz(inputs(prep: nil, dias: dias))

        XCTAssertEqual(seccion(model, id: "sleep")?.valor, "—")
        XCTAssertEqual(seccion(model, id: "rhr")?.valor, "—")
        XCTAssertEqual(seccion(model, id: "strain")?.valor, "—")
        XCTAssertEqual(seccion(model, id: "steps")?.valor, "—")

        if case .columnas(let n, _, _, _) = seccion(model, id: "sleep")?.chart {
            XCTAssertTrue(n.allSatisfy { $0.valor == nil }, "fantasma: sin datos")
        } else { XCTFail("sleep") }
        if case .regla(let pts, let banda, _, _) = seccion(model, id: "rhr")?.chart {
            XCTAssertTrue(pts.allSatisfy { $0 == nil })
            XCTAssertNil(banda)
        } else { XCTFail("rhr") }
        if case .colina(let p, _, let estela, _) = seccion(model, id: "carga")?.chart {
            XCTAssertNil(p)
            XCTAssertTrue(estela.isEmpty)
        } else { XCTFail("carga") }
    }

    func test_19_sin_dato_hoy_ultimo_nil_valor_dash() {
        let keys = LiquidHoyBuilder.dayKeys(endingAt: now, calendar: cal, count: 14)
        // Historia con datos, HOY sin sueño.
        let dias = keys.enumerated().map { i, k in
            metric(day: k, sleepMin: i == keys.count - 1 ? nil : 420)
        }
        let body = keys.map { bodyNight(day: $0) }
        let model = LiquidHoyBuilder.matriz(inputs(
            prep: prep(bodyHistory: body), dias: dias))

        XCTAssertEqual(seccion(model, id: "sleep")?.valor, "—")
        if case .columnas(let n, _, _, _) = seccion(model, id: "sleep")?.chart {
            XCTAssertNil(n.last?.valor, "HOY omitido en la gráfica")
            XCTAssertNotNil(n[n.count - 2].valor, "historia presente")
        } else { XCTFail("sleep") }
    }

    // MARK: 30 — Datasets puros; «—» vs «0»

    func test_30_cero_real_vs_ausente() {
        let keys = LiquidHoyBuilder.dayKeys(endingAt: now, calendar: cal, count: 14)
        // Esfuerzo = 0 real hoy; pasos ausente.
        let dias = keys.enumerated().map { i, k -> DailyMetric in
            if i == keys.count - 1 {
                return metric(day: k, strain: 0, steps: nil)
            }
            return metric(day: k)
        }
        let model = LiquidHoyBuilder.matriz(inputs(
            prep: prep(bodyHistory: keys.map { bodyNight(day: $0) }),
            dias: dias,
            steps: keys.dropLast().map { (day: $0, value: 5000) }))

        // Cero REAL de esfuerzo se formatea como cero, no como raya.
        XCTAssertEqual(seccion(model, id: "strain")?.valor, "0.0")
        // Pasos sin dato de HOY → raya.
        XCTAssertEqual(seccion(model, id: "steps")?.valor, "—")
    }

    func test_30_ventanas_terminan_en_hoy() {
        let keys20 = LiquidHoyBuilder.dayKeys(endingAt: now, calendar: cal, count: 20)
        XCTAssertEqual(keys20.count, 20)
        XCTAssertEqual(keys20.last, dayKey(0))
        XCTAssertEqual(keys20.first, dayKey(-19))
    }

    // MARK: FER-118 — tres estantes, y el scrub del guardián dice si el par votó

    /// El prototipo aprobado tiene TRES estantes (Deciden tu día · Te vigila · Contexto), cada uno
    /// con su «?»; el rótulo «Bitácora» se retiró y Pasos cierra Contexto, ancho. El orden de las
    /// 8 secciones (y por tanto `ordenA11y`) no cambia.
    func test_118_tres_estantes_sin_bitacora_y_pasos_cierra_contexto() {
        let dias = (-19...0).map { metric(day: dayKey($0)) }
        let m = LiquidHoyBuilder.matriz(inputs(prep: prep(), dias: dias))
        let niveles = m.bandas.compactMap { b -> String? in
            if case .nivel(let rotulo, _) = b { return rotulo } else { return nil }
        }
        XCTAssertEqual(niveles.count, 3, "tres estantes")
        XCTAssertFalse(niveles.contains { $0.lowercased().contains("logbook") || $0.lowercased().contains("bitácora") },
                       "sin estante Bitácora")
        // Cada estante trae su «?».
        for b in m.bandas {
            if case .nivel(_, let manualID) = b { XCTAssertNotNil(manualID, "cada estante con su «?»") }
        }
        // La última banda es Pasos, ancha (`.full`), dentro de Contexto.
        if case .full(let s)? = m.bandas.last { XCTAssertEqual(s.id, "steps") } else { XCTFail("Pasos cierra, ancho") }
        XCTAssertEqual(m.ordenA11y, ["sleep", "rhr", "guardian", "carga", "strain", "hrv", "stress", "steps"])
    }

    /// Mientras el dedo lee una noche del guardián, el subtítulo dice si el PAR votó — solo esa
    /// noche, y solo con el juicio del motor (`parFuera`, del arreglo sin recortar). Las demás
    /// noches llevan la fecha sola. Sin lectura, «sin lectura», como siempre.
    func test_118_scrub_guardian_dice_si_el_par_voto() {
        let keys = (-19...0).map { dayKey($0) }
        let dias = keys.map { metric(day: $0, temp: 0.1, resp: 14.0) }
        // El motor marcó el par FUERA hace 3 noches (índice 16 de 20) y en calma el resto.
        let historia: [Preparedness.SentinelNight] = keys.enumerated().map { i, k in
            let fuera = i == 16
            return .init(day: k, tempOut: fuera, respOut: fuera, tempMissing: false,
                         respMissing: false, respJudged: true, gapBefore: false)
        }
        let m = LiquidHoyBuilder.matriz(inputs(
            prep: prep(sentinel: sentinel(.quiet), sentinelHistory: historia), dias: dias))
        guard let noches = seccion(m, id: "guardian")?.scrubNoches else { return XCTFail("scrub del guardián") }
        XCTAssertEqual(noches.count, 20)
        let par = noches[16].sublabel, vecina = noches[15].sublabel
        XCTAssertTrue(par.contains(" · "), "la noche del par lleva la frase tras la fecha: \(par)")
        XCTAssertTrue(par.lowercased().contains("together") || par.lowercased().contains("juntas"),
                      "dice que las dos se salieron juntas: \(par)")
        XCTAssertFalse(vecina.lowercased().contains("together") || vecina.lowercased().contains("juntas"),
                       "la vecina en calma NO lo dice: \(vecina)")
        XCTAssertFalse(vecina.contains(" · "), "la vecina lleva solo la fecha")
        // Y la afirmación viene del motor: sin `parFuera` en la costura, sin frase en el scrub.
        if case .costura(let costura)? = seccion(m, id: "guardian")?.chart {
            XCTAssertTrue(costura[16].parFuera)
            XCTAssertFalse(costura[15].parFuera)
        } else { XCTFail("costura") }
    }

    func test_30_estela_excluye_hoy() {
        let keys = LiquidHoyBuilder.dayKeys(endingAt: now, calendar: cal, count: 20)
        // Serie con razón distinta cada día; HOY = 9.99 para detectarlo si se cuela.
        let series = keys.enumerated().map { i, k in (day: k, value: Double(i)) }
        let model = LiquidHoyBuilder.matriz(inputs(
            prep: prep(bodyHistory: keys.map { bodyNight(day: $0) }),
            dias: keys.map { metric(day: $0) },
            carga: TrainingLoadModel(acwr: 9.99, series: series)))
        if case .colina(let p, _, let estela, _) = seccion(model, id: "carga")?.chart {
            XCTAssertEqual(p, 9.99)
            XCTAssertFalse(estela.contains(9.99), "estela no incluye HOY")
            XCTAssertEqual(estela.count, 5)
            // Las 5 previas: índices 14…18 de la serie 0…19.
            XCTAssertEqual(estela, [14, 15, 16, 17, 18])
        } else { XCTFail("carga") }
    }
}
