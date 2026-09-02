import SwiftUI
import CenitDesign
import StrandTraining
import StrandAnalytics

// MARK: - Progression setup (2c, FER-D · FER-293 Liquid Glass · El Eje)
//
// The per-exercise load-progression plan, pushed from the exercise's «···» (and later from the session's
// «por qué» sheet / the detail's «Ciclo actual»). Handoff «Progresión de carga · 2c», with two agreed
// deviations from the mock: the screen SAVES ON BACK like every Instrumento editor (no «OK» button —
// RestEditorScreen's pattern), and the toggle is chrome (LiquidToggleStyle) — color stays on the
// increment and the consequence bar (verde de carga).
//
// Model honesty (vinculante): el «Objetivo de reps» de aquí escribe el PISO (`RoutineSet.reps`) de
// cada serie de trabajo (el llamador es dueño de esa escritura). Desde FER-94 existe además un TECHO
// opcional (`RoutineSet.repsRangeTop`) para prescribir un rango «8-12»; esta pantalla no lo edita
// —su celda de captura es trabajo aparte de FER-124— y la progresión ya lo respeta: sube al tocar el
// techo cuando existe, o el piso cuando no. El incremento sale del inventario de discos
// (`PlateMath.minimumIncrement`, FER-C) salvo override a mano.

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
            VStack(alignment: .leading, spacing: .zero) {
                // FER-198 (Ola 2): cabecera El Eje. FER-293: el resto de la hoja pasa a Liquid.
                EntrenarHojaCabecera(titulo: String(localized: "Raise with the plan"),
                                     subtitulo: String(localized: "Progression"),
                                     tono: .verde, salida: .guardar(String(localized: "Save")), onSalir: saveAndClose)
                Text("Cénit proposes the raise when you earn it. You can always edit the cell in session.")
                    .font(.system(size: LiquidType.lecturaHojaBase))
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, LiquidSpace.s150)

                EntrenarFilaHerramienta(rotulo: String(localized: "Automatic progression"),
                                        divider: false) {
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .toggleStyle(.liquid)
                }
                .padding(.vertical, LiquidSpace.s100)
                .liquidGlass(.pastillaSolida)
                .padding(.top, LiquidSpace.s400)

                consequence.padding(.top, LiquidSpace.bloqueAjuste)

                VStack(spacing: .zero) {
                    fila(rotulo: String(localized: "Rep goal"),
                         nota: String(localized: "applies to all \(workSetCount) work sets")) {
                        SegmentedPillControl(Self.repOptions, selection: $targetReps, theme: theme) { "\($0)" }
                    }
                    fila(rotulo: String(localized: "You raise when"),
                         nota: String(localized: "every set at the goal")) {
                        SegmentedPillControl([1, 2], selection: $sessions, theme: theme) {
                            $0 == 1 ? String(localized: "1 session") : String(localized: "2 in a row")
                        }
                    }
                    incrementRow
                    fila(rotulo: String(localized: "If you stall 3 sessions"),
                         nota: String(localized: "drop ~7.5% and rebuild")) {
                        SegmentedPillControl([DeloadPolicy.propose, .warn], selection: $deload, theme: theme) {
                            $0 == .propose ? String(localized: "Propose") : String(localized: "Warn only")
                        }
                    }
                    // FER-85: el rótulo describe el aplazamiento del veredicto (ámbar + fuera de rango).
                    fila(rotulo: String(localized: "Days that aren't in range"),
                         nota: String(localized: "defers the raise, doesn't cancel it: you take it with one tap in the session"),
                         divider: false) {
                        SegmentedPillControl([false, true], selection: $ignoreRecovery, theme: theme) {
                            $0 ? String(localized: "Ignore") : String(localized: "Defer")
                        }
                    }
                }
                .liquidGlass(.superficieSolida)
                .disabled(!enabled)
                .opacity(enabled ? 1 : CenitOpacity.dim)
                .padding(.top, LiquidSpace.bloqueAjuste)
            }
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.top, LiquidSpace.s300).padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .entrenarHojaFondo(tono: .verde)
        .pantallaFondo()
        .instrumentoTheme(theme)
        // FER-988: deslizar guarda igual que «Guardar» — la convención del editor Instrumento.
        .keepsSwipeBack { saveAndClose(); return false }
    }

    // MARK: Rows

    private func fila<Control: View>(rotulo: String, nota: String, divider: Bool = true,
                                     @ViewBuilder control: () -> Control) -> some View {
        EntrenarFilaHerramienta(rotulo: rotulo, nota: nota, divider: divider, control: control)
    }

    /// The increment: green because it IS the datum. ± steps by the derived minimum; landing back on the
    /// derived value clears the override (subtitle says which mode you're in).
    private var incrementRow: some View {
        fila(rotulo: String(localized: "Increment"),
             nota: incrementOverride == nil
                ? String(localized: "from your plates: the minimum is \(kgText(derivedIncrementKg))")
                : String(localized: "set by hand · your plates make \(kgText(derivedIncrementKg))")) {
            EntrenarStepper(
                valor: "+\(kgText(incrementKg)) kg",
                tono: .verde,
                talla: .fila,
                puedeBajar: incrementKg > derivedIncrementKg + 0.0001,
                puedeSubir: incrementKg < 20 - 0.0001,
                onBajar: { incrementKg = max(derivedIncrementKg, incrementKg - derivedIncrementKg) },
                onSubir: { incrementKg = min(20, incrementKg + derivedIncrementKg) })
        }
    }

    // MARK: Consequence

    /// The concrete outcome of the plan, with the exercise's real numbers — never an abstract promise.
    private var consequence: some View {
        Group {
            if enabled, let kg = currentWeightKg {
                let sessionsPhrase = sessions == 1
                    ? String(localized: "one session")
                    : String(localized: "two sessions in a row")
                let next = kgText(kg + incrementKg)
                LiquidPatternBlock(
                    overline: String(localized: "With this plan"),
                    lineas: ["\(workSetCount)×\(targetReps) with \(kgText(kg)) kg \(sessionsPhrase) → next time you train with \(next)."],
                    tono: LiquidColor.verdeCarga)
            } else if enabled {
                LiquidPatternBlock(
                    overline: String(localized: "With this plan"),
                    lineas: [String(localized: "Log a session of \(exerciseName) and the plan starts counting from its weight.")],
                    tono: LiquidColor.verdeCarga)
            } else {
                LiquidPatternBlock(
                    overline: String(localized: "With this plan"),
                    lineas: [String(localized: "Turn it on and Cénit proposes the raise. Off, you move the weight by hand each session.")],
                    tono: LiquidColor.tinta10)
            }
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
