#if os(iOS)
import SwiftUI
import CenitDesign
import StrandTraining
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - «Tu Plan» — the single home for the week + the routines (FER-890, was FER-533 + FER-534)
//
// One surface, one scroll: the week (assign a routine to each weekday, or leave it rest) up top, the
// weekly volume by group under it, then ALL your routines listed flat below — create / import / templates /
// library / folders. It fuses the old two pushed screens (the weekly plan editor and «Mis rutinas») into
// «Tu Plan», reached from the Entrenar landing's single «Editar».
//
// Folders — decision A (degrade): routines list FLAT here (no folder headers in the body). Folder
// management (create / rename / move / delete) stays alive behind the «Plantillas · Importar · Carpetas»
// menu and each routine's «···», and `folderId` and the folder model are untouched.
//
// «Liquid Glass · El Eje» (FER-292): an editor has no measured datum, so there is NO saturated color for
// the week — assigned-vs-rest contrast is ink WEIGHT (`tinta900` vs `tinta500`), hierarchy by paper cards
// + capillary `tinta10`, no card-in-card. Routines carry their per-routine tint only on the family dot /
// glyph / mini-bars (via `RoutineClassifier`). Tapping a day opens a `liquidMenu` of routines (grouped by
// folder) plus «Rest» to clear it; tapping a routine edits it.

struct WeeklyPlanEditorView: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the volume bars' one-shot grow-from-base entry (handoff `recGrow`).
    @State private var volumeBarsGrown = false

    /// Push «Rutina» — the prescription editor for a routine tapped in the list (FER-839/840).
    var openRoutine: (String) -> Void
    /// Push the exercise library (the single home for browsing exercises).
    var openLibrary: () -> Void
    /// Push «Editar día del plan» (1o, FER-747) for a weekday that has a routine. Tapping an assigned day
    /// edits its prescription; an empty day still opens the assign menu (decision A). Change-routine and
    /// mark-rest for an assigned day live inside 1o's header «···».
    var openDay: (Int) -> Void = { _ in }

    @State private var loaded = false
    @State private var routines: [Routine] = []
    @State private var folders: [RoutineFolder] = []
    /// The split as `weekday → routineId` (Calendar weekday convention, 1 = Sun … 7 = Sat).
    @State private var schedule: [Int: String] = [:]
    // FER-837: which weekday's assign paper menu is open.
    @State private var assignMenuDay: Int? = nil
    /// Planned work-set volume per routine, split into the four coarse groups (mock 1b's mini-bars +
    /// weekly footer). Built from each routine's exercises' primary muscles. `[routineId: [group: sets]]`.
    @State private var routineVolume: [String: [MuscleGroup: Int]] = [:]

    // Routines-management state (folded in from «Mis rutinas», FER-890).
    @State private var exerciseCounts: [String: Int] = [:]
    /// Top primary muscles per routine (Spanish labels) for the one-line metadata.
    @State private var routineMuscles: [String: [String]] = [:]
    /// The classified region per routine (`RoutineClassifier`, FER-775) — the SINGLE source of a routine's
    /// hue, shared with `EntrenarView`, so the same routine never changes color between screens.
    @State private var routineRegion: [String: RoutineRegion] = [:]
    /// Days since each routine was last trained (`routineId → whole days`), for the «hace N d» column.
    @State private var lastTrainedDays: [String: Int] = [:]
    @State private var showBuilder = false
    @State private var showTemplates = false
    @State private var showImport = false
    @State private var swipedRoutineId: String? = nil
    @State private var pendingUndo: DeletedRoutine? = nil
    @State private var pendingFolderUndo: DeletedFolder? = nil
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var pendingMove: Routine? = nil
    @State private var renameFolder: RoutineFolder? = nil
    @State private var renameText = ""
    // FER-837: which «···» paper menu is open (routine id / the tools row).
    @State private var menuRoutineId: String? = nil
    /// Secciones colapsadas (carpetas como subdivisiones, decisión Fer 2026-07-16).
    @State private var collapsedFolders: Set<String> = []
    /// El «···» de banda abierto (renombrar / borrar carpeta).
    @State private var menuFolderId: String? = nil
    /// La sección sobre la que flota ahora mismo una rutina arrastrada (id de carpeta, o
    /// `unfiledSectionID` para «Sueltas»). Solo pinta el resalte: el movimiento lo hace `accept`.
    @State private var dropTarget: String? = nil
    @State private var saveError = false
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject
    private static let unfiledSectionID = "unfiled-section"

    /// Monday-first display order in the Calendar weekday convention (2 = Mon … 1 = Sun).
    private let weekdays = [2, 3, 4, 5, 6, 7, 1]
    private var today: Int { Calendar.current.component(.weekday, from: Date()) }
    private var assignedCount: Int { schedule.count }

    /// Routines not shown under any listed folder — `folderId == nil`, or a folder that no longer exists.
    /// (Used only by the assign menu's grouping; the body lists routines flat — decision A.)
    private var unfiledRoutines: [Routine] {
        let ids = Set(folders.map(\.id))
        return routines.filter { $0.folderId == nil || !ids.contains($0.folderId!) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                header
                if loaded {
                    if !routines.isEmpty {
                        weekSection
                        volumeFooter
                    }
                    routinesSection
                }
            }
            .padding(.top, EntrenarMetrics.heroKickerTop)
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-200 (Anillo 2, épico FER-195): fondo de vidrio El Eje — la pantalla llega empujada
        // (WeeklyPlanMap / AppMap) y conserva su navegación/toolbar del stack ambiente tal cual.
        .entrenarHojaFondo(tono: .neutro)
        .overlay(alignment: .bottom) {
            if let d = pendingUndo { undoBanner(d) }
            else if let fd = pendingFolderUndo { folderUndoBanner(fd) }
        }
        // FER-969 / FER-280·2c: write failure → `.saveErrorToast` (misma receta, un solo dialecto).
        .saveErrorToast(isPresented: $saveError)
        .sensoryFeedback(trigger: pendingUndo?.id) { _, new in
            new != nil ? LiquidHaptica.advertencia.feedback : nil
        }
        // FER-952 unified flow: «＋ Nueva rutina» PUSHES the library as a screen (no sheet); adding
        // the picks creates the routine on the spot and lands on the unified «Rutina» editor.
        .navigationDestination(isPresented: $showBuilder) {
            ExerciseLibraryScreen(createFlow: true) { picks in createRoutine(picks) }
        }
        .sheet(isPresented: $showTemplates) {
            StarterTemplatesSheet { await load() }
                .environmentObject(repo).preferredColorScheme(.light)
        }
        .sheet(isPresented: $showImport) {
            WorkoutImportView { await load() }
                .environmentObject(repo).preferredColorScheme(.light)
        }
        .liquidInput(
            isPresented: Binding(get: { showNewFolder },
                                 set: { if !$0 { showNewFolder = false; newFolderName = ""; pendingMove = nil } }),
            text: $newFolderName,
            title: String(localized: "New folder"),
            context: String(localized: "YOUR PLAN"),
            placeholder: String(localized: "Folder name"),
            cta: String(localized: "Create")
        ) { _ in createFolder() }
        .liquidInput(
            isPresented: Binding(get: { renameFolder != nil },
                                 set: { if !$0 { renameFolder = nil } }),
            text: $renameText,
            title: String(localized: "Rename folder"),
            context: String(localized: "YOUR PLAN"),
            placeholder: String(localized: "Folder name"),
            cta: String(localized: "Rename")
        ) { _ in commitRename() }
        .task { await load() }
        // FER-787: the list + the week share one `load()`; the initial `.task` doesn't re-run on a
        // NavigationStack pop, so refresh on return (e.g. from the routine/day editor) too.
        .onAppear { if loaded { Task { await load() } } }
        .enableInjection()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            // FER-952 (owner, propuesta C aprobada): ONE integrated hero title — «Your weekly plan» —
            // no overline; the count rides as the subtitle. Nothing else on the screen changes.
            Text("Your weekly plan")
                .font(LiquidType.displayS)
                .tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            if loaded && !routines.isEmpty {
                // Handoff v4b: a terse count («4 días · 3 rutinas»), not an opinion.
                Text("\(assignedCount) days · \(routines.count) routines")
                    .font(LiquidType.cuerpoBanner)
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// This week's planned volume per group, summed across the scheduled days (drives the opinion + footer).
    private var weeklyVolume: [MuscleGroup: Int] {
        var out: [MuscleGroup: Int] = [:]
        for rid in schedule.values { for (g, n) in routineVolume[rid] ?? [:] { out[g, default: 0] += n } }
        return out
    }

    // MARK: - The week (one row per day)

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: .zero) {
            LiquidSectionHeader("The week") {
                Text("tap a day to edit it")
                    .font(LiquidType.unidad)
                    .foregroundStyle(LiquidColor.tinta500)
            }
            VStack(spacing: .zero) {
                ForEach(weekdays, id: \.self) { wd in
                    dayRow(wd)
                    if wd != weekdays.last { capillary }
                }
            }
            .padding(.vertical, LiquidSpace.s050)
            .padding(.horizontal, LiquidSpace.handoff14)
            .liquidGlass(.superficieSolida)
        }
    }

    /// One day: its weekday label (today marked), the assigned routine or «Rest». Decision A (FER-747):
    /// a day WITH a routine pushes 1o to edit its prescription (chevron ›); an EMPTY day still opens the
    /// assign `Menu` (chevron ▾) that picks a routine (grouped by folder) or leaves it as rest.
    @ViewBuilder
    private func dayRow(_ wd: Int) -> some View {
        if schedule[wd] != nil {
            // Propuesta B (elegida por Fer, 2026-07-16): la RUTINA es un chip troquel (tocarlo =
            // editar esa rutina — el mismo objeto que en el resto del app) y el ⇄ al borde de la
            // fila cambia la asignación del día. Dos objetos distintos, dos acciones obvias — los
            // dos chevrons (›/▾) confundían.
            assignedDayRow(wd)
        } else {
            Button { assignMenuDay = wd } label: { rowLabel(wd, chevron: "chevron.down") }
                .buttonStyle(.plain)
                .liquidMenu(
                    isPresented: Binding(get: { assignMenuDay == wd },
                                         set: { if !$0 { assignMenuDay = nil } }),
                    items: assignMenuItems(wd)
                )
        }
    }

    /// The assign menu rows (empty days): pick a routine — folders become submenus — or keep it as
    /// rest (FER-837, mock 4b).
    private func assignMenuItems(_ wd: Int) -> [LiquidMenuItem] {
        var rows: [LiquidMenuItem] = [
            .init(String(localized: "Rest"),
                  systemImage: schedule[wd] == nil ? "checkmark" : "moon.zzz") { clear(wd) }
        ]
        for folder in folders {
            let rs = routines.filter { $0.folderId == folder.id }
            if !rs.isEmpty {
                rows.append(.init(folder.name, systemImage: "folder",
                                  children: rs.map { routinePickItem(wd, $0) }))
            }
        }
        // Everything not in a listed folder (including a routine whose folder was deleted) so no
        // routine is ever un-pickable.
        rows += unfiledRoutines.map { routinePickItem(wd, $0) }
        return rows
    }

    private func assignedDayRow(_ wd: Int) -> some View {
        // Frontera de tipo preventiva (mismo fix del crash de previews, 2026-07-16).
        AnyView(assignedDayRowBody(wd))
    }

    @ViewBuilder
    private func assignedDayRowBody(_ wd: Int) -> some View {
        if let rid = schedule[wd], let r = routines.first(where: { $0.id == rid }) {
            let tint = routineTint(r)
            HStack(spacing: LiquidSpace.s300) {
                dayLabelColumn(wd)
                VStack(alignment: .leading, spacing: LiquidSpace.s125) {
                    OutlineCapsule(size: .sm, action: { openDay(wd) }) {
                        HStack(spacing: LiquidSpace.s150) {
                            EntrenarFamilyDot(tint)
                            Text(r.name)
                                .font(LiquidType.tituloFila)
                                .foregroundStyle(LiquidColor.tinta900)
                                .lineLimit(1).truncationMode(.tail)
                            LiquidIcon(.chevron, size: 11, color: tint)
                        }
                    }
                    .accessibilityLabel(Text("Edit \(r.name)"))
                    miniBars(rid)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(seriesText(rid))
                    .font(LiquidType.captionLectura)
                    .monospacedDigit()
                    .foregroundStyle(LiquidColor.tinta500)
                    .layoutPriority(1)
                Button { assignMenuDay = wd } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(LiquidType.iconSF(size: 15))
                        .foregroundStyle(LiquidColor.tinta500)
                        .frame(width: LiquidControl.hitTarget, height: LiquidControl.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Change this day's routine"))
                .liquidMenu(
                    isPresented: Binding(get: { assignMenuDay == wd },
                                         set: { if !$0 { assignMenuDay = nil } }),
                    items: assignMenuItems(wd)
                )
            }
            .frame(minHeight: LiquidControl.hitTarget)
            .padding(.vertical, LiquidSpace.filaRespiro)
        }
    }

    private func dayLabelColumn(_ wd: Int) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            Text(weekdayLabel(wd))
                .font(LiquidType.tituloFila)
                .foregroundStyle(wd == today ? LiquidColor.tinta900 : LiquidColor.tinta700)
            if wd == today {
                Text("today")
                    .textCase(.uppercase)
                    .font(LiquidType.microEstado)
                    .foregroundStyle(LiquidColor.tinta900)
            }
        }
        .frame(width: LiquidControl.lg, alignment: .leading)
    }

    private func routinePickItem(_ wd: Int, _ r: Routine) -> LiquidMenuItem {
        LiquidMenuItem(r.name, systemImage: schedule[wd] == r.id ? "checkmark" : nil) { assign(wd, r.id) }
    }

    private func rowLabel(_ wd: Int, chevron: String) -> some View {
        HStack(spacing: LiquidSpace.handoff14) {
            dayLabelColumn(wd)

            if let rid = schedule[wd], let r = routines.first(where: { $0.id == rid }) {
                VStack(alignment: .leading, spacing: LiquidSpace.s125) {
                    Text(r.name)
                        .font(LiquidType.cuerpoBanner)
                        .fontWeight(wd == today ? .semibold : .regular)
                        .foregroundStyle(LiquidColor.tinta900)
                    miniBars(rid)
                }
                Spacer(minLength: LiquidSpace.s200)
                Text(seriesText(rid))
                    .font(LiquidType.captionLectura)
                    .monospacedDigit()
                    .foregroundStyle(LiquidColor.tinta500)
            } else {
                Text("Rest")
                    .font(LiquidType.cuerpoBanner)
                    .foregroundStyle(LiquidColor.tinta500)
                Spacer(minLength: LiquidSpace.s200)
            }
            Image(systemName: chevron)
                .font(LiquidType.iconSF(size: 15))
                .foregroundStyle(LiquidColor.tinta500)
                .frame(width: LiquidControl.hitTarget, height: LiquidControl.hitTarget)
        }
        .frame(minHeight: LiquidControl.hitTarget)
        .padding(.vertical, LiquidSpace.filaRespiro)
        .contentShape(Rectangle())
    }

    /// Up to three tinted mini-bars (mock 1b): the routine's top groups by planned set volume, widths
    /// proportional to their share.
    @ViewBuilder private func miniBars(_ rid: String) -> some View {
        let vol = (routineVolume[rid] ?? [:]).sorted { $0.value > $1.value }.prefix(3)
        let maxV = vol.map(\.value).max() ?? 1
        HStack(spacing: LiquidSpace.s075) {
            ForEach(Array(vol.enumerated()), id: \.offset) { _, e in
                Capsule()
                    .fill(e.key.tint())
                    .frame(width: max(12, CGFloat(e.value) / CGFloat(maxV) * 34), height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func seriesText(_ rid: String) -> String {
        let n = (routineVolume[rid] ?? [:]).values.reduce(0, +)
        return String(localized: "\(n) sets")
    }

    // MARK: - Weekly volume footer (mock 1b) — planned sets bucketed into the four groups

    private var volumeFooter: some View {
        let vol = weeklyVolume
        let maxV = MuscleGroup.allCases.map { vol[$0] ?? 0 }.max() ?? 1
        return VStack(alignment: .leading, spacing: .zero) {
            LiquidSectionHeader("Weekly volume by group")
            HStack(alignment: .bottom, spacing: LiquidSpace.handoff14) {
                ForEach(Array(MuscleGroup.allCases.enumerated()), id: \.element) { i, g in
                    let v = vol[g] ?? 0
                    VStack(spacing: LiquidSpace.s125) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)  // token-exempt(dato): geometría de dato
                            .fill(v == 0 ? LiquidColor.tinta7 : g.tint())
                            .frame(height: max(8, CGFloat(v) / CGFloat(max(1, maxV)) * 34))
                            .frame(maxWidth: .infinity)
                            // Handoff `recGrow`: each bar grows from its base on entry, staggered
                            // left→right (150→330 ms). Reduce Motion skips it (bars appear settled).
                            .scaleEffect(y: volumeBarsGrown || reduceMotion ? 1 : 0.001, anchor: .bottom)
                            .animation(LiquidMotion.suave.delay(0.15 + 0.06 * Double(i)), value: volumeBarsGrown)
                        Text(g.label)
                            .liquidLabel()
                            .foregroundStyle(LiquidColor.tinta500)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .onAppear { volumeBarsGrown = true }
            // VoiceOver leía 4 rótulos sin valores; un solo elemento compuesto los une (auditoría a11y).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: MuscleGroup.allCases
                .map { String(localized: "\($0.label) \(vol[$0] ?? 0) sets") }
                .joined(separator: ", ")))
            // 2026-07-19 (decisión Fer): se retiró la nota al pie («Series planeadas. Core quedó corto
            // esta semana.»). El rótulo de sección ya dice «Volumen semanal por grupo» y las barras se
            // explican solas, así que el caso normal era puro relleno. Con ella se fue el aviso de grupo
            // rezagado; si se quiere de vuelta, que sea como marca EN la barra corta, no como prosa
            // debajo de la gráfica.
        }
    }

    // MARK: - Routines (flat list + create / import / templates / folders / library) — FER-890

    /// The per-routine tint (mock 1c/1a), resolved through the shared `RoutineClassifier` (FER-775) by the
    /// routine's own exercises — never the name's `hashValue` — so a routine keeps the SAME hue here, in the
    /// hub and in the editor. push → ember, pull → teal, leg/full → indigo; unclassifiable → default ember.
    private func routineTint(_ r: Routine) -> Color {
        return routineRegion[r.id].tint()
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: .zero) {
            LiquidSectionHeader("My routines") {
                Button { showBuilder = true } label: {
                    (Text(verbatim: "＋ ") + Text("New"))
                        .font(LiquidType.tituloFila)
                        .foregroundStyle(LiquidColor.tinta900)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("New routine"))
            }
            if routines.isEmpty {
                Text("No routines yet. Create one, start from a template, or import a plan.")
                    .font(LiquidType.cuerpoBanner)
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, LiquidSpace.seccionAire)
                    .padding(.bottom, LiquidSpace.s200)
            } else if folders.isEmpty {
                VStack(spacing: .zero) {
                    ForEach(routines) { r in
                        routineRow(r)
                        if r.id != routines.last?.id { capillary }
                    }
                }
                .padding(.vertical, LiquidSpace.s050)
                .padding(.horizontal, LiquidSpace.handoff14)
                .liquidGlass(.superficieSolida)
            } else {
                // Decisión Fer (2026-07-16 v2): carpetas = subdivisiones. FRONTERA DE TIPO
                // (AnyView): este bloque inline hacía explotar el layout de tipos de
                // AttributeGraph en el JIT de previews (crash SIGSEGV + VM 2.9 GB) — ver
                // Cenit-2026-07-16-220029.ips. No quitar sin re-verificar el canvas.
                foldersListErased
            }
            toolsChipsRow
            LiquidListCard {
                LiquidListRow(title: String(localized: "Exercise library"),
                              tone: nil, divider: false, action: openLibrary)
            }
            .padding(.top, LiquidSpace.s300)
        }
    }

    /// The routine's movement-family glyph kind, from its classified region (nil → the dumbbell).
    private func glyphKind(_ r: Routine) -> RoutineGlyphKind {
        switch routineRegion[r.id] {
        case .push: return .push
        case .pull: return .pull
        case .legs: return .legs
        case .fullBody, .none: return .fullBody
        }
    }

    /// The weekdays this routine is scheduled on, as the handoff's terse «lun·vie» (nil = unassigned).
    private func assignedDaysText(_ r: Routine) -> String? {
        let days = weekdays.filter { schedule[$0] == r.id }.map { weekdayLabel($0).lowercased() }
        return days.isEmpty ? nil : days.joined(separator: "·")
    }

    /// Items for the «Templates · Import · Folders» menu. Folders are degraded (decision A): they're not
    /// shown as headers in the body, but each existing folder keeps Rename/Delete here so full folder
    /// management stays reachable (FER-890 QA D1 — they used to hang off the removed folder headers).
    /// The three doors as equal-weight chips (FER-952): Templates and Import open their sheets;
    /// Folders anchors the folder-management paper menu (new / rename / delete).
    private var toolsChipsRow: some View {
        HStack(spacing: LiquidSpace.s200) {
            CrearPlanChip(onTemplates: { showTemplates = true }, onImport: { showImport = true })
            // Decisión Fer (2026-07-16 v2): UNA sola acción — crear la división. Renombrar/borrar
            // viven en la sub-cabecera de cada carpeta (··· → undo de 4 s al borrar).
            EntrenarChipHerramienta(systemImage: "folder.badge.plus", label: Text("New section")) {
                startNewFolder(moving: nil)
            }
        }
        .padding(.top, LiquidSpace.s300)
    }

    /// El cuerpo de secciones, borrado a AnyView — la frontera que mantiene chico el tipo de la
    /// pantalla (fix del crash de previews, 2026-07-16). Ver nota en `routinesSection`.
    private var foldersListErased: AnyView {
        let byFolder = Dictionary(grouping: routines, by: \.folderId)
        let unfiled = byFolder[nil] ?? []
        return AnyView(
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                ForEach(folders) { folder in
                    let rs = byFolder[folder.id] ?? []
                    folderCard(folder: folder, routines: rs)
                }
                // «Sueltas» también recibe: soltar aquí SACA la rutina de su carpeta. Sin esto el arrastre
                // sería de una sola dirección y habría que volver al menú para deshacerlo.
                if !unfiled.isEmpty {
                    unfiledCard(routines: unfiled)
                }
            }
        )
    }

    private func folderCard(folder: RoutineFolder, routines rs: [Routine]) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            folderBand(folder, count: rs.count)
            if !collapsedFolders.contains(folder.id) {
                ForEach(Array(rs.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { capillary }
                    routineRow(r).routineDraggable(r.id)
                }
            }
        }
        .padding(.vertical, LiquidSpace.s050)
        .padding(.horizontal, LiquidSpace.handoff14)
        .liquidGlass(.superficieSolida)
        .routineDropTarget(active: dropTarget == folder.id) { id in
            accept(id, into: folder.id)
        } targeted: { on in
            dropTarget = on ? folder.id : (dropTarget == folder.id ? nil : dropTarget)
        }
    }

    private func unfiledCard(routines unfiled: [Routine]) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            sectionBand(String(localized: "Loose"), count: unfiled.count,
                        collapsed: collapsedFolders.contains(Self.unfiledSectionID),
                        toggle: { toggleCollapse(Self.unfiledSectionID) })
            if !collapsedFolders.contains(Self.unfiledSectionID) {
                ForEach(Array(unfiled.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { capillary }
                    routineRow(r).routineDraggable(r.id)
                }
            }
        }
        .padding(.vertical, LiquidSpace.s050)
        .padding(.horizontal, LiquidSpace.handoff14)
        .liquidGlass(.superficieSolida)
        .routineDropTarget(active: dropTarget == Self.unfiledSectionID) { id in
            accept(id, into: nil)
        } targeted: { on in
            dropTarget = on ? Self.unfiledSectionID
                            : (dropTarget == Self.unfiledSectionID ? nil : dropTarget)
        }
    }

    /// Recibe una rutina soltada sobre una sección. Resuelve el id contra las rutinas cargadas —lo que
    /// entrega un proveedor de arrastre es texto y podría venir de cualquier app— y descarta el caso
    /// trivial de soltarla donde ya estaba, para no escribir en la base ni recargar por nada.
    private func accept(_ routineId: String, into folderId: String?) -> Bool {
        guard let r = routines.first(where: { $0.id == routineId }), r.folderId != folderId else { return false }
        move(r, to: folderId)
        return true
    }

    private func folderBand(_ f: RoutineFolder, count: Int) -> some View {
        sectionBand(f.name, count: count,
                    collapsed: collapsedFolders.contains(f.id),
                    toggle: { toggleCollapse(f.id) }) {
            Button { menuFolderId = f.id } label: {
                Image(systemName: "ellipsis")
                    .font(LiquidType.iconSF(size: 15))
                    .foregroundStyle(LiquidColor.tinta500)
                    .frame(width: LiquidControl.hitTarget, height: LiquidControl.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .liquidMenu(
                isPresented: Binding(get: { menuFolderId == f.id },
                                     set: { if !$0 { menuFolderId = nil } }),
                items: [
                    .init(String(localized: "Rename folder"), systemImage: "pencil") { startRename(f) },
                    .init(String(localized: "Delete folder"), systemImage: "trash", isDestructive: true) { deleteFolder(f) }
                ]
            )
        }
    }

    private func toggleCollapse(_ id: String) {
        withAnimation(LiquidMotion.toque) {
            if collapsedFolders.contains(id) { collapsedFolders.remove(id) } else { collapsedFolders.insert(id) }
        }
    }

    /// Sub-cabecera de carpeta El Eje: `liquidLabel` + conteo + trailing + chevron — sin banda
    /// de papel ni sangría extra (FER-292); la tarjeta padre da la jerarquía.
    private func sectionBand<T: View>(_ name: String, count: Int, collapsed: Bool,
                                      toggle: @escaping () -> Void,
                                      @ViewBuilder trailing: () -> T = { EmptyView() }) -> some View {
        HStack(spacing: LiquidSpace.s200) {
            Button(action: toggle) {
                HStack(spacing: LiquidSpace.s200) {
                    Text(verbatim: name)
                        .liquidLabel()
                        .foregroundStyle(LiquidColor.tinta500)
                    Text(verbatim: "· \(count)")
                        .font(LiquidType.filaConteo)
                        .foregroundStyle(LiquidColor.tinta500)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: name))
            .accessibilityValue(Text(collapsed ? "collapsed" : "expanded"))
            trailing()
            // LiquidIcon.chevron apunta ›; expandido gira a ▾ (HTML estado 3).
            LiquidIcon(.chevron, size: 12, color: LiquidColor.tinta500)
                .rotationEffect(.degrees(collapsed ? 0 : 90))
        }
        .frame(minHeight: LiquidControl.hitTarget)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, LiquidSpace.s100)
    }

    /// The one-line metadata under a routine name (mock 1c): exercise count, then its top primary muscles.
    private func metadataLine(_ r: Routine) -> String {
        var parts = [exerciseCountText(exerciseCounts[r.id] ?? 0)]
        let m = routineMuscles[r.id] ?? []
        if !m.isEmpty { parts.append(m.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    // (statusText «hoy / hace N d» retired in FER-940 — the trailing datum is the assigned days now.)

    /// The row's actions as the «···» paper menu (FER-837). The native long-press `contextMenu` was
    /// retired (FER-951): iOS draws it as a system balloon that ignores the theme — one menu, one look.
    private func routineLiquidItems(_ r: Routine) -> [LiquidMenuItem] {
        var move: [LiquidMenuItem] = folders.map { f in
            LiquidMenuItem(f.name, systemImage: r.folderId == f.id ? "checkmark" : "folder") { self.move(r, to: f.id) }
        }
        if r.folderId != nil {
            move.append(.init(String(localized: "Remove from folder"), systemImage: "folder.badge.minus") { self.move(r, to: nil) })
        }
        move.append(.init(String(localized: "New folder…"), systemImage: "folder.badge.plus") { startNewFolder(moving: r) })
        return [
            .init(String(localized: "Edit routine"), systemImage: "slider.horizontal.3") { openRoutine(r.id) },
            .init(String(localized: "Duplicate"), systemImage: "plus.square.on.square") { duplicate(r) },
            .init(String(localized: "Move to…"), systemImage: "folder", children: move),
            .init(String(localized: "Delete routine"), systemImage: "trash", isDestructive: true) { delete(r) }
        ]
    }

    private func routineRow(_ r: Routine) -> some View {
        SwipeToDeleteRow(
            isOpen: Binding(get: { swipedRoutineId == r.id },
                            set: { swipedRoutineId = $0 ? r.id : nil }),
            onDelete: { delete(r) }
        ) {
            HStack(spacing: LiquidSpace.s300) {
                Button { openRoutine(r.id) } label: {
                    HStack(spacing: LiquidSpace.s300) {
                        RoutineRegionGlyph(glyphKind(r), tint: routineTint(r))
                            .frame(width: 22, height: 22)
                            .frame(width: 38, height: 38)
                            .background(LiquidColor.tinta7,
                                        in: RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                            Text(r.name)
                                .font(LiquidType.tituloGemela)
                                .foregroundStyle(LiquidColor.tinta900)
                            Text(metadataLine(r))
                                .font(LiquidType.filaConteo)
                                .foregroundStyle(LiquidColor.tinta500)
                                .lineLimit(1).truncationMode(.tail)
                        }
                        Spacer(minLength: LiquidSpace.s200)
                        // Unassigned reads as the honest «—» (handoff: «Movilidad 20 min · —»).
                        Text(assignedDaysText(r) ?? "—")
                            .font(LiquidType.captionLectura)
                            .foregroundStyle(assignedDaysText(r) == nil
                                             ? LiquidColor.tinta500
                                             : LiquidColor.tinta700)
                    }
                    .frame(minHeight: LiquidControl.lg)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { menuRoutineId = r.id } label: {
                    Image(systemName: "ellipsis")
                        .font(LiquidType.iconSF(size: 15))
                        .foregroundStyle(LiquidColor.tinta500)
                        .frame(width: 32, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .liquidMenu(
                    isPresented: Binding(get: { menuRoutineId == r.id },
                                         set: { if !$0 { menuRoutineId = nil } }),
                    items: routineLiquidItems(r)
                )
            }
        }
    }

    // MARK: - Delete / undo (FER-491)

    private struct DeletedRoutine: Identifiable {
        let id = UUID()
        let routine: Routine
        let exercises: [RoutineExercise]
    }

    private func delete(_ r: Routine) {
        swipedRoutineId = nil
        Task {
            let exercises = await repo.routineExercises(routineId: r.id)
            do {
                try await repo.deleteRoutine(id: r.id)
                await load()
                withAnimation { pendingUndo = DeletedRoutine(routine: r, exercises: exercises) }
            } catch {
                saveError = true
            }
        }
    }

    private func undoDelete(_ d: DeletedRoutine) {
        Task {
            do {
                try await repo.saveRoutine(d.routine, exercises: d.exercises)
                await load()
                withAnimation { pendingUndo = nil }
            } catch {
                saveError = true
            }
        }
    }

    private func undoBanner(_ d: DeletedRoutine) -> some View {
        // FER-280·2c: receta → `UndoToast`; transition + auto-descarte quedan en el caller.
        UndoToast(message: String(localized: "Routine deleted"),
                  cta: String(localized: "Undo"),
                  action: { undoDelete(d) })
            .transition(LiquidMotion.risingFadeTransition)
            .task(id: d.id) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation { if pendingUndo?.id == d.id { pendingUndo = nil } }
            }
    }

    // MARK: - Duplicate (FER-528)

    private func duplicate(_ r: Routine) {
        Task {
            let exercises = await repo.routineExercises(routineId: r.id)
            let now = Int(Date().timeIntervalSince1970)
            let newId = UUID().uuidString
            let copy = Routine(id: newId, name: "\(r.name) \(String(localized: "(copy)"))",
                               tag: r.tag, folderId: r.folderId, createdTs: now, updatedTs: now,
                               sortOrder: r.sortOrder)
            let copiedExercises = exercises.map { ex -> RoutineExercise in
                var c = ex
                c.id = UUID().uuidString
                c.routineId = newId
                c.sets = ex.sets.map { var s = $0; s.id = UUID().uuidString; return s }
                return c
            }
            do {
                try await repo.saveRoutine(copy, exercises: copiedExercises)
                await load()
            } catch {
                saveError = true
            }
        }
    }

    // MARK: - Folders (FER-494) — management stays alive; only the body's folder grouping is gone (dec. A)

    private func startNewFolder(moving r: Routine?) {
        pendingMove = r; newFolderName = ""; showNewFolder = true
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        let toMove = pendingMove
        newFolderName = ""; pendingMove = nil
        guard !name.isEmpty else { return }
        Task {
            guard let store = await repo.storeHandle() else { saveError = true; return }
            let folder = RoutineFolder(name: name, sortOrder: folders.count)
            do {
                try await store.saveFolder(folder)
                if let toMove { try await store.setRoutineFolder(routineId: toMove.id, folderId: folder.id) }
                await load()
            } catch {
                saveError = true
            }
        }
    }

    private func startRename(_ f: RoutineFolder) { renameText = f.name; renameFolder = f }

    private func commitRename() {
        guard let f = renameFolder else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        renameFolder = nil
        guard !name.isEmpty else { return }
        Task {
            guard let store = await repo.storeHandle() else { saveError = true; return }
            do {
                try await store.saveFolder(RoutineFolder(id: f.id, name: name, sortOrder: f.sortOrder))
                await load()
            } catch {
                saveError = true
            }
        }
    }

    private func deleteFolder(_ f: RoutineFolder) {
        let members = routines.filter { $0.folderId == f.id }.map(\.id)
        Task {
            guard let store = await repo.storeHandle() else { saveError = true; return }
            do {
                try await store.deleteFolder(id: f.id)
                await load()
                withAnimation { pendingFolderUndo = DeletedFolder(folder: f, memberIds: members) }
            } catch {
                saveError = true
            }
        }
    }
    /// M5 (decisión Fer): borrar carpeta era destructivo inmediato — mismo contrato de undo 4 s
    /// que borrar rutina. Las rutinas miembro se restauran a la carpeta si el usuario se arrepiente.
    private struct DeletedFolder: Identifiable {
        let id = UUID()
        let folder: RoutineFolder
        let memberIds: [String]
    }

    private func undoDeleteFolder(_ d: DeletedFolder) {
        Task {
            guard let store = await repo.storeHandle() else { saveError = true; return }
            do {
                try await store.saveFolder(d.folder)
                for rid in d.memberIds { try await store.setRoutineFolder(routineId: rid, folderId: d.folder.id) }
                await load()
                withAnimation { pendingFolderUndo = nil }
            } catch {
                saveError = true
            }
        }
    }

    private func folderUndoBanner(_ d: DeletedFolder) -> some View {
        // FER-280·2c: gemela de undoBanner → `UndoToast`.
        UndoToast(message: String(localized: "Folder deleted"),
                  cta: String(localized: "Undo"),
                  action: { undoDeleteFolder(d) })
            .transition(LiquidMotion.risingFadeTransition)
            .task(id: d.id) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation { if pendingFolderUndo?.id == d.id { pendingFolderUndo = nil } }
            }
    }


    private func move(_ r: Routine, to folderId: String?) {
        Task {
            guard let store = await repo.storeHandle() else { saveError = true; return }
            do {
                try await store.setRoutineFolder(routineId: r.id, folderId: folderId)
                await load()
            } catch {
                saveError = true
            }
        }
    }

    // MARK: - Bits

    private var capillary: some View {
        Rectangle().fill(LiquidColor.tinta10).frame(height: 0.5)
    }

    /// Localized short weekday name (respects the user's locale), capitalized and without a trailing dot.
    private func weekdayLabel(_ wd: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols   // index 0 = Sunday … 6 = Saturday
        let raw = symbols[(wd - 1) % 7]
        return raw.replacingOccurrences(of: ".", with: "").capitalized
    }

    private func exerciseCountText(_ n: Int) -> String { String(localized: "\(n) exercises") }

    // MARK: - Data (writes the split via the F1 store CRUD, FER-531)

    /// FER-952 unified flow: the library's picks become a routine RIGHT HERE («New routine», 3×8 per
    /// exercise — the builder's defaults) and the unified editor opens to name and tune it.
    private func createRoutine(_ picks: [Exercise]) {
        guard !picks.isEmpty else { return }
        let now = Int(Date().timeIntervalSince1970)
        let r = Routine(name: String(localized: "New routine"), createdTs: now, updatedTs: now, sortOrder: 0)
        let exercises = picks.enumerated().map { idx, ex -> RoutineExercise in
            let usesReps = ex.type == .weightReps || ex.type == .bodyweight
            let reps: Int? = usesReps ? 8 : nil
            let sets = (0..<3).map { RoutineSet(position: $0, kind: .work, reps: reps, weightKg: nil) }
            return RoutineExercise(routineId: r.id, exerciseId: ex.id, position: idx,
                                   targetSets: 3, targetReps: reps, targetWeightKg: nil, sets: sets)
        }
        Task {
            do {
                try await repo.saveRoutine(r, exercises: exercises)
                await load()
                // FER-952 glitch: the library pops itself (dismiss) the moment onAdd returns — pushing the
                // editor DURING that pop stacked transitions and the new screen flashed in and out
                // (FER-171 lesson). Let the pop settle, then push.
                try? await Task.sleep(nanoseconds: 550_000_000)
                openRoutine(r.id)
            } catch {
                saveError = true
            }
        }
    }

    private func load() async {
        guard let store = await repo.storeHandle() else { loaded = true; return }
        let rs = (try? await store.routines()) ?? []
        // Planned volume per routine (mock 1b mini-bars + footer), exercise counts, top muscles, and the
        // classified region — all from the same per-routine exercise fetch.
        let all = await repo.allExercises()
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var vol: [String: [MuscleGroup: Int]] = [:]
        var counts: [String: Int] = [:]
        var muscles: [String: [String]] = [:]
        var regions: [String: RoutineRegion] = [:]
        for r in rs {
            let exs = (try? await store.routineExercises(routineId: r.id)) ?? []
            counts[r.id] = exs.count
            muscles[r.id] = Self.topMuscles(exs, byId: byId)
            let perExercise = exs.compactMap { byId[$0.exerciseId]?.primaryMuscles }
            regions[r.id] = RoutineClassifier.classify(primaryMusclesPerExercise: perExercise)
            var byGrp: [MuscleGroup: Int] = [:]
            for re in exs {
                guard let ex = byId[re.exerciseId], let g = exerciseGroup(ex) else { continue }
                let work = re.sets.filter { $0.kind == .work }.count
                byGrp[g, default: 0] += work > 0 ? work : re.targetSets
            }
            vol[r.id] = byGrp
        }
        let sessions = (try? await store.recentSessions(limit: 200)) ?? []
        routines = rs
        exerciseCounts = counts
        routineMuscles = muscles
        routineRegion = regions
        routineVolume = vol
        lastTrainedDays = Self.daysSinceLast(sessions)
        folders = (try? await store.routineFolders()) ?? []
        await reloadSchedule()
        loaded = true
    }

    /// An exercise's dominant group: the most-represented group across its primary muscles (nil if none map).
    private func exerciseGroup(_ ex: Exercise) -> MuscleGroup? {
        var tally: [MuscleGroup: Int] = [:]
        for m in ex.primaryMuscles { if let g = MuscleGroup.of(m) { tally[g, default: 0] += 1 } }
        return tally.max { $0.value < $1.value }?.key
    }

    /// Top primary muscles for a routine as Spanish labels (`MuscleVocabulary`), frequency-ranked.
    private static func topMuscles(_ exs: [RoutineExercise], byId: [String: Exercise]) -> [String] {
        var tally: [String: Int] = [:]; var order: [String] = []
        for re in exs {
            guard let ex = byId[re.exerciseId] else { continue }
            for m in ex.primaryMuscles { if tally[m] == nil { order.append(m) }; tally[m, default: 0] += 1 }
        }
        let idx = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return order.sorted { let a = tally[$0] ?? 0, b = tally[$1] ?? 0
            return a != b ? a > b : (idx[$0] ?? 0) < (idx[$1] ?? 0) }
            .prefix(3).map { MuscleVocabulary.es[$0] ?? $0.capitalized }
    }

    /// Whole days since each routine was last completed (newest session per routine wins).
    private static func daysSinceLast(_ sessions: [StrengthSession]) -> [String: Int] {
        let cal = Calendar.current; let today = cal.startOfDay(for: Date())
        var out: [String: Int] = [:]
        for s in sessions where s.endTs != nil {
            guard let rid = s.routineId, out[rid] == nil else { continue }
            let d = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(s.startTs)))
            out[rid] = cal.dateComponents([.day], from: d, to: today).day ?? 0
        }
        return out
    }

    private func reloadSchedule() async {
        guard let store = await repo.storeHandle() else { return }
        let rows = (try? await store.routineSchedule()) ?? []
        schedule = Dictionary(rows.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
    }

    private func assign(_ wd: Int, _ routineId: String) {
        Task {
            guard let store = await repo.storeHandle() else { return }
            do {
                try await store.setRoutineSchedule(weekday: wd, routineId: routineId)
                await reloadSchedule()
            } catch {
                saveError = true
            }
        }
    }

    private func clear(_ wd: Int) {
        Task {
            guard let store = await repo.storeHandle() else { saveError = true; return }
            do {
                try await store.clearRoutineSchedule(weekday: wd)
                await reloadSchedule()
            } catch {
                saveError = true
            }
        }
    }
}

// MARK: - Swipe-to-delete row (FER-491)

private struct SwipeToDeleteRow<Content: View>: View {
    @Binding var isOpen: Bool
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0

    private let revealWidth: CGFloat = 96
    private let fullSwipeThreshold: CGFloat = 200

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(LiquidType.iconSF(size: 17))
                    .foregroundStyle(LiquidColor.papelTarjeta)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(LiquidColor.negativo)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete routine"))

            content
                .background(LiquidColor.papelTarjeta)
                .offset(x: offset)
                .highPriorityGesture(drag)
        }
        .clipped()
        .onChange(of: isOpen) { _, open in
            if !open { withAnimation(LiquidMotion.filaDesliza) { offset = 0 } }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                let base: CGFloat = isOpen ? -revealWidth : 0
                offset = min(0, base + v.translation.width)
            }
            .onEnded { v in
                let dx = v.translation.width
                if !isOpen && -v.predictedEndTranslation.width > fullSwipeThreshold {
                    onDelete()
                    return
                }
                let open = isOpen ? !(dx > revealWidth * 0.5) : (-dx > revealWidth * 0.5)
                withAnimation(LiquidMotion.filaDesliza) {
                    offset = open ? -revealWidth : 0
                }
                isOpen = open
            }
    }
}

// MARK: - Coarse muscle grouping (mock 1b mini-bars + weekly volume footer)
//
// A planning-level bucketing of the catalog's 17 primary muscles into the four groups the mock draws.
// It's a display convention for the planner, not a physiological claim (no /cso surface): it colors the
// per-day mini-bars and sums the weekly «Volumen por grupo». Push/pull/legs take the routine tints;
// core stays ink-gray so a core deficit reads as absence, not another color.
enum MuscleGroup: CaseIterable {
    case push, pull, legs, core

    var label: String {
        switch self {
        case .push: return String(localized: "PUSH")
        case .pull: return String(localized: "PULL")
        case .legs: return String(localized: "LEGS")
        case .core: return String(localized: "CORE")
        }
    }

    /// Title-case name for prose (the day editor's meta line, 1o) — «Empuje · N ejercicios …». Explicit
    /// keys so they don't collide with the existing «Push» button string (which localizes to «Sube»).
    var title: String {
        switch self {
        case .push: return String(localized: "muscleGroup.push", defaultValue: "Push", comment: "routine group, title case")
        case .pull: return String(localized: "muscleGroup.pull", defaultValue: "Pull", comment: "routine group, title case")
        case .legs: return String(localized: "muscleGroup.legs", defaultValue: "Legs", comment: "routine group, title case")
        case .core: return String(localized: "muscleGroup.core", defaultValue: "Core", comment: "routine group, title case")
        }
    }

    func tint() -> Color {
        switch self {
        case .push: return LiquidColor.ambar
        case .pull: return LiquidColor.cian
        case .legs: return LiquidColor.indigo
        case .core: return LiquidColor.tinta500
        }
    }

    /// Map a catalog primary-muscle key (lowercased English) to its group; nil for anything unmapped.
    static func of(_ muscle: String) -> MuscleGroup? {
        switch muscle {
        case "chest", "shoulders", "triceps": return .push
        case "lats", "middle back", "lower back", "traps", "biceps", "forearms", "neck": return .pull
        case "quadriceps", "hamstrings", "glutes", "calves", "abductors", "adductors": return .legs
        case "abdominals": return .core
        default: return nil
        }
    }
}
#endif
