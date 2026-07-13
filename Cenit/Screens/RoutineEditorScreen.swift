#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// MARK: - «Rutina» — the ONE prescription editor (FER-839, handoff entrenamiento-v4 §2, screens 3a/4a/4b)
//
// Seeing, editing and starting a routine are no longer separate modes: this screen IS the routine, and you
// edit what you see. It generalizes the plan-day editor's table (1o, FER-747) and absorbs the read-only
// «Rutina de hoy» (FER-343) — both screens died here. Only the chrome changes per origin (mock 4a):
//
//   .today    → overline «Rutina de hoy · {día}» + CTA «Empezar»   (landing plan rows, empty-session fallback)
//   .planDay  → overline «Editando · {día}»      (autosave on exit; no explicit Save CTA)
//   .routine  → overline «Rutina»                (autosave on exit; no explicit Save CTA)
//
// The FER-A..G progression wiring survives the merge: the .today origin evaluates `ProgressionPlanner` per
// opted-in slot (history + plates + today's recovery) and hands `raise` to the session's PlanSlots, exactly
// like «Rutina de hoy» did. Guards: Notes-style autosave on exit for every origin (dirty → persist on back),
// a «Saved»/Undo chrome driven off the load-time `itemsSnapshot`, and a live session locks every editing
// surface (cells, menus, swipes) — resuming is the only action then.

/// Pushed onto the Entrenar stack to open «Rutina» with its origin chrome. One route type replaces the old
/// `RoutineRoute`/`PlanDayRoute` pair (a distinct `Hashable` per FER-171 still holds: this is one type).
enum RoutineEditorRoute: Hashable {
    /// Today's routine (nil id = resolve today's pick) — CTA «Empezar».
    case today(routineId: String?)
    /// One weekday of the plan (Calendar convention, 1 = Sun … 7 = Sat) — autosave on exit.
    case planDay(weekday: Int)
    /// A routine from «Mis rutinas» — autosave on exit.
    case routine(routineId: String)
}

struct RoutineEditorScreen: View {
    let origin: RoutineEditorRoute

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mediaCoordinator: MediaDownloadCoordinator
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State private var loaded = false
    @State private var routine: Routine?
    @State private var items: [EditorItem] = []
    /// Every routine, for the .planDay header «Change routine» picker.
    @State private var allRoutines: [Routine] = []
    /// Whether the prescription changed since load (drives save-on-exit, «Saved» status, and Undo).
    @State private var dirty = false
    /// Load-time copy of `items` — Undo restores this and re-persists so disk matches the reverted state.
    @State private var itemsSnapshot: [EditorItem] = []
    @State private var restTarget: RestEditTarget? = nil
    /// Which exercise's progression plan is being edited (2c push); nil = none.
    @State private var progressionTarget: ProgressionTarget? = nil
    @State private var showLibrary = false
    /// nil = the library appends; an index = it replaces that exercise (keeping its sets).
    @State private var replaceIndex: Int? = nil
    // FER-837: which «···» paper menu is open (the day's, or an exercise index).
    @State private var showDayMenu = false
    @State private var menuExerciseIndex: Int? = nil
    /// The exercise whose detail sheet is open (tap the name, parity with the library).
    @State private var detailExercise: Exercise? = nil
    /// The plate inventory: progression evaluation + the 2c increment hint.
    @StateObject private var plates = PlatesStore()
    /// Drag-reorder mode (6a, FER-841): every row compacts to thumb + name + summary and the set tables
    /// fold away; dropping reopens them. Entered by long-pressing an exercise header.
    @State private var reordering = false
    /// The routine hue + group label — refreshed by `refreshTint()` only when the exercise set changes,
    /// never per render (the ring in every set row reads the tint; see `dominantGroup`).
    @State private var routineTint: Color = .clear
    @State private var groupTitle: String = ""
    @FocusState private var focusedCell: String?

    /// A live guided session locks every editing surface (cells, menus, swipes) — the prescription under
    /// a running session must not shift (handoff guard).
    private var locked: Bool { model.strengthSession != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            if loaded, routine != nil {
                editor
            } else {
                Spacer()
                if loaded { emptyFallback }
                Spacer()
            }
        }
        .background(theme.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedCell = nil }.foregroundStyle(theme.ink)
            }
        }
        // 1e as a push: the shared rest editor edits one set's rest with a «this set / all sets» scope.
        // Changes land on the routine with the screen's own save flow, so the routine toggle is off.
        .navigationDestination(item: $restTarget) { t in
            RestEditorScreen(
                theme: theme,
                exerciseName: StrengthDisplay.name(items[t.ei].exercise),
                setNumber: RoutineSetEditing.workSetNumber(items[t.ei].re, t.si),
                current: RoutineSetEditing.effectiveRest(items[t.ei].re, t.si),
                persistsToRoutine: false,
                restingHR: nil, maxHR: nil,
                defaultApplyToAll: false,
                onCancel: { restTarget = nil },
                onApply: { config, applyToAll, _ in
                    RoutineSetEditing.applyRest(to: &items[t.ei].re, si: t.si, config: config, applyToAll: applyToAll)
                    dirty = true
                    restTarget = nil
                }
            )
            .toolbar(.hidden, for: .navigationBar)
        }
        // 2c as a push: the per-exercise progression plan (menu «···» → Progresión, mock 4b).
        .navigationDestination(item: $progressionTarget) { t in
            let ex = items[t.ei].exercise
            ProgressionSetupScreen(
                theme: theme,
                exercise: items[t.ei].re,
                exerciseName: StrengthDisplay.name(ex),
                currentWeightKg: items[t.ei].re.plannedSets.first { $0.kind == .work }?.weightKg,
                derivedIncrementKg: PlateMath.minimumIncrement(
                    for: .from(equipment: ex.equipment), inventory: plates.inventory),
                onBack: { progressionTarget = nil },
                onSave: { enabled, targetReps, sessions, incrementKg, deload, ignoreRecovery in
                    items[t.ei].re.progressionEnabled = enabled
                    items[t.ei].re.progressionSessions = sessions
                    items[t.ei].re.progressionIncrementKg = incrementKg
                    items[t.ei].re.progressionDeload = deload
                    items[t.ei].re.progressionIgnoreRecovery = ignoreRecovery
                    dirty = true
                    // The rep goal IS RoutineSet.reps (no ranges): with the plan on, write it onto
                    // every work set. Off, the prescription stays whatever the user typed.
                    guard enabled else { return }
                    for si in items[t.ei].re.sets.indices where items[t.ei].re.sets[si].kind == .work {
                        items[t.ei].re.sets[si].reps = targetReps
                    }
                }
            )
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showLibrary) {
            ExerciseLibraryScreen { picks in addOrReplace(with: picks) }
                .instrumentoTheme(theme).environmentObject(repo).environmentObject(mediaCoordinator).preferredColorScheme(.light)
        }
        // Tap an exercise's name/thumb to read its detail (Progreso + Records) — parity with the library.
        .sheet(item: $detailExercise) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { detailExercise = nil }.foregroundStyle(theme.ink)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
            }
            .instrumentoTheme(theme).environmentObject(repo).environmentObject(mediaCoordinator).preferredColorScheme(.light)
        }
        .task {
            guard !loaded else { return }
            await load()
            loaded = true
        }
    }

    // MARK: - Origin chrome (mock 4a)

    private var overline: String {
        switch origin {
        case .today:            return String(localized: "Today's routine") + " · " + shortWeekday
        case .planDay(let wd):  return String(localized: "Editing") + " · " + weekdayName(wd)
        case .routine:          return String(localized: "Routine")
        }
    }

    private var ctaTitle: String {
        // Only `.today` still pins a CTA («Empezar»/«Resume»); other origins autosave on exit.
        locked ? String(localized: "Resume") : String(localized: "Empezar")
    }

    private var startsSession: Bool { if case .today = origin { return true } else { return false } }
    private var isPlanDay: Bool { if case .planDay = origin { return true } else { return false } }

    // MARK: - Header (own back + Saved/Undo, over the hidden nav bar)

    private var header: some View {
        HStack(spacing: 8) {
            Button { back() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(StrandFont.glyph(.inline, weight: .semibold))
                    Text("Back").font(StrandFont.body)
                }
                .foregroundStyle(theme.ink).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(Text("Back"))
            Spacer()
            if dirty {
                Button { undo() } label: {
                    Text(String(localized: "Undo")).font(StrandFont.body).foregroundStyle(theme.ink)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: "Undo")))
            } else if loaded {
                Text(String(localized: "Saved"))
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
    }

    // MARK: - Editor (title + meta + per-exercise tables + pinned CTA)

    private var editor: some View {
        List {
            titleBlock.plainRow(top: 6, bottom: 6)
            if reordering { reorderList } else { fullList }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.paper)
        .environment(\.defaultMinListRowHeight, 1)
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        // Only `.today` starts a guided session; `.routine`/`.planDay` rely on autosave + header status.
        .safeAreaInset(edge: .bottom) { if startsSession { ctaBar } }
    }

    @ViewBuilder
    private var fullList: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { idx, _ in
                if firstOfGroup(idx) {
                    Text("Superset").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        .plainRow(top: CenitMetrics.sectionGap, bottom: 2)
                }
                exerciseHeader(idx)
                    .plainRow(top: firstOfGroup(idx) || idx == 0 ? CenitMetrics.gap : CenitMetrics.sectionGap)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !locked {
                            Button { duplicate(idx) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                .tint(theme.inkSecondary)
                        }
                    }
                ForEach(Array(items[idx].re.sets.enumerated()), id: \.element.id) { si, _ in
                    setRow(idx: idx, si: si).plainRow(top: 0, bottom: 0)
                        .swipeActions(edge: .trailing) {
                            if !locked {
                                Button(role: .destructive) { deleteSet(idx: idx, si: si) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
                if !locked { addSetRow(idx).plainRow(top: 4) }
            }
        if !locked { addExerciseRow.plainRow(top: CenitMetrics.sectionGap, bottom: CenitMetrics.screenPadding) }
    }

    // MARK: - Drag reorder (6a, FER-841)
    //
    // A block = one exercise, or a whole superset (consecutive exercises sharing `supersetGroup`) —
    // a superset always travels as ONE unit; breaking it stays a «···» action, never a drag side effect.
    // `List.onMove` does the dragging (the lifted preview mirrors the compact card row); dropping
    // flattens the blocks back into `items`, marks the prescription dirty (order persists in `position`
    // through the screen's normal save flow) and leaves the mode so the tables reopen.

    private struct ReorderBlock: Identifiable {
        let items: [EditorItem]
        var id: String { items[0].id }
        var isSuperset: Bool { items.count > 1 }
    }

    private var reorderBlocks: [ReorderBlock] {
        var blocks: [ReorderBlock] = []
        var i = 0
        while i < items.count {
            var run = [items[i]]
            if let g = items[i].re.supersetGroup {
                while i + 1 < items.count, items[i + 1].re.supersetGroup == g {
                    i += 1; run.append(items[i])
                }
            }
            blocks.append(ReorderBlock(items: run))
            i += 1
        }
        return blocks
    }

    @ViewBuilder
    private var reorderList: some View {
        ForEach(reorderBlocks) { block in
            // The List's reorder LIFT snapshots only the row CONTENT (not `listRowBackground`) and floats
            // it over a system-white platter — so a clear-margin row shows white around the card while
            // dragging (FER-847 round 2). Fix: make the content itself full-bleed OPAQUE paper — the
            // screen margin moves INSIDE as padding and a paper fill spans edge-to-edge — so the lifted
            // snapshot is paper, hiding the platter. Resting rows look identical (List bg is paper too).
            compactBlock(block)
                .padding(.horizontal, CenitMetrics.screenPadding)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.paper)
                .listRowInsets(EdgeInsets())
                .listRowBackground(theme.paper)
                .listRowSeparator(.hidden)
        }
        .onMove(perform: moveBlocks)
        Button { withAnimation(.snappy) { reordering = false } } label: {
            Text("Done reordering").font(StrandFont.subhead).foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .center).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .plainRow(top: CenitMetrics.gap, bottom: 2)
        Text("Drop to place. The sets come back when you let go.")
            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .plainRow(top: 0, bottom: CenitMetrics.screenPadding)
    }

    /// The compact card the drag lifts: thumb + name + «N sets · top kg» per exercise; a superset adds
    /// its teal left bar + «superset» overline and moves as one card.
    private func compactBlock(_ block: ReorderBlock) -> some View {
        HStack(spacing: 10) {
            if block.isSuperset {
                Capsule().fill(theme.dataHrv).frame(width: 2.5)
            }
            VStack(alignment: .leading, spacing: 8) {
                if block.isSuperset {
                    Text("Superset").instrumentoOverline().foregroundStyle(theme.dataHrv)
                }
                ForEach(block.items) { item in
                    HStack(spacing: 10) {
                        ExerciseThumbView(exercise: item.exercise, side: 28)
                        Text(StrengthDisplay.name(item.exercise))
                            .font(StrandFont.subhead).foregroundStyle(theme.ink).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(compactSummary(item.re))
                            .font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(theme.paper, in: RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous).strokeBorder(theme.hairlineStrong))
    }

    /// «3 sets · 90 kg» — work sets + the top work weight (weight omitted when none is set).
    private func compactSummary(_ re: RoutineExercise) -> String {
        let work = re.sets.filter { $0.kind == .work }
        var s = String(localized: "\(work.count) sets")
        if let top = work.compactMap(\.weightKg).max(), top > 0 {
            s += " · \(StrengthDisplay.weightNumber(top, system: system)) \(StrengthDisplay.weightUnit(system).lowercased())"
        }
        return s
    }

    private func moveBlocks(from source: IndexSet, to destination: Int) {
        var blocks = reorderBlocks
        blocks.move(fromOffsets: source, toOffset: destination)
        withAnimation(.snappy) {
            items = blocks.flatMap(\.items)
            reordering = false        // dropping reopens the tables (6a)
        }
        dirty = true
    }

    /// Overline per origin, the routine title underlined 2 px ink, and the dotted meta line.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(overline).groteskOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                if isPlanDay { dayMenu }
            }
            Text(routine?.name ?? "")
                .font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottomLeading) {
                    Rectangle().fill(theme.ink).frame(height: 2).offset(y: 5)
                }
            metaLine
        }
    }

    /// The dotted meta: routine hue dot + «{group} · N exercises · M sets · ~T min».
    private var metaLine: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(routineTint).frame(width: 8, height: 8)
                Text(groupTitle).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Text(String(localized: "\(items.count) exercises")).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            Text(String(localized: "\(totalSets) sets")).font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
            Text(String(localized: "~\(estimatedMinutes) min")).font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
        }
        .padding(.top, 2)
    }

    /// .planDay header «···»: assign/clear the day (choque 9 — «conserva lo callado»).
    private var dayMenu: some View {
        Button { showDayMenu = true } label: {
            Image(systemName: "ellipsis").font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(theme.inkTertiary).frame(width: 40, height: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Day options"))
        .disabled(locked)
        .paperMenu(isPresented: $showDayMenu, items: [
            .init(String(localized: "Change routine"), systemImage: "arrow.left.arrow.right",
                  children: allRoutines.map { r in
                      PaperMenuItem(r.name, systemImage: r.id == routine?.id ? "checkmark" : nil) { changeRoutine(to: r) }
                  }),
            .init(String(localized: "Mark as rest day"), systemImage: "moon.zzz", isDestructive: true) { markRest() }
        ])
    }

    // MARK: - Exercise header (thumb + tappable name + «···» + column header)

    private func exerciseHeader(_ idx: Int) -> some View {
        let item = items[idx]
        return VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            HStack(spacing: 11) {
                Button { detailExercise = item.exercise } label: {
                    ExerciseThumbView(exercise: item.exercise, side: 40)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens the exercise"))
                VStack(alignment: .leading, spacing: 1) {
                    Button { detailExercise = item.exercise } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            if item.exercise.type != .weightReps {
                                Text(StrengthDisplay.subtitle(item.exercise)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                            }
                            Text(StrengthDisplay.name(item.exercise)).font(StrandFont.headline).foregroundStyle(theme.ink)
                                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens the exercise"))
                    // Progression chip under the name (mock v8) — same destination as «···» → Progression.
                    if item.re.progressionEnabled {
                        Button { progressionTarget = ProgressionTarget(ei: idx) } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up")
                                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                                Text(progressionSummary(item.re))
                                    .font(StrandFont.caption)
                            }
                            .foregroundStyle(theme.dataRecovery)
                        }
                        .buttonStyle(.plain)
                        .disabled(locked)
                    }
                }
                Spacer(minLength: 8)
                if !locked { exerciseMenu(idx) }
            }
            columnHeader(item.exercise.type)
        }
        // Long-press enters reorder mode (6a): rows compact, ≡ handles appear, one drop reorders and
        // leaves the mode. `simultaneousGesture` — NOT `.onLongPressGesture` — because the row is mostly
        // Buttons (name → detail, «···» → menu) and a plain gesture never fires over them (FER-846);
        // simultaneous lets a short tap keep opening those while a ~0.4 s hold enters the mode.
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
            guard !locked else { return }
            focusedCell = nil
            withAnimation(.snappy) { reordering = true }
        })
        .accessibilityAction(named: Text("Reorder exercises")) {
            guard !locked else { return }
            withAnimation(.snappy) { reordering = true }
        }
    }

    /// The «···» menu, FINAL order (mock 4b). No «move» — reordering is drag-only (FER-841);
    /// «Duplicate» lives in the swipe.
    private func exerciseMenu(_ idx: Int) -> some View {
        Button { menuExerciseIndex = idx } label: {
            Image(systemName: "ellipsis").font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(theme.inkTertiary).frame(width: 32, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .paperMenu(
            isPresented: Binding(get: { menuExerciseIndex == idx },
                                 set: { if !$0 { menuExerciseIndex = nil } }),
            items: exerciseMenuItems(idx)
        )
    }

    /// The «···» rows, FINAL order (mock 4b). The active progression plan rides as the row's
    /// subtitle («+2,5 kg cada 2 ✓»).
    private func exerciseMenuItems(_ idx: Int) -> [PaperMenuItem] {
        let item = items[idx]
        var rows: [PaperMenuItem] = []
        // «Add warm-up» is a visible button next to «Add set» when none exist yet — not in the menu.
        let res = items.map(\.re)
        if idx < items.count - 1 && !RoutineSetEditing.sameGroup(res, idx, idx + 1) {
            rows.append(.init(String(localized: "Superset with next"), systemImage: "link") { supersetWithNext(idx) })
        }
        if RoutineSetEditing.inSuperset(res, idx) {
            rows.append(.init(String(localized: "Break superset"), systemImage: "link.badge.plus") { breakSuperset(idx) })
        }
        rows.append(.init(String(localized: "Replace exercise"), systemImage: "arrow.triangle.2.circlepath") {
            replaceIndex = idx; showLibrary = true
        })
        if item.exercise.type == .weightReps {
            rows.append(.init(String(localized: "Progression"),
                              subtitle: item.re.progressionEnabled ? progressionSummary(item.re) : nil,
                              systemImage: "chart.line.uptrend.xyaxis") {
                progressionTarget = ProgressionTarget(ei: idx)
            })
        }
        // A discoverable door into the drag mode (FER-847) — still no «move up/down»: the row only
        // enters the same drag-to-reorder the long-press does.
        rows.append(.init(String(localized: "Reorder exercises"), systemImage: "line.3.horizontal") {
            focusedCell = nil
            withAnimation(.snappy) { reordering = true }
        })
        rows.append(.init(String(localized: "Remove from routine"), systemImage: "trash", isDestructive: true) {
            deleteExercise(idx)
        })
        return rows
    }

    /// «+2,5 kg cada 2 ✓» — the active plan named in the menu row (mock 4b). Without an explicit
    /// increment (auto from plates), the row just marks the plan as on.
    private func progressionSummary(_ re: RoutineExercise) -> String {
        guard let inc = re.progressionIncrementKg else {
            return String(localized: "Progression · on")
        }
        let unit = StrengthDisplay.weightUnit(system).lowercased()
        return "+\(StrengthDisplay.weightNumber(inc, system: system)) \(unit) "
            + String(localized: "every \(re.progressionSessions)") + " ✓"
    }

    @ViewBuilder
    private func columnHeader(_ type: ExerciseType) -> some View {
        HStack(spacing: 8) {
            Text("SET").groteskOverline(small: true).foregroundStyle(theme.inkTertiary)
                .lineLimit(1).minimumScaleFactor(0.7).frame(width: 40, alignment: .center)
            if showsWeight(type) {
                Text(StrengthDisplay.weightUnit(system)).groteskOverline(small: true).foregroundStyle(theme.inkTertiary).frame(width: 78)
            }
            if showsReps(type) {
                Text("Reps").groteskOverline(small: true).foregroundStyle(theme.inkTertiary).frame(width: 58)
            }
            Spacer(minLength: 0)
            Text("Rest").groteskOverline(small: true).foregroundStyle(theme.inkTertiary)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    // MARK: - A set row (numeral ring in the routine hue + editable cells + rest chip)

    private func setRow(idx: Int, si: Int) -> some View {
        let set = items[idx].re.sets[si]
        let type = items[idx].exercise.type
        let rest = RoutineSetEditing.effectiveRest(items[idx].re, si)
        return HStack(spacing: 8) {
            numeralRing(idx: idx, si: si).frame(width: 40)
            if showsWeight(type) {
                cellField(weightText(idx: idx, si: si), id: "\(set.id)-w", keyboard: .decimalPad, width: 78)
            }
            if showsReps(type) {
                cellField(repsText(idx: idx, si: si), id: "\(set.id)-r", keyboard: .numberPad, width: 58)
            }
            // «la última vez» — grey history from session seed, one entry per set position.
            if let prev = lastSetHistoryLabel(idx: idx, si: si, type: type) {
                Text(prev)
                    .font(StrandFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(theme.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            if rest.mode == .heartRate {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(StrandFont.glyph(.chevron))
                    Text(String(localized: "HR"))
                        .font(StrandFont.caption)
                }
                .foregroundStyle(theme.dataHeart)
                .accessibilityLabel(Text("Heart-rate rest"))
            }
            RestChip(cfg: rest, timeColor: theme.inkSecondary) {
                focusedCell = nil; restTarget = RestEditTarget(ei: idx, si: si)
            }
            .disabled(locked)
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    /// Dim «80×7» from the seeded last session for this set index, when history exists.
    private func lastSetHistoryLabel(idx: Int, si: Int, type: ExerciseType) -> String? {
        guard items[idx].lastSets.indices.contains(si) else { return nil }
        let last = items[idx].lastSets[si]
        var parts: [String] = []
        if showsWeight(type), let w = last.weightKg {
            parts.append(StrengthDisplay.weightNumber(w, system: system))
        }
        if showsReps(type), let r = last.reps {
            parts.append("\(r)")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "×")
    }

    /// The set numeral in a 23 px ring of the routine hue («C» for a warm-up set, at half opacity).
    private func numeralRing(idx: Int, si: Int) -> some View {
        let warmup = items[idx].re.sets[si].kind == .warmup
        return Text(RoutineSetEditing.setLabel(items[idx].re, si))
            .font(InstrumentoType.grotesk(11, weight: .semibold)).monospacedDigit()
            .foregroundStyle(routineTint)
            .frame(width: 23, height: 23)
            .overlay(Circle().strokeBorder(routineTint.opacity(warmup ? 0.5 : 1), lineWidth: 1.5))
    }

    private func cellField(_ text: Binding<String>, id: String, keyboard: UIKeyboardType, width: CGFloat) -> some View {
        TextField("·", text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(StrandFont.bodyNumber)
            .foregroundStyle(theme.ink)
            .focused($focusedCell, equals: id)
            .disabled(locked)
            .frame(width: width, height: 31)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous).strokeBorder(theme.hairlineStrong))
    }

    private func addSetRow(_ idx: Int) -> some View {
        HStack(spacing: 16) {
            Button { addSet(idx) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(StrandFont.glyph(.chevron, weight: .semibold))
                    Text("Add set")
                }
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .frame(minHeight: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !hasWarmups(idx) {
                Button { addWarmupRamp(idx) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "flame").font(StrandFont.glyph(.chevron, weight: .semibold))
                        Text("Add warm-up")
                    }
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .frame(minHeight: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var addExerciseRow: some View {
        Button { replaceIndex = nil; showLibrary = true } label: {
            Label("Add exercise", systemImage: "plus").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pinned CTA (`.today` only — start / resume the guided session)

    private var ctaBar: some View {
        Button { start() } label: {
            Text(ctaTitle).font(InstrumentoType.grotesk(15, weight: .bold)).tracking(0.3)
                .foregroundStyle(theme.paper).frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(theme.paper)
    }

    // MARK: - Empty fallback (no routine resolved for this origin)

    private var emptyFallback: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz").font(StrandFont.glyph(.empty)).foregroundStyle(theme.inkTertiary)
            Text(isPlanDay ? "Rest day" : "No routine").font(StrandFont.title2).foregroundStyle(theme.ink)
            Text(isPlanDay ? "This day has no routine. Assign one from the weekly plan."
                           : "This routine could not be found.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Cell bindings

    private func repsText(idx: Int, si: Int) -> Binding<String> {
        Binding(get: { items[idx].re.sets[si].reps.map(String.init) ?? "" },
                set: { items[idx].re.sets[si].reps = Int($0.filter(\.isNumber)); dirty = true })
    }

    private func weightText(idx: Int, si: Int) -> Binding<String> {
        Binding(
            get: {
                guard let kg = items[idx].re.sets[si].weightKg, kg > 0 else { return "" }
                return StrengthDisplay.weightNumber(kg, system: system)
            },
            set: { raw in
                let norm = raw.replacingOccurrences(of: ",", with: ".")
                dirty = true
                guard let v = Double(norm), v > 0 else { items[idx].re.sets[si].weightKg = nil; return }
                items[idx].re.sets[si].weightKg = system == .imperial ? UnitFormatter.poundsToKg(v) : v
            })
    }

    private func showsReps(_ t: ExerciseType) -> Bool { t == .weightReps || t == .bodyweight }
    private func showsWeight(_ t: ExerciseType) -> Bool { t == .weightReps }

    // MARK: - Set + exercise mutations

    private func addSet(_ idx: Int) {
        let work = items[idx].re.sets.last { $0.kind == .work }
        let reps = work?.reps ?? (showsReps(items[idx].exercise.type) ? 8 : nil)
        items[idx].re.sets.append(RoutineSet(position: items[idx].re.sets.count, kind: .work,
                                             reps: reps, weightKg: work?.weightKg))
        dirty = true
    }

    private func deleteSet(idx: Int, si: Int) {
        guard items[idx].re.sets.count > 1 else { return }
        withAnimation(.snappy) { _ = items[idx].re.sets.remove(at: si) }
        renumber(idx)
        dirty = true
    }

    private func renumber(_ idx: Int) {
        for i in items[idx].re.sets.indices { items[idx].re.sets[i].position = i }
    }

    private func hasWarmups(_ idx: Int) -> Bool { items[idx].re.sets.contains { $0.kind == .warmup } }

    /// «Agregar calentamiento» (mock 4b): a 40·60·80 % ramp. Writes `warmupPercents` (the model's canonical
    /// record) AND materializes the three «C» rows the table shows, seeded from the top work weight when known.
    private func addWarmupRamp(_ idx: Int) {
        let ramp: [Double] = [0.4, 0.6, 0.8]
        items[idx].re.warmupPercents = ramp
        let top = items[idx].re.sets.first { $0.kind == .work }?.weightKg
        let usesReps = showsReps(items[idx].exercise.type)
        let rows = ramp.enumerated().map { i, pct in
            RoutineSet(position: i, kind: .warmup, reps: usesReps ? 10 : nil,
                       weightKg: top.map { $0 * pct })
        }
        withAnimation(.snappy) { items[idx].re.sets.insert(contentsOf: rows, at: 0) }
        renumber(idx)
        dirty = true
    }

    private func deleteExercise(_ idx: Int) {
        withAnimation(.snappy) { _ = items.remove(at: idx) }
        refreshTint()
        dirty = true
    }

    private func duplicate(_ idx: Int) {
        let src = items[idx]
        var copy = src.re
        copy.id = UUID().uuidString
        copy.position = idx + 1
        copy.supersetGroup = nil                                   // a duplicate stands on its own
        copy.sets = src.re.sets.map { s in var n = s; n.id = UUID().uuidString; return n }
        withAnimation(.snappy) { items.insert(EditorItem(re: copy, exercise: src.exercise), at: idx + 1) }
        refreshTint()
        dirty = true
    }

    /// Replace an exercise (keeping its sets) or append new ones, from the library (1f).
    private func addOrReplace(with picks: [Exercise]) {
        guard let first = picks.first else { return }
        if let i = replaceIndex, items.indices.contains(i) {
            items[i].exercise = first
            items[i].re.exerciseId = first.id
        } else {
            for pick in picks {
                let usesReps = pick.type == .weightReps || pick.type == .bodyweight
                let reps: Int? = usesReps ? 8 : nil
                let sets = (0..<3).map { RoutineSet(position: $0, kind: .work, reps: reps, weightKg: nil) }
                let re = RoutineExercise(routineId: routine?.id ?? "", exerciseId: pick.id, position: items.count,
                                         targetSets: 3, targetReps: reps, targetWeightKg: nil, sets: sets)
                items.append(EditorItem(re: re, exercise: pick))
            }
        }
        replaceIndex = nil
        refreshTint()
        dirty = true
    }

    // MARK: - Superset helpers (shared grouping logic lives in RoutineSetEditing)

    /// First member of a superset group (shows the «Superset» overline above it).
    private func firstOfGroup(_ i: Int) -> Bool { RoutineSetEditing.firstOfGroup(items.map(\.re), i) }

    private func supersetWithNext(_ i: Int) {
        var res = items.map(\.re)
        RoutineSetEditing.supersetWithNext(&res, i)
        for (j, re) in res.enumerated() { items[j].re = re }
        dirty = true
    }
    private func breakSuperset(_ i: Int) {
        var res = items.map(\.re)
        RoutineSetEditing.breakSuperset(&res, i)
        for (j, re) in res.enumerated() { items[j].re = re }
        dirty = true
    }

    // MARK: - Meta computations

    private var totalSets: Int { items.reduce(0) { $0 + $1.re.sets.filter { $0.kind == .work }.count } }

    /// A transparent time estimate (display only): ~40 s of work per work set plus its resolved rest.
    private var estimatedMinutes: Int {
        var seconds = 0
        for item in items {
            for si in item.re.sets.indices where item.re.sets[si].kind == .work {
                seconds += 40 + RoutineSetEditing.effectiveRest(item.re, si).seconds
            }
        }
        return max(1, Int((Double(seconds) / 60).rounded()))
    }

    /// The routine's dominant coarse group — deterministic tie-break (FER-750). Recomputed by
    /// `refreshTint()` only when the exercise set changes (load / add / replace / delete / duplicate):
    /// the tint colors every set-row ring, and re-tallying on each keystroke was wasted work.
    private func refreshTint() {
        var tally: [MuscleGroup: Int] = [:]
        for item in items {
            for m in item.exercise.primaryMuscles { if let g = MuscleGroup.of(m) { tally[g, default: 0] += 1 } }
        }
        var best: MuscleGroup?
        var bestCount = 0
        for g in MuscleGroup.allCases where (tally[g] ?? 0) > bestCount {
            best = g; bestCount = tally[g] ?? 0
        }
        routineTint = best?.tint(theme) ?? theme.inkTertiary
        groupTitle = best?.title ?? String(localized: "Mixed")
    }

    private func weekdayName(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[(weekday - 1) % 7]   // index 0 = Sunday … 6 = Saturday
    }
    private var shortWeekday: String {
        let idx = Calendar.current.component(.weekday, from: Date()) - 1
        return Calendar.current.shortWeekdaySymbols[idx]
    }

    // MARK: - Day assignment (.planDay «···»)

    /// The .planDay weekday; nil for the other origins (whose UI never shows the day menu).
    private var planWeekday: Int? {
        if case .planDay(let wd) = origin { return wd } else { return nil }
    }

    private func changeRoutine(to r: Routine) {
        guard let wd = planWeekday else { return }
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await store.setRoutineSchedule(weekday: wd, routineId: r.id)
            await load()
        }
    }

    private func markRest() {
        guard let wd = planWeekday else { return }
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await store.clearRoutineSchedule(weekday: wd)
            dismiss()
        }
    }

    // MARK: - Navigation (Notes-style: every origin autosaves on leave when dirty)

    private func back() {
        if dirty { persist() }
        dismiss()
    }

    /// Restore the load-time prescription, clear dirty, and re-persist so disk matches the undo.
    /// Stays on the editor — does not dismiss.
    private func undo() {
        items = itemsSnapshot
        dirty = false
        refreshTint()
        persist()
    }

    // MARK: - Start the guided session (progression wiring, FER-E/G parity with «Rutina de hoy»)

    private func start() {
        // A session already running → just resume it (don't rebuild over logged sets).
        if model.strengthSession != nil { model.resumeStrengthSession(); return }
        guard let r = routine else { return }
        if dirty { persist() }   // «se guardan al salir o empezar»
        let slots = items.map {
            StrengthSessionModel.PlanSlot(re: $0.re, exercise: $0.exercise, lastSets: $0.lastSets,
                                          raise: $0.raise)
        }
        model.startStrengthSession(routineId: r.id, routineName: r.name, slots: slots)
    }

    // MARK: - Load + save

    private func load() async {
        guard let store = await repo.storeHandle() else {
            routine = nil; items = []; itemsSnapshot = []; dirty = false; return
        }
        allRoutines = (try? await store.routines()) ?? []
        let target: Routine?
        switch origin {
        case .today(let id):
            // Today's pick: the given id, else today's SCHEDULED routine via the canonical resolver —
            // no arbitrary-routine fallback (the FER-531 contract); an unplanned day shows the empty state.
            let sched = (try? await store.routineSchedule()) ?? []
            let split = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
            let rid = id ?? WeeklySplit.todayRoutineId(
                split: split, todayWeekday: Calendar.current.component(.weekday, from: Date()))
            target = rid.flatMap { r in allRoutines.first { $0.id == r } }
        case .planDay(let wd):
            let sched = (try? await store.routineSchedule()) ?? []
            let rid = sched.first { $0.weekday == wd }?.routineId
            target = rid.flatMap { r in allRoutines.first { $0.id == r } }
        case .routine(let id):
            target = allRoutines.first { $0.id == id }
        }
        guard let r = target else {
            routine = nil; items = []; itemsSnapshot = []; dirty = false; return
        }
        routine = r
        let res = await repo.routineExercises(routineId: r.id)
        let all = await repo.allExercises()
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // FER-E: «la última vez» + progression, via the ONE `sessionSeed` implementation the landing
        // prefetch also calls (sub-épico 1 wiring). Only the .today origin can start a session, so the
        // save-only origins skip that per-exercise history I/O entirely.
        let inventory = plates.inventory
        let recovery = repo.today?.recovery
        var built: [EditorItem] = []
        for re in res {
            guard let ex = byId[re.exerciseId] else { continue }
            if startsSession {
                let seed = await repo.sessionSeed(re: re, exercise: ex, inventory: inventory, recovery: recovery)
                built.append(EditorItem(re: re, exercise: ex, lastSets: seed.lastSets,
                                        raise: seed.evaluation?.raise))
            } else {
                built.append(EditorItem(re: re, exercise: ex))
            }
        }
        items = built
        refreshTint()
        dirty = false
        // Capture the post-load prescription for Undo (value copy of Equatable structs).
        itemsSnapshot = items
    }

    private func persist() {
        guard let r = routine else { return }
        let now = Int(Date().timeIntervalSince1970)
        let updated = Routine(id: r.id, name: r.name, tag: r.tag, folderId: r.folderId,
                              createdTs: r.createdTs, updatedTs: now, sortOrder: r.sortOrder)
        let exercises = items.enumerated().map { idx, item -> RoutineExercise in
            var re = item.re; re.position = idx; re.routineId = r.id; return re
        }
        Task { try? await repo.saveRoutine(updated, exercises: exercises) }
    }
}

/// One exercise slot in the editor: the routine slot, its resolved exercise, and the session seeds
/// («la última vez» + an earned progression raise) the .today origin hands to the guided session.
private struct EditorItem: Identifiable {
    var re: RoutineExercise
    var exercise: Exercise
    var lastSets: [SetEntry] = []
    var raise: ProgressionPlanner.Raise? = nil
    var id: String { re.id }
}

// Shared list-row chrome: clear background, no system separator, standard screen margin with tunable
// vertical insets — a plain List that reproduces «Instrumento» spacing (same pattern as the builder).
private extension View {
    func plainRow(top: CGFloat = 8, bottom: CGFloat = 8) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: CenitMetrics.screenPadding,
                                      bottom: bottom, trailing: CenitMetrics.screenPadding))
    }
}
#endif
