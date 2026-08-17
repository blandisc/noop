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
        // FER-73 · H22: el SUEÑO se juzga contra el rango RECOMENDADO de salud (FER-44, gate
        // /cso), no contra tu base — así lo dice el acta y su hoja. La Matriz decía «in your
        // range» / «out of your range» (rango personal) para la misma noche.
        let enRangoSueno = String(localized: "matriz.sueno.rango.dentro",
                                  defaultValue: "recommended range")
        let fueraRangoSueno = String(localized: "matriz.sueno.rango.fuera",
                                     defaultValue: "below recommended")
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
            let estado = juicio.map { $0 ? fueraRangoSueno : enRangoSueno }
            let sub = estado.map { "\(fecha) · \($0)" } ?? fecha
            return .init(valor: HoyGramatica.formatoDuracion(mins), sublabel: sub)
        }
        // Sublabel de reposo (no-scrub): «anoche · <estado>» — la celda habla en palabras
        // (P2), y el dato del scrub la reemplaza al arrastrar. Mismo gate de honestidad.
        let sublabelSueno: String? = {
            if hoy?.totalSleepMin == nil && noches.allSatisfy({ $0.valor == nil }) {
                return String(localized: "hero.title.calibrando", defaultValue: "Getting to know you")
            }
            guard hoy?.totalSleepMin != nil else { return nil }
            guard let out = bodyByDay[hoyKey ?? ""]?.sleepOut else {
                return String(localized: "matriz.sueno.anoche", defaultValue: "last night")
            }
            let estado = out ? fueraRangoSueno : enRangoSueno
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
            formaSello: .luna, sello: .sueno, scrubNoches: scrubSueno)

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
        // FER-79 · D3: la ventana viva de FC (y de VFC más abajo) — el vacío inicial se recorta.
        let iniFC = inicioVivo([ptsFC])
        let ptsFCVivos = Array(ptsFC[iniFC...])
        let scrubFCVivo = Array(scrubFC[iniFC...])

        let seccionFC = MatrizSeccion(
            id: "rhr", hue: LiquidColor.rosa,
            // Título corto para la celda gemela (FER-56): «FC Reposo» / «Resting HR» pesa
            // parejo con «Sueño» y cabe en una línea al mismo tamaño. La hoja de detalle
            // conserva el nombre completo «FC en reposo».
            titulo: String(localized: "matriz.rhr.titulo.corto", defaultValue: "Resting HR"),
            valor: valorFC,
            unidad: ptsFC.contains(where: { $0 != nil }) ? String(localized: "bpm") : nil,
            // FER-55: sin «vota» (simétrico con Sueño — la gemela no puede quedar sola
            // con el sello o el par se ve roto). El manual «?» explica quién vota.
            destacada: true, vota: false,
            sublabel: sublabelFC(ptsFC: ptsFC, prep: prep, alerta: alertaFC),
            chartID: "matriz-rhr",
            // La regla al margen (FER-55, diseño final): tu rango ±1σ como tramo; relleno muere a 0
            // sobre el papel. Sin banda usable, la regla muestra solo el capilar.
            chart: .regla(puntos: ptsFCVivos, banda: bandaFC,
                          dominio: dominioCarriles(ptsFC, banda: bandaFC, fallback: 45...75),
                          alertaHoy: alertaFC),
            // Decisión del dueño (FER-55): el corazón de PARTÍCULAS (contorno denso,
            // quieto — gemelo de la luna), no la gota de las hojas.
            formaSello: .corazon,
            sello: .reposo,
            scrubNoches: scrubFCVivo)

        let ptsVFC: [Double?] = keys20.map { byDay[$0]?.avgHrv }
        let baseVFC = keys20.reversed().compactMap { bodyByDay[$0]?.hrvBaseCenter }.first
        let valorVFC = HoyGramatica.valorODash(ptsVFC.last.flatMap { $0 }) {
            "\(Int($0.rounded()))"
        }
        // Scrub de VFC (FER-62): día + valor. Sin estado de rango — la VFC NO vota, no hay
        // corte honesto que afirmar (paridad con la hoja «Tu contexto»): solo la fecha.
        let scrubVFC: [MatrizSeccion.ScrubNoche] = keys20.enumerated().map { idx, _ in
            let fecha = weekdayLabel(offsetFromToday: keys20.count - 1 - idx, now: i.now,
                                     calendar: i.calendar, formatter: diaFmt)
            guard let v = ptsVFC[idx] else {
                return .init(valor: "—",
                             sublabel: String(format: String(localized: "matriz.scrub.sinlectura",
                                                             defaultValue: "%@ · no reading"), fecha))
            }
            return .init(valor: "\(Int(v.rounded()))", sublabel: fecha)
        }
        let iniVFC = inicioVivo([ptsVFC])
        let ptsVFCVivos = Array(ptsVFC[iniVFC...])
        let scrubVFCVivo = Array(scrubVFC[iniVFC...])

        let seccionVFC = MatrizSeccion(
            id: "hrv", hue: LiquidColor.cian,
            titulo: String(localized: "HRV"),
            valor: valorVFC, unidad: String(localized: "ms"), terciaria: true,
            // Sublabel DESCRIPTIVO, simétrico con sus gemelas de contexto (Carga/Esfuerzo/
            // Estrés): el «no vota» ya no vive suelto aquí — lo lleva el rótulo de nivel
            // «Contexto» + la hoja «Tu contexto» (FER-61), así que las cuatro se ven parejas.
            sublabel: String(localized: "matriz.vfc.sub", defaultValue: "your daily HRV"),
            chartID: "matriz-hrv",
            chart: .lineaRellena(puntos: ptsVFCVivos, base: baseVFC,
                                 dominio: dominioLinea(ptsVFC, base: baseVFC, fallback: 20...80),
                                 alfa: 0.6, alertaHoy: .ninguna),
            sello: .hrv,
            scrubNoches: scrubVFCVivo)

        // —— 3. Guardián ——
        // FER-73 · H3/H5/H18: el juicio del par vale SOLO para la noche que esta pantalla llama
        // «hoy» (`sentinelHistory.last.day == hoyKey`; tras medianoche un prep viejo juzga OTRA
        // noche) y solo si el par entero se leyó y se pudo juzgar. Sin eso, ni chip verde ni
        // «dentro de tu banda»: se muestran los valores, sin afirmar patrón.
        let nocheJuzgada: Preparedness.SentinelNight? = {
            guard let n = prep?.sentinelHistory.last, let hk = hoyKey, n.day == hk else { return nil }
            return n
        }()
        let sentinelHoy: Preparedness.SentinelRead? = nocheJuzgada == nil ? nil : prep?.sentinel
        let chipJuzgado = chipGuardianJuzgado(sentinelHoy, noche: nocheJuzgada)
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
        let valorResp = HoyGramatica.valorODash(ptsResp.last.flatMap { $0 }, formato: HoyGramatica.formatoResp)
        // FER-79 · D3: las DOS filas del guardián comparten el mismo inicio vivo, para que sus
        // ejes sigan alineados entre sí (leer una contra la otra es parte de la regla del par).
        let iniGuardian = inicioVivo([ptsTemp, ptsResp])
        let hayLecturaGuardianHoy = ptsTemp.last.flatMap { $0 } != nil || ptsResp.last.flatMap { $0 } != nil
        let chip = chipGuardianModelo(chipJuzgado, noche: nocheJuzgada,
                                      hayLecturaHoy: hayLecturaGuardianHoy,
                                      calibrando: prep?.maturity == .calibrating)
        // Scrub de temp/resp (dueño 2026-08-15): día + lectura de esa noche, alineado 1:1 con la
        // serie que dibuja la línea serena. Serie de tiempo → el scrub se lee natural (a diferencia
        // de la colina de Carga, que es eje de valor y por eso NO se arrastra).
        // Banda ± del guardián: corte térmico público (± thermalOutC) y resp ~ base±.
        let thermalBand = Preparedness.Config.default.thermalOutC
        // FER-80 · LA COSTURA (propuesta C2, elegida por el dueño): las dos señales del par en
        // UNA sola gráfica, espejadas sobre un eje común, con el espacio entre ellas pintado.
        // Cada una se normaliza contra SU banda para que el espesor signifique lo mismo:
        //   · temperatura → |dev| / corte térmico público (banda absoluta en °C);
        //   · respiración → |rpm − base| / medio ancho de su banda típica.
        // Así 1.0 = «justo en el filo de tu banda» para las dos, y la boca se abre igual.
        let respBaseCostura: Double? = {
            let vistos = ptsResp.compactMap { $0 }
            guard vistos.count >= 3 else { return nil }
            return vistos.reduce(0, +) / Double(vistos.count)
        }()
        let respMedioAncho: Double = {
            guard let base = respBaseCostura else { return 2.0 }
            let vistos = ptsResp.compactMap { $0 }
            guard vistos.count >= 3 else { return 2.0 }
            let desv = vistos.map { abs($0 - base) }.reduce(0, +) / Double(vistos.count)
            return max(desv * 2, 0.8)          // piso: una banda plana no exagera el dibujo
        }()
        let nochesCostura: [MatrizCostura.Noche] = keys20.indices.map { idx in
            let dia = keys20[idx]
            let noche = sentByDay[dia]
            let t: Double? = ptsTemp[idx].map { abs($0) / max(thermalBand, 0.01) }
            let r: Double? = ptsResp[idx].flatMap { v in
                guard let base = respBaseCostura else { return nil }
                return abs(v - base) / respMedioAncho
            }
            // El par votó esa noche = el juicio del MOTOR para ESE día (nunca re-derivado aquí).
            let par = (noche?.tempOut ?? false) && (noche?.respOut ?? false)
            return .init(temp: t, resp: r, parFuera: par)
        }
        let nochesCosturaVivas = Array(nochesCostura[iniGuardian...])
        // El scrub de la costura lee LA NOCHE COMPLETA: las dos señales y su fecha.
        let scrubCostura: [MatrizSeccion.ScrubNoche] = keys20.indices.map { idx in
            let fecha = weekdayLabel(offsetFromToday: keys20.count - 1 - idx, now: i.now,
                                     calendar: i.calendar, formatter: diaFmt)
            let t = ptsTemp[idx].map { HoyGramatica.formatoDeltaTemp($0) }
            let r = ptsResp[idx].map { HoyGramatica.formatoResp($0) }
            switch (t, r) {
            case (nil, nil):
                return .init(valor: "—",
                             sublabel: String(format: String(localized: "matriz.scrub.sinlectura",
                                                             defaultValue: "%@ · no reading"), fecha))
            case (let t?, let r?):
                return .init(valor: "\(t) · \(r)", sublabel: fecha)
            case (let t?, nil):
                return .init(valor: t, sublabel: fecha)
            case (nil, let r?):
                return .init(valor: r, sublabel: fecha)
            }
        }
        let scrubCosturaVivo = Array(scrubCostura[iniGuardian...])
        // El par de números vive en el encabezado: «+0.1° · 14.9».
        let valorPar: String = {
            switch (valorTemp == "—", valorResp == "—") {
            case (false, false): return "\(valorTemp) · \(valorResp)"
            case (false, true):  return valorTemp
            case (true, false):  return valorResp
            case (true, true):   return "—"
            }
        }()

        let seccionGuardian = MatrizSeccion(
            id: "guardian", hue: LiquidColor.doradoTemp,
            huesPar: (LiquidColor.doradoTemp, LiquidColor.azul),
            // P4: el MISMO nombre que su luna en el héroe (una sola llave).
            titulo: String(localized: "Guardian"),
            // FER-80: los DOS números juntos, cada uno en su color, como manda la costura.
            valor: valorPar,
            // FER-57: la sublínea describe QUÉ vigila y CUÁNDO (el trabajo del vistazo, correcto
            // en los 5 estados); la REGLA vive SOLO tras el «?».
            sublabel: String(localized: "matriz.guardian.sub",
                             defaultValue: "your temperature and breathing while you sleep"),
            chartID: "matriz-guardian",
            // FER-80 · La costura: una sola gráfica para el par (antes dos filas que nunca se
            // miraban). Ya no hay `renglones`: la sección DIBUJA su chart.
            chart: .costura(noches: nochesCosturaVivas),
            chip: chip,
            scrubNoches: scrubCosturaVivo,
            selloGuardian: selloGuardianEstado(chipJuzgado))

        // —— 4. Carga | Esfuerzo ——
        let pCarga = razonCarga  // razón natural (API del riel: 0.8…1.3)
        // Estela: 5 posiciones PREVIAS (sin HOY), viejo → nuevo. Pareo día+valor para que el
        // scrub alinee 1:1 con los puntos que dibuja la colina.
        let keysEstelaPrev = Array(keys.dropLast().suffix(matrizVentanaEstela))
        let estelaPairs: [(day: String, v: Double)] = keysEstelaPrev.compactMap { k in
            cargaSeriesByDay[k].map { (k, $0) }
        }
        let estela: [Double] = estelaPairs.map(\.v)
        let valorCarga = HoyGramatica.valorODash(razonCarga) { String(format: "%.2f", $0) }
        let estadoCargaKey = HoyGramatica.estadoCarga(razon: razonCarga)
        // Scrub de Carga «como la hoja de resumen» (dueño 2026-08-15, 2.ª vuelta): el dedo
        // recorre los DÍAS en orden (índice uniforme, como toda serie de tiempo) y el marcador
        // se dibuja donde ESE día cae en la cuesta — el dedo no salta; el punto sí, porque eso
        // es el dato. Cada noche muestra razón + estado + fecha, como el popup de la hoja.
        func offsetHoyCarga(_ day: String) -> Int {
            guard let idx = keys.lastIndex(of: day) else { return 0 }
            return max(0, (keys.count - 1) - idx)
        }
        func lecturaCarga(_ v: Double, fecha: String) -> MatrizSeccion.ScrubNoche {
            let estado = HoyGramatica.estadoCarga(razon: v)
            return .init(valor: String(format: "%.2f", v),
                         sublabel: "\(fecha) · \(sublabelCargaConZona(estado))")
        }
        var scrubCarga: [MatrizSeccion.ScrubNoche] = estelaPairs.map { pair in
            lecturaCarga(pair.v, fecha: weekdayLabel(offsetFromToday: offsetHoyCarga(pair.day),
                                                      now: i.now, calendar: i.calendar, formatter: diaFmt))
        }
        if let hoyV = razonCarga {
            scrubCarga.append(lecturaCarga(hoyV, fecha: weekdayLabel(offsetFromToday: 0, now: i.now,
                                                                       calendar: i.calendar, formatter: diaFmt)))
        }
        let seccionCarga = MatrizSeccion(
            id: "carga", hue: LiquidColor.verdeCarga,
            titulo: String(localized: "Load"),
            valor: valorCarga,
            sublabel: sublabelCargaConZona(estadoCargaKey),
            chartID: "matriz-carga",
            chart: .colina(p: pCarga,
                             zona: ReadinessEngine.acwrSweetSpotLow...ReadinessEngine.acwrSweetSpotHigh,
                             estela: estela, alertaHoy: alertaCarga),
            sello: .carga,
            scrubNoches: scrubCarga.count > 1 ? scrubCarga : nil)

        let keysEsf = Array(keys.suffix(matrizVentanaEsfuerzo))
        let ptsEsf: [Double?] = keysEsf.map { byDay[$0]?.strain }
        let valorEsf = HoyGramatica.valorODash(ptsEsf.last.flatMap { $0 }) {
            String(format: "%.1f", $0)
        }
        // Scrub de Esfuerzo (FER-62): día + esfuerzo del día. Es una acumulación, no un
        // juicio de rango → sublabel = solo la fecha.
        let scrubEsf: [MatrizSeccion.ScrubNoche] = keysEsf.enumerated().map { idx, _ in
            let fecha = weekdayLabel(offsetFromToday: keysEsf.count - 1 - idx, now: i.now,
                                     calendar: i.calendar, formatter: diaFmt)
            guard let v = ptsEsf[idx] else {
                return .init(valor: "—",
                             sublabel: String(format: String(localized: "matriz.scrub.sinlectura",
                                                             defaultValue: "%@ · no reading"), fecha))
            }
            return .init(valor: String(format: "%.1f", v), sublabel: fecha)
        }
        let seccionEsf = MatrizSeccion(
            // Effort = Day Strain: su identidad es ÁMBAR (igual que la hoja de resumen y el
            // detalle «Day Strain»). Antes teal — chocaba con la identidad naranja del detalle.
            id: "strain", hue: LiquidColor.ambar,
            titulo: String(localized: "Effort"),
            valor: valorEsf,
            // Fuente única del sufijo de escala (no un literal): la hoja de detalle usa el
            // mismo `MetricFormat.scaleSuffix`, así que Matriz y hoja no divergen.
            unidad: valorEsf == "—" ? nil : MetricFormat.forMetric(.strain).scaleSuffix,
            sublabel: valorEsf == "—" ? nil
                : String(localized: "matriz.esf.sub", defaultValue: "today's effort so far"),
            chartID: "matriz-strain",
            chart: .barrasMini(valores: ptsEsf),
            sello: .esfuerzo,
            scrubNoches: scrubEsf)

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
        // Scrub de Estrés (FER-62): día + nivel (palabra). Los cortes son fijos, no un
        // juicio personal de rango → sublabel = solo la fecha.
        let scrubStress: [MatrizSeccion.ScrubNoche] = keysEstres.enumerated().map { idx, day in
            let fecha = weekdayLabel(offsetFromToday: keysEstres.count - 1 - idx, now: i.now,
                                     calendar: i.calendar, formatter: diaFmt)
            guard let v = stressByDay[day] else {
                return .init(valor: "—",
                             sublabel: String(format: String(localized: "matriz.scrub.sinlectura",
                                                             defaultValue: "%@ · no reading"), fecha))
            }
            let palabra: String
            switch StressBand(score: v) {
            case .low: palabra = String(localized: "Low")
            case .medium: palabra = String(localized: "Medium")
            case .high: palabra = String(localized: "High")
            }
            return .init(valor: palabra, sublabel: fecha)
        }
        let seccionStress = MatrizSeccion(
            // FER-59: Estrés RECEDE (era tinta900, máximo contraste — gritaba siendo la
            // referencia que no vota). tinta500 lo baja al peso de las demás de contexto.
            id: "stress", hue: LiquidColor.tinta500,
            titulo: String(localized: "Stress"),
            valor: valorStress,
            // FER-59: la escalerita es la tendencia de tus últimos 7 días — describir la
            // VENTANA, no un «vs» (los cortes son fijos; no es una comparación personal).
            sublabel: stressHoy == nil ? nil
                : String(localized: "matriz.stress.sub", defaultValue: "last 7 days"),
            chartID: "matriz-stress",
            chart: .escalerita(niveles: niveles),
            sello: .estres,
            scrubNoches: scrubStress)

        let keysPasos = Array(keys.suffix(matrizVentanaPasos))
        let ptsPasos: [Double?] = keysPasos.map { day in
            if let s = stepsByDay[day] { return s }
            return byDay[day]?.steps.map(Double.init)
        }
        let valorPasos = HoyGramatica.valorODash(ptsPasos.last.flatMap { $0 },
                                                 formato: HoyGramatica.formatoMiles)
        let seccionPasos = MatrizSeccion(
            // Steps = TEAL (el color de Pasos en la hoja de resumen). Antes gris (tinta700);
            // probé ámbar pero ese es de Effort — teal es su identidad real.
            id: "steps", hue: LiquidColor.teal,
            titulo: String(localized: "Steps"),
            valor: valorPasos, terciaria: true,
            chartID: "matriz-steps",
            chart: .barrasMini(valores: ptsPasos),
            sello: .pasos)

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
                // FER-56: el nivel gana su «?» reusando la hoja del guardián que YA existe
                // (`showGuardianHoja` vía `abrirHojaCaras("guardian")`) — la misma que abre el
                // encabezado. Sin segunda hoja: regla+estados+hedge con datos reales de hoy.
                .nivel(String(localized: "matriz.nivel.vigila",
                              defaultValue: "Watches over you"), manualID: "guardian"),
                .full(seccionGuardian),
                // FER-61: el nivel gana su «?» → hoja «Tu contexto», el hogar único del
                // «no deciden tu día» (resuelve la asimetría: antes solo VFC lo decía).
                .nivel(String(localized: "matriz.nivel.contexto",
                              defaultValue: "Context"), manualID: "manual.contexto"),
                .split(izq: seccionCarga, der: seccionEsf),
                .split(izq: seccionVFC, der: seccionStress),
                .nivel(String(localized: "matriz.nivel.bitacora",
                              defaultValue: "Logbook"), manualID: nil),
                .full(seccionPasos),
            ])
    }

    // MARK: Helpers

    /// FER-79 · D3 (dueño): **la ventana crece contigo**. La serie arranca en tu PRIMERA noche
    /// con lectura, no 20 días antes: con 3 noches los puntos se repartían en el 15 % derecho
    /// del ancho y el resto era aire. A partir de 20 noches el recorte no hace nada y la
    /// gráfica se comporta como siempre.
    ///
    /// Solo se recorta el vacío INICIAL: un hueco a media serie (una noche sin registrar)
    /// se conserva, porque ahí el vacío sí es información.
    static func inicioVivo(_ series: [[Double?]]) -> Int {
        let primeros = series.compactMap { $0.firstIndex(where: { $0 != nil }) }
        guard let ini = primeros.min() else { return 0 }
        return ini
    }

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


    /// FER-73 · H3: el chip del motor SOLO si el par entero se leyó y se pudo juzgar esa noche.
    /// `.quiet` con una señal ausente o con la respiración sin base usable NO es calma — el motor
    /// simplemente no marcó lo que no pudo leer (`respJudged` existe justo para esto).
    static func chipGuardianJuzgado(_ sentinel: Preparedness.SentinelRead?,
                                    noche: Preparedness.SentinelNight?) -> HoyGramatica.ChipGuardian? {
        guard let chip = HoyGramatica.chipGuardian(sentinel: sentinel) else { return nil }
        if chip == .calma, let noche, noche.tempMissing || noche.respMissing || !noche.respJudged {
            return nil
        }
        return chip
    }

    /// Chip §8 / criterio 10 — texto + tono resueltos; ordinal REAL de racha.
    /// Sin juicio (`chip == nil`) dice POR QUÉ, en tinta terciaria y sin afirmar calma:
    /// falta una señal → «Only one signal»; base formándose → «Getting to know you»; hay
    /// lectura pero el motor no comparó → «Not compared yet»; nada leído → «No readings yet».
    static func chipGuardianModelo(_ chip: HoyGramatica.ChipGuardian?,
                                   noche: Preparedness.SentinelNight? = nil,
                                   hayLecturaHoy: Bool = false,
                                   calibrando: Bool = false)
        -> MatrizHoyModel.ChipGuardian? {
        guard let chip else {
            if let noche, noche.tempMissing || noche.respMissing {
                return .init(texto: String(localized: "Only one signal"), tono: .terciario)
            }
            if !hayLecturaHoy {
                return .init(texto: String(localized: "No readings yet"), tono: .terciario)
            }
            if calibrando || noche?.respJudged == false {
                return .init(texto: String(localized: "hero.title.calibrando",
                                           defaultValue: "Getting to know you"), tono: .terciario)
            }
            return .init(texto: String(localized: "matriz.guardian.sincomparar",
                                       defaultValue: "Not compared yet"), tono: .terciario)
        }
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

    /// FER-56 · Ola 3 — el estado del sello VIVO del guardián, proyectado 1:1 del chip (nunca
    /// lo contradice): sin lectura del par ⇒ sin datos; una sola fuera ⇒ vigila esa (frío, sin
    /// alarma, como el chip terciario); el par 1.ª noche ⇒ ámbar; el par en racha ⇒ rojo.
    static func selloGuardianEstado(_ chip: HoyGramatica.ChipGuardian?) -> SelloGuardianVivo.Estado {
        guard let chip else { return .sinDatos }
        switch chip {
        case .calma:             return .calma
        case .vigilandoTemp:     return .vigilaTemp
        case .vigilandoResp:     return .vigilaResp
        case .ambasPrimeraNoche: return .ambasAmbar
        case .racha:             return .ambasRoja
        }
    }

    /// El MARCADOR ordinal solo (sin sustantivo), formateado POR locale porque su gramática es
    /// locale-específica: es-MX «N.ª» (femenino numérico, uniforme, concuerda con «noche»); en
    /// irregular (2nd/3rd/21st…). Pura y testeable (locale inyectable) — el sustantivo lo pone
    /// aparte el catálogo. `internal` a propósito: la prueba flexiona el locale sin tocar el proceso.
    static func ordinalMarcador(_ n: Int, locale: Locale = .current) -> String {
        let n = max(n, 2)
        if locale.language.languageCode == .spanish { return "\(n).ª" }
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "\(n)st" }
        if mod10 == 2 && mod100 != 12 { return "\(n)nd" }
        if mod10 == 3 && mod100 != 13 { return "\(n)rd" }
        return "\(n)th"
    }

    /// «2.ª noche» (es) / «2nd night» (en): el marcador ordinal + el sustantivo del catálogo.
    private static func ordinalRacha(_ n: Int) -> String {
        String(localized: "\(ordinalMarcador(n)) night")
    }

    /// FER-73 · HJ-07: UNA sola fuente para el vocabulario de las 4 bandas de carga —
    /// `ReadinessEngine.LoadBand.shortLabel`, el mismo que usa su hoja. La Matriz mantenía un
    /// set paralelo («Steady/Building/Unloading/Spike») y la hoja decía otra cosa para la misma
    /// banda («In balance/Ramping up/Easing off/Ramping fast»).
    private static func sublabelCarga(_ key: String) -> String {
        switch key {
        case "carga.estable":     return ReadinessEngine.LoadBand.sweetSpot.shortLabel
        case "carga.subiendo":    return ReadinessEngine.LoadBand.buildingFast.shortLabel
        case "carga.descargando": return ReadinessEngine.LoadBand.rampingDown.shortLabel
        case "carga.pico":        return ReadinessEngine.LoadBand.spiking.shortLabel
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
            return String(localized: "hero.title.calibrando", defaultValue: "Getting to know you")
        }
        // Sin lectura de HOY o sin veredicto real (nil/lowSignal): no se afirma rango
        // (espejo del gate fantasma del Cosmos — Grok #3).
        guard ptsFC.last.flatMap({ $0 }) != nil,
              let v = prep?.verdict, v != .lowSignal else { return nil }
        if alerta != .ninguna { return nil }  // el aro ya habla; no duplicar.
        // El MISMO juicio por-día que usa el scrub (autonomicOut de hoy).
        guard let hoyOut = prep?.bodyHistory.last?.autonomicOut else { return nil }
        let estado = hoyOut
            ? String(localized: "matriz.rango.fuera", defaultValue: "out of your range")
            : String(localized: "matriz.rango.dentro", defaultValue: "in your range")
        // Simetría del par (FER-56): la gemela habla con la MISMA estructura que Sueño
        // («anoche · <estado>»). La FC en reposo también es lectura de anoche, así que el
        // prefijo es igual de verdadero; reutiliza el mismo formato para que el par lea gemelo.
        return String(format: String(localized: "matriz.sueno.anoche.estado",
                                     defaultValue: "last night · %@"), estado)
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
