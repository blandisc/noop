#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import Inject   // recarga en caliente (dev-only, inerte en Release)

// ExerciseLibraryScreen.swift — browse the on-device exercise catalog (FER-346). Two modes from one
// view: BROWSE (opened from the Train hub — tap an exercise to open its detail) and ADD (presented by
// the routine builder with `onAdd` — multi-select, then "Add N" hands the picks back). Search + muscle
// and equipment filters narrow a long catalog; «Create exercise» adds a user-defined one. FER-289:
// piel Liquid Glass · El Eje (`LiquidCampoBusqueda` · `EntrenarFilaEjercicio` · `.superficieSolida`).

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
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                header
                searchField
                filterChips
                exerciseList
                createRow
            }
            .padding(.top, CenitMetrics.screenTop)
            .padding(.horizontal, LiquidSpace.s600)
            // The safeAreaInset already carves out the addBar's height — no magic 88.
            .padding(.bottom, LiquidSpace.s600)
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
                    .toolbarBackground(LiquidColor.papelTarjeta, for: .navigationBar)
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
        kickerText
            .liquidKicker()
            .foregroundStyle(LiquidColor.tinta700)
    }

    private var kickerText: Text {
        if loaded {
            return Text("Library · \(exercises.count) exercises")
        }
        return Text(createFlow ? "New routine · pick exercises" : (addMode ? "Add to routine" : "Library"))
    }

    private var searchField: some View {
        LiquidCampoBusqueda(
            placeholder: String(localized: "Search exercise"),
            text: $search,
            a11yLimpiar: String(localized: "Clear search"))
    }

    // MARK: - Filters

    private var filterChips: some View {
        HStack(spacing: LiquidSpace.s200) {
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
        var rows: [LiquidMenuItem] = [
            LiquidMenuItem(String(localized: "All"), systemImage: active == nil ? "checkmark" : nil) {
                selection.wrappedValue = nil
            }
        ]
        rows += options.map { opt in
            LiquidMenuItem(label(opt), systemImage: active == opt ? "checkmark" : nil) {
                selection.wrappedValue = opt
            }
        }
        return OutlineCapsule(theme: theme, size: .md, filled: active != nil,
                              action: { isPresented.wrappedValue = true }) {
            HStack(spacing: LiquidSpace.s200) {
                Text(active.map(label) ?? title)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(active == nil ? LiquidColor.tinta900 : LiquidColor.papelTarjeta)
                LiquidIcon(.chevron, size: 12,
                           color: active == nil ? LiquidColor.tinta500 : LiquidColor.papelTarjeta)
                    .rotationEffect(.degrees(90))
            }
        }
        // FER-121: el chip visible mide ~28pt de alto; el toque real crece a 44 (HIG) SOLO en
        // vertical (mismo truco que `PaperStepper.hitTarget`, FER-947 en StrandDesign) para no
        // invadir al chip vecino del mismo renglón.
        .verticalHitTarget(visible: 28)
        .liquidMenu(isPresented: isPresented, items: rows)
    }

    // MARK: - List
    //
    // Un contenedor `.superficieSolida` POR sección (historial + cada grupo muscular), no por
    // fila ni uno solo envolviendo toda la lista: el `LiquidSectionHeader` queda fuera del
    // papel (mismo patrón que `LiquidListCard` + encabezado), y cada bloque visual es UNA
    // tarjeta de vidrio con pad V `s050` / H 14.

    private var exerciseList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if loaded && filtered.isEmpty {
                Text("No exercises match your filters.")
                    .font(LiquidType.cuerpoBanner)
                    .foregroundStyle(LiquidColor.tinta700)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, LiquidSpace.seccionAire)
            }
            // «Con historial tuyo» — the exercises you've logged, first, each with its best mark.
            if !mine.isEmpty {
                LiquidSectionHeader("With your history") {
                    Text("Best mark").liquidLabel().foregroundStyle(LiquidColor.tinta500)
                }
                sectionCard {
                    ForEach(Array(mine.enumerated()), id: \.element.id) { _, ex in
                        exerciseRow(ex, showsHistory: true,
                                    divider: ex.id != mine.last?.id)
                    }
                }
            }
            // «De la biblioteca» — catalog remainder, one overline section per primary muscle.
            if !rest.isEmpty {
                ForEach(Array(libraryGroups.enumerated()), id: \.element.key) { _, group in
                    LiquidSectionHeader("\(group.key.isEmpty ? String(localized: "Other") : StrengthDisplay.muscle(group.key)) · \(String(localized: "FROM THE LIBRARY"))")
                    sectionCard {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { _, ex in
                            exerciseRow(ex, showsHistory: false,
                                        divider: ex.id != group.items.last?.id)
                        }
                    }
                }
            }
        }
        .padding(.top, LiquidSpace.seccionAire)
    }

    /// Papel opaco de una sección de filas (pad 2/14 · radio tarjeta vía la receta).
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.vertical, LiquidSpace.s050)
            .padding(.horizontal, 14)
            .liquidGlass(.superficieSolida)
    }

    /// A user-created exercise with no primary muscle: it doesn't count toward the muscle map or the
    /// weekly volume, so the library offers to complete it instead of opening its (empty) detail (FER-995).
    private func needsMuscle(_ ex: Exercise) -> Bool {
        customIds.contains(ex.id) && ex.primaryMuscles.isEmpty
    }

    /// Fila vía `EntrenarFilaEjercicio`. En ADD: dos botones hermanos (detalle + toggle) —
    /// FER-121. En BROWSE: un solo Button con chevron.
    private func exerciseRow(_ ex: Exercise, showsHistory: Bool, divider: Bool) -> some View {
        let incomplete = needsMuscle(ex)
        let family: EntrenarFamily? = {
            guard let primary = ex.primaryMuscles.first, !primary.isEmpty else { return nil }
            return theme.movementFamily(primaryMuscles: [primary])
        }()
        let dato: (valor: String, rotulo: String)? = {
            guard showsHistory, let kg = bestKg[ex.id] else { return nil }
            return (valor: StrengthDisplay.weight(kg, system: system),
                    rotulo: String(localized: "your record"))
        }()
        return EntrenarFilaEjercicio(
            family: family,
            nombre: StrengthDisplay.name(ex),
            meta: StrengthDisplay.subtitle(ex),
            dato: dato,
            afordancia: addMode
                ? .agregar(seleccionado: selected.contains(ex.id))
                : .chevron,
            aviso: incomplete ? String(localized: "No muscle · tap to complete") : nil,
            divider: divider,
            agregarLabel: String(localized: "Add"),
            a11yAgregar: String(localized: "Add to selection"),
            a11yQuitar: String(localized: "Remove from selection"),
            action: { openDetail(ex) },
            onToggle: addMode ? { toggle(ex) } : nil
        ) {
            ExerciseThumbView(exercise: ex, side: 52)
        }
    }

    /// Opens the row's detail — or, for a custom exercise still missing its muscle, the completion form
    /// instead (FER-995). Shared by both modes so BROWSE and ADD agree on what a tap does.
    private func openDetail(_ ex: Exercise) {
        if needsMuscle(ex) { editingExercise = ex } else { detail = ex }
    }

    // Handoff V10 (FER-139) + FER-289: pastilla sólida bottom-right, sin ＋ ámbar.
    private var createRow: some View {
        HStack {
            Spacer(minLength: 0)
            LiquidGlassButton(String(localized: "Create exercise"), variant: .solida) {
                showCreate = true
            }
        }
        .padding(.top, LiquidSpace.s400)
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
        // FER-289: `StrandCTAButton` sustituye a `InstrumentoAddButton`. `.solid` en creación
        // (salida del flujo); `.outline` al agregar a rutina existente. Copy y disabled iguales.
        StrandCTAButton(LocalizedStringKey(addBarLabel),
                        kind: createFlow ? .solid : .outline) {
            onAdd?(exercises.filter { selected.contains($0.id) })
            dismiss()
        }
        .disabled(selected.isEmpty)
        .padding(.horizontal, LiquidSpace.s600)
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

                VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                    Text("Name").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    TextField("e.g. Svend press", text: $name)
                        .font(StrandFont.body).foregroundStyle(theme.ink)
                        .padding(.horizontal, LiquidSpace.s300).padding(.vertical, CenitMetrics.rowVPad)
                        // Same skin as the Library's search field — one text-field look per flow.
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
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
                        .padding(.bottom, LiquidSpace.s100)
                    Divider().overlay(theme.hairline)
                    pickerRow("Equipment", isPresented: $showEquipPicker, selection: $equip, options: equipment, placeholder: String(localized: "Pick equipment"), label: StrengthDisplay.equipment)
                }

                VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                    Text("Record type").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    ForEach(ExerciseType.allCases, id: \.self) { t in typeOption(t) }
                }

                Button { create() } label: {
                    Text(isEditing ? "Save changes" : "Create exercise")
                        .font(InstrumentoType.grotesk(15, weight: .bold))
                        .foregroundStyle(canCreate ? theme.ink : theme.inkTertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, LiquidSpace.s300)
                        .liquidGlass(.pastillaSolida)
                        .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(EntrenarPressStyle()).disabled(!canCreate)
            }
            .padding(.top, CenitMetrics.screenTop).padding(.horizontal, LiquidSpace.s600).padding(.bottom, LiquidSpace.s600)
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
                HStack(spacing: LiquidSpace.s100) {
                    Text(selection.wrappedValue.isEmpty ? placeholder : label(selection.wrappedValue))
                        .font(StrandFont.body).foregroundStyle(selection.wrappedValue.isEmpty ? theme.inkTertiary : theme.inkSecondary)
                    StrandIcon.down.image.font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                }
            }
            .buttonStyle(EntrenarPressStyle())
            .liquidMenu(isPresented: isPresented, items: options.map { opt in
                LiquidMenuItem(label(opt), systemImage: selection.wrappedValue == opt ? "checkmark" : nil) {
                    selection.wrappedValue = opt
                }
            })
        }
        .frame(minHeight: EntrenarMetrics.row)   // HIG minimum touch target (44)
    }

    private func typeOption(_ t: ExerciseType) -> some View {
        Button { type = t } label: {
            HStack(spacing: LiquidSpace.s300) {
                Image(systemName: StrengthDisplay.typeIcon(t)).font(StrandFont.glyph(.lead))
                    .foregroundStyle(type == t ? theme.ink : theme.inkTertiary).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(StrengthDisplay.typeLabel(t)).font(StrandFont.body).foregroundStyle(theme.ink)
                    Text(StrengthDisplay.typeDetail(t)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                if type == t { StrandIcon.confirm.image.font(StrandFont.glyph(.inline, weight: .semibold)).foregroundStyle(theme.ink) }
            }
            .padding(.horizontal, LiquidSpace.s300).padding(.vertical, CenitMetrics.rowVPad).contentShape(Rectangle())
            .background(type == t ? theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous))  // token-exempt: fondo condicional
            .overlay(RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
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
