import SwiftUI
import CenitDesign
import StrandTraining
import StrandAnalytics

// MARK: - Progression setup (2c, FER-D · FER-293 Liquid Glass · El Eje)
//
// The per-exercise load-progression plan, pushed from the exercise's «···» (and later from the session's
// «por qué» sheet / the detail's «Ciclo actual»). Handoff «Progresión de carga · 2c», with two agreed
// deviations from the mock: the screen SAVES ON BACK like every editor here (no «OK» button —
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let exerciseName: String
    /// Current working weight (kg) for the consequence copy; nil = no history yet.
    let currentWeightKg: Double?
    /// Number of work sets, for «se aplica a las N series de trabajo» + the consequence copy.
    let workSetCount: Int
    /// The increment derived from the user's inventory (FER-C) when there's no manual override.
    let derivedIncrementKg: Double
    let onBack: () -> Void
    /// Fired on back: (enabled, targetReps, sessions, incrementKg — nil = keep deriving, deload,
    /// ignoreRecovery, useRPE). `useRPE` ola 1 · E5 — el ritmo «según reps en reserva» (D-Q1/D-Q6).
    let onSave: (Bool, Int, Int, Double?, DeloadPolicy, Bool, Bool) -> Void

    @State private var enabled: Bool
    @State private var targetReps: Int
    @State private var sessions: Int
    /// The increment shown/edited, seeded from the override or the derived value.
    @State private var incrementKg: Double
    @State private var deload: DeloadPolicy
    @State private var ignoreRecovery: Bool
    @ScaledMetric(relativeTo: .footnote) private var lectura = LiquidType.lecturaHojaBase
    /// Ola 1 · E5: `RoutineExercise.progressionUseRPE` — el tercer ritmo («Reps en reserva»).
    @State private var useRPE: Bool
    /// Pasada 2 (`ola1-pantallas.html` §3b): siete controles hechos cuatro visibles + estos plegados.
    @State private var ajustesAbiertos = false

    init(exercise: RoutineExercise, exerciseName: String,
         currentWeightKg: Double?, derivedIncrementKg: Double,
         onBack: @escaping () -> Void,
         onSave: @escaping (Bool, Int, Int, Double?, DeloadPolicy, Bool, Bool) -> Void) {
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
        _useRPE = State(initialValue: exercise.progressionUseRPE)
    }

    static let repOptions = [6, 8, 10, 12]

    // MARK: - Ritmo (Pasada 2, ola 1 · E5) — lista con palomita, nunca segmentado (D-Q1/D-Q6,
    // DECISIONS ola 1 §9). Tres opciones, un solo `useRPE` + `sessions` debajo (E4 ya los gobierna).

    enum Ritmo: CaseIterable { case constante, rapido, repsEnReserva }

    /// Rutinas existentes muestran su estado real: 2 sesiones → Constante, 1 → Rápido (sin migración,
    /// `progressionUseRPE` nace en `false`).
    private var ritmo: Ritmo {
        if useRPE { return .repsEnReserva }
        return sessions <= 1 ? .rapido : .constante
    }

    /// Constante = sessions 2, useRPE false · Rápido = sessions 1, useRPE false · Reps en reserva =
    /// useRPE true (`sessions` se conserva — es el umbral del caso no-cómodo, E4 lo sigue usando).
    private func selectRitmo(_ r: Ritmo) {
        switch r {
        case .constante:     useRPE = false; sessions = 2
        case .rapido:        useRPE = false; sessions = 1
        case .repsEnReserva: useRPE = true
        }
    }

    private func ritmoTitulo(_ r: Ritmo) -> String {
        switch r {
        case .constante:     return String(localized: "Steady rhythm")
        case .rapido:        return String(localized: "Fast rhythm")
        case .repsEnReserva: return String(localized: "Reps in reserve rhythm")
        }
    }

    private func ritmoSubtitulo(_ r: Ritmo) -> String {
        switch r {
        case .constante:     return String(localized: "raises after 2 sessions in a row")
        case .rapido:        return String(localized: "raises after 1")
        case .repsEnReserva: return String(localized: "1 if you had 2 to spare · waits if you hit failure")
        }
    }

    private var ritmoSection: some View {
        VStack(alignment: .leading, spacing: .zero) {
            // Sin filete propio: `incrementRow` (la fila de arriba) ya cierra con el suyo — dos
            // filetes pegados se leerían como uno solo, más grueso, sin espacio entre ellos.
            Text("Rhythm")
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
                .padding(.horizontal, LiquidSpace.s400)
                .padding(.top, LiquidSpace.s300)
                .padding(.bottom, LiquidSpace.s100)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Compensa el padding propio de `LiquidListRow` (`LiquidSpace.s100`) para alinear su
            // texto con el resto de las filas de esta tarjeta (`LiquidSpace.s400`) — sin envolver en
            // `LiquidListCard`, que traería SU vidrio (ADN §11.1, no-sheet-glass: esta hoja ya es
            // papel opaco, `.superficieSolida`).
            VStack(spacing: .zero) {
                ForEach(Array(Ritmo.allCases.enumerated()), id: \.offset) { idx, r in
                    LiquidListRow(title: ritmoTitulo(r), subtitle: ritmoSubtitulo(r),
                                  tone: LiquidColor.verdeCarga, seleccionado: ritmo == r,
                                  divider: idx < Ritmo.allCases.count - 1,
                                  action: { selectRitmo(r) })
                }
            }
            .padding(.horizontal, LiquidSpace.s300)
        }
    }

    // MARK: - Ajustes finos (Pasada 2): «Si te estancas» + «Cuando tu cuerpo dice mantén», plegados.

    private var ajustesFinosToggle: some View {
        Button {
            withAnimation(reduceMotion ? LiquidMotion.fundido : LiquidMotion.suave) { ajustesAbiertos.toggle() }
        } label: {
            HStack(spacing: LiquidSpace.s100) {
                Text("Fine-tune")
                CenitIcon.down.image
                    .font(LiquidType.iconSF(size: 11).weight(.semibold))
                    .rotationEffect(.degrees(ajustesAbiertos ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .font(LiquidType.cuerpo)
            .foregroundStyle(LiquidColor.tinta500)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityValue(Text(ajustesAbiertos ? "expanded" : "collapsed"))
    }

    /// Kilograms for display: trailing zeros trimmed, locale decimal separator ("2,5" in es-MX).
    private func kgText(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// nil when the shown increment still matches the derived one — keep deriving from the inventory.
    private var incrementOverride: Double? {
        abs(incrementKg - derivedIncrementKg) < 0.0001 ? nil : incrementKg
    }

    private func saveAndClose() {
        onSave(enabled, targetReps, sessions, incrementOverride, deload, ignoreRecovery, useRPE)
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
                    .font(.system(size: lectura))
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

                // Pasada 2 (`ola1-pantallas.html` §3b, ola 1 · E5): de siete controles del mismo
                // tamaño a cuatro visibles (reps, paso, ritmo) + dos plegados — misma funcionalidad,
                // «Subes cuando» y «Usar reps en reserva» eran la misma pregunta (a qué ritmo).
                VStack(spacing: .zero) {
                    fila(rotulo: String(localized: "Rep goal"),
                         nota: String(localized: "applies to all \(workSetCount) work sets")) {
                        SegmentedPillControl(Self.repOptions, selection: $targetReps) { "\($0)" }
                    }
                    incrementRow
                    ritmoSection
                }
                .liquidGlass(.superficieSolida)
                .disabled(!enabled)
                .opacity(enabled ? 1 : CenitOpacity.dim)
                .padding(.top, LiquidSpace.bloqueAjuste)

                ajustesFinosToggle
                    .padding(.top, LiquidSpace.s300)
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : CenitOpacity.dim)

                if ajustesAbiertos {
                    VStack(spacing: .zero) {
                        fila(rotulo: String(localized: "If you stall 3 sessions"),
                             nota: String(localized: "drop ~7.5% and rebuild")) {
                            SegmentedPillControl([DeloadPolicy.propose, .warn], selection: $deload) {
                                $0 == .propose ? String(localized: "Propose") : String(localized: "Warn only")
                            }
                        }
                        // FER-85: el rótulo describe el aplazamiento del veredicto (ámbar + fuera de
                        // rango). Ola 1 · E5: renombrada de «Días fuera de rango» a lo que de verdad
                        // dice — el veredicto del cuerpo, no un calendario.
                        fila(rotulo: String(localized: "When your body says hold"),
                             nota: String(localized: "defers the raise, doesn't cancel it: you take it with one tap in the session"),
                             divider: false) {
                            SegmentedPillControl([false, true], selection: $ignoreRecovery) {
                                $0 ? String(localized: "Raise anyway") : String(localized: "Wait")
                            }
                        }
                    }
                    .liquidGlass(.superficieSolida)
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : CenitOpacity.dim)
                    .padding(.top, LiquidSpace.s300)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.top, LiquidSpace.s300).padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .entrenarHojaFondo(tono: .verde)
        .pantallaFondo()
        // FER-988: deslizar guarda igual que «Guardar» — la convención del editor.
        .keepsSwipeBack { saveAndClose(); return false }
    }

    // MARK: Rows

    private func fila<Control: View>(rotulo: String, nota: String, divider: Bool = true,
                                     @ViewBuilder control: () -> Control) -> some View {
        EntrenarFilaHerramienta(rotulo: rotulo, nota: nota, divider: divider, control: control)
    }

    /// The increment: green because it IS the datum. ± steps by the derived minimum; landing back on the
    /// derived value clears the override (subtitle says which mode you're in). Ola 1 · E5 (Pasada 2):
    /// rótulo «Paso de carga» — «Incremento» era jerga de motor, no de usuario.
    private var incrementRow: some View {
        fila(rotulo: String(localized: "Load step"),
             nota: incrementOverride == nil
                ? String(localized: "from your plates")
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

    /// «Subes 2.5 kg cuando cumples 8 reps con ritmo constante. Si te estancas tres veces, bajas
    /// 7.5 %.» — Pasada 2 (`ola1-pantallas.html` §3b, ola 1 · E5): la REGLA en una frase, arriba de
    /// todo, en vez de la aritmética de una sesión con el peso de hoy que esta tarjeta mostraba
    /// antes. Real, no un ejemplo vago: reps, paso, ritmo y deload son los controles de abajo — se
    /// recalcula con cada uno.
    private var consequence: some View {
        Group {
            if enabled {
                LiquidPatternBlock(
                    overline: String(localized: "With this plan"),
                    lineas: [resumenPhrase],
                    tono: LiquidColor.verdeCarga)
            } else {
                LiquidPatternBlock(
                    overline: String(localized: "With this plan"),
                    lineas: [String(localized: "Turn it on and Cénit proposes the raise. Off, you move the weight by hand each session.")],
                    tono: LiquidColor.tinta10)
            }
        }
    }

    private var resumenPhrase: String {
        let ritmoWord: String
        switch ritmo {
        case .constante:     ritmoWord = String(localized: "constant")
        case .rapido:        ritmoWord = String(localized: "fast")
        case .repsEnReserva: ritmoWord = String(localized: "reps in reserve")
        }
        let head = String(format: String(localized: "You raise %@ kg when you hit %lld reps with a %@ rhythm."),
                          kgText(incrementKg), targetReps, ritmoWord)
        let tail: String
        if deload == .propose {
            let deloadPercent = kgText(ProgressionMath.deloadFraction * 100)
            tail = String(format: String(localized: "Stall three times and you drop %@%%."), deloadPercent)
        } else {
            tail = String(localized: "Stall three times and Cénit just warns you.")
        }
        return head + " " + tail
    }
}

#if DEBUG
#Preview("Progresión · activada") {
    ProgressionSetupScreen(
        exercise: RoutineExercise(routineId: "rt", exerciseId: "squat", position: 0, targetSets: 4,
                                  targetReps: 8, targetWeightKg: 100,
                                  progressionEnabled: true),
        exerciseName: "Sentadilla",
        currentWeightKg: 100, derivedIncrementKg: 2.5,
        onBack: {}, onSave: { _, _, _, _, _, _, _ in })
}

#Preview("Progresión · apagada") {
    ProgressionSetupScreen(
        exercise: RoutineExercise(routineId: "rt", exerciseId: "curl", position: 0, targetSets: 3,
                                  targetReps: 10),
        exerciseName: "Curl femoral",
        currentWeightKg: nil, derivedIncrementKg: 2.5,
        onBack: {}, onSave: { _, _, _, _, _, _, _ in })
}

/// Ola 1 · E5: la lista con palomita en «Reps en reserva» — la rutina YA trae `progressionUseRPE`
/// encendido (plantilla nueva, D-Q6), así que abre con el tercer renglón seleccionado.
#Preview("Progresión · reps en reserva") {
    ProgressionSetupScreen(
        exercise: RoutineExercise(routineId: "rt", exerciseId: "bench", position: 0, targetSets: 4,
                                  targetReps: 8, targetWeightKg: 60,
                                  progressionEnabled: true, progressionUseRPE: true),
        exerciseName: "Press banca",
        currentWeightKg: 60, derivedIncrementKg: 2.5,
        onBack: {}, onSave: { _, _, _, _, _, _, _ in })
}
#endif
