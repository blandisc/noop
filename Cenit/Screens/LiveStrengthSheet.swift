#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import StrandTraining
import StrandAnalytics
import CenitStore
import Inject   // recarga en caliente (dev-only, inerte en Release)

// 2026-07-19: `plateNumber` y `massString` vivían aquí como copias privadas y se habían desfasado de
// `StrengthDisplay`, que es lo que usa el editor: en imperial esta copia conservaba el decimal, así que
// la MISMA serie se leía «182 lb» en editar y «181.9 lb» en la sesión. Ahora son métodos de la vista
// (para tener `units` a la mano) y ambos enrutan por `StrengthDisplay`, la única fuente del formato.

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
//
// FER-170 (F5, épico FER-165): «La Hoja viva» (`HojaSesionViva`, `Cenit/Screens/Hoja/`) es el bucle
// vivo real desde F2 — este tipo se queda vivo solo para el acta/summary y el estado «Rápida vacía»
// ad-hoc (B13); su modo Foco modal se retiró (el enfoque nuevo vive en `RoutineSheetLiveFoco.swift`,
// una EXPANSIÓN de la tarjeta activa de la Hoja, no un tipo aparte).

// MARK: - The guided session sheet

/// The guided strength session, in the light «Instrumento diurno» language. The theme is passed in
/// explicitly (it doesn't cross the `.sheet` boundary — FER-190). The weight is the dominant datum in the
/// effort hue; the table is a detented `.sheet` drawer; rest is a fixed countdown that hosts the plan
/// navigator. The session itself lives in `AppModel`, so dismissing this sheet never ends it.
struct LiveStrengthSheet: View {
    @Environment(AppModel.self) private var model
    /// FER-93: para no soltar el aviso del descanso cuando la app vuelve del bloqueo.
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var tabRouter: TabRouter
    @ObservedObject var session: StrengthSessionModel
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    /// FER-87 · the acta's «Guardado en Salud» row needs to know whether the iPhone's opt-in Health
    /// mirror is even on (off by default) — the same gate `saveStrengthWorkoutIfEnabled` itself reads
    /// (`HealthKitBridge.swift`), so the row never claims a save the engine wouldn't have attempted.
    @AppStorage(HealthKitBridge.saveStrengthWorkoutsKey) private var saveStrengthWorkouts = false
    var theme: InstrumentoTheme = .base

    /// FER-170 (F5, épico FER-165): el modo Foco vigente que vivía en este tipo (la instancia
    /// efímera `startInFocus`/`onExitFocus` que F2 montaba desde `HojaSesionViva`) se RETIRÓ — el
    /// enfoque ahora es una expansión de la tarjeta activa dentro de la Hoja viva misma
    /// (`RoutineSheetLiveFoco.swift`). Este tipo se queda vivo solo para el acta/summary
    /// (`bodySummaryScroll`) y el estado «Rápida vacía» ad-hoc (B13, `emptyAdHocSession`) — los dos
    /// que `HojaSesionViva.body` sigue montando construyendo una instancia fresca de ESTE tipo.
    init(session: StrengthSessionModel, theme: InstrumentoTheme = .base) {
        self.session = session
        self.theme = theme
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmFinish = false
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
    struct RIRTarget: Equatable { let ei: Int; let si: Int }

    /// La decisión pura detrás del candado de `selectedRIRTarget` (revisión ronda 2, hallazgo grave):
    /// el RIR elegido solo sobrevive para la MISMA serie en la que se tocó el segmento. Probada en
    /// `LiveStrengthSheetRIRTests`.
    static func rirScoped(selectedRIR: Int?, selectedRIRTarget: RIRTarget?, registering: RIRTarget) -> Int? {
        selectedRIRTarget == registering ? selectedRIR : nil
    }

    /// The empty «Rápido de fuerza» state (FER-762): no routine, no exercises added yet. Its search field
    /// opens `ExerciseLibraryScreen` in ADD mode; the freshness suggestions load once when this state
    /// appears. `nil` = not loaded yet (the `.task` hasn't resolved); `[]` = loaded, honestly no fresh
    /// muscle to suggest — one optional instead of a separate "have I tried yet" flag.
    @State private var showLibraryPicker = false
    /// r21 (auditoría UX #5a): el `ei` cuyo «Superserie con el siguiente» robaría al vecino de otra
    /// pareja existente — pide confirmación antes de deshacerla.
    @State private var confirmSupersetSteal: Int?
    /// Canvas pass 2026-07-15 (menú «Progresión»): which exercise's progression mini-sheet is open.
    struct ProgressionEditTarget: Identifiable { let id: Int }
    @State private var progressionEdit: ProgressionEditTarget?
    /// The backing routine's exercises, keyed by `RoutineExercise.id` (== `ExerciseRun.id`) — the menu's
    /// progression subtitle and the mini-sheet read/write here; loaded once per routine.
    @State private var routineREs: [String: RoutineExercise] = [:]

    @State private var freshSuggestions: [QuickSuggestion]?
    /// The verdict the suggestions above were computed under (FER-82): a panel first built while the
    /// verdict was still pending must recompute when it lands, or it stays empty all session.
    @State private var suggestionsAdvice: TrainingRegulation.Advice?
    @State private var loadedMuscle: String?
    /// The exercise whose «Change {exercise}» sheet is open (FER-894). nil = closed.
    @State private var changeExercise: ChangeTarget?
    /// The terminal «Nothing to save» result card for discarding an empty session (FER-894 · Estados 2).
    @State private var nothingToSave = false
    @State private var saveError = false
    /// El hilo compacto de la cabecera (FER-133): la MISMA hoja del acta de Hoy que abre el hilo de
    /// la landing (`EntrenarView.showVeredictoActa`) — dos puertas, un solo destino.
    @State private var showVeredictoActa = false
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
        // FER-998: la sesión se presenta como `fullScreenCover`, así que no hereda el gesto de borde
        // de iOS — se lo damos. Hace lo MISMO que el botón: minimiza. La sesión sigue viva; deslizar
        // nunca la termina ni la descarta.
        .edgeSwipeToExit { model.strengthSheetPresented = false }
        .enableInjection()
    }

    /// Phase content only: nothing-to-save / summary / empty ad-hoc — the guided live table moved to
    /// `HojaSesionViva` (F5, épico FER-165); this type only ever mounts for these two branches.
    @ViewBuilder
    private var bodyPhaseContent: some View {
        Group {
            if nothingToSave {
                nothingToSaveCard
            } else if let summary = session.summary {
                bodySummaryScroll(summary)
            } else if isEmptyAdHoc {
                emptyAdHocSession
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
            .padding(.top, EntrenarMetrics.ctaRowTop)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Theme, banners, library picker, rest-anchor onChange — no session sheets yet.
    private var bodyChrome: some View {
        bodyPhaseContent
            // FER-198 (Ola 2, épico FER-195): fondo de vidrio El Eje (Ola 1, FER-197) para las 3
            // secciones que este tipo monta (nothingToSave / summaryPhase / emptyAdHocSession) —
            // un solo `fullScreenCover`, un solo fondo compartido; ninguna cambia su header (no
            // traen uno propio) ni su lógica de cierre.
            .entrenarHojaFondo(tono: .neutro)
            .instrumentoTheme(theme)
            .safeAreaInset(edge: .top) { if session.saveError { saveErrorBanner } }
            // FER-969: mid-session routine write failure (insert / superset / progression) — toast only;
            // the FINAL session save failure is the persistent `saveErrorBanner` above (X-01), not this.
            // Componente compartido desde 2026-07-19 (era la misma copia en tres pantallas).
            .saveErrorToast(isPresented: $saveError)
            // FER-935: hoisted from `emptyAdHocSession` to the shared root so the «＋» rail node also opens
            // the picker in a populated (routine-backed) session, not just the ad-hoc empty state.
            .sheet(isPresented: $showLibraryPicker) {
                bodyLibraryPickerSheet
            }
            .onChange(of: session.phase) { _, phase in
                if phase != .resting {
                    restAnchorEi = nil
                }
                // El pulso con el que ARRANCA el descanso (revisión ronda 2, hallazgo menor): sin esto
                // `RestBand` nunca dibuja el punto del riel mientras el pulso todavía va cayendo — solo
                // al llegar. Se captura una sola vez al entrar a descanso, se limpia al salir.
                if phase == .resting { restStartBpm = model.watchBpm } else { restStartBpm = nil }
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

    /// Progression / detail / change / rest·plates·RPE·note + the share fullScreen cover.
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
            // El hilo compacto de la cabecera (FER-133) abre la MISMA hoja del acta de Hoy que
            // `EntrenarView.hiloDelVeredicto` — mismo modelo y misma vista, para que la sesión y la
            // landing nunca puedan contar el día distinto.
            .sheet(isPresented: $showVeredictoActa) {
                bodyVeredictoActaSheet
            }
            .sheet(item: $restEdit) { edit in
                restEditorSheet(edit)
            }
            .sheet(item: $platesTarget) { target in
                platesSheet(target)
            }
            .sheet(item: $rpeTarget) { target in
                rpeSheet(target)
            }
            .sheet(item: $noteTarget) { target in
                noteSheet(target)
            }
            .fullScreenCover(item: $shareReceipt) { ref in
                bodyShareCover(ref)
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
                // El mínimo REAL según los discos que tienes, no el paso plano de la UI. Esta pantalla
                // imprime «según tus discos: el mínimo es X» y, si dejas el default, guarda `nil`
                // («usa el derivado»): con el paso plano la frase mentía Y se persistía un incremento
                // que nunca elegiste. En imperial era más falso todavía — mandaba 2.2679 kg (5 lb),
                // que no sale de ningún disco. El editor ya mandaba lo correcto; la sesión no, y el
                // arreglo de `progressionSubtitle` sólo cubrió la superficie de LECTURA. (2026-07-19)
                derivedIncrementKg: PlateMath.minimumIncrement(
                    for: .from(equipment: ExerciseCatalog.byID(run.exerciseId)?.equipment),
                    inventory: model.plates.inventory),
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

    /// La boleta del veredicto (FER-133): `VeredictoActaSheet`, la MISMA vista que
    /// `EntrenarView.showVeredictoActa` — dos call sites, un solo oráculo.
    private var bodyVeredictoActaSheet: some View {
        VeredictoActaSheet(prep: model.repo.todayPreparedness,
                           healthConnected: model.healthBridge?.auth == .authorized,
                           fullyLoaded: model.repo.fullyLoaded)
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


    // MARK: Rail + accordion (FER-929)

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

    /// The exercise the current rest belongs to (canvas pass 2026-07-15, owner bug #4): registering the
    /// LAST set advances `currentIndex` to the next exercise, but the rest card must stay GLUED under
    /// the exercise you just finished — so every register path stamps the anchor before advancing.
    @State private var restAnchorEi: Int?
    /// El pulso en el instante en que arrancó el descanso (revisión ronda 2, hallazgo menor; comentario
    /// corregido en ronda 3 — es una lectura puntual, no un máximo corrido): `RestBand` necesita este
    /// dato para dibujar el punto del riel MIENTRAS el pulso cae, no solo al llegar (`RestBand.railProgress`
    /// es `1` — listo — sin `startBpm`). Se captura una vez al entrar a descanso (`bodyChrome`'s
    /// `.onChange(of: session.phase)`) y se limpia al salir; si el pulso sigue subiendo unos segundos
    /// más tras entrar a descanso, el riel arranca desde esa lectura y no desde el pico real — aceptado
    /// porque el riel solo ilustra la caída, no reporta el pico.
    @State private var restStartBpm: Int?

    /// The exercise whose accordion is OPEN: while resting, the anchor (the exercise you just worked)
    /// holds the accordion open — the jump to `currentIndex` happens when the rest ends (owner r6).
    private var accordionIndex: Int {
        (session.phase == .resting ? restAnchorEi : nil) ?? session.currentIndex
    }


    /// FER-135 (V6, revisión ronda 1, hallazgo grave) · reusada por FER-170 (F5, épico FER-165): si
    /// el HECHO de un ejercicio (D3 del enfoque nuevo, `HojaFoco` en `RoutineSheetLiveFoco.swift`)
    /// debe mostrarse YA o esperar a que el descanso que acaba de arrancar termine primero. Checando
    /// cualquier serie siempre entra a descanso primero; HECHO solo aparece cuando ese descanso de
    /// verdad terminó. `.pending` defiere a un ancla que el caller sostiene hasta que
    /// `onChange(of: session.phase)` deja `.resting`; `.immediate` es solo para los casos sin
    /// descanso real que esperar (uno fijo de 0 s, o la última serie de toda la sesión). Pura y
    /// sin estado — el mismo par (¿el ejercicio/ronda cerró?, ¿arrancó un descanso real?) decide
    /// igual sea cual sea la piel que la llama.
    enum FocusDoneTiming: Equatable { case none, pending, immediate }
    static func focusDoneTiming(exerciseFullyDone: Bool, restStarting: Bool) -> FocusDoneTiming {
        guard exerciseFullyDone else { return .none }
        return restStarting ? .pending : .immediate
    }

    /// La decisión pura detrás de `registerActiveSet` (revisión ronda 1, hallazgo grave): qué RPE
    /// escribir al registrar una serie, o `nil` para no tocar el campo. Dos guardas, cada una
    /// honesta a su manera: un RPE ya puesto a mano (`existingRPE != nil`, por la hoja de RPE) nunca
    /// se pisa, y si el usuario NUNCA tocó el segmento «QUEDABAN» esta serie (`selectedRIR == nil`,
    /// p.ej. palomeó directo desde el ✓ de la tabla sin abrir el teclado) no se fabrica un RPE por
    /// defecto — el dato se queda sin capturar, como de verdad está. Probada en
    /// `LiveStrengthSheetRIRTests`.
    static func rpeToWrite(selectedRIR: Int?, existingRPE: Double?) -> Double? {
        guard existingRPE == nil, let rir = selectedRIR else { return nil }
        return rpe(fromRIR: rir)
    }

    /// RIR → RPE (FER-134): el motor guarda esfuerzo percibido en RPE (0–10); «QUEDABAN» es la MISMA
    /// captura leída como reps en reserva. RPE = 10 − RIR; «4+» se guarda como RIR 4 (RPE 6) — el
    /// motor no distingue «4» de «más de 4», las dos leen «con margen». Probada en
    /// `LiveStrengthSheetRIRTests`.
    static func rpe(fromRIR rir: Int) -> Double { Double(10 - min(4, max(0, rir))) }

    /// La lectura inversa para la tabla (handoff «Sesión en vivo» §4, ítem 4: «"Q n" ... en filas
    /// hechas (QUEDABAN = RIR)»): el motor solo guarda RPE (`WorkingSet.rpe`), así que la columna
    /// de `SetTable` recibe la lectura QUEDABAN ya formateada en vez del RPE crudo — el campo no
    /// cambia, solo cómo se lee en ESTA tabla (RIR = 10 − RPE, saturado a 0…4, «4+» en el tope).
    /// `RoutineEditorScreen` sigue leyendo `set.rpe` sin pasar por aquí — su columna RPE es RPE de
    /// verdad, no QUEDABAN (revisión ronda 3, hallazgo grave/menor duplicado).
    static func qLabel(fromRPE rpe: Double) -> String {
        let rir = 10 - Int(rpe.rounded())
        let clamped = min(max(rir, 0), 4)
        // «Q» es la abreviatura del prototipo (copy.md «Sesión en vivo»), no una palabra a traducir —
        // igual que el badge «C» de calentamiento en la misma tabla (`badgeText` arriba).
        return clamped >= 4 ? "Q 4+" : "Q \(clamped)"
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


    // MARK: _LiveHead (FER-929 — cabecera COMPACTA desde FER-133, handoff «Sesión en vivo» v4)

    private var liveHead: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionHeaderRow
            // Barra 3pt en el tinte de la rutina (FER-133 · V4) — reemplaza el desglose por ejercicio
            // de FER-929: el handoff la simplifica a «% ejercicios hechos», y el desglose ya se lee en
            // el riel de la lista de abajo (doble contabilidad). No hay plan en ad-hoc.
            if !isEmptyAdHoc {
                sessionProgressStrip.padding(.top, CenitMetrics.gap)
            }
            // El hilo compacto del veredicto (FER-133): SOLO con lighter/recover, silencio en lo demás.
            hiloCompacto
            // The Apple Watch mirror status (FER-742) — drawn ONLY when the watch fails.
            watchStatusLine
        }
        .padding(.horizontal, EntrenarMetrics.sessionHeaderMarginH)
        .padding(.top, EntrenarMetrics.sessionHeaderPaddingTop)
        .padding(.bottom, EntrenarMetrics.sessionHeaderPaddingBottom)
        .entrenarHojaBarraFondo(tono: .neutro)
        // Canvas pass 2026-07-15: the bottom hairline under the progress bar is gone — the whitespace
        // and the rail thread separate head from list on their own (owner call, punto 6).
    }

    /// La fila de la cabecera compacta: «‹» minimiza · punto de familia + título · sub «ejercicio N de
    /// M · en curso» / «pausada» a la izquierda; ♥ (solo con FC viva) · reloj · pausa · «Terminar» a
    /// la derecha — todo en una sola fila de 36 pt de alto (handoff «Sesión en vivo» v4).
    private var sessionHeaderRow: some View {
        HStack(spacing: CenitMetrics.space2) {
            // FER-998: el mismo gesto de siempre. El rol es minimizar (chevron) pero NO vuelve:
            // la sesión sigue viva y la píldora la reabre. Por eso el label de VoiceOver es suyo.
            sessionHeaderDisc("chevron.left", label: Text("Minimize session")) {
                model.strengthSheetPresented = false
            }
            VStack(alignment: .leading, spacing: CenitMetrics.space1) {
                HStack(spacing: CenitMetrics.space2) {
                    // Sin rutina (sesión rápida) no hay familia que señalar: el punto se calla,
                    // igual que el subtítulo de abajo.
                    if !isEmptyAdHoc {
                        EntrenarFamilyDot(railTint, size: EntrenarMetrics.familyDotCompact)
                    }
                    Text(isEmptyAdHoc ? String(localized: "Quick strength") : session.routineName)
                        .entrenarSessionHeaderTitle()
                        .foregroundStyle(theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                if !isEmptyAdHoc {
                    sessionHeaderSubtitle
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.inkTertiary)
                        .lineLimit(1).minimumScaleFactor(0.8)   // mismo criterio que el título
                }
            }
            Spacer(minLength: CenitMetrics.space2)
            sessionHeaderHeartRate
            sessionHeaderClock
            if let alternarPausa {
                sessionHeaderDisc(session.paused ? "play.fill" : "pause.fill",
                                   label: Text(session.paused ? "Resume session" : "Pause session"),
                                   glyph: .inline, action: alternarPausa)
            }
            sessionHeaderEndButton
        }
    }

    /// «Serie N de M · en curso» / «pausada» (FER-246 — misma unidad que la Hoja viva).
    private var sessionHeaderSubtitle: Text {
        if session.paused { return Text("paused") }
        let total = session.doneCount + session.pendingCount
        let current = session.isComplete ? total : session.doneCount + 1
        return Text("Set \(current) of \(total) · in progress")
    }

    /// ♥ 118 — SOLO con FC viva (Apple Watch conectado). SIN punto animado a propósito (decisión del
    /// dueño): el numeral ya es la señal de vida, un segundo indicador parpadeando al lado no añade
    /// nada y compite con el reloj.
    @ViewBuilder private var sessionHeaderHeartRate: some View {
        if let bpm = model.watchBpm {
            // El numeral es 13 pt, por debajo del piso de 24 en que el ADN permite el hue saturado en
            // texto — el mismo tono de lectura que `SessionStatsBar` ya usa para este mismo hue.
            let tone = theme.onPaper(theme.dataHeart)
            HStack(spacing: CenitMetrics.space1) {
                Image(systemName: "heart.fill").font(StrandFont.glyph(.chevron))
                Text("\(bpm)").font(StrandFont.subhead.weight(.semibold))
            }
            .foregroundStyle(tone)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Heart rate \(bpm) beats per minute"))
        }
    }

    private var sessionHeaderClock: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
            let elapsed = session.elapsedSeconds(now: ctx.date)
            Text(Self.clock(elapsed))
                .font(InstrumentoType.groteskSessionClockCompact)
                .tracking(InstrumentoType.groteskSessionClockCompactTracking)
                .foregroundStyle(session.paused ? theme.inkTertiary : theme.ink)
                // r22: los dígitos RUEDAN en vez de parpadear — misma voz que el descanso.
                .contentTransition(.numericText())
                .animation(.default, value: elapsed)
                .accessibilityLabel(Text(session.paused ? "Paused at \(Self.clock(elapsed))"
                                                         : "Elapsed \(Self.clock(elapsed))"))
                // r20 (auditoría UX #3): el trait le dice a VoiceOver que NO re-anuncie cada tick —
                // el usuario lo consulta, el reloj no lo interrumpe.
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// Un disco de 36 «papel + canto» (handoff «Sesión en vivo» v4): mismo lenguaje que `BackButton`
    /// (papel + filo `hairlineStrong`), al tamaño compacto de esta cabecera — comparte fila con el
    /// reloj y «Terminar», y el disco de 40 de `BackButton` la desbordaba.
    /// `glyph`: `.chevron` (12) para el «‹» de minimizar, que SÍ es un chevron; `.inline` (15) para
    /// ❚❚/▶, el mismo tamaño con que el teclado dibuja la otra cara de `alternarPausa`.
    private func sessionHeaderDisc(_ symbol: String, label: Text, glyph: StrandFont.GlyphSize = .chevron,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(StrandFont.glyph(glyph, weight: .semibold))
                .foregroundStyle(theme.ink)
                .frame(width: EntrenarMetrics.secondaryButton, height: EntrenarMetrics.secondaryButton)
                .background(Circle().fill(theme.paper))
                .overlay(Circle().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)   // 44 pt de toque
                .contentShape(Circle())
        }
        .buttonStyle(EntrenarPressStyle())
        .accessibilityLabel(label)
    }

    /// «Terminar» siempre, o «Descartar» mientras la sesión ad hoc sigue vacía — la misma regla que
    /// el header a pantalla completa tenía antes de FER-133, ahora en la píldora compacta.
    @ViewBuilder private var sessionHeaderEndButton: some View {
        if isEmptyAdHoc {
            sessionHeaderPill(Text("Discard"), accessibilityLabel: Text("Discard workout")) {
                discardEmptySession()
            }
        } else {
            sessionHeaderPill(Text("Finish"), accessibilityLabel: Text("Finish")) {
                finishTapped()
            }
        }
    }

    /// La píldora «papel + canto» de 36 pt de alto de la cabecera — mismo lenguaje que
    /// `sessionHeaderDisc`, en cápsula en vez de círculo.
    private func sessionHeaderPill(_ label: Text, accessibilityLabel: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .entrenarSessionEndLabel()
                .foregroundStyle(theme.ink)
                .padding(.horizontal, CenitMetrics.receiptPadding)
                .frame(height: EntrenarMetrics.secondaryButton)
                .background(Capsule().fill(theme.paper))
                .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(EntrenarPressStyle())
        .frame(minHeight: CenitMetrics.touchTarget)   // 44 pt de toque sobre el dibujo de 36
        .contentShape(Capsule())
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Barra de progreso (FER-133 · V4)

    private var sessionProgressStrip: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: EntrenarMetrics.progressBarRadius, style: .continuous)
                    .fill(theme.hairline)
                RoundedRectangle(cornerRadius: EntrenarMetrics.progressBarRadius, style: .continuous)
                    .fill(session.paused ? theme.inkDim : railTint)
                    .frame(width: geo.size.width * sessionProgressFraction)
            }
        }
        .frame(height: EntrenarMetrics.progressBar)
        .animation(LiquidMotion.suave, value: sessionProgressFraction)
        .accessibilityElement()
        .accessibilityLabel(Text("Session progress"))
        .accessibilityValue(Text("\(Int((sessionProgressFraction * 100).rounded())) percent complete"))
    }

    /// Ejercicios NO saltados ya completados: el índice ya quedó atrás, o todas sus series están
    /// hechas. A diferencia de `railState`, NO antepone «es el activo»: para un % de barra, el
    /// ejercicio abierto con todas sus series palomeadas ya cuenta como hecho (el borde se adelanta
    /// una fracción, que es lo honesto para el progreso).
    private var doneExerciseCount: Int {
        session.activeExercises.filter { entry in
            entry.index < session.currentIndex || entry.run.sets.allSatisfy(\.done)
        }.count
    }

    /// % de ejercicios hechos (hechos/total) — 0 al inicio de la sesión, 1 cuando todos cierran.
    private var sessionProgressFraction: CGFloat {
        let total = session.activeExercises.count
        guard total > 0 else { return 0 }
        return CGFloat(doneExerciseCount) / CGFloat(total)
    }

    // MARK: - Hilo compacto del veredicto (FER-133 · V4)

    /// SOLO cuando el día tiene algo que decir Y lo dice conteniendo la subida (`lighter`/`recover`):
    /// `TrainingRegulation.explainsHeldRaise` es exactamente ese criterio (`speaks && !allowsRaise`).
    /// Con `planAsIs`/`silent`/`pending` el hilo calla — el handoff dice «en verde, silencio», y el
    /// veredicto ya se dijo una vez en la landing (`EntrenarView.hiloDelVeredicto`).
    @ViewBuilder private var hiloCompacto: some View {
        if TrainingRegulation.explainsHeldRaise(model.repo.trainingAdvice),
           let hilo = LiquidHoyBuilder.hiloEntrenar(
               prep: model.repo.todayPreparedness,
               nights: model.repo.todayPreparedness?.autonomicNights ?? 0,
               healthConnected: model.healthBridge?.auth == .authorized,
               verdictPending: model.repo.todayPreparedness == nil && !model.repo.fullyLoaded,
               hasPlan: !isEmptyAdHoc) {
            EntrenarHilo(tone: hilo.tono.entrenarTone,
                         word: LocalizedStringKey(hilo.palabra),
                         advice: hilo.consejo.map { LocalizedStringKey($0) },
                         radio: EntrenarMetrics.orbeSesionCabecera,
                         hint: "Opens today's ballot") {
                showVeredictoActa = true
            }
            // `CenitMetrics.gap` (12), no `space2` (8) como en `EntrenarView.hiloDelVeredicto`: ahí el
            // hilo abre la landing y separa del héroe de la sesión; aquí separa de la barra de
            // progreso de 3 pt — un elemento más delgado pide más aire para no leerse pegado.
            .padding(.top, CenitMetrics.gap)
        }
    }


    // MARK: - La barra de estado (FER-86 · E5 — ahora es `SessionStatsBar`, la pieza de E2)

    /// Pausar o reanudar, según toque. Una sola definición para las DOS superficies que la disparan
    /// (la cabecera y el teclado, que se turnan el borde inferior): así no pueden divergir ni quedar
    /// una sin la otra. `nil` cuando no hay sesión que pausar.
    private var alternarPausa: (() -> Void)? {
        guard puedeControlarPausa else { return nil }
        return {
            if session.paused { model.resumeStrengthSessionFromPause() }
            else { model.pauseStrengthSession() }
        }
    }

    /// La pausa solo existe mientras hay sesión que pausar: una sesión ad hoc vacía no se pausa, se
    /// descarta, y una que ya rindió su acta no vuelve atrás.
    private var puedeControlarPausa: Bool { !isEmptyAdHoc && session.summary == nil }



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
            // Ronda 2 revisión final, hallazgo grave (g4-a11y): `.combine` vivía en el HStack completo,
            // fundiendo el botón «Retry» — un `Button` hermano real — en un solo elemento estático sin
            // acción. Solo el icono+texto se combinan; el botón queda fuera, alcanzable para VoiceOver.
            HStack(spacing: 6) {
                Image(systemName: icon).font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)
                Text(text).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            .accessibilityElement(children: .combine)
            if retry {
                Button { model.retryWatchMirroring() } label: {
                    Text("Retry").font(StrandFont.caption).fontWeight(.medium).foregroundStyle(theme.ink)
                }
                .buttonStyle(.plain).padding(.leading, 2)  // token-exempt: ajuste óptico
            }
        }
    }

    /// FER-969 (X-01): the final save failed — the workout is still on this phone (FER-798 snapshot);
    /// say so and offer retry instead of pretending the receipt is coming.
    private var saveErrorBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space2) {
            Image(systemName: "exclamationmark.triangle")
                .font(StrandFont.glyph(.chevron)).foregroundStyle(theme.critical)
                .accessibilityHidden(true)
            // Ronda 2 revisión final, hallazgo grave (g4-a11y): `.combine` vivía en el HStack completo,
            // fundiendo el único botón «Retry» del camino de recuperación de errores — VoiceOver no
            // podía reintentar el guardado. Solo el bloque de texto se combina; el botón queda suelto.
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn't save the workout. Try again.")
                    .font(StrandFont.caption).fontWeight(.medium).foregroundStyle(theme.ink)
                Text("Your sets are safe on this phone.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: CenitMetrics.space2)
            Button { model.retryStrengthSave() } label: {
                Text("Retry").font(StrandFont.caption).fontWeight(.medium).foregroundStyle(theme.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.vertical, CenitMetrics.rowVPad)
        .background(theme.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
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
                    do {
                        try await model.repo.updateRoutineExerciseRest(
                            routineExerciseId: reId, routineId: routineId,
                            mode: config.mode, seconds: config.seconds,
                            reference: config.hrReference, value: config.hrValue)
                    } catch {
                        saveError = true
                    }
                }
            }
        } else if let si {
            session.updateRest(exercise: ei, set: si, rest: config)
            if saveToRoutine, let routineId = session.routineId,
               session.runs[ei].sets.indices.contains(si) {
                let routineSetId = session.runs[ei].sets[si].id   // seeded from the planned RoutineSet id
                Task {
                    do {
                        try await model.repo.updateRoutineSetRest(
                            routineSetId: routineSetId, routineId: routineId, rest: config)
                    } catch {
                        saveError = true
                    }
                }
            }
        }
    }

    // MARK: Custom keypad input (FER-716)
    /// es-MX decimal formatting: comma decimal, no trailing zero on whole numbers (8, not 8,0; 8,5).
    /// Shared by `RPESheet`'s set weight (FER-930) and, since la adopción FER-86, `entrenarRow`'s RPE
    /// column — la celda RPE en sí (con su toque a `rpeTarget`) ahora es de `SetTable`.
    static func formatDecimalComma(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: Empty ad-hoc state (mock B13 `hoja-mapa.html`, FER-191 reskin of FER-762 — same freshness
    // + search logic below, only the piel changes to La Hoja's liquid glass: `EntrenarModulo`/`LiquidTono`)

    private var emptyAdHocSession: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("No routine: add exercises as you go. Rest defaults to 2 min, change it set by set.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button { showLibraryPicker = true } label: {
                    EntrenarModulo(tono: .neutro) {
                        HStack(spacing: 9) {
                            StrandIcon.search.image.font(StrandFont.glyph(.inline)).foregroundStyle(theme.inkTertiary)
                            Text("Search the library…").font(StrandFont.body).foregroundStyle(theme.inkTertiary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .buttonStyle(EntrenarPressStyle())
                .padding(.top, 2)  // token-exempt: ajuste óptico
                .accessibilityLabel(Text("Search the exercise library"))

                // FER-762: a brand-new user has no muscle-load history yet — `loadFreshSuggestions` then
                // returns no picks. Falling back to the search-only flow (no orphaned "Fresh today" header
                // over an empty list) rather than a section with nothing under it.
                if let suggestions = freshSuggestions, !suggestions.isEmpty {
                    Text("Fresh today").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        .padding(.top, LiquidSpace.seccionCanto)
                    VStack(spacing: CenitMetrics.space2) {
                        ForEach(suggestions) { s in freshSuggestionChip(s) }
                    }

                    if let muscle = loadedMuscle {
                        (Text(MuscleAtlas.name(muscle)) + Text(verbatim: " ") + Text("still carries load · suggestions avoid it."))
                            .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, CenitMetrics.cardPadding).padding(.vertical, CenitMetrics.gap)
                            .liquidGlass(.superficieSolida)
                            .padding(.top, 3)  // token-exempt: ajuste óptico
                    }
                }

                Divider().overlay(theme.hairline).padding(.top, LiquidSpace.seccionCanto)
                Text("You'll be able to save this as a routine when you finish · it doesn't touch your plan.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, LiquidSpace.seccionCanto)
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, CenitMetrics.cardPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-198 (Ola 2): SIN fondo propio — lo aporta el `.entrenarHojaFondo` compartido de
        // `bodyChrome` (una sola raíz para las 3 secciones). Un segundo aquí apilaba material y
        // destello (costura visible); el `.background(theme.paper)` opaco de antes se removió por lo
        // mismo. Buscador de frescura y demás lógica de esta sección, intactos.
        .safeAreaInset(edge: .top, spacing: 0) { liveHead }
        // FER-82: las sugerencias las gatea el veredicto, así que una lista calculada mientras el
        // veredicto todavía se computaba está vencida en cuanto aterriza. Se recalcula cuando el
        // consejo con el que se calculó ya no es el de hoy.
        //
        // Deliberadamente NO se llavea a `repo.refreshSeq`: esta hoja no observa `Repository` (llega
        // por `model`), así que la llave no cambiaría sola y sería un arreglo de mentira. Con `.task`
        // a secas se recalcula cada vez que el panel aparece, que es cuando el usuario lo lee.
        .task {
            guard freshSuggestions == nil || suggestionsAdvice != model.repo.trainingAdvice else { return }
            await loadFreshSuggestions()
        }
    }

    /// Un ejercicio fresco como cápsula de vidrio de La Hoja (FER-191): el mismo dato que
    /// `loadFreshSuggestions` calculaba antes (ejercicio + músculo + última marca), ahora en el
    /// idioma de `EntrenarModulo`, teñido por la familia de su músculo (`LiquidTono`) — la cápsula
    /// entera es el toque de «agregar», sin un pill «Add» aparte.
    private func freshSuggestionChip(_ s: QuickSuggestion) -> some View {
        let tono = chipTono(for: s.muscle)
        return Button { Task { await addExercises([s.exercise]) } } label: {
            EntrenarModulo(tono: tono) {
                HStack(spacing: CenitMetrics.gap) {
                    RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                        .fill(theme.surface).frame(width: 40, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(StrengthDisplay.name(s.exercise)).font(StrandFont.body).foregroundStyle(theme.ink)
                        (Text(MuscleAtlas.name(s.muscle)) + Text(verbatim: " · ") + Text("fresh")
                            + (lastTimeText(s).map { Text(verbatim: " · ") + Text("last time \($0)") } ?? Text(verbatim: "")))
                            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                    Spacer(minLength: CenitMetrics.space2)
                    StrandIcon.add.image.font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(tono.rotulo)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(EntrenarPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Add \(StrengthDisplay.name(s.exercise))"))
    }

    /// El tono de vidrio de la cápsula (FER-191): el músculo de la sugerencia → su región de
    /// entrenamiento (`RoutineClassifier`, el MISMO clasificador que tiñe rutinas y sesiones) →
    /// la familia de diseño → su `LiquidTono`. Músculos neutros (abdominales, cuello, lumbar) no
    /// clasifican a ninguna región — caen a `.neutro`, el mismo vidrio blanco de las tarjetas de
    /// ejercicio ya en curso, en vez de inventar un color.
    private func chipTono(for muscle: String) -> LiquidTono {
        RoutineClassifier.region(for: muscle)?.family.tono ?? .neutro
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
        let advice = model.repo.trainingAdvice
        let cal = Calendar.current
        guard let since = cal.date(byAdding: .day, value: -84, to: cal.startOfDay(for: Date())) else { return }
        let sinceTs = Int(since.timeIntervalSince1970)
        async let eventsTask = model.repo.muscleSetEvents(sinceTs: sinceTs)
        async let exercisesTask = model.repo.allExercises()
        async let historyTask = model.repo.recentWorkSets(sinceTs: sinceTs)
        let (events, exercises, history) = await (eventsTask, exercisesTask, historyTask)
        let loads = MuscleFatigueMap.loads(events: events)
        let historyIds = Set(history.map(\.exerciseId))

        // Same engine call `MuscleMapScreen` reads (`.readyMuscles`), not a hand-rolled filter/sort.
        //
        // FER-82: the SYSTEMIC gate is the day's verdict, not the 0–100 score. Suggesting «agrega este
        // ejercicio, ese músculo está fresco» on a day Entrenar is saying «Recupera» was the old second
        // oracle, alive inside the session. The score keeps deciding per-muscle freshness (that is what
        // it measures); whether to suggest ADDING work at all is the verdict's call.
        // Igual que el mapa (MuscleMapScreen): el motor recibe `nil` —ningún gate por score— y la
        // compuerta sistémica la pone el veredicto aquí. Solo «Recupera» corta las sugerencias.
        let freshMuscles = TrainingRegulation.gatesTraining(advice)
            ? []
            : MuscleFatigueMap.recommendation(loads: loads, recovery: nil).readyMuscles
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
        // El consejo se sella JUNTO con el resultado, no antes de las lecturas: si se marcara al
        // entrar, una pasada abortada dejaría el sello puesto y la sección no se recalcularía nunca.
        suggestionsAdvice = advice
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
            // Nancy · ronda 12: misma regla que la sesión viva (insertExercise) — el punto de
            // inserción salta al final del bloque de superserie; la computación vive en UN solo
            // helper (`insertionIndex(afterRunId:)`) para que las dos entradas no vuelvan a divergir.
            var insertAt = res.insertionIndex(afterRunId: activeRunId)
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
        VStack(alignment: .leading, spacing: LiquidSpace.estadoVacioAire) {
            Image(systemName: "checkmark.seal")
                .font(StrandFont.glyph(.empty)).foregroundStyle(theme.inkSecondary)
                .accessibilityHidden(true)
            Text("Nothing to save")
                .font(LiquidType.displayS)
                .tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text("Your history stays clean: no sets were logged this session.")
                .font(StrandFont.subhead).foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
            StrandCTAButton("Got it", tint: LiquidColor.tinta900) {
                model.endStrengthSession(save: false)
            }
            .padding(.top, CenitMetrics.space1)
            .accessibilityLabel(Text("Got it, close the session"))
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // 2026-07-19 (decisión Fer): se retiró el `discardFooter` — la cápsula roja flotante al final del
    // scroll. Era una SEGUNDA PUERTA al mismo cuarto: «Terminar» ya abre un diálogo con «Descartar
    // entrenamiento» adentro, en los dos estados (`bodyFinishConfirmActions`). Y su cápsula roja de
    // contorno era, literalmente, el botón del diálogo que abría — el vocabulario de «confirmar la
    // destrucción» gastado en el control que solo invita, que es el mismo argumento que ya justificaba
    // vestir «Terminar» de tinta y no de alarma. Una destructiva con una sola puerta es más segura que
    // con dos. El «Descartar» gris del encabezado para la sesión vacía (`discardEmptySession`) NO se
    // tocó: es otro estado y otro camino.

    // MARK: Inline helpers (formatting / focus / actions)
    private func distanceText(_ meters: Double) -> String {
        let v = imperial ? meters / Self.metersPerMile : meters / 1000
        return String(format: "%.2f %@", v, imperial ? "mi" : "km")
    }
    // MARK: Summary phase (the post-session receipt · FER-409, redesigned per «Flujo Entrenar v3 · 1l»)

    @ViewBuilder
    private func summaryPhase(_ s: StrengthSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            receiptHeader(s)
            if s.watchRecorded { receiptWatchOrigin }
            receiptHeadline(s)
            receiptHero(s)
            receiptStats(s)
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

            if let band = s.costBand { receiptCost(band) }

            // FER-87: the workout only really reached Apple Health when the Watch recorded it
            // (always true) or the iPhone's opt-in mirror is on — the exact gate the save itself
            // reads, so this row never claims a save the app never attempted.
            if s.watchRecorded || saveStrengthWorkouts { receiptHealthSaved(s) }

            // copy.md «Acta»: «Imprimir recibo» — el handoff manda, sustituye a «Compartir…». El
            // destino no cambia: el recibo térmico ya existente (`ReceiptPrinterScreen`).
            LiquidGlassButton("Print receipt", variant: .solida, expands: true, systemImage: "printer") {
                shareReceipt = ShareRef(sessionId: session.id)
            }
            .padding(.top, LiquidSpace.s150)

            // copy.md «Acta»: «Listo» va en verde (quisquilloso ronda 4) — mismo CTA, tint Liquid.
            StrandCTAButton("Done", tint: LiquidColor.positivo) { model.closeStrengthSummary() }
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
            withAnimation(LiquidMotion.conteo) { receiptCountUp = true }
        }
        session.receiptCountUpPlayed = true
    }

    /// «Sesión guardada · jue 2 jul» + the data-origin dot for the energy figure (strap Keytel vs MET).
    private func receiptHeader(_ s: StrengthSummary) -> some View {
        HStack(spacing: CenitMetrics.space2) {
            Text("\(String(localized: "Session saved")) · \(receiptDate(s.endTs))")
                .liquidKicker().foregroundStyle(LiquidColor.tinta700)
            Spacer(minLength: CenitMetrics.space2)
            // FER-742: when the watch recorded, its origin line replaces the iPhone's energy-origin dot below.
            if let src = s.energySource, !s.watchRecorded { originRow(src) }
        }
    }

    /// FER-742: the receipt's origin line when the Apple Watch recorded the real FC/kcal and saved the
    /// workout to Health — shown instead of the iPhone's energy-origin dot.
    private var receiptWatchOrigin: some View {
        HStack(spacing: 5) {
            Image(systemName: "applewatch").font(StrandFont.glyph(.chevron)).foregroundStyle(LiquidColor.tinta500)
                .accessibilityHidden(true)
            Text("Heart rate and calories from Apple Watch, saved to Health")
                .font(StrandFont.footnote).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func receiptDate(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts))
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// The data-origin row on the receipt (FER-716): where this session's energy figure came from — the
    /// watch (Keytel, revived FER-226) or an estimate (MET fallback). `.bandCalculated`'s RAW VALUE stays
    /// `"band_calculated"` (persisted, `Training.swift`) — only the human-facing copy changed; the app has
    /// no strap any more (F7 "la banda nunca existió").
    private func originRow(_ src: EnergySource) -> some View {
        HStack(spacing: 5) {
            Circle().fill(src == .bandCalculated ? LiquidColor.verdeCarga : LiquidColor.tinta500)
                .frame(width: 6, height: 6)
            Text(src == .bandCalculated ? "Watch + calculated" : "Estimated")
                .font(StrandFont.footnote).foregroundStyle(LiquidColor.tinta500)
        }
        .accessibilityElement(children: .combine)
    }

    /// The editorial headline: «{rutina}, hecha.» + the session's one honest achievement.
    private func receiptHeadline(_ s: StrengthSummary) -> some View {
        (Text("\(s.routineName), done.") + Text(verbatim: "\n") + Text(verbatim: achievementLine(s)))
            .font(LiquidType.displayL)
            .tracking(LiquidType.displayLTracking)
            .foregroundStyle(LiquidColor.tinta900)
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

    /// The receipt's dominant numeral (FER-87): promotes Effort/21 to a hero — same
    /// `MetricFormat.forMetric(.strain)` grammar as the Hoy hero/sheet (never a bespoke
    /// `String(format:)`), colored `theme.dataStrain` — never the RPE hue (a different datum; see
    /// the enfoque's RPE door in `RoutineSheetLiveFoco.swift` for that one). Without cardiac data
    /// (no Watch, no HR permission, or a session too short) it falls back to the session's duration in
    /// plain `theme.ink` — never invents a strain. `SessionRecoveryCost.cost(sessionStrain:)` (unchanged,
    /// called with no `meanHRRPct` fallback in `AppModel+Strength.swift`) already guarantees
    /// `s.costBand == nil` whenever `s.strain == nil`, so the COST block below stays correctly
    /// hidden with no extra guard.
    ///
    /// FER-226 round 2 (D1): the effort-vs-duration CHOICE is `SessionEffortDisplay.resolve` — this view
    /// only renders whichever case it returns, never re-derives the precedence with its own `if let
    /// strain`. `.durationWithHR`'s avgHr isn't shown IN the hero (it already has its own home in
    /// `receiptStatsThirdSlot`/`receiptStats` below); both duration cases render identically here.
    private func receiptHero(_ s: StrengthSummary) -> some View {
        Group {
            switch SessionEffortDisplay.resolve(strain: s.strain, avgHr: s.avgHr) {
            case .effort(let strain):
                let format = MetricFormat.forMetric(.strain)
                let value = format.numeral(strain)
                let zero = format.numeral(0)
                let numeral = Text(receiptCountUp ? value : zero)
                    .instrumentoHero(76).monospacedDigit().contentTransition(.numericText())
                    .foregroundStyle(LiquidColor.ambar)
                    .lineLimit(1).minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Effort").liquidLabel().foregroundStyle(LiquidColor.tinta500)
                    if reflow, let suffix = format.scaleSuffix {
                        numeral
                        Text(suffix).font(LiquidType.boton).foregroundStyle(LiquidColor.ambar)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            numeral
                            if let suffix = format.scaleSuffix {
                                Text(suffix).font(LiquidType.boton).foregroundStyle(LiquidColor.ambar)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Effort"))
                .accessibilityValue(Text(Self.strainAccessibilityValue(value, scaleSuffix: format.scaleSuffix)))
            case .durationWithHR, .durationOnly:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duration").liquidLabel().foregroundStyle(LiquidColor.tinta500)
                    Text(receiptCountUp ? Self.clock(s.durationS) : "0:00")
                        .instrumentoHero(76).monospacedDigit().contentTransition(.numericText())
                        .foregroundStyle(theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Duration"))
                .accessibilityValue(Text(Self.clock(s.durationS)))
            }
        }
    }

    /// VoiceOver value for the Effort hero — «13.8 of 21», never «13.8 of nil» or a hardcoded scale:
    /// derives the bare number from `MetricFormat`'s own `scaleSuffix` («/ 21») so a future change to
    /// strain's scale can't silently desync the spoken value from the printed one (the exact class of
    /// bug `MetricFormat`'s header doc warns about — one metric, two numbers, two places). `static`
    /// (not `private`) so `CenitUnitTests` can call it directly, same as `Self.clock` below.
    static func strainAccessibilityValue(_ value: String, scaleSuffix: String?) -> String {
        guard let scaleSuffix else { return value }
        let scale = scaleSuffix.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return scale.isEmpty ? value : String(localized: "\(value) of \(scale)")
    }

    /// Which datum fills `receiptStats`' third slot (FER-87) — mutually exclusive with the Effort
    /// hero above, which already shows strain: a session WITH strain never repeats it here (`.sets`
    /// instead); a session withOUT strain but with captured HR still proves the watch was read
    /// (`.avgHr`, FER-498/FER-226); neither → nothing invented (`.none`). Pure and `static` so the
    /// exclusivity itself — not just today's happy path — is what the test locks down.
    ///
    /// FER-226 round 2 (D1): delegates the actual precedence to `SessionEffortDisplay.resolve` (the
    /// SAME call `receiptHero` above makes) instead of re-deriving it — a session's hero and its third
    /// stat slot must never be able to disagree about whether strain, avgHr, or neither applies.
    enum ReceiptStatsThirdSlot: Equatable {
        case sets(Int)
        case avgHr(Int)
        case none
    }

    static func receiptStatsThirdSlot(strain: Double?, setCount: Int, avgHr: Int?) -> ReceiptStatsThirdSlot {
        switch SessionEffortDisplay.resolve(strain: strain, avgHr: avgHr) {
        case .effort: return .sets(setCount)
        case .durationWithHR(let bpm): return .avgHr(bpm)
        case .durationOnly: return .none
        }
    }

    /// The receipt's secondary metrics (FER-87: duración · volumen · series-o-FC-promedio). Strain
    /// and calories moved out — strain is now the hero above (never repeated here), calories moved to
    /// «Guardado en Salud» below. No dashes: a metric without data simply isn't rendered.
    private func receiptStats(_ s: StrengthSummary) -> some View {
        let thirdSlot = Self.receiptStatsThirdSlot(strain: s.strain, setCount: s.setCount, avgHr: s.avgHr)
        let cells = Group {
            receiptStat("Duration", value: Self.clock(s.durationS), zero: "0:00")
            receiptStat("Volume", value: plateNumber(displayWeight(s.volumeKg)), zero: "0",
                        unit: UnitFormatter.massUnit(units))
            switch thirdSlot {
            case .sets(let count):
                receiptStat("Sets", value: "\(count)", zero: "0")
            case .avgHr(let bpm):
                receiptStat("Avg HR", value: "\(bpm)", zero: "0", unit: String(localized: "bpm"))
            case .none:
                EmptyView()
            }
        }
        return Group {
            if reflow {
                VStack(alignment: .leading, spacing: CenitMetrics.gap) { cells }
            } else {
                HStack(alignment: .top, spacing: LiquidSpace.seccionAire) { cells; Spacer(minLength: 0) }
            }
        }
        .padding(.bottom, CenitMetrics.gap)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    private func receiptStat(_ label: LocalizedStringKey, value: String, zero: String,
                             unit: String? = nil, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(receiptCountUp ? value : zero)
                    .font(LiquidType.valorL)
                    .monospacedDigit().contentTransition(.numericText())
                    .foregroundStyle(color ?? LiquidColor.tinta900)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let unit { Text(unit).font(StrandFont.caption).foregroundStyle(LiquidColor.tinta500) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// «Guardado en Salud» (FER-87, new): confirms the session reached Apple Health, with its kcal
    /// when known. Shown only when that's actually true for THIS session — the Watch path always is
    /// (`s.watchRecorded`); the iPhone path is opt-in and off by default, so the call site gates on
    /// `saveStrengthWorkouts` (the same `UserDefaults` key `saveStrengthWorkoutIfEnabled` itself
    /// checks before writing). `StrengthSummary` carries no per-session save-succeeded flag — adding
    /// one is a model change, out of this light-lane phase — so a denied permission after opt-in is
    /// this row's one known blind spot, same as the rest of the app's best-effort Health mirror.
    /// Replaces the retired Diet block (FER-92/E11 already turned Diet into a dead route from Entrenar).
    private func receiptHealthSaved(_ s: StrengthSummary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(LiquidColor.verdeProfundo)
                .accessibilityHidden(true)
            Text(Self.healthSavedText(s)).font(StrandFont.caption).foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The kcal figure carries the same «estimated» qualifier `receiptStats` used to show (FER-715
    /// origin: Keytel over strap HR vs. MET fallback) — moved here so it isn't lost, not dropped.
    /// `static` (not `private`) so `CenitUnitTests` can call it directly, same as `Self.clock` below.
    static func healthSavedText(_ s: StrengthSummary) -> String {
        guard let kcal = s.energyKcal else { return String(localized: "Saved to Health") }
        let kcalInt = Int(kcal.rounded())
        return s.energySource == .estimated
            ? String(localized: "Saved to Health · \(kcalInt) kcal estimated")
            : String(localized: "Saved to Health · \(kcalInt) kcal")
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
            Text("Against your last \(s.routineName)").liquidKicker().foregroundStyle(LiquidColor.tinta700)
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
            Text(label).font(StrandFont.caption).foregroundStyle(LiquidColor.tinta700)
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(LiquidColor.tinta10)
                    Capsule().fill(neutral ? LiquidColor.tinta10 : LiquidColor.verdeCarga)
                        .opacity(neutral || positive ? 1 : 0.75)
                        .frame(width: max(4, w * (current / maxV)))
                    Rectangle().fill(LiquidColor.tinta900).frame(width: 2, height: 14)
                        .offset(x: min(w - 2, max(0, w * (prev / maxV) - 1)))
                }
            }
            .frame(height: 8)
            Text(delta).font(InstrumentoType.groteskNumber(12, weight: .regular))
                .foregroundStyle(positive ? LiquidColor.positivo : LiquidColor.tinta700)
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
        VStack(alignment: .leading, spacing: CenitMetrics.space1) {
            HStack(spacing: CenitMetrics.space2) {
                Image(systemName: "star").font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(LiquidColor.rosa)
                Text(prs.count == 1 ? String(localized: "A personal record")
                     : String(localized: "\(prs.count) personal records"))
                    .font(StrandFont.subhead).fontWeight(.semibold).foregroundStyle(LiquidColor.tinta900)
            }
            .padding(.bottom, CenitMetrics.space1)
            ForEach(Array(prs.enumerated()), id: \.element.id) { i, pr in
                HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.gap) {
                    (Text(verbatim: pr.exercise) + Text(verbatim: " · ") + Text(Self.prMetricLabel(pr.metric)))
                        .font(StrandFont.caption).foregroundStyle(LiquidColor.tinta900)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    (Text(verbatim: prPriorText(pr)).foregroundColor(LiquidColor.tinta700)
                        + Text(verbatim: " → ")
                        + Text(verbatim: prValue(pr)).fontWeight(.semibold).foregroundColor(LiquidColor.tinta900))
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
        .padding(.horizontal, CenitMetrics.cardPadding).padding(.vertical, CenitMetrics.cardPadding)
        .liquidGlass(.superficieSolida)
    }

    /// «Por ejercicio»: one quiet row per exercise — sets · top datum · trend vs «la última vez».
    private func receiptExercises(_ lines: [StrengthSummary.ExerciseLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("By exercise").liquidKicker().foregroundStyle(LiquidColor.tinta700)
                .padding(.bottom, 2)  // token-exempt: ajuste óptico
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                HStack(spacing: CenitMetrics.gap) {
                    Text(line.name).font(StrandFont.subhead).foregroundStyle(LiquidColor.tinta900)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(exerciseLineDetail(line))
                        .font(StrandFont.caption).monospacedDigit().foregroundStyle(LiquidColor.tinta700)
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
                .foregroundStyle(LiquidColor.positivo)
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

    /// Recovery cost (conserves FER-409). FER-87 drops the filled
    /// `patternBlock` box: the active band now reads as its name UNDERLINED in its AA reading-tone
    /// (`OKLab.darkened`, never the raw data hue on text <24pt) among the other two bands, dimmed —
    /// plain ink on paper, no molding. `Self.bandDetail`'s fixed per-band text is unchanged (still no
    /// `SessionRecoveryCost.Result.basis` — `StrengthSummary.costBand` only ever stores the `Band`).
    /// Revisión final (FER-140), hallazgo grave: copy.md «Acta» prohíbe explícitamente cualquier
    /// frase de mañana hasta que exista F4 — `tomorrowPct` ya no se pinta aquí (el dato sigue vivo
    /// en `StrengthSummary.costTomorrowPct` para cuando F4 exista).
    private func receiptCost(_ band: SessionRecoveryCost.Band) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            // Revisión final (g5-copy): copy.md «Acta» manda `COSTO CARDIOVASCULAR` para este rótulo,
            // no «Costo de recuperación» — dos frases distintas para el mismo bloque.
            Text("Cardiovascular cost").liquidLabel().foregroundStyle(LiquidColor.tinta500)
            Group {
                if reflow {
                    VStack(alignment: .leading, spacing: CenitMetrics.space1) {
                        bandNameText(.light, active: band)
                        bandNameText(.moderate, active: band)
                        bandNameText(.high, active: band)
                    }
                } else {
                    HStack(spacing: 14) {
                        bandNameText(.light, active: band)
                        bandNameText(.moderate, active: band)
                        bandNameText(.high, active: band)
                    }
                }
            }
            Text(Self.bandDetail(band)).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Revisión final (g5-copy): copy.md pide solo `estimación`, no «Estimación · tú decides».
            // Clave distinta a la «Estimate» ya existente (es «Estimado», otro contexto) para no
            // colisionar dos entradas iguales en el catálogo.
            Text("Estimate, you decide").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .padding(.top, 2)  // token-exempt: ajuste óptico
        }
        .accessibilityElement(children: .combine)
    }

    /// One name in the LIGERO / MODERADO / ALTO tri-state row — underlined + AA reading-tone when
    /// active, tenue ink otherwise. Inactive names stay OUT of VoiceOver (`accessibilityHidden`) so
    /// the block reads exactly as it did before FER-87: only the active band's name is spoken.
    private func bandNameText(_ b: SessionRecoveryCost.Band, active: SessionRecoveryCost.Band) -> some View {
        let isActive = b == active
        return Text(Self.bandLabel(b))
            .font(StrandFont.caption.weight(isActive ? .semibold : .regular))
            .textCase(.uppercase)
            .underline(isActive)
            .foregroundStyle(isActive
                ? theme.onPaper(bandColor(b))
                : theme.inkTertiary)
            .accessibilityHidden(!isActive)
    }

    /// The beaten record, for the «prior → new» framing. Volume compares totals (kg), matching `prValue`.
    private func prPriorText(_ pr: StrengthSummary.PR) -> String {
        switch pr.metric {
        case .maxWeight: return plateNumber(displayWeight(pr.priorValueKg ?? 0))
        case .maxReps:   return "\(pr.priorReps ?? 0)"
        case .maxVolume: return plateNumber(displayWeight(pr.priorValueKg ?? 0))
        }
    }

    /// «Músculos de hoy» (FER-87): retires the per-muscle chip-with-background (`ChipFlow`) for one
    /// line of running ink text — the muscles are context here, not N separate controls. The only tap
    /// target left is «Ver mapa» (same copy/pattern `WorkoutHistoryScreen` already uses for its own
    /// muscle-map door — toque 44, HIG §8.7-4), which still opens the same fatigue map via
    /// `openFatigueMap()`. The old per-chip hint («Tap a muscle to see when to train it again.») is
    /// retired with it — it described a per-muscle tap that no longer exists.
    private func summaryMuscles(_ muscles: [StrengthSummary.WorkedMuscle]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space2) {
                Text("Today's muscles").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: CenitMetrics.space2)
                Button { openFatigueMap() } label: {
                    Text("See map").font(StrandFont.subhead).foregroundStyle(theme.ink)
                        .frame(minHeight: CenitMetrics.touchTarget)   // toque 44 (HIG §8.7-4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens the fatigue map"))
            }
            // FER-124: los PRINCIPALES en semibold, los de APOYO en normal — «como el handoff».
            // Una sola línea de tinta corrida; el papel lo dice el peso, no un color (el hue no
            // entra aquí: sería un tercer significado en una fila que ya distingue por peso).
            musclesText(muscles)
                .font(StrandFont.subhead).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                // VoiceOver no oye la negrita: nombra el papel en palabras.
                .accessibilityLabel(musclesAccessibilityLabel(muscles))
        }
    }

    /// La línea de músculos con su peso tipográfico: principal semibold, apoyo regular, unidos por «·».
    private func musclesText(_ muscles: [StrengthSummary.WorkedMuscle]) -> Text {
        muscles.enumerated().reduce(Text(verbatim: "")) { acc, pair in
            let (i, m) = pair
            let sep = i == 0 ? Text(verbatim: "") : Text(verbatim: " · ").foregroundStyle(theme.inkTertiary)
            let name = Text(verbatim: m.name).fontWeight(m.isPrimary ? .semibold : .regular)
            return acc + sep + name
        }
    }

    /// Lo que VoiceOver dice: la negrita no se oye, así que el papel va en palabras.
    private func musclesAccessibilityLabel(_ muscles: [StrengthSummary.WorkedMuscle]) -> Text {
        let primary = muscles.filter(\.isPrimary).map(\.name)
        let support = muscles.filter { !$0.isPrimary }.map(\.name)
        var t = Text("Worked: ") + Text(verbatim: primary.joined(separator: ", "))
        if !support.isEmpty {
            t = t + Text(". Support: ") + Text(verbatim: support.joined(separator: ", "))
        }
        return t
    }

    /// Close the summary and hand off to «Entrenar» → fatigue map (no third sheet stacked on the session).
    private func openFatigueMap() {
        tabRouter.openFatigueMap()
        model.closeStrengthSummary()
    }

    // MARK: Summary formatting

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
        switch b {
        case .light: return LiquidColor.positivo
        case .moderate: return LiquidColor.ambar
        case .high: return LiquidColor.negativo
        }
    }

    // MARK: Small builders

    private func finishTapped() {
        confirmFinish = true
    }
    // MARK: Units / formatting

    private func displayWeight(_ kg: Double) -> Double { imperial ? UnitFormatter.kgToPounds(kg) : kg }

    /// Formatea un valor YA convertido (el patrón `plateNumber(displayWeight(x))` de toda esta pantalla).
    /// Enruta por `StrengthDisplay`: la regla de formato vive ahí y solo ahí.
    private func plateNumber(_ v: Double) -> String { StrengthDisplay.displayNumber(v, system: units) }

    /// Un peso en kg, con su unidad («82.5 kg» / «182 lb»).
    private func massString(_ kg: Double, units: UnitSystem) -> String {
        StrengthDisplay.weight(kg, system: units)
    }

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

// MARK: - Live BPM dot (FER-716)


#endif
