#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// ExerciseLibraryScreen.swift — browse the on-device exercise catalog (FER-346). Two modes from one
// view: BROWSE (opened from the Train hub — tap an exercise to open its detail) and ADD (presented by
// the routine builder with `onAdd` — multi-select, then "Add N" hands the picks back). Search + muscle
// and equipment filters narrow a long catalog; «Create exercise» adds a user-defined one. «Báscula de
// papel»: ink on paper, no datum here so no color; selection is quiet ink chrome.

struct ExerciseLibraryScreen: View {
    /// Non-nil → ADD mode: multi-select with an "Add N" action that returns the picks. Nil → BROWSE.
    var onAdd: (([Exercise]) -> Void)? = nil

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State private var exercises: [Exercise] = []
    @State private var muscleOptions: [String] = []
    @State private var equipmentOptions: [String] = []
    /// Exercise ids the user has logged work sets for (v3 · 1f) — surfaces «Con historial tuyo» first.
    @State private var historyIds: Set<String> = []
    /// Per-exercise best-weight PR + a max-weight-by-day sparkline, for the «Con historial tuyo» rows. Only
    /// built for the (small) set of exercises with history, so it stays cheap.
    @State private var bestKg: [String: Double] = [:]
    @State private var sparklines: [String: [Double]] = [:]
    @State private var loaded = false
    @State private var search = ""
    @State private var muscle: String? = nil
    @State private var equipment: String? = nil
    @State private var selected: Set<String> = []
    @State private var detail: Exercise? = nil
    @State private var showCreate = false

    private var addMode: Bool { onAdd != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                searchField
                filterChips
                Divider().overlay(theme.hairline)
                exerciseList
                createRow
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, addMode ? 88 : NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { if addMode { addBar } }
        .task { await reload() }
        .sheet(item: $detail) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { detail = nil }.foregroundStyle(theme.ink)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
            }
            .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .sheet(isPresented: $showCreate) {
            CreateExerciseSheet(muscles: muscleOptions, equipment: equipmentOptions) { ex in
                Task { try? await repo.saveCustomExercise(ex); await reload() }
            }
            .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(addMode ? "Add to routine" : "Train")
                .instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("Library").font(StrandFont.title1).foregroundStyle(theme.ink)
            // The count reflects the REAL loaded catalog (never a made-up figure). Hidden until loaded so
            // it never flashes a wrong 0.
            if loaded {
                Text("\(exercises.count) exercises")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
            TextField("Search exercise", text: $search)
                .font(StrandFont.body).foregroundStyle(theme.ink)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.inkTertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(theme.hairline.opacity(0.6), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - Filters

    private var filterChips: some View {
        HStack(spacing: 8) {
            filterMenu(title: String(localized: "Muscle"), selection: $muscle, options: muscleOptions, label: StrengthDisplay.muscle)
            filterMenu(title: String(localized: "Equipment"), selection: $equipment, options: equipmentOptions, label: StrengthDisplay.equipment)
            Spacer(minLength: 0)
        }
    }

    private func filterMenu(title: String, selection: Binding<String?>, options: [String],
                            label: @escaping (String) -> String) -> some View {
        let active = selection.wrappedValue
        return Menu {
            Button { selection.wrappedValue = nil } label: {
                Label("All", systemImage: active == nil ? "checkmark" : "")
            }
            ForEach(options, id: \.self) { opt in
                Button { selection.wrappedValue = opt } label: {
                    Label(label(opt), systemImage: active == opt ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(active.map(label) ?? title)
                    .font(StrandFont.subhead)
                    .foregroundStyle(active == nil ? theme.ink : theme.paper)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(active == nil ? theme.inkTertiary : theme.paper)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(active == nil ? Color.clear : theme.ink,
                        in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: active == nil ? 1 : 0))
        }
    }

    // MARK: - List

    private var exerciseList: some View {
        let rows = filtered   // filter the 800+ catalog once per body pass, not per ForEach read
        let mine = rows.filter { historyIds.contains($0.id) }
        let rest = rows.filter { !historyIds.contains($0.id) }
        return LazyVStack(alignment: .leading, spacing: 0) {
            if loaded && rows.isEmpty {
                Text("No exercises match your filters.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 18)
            }
            // «Con historial tuyo» — the exercises you've logged, first, each with its best mark + sparkline.
            if !mine.isEmpty {
                Text("With your history").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .padding(.top, 4).padding(.bottom, 6)
                ForEach(mine) { ex in
                    exerciseRow(ex, showsHistory: true)
                    if ex.id != mine.last?.id { Divider().overlay(theme.hairline.opacity(0.7)) }
                }
            }
            // «De la biblioteca» — the rest of the catalog.
            if !rest.isEmpty {
                Text("From the library").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .padding(.top, mine.isEmpty ? 4 : 18).padding(.bottom, 6)
                ForEach(rest) { ex in
                    exerciseRow(ex, showsHistory: false)
                    if ex.id != rest.last?.id { Divider().overlay(theme.hairline.opacity(0.7)) }
                }
            }
        }
    }

    private func exerciseRow(_ ex: Exercise, showsHistory: Bool) -> some View {
        Button {
            if addMode { toggle(ex) } else { detail = ex }
        } label: {
            HStack(spacing: 13) {
                ExerciseThumbnail(side: 48)   // reserved media slot (FER-751); FER-722 fills it
                VStack(alignment: .leading, spacing: 2) {
                    Text(StrengthDisplay.name(ex)).font(StrandFont.body).foregroundStyle(theme.ink)
                        .multilineTextAlignment(.leading)
                    // Best mark for a history row; the muscle subtitle otherwise.
                    if showsHistory, let kg = bestKg[ex.id] {
                        Text("Best \(StrengthDisplay.weight(kg, system: system))")
                            .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    } else {
                        Text(StrengthDisplay.subtitle(ex)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                }
                Spacer(minLength: 8)
                // A quiet weight-over-time sparkline in the «paper trench» for history rows.
                if showsHistory, let s = sparklines[ex.id], s.count >= 2 {
                    Sparkline(values: s,
                              gradient: Gradient(colors: [theme.inkTertiary, theme.inkSecondary]),
                              bandColor: theme.hairlineStrong,
                              showsHead: false, showsScrub: false)
                        .frame(width: 56, height: 20)
                        .accessibilityHidden(true)
                }
                trailingAccessory(ex)
            }
            .padding(.vertical, 11).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The trailing control: an «Add» affordance in ADD mode (a check when picked), a chevron in BROWSE.
    @ViewBuilder
    private func trailingAccessory(_ ex: Exercise) -> some View {
        if addMode {
            if selected.contains(ex.id) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 21)).foregroundStyle(theme.ink)
            } else {
                Text("Add").font(StrandFont.subhead).foregroundStyle(theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
        } else {
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.inkTertiary)
        }
    }

    private var createRow: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                Text("Create exercise").font(StrandFont.body)
            }
            .foregroundStyle(theme.inkSecondary).padding(.vertical, 13).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add bar (ADD mode)

    private var addBar: some View {
        Button { onAdd?(exercises.filter { selected.contains($0.id) }); dismiss() } label: {
            Text(selected.isEmpty ? "Select exercises" : "Add \(selected.count) exercise\(selected.count == 1 ? "" : "s")")
                .font(StrandFont.headline).foregroundStyle(selected.isEmpty ? theme.inkTertiary : theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(theme.surface, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(selected.isEmpty)
        .padding(.horizontal, NoopMetrics.screenPadding).padding(.bottom, 8)
        .background(theme.paper.opacity(0.96).ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Data

    private func reload() async {
        exercises = await repo.allExercises()
        // Filter options are invariant between reloads — derive them once here, not per body pass.
        muscleOptions = Set(exercises.flatMap { $0.primaryMuscles }).sorted()
        equipmentOptions = Set(exercises.compactMap { $0.equipment }).sorted()
        await loadHistory()
        loaded = true
    }

    /// «Con historial tuyo» (1f): the exercises the user has ever logged, plus each one's best weight and a
    /// weight-by-day sparkline. `recentWorkSets(sinceTs: 0)` gives the id set cheaply; the per-exercise
    /// history is fetched only for that (small) set, so a huge catalog stays fast.
    private func loadHistory() async {
        let events = await repo.recentWorkSets(sinceTs: 0)
        let ids = Set(events.map(\.exerciseId))
        historyIds = ids
        var best: [String: Double] = [:]
        var sparks: [String: [Double]] = [:]
        for id in ids {
            let hist = await repo.exerciseHistory(exerciseId: id)   // oldest→newest (startTs, weightKg, reps)
            guard !hist.isEmpty else { continue }
            best[id] = hist.map(\.weightKg).max()
            // Max weight per day, oldest→newest — a quiet progress trace.
            var byDay: [String: Double] = [:]
            for h in hist {
                let key = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(h.startTs)))
                byDay[key] = Swift.max(byDay[key] ?? 0, h.weightKg)
            }
            sparks[id] = byDay.sorted { $0.key < $1.key }.map(\.value)
        }
        bestKg = best
        sparklines = sparks
    }

    private func toggle(_ ex: Exercise) {
        if selected.contains(ex.id) { selected.remove(ex.id) } else { selected.insert(ex.id) }
    }

    private var filtered: [Exercise] {
        exercises.filter { ex in
            (search.isEmpty || ex.name.localizedCaseInsensitiveContains(search)
                || (ex.nameES?.localizedCaseInsensitiveContains(search) ?? false))   // search both languages (FER-501)
            && (muscle == nil || ex.primaryMuscles.contains(muscle!) || ex.secondaryMuscles.contains(muscle!))
            && (equipment == nil || ex.equipment == equipment)
        }
    }
}

// MARK: - Create exercise (sheet)

/// «Crear ejercicio propio»: name + primary muscle + equipment + record type. Builds a user-defined
/// `Exercise` (a fresh UUID id) and hands it back; the catalog stays read-only.
private struct CreateExerciseSheet: View {
    let muscles: [String]
    let equipment: [String]
    let onCreate: (Exercise) -> Void

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var muscle: String = ""
    @State private var equip: String = ""
    @State private var type: ExerciseType = .weightReps

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text("New exercise").font(StrandFont.title1).foregroundStyle(theme.ink)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Name").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    TextField("e.g. Svend press", text: $name)
                        .font(StrandFont.body).foregroundStyle(theme.ink)
                        .padding(.horizontal, 13).padding(.vertical, 11)
                        .background(theme.hairline.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    pickerRow("Primary muscle", selection: $muscle, options: muscles, placeholder: String(localized: "Pick a muscle"), label: StrengthDisplay.muscle)
                    Divider().overlay(theme.hairline)
                    pickerRow("Equipment", selection: $equip, options: equipment, placeholder: String(localized: "Pick equipment"), label: StrengthDisplay.equipment)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Record type").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    ForEach(ExerciseType.allCases, id: \.self) { t in typeOption(t) }
                }

                Button { create() } label: {
                    Text("Create exercise").font(StrandFont.headline)
                        .foregroundStyle(canCreate ? theme.ink : theme.inkTertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(theme.surface, in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain).disabled(!canCreate)
            }
            .padding(.top, 20).padding(.horizontal, NoopMetrics.screenPadding).padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
    }

    private func pickerRow(_ title: LocalizedStringKey, selection: Binding<String>, options: [String], placeholder: String,
                           label: @escaping (String) -> String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(StrandFont.body).foregroundStyle(theme.ink).frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                ForEach(options, id: \.self) { opt in
                    Button { selection.wrappedValue = opt } label: {
                        Label(label(opt), systemImage: selection.wrappedValue == opt ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(selection.wrappedValue.isEmpty ? placeholder : label(selection.wrappedValue))
                        .font(StrandFont.body).foregroundStyle(selection.wrappedValue.isEmpty ? theme.inkTertiary : theme.inkSecondary)
                    Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
                }
            }
        }
        .frame(minHeight: 40)
    }

    private func typeOption(_ t: ExerciseType) -> some View {
        Button { type = t } label: {
            HStack(spacing: 11) {
                Image(systemName: StrengthDisplay.typeIcon(t)).font(.system(size: 17))
                    .foregroundStyle(type == t ? theme.ink : theme.inkTertiary).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(StrengthDisplay.typeLabel(t)).font(StrandFont.body).foregroundStyle(theme.ink)
                    Text(StrengthDisplay.typeDetail(t)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                if type == t { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.ink) }
            }
            .padding(.horizontal, 13).padding(.vertical, 11).contentShape(Rectangle())
            .background(type == t ? theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(type == t ? theme.ink : theme.hairline, lineWidth: type == t ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func create() {
        let ex = Exercise(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces),
                          type: type, equipment: equip.isEmpty ? nil : equip,
                          primaryMuscles: muscle.isEmpty ? [] : [muscle], secondaryMuscles: [], cues: [])
        onCreate(ex); dismiss()
    }
}
#endif
