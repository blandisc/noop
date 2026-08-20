#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - «Rutina» — the ONE prescription editor (FER-839, handoff entrenamiento-v4 §2, screens 3a/4a/4b)
//
// Seeing, editing and starting a routine are no longer separate modes: this screen IS the routine, and you
// edit what you see. It generalizes the plan-day editor's table (1o, FER-747) and absorbs the read-only
// «Rutina de hoy» (FER-343) — both screens died here. Only the chrome changes per origin (mock 4a):
//
//   .today    → overline «Rutina de hoy · {día}» + CTA «Empezar»   (landing plan rows, empty-session fallback)
//   .planDay  → overline «Editando · {día}»      (autosave on exit; no explicit Save CTA)
//   .routine  → overline «Rutina»                (autosave on exit; no explicit Save CTA)
//
// The FER-A..G progression wiring survives the merge: the .today origin evaluates `ProgressionPlanner` per
// opted-in slot (history + plates + today's verdict, FER-82) and hands `raise` to the session's PlanSlots, exactly
// like «Rutina de hoy» did. Guards: Notes-style autosave on exit for every origin (dirty → persist on back),
// a «Saved»/Undo chrome driven off the load-time `itemsSnapshot`, and a live session locks every editing
// surface (cells, menus, swipes) — resuming is the only action then.

/// Pushed onto the Entrenar stack to open «Rutina» with its origin chrome. One route type replaces the old
/// `RoutineRoute`/`PlanDayRoute` pair (a distinct `Hashable` per FER-171 still holds: this is one type).
enum RoutineEditorRoute: Hashable {
    /// Today's routine (nil id = resolve today's pick) — CTA «Empezar».
    case today(routineId: String?)
    /// One weekday of the plan (Calendar convention, 1 = Sun … 7 = Sat) — autosave on exit.
    case planDay(weekday: Int)
    /// A routine from «Mis rutinas» — autosave on exit.
    case routine(routineId: String)
}

struct RoutineEditorScreen: View {
    let origin: RoutineEditorRoute

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var mediaCoordinator: MediaDownloadCoordinator
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State private var loaded = false
    @State private var routine: Routine?
    @State private var items: [EditorItem] = []
    /// Every routine, for the .planDay header «Change routine» picker.
    @State private var allRoutines: [Routine] = []
    /// Whether the prescription changed since load (drives save-on-exit, «Saved» status, and Undo).
    @State private var dirty = false
    /// Load-time copy of `items` — Undo restores this and re-persists so disk matches the reverted state.
    @State private var itemsSnapshot: [EditorItem] = []
    @State private var restTarget: RestEditTarget? = nil
    /// Which exercise's progression plan is being edited (2c push); nil = none.
    @State private var progressionTarget: ProgressionTarget? = nil
    @State private var showLibrary = false
    /// nil = the library appends; an index = it replaces that exercise (keeping its sets).
    @State private var replaceIndex: Int? = nil
    // FER-837: which «···» paper menu is open (the day's, or an exercise index).
    @State private var showDayMenu = false
    @State private var menuExerciseIndex: Int? = nil
    /// The exercise whose detail sheet is open (tap the name, parity with the library).
    @State private var detailExercise: Exercise? = nil
    /// The plate inventory: progression evaluation + the 2c increment hint.
    @StateObject private var plates = PlatesStore()
    /// Drag-reorder mode (6a, FER-841): every row compacts to thumb + name + summary and the set tables
    /// fold away; dropping reopens them. Entered by long-pressing an exercise header.
    @State private var reordering = false
    /// The set whose long-press armed the «Delete set» pill (Serie activa's gesture — cards are single
    /// List rows, so swipe can't reach the inner set rows). nil = none armed.
    @State private var armedDeleteSetId: String? = nil
    /// The routine hue + group label — refreshed by `refreshTint()` only when the exercise set changes,
    /// never per render (the ring in every set row reads the tint; see `dominantGroup`).
    @State private var routineTint: Color = .clear
    @State private var groupTitle: String = ""
    @State private var saveError = false

    // MARK: La receta que se pliega sola (FER-88)
    //
    // Tocar la receta colapsada la abre aunque las series sean iguales — un `@State` de «expandido»
    // por ejercicio, independiente del resultado del detector (`RoutineSetEditing.workSetsAreEqual`).
    /// Ids de `RoutineExercise` cuya receta el usuario expandió A MANO (aunque el detector diga que
    /// sus series son iguales). El detector decide el colapso «automático»; esto solo lo anula.
    @State private var expandedExercises: Set<String> = []
    /// El ejercicio (índice en `items`) pendiente de confirmar «Igualar todas». `nil` = ningún aviso
    /// abierto.
    @State private var equalizeTarget: Int? = nil

    // MARK: Captura con el keypad de la sesión (2026-07-19)
    //
    // El editor usaba `TextField` + teclado nativo mientras la sesión activa usa `SessionKeypad`, y el
    // dueño pidió una sola forma de teclear en las dos. Se adopta el keypad, no el teclado: el teclado
    // del sistema se come media pantalla justo donde vive la tabla, y el keypad ya trae el paso ± que
    // esta pantalla también quiere.
    //
    // El keypad NO reimplementa la máquina de estados de la sesión: los bindings `weightText`/`repsText`
    // ya parsean y guardan (incluida la conversión imperial), así que las teclas sólo mueven un buffer
    // de texto y lo empujan por ese binding. Lo que la sesión tiene y aquí no: «copiar la anterior» y la
    // calculadora de discos, que son gestos de captura en vivo, no de prescripción.
    /// La celda que se está tecleando; nil = keypad oculto.
    @State private var activeCell: EditorCell?
    /// El texto a medio teclear. `bufferTyped` distingue «lo que muestra el modelo» de «lo que el
    /// usuario ya empezó a escribir», para que la primera tecla reemplace en vez de concatenar.
    @State private var buffer: String = ""
    @State private var bufferTyped = false

    /// Identifica una celda de la tabla: qué ejercicio, qué serie y cuál de las dos columnas.
    struct EditorCell: Hashable {
        let idx: Int
        let si: Int
        let isWeight: Bool
    }

    /// A live guided session locks every editing surface (cells, menus, swipes) — the prescription under
    /// a running session must not shift (handoff guard).
    private var locked: Bool {
        guard let session = model.strengthSession else { return false }
        // Solo bloquea la rutina QUE la sesión está corriendo (sus slots son un snapshot de esta
        // prescripción); cualquier otra rutina se edita libre aunque haya sesión viva (2026-07-16).
        return session.routineId != nil && session.routineId == routine?.id
    }

    /// Inject: los hooks van en la vista NO privada más externa del archivo (ver `EntrenarView`).
    @ObserveInjection private var inject
    var body: some View {
        VStack(spacing: 0) {
            header
            if loaded, routine != nil {
                editor
            } else {
                Spacer()
                if loaded { emptyFallback }
                Spacer()
            }
        }
        .background(theme.paper.ignoresSafeArea())
        .onDisappear { if dirty, !isOrphan { persist() } }
        // FER-969: el fallo de escritura es un banner honesto, no éxito silencioso. Componente
        // compartido desde 2026-07-19 (era la misma copia en tres pantallas).
        .saveErrorToast(isPresented: $saveError)
        // «Igualar todas» (FER-88): solo se ofrece cuando hay algo que perder (el llamador ya filtra
        // por `!setsAreEqual`), así que el mensaje puede ser concreto sin volverse una advertencia
        // vaga. «Dejarlo como está» reusa la copia ya establecida en el resto del app.
        .instrumentoConfirm(
            isPresented: Binding(get: { equalizeTarget != nil }, set: { if !$0 { equalizeTarget = nil } }),
            title: String(localized: "Equalize all sets?"),
            context: String(localized: "ROUTINE"),
            message: String(localized: "Every work set will match the first one's weight and reps."),
            actions: [
                .init(String(localized: "Keep as is"), role: .primary),
                .init(String(localized: "Equalize"), role: .destructive) {
                    if let idx = equalizeTarget { equalizeAll(idx) }
                }
            ]
        )
        .toolbar(.hidden, for: .navigationBar)
        // FER-988: ocultar la barra mata el gesto de volver; esto lo devuelve. Con cambios sin
        // guardar vetamos el pop y corremos `back()` — el mismo autosave que corre el botón, en vez
        // de sacar la pantalla de la pila y perder el trabajo.
        .keepsSwipeBack {
            guard dirty || isOrphan else { return true }
            back()
            return false
        }
        // El keypad se monta al pie y reemplaza al teclado del sistema; su propia tecla «ocultar»
        // sustituye a la barra «Done» que necesitaba el TextField.
        .safeAreaInset(edge: .bottom, spacing: 0) { keypadInset }
        // 1e as a push: the shared rest editor edits one set's rest with a «this set / all sets» scope.
        // Changes land on the routine with the screen's own save flow, so the routine toggle is off.
        // Rest is per EXERCISE (FER-952): `setNumber: nil` hides the editor's set-scope section and
        // every apply writes the exercise default (clearing any legacy per-set overrides).
        .navigationDestination(item: $restTarget) { t in
            RestEditorScreen(
                theme: theme,
                exerciseName: StrengthDisplay.name(items[t.ei].exercise),
                setNumber: nil,
                current: exerciseRest(t.ei),
                persistsToRoutine: false,
                // Reposo/máx reales (2026-07-16): la hoja dice «reposo 58 + margen 20 = 78» también
                // desde el editor — misma fuente que la sesión (última fila con restingHr + Tanaka).
                restingHR: repo.days.compactMap(\.restingHr).last.map(Double.init),
                maxHR: Double(model.profile.hrMax),
                defaultApplyToAll: true,
                onCancel: { restTarget = nil },
                onApply: { config, _, _ in
                    RoutineSetEditing.applyRest(to: &items[t.ei].re, si: 0, config: config, applyToAll: true)
                    dirty = true
                    restTarget = nil
                }
            )
            .toolbar(.hidden, for: .navigationBar)
        }
        // 2c as a push: the per-exercise progression plan (menu «···» → Progresión, mock 4b).
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
                    dirty = true
                    // El objetivo escribe el PISO (`RoutineSet.reps`) de cada serie de trabajo con
                    // el plan encendido; apagado, la prescripción se queda como el usuario la tecleó.
                    // El TECHO del rango (`repsRangeTop`, FER-94) es opcional y no se toca aquí.
                    guard enabled else { return }
                    for si in items[t.ei].re.sets.indices where items[t.ei].re.sets[si].kind == .work {
                        items[t.ei].re.sets[si].reps = targetReps
                    }
                }
            )
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showLibrary) {
            ExerciseLibraryScreen { picks in addOrReplace(with: picks) }
                .instrumentoTheme(theme).environmentObject(repo).environmentObject(mediaCoordinator).preferredColorScheme(.light)
        }
        // Tap an exercise's name/thumb to read its detail (Progreso + Records) — parity with the library.
        .sheet(item: $detailExercise) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { detailExercise = nil }.foregroundStyle(theme.ink)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
            }
            .instrumentoTheme(theme).environmentObject(repo).environmentObject(mediaCoordinator).preferredColorScheme(.light)
        }
        .task {
            guard !loaded else { return }
            await load()
            loaded = true
        }
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    // MARK: - Origin chrome (mock 4a)

    private var overline: String {
        switch origin {
        case .today:            return String(localized: "Today's routine") + " · " + shortWeekday
        case .planDay(let wd):  return String(localized: "Editing") + " · " + weekdayName(wd)
        case .routine:          return String(localized: "Routine")
        }
    }

    private var ctaTitle: String {
        // Only `.today` still pins a CTA («Empezar»/«Resume»); other origins autosave on exit.
        locked ? String(localized: "Resume") : String(localized: "Empezar")
    }

    // FER-952: EVERY origin can start the session from the editor (the owner's ask) — not just
    // «Rutina de hoy». The CTA hides only while the routine is empty or still loading.
    private var startsSession: Bool { routine != nil && !items.isEmpty }
    private var isPlanDay: Bool { if case .planDay = origin { return true } else { return false } }

    // MARK: - Header (own back + Saved/Undo, over the hidden nav bar)

    private var header: some View {
        HStack(spacing: 8) {
            BackButton(role: .back, theme: theme) { back() }
                .padding(.leading, -2)
            Spacer()
            if dirty {
                Button { undo() } label: {
                    Text(String(localized: "Undo")).font(StrandFont.body).foregroundStyle(theme.ink)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: "Undo")))
            } else if loaded {
                Text(String(localized: "Saved"))
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
    }

    // MARK: - Editor (title + meta + per-exercise tables + pinned CTA)

    private var editor: some View {
        List {
            titleBlock.plainRow(top: 6, bottom: 6)
            if reordering { reorderList } else { fullList }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.paper)
        .environment(\.defaultMinListRowHeight, 1)
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        // Only `.today` starts a guided session; `.routine`/`.planDay` rely on autosave + header status.
        .safeAreaInset(edge: .bottom) { if startsSession { ctaBar } }
    }

    // The editor now speaks the Serie activa's language (FER-952 approved mock): each exercise is a
    // flat «recibo» card (surface + hairline, cardRadius, no shadow) hung off the family rail with its
    // dot; a superset rides a full-strength teal rail with A1/A2 badges. Breathing lives INSIDE each
    // row (r18: List insets would slice the rail into segments).
    @ViewBuilder
    private var fullList: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { idx, _ in
                let grouped = RoutineSetEditing.inSuperset(items.map(\.re), idx)
                if firstOfGroup(idx) {
                    SupersetTag()
                        .padding(.leading, 26)  // token-exempt: gutter del riel (Serie activa)
                        .plainRow(top: CenitMetrics.sectionGap, bottom: 0)
                }
                exerciseCard(idx, grouped: grouped)
                    .plainRow(top: 0, bottom: 0)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !locked {
                            Button { duplicate(idx) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                .tint(theme.inkSecondary)
                        }
                    }
                if isLastOfGroup(idx) {
                    // Handoff (regla 5): the superset's rest rule, spelled out at the decision point.
                    Text("No rest between them: you rest when the round ends.")
                        .font(StrandFont.caption).foregroundStyle(theme.dataHrv)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 26)  // token-exempt: gutter del riel (Serie activa)
                        .plainRow(top: 8)
                }
            }
        // top: 0 — the node's thread must butt the last card's rail seam-to-seam; its breathing
        // lives inside the row (minHeight 44 + gap), not in an inset hole.
        if !locked { addExerciseRow.plainRow(top: 0, bottom: CenitMetrics.screenPadding) }
    }

    /// One exercise as a Serie activa «recibo» card: header row (badge + thumb + name + «···»), the
    /// exercise-level rest chip, the SERIE/KG/REPS table and the twin add-set / warm-up pills.
    private func exerciseCard(_ idx: Int, grouped: Bool) -> some View {
        let item = items[idx]
        // Breathing INSIDE the row so the rail behind never breaks: tight within a superset,
        // sectionGap between unrelated exercises.
        let topGap: CGFloat = grouped
            ? (firstOfGroup(idx) ? 6 : CenitMetrics.space2)
            : (idx == 0 ? 6 : CenitMetrics.sectionGap)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if grouped { supersetBadge(idx) }
                Button { detailExercise = item.exercise } label: {
                    ExerciseThumbView(exercise: item.exercise, side: 40)
                        .overlay(RoundedRectangle(cornerRadius: ExerciseThumbnail.tileCornerRadius(side: 40), style: .continuous)
                            .strokeBorder(theme.movementFamilyTint(primaryMuscles: item.exercise.primaryMuscles), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens the exercise"))
                VStack(alignment: .leading, spacing: 1) {
                    Button { detailExercise = item.exercise } label: {
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
                    .accessibilityHint(Text("Opens the exercise"))
                    if item.re.progressionEnabled {
                        ProgressionChip(re: item.re, system: system, theme: theme,
                                        derivedIncrementKg: PlateMath.minimumIncrement(for: .from(equipment: item.exercise.equipment), inventory: plates.inventory),
                                        disabled: locked, action: { progressionTarget = ProgressionTarget(ei: idx) })
                    }
                }
                Spacer(minLength: 8)
                if !locked { exerciseMenu(idx) }
            }
            RestChip(cfg: exerciseRest(idx)) {
                activeCell = nil; restTarget = RestEditTarget(ei: idx, si: 0)
            }
            .disabled(locked)
            .padding(.top, 9)  // token-exempt: ritmo interno del recibo (Serie activa)
            recetaOrTable(idx)
        }
        .padding(.horizontal, CenitMetrics.receiptPadding).padding(.vertical, CenitMetrics.gap)
        .background(
            RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .fill(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1))
        )
        .padding(.top, topGap)
        // The rail is a BACKGROUND of the whole row (gap included) so segments butt seam-to-seam —
        // family tint (solo) or teal (superset), both at strokeSoft: el riel es estructura, no dato.
        // The FIRST card births the thread AT its dot (Serie activa's «birth-at-the-dot»: nothing
        // above), and the dot anchors to the THUMB's center (card pad 12 + thumb 40/2).
        .background(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill((grouped ? theme.dataHrv
                                   : theme.movementFamilyTint(primaryMuscles: item.exercise.primaryMuscles))
                        .opacity(StrandOpacity.strokeSoft))
                    .frame(width: 2)
                    .offset(x: -20)
                    .padding(.top, idx == 0 ? topGap + 32 : 0)
                if !grouped {
                    // Anillo de papel bajo el punto (Serie activa r18): separa el dot del hilo.
                    ZStack {
                        EntrenarFamilyDot(theme.movementFamilyTint(primaryMuscles: item.exercise.primaryMuscles),
                                          sobreFondo: true)
                    }
                    .offset(x: -26.5, y: topGap + 32 - 7.5)
                }
            }
            .allowsHitTesting(false)
        }
        .padding(.leading, 26)  // token-exempt: gutter del riel (Serie activa)
        .accessibilityAction(named: Text("Reorder exercises")) {
            guard !locked else { return }
            withAnimation(.snappy) { reordering = true }
        }
    }

    // MARK: - La receta que se pliega sola (FER-88)
    //
    // `RoutineSetEditing.workSetsAreEqual` decide: series de trabajo iguales → una `RecetaLine`
    // («3 series · 80 kg × 8») con chevron; distintas → los renglones de siempre, coronados por el
    // aviso «series distintas» + «Igualar todas». Tocar la receta colapsada la abre aunque el
    // detector diga que ya es una línea (`expandedExercises`, independiente del resultado).

    private func setsAreEqual(_ idx: Int) -> Bool {
        RoutineSetEditing.workSetsAreEqual(items[idx].re.sets)
    }

    private func isExpanded(_ idx: Int) -> Bool {
        expandedExercises.contains(items[idx].re.id) || !setsAreEqual(idx)
    }

    @ViewBuilder
    private func recetaOrTable(_ idx: Int) -> some View {
        if isExpanded(idx) {
            if !setsAreEqual(idx) {
                EqualizeSetsPrompt(
                    family: theme.movementFamily(primaryMuscles: items[idx].exercise.primaryMuscles),
                    disabled: locked
                ) { equalizeTarget = idx }
                .padding(.top, CenitMetrics.gap)
            }
            columnHeader(items[idx].exercise.type).padding(.top, CenitMetrics.gap)
            ForEach(Array(items[idx].re.sets.enumerated()), id: \.element.id) { si, _ in
                interactiveSetRow(idx: idx, si: si)
            }
            if !locked { addRowPills(idx).padding(.top, 10) }
        } else {
            RecetaLine(recetaSummary(idx)) {
                withAnimation(.snappy) { _ = expandedExercises.insert(items[idx].re.id) }
            }
            .padding(.top, CenitMetrics.gap)
        }
    }

    /// «3 series · 80 kg × 8» — solo cuenta series de TRABAJO (el calentamiento no forma parte de la
    /// receta plegada, igual que no cuenta para el detector). Formato de hoy (solo piso): compondrá
    /// «piso-techo» con `RoutineSet.repsRangeLabel` en cuanto E13/FER-94 aterrice `repsRangeTop` en
    /// `Training.swift` — bloqueado hoy (ver nota gemela en `RoutineSetEditing.workSetsAreEqual`).
    private func recetaSummary(_ idx: Int) -> String {
        let work = items[idx].re.sets.filter { $0.kind == .work }
        let type = items[idx].exercise.type
        var parts: [String] = []
        if showsWeight(type), let w = work.first?.weightKg, w > 0 {
            parts.append("\(StrengthDisplay.weightNumber(w, system: system)) \(StrengthDisplay.weightUnit(system).lowercased())")
        }
        if showsReps(type), let r = work.first?.reps {
            parts.append("\(r)")
        }
        let count = String(localized: "\(work.count) sets")
        guard !parts.isEmpty else { return count }
        return count + " · " + parts.joined(separator: " × ")
    }

    /// «Igualar todas» (tras confirmar): cada serie de TRABAJO toma el peso y las reps de la
    /// PRIMERA. El calentamiento no se toca — nunca formó parte de la comparación.
    private func equalizeAll(_ idx: Int) {
        guard let first = items[idx].re.sets.first(where: { $0.kind == .work }) else { return }
        for si in items[idx].re.sets.indices where items[idx].re.sets[si].kind == .work {
            items[idx].re.sets[si].weightKg = first.weightKg
            items[idx].re.sets[si].reps = first.reps
        }
        dirty = true
    }

    /// «A1 / A2» — the superset member badge, the Serie activa's grammar for the pair.
    private func supersetBadge(_ idx: Int) -> some View {
        let res = items.map(\.re)
        var groups: [Int] = []
        for re in res.prefix(idx + 1) {
            if let g = re.supersetGroup, !groups.contains(g) { groups.append(g) }
        }
        var n = 1
        var i = idx
        while i > 0, RoutineSetEditing.sameGroup(res, i - 1, i) { n += 1; i -= 1 }
        let letter = String(UnicodeScalar(64 + min(max(groups.count, 1), 26))!)
        // Decisión Fer (auditoría G): UNA sola forma para A1/A2 en todo el flujo — el círculo teal
        // relleno de la Serie activa (antes aquí era chip de texto sobre tinte).
        return Circle().fill(theme.dataHrv)
            .frame(width: 17, height: 17)
            .overlay {
                Text(verbatim: "\(letter)\(n)").font(StrandFont.footnote).fontWeight(.semibold)
                    .foregroundStyle(theme.paper)
            }
    }

    /// A set row + the Serie activa's armed-delete gesture: long-press lifts the row and offers the
    /// «Delete set» pill; any other tap disarms. (Cards are single List rows, so swipe can't reach.)
    private func interactiveSetRow(idx: Int, si: Int) -> some View {
        let setId = items[idx].re.sets[si].id
        return setRow(idx: idx, si: si)
            .overlay(alignment: .trailing) {
                if armedDeleteSetId == setId {
                    // La pastilla es el componente compartido; el ACTO es de esta pantalla (borra la
                    // prescripción, no una captura).
                    DeleteSetPill {
                        withAnimation(.snappy) { armedDeleteSetId = nil; deleteSet(idx: idx, si: si) }
                    }
                }
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                // m2 (auditoría): la última serie no se arma — borrarla dejaría la tabla vacía;
                // para quitar el ejercicio completo está el menú «…».
                guard !locked, items[idx].re.sets.count > 1 else { return }
                withAnimation(StrandMotion.gentle) { armedDeleteSetId = setId }
            })
            .simultaneousGesture(TapGesture().onEnded {
                if armedDeleteSetId != nil {
                    withAnimation(StrandMotion.gentle) { armedDeleteSetId = nil }
                }
            })
            .accessibilityActions {
                if !locked, items[idx].re.sets.count > 1 {
                    Button("Delete set") { deleteSet(idx: idx, si: si) }
                }
            }
    }

    // MARK: - Drag reorder (6a, FER-841)
    //
    // A block = one exercise, or a whole superset (consecutive exercises sharing `supersetGroup`) —
    // a superset always travels as ONE unit; breaking it stays a «···» action, never a drag side effect.
    // `List.onMove` does the dragging (the lifted preview mirrors the compact card row); dropping
    // flattens the blocks back into `items`, marks the prescription dirty (order persists in `position`
    // through the screen's normal save flow) and leaves the mode so the tables reopen.

    private struct ReorderBlock: Identifiable {
        let items: [EditorItem]
        var id: String { items[0].id }
        var isSuperset: Bool { items.count > 1 }
    }

    private var reorderBlocks: [ReorderBlock] {
        var blocks: [ReorderBlock] = []
        var i = 0
        while i < items.count {
            var run = [items[i]]
            if let g = items[i].re.supersetGroup {
                while i + 1 < items.count, items[i + 1].re.supersetGroup == g {
                    i += 1; run.append(items[i])
                }
            }
            blocks.append(ReorderBlock(items: run))
            i += 1
        }
        return blocks
    }

    @ViewBuilder
    private var reorderList: some View {
        ForEach(reorderBlocks) { block in
            // The List's reorder LIFT snapshots only the row CONTENT (not `listRowBackground`) and floats
            // it over a system-white platter — so a clear-margin row shows white around the card while
            // dragging (FER-847 round 2). Fix: make the content itself full-bleed OPAQUE paper — the
            // screen margin moves INSIDE as padding and a paper fill spans edge-to-edge — so the lifted
            // snapshot is paper, hiding the platter. Resting rows look identical (List bg is paper too).
            compactBlock(block)
                .padding(.horizontal, CenitMetrics.screenPadding)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.paper)
                .listRowInsets(EdgeInsets())
                .listRowBackground(theme.paper)
                .listRowSeparator(.hidden)
        }
        .onMove(perform: moveBlocks)
        Button { withAnimation(.snappy) { reordering = false } } label: {
            Text("Done reordering").font(StrandFont.subhead).foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .center).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .plainRow(top: CenitMetrics.gap, bottom: 2)
        Text("Drop to place. The sets come back when you let go.")
            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .plainRow(top: 0, bottom: CenitMetrics.screenPadding)
    }

    /// The compact card the drag lifts: thumb + name + «N sets · top kg» per exercise; a superset adds
    /// its teal left bar + «superset» overline and moves as one card.
    private func compactBlock(_ block: ReorderBlock) -> some View {
        HStack(spacing: 10) {
            if block.isSuperset {
                Capsule().fill(theme.dataHrv).frame(width: 2.5)
            }
            VStack(alignment: .leading, spacing: 8) {
                if block.isSuperset {
                    SupersetTag()
                }
                ForEach(block.items) { item in
                    HStack(spacing: 10) {
                        ExerciseThumbView(exercise: item.exercise, side: 28)
                        Text(StrengthDisplay.name(item.exercise))
                            .font(StrandFont.subhead).foregroundStyle(theme.ink).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(compactSummary(item.re))
                            .font(InstrumentoType.groteskNumber(12, weight: .regular)).foregroundStyle(theme.inkTertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(theme.paper, in: RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous).strokeBorder(theme.hairlineStrong))
    }

    /// «3 sets · 90 kg» — work sets + the top work weight (weight omitted when none is set).
    private func compactSummary(_ re: RoutineExercise) -> String {
        let work = re.sets.filter { $0.kind == .work }
        var s = String(localized: "\(work.count) sets")
        if let top = work.compactMap(\.weightKg).max(), top > 0 {
            s += " · \(StrengthDisplay.weightNumber(top, system: system)) \(StrengthDisplay.weightUnit(system).lowercased())"
        }
        return s
    }

    private func moveBlocks(from source: IndexSet, to destination: Int) {
        var blocks = reorderBlocks
        blocks.move(fromOffsets: source, toOffset: destination)
        withAnimation(.snappy) {
            items = blocks.flatMap(\.items)
            reordering = false        // dropping reopens the tables (6a)
        }
        dirty = true
    }

    /// One-step move from the «···» menu (r20 parity with the live session). A plain item swap —
    /// crossing a superset boundary just leaves/joins visually; groups are preserved by their ids.
    private func moveExercise(_ idx: Int, to dest: Int) {
        guard items.indices.contains(idx), items.indices.contains(dest) else { return }
        withAnimation(.snappy) { items.swapAt(idx, dest) }
        dirty = true
    }

    /// Overline per origin, the routine title underlined 2 px ink, and the dotted meta line.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(overline).groteskOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                if isPlanDay { dayMenu }
            }
            // Serie activa look (FER-952 approved mock): no ink seal — the session header is bare.
            // The title is EDITABLE here (unified flow: a routine born from the library arrives as
            // «New routine» and gets its real name right where you see it). Autosaves like the rest.
            TextField("Routine name", text: Binding(
                get: { routine?.name ?? "" },
                set: { routine?.name = $0; dirty = true }
            ))
            .font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking)
            .foregroundStyle(theme.ink)
            .disabled(locked)
            .frame(maxWidth: .infinity, alignment: .leading)
            if locked {
                // El porqué del bloqueo, dicho — controles muertos sin explicación era la queja
                // «no me deja editar» (canvas 2026-07-16).
                Text("Session in progress · finish it to edit")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .padding(.top, 2)
            }
            metaLine
        }
    }

    /// The dotted meta: routine hue dot + «{group} · N exercises · M sets · ~T min».
    private var metaLine: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                EntrenarFamilyDot(routineTint)
                Text(groupTitle).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Text(String(localized: "\(items.count) exercises")).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            Text(String(localized: "\(totalSets) sets")).font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
            Text(String(localized: "~\(estimatedMinutes) min")).font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
        }
        .padding(.top, 2)
    }

    /// .planDay header «···»: assign/clear the day (choque 9 — «conserva lo callado»).
    private var dayMenu: some View {
        Button { showDayMenu = true } label: {
            Image(systemName: "ellipsis").font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(theme.inkTertiary).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Day options"))
        .disabled(locked)
        .paperMenu(isPresented: $showDayMenu, items: [
            .init(String(localized: "Change routine"), systemImage: "arrow.left.arrow.right",
                  children: allRoutines.map { r in
                      PaperMenuItem(r.name, systemImage: r.id == routine?.id ? "checkmark" : nil) { changeRoutine(to: r) }
                  }),
            .init(String(localized: "Mark as rest day"), systemImage: "moon.zzz", isDestructive: true) { markRest() }
        ])
    }

    // MARK: - Exercise header (thumb + tappable name + «···» + column header)

    /// The «···» menu, FINAL order (mock 4b). No «move» — reordering is drag-only (FER-841);
    /// «Duplicate» lives in the swipe.
    private func exerciseMenu(_ idx: Int) -> some View {
        Button { menuExerciseIndex = idx } label: {
            Image(systemName: "ellipsis").font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(theme.inkTertiary).frame(width: 30, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .paperMenu(
            isPresented: Binding(get: { menuExerciseIndex == idx },
                                 set: { if !$0 { menuExerciseIndex = nil } }),
            items: exerciseMenuItems(idx)
        )
    }

    /// The «···» rows, FINAL order (mock 4b). The active progression plan rides as the row's
    /// subtitle («+2,5 kg cada 2 ✓»).
    private func exerciseMenuItems(_ idx: Int) -> [PaperMenuItem] {
        let item = items[idx]
        var rows: [PaperMenuItem] = []
        // «Add warm-up» is a visible button next to «Add set» when none exist yet — not in the menu.
        // Handoff hierarchy (FER-952): order → structure → plan → destructive. «Reorder» leads (where
        // the handoff's Subir/Bajar sit — FER-841/847 replaced them with drag).
        let res = items.map(\.re)
        // Serie activa r20: Move up / Move down lead the menu; «Reorder» keeps the drag-mode door.
        if idx > 0 {
            rows.append(.init(String(localized: "Move up"), systemImage: "arrow.up") { moveExercise(idx, to: idx - 1) })
        }
        if idx < items.count - 1 {
            rows.append(.init(String(localized: "Move down"), systemImage: "arrow.down") { moveExercise(idx, to: idx + 1) })
        }
        rows.append(.init(String(localized: "Reorder exercises"), systemImage: "line.3.horizontal") {
            activeCell = nil
            withAnimation(.snappy) { reordering = true }
        })
        if idx < items.count - 1 && !RoutineSetEditing.sameGroup(res, idx, idx + 1) {
            rows.append(.init(String(localized: "Superset with next"), systemImage: "link") { supersetWithNext(idx) })
        }
        if RoutineSetEditing.inSuperset(res, idx) {
            rows.append(.init(String(localized: "Undo superset"), systemImage: "link") { breakSuperset(idx) })
        }
        if item.exercise.type == .weightReps {
            rows.append(.init(String(localized: "Progression"),
                              subtitle: item.re.progressionEnabled
                                  ? ProgressionChip.summary(item.re, system: system,
                                                            derived: PlateMath.minimumIncrement(for: .from(equipment: item.exercise.equipment), inventory: plates.inventory))
                                  : nil,
                              systemImage: "chart.line.uptrend.xyaxis") {
                progressionTarget = ProgressionTarget(ei: idx)
            })
        }
        rows.append(.init(String(localized: "Change exercise"), systemImage: "arrow.triangle.2.circlepath") {
            replaceIndex = idx; showLibrary = true
        })
        rows.append(.init(String(localized: "Remove from routine"), systemImage: "trash", isDestructive: true) {
            deleteExercise(idx)
        })
        return rows
    }

    @ViewBuilder
    private func columnHeader(_ type: ExerciseType) -> some View {
        // Handoff (FER-952, rest-per-exercise): SERIE / KG / REPS only — rest left the table for the
        // exercise-level chip under the name.
        HStack(spacing: 8) {
            Text("SET").groteskOverline(small: true).foregroundStyle(theme.inkTertiary)
                .lineLimit(1).minimumScaleFactor(0.7).frame(width: 40, alignment: .center)
            if showsWeight(type) {
                Text(StrengthDisplay.weightUnit(system)).groteskOverline(small: true).foregroundStyle(theme.inkTertiary).frame(width: 74)
            }
            if showsReps(type) {
                // Handoff: KG and REPS weigh the same — twin 74pt columns.
                Text("Reps").groteskOverline(small: true).foregroundStyle(theme.inkTertiary).frame(width: 74)
            }
            Spacer(minLength: 0)
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
                cellField(EditorCell(idx: idx, si: si, isWeight: true), width: 74)
            }
            if showsReps(type) {
                cellField(EditorCell(idx: idx, si: si, isWeight: false), width: 74)
            }
            // «la última vez» — grey history from session seed, one entry per set position (r26:
            // measured datum → Grotesk tabular, the live session's previous-cell voice).
            if let prev = lastSetHistoryLabel(idx: idx, si: si, type: type) {
                Text(prev)
                    .font(InstrumentoType.groteskNumber(12, weight: .regular))
                    .foregroundStyle(theme.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    /// Dim «80×7» from the seeded last session for this set index, when history exists.
    private func lastSetHistoryLabel(idx: Int, si: Int, type: ExerciseType) -> String? {
        guard items[idx].lastSets.indices.contains(si) else { return nil }
        let last = items[idx].lastSets[si]
        var parts: [String] = []
        if showsWeight(type), let w = last.weightKg {
            parts.append(StrengthDisplay.weightNumber(w, system: system))
        }
        if showsReps(type), let r = last.reps {
            parts.append("\(r)")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "×")
    }

    /// The set numeral, plain ink («C» for a warm-up set, in tertiary). Handoff: no ring — a tinted
    /// ring per row is color-as-decoration (§8.4); the hue lives only in the meta dot and rails.
    ///
    /// **Diverge a propósito de `LiveStrengthSheet.badge`, y eso NO es deuda** (decisión Fer
    /// 2026-07-19). Las dos pantallas citaban §8.4 y llegaban a lo opuesto: aquí sin anillo, allá con
    /// anillo ámbar. Gana cada una en su contexto — planeando el martes en el sillón «cuál serie es» se
    /// lee tranquilo y el anillo sería cromo; con la barra en la mano «cuál voy» tiene que gritar y el
    /// anillo hace trabajo real. La auditoría de duplicación marcó esto como divergencia a corregir; se
    /// revisó y se decidió CONSERVARLA. Si alguien vuelve a «unificarlas», que sea con este párrafo
    /// enfrente. Nota gemela en `LiveStrengthSheet.badge`.
    private func numeralRing(idx: Int, si: Int) -> some View {
        let warmup = items[idx].re.sets[si].kind == .warmup
        return Text(RoutineSetEditing.setLabel(items[idx].re, si))
            .font(InstrumentoType.grotesk(13, weight: .semibold)).monospacedDigit()
            .foregroundStyle(warmup ? theme.inkTertiary : theme.ink)
    }

    /// La celda de captura — **papel pautado, no caja** (decisión Fer 2026-07-19).
    ///
    /// Traía relleno `surface` + borde `insetRadius`, mientras la sesión activa usa una regla inferior.
    /// Dos gramáticas de formulario para el mismo dato. Gana la regla, por dos razones: DESIGN.md §8.7
    /// reserva las cápsulas y cajas a las ACCIONES —una caja alrededor de un número es cromo— y la
    /// metáfora del DNA es papel, donde un dato se escribe sobre una raya, no dentro de un cuadro. De
    /// paso la celda sube de 32 a 44 pt: la caja estaba por debajo del mínimo de la HIG.
    ///
    /// El MECANISMO sigue siendo el teclado nativo aquí y `SessionKeypad` allá, y eso es diferencia real
    /// de producto: en sesión hacen falta ± por discos y no perder media pantalla bajo el teclado. Ver
    /// la nota al pie del PR sobre por qué el keypad no se portó en este paso.
    private func cellField(_ cell: EditorCell, width: CGFloat) -> some View {
        let shown = activeCell == cell && bufferTyped ? buffer : binding(for: cell).wrappedValue
        return Button {
            guard !locked else { return }
            withAnimation(.snappy(duration: 0.22)) { activeCell = cell }
            buffer = binding(for: cell).wrappedValue
            bufferTyped = false
        } label: {
            HStack(spacing: 1) {
                Text(shown.isEmpty ? "—" : shown)
                    .foregroundStyle(shown.isEmpty ? theme.inkTertiary : theme.ink)
                if activeCell == cell {
                    Rectangle().fill(theme.ink).frame(width: 2, height: 18)   // caret
                        .opacity(0.9)   // token-exempt: opacidad de caret >0.70, igual que la sesión
                }
            }
            .setCellChrome(width: width, focused: activeCell == cell)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    // MARK: - Keypad (la misma captura que la sesión activa)

    private func binding(for cell: EditorCell) -> Binding<String> {
        cell.isWeight ? weightText(idx: cell.idx, si: cell.si) : repsText(idx: cell.idx, si: cell.si)
    }

    /// El keypad montado al pie, atado a la celda activa. Se oculta solo cuando no hay celda.
    @ViewBuilder private var keypadInset: some View {
        if let cell = activeCell {
            SessionKeypad(
                theme: theme,
                stepLabel: cell.isWeight ? (system == .imperial ? "±5" : "±2,5") : "±1",
                // «Copiar la anterior» y los discos son gestos de captura EN VIVO: aquí se prescribe,
                // y la app no debe inventarle al usuario un valor que no tecleó.
                canCopyPrevious: false,
                platesEnabled: false,
                onDigit: { keypadInput(String($0)) },
                onComma: { keypadComma() },
                onBackspace: { keypadBackspace() },
                onNext: { focusNextCell(after: cell) },
                onCopyPrevious: {},
                onStep: { keypadStep(cell) },
                // «Copiar arriba» (FER-88): atajo del EDITOR, no lectura de historial — copia la
                // MISMA columna de la serie anterior DENTRO de esta misma prescripción. Oculto en la
                // primera serie de un ejercicio: no hay «arriba» de qué copiar.
                onCopyAbove: cell.si > 0 ? { copyAbove(cell) } : nil,
                onHide: { withAnimation(.snappy(duration: 0.22)) { activeCell = nil } }
            )
            .transition(.move(edge: .bottom))
        }
    }

    private func keypadInput(_ digit: String) {
        if !bufferTyped { buffer = ""; bufferTyped = true }
        buffer += digit
        commitBuffer()
    }

    private func keypadComma() {
        guard let cell = activeCell, cell.isWeight else { return }   // las reps son enteras
        if !bufferTyped { buffer = "0"; bufferTyped = true }
        if !buffer.contains(",") && !buffer.contains(".") { buffer += "," }
        commitBuffer()
    }

    private func keypadBackspace() {
        if !bufferTyped { buffer = ""; bufferTyped = true }
        if !buffer.isEmpty { buffer.removeLast() }
        commitBuffer()
    }

    /// El ± suma un paso sobre el valor del MODELO (no sobre el buffer a medias), y resincroniza.
    private func keypadStep(_ cell: EditorCell) {
        guard items.indices.contains(cell.idx), items[cell.idx].re.sets.indices.contains(cell.si) else { return }
        if cell.isWeight {
            let stepKg = system == .imperial ? 5 * 0.45359237 : 2.5
            let current = items[cell.idx].re.sets[cell.si].weightKg ?? 0
            items[cell.idx].re.sets[cell.si].weightKg = current + stepKg
        } else {
            items[cell.idx].re.sets[cell.si].reps = (items[cell.idx].re.sets[cell.si].reps ?? 0) + 1
        }
        dirty = true
        buffer = binding(for: cell).wrappedValue
        bufferTyped = false
    }

    /// Empuja el buffer por el binding, que ya parsea y guarda (incluida la conversión imperial).
    private func commitBuffer() {
        guard let cell = activeCell else { return }
        binding(for: cell).wrappedValue = buffer
    }

    /// «Copiar arriba» (FER-88): copia el valor YA FORMATEADO de la MISMA columna de la serie
    /// anterior dentro del MISMO ejercicio — reusa `binding(for:)`, así que hereda su parseo/formato
    /// (incluida la conversión imperial) sin duplicarlo. Un valor vacío arriba no copia nada.
    private func copyAbove(_ cell: EditorCell) {
        guard cell.si > 0, items.indices.contains(cell.idx),
              items[cell.idx].re.sets.indices.contains(cell.si - 1) else { return }
        let above = EditorCell(idx: cell.idx, si: cell.si - 1, isWeight: cell.isWeight)
        let value = binding(for: above).wrappedValue
        guard !value.isEmpty else { return }
        withAnimation(.snappy(duration: 0.22)) { activeCell = cell }
        buffer = value
        bufferTyped = true
        commitBuffer()
    }

    /// Peso → reps de la misma serie → peso de la siguiente. Al final del ejercicio, cierra el keypad.
    private func focusNextCell(after cell: EditorCell) {
        guard items.indices.contains(cell.idx) else { activeCell = nil; return }
        let type = items[cell.idx].exercise.type
        let next: EditorCell? = {
            if cell.isWeight, showsReps(type) { return EditorCell(idx: cell.idx, si: cell.si, isWeight: false) }
            let nextSi = cell.si + 1
            guard items[cell.idx].re.sets.indices.contains(nextSi) else { return nil }
            return EditorCell(idx: cell.idx, si: nextSi, isWeight: showsWeight(type))
        }()
        withAnimation(.snappy(duration: 0.22)) { activeCell = next }
        if let next { buffer = binding(for: next).wrappedValue; bufferTyped = false }
    }

    /// The card's closing row (approved mock): TWIN pills of equal weight — «＋ Agregar serie» on the
    /// sunken gray, «🔥 Calentamiento» spelled in the ember voice (it deserved to be seen). The warm-up
    /// pill hides once the ramp exists.
    /// The card's closing row: the shared `SetActionPills` — twin full-width pills, ink primary + ember
    /// outline warm-up, identical to the live session's (see the component for the decisions behind it).
    private func addRowPills(_ idx: Int) -> some View {
        SetActionPills(showWarmup: !hasWarmups(idx), theme: theme,
                       addSet: { addSet(idx) }, addWarmup: { addWarmupRamp(idx) })
    }

    /// The rail's terminal node — the shared `AddExerciseNode` (see the component for the decisions
    /// behind it). The thread takes the last card's tint so the line arrives in its own color.
    private var addExerciseRow: some View {
        let lastTint: Color = {
            guard let last = items.last else { return theme.dataStrain }
            let res = items.map(\.re)
            if RoutineSetEditing.inSuperset(res, items.count - 1) { return theme.dataHrv }
            return theme.movementFamilyTint(primaryMuscles: last.exercise.primaryMuscles)
        }()
        return AddExerciseNode(theme: theme, threadTint: lastTint) {
            replaceIndex = nil
            showLibrary = true
        }
    }

    // MARK: - Pinned CTA (`.today` only — start / resume the guided session)

    private var ctaBar: some View {
        // Handoff: «Empezar» is the EMBER door with the play glyph — the one saturated CTA on screen.
        Button { start() } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))  // token-exempt: glifo del CTA
                Text(ctaTitle).font(InstrumentoType.grotesk(15, weight: .bold)).tracking(0.3)
            }
            .foregroundStyle(theme.paper).frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(theme.dataStrain, in: RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(theme.paper)
    }

    // MARK: - Empty fallback (no routine resolved for this origin)

    private var emptyFallback: some View {
        VStack(spacing: 10) {
            StrandIcon.sleep.image.font(StrandFont.glyph(.empty)).foregroundStyle(theme.inkTertiary)
            Text(isPlanDay ? "Rest day" : "No routine").font(StrandFont.title2).foregroundStyle(theme.ink)
            Text(isPlanDay ? "This day has no routine. Assign one from the weekly plan."
                           : "This routine could not be found.")
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
        renumber(idx)
        dirty = true
    }

    private func renumber(_ idx: Int) {
        for i in items[idx].re.sets.indices { items[idx].re.sets[i].position = i }
    }

    private func hasWarmups(_ idx: Int) -> Bool { items[idx].re.sets.contains { $0.kind == .warmup } }

    /// «Agregar calentamiento» (mock 4b): a 40·60·80 % ramp. Writes `warmupPercents` (the model's canonical
    /// record) AND materializes the three «C» rows the table shows, seeded from the top work weight when known.
    private func addWarmupRamp(_ idx: Int) {
        let ramp = RoutineSetEditing.warmupFactors
        items[idx].re.warmupPercents = ramp
        let top = items[idx].re.sets.first { $0.kind == .work }?.weightKg
        let usesReps = showsReps(items[idx].exercise.type)
        let rows = ramp.enumerated().map { i, pct in
            RoutineSet(position: i, kind: .warmup, reps: usesReps ? RoutineSetEditing.warmupReps : nil,
                       weightKg: top.map { $0 * pct })
        }
        withAnimation(.snappy) { items[idx].re.sets.insert(contentsOf: rows, at: 0) }
        renumber(idx)
        dirty = true
    }

    private func deleteExercise(_ idx: Int) {
        withAnimation(.snappy) { _ = items.remove(at: idx) }
        refreshTint()
        dirty = true
    }

    private func duplicate(_ idx: Int) {
        let src = items[idx]
        var copy = src.re
        copy.id = UUID().uuidString
        copy.position = idx + 1
        copy.supersetGroup = nil                                   // a duplicate stands on its own
        copy.sets = src.re.sets.map { s in var n = s; n.id = UUID().uuidString; return n }
        withAnimation(.snappy) { items.insert(EditorItem(re: copy, exercise: src.exercise), at: idx + 1) }
        refreshTint()
        dirty = true
    }

    /// Replace an exercise (keeping its sets) or append new ones, from the library (1f).
    private func addOrReplace(with picks: [Exercise]) {
        guard let first = picks.first else { return }
        if let i = replaceIndex, items.indices.contains(i) {
            items[i].exercise = first
            items[i].re.exerciseId = first.id
        } else {
            for pick in picks {
                let usesReps = pick.type == .weightReps || pick.type == .bodyweight
                let reps: Int? = usesReps ? 8 : nil
                let sets = (0..<3).map { RoutineSet(position: $0, kind: .work, reps: reps, weightKg: nil) }
                let re = RoutineExercise(routineId: routine?.id ?? "", exerciseId: pick.id, position: items.count,
                                         targetSets: 3, targetReps: reps, targetWeightKg: nil, sets: sets)
                items.append(EditorItem(re: re, exercise: pick))
            }
        }
        replaceIndex = nil
        refreshTint()
        dirty = true
    }

    // MARK: - Superset helpers (shared grouping logic lives in RoutineSetEditing)

    /// First member of a superset group (shows the «Superset» overline above it).
    private func firstOfGroup(_ i: Int) -> Bool { RoutineSetEditing.firstOfGroup(items.map(\.re), i) }

    /// The exercise-level rest rule (FER-952: rest is per exercise now — the model's set overrides
    /// remain readable, but every edit writes the exercise default and clears them).
    private func exerciseRest(_ idx: Int) -> RestConfig {
        let re = items[idx].re
        return RestConfig(mode: re.restMode, seconds: re.restSeconds,
                          hrReference: re.hrRestReference, hrValue: re.hrRestValue)
    }

    /// The last member of a superset group — anchors the handoff's rest-rule caption.
    private func isLastOfGroup(_ i: Int) -> Bool {
        let res = items.map(\.re)
        guard RoutineSetEditing.inSuperset(res, i) else { return false }
        return i == items.count - 1 || !RoutineSetEditing.sameGroup(res, i, i + 1)
    }

    private func supersetWithNext(_ i: Int) {
        var res = items.map(\.re)
        RoutineSetEditing.supersetWithNext(&res, i)
        for (j, re) in res.enumerated() { items[j].re = re }
        dirty = true
    }
    private func breakSuperset(_ i: Int) {
        var res = items.map(\.re)
        RoutineSetEditing.breakSuperset(&res, i)
        for (j, re) in res.enumerated() { items[j].re = re }
        dirty = true
    }

    // MARK: - Meta computations

    private var totalSets: Int { items.reduce(0) { $0 + $1.re.sets.filter { $0.kind == .work }.count } }

    /// A transparent time estimate (display only): ~40 s of work per work set plus its resolved rest.
    private var estimatedMinutes: Int {
        var seconds = 0
        for item in items {
            for si in item.re.sets.indices where item.re.sets[si].kind == .work {
                seconds += 40 + RoutineSetEditing.effectiveRest(item.re, si).seconds
            }
        }
        return max(1, Int((Double(seconds) / 60).rounded()))
    }

    /// The routine's dominant coarse group — deterministic tie-break (FER-750). Recomputed by
    /// `refreshTint()` only when the exercise set changes (load / add / replace / delete / duplicate):
    /// the tint colors every set-row ring, and re-tallying on each keystroke was wasted work.
    private func refreshTint() {
        var tally: [MuscleGroup: Int] = [:]
        for item in items {
            for m in item.exercise.primaryMuscles { if let g = MuscleGroup.of(m) { tally[g, default: 0] += 1 } }
        }
        var best: MuscleGroup?
        var bestCount = 0
        for g in MuscleGroup.allCases where (tally[g] ?? 0) > bestCount {
            best = g; bestCount = tally[g] ?? 0
        }
        routineTint = best?.tint(theme) ?? theme.inkTertiary
        groupTitle = best?.title ?? String(localized: "Mixed")
    }

    private func weekdayName(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[(weekday - 1) % 7]   // index 0 = Sunday … 6 = Saturday
    }
    private var shortWeekday: String {
        let idx = Calendar.current.component(.weekday, from: Date()) - 1
        return Calendar.current.shortWeekdaySymbols[idx]
    }

    // MARK: - Day assignment (.planDay «···»)

    /// The .planDay weekday; nil for the other origins (whose UI never shows the day menu).
    private var planWeekday: Int? {
        if case .planDay(let wd) = origin { return wd } else { return nil }
    }

    private func changeRoutine(to r: Routine) {
        guard let wd = planWeekday else { return }
        Task {
            guard let store = await repo.storeHandle() else { saveError = true; return }
            do {
                try await store.setRoutineSchedule(weekday: wd, routineId: r.id)
                await load()
            } catch {
                saveError = true
            }
        }
    }

    private func markRest() {
        guard let wd = planWeekday else { return }
        Task {
            // C2: salir por «descanso» también autosalva (contrato Notas). FER-969: stay on failure.
            if dirty, !(await persistNow()) { return }
            guard let store = await repo.storeHandle() else { saveError = true; return }
            do {
                try await store.clearRoutineSchedule(weekday: wd)
            } catch {
                // QA D1: a failed clear must not dismiss as if the day were marked rest.
                saveError = true
                return
            }
            dismiss()
        }
    }

    // MARK: - Navigation (Notes-style: every origin autosaves on leave when dirty)

    private func back() {
        if isOrphan {
            Task { await discardOrphan(); dismiss() }
            return
        }
        guard dirty else { dismiss(); return }
        // Guardar ANTES de salir: el hub recarga en el onAppear del pop y leería el plan viejo si el
        // save siguiera en vuelo (bug «agregué ejercicios y no se ven», canvas 2026-07-16).
        // FER-969: on failure stay put, keep dirty, surface the banner — never pretend success.
        Task {
            if await persistNow() { dismiss() }
        }
    }

    /// C1 (decisión Fer): quedó vacía y con el nombre de fábrica — el flujo de creación la persiste
    /// antes de abrir el editor, así que salir así dejaría una «Nueva rutina» fantasma en la lista.
    private var isOrphan: Bool {
        guard let r = routine else { return false }
        return items.isEmpty && r.name == String(localized: "New routine")
    }

    private func discardOrphan() async {
        guard let r = routine else { return }
        try? await repo.deleteRoutine(id: r.id)
    }

    /// Restore the load-time prescription, clear dirty, and re-persist so disk matches the undo.
    /// Stays on the editor — does not dismiss.
    private func undo() {
        items = itemsSnapshot
        dirty = false
        refreshTint()
        persist()
    }

    // MARK: - Start the guided session (progression wiring, FER-E/G parity with «Rutina de hoy»)

    private func start() {
        // A session already running → just resume it (don't rebuild over logged sets).
        if model.strengthSession != nil { model.resumeStrengthSession(); return }
        guard let r = routine else { return }
        if dirty { persist() }   // «se guardan al salir o empezar»
        let slots = items.map {
            StrengthSessionModel.PlanSlot(re: $0.re, exercise: $0.exercise, lastSets: $0.lastSets,
                                          raise: $0.raise)
        }
        model.startStrengthSession(routineId: r.id, routineName: r.name, slots: slots)
    }

    // MARK: - Load + save

    /// El último paso de «la línea de la subida» (decisión #4 del épico): pasa la evaluación de
    /// `ProgressionPlanner`/`sessionSeed` a `EditorItem.raise` SIN condicionarla por `advice` — la
    /// aplicación (`waiting == false`) contra la retención (`waiting == true`) ya la decidió
    /// `ProgressionPlanner`, y este punto no debe re-filtrarla una segunda vez. Extraída de `load()`
    /// como función nombrada y `static` (pura, sin `Repository`) para que
    /// `RoutineEditorScreenRaiseTests` truene si alguien envuelve esta línea en
    /// `if TrainingRegulation.allowsRaise(advice) { … } else { nil }`/`explainsHeldRaise(advice)`.
    static func raiseForEditorItem(
        _ evaluation: (state: ProgressionState, raise: ProgressionPlanner.Raise?)?
    ) -> ProgressionPlanner.Raise? {
        evaluation?.raise
    }

    private func load() async {
        guard let store = await repo.storeHandle() else {
            routine = nil; items = []; itemsSnapshot = []; dirty = false; return
        }
        allRoutines = (try? await store.routines()) ?? []
        let target: Routine?
        switch origin {
        case .today(let id):
            // Today's pick: the given id, else today's SCHEDULED routine via the canonical resolver —
            // no arbitrary-routine fallback (the FER-531 contract); an unplanned day shows the empty state.
            let sched = (try? await store.routineSchedule()) ?? []
            let split = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
            let rid = id ?? WeeklySplit.todayRoutineId(
                split: split, todayWeekday: Calendar.current.component(.weekday, from: Date()))
            target = rid.flatMap { r in allRoutines.first { $0.id == r } }
        case .planDay(let wd):
            let sched = (try? await store.routineSchedule()) ?? []
            let rid = sched.first { $0.weekday == wd }?.routineId
            target = rid.flatMap { r in allRoutines.first { $0.id == r } }
        case .routine(let id):
            target = allRoutines.first { $0.id == id }
        }
        guard let r = target else {
            routine = nil; items = []; itemsSnapshot = []; dirty = false; return
        }
        routine = r
        let res = await repo.routineExercises(routineId: r.id)
        let all = await repo.allExercises()
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // FER-E: «la última vez» + progression, via the ONE `sessionSeed` implementation the landing
        // prefetch also calls (sub-épico 1 wiring). Only the .today origin can start a session, so the
        // save-only origins skip that per-exercise history I/O entirely.
        let inventory = plates.inventory
        // One verdict for the whole table (FER-82): read before the loop, never inside it, so the
        // session can't open with some exercises raised and others held.
        let advice = repo.trainingAdvice
        // El gate se calcula con datos LOCALES, no con `startsSession`: esa propiedad mira `items`,
        // que en este punto sigue vacío (se asigna al final del método), así que el editor cargaba
        // SIEMPRE por la rama sin semilla y la sesión que arrancaba desde aquí no llevaba ni «la
        // última vez» ni la subida. La fila «↑ X te espera» del héroe entra justo por esta puerta.
        let willStart = !isPlanDay && !res.isEmpty
        var built: [EditorItem] = []
        for re in res {
            guard let ex = byId[re.exerciseId] else { continue }
            if willStart {
                let seed = await repo.sessionSeed(re: re, exercise: ex, inventory: inventory, advice: advice)
                built.append(EditorItem(re: re, exercise: ex, lastSets: seed.lastSets,
                                        raise: Self.raiseForEditorItem(seed.evaluation)))
            } else {
                built.append(EditorItem(re: re, exercise: ex))
            }
        }
        items = built
        refreshTint()
        dirty = false
        // Capture the post-load prescription for Undo (value copy of Equatable structs).
        itemsSnapshot = items
    }

    private func persist() {
        Task { await persistNow() }
    }

    /// Returns `true` when the routine was written. On failure keeps `dirty` and shows the banner.
    @discardableResult
    private func persistNow() async -> Bool {
        guard let r = routine else { return true }
        let now = Int(Date().timeIntervalSince1970)
        let updated = Routine(id: r.id, name: r.name, tag: r.tag, folderId: r.folderId,
                              createdTs: r.createdTs, updatedTs: now, sortOrder: r.sortOrder)
        let exercises = items.enumerated().map { idx, item -> RoutineExercise in
            var re = item.re; re.position = idx; re.routineId = r.id; return re
        }
        do {
            try await repo.saveRoutine(updated, exercises: exercises)
            return true
        } catch {
            saveError = true
            return false
        }
    }
}

/// One exercise slot in the editor: the routine slot, its resolved exercise, and the session seeds
/// («la última vez» + an earned progression raise) the .today origin hands to the guided session.
private struct EditorItem: Identifiable {
    var re: RoutineExercise
    var exercise: Exercise
    var lastSets: [SetEntry] = []
    var raise: ProgressionPlanner.Raise? = nil
    var id: String { re.id }
}

// Shared list-row chrome: clear background, no system separator, standard screen margin with tunable
// vertical insets — a plain List that reproduces «Instrumento» spacing (same pattern as the builder).
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
