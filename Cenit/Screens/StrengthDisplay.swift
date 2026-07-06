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
    static func name(_ e: Exercise) -> String { e.displayName(localized: localized) }

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

    /// Just the number, in the user's unit, for a big tabular hero ("80", "176"). No decimals on whole
    /// kg; pounds round to whole.
    static func weightNumber(_ kg: Double, system: UnitSystem) -> String {
        switch system {
        case .imperial: return "\(Int(UnitFormatter.kgToPounds(kg).rounded()))"
        case .metric:   return kg == kg.rounded() ? "\(Int(kg))" : String(format: "%.1f", kg)
        }
    }

    static func weightUnit(_ system: UnitSystem) -> String { UnitFormatter.massUnit(system) }

    /// Number + unit together ("80 kg", "176 lb") for inline summaries.
    static func weight(_ kg: Double, system: UnitSystem) -> String {
        "\(weightNumber(kg, system: system)) \(weightUnit(system))"
    }
}
#endif
