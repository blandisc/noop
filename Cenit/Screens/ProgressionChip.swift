import SwiftUI
import StrandDesign
import StrandTraining

/// ↗ +2,5 kg cada 2 — active progression plan chip under an exercise name (RoutineEditor / Builder).
struct ProgressionChip: View {
    let re: RoutineExercise
    let system: UnitSystem
    let theme: InstrumentoTheme
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                StrandIcon.up.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                Text(Self.summary(re, system: system))
                    .font(StrandFont.caption)
            }
            .foregroundStyle(theme.dataRecovery)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// «+2,5 kg cada 2 ✓» — the active plan. Without an explicit increment, just marks the plan as on.
    static func summary(_ re: RoutineExercise, system: UnitSystem) -> String {
        guard let inc = re.progressionIncrementKg else {
            return String(localized: "Progression · on")
        }
        let unit = StrengthDisplay.weightUnit(system).lowercased()
        return "+\(StrengthDisplay.weightNumber(inc, system: system)) \(unit) "
            + String(localized: "every \(re.progressionSessions)") + " ✓"
    }
}

#if DEBUG
#Preview("ProgressionChip") {
    let re = RoutineExercise(
        routineId: "preview",
        exerciseId: "bench",
        position: 0,
        targetSets: 3,
        progressionEnabled: true,
        progressionSessions: 2,
        progressionIncrementKg: 2.5
    )
    ProgressionChip(
        re: re,
        system: .metric,
        theme: .base,
        action: {}
    )
    .padding()
    .background(InstrumentoTheme.base.paper)
}
#endif
