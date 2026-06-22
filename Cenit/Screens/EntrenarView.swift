#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// MARK: - Entrenar (the Train tab root) — FER-343
//
// The redesigned «Entrenar» hub in the light «Instrumento diurno» language (warm paper, color only on
// the datum, hierarchy by space). It replaces the interim list of rows (FER-342) with a real hub: a
// «Hoy» card carrying the day's routine + a recovery band, the «Mis rutinas» list, and the
// Respira / Intervalos / En-vivo tools. The door to the strength tracker (FER-39 epic).
//
// Navigation, like Cuerpo/Ajustes, is owned by the tab's `NavigationStack` in RootTabView: the hub
// pushes «Rutina de hoy» / Respira / Intervalos via the injected closures, so the screen stays
// decoupled from the private route types. En vivo opens its own sheet (the recorder lives in AppModel).
//
// Out of scope here (each its own issue): the routine builder (FER-346) and the guided session
// (FER-347). Their entry points show an honest «coming soon» note rather than a dead action.

/// Theme wrapper: anchors `\.instrumentoTheme` to the single warm day paper (`.base`), then hands to
/// `EntrenarLanding`, which reads the resolved theme. (FER-398 retired the by-the-hour tint.)
struct EntrenarView: View {
    /// Push «Rutina de hoy» for a given routine id (the tab's NavigationStack owns the path).
    var openRoutine: (String) -> Void
    /// Push the exercise library (browse) onto the tab's NavigationStack.
    var openLibrary: () -> Void
    var openBreathe: () -> Void
    var openIntervals: () -> Void
    var openDiet: () -> Void

    var body: some View {
        EntrenarLanding(openRoutine: openRoutine, openLibrary: openLibrary,
                        openBreathe: openBreathe, openIntervals: openIntervals, openDiet: openDiet)
            .instrumentoTheme(.base)
    }
}

private struct EntrenarLanding: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tabRouter: TabRouter
    @Environment(\.instrumentoTheme) private var theme

    var openRoutine: (String) -> Void
    var openLibrary: () -> Void
    var openBreathe: () -> Void
    var openIntervals: () -> Void
    var openDiet: () -> Void

    @State private var loaded = false
    @State private var routines: [Routine] = []
    @State private var exerciseCounts: [String: Int] = [:]
    /// Drives the routine builder sheet (FER-346): `.new` or `.edit(routine)`.
    @State private var builderTarget: BuilderTarget? = nil
    /// Drives the «start from a template» sheet (FER-386).
    @State private var showTemplates = false
    /// Drives the «import an LLM-generated plan» sheet (FER-496).
    @State private var showImport = false
    /// Which routine row is currently swiped open — only one at a time. FER-491.
    @State private var swipedRoutineId: String? = nil
    /// A just-deleted routine + its exercises, kept in memory so «Undo» can restore it. FER-491.
    @State private var pendingUndo: DeletedRoutine? = nil
    /// User-created folders for «Mis rutinas» (FER-494); empty = the flat list, as before.
    @State private var folders: [RoutineFolder] = []
    /// Drives the «new folder» name alert; `pendingMove` (if set) moves that routine into the new folder.
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var pendingMove: Routine? = nil
    /// The folder being renamed (drives the rename alert) + its draft name.
    @State private var renameFolder: RoutineFolder? = nil
    @State private var renameText = ""

    /// Today's recovery (0–100), nil until a score exists. Drives whether the band shows.
    private var recovery: Double? { repo.today?.recovery }
    /// «Today's» pick: with no scheduler yet (W3·bucle), the most recent/ordered routine stands in.
    private var todayRoutine: Routine? { routines.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header

                if loaded {
                    if let today = todayRoutine {
                        hoyCard(today)
                        misRutinas
                    } else {
                        emptyHoy
                    }
                }

                herramientas
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        // «Undo» toast after a swipe-delete (FER-491): floats above the hub, auto-dismisses in ~4s.
        .overlay(alignment: .bottom) {
            if let d = pendingUndo { undoBanner(d) }
        }
        // Confirm the delete with a haptic; stay silent on the undo (id → nil).
        .sensoryFeedback(trigger: pendingUndo?.id) { _, new in new != nil ? .warning : nil }
        .sheet(item: $builderTarget) { target in
            RoutineBuilderScreen(routine: target.routine) { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        // «Start from a template» (FER-386): a `.sheet` like the builder, reloading the hub on add.
        .sheet(isPresented: $showTemplates) {
            StarterTemplatesSheet { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        // «Import plan» (FER-496): bring in an LLM-generated program. A `.sheet` like the builder,
        // reloading the hub when it creates routines.
        .sheet(isPresented: $showImport) {
            WorkoutImportView { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        // The guided strength session (FER-347). Hosted here at the hub root so it survives pushing
        // «Rutina de hoy» / switching tabs; the session itself lives in AppModel, so swiping the sheet
        // down only hides it (the «Resume» row below re-opens). A `.sheet` — no nested NavigationStack.
        .sheet(isPresented: $model.strengthSheetPresented, onDismiss: {
            // Swiping the summary away ends the session (FER-409); a mid-session swipe keeps it (the
            // «Resume» row re-opens). Only the post-finish receipt carries a `summary`.
            if model.strengthSession?.summary != nil { model.closeStrengthSummary() }
        }) {
            if let session = model.strengthSession {
                LiveStrengthSheet(session: session, theme: theme)
                    .environmentObject(model)
                    .environmentObject(tabRouter)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(theme.paper)
                    .preferredColorScheme(.light)
            }
        }
        // New folder (FER-494): name it, then optionally drop a pending routine into it.
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = ""; pendingMove = nil }
            Button("Create") { createFolder() }
        }
        // Rename folder.
        .alert("Rename folder", isPresented: Binding(get: { renameFolder != nil },
                                                     set: { if !$0 { renameFolder = nil } })) {
            TextField("Folder name", text: $renameText)
            Button("Cancel", role: .cancel) { renameFolder = nil }
            Button("Save") { commitRename() }
        }
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Train").font(StrandFont.title1).foregroundStyle(theme.ink)
            Text("Your plan for today, your routines, and your tools.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - «Hoy» card

    private func hoyCard(_ routine: Routine) -> some View {
        Button { openRoutine(routine.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(routine.name)
                    .font(StrandFont.title2).foregroundStyle(theme.ink)
                    .padding(.top, 3)
                Text(exerciseCountText(exerciseCounts[routine.id] ?? 0))
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .padding(.top, 2)

                if let rec = recovery {
                    Divider().overlay(theme.hairline).padding(.vertical, 14)
                    RecoveryBand(recovery: rec)
                }

                HStack(spacing: 6) {
                    Text("View routine").font(StrandFont.headline).foregroundStyle(theme.ink)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
                .padding(.top, 16)
            }
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens today's routine"))
    }

    // MARK: - «Mis rutinas»

    /// Routines with no folder («Sin carpeta»).
    private var unfiledRoutines: [Routine] { routines.filter { $0.folderId == nil } }
    private func routines(in folder: RoutineFolder) -> [Routine] { routines.filter { $0.folderId == folder.id } }

    private var misRutinas: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("My routines").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: 0) {
                // A section per folder (FER-494), then the unfiled routines. With no folders this is
                // just the flat list, as before — the «Sin carpeta» header only appears alongside folders.
                ForEach(folders) { folder in
                    folderHeader(folder)
                    routineList(routines(in: folder))
                }
                if !folders.isEmpty && !unfiledRoutines.isEmpty {
                    Text("Sin carpeta").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        .padding(.top, 14).padding(.bottom, 2)
                }
                routineList(unfiledRoutines)

                divider
                actionRow("plus", "New routine") { builderTarget = .new }
                divider
                actionRow("folder.badge.plus", "New folder") { startNewFolder(moving: nil) }
                divider
                actionRow("square.stack.3d.up", "Start from a template") { showTemplates = true }
                    .accessibilityHint(Text("Copy a starter routine into My routines"))
            }
        }
    }

    /// The rows for one group of routines, each separated by a hairline.
    @ViewBuilder
    private func routineList(_ rs: [Routine]) -> some View {
        ForEach(rs) { r in
            routineRow(r)
            if r.id != rs.last?.id { divider }
        }
    }

    /// A folder section header: a folder glyph, its name + routine count, and a «⋯» menu to rename or
    /// delete it (deleting keeps its routines, they fall to «Sin carpeta»).
    private func folderHeader(_ f: RoutineFolder) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "folder").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
            Text(f.name).font(StrandFont.body).foregroundStyle(theme.ink)
            Text("· \(routines(in: f).count)").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 0)
            Menu {
                Button { startRename(f) } label: { Label("Rename folder", systemImage: "pencil") }
                Button(role: .destructive) { deleteFolder(f) } label: { Label("Delete folder", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary).frame(width: 32, height: 40).contentShape(Rectangle())
            }
        }
        .padding(.top, 12).padding(.bottom, 2)
    }

    private func actionRow(_ symbol: String, _ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 30)
                    .font(.system(size: 17)).foregroundStyle(theme.inkSecondary)
                Text(title).font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func routineRow(_ r: Routine) -> some View {
        SwipeToDeleteRow(
            isOpen: Binding(get: { swipedRoutineId == r.id },
                            set: { swipedRoutineId = $0 ? r.id : nil }),
            onDelete: { delete(r) }
        ) {
            Button { openRoutine(r.id) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(StrandFont.body).foregroundStyle(theme.ink)
                        Text(exerciseCountText(exerciseCounts[r.id] ?? 0))
                            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
                .frame(minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button { builderTarget = .edit(r) } label: { Label("Edit routine", systemImage: "slider.horizontal.3") }
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
        }
    }

    // MARK: - Delete / undo (FER-491)

    /// One just-deleted routine kept in memory so the «Undo» toast can restore it intact.
    private struct DeletedRoutine: Identifiable {
        let id = UUID()
        let routine: Routine
        let exercises: [RoutineExercise]
    }

    /// Read the routine's exercises (so an undo can restore them), delete it, reload, then show «Undo».
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

    /// The dark «Routine deleted · Undo» toast (Apple Mail pattern). Auto-dismisses after ~4s.
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

    // MARK: - Empty state (no routines yet → CTA, FER-343 criterion)

    private var emptyHoy: some View {
        VStack(spacing: 14) {
            Image(systemName: "dumbbell")
                .font(.system(size: 38, weight: .regular)).foregroundStyle(theme.inkTertiary)
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
                Button { openLibrary() } label: {
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
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: - Tools

    private var herramientas: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tools").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: 0) {
                if model.strengthSession != nil {
                    resumeStrengthRow
                    divider
                }
                LiveWorkoutHubRow()
                divider
                toolRow("Exercise library", "book", action: openLibrary)
                divider
                toolRow("Import plan", "square.and.arrow.down", action: { showImport = true })
                divider
                toolRow("Breathe", "wind", action: openBreathe)
                divider
                toolRow("Intervals", "timer", action: openIntervals)
                divider
                toolRow("Diet", "fork.knife", action: openDiet)
            }
        }
    }

    /// «Resume» the in-progress guided session (FER-347) — shown only while a session runs but its sheet
    /// is dismissed, so the durable session is always one tap away from the hub.
    private var resumeStrengthRow: some View {
        Button { model.resumeStrengthSession() } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.functional").frame(width: 30)
                    .font(.system(size: 17)).foregroundStyle(theme.dataStrain)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Workout in progress").font(StrandFont.body).foregroundStyle(theme.ink)
                    Text(model.strengthSession?.routineName ?? "")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                Text("Resume").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Resume workout in progress"))
    }

    private func toolRow(_ title: LocalizedStringKey, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 30)
                    .font(.system(size: 19)).foregroundStyle(theme.inkSecondary)
                Text(title).font(StrandFont.body).foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bits

    private var divider: some View { Divider().overlay(theme.hairline) }

    private func exerciseCountText(_ n: Int) -> String {
        String(localized: "\(n) exercises")
    }

    // MARK: - Data

    private func load() async {
        guard let store = await repo.storeHandle() else { loaded = true; return }
        let rs = (try? await store.routines()) ?? []
        var counts: [String: Int] = [:]
        for r in rs {
            counts[r.id] = (try? await store.routineExercises(routineId: r.id))?.count ?? 0
        }
        routines = rs
        exerciseCounts = counts
        folders = (try? await store.routineFolders()) ?? []
        loaded = true
    }

    // MARK: - Folders (FER-494)

    private func startNewFolder(moving r: Routine?) {
        pendingMove = r
        newFolderName = ""
        showNewFolder = true
    }

    /// Create the folder, then (if invoked from a routine's «Move to…») drop that routine into it.
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

    private func startRename(_ f: RoutineFolder) {
        renameText = f.name
        renameFolder = f
    }

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

    /// Delete a folder; its routines stay (they fall to «Sin carpeta»).
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
}

// MARK: - Recovery band (the «sube / mantén / baja» autoregulation suggestion — FER-349)

/// The recovery band: an OPT-IN "push / hold / ease" suggestion shown before a session, driven by the
/// cited `TrainingRegulation` rule (StrandAnalytics) rather than ad-hoc cuts. It maps today's recovery
/// to the app's canonical recovery bands and carries a fixed "suggestion · you decide" label — it
/// never gates training. It **never appears without a recovery score** (the rule returns nil and the
/// caller hides the slot — no invented advice).
struct RecoveryBand: View {
    @Environment(\.instrumentoTheme) private var theme
    let recovery: Double

    /// The cited rule. The score-only path uses the canonical recovery bands; a personal z is preferred
    /// when a caller has it (not plumbed here yet).
    private var suggestion: TrainingRegulation.Suggestion? {
        TrainingRegulation.suggest(recovery: recovery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recovery band").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if let s = suggestion {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(word(s.adjustment))
                        .font(StrandFont.title2).foregroundStyle(color(s.adjustment))
                    Text(detail(s.reason))
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
                        .accessibilityHidden(true)
                    Text("Suggestion · you decide")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func word(_ a: TrainingRegulation.Adjustment) -> LocalizedStringKey {
        switch a {
        case .dialUp:   return "Push"
        case .hold:     return "Hold"
        case .dialBack: return "Ease"
        }
    }

    private func color(_ a: TrainingRegulation.Adjustment) -> Color {
        switch a {
        case .dialUp:   return theme.verdict   // recovered — push (green)
        case .hold:     return theme.ink       // within your normal — no color
        case .dialBack: return theme.warning   // under-recovered — ease off (amber)
        }
    }

    private func detail(_ reason: TrainingRegulation.Reason) -> String {
        let n = Int(recovery.rounded())
        switch reason {
        case .recoveryHigh:  return String(localized: "Recovery \(n) · high. A good day to add load.")
        case .withinNormal:  return String(localized: "Recovery \(n) · moderate. Keep your usual load.")
        case .recoveryLow:   return String(localized: "Recovery \(n) · low. Pull back the volume today.")
        }
    }
}

// MARK: - Honest «coming soon» sheet (for builder/guided start — FER-346 / FER-347)

/// A quiet Instrumento sheet that names what's coming, instead of a dead button. Used by the routine
/// builder entry points until FER-346 ships.
struct TrainingSoonSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    let overline: LocalizedStringKey
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(overline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(title).font(StrandFont.title1).foregroundStyle(theme.ink)
            }
            Text(message)
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.paper.ignoresSafeArea())
    }
}

// MARK: - Swipe-to-delete row (FER-491)

/// A row that slides left under a horizontal drag to reveal a destructive «Delete» button, while
/// keeping the «Instrumento» look (the row sits on warm paper — no `List` chrome). A full-swipe past a
/// threshold deletes directly; a half-swipe parks the button open; opening another row (or deleting)
/// closes it via the `isOpen` binding. The wrapped content keeps its own tap + context menu — the drag
/// only engages once the finger moves horizontally, so a tap or long-press still reaches the content.
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
                    .font(.system(size: 18, weight: .semibold))
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
#endif
