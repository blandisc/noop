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
        let seccionSueno = MatrizSeccion(
            id: "sleep", hue: LiquidColor.indigo,
            titulo: String(localized: "Sleep"),
            // «vota» es ROL estable del modelo (las decisoras §6), no «votó esta noche» —
            // por eso no se apaga sin lectura. Carga NUNCA vota (loadAxis inRange/noData).
            valor: valorSueno, destacada: true, vota: true,
            sublabel: (hoy?.totalSleepMin == nil && noches.allSatisfy { $0.valor == nil })
                ? String(localized: "Getting to know you") : nil,
            chartID: "matriz-sleep",
            chart: .columnas(noches: noches, referencia: 7, referenciaTag: "7 h",
                             dominio: 4...10))

        // —— 2. FC | VFC (20) ——
        let keys20 = keys  // ya son 20
        let ptsFC: [Double?] = keys20.map { bodyByDay[$0]?.rhrResolved ?? byDay[$0].flatMap { $0.restingHr.map(Double.init) } }
        let baseFC = keys20.reversed().compactMap { bodyByDay[$0]?.rhrBaseCenter }.first
        let valorFC = HoyGramatica.valorODash(ptsFC.last.flatMap { $0 }) {
            "\(Int($0.rounded()))"
        }
        let seccionFC = MatrizSeccion(
            id: "rhr", hue: LiquidColor.rosa,
            titulo: String(localized: "Resting HR"),
            valor: valorFC, unidad: valorFC == "—" ? nil : String(localized: "bpm"),
            destacada: true, vota: true,
            sublabel: sublabelFC(ptsFC: ptsFC, prep: prep, alerta: alertaFC),
            chartID: "matriz-rhr",
            chart: .lineaRellena(puntos: ptsFC, base: baseFC,
                                 dominio: dominioLinea(ptsFC, base: baseFC, fallback: 45...75),
                                 alfa: 1.0, alertaHoy: alertaFC))

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
        // z_mal = −orientedZ del eje autonómico (compuesto; wRHR=1) — la MISMA
        // derivación que usa la ancla del Cosmos (§6).
        let zMal: Double? = {
            guard let z = prep?.drivers.first(where: { $0.axis == .autonomic })?.orientedZ
            else { return nil }
            return -z
        }()
        if let z = zMal, z <= -2 {
            return String(localized: "matriz.fc.baja",
                          defaultValue: "low · good side")
        }
        return String(localized: "matriz.fc.enrango", defaultValue: "in your range")
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
