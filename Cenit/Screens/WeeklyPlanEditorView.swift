#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

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
// «Instrumento diurno»: an editor has no measured datum, so there is NO saturated color for the week — the
// assigned-vs-rest contrast is carried by ink WEIGHT (a routine name in `ink` vs «Rest» in `inkDim`), and
// hierarchy by space + hairlines, no card-in-card. Routines carry their per-routine tint only on the 8pt
// identity dot (via `RoutineClassifier`, the same hue the hub uses). Tapping a day opens a native paper
// menu of routines (grouped by folder, FER-494) plus «Rest» to clear it; tapping a routine edits it.

struct WeeklyPlanEditorView: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.instrumentoTheme) private var theme

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
    /// The routine the builder just created; pushed onto «Rutina» when its sheet finishes dismissing
    /// (pushing mid-dismiss stacks transitions, FER-171 lesson).
    @State private var savedRoutineId: String? = nil
    @State private var showTemplates = false
    @State private var showImport = false
    @State private var swipedRoutineId: String? = nil
    @State private var pendingUndo: DeletedRoutine? = nil
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var pendingMove: Routine? = nil
    @State private var renameFolder: RoutineFolder? = nil
    @State private var renameText = ""
    // FER-837: which «···» paper menu is open (routine id / the tools row).
    @State private var menuRoutineId: String? = nil
    @State private var showToolsMenu = false

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
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                header
                if loaded {
                    if !routines.isEmpty {
                        weekSection
                        volumeFooter
                    }
                    routinesSection
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .overlay(alignment: .bottom) { if let d = pendingUndo { undoBanner(d) } }
        .sensoryFeedback(trigger: pendingUndo?.id) { _, new in new != nil ? .warning : nil }
        // Create-only builder (FER-840): saving hands back the new routine's id, and the dismissed sheet
        // opens it straight on the unified «Rutina» editor (opening mid-dismiss stacks transitions — FER-171).
        .sheet(isPresented: $showBuilder, onDismiss: {
            if let id = savedRoutineId { savedRoutineId = nil; openRoutine(id) }
        }) {
            RoutineBuilderScreen { id in
                savedRoutineId = id
                await load()
            }
            .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .sheet(isPresented: $showTemplates) {
            StarterTemplatesSheet { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .sheet(isPresented: $showImport) {
            WorkoutImportView { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .instrumentoInput(
            isPresented: Binding(get: { showNewFolder },
                                 set: { if !$0 { showNewFolder = false; newFolderName = ""; pendingMove = nil } }),
            text: $newFolderName,
            title: String(localized: "New folder"),
            context: String(localized: "YOUR PLAN"),
            placeholder: String(localized: "Folder name"),
            cta: String(localized: "Create")
        ) { _ in createFolder() }
        .instrumentoInput(
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Train").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("Your plan").font(StrandFont.title1).foregroundStyle(theme.ink)
            if loaded && !routines.isEmpty {
                Text(balanceOpinion)
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
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

    /// The sub that opines on the week's balance (mock 1b): how many training days, and whether the big
    /// three (push/pull/legs) are each covered.
    private var balanceOpinion: String {
        let days = assignedCount
        if days == 0 { return String(localized: "No training days yet · assign a routine to a day.") }
        let uncovered = [MuscleGroup.push, .pull, .legs].contains { (weeklyVolume[$0] ?? 0) == 0 }
        let daysText = days == 1 ? String(localized: "1 training day") : String(localized: "\(days) training days")
        return uncovered
            ? String(localized: "\(daysText) · some groups are still uncovered.")
            : String(localized: "\(daysText) · push, pull and legs each covered.")
    }

    // MARK: - The week (one row per day)

    private var weekSection: some View {
        VStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { wd in
                dayRow(wd)
                if wd != weekdays.last { divider }
            }
        }
    }

    /// One day: its weekday label (today marked), the assigned routine or «Rest». Decision A (FER-747):
    /// a day WITH a routine pushes 1o to edit its prescription (chevron ›); an EMPTY day still opens the
    /// assign `Menu` (chevron ▾) that picks a routine (grouped by folder) or leaves it as rest.
    @ViewBuilder
    private func dayRow(_ wd: Int) -> some View {
        if schedule[wd] != nil {
            Button { openDay(wd) } label: { rowLabel(wd, chevron: "chevron.right") }
                .buttonStyle(.plain)
        } else {
            Button { assignMenuDay = wd } label: { rowLabel(wd, chevron: "chevron.down") }
                .buttonStyle(.plain)
                .paperMenu(
                    isPresented: Binding(get: { assignMenuDay == wd },
                                         set: { if !$0 { assignMenuDay = nil } }),
                    items: assignMenuItems(wd)
                )
        }
    }

    /// The assign menu rows (empty days): pick a routine — folders become submenus — or keep it as
    /// rest (FER-837, mock 4b).
    private func assignMenuItems(_ wd: Int) -> [PaperMenuItem] {
        var rows: [PaperMenuItem] = [
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

    private func routinePickItem(_ wd: Int, _ r: Routine) -> PaperMenuItem {
        PaperMenuItem(r.name, systemImage: schedule[wd] == r.id ? "checkmark" : nil) { assign(wd, r.id) }
    }

    private func rowLabel(_ wd: Int, chevron: String) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(weekdayLabel(wd))
                    .font(StrandFont.mono)
                    .foregroundStyle(wd == today ? theme.ink : theme.inkSecondary)
                if wd == today {
                    Text("today").textCase(.uppercase)
                        .font(StrandFont.footnote).fontWeight(.semibold).foregroundStyle(theme.dataRecovery)
                }
            }
            .frame(width: 52, alignment: .leading)

            if let rid = schedule[wd], let r = routines.first(where: { $0.id == rid }) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(r.name).font(StrandFont.body).fontWeight(wd == today ? .semibold : .regular)
                        .foregroundStyle(theme.ink)
                    miniBars(rid)
                }
                Spacer(minLength: 8)
                Text(seriesText(rid)).font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
            } else {
                Text("Rest").font(StrandFont.body).foregroundStyle(theme.inkDim)
                Spacer(minLength: 8)
            }
            Image(systemName: chevron)
                .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
        }
        .frame(minHeight: 52)
        .padding(.horizontal, wd == today ? 10 : 0)
        .background {
            if wd == today {
                RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous).fill(theme.surface)
            }
        }
        .contentShape(Rectangle())
    }

    /// Up to three tinted mini-bars (mock 1b): the routine's top groups by planned set volume, widths
    /// proportional to their share.
    @ViewBuilder private func miniBars(_ rid: String) -> some View {
        let vol = (routineVolume[rid] ?? [:]).sorted { $0.value > $1.value }.prefix(3)
        let maxV = vol.map(\.value).max() ?? 1
        HStack(spacing: 3) {
            ForEach(Array(vol.enumerated()), id: \.offset) { _, e in
                Capsule().fill(e.key.tint(theme))
                    .frame(width: max(12, CGFloat(e.value) / CGFloat(maxV) * 34), height: 4)
            }
        }
    }

    private func seriesText(_ rid: String) -> String {
        let n = (routineVolume[rid] ?? [:]).values.reduce(0, +)
        return String(localized: "\(n) sets")
    }

    // MARK: - Weekly volume footer (mock 1b) — planned sets bucketed into the four groups

    private var volumeFooter: some View {
        let vol = weeklyVolume
        let maxV = MuscleGroup.allCases.map { vol[$0] ?? 0 }.max() ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Text("Weekly volume by group").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(MuscleGroup.allCases, id: \.self) { g in
                    let v = vol[g] ?? 0
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)  // token-exempt: geometría de dato
                            .fill(v == 0 ? theme.hairlineStrong : g.tint(theme))
                            .frame(height: max(8, CGFloat(v) / CGFloat(max(1, maxV)) * 34))
                            .frame(maxWidth: .infinity)
                        Text(g.label).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                }
            }
        }
        .padding(.top, 6)
        .overlay(alignment: .top) { Divider().overlay(theme.hairline) }
    }

    // MARK: - Routines (flat list + create / import / templates / folders / library) — FER-890

    /// The per-routine tint (mock 1c/1a), resolved through the shared `RoutineClassifier` (FER-775) by the
    /// routine's own exercises — never the name's `hashValue` — so a routine keeps the SAME hue here, in the
    /// hub and in the editor. push → ember, pull → teal, leg/full → indigo; unclassifiable → default ember.
    private func routineTint(_ r: Routine) -> Color {
        switch routineRegion[r.id] {
        case .push:            return theme.dataStrain
        case .pull:            return theme.dataHrv
        case .legs, .fullBody: return theme.dataSleep
        case nil:              return theme.dataStrain
        }
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("My routines").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: 0) {
                if routines.isEmpty {
                    Text("No routines yet. Create one, start from a template, or import a plan.")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 10)
                    divider
                } else {
                    ForEach(routines) { r in
                        routineRow(r)
                        if r.id != routines.last?.id { divider }
                    }
                    divider
                }
                actionRow("plus", "New routine") { showBuilder = true }
                divider
                // The mock folds templates / import / folders into one row; the menu keeps all three
                // functions (decision A: conserve plantillas, import, carpetas behind this row).
                actionMenuRow("rectangle.stack", "Templates · Import · Folders", isPresented: $showToolsMenu, items: toolsMenuItems)
                divider
                actionRow("book", "Exercise library", action: openLibrary)
            }
        }
    }

    /// Items for the «Templates · Import · Folders» menu. Folders are degraded (decision A): they're not
    /// shown as headers in the body, but each existing folder keeps Rename/Delete here so full folder
    /// management stays reachable (FER-890 QA D1 — they used to hang off the removed folder headers).
    private var toolsMenuItems: [PaperMenuItem] {
        var items: [PaperMenuItem] = [
            .init(String(localized: "Start from a template"), systemImage: "square.stack.3d.up") { showTemplates = true },
            .init(String(localized: "Import plan"), systemImage: "square.and.arrow.down") { showImport = true },
            .init(String(localized: "New folder"), systemImage: "folder.badge.plus") { startNewFolder(moving: nil) }
        ]
        for f in folders {
            items.append(.init(f.name, systemImage: "folder", children: [
                .init(String(localized: "Rename folder…"), systemImage: "pencil") { startRename(f) },
                .init(String(localized: "Delete folder"), systemImage: "trash", isDestructive: true) { deleteFolder(f) }
            ]))
        }
        return items
    }

    private func actionRow(_ symbol: String, _ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 30)
                    .font(StrandFont.glyph(.lead)).foregroundStyle(theme.inkSecondary)
                Text(title).font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Like `actionRow` but reveals a paper menu (mock 1c's «Plantillas · Importar · Carpetas»), with a chevron.
    private func actionMenuRow(_ symbol: String, _ title: LocalizedStringKey,
                               isPresented: Binding<Bool>, items: [PaperMenuItem]) -> some View {
        Button { isPresented.wrappedValue = true } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 30)
                    .font(StrandFont.glyph(.lead)).foregroundStyle(theme.inkSecondary)
                Text(title).font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .paperMenu(isPresented: isPresented, items: items)
    }

    /// The one-line metadata under a routine name (mock 1c): exercise count, then its top primary muscles.
    private func metadataLine(_ r: Routine) -> String {
        var parts = [exerciseCountText(exerciseCounts[r.id] ?? 0)]
        let m = routineMuscles[r.id] ?? []
        if !m.isEmpty { parts.append(m.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// Trailing status (mock 1c): «hoy» in green if it's today's scheduled routine, else «hace N d» from
    /// the last time this routine was trained (nil if never).
    private func statusText(_ r: Routine) -> (text: String, isToday: Bool)? {
        if schedule[today] == r.id { return (String(localized: "today"), true) }
        guard let d = lastTrainedDays[r.id] else { return nil }
        if d <= 0 { return (String(localized: "today"), false) }
        return (d == 1 ? String(localized: "1 d ago") : String(localized: "\(d) d ago"), false)
    }

    @ViewBuilder
    private func routineActions(_ r: Routine) -> some View {
        // Editing lives on the unified «Rutina» editor now (FER-840) — same push as tapping the row.
        Button { openRoutine(r.id) } label: { Label("Edit routine", systemImage: "slider.horizontal.3") }
        Button { duplicate(r) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Menu {
            ForEach(folders) { f in
                Button { move(r, to: f.id) } label: {
                    Label(f.name, systemImage: r.folderId == f.id ? "checkmark" : "folder")
                }
            }
            if r.folderId != nil {
                Button { move(r, to: nil) } label: { Label("Remove from folder", systemImage: "folder.badge.minus") }
            }
            Divider()
            Button { startNewFolder(moving: r) } label: { Label("New folder…", systemImage: "folder.badge.plus") }
        } label: { Label("Move to…", systemImage: "folder") }
        Button(role: .destructive) { delete(r) } label: { Label("Delete routine", systemImage: "trash") }
    }

    /// The same actions as `routineActions`, as the «···» paper menu (FER-837). The long-press
    /// `contextMenu` keeps the native ViewBuilder version above.
    private func routinePaperItems(_ r: Routine) -> [PaperMenuItem] {
        var move: [PaperMenuItem] = folders.map { f in
            PaperMenuItem(f.name, systemImage: r.folderId == f.id ? "checkmark" : "folder") { self.move(r, to: f.id) }
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
            HStack(spacing: 8) {
                Button { openRoutine(r.id) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)   // token-exempt: geometría de dato (punto 8pt)
                                    .fill(routineTint(r)).frame(width: 8, height: 8)
                                Text(r.name).font(StrandFont.body).fontWeight(.semibold).foregroundStyle(theme.ink)
                            }
                            Text(metadataLine(r)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                                .padding(.leading, 15)
                        }
                        Spacer(minLength: 8)
                        if let status = statusText(r) {
                            Text(status.text).font(StrandFont.caption)
                                .foregroundStyle(status.isToday ? theme.dataRecovery : theme.inkTertiary)
                        }
                    }
                    .frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { routineActions(r) }

                Button { menuRoutineId = r.id } label: {
                    Image(systemName: "ellipsis").font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary).frame(width: 32, height: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .paperMenu(
                    isPresented: Binding(get: { menuRoutineId == r.id },
                                         set: { if !$0 { menuRoutineId = nil } }),
                    items: routinePaperItems(r)
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
            try? await repo.deleteRoutine(id: r.id)
            await load()
            withAnimation { pendingUndo = DeletedRoutine(routine: r, exercises: exercises) }
        }
    }

    private func undoDelete(_ d: DeletedRoutine) {
        Task {
            try? await repo.saveRoutine(d.routine, exercises: d.exercises)
            await load()
            withAnimation { pendingUndo = nil }
        }
    }

    private func undoBanner(_ d: DeletedRoutine) -> some View {
        HStack(spacing: 12) {
            Text("Routine deleted").font(StrandFont.subhead).foregroundStyle(theme.surface)
            Spacer(minLength: 8)
            Button { undoDelete(d) } label: {
                Text("Undo").font(StrandFont.headline).foregroundStyle(theme.surface)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
            try? await repo.saveRoutine(copy, exercises: copiedExercises)
            await load()
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
            guard let store = await repo.storeHandle() else { return }
            let folder = RoutineFolder(name: name, sortOrder: folders.count)
            try? await store.saveFolder(folder)
            if let toMove { try? await store.setRoutineFolder(routineId: toMove.id, folderId: folder.id) }
            await load()
        }
    }

    private func startRename(_ f: RoutineFolder) { renameText = f.name; renameFolder = f }

    private func commitRename() {
        guard let f = renameFolder else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        renameFolder = nil
        guard !name.isEmpty else { return }
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await store.saveFolder(RoutineFolder(id: f.id, name: name, sortOrder: f.sortOrder))
            await load()
        }
    }

    private func deleteFolder(_ f: RoutineFolder) {
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await store.deleteFolder(id: f.id)
            await load()
        }
    }

    private func move(_ r: Routine, to folderId: String?) {
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await store.setRoutineFolder(routineId: r.id, folderId: folderId)
            await load()
        }
    }

    // MARK: - Bits

    private var divider: some View { Divider().overlay(theme.hairline) }

    /// Localized short weekday name (respects the user's locale), capitalized and without a trailing dot.
    private func weekdayLabel(_ wd: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols   // index 0 = Sunday … 6 = Saturday
        let raw = symbols[(wd - 1) % 7]
        return raw.replacingOccurrences(of: ".", with: "").capitalized
    }

    private func exerciseCountText(_ n: Int) -> String { String(localized: "\(n) exercises") }

    // MARK: - Data (writes the split via the F1 store CRUD, FER-531)

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
            try? await store.setRoutineSchedule(weekday: wd, routineId: routineId)
            await reloadSchedule()
        }
    }

    private func clear(_ wd: Int) {
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await store.clearRoutineSchedule(weekday: wd)
            await reloadSchedule()
        }
    }
}

// MARK: - Swipe-to-delete row (FER-491)

private struct SwipeToDeleteRow<Content: View>: View {
    @Environment(\.instrumentoTheme) private var theme
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
                    .font(StrandFont.glyph(.lead, weight: .semibold))
                    .foregroundStyle(theme.surface)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(theme.critical)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete routine"))

            content
                .background(theme.paper)
                .offset(x: offset)
                .highPriorityGesture(drag)
        }
        .clipped()
        .onChange(of: isOpen) { _, open in
            if !open { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { offset = 0 } }
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
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
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

    func tint(_ theme: InstrumentoTheme) -> Color {
        switch self {
        case .push: return theme.dataStrain
        case .pull: return theme.dataHrv
        case .legs: return theme.dataSleep
        case .core: return theme.inkTertiary
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
