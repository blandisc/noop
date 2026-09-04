#if os(iOS)
import SwiftUI
import StrandTraining

// StrengthDisplay.swift — small display helpers shared by the strength screens (FER-346).
//
// The seed catalog (free-exercise-db) stores names, muscles and equipment as lowercase English data
// (e.g. "chest", "body only") — it's content, not UI chrome, so it's shown title-cased, not localized.
// UI labels/buttons are localized via the string catalog as usual. Weights are stored SI (kg) and
// formatted to the user's unit preference here, so no screen reformats by hand.

enum StrengthDisplay {

    /// Whether to show the Spanish catalog labels — driven by the device language (FER-501). The
    /// catalog is content (not string-catalog chrome), so the screens localize it through here.
    static var localized: Bool { Locale.current.language.languageCode?.identifier == "es" }

    /// Title-case a lowercase catalog token: "anterior deltoid" → "Anterior Deltoid".
    static func titleCase(_ s: String) -> String {
        s.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// An exercise's display name in the device language: Spanish when a translation exists, else
    /// the English catalog name. Custom exercises (no `nameES`) always show what the user typed. (FER-501)
    ///
    /// La inicial se fuerza a mayúscula. El catálogo empaquetado ya viene en Title Case, pero los
    /// ejercicios que entran por importación llegan en minúsculas («dumbbell incline bench press») y se
    /// veían así en la sesión (bug Fer 2026-07-18). Se capitaliza SOLO la primera letra, no cada palabra:
    /// title-case reescribiría lo que el usuario tecleó en un ejercicio propio, y en español además sería
    /// incorrecto («Curl Inclinado Con Mancuernas»).
    static func name(_ e: Exercise) -> String { sentenceCase(e.displayName(localized: localized)) }

    /// Primera letra en mayúscula, el resto intacto. Respeta acrónimos y lo que el usuario escribió.
    static func sentenceCase(_ s: String) -> String {
        guard let f = s.first, f.isLowercase else { return s }
        return f.uppercased() + s.dropFirst()
    }

    /// A muscle key's display label: the Spanish term on a Spanish device, else the title-cased English
    /// key. The KEY itself is never changed — filters and the muscle-fatigue map still join on it. (FER-501)
    static func muscle(_ key: String) -> String {
        (localized ? MuscleVocabulary.es[key] : nil) ?? titleCase(key)
    }

    /// An equipment key's display label, same rule as `muscle`. (FER-501)
    static func equipment(_ key: String) -> String {
        (localized ? EquipmentVocabulary.es[key] : nil) ?? titleCase(key)
    }

    /// A one-line subtitle for an exercise row: "Chest · Barbell" (equipment omitted when absent).
    static func subtitle(_ e: Exercise) -> String {
        let m = e.primaryMuscles.first.map(muscle) ?? ""
        guard let eq = e.equipment, !eq.isEmpty else { return m }
        return m.isEmpty ? equipment(eq) : "\(m) · \(equipment(eq))"
    }

    // MARK: - Record type

    static func typeLabel(_ t: ExerciseType) -> LocalizedStringKey {
        switch t {
        case .weightReps: return "Weight × reps"
        case .bodyweight: return "Bodyweight"
        case .time:       return "Time"
        case .distance:   return "Distance"
        }
    }

    /// The resolved (localized) type label as a plain `String` — for the title overline, where it must
    /// be de-duplicated against the equipment label (FER-739). Mirrors `typeLabel`'s keys.
    static func typeName(_ t: ExerciseType) -> String {
        switch t {
        case .weightReps: return String(localized: "Weight × reps")
        case .bodyweight: return String(localized: "Bodyweight")
        case .time:       return String(localized: "Time")
        case .distance:   return String(localized: "Distance")
        }
    }

    static func typeDetail(_ t: ExerciseType) -> LocalizedStringKey {
        switch t {
        case .weightReps: return "Barbell, dumbbell, machine, cable"
        case .bodyweight: return "Reps, with optional added load"
        case .time:       return "Held or timed (plank, stretch)"
        case .distance:   return "Distance and time (cardio)"
        }
    }

    static func typeIcon(_ t: ExerciseType) -> String {
        switch t {
        case .weightReps: return "dumbbell"
        case .bodyweight: return "figure.strengthtraining.functional"
        case .time:       return "clock"
        case .distance:   return "ruler"
        }
    }

    // MARK: - Weights (stored kg → user's unit)

    /// Formatea un valor YA convertido a la unidad de destino. **La regla de formato vive aquí y solo
    /// aquí** (2026-07-19): en imperial el peso se cuenta entero —82.5 kg son «182 lb», no «181.9»,
    /// que es precisión falsa y además ninguna barra la puede armar—; en métrico, un decimal solo si
    /// no es redondo.
    ///
    /// Existe separada de `weightNumber` porque varias superficies (celdas, discos, ±paso) ya traen el
    /// valor convertido y solo necesitan el formato. Antes cada una traía su propia copia y la de la
    /// sesión activa se quedó con el decimal: la MISMA serie se leía «182 lb» en editar y «181.9 lb»
    /// en la sesión — el mismo número contradiciéndose entre dos pantallas.
    static func displayNumber(_ value: Double, system: UnitSystem) -> String {
        switch system {
        case .imperial: return "\(Int(value.rounded()))"
        case .metric:   return isWhole(value) ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
        }
    }

    /// ¿El número es entero, ignorando el ruido del viaje kg↔lb?
    ///
    /// 5 lb guardadas como kg y convertidas de vuelta dan **4.999999…**, que no es igual a su propio
    /// `rounded()`: sin esto, el paso «±5» se imprimía «±5.0».
    ///
    /// Es una COMPARACIÓN con tolerancia, no una normalización del valor — y esa distinción importa.
    /// El primer intento redondeaba el número a un decimal antes de usarlo, y eso redondea DOS veces:
    /// 100 kg son 220.462 lb, que snapeado da 220.5 y luego sube a **221** cuando lo correcto es 220.
    /// Lo cazó `testImperialRoundsUpAndDownAtTheHalf`. La tolerancia sólo decide el FORMATO; el valor
    /// que se redondea sigue siendo el original. (2026-07-19)
    private static func isWhole(_ v: Double) -> Bool { abs(v - v.rounded()) < 0.005 }

    /// Just the number, in the user's unit, for a big tabular hero ("80", "176"). No decimals on whole
    /// kg; pounds round to whole.
    static func weightNumber(_ kg: Double, system: UnitSystem) -> String {
        displayNumber(system == .imperial ? UnitFormatter.kgToPounds(kg) : kg, system: system)
    }

    /// Un **incremento**, no un peso absoluto — y por eso NO usa la regla de arriba (2026-07-19).
    ///
    /// Redondear a entero es correcto para un peso que se carga en la barra («182 lb»: nadie arma
    /// 181.9). Aplicado a un salto de progresión es falso: un incremento de 2.5 lb —el micro-disco más
    /// común en un gimnasio imperial— se leería «+3 lb», que es 20 % más de lo que la app va a subir de
    /// verdad. El error relativo de redondear crece cuanto más chico es el número, así que un
    /// incremento conserva su decimal en las dos unidades.
    static func incrementNumber(_ kg: Double, system: UnitSystem) -> String {
        let v = system == .imperial ? UnitFormatter.kgToPounds(kg) : kg
        return isWhole(v) ? "\(Int(v.rounded()))" : String(format: "%.1f", v)
    }

    static func weightUnit(_ system: UnitSystem) -> String { UnitFormatter.massUnit(system) }

    /// Number + unit together ("80 kg", "176 lb") for inline summaries.
    static func weight(_ kg: Double, system: UnitSystem) -> String {
        "\(weightNumber(kg, system: system)) \(weightUnit(system))"
    }

    // MARK: - Record dates (FER-360)

    /// The «nuevo» recency window, in whole calendar days: a mark set today through 6 days ago reads
    /// as recent. Shared by `recordDate` below (relative-vs-short cutoff) and «Tus marcas»' own
    /// «nuevo» badge — ONE threshold, not two numbers invented separately.
    static let recordRecentWindowDays = 6

    /// A `PersonalRecord`'s date, shared by the exercise detail's Records rows and «Tus marcas» so
    /// the same PR reads the same date in both places: relative within the recent window («hace 3
    /// días» / «3 days ago» — `Date.FormatStyle`, no catalog key, locale-correct for free), else a
    /// short day + month («14 ago» / «Aug 14»), same format `historyDayText` already uses.
    static func recordDate(_ ts: Int, now: Date = Date(), calendar: Calendar = .current) -> Text {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        if daysAgo <= recordRecentWindowDays {
            return Text(date.formatted(.relative(presentation: .named)))
        }
        return Text(date, format: .dateTime.day().month(.abbreviated))
    }
}
#endif
