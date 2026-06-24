#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - Weekly plan editor (FER-533) — «Entrenar v2 · La Semana», F2 of FER-530
//
// Assign a routine to each weekday, or leave a day as rest. The split it writes (via the F1 store CRUD,
// FER-531) is what the redesigned landing (F3) reads for the week strip and «today's routine». Reached
// for now from a temporary «Weekly plan» row on the Entrenar landing; F3 opens it from «Tu plan / Editar».
//
// «Instrumento diurno»: an editor has no measured datum, so there is NO saturated color anywhere — the
// assigned-vs-rest contrast is carried by ink WEIGHT (a routine name in `ink` vs «Rest» in `inkDim`),
// hierarchy by space + hairlines, no card-in-card. Tapping a day opens a native `Menu` of routines
// (grouped by folder, FER-494) plus «Rest» to clear it.

struct WeeklyPlanEditorView: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.instrumentoTheme) private var theme

    /// Push «Mis rutinas» — the single home for create / import / templates / library + folders (F4).
    var openRoutines: () -> Void

    @State private var loaded = false
    @State private var routines: [Routine] = []
    @State private var folders: [RoutineFolder] = []
    /// The split as `weekday → routineId` (Calendar weekday convention, 1 = Sun … 7 = Sat).
    @State private var schedule: [Int: String] = [:]

    /// Monday-first display order in the Calendar weekday convention (2 = Mon … 1 = Sun).
    private let weekdays = [2, 3, 4, 5, 6, 7, 1]
    private var today: Int { Calendar.current.component(.weekday, from: Date()) }
    private var assignedCount: Int { schedule.count }

    /// Routines not shown under any listed folder — `folderId == nil`, or a folder that no longer exists.
    private var unfiledRoutines: [Routine] {
        let ids = Set(folders.map(\.id))
        return routines.filter { $0.folderId == nil || !ids.contains($0.folderId!) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header
                if loaded {
                    if routines.isEmpty {
                        emptyState
                    } else {
                        weekSection
                        manageSection
                    }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Train").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("Weekly plan").font(StrandFont.title1).foregroundStyle(theme.ink)
            if loaded && !routines.isEmpty {
                Text(summaryText)
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summaryText: String {
        String(localized: "\(assignedCount) of 7 days planned · tap a day to change it")
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

    /// One day: its weekday label (today marked), the assigned routine or «Rest», and a chevron. The whole
    /// row is the label of a `Menu` that picks a routine (grouped by folder) or clears the day.
    private func dayRow(_ wd: Int) -> some View {
        Menu {
            Button { clear(wd) } label: {
                Label("Rest", systemImage: schedule[wd] == nil ? "checkmark" : "moon.zzz")
            }
            ForEach(folders) { folder in
                let rs = routines.filter { $0.folderId == folder.id }
                if !rs.isEmpty {
                    Section(folder.name) { ForEach(rs) { routinePick(wd, $0) } }
                }
            }
            // Everything not in a listed folder (including a routine whose folder was deleted) so no
            // routine is ever un-pickable.
            let unfiled = unfiledRoutines
            if !unfiled.isEmpty {
                Section { ForEach(unfiled) { routinePick(wd, $0) } }
            }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(weekdayLabel(wd))
                        .font(StrandFont.mono)
                        .foregroundStyle(wd == today ? theme.ink : theme.inkSecondary)
                    if wd == today {
                        Text("today").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                }
                .frame(width: 52, alignment: .leading)

                if let rid = schedule[wd], let r = routines.first(where: { $0.id == rid }) {
                    Text(r.name).font(StrandFont.body).foregroundStyle(theme.ink)
                } else {
                    Text("Rest").font(StrandFont.body).foregroundStyle(theme.inkDim)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 52).contentShape(Rectangle())
        }
    }

    /// A routine in the picker — a checkmark marks the one currently assigned to this day. `r.name` is
    /// user data → verbatim.
    private func routinePick(_ wd: Int, _ r: Routine) -> some View {
        Button { assign(wd, r.id) } label: {
            if schedule[wd] == r.id { Label(r.name, systemImage: "checkmark") }
            else { Text(r.name) }
        }
    }

    // MARK: - Manage (single link to the routine home — F4/F5)
    //
    // Create / import / templates / library all live in «Mis rutinas» now; the editor only assigns a
    // routine to each day and links there.

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Routines").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Button(action: openRoutines) {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet").frame(width: 30)
                        .font(.system(size: 18)).foregroundStyle(theme.inkSecondary)
                    Text("Manage routines").font(StrandFont.body).foregroundStyle(theme.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
                .frame(minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty state (no routines yet → can't assign)

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 38, weight: .regular)).foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text("Create a routine first")
                .font(StrandFont.title2).foregroundStyle(theme.ink).multilineTextAlignment(.center)
            Text("You need at least one routine to plan your week.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button { openRoutines() } label: {
                Text("Go to My routines").font(StrandFont.headline).foregroundStyle(theme.paperHi)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: - Bits

    private var divider: some View { Divider().overlay(theme.hairline) }

    /// Localized short weekday name (respects the user's locale), capitalized and without a trailing dot.
    private func weekdayLabel(_ wd: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols   // index 0 = Sunday … 6 = Saturday
        let raw = symbols[(wd - 1) % 7]
        return raw.replacingOccurrences(of: ".", with: "").capitalized
    }

    // MARK: - Data (writes the split via the F1 store CRUD, FER-531)

    private func load() async {
        guard let store = await repo.storeHandle() else { loaded = true; return }
        routines = (try? await store.routines()) ?? []
        folders = (try? await store.routineFolders()) ?? []
        await reloadSchedule()
        loaded = true
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
#endif
