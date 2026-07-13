#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// WorkoutEditSheet.swift — edit a SAVED strength session (FER-556). Opened from
// `WorkoutSessionDetailScreen`'s «Editar». Corrects the user-authored data: each set's weight/reps,
// add/remove a set, reassign an exercise, the date/time, the routine, and notes. It NEVER touches the
// strap's captured truth (`strain`/`avgHr`/`deviceId`) — those ride through unchanged and show here as a
// read-only «Del cuerpo» block. Persists via `repo.updateSession`, which recomputes the affected PRs
// exactly (a corrected weight can lower a record). «Instrumento»: ink on warm paper, fields are faint
// underlines you fill «with pen», the only color on the physiological datum. Reuses the inline weight/reps
// vocabulary of `LiveStrengthSheet` so there's no new pattern to learn.

struct WorkoutEditSheet: View {
    let session: StrengthSession
    /// Called after a successful save (the detail reloads + bumps the list).
    let onSaved: () async -> Void

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    // MARK: Editable working copy

    @State private var startDate: Date
    @State private var routineId: String?
    @State private var notes: String
    @State private var groups: [EditGroup]
    private let otherSets: [SetEntry]          // non-work sets, preserved verbatim on save
    private let originalStartTs: Int
    private let originalEndTs: Int?
    private let original: Snapshot             // for dirty detection

    // MARK: Loaded context

    @State private var routines: [Routine] = []
    @State private var exercisesByID: [String: Exercise] = [:]

    // MARK: Transient UI

    @FocusState private var focused: CellRef?
    @State private var buffers: [CellRef: String] = [:]
    @State private var reassignGroup: ReassignTarget?
    @State private var showDiscard = false
    @State private var saveError = false
    @State private var showRoutineMenu = false

    init(session: StrengthSession, sets: [SetEntry], onSaved: @escaping () async -> Void) {
        self.session = session
        self.onSaved = onSaved
        _startDate = State(initialValue: Date(timeIntervalSince1970: TimeInterval(session.startTs)))
        _routineId = State(initialValue: session.routineId)
        _notes = State(initialValue: session.notes ?? "")
        let work = sets.filter { $0.kind == .work }
        otherSets = sets.filter { $0.kind != .work }
        var order: [String] = []
        var by: [String: [SetEntry]] = [:]
        for s in work {
            if by[s.exerciseId] == nil { order.append(s.exerciseId) }
            by[s.exerciseId, default: []].append(s)
        }
        let g = order.map { id in EditGroup(exerciseId: id, sets: (by[id] ?? []).map(EditSet.init)) }
        _groups = State(initialValue: g)
        originalStartTs = session.startTs
        originalEndTs = session.endTs
        original = Snapshot(startTs: session.startTs, routineId: session.routineId,
                            notes: session.notes ?? "", groups: g)
    }

    var body: some View {
        NavigationStack {
            listBody
            .background(theme.paper.ignoresSafeArea())
            .navigationTitle("Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }.foregroundStyle(theme.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(StrandFont.headline)
                        .foregroundStyle(canSave ? theme.ink : theme.inkTertiary)
                        .disabled(!canSave)
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .instrumentoConfirm(
            isPresented: $showDiscard,
            title: String(localized: "Discard changes?"),
            context: String(localized: "WORKOUT · UNSAVED CHANGES"),
            message: String(localized: "Your edits to this workout will be lost."),
            actions: [
                .init(String(localized: "Keep editing"), role: .primary),
                .init(String(localized: "Discard changes"), role: .destructive) { dismiss() }
            ]
        )
        // FER-837: save failure is an inline banner (a result must not cover the screen), not an alert.
        .overlay(alignment: .top) {
            if saveError {
                Text("Couldn't save the workout. Try again.")
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
        .sheet(item: $reassignGroup) { target in
            NavigationStack {
                ExerciseLibraryScreen { picks in
                    if let ex = picks.first { reassign(group: target.index, to: ex) }
                    reassignGroup = nil
                }
                .navigationTitle("Choose exercise")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(theme.paper, for: .navigationBar)
            }
            .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .task {
            routines = await repo.routines()
            let all = await repo.allExercises()
            exercisesByID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    // MARK: - List

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: CenitMetrics.screenPadding, bottom: 0, trailing: CenitMetrics.screenPadding)
    }

    private var listBody: some View {
        List {
            Section {
                whenSection.plainRow(rowInsets)
                routineSection.plainRow(rowInsets)
                capturedSection.plainRow(rowInsets)
            }
            ForEach(Array(groups.enumerated()), id: \.element.id) { gi, _ in
                exerciseSection(gi)
            }
            if workSetCount == 0 {
                Section { validationNote("A workout needs at least one set.").plainRow(rowInsets) }
            } else if !repsValid {
                Section { validationNote("Check the weight and reps.").plainRow(rowInsets) }
            }
            Section { notesSection.plainRow(rowInsets) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private func exerciseSection(_ gi: Int) -> some View {
        let type = exercisesByID[groups[gi].exerciseId]?.type ?? .weightReps
        return Section {
            ForEach(Array(groups[gi].sets.enumerated()), id: \.element.id) { si, _ in
                setRow(gi: gi, si: si, type: type).plainRow(rowInsets)
            }
            .onDelete { offsets in removeSets(gi: gi, offsets) }
            addSetRow(gi).plainRow(rowInsets)
        } header: {
            exerciseHeader(gi).textCase(nil)
        }
    }

    // MARK: - Sections

    private var whenSection: some View {
        HStack {
            Text("When").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 12)
            DatePicker("", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden().tint(theme.dataStrain)
        }
    }

    private var routineSection: some View {
        HStack {
            Text("Routine").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 12)
            Button { showRoutineMenu = true } label: {
                HStack(spacing: 5) {
                    Text(routineLabel).font(StrandFont.body).foregroundStyle(theme.ink)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
            }
            .buttonStyle(.plain)
            .paperMenu(isPresented: $showRoutineMenu, items:
                [PaperMenuItem(String(localized: "No routine"),
                               systemImage: routineId == nil ? "checkmark" : nil) { routineId = nil }]
                + routines.map { r in
                    PaperMenuItem(r.name, systemImage: routineId == r.id ? "checkmark" : nil) { routineId = r.id }
                })
        }
    }

    /// The strap's captured truth — shown so the user knows it exists and why it isn't editable.
    @ViewBuilder
    private var capturedSection: some View {
        if session.strain != nil || session.avgHr != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("From your body").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(spacing: 20) {
                    if let strain = session.strain {
                        readonlyStat(StrengthHistoryFormat.strain(strain), label: "Effort")
                    }
                    if let hr = session.avgHr {
                        readonlyStat("\(hr)", unit: "bpm", label: "Avg HR")
                    }
                }
                Text("Effort and heart rate are measured by your band. They can't be edited.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.paperHi, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        }
    }

    private func readonlyStat(_ value: String, unit: String? = nil, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(StrandFont.number(18, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    .monospacedDigit()
                if let unit { Text(unit).font(StrandFont.caption).foregroundStyle(theme.inkTertiary) }
            }
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private func exerciseHeader(_ gi: Int) -> some View {
        Button { reassignGroup = ReassignTarget(index: gi) } label: {
            HStack(spacing: 6) {
                Text(exerciseName(groups[gi].exerciseId)).font(StrandFont.headline).foregroundStyle(theme.ink)
                StrandIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel(Text(exerciseName(groups[gi].exerciseId)))
        .accessibilityHint(Text("Change exercise"))
    }

    private func addSetRow(_ gi: Int) -> some View {
        Button { addSet(gi) } label: {
            HStack(spacing: 6) {
                StrandIcon.add.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                Text("Add set").font(StrandFont.subhead)
            }
            .foregroundStyle(theme.inkSecondary)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Adds a set to this exercise"))
    }

    private func setRow(gi: Int, si: Int, type: ExerciseType) -> some View {
        HStack(spacing: 10) {
            Text("Set \(si + 1)").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                .frame(minWidth: 48, alignment: .leading)
            Spacer(minLength: 8)
            switch type {
            case .weightReps, .bodyweight:
                if type == .bodyweight {
                    Text("+").font(StrandFont.body).foregroundStyle(theme.inkTertiary)
                }
                numberField(.init(g: gi, s: si, field: .weight), isInt: false)
                Text("×").font(StrandFont.body).foregroundStyle(theme.inkTertiary)
                numberField(.init(g: gi, s: si, field: .reps), isInt: true)
            case .time, .distance:
                Text(StrengthHistoryFormat.setLine(setEntrySnapshot(gi, si, type: type), system: system))
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary).monospacedDigit()
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(setAccessibilityLabel(gi: gi, si: si, type: type)))
    }

    /// An editable numeric cell — the proven `LiveStrengthSheet` pattern: a faint underline you fill, with
    /// a transient text buffer so a half-typed entry isn't fought, and the model updated on each valid parse.
    private func numberField(_ ref: CellRef, isInt: Bool) -> some View {
        let value = ref.field == .weight ? displayWeight(groups[ref.g].sets[ref.s].weightKg)
                                         : Double(groups[ref.g].sets[ref.s].reps)
        let text = Binding<String>(
            get: { buffers[ref] ?? formatCell(value, isInt: isInt) },
            set: { raw in
                buffers[ref] = raw
                guard let v = Self.parseDouble(raw) else { return }
                if ref.field == .weight { groups[ref.g].sets[ref.s].weightKg = max(0, storedKg(fromDisplay: v)) }
                else { groups[ref.g].sets[ref.s].reps = max(0, Int(v.rounded())) }
            })
        return TextField("", text: text)
            .keyboardType(isInt ? .numberPad : .decimalPad)
            .multilineTextAlignment(.center)
            .font(StrandFont.number(16, weight: .regular)).monospacedDigit()
            .foregroundStyle(theme.ink)
            .focused($focused, equals: ref)
            .frame(width: 64, height: 44)
            .overlay(alignment: .bottom) {
                Rectangle().fill(focused == ref ? theme.dataStrain : theme.hairlineStrong)
                    .frame(height: focused == ref ? 2 : 1).padding(.bottom, 6)
            }
            .onChange(of: focused) { _, now in if now != ref { buffers[ref] = nil } }   // drop buffer on blur
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            TextField("Add a note (optional)", text: $notes, axis: .vertical)
                .font(StrandFont.body).foregroundStyle(theme.ink)
                .lineLimit(1...5)
        }
    }

    private func validationNote(_ key: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle").font(StrandFont.glyph(.chevron))
            Text(key).font(StrandFont.caption)
        }
        .foregroundStyle(theme.dataStrain)
    }

    // MARK: - Derived

    private var routineLabel: String {
        routineId.flatMap { id in routines.first { $0.id == id }?.name } ?? String(localized: "No routine")
    }

    private func exerciseName(_ id: String) -> String {
        exercisesByID[id].map(StrengthDisplay.name) ?? String(localized: "Exercise")
    }

    private var repsValid: Bool {
        for g in groups {
            let type = exercisesByID[g.exerciseId]?.type ?? .weightReps
            if type == .weightReps || type == .bodyweight, g.sets.contains(where: { $0.reps < 1 }) {
                return false
            }
        }
        return true
    }

    private var workSetCount: Int { groups.reduce(0) { $0 + $1.sets.count } }

    private var currentSnapshot: Snapshot {
        Snapshot(startTs: Int(startDate.timeIntervalSince1970), routineId: routineId,
                 notes: notes, groups: groups)
    }
    private var isDirty: Bool { currentSnapshot != original }
    private var canSave: Bool { isDirty && workSetCount >= 1 && repsValid }

    // MARK: - Mutations

    private func addSet(_ gi: Int) {
        let template = groups[gi].sets.last
        groups[gi].sets.append(EditSet(new: groups[gi].sets.last?.ts ?? originalStartTs, template: template))
    }

    private func removeSets(gi: Int, _ offsets: IndexSet) {
        guard groups.indices.contains(gi) else { return }
        groups[gi].sets.remove(atOffsets: offsets)
        if groups[gi].sets.isEmpty { groups.remove(at: gi) }   // an emptied exercise drops out
    }

    private func reassign(group gi: Int, to ex: Exercise) {
        guard groups.indices.contains(gi) else { return }
        groups[gi].exerciseId = ex.id
        exercisesByID[ex.id] = ex
    }

    // MARK: - Cancel / save

    private func cancel() {
        if isDirty { showDiscard = true } else { dismiss() }
    }

    private func save() {
        let newStart = Int(startDate.timeIntervalSince1970)
        let delta = newStart - originalStartTs
        var updated = session                        // id / deviceId / strain / avgHr ride through unchanged
        updated.startTs = newStart
        updated.endTs = originalEndTs.map { $0 + delta }   // preserve duration
        updated.routineId = routineId
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = trimmed.isEmpty ? nil : trimmed

        var out: [SetEntry] = []
        var pos = 0
        for g in groups {
            let type = exercisesByID[g.exerciseId]?.type ?? .weightReps
            let usesWeightReps = (type == .weightReps || type == .bodyweight)
            for s in g.sets {
                out.append(SetEntry(id: s.id, sessionId: session.id, exerciseId: g.exerciseId, position: pos,
                                    kind: .work,
                                    weightKg: usesWeightReps ? s.weightKg : nil,
                                    reps: usesWeightReps ? s.reps : nil,
                                    timeS: s.timeS, distanceM: s.distanceM, done: true, ts: s.ts))
                pos += 1
            }
        }
        for var s in otherSets { s.position = pos; out.append(s); pos += 1 }   // preserve warm-ups etc.

        Task {
            do {
                try await repo.updateSession(updated, sets: out)
                await onSaved()
                dismiss()
            } catch {
                saveError = true
            }
        }
    }

    // MARK: - Unit + format helpers (mirror LiveStrengthSheet)

    private func displayWeight(_ kg: Double) -> Double {
        system == .imperial ? UnitFormatter.kgToPounds(kg) : kg
    }
    private func storedKg(fromDisplay shown: Double) -> Double {
        system == .imperial ? UnitFormatter.poundsToKg(shown) : shown
    }

    private func formatCell(_ v: Double, isInt: Bool) -> String {
        if isInt { return "\(Int(v.rounded()))" }
        return v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }

    private static func parseDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return trimmed.isEmpty ? nil : Double(trimmed)
    }

    /// A `SetEntry` snapshot for read-only time/distance display (the editor doesn't type those).
    private func setEntrySnapshot(_ gi: Int, _ si: Int, type: ExerciseType) -> SetEntry {
        let s = groups[gi].sets[si]
        return SetEntry(id: s.id, sessionId: session.id, exerciseId: groups[gi].exerciseId, position: si,
                        kind: .work, weightKg: nil, reps: nil, timeS: s.timeS, distanceM: s.distanceM,
                        done: true, ts: s.ts)
    }

    private func setAccessibilityLabel(gi: Int, si: Int, type: ExerciseType) -> String {
        let s = groups[gi].sets[si]
        switch type {
        case .weightReps, .bodyweight:
            return String(localized: "Set \(si + 1), \(StrengthDisplay.weight(s.weightKg, system: system)) by \(s.reps) reps, editable")
        case .time, .distance:
            return String(localized: "Set \(si + 1)")
        }
    }
}

// MARK: - Working-copy models

/// An editable exercise group: a (mutable) exercise id and its ordered work sets.
private struct EditGroup: Identifiable, Equatable {
    let id = UUID()
    var exerciseId: String
    var sets: [EditSet]
}

/// One editable work set. Keeps the original set id (so links/PRs stay stable); a fresh set gets a new id.
private struct EditSet: Identifiable, Equatable {
    let id: String
    var weightKg: Double
    var reps: Int
    var timeS: Double?
    var distanceM: Double?
    let ts: Int

    init(_ s: SetEntry) {
        id = s.id; weightKg = s.weightKg ?? 0; reps = s.reps ?? 0
        timeS = s.timeS; distanceM = s.distanceM; ts = s.ts
    }
    init(new ts: Int, template: EditSet?) {
        id = UUID().uuidString
        weightKg = template?.weightKg ?? 0
        reps = template?.reps ?? 8
        timeS = nil; distanceM = nil
        self.ts = ts
    }
}

/// A value snapshot of everything editable — compared to detect unsaved changes.
private struct Snapshot: Equatable {
    let startTs: Int
    let routineId: String?
    let notes: String
    let groups: [EditGroup]
}

/// Identifies an editable inline cell (which set, which field).
private struct CellRef: Hashable {
    enum Field { case weight, reps }
    let g: Int
    let s: Int
    let field: Field
}

/// The exercise group whose reassignment picker is open (wraps an index so `.sheet(item:)` has identity).
private struct ReassignTarget: Identifiable {
    let id = UUID()
    let index: Int
}

private extension View {
    /// A list row that disappears into the paper: clear background, no separator, screen-margin insets —
    /// so the `List` reproduces the «Instrumento» look (same recipe as `RoutineBuilderScreen`).
    func plainRow(_ insets: EdgeInsets) -> some View {
        self.listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(insets)
    }
}
#endif
