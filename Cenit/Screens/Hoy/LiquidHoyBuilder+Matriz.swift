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
    /// FER-125: 7 días, como el prototipo aprobado (era 14; Esfuerzo se lee por semana).
    static let matrizVentanaEsfuerzo = 7
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
                                  defaultValue: "within the recommended range")
        // SIN DIRECCIÓN (adversarial, segunda vuelta): el eje de sueño sale por `isOut`, que es
        // `.low || .high`. Sobre una noche de 9 h el rótulo «abajo del recomendado» afirmaba lo
        // contrario de lo que pasó, y `bodyHistory` no expone el lado — así que el rótulo dice
        // lo único que el motor sí juzgó: que quedó fuera.
        let fueraRangoSueno = String(localized: "matriz.sueno.rango.fuera.v2",
                                     defaultValue: "outside the recommended range")
        let scrubSueno: [MatrizSeccion.ScrubNoche] = keysSueno.enumerated().map { idx, day in
            let mins = byDay[day]?.totalSleepMin
            let offsetDesdeFin = keysSueno.count - 1 - idx
            let fecha = weekdayLabel(offsetFromToday: offsetDesdeFin, now: i.now,
                                     calendar: i.calendar, formatter: diaFmt, nocturna: true)
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
            guard hoy?.totalSleepMin != nil else {
                // Sin la noche pero con historia: lo mismo que dice su scrub y el chip del guardián
                // («anoche · sin lectura»), no un silencio (quisquilloso Q2-13).
                return noches.contains(where: { $0.valor != nil })
                    ? String(format: String(localized: "matriz.scrub.sinlectura", defaultValue: "%@ · no reading"),
                             String(localized: "matriz.sueno.anoche", defaultValue: "last night"))
                    : nil
            }
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
            valor: valorSueno,
            // «h» como su gemela dice «lpm», su hoja y el prototipo (quisquilloso Q-06).
            unidad: valorSueno == "—" ? nil : String(localized: "h"),
            destacada: true,
            sublabel: sublabelSueno,
            chartID: "matriz-sleep",
            chart: .columnas(noches: noches, referencia: 7, referenciaTag: "7 h",
                             dominio: dominioSueno(noches)),
            formaSello: .luna, glifoSello: .luna, scrubNoches: scrubSueno)

        // —— 2. FC | VFC (20) ——
        let keys20 = keys  // ya son 20
        let ptsFC: [Double?] = keys20.map { finito(bodyByDay[$0]?.rhrResolved ?? byDay[$0].flatMap { $0.restingHr.map(Double.init) }) }
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
                                     calendar: i.calendar, formatter: diaFmt,
                                     nocturna: prep?.isNightAnchored == true)
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
            destacada: true,
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
            glifoSello: .corazon,
            scrubNoches: scrubFCVivo)

        let ptsVFC: [Double?] = keys20.map { finito(byDay[$0]?.avgHrv) }
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
            valor: valorVFC, unidad: String(localized: "ms"),
            // Sublabel DESCRIPTIVO, simétrico con sus gemelas de contexto (Carga/Esfuerzo/
            // Estrés): el «no vota» ya no vive suelto aquí — lo lleva el rótulo de nivel
            // «Contexto» + la hoja «Tu contexto» (FER-61), así que las cuatro se ven parejas.
            sublabel: valorVFC == "—" ? nil : String(localized: "matriz.vfc.sub", defaultValue: "your daily HRV"),
            chartID: "matriz-hrv",
            chart: .lineaRellena(puntos: ptsVFCVivos, base: baseVFC,
                                 dominio: dominioLinea(ptsVFC, base: baseVFC, fallback: 20...80),
                                 alfa: 0.6, alertaHoy: .ninguna),
            glifoSello: .onda,
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
        var ptsTemp: [Double?] = keys20.map { finito(byDay[$0]?.skinTempDevC) }
        // HOY usa el dev térmico AJUSTADO (descuento lúteo ya aplicado) — el MISMO número
        // que juzga el guardián y que muestra la cara Cosmos (+Cosmos.swift), para que las
        // dos caras jamás se contradigan sobre la temperatura (la deriva que FER-51 elimina).
        // La historia se queda cruda: el motor no expone un ajuste por-día, solo el de hoy.
        // SELLADO POR DÍA (H6, extendido en la revisión adversarial): `thermalAdjustedDevC` es
        // el ajuste de LA NOCHE QUE EL MOTOR JUZGÓ, no «el de la última casilla». Pasada la
        // medianoche la última casilla ya es el día nuevo (vacío) y plantar ahí el número de
        // anteanoche hacía que el guardián mostrara una temperatura que el héroe —sellado en
        // TodayView desde H6— ya no muestra: dos caras de la misma pantalla contradiciéndose.
        if let adj = prep?.thermalAdjustedDevC, let hk = hoyKey,
           prep?.sentinelHistory.last?.day == hk, keys20.last == hk, !ptsTemp.isEmpty {
            ptsTemp[ptsTemp.count - 1] = adj
        }
        let ptsResp: [Double?] = keys20.map { finito(byDay[$0]?.respRateBpm) }
        let valorTemp = HoyGramatica.valorODash(ptsTemp.last.flatMap { $0 },
                                                formato: HoyGramatica.formatoDeltaTemp)
        let valorResp = HoyGramatica.valorODash(ptsResp.last.flatMap { $0 }, formato: HoyGramatica.formatoResp)
        // FER-79 · D3: las DOS filas del guardián comparten el mismo inicio vivo, para que sus
        // ejes sigan alineados entre sí (leer una contra la otra es parte de la regla del par).
        let iniGuardian = inicioVivo([ptsTemp, ptsResp])
        let hayLecturaGuardianHoy = ptsTemp.last.flatMap { $0 } != nil || ptsResp.last.flatMap { $0 } != nil
        let hayHistoriaGuardian = ptsTemp.contains { $0 != nil } || ptsResp.contains { $0 != nil }
        let chip = chipGuardianModelo(chipJuzgado, noche: nocheJuzgada,
                                      hayLecturaHoy: hayLecturaGuardianHoy,
                                      hayHistoria: hayHistoriaGuardian,
                                      calibrando: prep?.maturity == .calibrating)
        // Scrub de temp/resp (dueño 2026-08-15): día + lectura de esa noche, alineado 1:1 con la
        // serie que dibuja la línea serena. Serie de tiempo → el scrub se lee natural (a diferencia
        // de la colina de Carga, que es eje de valor y por eso NO se arrastra).
        // Banda ± del guardián: corte térmico público (± thermalOutC) y resp ~ base±.
        let thermalBand = Preparedness.Config.default.thermalOutC
        // FER-80 · LA COSTURA (propuesta C2, elegida por el dueño): las dos señales del par en
        // UNA sola gráfica, espejadas sobre un eje común, con el espacio entre ellas pintado.
        //
        // Cómo se convierte cada señal en «cuánto se abre su labio» (1.0 = justo en el filo de
        // tu banda), tras la revisión adversarial:
        //   · temperatura → dev / corte térmico público, FIRMADO.
        //   · respiración → (rpm − centro) / medio ancho, FIRMADO, con centro = MEDIANA y ancho =
        //     MAD de las noches que el motor juzgó DENTRO. Mediana y MAD porque son robustas
        //     (con media, una noche enferma corría el centro y engordaba el ancho, diluyendo
        //     justo la que debía abrirse — P-1); y solo las sanas porque una racha larga
        //     arrastraba la base hasta volverse invisible (C3).
        //
        // Qué se hace con el SIGNO no se decide aquí: lo decide el dibujo, en
        // `MatrizCostura.fraccionFilo`, que aprieta el lado bajo contra el eje porque el
        // centinela nunca marca una noche fría (C1) pero tampoco puede borrarla (COS-4).
        //
        // Y sobre las dos, el ANCLA: el labio se somete al juicio del motor por noche. Ninguna
        // escala aproximada puede dibujar «dentro» lo que el motor marcó fuera, ni al revés.
        let respEscala: (centro: Double, medioAncho: Double)? = {
            // La base se calcula SOLO con las noches que el motor juzgó DENTRO. Si se usan todas,
            // un desplazamiento sostenido (diez noches enfermas seguidas) arrastra el centro y se
            // vuelve invisible: la mitad enferma se ve tan «normal» como la sana (adversarial C3).
            let sanas: [Double] = keys20.indices.compactMap { idx -> Double? in
                guard let v = ptsResp[idx] else { return nil }
                guard let n = sentByDay[keys20[idx]] else { return v }   // sin juicio: cuenta
                return (n.respJudged && n.respOut) ? nil : v
            }
            let vistos = (sanas.count >= 3 ? sanas : ptsResp.compactMap { $0 }).sorted()
            guard vistos.count >= 3 else { return nil }
            func mediana(_ xs: [Double]) -> Double {
                let m = xs.count / 2
                return xs.count % 2 == 1 ? xs[m] : (xs[m - 1] + xs[m]) / 2
            }
            let centro = mediana(vistos)
            let mad = mediana(vistos.map { abs($0 - centro) }.sorted())
            // 1.4826·MAD ≈ σ para una normal; ×2 para que «el filo» sea ~2σ, el orden del corte
            // que usa el motor. Piso 0.8 rpm: una serie plana no exagera el dibujo.
            return (centro, max(mad * 1.4826 * 2, 0.8))
        }()
        let nochesCostura: [MatrizCostura.Noche] = keys20.indices.map { idx in
            let dia = keys20[idx]
            let noche = sentByDay[dia]
            // La magnitud va FIRMADA: negativo = por debajo de tu centro. Quien decide qué hacer
            // con el signo es el dibujo, no esta cuenta (`MatrizCostura.fraccionFilo`), y lo que
            // hace es apretar el lado bajo contra el eje: el centinela marca temperatura ALTA y
            // respiración ALTA, nunca la baja, así que ese lado no puede parecer «te saliste»
            // (adversarial C1) — pero tampoco puede desaparecer. Recortarlo a 0 (primer intento
            // de esta revisión) aplanaba media serie sobre el eje y afirmaba «justo en el centro
            // de tu banda» en noches de −0.4 °C que el scrub sí distinguía (adversarial COS-4).
            let t: Double? = ptsTemp[idx].map { $0 / max(thermalBand, 0.01) }
            var r: Double? = ptsResp[idx].flatMap { v in
                guard let esc = respEscala else { return nil }
                return (v - esc.centro) / esc.medioAncho
            }
            // ANCLA AL MOTOR (P-1). La respiración lo necesita porque el motor la juzga con z
            // contra tu base EWMA y aquí solo tenemos una escala aproximada. La temperatura HOY
            // cuadra por construcción (mismo corte, mismo número), pero se ancla igual: el día
            // que alguien mueva `thermalOutC` o el ajuste de fase, el dibujo seguirá diciendo lo
            // mismo que el juicio en vez de separarse en silencio.
            // La regla, en una línea: **SOLO lo que el motor marcó fuera puede dibujarse fuera.**
            // Marcado fuera → al menos 1.02; todo lo demás → como mucho 0.98. «Todo lo demás»
            // incluye las noches que el motor NO PUDO juzgar, y ahí estaba el agujero: el ancla
            // se condicionaba a `respJudged`, o sea que se apagaba sola justo cuando el motor no
            // tiene opinión — y entonces la escala aproximada podía mandar una noche sin juicio
            // al 0.94 del recorrido, MÁS LEJOS que una noche que el guardián sí marcó, cruzando
            // entero el hueco que existe para impedirlo (cuarta vuelta adversarial; le pasa a
            // todo usuario en sus primeras 4 noches, y otra vez cada vez que su base se resiembra).
            func anclada(_ magnitud: Double?, fuera: Bool) -> Double? {
                guard let magnitud else { return nil }
                return fuera ? max(magnitud, 1.02) : min(magnitud, 0.98)
            }
            // Y lo que el motor NO PUDO juzgar no se dibuja: ni fuera ni dentro. Apretarlo a
            // ≤0.98 —el primer intento de la cuarta vuelta— cambiaba una mentira por su espejo:
            // la noche de 17.8 rpm de tu tercera noche se colocaba a un pelo por dentro del
            // filo, con su orilla, su boca y su joya, mientras el chip decía «Conociéndote» y la
            // hoja del guardián dibujaba esa misma noche como «sin dato». El propio tipo lo
            // documenta: `nil` = no se leyó **o no se pudo juzgar** (quinta vuelta adversarial).
            //
            // Es seguro para el ámbar del par: `respOut` solo puede ser true con base usable, o
            // sea que ninguna noche que el guardián marcó se pierde por esta puerta.
            // Las dos señales NO se tratan igual, y la diferencia es de fondo: la temperatura
            // se juzga contra un corte PÚBLICO y absoluto (±`thermalOutC`) sobre una desviación
            // que ya viene normalizada contra tu propia base, así que su posición significa lo
            // mismo con o sin veredicto del centinela. La respiración se juzga con z contra tu
            // base EWMA, y aquí solo hay una mediana/MAD aproximada: sin el juicio del motor no
            // hay banda contra la cual colocarla, y el propio motor lo dice
            // (`respJudged == false` significa «no evaluada», nunca «en rango»).
            let tAnclada = noche != nil ? anclada(t, fuera: noche?.tempOut ?? false) : t
            r = (noche?.respJudged ?? false) ? anclada(r, fuera: noche?.respOut ?? false) : nil
            // El par votó esa noche = el juicio del MOTOR para ESE día (nunca re-derivado aquí).
            let par = (noche?.tempOut ?? false) && (noche?.respOut ?? false)
            // Sin magnitud, la orilla se calla: `Noche` DERIVA sus banderas del valor (ya no se
            // pasan). Con lectura pero sin escala —menos de 3 noches de respiración— dibujarla
            // pegada al eje con su joya de HOY afirmaba «justo en el centro de tu banda»
            // mientras el chip de la misma tarjeta decía «Conociéndote» (adversarial COS-2).
            // Lo que se calla es la POSICIÓN: el número crudo sigue vivo en el encabezado y en
            // el scrub, y el ámbar del par ya no depende de que esta orilla exista (COS-1).
            return .init(temp: tAnclada, resp: r, parFuera: par)
        }
        let nochesCosturaVivas = Array(nochesCostura[iniGuardian...])
        // El scrub de la costura lee LA NOCHE COMPLETA: las dos señales y su fecha.
        let scrubCostura: [MatrizSeccion.ScrubNoche] = keys20.indices.map { idx in
            let fechaSola = weekdayLabel(offsetFromToday: keys20.count - 1 - idx, now: i.now,
                                         calendar: i.calendar, formatter: diaFmt, nocturna: true)
            // FER-118: mientras el dedo lee una noche, el subtítulo dice si el PAR votó esa
            // noche — y solo eso, y solo con el juicio del motor (`parFuera` de `nochesCostura`,
            // el arreglo SIN recortar: mismo índice que `keys20`; el recorte viene después).
            let fecha = nochesCostura[idx].parFuera
                ? String(format: String(localized: "matriz.guardian.scrub.par",
                                        defaultValue: "%@ · both moved out together"), fechaSola)
                : fechaSola
            let t = ptsTemp[idx].map { HoyGramatica.formatoDeltaTemp($0) }
            let r = ptsResp[idx].map { HoyGramatica.formatoResp($0) }
            switch (t, r) {
            case (nil, nil):
                return .init(valor: "—",
                             sublabel: String(format: String(localized: "matriz.scrub.sinlectura",
                                                             defaultValue: "%@ · no reading"), fechaSola))
            default:
                // La MISMA regla que el encabezado (adversarial C4, extendida al scrub en
                // COS/A4): con una sola señal, el número solitario se pintaba con el hue de la
                // otra —el color es lo único que las distingue— así que el guion ocupa el lugar
                // de la que faltó y el par conserva su forma.
                return .init(valor: "\(t ?? "—") · \(r ?? "—")", sublabel: fecha)
            }
        }
        let scrubCosturaVivo = Array(scrubCostura[iniGuardian...])
        // El par de números vive en el encabezado: «+0.1° · 14.9».
        // El par conserva SIEMPRE su forma «temp · resp» mientras haya al menos una lectura
        // (adversarial C4): con una sola, el número solitario se pintaba con el hue de la OTRA
        // señal —el color es lo único que las identifica— y sin unidad. El guion ocupa el lugar
        // de la que faltó, en su propio color.
        let valorPar: String = (valorTemp == "—" && valorResp == "—")
            ? "—"
            : "\(valorTemp) · \(valorResp)"

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
            // P-4: VoiceOver nombra cada señal — «+0.1° · 14.9» leído de corrido no dice cuál
            // es cuál (antes lo decían los dos renglones que la costura sustituyó).
            a11yValor: {
                var partes: [String] = []
                if valorTemp != "—" {
                    partes.append("\(String(localized: "Skin temp")) \(valorTemp)")
                }
                if valorResp != "—" {
                    partes.append("\(String(localized: "Breathing")) \(valorResp) \(String(localized: "rpm"))")
                }
                return partes.isEmpty ? nil : partes.joined(separator: ", ")
            }(),
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
                         sublabel: "\(fecha) · \(sublabelCarga(estado, locale: i.locale))")
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
            // FER-125: la zona ideal ya la dibuja la campana con sus etiquetas (0.8 · 1.3); el
            // sublabel dice solo el estado, en minúscula como sus vecinos («en equilibrio»).
            sublabel: sublabelCarga(estadoCargaKey, locale: i.locale),
            chartID: "matriz-carga",
            chart: .colina(p: pCarga,
                             zona: ReadinessEngine.acwrSweetSpotLow...ReadinessEngine.acwrSweetSpotHigh,
                             estela: estela, alertaHoy: alertaCarga),
            glifoSello: .carga,
            scrubNoches: scrubCarga.count > 1 ? scrubCarga : nil)

        let keysEsf = Array(keys.suffix(matrizVentanaEsfuerzo))
        let ptsEsf: [Double?] = keysEsf.map { finito(byDay[$0]?.strain) }
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
            glifoSello: .llama,
            scrubNoches: scrubEsf)

        // —— 5. Estrés | Pasos ——
        let keysEstres = Array(keys.suffix(matrizVentanaEstres))
        // Cortes fijos 1.0/2.0 SOLO como geometría (StressBand) — sin color de juicio.
        let niveles: [Int?] = keysEstres.map { day in stressByDay[day].map(nivelStress) }
        let stressHoy = hoyKey.flatMap { stressByDay[$0] }
        // FER-125 (prototipo aprobado): la palabra va en MINÚSCULA («bajo · medio · alto») y
        // toma el color de calor de su nivel (la misma rampa que las celdas, FER-60).
        func palabraStress(_ v: Double) -> String {
            let p: String
            switch StressBand(score: v) {
            case .low: p = String(localized: "Low")
            case .medium: p = String(localized: "Medium")
            case .high: p = String(localized: "High")
            }
            return p.lowercased(with: i.locale)
        }
        let valorStress: String = stressHoy.map(palabraStress) ?? "—"
        // Una sola rampa de calor para la palabra y las celdas: `MatrizEscalerita.colorNivel`
        // (revisión adversarial M35-04: dos switches se desincronizan).
        func nivelStress(_ v: Double) -> Int {
            switch StressBand(score: v) {
            case .low: return 0
            case .medium: return 1
            case .high: return 2
            }
        }
        let hueStress: Color = stressHoy.map { MatrizEscalerita.colorNivel(nivelStress($0)) } ?? LiquidColor.tinta500
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
            return .init(valor: palabraStress(v), sublabel: fecha)
        }
        let seccionStress = MatrizSeccion(
            // FER-59: Estrés RECEDE (era tinta900) — y desde FER-125 su hue es el CALOR de su
            // nivel de hoy (tinta500 bajo · ocre medio · siena alto), como el prototipo.
            id: "stress", hue: hueStress,
            titulo: String(localized: "Stress"),
            valor: valorStress,
            // FER-59: la escalerita es la tendencia de tus últimos 7 días — describir la
            // VENTANA, no un «vs» (los cortes son fijos; no es una comparación personal).
            sublabel: stressHoy == nil ? nil
                : String(localized: "matriz.stress.sub", defaultValue: "last 7 days"),
            chartID: "matriz-stress",
            chart: .escalerita(niveles: niveles),
            glifoSello: .estres,
            scrubNoches: scrubStress)

        let keysPasos = Array(keys.suffix(matrizVentanaPasos))
        let ptsPasos: [Double?] = keysPasos.map { day in
            if let s = stepsByDay[day] { return finito(s) }
            return finito(byDay[day]?.steps.map(Double.init))
        }
        // FER-125 (prototipo aprobado): los pasos se leen en MILES con un decimal y la unidad
        // «k» («6,2 k» en es · «6.2 k» en en) — el número corto del mockup; el conteo exacto
        // vive en la hoja. Escala 0…máximo de la ventana; el promedio de la ventana es la
        // línea punteada de referencia de la gráfica.
        let formatoK: (Double) -> String = { HoyGramatica.formatoMilesK($0, locale: i.locale) }
        let valorPasos = HoyGramatica.valorODash(ptsPasos.last.flatMap { $0 }, formato: formatoK)
        // El promedio es de los días ANTERIORES (hoy va a medias y lo arrastraría hacia abajo:
        // a las 8 a.m. con 300 pasos, «tu promedio» caería ~7 % — revisión adversarial M35-01).
        let pasosPrevios = ptsPasos.dropLast().compactMap { $0 }
        let promedioPasos: Double? = pasosPrevios.count >= 2
            ? pasosPrevios.reduce(0, +) / Double(pasosPrevios.count) : nil
        // VoiceOver no ve la «k» (es un Text al lado del número): la voz lee el conteo entero.
        let a11yPasos: (Double) -> String = { "\(HoyGramatica.formatoMiles($0)) \(String(localized: "Steps"))" }
        // Scrub de Pasos (FER-118, «scrub en todas las gráficas» — era la única sin él): día +
        // pasos del día. Es un conteo, no un juicio de rango → sublabel = solo la fecha.
        let scrubPasos: [MatrizSeccion.ScrubNoche] = keysPasos.enumerated().map { idx, _ in
            let fecha = weekdayLabel(offsetFromToday: keysPasos.count - 1 - idx, now: i.now,
                                     calendar: i.calendar, formatter: diaFmt)
            guard let v = ptsPasos[idx] else {
                return .init(valor: "—",
                             sublabel: String(format: String(localized: "matriz.scrub.sinlectura",
                                                             defaultValue: "%@ · no reading"), fecha))
            }
            return .init(valor: formatoK(v), sublabel: fecha, a11yValor: a11yPasos(v))
        }
        let seccionPasos = MatrizSeccion(
            // Steps = TEAL (el color de Pasos en la hoja de resumen). Antes gris (tinta700);
            // probé ámbar pero ese es de Effort — teal es su identidad real.
            id: "steps", hue: LiquidColor.teal,
            titulo: String(localized: "Steps"),
            valor: valorPasos,
            unidad: valorPasos == "—" ? nil : String(localized: "matriz.pasos.k", defaultValue: "k"),
            sublabel: valorPasos == "—" ? nil
                : String(localized: "matriz.pasos.sub", defaultValue: "today · 14 days"),
            chartID: "matriz-steps",
            chart: .barrasMini(valores: ptsPasos, promedio: promedioPasos),
            glifoSello: .pasos,
            scrubNoches: scrubPasos,
            a11yValor: ptsPasos.last.flatMap { $0 }.map(a11yPasos))

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
                // FER-118: Pasos cierra el estante Contexto, ancho. El rótulo «Bitácora» se
                // retiró (el prototipo aprobado tiene TRES estantes, con su «?» cada uno).
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
    /// `nocturna`: la serie es de NOCHES (Sueño, FC, guardián) y su último índice se llama «anoche»
    /// —como lo llama el módulo al soltar—, no «Hoy» (quisquilloso Q-16; prototipo: sueño/fc/guard
    /// «anoche», esf/estrés/pasos/carga/VFC «hoy»).
    static func weekdayLabel(offsetFromToday: Int, now: Date, calendar: Calendar,
                             formatter: DateFormatter, nocturna: Bool = false) -> String {
        if offsetFromToday == 0 {
            // Clave propia del scrub («Last night», como «Wed»): la prosa del módulo sigue en
            // `matriz.sueno.anoche` («last night»). En es las dos van en minúscula, como «mié».
            return nocturna ? String(localized: "matriz.scrub.anoche", defaultValue: "Last night")
                            : String(localized: "matriz.scrub.hoy", defaultValue: "Today")
        }
        let start = calendar.startOfDay(for: now)
        let d = calendar.date(byAdding: .day, value: -offsetFromToday, to: start) ?? start
        return formatter.string(from: d)
    }

    /// Dominio de las columnas de sueño: 4…10 h como base, AMPLIADO hasta la noche más corta/larga
    /// de la ventana (FER-128, exploradores: una noche de 2 h o de 12 h se pintaba idéntica al piso
    /// o al techo, con el aro encima del rótulo «7 h»). La referencia sigue en 7 h.
    static func dominioSueno(_ noches: [MatrizColumnas.Noche]) -> ClosedRange<Double> {
        let horas = noches.compactMap { $0.valor }.filter(\.isFinite)
        let lo = min(4, (horas.min() ?? 4).rounded(.down))
        let hi = max(10, (horas.max() ?? 10).rounded(.up))
        return lo...max(hi, lo + 1)
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
                                   hayHistoria: Bool = false,
                                   calibrando: Bool = false)
        -> MatrizHoyModel.ChipGuardian? {
        guard let chip else {
            // Orden: primero «no hubo NADA» (adversarial C5 — con las dos ausentes, `tempMissing`
            // era true y el chip decía «solo una señal», que es falso), y solo después «falta una».
            // FER-128 (explorador): «Aún no hay lecturas» sobre una gráfica llena de noches era
            // falso (cada mañana antes de sincronizar el reloj): con historia, «Sin lectura de hoy».
            if !hayLecturaHoy {
                return hayHistoria
                    ? .init(texto: String(localized: "No reading last night"), tono: .terciario)
                    : .init(texto: String(localized: "No readings yet"), tono: .terciario)
            }
            if let noche, noche.tempMissing != noche.respMissing {
                return .init(texto: String(localized: "Only one signal"), tono: .terciario)
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
    private static func sublabelCarga(_ key: String, locale: Locale) -> String {
        let s: String
        switch key {
        case "carga.estable":     s = ReadinessEngine.LoadBand.sweetSpot.shortLabel
        case "carga.subiendo":    s = ReadinessEngine.LoadBand.buildingFast.shortLabel
        case "carga.descargando": s = ReadinessEngine.LoadBand.rampingDown.shortLabel
        case "carga.pico":        s = ReadinessEngine.LoadBand.spiking.shortLabel
        default:                  s = String(localized: "Calibrating")
        }
        return s.lowercased(with: locale)
    }

    /// Dominio de línea: min/max de puntos+base con padding, o fallback.
    /// Dominio de los carriles de FC: la serie + la banda completa, con aire — la banda
    /// nunca se corta en el borde del lienzo (los carriles de fuera necesitan existir).
    /// Un valor no finito (NaN/±inf) es un HUECO, no un dato: un NaN en un dominio tumbaba la app
    /// («Range requires lowerBound <= upperBound») y en una gráfica daba geometría no finita
    /// (FER-128, explorador Grok). Se sanea en la entrada: toda serie pasa por aquí.
    static func finito(_ v: Double?) -> Double? {
        guard let v, v.isFinite else { return nil }
        return v
    }

    static func dominioCarriles(_ pts: [Double?], banda: ClosedRange<Double>?,
                                fallback: ClosedRange<Double>) -> ClosedRange<Double> {
        var vals = pts.compactMap { $0 }.filter(\.isFinite)
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
        var vals = pts.compactMap { $0 }.filter(\.isFinite)
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
            // «Conociéndote» promete un proceso en marcha. Sin FC nocturna posible no lo hay, y
            // el héroe de la misma pantalla ya dijo lo contrario: la celda callaba la verdad y
            // repetía la promesa (cuarta vuelta adversarial).
            guard prep?.autonomicPossible != false else {
                // El módulo es angosto: la frase del héroe («Todavía no puedo leer tus mañanas»)
                // no cabía en una línea (dueño, FER-125) — misma verdad, más corta.
                return String(localized: "matriz.fc.sinmananas", defaultValue: "no morning reads yet")
            }
            // Y solo si la base SE ESTÁ formando. A quien tiene meses de historia y dejó el
            // reloj treinta días, la ventana de 20 días le sale vacía pero su rango ya existe:
            // «Conociéndote» le decía que empezaba de cero justo debajo de un héroe que le
            // habla de su rango de siempre (quinta vuelta adversarial).
            if prep?.maturity == .stale {
                return String(localized: "hero.title.rancia", defaultValue: "Your range needs fresh nights")
            }
            guard prep == nil || prep?.maturity == .calibrating else { return nil }
            return String(localized: "hero.title.calibrando", defaultValue: "Getting to know you")
        }
        // Sin lectura de HOY o sin veredicto real (nil/lowSignal): no se afirma rango
        // (espejo del gate fantasma del Cosmos — Grok #3).
        guard ptsFC.last.flatMap({ $0 }) != nil else {
            // Sin la noche pero con historia: «anoche · sin lectura», como su scrub (Q2-13).
            guard ptsFC.contains(where: { $0 != nil }), prep?.isNightAnchored != false else { return nil }
            return String(format: String(localized: "matriz.scrub.sinlectura", defaultValue: "%@ · no reading"),
                          String(localized: "matriz.sueno.anoche", defaultValue: "last night"))
        }
        // Con lectura pero SIN veredicto real (nil/lowSignal) no se afirma rango — pero la gemela
        // Sueño sí dice «anoche» en ese caso: FC también (quisquilloso Q-15b), si es nocturna.
        guard let v = prep?.verdict, v != .lowSignal else {
            return prep?.isNightAnchored == true
                ? String(localized: "matriz.sueno.anoche", defaultValue: "last night") : nil
        }
        // FER-128 (dueño, captura a xxxLarge): con el aro puesto el sublabel quedaba VACÍO
        // mientras Sueño, su gemela, decía «anoche · fuera del rango recomendado» con el suyo, y
        // el héroe listado decía «fuera de tu rango» para FC. El aro y las palabras dicen lo mismo
        // a la vez — como en Sueño (antes: «el aro ya habla; no duplicar», FER-55).
        // El MISMO juicio por-día que usa el scrub (autonomicOut de hoy).
        guard let hoyOut = prep?.bodyHistory.last?.autonomicOut else { return nil }
        let estado = hoyOut
            ? String(localized: "matriz.rango.fuera", defaultValue: "out of your range")
            : String(localized: "matriz.rango.dentro", defaultValue: "in your range")
        // Simetría del par (FER-56): la gemela habla con la MISMA estructura que Sueño
        // («anoche · <estado>»). Pero SOLO cuando la lectura es de la noche: en «lectura de día»
        // —el que trae el reloj despierto y duerme sin él— el número viene de la serie de
        // vigilia, y el prefijo «anoche» afirmaba una medición nocturna que no existe, justo
        // debajo de un héroe que dice lo contrario (cuarta vuelta adversarial).
        guard prep?.isNightAnchored == true else { return estado }
        return String(format: String(localized: "matriz.sueno.anoche.estado",
                                     defaultValue: "last night · %@"), estado)
    }

}
