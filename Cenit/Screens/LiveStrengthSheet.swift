#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import StrandTraining
import StrandAnalytics
import WhoopProtocol
import WhoopStore
import Inject   // recarga en caliente (dev-only, inerte en Release)

// Plate weights read cleaner without a trailing «.0» (60, not 60.0) but keep a half-plate decimal (2.5).
private func plateNumber(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v.rounded())) : String(format: "%.1f", v)
}

/// A weight in kilograms formatted for display in the user's unit, e.g. "82.5 kg" / "180 lb".
private func massString(_ kg: Double, units: UnitSystem) -> String {
    let v = units == .imperial ? UnitFormatter.kgToPounds(kg) : kg
    return "\(plateNumber(v)) \(UnitFormatter.massUnit(units))"
}

// MARK: - Guided strength session (FER-347, full-screen since FER-716)
//
// The heart of the strength tracker: the guided, set-by-set execution as ONE continuous logging table
// («Flujo Entrenar v3 · 1j»). No modal «Foco» — the active row edits inline with the custom keypad, a
// time/distance row expands with a compact stopwatch, and the rest slots in as the inline 1k card.
// Finishing renders the 1l receipt in place.
//
// The session lives in `AppModel` (global) and is presented as a `fullScreenCover` at the RootTabView
// shell, so minimizing («‹») or switching tabs never loses it; the floating `SessionPill` re-opens it
// from any tab. No nested NavigationStack (FER-171). Runs fully offline and without HealthKit
// (logging strength is manual).

// MARK: - The guided session sheet

/// The guided strength session, in the light «Instrumento diurno» language. The theme is passed in
/// explicitly (it doesn't cross the `.sheet` boundary — FER-190). The weight is the dominant datum in the
/// effort hue; the table is a detented `.sheet` drawer; rest is a fixed countdown that hosts the plan
/// navigator. The session itself lives in `AppModel`, so dismissing this sheet never ends it.
struct LiveStrengthSheet: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var tabRouter: TabRouter
    @ObservedObject var session: StrengthSessionModel
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    var theme: InstrumentoTheme = .base

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    /// Which runs have their «por qué» raise card expanded (FER-E), by run id.
    @State private var whyRaiseOpen: Set<String> = []
    /// The cell the custom keypad is editing (FER-716) — one at a time, so a single working buffer is
    /// enough. `nil` = no cell active (keypad hidden). Replaces the native keyboard + `@FocusState`.
    @State private var activeCell: CellRef?
    /// The working string of the active cell. Shown while editing; parsed into the model on every change,
    /// so the value persists without an explicit commit. Empty / unparseable keeps the previous value.
    @State private var buffer: String = ""
    /// Whether the user has typed since activating this cell — enables «replace on first keystroke»
    /// (tap a cell showing 60, type 6 → 6, not 606), the expected Hevy-style behavior.
    @State private var bufferTyped: Bool = false
    /// The exercise whose detail sheet is open — set by tapping an exercise's name (FER-538). nil = closed.
    /// Resolving the full `Exercise` (catalog + custom) is deferred to the tap so the session model stays lean.
    @State private var detailExercise: Exercise?
    /// The exercise whose rest editor is open — set by tapping its rest chip (FER-540). nil = closed.
    @State private var restEdit: RestEdit?
    /// Whether the receipt numerals show their final values (FER-716). Starts false so the first
    /// appearance rolls 0 → value; `playReceiptCountUp` flips it (animated only the first time).
    @State private var receiptCountUp = false
    /// The plate calculator (FER-720 · 3a), opened from the keypad's «⛓ discos» for a weight cell. nil = closed.
    @State private var platesTarget: PlatesTarget?
    /// The share-receipt screen (FER-720 · 3c), opened from the 1l receipt. nil = closed.
    @State private var shareReceipt: ShareRef?
    /// The set whose RPE sheet is open (FER-930), tapped from the table's RPE cell. nil = closed.
    @State private var rpeTarget: RPETarget?
    /// The exercise whose note sheet is open (FER-932), tapped from the «✎ Nota» chip. nil = closed.
    @State private var noteTarget: NoteTarget?
    /// This session's prior notes for `noteTarget.exerciseId` (across other sessions), loaded when the
    /// sheet opens — «NOTAS ANTERIORES». nil = still loading / not opened; [] = loaded, honestly empty.
    @State private var noteHistory: [ExerciseNote]?

    /// The empty «Rápido de fuerza» state (FER-762): no routine, no exercises added yet. Its search field
    /// opens `ExerciseLibraryScreen` in ADD mode; the freshness suggestions load once when this state
    /// appears. `nil` = not loaded yet (the `.task` hasn't resolved); `[]` = loaded, honestly no fresh
    /// muscle to suggest — one optional instead of a separate "have I tried yet" flag.
    @State private var showLibraryPicker = false
    /// FER-938: the id of a set just appended via «+ Serie», so its row shows the «COPIADA DE LA N» hint +
    /// dashed border until it's logged (the guard `!set.done` retires the hint the moment it's marked).
    /// Id de la fila recién añadida — solo dispara la háptica ligera del renglón nuevo (r22).
    @State private var addedSetId: String?
    /// r15: la fila «armada» para borrar (long-press) — brinca en su lugar y ofrece «Quitar serie».
    @State private var armedDeleteSetId: String?
    /// FER-936: which exercise's «≡» reorder handle is momentarily emphasised (ember) after picking
    /// «Reordenar» from its menu — a discoverability nudge toward the drag that already reorders.
    @State private var reorderHint: Int?
    /// «Modo mover» (FER-933): every exercise collapses to a compressed row and a `DragGesture` on each
    /// row shows the handoff's «SOLTAR AQUÍ · POSICIÓN N» drop zone. Entered by long-press on any rail row
    /// or the menu's «Reordenar» item; exits via «Listo». A view-layer toggle only — the model is untouched.
    @State private var reorderMode = false
    /// r20 (auditoría UX #6f): las celdas de captura crecen con Dynamic Type intermedio (tope 1.3×
    /// para que la retícula SERIE/KG/REPS/RPE no desborde antes del reflow AX1).
    @ScaledMetric(relativeTo: .body) private var cellDynamicScale: CGFloat = 1
    /// r20: el proxy del ScrollView, capturado al aparecer — «Agregar serie» lo usa para que la
    /// fila nueva no nazca tapada por la barra/teclado.
    @State private var scrollProxy: ScrollViewProxy?
    /// r21 (auditoría UX #5a): el `ei` cuyo «Superserie con el siguiente» robaría al vecino de otra
    /// pareja existente — pide confirmación antes de deshacerla.
    @State private var confirmSupersetSteal: Int?
    /// Canvas pass 2026-07-15 (menú «Progresión»): which exercise's progression mini-sheet is open.
    struct ProgressionEditTarget: Identifiable { let id: Int }
    @State private var progressionEdit: ProgressionEditTarget?
    /// The backing routine's exercises, keyed by `RoutineExercise.id` (== `ExerciseRun.id`) — the menu's
    /// progression subtitle and the mini-sheet read/write here; loaded once per routine.
    @State private var routineREs: [String: RoutineExercise] = [:]
    /// The exercise index currently being dragged in modo mover, and the slot its drop would land on.
    /// nil/nil when nothing is mid-drag.
    @State private var reorderDraggingIndex: Int?
    @State private var reorderTargetIndex: Int?

    /// FER-936: the breathing ember halo behind the active exercise's «···». A stroked ring (not a blurred
    /// shadow, per DNA) that pulses opacity + scale; a steady faint ring under Reduce Motion.
    private struct TapRing: View {
        let color: Color
        let animated: Bool
        @State private var on = false
        var body: some View {
            Circle()
                .strokeBorder(color, lineWidth: 2)
                .opacity(on ? 0.10 : 0.28)
                .scaleEffect(on ? 1.0 : 0.82)
                .frame(width: 30, height: 30)
                .onAppear { if animated { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { on = true } } }
        }
    }
    @State private var freshSuggestions: [QuickSuggestion]?
    @State private var loadedMuscle: String?
    /// Full-screen «Focus mode» cover — entry from the inline set list; dismiss returns to the table
    /// without ending the session (mock v21 handoff). Additive only; does not replace `inlineSession`.
    @State private var focusMode = false
    /// Manual Tiempo/FC toggle for the full-screen rest hero (FER-934). nil = follow `currentRestMode`
    /// (FC when a rest target exists and the strap has signal); the user can flip it either way.
    @State private var focusRestShowsHR: Bool?
    /// Which exercise's «···» paper menu is open (FER-894 · «Cómo llego a Cambiar»), by run index. nil = closed.
    @State private var menuExerciseIndex: Int?
    /// The exercise whose «Change {exercise}» sheet is open (FER-894). nil = closed.
    @State private var changeExercise: ChangeTarget?
    /// The terminal «Nothing to save» result card for discarding an empty session (FER-894 · Estados 2).
    @State private var nothingToSave = false
    @State private var saveError = false
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    /// Identifies which exercise the «Change» sheet is swapping (FER-894); carries the run for its header
    /// and same-muscle shortlist. `id` is the run id so `.sheet(item:)` re-presents cleanly per exercise.
    struct ChangeTarget: Identifiable {
        let ei: Int
        let run: StrengthSessionModel.ExerciseRun
        var id: String { run.id }
    }

    /// One «Sugeridos · músculos frescos hoy» row: an exercise for a fresh muscle, with its last logged set.
    struct QuickSuggestion: Identifiable {
        let exercise: Exercise
        let muscle: String
        let lastWeightKg: Double?
        let lastReps: Int?
        var id: String { exercise.id }
    }

    /// Identifies which exercise's rest is being edited (FER-716); `setIndex` non-nil = a per-set edit
    /// (from the rest card), nil = exercise-scope (from the rest chip). The editor seeds from `runs[id]`.
    struct RestEdit: Identifiable { let id: Int; var setIndex: Int? = nil }

    /// The exercise + work weight (kg) the plate calculator was opened for (FER-720 · 3a).
    struct PlatesTarget: Identifiable {
        let id = UUID(); let ei: Int; let weightKg: Double
        // r20 (auditoría UX #6c): «Añadir calentamiento» abre la MISMA hoja pero anclada a su
        // sección — pediste calentar, no discos.
        var startAtWarmup = false
    }

    /// Identifies which set's RPE sheet is open (FER-930): the exercise's run id + the set id (stable
    /// across re-renders, unlike an index), plus the header context (set number, weight, reps).
    struct RPETarget: Identifiable {
        let id: String   // setId — unique across the session
        let runId: String
        let setNumber: Int
        let weightKg: Double
        let reps: Int
        let currentRPE: Double?
    }

    /// Identifies which exercise's note sheet is open (FER-932): the run id + exercise id (for the
    /// history lookup) + the active set's number (for the «Solo la serie N» scope option).
    struct NoteTarget: Identifiable {
        let id: String   // runId
        let exerciseId: String
        let exerciseName: String
        let setId: String
        let setNumber: Int
    }
    /// A marker to present the receipt printer (thermal ticket); carries the real session id for
    /// barcode/order stability and set/HR loads. The summary comes from `session.summary`.
    struct ShareRef: Identifiable {
        let id = UUID()
        let sessionId: String
    }

    /// Identifies an editable inline cell: a weight or reps field at (exerciseIndex, setIndex).
    enum CellRef: Hashable { case weight(Int, Int), reps(Int, Int) }

    /// The user's resting-HR baseline for the HR rest target (FER-506): the most recent trustworthy nightly
    /// RHR. nil → the rest falls back to the fixed timer (peakDrop/fixedBpm still work via an explicit target).
    private var restingBaseline: Double? {
        // Explicit types — breaks the compactMap/last/map(Double.init) inference chain (type-check hotspot).
        let restingHrs: [Int] = model.repo.days.compactMap(\.restingHr)
        let last: Int? = restingHrs.last
        guard let last else { return nil }
        let baseline: Double = Double(last)
        return baseline
    }
    /// Profile HR-max (Tanaka if no override) — the Karvonen ceiling.
    private var profileMaxHR: Double { Double(model.profile.hrMax) }

    private var units: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var imperial: Bool { units == .imperial }
    /// Plate step: 2.5 kg metric, 5 lb imperial — stored as kg.
    private var weightStepKg: Double { imperial ? 5 * Self.kgPerPound : 2.5 }
    static let kgPerPound = 0.45359237
    static let metersPerMile = 1609.344
    /// Distance step: 0.1 km metric, 0.1 mi imperial — stored as meters.
    private var distanceStepM: Double { imperial ? Self.metersPerMile * 0.1 : 100 }
    /// At large accessibility sizes the cardio two-up reflows to a single column so nothing clips.
    private var reflow: Bool { typeSize >= .accessibility1 }

    /// The «Rápido de fuerza» empty state (FER-762): an ad-hoc session (no routine) with nothing logged
    /// yet — the search + freshness-suggestions state, before the first exercise turns this into a normal
    /// guided session.
    private var isEmptyAdHoc: Bool { session.routineId == nil && session.runs.isEmpty }

    // Type-check split (FER-981): `body` was the project’s costliest getter (~359 ms). Chunked into
    // phase content + chrome + presenters + confirms — same render, smaller expressions for the checker.
    var body: some View {
        bodyWithConfirms
        .enableInjection()
    }

    /// Phase content only: nothing-to-save / summary / empty ad-hoc / live inline session.
    @ViewBuilder
    private var bodyPhaseContent: some View {
        Group {
            if nothingToSave {
                nothingToSaveCard
            } else if let summary = session.summary {
                bodySummaryScroll(summary)
            } else if isEmptyAdHoc {
                emptyAdHocSession
            } else {
                inlineSession
            }
        }
    }

    @ViewBuilder
    private func bodySummaryScroll(_ summary: StrengthSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                summaryPhase(summary)
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Theme, banners, library picker, rest-anchor onChange — no session sheets yet.
    private var bodyChrome: some View {
        bodyPhaseContent
            .background(theme.paper.ignoresSafeArea())
            .instrumentoTheme(theme)
            .safeAreaInset(edge: .top) { if session.saveError { saveErrorBanner } }
            // FER-969: mid-session routine write failure (insert / superset / progression) — toast only;
            // the FINAL session save failure is the persistent `saveErrorBanner` above (X-01), not this.
            .overlay(alignment: .top) {
                bodySaveErrorToast
            }
            .animation(StrandMotion.fade, value: saveError)
            // FER-935: hoisted from `emptyAdHocSession` to the shared root so the «＋» rail node also opens
            // the picker in a populated (routine-backed) session, not just the ad-hoc empty state.
            .sheet(isPresented: $showLibraryPicker) {
                bodyLibraryPickerSheet
            }
            .onChange(of: session.phase) { _, phase in
                if phase != .resting { restAnchorEi = nil }
            }
    }

    @ViewBuilder
    private var bodySaveErrorToast: some View {
        if saveError {
            Text("Couldn't save. Try again.")
                .font(.system(size: 13))   // token-exempt: cuerpo de banner (13pt, igual que el mensaje de ConfirmCard)
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .patternBlock(theme, bar: theme.critical)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: .seconds(4))
                    saveError = false
                }
        }
    }

    @ViewBuilder
    private var bodyLibraryPickerSheet: some View {
        // Canvas pass 2026-07-15: sin leyenda (owner call) — el ejercicio se inserta después del
        // actual y se queda PERMANENTE en la rutina (persistencia abajo en `addExercises`).
        ExerciseLibraryScreen { picks in
            showLibraryPicker = false
            Task { await addExercises(picks) }
        }
        .instrumentoTheme(theme).environmentObject(model.repo).preferredColorScheme(.light)
    }

    /// Progression / detail / change / rest·plates·RPE·note (focus-silenced) + fullScreen covers.
    private var bodyPresenters: some View {
        bodyChrome
            .sheet(item: $progressionEdit) { target in
                bodyProgressionSheet(target)
            }
            .task(id: session.routineId) { await loadRoutineREs() }
            .sheet(item: $detailExercise) { ex in
                bodyDetailSheet(ex)
            }
            .sheet(item: $changeExercise) { target in
                bodyChangeSheet(target)
            }
            // r15: durante el modo foco estos cuatro presentadores externos se SILENCIAN (binding
            // constante nil) — el cover cuelga sus propias copias adentro; dos presentadores vivos
            // sobre el mismo estado peleaban la presentación y tumbaban el foco a la pantalla base.
            .sheet(item: focusMode ? .constant(nil) : $restEdit) { edit in
                restEditorSheet(edit)
            }
            .sheet(item: focusMode ? .constant(nil) : $platesTarget) { target in
                platesSheet(target)
            }
            .sheet(item: focusMode ? .constant(nil) : $rpeTarget) { target in
                rpeSheet(target)
            }
            .sheet(item: focusMode ? .constant(nil) : $noteTarget) { target in
                noteSheet(target)
            }
            .fullScreenCover(item: $shareReceipt) { ref in
                bodyShareCover(ref)
            }
            .fullScreenCover(isPresented: $focusMode) {
                bodyFocusCover
            }
    }

    @ViewBuilder
    private func bodyProgressionSheet(_ target: ProgressionEditTarget) -> some View {
        // r7: la pantalla de progresión COMPLETA (la misma del editor de rutina, con deload e
        // ignorar-recuperación) — el dueño la recordaba bien; la mini-hoja lean se retira.
        if session.runs.indices.contains(target.id) {
            let run = session.runs[target.id]
            ProgressionSetupScreen(
                theme: theme,
                exercise: routineREs[run.id] ?? syntheticRE(from: run, position: target.id),
                exerciseName: run.name,
                currentWeightKg: run.sets.first?.weightKg,
                derivedIncrementKg: weightStepKg,
                onBack: { progressionEdit = nil },
                onSave: { enabled, targetReps, sessions, incrementKg, deload, ignoreRecovery in
                    persistProgressionFull(runId: run.id, enabled: enabled, targetReps: targetReps,
                                           sessions: sessions, incrementKg: incrementKg,
                                           deload: deload, ignoreRecovery: ignoreRecovery)
                    progressionEdit = nil
                }
            )
            .padding(.top, CenitMetrics.gap)
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.paper)
            .preferredColorScheme(.light)
        }
    }

    @ViewBuilder
    private func bodyDetailSheet(_ ex: Exercise) -> some View {
        NavigationStack {
            ExerciseDetailScreen(exercise: ex)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { detailExercise = nil }.foregroundStyle(theme.ink)
                } }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(theme.paper, for: .navigationBar)
        }
        .instrumentoTheme(theme).environmentObject(model.repo).preferredColorScheme(.light)
    }

    @ViewBuilder
    private func bodyChangeSheet(_ target: ChangeTarget) -> some View {
        ChangeExerciseSheet(
            theme: theme, run: target.run, repo: model.repo,
            onUse: { ex in
                changeExercise = nil
                Task {
                    let last = await model.repo.exerciseHistory(exerciseId: ex.id).last
                    await MainActor.run {
                        withAnimation(.snappy) {
                            session.replaceExercise(at: target.ei, with: ex,
                                                    lastWeightKg: last?.weightKg, lastReps: last?.reps)
                        }
                    }
                }
            },
            onClose: { changeExercise = nil }
        )
        .instrumentoTheme(theme).preferredColorScheme(.light)
        .presentationBackground(theme.paper)
    }

    @ViewBuilder
    private func bodyShareCover(_ ref: ShareRef) -> some View {
        if let summary = session.summary {
            ReceiptPrinterScreen(
                theme: theme,
                summary: summary,
                sessionId: ref.sessionId,
                onClose: { shareReceipt = nil }
            )
            .environment(model)
        }
    }

    @ViewBuilder
    private var bodyFocusCover: some View {
        // r15: TODA la interacción del foco ocurre DENTRO del cover — discos, RPE, nota y el
        // editor de descanso cuelgan aquí (los presentadores externos quedan silenciados
        // mientras el foco está arriba). Un sheet presentado desde la base tumbaba el cover.
        focusModeView
            .sheet(item: $platesTarget) { target in
                platesSheet(target)
            }
            .sheet(item: $rpeTarget) { target in
                rpeSheet(target)
            }
            .sheet(item: $noteTarget) { target in
                noteSheet(target)
            }
            .sheet(item: $restEdit) { edit in
                restEditorSheet(edit)
            }
    }

    /// Destructive confirms (finish / discard / superset steal) — last layer on `body`.
    private var bodyWithConfirms: some View {
        bodyPresenters
            // S-2 (FER-830) → FER-837: one destructive-confirmation pattern across the flow, now the
            // «Instrumento» ConfirmCard. The stay-safe verb names its action («Keep training»), never a
            // generic cancel; destructive is always the red outline.
            .instrumentoConfirm(
                isPresented: $confirmFinish,
                title: String(localized: "Finish workout?"),
                context: String(localized: "SESSION · IN PROGRESS"),
                message: bodyFinishConfirmMessage,
                // r20 (auditoría UX #2): con 0 series «Guardar» descartaba en silencio (el modelo exige
                // doneCount > 0) — el botón hacía lo contrario de lo que decía. Sin series: quedarse es
                // la primaria y descartar la destructiva; guardar solo existe cuando hay qué guardar.
                actions: bodyFinishConfirmActions
            )
            .instrumentoConfirm(
                isPresented: $confirmDiscard,
                title: String(localized: "Discard workout?"),
                context: String(localized: "SESSION · IN PROGRESS"),
                message: String(localized: "Everything you logged in this session will be deleted. This can't be undone."),
                actions: [
                    .init(String(localized: "Keep training"), role: .primary),
                    .init(String(localized: "Discard workout"), role: .destructive) { model.endStrengthSession(save: false) }
                ]
            )
            // r21 (auditoría UX #5a): emparejar con un vecino que YA es de otra superserie deshace
            // aquella pareja — se confirma con su nombre en la mano, nunca en silencio.
            .instrumentoConfirm(
                isPresented: Binding(get: { confirmSupersetSteal != nil },
                                     set: { if !$0 { confirmSupersetSteal = nil } }),
                title: String(localized: "Break its current superset?"),
                context: String(localized: "SESSION · IN PROGRESS"),
                message: bodySupersetStealMessage,
                actions: [
                    .init(String(localized: "Pair here"), role: .primary) {
                        if let ei = confirmSupersetSteal {
                            withAnimation(.snappy) { session.toggleSupersetWithNext(ei) }
                            persistSupersetGroups()   // r30: también el robo consentido queda en la rutina
                        }
                        confirmSupersetSteal = nil
                    },
                    .init(String(localized: "Keep as is"), role: .secondary)
                ]
            )
    }

    private var bodyFinishConfirmMessage: String {
        if session.doneCount == 0 {
            return String(localized: "You haven't logged any sets yet.")
        }
        if session.pendingCount > 0 {
            return String(localized: "\(session.pendingCount) sets aren't logged yet. Save keeps them; discard deletes everything.")
        }
        return String(localized: "Save keeps this workout. Discard deletes everything you logged.")
    }

    private var bodyFinishConfirmActions: [InstrumentoConfirmAction] {
        if session.doneCount == 0 {
            return [
                .init(String(localized: "Keep training"), role: .primary),
                .init(String(localized: "Discard workout"), role: .destructive) { model.endStrengthSession(save: false) }
            ]
        }
        return [
            .init(String(localized: "Save workout"), role: .primary) { model.endStrengthSession(save: true) },
            .init(String(localized: "Keep training"), role: .secondary),
            .init(String(localized: "Discard workout"), role: .destructive) { model.endStrengthSession(save: false) }
        ]
    }

    private var bodySupersetStealMessage: String {
        let neighborName: String = confirmSupersetSteal.flatMap { ei -> String? in
            let next: Int = ei + 1
            guard session.runs.indices.contains(next) else { return nil }
            return session.runs[next].name
        } ?? ""
        return String(format: String(localized: "%@ is already paired in another superset. Pairing it here undoes that one."),
                      neighborName)
    }

    // MARK: Inline session (the default view — the Hevy-style logging table, FER-497)

    // Type-check split (FER-981): stack / row / chrome pieces keep inference off the ~136 ms getter.
    private var inlineSession: some View {
        // r18: ScrollView + VStack, ya NO `List` — the List's cells carried unpredictable per-row
        // slack that broke the rail thread at a different seam every round (r7–r17 chased it seam by
        // seam); a plain stack lays rows out exactly, so the thread segments butt by construction.
        // The List's one justification (per-set swipe-to-delete) died in r13 (long-press menu).
        // FER-929: rail + accordion — only the active exercise expands into its table; done/upcoming
        // exercises collapse to one line each, hung off a vertical rail (`railColumn`).
        // Canvas pass 2026-07-15 (sugerencia 3): the jump to the next exercise is NARRATED — when the
        // guided focus moves, the list scrolls the new active card into view instead of teleporting.
        ScrollViewReader { proxy in
            inlineSessionScroll(proxy: proxy)
        }
    }

    /// Scroll + chrome (head / keypad|stats / cell + accordion onChange). Row stack lives below.
    private func inlineSessionScroll(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            inlineSessionStack
        }
        .onAppear { scrollProxy = proxy }
        .background(theme.paper)
        // UX·anim #2: one clock for the exercise jump — the row collapse shares the scroll's gentle
        // spring so both read as a single continuous gesture (before: snappy vs. gentle fighting).
        .animation(StrandMotion.gentle, value: accordionIndex)
        .safeAreaInset(edge: .top, spacing: 0) { liveHead }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inlineSessionBottomInset
        }
        .onChange(of: activeCell) { _, newValue in
            // Seed the buffer from the newly-active cell's current value (replace-on-first-keystroke), and
            // make its row the «active» one so the header/rest logic tracks it.
            if let f = newValue {
                let (ei, si) = Self.indices(f)
                session.select(exerciseIndex: ei, setIndex: si)
                buffer = currentCellString(f); bufferTyped = false
            } else {
                buffer = ""; bufferTyped = false
            }
        }
        .onChange(of: accordionIndex) { _, newIndex in
            // Sugerencia 3 + r6: the narrated move happens when the ACCORDION moves — i.e. when the
            // rest ends — not when the model's index advances mid-rest.
            // anim r7: primero respira el colapso del descanso, LUEGO desliza (secuencia narrada).
            withAnimation(reduceMotion ? nil : StrandMotion.gentle.delay(0.15)) {
                proxy.scrollTo("session-exercise-\(newIndex)", anchor: .center)
            }
        }
    }

    @ViewBuilder
    private var inlineSessionBottomInset: some View {
        if let cell = activeCell { keypad(for: cell) } else { statsBar }
    }

    /// Exercise list + reorder bar + add/complete/discard footers (no chrome).
    @ViewBuilder
    private var inlineSessionStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            // FER-933: modo mover — every exercise compresses to a draggable row with a «SOLTAR AQUÍ ·
            // POSICIÓN N» drop zone; the accordion (`activeExerciseBlock`) stays closed for the duration.
            if reorderMode { reorderModeBar.plainRow(top: CenitMetrics.gap, bottom: 4).transition(.opacity) }
            ForEach(Array(session.runs.enumerated()), id: \.element.id) { ei, run in
                if !run.skipped {
                    inlineSessionRow(run: run, ei: ei)
                }
            }
            if !reorderMode {
                // Canvas pass 2026-07-15: no top inset — an inset is a HOLE in the rail thread; the
                // node's breathing lives in its own taller row so the line arrives unbroken.
                addExerciseNode.plainRow()
                // FER-952 (owner): the tail breathed 28+12+24 — tightened to the compact rhythm; the
                // stats bar below already separates the list from the edge.
                if session.isComplete, session.doneCount > 0 { completeFooter.plainRow(top: CenitMetrics.gap) }
                discardFooter.plainRow(top: 4, bottom: CenitMetrics.gap)
            }
        }
    }

    /// One exercise row in reorder mode or accordion (active / done / upcoming).
    @ViewBuilder
    private func inlineSessionRow(run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        if reorderMode {
            // UX·anim #3: mode changes fade explicitly — the row TYPE swap (riel ↔ mover)
            // had no declared transition and read as a flicker.
            reorderRow(run, ei: ei).plainRow(top: 4, bottom: 4).transition(.opacity)
        } else {
            switch railState(ei: ei, run: run) {
            case .active:
                activeExerciseBlock(run, ei: ei)
            case .done:
                doneRow(run, ei: ei)
                    .plainRow()
                    // anim r7: al completarse, la fila «se guarda» — entra desde arriba
                    // con fade, como asentándose en el riel.
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity))
            case .upcoming:
                comingRow(run, ei: ei)
                    .plainRow()
                    .transition(.opacity)
            }
        }
    }

    // MARK: Rail + accordion (FER-929)

    /// One exercise's position relative to the guided focus: active (accordion open), done (all its sets
    /// logged, or its index already passed), or upcoming. Derived purely from `StrengthSessionModel`'s
    /// existing `currentIndex`/`sets.done` — the model itself is untouched.
    private enum RailState { case active, done, upcoming }

    private func railState(ei: Int, run: StrengthSessionModel.ExerciseRun) -> RailState {
        if ei == accordionIndex { return .active }
        if ei < session.currentIndex || run.sets.allSatisfy(\.done) { return .done }
        return .upcoming
    }

    /// The vertical rail (canvas pass 2026-07-15): one CONTINUOUS thread in the routine's own family
    /// tint at low opacity («ember tenue» — structure, not datum), bridging the inter-row insets with
    /// negative vertical padding so it never breaks between rows. Each exercise hangs a fixed 9pt dot
    /// tinted by ITS movement family (push=ember · pull=teal · legs=indigo); the active dot keeps the
    /// existing soft halo. A superset span keeps its «A1»/«A2» teal badge (the LINE no longer flips
    /// teal — the badge/tag alone carry the superset, so rail-color and superset don't compete).
    /// Purely decorative — `accessibilityHidden`, the row's own label carries the state to VoiceOver.
    private func railColumn(_ state: RailState, superset: Bool, badgeText: String? = nil,
                            tint: Color, dotTopOffset: CGFloat? = nil, clipTop: Bool = false) -> some View {
        ZStack(alignment: dotTopOffset == nil ? .center : .top) {
            // The thread fills the WHOLE row height — rows butt exactly in the r18 stack layout, so
            // segments join seam-to-seam with no overshoot (r17's ±30 overlapped two 35%-alpha
            // rectangles and the doubled alpha DARKENED the lane — «overlap» visible). `clipTop`
            // (first exercise) starts the thread AT the dot — nothing hangs above.
            if clipTop {
                VStack(spacing: 0) {
                    Color.clear
                    Rectangle().fill(railTint.opacity(0.35)).frame(width: 2)  // token-exempt: decorative rail-thread alpha (structure, not datum)
                }
            } else {
                Rectangle().fill(railTint.opacity(0.35)).frame(width: 2)  // token-exempt: decorative rail-thread alpha (structure, not datum)
            }
            Group {
                if let badgeText {
                    Circle()
                        .fill(theme.dataHrv)
                        .frame(width: 17, height: 17)
                        .overlay {
                            Text(badgeText).font(StrandFont.footnote).fontWeight(.semibold)
                                .foregroundStyle(theme.paper)
                        }
                } else {
                    ZStack {
                        Circle().fill(theme.paper).frame(width: 15, height: 15)
                        Circle().fill(tint).frame(width: 9, height: 9)
                    }
                }
            }
            .padding(.top, dotTopOffset.map { $0 - 4.5 } ?? 0)
        }
        .frame(width: 14)
        .accessibilityHidden(true)
    }

    /// The rail only exists with 2+ exercises — a thread through a single stop reads orphaned
    /// (canvas pass 2026-07-15, sugerencia 2).
    private var showRail: Bool { session.runs.filter { !$0.skipped }.count > 1 }

    /// The first visible (non-skipped) exercise — its dot is the thread's BIRTHPLACE: no line above it.
    private var firstRailIndex: Int? { session.runs.firstIndex { !$0.skipped } }

    /// The routine's own family tint — the color of the rail thread. Classified from what the session
    /// actually contains (same `RoutineClassifier` the hub/plan use), so an ad-hoc session earns a color
    /// too. Push routines read ember, pull teal, legs indigo; mixed/full-body falls back to ember.
    private var railTint: Color {
        let muscles = session.runs.compactMap { ExerciseCatalog.byID($0.exerciseId)?.primaryMuscles }
        switch RoutineClassifier.classify(primaryMusclesPerExercise: muscles) {
        case .pull: return theme.dataHrv
        case .legs: return theme.dataSleep
        default: return theme.dataStrain
        }
    }

    /// Movement-family tint for ONE exercise's rail dot — r20: PROMOVIDO a StrandDesign
    /// (`InstrumentoTheme.movementFamilyTint`), como el código prometía; History/Biblioteca
    /// migran su copia local en un follow-up.
    private func categoryTint(_ run: StrengthSessionModel.ExerciseRun) -> Color {
        guard let ex = ExerciseCatalog.byID(run.exerciseId) else { return theme.dataStrain }
        return theme.movementFamilyTint(primaryMuscles: ex.primaryMuscles)
    }

    /// The «A1»/«A2» badge text for the run at `ei`: its superset letter + (position in the span + 1).
    /// nil when the run isn't in a real superset (railColumn then falls back to the plain dot).
    private func supersetBadgeText(ei: Int) -> String? {
        guard session.isInSuperset(ei) else { return nil }
        let members = session.supersetMembers(at: ei)
        guard let letter = session.supersetLetter(for: ei),
              let position = members.firstIndex(of: ei) else { return nil }
        return "\(letter)\(position + 1)"
    }

    /// «SUPERSERIE» tag, teal, next to a run's name when it's part of a real superset span (FER-931).
    @ViewBuilder private func supersetTag(_ ei: Int) -> some View {
        if session.isInSuperset(ei) {
            Text("SUPERSET").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.dataHrv)
        }
    }

    /// A finished exercise, compressed to one line: dimmed name + «carga × reps·reps·reps» + a green
    /// check. Still tappable — re-opens the accordion on its first not-done set so a set can be corrected.
    private func doneRow(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        Button {
            restAnchorEi = nil   // switching by hand releases the rest-held accordion
            withAnimation(.snappy(duration: 0.22)) {
                session.select(exerciseIndex: ei, setIndex: run.sets.firstIndex { !$0.done } ?? 0)
            }
        } label: {
            HStack(spacing: 12) {
                railColumn(.done, superset: session.isInSuperset(ei), badgeText: supersetBadgeText(ei: ei),
                           tint: categoryTint(run), clipTop: ei == firstRailIndex)
                // Canvas pass: dim the CONTENT, not the whole row — the rail thread and its dot stay at
                // full strength so the hilo reads continuous while the finished exercise recedes. The
                // row's breathing lives HERE (vertical padding), not in list insets, so cells butt up.
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        supersetTag(ei)
                        Text(run.name).font(StrandFont.body).foregroundStyle(theme.inkTertiary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // r26: dato medido → Grotesk (la voz de valores, aún comprimido).
                    Text(doneDetailText(run)).font(InstrumentoType.groteskNumber(12, weight: .regular)).foregroundStyle(theme.inkTertiary)
                        .lineLimit(1)
                    Image(systemName: "checkmark.circle.fill")
                        .font(StrandFont.glyph(.chevron)).foregroundStyle(theme.dataRecovery)
                }
                .opacity(StrandOpacity.dim)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // r20 (owner, UX #4): el long-press de mover se RETIRA — chocaba con el long-press de
        // «Quitar serie» (gestos idénticos, semánticas distintas). Mover entra SOLO por «≡».
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(supersetAccessibilityLabel(ei: ei, base: "\(run.name), done, \(doneDetailText(run))")))
        .accessibilityHint(Text("Double tap to reopen and correct a set"))
    }

    /// A not-yet-reached exercise, compressed to one line: name + its planned prescription. Tapping moves
    /// the guided focus here (the same `select` the plan navigator already used).
    private func comingRow(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        Button {
            restAnchorEi = nil   // switching by hand releases the rest-held accordion
            withAnimation(.snappy(duration: 0.22)) { session.select(exerciseIndex: ei, setIndex: 0) }
        } label: {
            HStack(spacing: 12) {
                railColumn(.upcoming, superset: session.isInSuperset(ei), badgeText: supersetBadgeText(ei: ei),
                           tint: categoryTint(run), clipTop: ei == firstRailIndex)
                // Canvas pass: upcoming rows now dim exactly like done rows (the row that «se escapaba»)
                // — content only, so the rail thread stays alive. Breathing inside the content.
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        supersetTag(ei)
                        Text(run.name).font(StrandFont.body).foregroundStyle(theme.ink).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(prescriptionText(run)).font(InstrumentoType.groteskNumber(12, weight: .regular)).foregroundStyle(theme.inkTertiary)
                        .lineLimit(1)
                }
                .opacity(StrandOpacity.dim)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // r20 (owner, UX #4): sin long-press de mover — entra solo por «≡» (ver doneRow).
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(supersetAccessibilityLabel(ei: ei, base: "\(run.name), coming up, \(prescriptionText(run))")))
        .accessibilityHint(Text("Double tap to move focus here"))
    }

    /// Appends the superset role to a row's a11y label when the run is grouped (FER-931), e.g.
    /// «Press banca, superserie A1, coming up, 60 kg × 8» — a plain exercise's label is untouched.
    private func supersetAccessibilityLabel(ei: Int, base: String) -> String {
        guard let badge = supersetBadgeText(ei: ei) else { return base }
        let role = String(format: String(localized: "superset %@"), badge)
        // Insert right after the name (before the first comma) so the role reads naturally.
        guard let commaRange = base.range(of: ",") else { return "\(base), \(role)" }
        var result = base
        result.insert(contentsOf: ", \(role)", at: commaRange.lowerBound)
        return result
    }

    /// «82,5 kg × 8·8·6» for a finished weight/reps or bodyweight exercise; falls back to the plain
    /// «previous» phrasing for time/distance (there's no per-set rep list to join there).
    private func doneDetailText(_ run: StrengthSessionModel.ExerciseRun) -> String {
        guard run.type == .weightReps || run.type == .bodyweight else { return previousText(run) ?? "" }
        let w = run.sets.first?.weightKg ?? 0
        let reps = run.sets.map { "\($0.reps)" }.joined(separator: "·")
        return "\(massText(w)) × \(reps)"
    }

    /// «82,5 kg × 8» — the planned first-set prescription for an upcoming exercise.
    private func prescriptionText(_ run: StrengthSessionModel.ExerciseRun) -> String {
        guard run.type == .weightReps || run.type == .bodyweight else {
            // FER-952 (UX M3): la clave suelta «series» traducía en→"series"; la plural ya dice set/serie bien.
            return String(localized: "\(run.sets.count) sets")
        }
        let w = run.sets.first?.weightKg ?? 0
        let reps = run.sets.first?.reps ?? 0
        return "\(massText(w)) × \(reps)"
    }

    /// The active exercise — ONE List row (r13). r14: the rail no longer has its own lane column —
    /// the thread hangs off the CARD (overlay, spans exactly its height) and the category dot hangs
    /// off the THUMBNAIL itself (overlay, vertically centered by alignment — zero math to drift).
    /// Card, thread and dot are one layout tree, so they can only move together. Swipe-to-delete
    /// needed List rows, so deleting a set is a long-press context menu (previewing JUST that row).
    private func activeExerciseBlock(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        VStack(spacing: 0) {
            exerciseHeader(run, ei: ei, first: true)
                .padding(.top, 12).padding(.horizontal, CenitMetrics.receiptPadding).padding(.bottom, 8)
            ForEach(Array(run.sets.enumerated()), id: \.element.id) { si, set in
                // FER-937: a «SERIES DE TRABAJO» rule separates the collapsible warm-up «C» rows
                // from the numbered work sets — drawn on the first work row after a warm-up.
                let afterWarmup = set.kind == .work && si > 0 && run.sets[si - 1].kind == .warmup
                VStack(spacing: 0) {
                    // El descanso vive DENTRO del bloque, pegado a su fila (r7/r12).
                    if restSlotIndex(run, ei: ei) == si { restInlineSlice(run) }
                    if afterWarmup { workSetsDivider.padding(.top, 12).padding(.bottom, 6) }
                    // r15 (owner): borrar es interacción PROPIA — el contextMenu del sistema es
                    // por CELDA (todos los long-press caían en la fila 1) y su lift fotografiaba
                    // la tarjeta entera. Ahora la fila armada brinca EN SU LUGAR sobre la tarjeta
                    // (scale + hover, mismo lenguaje que la tarjeta de descanso) y ofrece la
                    // pastilla «Quitar serie»; cualquier otro toque la desarma.
                    setRow(ei: ei, si: si, run: run, set: set, last: si == run.sets.count - 1)
                        .scaleEffect(armedDeleteSetId == set.id ? 1.03 : 1)
                        .shadow(color: .black.opacity(armedDeleteSetId == set.id ? 0.10 : 0),  // token-exempt: sombra transitoria de lift (hover), no superficie
                                radius: 10, y: 4)
                        .overlay(alignment: .trailing) {
                            if armedDeleteSetId == set.id { deleteSetPill(ei: ei, si: si) }
                        }
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                            withAnimation(StrandMotion.gentle) { armedDeleteSetId = set.id }
                        })
                        .simultaneousGesture(TapGesture().onEnded {
                            if armedDeleteSetId != nil {
                                withAnimation(StrandMotion.gentle) { armedDeleteSetId = nil }
                            }
                        })
                        .accessibilityActions {
                            Button("Delete set") { withAnimation(.snappy) { session.removeSet(exercise: ei, set: si) } }
                        }
                }
                .padding(.horizontal, CenitMetrics.receiptPadding)
                .zIndex(armedDeleteSetId == set.id ? 2 : 0)
            }
            // «Add set» closes the card — the handoff's ember pill, inside (FER-935 kin).
            // El descanso tras la ÚLTIMA serie vive aquí (r7/r12).
            VStack(spacing: 0) {
                if session.phase == .resting, ei == accordionIndex, session.summary == nil,
                   restSlotIndex(run, ei: ei) == nil {
                    restInlineSlice(run)
                }
                addSetButton(ei)
            }
            // r22 (simetría): la tarjeta cerraba con 8 abajo vs 12 arriba — parejo con el tope.
            .padding(.horizontal, CenitMetrics.receiptPadding)
            .padding(.top, 8).padding(.bottom, 12)
        }
        .background(
            // «Recibo» (owner r6): superficie PLANA — borde hairline, cero sombra. One simple
            // shape replaces the r8d per-slice UnevenRoundedRectangle + internal-edge mask.
            RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .fill(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1))
        )
        // r16/r18: the thread is a BACKGROUND of the card (behind the dot), 19pt into the gutter
        // (26 − 7), spanning exactly the card's height — in the r18 stack layout the card IS the
        // row, so the segment butts its neighbors seam-to-seam (no overshoot: doubled 35%-alpha
        // overlap darkened the lane). The FIRST exercise's birth-at-the-dot is a thumb-anchored
        // eraser in `exerciseHeader`.
        .background(alignment: .topLeading) {
            if showRail {
                Rectangle().fill(railTint.opacity(StrandOpacity.strokeSoft))
                    .frame(width: 2)
                    .offset(x: -20)
                    .allowsHitTesting(false)
            }
        }
        .padding(.leading, 26)
        .plainRow()
        .id("session-exercise-\(ei)")
        // r24 (owner): la bolita/tarjeta activa hace CROSSFADE al cambiar de ejercicio — antes el
        // bloque nuevo aparecía en seco mientras el viejo se comprimía; el fade cuenta la
        // continuidad del foco sobre el riel (comparte el reloj gentle del acordeón).
        .transition(.opacity)
    }

    /// The armed row's destructive affordance (r15) — a quiet critical-outline pill riding the
    /// lifted row's trailing edge (it covers the check so the only offered act is the deletion).
    private func deleteSetPill(ei: Int, si: Int) -> some View {
        Button {
            let wasWarmup = session.runs.indices.contains(ei)
                && session.runs[ei].sets.indices.contains(si)
                && session.runs[ei].sets[si].kind == .warmup
            withAnimation(.snappy) { session.removeSet(exercise: ei, set: si) }
            // r22 (owner): quitar la ÚLTIMA «C» del ejercicio apaga su calentamiento persistente.
            if wasWarmup, session.runs.indices.contains(ei),
               !session.runs[ei].sets.contains(where: { $0.kind == .warmup }) {
                model.plates.setWarmupAlways(session.runs[ei].exerciseId, false)
            }
            armedDeleteSetId = nil
        } label: {
            // r21 (owner): más discreto — se comía la fila hacia la izquierda; glifo chico, texto
            // caption plano, padding apretado.
            HStack(spacing: 5) {
                Image(systemName: "trash").font(StrandFont.glyph(.chevron))
                Text("Delete set").font(StrandFont.caption)
            }
            .foregroundStyle(theme.critical)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.critical.opacity(StrandOpacity.dim), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityLabel(Text("Delete set"))
    }

    /// The exercise the current rest belongs to (canvas pass 2026-07-15, owner bug #4): registering the
    /// LAST set advances `currentIndex` to the next exercise, but the rest card must stay GLUED under
    /// the exercise you just finished — so every register path stamps the anchor before advancing.
    @State private var restAnchorEi: Int?

    /// The exercise whose accordion is OPEN: while resting, the anchor (the exercise you just worked)
    /// holds the accordion open — the jump to `currentIndex` happens when the rest ends (owner r6).
    private var accordionIndex: Int {
        (session.phase == .resting ? restAnchorEi : nil) ?? session.currentIndex
    }

    /// Every «✓ registrar» in the view funnels here: stamp the rest's home exercise, THEN let the model
    /// advance. The anchor clears when the rest ends (`onChange` of `session.phase`).
    private func registerActiveSet() {
        restAnchorEi = session.currentIndex
        session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR)
    }

    /// The set index the inline rest card slots BEFORE — nil when the rest follows the exercise's
    /// last set (the card then lands after the table). r12 (owner): the card hangs off the LAST
    /// DONE row, always. Slotting before `currentSet` let the card wander: un-checking a row ABOVE
    /// moved `currentSet` up and dragged the resting card with it, away from the set just finished.
    private func restSlotIndex(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> Int? {
        guard session.phase == .resting, ei == accordionIndex, session.summary == nil else { return nil }
        guard let lastDone = run.sets.lastIndex(where: { $0.done }) else {
            return run.sets.isEmpty ? nil : 0
        }
        let si = run.sets.index(after: lastDone)
        return run.sets.indices.contains(si) ? si : nil
    }

    /// El descanso en línea EMBEBIDO en la rebanada de su fila (r7-fix): conserva su hover propio y el
    /// auto-cierre de descansos fijos; entra/sale como apertura de espacio, sin fila aparte que el
    /// List pueda fusionar.
    private func restInlineSlice(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        restInlineCard
            // A fixed rest that runs out dismisses itself — focus lands on the next active
            // set with no tap in between (HR rests keep the card up until the buzz/skip).
            .task(id: session.restEndsAt) {
                guard session.currentRestMode == .fixed, let end = session.restEndsAt else { return }
                let delay = end.timeIntervalSinceNow
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled, session.phase == .resting, !session.paused else { return }
                withAnimation(StrandMotion.gentle) { session.skipRest() }
            }
            .padding(.vertical, 8)
            // r17 (owner, propuesta 1 «el papel se abre»): la ENTRADA no viaja — las series se
            // apartan (el VStack abre el espacio) y la tarjeta se revela en su lugar con puro fade.
            // La salida se queda como r15: se hunde ANCLADA A SU TOPE (escala 0.92 + fade) mientras
            // las filas de abajo se cierran sobre ella.
            .transition(.asymmetric(
                insertion: .opacity,
                removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))))
    }

    /// FER-937: the «SERIES DE TRABAJO» rule between the warm-up «C» rows and the numbered work sets —
    /// two hairlines flanking a quiet overline. A label, not a datum, so it stays in tinted ink.
    private var workSetsDivider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(theme.hairline).frame(height: 1)
            Text("WORK SETS").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
        .accessibilityLabel(Text("Work sets"))
    }

    /// The riel's terminal node — a dotted circle affordance that opens the existing ad-hoc add-exercise
    /// flow (`showLibraryPicker` → `addExercises`). Positional insertion is a later child (FER-929 §1).
    private var addExerciseNode: some View {
        Button { showLibraryPicker = true } label: {
            HStack(spacing: 12) {
                // Canvas pass: the «＋» is the rail's TERMINAL stop — the thread drops from the cell
                // top and dies exactly at the ring's center; ring and thread share the same 14pt lane
                // center so they can't drift apart.
                ZStack {
                    VStack(spacing: 0) {
                        Rectangle().fill(railTint.opacity(0.35)).frame(width: 2)  // token-exempt: decorative rail-thread alpha (structure, not datum)
                            .opacity(showRail ? 1 : 0)
                        Color.clear
                    }
                    Circle().fill(theme.paper)
                        .overlay(Circle().strokeBorder(theme.dataStrain, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.dataStrain)  // token-exempt: tiny plus glyph sized to the 18pt dotted add-node
                        )
                }
                .frame(width: 14)
                // Más prominente (Fer 2026-07-16): mismo chip de ancho completo que el editor.
                HStack(spacing: 8) {
                    StrandIcon.add.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                    Text("Add exercise").font(StrandFont.subhead.weight(.semibold))
                }
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(theme.patternBlock, in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
            }
            .frame(minHeight: 44 + CenitMetrics.gap)   // the row's own breathing — not an inset hole
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add exercise"))
    }

    /// The custom keypad bound to the active cell (FER-716).
    @ViewBuilder private func keypad(for cell: CellRef) -> some View {
        let (ei, si) = Self.indices(cell)
        let run = session.runs.indices.contains(ei) ? session.runs[ei] : nil
        SessionKeypad(
            theme: theme,
            stepLabel: isWeightCell(cell) ? (imperial ? "±5" : "±2,5") : "±1",
            canCopyPrevious: run.map { previousText($0) != nil } ?? false,
            // r15 (owner): discos solo para ejercicios de BARRA — un dumbbell no se carga por lado.
            platesEnabled: isWeightCell(cell) && usesBarbell(ei),
            onDigit: { keypadInput(String($0)) },
            onComma: { keypadComma() },
            onBackspace: { keypadBackspace() },
            onNext: { focusNextCell() },
            onCopyPrevious: { if let run { prefillTapped(ei: ei, si: si, run: run); syncBufferFromModel(cell) } },
            onStep: { keypadStep(cell) },
            onPlates: { openPlates(ei: ei, si: si) },
            onHide: { withAnimation(.snappy(duration: 0.22)) { activeCell = nil } }
        )
        .transition(.move(edge: .bottom))
    }

    /// The plate-calculator sheet content, shared by the two presenters (main body + inside the focus
    /// cover — a sheet can only present from the frontmost layer).
    private func platesSheet(_ target: PlatesTarget) -> some View {
        PlatesScreen(
            theme: theme,
            targetKg: target.weightKg,
            exerciseName: session.runs.indices.contains(target.ei) ? session.runs[target.ei].name : "",
            store: model.plates,
            onInsertWarmup: { sets in
                session.insertWarmup(exercise: target.ei, sets: sets)
                // r22 (owner): insertar la rampa ACTIVA el calentamiento del ejercicio — las
                // sesiones futuras nacen con sus «C» (se apaga quitando la última «C» en sesión).
                if session.runs.indices.contains(target.ei) {
                    model.plates.setWarmupAlways(session.runs[target.ei].exerciseId, true)
                }
                platesTarget = nil
            },
            onClose: { platesTarget = nil },
            startAtWarmup: target.startAtWarmup
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(theme.paper)
    }

    /// Open the plate calculator (FER-720 · 3a) for a weight cell, seeded with that set's current load.
    private func openPlates(ei: Int, si: Int, startAtWarmup: Bool = false) {
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return }
        platesTarget = PlatesTarget(ei: ei, weightKg: session.runs[ei].sets[si].weightKg,
                                    startAtWarmup: startAtWarmup)
    }

    /// r15 (owner): la calculadora de discos solo aplica a ejercicios de BARRA — «por lado» no
    /// significa nada en un dumbbell/máquina. free-exercise-db: «barbell» y «e-z curl bar».
    private func usesBarbell(_ ei: Int) -> Bool {
        guard session.runs.indices.contains(ei),
              let eq = ExerciseCatalog.byID(session.runs[ei].exerciseId)?.equipment?.lowercased()
        else { return false }
        return eq.contains("barbell") || eq.contains("curl bar")
    }

    /// The RPE sheet content, shared by the two presenters (main body + inside the focus cover).
    private func rpeSheet(_ target: RPETarget) -> some View {
        RPESheet(theme: theme, target: target,
                 weightLabel: "\(plateNumber(displayWeight(target.weightKg))) \(UnitFormatter.massUnit(units))",
                 onPick: { rpe in
                     session.setRPE(exercise: target.runId, set: target.id, rpe: rpe)
                     rpeTarget = nil
                 },
                 onClose: { rpeTarget = nil })
            .presentationDetents([.height(560)])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.paper)
            .preferredColorScheme(.light)
    }

    /// The note sheet content, shared by the two presenters (main body + inside the focus cover).
    @ViewBuilder private func noteSheet(_ target: NoteTarget) -> some View {
        if let run = session.runs.first(where: { $0.id == target.id }) {
            NoteSheet(
                theme: theme, target: target,
                initialScope: .exercise,
                exerciseText: run.note ?? "",
                setText: run.sets.first(where: { $0.id == target.setId })?.note ?? "",
                history: noteHistory,
                onSave: { scope, text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let value: String? = trimmed.isEmpty ? nil : trimmed
                    switch scope {
                    case .exercise: session.setExerciseNote(exercise: target.id, text: value)
                    case .set: session.setSetNote(exercise: target.id, set: target.setId, text: value)
                    }
                    noteTarget = nil
                },
                onClose: { noteTarget = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.paper)
            .preferredColorScheme(.light)
        }
    }

    /// The rest-editor sheet content, shared by the two presenters (main body + inside the focus cover).
    @ViewBuilder private func restEditorSheet(_ edit: RestEdit) -> some View {
        if session.runs.indices.contains(edit.id) {
            let run = session.runs[edit.id]
            let si = edit.setIndex
            let current: RestConfig = (si.flatMap { run.sets.indices.contains($0) ? run.sets[$0].rest : nil }) ?? run.restConfig
            RestEditorScreen(
                theme: theme, exerciseName: run.name,
                setNumber: si.map { $0 + 1 },
                current: current,
                persistsToRoutine: session.routineId != nil,
                restingHR: restingBaseline, maxHR: profileMaxHR,
                defaultApplyToAll: si == nil,
                closeAsDismiss: true,   // FER-831: presented as a .sheet here → close with ✕, not a back chevron
                onCancel: { restEdit = nil },
                onApply: { config, applyToAll, saveToRoutine in
                    applyRestEdit(ei: edit.id, si: si, config: config, applyToAll: applyToAll, saveToRoutine: saveToRoutine)
                    restEdit = nil
                }
            )
            .preferredColorScheme(.light)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(theme.paper)
        }
    }

    private static func indices(_ ref: CellRef) -> (Int, Int) {
        switch ref { case let .weight(e, s): return (e, s); case let .reps(e, s): return (e, s) }
    }

    // MARK: _LiveHead (FER-929 — replaces the old `sessionHeader`: nav + title + live counters)

    private var liveHead: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            // Nav row: minimize «‹» (session stays alive, the pill re-opens it) · live/paused pulse.
            HStack(spacing: 10) {
                Button { model.strengthSheetPresented = false } label: {
                    StrandIcon.back.image
                        .font(StrandFont.glyph(.lead, weight: .semibold)).foregroundStyle(theme.ink)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Minimize session"))
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    // Canvas pass 2026-07-15: recording-red and STILL — a state lamp, not a heartbeat
                    // (the pulsing ember dot read as «loading»; owner call).
                    Circle().fill(session.paused ? theme.inkDim : theme.critical)
                        .frame(width: 8, height: 8)
                    Text(session.paused ? "Paused" : "In progress")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.leading, -10)   // pull the 44pt chevron target back to the 24pt margin edge

            // Title, underlined solid `ink` (not the dotted neutral rule reserved for table values).
            // Canvas pass 2026-07-15: sin subrayado — el peso de la tipografía basta (owner call).
            // FER-952 (A2): the overline ABOVE the title retired — the title gets the full width and
            // its meta rides BELOW as its own line (family dot · exercises · sets · done).
            // FER-952: same title voice as the editor (Grotesk screen title) — the two screens are
            // one instrument in two moments.
            Text(isEmptyAdHoc ? String(localized: "Quick strength") : session.routineName)
                .font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking)
                .foregroundStyle(theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)

            if !isEmptyAdHoc {
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle().fill(sessionRegion.tint(theme)).frame(width: 8, height: 8)
                        if let word = sessionRegionWord { Text(word) }
                    }
                    Text("\(session.activeExercises.count) exercises · \(sessionSetsTotal) sets · \(session.doneCount) done")
                        .monospacedDigit()
                }
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)   // the progress bar's a11y value already tells this story
            }

            // Metrics: clock (dims + freezes while paused, FER-823) · BPM (strap-only, never «♥ --») ·
            // done/total · Spacer · Pausa/Reanuda + Terminar (or Discard for an empty ad-hoc session).
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                    let elapsed = session.elapsedSeconds(now: ctx.date)
                    Text(Self.clock(elapsed))
                        .font(InstrumentoType.groteskSessionClockInline)
                        .tracking(InstrumentoType.groteskSessionClockTracking)
                        .foregroundStyle(session.paused ? theme.inkTertiary : theme.ink)
                        // r22: los dígitos RUEDAN en vez de parpadear — misma voz que el descanso.
                        .contentTransition(.numericText())
                        .animation(.default, value: elapsed)
                        .accessibilityLabel(Text(session.paused ? "Paused at \(Self.clock(elapsed))"
                                                                 : "Elapsed \(Self.clock(elapsed))"))
                        // r20 (auditoría UX #3): el trait le dice a VoiceOver que NO re-anuncie
                        // cada tick — el usuario lo consulta, el reloj no lo interrumpe.
                        .accessibilityAddTraits(.updatesFrequently)
                }
                // BPM fused to the clock — the app's one always-on pulse. Hidden (not dashed) with no strap.
                PulseReader(model.live.pulse) { p in
                    if let bpm = p.smoothedBpm {
                        HStack(spacing: 6) {
                            BpmPulseDot(color: theme.dataHeart, animated: !reduceMotion)
                            // r26 (owner): valor VIVO → Grotesk tabular, como todo dato medido.
                            Text("\(bpm)").font(InstrumentoType.groteskNumber(12, weight: .medium)).foregroundStyle(theme.dataHeart)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text("Heart rate \(bpm)"))
                    }
                }
                // r20 (auditoría UX #6a): el progreso estaba por TRIPLICADO (texto + filete + barra
                // inferior) — fuera el textual; el filete de abajo y los contadores ya lo cuentan.
                Spacer(minLength: 8)
                headActionButtons
            }

            // Per-exercise progress, a 3px filete (FER-823: no hue while paused). No plan in ad-hoc.
            if !isEmptyAdHoc {
                SessionProgressBar(segments: progressSegments,
                                   hue: session.paused ? theme.inkDim : theme.dataStrain,
                                   track: theme.hairline, height: 3)
                    // anim r7: el llenado del segmento se anima al palomear (antes saltaba).
                    .animation(StrandMotion.gentle, value: session.doneCount)
                    .accessibilityLabel(Text("Session progress"))
                    .accessibilityValue(Text("\(session.doneCount) of \(sessionSetsTotal) sets"))
            }

            // The Apple Watch mirror status (FER-742) — drawn ONLY when the watch fails.
            watchStatusLine
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(theme.paper)
        // Canvas pass 2026-07-15: the bottom hairline under the progress bar is gone — the whitespace
        // and the rail thread separate head from list on their own (owner call, punto 6).
    }

    /// The session's movement region (push/pull/legs), classified from its runs' exercises — the same
    /// single-source rule every routine surface uses (FER-898). Feeds the header's meta dot (A2).
    private var sessionRegion: RoutineRegion? {
        let per = session.runs.map { run in
            ExerciseCatalog.all.first(where: { $0.id == run.exerciseId })?.primaryMuscles ?? []
        }
        return RoutineClassifier.classify(primaryMusclesPerExercise: per)
    }

    /// The region as a quiet word next to the dot («push» / «pull» / «legs» / «full body»).
    private var sessionRegionWord: LocalizedStringKey? {
        switch sessionRegion {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .fullBody: return "Full body"
        case nil: return nil
        }
    }

    /// r21 (deuda front): los botones-cápsula del header salen de UNA fábrica — misma gramática
    /// (surface + hairlineStrong), solo cambia el contenido. r24 (owner): altura FIJA en vez de
    /// padding vertical — Pausar (SF subhead) y Terminar (Grotesk) tienen métricas de fuente
    /// distintas y sus cápsulas salían de tamaños diferentes.
    private func headerCapsule<Content: View>(action: @escaping () -> Void,
                                              @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// The header's right-side action(s), FER-823: paused → «Resume» is the primary action (finish after
    /// resuming); running with sets → a pause toggle sits left of Finish; an empty ad-hoc session only
    /// offers Discard. Unchanged behavior from the pre-FER-929 `sessionHeader` — only its container moved.
    @ViewBuilder private var headActionButtons: some View {
        if session.paused {
            headerCapsule(action: { model.resumeStrengthSessionFromPause() }) {
                Label("Resume", systemImage: "play.fill").labelStyle(.titleAndIcon)
                    .font(InstrumentoType.grotesk(15, weight: .semibold)).foregroundStyle(theme.ink)
            }
            .accessibilityLabel(Text("Resume session"))
        } else if !isEmptyAdHoc {
            // Canvas pass 2026-07-15: Pausa dresses like Terminar's sibling — same capsule grammar.
            headerCapsule(action: { model.pauseStrengthSession() }) {
                // r27 (owner): solo las dos barritas — el símbolo universal basta; la palabra la
                // lleva VoiceOver.
                Image(systemName: "pause.fill")
                    .font(StrandFont.glyph(.inline, weight: .semibold)).foregroundStyle(theme.ink)
            }
            .accessibilityLabel(Text("Pause session"))
            // r20 (auditoría UX #6d + owner): Terminar-y-guardar es el acto constructivo esperado —
            // vestirlo de alarma desensibilizaba el rojo del Descartar real. Tinta, voz Grotesk.
            headerCapsule(action: { finishTapped() }) {
                Text("Finish").font(InstrumentoType.grotesk(15, weight: .semibold)).foregroundStyle(theme.ink)
            }
            .accessibilityLabel(Text("Finish workout"))
        } else {
            headerCapsule(action: { discardEmptySession() }) {
                Text("Discard").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
            .accessibilityLabel(Text("Discard workout"))
        }
    }

    // MARK: _StatsBar (FER-929 — fixed bottom bar; the keypad takes this slot instead while a cell is active)

    private var statsBar: some View {
        // r20 (owner): de regreso a la pila original — «Modo foco» arriba, contadores centrados
        // abajo (la línea-de-recibo de r18 no gustó). Lo que sí se queda de r18/r19: el icono
        // correcto (expandir a pantalla completa, validado vs HIG) — ahora en un mini-troquel de
        // papel que le da cuerpo sin volverlo cápsula gritona — y el target de 44pt.
        VStack(spacing: 14) {
            if !isEmptyAdHoc && session.summary == nil {
                // r21 (owner): la cápsula del handoff — icono + «Modo foco» juntos dentro de UNA
                // cápsula surface con hairline, texto semibold en tinta.
                Button { focusMode = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.inset.filled")
                            .font(StrandFont.glyph(.chevron, weight: .semibold))
                        Text("Focus mode").font(StrandFont.subhead.weight(.semibold))
                    }
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Focus mode"))
                .accessibilityHint(Text("Opens a full-screen set logger"))
            }
            // kg · series · (kcal only with a streaming strap, never dashes) — same sources as before,
            // now with the handoff's typographic contrast: Grotesk-bold values, light labels.
            counterLineStyled
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(counterLine))
        }
        .frame(maxWidth: .infinity)
        // r22 (simetría): 8/10 a ojo → rowVPad parejo arriba y abajo.
        .padding(.vertical, CenitMetrics.rowVPad)
        .background(theme.paper)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    // MARK: - Focus mode (full-screen cover · additive entry from the inline list)

    /// Full-screen capture/rest surface. Closing returns to the inline table; session state is unchanged.
    /// FER-934: while resting, the whole surface flips to the `dataRecovery` green with crema ink
    /// (handoff `_RestFull`); the capture variant keeps the paper background untouched.
    private var focusModeView: some View {
        let resting = session.phase == .resting
        return VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            // Canvas pass 2026-07-15 (handoff `_FocusScreen`): capturing shows «× · MODO FOCO · SERIE
            // N DE M · reloj»; resting keeps FER-934's toggle-left/×-right green arrangement.
            HStack(spacing: 12) {
                if resting {
                    focusRestModeToggle
                    Spacer(minLength: 0)
                    focusCloseButton(onGreen: true)
                } else {
                    focusCloseButton(onGreen: false)
                    if let run = session.current {
                        Text("FOCUS MODE · SET \(min(run.currentSet + 1, run.sets.count)) OF \(run.sets.count)")
                            .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                        Text(Self.clock(session.elapsedSeconds(now: ctx.date)))
                            .font(InstrumentoType.groteskNumber(15)).monospacedDigit()
                            .foregroundStyle(theme.inkSecondary)
                    }
                    .accessibilityHidden(true)
                }
            }

            if resting {
                focusRestPhase
            } else {
                focusCapturePhase
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, CenitMetrics.sectionGap)
        .padding(.bottom, CenitMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background((resting ? theme.dataRecovery : theme.paper).ignoresSafeArea())
        .instrumentoTheme(theme)
        .preferredColorScheme(.light)
    }

    @ViewBuilder private var focusCapturePhase: some View {
        if let run = session.current {
            // Canvas pass 2026-07-15: rebuilt to the owner's handoff capture — centered thumb + name +
            // «la última vez», KG/REPS stepper cards, the big ink «✓ Registrar serie» pill, the quick
            // links row, and a prev/next exercise bar at the bottom.
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                Spacer(minLength: 0)
                // Canvas pass 2026-07-15: bigger hero (56pt thumb + 24pt Grotesk title), the row
                // left-aligned (long names get the room), the whole block vertically centered.
                HStack(spacing: 14) {
                    SessionRunThumb(exerciseId: run.exerciseId, side: 56)
                        // r25 (owner): mismo marco de familia que la Biblioteca y la tarjeta activa.
                        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                            .strokeBorder(categoryTint(run), lineWidth: 2))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(run.name).font(InstrumentoType.grotesk(24, weight: .semibold))
                            .foregroundStyle(theme.ink)
                            .lineLimit(2).minimumScaleFactor(0.7)
                        if let prev = previousText(run) {
                            Text(String(localized: "last time ") + prev)
                                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                // r20/r28 (owner): el foco SIEMPRE narra la superserie — quien no es el último lleva
                // la leyenda «sin descanso entre A1 y A2»; el último (que sí descansa) lleva el
                // sello «SUPERSERIE · A2» en vez de un copy que no le aplica.
                focusSupersetCaption(session.currentIndex)

                switch run.type {
                case .weightReps:
                    HStack(alignment: .top, spacing: 12) {
                        focusKgCard
                        focusRepsCard(run)
                    }
                    focusRegisterButton
                    focusQuickLinks(run)
                case .bodyweight:
                    focusRepsHero
                    focusAddedWeightRow
                    focusRegisterButton
                    focusQuickLinks(run)
                case .time:
                    focusTimeControls
                case .distance:
                    focusDistanceControls
                }
                Spacer(minLength: 0)
                focusPrevNextBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                // r20 (owner): voz Grotesk también aquí — mismo cierre que completePhase.
                Text("All done").font(InstrumentoType.grotesk(24, weight: .semibold)).foregroundStyle(theme.ink)
                Text("No pending set. Close focus mode to finish from the list.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var focusWeightHero: some View {
        HStack {
            stepper(system: "minus") { session.bumpWeight(byKg: -weightStepKg) }
                .accessibilityLabel(Text("Decrease weight"))
            Spacer(minLength: CenitMetrics.gap)
            VStack(spacing: 0) {
                Text(plateNumber(displayWeight(session.currentSet?.weightKg ?? 0)))
                    .instrumentoHero(76).foregroundStyle(theme.dataStrain)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                Text(UnitFormatter.massUnit(units)).font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: CenitMetrics.gap)
            stepper(system: "plus") { session.bumpWeight(byKg: weightStepKg) }
                .accessibilityLabel(Text("Increase weight"))
        }
        .accessibilityElement(children: .contain)
    }

    private var focusRepsHero: some View {
        HStack {
            stepper(system: "minus") { session.bumpReps(-1) }
                .accessibilityLabel(Text("Decrease reps"))
            Spacer(minLength: CenitMetrics.gap)
            VStack(spacing: 0) {
                Text("\(session.currentSet?.reps ?? 0)")
                    .instrumentoHero(76).foregroundStyle(theme.dataStrain)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                Text("reps").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: CenitMetrics.gap)
            stepper(system: "plus") { session.bumpReps(1) }
                .accessibilityLabel(Text("Increase reps"))
        }
        .accessibilityElement(children: .contain)
    }

    private var focusRepsRow: some View {
        HStack {
            Text("Reps").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
            Spacer()
            HStack(spacing: CenitMetrics.sectionGap) {
                stepper(system: "minus", size: 34) { session.bumpReps(-1) }
                    .accessibilityLabel(Text("Decrease reps"))
                Text("\(session.currentSet?.reps ?? 0)")
                    // r26: valor vivo → Grotesk tabular.
                    .font(InstrumentoType.groteskNumber(22, weight: .medium)).foregroundStyle(theme.ink)
                    .frame(minWidth: 34)
                stepper(system: "plus", size: 34) { session.bumpReps(1) }
                    .accessibilityLabel(Text("Increase reps"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var focusAddedWeightRow: some View {
        let kg = session.currentSet?.weightKg ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Added weight").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                Text(kg > 0 ? "optional" : "optional · bodyweight only")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Spacer()
            HStack(spacing: CenitMetrics.sectionGap) {
                stepper(system: "minus", size: 34) { session.bumpWeight(byKg: -weightStepKg) }
                    .accessibilityLabel(Text("Decrease added weight"))
                Text("+\(plateNumber(displayWeight(kg))) \(UnitFormatter.massUnit(units))")
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .font(InstrumentoType.groteskNumber(22, weight: .medium))
                    .foregroundStyle(kg > 0 ? theme.ink : theme.inkTertiary)
                stepper(system: "plus", size: 34) { session.bumpWeight(byKg: weightStepKg) }
                    .accessibilityLabel(Text("Increase added weight"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var focusRegisterButton: some View {
        Button {
            withAnimation(StrandMotion.gentle) {
                registerActiveSet()
            }
        } label: {
            // Canvas pass 2026-07-15: the handoff's big ink capsule.
            Label("Register set", systemImage: "checkmark")
                .font(StrandFont.headline).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(theme.ink, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// The focus close «×» — ink-on-paper while capturing, crema-on-green while resting (FER-934).
    private func focusCloseButton(onGreen: Bool) -> some View {
        Button { focusMode = false } label: {
            StrandIcon.close.image
                .font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(onGreen ? theme.paper : theme.ink)
                .frame(width: 38, height: 38)
                .background(onGreen ? theme.paper.opacity(StrandOpacity.tintFillStrong) : theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(onGreen ? theme.paper.opacity(StrandOpacity.strokeSoft) : theme.hairlineStrong, lineWidth: 1))
                // r19 (auditoría UI): target de 44pt — el círculo visual se queda en 38.
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close focus mode"))
    }

    /// The KG stepper card (extracted so the capture switch stays cheap to type-check).
    private var focusKgCard: some View {
        focusStepperCard(UnitFormatter.massUnit(units).uppercased(),
                         value: plateNumber(displayWeight(session.currentSet?.weightKg ?? 0)),
                         // r19 (auditoría UI): la carga es familia EMBER en toda la sesión — el verde
                         // es recuperación/veredicto y el teclado ya lo reserva para «Siguiente».
                         valueTint: theme.dataStrain,
                         minusLabel: "Decrease weight", plusLabel: "Increase weight",
                         minus: { session.bumpWeight(byKg: -weightStepKg) },
                         plus: { session.bumpWeight(byKg: weightStepKg) }) {
            // r15 (owner): el atajo a discos solo existe en ejercicios de BARRA — en dumbbell/
            // máquina la leyenda queda en el puro paso «±2,5».
            if usesBarbell(session.currentIndex) {
                Button {
                    platesTarget = PlatesTarget(ei: session.currentIndex,
                                                weightKg: session.currentSet?.weightKg ?? 0)
                } label: {
                    // r14: fuera el glifo «⛓» (tofu en Grotesk) — la leyenda queda «±2,5 · discos».
                    Text("±\(plateNumber(displayWeight(weightStepKg))) · " + String(localized: "plates"))
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary).underline()
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            } else {
                Text("±\(plateNumber(displayWeight(weightStepKg)))")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
        }
    }

    /// The REPS stepper card (see `focusKgCard`).
    private func focusRepsCard(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        focusStepperCard(String(localized: "Reps").uppercased(),
                         value: "\(session.currentSet?.reps ?? 0)",
                         valueTint: theme.ink,
                         minusLabel: "Decrease reps", plusLabel: "Increase reps",
                         minus: { session.bumpReps(-1) },
                         plus: { session.bumpReps(1) }) {
            if let lr = run.lastReps {
                Text(String(localized: "target \(lr)"))
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            } else {
                Color.clear.frame(height: 14)
            }
        }
    }

    /// One handoff stepper card: overline unit, −/+ round steps flanking the big Grotesk value, and a
    /// caption slot («±2,5 · discos» / «objetivo N»).
    private func focusStepperCard<Caption: View>(_ overline: String, value: String, valueTint: Color,
                                                 minusLabel: LocalizedStringKey, plusLabel: LocalizedStringKey,
                                                 minus: @escaping () -> Void, plus: @escaping () -> Void,
                                                 @ViewBuilder caption: () -> Caption) -> some View {
        VStack(spacing: 6) {
            Text(overline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            // r23 (owner): spacing y padding ceden ~20pt al numeral — un «102,5» ya no se encoge
            // a letra chica entre los dos cuadros.
            HStack(spacing: 6) {
                focusRoundStep("minus", label: minusLabel, action: minus)
                Text(value).font(InstrumentoType.groteskNumber(32)).monospacedDigit()
                    .foregroundStyle(valueTint).lineLimit(1).minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity)
                focusRoundStep("plus", label: plusLabel, action: plus)
            }
            caption()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 8)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func focusRoundStep(_ system: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        // r14 (owner): pasos de tinta y cuadrados. r23 (owner): un poco MÁS CHICOS (36pt visuales)
        // para cederle ancho al numeral — con cargas de cientos («102,5») el valor es el héroe, no
        // los botones. El toque conserva ~44pt vía contentShape extendido.
        Button(action: action) {
            Image(systemName: system).font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(theme.paper)
                .frame(width: 36, height: 36)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
                .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    /// «♥ Descanso · RPE · ✎ Nota» — the handoff's quiet action row under the register pill; each link
    /// opens the sheet the inline table already uses (rest editor / RPE / note).
    private func focusQuickLinks(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Button { openRestEditor(ei: session.currentIndex, setIndex: run.currentSet) } label: {
                Label("Rest", systemImage: "heart.fill")
                    .font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.dataHrv)
            }
            .buttonStyle(.plain)
            Text(verbatim: "·").font(StrandFont.caption).foregroundStyle(theme.inkDim)
            Button {
                guard run.sets.indices.contains(run.currentSet) else { return }
                let set = run.sets[run.currentSet]
                rpeTarget = RPETarget(id: set.id, runId: run.id, setNumber: run.currentSet + 1,
                                      weightKg: displayWeight(set.weightKg), reps: set.reps, currentRPE: set.rpe)
            } label: {
                Text(verbatim: "RPE").font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.dataEffort)
            }
            .buttonStyle(.plain)
            Text(verbatim: "·").font(StrandFont.caption).foregroundStyle(theme.inkDim)
            Button { openNote(exercise: run, ei: session.currentIndex) } label: {
                Label("Note", systemImage: "pencil")
                    .font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.ink)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    /// «‹ anterior — siguiente ›» bottom bar (handoff): jumps the guided focus to the neighboring
    /// non-skipped exercise, landing on its first pending set.
    @ViewBuilder private var focusPrevNextBar: some View {
        let prev = focusNeighbor(-1)
        let next = focusNeighbor(1)
        if prev != nil || next != nil {
            HStack {
                if let p = prev {
                    Button { focusJump(to: p) } label: {
                        Text("‹ \(session.runs[p].name)").font(StrandFont.subhead)
                            .foregroundStyle(theme.inkSecondary).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 12)
                if let n = next {
                    Button { focusJump(to: n) } label: {
                        Text("\(session.runs[n].name) ›").font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(theme.ink).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
        }
    }

    /// The nearest non-skipped exercise `delta` steps away from the guided focus, if any.
    private func focusNeighbor(_ delta: Int) -> Int? {
        var i = session.currentIndex + delta
        while session.runs.indices.contains(i) {
            if !session.runs[i].skipped { return i }
            i += delta
        }
        return nil
    }

    private func focusJump(to ei: Int) {
        restAnchorEi = nil
        withAnimation(StrandMotion.gentle) {
            session.select(exerciseIndex: ei,
                           setIndex: session.runs[ei].sets.firstIndex { !$0.done } ?? 0)
        }
    }

    /// Time sets: running clock + Start / Stop-and-save. Goal store omitted (not present on the live
    /// sheet after the Foco removal) — plain timer is the simplification.
    @ViewBuilder private var focusTimeControls: some View {
        let running = session.timerStart != nil
        if running {
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                focusTimeReadout(elapsed: session.timerElapsed(now: ctx.date))
            }
        } else {
            focusTimeReadout(elapsed: session.currentSet?.timeS ?? 0)
        }
        Button {
            withAnimation(StrandMotion.gentle) {
                if running {
                    registerActiveSet()
                } else {
                    session.startSetTimer()
                }
            }
        } label: {
            Label(running ? "Stop and save" : "Start",
                  systemImage: running ? "stop.fill" : "play.fill")
                .font(StrandFont.headline).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CenitMetrics.sectionGap)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func focusTimeReadout(elapsed: Int) -> some View {
        Text(Self.clock(elapsed))
            .instrumentoHero(76).monospacedDigit()
            .foregroundStyle(elapsed > 0 ? theme.dataStrain : theme.inkTertiary)
            .minimumScaleFactor(0.5).lineLimit(1)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text("Timing, \(elapsed) seconds"))
    }

    @ViewBuilder private var focusDistanceControls: some View {
        let dist = session.currentSet?.distanceM ?? 0
        let running = session.timerStart != nil
        VStack(spacing: CenitMetrics.gap) {
            HStack {
                stepper(system: "minus") { session.bumpDistance(byMeters: -distanceStepM) }
                    .accessibilityLabel(Text("Decrease distance"))
                Spacer(minLength: CenitMetrics.gap)
                VStack(spacing: 0) {
                    Text(distanceNumber(dist))
                        .instrumentoHero(76).foregroundStyle(theme.dataStrain)
                        .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    Text(imperial ? "mi" : "km").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: CenitMetrics.gap)
                stepper(system: "plus") { session.bumpDistance(byMeters: distanceStepM) }
                    .accessibilityLabel(Text("Increase distance"))
            }
            if running {
                TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                    Text(Self.clock(session.timerElapsed(now: ctx.date)))
                        .font(InstrumentoType.groteskNumber(22, weight: .medium)).foregroundStyle(theme.ink)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                }
            } else {
                Text(Self.clock(session.currentSet?.timeS ?? 0))
                    .font(StrandFont.title2).monospacedDigit()
                    .foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: CenitMetrics.gap) {
                Button {
                    withAnimation(StrandMotion.gentle) {
                        running ? session.stopSetTimer() : session.startSetTimer()
                    }
                } label: {
                    Text(running ? "Stop" : "Start")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CenitMetrics.gap)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                            .strokeBorder(theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(running ? "Stop the timer" : "Start the timer"))
            }
        }
        let captured = dist > 0 || (session.currentSet?.timeS ?? 0) > 0 || running
        Button {
            withAnimation(StrandMotion.gentle) {
                registerActiveSet()
            }
        } label: {
            Label("Register set", systemImage: "checkmark")
                .font(StrandFont.headline).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CenitMetrics.sectionGap)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!captured)
        .opacity(captured ? 1 : StrandOpacity.dim)
    }

    /// Rest phase scaled to full-screen, fully dressed in `dataRecovery` green + crema ink (FER-934,
    /// handoff `_RestFull`). Reuses the inline card's readiness/time evaluation patterns; only the
    /// vestment changes, the rest engine (`extendRest`/`skipRest`/`computeRestTarget`) is untouched.
    private var focusRestPhase: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            // Canvas pass 2026-07-15: the exercise's thumbnail anchors the caption — you know whose
            // rest this is at a glance, same as the list.
            HStack(spacing: 10) {
                if session.runs.indices.contains(accordionIndex) {
                    SessionRunThumb(exerciseId: session.runs[accordionIndex].exerciseId, side: 28)
                }
                Text(focusRestCaption).font(StrandFont.subhead).foregroundStyle(theme.paper)
            }

            if focusRestWantsHR, let started = session.restStartedAt {
                PulseReader(model.live.pulse) { p in
                    TimelineView(.periodic(from: started, by: 1)) { ctx in
                        // r20 (auditoría UX #1): mismo congelamiento que la tarjeta inline.
                        let tick = session.paused ? (session.pausedAt ?? ctx.date) : ctx.date
                        let elapsed = max(0, Int(tick.timeIntervalSince(started)))
                        let v = RestReadinessRule.evaluate(
                            currentHR: p.smoothedBpm, worn: model.live.worn, restingHR: restingBaseline,
                            elapsedS: elapsed, targetHR: session.currentRestTarget)
                        let noSignal = v.state == .noSignal
                        if !noSignal {
                            focusRestHRHero(elapsed: elapsed, readiness: v)
                        } else {
                            focusRestTimeHero(end: session.restEndsAt, now: tick, noStrapFallback: noSignal)
                        }
                    }
                }
            } else if let end = session.restEndsAt, let started = session.restStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    focusRestTimeHero(end: end,
                                      now: session.paused ? (session.pausedAt ?? ctx.date) : ctx.date,
                                      noStrapFallback: false)
                }
            }

            HStack(spacing: CenitMetrics.gap) {
                focusRestAdjust("−15") { session.extendRest(byseconds: -15) }
                Button { withAnimation(StrandMotion.gentle) { session.skipRest() } } label: {
                    Text("Skip")
                        .font(StrandFont.headline).foregroundStyle(theme.dataRecovery)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CenitMetrics.sectionGap)
                        .background(theme.paper, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Skip rest"))
                focusRestAdjust("+15") { session.extendRest(byseconds: 15) }
            }

            Spacer(minLength: 0)   // r6: «SIGUE» baja hasta el fondo, con su margen del contenedor
            focusRestNextCard
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// «<ejercicio> · serie N ✓» — the just-completed set, for orientation while the screen is all green.
    private var focusRestCaption: String {
        guard session.runs.indices.contains(accordionIndex) else { return String(localized: "Rest") }
        let run = session.runs[accordionIndex]
        let doneIndex = run.currentSet - 1
        guard run.sets.indices.contains(doneIndex) else { return run.name }
        let n = run.sets.prefix(doneIndex + 1).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
        return "\(run.name) · " + String(localized: "set \(n)") + " ✓"
    }

    /// Tiempo/FC segmented toggle (FER-934 §3.2) — only shown when the active rest actually resolved a
    /// heart-rate target; a fixed-time rest has nothing to switch to. Defaults to FC (`nil` ≙ true).
    @ViewBuilder private var focusRestModeToggle: some View {
        // r7: el toggle vive SIEMPRE en el descanso (handoff) — en descansos por tiempo arranca en
        // «Tiempo»; la pestaña FC muestra el pulso en vivo (y cae a tiempo si no hay señal).
        Group {
            let showsHR = focusRestShowsHR ?? (session.currentRestMode == .heartRate)
            HStack(spacing: 2) {
                focusRestModeTab(String(localized: "Time"), systemImage: "timer", active: !showsHR) {
                    focusRestShowsHR = false
                }
                focusRestModeTab(String(localized: "HR"), systemImage: "heart.fill", active: showsHR) {
                    focusRestShowsHR = true
                }
            }
            .padding(3)
            // r6: rectangular como el handoff — misma gramática que el selector global.
            .background(theme.paper.opacity(StrandOpacity.tintFillStrong),
                        in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
        }
    }

    /// El héroe del descanso respeta el toggle también en descansos POR TIEMPO (r7): si el usuario
    /// pide FC y hay pulso, lo enseña aunque el descanso sea fijo.
    private var focusRestWantsHR: Bool { focusRestShowsHR ?? (session.currentRestMode == .heartRate) }

    private func focusRestModeTab(_ label: String, systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(StrandFont.caption).fontWeight(.semibold)
                .foregroundStyle(active ? theme.dataRecovery : theme.paper)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? theme.paper : Color.clear,
                            in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func focusRestHRHero(elapsed: Int, readiness v: RestReadiness) -> some View {
        let bpm = model.bpm ?? 0
        let target = session.currentRestTarget
        let ready = v.ready
        return VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            if ready {
                Text("Ready")
                    .instrumentoHero(76).foregroundStyle(theme.paper)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.gap) {
                    Text("\(bpm)").instrumentoHero(100).monospacedDigit().foregroundStyle(theme.paper)
                    Text("bpm").font(StrandFont.headline).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
                }
            }
            if let target, !ready {
                (Text(String(localized: "dropping toward "))
                 + Text("\(target) bpm").bold()
                 + Text(" · " + String(localized: "the strap will buzz")))
                    .font(StrandFont.caption).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
            } else if let toReady = v.bpmToReady, !ready {
                Text("\(toReady) bpm to ready")
                    .font(StrandFont.subhead).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
            }
            focusRestHRTrack(bpm: bpm, target: target)
            Text("\(Self.clock(elapsed)) " + String(localized: "of rest · the strap buzzes on arrival"))
                .font(StrandFont.caption).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func focusRestTimeHero(end: Date?, now: Date, noStrapFallback: Bool) -> some View {
        let cappedEnd = noStrapFallback
            ? min(end ?? now, (session.restStartedAt ?? now).addingTimeInterval(300))
            : end
        let remaining = cappedEnd.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) } ?? 0
        let total = max(1, cappedEnd.map { Int($0.timeIntervalSince(session.restStartedAt ?? now)) } ?? remaining)
        return VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            ZStack {
                Circle().stroke(theme.paper.opacity(0.22), lineWidth: 10)  // token-exempt: pista sin llenar del anillo de progreso (geometría, FER-934)
                Circle()
                    .trim(from: 0, to: max(0, min(1, Double(remaining) / Double(total))))
                    .stroke(theme.paper, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // r22: barrido CONTINUO — el anillo drena en lineal de 1 s en vez de brincar
                    // por segundo (ReduceMotion lo respeta el sistema al aplanar la transacción).
                    .animation(.linear(duration: 1), value: remaining)
                VStack(spacing: 2) {
                    Text(Self.clock(remaining))
                        .instrumentoHero(72).monospacedDigit().foregroundStyle(theme.paper)
                        .contentTransition(.numericText())
                    Text(String(localized: "of \(total) s"))
                        .font(StrandFont.caption).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
                }
            }
            .frame(width: 232, height: 232)
            .frame(maxWidth: .infinity)
            Text(noStrapFallback ? String(localized: "No strap signal: resting by time, 5 min cap")
                                  : String(localized: "Rings and buzzes when it ends."))
                .font(StrandFont.caption).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // r20 (auditoría UX #3): hitos, no ticks.
        .accessibilityLabel(Text(restA11yPhrase(remaining: remaining)))
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Focus-mode FC track (FER-934): crema-on-green variant of `restHRTrack`, kept separate so the
    /// shared inline-card track (dataHeart→dataRecovery gradient) is untouched.
    private func focusRestHRTrack(bpm: Int, target: Int?) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let hi = Double((target ?? bpm) + 40)
            let lo = Double(target ?? bpm)
            let frac = hi > lo ? max(0, min(1, (hi - Double(bpm)) / (hi - lo))) : 1
            ZStack(alignment: .leading) {
                Capsule().fill(theme.paper.opacity(0.22))  // token-exempt: pista sin llenar de la barra de FC (geometría, FER-934)
                Capsule().fill(theme.paper).frame(width: w * frac)
                Rectangle().fill(theme.paper).frame(width: 2, height: 14)
                    .offset(x: w - 1)
            }
        }
        .frame(height: 6)
    }

    private func focusRestAdjust(_ label: String, _ action: @escaping () -> Void) -> some View {
        // r29 (owner): centrado ÓPTICO — el signo (glifo proporcional con su propio side-bearing)
        // descentraba el conjunto dentro del frame; ahora vive en un riel fijo de 12pt y el «15»
        // queda con geometría IDÉNTICA en ambos botones.
        let sign = String(label.prefix(1))
        let digits = String(label.dropFirst())
        return Button(action: action) {
            HStack(spacing: 0) {
                Text(sign).font(StrandFont.headline).frame(width: 12)
                Text(digits).font(StrandFont.headline).monospacedDigit()
            }
            .foregroundStyle(theme.paper)
            .frame(width: 56)
            .padding(.vertical, CenitMetrics.sectionGap)
            .background(theme.paper.opacity(StrandOpacity.tintFillStrong), in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.paper.opacity(StrandOpacity.strokeSoft), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label == "−15" ? "Subtract 15 seconds" : "Add 15 seconds"))
    }

    /// «SIGUE» card (FER-934 §3.6): the next real step, derived the same way the inline UI derives it —
    /// `registerCurrentSet` already advanced `session.current`/`currentSet` before starting this rest, so
    /// it reflects either the next set of the active exercise or the next exercise once this one is done.
    @ViewBuilder private var focusRestNextCard: some View {
        if let run = session.current {
            let si = run.currentSet
            let n = run.sets.prefix(si + 1).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
            let load = run.sets.indices.contains(si) ? run.sets[si].weightKg : nil
            HStack(spacing: 12) {
                // Canvas pass 2026-07-15: the next exercise's thumbnail rides the SIGUE card.
                SessionRunThumb(exerciseId: run.exerciseId, side: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next").instrumentoOverline().foregroundStyle(theme.paper)
                    if let load, load > 0 {
                        Text("\(run.name) · " + String(localized: "set \(n)") + " · \(massText(load))")
                            .font(StrandFont.subhead).foregroundStyle(theme.paper)
                    } else {
                        Text("\(run.name) · " + String(localized: "set \(n)"))
                            .font(StrandFont.subhead).foregroundStyle(theme.paper)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(theme.paper.opacity(StrandOpacity.tintFillStrong), in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        }
    }

    /// One progress segment per non-skipped exercise: width ∝ its set count, fill = fraction of its sets done.
    private var progressSegments: [SessionProgressBar.Segment] {
        session.runs.filter { !$0.skipped }.map { run in
            let total = max(run.sets.count, 1)
            let done = run.sets.filter(\.done).count
            // r7 (owner): cada segmento en el hue de SU ejercicio (familia push/pull/legs).
            return .init(sets: total, done: Double(done) / Double(total),
                         tint: session.paused ? nil : categoryTint(run))
        }
    }

    /// Total planned sets across non-skipped exercises (the progress denominator).
    private var sessionSetsTotal: Int {
        session.runs.filter { !$0.skipped }.reduce(0) { $0 + $1.sets.count }
    }

    /// «2.480 kg · 8/17 series · ~312 kcal» — the kcal clause is dropped entirely when there's no strap
    /// HR (no dashes, no zero): the receipt is where the estimate lands.
    private var counterLine: String {
        var parts = ["\(massText(sessionVolumeKg))",
                     "\(session.doneCount)/\(sessionSetsTotal) " + String(localized: "series")]
        if let kcal = liveKcal { parts.append("~\(kcal) kcal") }
        return parts.joined(separator: " · ")
    }

    /// The counter line with the handoff's typographic contrast (canvas pass 2026-07-15): values in
    /// Grotesk bold, labels/separators in light secondary ink. An HStack of small Texts (not one
    /// concatenated Text) so the type-checker stays fast. Same data as `counterLine` (the a11y read).
    private var counterLineStyled: some View {
        let done = "\(session.doneCount)/\(sessionSetsTotal)"
        let kcal = liveKcal
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            counterValue(massText(sessionVolumeKg))
            counterDot
            counterValue(done)
            counterLabel(String(localized: "series"))
            if let kcal {
                counterDot
                counterValue("~\(kcal)")
                counterLabel("kcal")
            }
        }
    }

    private func counterValue(_ s: String) -> some View {
        // r20 (auditoría UX #6f): también los contadores escalan con Dynamic Type intermedio.
        // r22: y ruedan al cambiar (numericText) — el recibo respira al palomear.
        Text(s).font(InstrumentoType.groteskNumber(15, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(theme.ink)
            .contentTransition(.numericText())
            .animation(StrandMotion.gentle, value: s)
    }
    private func counterLabel(_ s: String) -> some View {
        Text(s).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
    }
    private var counterDot: some View {
        Text(verbatim: "·").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
    }

    /// Live energy estimate (kcal) from the strap samples captured so far — nil (so the clause is hidden)
    /// until the strap has streamed HR. Same Keytel entry point as the receipt/persist path (FER-715).
    private var liveKcal: Int? {
        let samples = session.hrSamples
        guard samples.count >= Calories.strengthEnergyMinSamples else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let profile = UserProfile(weightKg: model.profile.weightKg, heightCm: model.profile.heightCm,
                                  age: Double(model.profile.age), sex: model.profile.sex)
        let kcal = Calories.estimateStrengthEnergy(
            hrSamples: samples, durationSeconds: Double(max(0, now - session.startTs)),
            profile: profile, hrMax: Double(model.profile.hrMax))
        return Int(kcal.rounded())
    }

    /// Done weight×reps volume across non-skipped exercises (bodyweight adds lastre×reps; time/distance 0).
    private var sessionVolumeKg: Double {
        session.runs.filter { !$0.skipped }.reduce(0.0) { acc, run in
            guard run.type == .weightReps || run.type == .bodyweight else { return acc }
            return acc + run.sets.filter(\.done).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
        }
    }

    /// Today's recovery score (nil while calibrating) — feeds the muscle-fatigue readiness map.
    private var recovery: Double? { model.repo.today?.recovery }

    /// The Apple Watch mirror line (FER-742): «Reloj grabando» when the watch confirms; «El reloj no
    /// respondió» + «Reintentar» on a first miss; «Sin reloj esta sesión» once the retry is spent. Nothing
    /// while the mirror is off, absent, or still connecting — the tertiary ink keeps it out of the way.
    @ViewBuilder
    private var watchStatusLine: some View {
        switch model.watchSessionStatus {
        case .notResponding:
            watchLine("applewatch.slash", "The watch didn't respond", retry: true)
        case .unavailable:
            watchLine("applewatch.slash", "No watch this session", retry: false)
        case .recording, .inactive, .waiting:
            // v21: normal states (including a healthy «recording» mirror) cost no row — silent unless it fails.
            EmptyView()
        }
    }

    private func watchLine(_ icon: String, _ text: LocalizedStringKey, retry: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text(text).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            if retry {
                Button { model.retryWatchMirroring() } label: {
                    Text("Retry").font(StrandFont.caption).fontWeight(.medium).foregroundStyle(theme.ink)
                }
                .buttonStyle(.plain).padding(.leading, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// FER-969 (X-01): the final save failed — the workout is still on this phone (FER-798 snapshot);
    /// say so and offer retry instead of pretending the receipt is coming.
    private var saveErrorBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(StrandFont.glyph(.chevron)).foregroundStyle(theme.critical)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn't save the workout. Try again.")
                    .font(StrandFont.caption).fontWeight(.medium).foregroundStyle(theme.ink)
                Text("Your sets are safe on this phone.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
            Spacer(minLength: 8)
            Button { model.retryStrengthSave() } label: {
                Text("Retry").font(StrandFont.caption).fontWeight(.medium).foregroundStyle(theme.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.vertical, 10)
        .background(theme.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Exercise header + inline rows

    /// One exercise's header: a type overline (for non-weight×reps), the name, and the column header.
    /// Grouped by whitespace + hairlines — a registration sheet, not a grid.
    private func exerciseHeader(_ run: StrengthSessionModel.ExerciseRun, ei: Int, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            // r7: alignment .top — con nombres largos (2-3 líneas) el HStack crecía y el thumb se
            // centraba más abajo, dejando la bolita (fija a 34pt) descentrada. Anclado arriba, el
            // centro del thumb SIEMPRE queda a 12+22=34, donde vive el punto.
            HStack(alignment: .top, spacing: 12) {
                SessionRunThumb(exerciseId: run.exerciseId)   // baked still fills the FER-751 slot
                    // r25 (owner): el marco de 2pt en el hue de familia — la MISMA receta de la
                    // Biblioteca (handoff), así el thumb dice su familia igual en todo el app.
                    .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                        .strokeBorder(categoryTint(run), lineWidth: 2))
                    // r16: el NACIMIENTO del hilo también se ancla al thumb — un borrador de papel
                    // tapa el hilo desde arriba de la tarjeta hasta el CENTRO del thumb (donde vive
                    // la bolita); el anillo remata la orilla. La constante «34 desde la tarjeta» de
                    // r14 mentía: la celda trae holgura y el hueco bolita→línea medía ~17pt.
                    .overlay(alignment: .topLeading) {
                        if showRail, ei == firstRailIndex {
                            Rectangle().fill(theme.paper)
                                .frame(width: 6, height: 60)
                                .offset(x: -36, y: 22 - 60)
                                .allowsHitTesting(false)
                        }
                    }
                    // r14: la bolita es OVERLAY del thumbnail — centro vertical por ALINEACIÓN
                    // (no hay constante que pueda derivar) y en X aterriza sobre el hilo del
                    // mismo árbol de la tarjeta: 14 de padding + 26 de canaleta − 7 del carril
                    // = 33 a la izquierda del thumb (−8.5 corre el anillo a su centro).
                    .overlay(alignment: .leading) {
                        if showRail {
                            ZStack {
                                Circle().fill(theme.paper).frame(width: 17, height: 17)
                                Circle().fill(categoryTint(run)).frame(width: 11, height: 11)
                            }
                            .offset(x: -33 - 8.5)
                            .allowsHitTesting(false)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                supersetTag(ei)
                if run.type != .weightReps {
                    Text(typeWord(run.type)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        .accessibilityHidden(true)
                }
                // Tap the name → the exercise's Detail (how-to, trend, records) as a sheet (FER-538).
                Button { openDetail(run) } label: {
                    // r8b (owner): sin chevron junto al nombre — el toque al nombre sigue abriendo el
                    // detalle; la flecha era ruido.
                    Text(run.name).font(StrandFont.headline).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(run.name))
                .accessibilityHint(Text("View exercise detail"))
                }
                exerciseMenuButton(ei: ei, run: run)
                reorderHandle(ei: ei, run: run)
            }
            // r20 (owner, UX #4): el long-press de mover se retira también del header — un solo
            // gesto por tarjeta (long-press = quitar serie); mover entra por «≡» o por el menú.
            // FER-E · 2b: the earned raise, named where you train. «↑ hoy 102,5 · por qué» toggles the
            // arithmetic card; green because the raise IS the datum.
            if let raise = run.proposedRaise {
                raiseLine(raise, ei: ei)
                if whyRaiseOpen.contains(run.id) { whyRaiseCard(raise, ei: ei) }
            }
            HStack(spacing: 8) {
                restChip(run, ei: ei)
                noteChip(run, ei: ei)
            }
            supersetNoRestCaption(ei)
            if !reflow { columnHeader(run.type) }
        }
        .padding(.top, first ? CenitMetrics.gap : CenitMetrics.sectionGap)
    }

    /// r28 (owner): la voz de superserie del FOCO — miembros no-últimos heredan la leyenda «sin
    /// descanso»; el último lleva su sello «SUPERSERIE · A2» (descansa normal, pero sigue en pareja).
    @ViewBuilder private func focusSupersetCaption(_ ei: Int) -> some View {
        let members = session.supersetMembers(at: ei)
        if members.count > 1, members.last == ei, let badge = supersetBadgeText(ei: ei) {
            Text(String(format: String(localized: "SUPERSET · %@"), badge))
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.dataHrv)
        } else {
            supersetNoRestCaption(ei)
        }
    }

    /// «SIN DESCANSO ENTRE A1 Y A2» — shown only on the active block, only while it's a superset member
    /// that isn't the group's last (FER-931; the last member rests normally, so gets no caption).
    @ViewBuilder private func supersetNoRestCaption(_ ei: Int) -> some View {
        let members = session.supersetMembers(at: ei)
        if members.count > 1, members.last != ei,
           let currentBadge = supersetBadgeText(ei: ei),
           let nextIndex = members.first(where: { $0 > ei }), let nextBadge = supersetBadgeText(ei: nextIndex) {
            Text(String(format: String(localized: "NO REST BETWEEN %@ AND %@"), currentBadge, nextBadge))
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.dataHrv)
        }
    }

    /// The «···» exercise menu (FER-894 · «Cómo llego a Cambiar»): a themed paper menu (spec 4b) with
    /// View / Change / Skip / Remove. Reorder stays the drag handle (`reorderHandle`), never duplicated here.
    @ViewBuilder private func exerciseMenuButton(ei: Int, run: StrengthSessionModel.ExerciseRun) -> some View {
        Button { menuExerciseIndex = ei } label: {
            Image(systemName: "ellipsis")
                .font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(ei == session.currentIndex ? theme.dataStrain : theme.inkTertiary)
                .frame(width: 30, height: 44)
                .background {
                    // FER-936 tapRing: the active exercise's «···» wears a gently breathing ember ring,
                    // inviting a tap (menu holds Change / Reorder / Skip). Static under Reduce Motion.
                    if ei == session.currentIndex {
                        TapRing(color: theme.dataStrain, animated: !reduceMotion)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("More options for \(run.name)"))
        .paperMenu(
            isPresented: Binding(get: { menuExerciseIndex == ei },
                                 set: { if !$0 { menuExerciseIndex = nil } }),
            items: exerciseMenuItems(ei: ei, run: run)
        )
    }

    /// Canvas pass 2026-07-15: the handoff's `_ExMenu` set, in its order — Subir · Bajar · Añadir
    /// calentamiento · Superserie con el siguiente · Progresión (estado) · Cambiar · Quitar. «Ver
    /// ejercicio» dropped (tapping the name already opens it); «Saltar»/«Reordenar» dropped per the
    /// owner's explicit list (modo mover keeps its long-press entry).
    private func exerciseMenuItems(ei: Int, run: StrengthSessionModel.ExerciseRun) -> [PaperMenuItem] {
        var rows: [PaperMenuItem] = []
        if ei > 0 {
            rows.append(.init(String(localized: "Move up"), systemImage: "arrow.up") {
                withAnimation(.snappy) { reorderExercise(ei, by: -1) }
            })
        }
        if ei < session.runs.count - 1 {
            rows.append(.init(String(localized: "Move down"), systemImage: "arrow.down") {
                withAnimation(.snappy) { reorderExercise(ei, by: 1) }
            })
        }
        // r20 (auditoría UX #6c): la rampa de calentamiento es matemática de BARRA (PlateMath) —
        // en dumbbell/máquina la entrada mentía; y cuando aplica, la hoja abre YA en su sección.
        if usesBarbell(ei) {
            rows.append(.init(String(localized: "Add warm-up"), systemImage: "flame") {
                openPlates(ei: ei, si: min(run.currentSet, max(0, run.sets.count - 1)), startAtWarmup: true)
            })
        }
        if ei < session.runs.count - 1 {
            let paired = run.supersetGroup != nil && run.supersetGroup == session.runs[ei + 1].supersetGroup
            rows.append(.init(String(localized: paired ? "Undo superset" : "Superset with next"),
                              systemImage: "link") {
                // r21 (auditoría UX #5a): si el vecino YA forma pareja en otra superserie, emparejar
                // aquí la deshace — eso se confirma, no se hace en silencio.
                if !paired, session.runs[ei + 1].supersetGroup != nil {
                    confirmSupersetSteal = ei
                } else {
                    withAnimation(.snappy) { session.toggleSupersetWithNext(ei) }
                    persistSupersetGroups()   // r30: la pareja (o su deshecho) queda en la rutina
                }
            })
        }
        rows.append(.init(String(localized: "Progression"),
                          subtitle: progressionSubtitle(run),
                          systemImage: "chart.line.uptrend.xyaxis") {
            progressionEdit = ProgressionEditTarget(id: ei)
        })
        rows.append(.init(String(localized: "Change exercise"), systemImage: "arrow.triangle.2.circlepath") {
            changeExercise = ChangeTarget(ei: ei, run: run)
        })
        // Never leave the session empty — the last exercise can't be removed.
        if session.runs.count > 1 {
            rows.append(.init(String(localized: "Remove from session"), systemImage: "trash", isDestructive: true) {
                withAnimation(.snappy) { session.removeExercise(at: ei) }
            })
        }
        return rows
    }

    /// «activada · +2,5 kg cada 2 ✓» / «desactivada» — the progression state, read from the backing
    /// routine (cached at open; the session run doesn't carry progression config).
    private func progressionSubtitle(_ run: StrengthSessionModel.ExerciseRun) -> String {
        guard let re = routineREs[run.id] else { return String(localized: "off") }
        guard re.progressionEnabled else { return String(localized: "off") }
        let inc = re.progressionIncrementKg ?? 2.5
        return String(localized: "on") + " · +\(plateNumber(displayWeight(inc))) " +
               UnitFormatter.massUnit(units) + " " + String(localized: "every \(re.progressionSessions)") + " ✓"
    }

    /// The always-on, tenue reorder affordance (Sesión v21): a «≡» handle on each exercise header. Dragging
    /// it up/down reorders the exercise directly, riding the existing swap logic (`moveExerciseEarlier`,
    /// which keeps the focused exercise focused) — the same reorder the plan navigator exposes, now with a
    /// visible grab. VoiceOver gets explicit move-earlier / move-later actions since a drag isn't reachable.
    private func reorderHandle(ei: Int, run: StrengthSessionModel.ExerciseRun) -> some View {
        let hinted = reorderHint == ei
        return Image(systemName: "line.3.horizontal")
            .font(StrandFont.glyph(.chevron))
            .foregroundStyle(hinted ? theme.dataStrain : theme.inkTertiary)
            .scaleEffect(hinted ? 1.18 : 1)
            .animation(.snappy, value: hinted)
            .frame(width: 30, height: 44)
            .contentShape(Rectangle())
            // FER-936: the ember nudge from the menu fades on its own after a couple of seconds.
            .task(id: reorderHint) {
                guard reorderHint == ei else { return }
                try? await Task.sleep(for: .seconds(2.5))
                if reorderHint == ei { withAnimation(.snappy) { reorderHint = nil } }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 6)
                    .onEnded { value in
                        // Translate the vertical drag into whole-slot moves (~one exercise row per step).
                        let step: CGFloat = 56
                        let steps = Int((value.translation.height / step).rounded())
                        if steps != 0 { withAnimation(.snappy) { reorderExercise(ei, by: steps) } }
                    }
            )
            // r20 (owner, UX #4): TOCAR «≡» entra a modo mover — es LA entrada al modo (el
            // long-press ambiguo de header/renglones se retiró; el menú conserva Subir/Bajar).
            .onTapGesture { withAnimation(.snappy) { reorderMode = true } }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Reorder \(run.name)"))
            .accessibilityHint(Text("Drag to change the order"))
            .accessibilityAction(named: Text("Move earlier")) {
                withAnimation(.snappy) { reorderExercise(ei, by: -1) }
            }
            .accessibilityAction(named: Text("Move later")) {
                withAnimation(.snappy) { reorderExercise(ei, by: 1) }
            }
    }

    /// Move the exercise at `ei` by `steps` slots (negative = earlier, positive = later), one swap at a time.
    /// Both directions ride the existing `moveExerciseEarlier` swap (moving a slot later == pulling the next
    /// one earlier), so the session engine and its focus tracking stay the single source of truth.
    private func reorderExercise(_ ei: Int, by steps: Int) {
        guard steps != 0 else { return }
        var idx = ei
        if steps < 0 {
            for _ in 0..<(-steps) where idx > 0 { session.moveExerciseEarlier(idx); idx -= 1 }
        } else {
            for _ in 0..<steps where idx < session.runs.count - 1 { session.moveExerciseEarlier(idx + 1); idx += 1 }
        }
    }

    // MARK: Modo mover (FER-933) — handoff `_ListScreen.dc.html` reorder state, adopted on the riel.

    /// The mode bar above the list: overline «MOVIENDO · ARRASTRA SOBRE EL RIEL» (ember) + «Listo» (verde).
    private var reorderModeBar: some View {
        HStack {
            Text("MOVING · DRAG ALONG THE RAIL")
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.dataStrain)
            Spacer()
            Button {
                withAnimation(.snappy) {
                    reorderMode = false
                    reorderDraggingIndex = nil
                    reorderTargetIndex = nil
                }
            } label: {
                Text("Done").font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.dataRecovery)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Done reordering"))
        }
    }

    /// Clamp `ei + steps` to a valid slot — the same bound `reorderExercise` enforces one swap at a time,
    /// computed up front here purely to label the drop zone while dragging.
    private func reorderClampedTarget(_ ei: Int, steps: Int) -> Int {
        max(0, min(session.runs.count - 1, ei + steps))
    }

    /// The dashed ember drop zone, «SOLTAR AQUÍ · POSICIÓN N» (1-based), shown at the slot a live drag
    /// would land on.
    private func reorderDropZone(position: Int) -> some View {
        Text(String(format: String(localized: "DROP HERE · POSITION %d"), position + 1))
            .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
            .foregroundStyle(theme.dataStrain)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(theme.dataStrain.opacity(0.06), in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))  // token-exempt: decorative drop-zone tint alpha
            .overlay {
                RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                    .strokeBorder(theme.dataStrain, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            .padding(.bottom, 6)
            .accessibilityHidden(true)
    }

    /// One exercise, compressed to a single draggable line in modo mover: dot handle + name + its current
    /// prescription/done detail. A vertical `DragGesture` rides the same slot-stepping `reorderExercise`
    /// the always-on «≡» handle uses; the row that's mid-drag lifts (scale + rotate + ember border +
    /// shadow), the rest dim, and `reorderDropZone` renders above the destination slot. Reduce Motion drops
    /// the scale/rotation, keeping only the border + soft shadow.
    private func reorderRow(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        let dragging = reorderDraggingIndex == ei
        let anyDragging = reorderDraggingIndex != nil
        return VStack(spacing: 0) {
            if let target = reorderTargetIndex, target == ei, !dragging {
                reorderDropZone(position: target)
            }
            HStack(spacing: 12) {
                Text(run.name).font(StrandFont.body).foregroundStyle(theme.ink).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(run.sets.allSatisfy(\.done) ? doneDetailText(run) : prescriptionText(run))
                    .font(InstrumentoType.groteskNumber(12, weight: .regular)).foregroundStyle(theme.inkTertiary).lineLimit(1)
                // r8 (owner): la manija vive a la DERECHA — es donde estaba el pulgar al entrar al
                // modo (la «≡» del header); antes brincaba al lado izquierdo y había que cruzar.
                Image(systemName: "line.3.horizontal")
                    .font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                    .strokeBorder(dragging ? theme.dataStrain : theme.hairlineStrong, lineWidth: dragging ? 2 : 1)
            }
            .shadow(color: dragging ? theme.dataStrain.opacity(0.25) : .clear,  // token-exempt: decorative lift-shadow alpha
                    radius: dragging ? 10 : 0, y: dragging ? 4 : 0)
            .scaleEffect(dragging && !reduceMotion ? 1.03 : 1)
            .rotationEffect(.degrees(dragging && !reduceMotion ? -1 : 0))
            .opacity(anyDragging && !dragging ? StrandOpacity.dim : 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        reorderDraggingIndex = ei
                        let step: CGFloat = 56
                        let steps = Int((value.translation.height / step).rounded())
                        reorderTargetIndex = reorderClampedTarget(ei, steps: steps)
                    }
                    .onEnded { value in
                        let step: CGFloat = 56
                        let steps = Int((value.translation.height / step).rounded())
                        if steps != 0 { withAnimation(.snappy) { reorderExercise(ei, by: steps) } }
                        reorderDraggingIndex = nil
                        reorderTargetIndex = nil
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(run.name))
            .accessibilityHint(Text("Drag to change the order"))
            .accessibilityAction(named: Text("Move earlier")) {
                withAnimation(.snappy) { reorderExercise(ei, by: -1) }
            }
            .accessibilityAction(named: Text("Move later")) {
                withAnimation(.snappy) { reorderExercise(ei, by: 1) }
            }
        }
    }

    // MARK: Proposed raise (FER-E)

    private func raiseLine(_ raise: ProgressionPlanner.Raise, ei: Int) -> some View {
        Button {
            withAnimation(StrandMotion.interactive) {
                let id = session.runs[ei].id
                if whyRaiseOpen.contains(id) { whyRaiseOpen.remove(id) } else { whyRaiseOpen.insert(id) }
            }
        } label: {
            HStack(spacing: 5) {
                StrandIcon.up.image
                    .font(StrandFont.glyph(.chevron, weight: .bold))
                Text("today \(massText(raise.toKg))")
                    .font(InstrumentoType.grotesk(12, weight: .bold)).monospacedDigit()
                Text("·").foregroundStyle(theme.inkTertiary)
                Text("why")
                    .font(InstrumentoType.grotesk(12, weight: .bold))
                    .underline(pattern: .dot, color: theme.dataRecovery.opacity(0.55))   // token-exempt: subrayado punteado decorativo
            }
            .foregroundStyle(theme.dataRecovery)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Today you raise to \(massText(raise.toKg))"))
        .accessibilityHint(Text("Shows why, with your real dates"))
    }

    /// The «por qué» block (WhyRaiseCard, handoff 2b): connection surface, 2.5pt green bar, the arithmetic
    /// phrase, and the two text actions. «Volver a X» is the per-session opt-out: it reseeds the undone
    /// cells back to the old weight and drops the proposal — it never counts as a cycle failure.
    private func whyRaiseCard(_ raise: ProgressionPlanner.Raise, ei: Int) -> some View {
        NoteStrip(style: .info, theme: theme) {
            VStack(alignment: .leading, spacing: 7) {
                Text("WHY \(massText(raise.toKg))")
                    .instrumentoOverline().foregroundStyle(theme.dataRecovery)
                Text(verbatim: raise.phrase)
                    .font(StrandFont.caption).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Goal today: \(session.runs[ei].sets.count)×\(session.runs[ei].sets.first?.reps ?? 0) with the new weight. Losing a rep or two on a raise is normal; you win them back in 1 or 2 sessions.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 18) {
                    Button { withAnimation(StrandMotion.interactive) { _ = whyRaiseOpen.remove(session.runs[ei].id) } } label: {
                        Text("Keep \(massText(raise.toKg))")
                            .font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.dataRecovery)
                    }
                    .buttonStyle(.plain)
                    Button { revertRaise(ei: ei) } label: {
                        Text("Back to \(massText(raise.fromKg))")
                            .font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.inkSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
    }

    /// The per-session opt-out («Volver a X»): undone cells go back to the old weight; done sets keep
    /// whatever was actually lifted. The session is persisted as opted-out (FER-835), so the cycle
    /// ignores it entirely — neither hit nor miss; the earned raise is proposed again next session.
    private func revertRaise(ei: Int) {
        guard session.runs.indices.contains(ei),
              let raise = session.runs[ei].proposedRaise else { return }
        withAnimation(StrandMotion.interactive) {
            for si in session.runs[ei].sets.indices where !session.runs[ei].sets[si].done {
                session.runs[ei].sets[si].weightKg = raise.fromKg
            }
            session.runs[ei].proposedRaise = nil
            session.runs[ei].raiseOptedOut = true
            whyRaiseOpen.remove(session.runs[ei].id)
        }
    }

    /// A quiet, tappable chip showing this exercise's rest — tap to edit it mid-session (FER-540).
    /// r15 (owner, propuesta B): chips «troquel» — papel hundido sobre la tarjeta (paper dentro de
    /// surface, borde hairlineStrong, esquina continua), el ÚNICO color vive en el icono y el valor
    /// va en tinta media. Misma familia que los discos troquel del hub.
    private func restChip(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        // MISMO chip que el editor (decisión Fer 2026-07-16): ♥ recovery cuando el descanso es por
        // FC (con su valor), reloj ámbar cuando es por tiempo — una sola gramática en todo el flujo.
        let cfg = run.effectiveRest(forSet: run.currentSet)
        let isHR = cfg.mode == .heartRate
        return Button { openRestEditor(ei: ei) } label: {
            HStack(spacing: 6) {
                (isHR ? StrandIcon.heart.image : StrandIcon.clock.image)
                    .font(StrandFont.glyph(.chevron))
                    .foregroundStyle(isHR ? theme.dataRecovery : theme.dataStrain)
                Text(RoutineSetEditing.restChipLabel(cfg))
                    .font(InstrumentoType.groteskNumber(12, weight: .medium)).foregroundStyle(theme.ink)
                StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .troquelChip(theme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Edit rest"))
        .accessibilityValue(Text(RoutineSetEditing.restChipLabel(cfg)))
    }

    /// The «✎ Nota» chip (FER-932), next to the rest chip on the active exercise's header. Opens
    /// `NoteSheet` without touching `restEndsAt` — a running rest keeps counting behind it. Fills when
    /// this run (or any of its sets) already carries a note.
    private func noteChip(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        // r15 (owner, propuesta B): troquel hermano del chip de descanso — icono teal, punto ámbar
        // solo cuando ya hay nota (el estado es el datum).
        Button { openNote(exercise: run, ei: ei) } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(StrandFont.glyph(.chevron)).foregroundStyle(theme.dataHrv)
                Text("Note").font(StrandFont.caption.weight(.medium))
                    .foregroundStyle(run.hasNote ? theme.ink : theme.inkSecondary)
                if run.hasNote {
                    Circle().fill(theme.dataStrain).frame(width: 5, height: 5)
                }
            }
            .troquelChip(theme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(run.hasNote ? "Edit note, has a note" : "Add note"))
    }

    /// Resolve the full `Exercise` for a session run (override > custom > catalog, FER-541) and open its
    /// Detail sheet. Dismissing it leaves the session untouched — the session lives in `AppModel`.
    private func openDetail(_ run: StrengthSessionModel.ExerciseRun) {
        Task {
            if let ex = await model.repo.resolvedExercise(run.exerciseId) {
                await MainActor.run { detailExercise = ex }
            }
        }
    }

    /// Open the note sheet (FER-932) for the active exercise, from the «✎ Nota» chip. Never touches
    /// `restEndsAt` — a running rest keeps counting behind the sheet. Loads the cross-session history
    /// (`exerciseNotes(excludingSession:)`) fresh each open so a note saved elsewhere shows up.
    private func openNote(exercise run: StrengthSessionModel.ExerciseRun, ei: Int) {
        let setNumber = min(run.currentSet + 1, max(run.sets.count, 1))
        let setId = run.sets.indices.contains(run.currentSet) ? run.sets[run.currentSet].id : (run.sets.first?.id ?? "")
        noteTarget = NoteTarget(id: run.id, exerciseId: run.exerciseId, exerciseName: run.name,
                                 setId: setId, setNumber: setNumber)
        noteHistory = nil
        Task {
            guard let store = await model.repo.storeHandle() else { return }
            let history = (try? await store.exerciseNotes(exerciseId: run.exerciseId,
                                                           excludingSession: session.id)) ?? []
            await MainActor.run { noteHistory = history }
        }
    }

    /// Open the rest editor (FER-540/716). `setIndex` non-nil → a per-set edit (from the rest card);
    /// nil → exercise-scope (from the rest chip).
    private func openRestEditor(ei: Int, setIndex: Int? = nil) {
        guard session.runs.indices.contains(ei) else { return }
        restEdit = RestEdit(id: ei, setIndex: setIndex)
    }

    /// Apply an edited rest from the 1e editor (FER-716): to the live session at the chosen scope, and —
    /// when «save to routine» is on and the session is backed by a saved routine — persist it (per-set via
    /// `updateRoutineSetRest`, or the whole exercise via the cascading `updateRoutineExerciseRest`).
    private func applyRestEdit(ei: Int, si: Int?, config: RestConfig, applyToAll: Bool, saveToRoutine: Bool) {
        guard session.runs.indices.contains(ei) else { return }
        if applyToAll || si == nil {
            session.updateRest(exercise: ei, mode: config.mode, seconds: config.seconds,
                               reference: config.hrReference, value: config.hrValue)
            if saveToRoutine, let routineId = session.routineId {
                let reId = session.runs[ei].id
                Task {
                    await model.repo.updateRoutineExerciseRest(
                        routineExerciseId: reId, routineId: routineId,
                        mode: config.mode, seconds: config.seconds,
                        reference: config.hrReference, value: config.hrValue)
                }
            }
        } else if let si {
            session.updateRest(exercise: ei, set: si, rest: config)
            if saveToRoutine, let routineId = session.routineId,
               session.runs[ei].sets.indices.contains(si) {
                let routineSetId = session.runs[ei].sets[si].id   // seeded from the planned RoutineSet id
                Task { await model.repo.updateRoutineSetRest(routineSetId: routineSetId, routineId: routineId, rest: config) }
            }
        }
    }

    /// The quiet column header (overline). Hidden at accessibility sizes — each reflowed cell self-labels.
    private func columnHeader(_ type: ExerciseType) -> some View {
        let titles = columnTitles(type)
        return HStack(spacing: 8) {   // = spacing de gridRow: header y datos comparten geometría
            // El badge vive en un frame de 44 (26 visual + aire): el header usa el MISMO ancho,
            // si no, todas las columnas arrancan corridas (bug de alineación, canvas 2026-07-16).
            Text("SET").instrumentoOverline().foregroundStyle(theme.inkTertiary).frame(width: 44, alignment: .center)
            // FER-952 (modelo fantasma): la columna PREV murió — la última vez vive dentro de las
            // celdas como semilla tenue. El hueco flexible mantiene las columnas pegadas a la derecha.
            Spacer(minLength: 0)
            ForEach(titles.indices, id: \.self) { i in
                let isRPE = hasRPEColumn(type) && i == titles.indices.last
                Text(titles[i]).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .frame(width: isRPE ? rpeColumnWidth : cellWidth(type), alignment: .center)
            }
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    private func columnTitles(_ type: ExerciseType) -> [LocalizedStringKey] {
        switch type {
        case .weightReps: return [massUnitTitle, "REPS", "RPE"]
        case .bodyweight: return ["+LOAD", "REPS", "RPE"]
        case .time:       return ["TIME"]
        case .distance:   return [imperial ? "MI" : "KM", "TIME"]
        }
    }
    private var massUnitTitle: LocalizedStringKey { imperial ? "LB" : "KG" }
    /// La columna RPE: más angosta que las de captura (su contenido es «RPE» o «9,5»).
    private let rpeColumnWidth: CGFloat = 44
    /// ¿La última columna de este tipo es RPE? (weightReps/bodyweight sí; time/distance no.)
    private func hasRPEColumn(_ type: ExerciseType) -> Bool {
        type == .weightReps || type == .bodyweight
    }
    private func cellWidth(_ type: ExerciseType) -> CGFloat {
        switch type {
        // FER-952 fantasma: sin columna PREV las celdas recuperan aire.
        case .weightReps: return 64
        case .bodyweight: return 64
        case .time:       return 70
        case .distance:   return 60
        }
    }

    // MARK: A single set row

    @ViewBuilder private func setRow(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                                     set: StrengthSessionModel.WorkingSet, last: Bool) -> some View {
        let active = ei == session.currentIndex && si == run.currentSet && !set.done && session.summary == nil
        // A time / distance set, when it's the active row, expands inline with a compact stopwatch +
        // live HR zone (FER-716: this replaces the modal «Foco»). Other rows are the flat logging row.
        let cardio = run.type == .time || run.type == .distance
        Group {
            if active && cardio { cardioInlineRow(ei: ei, si: si, run: run, set: set) }
            else if reflow { reflowRow(ei: ei, si: si, run: run, set: set) }
            else { gridRow(ei: ei, si: si, run: run, set: set) }
        }
        .padding(.vertical, reflow ? 8 : 2)
        // r6: sin resaltado de fila (desbordaba el borde de la tarjeta) — la serie en curso se marca
        // solo con su numeral subrayado. El divisor vive a nivel rebanada (recibo, borde a borde).
        // FER-938 retirado: la fila copiada llega como semilla tenue (modelo fantasma) y se explica sola.
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        // r13: «Delete set» reaches VoiceOver through the row's context menu (actions rotor) — the
        // manual accessibilityAction duplicated it.
    }

    private func gridRow(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                         set: StrengthSessionModel.WorkingSet) -> some View {
        // Modelo fantasma (decisión Fer, FER-952): la columna PREV murió — «la última vez» vive
        // DENTRO de las celdas como semilla en tinta tenue hasta que la tocas; palomear una fila
        // sin tocar registra exactamente lo de la vez pasada.
        HStack(spacing: 8) {
            badge(run: run, si: si)
            Spacer(minLength: 0)
            dataCells(ei: ei, si: si, run: run, set: set)
            checkButton(ei: ei, si: si, set: set)
        }
    }

    private func reflowRow(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                           set: StrengthSessionModel.WorkingSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                badge(run: run, si: si)
                Spacer()
                checkButton(ei: ei, si: si, set: set)
            }
            HStack(spacing: 16) { dataCells(ei: ei, si: si, run: run, set: set) }
        }
    }

    /// The active time / distance row, expanded inline (FER-716) — a compact stopwatch (the elapsed /
    /// captured time as the dominant datum), a Start/Stop capsule (Stop registers the set and starts the
    /// rest), a distance stepper for distance sets, and the strap's live HR zone on the right.
    @ViewBuilder private func cardioInlineRow(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                                              set: StrengthSessionModel.WorkingSet) -> some View {
        let running = session.timerStart != nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                badge(run: run, si: si)
                // The clock — ticks live while running, else shows the captured time.
                Group {
                    if running {
                        TimelineView(.periodic(from: Date(), by: 1)) { ctx in cardioClock(session.timerElapsed(now: ctx.date)) }
                    } else {
                        cardioClock(set.timeS ?? 0)
                    }
                }
                Spacer(minLength: 8)
                startStopButton(running: running)
                checkButton(ei: ei, si: si, set: set)
            }
            // The live intensity scale: the whole Z1–Z5 ramp with the current zone lit, «N% of your max»
            // beneath (FER-894 · Estados 2). Only appears with a strap reading — no dashes, no empty ramp.
            PulseReader(model.live.pulse) { p in
                if let hr = p.smoothedBpm { hrZoneRampRow(hr) }
            }
            if run.type == .distance { distanceStepperRow(set.distanceM ?? 0) }
        }
        .frame(minHeight: run.type == .distance ? 150 : 118)
        .accessibilityElement(children: .contain)
    }

    private func cardioClock(_ elapsed: Int) -> some View {
        Text(Self.clock(elapsed))
            .font(InstrumentoType.groteskSessionClock).tracking(InstrumentoType.groteskSessionClockTracking)
            .foregroundStyle(elapsed > 0 ? theme.ink : theme.inkTertiary)
            .monospacedDigit()
    }

    private func startStopButton(running: Bool) -> some View {
        Button {
            withAnimation(.snappy) {
                running ? registerActiveSet()
                        : session.startSetTimer()
            }
        } label: {
            Text(running ? "Stop" : "Start").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .padding(.horizontal, 14).frame(height: 34)
                .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(running ? "Stop and register set" : "Start timer"))
    }

    /// The live HR intensity as a full Z1–Z5 ramp (FER-894 · Estados 2): five segments, the current zone lit
    /// in its `hrZoneRamp` hue, with «♥ bpm · N% of your max» beneath. Replaces the single-zone chip so the
    /// whole scale — and how far into it you are — is legible at a glance. Hidden when there's no strap.
    /// Paleta compartida: `InstrumentoTheme.hrZoneRamp`. 1 de 3 superficies de zonas HR distintas (aquí = intensidad ahora; WorkoutDetailScreen = %-tiempo; MetricDetailScreen = minutos) — NO se unifican, solo comparten la paleta (FER-908).
    private func hrZoneRampRow(_ hr: Int) -> some View {
        let zone = hrZone(hr)
        let maxHR = Double(model.profile.hrMax)
        let pct = maxHR > 0 ? Int((Double(hr) / maxHR * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { z in
                    let hue = theme.hrZoneRamp[z - 1]
                    let lit = z == zone
                    Text("Z\(z)")
                        .font(StrandFont.caption).monospacedDigit()
                        .foregroundStyle(lit ? theme.paper : theme.inkTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(lit ? hue : theme.surface,
                                    in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: lit ? 0 : 1))
                }
            }
            HStack(spacing: 5) {
                StrandIcon.heart.image.font(StrandFont.glyph(.chevron)).foregroundStyle(theme.hrZoneRamp[zone - 1])
                Text("\(hr)").font(InstrumentoType.groteskNumber(15, weight: .medium)).foregroundStyle(theme.ink)
                Text("·").foregroundStyle(theme.inkTertiary)
                // Literal «%» next to a format specifier breaks String(format:) parsing — compose it.
                (Text(verbatim: "\(pct)% ") + Text("of your max")).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Heart rate \(hr), zone \(zone), \(pct) percent of your maximum"))
    }

    private func distanceStepperRow(_ meters: Double) -> some View {
        HStack(spacing: 14) {
            stepper(system: "minus", size: 26) { session.bumpDistance(byMeters: -distanceStepM) }
                .accessibilityLabel(Text("Decrease distance"))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(distanceNumber(meters)).font(InstrumentoType.groteskNumber(18, weight: .medium)).monospacedDigit()
                    .foregroundStyle(theme.ink)
                Text(imperial ? "mi" : "km").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            stepper(system: "plus", size: 26) { session.bumpDistance(byMeters: distanceStepM) }
                .accessibilityLabel(Text("Increase distance"))
        }
        .padding(.leading, 44)
    }

    // MARK: - Inline rest card (1k, FER-716)

    /// The rest card — the ONE surface in the flow that lifts off the paper (`floatShadow`), because it's
    /// literally above the session's time. Slots between the marked set and the next; the table never
    /// disappears. By-HR: the live pulse drops toward the threshold; by-time: a countdown. No strap on an
    /// HR rest → it degrades to a capped timer with an honest notice (no dashes, no red).
    @ViewBuilder private var restInlineCard: some View {
        let hrMode = session.currentRestMode == .heartRate
        VStack(alignment: .leading, spacing: 12) {
            if hrMode, let started = session.restStartedAt {
                // PulseReader: the by-HR rest card follows the live pulse per beat (the TimelineView
                // alone would cap it at 1 s), and the haptic trigger keeps its per-beat evaluation (FER-755).
                PulseReader(model.live.pulse) { p in
                    TimelineView(.periodic(from: started, by: 1)) { ctx in
                        // r20 (auditoría UX #1): en pausa el reloj visible se CONGELA al instante de
                        // pausedAt — el modelo ya pausaba, pero la tarjeta seguía drenando a 0:00 y
                        // al reanudar el conteo rebotaba. El instrumento no miente en pausa.
                        let tick = session.paused ? (session.pausedAt ?? ctx.date) : ctx.date
                        let elapsed = max(0, Int(tick.timeIntervalSince(started)))
                        let v = RestReadinessRule.evaluate(
                            currentHR: p.smoothedBpm, worn: model.live.worn, restingHR: restingBaseline,
                            elapsedS: elapsed, targetHR: session.currentRestTarget)
                        if v.state == .noSignal {
                            restCardTimeBody(end: session.restEndsAt, now: tick, noStrapFallback: true)
                        } else {
                            restCardHRBody(elapsed: elapsed, readiness: v)
                        }
                    }
                    .sensoryFeedback(.success, trigger: p.smoothedBpm != nil && session.currentRestTarget != nil)
                }
            } else if let end = session.restEndsAt, let started = session.restStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    restCardTimeBody(end: end,
                                     now: session.paused ? (session.pausedAt ?? ctx.date) : ctx.date,
                                     noStrapFallback: false)
                }
            }
            restCardPills
            // (El «SIGUE» vive solo en el descanso a pantalla completa — owner call 2026-07-15: dentro
            // del mismo ejercicio ya sabes qué sigue, la tarjeta en línea no lo repite.)
        }
        // r21 (auditoría UI V6): 17/15 a ojo → el padding del recibo, como sus rebanadas hermanas.
        .padding(.horizontal, CenitMetrics.receiptPadding).padding(.vertical, CenitMetrics.receiptPadding)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairlineStrong, lineWidth: 1))
        .floatShadow(theme)
        .padding(.horizontal, -4).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    /// By-HR rest body: the live pulse dropping toward the threshold, with a gradient track + ink tick.
    private func restCardHRBody(elapsed: Int, readiness v: RestReadiness) -> some View {
        let bpm = model.bpm ?? 0
        let target = session.currentRestTarget
        let ready = v.ready
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                // r19 (auditoría UI): overline de token en tinta terciaria — el estado ya lo cuenta
                // el numeral; el hue jamás anuncia (§8.4).
                Text("Resting · by HR").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("\(Self.clock(elapsed)) elapsed").font(StrandFont.caption).monospacedDigit()
                    .foregroundStyle(theme.inkTertiary)
            }
            Text(ready ? String(localized: "Ready") : "\(bpm)")
                .font(InstrumentoType.groteskRestPulse).tracking(InstrumentoType.groteskRestPulseTracking)
                .monospacedDigit()
                .foregroundStyle(theme.dataRecovery)
                .contentTransition(.numericText())
            restHRTrack(bpm: bpm, target: target)
            if let target, !ready {
                (Text(String(localized: "dropping toward "))
                 + Text("\(target) bpm").foregroundColor(theme.dataRecovery).bold()
                 + Text(" · " + String(localized: "the strap will buzz")))
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The FC track: a linear scale from a warm start toward the threshold; the ink tick is the threshold
    /// (position is the channel), the `dataHeart → dataRecovery` gradient reinforces hot → goal.
    private func restHRTrack(bpm: Int, target: Int?) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Progress toward ready: from a nominal peak (~target+40) down to the target.
            let hi = Double((target ?? bpm) + 40)
            let lo = Double(target ?? bpm)
            let frac = hi > lo ? max(0, min(1, (hi - Double(bpm)) / (hi - lo))) : 1
            ZStack(alignment: .leading) {
                Capsule().fill(theme.hairline)
                Capsule().fill(LinearGradient(colors: [theme.dataHeart, theme.dataRecovery],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * frac)
                Rectangle().fill(theme.ink).frame(width: 2, height: 14)
                    .offset(x: w - 1)   // threshold tick at the ready end
            }
        }
        .frame(height: 6)
    }

    /// By-time rest body (also the no-strap fallback for an HR rest, capped at 5 min with a notice).
    private func restCardTimeBody(end: Date?, now: Date, noStrapFallback: Bool) -> some View {
        let cappedEnd = noStrapFallback ? min(end ?? now, (session.restStartedAt ?? now).addingTimeInterval(300)) : end
        let remaining = cappedEnd.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                // r20 (auditoría UX #1): en pausa el overline lo DICE — el reloj congelado sin
                // etiqueta parecería colgado.
                Text(session.paused ? "Paused" : (noStrapFallback ? "Resting · by time" : "Resting"))
                    .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
            }
            Text(Self.clock(remaining))
                .font(InstrumentoType.groteskRestPulse).tracking(InstrumentoType.groteskRestPulseTracking)
                .monospacedDigit()
                .foregroundStyle(remaining == 0 ? theme.dataRecovery : theme.ink)
                .contentTransition(.numericText())
            if noStrapFallback {
                Text("No strap signal: resting by time, 5 min cap")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // r20 (auditoría UX #3): VoiceOver oye hitos, no cada tick — label cuantizado + trait.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(session.paused ? String(localized: "Paused")
                                                : restA11yPhrase(remaining: remaining)))
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// r20 (auditoría UX #3): el restante del descanso para VoiceOver, en cubetas (60/30/15 s) —
    /// el cursor encima del reloj deja de parlotear cada segundo.
    private func restA11yPhrase(remaining: Int) -> String {
        guard remaining > 0 else { return String(localized: "Rest done") }
        if remaining <= 10 { return String(localized: "Resting, almost done") }
        let bucket = remaining <= 60 ? ((remaining + 14) / 15) * 15 : ((remaining + 29) / 30) * 30
        return String(localized: "Resting, \(bucket) seconds left")
    }

    private var restCardPills: some View {
        HStack(spacing: 10) {
            Button { openRestEditor(ei: session.currentIndex,
                                    setIndex: session.runs.indices.contains(session.currentIndex) ? session.runs[session.currentIndex].currentSet : nil) } label: {
                Label("Change rest", systemImage: "pencil").font(StrandFont.caption).foregroundStyle(theme.ink)
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button { withAnimation(StrandMotion.gentle) { session.skipRest() } } label: {
                Text("Skip").font(StrandFont.caption).foregroundStyle(theme.ink)
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    /// The set-number badge — a non-interactive marker in the effort hue (FER-716: the Foco is gone; the
    /// row itself is the interactive surface). A ring with the set number.
    /// The set's number badge. FER-937: a warm-up set shows a «C» (calentamiento) in a tenue ring and does
    /// not consume a work-set number; work sets are numbered 1..n counting only `.work` rows, so a warm-up
    /// never pushes «serie 1» to «serie 3».
    private func badge(run: StrengthSessionModel.ExerciseRun, si: Int) -> some View {
        let isWarmup = run.sets[si].kind == .warmup
        let workNumber = run.sets.prefix(si + 1).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
        let label = isWarmup ? String(localized: "C") : "\(workNumber)"
        // Canvas pass (propuesta C): the set being worked RIGHT NOW wears a 2pt ink underline beneath
        // its numeral — the same ink language as the block's rule, no color accent, survives
        // «Differentiate without color» by shape alone.
        let isCurrent = si == run.currentSet && !run.sets[si].done
        return Text(label).font(InstrumentoType.groteskNumber(12, weight: .medium)).monospacedDigit()
            .foregroundStyle(isWarmup ? theme.dataStrain.opacity(StrandOpacity.dim) : theme.dataStrain)  // token-exempt: warm-up badge tenue (handoff «C»)
            .frame(width: 26, height: 26)
            .overlay(Circle().strokeBorder(theme.dataStrain.opacity(isWarmup ? StrandOpacity.dim : 1), lineWidth: 1.5))  // token-exempt: warm-up ring tenue
            .overlay(alignment: .bottom) {
                if isCurrent, !isWarmup {
                    Rectangle().fill(theme.ink).frame(width: 16, height: 2).offset(y: 5)
                }
            }
            .frame(width: reflow ? 26 : 44, height: reflow ? 26 : 44, alignment: .center)
            .accessibilityLabel(Text(isWarmup ? "Warm-up set" : "Set \(workNumber)"))
    }

    /// The editable / captured data columns, by exercise type.
    @ViewBuilder private func dataCells(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                                        set: StrengthSessionModel.WorkingSet) -> some View {
        let ghost = !set.done && !set.touched
        switch run.type {
        case .weightReps:
            numberCell(.weight(ei, si), value: displayWeight(set.weightKg), isInt: false, done: set.done, type: run.type, ghost: ghost)
            numberCell(.reps(ei, si), value: Double(set.reps), isInt: true, done: set.done, type: run.type, ghost: ghost)
            rpeCell(ei: ei, si: si, run: run, set: set)
        case .bodyweight:
            HStack(spacing: 1) {
                Text("+").font(StrandFont.body).foregroundStyle(set.done ? theme.inkSecondary : theme.inkTertiary)
                numberCell(.weight(ei, si), value: displayWeight(set.weightKg), isInt: false, done: set.done, type: run.type, width: run.type == .bodyweight ? 48 : 56, ghost: ghost)
            }
            .frame(width: reflow ? nil : cellWidth(run.type), alignment: reflow ? .leading : .center)
            numberCell(.reps(ei, si), value: Double(set.reps), isInt: true, done: set.done, type: run.type, ghost: ghost)
            rpeCell(ei: ei, si: si, run: run, set: set)
        case .time:
            capturedCell(ei: ei, si: si, run: run,
                         text: (set.timeS ?? 0) > 0 ? Self.clock(set.timeS ?? 0) : nil)
        case .distance:
            capturedCell(ei: ei, si: si, run: run,
                         text: (set.distanceM ?? 0) > 0 ? distanceText(set.distanceM ?? 0) : nil)
            capturedCell(ei: ei, si: si, run: run,
                         text: (set.timeS ?? 0) > 0 ? Self.clock(set.timeS ?? 0) : nil)
        }
    }

    /// An editable numeric cell — a form field on paper (a faint underline you fill «with pen»). An empty or
    /// unparseable entry keeps the previous value (the buffer is dropped on blur). FER-497.
    /// An editable numeric cell — a form field on paper filled «with the pen». Tapping it activates the
    /// custom keypad (FER-716, no native keyboard, no «Foco»); while active it shows the working buffer
    /// with a caret and a 2px ink underline, otherwise the formatted value with a hairline underline.
    private func numberCell(_ ref: CellRef, value: Double, isInt: Bool, done: Bool,
                            type: ExerciseType, width: CGFloat? = nil, ghost: Bool = false) -> some View {
        let active = activeCell == ref
        let shown = active ? buffer : formatCell(value, isInt: isInt)
        // Canvas pass 2026-07-15 (UX·anim #1): opening the keypad animates like closing it — the
        // `.move(edge: .bottom)` transition only runs inside withAnimation; bare assignment popped.
        return Button { withAnimation(.snappy(duration: 0.22)) { activeCell = ref } } label: {
            HStack(spacing: 1) {
                Text(shown.isEmpty ? " " : shown)
                    // r20 (auditoría UX #6f): el numeral escala con Dynamic Type intermedio.
                    .font(InstrumentoType.groteskNumber(16, weight: .medium, relativeTo: .body)).monospacedDigit()
                    // Fantasma FER-952: la semilla («la última vez») habla tenue hasta que la tocas;
                    // el ✓ la registra tal cual — «si no lleno nada, es lo mismo que la anterior».
                    .foregroundStyle(done ? theme.inkSecondary : (ghost && !active ? theme.inkDim : theme.ink))
                if active {
                    Rectangle().fill(theme.ink).frame(width: 2, height: 18)   // caret
                        .opacity(0.9) // token-exempt: opacidad de caret >0.70
                }
            }
            .frame(width: (width ?? (reflow ? 64 : cellWidth(type))) * min(cellDynamicScale, 1.3), height: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(active ? theme.ink : theme.hairlineStrong)
                    .frame(height: active ? 2 : 1)
                    .padding(.bottom, 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(cellLabel(ref)))
        .accessibilityValue(Text(shown))
    }

    // MARK: Custom keypad input (FER-716)

    /// The active cell's current model value as a display string (seeds the buffer on activate).
    private func currentCellString(_ ref: CellRef) -> String {
        let (ei, si) = Self.indices(ref)
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return "" }
        let set = session.runs[ei].sets[si]
        switch ref {
        case .weight: return formatCell(displayWeight(set.weightKg), isInt: false)
        case .reps:   return formatCell(Double(set.reps), isInt: true)
        }
    }
    private func isWeightCell(_ ref: CellRef) -> Bool { if case .weight = ref { return true }; return false }

    /// Append a digit — replacing the seeded value on the first keystroke (Hevy-style).
    private func keypadInput(_ digit: String) {
        if !bufferTyped { buffer = ""; bufferTyped = true }
        buffer += digit
        commitBuffer()
    }
    private func keypadComma() {
        guard let cell = activeCell, isWeightCell(cell) else { return }   // reps are integers
        if !bufferTyped { buffer = "0"; bufferTyped = true }
        if !buffer.contains(",") && !buffer.contains(".") { buffer += "," }
        commitBuffer()
    }
    private func keypadBackspace() {
        if !bufferTyped { buffer = ""; bufferTyped = true }
        if !buffer.isEmpty { buffer.removeLast() }
        commitBuffer()
    }
    /// Quick add a plate / rep with the ± pill (adds the step; decrement via editing). Acts on the active
    /// cell's row, which `activeCell` has already made the current set.
    private func keypadStep(_ cell: CellRef) {
        switch cell {
        case .weight: session.bumpWeight(byKg: weightStepKg)
        case .reps:   session.bumpReps(1)
        }
        syncBufferFromModel(cell)
    }
    /// Push the buffer's parsed value into the model — empty / invalid keeps the previous value.
    private func commitBuffer() {
        guard let cell = activeCell, let v = Self.parseDouble(buffer) else { return }
        let (ei, si) = Self.indices(cell)
        switch cell {
        case .weight: session.setWeight(exercise: ei, set: si, kg: storedKg(fromDisplay: v))
        case .reps:   session.setReps(exercise: ei, set: si, reps: Int(v.rounded()))
        }
    }
    /// Re-seed the buffer from the model after a mutation that didn't come from typing (± / copy last).
    private func syncBufferFromModel(_ cell: CellRef) { buffer = currentCellString(cell); bufferTyped = false }

    /// The RPE cell (FER-930): tap opens the RPE sheet for this set. Shows the captured value in
    /// `dataEffort` (the datum's own color) when set, else a tenue «RPE» placeholder — never a nag, never
    /// blocking the check button next to it. Entirely independent of `done`.
    private func rpeCell(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                         set: StrengthSessionModel.WorkingSet) -> some View {
        Button {
            rpeTarget = RPETarget(id: set.id, runId: run.id, setNumber: si + 1,
                                  weightKg: displayWeight(set.weightKg), reps: set.reps, currentRPE: set.rpe)
        } label: {
            Group {
                if let rpe = set.rpe {
                    Text(Self.formatDecimalComma(rpe))
                        .font(InstrumentoType.groteskNumber(16, weight: .medium)).monospacedDigit()
                        .foregroundStyle(theme.dataEffort)
                } else {
                    Text("RPE").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                }
            }
            .frame(width: reflow ? nil : rpeColumnWidth, height: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.hairline).frame(height: 1).padding(.bottom, 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("RPE"))
        .accessibilityValue(Text(set.rpe.map(Self.formatDecimalComma) ?? String(localized: "Not recorded")))
    }

    /// es-MX decimal formatting: comma decimal, no trailing zero on whole numbers (8, not 8,0; 8,5).
    /// Shared by RPE values and, in `RPESheet`, the set's weight (FER-930).
    static func formatDecimalComma(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// A captured (non-typed) time / distance cell — tap to select the row, which expands it inline with the
    /// stopwatch (FER-716: the Foco is gone). Shows «—» until set.
    private func capturedCell(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun, text: String?) -> some View {
        Button { withAnimation(StrandMotion.gentle) { session.select(exerciseIndex: ei, setIndex: si) } } label: {
            Group {
                if let text {
                    Text(text).font(InstrumentoType.groteskNumber(16, weight: .medium)).monospacedDigit().foregroundStyle(theme.ink)
                } else {
                    Image(systemName: "play.circle").font(StrandFont.glyph(.lead)).foregroundStyle(theme.inkTertiary)
                }
            }
            .frame(width: reflow ? nil : cellWidth(run.type))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(text ?? String(localized: "Not recorded")))
        .accessibilityHint(Text("Expands the timer"))
    }

    /// The done toggle (the datum's color — green when logged). 44pt touch target. Checking the ACTIVE
    /// pending set registers it and starts the rest (FER-716: the rest card appears inline); any other
    /// tap is a plain toggle (a correction that starts no rest).
    private func checkButton(ei: Int, si: Int, set: StrengthSessionModel.WorkingSet) -> some View {
        let curSet = session.runs.indices.contains(ei) ? session.runs[ei].currentSet : -1
        let isActivePending = ei == session.currentIndex && si == curSet && !set.done
        return Button {
            withAnimation(.snappy) {
                if set.done {
                    // Desmarcar una serie hecha: corrección, sin descanso.
                    session.toggleDone(exercise: ei, set: si)
                } else {
                    // r10 (owner): palomear CUALQUIER serie pendiente registra con su descanso —
                    // antes solo la «actual» descansaba; las demás iban por toggleDone y el descanso
                    // nunca aparecía (el comportamiento «raro»).
                    activeCell = nil
                    if !isActivePending { session.select(exerciseIndex: ei, setIndex: si) }
                    registerActiveSet()
                }
            }
        } label: {
            Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                .font(StrandFont.glyph(.lead))
                .foregroundStyle(set.done ? theme.dataRecovery
                                 : isActivePending ? theme.dataStrain : theme.inkDim)
                // anim r7: el gesto más repetido de la sesión merece su micro-momento — pop del
                // símbolo + confirmación háptica al palomear (ReduceMotion: el bounce se omite solo).
                .symbolEffect(.bounce, value: set.done)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: set.done)
        .frame(width: reflow ? nil : 44)
        .accessibilityLabel(Text(set.done ? "Mark set \(si + 1) as not done" : "Mark set \(si + 1) as done"))
    }

    /// Insert the 40·60·80% warm-up ramp at the front of an exercise (FER-952 — the pill next to
    /// «+ Serie»; reuses the editor's ramp and the model's `insertWarmup`).
    private func addWarmupRamp(_ ei: Int) {
        guard session.runs.indices.contains(ei) else { return }
        // Explicit types — breaks mixed Double/tuple/map inference (type-check hotspot).
        let workWeight: Double? = session.runs[ei].sets.first(where: { $0.kind == .work })?.weightKg
        let firstWeight: Double? = session.runs[ei].sets.first?.weightKg
        let top: Double = workWeight ?? firstWeight ?? 0
        let factors: [Double] = [0.4, 0.6, 0.8]
        let ramp: [(weightKg: Double, reps: Int)] = factors.map { factor -> (weightKg: Double, reps: Int) in
            let weightKg: Double = top * factor
            let reps: Int = 10
            return (weightKg: weightKg, reps: reps)
        }
        withAnimation(StrandMotion.gentle) { session.insertWarmup(exercise: ei, sets: ramp) }
    }

    private func addSetButton(_ ei: Int) -> some View {
        // Canvas pass 2026-07-15: the handoff's ember «+ Serie» pill, living INSIDE the card as its
        // closing row (top hairline separates it from the last set). FER-952 seats the warm-up pill
        // next to it — quiet ember outline, visible only while the exercise has no warm-ups yet
        // (same grammar as the routine editor's twin pills).
        HStack(spacing: 8) {
            Button {
                // Canvas pass 2026-07-15: a contained, gentle open — ONE row's worth of space, not a leap
                // (owner: «que se abra solamente con un nuevo renglón»).
                withAnimation(StrandMotion.gentle) {
                    session.addSet(exercise: ei)
                    // r20 (sugerencia propia aprobada): la fila nueva no nace tapada por la barra —
                    // el bloque se asoma completo (su fondo incluye al propio botón).
                    scrollProxy?.scrollTo("session-exercise-\(ei)", anchor: .bottom)
                }
                addedSetId = session.runs.indices.contains(ei) ? session.runs[ei].sets.last?.id : nil
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.paper)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(theme.dataStrain, in: Capsule())
                    .frame(minHeight: 44)          // visual 33, toque 44 (HIG §8.7-4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // r22: confirmación táctil ligera al abrir el renglón nuevo — hermana del .success del ✓.
            .sensoryFeedback(.impact(weight: .light), trigger: addedSetId)
            if session.runs.indices.contains(ei), !session.runs[ei].sets.contains(where: { $0.kind == .warmup }) {
                Button { addWarmupRamp(ei) } label: {
                    Label("Add warm-up", systemImage: "flame")
                        .font(StrandFont.subhead.weight(.medium)).foregroundStyle(theme.dataStrain)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(theme.dataStrain.opacity(StrandOpacity.strokeSoft), lineWidth: 1))
                        .frame(minHeight: 44)      // visual 33, toque 44 (HIG §8.7-4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    // MARK: Empty ad-hoc state (mock 1p, FER-762)

    private var emptyAdHocSession: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("No routine: add exercises as you go. Rest defaults to 2 min, change it set by set.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button { showLibraryPicker = true } label: {
                    HStack(spacing: 9) {
                        StrandIcon.search.image.font(StrandFont.glyph(.inline)).foregroundStyle(theme.inkTertiary)
                        Text("Search the library…").font(StrandFont.body).foregroundStyle(theme.inkTertiary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13).padding(.vertical, 11)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityLabel(Text("Search the exercise library"))

                // FER-762: a brand-new user has no muscle-load history yet — `loadFreshSuggestions` then
                // returns no picks. Falling back to the search-only flow (no orphaned "Suggested" header
                // over an empty list) rather than a section with nothing under it.
                if let suggestions = freshSuggestions, !suggestions.isEmpty {
                    Text("Suggested · muscles fresh today").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        .padding(.top, 10)
                    ForEach(suggestions) { s in suggestionRow(s) }

                    if let muscle = loadedMuscle {
                        (Text(MuscleAtlas.name(muscle)) + Text(verbatim: " ") + Text("still carries load · suggestions avoid it."))
                            .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 13).padding(.vertical, 11)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                                .strokeBorder(theme.hairline, lineWidth: 1))
                            .padding(.top, 3)
                    }
                }

                Divider().overlay(theme.hairline).padding(.top, 10)
                Text("You'll be able to save this as a routine when you finish · it doesn't touch your plan.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, 16)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .safeAreaInset(edge: .top, spacing: 0) { liveHead }
        .task {
            guard freshSuggestions == nil else { return }
            await loadFreshSuggestions()
        }
    }

    private func suggestionRow(_ s: QuickSuggestion) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                .fill(theme.surface).frame(width: 48, height: 48)
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(StrengthDisplay.name(s.exercise)).font(StrandFont.body).foregroundStyle(theme.ink)
                (Text(MuscleAtlas.name(s.muscle)) + Text(verbatim: " · ") + Text("fresh")
                    + (lastTimeText(s).map { Text(verbatim: " · ") + Text("last time \($0)") } ?? Text(verbatim: "")))
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: 8)
            Button { Task { await addExercises([s.exercise]) } } label: {
                Text("Add").font(StrandFont.caption).foregroundStyle(theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add \(StrengthDisplay.name(s.exercise))"))
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(theme.hairline) }
    }

    /// «82,5 kg × 8» — the last logged weight/reps for a suggestion, plain data (not a localized phrase,
    /// same convention as `previousText`).
    private func lastTimeText(_ s: QuickSuggestion) -> String? {
        guard let w = s.lastWeightKg, let r = s.lastReps else { return nil }
        return "\(massText(w)) × \(r)"
    }

    /// Freshness suggestions (FER-762): the same fetch-and-expand `MuscleFatigueMap` recipe as the muscle
    /// map, over the trailing 84 days — the top 3 fresh muscles, one exercise each (preferring one the
    /// user has history for), plus a note naming the single most-loaded muscle the picks are avoiding.
    private func loadFreshSuggestions() async {
        let cal = Calendar.current
        guard let since = cal.date(byAdding: .day, value: -84, to: cal.startOfDay(for: Date())) else { return }
        let sinceTs = Int(since.timeIntervalSince1970)
        async let eventsTask = model.repo.muscleSetEvents(sinceTs: sinceTs)
        async let exercisesTask = model.repo.allExercises()
        async let historyTask = model.repo.recentWorkSets(sinceTs: sinceTs)
        let (events, exercises, history) = await (eventsTask, exercisesTask, historyTask)
        let loads = MuscleFatigueMap.loads(events: events)
        let historyIds = Set(history.map(\.exerciseId))

        // Same engine call `MuscleMapScreen` reads (`.readyMuscles`), not a hand-rolled filter/sort: it
        // already gates fresh muscles behind systemic recovery (a red-recovery day suggests nothing).
        let freshMuscles = MuscleFatigueMap.recommendation(loads: loads, recovery: recovery).readyMuscles
        var picked: [(exercise: Exercise, muscle: String)] = []
        var usedExerciseIds: Set<String> = []
        for muscle in freshMuscles {
            guard picked.count < 3 else { break }
            let candidates = exercises.filter { $0.primaryMuscles.contains(muscle) && !usedExerciseIds.contains($0.id) }
            guard let ex = candidates.first(where: { historyIds.contains($0.id) }) ?? candidates.first else { continue }
            usedExerciseIds.insert(ex.id)
            picked.append((exercise: ex, muscle: muscle))
        }
        // The per-exercise "last time" lookups are independent JOINs — run them concurrently, not one
        // await per loop iteration.
        freshSuggestions = await withTaskGroup(of: QuickSuggestion.self) { group in
            for (ex, muscle) in picked {
                group.addTask {
                    let last = await self.model.repo.exerciseHistory(exerciseId: ex.id).last
                    return QuickSuggestion(exercise: ex, muscle: muscle, lastWeightKg: last?.weightKg, lastReps: last?.reps)
                }
            }
            var results: [QuickSuggestion] = []
            for await s in group { results.append(s) }
            // Restore freshness order (most-fresh-first) — a TaskGroup completes in arbitrary order.
            let order = Dictionary(uniqueKeysWithValues: picked.enumerated().map { ($1.exercise.id, $0) })
            return results.sorted { (order[$0.exercise.id] ?? 0) < (order[$1.exercise.id] ?? 0) }
        }
        loadedMuscle = loads.filter { $0.state == .loaded }.max { $0.load < $1.load }?.muscle
    }

    /// Add one or more exercises to the session (from a suggestion or the library picker), seeding each
    /// from its last logged set when there's history. The empty ad-hoc state falls away on its own once
    /// `session.runs` isn't empty. FER-935: when the session already has runs (routine-backed or an
    /// ad-hoc session past its first exercise), the picks land right after the active exercise instead of
    /// at the end — iterated in REVERSE so the batch stays contiguous and in the user's chosen order
    /// (each `insertExerciseAfterCurrent` call lands at the same `currentIndex + 1` slot, pushing the
    /// previous insert one further along — see its doc comment).
    private func addExercises(_ picks: [Exercise]) async {
        let lasts = await withTaskGroup(of: (String, Double?, Int?).self) { group in
            for ex in picks {
                group.addTask {
                    let last = await self.model.repo.exerciseHistory(exerciseId: ex.id).last
                    return (ex.id, last?.weightKg, last?.reps)
                }
            }
            var results: [String: (Double?, Int?)] = [:]
            for await (id, weight, reps) in group { results[id] = (weight, reps) }
            return results
        }
        if session.runs.isEmpty {
            for ex in picks {
                let last = lasts[ex.id]
                session.addExercise(ex, lastWeightKg: last?.0, lastReps: last?.1)
            }
        } else {
            for ex in picks.reversed() {
                let last = lasts[ex.id]
                session.insertExerciseAfterCurrent(ex, lastWeightKg: last?.0, lastReps: last?.1)
            }
            // Canvas pass 2026-07-15 (owner call): the added exercise is PERMANENT — it also lands in
            // the backing routine, right after the active exercise's slot.
            if session.routineId != nil { persistInsertedExercises(picks) }
        }
    }

    /// Persist mid-session additions into the backing routine (after the active exercise's position),
    /// renumbering positions — fire-and-forget; the live session already has its runs.
    private func persistInsertedExercises(_ picks: [Exercise]) {
        guard let rid = session.routineId else { return }
        let activeRunId = session.runs.indices.contains(session.currentIndex)
            ? session.runs[session.currentIndex].id : nil
        Task {
            guard let store = await model.repo.storeHandle(),
                  var res = try? await store.routineExercises(routineId: rid),
                  let routine = (try? await store.routines())?.first(where: { $0.id == rid }) else { return }
            var insertAt = activeRunId.flatMap { id in
                res.firstIndex(where: { $0.id == id }).map { $0 + 1 }
            } ?? res.count
            for ex in picks {
                let re = RoutineExercise(routineId: rid, exerciseId: ex.id, position: insertAt,
                                         targetSets: 1, targetReps: 8,
                                         restMode: .fixed, restSeconds: StrengthSessionModel.adHocRestSeconds)
                res.insert(re, at: min(insertAt, res.count))
                insertAt += 1
            }
            for i in res.indices { res[i].position = i }
            do {
                try await store.saveRoutine(routine, exercises: res)
                await loadRoutineREs()
            } catch {
                saveError = true
            }
        }
    }

    /// Load the backing routine's exercises into the menu/progression cache.
    private func loadRoutineREs() async {
        guard let rid = session.routineId, let store = await model.repo.storeHandle() else { return }
        let res = (try? await store.routineExercises(routineId: rid)) ?? []
        routineREs = Dictionary(uniqueKeysWithValues: res.map { ($0.id, $0) })
    }

    /// A stand-in RoutineExercise built from the LIVE run, so the full progression screen can open
    /// even when the backing routine isn't loaded (preview / ad-hoc). Saving persists only when a
    /// real routine exists.
    private func syntheticRE(from run: StrengthSessionModel.ExerciseRun, position: Int) -> RoutineExercise {
        let planned = run.sets.enumerated().map { i, set in
            RoutineSet(position: i, kind: set.kind, reps: set.reps, weightKg: set.weightKg)
        }
        return RoutineExercise(routineId: session.routineId ?? "adhoc", exerciseId: run.exerciseId,
                               position: position, targetSets: max(1, planned.count),
                               targetReps: run.sets.first?.reps,
                               restMode: run.restMode == .heartRate ? .heartRate : .fixed,
                               restSeconds: run.restSeconds, sets: planned)
    }

    /// Persist the FULL progression config (r7 — the real ProgressionSetupScreen fields) into the
    /// backing routine, including the rep goal onto the plan's work sets.
    /// r30 (owner): «si algo se determina como superset, SE QUEDA como superset» — cada cambio de
    /// pareja hecho en la sesión se escribe a la RUTINA (el mismo camino que la progresión), así
    /// la próxima sesión nace con las mismas parejas. Ad-hoc (sin rutina) no tiene dónde persistir.
    private func persistSupersetGroups() {
        guard let rid = session.routineId else { return }
        let groups = Dictionary(uniqueKeysWithValues: session.runs.map { ($0.id, $0.supersetGroup) })
        Task {
            guard let store = await model.repo.storeHandle(),
                  var res = try? await store.routineExercises(routineId: rid),
                  let routine = (try? await store.routines())?.first(where: { $0.id == rid }) else { return }
            for i in res.indices where groups.keys.contains(res[i].id) {
                res[i].supersetGroup = groups[res[i].id] ?? nil
            }
            do {
                try await store.saveRoutine(routine, exercises: res)
                for re in res { routineREs[re.id] = re }
            } catch {
                saveError = true
            }
        }
    }

    private func persistProgressionFull(runId: String, enabled: Bool, targetReps: Int, sessions: Int,
                                        incrementKg: Double?, deload: DeloadPolicy, ignoreRecovery: Bool) {
        guard let rid = session.routineId else { return }
        Task {
            guard let store = await model.repo.storeHandle(),
                  var res = try? await store.routineExercises(routineId: rid),
                  let idx = res.firstIndex(where: { $0.id == runId }),
                  let routine = (try? await store.routines())?.first(where: { $0.id == rid }) else { return }
            res[idx].progressionEnabled = enabled
            res[idx].progressionSessions = sessions
            res[idx].progressionIncrementKg = incrementKg
            res[idx].progressionDeload = deload
            res[idx].progressionIgnoreRecovery = ignoreRecovery
            res[idx].targetReps = targetReps
            for i in res[idx].sets.indices where res[idx].sets[i].kind == .work {
                res[idx].sets[i].reps = targetReps
            }
            do {
                try await store.saveRoutine(routine, exercises: res)
                routineREs[res[idx].id] = res[idx]
            } catch {
                saveError = true
            }
        }
    }

    /// Discard the empty ad-hoc session (its «Descartar» pill, FER-762). Nothing was logged, so instead of a
    /// destructive confirmation this shows a calm terminal result — «Nothing to save» (FER-894 · Estados 2) —
    /// and only ends the session when the user taps «Got it». A result state, not a warning.
    private func discardEmptySession() {
        withAnimation(.snappy) { nothingToSave = true }
    }

    /// The «Nothing to save · your history stays clean» result card (FER-894). Terminal state for an
    /// empty-session discard: no numbers to celebrate, just reassurance that nothing was recorded.
    private var nothingToSaveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal")
                .font(StrandFont.glyph(.empty)).foregroundStyle(theme.inkSecondary)
                .accessibilityHidden(true)
            Text("Nothing to save").font(StrandFont.title1).foregroundStyle(theme.ink)
            Text("Your history stays clean: no sets were logged this session.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { model.endStrengthSession(save: false) } label: {
                Text("Got it")
                    .font(StrandFont.headline).foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain).padding(.top, 4)
            .accessibilityLabel(Text("Got it, close the session"))
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: Complete + discard footers

    private var completeFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(theme.hairline).frame(height: 1)
            completePhase
        }
    }

    private var discardFooter: some View {
        // Canvas pass 2026-07-15: dressed as the destructive sibling of the header's «Terminar» —
        // same capsule grammar, red by border, never a fill (DNA: primary-by-border).
        Button(role: .destructive) { confirmDiscard = true } label: {
            Text("Discard workout").font(StrandFont.subhead.weight(.medium)).foregroundStyle(theme.critical)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.critical.opacity(StrandOpacity.dim), lineWidth: 1))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .accessibilityLabel(Text("Discard workout"))
    }

    // MARK: Inline helpers (formatting / focus / actions)

    /// Tap-ANTERIOR: copy last time into this row (weight/reps/distance; a time set captures live).
    private func prefillTapped(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun) {
        session.prefillPrevious(exercise: ei, set: si)
    }

    private func previousText(_ run: StrengthSessionModel.ExerciseRun) -> String? {
        switch run.type {
        case .weightReps:
            guard let w = run.lastWeightKg, let r = run.lastReps else { return nil }
            return "\(massText(w))×\(r)"
        case .bodyweight:
            guard let r = run.lastReps else { return nil }
            let w = run.lastWeightKg ?? 0
            return "+\(plateNumber(displayWeight(w)))×\(r)"
        case .time:
            guard let t = run.lastTimeS else { return nil }
            return Self.clock(t)
        case .distance:
            guard let d = run.lastDistanceM else { return nil }
            return "\(distanceText(d)) · \(Self.clock(run.lastTimeS ?? 0))"
        }
    }

    private func formatCell(_ value: Double, isInt: Bool) -> String {
        isInt ? "\(Int(value.rounded()))" : plateNumber(value)
    }
    private static func parseDouble(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Double(t)
    }
    private func storedKg(fromDisplay v: Double) -> Double { imperial ? v * Self.kgPerPound : v }

    private func cellLabel(_ ref: CellRef) -> LocalizedStringKey {
        switch ref {
        case let .weight(_, si): return "Weight, set \(si + 1)"
        case let .reps(_, si):   return "Reps, set \(si + 1)"
        }
    }

    /// The editable cells in row-major order, for the keyboard «Next» button.
    private var editableCells: [CellRef] {
        var out: [CellRef] = []
        for (ei, run) in session.runs.enumerated() where !run.skipped {
            guard run.type == .weightReps || run.type == .bodyweight else { continue }
            for si in run.sets.indices { out.append(.weight(ei, si)); out.append(.reps(ei, si)) }
        }
        return out
    }
    private func focusNextCell() {
        let cells = editableCells
        guard let cur = activeCell, let idx = cells.firstIndex(of: cur) else { activeCell = nil; return }
        activeCell = idx + 1 < cells.count ? cells[idx + 1] : nil
    }

    private func distanceText(_ meters: Double) -> String {
        let v = imperial ? meters / Self.metersPerMile : meters / 1000
        return String(format: "%.2f %@", v, imperial ? "mi" : "km")
    }

    private func typeWord(_ t: ExerciseType) -> LocalizedStringKey {
        switch t {
        case .weightReps: return "Weight"
        case .bodyweight: return "Bodyweight"
        case .time:       return "Time"
        case .distance:   return "Distance"
        }
    }

    /// Coarse 1–5 HR zone from %HRmax — the same thresholds as the live zone-coaching haptics.
    private func hrZone(_ hr: Int) -> Int {
        let maxHR = Double(model.profile.hrMax)
        guard maxHR > 0 else { return 1 }
        let pct = Double(hr) / maxHR
        return pct >= 0.9 ? 5 : pct >= 0.8 ? 4 : pct >= 0.7 ? 3 : pct >= 0.6 ? 2 : 1
    }

    /// Stored meters → the user's unit (km / mi), two decimals.
    private func distanceNumber(_ meters: Double) -> String {
        let v = imperial ? meters / Self.metersPerMile : meters / 1000
        return String(format: "%.2f", v)
    }

    // MARK: Complete / empty phase (every exercise done or skipped)

    private var completePhase: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(StrandFont.glyph(.empty))
                .foregroundStyle(theme.dataRecovery).accessibilityHidden(true)
            // r20 (owner): el cierre habla en la voz del recibo — Grotesk, no title del sistema.
            Text(session.doneCount > 0 ? "All done" : "Nothing left")
                .font(InstrumentoType.grotesk(24, weight: .semibold)).foregroundStyle(theme.ink)
            Text(session.doneCount > 0
                 ? "You logged \(session.doneCount) sets. Finish to save this workout."
                 : "Every exercise was skipped. Finish to close, or resume from the hub.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { finishTapped() } label: {
                Label("Finish", systemImage: "checkmark")
                    .font(StrandFont.headline).foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain).padding(.top, 4)
            // Keep the way back: tapping an exercise re-focuses its rows to edit (or add sets).
            if !session.activeExercises.isEmpty {
                planNavigator.padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Summary phase (the post-session receipt · FER-409, redesigned per «Flujo Entrenar v3 · 1l»)

    @ViewBuilder
    private func summaryPhase(_ s: StrengthSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            receiptHeader(s)
            if s.watchRecorded { receiptWatchOrigin }
            receiptHeadline(s)
            receiptStats(s)
            if let kcal = s.energyKcal { receiptDietBlock(kcal: kcal, estimated: s.energySource == .estimated) }
            if let c = s.comparison { receiptComparison(s, c) }

            if !s.prs.isEmpty {
                receiptRecords(s.prs)
            } else if s.isFirstTime {
                Text("First time logging these. From here on you'll see your progress.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !s.exercises.isEmpty { receiptExercises(s.exercises) }

            // Conserved from FER-409 (not in the 1l mock, but it's the only path to the fatigue map).
            if !s.muscles.isEmpty { summaryMuscles(s.muscles) }

            if let band = s.costBand { receiptCost(band, tomorrowPct: s.costTomorrowPct) }

            Button { shareReceipt = ShareRef(sessionId: session.id) } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
                    .font(StrandFont.subhead).fontWeight(.medium)
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous)
                        .strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.top, 6)

            Button { model.closeStrengthSummary() } label: {
                Text("Done")
                    .font(InstrumentoType.grotesk(15, weight: .bold)).tracking(0.3)
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { playReceiptCountUp() }
    }

    /// The 0→value count-up (FER-716): the numerals roll up over 750 ms ONLY the first time the receipt
    /// appears (at save). `receiptCountUpPlayed` lives on the session, so re-opening (or re-scrolling)
    /// renders the final values immediately. Reduce Motion skips the roll entirely.
    private func playReceiptCountUp() {
        if session.receiptCountUpPlayed || reduceMotion {
            receiptCountUp = true
        } else {
            withAnimation(StrandMotion.countUp) { receiptCountUp = true }
        }
        session.receiptCountUpPlayed = true
    }

    /// «Sesión guardada · jue 2 jul» + the data-origin dot for the energy figure (strap Keytel vs MET).
    private func receiptHeader(_ s: StrengthSummary) -> some View {
        HStack(spacing: 8) {
            Text("\(String(localized: "Session saved")) · \(receiptDate(s.endTs))")
                .groteskOverline().foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 8)
            // FER-742: when the watch recorded, its origin line replaces the iPhone's energy-origin dot below.
            if let src = s.energySource, !s.watchRecorded { originRow(src) }
        }
    }

    /// FER-742: the receipt's origin line when the Apple Watch recorded the real FC/kcal and saved the
    /// workout to Health — shown instead of the iPhone's energy-origin dot.
    private var receiptWatchOrigin: some View {
        HStack(spacing: 5) {
            Image(systemName: "applewatch").font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text("Heart rate and calories from Apple Watch, saved to Health")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func receiptDate(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts))
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// The data-origin row on the receipt (FER-716): where this session's energy figure came from — the
    /// strap (Keytel) or an estimate (MET fallback).
    private func originRow(_ src: EnergySource) -> some View {
        HStack(spacing: 5) {
            Circle().fill(src == .bandCalculated ? theme.originBand : theme.originComputed)
                .frame(width: 6, height: 6)
            Text(src == .bandCalculated ? "Band + calculated" : "Estimated")
                .font(.system(size: 10)).foregroundStyle(theme.inkTertiary) // token-exempt: microtexto <11pt
        }
        .accessibilityElement(children: .combine)
    }

    /// The editorial headline: «{rutina}, hecha.» + the session's one honest achievement.
    private func receiptHeadline(_ s: StrengthSummary) -> some View {
        (Text("\(s.routineName), done.") + Text(verbatim: "\n") + Text(verbatim: achievementLine(s)))
            .font(InstrumentoType.groteskReceiptHeadline)
            .tracking(InstrumentoType.groteskReceiptHeadlineTracking)
            .foregroundStyle(theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// One achievement, best available first: new records → more volume than last time → first time →
    /// the plain set count. Never invents a comparison that isn't there.
    private func achievementLine(_ s: StrengthSummary) -> String {
        if s.prs.count == 1 { return String(localized: "A new personal record.") }
        if s.prs.count > 1 { return String(localized: "\(s.prs.count) new personal records.") }
        if let pct = s.comparison?.volumeDeltaPct(s.volumeKg), pct >= 1 {
            return String(localized: "+\(pct)% volume vs your last one.")
        }
        if s.isFirstTime { return String(localized: "First time with this routine.") }
        return String(localized: "\(s.setCount) sets logged.")
    }

    /// The four receipt metrics (duración · volumen · strain · kcal). Strain is the one colored datum;
    /// with no strain but captured HR, the avg-HR slot proves the strap was read (FER-498). No dashes:
    /// a metric without data simply isn't rendered.
    private func receiptStats(_ s: StrengthSummary) -> some View {
        let cells = Group {
            receiptStat("Duration", value: Self.clock(s.durationS), zero: "0:00")
            receiptStat("Volume", value: plateNumber(displayWeight(s.volumeKg)), zero: "0",
                        unit: UnitFormatter.massUnit(units))
            if let strain = s.strain {
                receiptStat("Strain", value: Self.strainText(strain), zero: Self.strainText(0),
                            color: theme.dataStrain)
            } else if let avgHr = s.avgHr {
                receiptStat("Avg HR", value: "\(avgHr)", zero: "0", unit: String(localized: "bpm"))
            }
            if let kcal = s.energyKcal {
                receiptStat(s.energySource == .estimated ? "Calories · estimated" : "Calories",
                            value: "\(Int(kcal.rounded()))", zero: "0", unit: "kcal")
            }
        }
        return Group {
            if reflow {
                VStack(alignment: .leading, spacing: 12) { cells }
            } else {
                HStack(alignment: .top, spacing: 20) { cells; Spacer(minLength: 0) }
            }
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    private func receiptStat(_ label: LocalizedStringKey, value: String, zero: String,
                             unit: String? = nil, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).groteskOverline(small: true).foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(receiptCountUp ? value : zero)
                    .font(InstrumentoType.groteskReceiptStat)
                    .tracking(InstrumentoType.groteskReceiptStatTracking)
                    .monospacedDigit().contentTransition(.numericText())
                    .foregroundStyle(color ?? theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let unit { Text(unit).font(StrandFont.caption).foregroundStyle(theme.inkTertiary) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The Diet block (decision: link ONLY, no target-% math): the session's kcal in prose + «Dieta →».
    /// Until the Diet section lands, the link parks the user on «Entrenar» (where it will live).
    private func receiptDietBlock(kcal: Double, estimated: Bool) -> some View {
        Button {
            tabRouter.select(.train)
            model.closeStrengthSummary()
        } label: {
            HStack(spacing: 10) {
                (Text(verbatim: "\(Int(kcal.rounded())) kcal ").fontWeight(.semibold).foregroundColor(theme.ink)
                    + Text(estimated ? "estimated from this session." : "logged from this session.")
                        .foregroundColor(theme.inkSecondary))
                    .font(StrandFont.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 3) {
                    Text("Diet").font(StrandFont.caption).fontWeight(.semibold)
                    Image(systemName: "arrow.right").font(StrandFont.glyph(.chevron, weight: .semibold))
                }
                .foregroundStyle(theme.dataRecovery)
                .fixedSize()
            }
            .padding(.leading, 12).padding(.trailing, 12).padding(.vertical, 9)
            .patternBlock(theme, bar: theme.dataStrain)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// «Contra tu última {rutina}» — three bars (volumen / series / duración) against the previous
    /// session of the SAME routine. The tick marks last time; the bar is this session.
    private func receiptComparison(_ s: StrengthSummary, _ c: StrengthSummary.Comparison) -> some View {
        let volDelta: String = {
            guard let pct = c.volumeDeltaPct(s.volumeKg) else { return "=" }
            return pct == 0 ? "=" : (pct > 0 ? "+\(pct)%" : "−\(-pct)%")
        }()
        let setsDelta = s.setCount == c.prevSetCount
            ? "\(s.setCount) = \(c.prevSetCount)"
            : (s.setCount > c.prevSetCount ? "+\(s.setCount - c.prevSetCount)" : "−\(c.prevSetCount - s.setCount)")
        let minDiff = Int((Double(s.durationS - c.prevDurationS) / 60).rounded())
        let durDelta = minDiff == 0 ? "=" : (minDiff > 0
            ? String(localized: "+\(minDiff) min") : String(localized: "−\(-minDiff) min"))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Against your last \(s.routineName)").groteskOverline().foregroundStyle(theme.inkTertiary)
            comparisonRow("Volume", current: s.volumeKg, prev: c.prevVolumeKg,
                          delta: volDelta, positive: s.volumeKg > c.prevVolumeKg)
            comparisonRow("Sets", current: Double(s.setCount), prev: Double(c.prevSetCount),
                          delta: setsDelta, positive: s.setCount > c.prevSetCount)
            comparisonRow("Duration", current: Double(s.durationS), prev: Double(c.prevDurationS),
                          delta: durDelta, positive: false, neutral: true)
        }
    }

    /// One comparison bar: label · track with this session's fill + an ink tick at last time · delta.
    /// Duration is `neutral` (longer isn't better) — gray fill, quiet delta.
    private func comparisonRow(_ label: LocalizedStringKey, current: Double, prev: Double,
                               delta: String, positive: Bool, neutral: Bool = false) -> some View {
        let maxV = max(current, prev, 1)
        return HStack(spacing: 10) {
            Text(label).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline)
                    Capsule().fill(neutral ? theme.hairlineStrong : theme.dataRecovery)
                        .opacity(neutral || positive ? 1 : 0.75)
                        .frame(width: max(4, w * (current / maxV)))
                    Rectangle().fill(theme.ink).frame(width: 2, height: 14)
                        .offset(x: min(w - 2, max(0, w * (prev / maxV) - 1)))
                }
            }
            .frame(height: 8)
            Text(delta).font(InstrumentoType.groteskNumber(12, weight: .regular))
                .foregroundStyle(positive ? theme.positiveText : theme.inkSecondary)
                .frame(width: 56, alignment: .trailing)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(delta))
    }

    /// The records card — the one `surface` card of the receipt. Each row frames the beaten record:
    /// «100 → 102,5 kg».
    private func receiptRecords(_ prs: [StrengthSummary.PR]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "star").font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(theme.dataRecovery)
                Text(prs.count == 1 ? String(localized: "A personal record")
                     : String(localized: "\(prs.count) personal records"))
                    .font(StrandFont.subhead).fontWeight(.semibold).foregroundStyle(theme.ink)
            }
            .padding(.bottom, 4)
            ForEach(Array(prs.enumerated()), id: \.element.id) { i, pr in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    (Text(verbatim: pr.exercise) + Text(verbatim: " · ") + Text(Self.prMetricLabel(pr.metric)))
                        .font(StrandFont.caption).foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    (Text(verbatim: prPriorText(pr)).foregroundColor(theme.inkTertiary)
                        + Text(verbatim: " → ")
                        + Text(verbatim: prValue(pr)).fontWeight(.semibold).foregroundColor(theme.ink))
                        // r26: los récords del recibo son valores → Grotesk tabular.
                        .font(InstrumentoType.groteskNumber(12, weight: .regular))
                }
                .frame(minHeight: 38)
                .overlay(alignment: .bottom) {
                    if i < prs.count - 1 { Rectangle().fill(theme.hairline).frame(height: 1) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    /// «Por ejercicio»: one quiet row per exercise — sets · top datum · trend vs «la última vez».
    private func receiptExercises(_ lines: [StrengthSummary.ExerciseLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("By exercise").groteskOverline().foregroundStyle(theme.inkTertiary)
                .padding(.bottom, 2)
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                HStack(spacing: 12) {
                    Text(line.name).font(StrandFont.subhead).foregroundStyle(theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(exerciseLineDetail(line))
                        .font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkSecondary)
                    exerciseTrendGlyph(line.trend)
                }
                .frame(minHeight: 40)
                .overlay(alignment: .bottom) {
                    if i < lines.count - 1 { Rectangle().fill(theme.hairline).frame(height: 1) }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func exerciseLineDetail(_ line: StrengthSummary.ExerciseLine) -> String {
        let top: String? = {
            if let w = line.topWeightKg, w > 0 { return massText(w) }
            if let t = line.topTimeS, t > 0 { return Self.clock(t) }
            if let d = line.topDistanceM, d > 0 { return distanceText(d) }
            return nil
        }()
        guard let top else { return String(localized: "\(line.setCount) sets") }
        return String(localized: "\(line.setCount) sets · \(top)")
    }

    @ViewBuilder private func exerciseTrendGlyph(_ trend: Int?) -> some View {
        switch trend {
        case .some(1):
            StrandIcon.up.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                .foregroundStyle(theme.positiveText)
                .accessibilityLabel(Text("Up vs last time"))
        case .some(-1):
            Image(systemName: "arrow.down").font(StrandFont.glyph(.chevron, weight: .semibold))
                .foregroundStyle(theme.inkTertiary)
                .accessibilityLabel(Text("Down vs last time"))
        case .some:
            Text(verbatim: "=").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .accessibilityLabel(Text("Same as last time"))
        case nil:
            Color.clear.frame(width: 12, height: 1)
        }
    }

    /// Recovery cost + tomorrow's projection (conserves FER-409/442) as a «patrón» block whose left bar
    /// wears the band's color.
    private func receiptCost(_ band: SessionRecoveryCost.Band, tomorrowPct: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recovery cost").groteskOverline(small: true).foregroundStyle(theme.inkTertiary)
            Text(Self.bandLabel(band)).font(StrandFont.subhead).fontWeight(.semibold)
                .foregroundStyle(bandColor(band))
            Text(Self.bandDetail(band)).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Tomorrow's projection given today's cost (FER-442): the prose in ink, the datum in
            // recovery green. Hidden when there isn't ~2 weeks of base (the engine returns nil).
            if let pct = tomorrowPct {
                (Text("Tomorrow, if you rest well, you should be around ").foregroundColor(theme.inkSecondary)
                    + Text("~\(pct)%").foregroundColor(theme.positiveText).fontWeight(.semibold))
                    .font(StrandFont.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Estimate · you decide").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .patternBlock(theme, bar: bandColor(band))
        .accessibilityElement(children: .combine)
    }

    /// The beaten record, for the «prior → new» framing. Volume compares totals (kg), matching `prValue`.
    private func prPriorText(_ pr: StrengthSummary.PR) -> String {
        switch pr.metric {
        case .maxWeight: return plateNumber(displayWeight(pr.priorValueKg ?? 0))
        case .maxReps:   return "\(pr.priorReps ?? 0)"
        case .maxVolume: return plateNumber(displayWeight(pr.priorValueKg ?? 0))
        }
    }

    private func summaryMuscles(_ muscles: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Today's muscles").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("Tap a muscle to see when to train it again.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            ChipFlow(spacing: 7) {
                ForEach(muscles, id: \.self) { m in
                    Button { openFatigueMap() } label: {
                        Text(m).font(StrandFont.subhead).foregroundStyle(theme.ink)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
                                .strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens the fatigue map"))
                }
            }
        }
    }

    /// Close the summary and hand off to «Cuerpo» → fatigue map (no third sheet stacked on the session).
    private func openFatigueMap() {
        tabRouter.openFatigueMap()
        model.closeStrengthSummary()
    }

    // MARK: Summary formatting

    private static func strainText(_ v: Double) -> String { String(format: "%.1f", v) }

    private func prValue(_ pr: StrengthSummary.PR) -> String {
        switch pr.metric {
        case .maxWeight: return massText(pr.valueKg ?? 0)
        case .maxReps:   return "\(pr.reps ?? 0)"
        // Volume frames TOTALS («2.070 → 2.160 kg»), matching `prPriorText`.
        case .maxVolume: return massText((pr.valueKg ?? 0) * Double(pr.reps ?? 0))
        }
    }

    private static func prMetricLabel(_ m: PRMetric) -> LocalizedStringKey {
        switch m {
        case .maxWeight: return "Max weight"
        case .maxReps:   return "Most reps"
        case .maxVolume: return "Best set"
        }
    }

    private static func bandLabel(_ b: SessionRecoveryCost.Band) -> LocalizedStringKey {
        switch b { case .light: return "Light"; case .moderate: return "Moderate"; case .high: return "High" }
    }

    private static func bandDetail(_ b: SessionRecoveryCost.Band) -> LocalizedStringKey {
        switch b {
        case .light:    return "Low cardiovascular cost. Your body barely felt it."
        case .moderate: return "A session that counted. Give yourself some rest."
        case .high:     return "A demanding session. Make sleep a priority today."
        }
    }

    private func bandColor(_ b: SessionRecoveryCost.Band) -> Color {
        switch b { case .light: return theme.dataRecovery; case .moderate: return theme.dataStrain; case .high: return theme.dataHeart }
    }

    // MARK: The «change exercise» bridge (hosted by the complete footer)

    private var planNavigator: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Change exercise").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(spacing: 0) {
                ForEach(Array(session.activeExercises.enumerated()), id: \.element.run.id) { pair in
                    let item = pair.element
                    navigatorRow(index: item.index, run: item.run, isFirst: pair.offset == 0)
                    if pair.offset != session.activeExercises.count - 1 { Divider().overlay(theme.hairline) }
                }
            }
            .padding(.horizontal, 14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
        }
    }

    private func navigatorRow(index: Int, run: StrengthSessionModel.ExerciseRun, isFirst: Bool) -> some View {
        let isCurrent = index == session.currentIndex
        let complete = !run.sets.contains { !$0.done }
        return HStack(spacing: 10) {
            Button { withAnimation(.snappy) { session.goToExercise(index) } } label: {
                HStack(spacing: 10) {
                    Image(systemName: complete ? "checkmark.circle.fill" : (isCurrent ? "circle.fill" : "circle"))
                        .font(StrandFont.glyph(.inline))
                        .foregroundStyle(complete ? theme.dataRecovery : (isCurrent ? theme.dataStrain : theme.inkTertiary))
                    Text(run.name).font(StrandFont.body)
                        .foregroundStyle(isCurrent ? theme.ink : theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isCurrent {
                Text("now").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            } else {
                HStack(spacing: 14) {
                    if !isFirst {
                        Button { withAnimation(.snappy) { session.moveExerciseEarlier(index) } } label: {
                            StrandIcon.up.image.font(StrandFont.glyph(.inline, weight: .semibold))
                                .foregroundStyle(theme.inkSecondary)
                        }
                        .buttonStyle(.plain).accessibilityLabel(Text("Move \(run.name) earlier"))
                    }
                    Button { withAnimation(.snappy) { session.skipExercise(index) } } label: {
                        Image(systemName: "forward.end").font(StrandFont.glyph(.inline, weight: .semibold))
                            .foregroundStyle(theme.inkSecondary)
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Skip \(run.name)"))
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
    }

    // MARK: Small builders

    private func stepper(system: String, size: CGFloat = 42, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: size > 38 ? 22 : 18, weight: .regular)) // token-exempt: tamaño de glifo condicional
                .foregroundStyle(theme.inkSecondary)
                .frame(width: size, height: size)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func finishTapped() {
        confirmFinish = true
    }

    private func restChipText(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 { return String(localized: "Rest \(seconds / 60) min") }
        return String(localized: "Rest \(seconds)s")
    }

    // MARK: Units / formatting

    private func displayWeight(_ kg: Double) -> Double { imperial ? UnitFormatter.kgToPounds(kg) : kg }
    private func massText(_ kg: Double) -> String { massString(kg, units: units) }

    static func clock(_ seconds: Int) -> String { SessionClock.format(seconds) }
}

/// Strips a `List` row down to the warm-paper language: one screen margin, no native background, no native
/// separator (the table draws its own hairlines). `top`/`bottom` tune the vertical rhythm per row. FER-497.
private extension View {
    func plainRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        // r18: the session left `List` for ScrollView+VStack — same screen margin and rhythm knobs
        // as the old listRowInsets version, but real stack layout: row seams are exact, so the rail
        // thread butts segment-to-segment with no overshoot and no double-alpha overlap.
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: top, leading: CenitMetrics.screenPadding,
                                bottom: bottom, trailing: CenitMetrics.screenPadding))
    }

}

/// Minimal flow layout: lays subviews left-to-right, wrapping to a new row when the next would overflow
/// the proposed width. Used for the summary's muscle chips (FER-409) so they wrap instead of truncating
/// at large Dynamic Type sizes.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW.isFinite ? maxW : x, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > bounds.width { x = 0; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Live BPM dot (FER-716)

/// The one always-on pulse of the app: the session header's live-BPM dot, breathing at 1.1 s. Falls
/// back to a static dot under Reduce Motion (the preset does not self-disable).
private struct BpmPulseDot: View {
    let color: Color
    var animated: Bool = true
    @State private var pulsing = false
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .scaleEffect(animated && pulsing ? 1.35 : 1.0)
            .opacity(animated && pulsing ? 0.65 : 1.0)
            .onAppear { if animated { withAnimation(StrandMotion.livePulse) { pulsing = true } } }
            .accessibilityHidden(true)
    }
}

#endif
