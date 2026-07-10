#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - «Mis rutinas» — routine + folder management (FER-534)
//
// The routine library management — create / edit / duplicate / delete routines, folders (FER-494),
// swipe-to-delete with undo (FER-491), and drag-to-reorder/move (FER-526). It used to live inline on the
// Entrenar landing; the «La Semana» redesign (FER-530) turned the landing into a planner, so this moved
// into its own screen, reached from the weekly plan editor's «Build» section. Same behavior, relocated.
//
// Navigation (opening a routine, browsing the library) is owned by the Entrenar NavigationStack in
// RootTabView and reaches here via the injected closures.

struct MisRutinasScreen: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.instrumentoTheme) private var theme

    var openRoutine: (String) -> Void
    var openLibrary: () -> Void

    @State private var loaded = false
    @State private var routines: [Routine] = []
    @State private var exerciseCounts: [String: Int] = [:]
    /// Top primary muscles per routine (Spanish labels) for the one-line metadata (mock 1c).
    @State private var routineMuscles: [String: [String]] = [:]
    /// The weekly split (`weekday → routineId`), so today's routine reads «hoy».
    @State private var schedule: [Int: String] = [:]
    /// Days since each routine was last trained (`routineId → whole days`), for the «hace N d» column.
    @State private var lastTrainedDays: [String: Int] = [:]
    @State private var builderTarget: BuilderTarget? = nil
    @State private var showTemplates = false
    @State private var showImport = false
    @State private var swipedRoutineId: String? = nil
    @State private var pendingUndo: DeletedRoutine? = nil
    @State private var folders: [RoutineFolder] = []
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var pendingMove: Routine? = nil
    @State private var renameFolder: RoutineFolder? = nil
    @State private var renameText = ""
    @State private var dropTarget: String? = nil
    // FER-837: which «···» paper menu is open (folder id / routine id / the tools row).
    @State private var menuFolderId: String? = nil
    @State private var menuRoutineId: String? = nil
    @State private var showToolsMenu = false
    private static let unfiledDropID = "__unfiled__"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header
                if loaded {
                    if routines.isEmpty { emptyState } else { misRutinas }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .overlay(alignment: .bottom) { if let d = pendingUndo { undoBanner(d) } }
        .sensoryFeedback(trigger: pendingUndo?.id) { _, new in new != nil ? .warning : nil }
        .sheet(item: $builderTarget) { target in
            RoutineBuilderScreen(routine: target.routine) { await load() }
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
            context: String(localized: "MY ROUTINES"),
            placeholder: String(localized: "Folder name"),
            cta: String(localized: "Create")
        ) { _ in createFolder() }
        .instrumentoInput(
            isPresented: Binding(get: { renameFolder != nil },
                                 set: { if !$0 { renameFolder = nil } }),
            text: $renameText,
            title: String(localized: "Rename folder"),
            context: String(localized: "MY ROUTINES"),
            placeholder: String(localized: "Folder name"),
            cta: String(localized: "Rename")
        ) { _ in commitRename() }
        .task { await load() }
    }

    private var header: some View {
        Text("My routines").font(StrandFont.title1).foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The handoff's per-routine tint (mock 1c/1a): push → ember, pull → teal, leg → indigo, keyed off the
    /// routine name's split keyword with a stable fallback so each routine keeps one consistent dot.
    private func routineTint(_ name: String) -> Color {
        let n = name.lowercased()
        if n.contains("empuj") || n.contains("push") || n.contains("pecho") { return theme.dataStrain }
        if n.contains("tir") || n.contains("pull") || n.contains("espalda") { return theme.dataHrv }
        if n.contains("pierna") || n.contains("leg") || n.contains("quad") || n.contains("glúteo") { return theme.dataSleep }
        let tints = [theme.dataStrain, theme.dataHrv, theme.dataSleep]
        return tints[abs(name.hashValue) % tints.count]
    }

    // MARK: - The list

    private var routinesByFolder: [String?: [Routine]] { Dictionary(grouping: routines, by: \.folderId) }

    private var misRutinas: some View {
        let byFolder = routinesByFolder
        let unfiled = byFolder[nil] ?? []
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(folders) { folder in
                    let rs = byFolder[folder.id] ?? []
                    folderHeader(folder, count: rs.count)
                    routineList(rs)
                }
                if !folders.isEmpty && !unfiled.isEmpty {
                    Text("Unfiled").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14).padding(.bottom, 2)
                        .dropHighlight(dropTarget == Self.unfiledDropID, fill: theme.surface, stroke: theme.ink)
                        .dropDestination(for: String.self) { items, _ in handleDrop(onFolder: nil, items) }
                            isTargeted: { setDropTarget(Self.unfiledDropID, $0) }
                }
                routineList(unfiled)

                divider
                actionRow("plus", "New routine") { builderTarget = .new }
                divider
                // The mock folds templates / import / folders into one row; the menu keeps all three
                // functions (choque 9: conserve plantillas, import, carpetas).
                actionMenuRow("rectangle.stack", "Templates · Import · Folders", isPresented: $showToolsMenu, items: [
                    .init(String(localized: "Start from a template"), systemImage: "square.stack.3d.up") { showTemplates = true },
                    .init(String(localized: "Import plan"), systemImage: "square.and.arrow.down") { showImport = true },
                    .init(String(localized: "New folder"), systemImage: "folder.badge.plus") { startNewFolder(moving: nil) }
                ])
                divider
                actionRow("book", "Exercise library", action: openLibrary)
            }
        }
    }

    @ViewBuilder
    private func routineList(_ rs: [Routine]) -> some View {
        ForEach(rs) { r in
            routineRow(r)
            if r.id != rs.last?.id { divider }
        }
    }

    private func folderHeader(_ f: RoutineFolder, count: Int) -> some View {
        let targeted = dropTarget == f.id
        return HStack(spacing: 9) {
            Image(systemName: "folder").font(StrandFont.glyph(.inline)).foregroundStyle(theme.inkTertiary)
            Text(f.name).font(StrandFont.body).foregroundStyle(theme.ink)
            Text("· \(count)").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 0)
            Button { menuFolderId = f.id } label: {
                Image(systemName: "ellipsis").font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary).frame(width: 32, height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .paperMenu(
                isPresented: Binding(get: { menuFolderId == f.id },
                                     set: { if !$0 { menuFolderId = nil } }),
                items: [
                    .init(String(localized: "Rename folder"), systemImage: "pencil") { startRename(f) },
                    .init(String(localized: "Delete folder"), systemImage: "trash", isDestructive: true) { deleteFolder(f) }
                ]
            )
        }
        .padding(.top, 12).padding(.bottom, 2)
        .dropHighlight(targeted, fill: theme.surface, stroke: theme.ink)
        .draggable("f:\(f.id)")
        .dropDestination(for: String.self) { items, _ in handleDrop(onFolder: f.id, items) }
            isTargeted: { setDropTarget(f.id, $0) }
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
        let today = Calendar.current.component(.weekday, from: Date())
        if schedule[today] == r.id { return (String(localized: "today"), true) }
        guard let d = lastTrainedDays[r.id] else { return nil }
        if d <= 0 { return (String(localized: "today"), false) }
        return (d == 1 ? String(localized: "1 d ago") : String(localized: "\(d) d ago"), false)
    }

    @ViewBuilder
    private func routineActions(_ r: Routine) -> some View {
        Button { builderTarget = .edit(r) } label: { Label("Edit routine", systemImage: "slider.horizontal.3") }
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
            .init(String(localized: "Edit routine"), systemImage: "slider.horizontal.3") { builderTarget = .edit(r) },
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
                                    .fill(routineTint(r.name)).frame(width: 8, height: 8)
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
        .draggable("r:\(r.id)")
        .dropDestination(for: String.self) { items, _ in handleDrop(onRoutine: r, items) }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "dumbbell")
                .font(StrandFont.glyph(.empty)).foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text("No routines yet")
                .font(StrandFont.title2).foregroundStyle(theme.ink).multilineTextAlignment(.center)
            Text("Create your first routine, or start from a template.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                QuietButton("New routine") { builderTarget = .new }
                Button { showTemplates = true } label: {
                    Text("Start from a template")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                .buttonStyle(.plain)
                Button { showImport = true } label: {
                    Text("Import plan")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                .buttonStyle(.plain)
                Button(action: openLibrary) {
                    Text("Browse the exercise library")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .instrumentoCard(.card, theme: theme)
    }

    // MARK: - Drag & drop (FER-526)

    private func dragID(_ s: String, _ prefix: Character) -> String? {
        guard let first = s.first, first == prefix, s.dropFirst().first == ":" else { return nil }
        return String(s.dropFirst(2))
    }

    private func setDropTarget(_ id: String, _ targeted: Bool) {
        if targeted { dropTarget = id } else if dropTarget == id { dropTarget = nil }
    }

    private func flattenedRoutineIds() -> [String] {
        let byFolder = routinesByFolder
        var ids = folders.flatMap { (byFolder[$0.id] ?? []).map(\.id) }
        ids += (byFolder[nil] ?? []).map(\.id)
        return ids
    }

    private func handleDrop(onFolder folderId: String?, _ items: [String]) -> Bool {
        dropTarget = nil
        guard let item = items.first else { return false }
        if let rid = dragID(item, "r") {
            if let r = routines.first(where: { $0.id == rid }) { move(r, to: folderId) }
            return true
        }
        if let fid = dragID(item, "f"), let targetFolderId = folderId {
            reorderFolder(fid, before: targetFolderId)
            return true
        }
        return false
    }

    private func handleDrop(onRoutine target: Routine, _ items: [String]) -> Bool {
        guard let item = items.first, let rid = dragID(item, "r"), rid != target.id else { return false }
        var order = flattenedRoutineIds()
        order.removeAll { $0 == rid }
        guard let idx = order.firstIndex(of: target.id) else { return false }
        order.insert(rid, at: idx)
        Task { try? await repo.reorderRoutines(order); await refreshFoldersAndRoutines() }
        return true
    }

    private func reorderFolder(_ draggedId: String, before targetId: String) {
        guard draggedId != targetId else { return }
        var order = folders.map(\.id)
        order.removeAll { $0 == draggedId }
        guard let idx = order.firstIndex(of: targetId) else { return }
        order.insert(draggedId, at: idx)
        Task { try? await repo.reorderFolders(order); await refreshFoldersAndRoutines() }
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
        .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .padding(.horizontal, NoopMetrics.screenPadding)
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

    // MARK: - Folders (FER-494)

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
            await refreshFoldersAndRoutines()
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
            await refreshFoldersAndRoutines()
        }
    }

    private func deleteFolder(_ f: RoutineFolder) {
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await store.deleteFolder(id: f.id)
            await refreshFoldersAndRoutines()
        }
    }

    private func move(_ r: Routine, to folderId: String?) {
        Task {
            guard let store = await repo.storeHandle() else { return }
            try? await store.setRoutineFolder(routineId: r.id, folderId: folderId)
            await refreshFoldersAndRoutines()
        }
    }

    // MARK: - Data

    private func load() async {
        guard let store = await repo.storeHandle() else { loaded = true; return }
        let rs = (try? await store.routines()) ?? []
        let all = await repo.allExercises()
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var counts: [String: Int] = [:]
        var muscles: [String: [String]] = [:]
        for r in rs {
            let exs = (try? await store.routineExercises(routineId: r.id)) ?? []
            counts[r.id] = exs.count
            muscles[r.id] = Self.topMuscles(exs, byId: byId)
        }
        let sched = (try? await store.routineSchedule()) ?? []
        let sessions = (try? await store.recentSessions(limit: 200)) ?? []
        routines = rs
        exerciseCounts = counts
        routineMuscles = muscles
        schedule = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
        lastTrainedDays = Self.daysSinceLast(sessions)
        folders = (try? await store.routineFolders()) ?? []
        loaded = true
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

    private func refreshFoldersAndRoutines() async {
        guard let store = await repo.storeHandle() else { return }
        routines = (try? await store.routines()) ?? []
        folders = (try? await store.routineFolders()) ?? []
    }

    private func exerciseCountText(_ n: Int) -> String { String(localized: "\(n) exercises") }

    private var divider: some View { Divider().overlay(theme.hairline) }
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

private extension View {
    @ViewBuilder
    func dropHighlight(_ targeted: Bool, fill: Color, stroke: Color) -> some View {
        self
            .padding(.horizontal, targeted ? 10 : 0)
            .background(targeted ? fill : .clear, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))   // token-exempt: fondo condicional
            .overlay { if targeted {
                RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous).strokeBorder(stroke, lineWidth: 1.5) } }
            .animation(.snappy, value: targeted)
            .contentShape(Rectangle())
    }
}
#endif
