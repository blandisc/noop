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
    /// Planned work-set volume per routine, split into the four coarse groups (mock 1b's mini-bars +
    /// weekly footer). Built from each routine's exercises' primary muscles. `[routineId: [group: sets]]`.
    @State private var routineVolume: [String: [MuscleGroup: Int]] = [:]

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
                        volumeFooter
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
            Text("Your week, in balance").font(StrandFont.title1).foregroundStyle(theme.ink)
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 52)
            .padding(.horizontal, wd == today ? 10 : 0)
            .background {
                if wd == today {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surface)
                }
            }
            .contentShape(Rectangle())
        }
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

    /// A routine in the picker — a checkmark marks the one currently assigned to this day. `r.name` is
    /// user data → verbatim.
    private func routinePick(_ wd: Int, _ r: Routine) -> some View {
        Button { assign(wd, r.id) } label: {
            if schedule[wd] == r.id { Label(r.name, systemImage: "checkmark") }
            else { Text(r.name) }
        }
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
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
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
        // Planned volume per routine, bucketed into the four groups (mock 1b mini-bars + footer). Each
        // exercise's work sets are attributed to its dominant group, so the per-routine sum is total sets.
        let all = await repo.allExercises()
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String: [MuscleGroup: Int]] = [:]
        for r in routines {
            let exs = await repo.routineExercises(routineId: r.id)
            var byGrp: [MuscleGroup: Int] = [:]
            for re in exs {
                guard let ex = byId[re.exerciseId], let g = exerciseGroup(ex) else { continue }
                let work = re.sets.filter { $0.kind == .work }.count
                byGrp[g, default: 0] += work > 0 ? work : re.targetSets
            }
            out[r.id] = byGrp
        }
        routineVolume = out
        await reloadSchedule()
        loaded = true
    }

    /// An exercise's dominant group: the most-represented group across its primary muscles (nil if none map).
    private func exerciseGroup(_ ex: Exercise) -> MuscleGroup? {
        var tally: [MuscleGroup: Int] = [:]
        for m in ex.primaryMuscles { if let g = MuscleGroup.of(m) { tally[g, default: 0] += 1 } }
        return tally.max { $0.value < $1.value }?.key
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
