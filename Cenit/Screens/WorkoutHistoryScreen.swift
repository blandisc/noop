#if os(iOS)
import SwiftUI
import CenitDesign
import StrandAnalytics
import StrandTraining
import CenitStore   // WorkoutRow — the journal join that carries zones / max HR (FER-952)
import Inject   // recarga en caliente (dev-only, inerte en Release)

// «Mis entrenamientos» (FER-504): sesiones de fuerza completadas en Liquid Glass · El Eje (tinta en
// pesos/series; color solo en el dato fisiológico). Solo lectura; vive en el stack de Entrenar.

/// A session pushed onto the train stack for its detail. Carries the scalar fields the detail header
/// needs (so it doesn't refetch the row); the per-exercise sets are loaded by the detail screen. A
/// distinct Hashable type so the type-erased `trainStack` carries it alongside the other routes.
struct WorkoutSessionRoute: Hashable {
    let id: String
    let startTs: Int
    let endTs: Int?
    let strain: Double?
    let avgHr: Int?
    let routineName: String
}

/// Route pushed onto the Entrenar stack for the saved thermal-receipts grid.
struct SavedTicketsRoute: Hashable {}


/// Cross-screen state for the workout-history stack (FER-556). The detail is a sibling pushed onto the
/// same NavigationStack as the list, not its child — so a delete or edit done in the detail can't reach
/// the list directly. This shared object bridges them: the detail seeds `pendingUndo` (the list shows the
/// «Undo» banner after the pop) and bumps `reloadToken` (the list reloads, since `.task` isn't re-run on
/// pop-back). Injected once on the Entrenar NavigationStack in RootTabView.
@MainActor final class WorkoutHistoryCoordinator: ObservableObject {
    /// A just-deleted session + its sets, kept so «Undo» can restore it intact (reused from FER-527).
    struct DeletedSession: Identifiable, Equatable {
        let id = UUID()
        let session: StrengthSession
        let sets: [SetEntry]
    }
    @Published var pendingUndo: DeletedSession?
    /// Bumped after an edit/delete deeper in the stack so the list refreshes when shown again.
    @Published var reloadToken = 0
    func bumpReload() { reloadToken &+= 1 }
}

// MARK: - List

struct WorkoutHistoryScreen: View {
    /// Push a completed session's detail from a tapped calendar day (Alcance punto 2, FER-90) — the
    /// list rows still navigate via `NavigationLink(value:)`, which doesn't need this. Same pattern as
    /// `WorkoutSessionDetailScreen.openRoutine`: default nil so no other call site breaks.
    var openWorkoutSession: ((WorkoutSessionRoute) -> Void)?
    /// FER-202 (fusión «Historial unificado»): empuja el detalle de una fila de ACTIVIDAD (`WorkoutRow`
    /// — cardio de Apple / manual). La puerta lo cablea a su stack (que registra `WorkoutRow` como
    /// destino); nil = no navega (previews / puertas que solo muestran fuerza).
    var openCardio: ((WorkoutRow) -> Void)?
    /// FER-202: cierra la CAPA cuando esta pantalla ES la raíz del `workoutsLayer` de Cuerpo (no llega
    /// empujada, así que no hay «‹» del sistema; el toolbar dibuja «‹ Tendencias»). nil en la puerta de
    /// Entrenar, donde llega empujada al trainStack.
    var onClose: (() -> Void)?
    /// FER-202: el filtro con el que ABRE cada puerta — Entrenar `.strength` (bitácora de fuerza rica),
    /// Cuerpo `.all` (toda la actividad). Siembra `filtro`.
    let initialFilter: HistoryFilter

    /// El único inicializador (FER-202): además de las clausuras/puerta, siembra el `@State filtro` con
    /// `initialFilter`. Sustituye al memberwise para poder sembrar el estado desde el argumento.
    init(initialFilter: HistoryFilter = .strength,
         openWorkoutSession: ((WorkoutSessionRoute) -> Void)? = nil,
         openCardio: ((WorkoutRow) -> Void)? = nil,
         onClose: (() -> Void)? = nil) {
        self.initialFilter = initialFilter
        self.openWorkoutSession = openWorkoutSession
        self.openCardio = openCardio
        self.onClose = onClose
        _filtro = State(initialValue: initialFilter)
    }

    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var health: HealthKitBridge
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @EnvironmentObject private var coordinator: WorkoutHistoryCoordinator
    /// FER-202: el filtro-dialecto activo (sembrado desde `initialFilter` en `init`). `.strength` →
    /// dialecto bitácora de fuerza; `.all`/`.sport` → dialecto actividad («Todo»).
    @State private var filtro: HistoryFilter
    /// FER-202: la actividad de Apple Health / manual (`WorkoutRow`) que alimenta el dialecto «Todo».
    @State private var workoutRows: [WorkoutRow] = []
    /// FER-202: el rango del dialecto «Todo» (Fuerza usa ventanas nativas de 90 días, sin control de rango).
    @State private var range: ExploreRange = .all
    /// FER-202: el rango se siembra al rango más estrecho con datos UNA sola vez, no en cada recarga
    /// (`load()` corre en cada bump del coordinador), para no pisar la elección del usuario.
    @State private var didSeedRange = false
    @State private var sessions: [StrengthSession] = []
    @State private var routineNames: [String: String] = [:]
    @State private var volumes: [String: (volumeKg: Double, setCount: Int)] = [:]
    /// Trailing-30-day muscle set events for the compact «Volume per muscle» summary (FER-719 math).
    @State private var muscleEvents: [MuscleFatigueMap.MuscleSetEvent] = []
    /// Progression signals (raised / waiting / stalled) for exercises with progression enabled.
    @State private var progressionRows: [ProgressionRow] = []
    /// Movement family per routine (for the session rows' glyph/tint AND the calendar's cells) —
    /// classified once at load, from the same `RoutineClassifier` pass (Alcance punto 2).
    @State private var routineRegions: [String: RoutineRegion] = [:]
    @State private var loaded = false
    /// FER-969 / X-05a: undo-restore write failure on the list.
    @State private var saveError = false
    /// `repo.storeHandle()` came back nil — a real read failure, distinct from «cero sesiones»
    /// (Estados, decisión #16 del épico, FER-90).
    @State private var readError = false
    /// FER-136 · V7: marcas nuevas por sesión, acotado a `recentSessions90` (misma llamada acotada
    /// que `EntrenarView.marcaCount`, nunca un barrido sin ventana).
    @State private var marksBySession: [String: Int] = [:]
    /// FER-136 · V7: «Progreso por ejercicio» — un estimado de 1RM por cada ejercicio con historial,
    /// hasta 6 filas (mismo tope que `progressionRows`).
    @State private var progressExercises: [ProgressExerciseRow] = []
    /// La fila de «Progreso» tocada — abre `ExerciseDetailScreen` en su tab Progreso.
    @State private var progressDetailExercise: Exercise?
    /// «Registrar entreno a mano» (FER-136 · V7) — el mismo `ManualWorkoutSheet` que «Mis entrenamientos».
    @State private var showManualEntry = false
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s700) {
                header
                // FER-202: el interruptor de dialecto [Todo · Fuerza] — constante en toda la pantalla,
                // debajo del título. `.sport(...)` cuenta como «Todo» (el chip removible vive dentro).
                filterSegment
                if loaded {
                    if showsFuerzaDialect {
                        // Degradación honesta: bajo «Todo»/deporte sin permiso de Apple Salud y sin
                        // actividad, caemos al dialecto de Fuerza (on-device, no necesita permiso) + aviso.
                        if !isStrengthFilter { appleAviso }
                        fuerzaDialect
                    } else {
                        todoDialect
                    }
                    manualEntryRow
                }
            }
            .padding(.top, LiquidSpace.topeScroll)
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-202 (épico «Entrenar en vidrio»): suelo de cristal El Eje en vez del papel plano — la
        // misma receta de la familia que las hojas ya migradas (v1). El héroe/tiles se posan encima.
        .entrenarHojaFondo(tono: .neutro)
        .pantallaFondo()
        // FER-202: cuando esta pantalla es la RAÍZ de la capa de Cuerpo (no llega empujada), el toolbar
        // dibuja «‹ Tendencias» — no hay «‹» del sistema que la cierre. En la puerta de Entrenar `onClose`
        // es nil y este item no aparece (el stack ya trae su propio back).
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onClose() } label: {
                        HStack(spacing: LiquidSpace.s100) {
                            CenitIcon.back.image.font(LiquidType.iconSF(size: 15))
                            Text("Tendencias").font(LiquidType.tituloGemela)
                        }
                    }
                    .foregroundStyle(LiquidColor.tinta900)
                }
            }
        }
        // The detail push (`WorkoutSessionRoute`) is registered once on the Entrenar NavigationStack in
        // RootTabView (alongside the other train routes), so it isn't re-declared here.
        // «Undo» toast after a delete (FER-527), now seeded by the list OR the detail via the coordinator.
        .overlay(alignment: .bottom) { if let d = coordinator.pendingUndo { undoBanner(d) } }
        // FER-969 / FER-280·2c: undo-restore failure → `.saveErrorToast` (pad 16 ≡ cardPadding).
        .saveErrorToast(isPresented: $saveError,
                        message: String(localized: "Couldn't save the workout. Try again."))
        .sensoryFeedback(trigger: coordinator.pendingUndo?.id) { _, new in
            new != nil ? LiquidHaptica.advertencia.feedback : nil
        }
        // Reloads on first appear (token 0), whenever a delete/edit deeper in the stack bumps it, and
        // when the repository publishes a new pass — the progression rows read today's verdict, so a
        // cold-start visit corrects itself the moment it lands (FER-82) instead of staying empty.
        .task(id: [coordinator.reloadToken, repo.refreshSeq]) { await load() }
        // FER-136 · V7: «Progreso por ejercicio» abre el MISMO `ExerciseDetailScreen` que la sesión
        // detallada usa (mismo patrón `.sheet(item:)` que `WorkoutSessionDetailScreen.detailExercise`
        // más abajo en este archivo), en su tab Progreso.
        .sheet(item: $progressDetailExercise) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex, startOnProgress: true)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { progressDetailExercise = nil }.foregroundStyle(LiquidColor.tinta900)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
            }
            .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        // «Registrar entreno a mano ›» — el MISMO `ManualWorkoutSheet` que «Mis entrenamientos».
        .sheet(isPresented: $showManualEntry) {
            ManualWorkoutSheet(theme: theme) { row, replacing in
                Task {
                    do {
                        try await repo.saveManualWorkout(row, replacing: replacing)
                        coordinator.bumpReload()
                        // El registro a mano guarda un `WorkoutRow` (aparece bajo «Todo»): si estás en
                        // «Fuerza» al guardar, salta a «Todo» para que la entrada nunca «desaparezca».
                        withAnimation(LiquidMotion.fundido) { filtro = .all }
                    } catch {
                        saveError = true
                    }
                }
            }
            .instrumentoTheme(theme).preferredColorScheme(.light)
        }
        .enableInjection()
    }

    private var header: some View {
        // FER-246 / FER-294: título CONSTANTE «Historial». Bajo Fuerza el subtítulo sube a kicker;
        // bajo Todo el héroe del rango lleva el conteo.
        LiquidFlowTitle(
            kicker: showsFuerzaDialect ? historialSubtitle : nil,
            titulo: String(localized: "History"))
    }

    /// El dialecto BITÁCORA (filtro «Fuerza», o la degradación honesta sin permiso de Apple Salud): el
    /// layout de fuerza rica ya aprobado — Tu mes → Ciclos de subida → Volumen por músculo → Sesiones
    /// (calendario 13sem + línea solo-fuerza) → Progreso → Mis tickets. Ventanas nativas de 90 días.
    @ViewBuilder private var fuerzaDialect: some View {
        // El calendario (dentro de `sessionsSection`, como su cabecera) dibuja siempre — aun con cero
        // sesiones o error de lectura — para que «sin datos» y «no se pudo leer» nunca se lean como las
        // mismas 91 celdas vacías (Alcance punto 2, Estados). `tuMes`/`progressionBlock`/`muscleVolumeInline`
        // se ocultan sin sesiones: no tienen nada honesto que mostrar.
        if !sessions.isEmpty {
            tuMes
            progressionBlock
            muscleVolumeInline
        }
        sessionsSection
        if readError {
            readErrorBanner
        } else if sessions.isEmpty {
            emptyState
        } else {
            progressSection
            savedTicketsEntry
        }
    }

    // MARK: - FER-202 · interruptor de dialecto [Todo · Fuerza] + estados de puerta

    /// Los dos segmentos visibles: `.sport(...)` cuenta como «Todo» (el chip removible vive dentro).
    private enum SegTab: Hashable { case todo, fuerza }

    private var isStrengthFilter: Bool { if case .strength = filtro { return true }; return false }

    /// El binding del segmento: `.fuerza` ⇔ `filtro == .strength`; `.all`/`.sport` se leen como «Todo».
    /// Tocar «Fuerza» pone `.strength`; «Todo» limpia a `.all` (suelta cualquier deporte estrechado).
    private var segSelection: Binding<SegTab> {
        Binding(
            get: { isStrengthFilter ? .fuerza : .todo },
            set: { tab in withAnimation(LiquidMotion.fundido) { filtro = (tab == .fuerza) ? .strength : .all } }
        )
    }

    private var filterSegment: some View {
        SegmentedPillControl([SegTab.todo, SegTab.fuerza], selection: segSelection, theme: theme) { tab in
            tab == .todo ? String(localized: "All") : String(localized: "Strength")
        }
        .accessibilityLabel(Text("Filter"))
    }

    /// ¿Permiso de Apple Salud? `.unavailable` (sin HealthKit, p. ej. iPad) cuenta como «no bloquea»:
    /// no hay nada que conectar, así que no degradamos ni mostramos el aviso.
    private var appleAuthorized: Bool { health.auth == .authorized || health.auth == .unavailable }

    /// Rinde el dialecto de Fuerza cuando el filtro es `.strength`, O cuando estamos en «Todo»/deporte
    /// SIN permiso de Apple Salud y sin ninguna actividad importada — degradación honesta: la fuerza es
    /// on-device y no necesita permiso.
    private var showsFuerzaDialect: Bool {
        if isStrengthFilter { return true }
        return !appleAuthorized && workoutRows.isEmpty
    }

    /// El aviso azul-Apple sobre el dialecto degradado: honesto, no interactivo (Fuentes de datos vive
    /// en Ajustes). No promete lo que no puede hacer aquí: dice dónde conectar.
    private var appleAviso: some View {
        LiquidAviso(
            titulo: String(localized: "Connect Apple Health"),
            cuerpo: String(localized: "Turn it on in Settings to see your workouts from there."),
            tono: LiquidColor.azul)
    }

    // MARK: - FER-202 · dialecto ACTIVIDAD («Todo» / deporte)

    /// La línea de tiempo FUNDIDA (fuerza rica + actividad, con el eco de Apple de-duplicado). Base de
    /// todo el dialecto; el rango y el filtro se aplican encima. Pura (`UnifiedWorkoutHistory`).
    private var mergedEntries: [HistoryEntry] {
        UnifiedWorkoutHistory.merge(sessions: sessions, rows: workoutRows)
    }

    /// Cutoff NOW-anclado (inicio de hoy − (días−1)); nil para `.all`. Mismo ancla que la teja de
    /// «Entrenamientos» en Tendencias, para que los conteos coincidan.
    private func cutoffTs(for r: ExploreRange) -> Int? {
        guard let days = r.days else { return nil }
        let start = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date())
        return Int(start.timeIntervalSince1970)
    }

    private func entriesInRange(_ entries: [HistoryEntry], _ r: ExploreRange) -> [HistoryEntry] {
        guard let cut = cutoffTs(for: r) else { return entries }
        return entries.filter { $0.startTs >= cut }
    }

    /// El rango seleccionado si tiene ≥1 entrada, si no el menor rango mayor que sí (auto-ampliación).
    private var effectiveTodoRange: ExploreRange {
        let base = mergedEntries
        guard !base.isEmpty else { return range }
        for r in range.widening where !entriesInRange(base, r).isEmpty { return r }
        return .all
    }

    /// Las entradas visibles bajo «Todo»/deporte: fundidas → ventana efectiva → filtro (`.all`/`.sport`).
    private var todoVisibleEntries: [HistoryEntry] {
        UnifiedWorkoutHistory.filter(entriesInRange(mergedEntries, effectiveTodoRange), filtro)
    }

    /// El rango por defecto: el más estrecho que aún guarda ≥2 entradas; si no, «Todo». Se siembra UNA vez.
    private func defaultTodoRange(_ base: [HistoryEntry]) -> ExploreRange {
        guard !base.isEmpty else { return .all }
        for r in ExploreRange.allCases where r.days != nil {
            guard let cut = cutoffTs(for: r) else { continue }
            if base.filter({ $0.startTs >= cut }).count >= 2 { return r }
        }
        return .all
    }

    @ViewBuilder private var todoDialect: some View {
        let eff = effectiveTodoRange
        let visible = todoVisibleEntries
        SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme, tall: true) { $0.label }
        todoHero(count: visible.count, eff: eff, fellBack: eff != range)
        if case .sport(let name) = filtro { sportChip(name) }
        todoTiles(entries: visible)
        porDeporteSection(base: entriesInRange(mergedEntries, eff))
        todoTimeline(entries: visible)
        todoMetodo
    }

    /// Héroe del dialecto: el conteo del periodo en un módulo neutro de cristal (numeral Grotesk), NO
    /// una losa oscura. El sufijo «sesiones» y el pie de rango (o la nota de auto-ampliación) debajo.
    private func todoHero(count: Int, eff: ExploreRange, fellBack: Bool) -> some View {
        EntrenarModulo(tono: .neutro) {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
                    Text(verbatim: "\(count)")
                        .font(LiquidType.numeralHoja).foregroundStyle(LiquidColor.tinta900)
                        .monospacedDigit()
                    Text(count == 1 ? "session" : "sessions")
                        .font(LiquidType.numeralHojaUnidad).foregroundStyle(LiquidColor.tinta500)
                }
                Text(rangeCaptionText(eff: eff, fellBack: fellBack))
                    .font(LiquidType.cuerpoBanner)
                    .foregroundStyle(fellBack ? LiquidColor.atencionTexto : LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func rangeCaptionText(eff: ExploreRange, fellBack: Bool) -> String {
        if fellBack { return String(format: String(localized: "Sparse · widened to %@"), eff.phrase) }
        return eff.phrase
    }

    /// El chip removible del deporte estrechado — tocarlo suelta el filtro de vuelta a «Todo».
    private func sportChip(_ name: String) -> some View {
        let display = WorkoutSource.displaySport(name)
        return LiquidChipSeleccion(
            nombre: display,
            tono: LiquidColor.azul,
            a11yQuitar: String(localized: "Showing \(display) · tap to clear"),
            onQuitar: { withAnimation(LiquidMotion.fundido) { filtro = .all } })
    }

    /// «Este periodo» = Horas · Kcal (2 tiles). El conteo ya vive en el héroe, no se repite; «Volumen»
    /// se retira (mentía sobre cardio). Sobre las entradas visibles, honesto con lo que la lista muestra.
    private func todoTiles(entries: [HistoryEntry]) -> some View {
        let totals = periodTotals(entries)
        return HStack(spacing: LiquidSpace.s300) {
            EntrenarTile(tono: .neutro) { tileBody("Hours", totals.hours) }
            EntrenarTile(tono: .neutro) { tileBody("Energy", totals.kcal) }
        }
    }

    private func tileBody(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s075) {
            Text(label).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            Text(verbatim: value).font(LiquidType.valorL).foregroundStyle(LiquidColor.tinta900)
        }
        .accessibilityElement(children: .combine)
    }

    /// Horas + kcal sobre las entradas visibles (fuerza: endTs−startTs / energyKcal; cardio: durationS /
    /// energyKcal). «—» cuando no hay dato — nunca un cero fabricado.
    private func periodTotals(_ entries: [HistoryEntry]) -> (hours: String, kcal: String) {
        var seconds = 0
        var kcal = 0.0
        var hasKcal = false
        for e in entries {
            switch e {
            case .strength(let s):
                if let end = s.endTs, end > s.startTs { seconds += end - s.startTs }
                if let k = s.energyKcal { kcal += k; hasKcal = true }
            case .cardio(let r):
                seconds += Int(r.durationS ?? Double(max(0, r.endTs - r.startTs)))
                if let k = r.energyKcal { kcal += k; hasKcal = true }
            }
        }
        let hours = seconds > 0 ? String(format: "%.1f h", Double(seconds) / 3600) : "—"
        let kcalStr = hasKcal ? "\(CenitFormat.groupedInt(kcal)) kcal" : "—"
        return (hours, kcalStr)
    }

    /// «Por deporte»: los deportes de la actividad en la ventana (tocar estrecha a `.sport`) + una fila
    /// «Fuerza» que salta al dialecto de fuerza (`.strength`, NO `.sport("Fuerza")` — daría 0 sesiones).
    @ViewBuilder private func porDeporteSection(base: [HistoryEntry]) -> some View {
        let sports = UnifiedWorkoutHistory.sports(base)
        let strengthCount = base.filter(\.isStrength).count
        if !sports.isEmpty || strengthCount > 0 {
            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                LiquidSectionHeader("By sport")
                VStack(spacing: .zero) {
                    if strengthCount > 0 {
                        porDeporteRow(symbol: "dumbbell.fill", name: String(localized: "Strength"),
                                      count: strengthCount, divider: !sports.isEmpty) {
                            withAnimation(LiquidMotion.fundido) { filtro = .strength }
                        }
                    }
                    ForEach(Array(sports.enumerated()), id: \.element) { idx, sport in
                        let n = base.filter { if case .cardio(let r) = $0 { return r.sport == sport }; return false }.count
                        porDeporteRow(symbol: WorkoutSource.sfSymbol(for: sport),
                                      name: WorkoutSource.displaySport(sport), count: n,
                                      divider: idx != sports.count - 1) {
                            withAnimation(LiquidMotion.fundido) { filtro = .sport(sport) }
                        }
                    }
                }
                .padding(.horizontal, LiquidSpace.handoff14)
                .padding(.vertical, LiquidSpace.s050)
                .liquidGlass(.superficieSolida)
            }
        }
    }

    private func porDeporteRow(symbol: String, name: String, count: Int, divider: Bool,
                               tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: LiquidSpace.s300) {
                Image(systemName: symbol)
                    .font(LiquidType.iconSF(size: 15)).foregroundStyle(LiquidColor.tinta700)
                    .frame(width: 22)
                Text(verbatim: name).font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta900).lineLimit(1)
                Spacer(minLength: LiquidSpace.s200)
                Text(verbatim: "\(count)").font(LiquidType.valorS).foregroundStyle(LiquidColor.tinta700)
                LiquidIcon(.chevron, size: 12, color: LiquidColor.tinta500)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, LiquidSpace.s150)
            .padding(.horizontal, LiquidSpace.s100)
            .frame(minHeight: LiquidControl.hitTarget)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if divider { LiquidCapilar(eje: .horizontal) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityHint(Text("Narrows the list to this sport"))
    }

    /// La línea de tiempo MIXTA: cada entrada como fila rica de fuerza o fila de actividad, en el
    /// contenedor `EntrenarHistorialLista` (separadores tinta7). El vacío dice que el periodo está vacío.
    private func todoTimeline(entries: [HistoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            LiquidSectionHeader("Sessions") {
                Text(verbatim: "\(entries.count)").font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta700)
            }
            if entries.isEmpty {
                EntrenarHistorialLista(vacio: String(localized: "No sessions in this period yet."), filas: [AnyView]())
            } else {
                EntrenarHistorialLista(filas: entries.map { AnyView(entryRow($0)) })
            }
        }
    }

    @ViewBuilder private func entryRow(_ entry: HistoryEntry) -> some View {
        switch entry {
        case .strength(let s): fuerzaRow(s)
        case .cardio(let r):   cardioRow(r)
        }
    }

    /// Una `StrengthSession` como `EntrenarFilaFuerza` (glifo de familia + marca + esfuerzo).
    /// Nombre, meta, familia, marcas — una sola fila compartida con el dialecto Fuerza.
    private func fuerzaRow(_ s: StrengthSession) -> some View {
        let family: EntrenarFamily = s.routineId.flatMap { routineRegions[$0] }?.family ?? .fullBody
        return EntrenarFilaFuerza(
            family: family,
            nombre: name(for: s),
            meta: sessionMeta(s),
            marcas: marksBySession[s.id] ?? 0,
            esfuerzo: s.strain.map { StrengthHistoryFormat.strain($0) }
        ) { openWorkoutSession?(route(for: s)) }
    }

    /// Un `WorkoutRow` de actividad como `EntrenarFilaCardio` (SF Symbol neutro + origen + FC/duración).
    /// `detected`/`whoop` (raros en la práctica) caen a `.apple` — el componente solo tiene Apple/Manual;
    /// extender su `Origen` es refinamiento de v2.
    private func cardioRow(_ r: WorkoutRow) -> some View {
        let origen: EntrenarFilaCardio.Origen = WorkoutSource.classify(r.source) == .manual ? .manual : .apple
        return EntrenarFilaCardio(
            sfSymbol: WorkoutSource.sfSymbol(for: r.sport),
            deporte: WorkoutSource.displaySport(r.sport),
            origen: origen,
            meta: cardioMeta(r),
            dato: cardioDato(r)
        ) { openCardio?(r) }
    }

    private func cardioMeta(_ r: WorkoutRow) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(r.startTs))
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).lowercased()
        let mins = Int((r.durationS ?? Double(max(0, r.endTs - r.startTs))) / 60)
        return mins > 0 ? "\(date) · \(StrengthHistoryFormat.durationText(mins))" : date
    }

    /// FC media (rosa oscurecida AA) si la trae; si no, la duración en tinta. NUNCA esfuerzo/21: la
    /// escala de strain de cardio puede no ser la misma que la de fuerza (decisión del diseño).
    private func cardioDato(_ r: WorkoutRow) -> EntrenarFilaCardio.Dato {
        if let hr = r.avgHr {
            return .init(valor: "\(hr)", unidad: "bpm",
                         tono: LiquidTono.rosa.rotulo)
        }
        let mins = Int((r.durationS ?? Double(max(0, r.endTs - r.startTs))) / 60)
        return .init(valor: "\(mins)", unidad: String(localized: "min"), tono: LiquidColor.tinta700)
    }

    /// El pie honesto del dialecto: de dónde sale cada sesión y que el conteo sigue el rango de arriba.
    private var todoMetodo: some View {
        LiquidPatternBlock(
            overline: nil,
            lineas: [String(localized: "Each session is a workout from Apple Health, an on-device capture, or one you logged by hand. Counts follow the range above.")],
            tono: LiquidColor.tinta10)
    }

    /// «11 sesiones · 90 días · 3 marcas nuevas» — sin marcas nuevas en la ventana, la cláusula de
    /// marcas simplemente no aparece (copy.md «Historial»: «sin marcas: solo sesiones»). Singular/
    /// plural correcto en las dos partes.
    private var historialSubtitle: String {
        let sessionsPart = recentSessions90.count == 1
            ? String(localized: "1 session · 90 days")
            : String(localized: "\(recentSessions90.count) sessions · 90 days")
        guard marksTotal90 > 0 else { return sessionsPart }
        let marksPart = marksTotal90 == 1
            ? String(localized: "1 new mark")
            : String(localized: "\(marksTotal90) new marks")
        return "\(sessionsPart) · \(marksPart)"
    }

    /// Sesiones COMPLETADAS en los últimos 90 días naturales — la MISMA ventana y el MISMO filtro que
    /// `EntrenarView.recentSessions90` (`endTs != nil`, para que una sesión en curso nunca cuente
    /// como terminada aquí tampoco).
    private var recentSessions90: [StrengthSession] {
        let cutoff = Date().timeIntervalSince1970 - 90 * 86_400
        return sessions.filter { $0.endTs != nil && Double($0.startTs) >= cutoff }
    }

    /// Total de marcas nuevas en la ventana de 90 días — la suma de `marksBySession` (cargado en
    /// `load()`, acotado a `recentSessions90`).
    private var marksTotal90: Int { marksBySession.values.reduce(0, +) }

    // MARK: - «TU MES» (handoff v2, FER-941) — the weekly-volume card + the three month tiles

    @State private var selectedWeek: Int? = nil   // nil / 7 = current week

    /// Split for type-check cost (FER-981): volume card + month tiles are separate ViewBuilders.
    private var tuMes: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidSectionHeader("Your month")
            tuMesVolumeCard
            tuMesMonthTiles
        }
    }

    /// Weekly volume card (header, bars, selected-week strip) — extracted so its CGFloat/ternary
    /// chains type-check alone (FER-981).
    @ViewBuilder
    private var tuMesVolumeCard: some View {
        let weeks: [WeekVolume] = weeklyVolumes
        let peakRaw: Double = weeks.map(\.volumeKg).max() ?? 1.0
        let peak: Double = max(peakRaw, 1.0)
        let selectedId: Int = selectedWeek ?? 7
        let sel: WeekVolume = weeks.first { (w: WeekVolume) in w.id == selectedId } ?? weeks[7]
        EntrenarModulo(tono: .neutro) {
            VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                tuMesVolumeHeader
                tuMesWeeklyBars(weeks: weeks, peak: peak, selectedId: selectedId)
                tuMesSelectedWeekStrip(sel: sel)
            }
        }
    }

    @ViewBuilder
    private var tuMesVolumeHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Volume per week").font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
            Spacer(minLength: LiquidSpace.s200)
            if let delta: Double = monthVolumeDeltaPercent {
                tuMesDeltaChip(delta: delta)
            }
        }
    }

    /// «↗ +N% / ↘ −N% vs. last month» chip — valence color pre-bound so the ternary isn't re-inferred
    /// on every modifier (FER-981). LiquidStatePill.valencia (FER-280·2b).
    @ViewBuilder
    private func tuMesDeltaChip(delta: Double) -> some View {
        let up: Bool = delta >= 0
        let n: Int = abs(Int(delta.rounded()))
        // §8.7: valence en texto <24pt usa positivo / atencionTexto (AA), no el hue del dato.
        let valence: Color = up ? LiquidColor.positivo : LiquidColor.atencionTexto
        let label: String = up ? "↗ +\(n)% vs. last month" : "↘ −\(n)% vs. last month"
        LiquidStatePill(valencia: label, tono: valence)
    }

    /// 8-week bar chart + axis labels. Bar height uses fully-typed CGFloat math (FER-981).
    private func tuMesWeeklyBars(weeks: [WeekVolume], peak: Double, selectedId: Int) -> some View {
        VStack(spacing: LiquidSpace.s100) {
            HStack(alignment: .bottom, spacing: LiquidSpace.s150) {
                ForEach(weeks) { (w: WeekVolume) in
                    let isSelected: Bool = w.id == selectedId
                    let fill: Color = isSelected ? LiquidColor.verdeCarga : LiquidColor.tinta10
                    let ratio: Double = w.volumeKg / peak
                    let barH: CGFloat = max(CGFloat(3), CGFloat(ratio) * CGFloat(54))
                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)  // token-exempt(dato): geometría de dato
                        .fill(fill)
                        .frame(height: barH)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(LiquidMotion.toque) { selectedWeek = w.id } }
                }
            }
            .frame(height: 58, alignment: .bottom)
            Rectangle().fill(LiquidColor.tinta10).frame(height: 1.2)  // token-exempt(dato): eje de dato
            HStack {
                Text(weekLabel(weeks.first?.start)).font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                Spacer(minLength: LiquidSpace.s200)
                Text("this week").font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Volume over the last 8 weeks"))
    }

    @ViewBuilder
    private func tuMesSelectedWeekStrip(sel: WeekVolume) -> some View {
        let volumeText: String = StrengthHistoryFormat.volume(sel.volumeKg, system: system)
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            LiquidCapilar(eje: .horizontal)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: LiquidSpace.s025) {
                    Group {
                        if sel.isCurrent {
                            Text("This week · in progress").liquidLabel()
                        } else {
                            Text("Week of \(weekLabel(sel.start))").liquidLabel()
                        }
                    }
                    .foregroundStyle(LiquidColor.tinta500)
                    Text("\(sel.count) sessions · tap another bar to switch")
                        .font(LiquidType.filaConteo).foregroundStyle(LiquidColor.tinta500)
                }
                Spacer(minLength: 10)
                Text(volumeText)
                    .font(LiquidType.valorM).foregroundStyle(LiquidColor.tinta900)
            }
            .padding(.top, LiquidSpace.s250)
        }
    }

    /// The three month tiles (Sessions / Hours / Energy) with pre-formatted strings (FER-981).
    @ViewBuilder
    private var tuMesMonthTiles: some View {
        let m: MonthAggregate = monthAggregate
        let sessionsValue: String = "\(m.count)"
        let hoursValue: String = m.hours > 0 ? String(format: "%.1f", m.hours) : "—"
        let energyValue: String = m.energyKcal.map(CenitFormat.groupedInt) ?? "—"
        let energyUnit: LocalizedStringKey? = m.energyKcal != nil ? "kcal" : nil
        HStack(spacing: LiquidSpace.s200) {
            monthTile("Sessions", sessionsValue, caption: "this month")
            monthTile("Hours", hoursValue, caption: "trained")
            monthTile("Energy", energyValue, unit: energyUnit, caption: "measured")
        }
    }

    private func monthTile(_ label: LocalizedStringKey, _ value: String,
                           unit: LocalizedStringKey? = nil, caption: LocalizedStringKey) -> some View {
        EntrenarTile(tono: .neutro) {
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(label).liquidLabel().foregroundStyle(LiquidColor.tinta500)
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s075) {
                    Text(value).font(LiquidType.valorL).foregroundStyle(LiquidColor.tinta900)
                    if let unit { Text(unit).font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500) }
                }
                Text(caption).font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// «18 may» — a week-start date as the axis/strip label.
    private func weekLabel(_ d: Date?) -> String {
        guard let d else { return "" }
        return d.formatted(.dateTime.day().month(.abbreviated)).lowercased()
    }

    // MARK: - «VOLUMEN POR MÚSCULO · 30 DÍAS» (handoff v2, FER-941)
    //
    // Top four muscles by weekly work sets plus the weakest one, each with a proportional bar in its
    // movement-family tint; «Ver mapa» rides the band. The honest footnote names the neglected muscle.

    @ViewBuilder
    private var muscleVolumeInline: some View {
        let all = MuscleFatigueMap.weeklyVolumes(events: muscleEvents, days: 30)
        if !all.isEmpty {
            let sorted = all.sorted { $0.setsPerWeek > $1.setsPerWeek }
            let shown = muscleRowsToShow(sorted)
            let weakest = sorted.last
            let maxV = max(sorted.first?.setsPerWeek ?? 1, 0.1)
            VStack(alignment: .leading, spacing: LiquidSpace.s225) {
                LiquidSectionHeader("Volume per muscle · 30 days") {
                    NavigationLink(value: MuscleVolumeRoute()) {
                        Text("See map").font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
                            .frame(minHeight: 44)   // toque 44 (HIG §8.7-4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(shown, id: \.muscle) { v in
                    HStack(spacing: LiquidSpace.s250) {
                        Text(MuscleAtlas.name(v.muscle))
                            .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: 86, alignment: .leading)
                        Capsule()
                            .fill(LiquidColor.tinta7)
                            .frame(height: 12)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(v.setsPerWeek <= 0 ? LiquidColor.tinta10 : muscleTint(v.muscle))
                                        .frame(width: max(6, geo.size.width * CGFloat(min(v.setsPerWeek, maxV) / maxV)))
                                }
                            }
                            .clipShape(Capsule())
                        Text(MuscleFatigueMap.formattedSets(v.setsPerWeek))
                            .font(LiquidType.valorS).foregroundStyle(LiquidColor.tinta700)
                            .frame(minWidth: 34, alignment: .trailing).lineLimit(1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(MuscleAtlas.name(v.muscle)))
                    .accessibilityValue(Text("\(MuscleFatigueMap.formattedSets(v.setsPerWeek)) sets per week"))
                }
                LiquidPatternBlock(overline: nil, lineas: [muscleNote(weakest)], tono: LiquidColor.tinta10)
            }
        }
    }

    /// Top four by weekly sets, plus the weakest one (the honest tail) when it isn't already shown.
    private func muscleRowsToShow(_ sorted: [MuscleFatigueMap.MuscleWeeklyVolume]) -> [MuscleFatigueMap.MuscleWeeklyVolume] {
        var shown = Array(sorted.prefix(4))
        if let weakest = sorted.last, !shown.contains(where: { $0.muscle == weakest.muscle }) { shown.append(weakest) }
        return shown
    }

    /// «Series de trabajo por grupo.» + the neglected muscle when one sits at zero.
    private func muscleNote(_ weakest: MuscleFatigueMap.MuscleWeeklyVolume?) -> String {
        guard let weakest, weakest.setsPerWeek <= 0 else { return String(localized: "Work sets per muscle.") }
        return String(localized: "Work sets per muscle. \(MuscleAtlas.name(weakest.muscle)) has no volume in 30 days.")
    }

    /// The movement-family tint for a muscle key (push=ember · pull=teal · legs=indigo; else ink-ish).
    private func muscleTint(_ muscle: String) -> Color {
        // r21: mapeo PROMOVIDO a CenitDesign (`movementFamilyTint`) — una sola fuente de verdad.
        theme.movementFamilyTint(primaryMuscles: [muscle])
    }

    // MARK: - Your progression (raised / waiting / stalled signals)

    @ViewBuilder
    private var progressionBlock: some View {
        if !progressionRows.isEmpty {
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                // «Ciclos de subida», no «Tu progresión» (FER-148, decisión del dueño): en esta misma
                // pantalla vive «Progreso» (1RM por ejercicio, FER-136) y los dos nombres casi
                // iguales nombraban cosas distintas — este es el plan de subida, aquel el marcador.
                LiquidSectionHeader("Raise cycles")
                ForEach(progressionRows) { row in
                    HStack(spacing: LiquidSpace.s250) {
                        Text(row.name)
                            .font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta900)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: LiquidSpace.s200)
                        switch row.kind {
                        case .raised(let kg):
                            HStack(spacing: LiquidSpace.s100) {
                                CenitIcon.up.image
                                Text(StrengthDisplay.weight(kg, system: system))
                            }
                            .font(LiquidType.filaConteo)
                            .foregroundStyle(LiquidColor.positivo)   // §8.7 valence <24pt
                            .monospacedDigit()
                        case .deferred(let kg):
                            HStack(spacing: LiquidSpace.s100) {
                                Text("…")
                                Text(StrengthDisplay.weight(kg, system: system))
                            }
                            .font(LiquidType.filaConteo)
                            .foregroundStyle(LiquidColor.tinta500)
                            .monospacedDigit()
                        case .stalled:
                            Text("=")
                                .font(LiquidType.filaConteo)
                                .foregroundStyle(LiquidColor.atencionTexto)
                        }
                    }
                    .padding(.vertical, LiquidSpace.s100)
                    .accessibilityElement(children: .combine)
                }
                LiquidPatternBlock(
                    overline: nil,
                    lineas: [String(localized: "What rose, what waits for a day that doesn't hold it back, and what stalled.")],
                    tono: LiquidColor.verdeCarga)
            }
        }
    }

    /// La cabecera «Sessions»: el calendario tipo GitHub (91 días · 13 semanas terminando hoy) seguido
    /// de la lista COMPLETA — ya no una vista previa de 3 con «See all» empujando a una segunda
    /// pantalla (FER-90 · E9, Alcance puntos 1-2). `ForEach(sessions)` sobre un arreglo vacío no dibuja
    /// nada, así que esta misma vista sirve de cabecera-sola cuando `sessions.isEmpty` (el calendario
    /// dibuja sus 91 celdas `.empty`) sin una rama aparte.
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            LiquidSectionHeader("Sessions") {
                Text(verbatim: "\(String(localized: "Effort")) /21")
                    .font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta700)
            }
            TrainingCalendar(
                days: historyCalendarDays, size: .full, summary: historyCalendarSummary,
                onTapDay: { day in
                    // Atajo visual, no el camino accesible (VoiceOver lee `summary`, ver Estados);
                    // toda sesión sigue alcanzable por la fila de la lista de abajo (44+ pt).
                    guard let dest = sessionRouteByDay[day.id] else { return }
                    openWorkoutSession?(dest)
                },
                monthLabels: historyMonthLabels
            )
            .padding(.top, LiquidSpace.s150).padding(.bottom, LiquidSpace.s050)
            // FER-136 / FER-294: misma ventana de 90 días que `historialSubtitle`; misma fila
            // `EntrenarFilaFuerza` que el dialecto Todo (kill-the-class: una sola fila).
            if recentSessions90.isEmpty {
                EmptyView()
            } else {
                EntrenarHistorialLista(filas: recentSessions90.map { AnyView(fuerzaRow($0)) })
            }
        }
    }

    /// Día local (`yyyy-MM-dd`, `Calendar.current` — nunca UTC, ver memoria: fila fantasma UTC vs
    /// local) → clave del calendario y del diccionario de navegación (Alcance punto 2).
    static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// La sesión más reciente por día local — si dos cayeron el mismo día, gana la de `startTs` mayor
    /// (Alcance punto 2). Mismo filtro `endTs != nil` que `computeConstancyMonths` ya usa para no
    /// bucketizar una sesión sin cerrar. Extraída como función pura (no `private`, sin `self`) para que
    /// `WorkoutHistoryLocalDayTests` la pruebe sin instanciar la vista — antes de FER-90 esta reducción
    /// vivía inline en un computed var privado, imposible de probar desde `CenitUnitTests`.
    static func latestSessionByLocalDay(_ sessions: [StrengthSession]) -> [String: StrengthSession] {
        var out: [String: StrengthSession] = [:]
        for s in sessions where s.endTs != nil {
            let key = dayKeyFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(s.startTs)))
            if let existing = out[key], existing.startTs >= s.startTs { continue }
            out[key] = s
        }
        return out
    }

    private var latestSessionByDay: [String: StrengthSession] {
        Self.latestSessionByLocalDay(sessions)
    }

    /// Día local → su ruta, para que el toque del calendario navegue (Alcance punto 2).
    private var sessionRouteByDay: [String: WorkoutSessionRoute] {
        latestSessionByDay.mapValues(route(for:))
    }

    /// 91 días (13 semanas) terminando hoy, más viejo primero — así las 13 filas se leen de arriba
    /// (hace 13 semanas) a abajo (hoy), igual que la lista de sesiones que sigue. Cada día se tiñe con
    /// el MISMO `routineRegions` que `fuerzaRow` ya usa (Alcance punto 2) — sin rutina
    /// clasificable, el mismo respaldo «push», así que un día
    /// se lee igual en el calendario y en la fila de abajo.
    private var historyCalendarDays: [EntrenarCalendarDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let byDay = latestSessionByDay
        return (0..<91).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = Self.dayKeyFormatter.string(from: day)
            guard let s = byDay[key] else { return EntrenarCalendarDay(id: key, state: .empty) }
            if let rid = s.routineId, let region = routineRegions[rid] {
                return EntrenarCalendarDay(id: key, state: .done(region.family))
            }
            return EntrenarCalendarDay(id: key, state: .done(.push))
        }
    }

    /// Qué filas (de 7 días) llevan rótulo de mes: la fila 0 siempre, y cualquier fila cuyo primer día
    /// caiga en un mes distinto al de la fila anterior (Alcance punto 2).
    private var historyMonthLabels: [Int: LocalizedStringKey] {
        let cal = Calendar.current
        let days = historyCalendarDays
        var labels: [Int: LocalizedStringKey] = [:]
        var lastMonth: Int?
        for (rowIndex, start) in stride(from: 0, to: days.count, by: 7).enumerated() {
            guard let date = Self.dayKeyFormatter.date(from: days[start].id) else { continue }
            let month = cal.component(.month, from: date)
            if rowIndex == 0 || month != lastMonth { labels[rowIndex] = Self.monthLabel(month) }
            lastMonth = month
        }
        return labels
    }

    /// Abreviatura del mes en el idioma/calendario actual («jul», «ago») — no pasa por el catálogo de
    /// copy: la resuelve `Calendar.current`, igual que `computeConstancyMonths` en `EntrenarView`.
    private static func monthLabel(_ month: Int) -> LocalizedStringKey {
        LocalizedStringKey(Calendar.current.shortMonthSymbols[(month - 1) % 12].lowercased())
    }

    /// Resumen para VoiceOver: la rejilla es UN solo elemento (Estados → VoiceOver), nunca celda por
    /// celda.
    private var historyCalendarSummary: LocalizedStringKey {
        "\(latestSessionByDay.count) sessions in the last 13 weeks"
    }

    /// «vie 10 jul · 48 min · 4.320 kg» — everything the old card said, in one quiet line.
    private func sessionMeta(_ session: StrengthSession) -> String {
        var parts: [String] = [Date(timeIntervalSince1970: TimeInterval(session.startTs))
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).lowercased()]
        if let mins = StrengthHistoryFormat.durationMinutes(start: session.startTs, end: session.endTs) {
            parts.append(StrengthHistoryFormat.durationText(mins))
        }
        if let vol = volumes[session.id], vol.volumeKg > 0 {
            parts.append(StrengthHistoryFormat.volume(vol.volumeKg, system: system))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Saved tickets entry (thermal receipts peek)

    private var savedTicketsEntry: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidSectionHeader("My saved tickets")
            NavigationLink(value: SavedTicketsRoute()) {
                EntrenarModulo(tono: .neutro) {
                    HStack(spacing: LiquidSpace.s300) {
                        RoundedRectangle(cornerRadius: LiquidRadius.insetTarjeta, style: .continuous)
                            .fill(LiquidColor.tinta7)
                            .frame(width: 38, height: 38)
                            .overlay(
                                Image(systemName: "doc.plaintext")
                                    .font(LiquidType.iconSF(size: 17))
                                    .foregroundStyle(LiquidColor.tinta900)
                            )
                        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                            Text("My saved tickets").font(LiquidType.nivelTitulo).foregroundStyle(LiquidColor.tinta900)
                            Text("\(sessions.count) receipts · today's on top")
                                .font(LiquidType.filaConteo).foregroundStyle(LiquidColor.tinta500)
                        }
                        Spacer(minLength: LiquidSpace.s200)
                        LiquidIcon(.chevron, size: 12, color: LiquidColor.tinta500)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            // Revisión final (g4-a11y): sin agrupamiento, VoiceOver exponía ícono/título/subtítulo/
            // chevron como controles sueltos.
            .accessibilityElement(children: .combine)

            HStack(spacing: LiquidSpace.s250) {
                ForEach(Array(sessions.prefix(3).enumerated()), id: \.element.id) { index, session in
                    MiniTicketView(ticket: TicketMapping.miniTicket(
                        for: session,
                        index: index,
                        routineName: session.routineId.flatMap { routineNames[$0] },
                        volumeKg: volumes[session.id]?.volumeKg ?? 0,
                        system: system
                    ))
                    .frame(width: 110)
                }
            }

            LiquidPatternBlock(
                overline: nil,
                lineas: [String(localized: "Each session saves its receipt. Open them to reprint or share.")],
                tono: LiquidColor.tinta10)
        }
    }

    // MARK: - «Progreso» — por ejercicio (FER-136 · V7 · DECISIÓN DEL DUEÑO: se construye)

    @ViewBuilder private var progressSection: some View {
        if !progressExercises.isEmpty {
            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                LiquidSectionHeader("Progress") {
                    Text("per exercise").font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta700)
                }
                VStack(spacing: .zero) {
                    ForEach(Array(progressExercises.enumerated()), id: \.element.id) { idx, row in
                        progressRow(row, divider: idx != progressExercises.count - 1)
                    }
                }
                .padding(.horizontal, LiquidSpace.handoff14)
                .padding(.vertical, LiquidSpace.s050)
                .liquidGlass(.superficieSolida)
            }
        }
    }

    private func progressRow(_ row: ProgressExerciseRow, divider: Bool) -> some View {
        Button { progressDetailExercise = row.exercise } label: {
            HStack {
                (Text(verbatim: row.name)
                    .font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta900)
                 + Text(verbatim: " · ")
                    .font(LiquidType.filaConteo).foregroundStyle(LiquidColor.tinta500)
                 + Text(oneRMLabel(row.oneRMKg))
                    .font(LiquidType.filaConteo).foregroundStyle(LiquidColor.tinta500))
                Spacer(minLength: LiquidSpace.s200)
                LiquidIcon(.chevron, size: 12, color: LiquidColor.tinta500)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, LiquidSpace.s150)
            .padding(.horizontal, LiquidSpace.s100)
            .frame(minHeight: LiquidControl.hitTarget)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if divider { LiquidCapilar(eje: .horizontal) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(row.name) + Text(verbatim: ", ") + Text(oneRMLabel(row.oneRMKg)))
        .accessibilityHint(Text("Opens the full detail"))
    }

    private func oneRMLabel(_ kg: Double) -> String {
        String(localized: "Est. 1RM \(StrengthDisplay.weight(kg, system: system))")
    }

    // MARK: - «Registrar entreno a mano» (FER-136 · V7 — pie de Historial, mismo `ManualWorkoutSheet»)

    private var manualEntryRow: some View {
        HStack {
            Spacer(minLength: 0)
            LiquidGlassButton(String(localized: "Log a workout by hand"), variant: .solida) {
                showManualEntry = true
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            LiquidCapilar(eje: .horizontal)
            Image(systemName: "clock.arrow.circlepath")
                .font(LiquidType.iconSF(size: 22)).foregroundStyle(LiquidColor.tinta500)
                .accessibilityHidden(true)
            Text("No workouts yet").font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
            Text("When you finish a strength session, it shows up here with its breakdown, volume and effort.")
                .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, LiquidSpace.s400)
    }

    /// «Error de lectura» (Estados, decisión #16 del épico): sustituye la ilustración de «sin datos» —
    /// una lectura fallida de la base no es lo mismo que cero sesiones, y no debe leerse como tal.
    /// `LiquidPatternBlock` con barra `negativo`; a diferencia de un toast no se descarta solo,
    /// porque la condición no cambia sin un reintento (releer la pantalla).
    private var readErrorBanner: some View {
        LiquidPatternBlock(
            overline: nil,
            lineas: [String(localized: "Couldn't read your workout history. Try again.")],
            tono: LiquidColor.negativo)
    }

    // MARK: - Monthly + weekly aggregates (v3 · 1m)

    private struct MonthAggregate { let count: Int; let hours: Double; let volumeKg: Double; let energyKcal: Double? }

    /// One row in «Progreso» (FER-136 · V7): an exercise with logged history, its estimated 1RM.
    private struct ProgressExerciseRow: Identifiable {
        var id: String { exercise.id }
        let exercise: Exercise
        let name: String
        let oneRMKg: Double
    }

    /// One row in «Your progression»: an exercise whose cycle is raised, deferred, or stalled.
    private struct ProgressionRow: Identifiable {
        enum Kind {
            case raised(newKg: Double)
            case deferred(newKg: Double)
            case stalled
        }
        let id: String
        let name: String
        let kind: Kind
    }

    /// This calendar month's totals across finished sessions. kcal sums only sessions that carry it; nil
    /// when none do (so the cell is omitted rather than showing a partial or zero total).
    private var monthAggregate: MonthAggregate { aggregate(forMonthOf: Date()) }

    /// Previous calendar month's totals — same pattern as `monthAggregate`, one month back.
    private var previousMonthAggregate: MonthAggregate {
        let cal = Calendar.current
        let prev = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date.distantPast
        return aggregate(forMonthOf: prev)
    }

    /// Percent volume change this month vs last. nil when either side has no volume (avoids ÷0 / ∞%).
    private var monthVolumeDeltaPercent: Double? {
        let this = monthAggregate.volumeKg
        let prev = previousMonthAggregate.volumeKg
        guard prev > 0, this > 0 else { return nil }
        return (this - prev) / prev * 100
    }

    private func aggregate(forMonthOf reference: Date) -> MonthAggregate {
        let cal = Calendar.current
        let inMonth = sessions.filter {
            cal.isDate(Date(timeIntervalSince1970: TimeInterval($0.startTs)), equalTo: reference, toGranularity: .month)
        }
        var seconds = 0
        var kcal = 0.0
        var hasKcal = false
        var vol = 0.0
        for s in inMonth {
            if let end = s.endTs, end > s.startTs { seconds += end - s.startTs }
            if let k = s.energyKcal { kcal += k; hasKcal = true }
            vol += volumes[s.id]?.volumeKg ?? 0
        }
        return MonthAggregate(count: inMonth.count, hours: Double(seconds) / 3600,
                              volumeKg: vol, energyKcal: hasKcal ? kcal : nil)
    }

    private struct WeekVolume: Identifiable { let id: Int; let volumeKg: Double; let count: Int; let start: Date?; let isCurrent: Bool }

    /// Total volume per week over the last 8 weeks (oldest→newest), Monday-anchored. The last bucket is
    /// the current week (drawn in `dataRecovery`). Bucketing itself delegates to `TrainingWeeks` (FER-171
    /// · Parte B) — same cubeta Historial and the hub now share, instead of two hand-rolled copies.
    private var weeklyVolumes: [WeekVolume] {
        let raw = sessions.compactMap { s -> (ts: Double, volumeKg: Double)? in
            guard s.endTs != nil else { return nil }
            return (ts: Double(s.startTs), volumeKg: volumes[s.id]?.volumeKg ?? 0)
        }
        let buckets = TrainingWeeks.volumeBuckets(sessions: raw, weeks: 8, now: Date(), calendar: Calendar.current)
        return buckets.enumerated().map { i, b in
            WeekVolume(id: i, volumeKg: b.volumeKg, count: b.sessionCount, start: b.weekStart, isCurrent: b.isCurrent)
        }
    }

    // MARK: - Derived

    private func name(for session: StrengthSession) -> String {
        session.routineId.flatMap { routineNames[$0] } ?? String(localized: "Strength workout")
    }

    private func route(for session: StrengthSession) -> WorkoutSessionRoute {
        WorkoutSessionRoute(id: session.id, startTs: session.startTs, endTs: session.endTs,
                            strain: session.strain, avgHr: session.avgHr, routineName: name(for: session))
    }

    // MARK: - Delete / undo (FER-527)

    private func undoDelete(_ d: WorkoutHistoryCoordinator.DeletedSession) {
        Task {
            do {
                try await repo.saveSession(d.session, sets: d.sets)   // re-saving re-derives its PRs
                await load()
                withAnimation { coordinator.pendingUndo = nil }
            } catch {
                // Keep the Undo banner so the user can retry; surface the write failure.
                saveError = true
            }
        }
    }

    private func undoBanner(_ d: WorkoutHistoryCoordinator.DeletedSession) -> some View {
        // FER-285·c: receta → `UndoToast` (pad de la pieza); transition + auto-descarte en el caller.
        UndoToast(message: String(localized: "Workout deleted"),
                  cta: String(localized: "Undo"),
                  theme: theme,
                  action: { undoDelete(d) })
            .transition(LiquidMotion.risingFadeTransition)
            .task(id: d.id) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation { if coordinator.pendingUndo?.id == d.id { coordinator.pendingUndo = nil } }
            }
    }

    private func load() async {
        // Estados → «Error de lectura»: adelantado al frente, la misma llamada que ya usaba la
        // clasificación de rutinas más abajo. nil = fallo persistente de apertura/migración
        // (`Repository.swift`, memoizado en `store`) — las demás llamadas volverían vacías de todos
        // modos, así que no se disparan.
        guard let store = await repo.storeHandle() else {
            readError = true
            loaded = true
            return
        }
        readError = false
        async let s = repo.recentSessions()
        async let r = repo.routines()
        async let v = repo.sessionVolumes()
        // Compact muscle summary: trailing 30 days (not the full year the dedicated screen fetches).
        let cal = Calendar.current
        let muscleSinceTs: Int = {
            guard let d = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: Date())) else { return 0 }
            return Int(d.timeIntervalSince1970)
        }()
        async let muscle = repo.muscleSetEvents(sinceTs: muscleSinceTs)
        // FER-202: la actividad de Apple/manual del dialecto «Todo», en paralelo con lo de fuerza.
        async let w = repo.workoutRows()
        let (sessions, routines, volumes, muscleEvents) = await (s, r, v, muscle)
        self.sessions = sessions
        self.routineNames = Dictionary(routines.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        self.volumes = volumes
        self.muscleEvents = muscleEvents
        self.workoutRows = await w
        // Siembra el rango del dialecto «Todo» al más estrecho con ≥2 entradas, una sola vez.
        if !didSeedRange {
            self.range = defaultTodoRange(UnifiedWorkoutHistory.merge(sessions: sessions, rows: self.workoutRows))
            didSeedRange = true
        }
        self.loaded = true
        // Classify each routine's movement family for the session rows AND the calendar (same
        // resolution as the hub).
        var regions: [String: RoutineRegion] = [:]
        let custom = (try? await store.customExercises()) ?? []
        let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in routines {
            let exs = (try? await store.routineExercises(routineId: r.id)) ?? []
            let perExercise = exs.compactMap { re in
                (ExerciseCatalog.byID(re.exerciseId) ?? customByID[re.exerciseId])?.primaryMuscles
            }
            if let cat = RoutineClassifier.classify(primaryMusclesPerExercise: perExercise) {
                regions[r.id] = cat
            }
        }
        self.routineRegions = regions
        // Progression can take a beat (routines × exercises); paint the rest of the screen first.
        self.progressionRows = await loadProgressionRows()
        // FER-136 · V7: marcas por sesión (acotado a 90 días) y 1RM por ejercicio, tras el resto.
        self.marksBySession = await loadMarksBySession()
        self.progressExercises = await loadProgressExercises(sessions: sessions, customByID: customByID)
    }

    /// Marcas nuevas por sesión, acotado a `recentSessions90` — el mismo patrón acotado que
    /// `EntrenarView.marcaCount`, aquí escalado a la ventana completa de 90 días (no solo 2 filas)
    /// porque el subtítulo de esta pantalla necesita el total.
    private func loadMarksBySession() async -> [String: Int] {
        var marks: [String: Int] = [:]
        for s in recentSessions90 { marks[s.id] = await marcaCount(for: s) }
        return marks
    }

    /// Cuántos PR caen dentro de [inicio, fin] de una sesión — mismo cálculo que
    /// `EntrenarView.marcaCount`, duplicado aquí porque esa función es `private` allá.
    private func marcaCount(for session: StrengthSession) async -> Int {
        let sets = await repo.sessionSets(sessionId: session.id)
        let exerciseIds = Set(sets.map(\.exerciseId))
        let start = session.startTs, end = session.endTs ?? session.startTs
        var count = 0
        for exerciseId in exerciseIds {
            let prs = await repo.personalRecords(exerciseId: exerciseId)
            count += prs.filter { $0.ts >= start && $0.ts <= end }.count
        }
        return count
    }

    /// «Progreso por ejercicio» (FER-136 · V7): los ejercicios con historial REAL (sets logueados en
    /// las sesiones de `recentSessions`), no la composición actual de las rutinas — un ejercicio sigue
    /// apareciendo aquí aunque su rutina se haya editado o borrado después. 1RM reusa
    /// `OneRepMax.dailySparkline(...).last` — el MISMO cálculo que el numeral del héroe de
    /// `ExerciseDetailScreen.progressSection` (no `bestEstimate`, que es el máximo histórico y podía
    /// mostrar un número distinto al tocar la fila y entrar al mismo ejercicio; quisquilloso ronda 4).
    /// Deduplicado por exerciseId, tope 6 filas (mismo tope que `loadProgressionRows`), sesiones más
    /// recientes primero.
    private func loadProgressExercises(sessions: [StrengthSession], customByID: [String: Exercise]) async -> [ProgressExerciseRow] {
        var seen = Set<String>()
        var rows: [ProgressExerciseRow] = []
        outer: for session in sessions {
            let sets = await repo.sessionSets(sessionId: session.id)
            let exerciseIds = sets.map(\.exerciseId).reduce(into: [String]()) { acc, id in
                if !acc.contains(id) { acc.append(id) }
            }
            for exerciseId in exerciseIds {
                guard seen.insert(exerciseId).inserted else { continue }
                let history = await repo.exerciseHistory(exerciseId: exerciseId)
                let usable = history.filter { !$0.optedOut }.map {
                    (day: Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))),
                     weightKg: $0.weightKg, reps: $0.reps)
                }
                guard let oneRM = OneRepMax.dailySparkline(usable).last?.estimatedKg else { continue }
                guard let ex = ExerciseCatalog.byID(exerciseId) ?? customByID[exerciseId] else { continue }
                rows.append(.init(exercise: ex, name: StrengthDisplay.name(ex), oneRMKg: oneRM))
                if rows.count >= 6 { break outer }
            }
        }
        return rows
    }

    /// Exercises with progression enabled (deduped by exerciseId, first routine slot wins — same rule as
    /// ExerciseDetailScreen), classified into raised / deferred / stalled. Cap ~6 rows.
    private func loadProgressionRows() async -> [ProgressionRow] {
        let inventory = await MainActor.run { PlatesStore().inventory }
        // One verdict for the whole list, read before the loop (FER-82). While it is still being
        // computed the section stays empty rather than claiming raises wait on a day nobody has
        // judged yet — `speaks` is the same silence gate the hero uses.
        // Mientras el veredicto no aterriza, la sección no afirma que una subida espera por un día
        // que nadie ha juzgado todavía.
        let advice = repo.trainingAdvice
        guard TrainingRegulation.hasLanded(advice) else { return [] }
        let routines = await repo.routines()
        var seen = Set<String>()
        var slots: [RoutineExercise] = []
        for r in routines {
            let exs = await repo.routineExercises(routineId: r.id)
            for re in exs where re.progressionEnabled {
                if seen.insert(re.exerciseId).inserted { slots.append(re) }
            }
        }
        var rows: [ProgressionRow] = []
        for re in slots {
            let ex = await repo.resolvedExercise(re.exerciseId)
            let seed = await repo.sessionSeed(re: re, exercise: ex, inventory: inventory, advice: advice)
            guard let eval = seed.evaluation else { continue }
            let name = ex.map(StrengthDisplay.name) ?? re.exerciseId
            switch eval.state {
            case .readyToAdvance(let newKg):
                rows.append(.init(id: re.exerciseId, name: name, kind: .raised(newKg: newKg)))
            case .deferred(let newKg):
                rows.append(.init(id: re.exerciseId, name: name, kind: .deferred(newKg: newKg)))
            case .stalled(_), .deloading(_, _):
                rows.append(.init(id: re.exerciseId, name: name, kind: .stalled))
            case .inCycle:
                break
            }
            if rows.count >= 6 { break }
        }
        return rows
    }
}

// MARK: - Detail (per-exercise breakdown of one session)

struct WorkoutSessionDetailScreen: View {
    let route: WorkoutSessionRoute
    /// Opens a routine on the unified «Rutina» editor — «Duplicar como rutina» lands there after saving
    /// (FER-840). Injected by RootTabView (it owns the Entrenar stack); nil in contexts with no stack.
    var openRoutine: ((String) -> Void)? = nil

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var coordinator: WorkoutHistoryCoordinator
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    /// Drives «Duplicar como rutina» — a routine builder pre-filled with this session's exercises (2A).
    /// 2026-07-19: se retiró `RoutineBuilderScreen` — «Duplicar» ahora persiste la rutina y abre el
    /// editor directo, así que ya no hay hoja intermedia que presentar. Queda el flag de «guardando»
    /// para no disparar dos veces con un doble toque.
    @State private var duplicating = false
    /// El fallo al DUPLICAR va aparte de `saveError`: ese banner dice «no se pudo borrar», con copy
    /// propio, y reusarlo aquí le mentiría al usuario sobre qué falló.
    @State private var duplicateError = false
    /// Work sets grouped by exercise, in the order they were performed.
    @State private var groups: [(exerciseId: String, name: String, sets: [SetEntry])] = []
    /// Resolved exercises by id, so tapping a block opens its detail (FER-517).
    @State private var exercisesByID: [String: Exercise] = [:]
    /// The session's routine exercises (when it came from a saved routine), keyed by exerciseId — feeds the
    /// superset identification (v3 · 2A, FER-718). Empty for off-plan/one-off sessions.
    @State private var routineExercises: [RoutineExercise] = []
    /// Stored best-per-metric records per exercise, so a set that IS a personal best is flagged (2A).
    @State private var prsByExercise: [String: [PersonalRecord]] = [:]
    /// The exercise whose detail sheet is open (nil = none).
    @State private var detailExercise: Exercise?
    @State private var volumeKg: Double = 0
    @State private var setCount = 0
    @State private var loaded = false
    /// The full session row (incl. notes/routineId the route doesn't carry) — seeds the edit sheet (FER-556).
    @State private var fullSession: StrengthSession?
    @State private var allSets: [SetEntry] = []
    @State private var routineNames: [String: String] = [:]
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showMoreMenu = false
    @State private var saveError = false
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    // Display prefers the reloaded `fullSession` (so an edit's new date/routine shows at once), falling
    // back to the immutable route while it loads (FER-556).
    private var dispStart: Int { fullSession?.startTs ?? route.startTs }
    private var dispEnd: Int? { fullSession.map(\.endTs) ?? route.endTs }
    private var dispStrain: Double? { fullSession.map(\.strain) ?? route.strain }
    private var dispAvgHr: Int? { fullSession.map(\.avgHr) ?? route.avgHr }
    /// Energy is only on the full row (the route doesn't carry it). nil for a pre-v26 session (FER-715/718).
    private var dispEnergyKcal: Double? { fullSession?.energyKcal }
    private var dispRoutineName: String {
        guard let s = fullSession else { return route.routineName }
        return s.routineId.flatMap { routineNames[$0] } ?? String(localized: "Strength workout")
    }
    private var dispRoutineId: String? { fullSession?.routineId }
    /// La familia de la rutina para el punto de `heading` (Alcance punto 7) — mismo criterio de
    /// clasificación que el punto 5 de `WorkoutEditSheet` (`RoutineClassifier` sobre las primary
    /// muscles), pero sin llamada nueva al store: usa `routineExercises`/`exercisesByID`, que `load()`
    /// ya llena cuando la sesión viene de una rutina guardada. nil cuando la sesión no tiene rutina, o
    /// cuando `routineExercises` llegó vacío por un fallo de lectura benigno (Estados) — no hay nada
    /// que teñir en ninguno de los dos casos.
    private var dispRoutineRegion: RoutineRegion? {
        guard !routineExercises.isEmpty else { return nil }
        let perExercise = routineExercises.compactMap { exercisesByID[$0.exerciseId]?.primaryMuscles }
        return RoutineClassifier.classify(primaryMusclesPerExercise: perExercise)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.seccionAire) {
                heading
                hero
                // Handoff «Progreso C» (FER-952): zones ramp → FC media/máx → supports → note → source,
                // each block on a LiquidCapilar.
                if let zones = WorkoutZones.percents(journalRow?.zonesJSON) {
                    LiquidCapilar(eje: .horizontal)
                    zonesBlock(zones)
                }
                if dispAvgHr != nil || journalRow?.maxHr != nil {
                    LiquidCapilar(eje: .horizontal)
                    heartBlock
                }
                LiquidCapilar(eje: .horizontal)
                secondaries
                if let note = fullSession?.notes, !note.isEmpty {
                    noteBlock(note)
                }
                sourceBadge
                if loaded {
                    // Handoff: exercise blocks breathe compact (16), not the section's 28.
                    VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                        ForEach(Array(groups.enumerated()), id: \.element.exerciseId) { idx, g in
                            LiquidCapilar(eje: .horizontal)
                            exerciseBlock(g, index: idx)
                        }
                    }
                    LiquidCapilar(eje: .horizontal)
                    actions
                }
            }
            .padding(.top, LiquidSpace.topeScroll)
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-199 (Ola 3, épico FER-195): fondo de vidrio El Eje en vez del papel plano — la
        // pantalla llega empujada (`WorkoutSessionRoute`) y conserva su navegación/toolbar del
        // stack ambiente tal cual, sin cabecera propia que sustituir.
        .entrenarHojaFondo(tono: .neutro)
        // FER-969 / X-05a / FER-280·2c: delete failure → `.saveErrorToast`; do NOT pop or seed pendingUndo.
        .saveErrorToast(isPresented: $saveError,
                        message: String(localized: "Couldn't delete the workout. Try again."))
        // «Editar» / «Borrar entrenamiento» — visible from the detail, so deleting no longer needs the
        // list's long-press, and editing a saved session is finally possible (FER-556).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMoreMenu = true } label: {
                    Image(systemName: "ellipsis").foregroundStyle(LiquidColor.tinta900)
                }
                .accessibilityLabel(Text("More options"))
                .liquidMenu(isPresented: $showMoreMenu, items: [
                    // Both actions wait for the full row to load.
                    .init(String(localized: "Edit"), systemImage: "pencil") {
                        if fullSession != nil { showEdit = true }
                    },
                    .init(String(localized: "Delete workout"), systemImage: "trash", isDestructive: true) {
                        if fullSession != nil { showDeleteConfirm = true }
                    }
                ])
            }
        }
        .liquidConfirm(
            isPresented: $showDeleteConfirm,
            title: String(localized: "Delete this workout?"),
            context: String(localized: "HISTORY"),
            message: String(localized: "This removes the workout from your history."),
            actions: [
                .init(String(localized: "Keep workout"), role: .primary),
                .init(String(localized: "Delete workout"), role: .destructive) { performDelete() }
            ]
        )
        .sheet(item: $detailExercise) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { detailExercise = nil }.foregroundStyle(LiquidColor.tinta900)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
            }
            .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .sheet(isPresented: $showEdit) {
            if let s = fullSession {
                WorkoutEditSheet(session: s, sets: allSets) { await onEdited() }
                    .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
            }
        }
        .saveErrorToast(isPresented: $duplicateError)
        .task { await load() }
        .enableInjection()
    }

    // MARK: - Parity actions (v3 · 2A) — «Duplicar como rutina» + «Repetir hoy»

    private var actions: some View {
        VStack(spacing: LiquidSpace.s250) {
            CenitCTAButton("Repeat today") { repeatToday() }
                .disabled(groups.isEmpty)
            CenitCTAButton("Duplicate as routine", kind: .outline) { duplicateAsRoutine() }
                .disabled(groups.isEmpty)
        }
    }

    /// This session's exercises re-based onto builder items for «Duplicar como rutina». Each exercise gets
    /// as many sets as it had work sets in the session, carrying the logged reps/weight as the targets.
    /// Explicit types on the compactMap / RoutineExercise init cut inference cost (FER-981, ~:919).
    private var duplicateSeed: [(re: RoutineExercise, exercise: Exercise)] {
        typealias SeedItem = (re: RoutineExercise, exercise: Exercise)
        typealias Group = (exerciseId: String, name: String, sets: [SetEntry])
        return groups.compactMap { (g: Group) -> SeedItem? in
            guard let ex: Exercise = exercisesByID[g.exerciseId] else { return nil }
            let work: [SetEntry] = g.sets.filter { (s: SetEntry) in s.kind == .work }
            let sets: [RoutineSet] = work.enumerated().map { (i: Int, s: SetEntry) -> RoutineSet in
                RoutineSet(position: i, kind: .work, reps: s.reps, weightKg: s.weightKg)
            }
            let targetSets: Int = max(1, sets.count)
            let targetReps: Int? = work.first?.reps
            let targetWeightKg: Double? = work.first?.weightKg
            let group: Int? = supersetGroup(g.exerciseId)
            let re: RoutineExercise = RoutineExercise(
                routineId: "",
                exerciseId: g.exerciseId,
                position: 0,
                targetSets: targetSets,
                targetReps: targetReps,
                targetWeightKg: targetWeightKg,
                supersetGroup: group,
                sets: sets
            )
            let pair: SeedItem = (re: re, exercise: ex)
            return pair
        }
    }

    /// Crea la rutina con los ejercicios de esta sesión y la abre en «Rutina» para nombrarla y
    /// ajustarla. Mismo camino que «＋ Nueva rutina» del hub (`createRoutineFromHub`): persistir y
    /// empujar el editor, sin una segunda pantalla de prescripción de por medio.
    private func duplicateAsRoutine() {
        guard !duplicating else { return }
        // El guard mira el SEED, no `groups`: el seed descarta los ejercicios que ya no están en el
        // catálogo, así que una sesión con grupos puede producir cero ejercicios. Antes eso sólo abría
        // una hoja cancelable; ahora escribiría una rutina vacía a la base.
        let seed = duplicateSeed
        guard !seed.isEmpty else { return }
        duplicating = true
        let now = Int(Date().timeIntervalSince1970)
        let routine = Routine(name: duplicateName, createdTs: now, updatedTs: now, sortOrder: 0)
        let exercises: [RoutineExercise] = seed.enumerated().map { idx, item in
            var re = item.re
            re.routineId = routine.id
            re.position = idx
            return re
        }
        Task {
            defer { duplicating = false }
            do {
                try await repo.saveRoutine(routine, exercises: exercises)
                openRoutine?(routine.id)
            } catch {
                duplicateError = true
            }
        }
    }

    private var duplicateName: String {
        let defaultName: String = String(localized: "Strength workout")
        let newName: String = String(localized: "New routine")
        let name: String = dispRoutineName
        return name == defaultName ? newName : name
    }

    /// «Repetir hoy» (2A): start a fresh guided session from this session's exercises. Reuses each
    /// exercise's logged sets as its plan (targets + «la última vez» reference).
    private func repeatToday() {
        // The plan comes from each exercise's re.sets (targets); `lastSets` is the «la última vez» prefill,
        // left empty here so the session model seeds straight from the planned sets.
        typealias SeedItem = (re: RoutineExercise, exercise: Exercise)
        let seed: [SeedItem] = duplicateSeed
        let emptyLast: [SetEntry] = []
        let slots: [StrengthSessionModel.PlanSlot] = seed.map { (item: SeedItem) -> StrengthSessionModel.PlanSlot in
            StrengthSessionModel.PlanSlot(re: item.re, exercise: item.exercise, lastSets: emptyLast)
        }
        guard !slots.isEmpty else { return }
        // Fully-typed args so the startStrengthSession call doesn't re-infer through @Observable (FER-981).
        let routineId: String? = dispRoutineId
        let routineName: String = dispRoutineName
        let planSlots: [StrengthSessionModel.PlanSlot] = slots
        model.startStrengthSession(routineId: routineId, routineName: routineName, slots: planSlots)
    }

    /// Delete from the detail: read the sets (so an undo can restore them), delete (the store recomputes
    /// the affected PRs), seed the coordinator's «Undo» + reload, then pop back to the list (FER-556).
    /// FER-969: on failure stay on the detail — no optimistic pop, no pendingUndo.
    private func performDelete() {
        Task {
            let sets = allSets.isEmpty ? await repo.sessionSets(sessionId: route.id) : allSets
            do {
                try await repo.deleteSession(id: route.id)
                let session = fullSession ?? StrengthSession(id: route.id, startTs: route.startTs,
                                                             endTs: route.endTs, strain: route.strain, avgHr: route.avgHr)
                coordinator.pendingUndo = .init(session: session, sets: sets)
                coordinator.bumpReload()
                dismiss()
            } catch {
                saveError = true
            }
        }
    }

    /// After the edit sheet saves: reload the detail in place and bump the list so its row reflects the
    /// new date/routine/volume when popped back to.
    private func onEdited() async {
        await load()
        coordinator.bumpReload()
    }

    /// El punto de familia (Alcance punto 7) cierra el salto de estilo que hoy existe: tocar una fila
    /// teñida de la lista o un día del calendario (puntos 1-2) aterrizaba en un detalle sin ninguna
    /// identidad. El punto vive AL LADO del `LiquidFlowTitle`, no incrustado en el propio texto.
    private var heading: some View {
        HStack(alignment: .center, spacing: LiquidSpace.s200) {
            if let region = dispRoutineRegion { EntrenarFamilyDot(region.tint(theme)) }
            // «Sesión · {fecha}» — el kicker literal de copy.md «Acta» para el acta pasada
            // (FER-136 · V7). NOTA: esta pantalla sigue siendo `WorkoutSessionDetailScreen`, no una
            // reutilización completa de `LiveStrengthSheet.summaryPhase` (esa hoja arma su
            // `StrengthSummary` — comparación, costo, músculos — solo al CERRAR la sesión en vivo;
            // reconstruirla para una sesión pasada es un cambio de fondo, fuera de este carril ligero).
            LiquidFlowTitle(
                kicker: String(localized: "Session · \(StrengthHistoryFormat.dateTime(dispStart))"),
                titulo: dispRoutineName)
        }
    }

    // Effort (strain) is the hero in the effort hue, or duration in ink when the session had no
    // strain — the same rule as the post-session receipt (FER-409), formalized as
    // `SessionEffortDisplay` (FER-226): a session too short for strain but with a captured watch
    // average says so («Avg HR {n} bpm. Too short to score effort.») instead of the flatly wrong
    // «No heart rate this session.» when the watch WAS there.
    @ViewBuilder
    private var hero: some View {
        switch SessionEffortDisplay.resolve(strain: dispStrain, avgHr: dispAvgHr) {
        case .effort(let strain):
            // quisquilloso ronda 4: «/21» — el MISMO sufijo que la fila de Historial pinta para el
            // mismo esfuerzo, para que las dos pantallas lean el número con el mismo formato.
            heroStat("Effort", StrengthHistoryFormat.strain(strain), unit: "/21",
                     color: LiquidColor.ambar, caption: "What this session cost your body.")
        case .durationWithHR(let bpm):
            if let mins = StrengthHistoryFormat.durationMinutes(start: dispStart, end: dispEnd) {
                heroStat("Duration", "\(mins)", unit: "min", color: LiquidColor.tinta900,
                         caption: "Avg HR \(bpm) bpm. Too short to score effort.")
            }
        case .durationOnly:
            if let mins = StrengthHistoryFormat.durationMinutes(start: dispStart, end: dispEnd) {
                heroStat("Duration", "\(mins)", unit: "min",
                         color: LiquidColor.tinta900, caption: "No heart rate this session.")
            }
        }
    }

    private func heroStat(_ label: LocalizedStringKey, _ value: String, unit: String?,
                          color: Color, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            Text(label).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
                Text(value).font(LiquidType.numeralHoja).foregroundStyle(color)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                if let unit { Text(unit).font(LiquidType.numeralHojaUnidad).foregroundStyle(LiquidColor.tinta500) }
            }
            Text(caption).font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    /// The support figures as a REGULAR two-column grid (FER-952: the old auto-fit row read as
    /// off-center) — every cell speaks the heartBlock's grammar: overline on top, Grotesk 19 under.
    private var secondaries: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: LiquidSpace.s400) {
            if volumeKg > 0 {
                supportCell("Volume", StrengthHistoryFormat.volume(volumeKg, system: system))
            }
            supportCell("Sets", "\(setCount)")
            // Duration is the hero when there's no strain → don't repeat it as a secondary.
            if dispStrain != nil,
               let mins = StrengthHistoryFormat.durationMinutes(start: dispStart, end: dispEnd) {
                supportCell("Duration", StrengthHistoryFormat.durationText(mins))
            }
            // Avg HR lives in its own FC block (handoff «Progreso C») — not repeated here. Energy only
            // when the session carries it (FER-715/718): pre-v26 → omitted, never a fabricated 0.
            if let k = dispEnergyKcal { supportCell("Energy", CenitFormat.groupedInt(k)) }
        }
    }

    private func supportCell(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s075) {
            Text(label).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            Text(verbatim: value)
                .font(LiquidType.valorM).foregroundStyle(LiquidColor.tinta900)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - HR zones + heart + note + source (handoff «Progreso C», FER-952)

    /// Time-overlapping journal `WorkoutRow` — zones/max HR live only on the journal (no FK).
    @State private var journalRow: WorkoutRow? = nil

    /// The handoff's continuous warm ramp: one 34pt bar sliced by zone share, Z-labels + % below.
    /// Shares `theme.hrZoneRamp` (1 of 3 distinct HR-zone surfaces — palettes shared, geometry not, FER-908).
    private func zonesBlock(_ percents: [Double]) -> some View {
        let total = max(percents.reduce(0, +), 0.001)
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text("Heart-rate zones").liquidLabel().foregroundStyle(LiquidColor.tinta500)
            GeometryReader { geo in
                HStack(spacing: LiquidSpace.s050) {
                    ForEach(percents.indices, id: \.self) { i in
                        Rectangle().fill(theme.hrZoneRamp[i])
                            .frame(width: max(0, (geo.size.width - 8) * percents[i] / total))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous))
            }
            .frame(height: 34)  // token-exempt(dato): barra de zonas 34 del handoff
            HStack(spacing: .zero) {
                ForEach(percents.indices, id: \.self) { i in
                    VStack(spacing: LiquidSpace.s050) {
                        Text(verbatim: "Z\(i + 1)").font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                        Text(verbatim: "\(Int(percents[i].rounded()))%")
                            .font(LiquidType.valorS).foregroundStyle(LiquidColor.tinta900)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart-rate zones"))
        .accessibilityValue(Text(verbatim: percents.enumerated()
            .map { "Z\($0.offset + 1) \(Int($0.element.rounded()))%" }.joined(separator: ", ")))
    }

    /// «FC MEDIA / FC MÁX» — the wine-hued pair (handoff): Grotesk 19 numerals, unit quiet.
    private var heartBlock: some View {
        HStack(spacing: LiquidSpace.handoff44) {
            if let hr = dispAvgHr {
                VStack(alignment: .leading, spacing: LiquidSpace.s075) {
                    Text("Avg HR").liquidLabel().foregroundStyle(LiquidColor.tinta500)
                    HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
                        Text(verbatim: "\(hr)")
                            .font(LiquidType.valorM).foregroundStyle(LiquidTono.rosa.rotulo)
                        Text(verbatim: "bpm").font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
                    }
                }
            }
            if let maxHr = journalRow?.maxHr {
                VStack(alignment: .leading, spacing: LiquidSpace.s075) {
                    Text("Max HR").liquidLabel().foregroundStyle(LiquidColor.tinta500)
                    HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
                        Text(verbatim: "\(maxHr)")
                            .font(LiquidType.valorM).foregroundStyle(LiquidTono.rosa.rotulo)
                        Text(verbatim: "bpm").font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// «NOTA» — the session's own words, on the sunken block (handoff).
    private func noteBlock(_ note: String) -> some View {
        LiquidPatternBlock(
            overline: String(localized: "Note"),
            lineas: [note],
            tono: LiquidColor.tinta10)
    }

    /// «FUENTE» — measured with the band (journal join) vs estimated; honest, quiet, never a guess.
    private var sourceBadge: some View {
        HStack(spacing: LiquidSpace.s200) {
            Text("Source").liquidLabel().foregroundStyle(LiquidColor.tinta500)
            if journalRow != nil {
                LiquidOrigenBadge(String(localized: "Measured on device"),
                                  tono: LiquidColor.verdePrimario)
            } else {
                LiquidOrigenBadge(String(localized: "Estimated"), tono: nil)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Match this strength session to a journal workout by interval overlap
    /// (`a.start < b.end && b.start < a.end`); closest `startTs` wins.
    private func loadJournalRow() async {
        journalRow = nil
        let sStart = dispStart
        let sEnd = dispEnd ?? dispStart + 1
        let now = Int(Date().timeIntervalSince1970)
        let daysBack = max(3, (now - sStart) / 86_400 + 3)
        let rows = await repo.workoutRows(days: min(daysBack, 90))
        let matches = rows.filter { r in sStart < r.endTs && r.startTs < sEnd }
        journalRow = matches.min(by: { abs($0.startTs - sStart) < abs($1.startTs - sStart) })
    }


    private func exerciseBlock(_ g: (exerciseId: String, name: String, sets: [SetEntry]), index: Int) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            // A superset tag when this exercise shares its routine's `supersetGroup` with an adjacent one
            // in performed order (v3 · 2A). The datum here is anatomical/structural, so it stays in ink.
            if isInSuperset(index) {
                SupersetTag()
                    .padding(.bottom, LiquidSpace.s100)
            }
            exerciseTitle(g)
                .padding(.bottom, LiquidSpace.s150)
            ForEach(Array(g.sets.enumerated()), id: \.element.id) { idx, set in
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
                    Text("Set \(idx + 1)").font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                    if isPRSet(set, exerciseId: g.exerciseId) {
                        LiquidStatePill(valencia: "PR", tono: LiquidColor.atencionTexto)
                            .accessibilityLabel(Text("Personal record"))
                    }
                    Spacer(minLength: LiquidSpace.s200)
                    Text(StrengthHistoryFormat.setLine(set, system: system))
                        .font(LiquidType.valorS).foregroundStyle(LiquidColor.tinta900)
                }
                .padding(.vertical, LiquidSpace.s125)
                .overlay(alignment: .top) {
                    if idx > 0 { LiquidCapilar(eje: .horizontal) }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Whether the exercise at `groups[index]` belongs to a superset — it shares a non-nil routine
    /// `supersetGroup` with the exercise immediately before or after it in performed order.
    private func isInSuperset(_ index: Int) -> Bool {
        guard let g = supersetGroup(groups[index].exerciseId) else { return false }
        let before = index > 0 ? supersetGroup(groups[index - 1].exerciseId) : nil
        let after = index < groups.count - 1 ? supersetGroup(groups[index + 1].exerciseId) : nil
        return before == g || after == g
    }
    private func supersetGroup(_ exerciseId: String) -> Int? {
        routineExercises.first { $0.exerciseId == exerciseId }?.supersetGroup
    }

    /// Whether a work set matches this exercise's stored best (weight or single-set volume) — a personal
    /// record. Compared on the physical values, so an equal-best set still reads as a PR.
    private func isPRSet(_ set: SetEntry, exerciseId: String) -> Bool {
        guard set.kind == .work, let w = set.weightKg, w > 0, let reps = set.reps else { return false }
        let prs = prsByExercise[exerciseId] ?? []
        for pr in prs {
            switch pr.metric {
            case .maxWeight where pr.valueKg == w: return true
            case .maxVolume where pr.valueKg == w && pr.reps == reps: return true
            default: break
            }
        }
        return false
    }

    /// The exercise's name — a tappable row (name + chevron) that opens its detail when the exercise
    /// resolves (FER-517); plain text otherwise, so there's no dead tap on an unknown id.
    @ViewBuilder
    private func exerciseTitle(_ g: (exerciseId: String, name: String, sets: [SetEntry])) -> some View {
        if let ex = exercisesByID[g.exerciseId] {
            Button { detailExercise = ex } label: {
                HStack(spacing: LiquidSpace.s150) {
                    Text(g.name).font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
                    LiquidIcon(.chevron, size: 12, color: LiquidColor.tinta500)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: EntrenarMetrics.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(EntrenarPressStyle())
            // Revisión final (g4-a11y): igual que `progressRow`/`manualEntryRow` — combinar y ocultar
            // el chevron para que VoiceOver anuncie un solo control con un rótulo, no el glifo suelto.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(g.name))
            .accessibilityHint(Text("Opens the exercise"))
        } else {
            Text(g.name).font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
        }
    }

    private func load() async {
        let sets = await repo.sessionSets(sessionId: route.id)
        let exercises = await repo.allExercises()
        let routines = await repo.routines()
        fullSession = await repo.session(id: route.id)
        allSets = sets
        routineNames = Dictionary(routines.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let names = Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        exercisesByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Only work sets, in performed order, grouped by exercise (first-seen order preserved).
        let work = sets.filter { $0.kind == .work }
        var order: [String] = []
        var byExercise: [String: [SetEntry]] = [:]
        for s in work {
            if byExercise[s.exerciseId] == nil { order.append(s.exerciseId) }
            byExercise[s.exerciseId, default: []].append(s)
        }
        groups = order.map { id in
            (exerciseId: id,
             name: names[id].map(StrengthDisplay.titleCase) ?? String(localized: "Exercise"),
             sets: byExercise[id] ?? [])
        }
        volumeKg = work.reduce(0) { acc, s in
            guard let w = s.weightKg, let r = s.reps else { return acc }
            return acc + w * Double(r)
        }
        setCount = work.count

        // Superset identification (2A): the session's routine exercises carry `supersetGroup`. Loaded only
        // when the session links to a saved routine — off-plan/one-off sessions have none.
        if let rid = fullSession?.routineId {
            routineExercises = await repo.routineExercises(routineId: rid)
        }
        // Personal records per exercise, so a set that matches a stored best is flagged (2A).
        var prMap: [String: [PersonalRecord]] = [:]
        for id in order { prMap[id] = await repo.personalRecords(exerciseId: id) }
        prsByExercise = prMap

        // Journal join (zones / max HR live only on the journal — handoff «Progreso C», FER-952).
        await loadJournalRow()

        loaded = true
    }
}

// MARK: - Formatting (shared by list + detail)

enum StrengthHistoryFormat {
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d MMM y · HH:mm")
        return f
    }()

    static func dateTime(_ ts: Int) -> String {
        dateTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// Whole minutes between start and end, or nil when the session has no end time.
    static func durationMinutes(start: Int, end: Int?) -> Int? {
        guard let end, end > start else { return nil }
        return (end - start) / 60
    }

    /// "42 min" or "1 h 12 min".
    static func durationText(_ minutes: Int) -> String {
        if minutes < 60 { return String(localized: "\(minutes) min") }
        return String(localized: "\(minutes / 60) h \(minutes % 60) min")
    }

    /// Reused across every session row's volume label — building a `NumberFormatter` is hundreds of µs,
    /// and `volume(_:system:)` is called once per visible row in the history `LazyVStack` (was allocating
    /// a fresh formatter each time → scroll jank). Same `static let` pattern as `dateTimeFormatter` above.
    private static let volumeFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    /// Total volume in the user's unit, with thousands grouping: "3,325 kg" / "7,330 lb".
    static func volume(_ kg: Double, system: UnitSystem) -> String {
        let value = system == .imperial ? UnitFormatter.kgToPounds(kg) : kg
        let num = volumeFormatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
        return "\(num) \(StrengthDisplay.weightUnit(system))"
    }

    static func strain(_ v: Double) -> String { String(format: "%.1f", v) }

    /// «QUEDABAN» read for a day's captured effort (FER-147) — the Historial tab's per-day subrow.
    /// Same RIR reading as `LiveStrengthSheet.qLabel`: per set `rir = clamp(10 − round(rpe), 0, 4)`,
    /// 4 reads «4+»; the day shows the RANGE across only the sets that captured an RPE. `nil` when no
    /// set of the day captured one — the fragment is omitted entirely, silence over a fabricated zero.
    static func rirRange(rpes: [Double]) -> String? {
        let rirs = rpes.map { min(max(10 - Int($0.rounded()), 0), 4) }
        guard let lo = rirs.min(), let hi = rirs.max() else { return nil }
        func label(_ r: Int) -> String { r >= 4 ? "4+" : "\(r)" }
        return lo == hi ? label(lo) : "\(label(lo))-\(label(hi))"
    }

    /// One performed set as "20 kg × 6", "8 reps" (bodyweight), or a time/distance fallback.
    static func setLine(_ s: SetEntry, system: UnitSystem) -> String {
        if let w = s.weightKg, w > 0, let r = s.reps {
            return "\(StrengthDisplay.weight(w, system: system)) × \(r)"
        }
        if let r = s.reps { return String(localized: "\(r) reps") }
        if let t = s.timeS { return "\(Int(t)) s" }
        if let d = s.distanceM { return "\(Int(d)) m" }
        return "—"
    }
}
#endif
