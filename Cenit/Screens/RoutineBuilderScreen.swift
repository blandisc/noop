#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// RoutineBuilderScreen.swift — create and edit reusable routines (FER-346). The Train hub's «Mis
// rutinas» list (`EntrenarView`, FER-343) opens this builder as a sheet — `.new` or `.edit(routine)`
// — so it carries its own routine id (a value the hub's typed nav path can't, FER-171). The builder
// adds exercises from the library (multi-add), reorders/deletes them, groups them into supersets, and
// tunes each one in `RoutineExerciseEditor`. «Báscula de papel»: weights in ink, no color (no live
// physiology here); hierarchy by space + hairlines, no card-in-card.

// MARK: - Builder target

/// What the builder sheet is editing: a fresh routine or an existing one. Driven by `EntrenarView`'s
/// «Mis rutinas» (the routine list is FER-343's hub; this is just the create/edit target).
enum BuilderTarget: Identifiable {
    case new
    case edit(Routine)
    var id: String { routine?.id ?? "new" }
    var routine: Routine? { if case .edit(let r) = self { return r } else { return nil } }
}

// MARK: - Builder

struct RoutineBuilderScreen: View {
    /// nil → a fresh routine; otherwise the routine to edit (its exercises load on appear).
    let routine: Routine?
    /// Called after a successful save so the caller can refresh its list.
    var onSaved: (() async -> Void)? = nil

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository

    @State private var name: String = ""
    @State private var items: [BuilderItem] = []
    @State private var loaded = false
    @State private var showLibrary = false
    @State private var editingIndex: Int? = nil

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
                if !items.isEmpty { ToolbarItem(placement: .topBarLeading) { EditButton().foregroundStyle(theme.inkSecondary) } }
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
        .sheet(item: editorBinding) { wrap in
            RoutineExerciseEditor(item: $items[wrap.index])
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

    // MARK: - List

    private var listBody: some View {
        List {
            Section { nameField.listRowInsets(EdgeInsets(top: 8, leading: NoopMetrics.screenPadding, bottom: 8, trailing: NoopMetrics.screenPadding)) }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)

            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    exerciseRow(idx)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: NoopMetrics.screenPadding, bottom: 0, trailing: NoopMetrics.screenPadding))
                }
                .onMove(perform: move)
                .onDelete(perform: deleteRows)
            }

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 20) {
                        Button { showLibrary = true } label: {
                            Label("Add exercise", systemImage: "plus").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                        }.buttonStyle(.plain)
                    }
                }
                .listRowInsets(EdgeInsets(top: 14, leading: NoopMetrics.screenPadding, bottom: 8, trailing: NoopMetrics.screenPadding))
            }
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(routine == nil ? "New routine" : "Editing").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            TextField("Routine name", text: $name)
                .font(StrandFont.title1).foregroundStyle(theme.ink)
        }
    }

    @ViewBuilder
    private func exerciseRow(_ idx: Int) -> some View {
        let item = items[idx]
        let grouped = inSuperset(idx)
        let firstOfGroup = grouped && !sameGroup(idx, idx - 1)
        VStack(alignment: .leading, spacing: 0) {
            if firstOfGroup {
                Text("Superset").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .padding(.leading, grouped ? 13 : 0).padding(.top, 12).padding(.bottom, 2)
            }
            HStack(spacing: 11) {
                if grouped {
                    Rectangle().fill(theme.hairlineStrong).frame(width: 2)
                        .padding(.vertical, sameGroup(idx, idx + 1) || sameGroup(idx, idx - 1) ? 0 : 8)
                }
                Button { editingIndex = idx } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.exercise.name).font(StrandFont.body).foregroundStyle(theme.ink)
                        Text(summary(item)).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Menu {
                    Button { editingIndex = idx } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                    if idx < items.count - 1 && !sameGroup(idx, idx + 1) {
                        Button { supersetWithNext(idx) } label: { Label("Superset with next", systemImage: "link") }
                    }
                    if grouped {
                        Button { breakSuperset(idx) } label: { Label("Break superset", systemImage: "link.badge.plus") }
                    }
                    Button(role: .destructive) { deleteRows(IndexSet(integer: idx)) } label: { Label("Remove", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary).frame(width: 32, height: 40).contentShape(Rectangle())
                }
            }
            .padding(.vertical, 10)
            Divider().overlay(theme.hairline.opacity(0.7)).padding(.leading, grouped ? 13 : 0)
        }
    }

    private func summary(_ item: BuilderItem) -> String {
        let re = item.re
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        let work = re.sets.filter { $0.kind == .work }
        let count = work.isEmpty ? re.targetSets : work.count
        var parts: [String] = ["\(count) set\(count == 1 ? "" : "s")"]
        // Reps and weight collapse to a single value when uniform, else show first→last (the user's
        // intended progression across the sets, e.g. "8–4 reps · 60–80 kg").
        let reps = work.compactMap { $0.reps }
        if let r = rangeText(reps, { "\($0)" }) {
            parts.append("\(r) reps")
        } else if let r = re.targetReps {
            parts.append("\(r) rep\(r == 1 ? "" : "s")")
        }
        let weights = work.compactMap { $0.weightKg }.filter { $0 > 0 }
        if let r = rangeText(weights, { StrengthDisplay.weightNumber($0, system: system) }) {
            parts.append("\(r) \(StrengthDisplay.weightUnit(system))")
        } else if let w = re.targetWeightKg, w > 0 {
            parts.append(StrengthDisplay.weight(w, system: system))
        }
        return parts.joined(separator: " · ")
    }

    /// Formatted "60" when all values are equal, "60–80" (first→last) when they differ, nil when empty.
    private func rangeText<T: Equatable>(_ values: [T], _ fmt: (T) -> String) -> String? {
        guard let first = values.first, let last = values.last else { return nil }
        return values.allSatisfy { $0 == first } ? fmt(first) : "\(fmt(first))–\(fmt(last))"
    }

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    // MARK: - Superset helpers

    private func inSuperset(_ i: Int) -> Bool {
        guard items.indices.contains(i), items[i].re.supersetGroup != nil else { return false }
        return sameGroup(i, i - 1) || sameGroup(i, i + 1)
    }
    private func sameGroup(_ a: Int, _ b: Int) -> Bool {
        guard items.indices.contains(a), items.indices.contains(b) else { return false }
        guard let ga = items[a].re.supersetGroup, let gb = items[b].re.supersetGroup else { return false }
        return ga == gb
    }
    private func supersetWithNext(_ i: Int) {
        guard i < items.count - 1 else { return }
        let group = items[i].re.supersetGroup ?? items[i + 1].re.supersetGroup ?? nextFreeGroup()
        items[i].re.supersetGroup = group
        items[i + 1].re.supersetGroup = group
    }
    private func breakSuperset(_ i: Int) {
        guard let g = items[i].re.supersetGroup else { return }
        items[i].re.supersetGroup = nil
        // A group left with a single member is no longer a superset — clear it too.
        let remaining = items.indices.filter { items[$0].re.supersetGroup == g }
        if remaining.count == 1 { items[remaining[0]].re.supersetGroup = nil }
    }
    private func nextFreeGroup() -> Int {
        (items.compactMap { $0.re.supersetGroup }.max() ?? 0) + 1
    }

    // MARK: - Mutations

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
    private func move(from: IndexSet, to: Int) { items.move(fromOffsets: from, toOffset: to) }
    private func deleteRows(_ offsets: IndexSet) { items.remove(atOffsets: offsets) }

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

    // Identifiable wrapper so `.sheet(item:)` can edit a row by index.
    private var editorBinding: Binding<EditorWrap?> {
        Binding(get: { editingIndex.map(EditorWrap.init) }, set: { editingIndex = $0?.index })
    }
}

private struct BuilderItem: Identifiable {
    var re: RoutineExercise
    let exercise: Exercise
    var id: String { re.id }
}

private struct EditorWrap: Identifiable { let index: Int; var id: Int { index } }

// MARK: - Per-exercise editor

/// Tune one routine slot: the per-set scheme (each work set's own reps/weight, add/remove — FER-492),
/// an auto warm-up ramp from % of the working weight (40/60/80, toggleable — warm-ups don't count
/// toward PR or volume), and the rest rule (by heart rate, the strap differentiator, or a fixed timer).
private struct RoutineExerciseEditor: View {
    @Binding var item: BuilderItem

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    @FocusState private var focusedCell: String?

    private let warmupPresets: [Double] = [0.4, 0.6, 0.8]
    private var showsReps: Bool { item.exercise.type == .weightReps || item.exercise.type == .bodyweight }
    private var showsWeight: Bool { item.exercise.type == .weightReps }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(StrengthDisplay.subtitle(item.exercise)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        Text(item.exercise.name).font(StrandFont.title1).foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .rowChrome(top: 20, bottom: 0)
                }
                seriesSection
                if showsWeight { Section { warmup.rowChrome() } }
                Section { rest.rowChrome() }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .background(theme.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(theme.ink)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedCell = nil }.foregroundStyle(theme.ink)
                }
            }
        }
    }

    // MARK: Series (per-set table)

    @ViewBuilder
    private var seriesSection: some View {
        Section {
            seriesHeader.rowChrome(top: 4, bottom: 4)
            ForEach(Array(item.re.sets.enumerated()), id: \.element.id) { idx, _ in
                setRow($item.re.sets[idx], index: idx).rowChrome(top: 0, bottom: 0)
            }
            .onDelete(perform: deleteSets)
            Button { addSet() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add set")
                }
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .rowChrome(top: 0, bottom: 0)
            Text("Swipe a set to delete it.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .rowChrome(top: 8, bottom: 0)
        } header: { EmptyView() }
    }

    private var seriesHeader: some View {
        HStack(spacing: 10) {
            Text("Set").instrumentoOverline().foregroundStyle(theme.inkTertiary).frame(width: 30, alignment: .leading)
            Spacer(minLength: 0)
            if showsWeight {
                Text(StrengthDisplay.weightUnit(system)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .frame(width: 80)
            }
            if showsReps {
                Text("Reps").instrumentoOverline().foregroundStyle(theme.inkTertiary).frame(width: 80)
            }
        }
    }

    private func setRow(_ set: Binding<RoutineSet>, index: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .monospacedDigit().frame(width: 30, alignment: .leading)
            Spacer(minLength: 0)
            if showsWeight {
                cellField(weightText(set), placeholder: "—", id: "\(set.wrappedValue.id)-w", keyboard: .decimalPad)
            }
            if showsReps {
                cellField(repsText(set), placeholder: "—", id: "\(set.wrappedValue.id)-r", keyboard: .numberPad)
            }
        }
        .frame(minHeight: 46)
        .overlay(alignment: .top) { Divider().overlay(theme.hairline) }
    }

    private func cellField(_ text: Binding<String>, placeholder: String, id: String, keyboard: UIKeyboardType) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(StrandFont.bodyNumber)
            .foregroundStyle(theme.ink)
            .focused($focusedCell, equals: id)
            .frame(width: 80, height: 34)
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.hairline))
    }

    // MARK: Set mutations + cell bindings

    private func addSet() {
        let last = item.re.sets.last
        item.re.sets.append(RoutineSet(position: item.re.sets.count, kind: .work,
                                       reps: last?.reps ?? (showsReps ? 8 : nil), weightKg: last?.weightKg))
    }

    private func deleteSets(_ offsets: IndexSet) {
        guard item.re.sets.count > offsets.count else { return }   // keep at least one set
        item.re.sets.remove(atOffsets: offsets)
        for i in item.re.sets.indices { item.re.sets[i].position = i }
    }

    private func repsText(_ set: Binding<RoutineSet>) -> Binding<String> {
        Binding(get: { set.wrappedValue.reps.map(String.init) ?? "" },
                set: { set.wrappedValue.reps = Int($0.filter(\.isNumber)) })
    }

    private func weightText(_ set: Binding<RoutineSet>) -> Binding<String> {
        Binding(
            get: {
                guard let kg = set.wrappedValue.weightKg, kg > 0 else { return "" }
                return StrengthDisplay.weightNumber(kg, system: system)
            },
            set: { raw in
                let norm = raw.replacingOccurrences(of: ",", with: ".")
                guard let v = Double(norm), v > 0 else { set.wrappedValue.weightKg = nil; return }
                set.wrappedValue.weightKg = system == .imperial ? UnitFormatter.poundsToKg(v) : v
            })
    }

    // MARK: Warm-up

    private var warmup: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Warm-up · auto from %").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(spacing: 8) {
                ForEach(warmupPresets, id: \.self) { p in warmupChip(p) }
            }
            Text("Ramp sets from the working weight. Warm-ups don't count toward PR or volume.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func warmupChip(_ p: Double) -> some View {
        let on = item.re.warmupPercents.contains(p)
        return Button {
            if on { item.re.warmupPercents.removeAll { $0 == p } }
            else { item.re.warmupPercents = (item.re.warmupPercents + [p]).sorted() }
        } label: {
            Text("\(Int(p * 100))%").font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(on ? theme.ink : theme.inkTertiary)
                .padding(.horizontal, 15).padding(.vertical, 7)
                .overlay(Capsule(style: .continuous).strokeBorder(on ? theme.ink : theme.hairlineStrong, lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Rest

    private var rest: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Rest between sets").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Picker("Rest mode", selection: $item.re.restMode) {
                Text("By HR").tag(RestMode.heartRate)
                Text("Fixed").tag(RestMode.fixed)
            }
            .pickerStyle(.segmented)
            if item.re.restMode == .fixed {
                HStack(spacing: 14) {
                    Text("Seconds").font(StrandFont.body).foregroundStyle(theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        Text("\(item.re.restSeconds) s").font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
                        Stepper("Seconds", value: $item.re.restSeconds, in: 15...300, step: 15).labelsHidden().tint(theme.inkSecondary)
                    }
                }
                .frame(minHeight: 40)
            }
            Text(item.re.restMode == .heartRate
                 ? "Ready when your pulse drops — your strap reads it."
                 : "A fixed countdown between sets.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

}

// Shared list-row chrome for the editor: clear background, no system separator (rows draw their own
// hairline), and the standard screen margin with tunable vertical insets — so a plain List reproduces
// the «Instrumento» spacing without card chrome.
private extension View {
    func rowChrome(top: CGFloat = 8, bottom: CGFloat = 8) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: NoopMetrics.screenPadding,
                                      bottom: bottom, trailing: NoopMetrics.screenPadding))
    }
}
#endif
