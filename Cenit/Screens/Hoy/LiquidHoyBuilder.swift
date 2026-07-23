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
    }

    struct Output {
        let model: LiquidHoyModel
        let heroRoute: HeroRoute
    }

    // MARK: Build

    static func build(_ i: Inputs) -> Output {
        let (hero, route) = hero(prep: i.preparedness, sleepMin: i.sleep?.value,
                                 nights: i.preparedness?.autonomicNights ?? 0)
        let model = LiquidHoyModel(
            kicker: kicker(now: i.now, calendar: i.calendar, locale: i.locale),
            dial: .init(night: i.night, sol: i.sol,
                        marker: markerHour(now: i.now, calendar: i.calendar)),
            senales: senales(prep: i.preparedness, thermalDeviation: i.thermalDeviation),
            hero: hero,
            carga: carga(i.trainingLoad),
            metricas: metricas(i),
            heroHint: String(localized: "Opens the detail"),
            ambiente: ambiente(prep: i.preparedness))
        return Output(model: model, heroRoute: route)
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

    static func hero(prep: Preparedness.Read?, sleepMin: Double?, nights: Int)
        -> (LiquidHoyModel.Hero, HeroRoute) {
        if let prep, prep.verdict != .lowSignal {
            if prep.isNightAnchored {
                return (veredicto(prep.verdict, nights: nights), .autonomic)
            }
            return (lecturaDeDia(prep), .autonomic)
        }
        // Decisión del dueño (sesión /inject 2026-07-22): sin veredicto NO se disfraza el
        // héroe con otro dato — los 5 estados canónicos son full/caution/easy · lectura de
        // día · «aún sin datos suficientes». El fallback de sueño de anoche se retiró.
        return (suenoFallback(sleepMin: sleepMin), .autonomic)
    }

    /// Renglones 1 (full/caution/easy con noche): la palabra-veredicto con su tono.
    private static func veredicto(_ v: Preparedness.Verdict, nights: Int) -> LiquidHoyModel.Hero {
        let clamped = min(nights, 21)
        // El tether de confianza vive SOLO aquí (paridad con `SelloConfianzaArco`).
        let confianza = clamped < 21
            ? String(localized: "Confidence: \(clamped) of 21 nights")
            : nil
        switch v {
        case .full:
            return .veredicto(
                title: String(localized: "Go all in"),
                highlight: String(localized: "hero.highlight.full", defaultValue: "all in"),
                highlightTone: LiquidColor.verdePrimario,
                subtitle: String(localized: "You woke up on your baseline."),
                confianza: confianza)
        case .caution:
            return .veredicto(
                title: String(localized: "Good, one thing to watch"),
                highlight: String(localized: "hero.highlight.caution", defaultValue: "one thing"),
                highlightTone: LiquidColor.atencion,
                subtitle: String(localized: "You're doing well, with one thing to watch."),
                confianza: confianza)
        case .easy, .lowSignal:
            // lowSignal jamás llega aquí (el if-chain lo manda al estado sin datos).
            // D1 resuelta por el dueño (/inject): «Ándate leve» habla en ROJO, como la
            // superficie clásica (algo está MUY fuera; el ámbar es para «un detalle»).
            return .veredicto(
                title: String(localized: "Take it easy"),
                highlight: String(localized: "hero.highlight.easy", defaultValue: "easy"),
                highlightTone: LiquidColor.negativo,
                subtitle: String(localized: "Your body's asking you to ease off today."),
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
    private static func suenoFallback(sleepMin: Double?) -> LiquidHoyModel.Hero {
        _ = sleepMin
        return .demotado(
            kicker: String(localized: "READINESS"),
            title: String(localized: "Not enough data yet"),
            subtitle: String(localized: "Sleep with your Apple Watch a few nights and your daily verdict will appear here."))
    }

    // MARK: Señales (port literal de `TodayView.needles()`)

    static func senales(prep: Preparedness.Read?, thermalDeviation: Double?)
        -> [LiquidHoyModel.Senal] {
        func driver(_ ax: Preparedness.Axis) -> Preparedness.Driver? {
            prep?.drivers.first { $0.axis == ax }
        }

        var out: [LiquidHoyModel.Senal] = []

        // AUTONÓMICO — posición desde el z orientado del compuesto.
        let aut = driver(.autonomic)
        out.append(.init(
            id: "autonomico", label: String(localized: "Autonomic"),
            caption: caption(for: aut?.state),
            progress: (aut?.state.hasData ?? false) ? positionFromZ(aut?.orientedZ) : nil,
            icon: .ondaSenal,
            state: (aut?.state.isOut ?? false) ? .atencion : .ok))

        // SUEÑO — posición categórica por estado.
        let sleep = driver(.sleep)
        out.append(.init(
            id: "sueno", label: String(localized: "Sleep"),
            caption: caption(for: sleep?.state),
            progress: (sleep?.state.hasData ?? false) ? positionFromState(sleep!.state) : nil,
            icon: .lunaSenal,
            state: (sleep?.state.isOut ?? false) ? .atencion : .ok))

        // TÉRMICO — la MISMA última desviación que el tile (FER-1043) con el corte del motor.
        // Desviación deliberada vs `needles()`: sin lectura el orbe queda «sin datos» en vez
        // de ocultarse (la zona conserva sus 3 orbes y sus 3 cables).
        if let dev = thermalDeviation {
            let cut = Preparedness.Config.default.thermalOutC
            let state: Preparedness.AxisState = dev >= cut ? .high : (dev <= -cut ? .low : .inRange)
            out.append(.init(
                id: "termico", label: String(localized: "Thermal"),
                caption: caption(for: state),
                progress: positionFromState(state),
                icon: .termoSenal,
                state: state.isOut ? .atencion : .ok))
        } else {
            out.append(.init(
                id: "termico", label: String(localized: "Thermal"),
                caption: caption(for: Preparedness.AxisState.noData),
                progress: nil, icon: .termoSenal, state: .ok))
        }
        return out
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
        case .inRange: return String(localized: "In your range")
        case .low: return String(localized: "Below your base")
        case .high: return String(localized: "Above your base")
        case .noData, nil: return String(localized: "No data")
        }
    }

    // MARK: Carga (mismo mapeo que `TrainingLoadStrip`)

    static func carga(_ trainingLoad: TrainingLoadModel?) -> LiquidHoyModel.Carga? {
        guard let trainingLoad else { return nil }   // sin sembrar → sin barra (paridad)
        guard let acwr = trainingLoad.acwr, let band = trainingLoad.band else {
            return .calibrando(status: String(localized: "Calibrating").uppercased())
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
        return .medida(pos: pos, zone: zone, status: band.shortLabel.uppercased(),
                       ratio: String(format: "%.2f", acwr),
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
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}
