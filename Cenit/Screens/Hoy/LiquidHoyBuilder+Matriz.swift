import Foundation
import SwiftUI
import StrandAnalytics
import StrandDesign
import CenitStore

// MARK: - LiquidHoyBuilder · Cara Matriz (FER-51 · F1 · Lane B)
//
// Proyección PURA → `MatrizHoyModel`. Cero efectos, cero fechas mágicas (usa `i.now` /
// `i.calendar`). Cero re-derivación de umbrales del motor: severidad y chip salen de
// `HoyGramatica`; historia juzgada de `prep.bodyHistory` / `sentinelHistory`.
//
// Ventanas fijas §7: sueño 14 · FC/VFC/guardián 20 · estela carga 5 · esfuerzo/pasos 14
// · estrés 7. «—» vs ausente se distinguen vía `HoyGramatica.valorODash`.

extension LiquidHoyBuilder {

    // MARK: Ventanas

    static let matrizVentanaSueno = 14
    static let matrizVentanaFC = 20
    static let matrizVentanaGuardian = 20
    static let matrizVentanaEstela = 5
    static let matrizVentanaEsfuerzo = 14
    static let matrizVentanaPasos = 14
    static let matrizVentanaEstres = 7

    // MARK: Public entry

    /// Proyección pura de los datos del motor al modelo de la cara Matriz.
    static func matriz(_ i: MatrizInputs) -> MatrizHoyModel {
        let keys = dayKeys(endingAt: i.now, calendar: i.calendar, count: matrizVentanaFC)
        let byDay = Dictionary(uniqueKeysWithValues: i.diasRecientes.map { ($0.day, $0) })
        let bodyByDay = Dictionary(uniqueKeysWithValues: (i.prep?.bodyHistory ?? []).map { ($0.day, $0) })
        let sentByDay = Dictionary(uniqueKeysWithValues: (i.prep?.sentinelHistory ?? []).map { ($0.day, $0) })
        let stressByDay = Dictionary(uniqueKeysWithValues: i.stressTrend.map { ($0.day, $0.value) })
        let stepsByDay = Dictionary(uniqueKeysWithValues: i.stepsEstimados.map { ($0.day, $0.value) })
        let cargaSeriesByDay = Dictionary(uniqueKeysWithValues: (i.carga?.series ?? []).map { ($0.day, $0.value) })

        let hoyKey = keys.last
        let hoy = hoyKey.flatMap { byDay[$0] }
        let prep = i.prep
        let razonCarga = i.carga?.acwr

        // Severidades de HOY (única fuente: HoyGramatica).
        let alertaSueno = mapaAlerta(HoyGramatica.severidad(senal: .sleep, prep: prep, razonCarga: razonCarga))
        let alertaFC = mapaAlerta(HoyGramatica.severidad(senal: .rhr, prep: prep, razonCarga: razonCarga))
        let alertaGuardian = mapaAlerta(HoyGramatica.severidad(senal: .skintemp, prep: prep, razonCarga: razonCarga))
        let alertaCarga = mapaAlerta(HoyGramatica.severidad(senal: .carga, prep: prep, razonCarga: razonCarga))


        // —— 1. Sueño (14 columnas) ——
        let keysSueno = Array(keys.suffix(matrizVentanaSueno))
        let noches: [MatrizColumnas.Noche] = keysSueno.map { day in
            let min = byDay[day]?.totalSleepMin
            // Historia juzgada con bodyHistory de ESE día — jamás con el juicio de hoy.
            let out = bodyByDay[day]?.sleepOut == true
            let alerta: MedidorLunar.Alerta = {
                if day == hoyKey { return alertaSueno }
                return out ? .atencion : .ninguna
            }()
            // Valor en HORAS para el dominio del chart (referencia 7 h).
            let horas = min.map { $0 / 60.0 }
            return MatrizColumnas.Noche(valor: horas, alerta: alerta)
        }
        let valorSueno = HoyGramatica.valorODash(hoy?.totalSleepMin) {
            HoyGramatica.formatoDuracion($0)
        }
        // Scrub (FER-55): cada noche con su día + horas + estado, ya formateados. El
        // último = hoy. La honestidad manda: sin lectura → «—» y «no reading».
        let diaFmt = weekdayFormatter(locale: i.locale, calendar: i.calendar)
        // Vocabulario ÚNICO, igual que la hoja de detalle y el héroe (revisión del dueño):
        // «in your range» / «out of your range». Y jamás afirmamos rango sin juicio del
        // motor para ESE día (hallazgo Grok #5: `sleepOut==true` también dispara por
        // eficiencia, y `nil` no es «en rango»). Sin juicio → sólo la fecha.
        let enRango = String(localized: "matriz.rango.dentro", defaultValue: "in your range")
        let fueraRango = String(localized: "matriz.rango.fuera", defaultValue: "out of your range")
        let scrubSueno: [MatrizSeccion.ScrubNoche] = keysSueno.enumerated().map { idx, day in
            let mins = byDay[day]?.totalSleepMin
            let offsetDesdeFin = keysSueno.count - 1 - idx
            let fecha = weekdayLabel(offsetFromToday: offsetDesdeFin, now: i.now,
                                     calendar: i.calendar, formatter: diaFmt)
            guard let mins else {
                return .init(valor: "—",
                             sublabel: String(format: String(localized: "matriz.scrub.sinlectura",
                                                             defaultValue: "%@ · no reading"), fecha))
            }
            // El juicio del día: nil = ese día no tiene juicio de rango todavía.
            // Paréntesis obligatorio: sin ellos `?.sleepOut.map` aplica `.map` al Bool,
            // no al Bool? del optional-chaining (precedencia de `?.`).
            let juicio: Bool? = bodyByDay[day]?.sleepOut
            let estado = juicio.map { $0 ? fueraRango : enRango }
            let sub = estado.map { "\(fecha) · \($0)" } ?? fecha
            return .init(valor: HoyGramatica.formatoDuracion(mins), sublabel: sub)
        }
        // Sublabel de reposo (no-scrub): «anoche · <estado>» — la celda habla en palabras
        // (P2), y el dato del scrub la reemplaza al arrastrar. Mismo gate de honestidad.
        let sublabelSueno: String? = {
            if hoy?.totalSleepMin == nil && noches.allSatisfy({ $0.valor == nil }) {
                return String(localized: "Getting to know you")
            }
            guard hoy?.totalSleepMin != nil else { return nil }
            guard let out = bodyByDay[hoyKey ?? ""]?.sleepOut else {
                return String(localized: "matriz.sueno.anoche", defaultValue: "last night")
            }
            let estado = out ? fueraRango : enRango
            return String(format: String(localized: "matriz.sueno.anoche.estado",
                                         defaultValue: "last night · %@"), estado)
        }()
        let seccionSueno = MatrizSeccion(
            id: "sleep", hue: LiquidColor.indigo,
            titulo: String(localized: "Sleep"),
            // FER-55: fuera el sello «vota» de las gemelas — la jerarquía la dan el nivel,
            // el orden y el manual «?». Carga NUNCA vota (loadAxis inRange/noData).
            valor: valorSueno, destacada: true, vota: false,
            sublabel: sublabelSueno,
            chartID: "matriz-sleep",
            chart: .columnas(noches: noches, referencia: 7, referenciaTag: "7 h",
                             dominio: 4...10),
            formaSello: .luna, scrubNoches: scrubSueno)

        // —— 2. FC | VFC (20) ——
        let keys20 = keys  // ya son 20
        let ptsFC: [Double?] = keys20.map { bodyByDay[$0]?.rhrResolved ?? byDay[$0].flatMap { $0.restingHr.map(Double.init) } }
        let baseFC = keys20.reversed().compactMap { bodyByDay[$0]?.rhrBaseCenter }.first
        // La banda «tu rango» (±1σ del motor, el MISMO σ del corte del veredicto) — los
        // carriles de la celda (FER-55). Sin base usable no hay carriles honestos.
        let bandaFC = keys20.reversed().compactMap { bodyByDay[$0]?.rhrBand }.first
        let valorFC = HoyGramatica.valorODash(ptsFC.last.flatMap { $0 }) {
            "\(Int($0.rounded()))"
        }
        // Scrub de FC (paridad con Sueño): día + bpm + estado. El juicio del día es el
        // del MOTOR (autonomicOrientedZ presente = juzgado; su Out = fuera). Sin juicio,
        // solo la fecha — jamás afirmar rango sin dato.
        let scrubFC: [MatrizSeccion.ScrubNoche] = keys20.enumerated().map { idx, day in
            let offsetDesdeFin = keys20.count - 1 - idx
            let fecha = weekdayLabel(offsetFromToday: offsetDesdeFin, now: i.now,
                                     calendar: i.calendar, formatter: diaFmt)
            guard let v = ptsFC[idx] else {
                return .init(valor: "—",
                             sublabel: String(format: String(localized: "matriz.scrub.sinlectura",
                                                             defaultValue: "%@ · no reading"), fecha))
            }
            let noche = bodyByDay[day]
            let estado: String? = (noche?.autonomicOrientedZ != nil)
                ? ((noche?.autonomicOut == true) ? fueraRango : enRango) : nil
            let sub = estado.map { "\(fecha) · \($0)" } ?? fecha
            return .init(valor: "\(Int(v.rounded()))", sublabel: sub)
        }
        let seccionFC = MatrizSeccion(
            id: "rhr", hue: LiquidColor.rosa,
            titulo: String(localized: "Resting HR"),
            valor: valorFC,
            unidad: ptsFC.contains(where: { $0 != nil }) ? String(localized: "bpm") : nil,
            // FER-55: sin «vota» (simétrico con Sueño — la gemela no puede quedar sola
            // con el sello o el par se ve roto). El manual «?» explica quién vota.
            destacada: true, vota: false,
            sublabel: sublabelFC(ptsFC: ptsFC, prep: prep, alerta: alertaFC),
            chartID: "matriz-rhr",
            // Los carriles (FER-55): tu rango ±1σ como franja; blend inferior muere a 0
            // sobre el papel. Sin banda usable, MatrizCarriles pinta solo la curva.
            chart: .carriles(puntos: ptsFC, banda: bandaFC,
                             dominio: dominioCarriles(ptsFC, banda: bandaFC, fallback: 45...75),
                             alertaHoy: alertaFC),
            // Decisión del dueño (FER-55): el corazón de PARTÍCULAS (contorno denso,
            // quieto — gemelo de la luna), no la gota de las hojas.
            formaSello: .corazon,
            scrubNoches: scrubFC)

        let ptsVFC: [Double?] = keys20.map { byDay[$0]?.avgHrv }
        let baseVFC = keys20.reversed().compactMap { bodyByDay[$0]?.hrvBaseCenter }.first
        let valorVFC = HoyGramatica.valorODash(ptsVFC.last.flatMap { $0 }) {
            "\(Int($0.rounded()))"
        }
        let seccionVFC = MatrizSeccion(
            id: "hrv", hue: LiquidColor.cian,
            titulo: String(localized: "HRV"),
            valor: valorVFC, unidad: String(localized: "ms"), terciaria: true,
            // P3: el abstenido explica su papel y promete el porqué a un tap.
            sublabel: String(localized: "matriz.vfc.referencia",
                             defaultValue: "reference · does not vote · why?"),
            chartID: "matriz-hrv",
            chart: .lineaRellena(puntos: ptsVFC, base: baseVFC,
                                 dominio: dominioLinea(ptsVFC, base: baseVFC, fallback: 20...80),
                                 alfa: 0.6, alertaHoy: .ninguna))

        // —— 3. Guardián ——
        let chip = chipGuardianModelo(prep?.sentinel)
        var ptsTemp: [Double?] = keys20.map { byDay[$0]?.skinTempDevC }
        // HOY usa el dev térmico AJUSTADO (descuento lúteo ya aplicado) — el MISMO número
        // que juzga el guardián y que muestra la cara Cosmos (+Cosmos.swift), para que las
        // dos caras jamás se contradigan sobre la temperatura (la deriva que FER-51 elimina).
        // La historia se queda cruda: el motor no expone un ajuste por-día, solo el de hoy.
        if let adj = prep?.thermalAdjustedDevC, !ptsTemp.isEmpty {
            ptsTemp[ptsTemp.count - 1] = adj
        }
        let ptsResp: [Double?] = keys20.map { byDay[$0]?.respRateBpm }
        let valorTemp = HoyGramatica.valorODash(ptsTemp.last.flatMap { $0 },
                                                formato: HoyGramatica.formatoDeltaTemp)
        let valorResp = HoyGramatica.valorODash(ptsResp.last.flatMap { $0 }) {
            String(format: "%.1f", $0)
        }
        // Banda ± del guardián: corte térmico público (± thermalOutC) y resp ~ base±.
        let thermalBand = Preparedness.Config.default.thermalOutC
        let seccionGuardian = MatrizSeccion(
            id: "guardian", hue: LiquidColor.doradoTemp,
            huesPar: (LiquidColor.doradoTemp, LiquidColor.azul),
            // P4: el MISMO nombre que su luna en el héroe (una sola llave).
            titulo: String(localized: "Guardian"),
            valor: "",
            sublabel: String(localized: "matriz.guardian.sub",
                             defaultValue: "watches fever and breathing while you sleep"),
            chartID: "matriz-guardian",
            chart: .lineaSerena(puntos: ptsTemp, banda: -thermalBand...thermalBand,
                                dominio: -1.5...1.5, alertaHoy: alertaGuardian),
            chip: chip,
            renglones: [
                MatrizRenglon(
                    id: "skintemp",
                    titulo: String(localized: "Skin temp"),
                    valor: valorTemp,
                    // El juicio es POR SEÑAL (tempOut) y solo con lectura de hoy —
                    // afirmar «dentro de tu banda» sin dato o contra el flag del motor
                    // es copy que miente (gate del repo; Grok+DeepSeek convergieron).
                    sublabel: valorTemp == "—" ? nil
                        : ((prep?.sentinel?.tempOut ?? false)
                            ? String(localized: "matriz.temp.fuera", defaultValue: "outside your band")
                            : String(localized: "matriz.temp.enbanda", defaultValue: "within your band")),
                    hue: LiquidColor.doradoTemp,
                    chartID: "matriz-guardian-temp",
                    chart: .lineaSerena(puntos: ptsTemp, banda: -thermalBand...thermalBand,
                                        dominio: -1.5...1.5, alertaHoy: alertaGuardian),
                    subrayado: alertaGuardian),
                MatrizRenglon(
                    id: "resp",
                    titulo: String(localized: "Breathing"),
                    valor: valorResp, unidad: valorResp == "—" ? nil : String(localized: "rpm"),
                    sublabel: valorResp == "—" ? nil
                        : ((prep?.sentinel?.respOut ?? false)
                            ? String(localized: "matriz.resp.fuera", defaultValue: "above your usual")
                            : String(localized: "matriz.resp.tipica", defaultValue: "typical for you")),
                    hue: LiquidColor.azul,
                    chartID: "matriz-guardian-resp",
                    chart: .lineaSerena(puntos: ptsResp, banda: nil,
                                        dominio: dominioLinea(ptsResp, base: nil, fallback: 8...22),
                                        alertaHoy: alertaGuardian),
                    subrayado: alertaGuardian),
            ])

        // —— 4. Carga | Esfuerzo ——
        let pCarga = razonCarga  // razón natural (API del riel: 0.8…1.3)
        // Estela: 5 posiciones PREVIAS (sin HOY), viejo → nuevo.
        let keysEstelaPrev = Array(keys.dropLast().suffix(matrizVentanaEstela))
        let estela: [Double] = keysEstelaPrev.compactMap { cargaSeriesByDay[$0] }
        let valorCarga = HoyGramatica.valorODash(razonCarga) { String(format: "%.2f", $0) }
        let estadoCargaKey = HoyGramatica.estadoCarga(razon: razonCarga)
        let seccionCarga = MatrizSeccion(
            id: "carga", hue: LiquidColor.verdePrimario,
            titulo: String(localized: "Load"),
            valor: valorCarga,
            sublabel: sublabelCargaConZona(estadoCargaKey),
            chartID: "matriz-carga",
            chart: .rielZona(p: pCarga,
                             zona: ReadinessEngine.acwrSweetSpotLow...ReadinessEngine.acwrSweetSpotHigh,
                             estela: estela, alertaHoy: alertaCarga))

        let keysEsf = Array(keys.suffix(matrizVentanaEsfuerzo))
        let ptsEsf: [Double?] = keysEsf.map { byDay[$0]?.strain }
        let valorEsf = HoyGramatica.valorODash(ptsEsf.last.flatMap { $0 }) {
            String(format: "%.1f", $0)
        }
        let seccionEsf = MatrizSeccion(
            id: "strain", hue: LiquidColor.teal,
            titulo: String(localized: "Effort"),
            valor: valorEsf, unidad: valorEsf == "—" ? nil : "/ 21",
            sublabel: valorEsf == "—" ? nil
                : String(localized: "matriz.esf.sub", defaultValue: "today's effort so far"),
            chartID: "matriz-strain",
            chart: .barrasMini(valores: ptsEsf))

        // —— 5. Estrés | Pasos ——
        let keysEstres = Array(keys.suffix(matrizVentanaEstres))
        let niveles: [Int?] = keysEstres.map { day in
            guard let v = stressByDay[day] else { return nil }
            // Cortes fijos 1.0/2.0 SOLO como geometría (StressBand) — sin color de juicio.
            switch StressBand(score: v) {
            case .low: return 0
            case .medium: return 1
            case .high: return 2
            }
        }
        let stressHoy = hoyKey.flatMap { stressByDay[$0] }
        let valorStress: String = {
            guard let v = stressHoy else { return "—" }
            switch StressBand(score: v) {
            case .low: return String(localized: "Low")
            case .medium: return String(localized: "Medium")
            case .high: return String(localized: "High")
            }
        }()
        let seccionStress = MatrizSeccion(
            id: "stress", hue: LiquidColor.tinta900,
            titulo: String(localized: "Stress"),
            valor: valorStress,
            sublabel: stressHoy == nil ? nil : String(localized: "vs your 7 days"),
            chartID: "matriz-stress",
            chart: .escalerita(niveles: niveles))

        let keysPasos = Array(keys.suffix(matrizVentanaPasos))
        let ptsPasos: [Double?] = keysPasos.map { day in
            if let s = stepsByDay[day] { return s }
            return byDay[day]?.steps.map(Double.init)
        }
        let valorPasos = HoyGramatica.valorODash(ptsPasos.last.flatMap { $0 },
                                                 formato: HoyGramatica.formatoMiles)
        let seccionPasos = MatrizSeccion(
            id: "steps", hue: LiquidColor.tinta700,
            titulo: String(localized: "Steps"),
            valor: valorPasos, terciaria: true,
            chartID: "matriz-steps",
            chart: .barrasMini(valores: ptsPasos))

        // sentByDay: reservado para los aros históricos del guardián — la API de línea serena
        // solo pinta alertaHoy hoy; la historia fuera se cubre en tests del modelo (deuda §7,
        // hallazgo adversarial Grok #3, difería StrandDesign per-punto).
        _ = sentByDay

        return MatrizHoyModel(

            bandas: [
                // Opción A del dueño (2026-08-06): el ORDEN enseña el modelo.
                // Las dos votantes GEMELAS abren la Matriz, lado a lado.
                // FER-54: el nivel que manda gana su manual — tocar el rótulo abre
                // la hoja «¿Qué decide tu día?» (el patrón queda listo para escalar
                // a los otros niveles cuando tengan la suya).
                .nivel(String(localized: "matriz.nivel.deciden",
                              defaultValue: "Decide your day"),
                       manualID: "manual.deciden"),
                .split(izq: seccionSueno, der: seccionFC),
                .nivel(String(localized: "matriz.nivel.vigila",
                              defaultValue: "Watches over you"), manualID: nil),
                .full(seccionGuardian),
                .nivel(String(localized: "matriz.nivel.contexto",
                              defaultValue: "Context"), manualID: nil),
                .split(izq: seccionCarga, der: seccionEsf),
                .split(izq: seccionVFC, der: seccionStress),
                .nivel(String(localized: "matriz.nivel.bitacora",
                              defaultValue: "Logbook"), manualID: nil),
                .full(seccionPasos),
            ])
    }

    // MARK: Helpers

    /// yyyy-MM-dd local, oldest → newest, ending at `now`'s civil day.
    static func dayKeys(endingAt now: Date, calendar: Calendar, count: Int) -> [String] {
        let start = calendar.startOfDay(for: now)
        let fmt = dayKeyFormatter(calendar: calendar)
        return (0..<count).reversed().map { offset in
            let d = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
            return fmt.string(from: d)
        }
    }

    private static func dayKeyFormatter(calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// Formateador de día de la semana corto («Mon», «lun») para el scrub (FER-55).
    static func weekdayFormatter(locale: Locale, calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = locale
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }

    /// Rótulo del día para la noche a `offsetFromToday` días atrás. Hoy → «Today».
    static func weekdayLabel(offsetFromToday: Int, now: Date, calendar: Calendar,
                             formatter: DateFormatter) -> String {
        if offsetFromToday == 0 {
            return String(localized: "matriz.scrub.hoy", defaultValue: "Today")
        }
        let start = calendar.startOfDay(for: now)
        let d = calendar.date(byAdding: .day, value: -offsetFromToday, to: start) ?? start
        return formatter.string(from: d)
    }

    static func mapaAlerta(_ a: HoyGramatica.Alerta) -> MedidorLunar.Alerta {
        switch a {
        case .ninguna: return .ninguna
        case .atencion: return .atencion
        case .alarma: return .alarma
        }
    }


    /// Chip §8 / criterio 10 — texto + tono resueltos; ordinal REAL de racha.
    static func chipGuardianModelo(_ sentinel: Preparedness.SentinelRead?)
        -> MatrizHoyModel.ChipGuardian? {
        guard let chip = HoyGramatica.chipGuardian(sentinel: sentinel) else { return nil }
        switch chip {
        case .calma:
            return .init(texto: String(localized: "At ease"), tono: .calma)
        case .vigilandoTemp:
            return .init(texto: String(localized: "Watching your temperature"),
                         tono: .terciario)
        case .vigilandoResp:
            return .init(texto: String(localized: "Watching your breathing"),
                         tono: .terciario)
        case .ambasPrimeraNoche:
            return .init(texto: String(localized: "Temperature and breathing off"),
                         tono: .atencion)
        case .racha(let n):
            let base = String(localized: "Temperature and breathing off")
            let sufijo = ordinalRacha(n)
            return .init(texto: "\(base) · \(sufijo)", tono: .alarma)
        }
    }

    /// «2nd night», «3rd night», … — ordinal REAL de `streakNights`.
    private static func ordinalRacha(_ n: Int) -> String {
        let n = max(n, 2)
        // English source (app catalog language); es-MX se resuelve en el catálogo §11 (Lane D).
        let ord: String
        switch n {
        case 2: ord = "2nd"
        case 3: ord = "3rd"
        default:
            let mod10 = n % 10
            let mod100 = n % 100
            if mod10 == 1 && mod100 != 11 { ord = "\(n)st" }
            else if mod10 == 2 && mod100 != 12 { ord = "\(n)nd" }
            else if mod10 == 3 && mod100 != 13 { ord = "\(n)rd" }
            else { ord = "\(n)th" }
        }
        return String(localized: "\(ord) night")
    }

    private static func sublabelCarga(_ key: String) -> String {
        switch key {
        case "carga.estable":     return String(localized: "Steady")
        case "carga.subiendo":    return String(localized: "Building")
        case "carga.descargando": return String(localized: "Unloading")
        case "carga.pico":        return String(localized: "Spike")
        case "carga.calibrando":  return String(localized: "Calibrating")
        default:                  return String(localized: "Calibrating")
        }
    }

    /// Dominio de línea: min/max de puntos+base con padding, o fallback.
    /// Dominio de los carriles de FC: la serie + la banda completa, con aire — la banda
    /// nunca se corta en el borde del lienzo (los carriles de fuera necesitan existir).
    static func dominioCarriles(_ pts: [Double?], banda: ClosedRange<Double>?,
                                fallback: ClosedRange<Double>) -> ClosedRange<Double> {
        var vals = pts.compactMap { $0 }
        if let banda {
            vals.append(banda.lowerBound)
            vals.append(banda.upperBound)
        }
        guard let lo = vals.min(), let hi = vals.max() else { return fallback }
        if lo == hi { return (lo - 5)...(hi + 5) }
        let pad = (hi - lo) * 0.3   // aire extra: que se VEAN los carriles de fuera
        return (lo - pad)...(hi + pad)
    }

    private static func dominioLinea(_ pts: [Double?], base: Double?,
                                     fallback: ClosedRange<Double>) -> ClosedRange<Double> {
        var vals = pts.compactMap { $0 }
        if let base { vals.append(base) }
        guard let lo = vals.min(), let hi = vals.max() else { return fallback }
        if lo == hi {
            return (lo - 5)...(hi + 5)
        }
        let pad = (hi - lo) * 0.15
        return (lo - pad)...(hi + pad)
    }
    /// Estado de la FC en palabras (P2, estudio en frío): la MISMA regla del Cosmos —
    /// z_mal ≤ −2 = «inusualmente baja» SIN alerta (§6: el lado bueno no alarma).
    /// FER-55 (panel B, Grok ALTA #1): el sublabel de FC dice el JUICIO DEL MOTOR —
    /// la única voz que héroe, scrub y hoja comparten. La franja ±1σ es geografía
    /// («donde sueles estar»), no la definición de «out of your range»: juzgar por
    /// `banda.contains` invertía el vocabulario (con FC alta el aro apaga el sublabel,
    /// así que «out» solo aparecía en el caso BUENO, contradiciendo héroe y scrub).
    private static func sublabelFC(ptsFC: [Double?], prep: Preparedness.Read?,
                                   alerta: MedidorLunar.Alerta) -> String? {
        if ptsFC.allSatisfy({ $0 == nil }) {
            return String(localized: "Getting to know you")
        }
        // Sin lectura de HOY o sin veredicto real (nil/lowSignal): no se afirma rango
        // (espejo del gate fantasma del Cosmos — Grok #3).
        guard ptsFC.last.flatMap({ $0 }) != nil,
              let v = prep?.verdict, v != .lowSignal else { return nil }
        if alerta != .ninguna { return nil }  // el aro ya habla; no duplicar.
        // El MISMO juicio por-día que usa el scrub (autonomicOut de hoy).
        guard let hoyOut = prep?.bodyHistory.last?.autonomicOut else { return nil }
        return hoyOut
            ? String(localized: "matriz.rango.fuera", defaultValue: "out of your range")
            : String(localized: "matriz.rango.dentro", defaultValue: "in your range")
    }

    /// Sublabel de carga + la zona ideal del ACWR (escala honesta, P2).
    private static func sublabelCargaConZona(_ key: String) -> String {
        let zona = String(format: String(localized: "matriz.carga.zona",
                                         defaultValue: "sweet spot %.1f–%.1f"),
                          ReadinessEngine.acwrSweetSpotLow,
                          ReadinessEngine.acwrSweetSpotHigh)
        let estado = sublabelCarga(key)
        return estado.isEmpty ? zona : "\(estado) · \(zona)"
    }
}
