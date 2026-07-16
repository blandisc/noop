#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import StrandTraining
import StrandAnalytics
import WhoopProtocol
import WhoopStore

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
    @EnvironmentObject private var model: AppModel
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
    @State private var copiedSetId: String?
    /// FER-936: which exercise's «≡» reorder handle is momentarily emphasised (ember) after picking
    /// «Reordenar» from its menu — a discoverability nudge toward the drag that already reorders.
    @State private var reorderHint: Int?
    /// «Modo mover» (FER-933): every exercise collapses to a compressed row and a `DragGesture` on each
    /// row shows the handoff's «SOLTAR AQUÍ · POSICIÓN N» drop zone. Entered by long-press on any rail row
    /// or the menu's «Reordenar» item; exits via «Listo». A view-layer toggle only — the model is untouched.
    @State private var reorderMode = false
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
    struct PlatesTarget: Identifiable { let id = UUID(); let ei: Int; let weightKg: Double }

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
    private var restingBaseline: Double? { model.repo.days.compactMap(\.restingHr).last.map(Double.init) }
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

    var body: some View {
        Group {
            if nothingToSave {
                nothingToSaveCard
            } else if let summary = session.summary {
                ScrollView {
                    VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                        summaryPhase(summary)
                    }
                    .padding(.horizontal, CenitMetrics.screenPadding)
                    .padding(.top, 18)
                    .padding(.bottom, CenitMetrics.screenPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if isEmptyAdHoc {
                emptyAdHocSession
            } else {
                inlineSession
            }
        }
        .background(theme.paper.ignoresSafeArea())
        .instrumentoTheme(theme)
        // FER-935: hoisted from `emptyAdHocSession` to the shared root so the «＋» rail node also opens
        // the picker in a populated (routine-backed) session, not just the ad-hoc empty state.
        .sheet(isPresented: $showLibraryPicker) {
            VStack(alignment: .leading, spacing: 0) {
                if !session.runs.isEmpty {
                    Text("inserted after the current · today only")
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                        .padding(.horizontal, CenitMetrics.screenPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }
                ExerciseLibraryScreen { picks in
                    showLibraryPicker = false
                    Task { await addExercises(picks) }
                }
            }
            .background(theme.paper.ignoresSafeArea())
            .instrumentoTheme(theme).environmentObject(model.repo).preferredColorScheme(.light)
        }
        .sheet(item: $detailExercise) { ex in
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
        .sheet(item: $changeExercise) { target in
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
        .sheet(item: $restEdit) { edit in
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
        .sheet(item: $platesTarget) { target in
            PlatesScreen(
                theme: theme,
                targetKg: target.weightKg,
                exerciseName: session.runs.indices.contains(target.ei) ? session.runs[target.ei].name : "",
                store: model.plates,
                onInsertWarmup: { sets in
                    session.insertWarmup(exercise: target.ei, sets: sets)
                    platesTarget = nil
                },
                onClose: { platesTarget = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(theme.paper)
        }
        .sheet(item: $rpeTarget) { target in
            RPESheet(theme: theme, target: target,
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
        .sheet(item: $noteTarget) { target in
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
        .fullScreenCover(item: $shareReceipt) { ref in
            if let summary = session.summary {
                ReceiptPrinterScreen(
                    theme: theme,
                    summary: summary,
                    sessionId: ref.sessionId,
                    onClose: { shareReceipt = nil }
                )
                .environmentObject(model)
            }
        }
        .fullScreenCover(isPresented: $focusMode) {
            focusModeView
        }
        // S-2 (FER-830) → FER-837: one destructive-confirmation pattern across the flow, now the
        // «Instrumento» ConfirmCard. The stay-safe verb names its action («Keep training»), never a
        // generic cancel; destructive is always the red outline.
        .instrumentoConfirm(
            isPresented: $confirmFinish,
            title: String(localized: "Finish workout?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            message: session.doneCount == 0
                ? String(localized: "You haven't logged any sets yet.")
                : (session.pendingCount > 0
                   ? String(localized: "\(session.pendingCount) sets aren't logged yet. Save keeps them; discard deletes everything.")
                   : String(localized: "Save keeps this workout. Discard deletes everything you logged.")),
            actions: [
                .init(String(localized: "Save workout"), role: .primary) { model.endStrengthSession(save: true) },
                .init(String(localized: "Keep training"), role: .secondary),
                .init(String(localized: "Discard workout"), role: .destructive) { model.endStrengthSession(save: false) }
            ]
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
    }

    // MARK: Inline session (the default view — the Hevy-style logging table, FER-497)

    private var inlineSession: some View {
        // A flat List (not ScrollView) so each set row gets a real swipe-to-delete; styled down to the
        // warm-paper language — no native separators / background, our own hairlines. FER-497.
        // FER-929: rail + accordion — only the active exercise expands into its table; done/upcoming
        // exercises collapse to one line each, hung off a vertical rail (`railColumn`).
        List {
            // FER-933: modo mover — every exercise compresses to a draggable row with a «SOLTAR AQUÍ ·
            // POSICIÓN N» drop zone; the accordion (`activeExerciseBlock`) stays closed for the duration.
            if reorderMode { reorderModeBar.plainRow(top: CenitMetrics.gap, bottom: 4) }
            ForEach(Array(session.runs.enumerated()), id: \.element.id) { ei, run in
                if !run.skipped {
                    if reorderMode {
                        reorderRow(run, ei: ei).plainRow(top: 4, bottom: 4)
                    } else {
                        switch railState(ei: ei, run: run) {
                        case .active:
                            activeExerciseBlock(run, ei: ei)
                        case .done:
                            doneRow(run, ei: ei)
                                .plainRow(top: 2, bottom: 2)
                                .transition(.opacity)
                        case .upcoming:
                            comingRow(run, ei: ei)
                                .plainRow(top: 2, bottom: 2)
                                .transition(.opacity)
                        }
                    }
                }
            }
            if !reorderMode {
                addExerciseNode.plainRow(top: CenitMetrics.gap)
                if session.isComplete, session.doneCount > 0 { completeFooter.plainRow(top: CenitMetrics.sectionGap) }
                discardFooter.plainRow(top: CenitMetrics.gap, bottom: CenitMetrics.screenPadding)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.paper)
        .environment(\.defaultMinListRowHeight, 1)
        .animation(.snappy(duration: 0.22), value: session.currentIndex)
        .safeAreaInset(edge: .top, spacing: 0) { liveHead }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let cell = activeCell { keypad(for: cell) } else { statsBar }
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
    }

    // MARK: Rail + accordion (FER-929)

    /// One exercise's position relative to the guided focus: active (accordion open), done (all its sets
    /// logged, or its index already passed), or upcoming. Derived purely from `StrengthSessionModel`'s
    /// existing `currentIndex`/`sets.done` — the model itself is untouched.
    private enum RailState { case active, done, upcoming }

    private func railState(ei: Int, run: StrengthSessionModel.ExerciseRun) -> RailState {
        if ei == session.currentIndex { return .active }
        if ei < session.currentIndex || run.sets.allSatisfy(\.done) { return .done }
        return .upcoming
    }

    /// The vertical rail: a 2px hairline (teal for a superset span, `theme.dataHrv`) with one dot per
    /// exercise — or, inside a superset span, an «A1»/«A2» badge in place of the plain dot (FER-931).
    /// Purely decorative — `accessibilityHidden`, the row's own label carries the state to VoiceOver.
    private func railColumn(_ state: RailState, superset: Bool, badgeText: String? = nil) -> some View {
        ZStack {
            Rectangle().fill(superset ? theme.dataHrv : theme.hairlineStrong).frame(width: 2)
            if let badgeText {
                Circle()
                    .fill(theme.dataHrv)
                    .frame(width: state == .active ? 20 : 17, height: state == .active ? 20 : 17)
                    .overlay {
                        Text(badgeText).font(StrandFont.footnote).fontWeight(.semibold)
                            .foregroundStyle(theme.paper)
                    }
                    .opacity(state == .done ? StrandOpacity.dim : 1)
            } else {
                Circle()
                    .fill(state == .active ? theme.dataStrain : state == .done ? theme.inkDim : theme.hairlineStrong)
                    .frame(width: state == .active ? 14 : 11, height: state == .active ? 14 : 11)
                    .opacity(state == .done ? StrandOpacity.dim : 1)
                    .overlay {
                        if state == .active {
                            Circle().strokeBorder(theme.dataStrain.opacity(0.3), lineWidth: 3)  // token-exempt: decorative active-node halo ring alpha
                                .frame(width: 22, height: 22)
                        }
                    }
            }
        }
        .frame(width: 14)
        .accessibilityHidden(true)
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
            withAnimation(.snappy(duration: 0.22)) {
                session.select(exerciseIndex: ei, setIndex: run.sets.firstIndex { !$0.done } ?? 0)
            }
        } label: {
            HStack(spacing: 12) {
                railColumn(.done, superset: session.isInSuperset(ei), badgeText: supersetBadgeText(ei: ei))
                VStack(alignment: .leading, spacing: 1) {
                    supersetTag(ei)
                    Text(run.name).font(StrandFont.body).foregroundStyle(theme.inkTertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(doneDetailText(run)).font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
                    .lineLimit(1)
                Image(systemName: "checkmark.circle.fill")
                    .font(StrandFont.glyph(.chevron)).foregroundStyle(theme.dataRecovery)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(StrandOpacity.dim)
        // FER-933: long-press any rail row to enter modo mover (`simultaneousGesture`, not
        // `.onLongPressGesture`, so the row's own tap-to-reopen keeps working — same pattern as
        // RoutineEditorScreen's reorder entry).
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
            withAnimation(.snappy) { reorderMode = true }
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(supersetAccessibilityLabel(ei: ei, base: "\(run.name), done, \(doneDetailText(run))")))
        .accessibilityHint(Text("Double tap to reopen and correct a set"))
    }

    /// A not-yet-reached exercise, compressed to one line: name + its planned prescription. Tapping moves
    /// the guided focus here (the same `select` the plan navigator already used).
    private func comingRow(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { session.select(exerciseIndex: ei, setIndex: 0) }
        } label: {
            HStack(spacing: 12) {
                railColumn(.upcoming, superset: session.isInSuperset(ei), badgeText: supersetBadgeText(ei: ei))
                VStack(alignment: .leading, spacing: 1) {
                    supersetTag(ei)
                    Text(run.name).font(StrandFont.body).foregroundStyle(theme.ink).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(prescriptionText(run)).font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
                    .lineLimit(1)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // FER-933: same long-press entry into modo mover as `doneRow`.
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
            withAnimation(.snappy) { reorderMode = true }
        })
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
            return "\(run.sets.count) " + String(localized: "series")
        }
        let w = run.sets.first?.weightKg ?? 0
        let reps = run.sets.first?.reps ?? 0
        return "\(massText(w)) × \(reps)"
    }

    /// The active exercise: rail dot + full header, then its set table inside a `surface` card (spec §3),
    /// the inline rest card, and «Add set» — the exact content `inlineSession` rendered per exercise
    /// before FER-929, just no longer repeated for every exercise at once.
    @ViewBuilder private func activeExerciseBlock(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            railColumn(.active, superset: session.isInSuperset(ei), badgeText: supersetBadgeText(ei: ei))
            exerciseHeader(run, ei: ei, first: true)
        }
        .plainRow(top: CenitMetrics.gap)
        ForEach(Array(run.sets.enumerated()), id: \.element.id) { si, set in
            // FER-937: a «SERIES DE TRABAJO» rule separates the collapsible warm-up «C» rows from the
            // numbered work sets — drawn on the first work row that follows a warm-up.
            let afterWarmup = set.kind == .work && si > 0 && run.sets[si - 1].kind == .warmup
            VStack(spacing: 0) {
                if afterWarmup { workSetsDivider.padding(.top, 4).padding(.bottom, 6) }
                setRow(ei: ei, si: si, run: run, set: set, last: si == run.sets.count - 1)
            }
                .activeCardRow(top: si == 0, bottom: si == run.sets.count - 1, theme: theme)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        withAnimation(.snappy) { session.removeSet(exercise: ei, set: si) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
        }
        // The rest card (1k) slots between this exercise's rows and the next, while resting here.
        if session.phase == .resting, ei == session.currentIndex, session.summary == nil {
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
                .plainRow(top: 4)
        }
        addSetButton(ei).plainRow(top: 4)
    }

    /// FER-937: the «SERIES DE TRABAJO» rule between the warm-up «C» rows and the numbered work sets —
    /// two hairlines flanking a quiet overline. A label, not a datum, so it stays in tinted ink.
    private var workSetsDivider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(theme.hairline).frame(height: 1)
            Text("WORK SETS").instrumentoOverline().foregroundStyle(theme.inkDim)
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
        .accessibilityLabel(Text("Work sets"))
    }

    /// The riel's terminal node — a dotted circle affordance that opens the existing ad-hoc add-exercise
    /// flow (`showLibraryPicker` → `addExercises`). Positional insertion is a later child (FER-929 §1).
    private var addExerciseNode: some View {
        Button { showLibraryPicker = true } label: {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(theme.dataStrain, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.dataStrain)  // token-exempt: tiny plus glyph sized to the 18pt dotted add-node
                    )
                Text("Add exercise").font(StrandFont.subhead).foregroundStyle(theme.ink)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
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
            platesEnabled: isWeightCell(cell),
            onDigit: { keypadInput(String($0)) },
            onComma: { keypadComma() },
            onBackspace: { keypadBackspace() },
            onNext: { focusNextCell() },
            onCopyPrevious: { if let run { prefillTapped(ei: ei, si: si, run: run); syncBufferFromModel(cell) } },
            onStep: { keypadStep(cell) },
            onPlates: { openPlates(ei: ei, si: si) }
        )
        .transition(.move(edge: .bottom))
    }

    /// Open the plate calculator (FER-720 · 3a) for a weight cell, seeded with that set's current load.
    private func openPlates(ei: Int, si: Int) {
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return }
        platesTarget = PlatesTarget(ei: ei, weightKg: session.runs[ei].sets[si].weightKg)
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
                    BpmPulseDot(color: theme.dataStrain, animated: !reduceMotion && !session.paused)
                    Text(session.paused ? "Paused" : "In progress")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.leading, -10)   // pull the 44pt chevron target back to the 24pt margin edge

            // Overline: hidden in ad-hoc (no plan to name). No per-day schedule is exposed by
            // `StrengthSessionModel` today, so this counts exercises rather than inventing a day count.
            if !isEmptyAdHoc {
                Text("ROUTINE · \(session.activeExercises.count) EXERCISES")
                    .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)
            }

            // Title, underlined solid `ink` (not the dotted neutral rule reserved for table values).
            Text(isEmptyAdHoc ? String(localized: "Quick strength") : session.routineName)
                .font(StrandFont.title2).foregroundStyle(theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .overlay(alignment: .bottomLeading) {
                    Rectangle().fill(theme.ink).frame(height: 2).offset(y: 3)
                }
                .padding(.bottom, 3)

            // Metrics: clock (dims + freezes while paused, FER-823) · BPM (strap-only, never «♥ --») ·
            // done/total · Spacer · Pausa/Reanuda + Terminar (or Discard for an empty ad-hoc session).
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                    let elapsed = session.elapsedSeconds(now: ctx.date)
                    Text(Self.clock(elapsed))
                        .font(InstrumentoType.groteskSessionClockInline)
                        .tracking(InstrumentoType.groteskSessionClockTracking)
                        .foregroundStyle(session.paused ? theme.inkDim : theme.ink)
                        .accessibilityLabel(Text(session.paused ? "Paused at \(Self.clock(elapsed))"
                                                                 : "Elapsed \(Self.clock(elapsed))"))
                }
                // BPM fused to the clock — the app's one always-on pulse. Hidden (not dashed) with no strap.
                PulseReader(model.live.pulse) { p in
                    if let bpm = p.smoothedBpm {
                        HStack(spacing: 6) {
                            BpmPulseDot(color: theme.dataHeart, animated: !reduceMotion)
                            Text("\(bpm)").font(StrandFont.caption.monospacedDigit()).foregroundStyle(theme.dataHeart)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text("Heart rate \(bpm)"))
                    }
                }
                Text("· \(session.doneCount)/\(sessionSetsTotal)")
                    .font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                headActionButtons
            }

            // Per-exercise progress, a 3px filete (FER-823: no hue while paused). No plan in ad-hoc.
            if !isEmptyAdHoc {
                SessionProgressBar(segments: progressSegments,
                                   hue: session.paused ? theme.inkDim : theme.dataStrain,
                                   track: theme.hairline, height: 3)
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
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    /// The header's right-side action(s), FER-823: paused → «Resume» is the primary action (finish after
    /// resuming); running with sets → a pause toggle sits left of Finish; an empty ad-hoc session only
    /// offers Discard. Unchanged behavior from the pre-FER-929 `sessionHeader` — only its container moved.
    @ViewBuilder private var headActionButtons: some View {
        if session.paused {
            Button { model.resumeStrengthSessionFromPause() } label: {
                Label("Resume", systemImage: "play.fill").labelStyle(.titleAndIcon)
                    .font(StrandFont.subhead).foregroundStyle(theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Resume session"))
        } else if !isEmptyAdHoc {
            Button { model.pauseStrengthSession() } label: {
                Image(systemName: "pause.fill")
                    .font(StrandFont.glyph(.inline, weight: .semibold)).foregroundStyle(theme.ink)
                    .frame(width: 38, height: 38)
                    .background(theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Pause session"))
            // Ending the session is the one destructive-ish act in the header — it carries the
            // reserved alert hue (label + border, never a fill: primary-by-border, DNA §).
            Button { finishTapped() } label: {
                Text("Finish").font(StrandFont.subhead).foregroundStyle(theme.critical)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.critical.opacity(StrandOpacity.dim), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Finish workout"))
        } else {
            Button { discardEmptySession() } label: {
                Text("Discard").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Discard workout"))
        }
    }

    // MARK: _StatsBar (FER-929 — fixed bottom bar; the keypad takes this slot instead while a cell is active)

    private var statsBar: some View {
        VStack(spacing: 8) {
            // Focus mode entry moved here from the old header row (mock v21 → FER-929 §3): full-screen
            // capture/rest; does not replace the inline table.
            if !isEmptyAdHoc && session.summary == nil {
                Button { focusMode = true } label: {
                    Label("Focus mode", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(StrandFont.subhead).foregroundStyle(theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Focus mode"))
                .accessibilityHint(Text("Opens a full-screen set logger"))
            }
            // kg · series · (kcal only with a streaming strap, never dashes) — same source as before.
            Text(counterLine).font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkSecondary)
                .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 10)
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
            HStack {
                if resting { focusRestModeToggle }
                Spacer(minLength: 0)
                Button { focusMode = false } label: {
                    StrandIcon.close.image
                        .font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(resting ? theme.paper : theme.ink)
                        .frame(width: 38, height: 38)
                        .background(resting ? theme.paper.opacity(StrandOpacity.tintFillStrong) : theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(resting ? theme.paper.opacity(StrandOpacity.strokeSoft) : theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close focus mode"))
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
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                    Text(run.name).font(StrandFont.title1).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Set \(run.currentSet + 1) of \(run.sets.count)")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }

                switch run.type {
                case .weightReps:
                    focusWeightHero
                    focusRepsRow
                    focusRegisterButton
                case .bodyweight:
                    focusRepsHero
                    focusAddedWeightRow
                    focusRegisterButton
                case .time:
                    focusTimeControls
                case .distance:
                    focusDistanceControls
                }
            }
        } else {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("All done").font(StrandFont.title1).foregroundStyle(theme.ink)
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
                    .font(StrandFont.title2).monospacedDigit().foregroundStyle(theme.ink)
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
                    .font(StrandFont.title2).monospacedDigit()
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
                session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR)
            }
        } label: {
            Label("Register set", systemImage: "checkmark")
                .font(StrandFont.headline).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CenitMetrics.sectionGap)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
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
                    session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR)
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
                        .font(StrandFont.title2).monospacedDigit().foregroundStyle(theme.ink)
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
                session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR)
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
            Text(focusRestCaption).font(StrandFont.subhead).foregroundStyle(theme.paper.opacity(0.8))  // token-exempt: crema al 0.8 sobre verde · subtítulo del descanso (arriba del techo de muted, FER-934)

            if session.currentRestMode == .heartRate, let started = session.restStartedAt {
                PulseReader(model.live.pulse) { p in
                    TimelineView(.periodic(from: started, by: 1)) { ctx in
                        let elapsed = max(0, Int(ctx.date.timeIntervalSince(started)))
                        let v = RestReadinessRule.evaluate(
                            currentHR: p.smoothedBpm, worn: model.live.worn, restingHR: restingBaseline,
                            elapsedS: elapsed, targetHR: session.currentRestTarget)
                        let noSignal = v.state == .noSignal
                        if (focusRestShowsHR ?? true) && !noSignal {
                            focusRestHRHero(elapsed: elapsed, readiness: v)
                        } else {
                            focusRestTimeHero(end: session.restEndsAt, now: ctx.date, noStrapFallback: noSignal)
                        }
                    }
                }
            } else if let end = session.restEndsAt, let started = session.restStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    focusRestTimeHero(end: end, now: ctx.date, noStrapFallback: false)
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

            focusRestNextCard
        }
    }

    /// «<ejercicio> · serie N ✓» — the just-completed set, for orientation while the screen is all green.
    private var focusRestCaption: String {
        guard session.runs.indices.contains(session.currentIndex) else { return String(localized: "Rest") }
        let run = session.runs[session.currentIndex]
        let doneIndex = run.currentSet - 1
        guard run.sets.indices.contains(doneIndex) else { return run.name }
        let n = run.sets.prefix(doneIndex + 1).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
        return "\(run.name) · " + String(localized: "set \(n)") + " ✓"
    }

    /// Tiempo/FC segmented toggle (FER-934 §3.2) — only shown when the active rest actually resolved a
    /// heart-rate target; a fixed-time rest has nothing to switch to. Defaults to FC (`nil` ≙ true).
    @ViewBuilder private var focusRestModeToggle: some View {
        if session.currentRestMode == .heartRate {
            let showsHR = focusRestShowsHR ?? true
            HStack(spacing: 2) {
                focusRestModeTab(String(localized: "Time"), systemImage: "timer", active: !showsHR) {
                    focusRestShowsHR = false
                }
                focusRestModeTab(String(localized: "HR"), systemImage: "heart.fill", active: showsHR) {
                    focusRestShowsHR = true
                }
            }
            .padding(3)
            .background(theme.paper.opacity(StrandOpacity.tintFillStrong), in: Capsule())
        }
    }

    private func focusRestModeTab(_ label: String, systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(StrandFont.caption).fontWeight(.semibold)
                .foregroundStyle(active ? theme.dataRecovery : theme.paper)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? theme.paper : Color.clear, in: Capsule())
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
        .accessibilityLabel(Text(remaining == 0 ? "Rest done" : "Resting, \(remaining) seconds left"))
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
        Button(action: action) {
            Text(label).font(StrandFont.headline).monospacedDigit().foregroundStyle(theme.paper)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Next").font(StrandFont.caption).fontWeight(.semibold)
                    .tracking(0.8).textCase(.uppercase).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
                if let load, load > 0 {
                    Text("\(run.name) · " + String(localized: "set \(n)") + " · \(massText(load))")
                        .font(StrandFont.subhead).foregroundStyle(theme.paper)
                } else {
                    Text("\(run.name) · " + String(localized: "set \(n)"))
                        .font(StrandFont.subhead).foregroundStyle(theme.paper)
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
            return .init(sets: total, done: Double(done) / Double(total))
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

    // MARK: Exercise header + inline rows

    /// One exercise's header: a type overline (for non-weight×reps), the name, and the column header.
    /// Grouped by whitespace + hairlines — a registration sheet, not a grid.
    private func exerciseHeader(_ run: StrengthSessionModel.ExerciseRun, ei: Int, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            HStack(spacing: 12) {
                SessionRunThumb(exerciseId: run.exerciseId)   // baked still fills the FER-751 slot
                VStack(alignment: .leading, spacing: 2) {
                supersetTag(ei)
                if run.type != .weightReps {
                    Text(typeWord(run.type)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        .accessibilityHidden(true)
                }
                // Tap the name → the exercise's Detail (how-to, trend, records) as a sheet (FER-538).
                Button { openDetail(run) } label: {
                    HStack(spacing: 8) {
                        Text(run.name).font(StrandFont.headline).foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        StrandIcon.disclosure.image
                            .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(run.name))
                .accessibilityHint(Text("View exercise detail"))
                }
                exerciseMenuButton(ei: ei, run: run)
                reorderHandle(ei: ei, run: run)
            }
            // FER-933: long-press the active exercise's header also enters modo mover — same entry as the
            // compressed rail rows (`doneRow`/`comingRow`).
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                withAnimation(.snappy) { reorderMode = true }
            })
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

    private func exerciseMenuItems(ei: Int, run: StrengthSessionModel.ExerciseRun) -> [PaperMenuItem] {
        var rows: [PaperMenuItem] = [
            .init(String(localized: "View exercise"), systemImage: "info.circle") { openDetail(run) },
            .init(String(localized: "Change exercise"), systemImage: "arrow.triangle.2.circlepath") {
                changeExercise = ChangeTarget(ei: ei, run: run)
            },
            .init(String(localized: "Skip exercise"), systemImage: "forward.end") {
                withAnimation(.snappy) { session.skipExercise(ei) }
            },
            // FER-933: «Reordenar» now enters modo mover — the handoff's compressed-rows + «SOLTAR AQUÍ»
            // drag surface — instead of only hinting the header's «≡» handle (FER-936's original wiring).
            .init(String(localized: "Reorder"), systemImage: "line.3.horizontal") {
                withAnimation(.snappy) { reorderMode = true }
            }
        ]
        // Never leave the session empty — the last exercise can only be skipped, not removed.
        if session.runs.count > 1 {
            rows.append(.init(String(localized: "Remove from session"), systemImage: "trash", isDestructive: true) {
                withAnimation(.snappy) { session.removeExercise(at: ei) }
            })
        }
        return rows
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
                Image(systemName: "line.3.horizontal")
                    .font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                Text(run.name).font(StrandFont.body).foregroundStyle(theme.ink).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(run.sets.allSatisfy(\.done) ? doneDetailText(run) : prescriptionText(run))
                    .font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary).lineLimit(1)
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
    private func restChip(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        Button { openRestEditor(ei: ei) } label: {
            HStack(spacing: 6) {
                StrandIcon.clock.image.font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                Text(restChipLabel(run)).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Edit rest"))
        .accessibilityValue(Text(restChipLabel(run)))
    }

    /// Mode-aware chip text: the fixed duration, or «by HR» when the rest is heart-rate driven.
    private func restChipLabel(_ run: StrengthSessionModel.ExerciseRun) -> String {
        run.restMode == .heartRate ? String(localized: "Rest · by HR") : restChipText(run.restSeconds)
    }

    /// The «✎ Nota» chip (FER-932), next to the rest chip on the active exercise's header. Opens
    /// `NoteSheet` without touching `restEndsAt` — a running rest keeps counting behind it. Fills when
    /// this run (or any of its sets) already carries a note.
    private func noteChip(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        Button { openNote(exercise: run, ei: ei) } label: {
            HStack(spacing: 6) {
                Image(systemName: run.hasNote ? "square.and.pencil" : "square.and.pencil")
                    .font(StrandFont.glyph(.chevron)).foregroundStyle(run.hasNote ? theme.dataStrain : theme.inkTertiary)
                Text("Note").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                if run.hasNote {
                    Circle().fill(theme.dataStrain).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
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
        return HStack(spacing: 8) {
            Text("SET").instrumentoOverline().foregroundStyle(theme.inkTertiary).frame(width: 44, alignment: .center)
            Text("PREVIOUS · REST").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(titles.indices, id: \.self) { i in
                Text(titles[i]).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .frame(width: cellWidth(type), alignment: .center)
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
    private func cellWidth(_ type: ExerciseType) -> CGFloat {
        switch type {
        case .weightReps: return 56
        case .bodyweight: return 60
        case .time:       return 70
        case .distance:   return 56
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
        .padding(.horizontal, active ? 6 : 0)
        .background(active ? theme.surface : .clear,
                    in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
        .overlay {
            // FER-938: a dashed ember outline marks a just-copied, not-yet-logged set.
            if set.id == copiedSetId, !set.done {
                RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.dataStrain, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(theme.hairline).frame(height: 1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            Button("Delete set") { withAnimation(.snappy) { session.removeSet(exercise: ei, set: si) } }
        }
    }

    private func gridRow(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                         set: StrengthSessionModel.WorkingSet) -> some View {
        HStack(spacing: 8) {
            badge(run: run, si: si)
            if set.id == copiedSetId, !set.done, si > 0 {
                // FER-938: the freshly-added set advertises where its values came from, in place of «anterior».
                let fromNumber = run.sets.prefix(si).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
                Text("COPIED FROM \(fromNumber)").instrumentoOverline().foregroundStyle(theme.dataStrain)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                previousCell(ei: ei, si: si, run: run)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            previousCell(ei: ei, si: si, run: run)
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
                running ? session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR)
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
                Text("\(hr)").font(StrandFont.subhead.monospacedDigit()).foregroundStyle(theme.ink)
                Text("·").foregroundStyle(theme.inkTertiary)
                Text("\(pct)% of your max").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
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
                Text(distanceNumber(meters)).font(StrandFont.number(18, weight: .regular)).monospacedDigit()
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
                        let elapsed = max(0, Int(ctx.date.timeIntervalSince(started)))
                        let v = RestReadinessRule.evaluate(
                            currentHR: p.smoothedBpm, worn: model.live.worn, restingHR: restingBaseline,
                            elapsedS: elapsed, targetHR: session.currentRestTarget)
                        if v.state == .noSignal {
                            restCardTimeBody(end: session.restEndsAt, now: ctx.date, noStrapFallback: true)
                        } else {
                            restCardHRBody(elapsed: elapsed, readiness: v)
                        }
                    }
                    .sensoryFeedback(.success, trigger: p.smoothedBpm != nil && session.currentRestTarget != nil)
                }
            } else if let end = session.restEndsAt, let started = session.restStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    restCardTimeBody(end: end, now: ctx.date, noStrapFallback: false)
                }
            }
            restCardPills
        }
        .padding(.horizontal, 17).padding(.vertical, 15)
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
                Text("Resting · by HR").font(StrandFont.caption).fontWeight(.semibold)
                    .tracking(0.8).textCase(.uppercase).foregroundStyle(theme.dataStrain)
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
                Text(noStrapFallback ? "Resting · by time" : "Resting")
                    .font(StrandFont.caption).fontWeight(.semibold)
                    .tracking(0.8).textCase(.uppercase).foregroundStyle(theme.dataStrain)
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
        return Text(label).font(StrandFont.caption).monospacedDigit()
            .foregroundStyle(isWarmup ? theme.dataStrain.opacity(StrandOpacity.dim) : theme.dataStrain)  // token-exempt: warm-up badge tenue (handoff «C»)
            .frame(width: 26, height: 26)
            .overlay(Circle().strokeBorder(theme.dataStrain.opacity(isWarmup ? StrandOpacity.dim : 1), lineWidth: 1.5))  // token-exempt: warm-up ring tenue
            .frame(width: reflow ? 26 : 44, height: reflow ? 26 : 44, alignment: .center)
            .accessibilityLabel(Text(isWarmup ? "Warm-up set" : "Set \(workNumber)"))
    }

    /// «ANTERIOR · DESCANSO» — last time's value + this set's own rest (FER-716, per-set since F0);
    /// tap to copy last time into this row. «—» (and inert) when there's neither.
    @ViewBuilder private func previousCell(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun) -> some View {
        let rest = shortRest(run.effectiveRest(forSet: si))
        if let text = previousText(run) {
            Button { prefillTapped(ei: ei, si: si, run: run) } label: {
                Text(reflow ? "Previous: \(text)" : "\(text) · \(rest)")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Previous, \(text)"))
            .accessibilityHint(Text("Copies it to this set"))
        } else {
            Text(verbatim: "— · \(rest)").font(StrandFont.caption).foregroundStyle(theme.inkDim) // token-exempt: glifo «sin registro previo» (—), no es copy conector
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityLabel(Text("No previous record"))
        }
    }

    /// A set's rest, compressed for the ANTERIOR cell: «2 min» / «90 s» / «por FC».
    private func shortRest(_ config: RestConfig) -> String {
        guard config.mode != .heartRate else { return String(localized: "by HR") }
        if config.seconds >= 60, config.seconds % 60 == 0 { return "\(config.seconds / 60) min" }
        return "\(config.seconds) s"
    }

    /// The editable / captured data columns, by exercise type.
    @ViewBuilder private func dataCells(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                                        set: StrengthSessionModel.WorkingSet) -> some View {
        switch run.type {
        case .weightReps:
            numberCell(.weight(ei, si), value: displayWeight(set.weightKg), isInt: false, done: set.done, type: run.type)
            numberCell(.reps(ei, si), value: Double(set.reps), isInt: true, done: set.done, type: run.type)
            rpeCell(ei: ei, si: si, run: run, set: set)
        case .bodyweight:
            HStack(spacing: 1) {
                Text("+").font(StrandFont.body).foregroundStyle(set.done ? theme.inkSecondary : theme.inkTertiary)
                numberCell(.weight(ei, si), value: displayWeight(set.weightKg), isInt: false, done: set.done, type: run.type, width: run.type == .bodyweight ? 48 : 56)
            }
            .frame(width: reflow ? nil : cellWidth(run.type), alignment: reflow ? .leading : .center)
            numberCell(.reps(ei, si), value: Double(set.reps), isInt: true, done: set.done, type: run.type)
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
                            type: ExerciseType, width: CGFloat? = nil) -> some View {
        let active = activeCell == ref
        let shown = active ? buffer : formatCell(value, isInt: isInt)
        return Button { activeCell = ref } label: {
            HStack(spacing: 1) {
                Text(shown.isEmpty ? " " : shown)
                    .font(StrandFont.number(16, weight: .regular)).monospacedDigit()
                    .foregroundStyle(done ? theme.inkSecondary : theme.ink)
                if active {
                    Rectangle().fill(theme.ink).frame(width: 2, height: 18)   // caret
                        .opacity(0.9) // token-exempt: opacidad de caret >0.70
                }
            }
            .frame(width: width ?? (reflow ? 64 : cellWidth(type)), height: 44)
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
                        .font(StrandFont.number(16, weight: .regular)).monospacedDigit()
                        .foregroundStyle(theme.dataEffort)
                } else {
                    Text("RPE").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                }
            }
            .frame(width: reflow ? nil : cellWidth(run.type), height: 44)
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
                    Text(text).font(StrandFont.number(16, weight: .regular)).monospacedDigit().foregroundStyle(theme.ink)
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
                if isActivePending { activeCell = nil; session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR) }
                else { session.toggleDone(exercise: ei, set: si) }
            }
        } label: {
            Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                .font(StrandFont.glyph(.lead))
                .foregroundStyle(set.done ? theme.dataRecovery
                                 : isActivePending ? theme.dataStrain : theme.inkDim)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: reflow ? nil : 44)
        .accessibilityLabel(Text(set.done ? "Mark set \(si + 1) as not done" : "Mark set \(si + 1) as done"))
    }

    private func addSetButton(_ ei: Int) -> some View {
        Button {
            withAnimation(.snappy) { session.addSet(exercise: ei) }
            copiedSetId = session.runs.indices.contains(ei) ? session.runs[ei].sets.last?.id : nil  // FER-938
        } label: {
            Label("Add set", systemImage: "plus")
                .font(StrandFont.subhead).foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(theme.paper, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
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
        Button(role: .destructive) { confirmDiscard = true } label: {
            Text("Discard workout").font(StrandFont.subhead).foregroundStyle(theme.critical)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            return "\(massText(w)) × \(r)"
        case .bodyweight:
            guard let r = run.lastReps else { return nil }
            let w = run.lastWeightKg ?? 0
            return "+\(plateNumber(displayWeight(w))) × \(r)"
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
            Text(session.doneCount > 0 ? "All done" : "Nothing left")
                .font(StrandFont.title1).foregroundStyle(theme.ink)
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
            Text(delta).font(StrandFont.caption).monospacedDigit()
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
                        .font(StrandFont.caption).monospacedDigit()
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
        self
            .listRowInsets(EdgeInsets(top: top, leading: CenitMetrics.screenPadding,
                                      bottom: bottom, trailing: CenitMetrics.screenPadding))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// FER-929: the active exercise's set table lives inside one `surface` card (spec §3) — `top`/`bottom`
    /// round only the first/last row's corresponding corners so the stack of rows reads as one card.
    func activeCardRow(top: Bool, bottom: Bool, theme: InstrumentoTheme) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: top ? CenitMetrics.cardRadius : 0,
            bottomLeadingRadius: bottom ? CenitMetrics.cardRadius : 0,
            bottomTrailingRadius: bottom ? CenitMetrics.cardRadius : 0,
            topTrailingRadius: top ? CenitMetrics.cardRadius : 0)
        return self
            .listRowInsets(EdgeInsets(top: 0, leading: CenitMetrics.screenPadding,
                                      bottom: 0, trailing: CenitMetrics.screenPadding))
            .listRowBackground(shape.fill(theme.surface).overlay(shape.strokeBorder(theme.hairline, lineWidth: 1)))
            .listRowSeparator(.hidden)
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
