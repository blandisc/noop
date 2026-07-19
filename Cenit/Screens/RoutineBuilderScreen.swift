#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// RoutineBuilderScreen.swift — CREATE reusable routines (FER-346, inline rewrite FER-561; create-only
// since FER-840). The Train hub opens this as a sheet to build a NEW routine from scratch or from a
// session seed; editing an existing routine happens on the unified «Rutina» editor (`RoutineEditorScreen`,
// FER-839) — `onSaved` hands back the new routine's id so the caller opens it there. EVERYTHING is edited
// on ONE screen (Hevy-style): each exercise shows its set table inline, matching the live session's
// logging table (LiveStrengthSheet, FER-497). «Báscula de papel»: weights in ink, no color; a flat List +
// hairlines (no card-in-card), native swipe-to-delete on sets.

// MARK: - Builder

struct RoutineBuilderScreen: View {
    /// Called after the new routine persists, with its id — the caller opens it on «Rutina» (FER-840).
    var onSaved: ((String) async -> Void)? = nil

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var mediaCoordinator: MediaDownloadCoordinator
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State private var name: String = ""
    @State private var items: [BuilderItem] = []
    @State private var showLibrary = false
    /// Which set's rest is being edited (drives the 1e push); nil = none. Rest is per-set now (choque 3):
    /// each set carries its own `RestConfig` override, edited in the shared `RestEditorScreen`.
    @State private var restTarget: RestEditTarget? = nil
    /// Which exercise's progression plan is being edited (drives the 2c push, FER-D); nil = none.
    @State private var progressionTarget: ProgressionTarget? = nil
    // FER-837: which exercise's «···» paper menu is open.
    @State private var menuExerciseIndex: Int? = nil
    /// The plate inventory, to derive the default increment (FER-C). UserDefaults-backed, cheap.
    @StateObject private var plates = PlatesStore()
    /// Which exercise's info sheet is open (tap the row's name/thumb to open its detail, like the library).
    @State private var detail: Exercise? = nil
    @State private var saveError = false
    @FocusState private var focusedCell: String?

    private let routineId: String

    init(onSaved: ((String) async -> Void)? = nil) {
        self.onSaved = onSaved
        self.routineId = UUID().uuidString
    }

    /// «Duplicar como rutina» (2A): a fresh routine pre-filled with a session's exercises. `seedName`
    /// seeds the name field; `seed` re-bases each exercise onto the new routine id. Both are fixed at
    /// init, so `items` starts seeded — no async load step.
    init(seedName: String, seed: [(re: RoutineExercise, exercise: Exercise)], onSaved: ((String) async -> Void)? = nil) {
        self.onSaved = onSaved
        let newId = UUID().uuidString
        self.routineId = newId
        _items = State(initialValue: seed.enumerated().map { idx, item in
            var re = item.re; re.routineId = newId; re.position = idx
            return BuilderItem(re: re, exercise: item.exercise)
        })
        _name = State(initialValue: seedName)
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty { emptyBody } else { listBody }
            }
            .background(theme.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BackButton(role: .close, theme: theme) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HeaderActionButton(Text("Save"), enabled: canSave, theme: theme) { save() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedCell = nil }.foregroundStyle(theme.ink)
                }
            }
            // 1e as a push (choque 3): the shared `RestEditorScreen` edits one set's rest, with a
            // «this set / all sets» scope. In the builder every change lands on the routine at «Save», so
            // the «save to routine» toggle is off (persistsToRoutine: false).
            // Rest is per EXERCISE (FER-952) — same semantics as the unified editor.
            .navigationDestination(item: $restTarget) { t in
                RestEditorScreen(
                    theme: theme,
                    exerciseName: StrengthDisplay.name(items[t.ei].exercise),
                    setNumber: nil,
                    current: exerciseRest(t.ei),
                    persistsToRoutine: false,
                    restingHR: repo.days.compactMap(\.restingHr).last.map(Double.init),
                    maxHR: Double(model.profile.hrMax),
                    defaultApplyToAll: true,
                    onCancel: { restTarget = nil },
                    onApply: { config, _, _ in
                        RoutineSetEditing.applyRest(to: &items[t.ei].re, si: 0, config: config, applyToAll: true)
                        restTarget = nil
                    }
                )
                .toolbar(.hidden, for: .navigationBar)   // RestEditorScreen draws its own back/cancel header
                .keepsSwipeBack()   // ocultar la barra deja huérfano el gesto de volver
            }
            // 2c as a push (FER-D): the per-exercise progression plan. Saves on back (Instrumento editor
            // convention); like rest, every change lands on the routine at «Save».
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
                        // The rep goal IS RoutineSet.reps (no ranges): with the plan on, write it onto
                        // every work set. Off, the prescription stays whatever the user typed.
                        guard enabled else { return }
                        for si in items[t.ei].re.sets.indices where items[t.ei].re.sets[si].kind == .work {
                            items[t.ei].re.sets[si].reps = targetReps
                        }
                    }
                )
                .toolbar(.hidden, for: .navigationBar)   // ProgressionSetupScreen draws its own back header
                .keepsSwipeBack()   // ocultar la barra deja huérfano el gesto de volver
            }
        }
        .sheet(isPresented: $showLibrary) {
            ExerciseLibraryScreen { picks in append(picks) }
                .instrumentoTheme(theme).environmentObject(repo).environmentObject(mediaCoordinator).preferredColorScheme(.light)
        }
        // Tap an exercise's name/thumb to read its info — same detail sheet as the library (parity with 1f).
        .sheet(item: $detail) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { detail = nil }.foregroundStyle(theme.ink)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
            }
            .instrumentoTheme(theme).environmentObject(repo).environmentObject(mediaCoordinator).preferredColorScheme(.light)
        }
        // FER-969: save failure is an inline banner (same pattern as WorkoutEditSheet); stay open, no dismiss.
        .overlay(alignment: .top) {
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
        .animation(StrandMotion.fade, value: saveError)
    }

    // MARK: - Empty

    private var emptyBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                nameField
                VStack(spacing: 11) {
                    Image(systemName: "square.stack.3d.up").font(StrandFont.glyph(.empty)).foregroundStyle(theme.inkTertiary)
                    Text("No exercises yet").font(InstrumentoType.groteskHeadline(20)).foregroundStyle(theme.ink)
                    Text("Add exercises from the library to build this routine.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
                QuietButton("Add exercise") { showLibrary = true }
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 20).padding(.horizontal, CenitMetrics.screenPadding).padding(.bottom, CenitMetrics.screenPadding)
        }
    }

    // MARK: - Inline list (matches the live session table, FER-497)

    private var listBody: some View {
        // A flat List (not ScrollView) so each set row gets a real swipe-to-delete; styled down to the
        // warm-paper language — no native separators / background, our own hairlines (FER-497 pattern).
        List {
            nameField.plainRow(top: 8, bottom: 8)
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, _ in
                if firstOfGroup(idx) {
                    // Same voice + hue as the unified editor: the superset overline IS the datum.
                    Text("Superset").groteskOverline().foregroundStyle(theme.dataHrv)
                        .plainRow(top: CenitMetrics.sectionGap, bottom: 2)
                }
                // Proximity = grouping: members of a superset breathe `gap`, strangers `sectionGap`.
                exerciseHeader(idx).plainRow(top: firstOfGroup(idx) || idx == 0 ? CenitMetrics.gap
                    : (RoutineSetEditing.sameGroup(items.map(\.re), idx - 1, idx) ? CenitMetrics.gap : CenitMetrics.sectionGap))
                ForEach(Array(items[idx].re.sets.enumerated()), id: \.element.id) { si, _ in
                    setRow(idx: idx, si: si).plainRow(top: 0, bottom: 0)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleteSet(idx: idx, si: si) } label: { Label("Delete", systemImage: "trash") }
                        }
                }
                addSetRow(idx).plainRow(top: 4)
            }
            addExerciseRow.plainRow(top: CenitMetrics.sectionGap, bottom: CenitMetrics.screenPadding)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.paper)
        .environment(\.defaultMinListRowHeight, 1)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Same Grotesk voice as the unified editor (FER-952) — one conceptual screen, one look.
            Text("New routine").groteskOverline().foregroundStyle(theme.inkTertiary)
            TextField("Routine name", text: $name)
                .font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking)
                .foregroundStyle(theme.ink)
            if !items.isEmpty {
                if let region = builderRegion {
                    HStack(spacing: 6) {
                        Circle().fill(builderRegionTint(region)).frame(width: 8, height: 8)
                        // Color only in the datum: the dot carries the hue, the label stays ink.
                        Text(builderRegionLabel(region))
                            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                    .padding(.top, 2)
                }
                Text("\(items.count) exercises · \(builderTotalSets) sets")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
        }
    }

    /// Content-derived region for the in-progress routine (same classifier as Entrenar's tints).
    private var builderRegion: RoutineRegion? {
        RoutineClassifier.classify(primaryMusclesPerExercise: items.map { $0.exercise.primaryMuscles })
    }

    private var builderTotalSets: Int {
        items.reduce(0) { $0 + $1.re.sets.count }
    }

    private func builderRegionTint(_ region: RoutineRegion) -> Color {
        return region.tint(theme)
    }

    private func builderRegionLabel(_ region: RoutineRegion) -> String {
        switch region {
        case .push: return "push"
        case .pull: return "pull"
        case .legs: return "legs"
        case .fullBody: return "full body"
        }
    }

    // MARK: - Exercise header (name + ⋯ menu + rest chip + column header)

    private func exerciseHeader(_ idx: Int) -> some View {
        let item = items[idx]
        return VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            HStack(spacing: 11) {
                // Tapping the thumb/name opens the exercise info sheet (parity with the library, FER-776).
                Button { detail = item.exercise } label: {
                    // r25: the thumb wears its movement family (same frame as editor + Serie activa).
                    ExerciseThumbView(exercise: item.exercise, side: 40)   // cached GIF still, or paper placeholder (FER-790)
                        .overlay(RoundedRectangle(cornerRadius: ExerciseThumbnail.tileCornerRadius(side: 40), style: .continuous)
                            .strokeBorder(theme.movementFamilyTint(primaryMuscles: item.exercise.primaryMuscles), lineWidth: 2))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 1) {
                    Button { detail = item.exercise } label: {
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
                    // Progression chip under the name — same destination as «···» → Progression.
                    if item.re.progressionEnabled {
                        ProgressionChip(re: item.re, system: system, theme: theme,
                                        derivedIncrementKg: PlateMath.minimumIncrement(for: .from(equipment: item.exercise.equipment), inventory: plates.inventory),
                                        action: { progressionTarget = ProgressionTarget(ei: idx) })
                    }
                }
                Spacer(minLength: 8)
                Button { menuExerciseIndex = idx } label: {
                    Image(systemName: "ellipsis").font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary).frame(width: 30, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .paperMenu(
                    isPresented: Binding(get: { menuExerciseIndex == idx },
                                         set: { if !$0 { menuExerciseIndex = nil } }),
                    items: exerciseMenuItems(idx, item: item)
                )
            }
            // Handoff (rest-per-exercise): one rest decision per exercise, as a chip under the name.
            RestChip(cfg: exerciseRest(idx)) {
                focusedCell = nil; restTarget = RestEditTarget(ei: idx, si: 0)
            }
            columnHeader(item.exercise.type)
        }
    }

    /// Quiet column header (SET · KG · REPS, gated by exercise type) with a hairline underline.
    @ViewBuilder
    private func columnHeader(_ type: ExerciseType) -> some View {
        HStack(spacing: 8) {
            // Same table metrics as the unified editor (FER-952): 40 / twin 74s.
            Text("SET").groteskOverline(small: true).foregroundStyle(theme.inkTertiary).lineLimit(1).minimumScaleFactor(0.7).frame(width: 40, alignment: .center)
            if showsWeight(type) {
                Text(StrengthDisplay.weightUnit(system)).groteskOverline(small: true).foregroundStyle(theme.inkTertiary).frame(width: 74)
            }
            if showsReps(type) {
                Text("Reps").groteskOverline(small: true).foregroundStyle(theme.inkTertiary).frame(width: 74)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    // MARK: - A set row (editable cells; warm-up = «C»)

    private func setRow(idx: Int, si: Int) -> some View {
        let set = items[idx].re.sets[si]
        let type = items[idx].exercise.type
        return HStack(spacing: 8) {
            Text(RoutineSetEditing.setLabel(items[idx].re, si))
                .font(InstrumentoType.grotesk(13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(set.kind == .warmup ? theme.inkTertiary : theme.ink)
                .frame(width: 40, alignment: .center)
            if showsWeight(type) {
                cellField(weightText(idx: idx, si: si), id: "\(set.id)-w", keyboard: .decimalPad)
            }
            if showsReps(type) {
                cellField(repsText(idx: idx, si: si), id: "\(set.id)-r", keyboard: .numberPad)
            }
            Spacer(minLength: 6)
        }
        .frame(minHeight: 44)
        // Hairline BELOW the row, like the editor and the handoff's border-bottom.
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    private func cellField(_ text: Binding<String>, id: String, keyboard: UIKeyboardType) -> some View {
        TextField("—", text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            // Handoff: the prescription's figures speak Grotesk (400 15), like every datum on paper.
            .font(InstrumentoType.grotesk(15)).monospacedDigit()
            .foregroundStyle(theme.ink)
            .focused($focusedCell, equals: id)
            .frame(width: 74, height: 32)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous).strokeBorder(theme.hairlineStrong))
    }

    private func addSetRow(_ idx: Int) -> some View {
        Button { addSet(idx) } label: {
            HStack(spacing: 8) {
                StrandIcon.add.image
                Text("Add set")
            }
            .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var addExerciseRow: some View {
        // The same centered outline door as the unified editor (handoff spec).
        Button { showLibrary = true } label: {
            Label("Add exercise", systemImage: "plus")
                .font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 13)  // token-exempt: 13 del handoff
                .contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cell bindings

    private func repsText(idx: Int, si: Int) -> Binding<String> {
        Binding(get: { items[idx].re.sets[si].reps.map(String.init) ?? "" },
                set: { items[idx].re.sets[si].reps = Int($0.filter(\.isNumber)) })
    }

    private func weightText(idx: Int, si: Int) -> Binding<String> {
        Binding(
            get: {
                guard let kg = items[idx].re.sets[si].weightKg, kg > 0 else { return "" }
                return StrengthDisplay.weightNumber(kg, system: system)
            },
            set: { raw in
                let norm = raw.replacingOccurrences(of: ",", with: ".")
                guard let v = Double(norm), v > 0 else { items[idx].re.sets[si].weightKg = nil; return }
                items[idx].re.sets[si].weightKg = system == .imperial ? UnitFormatter.poundsToKg(v) : v
            })
    }

    private func showsReps(_ t: ExerciseType) -> Bool { t == .weightReps || t == .bodyweight }
    private func showsWeight(_ t: ExerciseType) -> Bool { t == .weightReps }

    // MARK: - Set mutations

    private func addSet(_ idx: Int) {
        let work = items[idx].re.sets.last { $0.kind == .work }
        let reps = work?.reps ?? (showsReps(items[idx].exercise.type) ? 8 : nil)
        items[idx].re.sets.append(RoutineSet(position: items[idx].re.sets.count, kind: .work,
                                             reps: reps, weightKg: work?.weightKg))
    }

    /// The exercise «···» actions as paper-menu rows (FER-837). The Progression row carries its
    /// state as the paper menu's subtitle («+2,5 kg cada 2 ✓» pattern from mock 4b).
    private func exerciseMenuItems(_ idx: Int, item: BuilderItem) -> [PaperMenuItem] {
        var rows: [PaperMenuItem] = []
        if idx > 0 { rows.append(.init(String(localized: "Move up"), systemImage: "arrow.up") { moveUp(idx) }) }
        if idx < items.count - 1 { rows.append(.init(String(localized: "Move down"), systemImage: "arrow.down") { moveDown(idx) }) }
        rows.append(.init(String(localized: "Add warm-up set"), systemImage: "flame") { addWarmup(idx) })
        if idx < items.count - 1 && !sameGroup(idx, idx + 1) {
            rows.append(.init(String(localized: "Superset with next"), systemImage: "link") { supersetWithNext(idx) })
        }
        if inSuperset(idx) {
            rows.append(.init(String(localized: "Break superset"), systemImage: "link.badge.plus") { breakSuperset(idx) })
        }
        // 2c (FER-D): the per-exercise progression plan. Weight-based exercises only —
        // bodyweight/time/distance have no load to progress.
        if item.exercise.type == .weightReps {
            rows.append(.init(String(localized: "Progression"),
                              subtitle: item.re.progressionEnabled ? String(localized: "on") : nil,
                              systemImage: "chart.line.uptrend.xyaxis") {
                progressionTarget = ProgressionTarget(ei: idx)
            })
        }
        rows.append(.init(String(localized: "Remove"), systemImage: "trash", isDestructive: true) { deleteExercise(idx) })
        return rows
    }

    private func addWarmup(_ idx: Int) {
        // Warm-up sets sit first; they don't count toward PR/volume and aren't logged in the session.
        items[idx].re.sets.insert(RoutineSet(position: 0, kind: .warmup, reps: showsReps(items[idx].exercise.type) ? 10 : nil,
                                             weightKg: nil), at: 0)
        renumber(idx)
    }

    private func deleteSet(idx: Int, si: Int) {
        guard items[idx].re.sets.count > 1 else { return }   // keep at least one set
        withAnimation(.snappy) { _ = items[idx].re.sets.remove(at: si) }
        renumber(idx)
    }

    private func renumber(_ idx: Int) {
        for i in items[idx].re.sets.indices { items[idx].re.sets[i].position = i }
    }

    // MARK: - Exercise mutations

    private func append(_ picks: [Exercise]) {
        for ex in picks {
            let usesReps = ex.type == .weightReps || ex.type == .bodyweight
            let defaultReps: Int? = usesReps ? 8 : nil
            let sets = (0..<3).map { RoutineSet(position: $0, kind: .work, reps: defaultReps, weightKg: nil) }
            let re = RoutineExercise(routineId: routineId, exerciseId: ex.id, position: items.count,
                                     targetSets: 3, targetReps: defaultReps, targetWeightKg: nil, sets: sets)
            items.append(BuilderItem(re: re, exercise: ex))
        }
    }

    private func moveUp(_ idx: Int) { guard idx > 0 else { return }; withAnimation(.snappy) { items.swapAt(idx, idx - 1) } }
    private func moveDown(_ idx: Int) { guard idx < items.count - 1 else { return }; withAnimation(.snappy) { items.swapAt(idx, idx + 1) } }
    private func deleteExercise(_ idx: Int) { withAnimation(.snappy) { _ = items.remove(at: idx) } }

    // MARK: - Superset helpers (shared grouping logic lives in RoutineSetEditing)

    private func inSuperset(_ i: Int) -> Bool { RoutineSetEditing.inSuperset(items.map(\.re), i) }
    private func sameGroup(_ a: Int, _ b: Int) -> Bool { RoutineSetEditing.sameGroup(items.map(\.re), a, b) }

    /// The exercise-level rest rule (FER-952: rest is per exercise now).
    private func exerciseRest(_ idx: Int) -> RestConfig {
        let re = items[idx].re
        return RestConfig(mode: re.restMode, seconds: re.restSeconds,
                          hrReference: re.hrRestReference, hrValue: re.hrRestValue)
    }
    /// First member of a superset group (shows the «Superset» header above it).
    private func firstOfGroup(_ i: Int) -> Bool { RoutineSetEditing.firstOfGroup(items.map(\.re), i) }

    private func supersetWithNext(_ i: Int) {
        var res = items.map(\.re)
        RoutineSetEditing.supersetWithNext(&res, i)
        for (j, re) in res.enumerated() { items[j].re = re }
    }
    private func breakSuperset(_ i: Int) {
        var res = items.map(\.re)
        RoutineSetEditing.breakSuperset(&res, i)
        for (j, re) in res.enumerated() { items[j].re = re }
    }

    // MARK: - Save

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !items.isEmpty }

    private func save() {
        let now = Int(Date().timeIntervalSince1970)
        let r = Routine(id: routineId, name: name.trimmingCharacters(in: .whitespaces),
                        tag: nil, createdTs: now, updatedTs: now, sortOrder: 0)
        let exercises = items.enumerated().map { idx, item -> RoutineExercise in
            var re = item.re; re.position = idx; re.routineId = routineId; return re
        }
        Task {
            do {
                try await repo.saveRoutine(r, exercises: exercises)
                await onSaved?(routineId)
                dismiss()
            } catch {
                saveError = true
            }
        }
    }
}

private struct BuilderItem: Identifiable {
    var re: RoutineExercise
    let exercise: Exercise
    var id: String { re.id }
}

// Shared list-row chrome: clear background, no system separator (rows draw their own hairline), standard
// screen margin with tunable vertical insets — a plain List that reproduces «Instrumento» spacing.
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
