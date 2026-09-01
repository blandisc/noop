#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import Inject   // recarga en caliente (dev-only, inerte en Release)

// ExerciseLibraryScreen.swift — browse the on-device exercise catalog (FER-346). Two modes from one
// view: BROWSE (opened from the Train hub — tap an exercise to open its detail) and ADD (presented by
// the routine builder with `onAdd` — multi-select, then "Add N" hands the picks back). Search + muscle
// and equipment filters narrow a long catalog; «Create exercise» adds a user-defined one. «Báscula de
// papel»: ink on paper, no datum here so no color; selection is quiet ink chrome.

// MARK: - Touch target (FER-121)
// The same principle as `PaperStepper.hitTarget` (FER-947, StrandDesign): padding + contentShape +
// negative padding cancel out in layout, so the visible control never changes size or pushes a
// neighbor — only the area that answers a tap grows to 44pt (HIG).
private extension View {
    /// Grows the tap target ONLY vertically, so a chip sitting beside others in the same row doesn't
    /// invade its neighbor's hit area.
    func verticalHitTarget(visible: CGFloat) -> some View {
        let pad = max(0, (EntrenarMetrics.row - visible) / 2)
        return padding(.vertical, pad).contentShape(Rectangle()).padding(.vertical, -pad)
    }
}

struct ExerciseLibraryScreen: View {
    /// M8 (decisión Fer): el flujo de CREACIÓN inyecta su contexto — el título dice «Nueva rutina»
    /// en vez del genérico «Agregar a rutina» (todavía no existe rutina a la cual agregar).
    var createFlow: Bool = false
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
    /// Ids of user-created exercises — the only rows the library may edit (FER-995).
    @State private var customIds: Set<String> = []
    /// The exercise being completed/edited in the sheet.
    @State private var editingExercise: Exercise? = nil
    @State private var filtered: [Exercise] = []
    @State private var mine: [Exercise] = []
    @State private var rest: [Exercise] = []
    @State private var libraryGroups: [(key: String, items: [Exercise])] = []
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

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
        // FER-198 (Ola 2, épico FER-195): fondo de vidrio El Eje (Ola 1, FER-197) — esta pantalla
        // no trae `NavigationStack` propio en ninguno de sus call sites (push/destination puros);
        // su kicker («Biblioteca · N ejercicios») se queda tal cual, no gana control de salida.
        .entrenarHojaFondo(tono: .neutro)
        .pantallaFondo()
        .safeAreaInset(edge: .bottom) { if addMode { addBar } }
        .task { await reload() }
        .onChange(of: search) {
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                rebuildFiltered()
            }
        }
        .onChange(of: muscle) { rebuildFiltered() }
        .onChange(of: equipment) { rebuildFiltered() }
        .onChange(of: typeFilter) { rebuildFiltered() }
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
            CreateExerciseSheet(catalog: exercises) { ex in
                Task { try? await repo.saveCustomExercise(ex); await reload() }
            }
            .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        // FER-995: completing an exercise created before the muscle was required — the same form,
        // pre-filled, keeping the id so the save edits in place.
        .sheet(item: $editingExercise) { ex in
            CreateExerciseSheet(catalog: exercises, editing: ex) { updated in
                Task { try? await repo.saveCustomExercise(updated); await reload() }
            }
            .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .enableInjection()
    }

    // MARK: - Header

    private var header: some View {
        // Handoff V10 (FER-139): a single kicker line — «Biblioteca · N ejercicios» — not the older
        // count-as-hero-title pattern (FER-942). The count reflects the REAL loaded catalog (never a
        // made-up figure); until it loads, the line falls back to the section name alone.
        Group {
            if loaded {
                Text("Library · \(exercises.count) exercises")
            } else {
                Text(createFlow ? "New routine · pick exercises" : (addMode ? "Add to routine" : "Library"))
            }
        }
        .entrenarCabeceraKicker().foregroundStyle(theme.inkTertiary)
    }

    private var searchField: some View {
        HStack(spacing: CenitMetrics.space2) {
            StrandIcon.search.image.font(StrandFont.glyph(.inline)).foregroundStyle(theme.inkTertiary)
            TextField("Search exercise", text: $search)
                .font(StrandFont.body).foregroundStyle(theme.ink)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            if !search.isEmpty {
                Button { search = "" } label: {
                    StrandIcon.close.image.foregroundStyle(theme.inkTertiary)
                }.buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, CenitMetrics.gap).padding(.vertical, CenitMetrics.rowVPad)
        // Campo de búsqueda opaco (anti vidrio-sobre-vidrio) dentro de la hoja El Eje.
        .liquidGlass(.superficieSolida)
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
        return OutlineCapsule(theme: theme, size: .md, filled: active != nil,
                              action: { isPresented.wrappedValue = true }) {
            HStack(spacing: CenitMetrics.space1) {
                Text(active.map(label) ?? title)
                    .font(StrandFont.subhead)
                    .foregroundStyle(active == nil ? theme.ink : theme.paper)
                StrandIcon.down.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(active == nil ? theme.inkTertiary : theme.paper)
            }
        }
        // FER-121: el chip visible mide ~28pt de alto; el toque real crece a 44 (HIG) SOLO en
        // vertical (mismo truco que `PaperStepper.hitTarget`, FER-947 en StrandDesign) para no
        // invadir al chip vecino del mismo renglón.
        .verticalHitTarget(visible: 28)
        .paperMenu(isPresented: isPresented, items: rows)
    }

    // MARK: - List

    private var exerciseList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if loaded && filtered.isEmpty {
                Text("No exercises match your filters.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, CenitMetrics.sectionGapCompact)
            }
            // «Con historial tuyo» — the exercises you've logged, first, each with its best mark + sparkline.
            if !mine.isEmpty {
                InstrumentoSectionBand("With your history") {
                    Text("Best mark").font(InstrumentoType.grotesk(11, weight: .semibold)).tracking(1.4)
                        .textCase(.uppercase).foregroundStyle(theme.inkTertiary)
                }
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

    /// A user-created exercise with no primary muscle: it doesn't count toward the muscle map or the
    /// weekly volume, so the library offers to complete it instead of opening its (empty) detail (FER-995).
    private func needsMuscle(_ ex: Exercise) -> Bool {
        customIds.contains(ex.id) && ex.primaryMuscles.isEmpty
    }

    /// Two real actions live on this row in ADD mode — open the detail vs. toggle the pick — so it can't
    /// be one `Button` whose label nests a second real `Button` inside it. That's exactly what shipped
    /// before FER-121: a `Button`-inside-a-`Button`, and VoiceOver couldn't reach the trailing toggle.
    /// In BROWSE there's only one action, so the whole row stays one real `Button`, as before.
    private func exerciseRow(_ ex: Exercise, showsHistory: Bool) -> some View {
        Group {
            if addMode {
                // The identity content becomes its own tappable element via `.onTapGesture` + an
                // explicit `.isButton` trait — a sibling of the trailing toggle's real `Button`, not a
                // container around it. VoiceOver now reaches "open detail" and "add/remove" one after
                // the other, in visual order, instead of one swallowing the other.
                HStack(spacing: CenitMetrics.gap) {
                    rowIdentity(ex, showsHistory: showsHistory)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .onTapGesture { openDetail(ex) }
                    trailingAccessory(ex)
                }
                .padding(.vertical, CenitMetrics.rowVPad)
            } else {
                Button {
                    openDetail(ex)
                } label: {
                    HStack(spacing: CenitMetrics.gap) {
                        rowIdentity(ex, showsHistory: showsHistory)
                        trailingAccessory(ex)
                    }
                    .padding(.vertical, CenitMetrics.rowVPad).contentShape(Rectangle())
                }
                .buttonStyle(EntrenarPressStyle())
            }
        }
    }

    /// Opens the row's detail — or, for a custom exercise still missing its muscle, the completion form
    /// instead (FER-995). Shared by both `exerciseRow` branches so BROWSE and ADD agree on what a tap does.
    private func openDetail(_ ex: Exercise) {
        if needsMuscle(ex) { editingExercise = ex } else { detail = ex }
    }

    /// The row's identity: thumbnail + name/subtitle + (in "With your history") the best-mark datum.
    /// In BROWSE it's wrapped in the row's own `Button`; in ADD mode it's a tappable sibling of the
    /// trailing toggle `Button` (see `exerciseRow`) — never a container around another real `Button`.
    private func rowIdentity(_ ex: Exercise, showsHistory: Bool) -> some View {
        HStack(spacing: CenitMetrics.gap) {
            // Handoff: the thumbnail carries a 2px frame in the exercise's movement-family hue.
            ExerciseThumbView(exercise: ex, side: 52)   // handoff: 52px thumb · cached GIF still or paper placeholder (FER-790)
                .overlay(RoundedRectangle(cornerRadius: ExerciseThumbnail.tileCornerRadius(side: 52), style: .continuous)
                    .strokeBorder(familyTint(ex), lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text(StrengthDisplay.name(ex)).font(StrandFont.body).foregroundStyle(theme.ink)
                    .multilineTextAlignment(.leading)
                if needsMuscle(ex) {
                    Text("No muscle · tap to complete")
                        .font(StrandFont.caption).foregroundStyle(theme.dataStrain)
                } else {
                    Text(StrengthDisplay.subtitle(ex)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
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
        }
    }

    /// The movement-family hue for an exercise (push=ember · pull=teal · legs=indigo), from its
    /// first primary muscle — same mapping as the history screen's muscle bars.
    private func familyTint(_ ex: Exercise) -> Color {
        // r21: mapeo PROMOVIDO a StrandDesign (`movementFamilyTint`) — una sola fuente de verdad.
        theme.movementFamilyTint(primaryMuscles: [ex.primaryMuscles.first ?? ""])
    }

    /// The trailing control: an «Add» affordance in ADD mode (a check when picked), a chevron in BROWSE.
    /// In ADD mode this is its own real `Button` — a sibling of the row's identity, never nested inside
    /// another `Button` (FER-121; see `exerciseRow`).
    @ViewBuilder
    private func trailingAccessory(_ ex: Exercise) -> some View {
        if addMode {
            Button {
                toggle(ex)
            } label: {
                // Ancho FIJO y alineado a la derecha: la cápsula «Agregar» y el círculo de la palomita
                // tienen anchos muy distintos, así que al alternar SwiftUI interpolaba entre los dos y la
                // palomita se veía deslizarse hacia la izquierda (bug Fer 2026-07-18). Con el carril fijo,
                // el control cambia en su sitio.
                Group {
                    if selected.contains(ex.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 21)).foregroundStyle(theme.ink)  // token-exempt: glifo 21pt fuera de banda lead
                    } else {
                        // «Agregar» es un BOTÓN: va en Grotesk, no en la SF del cuerpo de texto
                        // (DESIGN.md §«Space Grotesk toma … y botones»).
                        Text("Add").font(InstrumentoType.grotesk(13, weight: .semibold)).foregroundStyle(theme.ink)
                            .padding(.horizontal, CenitMetrics.gap).padding(.vertical, CenitMetrics.space1)
                            .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    }
                }
                // FER-121: ancho fijo de 78 (sin cambio) + alto a `EntrenarMetrics.row` (44, HIG). La
                // fila ya mide 52+ pt por la miniatura, así que crecer este alto no mueve nada — el
                // carril visible queda centrado igual, solo agranda el toque real del glifo/cápsula.
                .frame(width: 78, height: EntrenarMetrics.row)
            }
            .buttonStyle(EntrenarPressStyle())
            .contentShape(Rectangle())
            .animation(nil, value: selected)   // sin interpolación de layout: el cambio es instantáneo
            .accessibilityLabel(Text(selected.contains(ex.id) ? "Remove from selection" : "Add to selection"))
        } else {
            StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                .foregroundStyle(theme.inkTertiary)
        }
    }

    // Handoff V10 (FER-139): a paper pill, bottom-right, 44pt tall — not a full-width list row.
    private var createRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button { showCreate = true } label: {
                HStack(spacing: CenitMetrics.space2) {
                    StrandIcon.add.image.font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(theme.dataStrain)   // handoff: the ＋ carries the ember accent
                    Text("Create exercise").font(StrandFont.body).foregroundStyle(theme.ink)
                }
                .padding(.horizontal, CenitMetrics.gap)
                .frame(height: EntrenarMetrics.row)
                .liquidGlass(.pastillaSolida)
                .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(EntrenarPressStyle())
        }
        .padding(.top, CenitMetrics.space1)
    }

    // MARK: - Add bar (ADD mode)

    /// El botón dice a dónde va, no qué hace con la lista. En el flujo de CREACIÓN «Agregar 3 ejercicios»
    /// no se lee como la salida del flujo —suena a agregar a algo que ya existe— y la pantalla parecía
    /// no tener continuación (bug Fer 2026-07-18). Ahí nombra el resultado: «Crear rutina con 3».
    private var addBarLabel: String {
        if selected.isEmpty {
            return createFlow ? String(localized: "Pick at least one exercise")
                              : String(localized: "Select exercises")
        }
        return createFlow ? String(localized: "Create routine with \(selected.count)")
                          : String(localized: "Add \(selected.count) exercise(s)")
    }

    private var addBar: some View {
        // Mismo componente que «＋ Nueva rutina» del hub (decisión Fer 2026-07-19): agregar a una lista
        // se ve igual en toda la app. `prominent` solo en el flujo de CREACIÓN, donde el botón es la
        // salida del flujo y no una acción más. `addBarLabel` ya resuelve el copy y los plurales.
        InstrumentoAddButton(theme: theme,
                             label: addBarLabel,
                             prominent: createFlow,
                             disabled: selected.isEmpty) {
            onAdd?(exercises.filter { selected.contains($0.id) })
            dismiss()
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        // Libra el dock, que se queda visible (decisión Fer): el `safeAreaInset` inferior comparte carril
        // con la barra de pestañas y el botón quedaba medio tapado. Sin banda de papel detrás — la lámina
        // casi-opaca se desbordaba por abajo y se veía como un borde suelto; ahora solo flota la cápsula,
        // y el inset ya reserva el alto para que la lista no se le meta debajo.
        .padding(.bottom, 68)   // token-exempt: alto del dock + respiro
    }

    // MARK: - Data

    private func reload() async {
        exercises = await repo.allExercises()
        customIds = await repo.customExerciseIds()
        // Filter options are invariant between reloads — derive them once here, not per body pass.
        muscleOptions = Set(exercises.flatMap { $0.primaryMuscles }).sorted()
        equipmentOptions = Set(exercises.compactMap { $0.equipment }).sorted()
        await loadHistory()
        loaded = true
        rebuildFiltered()
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
        rebuildFiltered()
    }

    private func toggle(_ ex: Exercise) {
        if selected.contains(ex.id) { selected.remove(ex.id) } else { selected.insert(ex.id) }
    }

    private func rebuildFiltered() {
        let rows = exercises.filter { ex in
            (search.isEmpty || ex.name.localizedCaseInsensitiveContains(search)
                || (ex.nameES?.localizedCaseInsensitiveContains(search) ?? false))   // search both languages (FER-501)
            && (muscle == nil || ex.primaryMuscles.contains(muscle!) || ex.secondaryMuscles.contains(muscle!))
            && (equipment == nil || ex.equipment == equipment)
            && (typeFilter == nil || ex.type.rawValue == typeFilter!)
        }
        filtered = rows
        mine = rows.filter { historyIds.contains($0.id) }
        rest = rows.filter { !historyIds.contains($0.id) }
        var dict: [String: [Exercise]] = [:]
        for ex in rest {
            dict[ex.primaryMuscles.first ?? "", default: []].append(ex)
        }
        libraryGroups = dict.map { (key: $0.key, items: $0.value) }
            .sorted { a, b in
                let la = a.key.isEmpty ? String(localized: "Other") : StrengthDisplay.muscle(a.key)
                let lb = b.key.isEmpty ? String(localized: "Other") : StrengthDisplay.muscle(b.key)
                return la.localizedCaseInsensitiveCompare(lb) == .orderedAscending
            }
    }
}

// MARK: - Create exercise (sheet)

/// «Crear ejercicio propio»: name + primary muscle + equipment + record type. Builds a user-defined
/// `Exercise` and hands it back; the catalog stays read-only.
///
/// Shared by three callers (FER-995): the library's «create your own», the import flow's «create new»
/// (pre-filled with the plan's name and a muscle proposed by `MuscleInference`), and the repair path
/// that completes an exercise created before this existed. When `editing` is non-nil the sheet keeps
/// that exercise's id, so `saveCustomExercise`'s upsert edits in place instead of adding a duplicate.
///
/// The primary muscle is **required**: an exercise without one is invisible to the muscle map, the
/// weekly volume and `RoutineClassifier`, and that was silent data loss (FER-995).
struct CreateExerciseSheet: View {
    /// Non-nil → edit mode: keeps this exercise's id and pre-fills every field from it.
    var editing: Exercise? = nil
    let onCreate: (Exercise) -> Void
    /// The picker vocabularies, derived once from the catalog the caller passes — so both flows offer
    /// exactly the same options without each one re-deriving them.
    private let muscles: [String]
    private let equipment: [String]
    /// The muscle this sheet proposed from the name. Derived here rather than passed in, so proposing
    /// is the sheet's own behaviour and no caller can forget it.
    private let proposedMuscle: String

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var muscle: String
    @State private var equip: String
    @State private var type: ExerciseType
    @State private var showMusclePicker = false
    @State private var showEquipPicker = false

    /// `initialName` / `initialType` seed a *fresh* exercise (the import flow passes the plan's name and
    /// the type it declared); `editing` overrides both.
    init(catalog: [Exercise], editing: Exercise? = nil,
         initialName: String = "", initialType: ExerciseType = .weightReps,
         onCreate: @escaping (Exercise) -> Void) {
        self.muscles = Set(catalog.flatMap { $0.primaryMuscles }).sorted()
        self.equipment = Set(catalog.compactMap { $0.equipment }).sorted()
        self.editing = editing
        self.onCreate = onCreate
        let seedName = editing?.name ?? initialName
        let proposed = MuscleInference.primaryMuscle(forName: seedName) ?? ""
        self.proposedMuscle = proposed
        _name = State(initialValue: seedName)
        _muscle = State(initialValue: editing?.primaryMuscles.first ?? proposed)
        _equip = State(initialValue: editing?.equipment ?? "")
        _type = State(initialValue: editing?.type ?? initialType)
    }

    private var isEditing: Bool { editing != nil }
    /// True while the muscle shown is still the one proposed from the name — the sheet says so, so a
    /// guess is never passed off as a fact. An exercise that already had a muscle isn't a proposal.
    private var showsProposedHint: Bool {
        !proposedMuscle.isEmpty && muscle == proposedMuscle && editing?.primaryMuscles.first == nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 2) {
                    // The sheet speaks the same Grotesk voice as the Library header that opens it.
                    Text("Library").groteskSheetTitle().textCase(.uppercase).foregroundStyle(theme.inkTertiary)
                    Text(isEditing ? "Edit exercise" : "New exercise")
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
                    // The muscle is what makes the exercise count: say why it's being asked, and never
                    // let a proposal pass as a fact (FER-995).
                    Text(showsProposedHint
                         ? "Suggested from the name · change it if it's wrong."
                         : "Without it the exercise won't count toward your muscle map or weekly volume.")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, CenitMetrics.space1)
                    Divider().overlay(theme.hairline)
                    pickerRow("Equipment", isPresented: $showEquipPicker, selection: $equip, options: equipment, placeholder: String(localized: "Pick equipment"), label: StrengthDisplay.equipment)
                }

                VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                    Text("Record type").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    ForEach(ExerciseType.allCases, id: \.self) { t in typeOption(t) }
                }

                Button { create() } label: {
                    Text(isEditing ? "Save changes" : "Create exercise")
                        .font(InstrumentoType.grotesk(15, weight: .bold))
                        .foregroundStyle(canCreate ? theme.ink : theme.inkTertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, CenitMetrics.gap)
                        .liquidGlass(.pastillaSolida)
                        .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(EntrenarPressStyle()).disabled(!canCreate)
            }
            .padding(.top, CenitMetrics.screenTop).padding(.horizontal, CenitMetrics.screenPadding).padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-198 (Ola 2): fondo de vidrio El Eje — se CONSERVA el chrome actual (título Grotesk a
        // mano + el CTA grande de guardar abajo); esta hoja no tiene botón «Cancelar» hoy (solo
        // swipe-dismiss + el CTA de guardar) y NO se le agrega uno — el menú de presentación de
        // `EntrenarHojaFondo.swift` sugiere `EntrenarHojaCabecera(.cancelar(_:))` aquí, pero eso
        // AÑADIRÍA un control de salida que hoy no existe (violaría la regla de cero cambio de
        // comportamiento de la Ola 2) — se ignora deliberadamente y se flagea en el reporte.
        .entrenarHojaFondo(tono: .neutro)
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
            .buttonStyle(EntrenarPressStyle())
            .paperMenu(isPresented: isPresented, items: options.map { opt in
                PaperMenuItem(label(opt), systemImage: selection.wrappedValue == opt ? "checkmark" : nil) {
                    selection.wrappedValue = opt
                }
            })
        }
        .frame(minHeight: EntrenarMetrics.row)   // HIG minimum touch target (44)
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
        .buttonStyle(EntrenarPressStyle())
    }

    /// The muscle is required alongside the name (FER-995): shipping an exercise with no primary muscle
    /// is what made imported exercises invisible to the analysis in the first place.
    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !muscle.isEmpty
    }

    private func create() {
        // Edit mode reuses the id so the store's upsert updates in place; anything else the exercise
        // already carried (instructions, artwork) is preserved rather than blanked by this form.
        let base = editing
        let ex = Exercise(id: base?.id ?? UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces),
                          type: type, equipment: equip.isEmpty ? nil : equip,
                          primaryMuscles: [muscle], secondaryMuscles: base?.secondaryMuscles ?? [],
                          instructions: base?.instructions ?? [])
        onCreate(ex); dismiss()
    }
}
#endif
