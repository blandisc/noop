#if os(iOS)
import SwiftUI
import CenitDesign
import StrandTraining
import StrandAnalytics
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - «La Hoja» — F1, la hoja en frío (FER-166)
//
// Sustituye a `RoutineEditorScreen` (FER-839) como la superficie de crear/editar una rutina: crear
// ES editar (una rutina nueva nace vacía en esta misma hoja), autosave sin botón, UNA tarjeta
// abierta a la vez (las demás en receta de una línea), la superserie como tarjeta única sin letras
// A1/A2. `.live` (capturar en sesión) llega en F2 — hoy `Mode` solo tiene `.editing`.
//
// La lógica de negocio (cargar/guardar/deshacer/mutaciones) vive en `RoutineSheetLogic.swift`; la
// captura por teclado en `RoutineSheetKeypad.swift`. Este archivo es el cascarón: estado + `body` +
// navegación/hojas.

/// Pushed onto the Entrenar stack to open «La Hoja» with su origin chrome. Mismo tipo que
/// `RoutineEditorRoute` traía (FER-839/FER-171): un solo `Hashable` para los tres orígenes.
enum RoutineEditorRoute: Hashable {
    /// Today's routine (nil id = resolve today's pick) — CTA «Empezar».
    case today(routineId: String?)
    /// One weekday of the plan (Calendar convention, 1 = Sun … 7 = Sat) — autosave on exit.
    case planDay(weekday: Int)
    /// A routine from «Mis rutinas» — autosave on exit.
    case routine(routineId: String)
}

struct RoutineSheet: View {
    /// El modo de la hoja. `.live` (FER-167 · F2): capturar → descansar → repetir, montada por los
    /// 4 hosts (`RootTabView`/`AppMap`) en vez de `LiveStrengthSheet` directo — ese tipo sigue vivo
    /// para el modo Foco y el acta (ver `HojaSesionViva`), no se borra hasta F5.
    enum Mode { case editing, live }

    let origin: RoutineEditorRoute
    let mode: Mode

    // NO `private`: `RoutineSheetLogic.swift`/`RoutineSheetKeypad.swift`/`HojaCabecera.swift`/etc.
    // son extensiones y vistas HERMANAS en archivos distintos que necesitan leerlas (`private` en
    // Swift es de ARCHIVO, no de tipo).
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var repo: Repository
    @Environment(AppModel.self) var model
    @EnvironmentObject private var mediaCoordinator: MediaDownloadCoordinator
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State var loaded = false
    @State var routine: Routine?
    @State var items: [EditorItem] = []
    /// Every routine, for the .planDay header «Change routine» picker.
    @State var allRoutines: [Routine] = []
    /// Whether the prescription changed since load (drives save-on-exit, «Saved» status, and Undo).
    @State var dirty = false
    /// Load-time copy of `items` — Undo restores this and re-persists so disk matches the reverted state.
    @State var itemsSnapshot: [EditorItem] = []
    @State var restTarget: RestEditTarget? = nil
    /// Which exercise's progression plan is being edited (2c push); nil = none.
    @State var progressionTarget: ProgressionTarget? = nil
    @State var showLibrary = false
    /// nil = the library appends; an index = it replaces that exercise (keeping its sets).
    @State var replaceIndex: Int? = nil
    @State var showDayMenu = false
    @State var menuExerciseIndex: Int? = nil
    /// The exercise whose detail sheet is open (tap the name, parity with the library).
    @State var detailExercise: Exercise? = nil
    /// The plate inventory: progression evaluation + the 2c increment hint.
    @StateObject var plates = PlatesStore()
    @State var saveError = false

    // MARK: Tarjeta abierta única (FER-166)
    //
    // La Hoja muestra UN ejercicio a tinta plena a la vez; el resto pliega en receta. Ronda 2 (R5,
    // QA D8 = Grok G1): por ID de ejercicio, no por índice — un `Int` moría en cuanto borrar/mover
    // reindexaba el arreglo (la tarjeta abierta saltaba a la del vecino). Las tarjetas de
    // superserie no entran en este acordeón — se muestran siempre completas (mock
    // `hoja-pantallas.html` P1 `.ss2`); ver `load()` para por qué ese caso deja `openID` en nil.
    @State var openID: String? = nil
    /// El ejercicio (índice en `items`) pendiente de confirmar «Igualar todas» (ahora en «···», A3).
    @State var equalizeTarget: Int? = nil
    /// R8 (QA D10, adjudicado): una superserie legada con rondas YA desiguales no se aplana en
    /// silencio — la primera edición que dispararía el espejo queda aquí hasta que el confirm
    /// («¿Igualar todas las rondas?») la libere.
    struct PendingMirror { let idx: Int; let si: Int; let field: EditorCell.Field; let value: String }
    @State var pendingMirror: PendingMirror? = nil

    // MARK: Captura con el keypad de la sesión
    /// La celda que se está tecleando; nil = keypad oculto. Ver `RoutineSheetKeypad.swift`.
    @State var activeCell: EditorCell?
    @State var buffer: String = ""
    @State var bufferTyped = false

    /// El set cuyo long-press armó la pastilla «Quitar serie»; nil = ninguno armado.
    @State var armedDeleteSetId: String? = nil
    /// La serie en arrastre dentro de una tarjeta (reordenar series, GAP cerrado del lane).
    @State var dragSet: DragSetState? = nil

    /// El ejercicio cuya nota fija (✎) se está editando — reusa la hoja de nota existente
    /// (`NoteSheet`, capa 3 de `LiveStrengthSheet.swift`).
    @State var noteTarget: LiveStrengthSheet.NoteTarget? = nil
    @State var noteHistory: [ExerciseNote]? = nil

    /// Modo de reordenar EJERCICIOS (bloques completos, incl. superseries) — igual que
    /// `RoutineEditorScreen` (List/onMove, sin zonas).
    @State var reordering = false

    /// The routine hue + group label — refreshed by `refreshTint()` only when the exercise set changes.
    @State var routineTint: Color = .clear
    @State var groupTitle: String = ""

    init(origin: RoutineEditorRoute, mode: Mode = .editing) {
        self.origin = origin
        self.mode = mode
    }

    /// Identifica una celda de la tabla: qué ejercicio, qué serie, qué campo.
    struct EditorCell: Hashable {
        enum Field: Hashable { case weight, repsFloor, repsTop }
        let idx: Int
        let si: Int
        let field: Field
    }

    /// El set (o miembro de superserie) en arrastre. Ronda 2 (R2, QA D2 = Grok G6): llaveado por
    /// `dragID` — la identidad FROZEN al reconocer el gesto (`RoutineSet.id` para una serie,
    /// `RoutineExercise.id` para un miembro), nunca por un índice de posición que un swap a medio
    /// gesto ya movió. `startSi`/`currentSi` son posiciones resueltas contra esa identidad en cada
    /// llamada — nunca un `si` que el caller capturó al construir la fila.
    struct DragSetState: Equatable {
        let idx: Int          // exercise index (-1 = arrastre de MIEMBROS, no de series)
        let dragID: String
        let startSi: Int
        var currentSi: Int
    }

    /// A live guided session locks every editing surface — la prescripción bajo una sesión corriendo
    /// no debe moverse (handoff guard, igual que `RoutineEditorScreen`).
    var locked: Bool {
        guard let session = model.strengthSession else { return false }
        return session.routineId != nil && session.routineId == routine?.id
    }

    /// Inject: los hooks van en la vista NO privada más externa del archivo.
    @ObserveInjection private var inject
    var body: some View {
        switch mode {
        case .editing: editingBody
        case .live: liveBody
        }
    }

    /// FER-167 (F2): la Hoja viva lee `model.strengthSession` directo — nunca se fuerza el
    /// desenvuelto (el mismo cuidado que ya tenían los 4 hosts con `if let session = …`).
    @ViewBuilder private var liveBody: some View {
        if let session = model.strengthSession {
            HojaSesionViva(sheet: self, session: session)
        }
    }

    private var editingBody: some View {
        VStack(spacing: .zero) {
            HojaCabecera.header(sheet: self)
            if loaded, routine != nil {
                editor
            } else {
                Spacer()
                if loaded { emptyFallback }
                Spacer()
            }
        }
        .entrenarHojaFondo(tono: .indigo)
        .onDisappear { if dirty, !isOrphan { persist() } }
        .saveErrorToast(isPresented: $saveError)
        .liquidConfirm(
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
        .keepsSwipeBack {
            guard dirty || isOrphan else { return true }
            back()
            return false
        }
        .safeAreaInset(edge: .bottom, spacing: .zero) { keypadInset }
        .navigationDestination(item: $restTarget) { t in
            RestEditorScreen(
                exerciseName: StrengthDisplay.name(items[t.ei].exercise),
                setNumber: nil,
                current: exerciseRest(t.ei),
                persistsToRoutine: false,
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
        .navigationDestination(item: $progressionTarget) { t in
            let ex = items[t.ei].exercise
            ProgressionSetupScreen(
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
                    guard enabled else { return }
                    for si in items[t.ei].re.sets.indices where items[t.ei].re.sets[si].kind == .work {
                        items[t.ei].re.sets[si].reps = targetReps
                        // R4: este es un camino de escritura directo (no pasa por el binding
                        // gateado) — re-normaliza aquí también, el piso que la progresión acaba
                        // de subir puede alcanzar/pasar un techo ya puesto.
                        items[t.ei].re.sets[si].repsRangeTop = RoutineSet.normalizedRepsRangeTop(
                            reps: items[t.ei].re.sets[si].reps, top: items[t.ei].re.sets[si].repsRangeTop)
                    }
                }
            )
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showLibrary) {
            ExerciseLibraryScreen { picks in addOrReplace(with: picks) }
                .environmentObject(repo).environmentObject(mediaCoordinator).preferredColorScheme(.light)
        }
        .sheet(item: $detailExercise) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { detailExercise = nil }.foregroundStyle(LiquidColor.tinta900)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
            }
            .environmentObject(repo).environmentObject(mediaCoordinator).preferredColorScheme(.light)
        }
        .sheet(item: $noteTarget) { target in
            noteSheet(target)
        }
        .task {
            guard !loaded else { return }
            await load()
            loaded = true
        }
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    // MARK: - Editor (título + meta + tarjetas + CTA fijo)

    /// Confirm de espejo de rondas cuelga del editor (nodo distinto al de «Igualar todas» — FER-174).
    private var editor: some View {
        List {
            HojaCabecera.titleBlock(sheet: self).hojaRow(top: 6, bottom: 6)
            if reordering { reorderList } else { fullList }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LiquidColor.fondoAlto)
        .environment(\.defaultMinListRowHeight, 1)
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        .safeAreaInset(edge: .bottom) { if startsSession { HojaCabecera.ctaBar(sheet: self) } }
        // R8 (QA D10, adjudicado): una superserie legada con rondas ya desiguales pide confirmar
        // antes de que la primera edición las espeje a todas. Mismo patrón que «Igualar todas».
        .liquidConfirm(
            isPresented: Binding(get: { pendingMirror != nil }, set: { if !$0 { pendingMirror = nil } }),
            title: String(localized: "Equalize all rounds?"),
            context: String(localized: "ROUTINE"),
            message: String(localized: "This superset's rounds don't all match yet · this will make every round the same."),
            actions: [
                .init(String(localized: "Keep as is"), role: .primary),
                .init(String(localized: "Equalize"), role: .destructive) { confirmPendingMirror() }
            ]
        )
    }

    @ViewBuilder
    private var fullList: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
            let grouped = RoutineSetEditing.inSuperset(items.map(\.re), idx)
            if grouped {
                if firstOfGroup(idx) { supersetCard(from: idx).hojaRow(top: LiquidSpace.s700, bottom: 0) }
            } else if openID == item.id {
                HojaTarjetaEjercicio(sheet: self, idx: idx).hojaRow(top: idx == 0 ? 6 : LiquidSpace.s700, bottom: 0)
            } else {
                HojaPlegada.row(sheet: self, idx: idx).hojaRow(top: idx == 0 ? 6 : LiquidSpace.s700, bottom: 0)
            }
        }
        if !locked { HojaPlegada.addExercise(sheet: self).hojaRow(top: LiquidSpace.s700, bottom: LiquidSpace.s600) }
    }

    /// El primer índice de un grupo de superserie encabeza la tarjeta única con TODOS sus miembros.
    private func supersetCard(from idx: Int) -> some View {
        var members: [Int] = [idx]
        var i = idx
        let res = items.map(\.re)
        while i + 1 < items.count, RoutineSetEditing.sameGroup(res, i, i + 1) { i += 1; members.append(i) }
        return HojaTarjetaSuperserieCompuesta(sheet: self, members: members)
    }

    // MARK: - Empty fallback (no routine resolved for this origin)

    private var emptyFallback: some View {
        VStack(spacing: LiquidSpace.s250) {
            CenitIcon.sleep.image.font(LiquidType.iconSF(size: 34)).foregroundStyle(LiquidColor.tinta500)
            Text(isPlanDay ? "Rest day" : "No routine").font(LiquidType.displayS).foregroundStyle(LiquidColor.tinta900)
            Text(isPlanDay ? "This day has no routine. Assign one from the weekly plan."
                           : "This routine could not be found.")
                .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            // R14 (QA D12): el fallback de descanso no es un callejón sin salida — la puerta
            // regresa a Tu Plan, de donde SIEMPRE se llega a un `.planDay` vacío, para asignar.
            if isPlanDay {
                EntrenarCapsulaPuerta(String(localized: "ASSIGN")) { dismiss() }
                    .padding(.top, LiquidSpace.s150)
            }
        }
        .padding(.horizontal, LiquidSpace.s800)
    }

    // MARK: - Origin chrome

    var overline: String {
        switch origin {
        case .today:            return String(localized: "Today's routine") + " · " + shortWeekday
        case .planDay(let wd):  return String(localized: "Editing") + " · " + weekdayName(wd)
        case .routine:          return String(localized: "Routine")
        }
    }

    var ctaTitle: String {
        locked ? String(localized: "Resume") : String(localized: "Start")
    }

    /// R3 (QA D3, adjudicado por el director — ronda 2): `.planDay` NO tiene CTA de empezar (mapa
    /// A6). El editor de un día del plan es de PRESCRIPCIÓN, no de captura — «Empezar» desde
    /// ahí competía con el punto de entrada real (Tu Plan / Rutina de hoy). `.today`/`.routine`
    /// conservan el CTA (FER-952 sigue vigente para ellos).
    var startsSession: Bool { routine != nil && !items.isEmpty && !isPlanDay }
    var isPlanDay: Bool { if case .planDay = origin { return true } else { return false } }

    var planWeekday: Int? {
        if case .planDay(let wd) = origin { return wd } else { return nil }
    }

    func weekdayName(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[(weekday - 1) % 7]
    }
    var shortWeekday: String {
        let idx = Calendar.current.component(.weekday, from: Date()) - 1
        return Calendar.current.shortWeekdaySymbols[idx]
    }

    // MARK: - Reorder (bloques de ejercicio, ported de RoutineEditorScreen)

    struct ReorderBlock: Identifiable {
        let items: [EditorItem]
        var id: String { items[0].id }
        var isSuperset: Bool { items.count > 1 }
    }

    var reorderBlocks: [ReorderBlock] {
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
            compactBlock(block)
                .padding(.horizontal, LiquidSpace.s600)
                .padding(.vertical, LiquidSpace.s125)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(.superficieSolida)
                .listRowInsets(EdgeInsets())
                .listRowBackground(LiquidColor.fondoAlto)
                .listRowSeparator(.hidden)
        }
        .onMove(perform: moveBlocks)
        Button { withAnimation(.snappy) { reordering = false } } label: {
            Text("Done reordering").font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta900)
                .frame(maxWidth: .infinity, alignment: .center).frame(minHeight: LiquidControl.hitTarget).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hojaRow(top: LiquidSpace.s300, bottom: 2)
        Text("Drop to place. The sets come back when you let go.")
            .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
            .frame(maxWidth: .infinity, alignment: .center)
            .hojaRow(top: 0, bottom: LiquidSpace.s600)
    }

    private func compactBlock(_ block: ReorderBlock) -> some View {
        HStack(spacing: LiquidSpace.s250) {
            if block.isSuperset {
                // Acento vertical de superserie (dato, no barra): a 2.5 pt el redondeo no se lee.
                Rectangle()
                    .fill(LiquidColor.cian)
                    .frame(width: 2.5)
            }
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                if block.isSuperset { SupersetTag() }
                ForEach(block.items) { item in
                    HStack(spacing: LiquidSpace.s250) {
                        ExerciseThumbView(exercise: item.exercise, side: 28)
                        Text(StrengthDisplay.name(item.exercise))
                            .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta900).lineLimit(1)
                        Spacer(minLength: LiquidSpace.s200)
                        Text(compactSummary(item.re))
                            .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                    }
                }
            }
        }
        .padding(.horizontal, LiquidSpace.s300).padding(.vertical, LiquidSpace.s250)
        .liquidGlass(.superficieSolida)
    }

    private func compactSummary(_ re: RoutineExercise) -> String {
        let work = re.sets.filter { $0.kind == .work }
        var s = String(localized: "\(work.count) sets")
        if let top = work.compactMap(\.weightKg).max(), top > 0 {
            s += " · \(StrengthDisplay.weightNumber(top, system: system)) \(StrengthDisplay.weightUnit(system).lowercased())"
        }
        return s
    }

    /// R9 (Grok G7, ronda 2): un solo drop ya NO cierra el modo — dura hasta «Listo» (a diferencia
    /// del editor viejo, «dropping reopens the tables», que este issue reemplaza a propósito: la
    /// hoja puede pedir varios movimientos seguidos sin reabrir el menú cada vez).
    func moveBlocks(from source: IndexSet, to destination: Int) {
        guard !locked else { return }
        var blocks = reorderBlocks
        blocks.move(fromOffsets: source, toOffset: destination)
        withAnimation(.snappy) {
            items = blocks.flatMap(\.items)
        }
        dirty = true
    }

    // MARK: - Nota fija (✎) — reusa `NoteSheet` (capa 3, LiveStrengthSheets.swift)

    @ViewBuilder
    private func noteSheet(_ target: LiveStrengthSheet.NoteTarget) -> some View {
        if let idx = items.firstIndex(where: { $0.re.id == target.id }) {
            NoteSheet(
                target: target, initialScope: .exercise,
                exerciseText: items[idx].re.note ?? "", setText: "",
                history: noteHistory,
                onSave: { _, text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    items[idx].re.note = trimmed.isEmpty ? nil : trimmed
                    dirty = true
                    noteTarget = nil
                },
                onClose: { noteTarget = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(LiquidColor.fondoAlto)
            .preferredColorScheme(.light)
        }
    }

    func openNote(_ idx: Int) {
        guard items.indices.contains(idx) else { return }
        let re = items[idx].re
        let firstSet = re.sets.first
        noteTarget = LiveStrengthSheet.NoteTarget(
            id: re.id, exerciseId: re.exerciseId, exerciseName: StrengthDisplay.name(items[idx].exercise),
            setId: firstSet?.id ?? "", setNumber: 1)
        noteHistory = nil
        Task {
            guard let store = await repo.storeHandle() else { return }
            let history = (try? await store.exerciseNotes(exerciseId: re.exerciseId, excludingSession: "")) ?? []
            await MainActor.run { noteHistory = history }
        }
    }
}

/// One exercise slot in the editor: the routine slot, its resolved exercise, and the session seeds
/// («la última vez» + an earned progression raise) the .today origin hands to the guided session.
struct EditorItem: Identifiable {
    var re: RoutineExercise
    var exercise: Exercise
    var lastSets: [SetEntry] = []
    var raise: ProgressionPlanner.Raise? = nil
    /// B7 (FER-169): today's progression classification, carried through to the live session's deload
    /// pill — same convention as `raise` (only ever set on the `.today` origin's `willStart` path).
    var progressionState: ProgressionState? = nil
    var id: String { re.id }
}

// Shared list-row chrome: clear background, no system separator, standard screen margin with tunable
// vertical insets — same pattern as the old builder/editor. Named `hojaRow` (not `plainRow`):
// `LiveStrengthSheet.swift` already owns a `private extension View { func plainRow… }` with a
// DIFFERENT signature (ScrollView-era padding, no `List` insets) — `private` scopes its VISIBILITY
// to that file, but Swift still treats the identical signature as a module-wide redeclaration, so
// this needed its own name rather than colliding with a screen this issue must not touch.
extension View {
    func hojaRow(top: CGFloat = 8, bottom: CGFloat = 8) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: LiquidSpace.s600,
                                      bottom: bottom, trailing: LiquidSpace.s600))
    }
}
#endif
