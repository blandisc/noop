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
        case sleep       // fallback de sueño → detalle de sueño
        case salud       // sin permiso de Salud: la puerta abre el flujo de conexión (FER-10)
    }

    struct Output {
        let model: LiquidHoyModel
        let heroRoute: HeroRoute
    }

    // MARK: Build

    static func build(_ i: Inputs) -> Output {
        let (hero, route, calibracion) = hero(prep: i.preparedness, sleepMin: i.sleep?.value,
                                              nights: i.preparedness?.autonomicNights ?? 0,
                                              healthConnected: i.healthConnected,
                                              verdictPending: i.verdictPending)
        let model = LiquidHoyModel(
            kicker: kicker(now: i.now, calendar: i.calendar, locale: i.locale),
            dial: .init(night: i.night, sol: i.sol,
                        marker: markerHour(now: i.now, calendar: i.calendar)),
            senales: senales(prep: i.preparedness,
                             valores: (rhr: i.rhr.map { "\(Int($0.value.rounded())) \(String(localized: "bpm"))" },
                                       rhrNum: i.rhr.map { "\(Int($0.value.rounded()))" },
                                       sueno: i.sleep.map { sleepClockText($0.value) })),
            hero: hero,
            carga: carga(i.trainingLoad, locale: i.locale),
            metricas: metricas(i),
            guardian: guardian(prep: i.preparedness, thermalDeviation: i.thermalDeviation, resp: i.resp),
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

    /// La hoja del guardián (FER-10, revisión de usuario): contesta «¿qué es VIGILANDO?»
    /// con la regla del centinela — vigila, no vota; solo en pareja empuja. Jamás
    /// «enfermedad».
    static func guardianHoja(_ guardian: LiquidHoyModel.Guardian?) -> LiquidGuardianHoja {
        let estado = guardian?.estado ?? .tranquilo
        let ahora: String
        switch estado {
        case .tranquilo:
            ahora = String(localized: "Right now: inside your pattern.")
        case .tempFuera:
            ahora = String(localized: "Right now: only your temperature is off; your verdict doesn't change.")
        case .respFuera:
            ahora = String(localized: "Right now: only your breathing is off; your verdict doesn't change.")
        case .juntas:
            ahora = String(localized: "Right now: both moved out together, so they pushed today's verdict.")
        }
        return LiquidGuardianHoja(
            kicker: String(localized: "Watching").uppercased(),
            titulo: String(localized: "The guardian"),
            intro: String(localized: "Your nightly skin temperature and breathing, watched against your own pattern."),
            filaTemp: (String(localized: "Temperature"), guardian?.temp ?? "—",
                       estado == .tempFuera || estado == .juntas),
            filaResp: (String(localized: "Breathing"), guardian?.resp ?? "—",
                       estado == .respFuera || estado == .juntas),
            estadoAhora: ahora,
            reglaTitulo: String(localized: "It watches; it doesn't vote."),
            reglaCuerpo: String(localized: "One signal off your pattern never changes your verdict: a warm room or an extra blanket can move it on its own. Only when both move out together does the guardian push your day to a lighter one. It never diagnoses anything."))
    }

    /// Los rótulos del Ecosistema (FER-10) desde el catálogo, en caja alta del locale.
    static func rotulos(locale: Locale) -> EcosistemaRotulos {
        EcosistemaRotulos(
            reposo: String(localized: "At rest").uppercased(with: locale),
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
            anuncioVeredicto: String(localized: "Your verdict is in: %@"))
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

    static func hero(prep: Preparedness.Read?, sleepMin: Double?, nights: Int,
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
        let heroFallback = suenoFallback(sleepMin: sleepMin, nights: nights,
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
                subtitle: String(localized: "Both of your signals woke up in your range."),
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
    /// el sueño vive en su tile y su detalle). El parámetro `sleepMin` queda ignorado y se
    /// limpia de la firma en el cierre de la sesión (quitar parámetros no es inyectable).
    // TODO(/inject cierre): mover este copy al String Catalog (clave EN + es-MX) y limpiar
    // la firma + el caso `.sleep` de HeroRoute.
    private static func suenoFallback(sleepMin: Double?, nights: Int,
                                      healthConnected: Bool) -> LiquidHoyModel.Hero {
        _ = sleepMin
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

    /// La franja del guardián (FER-1047): temp + respiración, SIEMPRE visible bajo la carga.
    /// Refleja EXACTAMENTE los cortes del centinela del motor, leídos de `Preparedness.Read` sin
    /// tocar su API: temp fuera ⇔ el driver térmico votó `.high` (`skinTempDevC ≥ thermalOutC`,
    /// ya con el descuento lúteo del día); resp fuera ⇔ la z orientada de la respiración cruza
    /// `respBadZ`. `.juntas` ⇔ ambas ⇔ `sentinelOut` — el único caso en que el centinela empuja
    /// el veredicto. Una sola fuera NO cambia el veredicto (mata el falso positivo del cuarto
    /// caliente): el diseño enseña esa regla sin explicarla. Nunca dice «enfermedad».
    static func guardian(prep: Preparedness.Read?, thermalDeviation: Double?,
                         resp: Lectura?) -> LiquidHoyModel.Guardian? {
        // Sin ninguna de las dos lecturas no hay nada que vigilar (no se muestra).
        guard thermalDeviation != nil || resp != nil else { return nil }
        let tempHigh = prep?.drivers.first { $0.axis == .thermal }?.state == .high
        let respBadZ = Preparedness.Config.default.respBadZ
        let respHigh = prep?.signals.first { $0.signal == .resp }?.orientedZ
            .map { -$0 >= respBadZ } ?? false

        let estado: LiquidHoyModel.Guardian.Estado
        switch (tempHigh, respHigh) {
        case (true, true):   estado = .juntas
        case (true, false):  estado = .tempFuera
        case (false, true):  estado = .respFuera
        case (false, false): estado = .tranquilo
        }

        let tempStr = thermalDeviation.map { String(format: "%+.1f°", $0) } ?? "—"
        let respStr = resp.map { "\(Int($0.value.rounded())) \(String(localized: "rpm"))" } ?? "—"

        // FER-12: la RACHA del centinela (FER-8) enriquece el rótulo cuando ambas llevan >= 2 noches
        // JUNTAS. Número factual, sin adjetivos de gravedad; la salience NO crece con N (el tinte de la
        // franja es el mismo para 1 o 3 noches — solo se agrega el conteo, DNA «color solo en el dato»).
        // Gated en `.corroborated` del motor (la fuente autoritativa de la racha), no en la derivación
        // visual del estado, así que un desajuste imposible nunca muestra un conteo espurio.
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
        default:
            label = String(localized: "Watching")
        }
        // VoiceOver: honesto, jamás «enfermedad» ni diagnóstico. La frase corroborada solo aparece
        // cuando ambas se salieron JUNTAS (el caso en que sí cuenta); con racha, agrega el conteo.
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
        // El acta se SINTETIZA con sus tres filas fijas, no se itera sobre `drivers`: en el
        // `lowSignal` por falta de fila de hoy, `Preparedness` devuelve `drivers` VACÍO
        // (:163-166), y una tabla derivada de ahí simplemente no existiría.
        let estados = ejesActa.map { ax in
            prep?.drivers.first { $0.axis == ax }?.state ?? .noData
        }
        let fuera = estados.filter { $0.isOut }.count
        let conLectura = estados.filter { $0.hasData }.count
        // D1 del verificador: `isNightAnchored` es OBLIGATORIO. Sin noche grabada el héroe
        // se demota a propósito («Lectura de día», sin palabra) y el acta reinstalaba el
        // «Dale con todo» en grande: el usuario tocaba un héroe que se niega a dar
        // veredicto y aterrizaba en una hoja que se lo gritaba (invariante Preparedness:101).
        let hayVeredicto = prep != nil && prep?.verdict != .lowSignal
            && prep?.isNightAnchored == true
        // «Lectura de día»: hay señal autonómica (verdict != lowSignal) pero NO se grabó sueño
        // anoche (isNightAnchored == false). No hay veredicto —falta la noche—, pero la razón
        // NO es «me faltan tus noches» (la base puede estar madura): es que anoche no hubo
        // sueño. Sin distinguirlo, el conteo grande contradecía a su propia nota y al héroe.
        let esLecturaDeDia = prep != nil && prep?.verdict != .lowSignal
            && prep?.isNightAnchored == false

        let filas: [LiquidActa.Fila] = ejesActa.enumerated().map { i, ax in
            let estado = estados[i]
            let etiqueta = nombreEje(ax)
            let dijo = caption(for: estado)
            let base = baseDeEje(ax)
            // El label de VoiceOver dice el estado FUERA con palabras: el wash de color es
            // la única marca visual de la fila activa, y el color no habla.
            let a11y = [etiqueta, dijo, base].joined(separator: ", ")
                + (estado.isOut ? ", " + String(localized: "outside your range") : "")
            return LiquidActa.Fila(id: ax.rawValue, etiqueta: etiqueta, dijo: dijo,
                                   base: base, fuera: estado.isOut, a11y: a11y)
        }

        return LiquidActa(
            titulo: String(localized: "Readiness"),
            procedencia: String(localized: "Apple Health · this morning"),
            explicacion: String(localized: "The verdict for how you woke up: your signals against your own baseline. It's an approximation, not a diagnosis."),
            infoMostrar: String(localized: "Show explanation"),
            infoOcultar: String(localized: "Hide explanation"),
            nivel: hayVeredicto ? palabraVeredicto(prep!.verdict) : nil,
            sinLectura: hayVeredicto ? nil : String(localized: "No verdict yet"),
            conteo: hayVeredicto
                ? conteoActa(fuera: fuera, conLectura: conLectura)
                : esLecturaDeDia
                    ? String(localized: "No sleep recorded last night, so there's no morning verdict.")
                    : String(localized: "I need a few of your own nights before I can give you a verdict."),
            // El método en LLANO: nada de «ejes» (vocabulario de `Preparedness.Axis`, no del
            // usuario — en Hoy solo ve tres orbes con nombre propio).
            // v3 (hermana de FER-5, firmado /cso): la versión previa decía «tu respiración
            // puede marcar la señal por su cuenta» — cierto en v2 (`respOut` daba veto propio),
            // FALSO en v3: la respiración salió del voto (`wResp=0`) y ahora solo VIGILA en el
            // guardián junto con la temperatura, y ambas deben corroborar (Preparedness:24-25,
            // :513; Mishra 2020). El acta vota por 2 señales separadas (FC en reposo · sueño):
            // votos que no cuentan doble; respiración y temperatura no votan aquí.
            metodo: String(localized: "Your resting heart rate and your sleep are read as separate votes, so one rough night can't count against you twice. Your breathing and temperature only keep watch. They don't vote here."),
            metodoClave: String(localized: "acta.metodo.clave", defaultValue: "only keep watch"),
            filas: filas,
            notas: notasActa(prep: prep, fuera: fuera, conLectura: conLectura,
                             healthConnected: healthConnected),
            confianza: confianzaActa(prep: prep),
            plegable: plegableActa(prep: prep),
            verMas: String(localized: "See more in Trends"),
            verMasHint: String(localized: "Opens the detail"),
            tono: actaTono(prep),
            // El wash de la fila significa «esta es la que se salió». Con la histéresis
            // activa el veredicto puede seguir verde mientras una señal amaneció fuera:
            // pintar esa fila de verde diría lo contrario de lo que pasó.
            tonoFilas: prep?.verdict == .full && fuera > 0
                ? LiquidColor.atencion : actaTono(prep))
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
        case .autonomic: return String(localized: "Autonomic")
        case .sleep: return String(localized: "Sleep")
        case .thermal: return String(localized: "Thermal")
        case .load: return String(localized: "Load")
        }
    }

    /// Contra QUÉ se compara cada señal — cualitativo, nunca el umbral. Es el hallazgo real:
    /// las tres NO se juzgan contra la misma referencia (tu base / una banda fija / la base
    /// que Apple ya calculó).
    private static func baseDeEje(_ ax: Preparedness.Axis) -> String {
        switch ax {
        case .autonomic: return String(localized: "against your base")
        case .sleep: return String(localized: "against a fixed minimum")
        case .thermal: return String(localized: "against Apple's base")
        case .load: return ""
        }
    }

    static func conteoActa(fuera: Int, conLectura: Int) -> String {
        if fuera >= 2 { return String(localized: "Both of your signals woke up outside your range.") }
        if fuera == 1 { return String(localized: "1 of your 2 signals woke up outside your range.") }
        if conLectura < 2 { return String(localized: "Only \(conLectura) of your 2 signals had a reading today.") }
        return String(localized: "Both of your signals woke up in your range.")
    }

    /// Las notas del acta, con PRECEDENCIA explícita entre los dos avisos que cambian la
    /// lectura (sin ella, el caso `easy` + 1 fuera + tendencia abajo pintaba los dos y la
    /// hoja se contradecía).
    private static func notasActa(prep: Preparedness.Read?, fuera: Int, conLectura: Int,
                                  healthConnected: Bool) -> [LiquidActa.Nota] {
        var out: [LiquidActa.Nota] = []
        guard let prep, prep.verdict != .lowSignal else {
            if !healthConnected {
                out.append(.init(id: "permiso",
                                 texto: String(localized: "Connect Apple Health in Settings and your daily verdict will appear here."),
                                 avisa: true))
            }
            return out
        }

        // Sin noche grabada, el sueño no pudo votar (FER-1033, misma frase que el héroe).
        if !prep.isNightAnchored {
            out.append(.init(id: "noche",
                             texto: String(localized: "No sleep reading last night; this is less precise."),
                             avisa: true))
        }

        // 1) Empujón de tendencia — la causa cuando `easy` sale de UNA sola señal fuera.
        if prep.verdict == .easy && fuera == 1 && prep.trend == .below {
            out.append(.init(id: "tendencia",
                             texto: String(localized: "One signal outside your range, and your night-time HRV trend is coming down."),
                             avisa: true))
        } else if desfaseDeHisteresis(verdict: prep.verdict, fuera: fuera) {
            // 2) Histéresis — el acta de HOY no cuadra con el veredicto MOSTRADO.
            out.append(.init(id: "histeresis",
                             texto: String(localized: "Today I read \(fuera) of your signals outside your range; the verdict doesn't change until it repeats two days in a row."),
                             avisa: true))
        }

        // La carga se mide y NUNCA vota: baja a nota, en las dos variantes.
        let huboEntrenamiento = prep.drivers.first { $0.axis == .load }?.state.hasData ?? false
        out.append(.init(id: "carga", texto: huboEntrenamiento
            ? String(localized: "There was a workout today. It's measured, but it doesn't change your verdict yet.")
            : String(localized: "No workout recorded today. Load is measured, but it doesn't change your verdict yet.")))
        return out
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
        var lineas: [String] = []
        if let prep {
            // v3: el eje autonómico LEE las 3 señales en reposo (para el desglose), pero VOTA
            // solo con la FC en reposo (`wRHR=1`); VFC y respiración van de contexto. La línea
            // nombra ambas cosas —cuántas se leyeron y cuál decide— sin implicar que las 3 votan.
            lineas.append(String(localized: "Your autonomic axis reads \(prep.signalsPresent) of \(prep.signalsTotal) resting signals, but votes on just your resting heart rate; HRV and breathing ride along for context."))
        }
        lineas.append(String(localized: "A new verdict has to repeat two days in a row before it replaces the previous one."))
        lineas.append(String(localized: "Apple's HRV is a daytime average, not a sleep-window measurement: this reads your resting signals against your own norm."))
        lineas.append(String(localized: "O'Grady et al., 2024 · Task Force, 1996 · Plews et al., 2013. Approximate, no clinical claim."))
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

    // MARK: Formatters (ports de TodayViewSupport)

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
