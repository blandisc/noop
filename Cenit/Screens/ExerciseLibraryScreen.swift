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
    @EnvironmentObject private var mediaCoordinator: MediaDownloadCoordinator
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State private var exercises: [Exercise] = []
    @State private var muscleOptions: [String] = []
    @State private var equipmentOptions: [String] = []
    /// Exercise ids the user has logged work sets for (v3 · 1f) — surfaces «Con historial tuyo» first.
    @State private var historyIds: Set<String> = []
    /// Per-exercise best-weight PR for the «Con historial tuyo» rows — only built for the (small)
    /// set of exercises with history, so it stays cheap.
    @State private var bestKg: [String: Double] = [:]
    @State private var loaded = false
    @State private var search = ""
    @State private var muscle: String? = nil
    @State private var equipment: String? = nil
    @State private var typeFilter: String? = nil
    @State private var showMuscleFilter = false
    @State private var showEquipmentFilter = false
    @State private var showTypeFilter = false
    @State private var selected: Set<String> = []
    @State private var detail: Exercise? = nil
    @State private var showCreate = false

    private var addMode: Bool { onAdd != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                header
                searchField
                filterChips
                Divider().overlay(theme.hairline)
                exerciseList
                createRow
            }
            .padding(.top, CenitMetrics.screenTop)
            .padding(.horizontal, CenitMetrics.screenPadding)
            // The safeAreaInset already carves out the addBar's height — no magic 88.
            .padding(.bottom, CenitMetrics.screenPadding)
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
            // Handoff: overline «BIBLIOTECA» + the COUNT as the Grotesk hero title («873 ejercicios»).
            // The count reflects the REAL loaded catalog (never a made-up figure) — until it loads, the
            // title falls back to the section name so nothing flashes a wrong 0.
            Text(addMode ? "Add to routine" : "Library")
                .font(InstrumentoType.groteskSheetTitle).tracking(InstrumentoType.groteskSheetTitleTracking)
                .textCase(.uppercase).foregroundStyle(theme.inkTertiary)
            Group {
                if loaded {
                    Text("\(exercises.count) exercises")
                } else {
                    Text("Library")
                }
            }
            .font(InstrumentoType.groteskHeroNumeral(28)).tracking(InstrumentoType.groteskHeroTrackingScaled(28))
            .foregroundStyle(theme.ink)
            .padding(.top, 2)
        }
    }

    private var searchField: some View {
        HStack(spacing: CenitMetrics.space2) {
            StrandIcon.search.image.font(StrandFont.glyph(.inline)).foregroundStyle(theme.inkTertiary)
            TextField("Search exercise", text: $search)
                .font(StrandFont.body).foregroundStyle(theme.ink)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.inkTertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, CenitMetrics.gap).padding(.vertical, CenitMetrics.rowVPad)
        // Handoff: the search field sits on the raised paper surface (#FBF9F2) with a 1px control
        // hairline (#D8D0BD) at radius 12 — a defined field, not a tinted fill.
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
            .strokeBorder(theme.hairlineStrong, lineWidth: 1))
    }

    // MARK: - Filters

    private var filterChips: some View {
        HStack(spacing: CenitMetrics.space1) {
            filterMenu(title: String(localized: "Muscle"), isPresented: $showMuscleFilter,
                       selection: $muscle, options: muscleOptions, label: StrengthDisplay.muscle)
            filterMenu(title: String(localized: "Equipment"), isPresented: $showEquipmentFilter,
                       selection: $equipment, options: equipmentOptions, label: StrengthDisplay.equipment)
            filterMenu(title: String(localized: "Type"), isPresented: $showTypeFilter,
                       selection: $typeFilter,
                       options: ExerciseType.allCases.map(\.rawValue),
                       label: { StrengthDisplay.typeName(ExerciseType(rawValue: $0) ?? .weightReps) })
            Spacer(minLength: 0)
        }
    }

    private func filterMenu(title: String, isPresented: Binding<Bool>, selection: Binding<String?>,
                            options: [String], label: @escaping (String) -> String) -> some View {
        let active = selection.wrappedValue
        var rows: [PaperMenuItem] = [
            PaperMenuItem(String(localized: "All"), systemImage: active == nil ? "checkmark" : nil) {
                selection.wrappedValue = nil
            }
        ]
        rows += options.map { opt in
            PaperMenuItem(label(opt), systemImage: active == opt ? "checkmark" : nil) {
                selection.wrappedValue = opt
            }
        }
        return Button { isPresented.wrappedValue = true } label: {
            HStack(spacing: CenitMetrics.space1) {
                Text(active.map(label) ?? title)
                    .font(StrandFont.subhead)
                    .foregroundStyle(active == nil ? theme.ink : theme.paper)
                StrandIcon.down.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(active == nil ? theme.inkTertiary : theme.paper)
            }
            .padding(.horizontal, CenitMetrics.gap).padding(.vertical, 6)  // token-exempt: chip 6pt del handoff
            .background(active == nil ? Color.clear : theme.ink,
                        in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: active == nil ? 1 : 0))
        }
        .buttonStyle(.plain)
        .paperMenu(isPresented: isPresented, items: rows)
    }

    // MARK: - List

    private var exerciseList: some View {
        let rows = filtered   // filter the 800+ catalog once per body pass, not per ForEach read
        let mine = rows.filter { historyIds.contains($0.id) }
        let rest = rows.filter { !historyIds.contains($0.id) }
        // «De la biblioteca» grouped by primary muscle (empty key → "Other"), sorted by display label.
        let libraryGroups: [(key: String, items: [Exercise])] = {
            var dict: [String: [Exercise]] = [:]
            for ex in rest {
                dict[ex.primaryMuscles.first ?? "", default: []].append(ex)
            }
            return dict.map { (key: $0.key, items: $0.value) }
                .sorted { a, b in
                    let la = a.key.isEmpty ? String(localized: "Other") : StrengthDisplay.muscle(a.key)
                    let lb = b.key.isEmpty ? String(localized: "Other") : StrengthDisplay.muscle(b.key)
                    return la.localizedCaseInsensitiveCompare(lb) == .orderedAscending
                }
        }()
        return LazyVStack(alignment: .leading, spacing: 0) {
            if loaded && rows.isEmpty {
                Text("No exercises match your filters.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, CenitMetrics.sectionGapCompact)
            }
            // «Con historial tuyo» — the exercises you've logged, first, each with its best mark + sparkline.
            if !mine.isEmpty {
                InstrumentoSectionBand("With your history")
                    .padding(.top, CenitMetrics.space1).padding(.bottom, CenitMetrics.space2)
                ForEach(mine) { ex in
                    exerciseRow(ex, showsHistory: true)
                    if ex.id != mine.last?.id { Divider().overlay(theme.hairline.opacity(StrandOpacity.muted)) }
                }
            }
            // «De la biblioteca» — catalog remainder, one overline section per primary muscle.
            if !rest.isEmpty {
                ForEach(Array(libraryGroups.enumerated()), id: \.element.key) { index, group in
                    InstrumentoSectionBand("\(group.key.isEmpty ? String(localized: "Other") : StrengthDisplay.muscle(group.key)) · \(String(localized: "FROM THE LIBRARY"))")
                        .padding(.top, index == 0 && mine.isEmpty ? CenitMetrics.space1 : CenitMetrics.sectionGapCompact)
                        .padding(.bottom, CenitMetrics.space2)
                    ForEach(group.items) { ex in
                        exerciseRow(ex, showsHistory: false)
                        if ex.id != group.items.last?.id {
                            Divider().overlay(theme.hairline.opacity(StrandOpacity.muted))
                        }
                    }
                }
            }
        }
    }

    private func exerciseRow(_ ex: Exercise, showsHistory: Bool) -> some View {
        Button {
            detail = ex
        } label: {
            HStack(spacing: CenitMetrics.gap) {
                // Handoff: the thumbnail carries a 2px frame in the exercise's movement-family hue.
                ExerciseThumbView(exercise: ex, side: 52)   // handoff: 52px thumb · cached GIF still or paper placeholder (FER-790)
                    .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                        .strokeBorder(familyTint(ex), lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(StrengthDisplay.name(ex)).font(StrandFont.body).foregroundStyle(theme.ink)
                        .multilineTextAlignment(.leading)
                    Text(StrengthDisplay.subtitle(ex)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                // No sparkline here (FER-951): with long catalog names it starved the title into a
                // 4-line wrap. The record datum carries the story; the full trend lives in the detail.
                // Handoff: the best mark as the right-hand datum, in the family hue («82,5 kg / tu récord»).
                if showsHistory, let kg = bestKg[ex.id] {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(StrengthDisplay.weight(kg, system: system))
                            .font(InstrumentoType.grotesk(15, weight: .bold)).foregroundStyle(familyTint(ex))
                        Text("your record")
                            .font(InstrumentoType.groteskOverline).tracking(InstrumentoType.groteskOverlineTracking)
                            .foregroundStyle(theme.inkTertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
                trailingAccessory(ex)
            }
            .padding(.vertical, CenitMetrics.rowVPad).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The movement-family hue for an exercise (push=ember · pull=teal · legs=indigo), from its
    /// first primary muscle — same mapping as the history screen's muscle bars.
    private func familyTint(_ ex: Exercise) -> Color {
        let m = (ex.primaryMuscles.first ?? "").lowercased()
        if ["chest", "shoulders", "triceps"].contains(where: m.contains) { return theme.dataStrain }
        if ["lats", "back", "biceps", "traps", "forearms"].contains(where: m.contains) { return theme.dataHrv }
        if ["quadriceps", "hamstrings", "glutes", "calves", "abductors", "adductors"].contains(where: m.contains) { return theme.dataSleep }
        return theme.dataStrain
    }

    /// The trailing control: an «Add» affordance in ADD mode (a check when picked), a chevron in BROWSE.
    /// In ADD mode this is its own button — the row itself only opens the detail sheet.
    @ViewBuilder
    private func trailingAccessory(_ ex: Exercise) -> some View {
        if addMode {
            Button {
                toggle(ex)
            } label: {
                if selected.contains(ex.id) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 21)).foregroundStyle(theme.ink)  // token-exempt: glifo 21pt fuera de banda lead
                } else {
                    Text("Add").font(StrandFont.subhead).foregroundStyle(theme.ink)
                        .padding(.horizontal, CenitMetrics.gap).padding(.vertical, CenitMetrics.space1)
                        .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                .foregroundStyle(theme.inkTertiary)
        }
    }

    private var createRow: some View {
        Button { showCreate = true } label: {
            HStack(spacing: CenitMetrics.space2) {
                StrandIcon.add.image.font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(theme.dataStrain)   // handoff: the ＋ carries the ember accent
                Text("Create your own exercise").font(StrandFont.body).foregroundStyle(theme.ink)
            }
            .padding(.vertical, CenitMetrics.gap).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add bar (ADD mode)

    private var addBar: some View {
        Button { onAdd?(exercises.filter { selected.contains($0.id) }); dismiss() } label: {
            // A ternary with an interpolated branch resolves to plain `String`, not `LocalizedStringKey` —
            // wrap each branch in `String(localized:)` so both localize (and the count uses the catalog's
            // es-MX plural template) instead of silently falling back to English.
            Text(selected.isEmpty
                 ? String(localized: "Select exercises")
                 : String(localized: "Add \(selected.count) exercise(s)"))
                .font(StrandFont.headline).foregroundStyle(selected.isEmpty ? theme.inkTertiary : theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, CenitMetrics.gap)
                .background(theme.surface, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(selected.isEmpty)
        .padding(.horizontal, CenitMetrics.screenPadding).padding(.bottom, CenitMetrics.space2)
        .background(theme.paper.opacity(0.96).ignoresSafeArea(edges: .bottom))  // token-exempt: casi-opaco fuera de banda
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

    /// «Con historial tuyo» (1f): the exercises the user has ever logged, plus each one's best weight.
    /// `recentWorkSets(sinceTs: 0)` gives the id set cheaply; the per-exercise history is fetched only
    /// for that (small) set, so a huge catalog stays fast.
    private func loadHistory() async {
        let events = await repo.recentWorkSets(sinceTs: 0)
        let ids = Set(events.map(\.exerciseId))
        historyIds = ids
        var best: [String: Double] = [:]
        for id in ids {
            let hist = await repo.exerciseHistory(exerciseId: id)   // oldest→newest (startTs, weightKg, reps)
            guard !hist.isEmpty else { continue }
            best[id] = hist.map(\.weightKg).max()
        }
        bestKg = best
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
            && (typeFilter == nil || ex.type.rawValue == typeFilter!)
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
    @State private var showMusclePicker = false
    @State private var showEquipPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 2) {
                    // The sheet speaks the same Grotesk voice as the Library header that opens it.
                    Text("Library").groteskSheetTitle().textCase(.uppercase).foregroundStyle(theme.inkTertiary)
                    Text("New exercise")
                        .font(InstrumentoType.groteskHeroNumeral(28)).tracking(InstrumentoType.groteskHeroTrackingScaled(28))
                        .foregroundStyle(theme.ink)
                }

                VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                    Text("Name").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    TextField("e.g. Svend press", text: $name)
                        .font(StrandFont.body).foregroundStyle(theme.ink)
                        .padding(.horizontal, CenitMetrics.gap).padding(.vertical, CenitMetrics.rowVPad)
                        // Same skin as the Library's search field — one text-field look per flow.
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                            .strokeBorder(theme.hairlineStrong, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 2) {
                    pickerRow("Primary muscle", isPresented: $showMusclePicker, selection: $muscle, options: muscles, placeholder: String(localized: "Pick a muscle"), label: StrengthDisplay.muscle)
                    Divider().overlay(theme.hairline)
                    pickerRow("Equipment", isPresented: $showEquipPicker, selection: $equip, options: equipment, placeholder: String(localized: "Pick equipment"), label: StrengthDisplay.equipment)
                }

                VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                    Text("Record type").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    ForEach(ExerciseType.allCases, id: \.self) { t in typeOption(t) }
                }

                Button { create() } label: {
                    Text("Create exercise").font(StrandFont.headline)
                        .foregroundStyle(canCreate ? theme.ink : theme.inkTertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, CenitMetrics.gap)
                        .background(theme.surface, in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain).disabled(!canCreate)
            }
            .padding(.top, CenitMetrics.screenTop).padding(.horizontal, CenitMetrics.screenPadding).padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
    }

    private func pickerRow(_ title: LocalizedStringKey, isPresented: Binding<Bool>, selection: Binding<String>,
                           options: [String], placeholder: String,
                           label: @escaping (String) -> String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(StrandFont.body).foregroundStyle(theme.ink).frame(maxWidth: .infinity, alignment: .leading)
            Button { isPresented.wrappedValue = true } label: {
                HStack(spacing: CenitMetrics.space1) {
                    Text(selection.wrappedValue.isEmpty ? placeholder : label(selection.wrappedValue))
                        .font(StrandFont.body).foregroundStyle(selection.wrappedValue.isEmpty ? theme.inkTertiary : theme.inkSecondary)
                    StrandIcon.down.image.font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                }
            }
            .buttonStyle(.plain)
            .paperMenu(isPresented: isPresented, items: options.map { opt in
                PaperMenuItem(label(opt), systemImage: selection.wrappedValue == opt ? "checkmark" : nil) {
                    selection.wrappedValue = opt
                }
            })
        }
        .frame(minHeight: 44)   // HIG minimum touch target
    }

    private func typeOption(_ t: ExerciseType) -> some View {
        Button { type = t } label: {
            HStack(spacing: CenitMetrics.gap) {
                Image(systemName: StrengthDisplay.typeIcon(t)).font(StrandFont.glyph(.lead))
                    .foregroundStyle(type == t ? theme.ink : theme.inkTertiary).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(StrengthDisplay.typeLabel(t)).font(StrandFont.body).foregroundStyle(theme.ink)
                    Text(StrengthDisplay.typeDetail(t)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                if type == t { StrandIcon.confirm.image.font(StrandFont.glyph(.inline, weight: .semibold)).foregroundStyle(theme.ink) }
            }
            .padding(.horizontal, CenitMetrics.gap).padding(.vertical, CenitMetrics.rowVPad).contentShape(Rectangle())
            .background(type == t ? theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))  // token-exempt: fondo condicional
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                .strokeBorder(type == t ? theme.ink : theme.hairline, lineWidth: type == t ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func create() {
        let ex = Exercise(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces),
                          type: type, equipment: equip.isEmpty ? nil : equip,
                          primaryMuscles: muscle.isEmpty ? [] : [muscle], secondaryMuscles: [], instructions: [])
        onCreate(ex); dismiss()
    }
}
#endif
