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

    /// Title-case a lowercase catalog token: "anterior deltoid" → "Anterior Deltoid".
    static func titleCase(_ s: String) -> String {
        s.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// A one-line subtitle for an exercise row: "Chest · Barbell" (equipment omitted when absent).
    static func subtitle(_ e: Exercise) -> String {
        let muscle = e.primaryMuscles.first.map(titleCase) ?? ""
        guard let eq = e.equipment, !eq.isEmpty else { return muscle }
        return muscle.isEmpty ? titleCase(eq) : "\(muscle) · \(titleCase(eq))"
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
