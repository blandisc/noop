#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - Editar día del plan (1o, FER-747) — «Flujo Entrenar v3»
//
// The editor for ONE day of the weekly plan, reached by tapping a day that has a routine in 1b
// (`WeeklyPlanEditorView`). A «day» of the plan is the routine assigned to that weekday
// (`RoutineSchedule` → `Routine`); there is no per-day override, so «Guardar día» saves the routine —
// the same model 1d (`RoutineBuilderScreen`) edits. The handoff rule is «pantallas, no sheets»: this is
// a PUSH onto the Entrenar stack (not a sheet), with its own back/cancel header and a pinned CTA.
//
// It wears the day chrome the mock asks for — overline «EDITANDO · {DÍA}», the routine title underlined,
// a meta line dotted in the routine hue, set numerals in a ring of that hue — over the same inline set
// table as the builder (editable Kg/Reps cells, a per-set rest chip that pushes the shared 1e editor).
// Assigning/clearing the day (choque 9, «conserva lo callado») lives in the header «···»: Change routine
// / Mark as rest day. «Instrumento diurno»: weights in ink, color only on the rest datum and the hue ring.

/// Pushed onto the Entrenar stack to open «Editar día del plan» (1o) for a weekday (Calendar
/// convention, 1 = Sun … 7 = Sat). A distinct `Hashable` type (like `RoutineRoute`) so the type-erased
/// `trainStack` can carry it alongside `SecondaryScreen` without the FER-171 mixed-typed-path crash.
struct PlanDayRoute: Hashable { let weekday: Int }

struct PlanDayEditorScreen: View {
    let weekday: Int

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State private var loaded = false
    /// The routine assigned to this weekday (nil while loading, or if the day was cleared to rest).
    @State private var routine: Routine?
    @State private var items: [DayEditItem] = []
    /// Every routine, for the header «Change routine» picker.
    @State private var allRoutines: [Routine] = []
    /// Whether the prescription changed since load (drives the discard-on-back confirmation + Save).
    @State private var dirty = false
    @State private var restTarget: RestEditTarget? = nil
    @State private var showDiscardConfirm = false
    @State private var showReplaceLibrary = false
    @State private var replaceIndex: Int? = nil
    @FocusState private var focusedCell: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            if loaded, routine != nil {
                editor
            } else {
                Spacer()
                if loaded { restFallback }
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
        // Changes land on the routine at «Guardar día», so the «save to routine» toggle is off.
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
        .sheet(isPresented: $showReplaceLibrary) {
            ExerciseLibraryScreen { picks in replace(with: picks) }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .confirmationDialog("Discard changes to this day?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .task {
            guard !loaded else { return }
            await load()
            loaded = true
        }
    }

    // MARK: - Header (own back «Weekly plan» + «Cancel», FER-747)

    private var header: some View {
        HStack(spacing: 8) {
            Button { back() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(StrandFont.glyph(.inline, weight: .semibold))
                    Text("Weekly plan").font(StrandFont.body)
                }
                .foregroundStyle(theme.ink).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(Text("Back to weekly plan"))
            Spacer()
            Button { back() } label: {
                Text("Cancel").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NoopMetrics.screenPadding)
    }

    // MARK: - Editor (title + meta + per-exercise tables + pinned CTA)

    private var editor: some View {
        List {
            titleBlock.plainRow(top: 6, bottom: 6)
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, _ in
                exerciseHeader(idx).plainRow(top: idx == 0 ? NoopMetrics.gap : NoopMetrics.sectionGap)
                ForEach(Array(items[idx].re.sets.enumerated()), id: \.element.id) { si, _ in
                    setRow(idx: idx, si: si).plainRow(top: 0, bottom: 0)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleteSet(idx: idx, si: si) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                addSetRow(idx).plainRow(top: 4)
            }
            addExerciseRow.plainRow(top: NoopMetrics.sectionGap, bottom: NoopMetrics.screenPadding)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.paper)
        .environment(\.defaultMinListRowHeight, 1)
        .safeAreaInset(edge: .bottom) { ctaBar }
    }

    /// Overline «EDITANDO · {DÍA}», the routine title underlined, and the dotted meta line.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(overline).groteskOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                dayMenu
            }
            Text(routine?.name ?? "")
                .font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking)
                .foregroundStyle(theme.ink)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.ink).frame(height: 2).offset(y: 5)
                }
                .fixedSize(horizontal: true, vertical: false)
            metaLine
        }
    }

    private var overline: String {
        String(localized: "Editing") + " · " + weekdayName
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

    /// Header «···»: assign/clear the day (choque 9 — «conserva lo callado», re-dressed).
    private var dayMenu: some View {
        Menu {
            Menu {
                ForEach(allRoutines) { r in
                    Button { changeRoutine(to: r) } label: {
                        if r.id == routine?.id { Label(r.name, systemImage: "checkmark") } else { Text(r.name) }
                    }
                }
            } label: { Label("Change routine", systemImage: "arrow.left.arrow.right") }
            Button(role: .destructive) { markRest() } label: { Label("Mark as rest day", systemImage: "moon.zzz") }
        } label: {
            Image(systemName: "ellipsis").font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(theme.inkTertiary).frame(width: 40, height: 40).contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Day options"))
    }

    // MARK: - Exercise header (thumb + name + ⋯ + column header)

    private func exerciseHeader(_ idx: Int) -> some View {
        let item = items[idx]
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(spacing: 11) {
                thumb(item.exercise)
                VStack(alignment: .leading, spacing: 1) {
                    if item.exercise.type != .weightReps {
                        Text(StrengthDisplay.subtitle(item.exercise)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    }
                    Text(StrengthDisplay.name(item.exercise)).font(StrandFont.headline).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Menu {
                    if idx > 0 { Button { moveUp(idx) } label: { Label("Move up", systemImage: "arrow.up") } }
                    if idx < items.count - 1 { Button { moveDown(idx) } label: { Label("Move down", systemImage: "arrow.down") } }
                    Button { replaceIndex = idx; showReplaceLibrary = true } label: { Label("Replace exercise", systemImage: "arrow.triangle.2.circlepath") }
                    Button { duplicate(idx) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { deleteExercise(idx) } label: { Label("Remove", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary).frame(width: 32, height: 36).contentShape(Rectangle())
                }
            }
            columnHeader(item.exercise.type)
        }
    }

    /// A placeholder thumb (media EDB is a separate issue): a soft paper tile per the mock. Placeholder-first.
    private func thumb(_ exercise: Exercise) -> some View {
        RoundedRectangle(cornerRadius: NoopMetrics.insetRadius, style: .continuous)
            .fill(LinearGradient(colors: [theme.hairline, theme.hairlineStrong],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: "play.fill").font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary.opacity(StrandOpacity.dim)))
            .accessibilityHidden(true)
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
        return HStack(spacing: 8) {
            numeralRing(idx: idx, si: si).frame(width: 40)
            if showsWeight(type) {
                cellField(weightText(idx: idx, si: si), id: "\(set.id)-w", keyboard: .decimalPad, width: 78)
            }
            if showsReps(type) {
                cellField(repsText(idx: idx, si: si), id: "\(set.id)-r", keyboard: .numberPad, width: 58)
            }
            Spacer(minLength: 6)
            RestChip(cfg: RoutineSetEditing.effectiveRest(items[idx].re, si), timeColor: theme.inkSecondary) {
                focusedCell = nil; restTarget = RestEditTarget(ei: idx, si: si)
            }
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    /// The set numeral in a 23 px ring of the routine hue («C» for a warm-up set).
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
            .frame(width: width, height: 31)
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.insetRadius, style: .continuous).strokeBorder(theme.hairlineStrong))
    }

    private func addSetRow(_ idx: Int) -> some View {
        Button { addSet(idx) } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus").font(StrandFont.glyph(.chevron, weight: .semibold))
                Text("Add set")
            }
            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var addExerciseRow: some View {
        Button { replaceIndex = nil; showReplaceLibrary = true } label: {
            Label("Add exercise", systemImage: "plus").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pinned CTA

    private var ctaBar: some View {
        Button { save() } label: {
            Text("Save day").font(InstrumentoType.grotesk(15, weight: .bold)).tracking(0.3)
                .foregroundStyle(theme.paper).frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.ctaRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, NoopMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(theme.paper)
    }

    // MARK: - Rest-day fallback (the day was cleared while open)

    private var restFallback: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz").font(StrandFont.glyph(.empty)).foregroundStyle(theme.inkTertiary)
            Text("Rest day").font(StrandFont.title2).foregroundStyle(theme.ink)
            Text("This day has no routine. Assign one from the weekly plan.")
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
        for i in items[idx].re.sets.indices { items[idx].re.sets[i].position = i }
        dirty = true
    }

    private func moveUp(_ idx: Int) { guard idx > 0 else { return }; withAnimation(.snappy) { items.swapAt(idx, idx - 1) }; dirty = true }
    private func moveDown(_ idx: Int) { guard idx < items.count - 1 else { return }; withAnimation(.snappy) { items.swapAt(idx, idx + 1) }; dirty = true }
    private func deleteExercise(_ idx: Int) { withAnimation(.snappy) { _ = items.remove(at: idx) }; dirty = true }

    private func duplicate(_ idx: Int) {
        let src = items[idx]
        var copy = src.re
        copy.id = UUID().uuidString
        copy.position = idx + 1
        copy.supersetGroup = nil                                   // a duplicate stands on its own
        copy.sets = src.re.sets.map { s in var n = s; n.id = UUID().uuidString; return n }
        withAnimation(.snappy) { items.insert(DayEditItem(re: copy, exercise: src.exercise), at: idx + 1) }
        dirty = true
    }

    /// Replace an exercise (keeping its sets) or append new ones, from the library (1f).
    private func replace(with picks: [Exercise]) {
        guard let ex = picks.first else { return }
        if let i = replaceIndex, items.indices.contains(i) {
            items[i].exercise = ex
            items[i].re.exerciseId = ex.id
        } else {
            for pick in picks {
                let usesReps = pick.type == .weightReps || pick.type == .bodyweight
                let reps: Int? = usesReps ? 8 : nil
                let sets = (0..<3).map { RoutineSet(position: $0, kind: .work, reps: reps, weightKg: nil) }
                let re = RoutineExercise(routineId: routine?.id ?? "", exerciseId: pick.id, position: items.count,
                                         targetSets: 3, targetReps: reps, targetWeightKg: nil, sets: sets)
                items.append(DayEditItem(re: re, exercise: pick))
            }
        }
        replaceIndex = nil
        dirty = true
    }

    // MARK: - Meta computations

    private var totalSets: Int { items.reduce(0) { $0 + $1.re.sets.filter { $0.kind == .work }.count } }

    /// A transparent time estimate (display only, no /cso surface): ~40 s of work per work set plus its
    /// resolved rest, summed and rounded to minutes.
    private var estimatedMinutes: Int {
        var seconds = 0
        for item in items {
            for si in item.re.sets.indices where item.re.sets[si].kind == .work {
                seconds += 40 + RoutineSetEditing.effectiveRest(item.re, si).seconds
            }
        }
        return max(1, Int((Double(seconds) / 60).rounded()))
    }

    /// The day's dominant coarse group — the most-represented across the exercises' primary muscles.
    /// The tie-break is DETERMINISTIC: we scan `MuscleGroup.allCases` in its fixed order and only take a
    /// group when it's strictly ahead, so a tie always resolves to the same group. (A `Dictionary.max` by
    /// value is unstable across accesses, which made the hue + label flicker between re-renders, FER-750.)
    private var dominantGroup: MuscleGroup? {
        var tally: [MuscleGroup: Int] = [:]
        for item in items {
            for m in item.exercise.primaryMuscles { if let g = MuscleGroup.of(m) { tally[g, default: 0] += 1 } }
        }
        var best: MuscleGroup?
        var bestCount = 0
        for g in MuscleGroup.allCases where (tally[g] ?? 0) > bestCount {
            best = g; bestCount = tally[g] ?? 0
        }
        return best
    }
    private var routineTint: Color { dominantGroup?.tint(theme) ?? theme.inkTertiary }
    private var groupTitle: String { dominantGroup?.title ?? String(localized: "Mixed") }

    private var weekdayName: String {
        let symbols = Calendar.current.weekdaySymbols   // index 0 = Sunday … 6 = Saturday
        return symbols[(weekday - 1) % 7]
    }

    // MARK: - Day assignment (header «···»)

    private func changeRoutine(to r: Routine) {
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await store.setRoutineSchedule(weekday: weekday, routineId: r.id)
            await load()
        }
    }

    private func markRest() {
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await store.clearRoutineSchedule(weekday: weekday)
            dismiss()
        }
    }

    // MARK: - Navigation

    private func back() {
        if dirty { showDiscardConfirm = true } else { dismiss() }
    }

    // MARK: - Load + save

    private func load() async {
        guard let store = await repo.storeHandle() else { routine = nil; items = []; dirty = false; return }
        allRoutines = (try? await store.routines()) ?? []
        let rows = (try? await store.routineSchedule()) ?? []
        guard let rid = rows.first(where: { $0.weekday == weekday })?.routineId,
              let r = allRoutines.first(where: { $0.id == rid }) else {
            routine = nil; items = []; dirty = false; return
        }
        routine = r
        let res = await repo.routineExercises(routineId: r.id)
        let all = await repo.allExercises()
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        items = res.compactMap { re in byId[re.exerciseId].map { DayEditItem(re: re, exercise: $0) } }
        dirty = false
    }

    private func save() {
        guard let r = routine else { dismiss(); return }
        let now = Int(Date().timeIntervalSince1970)
        let updated = Routine(id: r.id, name: r.name, tag: r.tag, folderId: r.folderId,
                              createdTs: r.createdTs, updatedTs: now, sortOrder: r.sortOrder)
        let exercises = items.enumerated().map { idx, item -> RoutineExercise in
            var re = item.re; re.position = idx; re.routineId = r.id; return re
        }
        Task {
            try? await repo.saveRoutine(updated, exercises: exercises)
            dismiss()
        }
    }
}

/// One exercise slot in the day editor (mirrors the builder's item).
private struct DayEditItem: Identifiable {
    var re: RoutineExercise
    var exercise: Exercise
    var id: String { re.id }
}

// Shared list-row chrome: clear background, no system separator, standard screen margin with tunable
// vertical insets — a plain List that reproduces «Instrumento» spacing (same pattern as the builder).
private extension View {
    func plainRow(top: CGFloat = 8, bottom: CGFloat = 8) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: NoopMetrics.screenPadding,
                                      bottom: bottom, trailing: NoopMetrics.screenPadding))
    }
}
#endif
