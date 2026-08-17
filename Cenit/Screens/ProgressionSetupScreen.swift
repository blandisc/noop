import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// MARK: - Progression setup (2c, FER-D)
//
// The per-exercise load-progression plan, pushed from the exercise's «···» (and later from the session's
// «por qué» sheet / the detail's «Ciclo actual»). Handoff «Progresión de carga · 2c», with two agreed
// deviations from the mock: the screen SAVES ON BACK like every Instrumento editor (no «OK» button —
// RestEditorScreen's pattern), and the toggle is the house ink `InstrumentoToggleStyle`, not green
// («color solo en el dato»: the switch is chrome; green stays on the increment and the consequence).
//
// Model honesty (vinculante): there are NO rep ranges — the rep goal IS `RoutineSet.reps`. Picking an
// «Objetivo de reps» here rewrites every work set's reps (the caller owns that write). The increment
// derives from the plate inventory (`PlateMath.minimumIncrement`, FER-C) unless overridden by hand.

struct ProgressionSetupScreen: View {
    let theme: InstrumentoTheme
    let exerciseName: String
    /// Current working weight (kg) for the consequence copy; nil = no history yet.
    let currentWeightKg: Double?
    /// Number of work sets, for «se aplica a las N series de trabajo» + the consequence copy.
    let workSetCount: Int
    /// The increment derived from the user's inventory (FER-C) when there's no manual override.
    let derivedIncrementKg: Double
    let onBack: () -> Void
    /// Fired on back: (enabled, targetReps, sessions, incrementKg — nil = keep deriving, deload, ignoreRecovery).
    let onSave: (Bool, Int, Int, Double?, DeloadPolicy, Bool) -> Void

    @State private var enabled: Bool
    @State private var targetReps: Int
    @State private var sessions: Int
    /// The increment shown/edited, seeded from the override or the derived value.
    @State private var incrementKg: Double
    @State private var deload: DeloadPolicy
    @State private var ignoreRecovery: Bool

    init(theme: InstrumentoTheme, exercise: RoutineExercise, exerciseName: String,
         currentWeightKg: Double?, derivedIncrementKg: Double,
         onBack: @escaping () -> Void,
         onSave: @escaping (Bool, Int, Int, Double?, DeloadPolicy, Bool) -> Void) {
        self.theme = theme
        self.exerciseName = exerciseName
        self.currentWeightKg = currentWeightKg
        self.workSetCount = max(1, exercise.plannedSets.filter { $0.kind == .work }.count)
        self.derivedIncrementKg = derivedIncrementKg
        self.onBack = onBack
        self.onSave = onSave
        _enabled = State(initialValue: exercise.progressionEnabled)
        // Seed the rep goal from the plan's first work set (the goal IS RoutineSet.reps); snap to the
        // segmented options so the control always has a selection.
        let planReps = exercise.plannedSets.first { $0.kind == .work }?.reps ?? 8
        _targetReps = State(initialValue: Self.repOptions.min {
            abs($0 - planReps) < abs($1 - planReps) } ?? 8)
        _sessions = State(initialValue: max(1, min(2, exercise.progressionSessions)))
        _incrementKg = State(initialValue: exercise.progressionIncrementKg ?? derivedIncrementKg)
        _deload = State(initialValue: exercise.progressionDeload)
        _ignoreRecovery = State(initialValue: exercise.progressionIgnoreRecovery)
    }

    static let repOptions = [6, 8, 10, 12]

    /// Kilograms for display: trailing zeros trimmed, locale decimal separator ("2,5" in es-MX).
    private func kgText(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// nil when the shown increment still matches the derived one — keep deriving from the inventory.
    private var incrementOverride: Double? {
        abs(incrementKg - derivedIncrementKg) < 0.0001 ? nil : incrementKg
    }

    private func saveAndClose() {
        onSave(enabled, targetReps, sessions, incrementOverride, deload, ignoreRecovery)
        onBack()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                InstrumentoFlowTitle(overline: Text("Progression"),
                                     Text("Raise with the plan"))
                Text("Cénit proposes the raise when you earn it. You can always edit the cell in session.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                Toggle(isOn: $enabled) {
                    Text("Automatic progression").font(StrandFont.body).foregroundStyle(theme.ink)
                }
                .toggleStyle(.instrumento)
                .padding(.vertical, 9)
                .overlay(alignment: .top) { Divider().overlay(theme.hairline) }
                .overlay(alignment: .bottom) { Divider().overlay(theme.hairline) }
                .padding(.top, 16)

                consequence.padding(.top, 14)

                Group {
                    row(title: Text("Rep goal"),
                        subtitle: Text("applies to all \(workSetCount) work sets")) {
                        SegmentedPillControl(Self.repOptions, selection: $targetReps, theme: theme) { "\($0)" }
                    }
                    row(title: Text("You raise when"),
                        subtitle: Text("every set at the goal")) {
                        SegmentedPillControl([1, 2], selection: $sessions, theme: theme) {
                            $0 == 1 ? String(localized: "1 session") : String(localized: "2 in a row")
                        }
                    }
                    incrementRow
                    row(title: Text("If you stall 3 sessions"),
                        subtitle: Text("drop ~7.5% and rebuild")) {
                        SegmentedPillControl([DeloadPolicy.propose, .warn], selection: $deload, theme: theme) {
                            $0 == .propose ? String(localized: "Propose") : String(localized: "Warn only")
                        }
                    }
                    // FER-85: el rótulo decía «Recuperación baja» porque antes la compuerta era el
                    // score. Ahora la pone el veredicto, y también aplaza los días ámbar, que no son
                    // recuperación baja: el ajuste tiene que describir lo que de verdad hace.
                    row(title: Text("Days that aren't in range"),
                        subtitle: Text("defers the raise, doesn't cancel it: you take it with one tap in the session"),
                        lastRow: true) {
                        SegmentedPillControl([false, true], selection: $ignoreRecovery, theme: theme) {
                            $0 ? String(localized: "Ignore") : String(localized: "Defer")
                        }
                    }
                }
                .disabled(!enabled)
                .opacity(enabled ? 1 : StrandPalette.disabledOpacity)
                .padding(.top, 14)
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, 12).padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .instrumentoTheme(theme)
        // FER-988: deslizar guarda igual que el chevron — la convención del editor Instrumento.
        .keepsSwipeBack { saveAndClose(); return false }
    }

    private var header: some View {
        HStack {
            // Saves on back — the Instrumento editor convention (no «OK»); RestEditorScreen's chevron.
            BackButton(role: .back, theme: theme, action: saveAndClose)
                .padding(.leading, -2)
            Spacer()
        }
    }

    // MARK: Rows

    private func row(title: Text, subtitle: Text, lastRow: Bool = false,
                     @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                title.font(StrandFont.subhead).foregroundStyle(theme.ink)
                subtitle.font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The themed pill wants `maxWidth: .infinity` per segment; cap it so it can't starve the
            // title's width (which collapsed the row labels to 0pt). Title flexes, control is bounded.
            control().frame(maxWidth: 184, alignment: .trailing)
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { if !lastRow { Divider().overlay(theme.hairline) } }
    }

    /// The increment: green because it IS the datum. ± steps by the derived minimum; landing back on the
    /// derived value clears the override (subtitle says which mode you're in).
    private var incrementRow: some View {
        row(title: Text("Increment"),
            subtitle: incrementOverride == nil
                ? Text("from your plates: the minimum is \(kgText(derivedIncrementKg))")
                : Text("set by hand · your plates make \(kgText(derivedIncrementKg))")) {
            HStack(spacing: 10) {
                incrementStep("minus") { incrementKg = max(derivedIncrementKg, incrementKg - derivedIncrementKg) }
                Text("+\(kgText(incrementKg)) kg")
                    .font(InstrumentoType.grotesk(15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(theme.dataRecovery)
                incrementStep("plus") { incrementKg = min(20, incrementKg + derivedIncrementKg) }
            }
        }
    }

    private func incrementStep(_ system: String, _ action: @escaping () -> Void) -> some View {
        StepperButton(system: system, size: 32, shape: .circle,
                      glyph: StrandFont.caption, theme: theme, action: action)
    }

    // MARK: Consequence

    /// The concrete outcome of the plan, with the exercise's real numbers — never an abstract promise.
    private var consequence: some View {
        Group {
            if enabled, let kg = currentWeightKg {
                connectionBlock(
                    Text("With this plan: \(workSetCount)×\(targetReps) with \(kgText(kg)) kg \(sessions == 1 ? String(localized: "one session") : String(localized: "two sessions in a row")) → next time you train with **\(kgText(kg + incrementKg))**."),
                    accented: true)
            } else if enabled {
                connectionBlock(Text("Log a session of \(exerciseName) and the plan starts counting from its weight."),
                                accented: true)
            } else {
                connectionBlock(Text("Turn it on and Cénit proposes the raise. Off, you move the weight by hand each session."),
                                accented: false)
            }
        }
    }

    private func connectionBlock(_ text: Text, accented: Bool) -> some View {
        text.font(StrandFont.caption).foregroundStyle(accented ? theme.ink : theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface.opacity(0.001)) // token-exempt: hit-testing dentro del ScrollView
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                       bottomTrailingRadius: 8, topTrailingRadius: 8)
                    .fill(theme.hairline.opacity(0.55)))   // token-exempt: relleno decorativo de hairline
            .overlay(alignment: .leading) {
                if accented { Rectangle().fill(theme.dataRecovery).frame(width: 2.5) }
            }
    }
}

#if DEBUG
#Preview("Progresión · activada") {
    ProgressionSetupScreen(
        theme: .base,
        exercise: RoutineExercise(routineId: "rt", exerciseId: "squat", position: 0, targetSets: 4,
                                  targetReps: 8, targetWeightKg: 100,
                                  progressionEnabled: true),
        exerciseName: "Sentadilla",
        currentWeightKg: 100, derivedIncrementKg: 2.5,
        onBack: {}, onSave: { _, _, _, _, _, _ in })
}

#Preview("Progresión · apagada") {
    ProgressionSetupScreen(
        theme: .base,
        exercise: RoutineExercise(routineId: "rt", exerciseId: "curl", position: 0, targetSets: 3,
                                  targetReps: 10),
        exerciseName: "Curl femoral",
        currentWeightKg: nil, derivedIncrementKg: 2.5,
        onBack: {}, onSave: { _, _, _, _, _, _ in })
}
#endif
