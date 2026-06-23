#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// RoutineBuilderScreen.swift — create and edit reusable routines (FER-346, inline rewrite FER-561). The
// Train hub opens this as a sheet (`.new` / `.edit(routine)`), carrying its own routine id. EVERYTHING is
// edited on ONE screen (Hevy-style, FER-561): each exercise shows its set table inline — editable cells,
// a warm-up «C» row, add/delete sets, rest, reorder/superset via its ⋯ menu — matching the live session's
// logging table (LiveStrengthSheet, FER-497) so editing and training feel the same. «Báscula de papel»:
// weights in ink, no color; a flat List + hairlines (no card-in-card), native swipe-to-delete on sets.

// MARK: - Builder target

/// What the builder sheet is editing: a fresh routine or an existing one.
enum BuilderTarget: Identifiable {
    case new
    case edit(Routine)
    var id: String { routine?.id ?? "new" }
    var routine: Routine? { if case .edit(let r) = self { return r } else { return nil } }
}

// MARK: - Builder

struct RoutineBuilderScreen: View {
    let routine: Routine?
    var onSaved: (() async -> Void)? = nil

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State private var name: String = ""
    @State private var items: [BuilderItem] = []
    @State private var loaded = false
    @State private var showLibrary = false
    /// Which exercise's rest is being edited (drives the rest sheet); nil = none.
    @State private var restEdit: RestEditWrap? = nil
    @FocusState private var focusedCell: String?

    private let routineId: String

    init(routine: Routine?, onSaved: (() async -> Void)? = nil) {
        self.routine = routine
        self.onSaved = onSaved
        self.routineId = routine?.id ?? UUID().uuidString
        _name = State(initialValue: routine?.name ?? "")
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
                    Button("Cancel") { dismiss() }.foregroundStyle(theme.inkSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.foregroundStyle(canSave ? theme.ink : theme.inkTertiary).disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedCell = nil }.foregroundStyle(theme.ink)
                }
            }
        }
        .task {
            guard !loaded else { return }
            await loadExisting()
            loaded = true
        }
        .sheet(isPresented: $showLibrary) {
            ExerciseLibraryScreen { picks in append(picks) }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .sheet(item: $restEdit) { wrap in
            restSheet(wrap.index)
                .instrumentoTheme(theme).preferredColorScheme(.light)
        }
    }

    // MARK: - Empty

    private var emptyBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                nameField
                VStack(spacing: 11) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 32)).foregroundStyle(theme.inkTertiary)
                    Text("No exercises yet").font(StrandFont.title2).foregroundStyle(theme.ink)
                    Text("Add exercises from the library to build this routine.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
                QuietButton("Add exercise") { showLibrary = true }
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 20).padding(.horizontal, NoopMetrics.screenPadding).padding(.bottom, NoopMetrics.screenPadding)
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
                    Text("Superset").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        .plainRow(top: NoopMetrics.sectionGap, bottom: 2)
                }
                exerciseHeader(idx).plainRow(top: firstOfGroup(idx) || idx == 0 ? NoopMetrics.gap : NoopMetrics.sectionGap)
                ForEach(Array(items[idx].re.sets.enumerated()), id: \.element.id) { si, _ in
                    setRow(idx: idx, si: si).plainRow(top: 0, bottom: 0)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleteSet(idx: idx, si: si) } label: { Label("Delete", systemImage: "trash") }
                        }
                }
                addSetRow(idx).plainRow(top: 4)
                if lastOfGroup(idx) { restRow(idx).plainRow(top: NoopMetrics.gap) }
            }
            addExerciseRow.plainRow(top: NoopMetrics.sectionGap, bottom: NoopMetrics.screenPadding)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.paper)
        .environment(\.defaultMinListRowHeight, 1)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(routine == nil ? "New routine" : "Editing").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            TextField("Routine name", text: $name)
                .font(StrandFont.title1).foregroundStyle(theme.ink)
        }
    }

    // MARK: - Exercise header (name + ⋯ menu + rest chip + column header)

    private func exerciseHeader(_ idx: Int) -> some View {
        let item = items[idx]
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(spacing: 8) {
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
                    Button { addWarmup(idx) } label: { Label("Add warm-up set", systemImage: "flame") }
                    if idx < items.count - 1 && !sameGroup(idx, idx + 1) {
                        Button { supersetWithNext(idx) } label: { Label("Superset with next", systemImage: "link") }
                    }
                    if inSuperset(idx) {
                        Button { breakSuperset(idx) } label: { Label("Break superset", systemImage: "link.badge.plus") }
                    }
                    Button(role: .destructive) { deleteExercise(idx) } label: { Label("Remove", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary).frame(width: 32, height: 36).contentShape(Rectangle())
                }
            }
            columnHeader(item.exercise.type)
        }
    }

    /// Quiet column header (SET · KG · REPS, gated by exercise type) with a hairline underline.
    @ViewBuilder
    private func columnHeader(_ type: ExerciseType) -> some View {
        HStack(spacing: 10) {
            Text("SET").instrumentoOverline().foregroundStyle(theme.inkTertiary).frame(width: 34, alignment: .leading)
            Spacer(minLength: 0)
            if showsWeight(type) {
                Text(StrengthDisplay.weightUnit(system)).instrumentoOverline().foregroundStyle(theme.inkTertiary).frame(width: 76)
            }
            if showsReps(type) {
                Text("Reps").instrumentoOverline().foregroundStyle(theme.inkTertiary).frame(width: 76)
            }
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    // MARK: - A set row (editable cells; warm-up = «C»)

    private func setRow(idx: Int, si: Int) -> some View {
        let set = items[idx].re.sets[si]
        let type = items[idx].exercise.type
        return HStack(spacing: 10) {
            Text(setLabel(idx: idx, si: si))
                .font(set.kind == .warmup ? StrandFont.caption.weight(.semibold) : StrandFont.body)
                .foregroundStyle(set.kind == .warmup ? theme.inkTertiary : theme.inkSecondary)
                .monospacedDigit().frame(width: 34, alignment: .leading)
            Spacer(minLength: 0)
            if showsWeight(type) {
                cellField(weightText(idx: idx, si: si), id: "\(set.id)-w", keyboard: .decimalPad)
            }
            if showsReps(type) {
                cellField(repsText(idx: idx, si: si), id: "\(set.id)-r", keyboard: .numberPad)
            }
        }
        .frame(minHeight: 46)
        .overlay(alignment: .top) { Divider().overlay(theme.hairline) }
    }

    /// «C» for a warm-up set; otherwise its position among the work sets (1-based, warm-ups don't count).
    private func setLabel(idx: Int, si: Int) -> String {
        if items[idx].re.sets[si].kind == .warmup { return String(localized: "C") }
        let workIndex = items[idx].re.sets[0...si].filter { $0.kind == .work }.count
        return "\(workIndex)"
    }

    private func cellField(_ text: Binding<String>, id: String, keyboard: UIKeyboardType) -> some View {
        TextField("—", text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(StrandFont.bodyNumber)
            .foregroundStyle(theme.ink)
            .focused($focusedCell, equals: id)
            .frame(width: 76, height: 34)
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.hairline))
    }

    private func addSetRow(_ idx: Int) -> some View {
        Button { addSet(idx) } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Add set")
            }
            .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rest row (tappable → rest editor sheet; one per group)

    private func restRow(_ idx: Int) -> some View {
        Button { restEdit = RestEditWrap(index: idx) } label: {
            HStack(spacing: 7) {
                Image(systemName: "clock").font(.system(size: 13)).foregroundStyle(theme.inkTertiary)
                Text(inSuperset(idx) ? "Rest after the round" : "Rest").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                Text(restLabel(items[idx].re)).font(StrandFont.subhead).foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func restLabel(_ re: RoutineExercise) -> String {
        re.restMode == .heartRate ? String(localized: "by HR") : "\(re.restSeconds) s"
    }

    private func restSheet(_ idx: Int) -> some View {
        NavigationStack {
            List {
                RestEditor(restMode: $items[idx].re.restMode, restSeconds: $items[idx].re.restSeconds,
                           hrRestReference: $items[idx].re.hrRestReference, hrRestValue: $items[idx].re.hrRestValue)
                    .plainRow()
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .background(theme.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.paper, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { restEdit = nil }.foregroundStyle(theme.ink) } }
        }
        .presentationDetents([.medium])
    }

    private var addExerciseRow: some View {
        Button { showLibrary = true } label: {
            Label("Add exercise", systemImage: "plus").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
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

    // MARK: - Superset helpers (a group = consecutive exercises sharing supersetGroup)

    private func inSuperset(_ i: Int) -> Bool {
        guard items.indices.contains(i), items[i].re.supersetGroup != nil else { return false }
        return sameGroup(i, i - 1) || sameGroup(i, i + 1)
    }
    private func sameGroup(_ a: Int, _ b: Int) -> Bool {
        guard items.indices.contains(a), items.indices.contains(b),
              let ga = items[a].re.supersetGroup, let gb = items[b].re.supersetGroup else { return false }
        return ga == gb
    }
    /// First member of a superset group (shows the «Superset» header above it).
    private func firstOfGroup(_ i: Int) -> Bool { inSuperset(i) && !sameGroup(i, i - 1) }
    /// Last member of a group (shows the single group rest below it). Ungrouped exercises are their own last.
    private func lastOfGroup(_ i: Int) -> Bool { !sameGroup(i, i + 1) }

    private func supersetWithNext(_ i: Int) {
        guard i < items.count - 1 else { return }
        let group = items[i].re.supersetGroup ?? items[i + 1].re.supersetGroup ?? nextFreeGroup()
        items[i].re.supersetGroup = group
        items[i + 1].re.supersetGroup = group
    }
    private func breakSuperset(_ i: Int) {
        guard let g = items[i].re.supersetGroup else { return }
        items[i].re.supersetGroup = nil
        let remaining = items.indices.filter { items[$0].re.supersetGroup == g }
        if remaining.count == 1 { items[remaining[0]].re.supersetGroup = nil }
    }
    private func nextFreeGroup() -> Int { (items.compactMap { $0.re.supersetGroup }.max() ?? 0) + 1 }

    // MARK: - Load + save

    private func loadExisting() async {
        guard let routine else { return }
        let res = await repo.routineExercises(routineId: routine.id)
        let all = await repo.allExercises()
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        items = res.compactMap { re in byId[re.exerciseId].map { BuilderItem(re: re, exercise: $0) } }
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !items.isEmpty }

    private func save() {
        let now = Int(Date().timeIntervalSince1970)
        let r = Routine(id: routineId, name: name.trimmingCharacters(in: .whitespaces),
                        tag: routine?.tag, createdTs: routine?.createdTs ?? now, updatedTs: now,
                        sortOrder: routine?.sortOrder ?? 0)
        let exercises = items.enumerated().map { idx, item -> RoutineExercise in
            var re = item.re; re.position = idx; re.routineId = routineId; return re
        }
        Task {
            try? await repo.saveRoutine(r, exercises: exercises)
            await onSaved?()
            dismiss()
        }
    }
}

private struct BuilderItem: Identifiable {
    var re: RoutineExercise
    let exercise: Exercise
    var id: String { re.id }
}

/// Identifiable wrapper so the rest sheet can edit one exercise's rest by index.
private struct RestEditWrap: Identifiable { let index: Int; var id: Int { index } }

// Shared list-row chrome: clear background, no system separator (rows draw their own hairline), standard
// screen margin with tunable vertical insets — a plain List that reproduces «Instrumento» spacing.
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
