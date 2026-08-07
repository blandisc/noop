import Foundation
import SwiftUI
import StrandAnalytics
import StrandDesign

// MARK: - LiquidHoyBuilder (FER-1045)
//
// La proyección PURA del estado ya derivado de Hoy al modelo Liquid (`LiquidHoyModel`).
// NO re-evalúa ningún motor: recibe lo que `Repository`/`TodayView` ya resolvieron
// (Preparedness off-main, TrainingLoadModel, lecturas por tile) y solo mapea/formatea —
// el costo es O(#tiles).
//
// Paridad de producto (plan adversarial Claude+Grok, 3 rounds → GO):
//  · Héroe: port literal del if-chain de `TodayView.heroBlock` — tabla canónica de 4
//    renglones; `lowSignal` o `prep == nil` caen al fallback de SUEÑO (jamás un «Baja
//    señal» con palabra destacada). Strings = claves EXISTENTES del catálogo
//    (FER-1042 / FER-1033, allow-list /cso).
//  · Señales: port literal de `TodayView.needles()` (positionFromZ / positionFromState +
//    fallback térmico FER-1043). Única desviación deliberada: sin lectura térmica el orbe
//    se muestra «sin datos» (la composición conserva sus 3 orbes) en vez de ocultarse.
//  · Carga: mismo mapeo de la franja (`TrainingLoadStrip`): knob = clamp(acwr/2, .05, .95),
//    banda = `ReadinessEngine.loadBand`, ok solo en sweetSpot; sin modelo → sin barra;
//    `acwr == nil` → calibrando.
//  · Tiles: mismos 8 vitales, mismos formatters y el mismo contexto delta (`tileContext`).

enum LiquidHoyBuilder {

    // MARK: Entradas

    /// Un valor resuelto por las capas de Hoy + su procedencia (Apple Salud o no).
    struct Lectura: Equatable {
        let value: Double
        let fromApple: Bool

        init(_ value: Double, fromApple: Bool = true) {
            self.value = value
            self.fromApple = fromApple
        }
    }

    /// Las bases de 7 días por métrica (las MISMAS ventanas `history(base)` de los tiles).
    struct Historias {
        var sleep: [Double] = []
        var hrv: [Double] = []
        var rhr: [Double] = []
        var strain: [Double] = []
        var steps: [Double] = []
        var skinTemp: [Double] = []
        var resp: [Double] = []
        var stress: [Double] = []
    }

    struct Inputs {
        var preparedness: Preparedness.Read?
        /// La misma última desviación térmica que muestra el tile (FER-1043), para el eje.
        var thermalDeviation: Double?
        var trainingLoad: TrainingLoadModel?
        var sleep: Lectura?
        var hrv: Lectura?
        var rhr: Lectura?
        var strain: Double?
        var strainEstimated: Bool = false
        var steps: Double?
        var stepsEstimated: Bool = false
        var skinTemp: Lectura?
        var resp: Lectura?
        var stress: Double?
        var historias = Historias()
        /// ¿El permiso de Apple Salud está concedido? Sin él, el héroe «sin datos» pide
        /// conectar Salud en vez de una instrucción imposible (revote /inject).
        var healthConnected: Bool = true
        /// El veredicto todavía NO se ha calculado en este pase (solo sale del refresh completo,
        /// `Repository.performRefresh(full:)`). Distinto de «no hay veredicto»: con `true` el héroe
        /// dice que está leyendo, NO que no conoce tu base — a alguien con años de historia esa frase
        /// sería falsa, y aparecería en cada arranque en frío.
        var verdictPending: Bool = false
        /// La noche que esta pantalla llama «hoy» (`Repository.localDayKey`). El guardián solo
        /// afirma patrón cuando la última noche que el centinela juzgó ES esta — sin coincidencia
        /// (o sin sello) vigila en `.incompleto`, para no mezclar valores de hoy con un juicio de
        /// otra noche (FER-42).
        var nightKey: String? = nil
        /// Ventana de la sesión de sueño de anoche en horas locales 0–24 (nil = sin sesión).
        var night: (start: Double, end: Double)?
        /// Amanecer/atardecer locales en horas reloj (SolarClock; nil = caso polar).
        var sol: (start: Double, end: Double)?
        var now: Date = Date()
        var calendar: Calendar = .current
        var locale: Locale = .current
    }

    /// A dónde navega el tap del héroe — el MISMO destino que hoy (paridad).
    enum HeroRoute: Equatable {
        case autonomic   // veredicto y lectura de día → hoja autonómica
        case salud       // sin permiso de Salud: la puerta abre el flujo de conexión (FER-10)
    }

    struct Output {
        let model: LiquidHoyModel
        let heroRoute: HeroRoute
    }

    // MARK: Build

    static func build(_ i: Inputs) -> Output {
        let (hero, route, calibracion) = hero(prep: i.preparedness,
                                              nights: i.preparedness?.autonomicNights ?? 0,
                                              healthConnected: i.healthConnected,
                                              verdictPending: i.verdictPending)
        let ms = metricas(i)
        let cargaM = carga(i.trainingLoad, locale: i.locale)
        let guardianM = guardian(prep: i.preparedness, thermalDeviation: i.thermalDeviation,
                                 resp: i.resp, nightKey: i.nightKey)
        let model = LiquidHoyModel(
            kicker: kicker(now: i.now, calendar: i.calendar, locale: i.locale),
            dial: .init(night: i.night, sol: i.sol,
                        marker: markerHour(now: i.now, calendar: i.calendar)),
            senales: senales(prep: i.preparedness,
                             valores: (rhr: i.rhr.map { "\(Int($0.value.rounded())) \(String(localized: "bpm"))" },
                                       rhrNum: i.rhr.map { "\(Int($0.value.rounded()))" },
                                       sueno: i.sleep.map { sleepClockText($0.value) })),
            hero: hero,
            carga: cargaM,
            metricas: ms,
            guardian: guardianM,
            heroHint: String(localized: "Opens the detail"),
            ambiente: ambiente(prep: i.preparedness),
            cargaLabel: String(localized: "Load").uppercased(with: i.locale),
            kickerA11y: kickerA11y(now: i.now, calendar: i.calendar, locale: i.locale),
            // La afordancia de descubrimiento: la pastilla bajo el veredicto deja de ser el
            // tether de confianza (que DESAPARECÍA con la base madura, justo donde vive el
            // usuario el 90 % del tiempo) y pasa a ser la PUERTA. Siempre presente, en los
            // dos estados del héroe.
            heroPuerta: route == .salud ? String(localized: "Connect Health")
                                        : String(localized: "How I got here"),
            calibracion: calibracion,
            rotulos: rotulos(locale: i.locale))
        return Output(model: model, heroRoute: route)
    }

    /// Entradas de la hoja del guardián (FER-33 · F3): series de 14 noches + historial
    /// del centinela ya votado por el motor. El builder NO recalcula cortes.
    struct GuardianHojaInputs {
        var guardian: LiquidHoyModel.Guardian?
        var prep: Preparedness.Read?
        var tempTrend: [(fecha: Date, valor: Double)] = []
        var respTrend: [(fecha: Date, valor: Double)] = []
        var now: Date = Date()
        var calendar: Calendar = .current
        var locale: Locale = .current
    }

    /// La hoja del guardián (FER-33 · F3): contesta «¿qué es VIGILANDO?» con la familia
    /// de hojas (header, héroe-palabra, par vigilado con mini-gráficas, dominó, método).
    /// Jamás «enfermedad». Sin lecturas **no** afirma «dentro de tu patrón».
    static func guardianHoja(_ i: GuardianHojaInputs) -> LiquidGuardianHoja {
        let estado = i.guardian?.estado ?? .sinLectura
        let (nivel, sinLectura, conteo, nota, notaAvisa, enPatron) =
            copyGuardian(estado: estado, guardian: i.guardian, prep: i.prep)
        let sello = selloAnoche(now: i.now, calendar: i.calendar, locale: i.locale)
        let tempFuera = estado == .tempFuera || estado == .juntas
        let respFuera = estado == .respFuera || estado == .juntas
        let sinDatoAnoche = estado == .sinLectura

        // Banda del patrón en las mini-gráficas:
        // · temp: el corte absoluto del centinela (`thermalOutC`, ya público) — lo que el
        //   motor usa para marcar fuera; no se recalcula.
        // · resp: la banda «normal» del catálogo de niveles de la hoja de respiración
        //   (abierta por abajo, techo 20 rpm). El motor juzga por z-score de la base
        //   personal; sin exponer mean/sd al UI, esta es la aproximación limpia de la
        //   misma hoja de métrica (se reporta en el PR).
        // TEMPERATURA: el corte del motor es ABSOLUTO sobre la desviación contra TU base
        // (`skinTempDevC` ya es «cuánto te saliste de lo tuyo»), así que ±thermalOutC ES tu
        // patrón, dicho con el mismo número que usa el centinela para marcar.
        let tempBand = -Preparedness.Config.default.thermalOutC
            ... Preparedness.Config.default.thermalOutC
        // RESPIRACIÓN: SIN banda, a propósito. El motor la juzga por z-score contra TU base
        // personal, y esa base no está expuesta al UI. Aquí vivía «12...20», que es la tabla
        // POBLACIONAL del catálogo de niveles — dibujarla bajo el rótulo «la banda es tu
        // patrón», dos dedos arriba de un método que promete «no contra tablas de población»,
        // era afirmar lo contrario de lo que el motor hace. Con base estrecha, una noche podía
        // caer DENTRO de la banda dibujada y FUERA para el dominó, en la misma pantalla.
        // Sin banda la línea sigue contando su historia y nadie miente. (FER-33, gate /qa D1.)
        let respBand: ClosedRange<Double>? = nil

        // Calibrando, NINGUNA banda: la nota dice «las lecturas se muestran sin comparación»
        // y pintar el corredor de comparación al lado la desmentía. (gate /qa D4.)
        // «Comparando» solo en los estados donde el motor de verdad comparó: en los demás la
        // hoja muestra lecturas crudas, y ni el corredor ni VoiceOver pueden insinuar patrón.
        let comparando: Bool = {
            switch estado {
            case .tranquilo, .tempFuera, .respFuera, .juntas: return true
            case .sinLectura, .conociendote, .incompleto:     return false
            }
        }()
        let tempSerie = serieMini(
            puntos: i.tempTrend, banda: comparando ? tempBand : nil,
            sinDatoAnoche: sinDatoAnoche || i.guardian?.temp == "—",
            fmtValor: { String(format: "%+.1f°", $0) },
            fmtFecha: popupFechaFmt(locale: i.locale),
            a11y: String(localized: "Skin temperature, last 14 nights"),
            vacio: String(localized: "No readings yet."))
        let respSerie = serieMini(
            puntos: i.respTrend, banda: comparando ? respBand : nil,
            sinDatoAnoche: sinDatoAnoche || i.guardian?.resp == "—",
            fmtValor: { "\(Int($0.rounded())) \(String(localized: "rpm"))" },
            fmtFecha: popupFechaFmt(locale: i.locale),
            a11y: String(localized: "Breathing, last 14 nights"),
            vacio: String(localized: "No readings yet."))

        let tempVal = i.guardian?.temp ?? "—"
        let respVal = i.guardian?.resp ?? "—"
        let temp = LiquidGuardianHoja.Senal(
            id: "temp",
            etiqueta: String(localized: "Skin temperature"),
            valor: tempVal, tono: LiquidColor.ambar, fuera: tempFuera,
            icono: .termo,
            a11y: a11ySenal(String(localized: "Skin temperature"), tempVal, fuera: tempFuera, comparando: comparando),
            serie: tempSerie)
        let resp = LiquidGuardianHoja.Senal(
            id: "resp",
            etiqueta: String(localized: "Breathing"),
            valor: respVal, tono: LiquidColor.azul, fuera: respFuera,
            icono: .resp,
            a11y: a11ySenal(String(localized: "Breathing"), respVal, fuera: respFuera, comparando: comparando),
            serie: respSerie)

        let calibracion: LiquidGuardianHoja.Calibracion? = {
            guard estado == .conociendote else { return nil }
            // La barra cuenta lo que de verdad construye la base que falta: noches CON lectura
            // de respiración. Antes contaba noches de temperatura —otra señal, que ni siquiera
            // necesita base— así que podía llenarse del todo sin que el estado cambiara nunca.
            // Acotado a la meta: el criterio de salida del motor (`respJudged`) no es
            // exactamente «noches con lectura», así que el conteo podía pasarse y la barra
            // decía «5 de 4». (Revisión Grok r2 · N2.)
            let necesariasBase = Baselines.minNightsSeed
            let hechas = min(necesariasBase, i.prep.map { p in
                p.sentinelHistory.suffix(necesariasBase).filter { !$0.respMissing }.count
            } ?? 0)
            // El estado sale en cuanto la base de respiración es USABLE, y eso pasa en la
            // semilla del motor, no a las 14 noches. Con 14 la barra se estancaba cerca de
            // 4/14 y nunca llegaba al final: una barra que promete un viaje más largo del que
            // hace. (Revisión Grok H3 · DeepSeek D1.)
            let necesarias = necesariasBase
            let leyenda = String(format: String(localized: "%lld of %lld nights"),
                                 hechas, necesarias)
            return .init(
                titulo: String(localized: "Learning your pattern"),
                leyenda: leyenda,
                hechas: hechas, necesarias: necesarias)
        }()

        return LiquidGuardianHoja(
            // #inject r6 · «Guardian» a secas (decisión del dueño: le gusta más sin artículo).
            titulo: String(localized: "Guardian"),
            explicacion: String(localized: "It watches two signals from your night, your skin temperature and your breathing, against your own pattern from recent weeks. It doesn't vote on your verdict: it only pushes toward a lighter day when both drift out together. An approximation, not a diagnosis."),
            infoMostrar: String(localized: "Show explanation"),
            infoOcultar: String(localized: "Hide explanation"),
            nivel: nivel, sinLectura: sinLectura, conteo: conteo,
            sello: sello, enPatron: enPatron,
            temp: temp, resp: resp,
            pieTarjeta: pieVentana(prep: i.prep),
            nota: nota, notaAvisa: notaAvisa,
            reglaKicker: String(localized: "THE RULE"),
            reglaTexto: String(localized: "A single signal out never pushes your day. Only the pair, two nights in a row."),
            reglaClave: String(localized: "Only the pair, two nights in a row."),
            domino: dominoGuardian(prep: i.prep, estado: estado),
            metodo: .init(
                titulo: String(localized: "How it's calculated"),   // #inject r5 · unifica el pie con la familia (era «How it was obtained»)
                mostrar: String(localized: "Show method"),
                ocultar: String(localized: "Hide method"),
                nota: String(localized: "Both signals are read from your Apple Watch while you sleep and compared against your own pattern from recent weeks, not population tables. An isolated deviation is ignored on purpose: a warm room or an extra blanket can produce it alone."),
                origenEtiqueta: String(localized: "Apple Health"),
                origenSufijo: String(localized: "last night")),
            calibracion: calibracion)
    }

    /// Atajo de compatibilidad: hoja sin series (previews / callers viejos).
    static func guardianHoja(_ guardian: LiquidHoyModel.Guardian?) -> LiquidGuardianHoja {
        guardianHoja(GuardianHojaInputs(guardian: guardian, prep: nil))
    }

    // MARK: Guardián · copy y series (F3)

    private static func copyGuardian(
        estado: LiquidHoyModel.Guardian.Estado,
        guardian: LiquidHoyModel.Guardian?,
        prep: Preparedness.Read?
    ) -> (nivel: String?, sinLectura: String?, conteo: String,
          nota: String?, notaAvisa: Bool, enPatron: Bool) {
        switch estado {
        case .tranquilo:
            return (String(localized: "Inside your pattern"),
                    nil,
                    String(localized: "Your two night signals woke up where they always do."),
                    nil, false, true)
        case .tempFuera:
            return (String(localized: "One signal out"),
                    nil,
                    String(localized: "Your temperature woke up outside your pattern; breathing, where it always does."),
                    String(localized: "A single one can be the room, the blanket, or the night. The guardian waits."),
                    false, false)
        case .respFuera:
            return (String(localized: "One signal out"),
                    nil,
                    String(localized: "Your breathing woke up outside your pattern; temperature, where it always does."),
                    String(localized: "A single one can be the room, the blanket, or the night. The guardian waits."),
                    false, false)
        case .juntas:
            let streak = prep?.sentinel?.streakNights ?? 0
            let conteo = streak >= 2
                ? String(localized: "Your two signals woke up outside your pattern, for a second night.")
                : String(localized: "Your two signals woke up outside your pattern together.")
            return (String(localized: "Both out"),
                    nil,
                    conteo,
                    String(localized: "The guardian doesn't diagnose: it only eases your pace."),
                    true, false)
        case .sinLectura:
            return (nil,
                    String(localized: "No reading last night"),
                    String(localized: "With no night recorded, the guardian has nothing to compare against."),
                    String(localized: "Sleep with your Apple Watch and tomorrow it watches again."),
                    false, false)
        case .incompleto:
            // Dos razones distintas, una sola cosa que decir: todavía no hay juicio completo.
            if prep == nil {
                return (nil,
                        String(localized: "Reading your night"),
                        String(localized: "One moment: the guardian is still reading your signals."),
                        nil, false, false)
            }
            return (nil,
                    String(localized: "Only one signal"),
                    String(localized: "Last night only one of your two signals came through. The guardian needs both before it can say anything."),
                    nil, false, false)
        case .conociendote:
            // Misma clave que el héroe calibrando (`hero.title.calibrando` → «Conociéndote»).
            return (nil,
                    String(localized: "hero.title.calibrando", defaultValue: "Getting to know you"),
                    String(localized: "The guardian needs a few nights to learn your pattern."),
                    String(localized: "In the meantime, readings are shown without comparison."),
                    false, false)
        }
    }

    /// `comparando: false` mientras el guardián todavía aprende tu patrón: ahí la hoja dice
    /// «se muestran sin comparación», y VoiceOver no puede rematar cada señal con «en tu
    /// patrón» — quien ve y quien oye recibirían cosas distintas. (Revisión DeepSeek H2.)
    private static func a11ySenal(_ nombre: String, _ valor: String, fuera: Bool,
                                  comparando: Bool = true) -> String {
        let base = "\(nombre), \(valor)"
        if valor == "—" {
            return "\(base), \(String(localized: "no reading"))"
        }
        if !comparando { return base }
        return fuera
            ? "\(base), \(String(localized: "outside your pattern"))"
            : "\(base), \(String(localized: "inside your pattern"))"
    }

    /// El pie de la tarjeta del par: dice cuántas noches hay DE VERDAD detrás de las
    /// mini-gráficas. Estaba fijo en «tus últimas 14 noches» incluso sin serie o con historial
    /// corto, que es afirmar una ventana que no existe. (Revisión Grok r2 · N3.)
    private static func pieVentana(prep: Preparedness.Read?) -> String {
        let n = min(14, prep?.sentinelHistory.count ?? 0)
        guard n > 1 else { return "" }
        return String(format: String(localized: "your last %lld nights"), n)
    }

    /// Sello del héroe: «ANOCHE · 3 AGO». El DS no formatea fechas (contrato D3).
    static func selloAnoche(now: Date, calendar: Calendar, locale: Locale) -> String {
        let anoche = String(localized: "last night").uppercased(with: locale)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        // La noche que vigila es la de anoche (la que alimenta el veredicto de hoy).
        let ref = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let fecha = formatter.string(from: ref).uppercased(with: locale)
        return "\(anoche) · \(fecha)"
    }

    private static func popupFechaFmt(locale: Locale) -> @Sendable (Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return { f.string(from: $0) }
    }

    private static func serieMini(
        puntos: [(fecha: Date, valor: Double)],
        banda: ClosedRange<Double>?,
        sinDatoAnoche: Bool,
        fmtValor: @escaping @Sendable (Double) -> String,
        fmtFecha: @escaping @Sendable (Date) -> String,
        a11y: String,
        vacio: String
    ) -> LiquidGuardianHoja.SerieMini {
        let vals = puntos.map(\.valor)
        let lo: Double
        let hi: Double
        if let b = banda {
            let pad = max(0.2, (b.upperBound - b.lowerBound) * 0.25)
            let dataLo = vals.min() ?? b.lowerBound
            let dataHi = vals.max() ?? b.upperBound
            lo = min(b.lowerBound, dataLo) - pad
            hi = max(b.upperBound, dataHi) + pad
        } else if let vmin = vals.min(), let vmax = vals.max() {
            let pad = max(0.2, (vmax - vmin) * 0.15)
            lo = vmin - pad; hi = vmax + pad
        } else {
            lo = 0; hi = 1
        }
        let dominio = lo...max(hi, lo + 0.1)
        let puntoHoy = puntos.last.map { (fecha: $0.fecha, valor: $0.valor) }
        return .init(
            puntos: puntos, banda: banda, dominio: dominio,
            puntoHoy: puntoHoy, hoyAnillo: sinDatoAnoche,
            a11yLabel: a11y,
            formatoValor: fmtValor, formatoFecha: fmtFecha, vacio: vacio)
    }

    /// Dominó alimentado SOLO de `Preparedness.Read.sentinelHistory` (FER-33 · F1).
    /// Prohibido recalcular cortes del centinela en la capa app.
    private static func dominoGuardian(
        prep: Preparedness.Read?,
        estado: LiquidHoyModel.Guardian.Estado
    ) -> LiquidGuardianHoja.Domino {
        let hist = Array((prep?.sentinelHistory ?? []).suffix(5))
        // Rellenar a 5 por la izquierda con .sinDato si el historial es más corto.
        let pad = max(0, 5 - hist.count)
        let tempPts: [LiquidDominoRegla.Punto] =
            Array(repeating: .sinDato, count: pad) + hist.map(puntoTemp)
        let respPts: [LiquidDominoRegla.Punto] =
            Array(repeating: .sinDato, count: pad) + hist.map(puntoResp)

        // Cerco solo en «juntas» con racha ≥ 2, y NUNCA a través de un hueco de calendario.
        let streak = prep?.sentinel?.streakNights ?? 0
        let gapEnCerco: Bool = {
            guard hist.count >= 2 else { return false }
            // El cerco abarca las DOS últimas noches, así que lo que puede romperlo es el
            // hueco de la ÚLTIMA contra su anterior: `gapBefore` de la última. Mirar también
            // el de la penúltima apagaba el cerco por un hueco que cae FUERA de él, y el
            // diagrama contradecía al héroe («por segunda noche») en la misma pantalla.
            // (Revisión DeepSeek H1.)
            return hist.last?.gapBefore ?? false
        }()
        let encendida = estado == .juntas && streak >= 2 && !gapEnCerco

        let a11y = a11yDomino(temp: tempPts, resp: respPts, encendida: encendida)
        return .init(
            carriles: [
                .init(id: "temp", icono: .termo, tono: LiquidColor.ambar,
                      noches: tempPts, a11y: String(localized: "Skin temperature")),
                .init(id: "resp", icono: .resp, tono: LiquidColor.azul,
                      noches: respPts, a11y: String(localized: "Breathing")),
            ],
            cercoUltimas: encendida ? 2 : nil,
            etiquetas: [String(localized: "night before last"),
                        String(localized: "last night")],
            consecuencia: String(localized: "lighter day"),
            encendida: encendida,
            a11yLabel: a11y)
    }

    private static func puntoTemp(_ n: Preparedness.SentinelNight) -> LiquidDominoRegla.Punto {
        if n.tempMissing { return .sinDato }
        return n.tempOut ? .fuera : .dentro
    }

    private static func puntoResp(_ n: Preparedness.SentinelNight) -> LiquidDominoRegla.Punto {
        // respOut == false con respJudged == false es «el motor no la pudo juzgar»,
        // NO «está en rango». Pintarla tranquila dibujaría calma donde el motor dijo «no sé».
        if n.respMissing || !n.respJudged { return .sinDato }
        return n.respOut ? .fuera : .dentro
    }

    private static func a11yDomino(temp: [LiquidDominoRegla.Punto],
                                  resp: [LiquidDominoRegla.Punto],
                                  encendida: Bool) -> String {
        func carril(_ nombre: String, _ pts: [LiquidDominoRegla.Punto]) -> String {
            let tail = Array(pts.suffix(2))
            let labels = [String(localized: "night before last"),
                          String(localized: "last night")]
            var bits: [String] = []
            for (p, lab) in zip(tail, labels.suffix(tail.count)) {
                switch p {
                case .fuera: bits.append("\(String(localized: "out")) \(lab)")
                case .dentro: bits.append("\(String(localized: "in pattern")) \(lab)")
                case .sinDato: bits.append("\(String(localized: "no data")) \(lab)")
                }
            }
            return "\(nombre): \(bits.joined(separator: ", "))."
        }
        var parts = [
            carril(String(localized: "Skin temperature"), temp),
            carril(String(localized: "Breathing"), resp),
        ]
        if encendida {
            parts.append(String(localized: "Your day was pushed to a lighter one."))
        }
        return parts.joined(separator: " ")
    }

    /// Los rótulos del Ecosistema (FER-10) desde el catálogo, en caja alta del locale.
    static func rotulos(locale: Locale) -> EcosistemaRotulos {
        EcosistemaRotulos(
            // P4: la luna se llama IGUAL que su sección en la Matriz (era «At rest»
            // arriba y «Resting HR» abajo — nadie conectaba las dos).
            reposo: String(localized: "Resting HR").uppercased(with: locale),
            sueno: String(localized: "Sleep").uppercased(with: locale),
            guardian: String(localized: "Guardian").uppercased(with: locale),
            temperatura: String(localized: "Temperature").uppercased(with: locale),
            respiracion: String(localized: "Breathing").uppercased(with: locale),
            hintSeparar: String(localized: "Tap to separate").uppercased(with: locale),
            hintUnir: String(localized: "Tap to reunite").uppercased(with: locale),
            accionSeparar: String(localized: "Separate the signals"),
            accionUnir: String(localized: "Reunite the signals"),
            abrirReposo: String(localized: "Open at rest"),
            abrirSueno: String(localized: "Open sleep"),
            abrirGuardian: String(localized: "Open the guardian"),
            sinLecturaNoche: String(localized: "No reading last night"),
            sinLecturaHoy: String(localized: "No reading today"),
            guardianSinLecturas: String(localized: "Guardian: no readings today"),
            anuncioVeredicto: String(localized: "Your verdict is in: %@"),
            vigiaEnRango: String(localized: "In range"),
            vigiaFuera: String(localized: "Off your range"))
    }

    // MARK: Kicker + dial

    /// «MIÉ 22 DE JUL» — la fecha del día en el locale del usuario, caja alta, sin coma.
    static func kicker(now: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: now)
            .replacingOccurrences(of: ",", with: "")
            .uppercased(with: locale)
    }

    /// La fecha COMPLETA para VoiceOver («miércoles, 22 de julio de 2026») — la
    /// abreviatura en caja alta del kicker se deletrea mal (revote /inject).
    static func kickerA11y(now: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .full
        return formatter.string(from: now)
    }

    /// La hora local actual como fracción 0–24 para el marcador del dial.
    static func markerHour(now: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    /// El ambiente semántico del día (pedido del dueño /inject): verde = «Dale con todo»,
    /// ámbar = «con un detalle», rojo = «Ándate leve», neutro = sin veredicto nocturno.
    static func ambiente(prep: Preparedness.Read?) -> LiquidAmbiente {
        guard let prep, prep.verdict != .lowSignal, prep.isNightAnchored else { return .neutro }
        switch prep.verdict {
        case .full: return .bien
        case .caution: return .atencion
        case .easy: return .alerta
        case .lowSignal: return .neutro
        }
    }

    // MARK: Héroe (tabla canónica — port literal de `TodayView.heroBlock`)

    static func hero(prep: Preparedness.Read?, nights: Int,
                     healthConnected: Bool = true, verdictPending: Bool = false)
        -> (LiquidHoyModel.Hero, HeroRoute, LiquidHoyModel.Calibracion?) {
        // Todavía calculando (primer pintado): el veredicto solo sale del refresh completo. Decirle
        // «no conozco tu base» a alguien con años de historia es FALSO — y saldría en cada arranque.
        // Preferimos decir la verdad pequeña: lo estamos leyendo.
        if prep == nil, verdictPending {
            return (.demotado(kicker: String(localized: "READINESS"),
                              title: String(localized: "Reading your night…"),
                              subtitle: String(localized: "One moment.")),
                    .autonomic, nil)
        }
        if let prep, prep.verdict != .lowSignal {
            if prep.isNightAnchored {
                return (veredicto(prep.verdict, nights: nights, prep: prep), .autonomic, nil)
            }
            return (lecturaDeDia(prep), .autonomic, nil)
        }
        // Decisión del dueño (sesión /inject 2026-07-22): sin veredicto NO se disfraza el
        // héroe con otro dato. FER-10: con Salud conectada, el estado sin-base es la
        // ACRECIÓN del Ecosistema («Conociéndote · Noche n de m»).
        let heroFallback = suenoFallback(nights: nights,
                                         healthConnected: healthConnected)
        let calibracion: LiquidHoyModel.Calibracion? = healthConnected
            ? {
                let c = calibracionConteo(nights: nights)
                // Solo mientras la base SE FORMA (gate /cso B2): en el tope, el estado es
                // «sin lectura hoy», no acreción con puntos llenos.
                return c.noche < c.total ? .init(noche: c.noche, total: c.total) : nil
            }()
            : nil
        // Sin permiso, la puerta del héroe cambia de promesa: «Conectar Salud» (FER-10,
        // estado 8) — el único camino real es conceder el permiso.
        return (heroFallback, healthConnected ? .autonomic : .salud, calibracion)
    }

    /// Renglones 1 (full/caution/easy con noche): la palabra-veredicto con su tono.
    /// Pasada UX H8: con veredicto ámbar el subtítulo repetía el titular («Bien, con un
    /// detalle» / «Vas bien, con un detalle a vigilar») y el usuario tenía que escanear los
    /// tres orbes para saber CUÁL está fuera. `prep.drivers` ya lo sabe: se nombra el eje y
    /// su dirección. `nil` = ninguno fuera → el caller usa la frase genérica.
    private static func subtituloDetalle(_ prep: Preparedness.Read?) -> String? {
        // El PAR manda sobre el eje suelto. Con el centinela corroborado, lo que empujó el día
        // son temperatura y respiración JUNTAS — pero el eje térmico también aparece «fuera»
        // por su propio corte, y como es el primero de `drivers` que lo está, el barrido de
        // abajo culpaba a la temperatura SOLA. El héroe quedaba contradiciendo la regla que la
        // hoja del guardián enseña dos toques más abajo: una señal sola nunca empuja tu día,
        // solo el par. (Revisión adversarial de la auditoría de estados.)
        if prep?.sentinel?.state == .corroborated {
            return String(localized: "Your temperature and breathing moved out of your pattern together.")
        }
        guard let fuera = prep?.drivers.first(where: { $0.state.isOut }) else { return nil }
        switch (fuera.axis, fuera.state) {
        case (.sleep, .low):      return String(localized: "Your sleep came in below your range.")
        case (.sleep, _):         return String(localized: "Your sleep came in above your range.")
        case (.autonomic, .low):  return String(localized: "Your autonomic signal came in below your range.")
        case (.autonomic, _):     return String(localized: "Your autonomic signal came in above your range.")
        case (.thermal, .low):    return String(localized: "Your skin temperature came in below your baseline.")
        case (.thermal, _):       return String(localized: "Your skin temperature came in above your baseline.")
        case (.load, .low):       return String(localized: "Your training load came in below your usual.")
        case (.load, _):          return String(localized: "Your training load came in above your usual.")
        }
    }

    private static func veredicto(_ v: Preparedness.Verdict, nights: Int,
                                  prep: Preparedness.Read? = nil) -> LiquidHoyModel.Hero {
        // El denominador sale del MOTOR, no de la UI: `Baselines.minNightsTrust` es la
        // noche en la que la base deja de encogerse y el veredicto se para completo. Las
        // «21 noches» que decía este tether no existen en `Baselines` — eran un número de
        // pantalla presentado como meta del motor.
        let trust = Baselines.minNightsTrust
        let clamped = min(nights, trust)
        // Con la puerta puesta, el tether baja a línea secundaria y solo aparece mientras
        // la base es JOVEN: con la base firme no hay nada honesto que confesar.
        let confianza = clamped < trust
            ? String(localized: "Confidence: \(clamped) of \(trust) nights")
            : nil
        // Palabras FER-10 («El Ecosistema», aprobadas por el dueño en 6 iteraciones y
        // pasadas por /cso): LECTURAS de tu estado, no órdenes de coach. «En rango» /
        // «Hoy ve leve» / «Recupera» sustituyen a «Dale con todo» / «Bien, con un
        // detalle» / «Ándate leve».
        switch v {
        case .full:
            return .veredicto(
                title: String(localized: "hero.title.full", defaultValue: "In range"),
                highlight: String(localized: "hero.highlight.full", defaultValue: "range"),
                highlightTone: LiquidColor.verdePrimario,
                // FER-1047: el héroe afirma «tus DOS señales» (en reposo · sueño) — el eje autonómico
                // ya no cuenta como tres, y el térmico bajó al guardián que vigila pero no vota.
                // P1 (estudio en frío): el veredicto NOMBRA a sus votantes — los 4
                // perfiles tropezaron con «both of your signals» sin saber cuáles.
                subtitle: String(localized: "hero.sub.full.nombrado",
                                 defaultValue: "Your sleep and your resting heart rate woke up in your range."),
                confianza: confianza)
        case .caution:
            return .veredicto(
                title: String(localized: "hero.title.caution", defaultValue: "Go light today"),
                highlight: String(localized: "hero.highlight.caution", defaultValue: "light"),
                highlightTone: LiquidColor.atencion,
                subtitle: subtituloDetalle(prep) ??
                    String(localized: "You're doing well, with one thing to watch."),
                confianza: confianza)
        case .easy, .lowSignal:
            // lowSignal jamás llega aquí (el if-chain lo manda al estado sin datos).
            // El rojo conserva la decisión D1: habla en NEGATIVO (algo está MUY fuera).
            return .veredicto(
                title: String(localized: "hero.title.easy", defaultValue: "Recover"),
                highlight: String(localized: "hero.highlight.easy", defaultValue: "Recover"),
                highlightTone: LiquidColor.negativo,
                // El rojo también nombra su causa (gate /cso M3): el ámbar ya lo hacía.
                subtitle: subtituloDetalle(prep) ??
                    String(localized: "Your body's asking you to ease off today."),
                confianza: confianza)
        }
    }

    /// Renglón 2 (señales de cuerpo sin noche grabada): «lectura de día» honesta (FER-1033).
    private static func lecturaDeDia(_ prep: Preparedness.Read) -> LiquidHoyModel.Hero {
        let autonomic = prep.drivers.first { $0.axis == .autonomic }?.state
        return .demotado(
            kicker: String(localized: "DAYTIME READ"),
            title: autonomic == .low
                ? String(localized: "Your daytime signals are below your range.")
                : String(localized: "Your daytime signals are in your range."),
            subtitle: String(localized: "No sleep reading last night; this is less precise."))
    }

    /// Renglón 5 (`lowSignal` ∨ `prep == nil`): «aún sin datos suficientes» — SIEMPRE,
    /// haya o no sueño grabado (decisión del dueño: el héroe de sueño de anoche se retiró;
    /// el sueño vive en su tile y su detalle).
    private static func suenoFallback(nights: Int,
                                      healthConnected: Bool) -> LiquidHoyModel.Hero {
        // Sin permiso de Salud, «duerme con tu Watch» es una instrucción imposible: el
        // único camino real es conceder el permiso (revote /inject).
        guard healthConnected else {
            return .demotado(
                kicker: String(localized: "READINESS"),
                title: String(localized: "I don\'t know your baseline yet"),
                subtitle: String(localized: "Connect Apple Health in Settings and your daily verdict will appear here."))
        }
        // FER-10 «Conociéndote»: la calibración habla más bajito (displayS) y su avance es
        // honesto — el denominador sale del MOTOR (`Baselines.minNightsSeed`), no de la UI.
        // Gate /cso B2: con `nights >= total` la base YA está sembrada — este estado llega
        // por «falta la lectura de hoy» o «base rancia», y decir «se está formando» con
        // los puntos llenos sería falso. Ahí el héroe dice la causa real, sin contador.
        let (noche, total) = calibracionConteo(nights: nights)
        guard noche < total else {
            return .demotado(
                kicker: String(localized: "READINESS"),
                title: String(localized: "No reading today"),
                subtitle: String(localized: "Your range is formed; today's reading hasn't arrived yet."))
        }
        return .demotado(
            kicker: String(localized: "READINESS"),
            title: String(localized: "hero.title.calibrando", defaultValue: "Getting to know you"),
            subtitle: String(localized: "Night \(noche) of \(total) · your range is taking shape"))
    }

    /// El conteo honesto de la calibración: noche actual (acotada) de las que el motor
    /// necesita para sembrar la base (`Baselines.minNightsSeed`).
    static func calibracionConteo(nights: Int) -> (noche: Int, total: Int) {
        let total = Baselines.minNightsSeed
        return (min(max(0, nights), total), total)
    }

    // MARK: Señales (port literal de `TodayView.needles()`)

    static func senales(prep: Preparedness.Read?,
                        valores: (rhr: String?, rhrNum: String?, sueno: String?) = (nil, nil, nil))
        -> [LiquidHoyModel.Senal] {
        func driver(_ ax: Preparedness.Axis) -> Preparedness.Driver? {
            prep?.drivers.first { $0.axis == ax }
        }

        var out: [LiquidHoyModel.Senal] = []

        // EN REPOSO (FER-1047) — el eje autonómico vota con UNA sola señal densa: la FC en reposo
        // (`wRHR=1`). La VFC salió del voto: O'Grady 2024 midió SDNN con MAPE 28.88% aun en una
        // lectura corta supina matutina, y el SDNN all-day de Apple es un constructo distinto y
        // peor, así que sale con más razón. La respiración pasó al guardián junto con la temperatura.
        // respiración pasó al guardián junto con la temperatura. Por eso el orbe deja de decir
        // «AUTONÓMICO · 3 SEÑALES» y muestra su DATO honesto — la FC en reposo (p. ej. «52 lpm»).
        // Sin lectura vuelve al patrón normal (icono + «SIN DATOS»).
        let aut = driver(.autonomic)
        let autHasData = aut?.state.hasData ?? false
        let autFuera = aut?.state.isOut ?? false
        out.append(.init(
            id: "autonomico", label: String(localized: "At rest"),
            caption: caption(for: aut?.state),
            progress: autHasData ? positionFromZ(aut?.orientedZ) : nil,
            icon: .ondaSenal,
            state: autFuera ? .atencion : .ok,
            valor: autHasData ? valores.rhr : nil,
            // El badge del estado separado (FER-10): el número grande + su contexto.
            badge: autHasData ? valores.rhrNum.map {
                .init(valor: $0, contexto: autFuera
                      ? String(localized: "bpm · out of your range")
                      : String(localized: "bpm · in your range"))
            } : nil))

        // SUEÑO — posición categórica por estado.
        let sleep = driver(.sleep)
        let sleepHasData = sleep?.state.hasData ?? false
        let sleepFuera = sleep?.state.isOut ?? false
        out.append(.init(
            id: "sueno", label: String(localized: "Sleep"),
            caption: caption(for: sleep?.state),
            progress: sleepHasData ? positionFromState(sleep!.state) : nil,
            icon: .lunaSenal,
            state: sleepFuera ? .atencion : .ok,
            // Simétrico al reposo (Grok #5): sin driver de sueño con dato, NADA de valor —
            // «7:20» junto a «Sin lectura anoche» sería una contradicción de salud.
            valor: sleepHasData ? valores.sueno : nil,
            badge: sleepHasData ? valores.sueno.map {
                .init(valor: $0, contexto: sleepFuera
                      ? String(localized: "h · out of your range")
                      : String(localized: "h · in your range"))
            } : nil))

        // El TÉRMICO ya NO es un orbe: temperatura y respiración viven en la franja del guardián
        // (`guardian(...)`), que vigila pero no vota. «Mostrar no es votar» (FER-1047).
        return out
    }

    /// El guardián (FER-1047 / FER-33 · F3): temp + respiración, SIEMPRE visible en la
    /// columna VIGILANDO. Refleja EXACTAMENTE los cortes del centinela del motor, leídos de
    /// `Preparedness.Read` sin tocar su API: temp fuera ⇔ el driver térmico votó `.high`;
    /// resp fuera ⇔ la z orientada de la respiración cruza `respBadZ`. `.juntas` ⇔ ambas —
    /// el único caso en que el centinela empuja el veredicto. Una sola fuera NO cambia el
    /// veredicto. Nunca dice «enfermedad».
    ///
    /// Estados nuevos (F3, defectos reales corregidos):
    /// - `.sinLectura`: anoche no hubo ninguna de las dos señales — la hoja **no** afirma
    ///   «dentro de tu patrón».
    /// - `.conociendote`: aproximación con `prep.maturity == .calibrating` (madurez de la
    ///   base autonómica, la señal pública más limpia; no hay contador de noches de temp
    ///   expuesto aparte). Reportado en el PR.
    /// - FER-42 · `nightKey` (sin default, a propósito): la noche que la pantalla llama «hoy».
    ///   Todo estado que afirma patrón (`.tranquilo/.tempFuera/.respFuera/.juntas` y el
    ///   `.conociendote` que lee la última noche) exige que la última noche juzgada sea ESA;
    ///   si no coincide (o no hay sello), el guardián vigila en `.incompleto`.
    static func guardian(prep: Preparedness.Read?, thermalDeviation: Double?,
                         resp: Lectura?, nightKey: String?) -> LiquidHoyModel.Guardian? {
        let tempStr = thermalDeviation.map { String(format: "%+.1f°", $0) } ?? "—"
        let respStr = resp.map { "\(Int($0.value.rounded())) \(String(localized: "rpm"))" } ?? "—"

        // El guardián compara contra TU patrón, y quien lo calcula es el motor: sin `prep` no
        // hay comparación que afirmar. Pasaba en el primer pintado (el veredicto solo sale del
        // refresh completo), y con una lectura de temperatura presente la hoja caía a
        // «Dentro de tu patrón» en verde — el defecto exacto que este épico vino a matar,
        // vivo todavía en el arranque en frío. (Revisión Grok H1 · DeepSeek H3.)
        //
        // Y basta con que FALTE UNA de las dos: la hoja dice «tus dos señales», así que con
        // una en «—» estaba contando algo que no leyó.
        // Tres verdades DISTINTAS que la ronda 1 había colapsado en una sola. Decir «sin
        // lectura anoche» sobre una pantalla que muestra una temperatura es otra mentira,
        // solo que en la dirección contraria. (Revisión DeepSeek r2 · A1/C1.)
        if thermalDeviation == nil && resp == nil {
            // Nada que leer: la única en la que «sin lectura anoche» es cierto.
            let label = String(localized: "Watching")
            let a11y = String(localized: "Guardian: no readings today")
            return .init(label: label, temp: tempStr, resp: respStr,
                         estado: .sinLectura, a11y: a11y)
        }
        if prep == nil || thermalDeviation == nil || resp == nil {
            // Hay lectura, pero el guardián no puede cerrar su juicio: o falta una de las dos
            // señales (su regla necesita el par), o el motor todavía no ha calculado (primer
            // pintado). Se muestran los valores que sí hay, sin afirmar patrón.
            let label = String(localized: "Watching")
            let a11y = "\(tempStr), \(respStr)"
            return .init(label: label, temp: tempStr, resp: respStr,
                         estado: .incompleto, a11y: a11y)
        }

        // FER-42 · Sello de noche: el juicio del centinela es de UNA noche concreta
        // (`sentinelHistory.last`). Si esa noche no es la que esta pantalla llama «hoy»,
        // los valores mostrados (de hoy) y el juicio (de otra noche) serían de noches
        // distintas — pasaba con un `prep` viejo tras medianoche, antes del primer
        // recálculo del día. Sin sello que verificar (nightKey nil) o sin ninguna noche
        // juzgada, mismo trato: vigilar sin afirmar patrón. En el caso feliz cuadra por
        // construcción: `Preparedness.evaluate` exige `ordered.last.day == asOf`.
        guard let nightKey, let ultimaNoche = prep?.sentinelHistory.last,
              ultimaNoche.day == nightKey else {
            let label = String(localized: "Watching")
            let a11y = "\(tempStr), \(respStr)"
            return .init(label: label, temp: tempStr, resp: respStr,
                         estado: .incompleto, a11y: a11y)
        }

        // «Conociéndote»: el guardián solo puede empujar cuando las DOS señales se salen
        // JUNTAS, y la respiración es la única de las dos que necesita una base tuya para
        // poder juzgarse (el corte de temperatura es absoluto). Mientras el motor no pueda
        // juzgarla, el guardián no puede hacer su trabajo — y eso es exactamente lo que hay
        // que decir.
        //
        // Antes esto se decidía con `prep.maturity`, que es la madurez de la base de tu PULSO
        // EN REPOSO: una tercera señal, que el guardián ni siquiera vigila. Podía tapar un
        // «juntas» real (el chequeo retorna antes de calcular las señales) y llenaba una barra
        // que contaba noches de TEMPERATURA mientras el estado lo decidía otra cosa: una barra
        // que podía leer «14 de 14» y seguir diciendo «Conociéndote». (FER-33, gate /qa D3.)
        // (El sello de arriba garantiza `ultimaNoche`; el fallback por madurez que vivía aquí
        // murió con él — sin noche juzgada ya no se llega a este punto.)
        let respSinBase = !ultimaNoche.respJudged && !ultimaNoche.respMissing
        if respSinBase {
            let label = String(localized: "Watching")
            let palabra = String(localized: "hero.title.calibrando",
                                 defaultValue: "Getting to know you")
            let a11y = "\(palabra) \(tempStr), \(respStr)"
            return .init(label: label, temp: tempStr, resp: respStr,
                         estado: .conociendote, a11y: a11y)
        }

        let tempHigh = prep?.drivers.first { $0.axis == .thermal }?.state == .high
        // La respiración se marca con el juicio del MOTOR, no re-derivando el corte aquí: si
        // no la pudo juzgar, «no marcada» no es «en rango». Es la misma regla que ya respeta
        // el dominó, y la que hacía falta para que el héroe no la contradijera. (gate /qa D2.)
        let respHigh = ultimaNoche.respOut

        let estado: LiquidHoyModel.Guardian.Estado
        switch (tempHigh, respHigh) {
        case (true, true):   estado = .juntas
        case (true, false):  estado = .tempFuera
        case (false, true):  estado = .respFuera
        case (false, false): estado = .tranquilo
        }

        // FER-12: la RACHA del centinela enriquece el rótulo cuando ambas llevan >= 2 noches
        // JUNTAS. Número factual; la salience NO crece con N. Gated en `.corroborated`.
        let streak: Int = {
            guard estado == .juntas, let s = prep?.sentinel, s.state == .corroborated else { return 0 }
            return s.streakNights
        }()
        let nightsWord = String(localized: "nights")
        let label: String
        switch estado {
        case .juntas:
            label = streak >= 2 ? "\(String(localized: "Together")) · \(streak) \(nightsWord)"
                                : String(localized: "Together")
        case .tranquilo, .tempFuera, .respFuera, .sinLectura, .conociendote, .incompleto:
            label = String(localized: "Watching")
        }
        let prefijo: String
        if estado == .juntas {
            let base = String(localized: "Your temperature and breathing moved out of your pattern together.")
            prefijo = streak >= 2 ? "\(base) \(streak) \(nightsWord)." : base
        } else {
            prefijo = String(localized: "Watching")
        }
        let a11y = "\(prefijo) \(tempStr), \(respStr)"
        return .init(label: label, temp: tempStr, resp: respStr, estado: estado, a11y: a11y)
    }

    /// Port literal: + (mejor que tu base) → a la derecha, acotado a la banda visible.
    static func positionFromZ(_ z: Double?) -> Double {
        guard let z else { return 0.5 }
        return min(0.94, max(0.06, 0.5 + z / 4))
    }

    /// Port literal: posición categórica del estado.
    static func positionFromState(_ s: Preparedness.AxisState) -> Double {
        switch s {
        case .inRange: return 0.5
        case .low: return 0.2
        case .high: return 0.8
        case .noData: return 0.5
        }
    }

    private static func caption(for state: Preparedness.AxisState?) -> String {
        switch state {
        case .inRange: return String(localized: "In range")
        case .low: return String(localized: "Below your base")
        case .high: return String(localized: "Above your base")
        case .noData, nil: return String(localized: "No data")
        }
    }

    // MARK: Acta del veredicto — «Cómo llegué a esto»
    //
    // La proyección de `Preparedness.Read` a la hoja del acta. PURA y sin re-evaluar nada:
    // lee lo que el motor ya votó. Lo que afirma está verificado contra
    // `Preparedness.swift`:
    //  · el veredicto es un CONTEO de señales fuera (`rawVerdictAt` :286-293), no una suma
    //    ponderada: 0 → full, 1 → caution, ≥2 → easy;
    //  · la carga NUNCA entra a ese conteo (`loadAxis` :189-193) — por eso baja a nota;
    //  · la histéresis de 2 días (:300-312) hace que el veredicto MOSTRADO pueda no ser la
    //    lectura de hoy — por eso el aviso existe y es obligatorio;
    //  · el empujón de tendencia solo aplica caution → easy (:214) — es OTRA causa que la
    //    histéresis, así que tienen precedencia explícita.
    //
    // Lo que la hoja NO dice, porque `Read` no lo carga: el z por señal. Y lo que no dice
    // POR DECISIÓN: los pesos 0.35/0.40/0.25 y los cortes (±0.8 °C, <6 h) — knobs sin firmar
    // por `/cso` y, además, la allow-list de esta superficie (docs/ANALYTICS.md) prohíbe
    // publicar números aquí. La columna «contra qué base» es cualitativa: sigue enseñando el
    // hallazgo real (las tres señales NO se juzgan contra la misma referencia) sin publicar
    // un solo umbral.

    /// Las tres señales del acta, SIEMPRE en este orden — el mismo de los orbes de Hoy.
    // FER-1047: el acta explica las DOS señales que votan (en reposo · sueño). El térmico dejó de
    // ser una fila: temp + respiración viven en la franja del guardián («vigila pero no vota», salvo
    // cuando ambas se salen juntas — eso lo cuenta el centinela, no una fila del acta).
    private static let ejesActa: [Preparedness.Axis] = [.autonomic, .sleep]

    /// El tono del veredicto: los MISMOS que usa el héroe. Sin veredicto → tinta/500, y
    /// entonces la hoja no tiene una sola gota de color. `isNightAnchored` es OBLIGATORIO
    /// (mismo gate que `hayVeredicto` en `acta()`): sin noche grabada el acta lee «Aún sin
    /// veredicto», así que teñirla del color del veredicto abriría una hoja verde que se
    /// contradice con su propio texto.
    static func actaTono(_ prep: Preparedness.Read?) -> Color {
        guard let prep, prep.isNightAnchored else { return LiquidColor.tinta500 }
        switch prep.verdict {
        case .full: return LiquidColor.verdePrimario
        case .caution: return LiquidColor.atencion
        case .easy: return LiquidColor.negativo
        case .lowSignal: return LiquidColor.tinta500
        }
    }

    static func acta(prep: Preparedness.Read?, healthConnected: Bool = true) -> LiquidActa {
        // La boleta se SINTETIZA con sus dos votantes fijos, no se itera sobre `drivers`:
        // en el `lowSignal` por falta de fila de hoy, `Preparedness` devuelve `drivers`
        // VACÍO (:163-166) y una tabla derivada de ahí no existiría.
        let estados = ejesActa.map { ax in
            prep?.drivers.first { $0.axis == ax }?.state ?? .noData
        }
        let fuera = estados.filter { $0.isOut }.count
        // D1 del verificador: `isNightAnchored` es OBLIGATORIO (ver historial).
        let hayVeredicto = prep != nil && prep?.verdict != .lowSignal
            && prep?.isNightAnchored == true
        let esLecturaDeDia = prep != nil && prep?.verdict != .lowSignal
            && prep?.isNightAnchored == false
        let calibrando = prep?.maturity == .calibrating

        let desfase = hayVeredicto
            && desfaseDeHisteresis(verdict: prep!.verdict, fuera: fuera)
        let empujeTendencia = hayVeredicto && prep!.verdict == .easy && fuera == 1
            && prep!.trend == .below

        let filas: [LiquidActa.Fila] = ejesActa.enumerated().map { i, ax in
            filaBoleta(ax: ax, estado: estados[i], prep: prep,
                       hayVeredicto: hayVeredicto, esLecturaDeDia: esLecturaDeDia,
                       calibrando: calibrando, healthConnected: healthConnected)
        }

        let resumen = resumenBoleta(prep: prep, estados: estados, fuera: fuera,
                                    hayVeredicto: hayVeredicto,
                                    esLecturaDeDia: esLecturaDeDia,
                                    calibrando: calibrando,
                                    desfase: desfase, empujeTendencia: empujeTendencia,
                                    healthConnected: healthConnected)

        return LiquidActa(
            titulo: String(localized: "Readiness"),
            // Procedencia SIN fecha (revisión del dueño): la fecha del día ya vive en el
            // encabezado de Hoy; repetirla aquí confundía. Reusa la key ya traducida.
            procedencia: String(localized: "Apple Health · this morning"),
            // El ⓘ dice QUÉ es (una línea) — el hedge «aproximación» vive SOLO en «Cómo se
            // calcula» para no repetir (revisión del dueño: el ⓘ y el método decían casi lo
            // mismo).
            explicacion: String(localized: "The verdict for how you woke up: your signals against your own baseline."),
            infoMostrar: String(localized: "Show explanation"),
            infoOcultar: String(localized: "Hide explanation"),
            nivel: palabraBoleta(prep: prep, hayVeredicto: hayVeredicto,
                                 esLecturaDeDia: esLecturaDeDia, calibrando: calibrando,
                                 healthConnected: healthConnected),
            conteo: resumen.texto, conteoClave: resumen.clave,
            filas: filas,
            // Vigilantes SOLO con veredicto (/ux D7): su drama vive en el guardián.
            vigilantesLabel: hayVeredicto ? String(localized: "Watching, not voting") : nil,
            vigilantes: hayVeredicto
                ? [String(localized: "Breathing"), String(localized: "Temperature")] : [],
            vigilantesA11y: hayVeredicto
                ? String(localized: "Watching, not voting: breathing and temperature.") : nil,
            notas: notasBoleta(prep: prep, fuera: fuera, hayVeredicto: hayVeredicto,
                               esLecturaDeDia: esLecturaDeDia, desfase: desfase,
                               empujeTendencia: empujeTendencia,
                               healthConnected: healthConnected),
            confianza: confianzaActa(prep: prep),
            plegable: plegableActa(prep: prep),
            verMas: String(localized: "See more in Trends"),
            verMasHint: String(localized: "Opens the detail"),
            tono: actaTono(prep))
    }

    /// La palabra grande de la boleta: la del héroe con veredicto (paridad /cso B1) o la
    /// del estado sin veredicto — nunca nil.
    private static func palabraBoleta(prep: Preparedness.Read?, hayVeredicto: Bool,
                                      esLecturaDeDia: Bool, calibrando: Bool,
                                      healthConnected: Bool) -> String {
        if hayVeredicto { return palabraVeredicto(prep!.verdict) }
        if esLecturaDeDia { return String(localized: "Day reading") }
        if !healthConnected || prep == nil { return String(localized: "No reading") }
        if calibrando {
            return String(localized: "hero.title.calibrando", defaultValue: "Getting to know you")
        }
        return String(localized: "No reading")
    }

    /// Un votante de la boleta: glifo + sub + voto direccional + palabra + a11y.
    private static func filaBoleta(ax: Preparedness.Axis,
                                   estado: Preparedness.AxisState,
                                   prep: Preparedness.Read?,
                                   hayVeredicto: Bool, esLecturaDeDia: Bool,
                                   calibrando: Bool, healthConnected: Bool) -> LiquidActa.Fila {
        let esAuto = ax == .autonomic
        let glifo: LiquidIcon.Glyph = esAuto ? .corazon : .luna

        let votoEstado: LiquidVotoRiel.Estado
        switch estado {
        case .inRange: votoEstado = .dentro
        case .low:     votoEstado = .fueraAbajo
        case .high:    votoEstado = .fueraArriba
        case .noData:  votoEstado = (esAuto && calibrando && prep != nil) ? .calibrando : .sinLectura
        }

        let sub: String
        if esAuto {
            // El sub ESPECIFICA el tipo de FC (revisión del dueño): «de la noche» deja claro
            // que es la FC en reposo derivada de la noche, no un promedio. El detalle completo
            // (Apple Watch / fallback) vive en «Cómo se calcula».
            sub = votoEstado == .calibrando
                ? String(localized: "learning your base")
                : String(localized: "acta.sub.fc", defaultValue: "overnight · against your base")
        } else {
            // FER-44 (gate /cso): el sueño se juzga contra el rango RECOMENDADO de salud
            // (piso poblacional ~7h, Hirshkowitz 2015), NO contra base personal — usar base
            // personal de sueño-logrado normalizaría la privación crónica (Van Dongen 2003).
            // El copy lo dice como GUÍA, no como «mínimo» arbitrario de la app.
            sub = estado.hasData
                ? String(localized: "last night · vs. the recommended range")
                : String(localized: "vs. the recommended range")
        }

        let palabra: String
        switch votoEstado {
        case .dentro:                  palabra = String(localized: "acta.voto.in", defaultValue: "in")
        case .fueraAbajo, .fueraArriba: palabra = String(localized: "acta.voto.out", defaultValue: "out")
        case .calibrando:              palabra = "··"
        case .sinLectura:              palabra = String(localized: "no data")
        }

        // El tono del VOTO: verde dentro y el tono del desvío fuera — SOLO con veredicto.
        // Sin quórum la hoja entera habla en tinta (cero color, /ux D6): un eje fuera en
        // «Lectura de día»/lowSignal se DIBUJA fuera de banda, pero en tinta y sin wash
        // (revisión adversarial Grok r1, HIGH 2).
        let tonoVoto: Color
        if !hayVeredicto {
            tonoVoto = LiquidColor.tinta500
        } else if estado.isOut {
            tonoVoto = (prep?.verdict == .easy) ? LiquidColor.negativo : LiquidColor.atencion
        } else if votoEstado == .dentro {
            tonoVoto = LiquidColor.verdePrimario
        } else {
            tonoVoto = LiquidColor.tinta500
        }

        let nombre = nombreEje(ax)
        // El verbo del label distingue VOTAR de LEER: sin quórum NADIE «votó» — se leyó
        // (/ux D6; revisión adversarial Grok r1, HIGH 3: el label afirmaba un voto en
        // estados sin veredicto).
        let a11y: String
        switch votoEstado {
        case .dentro:
            a11y = hayVeredicto
                ? String(localized: "\(nombre), voted inside, \(sub).")
                : String(localized: "\(nombre), read inside, \(sub).")
        case .fueraAbajo, .fueraArriba:
            a11y = hayVeredicto
                ? String(localized: "\(nombre), voted outside, \(sub), outside your range.")
                : String(localized: "\(nombre), read outside, \(sub), outside your range.")
        case .calibrando:
            a11y = String(localized: "\(nombre), no vote yet, \(sub).")
        case .sinLectura:
            a11y = String(localized: "\(nombre), no data, \(sub).")
        }

        return LiquidActa.Fila(id: ax.rawValue, glifo: glifo, etiqueta: nombre, sub: sub,
                               estado: votoEstado, umbral: esAuto ? .rango : .minimo,
                               // El wash dice «este voto volteó el veredicto»: sin
                               // veredicto no hay wash (Grok r1 HIGH 2).
                               fuera: estado.isOut && hayVeredicto, tonoVoto: tonoVoto,
                               palabra: palabra,
                               // Hue de identidad = el MISMO de la celda de la Matriz (rosa FC ·
                               // indigo Sueño), vía token compartido: si cambia allá, cambia aquí.
                               hueMetrica: esAuto ? LiquidColor.rosa : LiquidColor.indigo,
                               a11y: a11y)
    }

    /// La frase-resumen bajo la palabra — sostiene el veredicto o cuenta el DESFASE de
    /// histéresis (/ux D5: el desfase ES lo que estás viendo, no una nota al pie).
    private static func resumenBoleta(prep: Preparedness.Read?,
                                      estados: [Preparedness.AxisState],
                                      fuera: Int, hayVeredicto: Bool,
                                      esLecturaDeDia: Bool, calibrando: Bool,
                                      desfase: Bool, empujeTendencia: Bool,
                                      healthConnected: Bool) -> (texto: String, clave: String?) {
        guard hayVeredicto else {
            if esLecturaDeDia {
                return (String(localized: "No sleep recorded last night: without its vote there's no quorum for a verdict."), nil)
            }
            if !healthConnected {
                return (String(localized: "Without Apple Health connected there's nothing to count."), nil)
            }
            if prep == nil {
                return (String(localized: "Nothing came in last night: no sleep and no resting signals."), nil)
            }
            if calibrando {
                return (String(localized: "The ballot is taking shape with your first nights."), nil)
            }
            return (String(localized: "Nothing came in last night: no sleep and no resting signals."), nil)
        }
        if empujeTendencia {
            return (String(localized: "One vote fell outside and your night HRV is trending down: that's why today asks for recovery."),
                    String(localized: "acta.resumen.tendencia.clave", defaultValue: "trending down"))
        }
        if desfase {
            let esperado: Int = prep!.verdict == .full ? 0 : (prep!.verdict == .caution ? 1 : 2)
            if fuera > esperado {
                // El plural importa (revisión DeepSeek r2): con los DOS votos fuera hoy el
                // singular «a vote» mentía la magnitud del desfase.
                let texto = fuera >= 2
                    ? String(localized: "Both votes fell outside today. A new verdict has to repeat two days in a row to replace yesterday's.")
                    : String(localized: "A vote fell outside today. A new verdict has to repeat two days in a row to replace yesterday's.")
                return (texto,
                        String(localized: "acta.resumen.hist.fuera.clave", defaultValue: "outside today"))
            }
            return (String(localized: "Your votes fell inside today. The verdict changes once the improvement repeats two days in a row."),
                    String(localized: "acta.resumen.hist.dentro.clave", defaultValue: "inside today"))
        }
        switch prep!.verdict {
        case .full:
            return (String(localized: "Both of your votes fell inside."),
                    String(localized: "acta.resumen.full.clave", defaultValue: "inside"))
        case .caution:
            let suenoFuera = estados.indices.contains(1) && estados[1].isOut
            return suenoFuera
                ? (String(localized: "Sleep voted outside; autonomic, inside."),
                   String(localized: "acta.resumen.caution.clave", defaultValue: "voted outside"))
                : (String(localized: "Autonomic voted outside; sleep, inside."),
                   String(localized: "acta.resumen.caution.clave", defaultValue: "voted outside"))
        case .easy:
            return (String(localized: "Both of your votes fell outside."),
                    String(localized: "acta.resumen.easy.clave", defaultValue: "outside"))
        case .lowSignal:
            return (String(localized: "Nothing came in last night: no sleep and no resting signals."), nil)
        }
    }

    /// Las notas de la boleta. El desfase y la tendencia YA viven en la frase-resumen; la
    /// carga solo aparece cuando HUBO entrenamiento (/ux D8).
    private static func notasBoleta(prep: Preparedness.Read?, fuera: Int,
                                    hayVeredicto: Bool, esLecturaDeDia: Bool,
                                    desfase: Bool, empujeTendencia: Bool,
                                    healthConnected: Bool) -> [LiquidActa.Nota] {
        var out: [LiquidActa.Nota] = []
        guard let prep else {
            if !healthConnected {
                out.append(.init(id: "permiso",
                                 texto: String(localized: "Connect Apple Health in Settings and your daily verdict will appear here."),
                                 avisa: true))
            } else {
                out.append(.init(id: "noche",
                                 texto: String(localized: "Sleep with your Apple Watch and tomorrow the ballot fills itself.")))
            }
            return out
        }

        if esLecturaDeDia || prep.verdict == .lowSignal {
            out.append(.init(id: "noche",
                             texto: String(localized: "Sleep with your Apple Watch and tomorrow the ballot fills itself.")))
            return out
        }

        if hayVeredicto && !desfase && !empujeTendencia {
            if fuera >= 2 {
                out.append(.init(id: "aviso",
                                 texto: String(localized: "Both out at once: today is for recovering, not pushing."),
                                 avisa: true))
            } else if fuera == 1 {
                out.append(.init(id: "voto",
                                 texto: String(localized: "One vote out lightens the day; it doesn't sink it.")))
            }
        }

        // La carga se mide y NUNCA vota — nota solo cuando hubo entrenamiento (/ux D8);
        // la aclaración permanente vive en «Cómo se calcula».
        let huboEntrenamiento = prep.drivers.first { $0.axis == .load }?.state.hasData ?? false
        if huboEntrenamiento {
            out.append(.init(id: "carga",
                             texto: String(localized: "There was a workout today. It's measured, but it doesn't change your verdict yet.")))
        }
        return out
    }

    /// La palabra del veredicto tal cual la dice el héroe (misma clave del catálogo).
    private static func palabraVeredicto(_ v: Preparedness.Verdict) -> String {
        switch v {
        // Paridad héroe↔acta (gate /cso B1): el acta dice EXACTAMENTE la palabra del
        // héroe FER-10 — jamás las retiradas.
        case .full: return String(localized: "hero.title.full", defaultValue: "In range")
        case .caution: return String(localized: "hero.title.caution", defaultValue: "Go light today")
        case .easy: return String(localized: "hero.title.easy", defaultValue: "Recover")
        // `lowSignal` no tiene palabra-veredicto: `hayVeredicto` lo excluye. Mapearlo a
        // «Ándate leve» era una trampa latente (D5 del verificador).
        case .lowSignal: return String(localized: "No verdict yet")
        }
    }

    private static func nombreEje(_ ax: Preparedness.Axis) -> String {
        switch ax {
        // «FC en reposo», no «Autonómico» (revisión del dueño): la fila vota SOLO con la FC
        // en reposo (wRHR=1); «Autonómico» era jerga y un tercer nombre para la misma señal
        // que la celda ya llama «FC en reposo». Reusa la MISMA key que la celda de la Matriz.
        case .autonomic: return String(localized: "Resting HR")
        case .sleep: return String(localized: "Sleep")
        case .thermal: return String(localized: "Thermal")
        case .load: return String(localized: "Load")
        }
    }

    /// ¿El conteo de hoy contradice al veredicto mostrado? (full→0, caution→1, easy→≥2).
    static func desfaseDeHisteresis(verdict: Preparedness.Verdict, fuera: Int) -> Bool {
        switch verdict {
        case .full: return fuera != 0
        case .caution: return fuera != 1
        case .easy: return fuera < 2
        case .lowSignal: return false
        }
    }

    /// La profundidad de la base — con los ÚNICOS denominadores que existen en el motor:
    /// `Baselines.minNightsSeed` (4) desbloquea, `Baselines.minNightsTrust` (14) da confianza
    /// plena. Y `LiquidCalibracionCard` («Calibrando tu base») SOLO mientras de verdad
    /// calibra: con la base ya usable, prosa sin barra de progreso.
    private static func confianzaActa(prep: Preparedness.Read?) -> LiquidActa.Confianza? {
        guard let prep else { return nil }
        let n = prep.autonomicNights
        if prep.maturity == .calibrating {
            let meta = Baselines.minNightsSeed
            return .calibrando(titulo: String(localized: "Calibrating your base"),
                               leyenda: String(localized: "\(min(n, meta)) of \(meta) nights"),
                               hechas: min(n, meta), necesarias: meta)
        }
        let trust = Baselines.minNightsTrust
        guard n < trust else { return nil }
        return .nota(String(localized: "Your verdict stands on \(n) of your own nights; at \(trust) your base is firm."))
    }

    private static func plegableActa(prep: Preparedness.Read?) -> LiquidActa.Metodo {
        // «Cómo se calcula» es el CÓMO (la mecánica); el ⓘ ya dijo el QUÉ. Primera línea:
        // QUÉ tipo de FC es (el dueño pidió especificarlo). Luego: los dos votos separados,
        // la histéresis, y la cita. Se quitó el «lee X de Y señales» (confundía) y el hedge
        // que ya no duplica al ⓘ.
        let lineas: [String] = [
            String(localized: "acta.metodo.fc",
                   defaultValue: "Your resting HR is your lowest pulse of the night, measured by your Apple Watch; when it isn't worn to sleep, Cénit uses Apple Health's resting heart rate."),
            String(localized: "acta.metodo.votos",
                   defaultValue: "Your sleep and your resting HR are read as separate votes, so a bad night doesn't count twice. Your breathing and temperature only watch; they don't vote here."),
            String(localized: "acta.metodo.histeresis",
                   defaultValue: "A new verdict has to repeat two days in a row before it replaces the previous one."),
            String(localized: "acta.metodo.cita",
                   defaultValue: "O'Grady et al., 2024 · Task Force, 1996 · Plews et al., 2013. Approximate, no clinical claim."),
        ]
        return .init(titulo: String(localized: "How it's calculated"),
                     mostrar: String(localized: "Show method"),
                     ocultar: String(localized: "Hide method"),
                     lineas: lineas)
    }

    #if DEBUG
    /// El acta que acompaña al héroe de DEMO de la sesión /inject (el simulador no tiene
    /// HealthKit): el mismo estado «Dale con todo» del ensamble, armado por el MISMO camino
    /// que producción para que lo que se pule sea el render real.
    static var actaEjemplo: LiquidActa {
        acta(prep: Preparedness.Read(
            verdict: .full,
            drivers: [
                .init(axis: .autonomic, state: .inRange, orientedZ: 0.2),
                .init(axis: .sleep, state: .inRange, orientedZ: nil),
                .init(axis: .thermal, state: .inRange, orientedZ: nil),
                .init(axis: .load, state: .inRange, orientedZ: nil),
            ],
            signalsPresent: 3, signalsTotal: 3,
            maturity: .provisional, autonomicNights: 8, trend: nil))
    }
    #endif

    // MARK: Autonómico (el desglose del eje — las 3 señales del compuesto)

    static func autonomicoTono(_ prep: Preparedness.Read?) -> Color {
        guard let st = prep?.drivers.first(where: { $0.axis == .autonomic })?.state else {
            return LiquidColor.tinta500
        }
        switch st {
        case .inRange: return LiquidColor.verdePrimario
        case .low, .high: return LiquidColor.atencion
        case .noData: return LiquidColor.tinta500
        }
    }

    /// La hoja del eje AUTONÓMICO — el desglose de las tres señales que `Preparedness` ya
    /// computó (`Read.signals`). Proyección pura: no decide nada, solo nombra/ordena/formatea
    /// lo que el motor votó. El bit `out` por señal viene del motor (mismo corte del compuesto),
    /// así el builder no adivina umbrales.
    static func autonomico(prep: Preparedness.Read?,
                           healthConnected: Bool = true,
                           locale: Locale = .current) -> LiquidAutonomico {
        let driver = prep?.drivers.first { $0.axis == .autonomic }
        let estado = driver?.state
        let hayBase = estado != nil && estado != .noData
        let enRango = estado == .inRange
        // Las señales llegan del motor YA ordenadas por peso. En v3 SOLO la FC en reposo vota
        // (`wRHR=1`); VFC y respiración se muestran como READ-OUT (`share==0`) — no cargan el voto.
        let signals = prep?.signals ?? []

        // Sin Preparedness (arranque en frío / sin base) la tabla conserva sus 3 filas fijas
        // en «Sin datos» —igual que `acta` sintetiza sus 3 ejes desde `ejesActa`— en vez de
        // una tarjeta de vidrio VACÍA. Orden por peso: FC en reposo ≥ VFC ≥ respiración.
        let filas: [LiquidAutonomico.Senal]
        if signals.isEmpty {
            let sinDato = caption(for: .noData)
            filas = [Preparedness.Signal.rhr, .hrv, .resp].map { sig in
                let etiqueta = nombreSenal(sig)
                return LiquidAutonomico.Senal(id: sig.rawValue, etiqueta: etiqueta, estado: sinDato,
                                              voto: nil, fuera: false, nota: nil,
                                              a11y: "\(etiqueta), \(sinDato)")
            }
        } else {
            // En v3 SOLO la FC en reposo vota (`wRHR=1`); VFC y respiración se muestran como
            // READ-OUT (`share==0`) — no cargan el voto.
            filas = signals.map { s in
                let etiqueta = nombreSenal(s.signal)
                let est = estadoSenal(s)
                let vota = s.share > 0
                // Color solo en el dato que decidió: una señal que no vota nunca se pinta como «fuera».
                let fuera = vota && s.out
                // Columna derecha: para el votante único «100 %» es ruido → muda; si algún día un
                // co-voto denso (RMSSD nocturno) baja su share, se muestra el porcentaje real. La
                // señal que no vota lleva el rótulo «referencia» para explicar por qué no tiñe.
                let voto: String? = vota
                    ? (s.share >= 0.999 ? nil : porcentajeVoto(s.share, locale: locale))
                    : String(localized: "reference")
                let a11yVoto = vota
                    ? (voto.map { String(localized: "\($0) of the vote") } ?? "")
                    : String(localized: "shown for reference, doesn't vote")
                let a11y = [etiqueta, est, a11yVoto]
                    .filter { !$0.isEmpty }.joined(separator: ", ")
                    + (fuera ? ", " + String(localized: "outside your range") : "")
                return LiquidAutonomico.Senal(id: s.signal.rawValue, etiqueta: etiqueta, estado: est,
                                              voto: voto, fuera: fuera, nota: nil, a11y: a11y)
            }
        }

        return LiquidAutonomico(
            titulo: String(localized: "Autonomic"),
            procedencia: String(localized: "Apple Health · this morning"),
            explicacion: String(localized: "Your resting nervous system, read mainly from your resting heart rate against your own base. HRV and breathing are shown too, but they don't carry the vote. An approximation, not a diagnosis."),
            infoMostrar: String(localized: "Show explanation"),
            infoOcultar: String(localized: "Hide explanation"),
            nivel: hayBase ? (enRango ? String(localized: "In range")
                                      : String(localized: "Off your range")) : nil,
            sinLectura: hayBase ? nil : String(localized: "No baseline yet"),
            conteo: conteoAutonomico(hayBase: hayBase, enRango: enRango,
                                     healthConnected: healthConnected),
            metodo: String(localized: "This axis counts as a single vote, so a rough morning can't push your day down more than once."),
            metodoClave: String(localized: "autonomico.metodo.clave", defaultValue: "a single vote"),
            senales: filas,
            plegable: plegableAutonomico(),
            enRango: enRango)
    }

    private static func nombreSenal(_ s: Preparedness.Signal) -> String {
        switch s {
        case .rhr: return String(localized: "Resting heart rate")
        case .hrv: return String(localized: "HRV")
        case .resp: return String(localized: "Breathing")
        }
    }

    /// Qué dijo la señal — dirección CORRECTA por señal (VFC peor = abajo; FC/resp peor = arriba).
    private static func estadoSenal(_ s: Preparedness.SignalRead) -> String {
        guard s.orientedZ != nil else { return String(localized: "No baseline") }
        guard s.out else { return String(localized: "In range") }
        switch s.signal {
        case .hrv: return String(localized: "Below your base")
        case .rhr, .resp: return String(localized: "Above your base")
        }
    }

    /// El voto como porcentaje entero, localizado («40 %»).
    private static func porcentajeVoto(_ share: Double, locale: Locale) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .percent
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: share)) ?? "\(Int((share * 100).rounded())) %"
    }

    private static func conteoAutonomico(hayBase: Bool, enRango: Bool,
                                         healthConnected: Bool) -> String {
        guard hayBase else {
            // La madurez del eje viene de la base de FC en reposo (`priorStates.rhr`), así el
            // cold-start habla de la FC, no de un «eje autonómico» abstracto.
            return healthConnected
                ? String(localized: "I need a few of your own nights to read your resting heart rate.")
                : String(localized: "Connect Apple Health in Settings to read your resting heart rate.")
        }
        // v3: la FC en reposo es el ÚNICO votante del eje, así el estado del eje = el de la FC
        // (`composite == zFC`). Revisar si algún día se cablea el co-voto de RMSSD nocturno (FER-5).
        return enRango
            ? String(localized: "Your resting heart rate woke up in your range.")
            : String(localized: "Your resting heart rate woke up above your base.")
    }

    private static func plegableAutonomico() -> LiquidAutonomico.Metodo {
        .init(titulo: String(localized: "How it's calculated"),
              mostrar: String(localized: "Show method"),
              ocultar: String(localized: "Hide method"),
              lineas: [
                String(localized: "Your resting heart rate against your own base is the vote: Apple's densest, most reliable signal, so it carries this axis on its own."),
                String(localized: "HRV and breathing are shown for context but don't vote here. Apple's all-day HRV is too noisy to trust, and breathing is watched by the sentinel alongside your temperature."),
                String(localized: "Apple's HRV is a daytime average, not a sleep-window reading, so it stays a reference here rather than a vote."),
                String(localized: "O'Grady et al., 2024 · Task Force, 1996 · Plews et al., 2013. Approximate, no clinical claim."),
              ])
    }

    #if DEBUG
    /// El desglose autonómico de DEMO (mismo estado «en rango» del ensamble /inject).
    static var autonomicoEjemplo: LiquidAutonomico {
        autonomico(prep: Preparedness.Read(
            verdict: .full,
            drivers: [.init(axis: .autonomic, state: .inRange, orientedZ: 0.2)],
            signals: [
                .init(signal: .rhr, orientedZ: 0.3, share: 1.0, flaggedAlone: false, out: false),
                .init(signal: .hrv, orientedZ: 0.1, share: 0.0, flaggedAlone: false, out: false),
                .init(signal: .resp, orientedZ: 0.2, share: 0.0, flaggedAlone: false, out: false),
            ],
            signalsPresent: 3, signalsTotal: 3,
            maturity: .provisional, autonomicNights: 8, trend: nil))
    }
    #endif

    // MARK: Carga (mismo mapeo que `TrainingLoadStrip`)

    static func carga(_ trainingLoad: TrainingLoadModel?,
                      locale: Locale = .current) -> LiquidHoyModel.Carga? {
        guard let trainingLoad else { return nil }   // sin sembrar → sin barra (paridad)
        guard let acwr = trainingLoad.acwr, let band = trainingLoad.band else {
            return .calibrando(status: String(localized: "Calibrating")
                .uppercased(with: locale))
        }
        // Escala 0…2; knob clampeado 0.05–0.95 como la franja actual.
        let pos = min(max(acwr / 2, 0.05), 0.95) * 100
        let zone: Int
        switch band {
        case .rampingDown: zone = 0
        case .sweetSpot: zone = 1
        case .buildingFast: zone = 2
        case .spiking: zone = 3
        }
        return .medida(pos: pos, zone: zone,
                       status: band.shortLabel.uppercased(with: locale),
                       ratio: String(format: "%.2f", acwr),
                       razon: acwr,
                       state: band.flag == .good ? .ok : .atencion)
    }

    // MARK: Métricas (mismos 8 vitales, mismo contexto delta)

    /// El contexto delta de un tile (port literal de `TodayView.tileContext`): nil cuando no
    /// hay valor de hoy; «armando» con <4 días de base; deadband → «En tu base»; y el delta
    /// firmado con su valencia por métrica.
    enum Contexto: Equatable {
        case building
        case ready(text: String, tone: LiquidDeltaTone)
    }

    static func contexto(today: Double?, history: [Double], betterHigher: Bool?,
                         deadband: Double, format: (Double) -> String) -> Contexto? {
        guard let t = today else { return nil }
        let valid = history.filter { $0.isFinite }
        guard valid.count >= 4 else { return .building }
        let mean = valid.reduce(0, +) / Double(valid.count)
        let change = t - mean
        if abs(change) <= deadband {
            return .ready(text: String(localized: "At your baseline"), tone: .neutral)
        }
        let up = change > 0
        let tone: LiquidDeltaTone = betterHigher.map { (up == $0) ? .up : .down } ?? .neutral
        let sign = up ? "+" : "\u{2212}"
        return .ready(text: "\(sign)\(format(abs(change))) \(String(localized: "vs your baseline"))",
                      tone: tone)
    }

    private static func deltaLine(_ contexto: Contexto?, placeholder: String? = nil)
        -> (text: String, tone: LiquidDeltaTone) {
        switch contexto {
        case .ready(let text, let tone): return (text, tone)
        case .building: return (String(localized: "No baseline of your own yet"), .neutral)
        case nil: return (placeholder ?? "", .neutral)
        }
    }

    static func metricas(_ i: Inputs) -> [LiquidHoyModel.Metrica] {
        var out: [LiquidHoyModel.Metrica] = []

        // Sueño — day-scoped; más es mejor.
        let sleepDelta = deltaLine(
            contexto(today: i.sleep?.value, history: i.historias.sleep, betterHigher: true,
                     deadband: 5, format: sleepDeltaText),
            placeholder: String(localized: "Tonight"))
        out.append(.init(
            id: "sleep", label: String(localized: "Sleep"),
            value: i.sleep.map { sleepClockText($0.value) } ?? "—",
            delta: sleepDelta.text, deltaTone: sleepDelta.tone,
            tone: i.sleep == nil ? LiquidColor.tinta500 : LiquidColor.indigo, icon: .luna,
            origen: origen(fromApple: i.sleep?.fromApple)))

        // HRV — más alta es mejor.
        let hrvDelta = deltaLine(contexto(today: i.hrv?.value, history: i.historias.hrv,
                                          betterHigher: true, deadband: 1,
                                          format: { "\(Int($0.rounded())) \(String(localized: "ms"))" }))
        out.append(.init(
            id: "hrv", label: String(localized: "HRV"),
            value: i.hrv.map { "\(Int($0.value.rounded()))" } ?? "—",
            unit: String(localized: "ms"),
            delta: hrvDelta.text, deltaTone: hrvDelta.tone,
            tone: i.hrv == nil ? LiquidColor.tinta500 : LiquidColor.cian, icon: .onda,
            origen: origen(fromApple: i.hrv?.fromApple)))

        // FC en reposo — más alta es PEOR.
        let rhrDelta = deltaLine(contexto(today: i.rhr?.value, history: i.historias.rhr,
                                          betterHigher: false, deadband: 1,
                                          format: { "\(Int($0.rounded())) \(String(localized: "bpm"))" }))
        out.append(.init(
            id: "rhr", label: String(localized: "Resting HR"),
            value: i.rhr.map { "\(Int($0.value.rounded()))" } ?? "—",
            unit: String(localized: "bpm"),
            delta: rhrDelta.text, deltaTone: rhrDelta.tone,
            tone: i.rhr == nil ? LiquidColor.tinta500 : LiquidColor.rosa, icon: .corazon,
            origen: origen(fromApple: i.rhr?.fromApple)))

        // Esfuerzo del día — sin valencia (FER-883: estimado Apple → «Day load» + medido).
        let strainDelta = deltaLine(contexto(today: i.strain, history: i.historias.strain,
                                             betterHigher: nil, deadband: 0.3,
                                             format: { String(format: "%.1f", $0) }))
        out.append(.init(
            id: "strain",
            label: i.strainEstimated ? String(localized: "Day load") : String(localized: "Day Strain"),
            value: i.strain.map { String(format: "%.1f", $0) } ?? "—",
            delta: strainDelta.text, deltaTone: strainDelta.tone,
            tone: i.strain == nil ? LiquidColor.tinta500 : LiquidColor.ambar, icon: .llama,
            origen: i.strainEstimated ? .medido : .calculado))

        // Pasos — más es mejor; estimado (FER-663) → «est.» + calculado.
        let stepsDelta = deltaLine(contexto(today: i.steps, history: i.historias.steps,
                                            betterHigher: true, deadband: 100,
                                            format: { StrandFormat.groupedInt($0) }))
        out.append(.init(
            id: "steps", label: String(localized: "Steps"),
            value: i.steps.map { StrandFormat.groupedInt($0) } ?? "—",
            unit: i.stepsEstimated ? String(localized: "est.") : "",
            delta: stepsDelta.text, deltaTone: stepsDelta.tone,
            tone: i.steps == nil ? LiquidColor.tinta500 : LiquidColor.teal, icon: .pasos,
            origen: i.stepsEstimated ? .calculado : .medido))

        // Temperatura de piel — desviación (°C) vs tu base; sin valencia.
        let skinDelta = deltaLine(contexto(today: i.skinTemp?.value, history: i.historias.skinTemp,
                                           betterHigher: nil, deadband: 0.1,
                                           format: { String(format: "%.1f °C", $0) }))
        out.append(.init(
            id: "skintemp", label: String(localized: "Skin temp"),
            value: i.skinTemp.map { String(format: "%+.1f", $0.value) } ?? "—",
            unit: "°C",
            delta: skinDelta.text, deltaTone: skinDelta.tone,
            tone: i.skinTemp == nil ? LiquidColor.tinta500 : LiquidColor.ambar, icon: .termo,
            origen: origen(fromApple: i.skinTemp?.fromApple)))

        // Respiración — sin valencia.
        let respDelta = deltaLine(contexto(today: i.resp?.value, history: i.historias.resp,
                                           betterHigher: nil, deadband: 0.5,
                                           format: { String(format: "%.1f", $0) }))
        out.append(.init(
            id: "resp", label: String(localized: "Respiration"),
            value: i.resp.map { String(format: "%.1f", $0.value) } ?? "—",
            unit: String(localized: "rpm"),
            delta: respDelta.text, deltaTone: respDelta.tone,
            tone: i.resp == nil ? LiquidColor.tinta500 : LiquidColor.azul, icon: .resp,
            origen: origen(fromApple: i.resp?.fromApple)))

        // Estrés — más alto es PEOR; el valor se bandea 0–3 (verde/ámbar/rojo).
        let stressDelta = deltaLine(contexto(today: i.stress, history: i.historias.stress,
                                             betterHigher: false, deadband: 0.1,
                                             format: { String(format: "%.1f", $0) }))
        out.append(.init(
            id: "stress", label: String(localized: "Stress"),
            value: i.stress.map { String(format: "%.1f", $0) } ?? "—",
            unit: i.stress == nil ? "" : "/ 3",
            delta: stressDelta.text, deltaTone: stressDelta.tone,
            tone: i.stress.map(stressTone) ?? LiquidColor.tinta500, icon: .estres,
            origen: .calculado))

        // VoiceOver (pasada UX): la valencia hace audible lo que el color muestra, y el
        // origen viaja como accessibilityValue.
        return out.map { m in
            LiquidHoyModel.Metrica(
                id: m.id, label: m.label, value: m.value, unit: m.unit, delta: m.delta,
                deltaTone: m.deltaTone, tone: m.tone, icon: m.icon, origen: m.origen,
                a11yValencia: valenciaA11y(m.deltaTone),
                a11yOrigen: m.value == "—" ? nil
                    : String(localized: m.origen == .medido
                             ? "Apple Health source" : "computed on your phone"))
        }
    }

    /// La valencia audible de un delta (nil cuando es neutro o no hay lectura).
    private static func valenciaA11y(_ tone: LiquidDeltaTone) -> String? {
        switch tone {
        case .up: return String(localized: "better than your base")
        case .down: return String(localized: "worse than your base")
        case .neutral: return nil
        }
    }

    /// El color del valor de Estrés por banda 0–3 (misma `StressBand` del tile actual),
    /// dicho en los semánticos Liquid: bajo → verde, medio → atención, alto → negativo.
    static func stressTone(_ score: Double) -> Color {
        switch StressBand(score: score) {
        case .low: return LiquidColor.verdePrimario
        case .medium: return LiquidColor.atencion
        case .high: return LiquidColor.negativo
        }
    }

    private static func origen(fromApple: Bool?) -> LiquidOrigen {
        fromApple == true ? .medido : .calculado
    }

    // MARK: Formatters de sueño (fuente única; las copias muertas de TodayViewSupport se borraron · F2)

    /// «7:20» — sueño en formato reloj.
    static func sleepClockText(_ mins: Double) -> String {
        String(format: "%d:%02d", Int(mins) / 60, Int(mins) % 60)
    }

    /// «18m» / «1h 5m» — el delta de sueño en unidades de una letra.
    static func sleepDeltaText(_ minutes: Double) -> String {
        // «1 h 5 min» / «18 min» (revote /inject): unidades SI legibles en es-MX y en.
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }
}
