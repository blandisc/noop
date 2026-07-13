#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandTraining

// WorkoutHistoryScreen.swift — «Mis entrenamientos» (FER-504): the completed strength sessions, newest
// first, each opening a per-exercise breakdown. Read-only — it never edits or deletes a session. Pure
// «Instrumento diurno»: warm paper, weights/sets in ink, the only color on the *physiological* datum
// (effort/strain and heart rate, in `dataStrain`). The data already exists (strengthSession + setEntry,
// FER-345); this is the screen that finally surfaces it. Pushed onto the Entrenar NavigationStack.

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
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @EnvironmentObject private var coordinator: WorkoutHistoryCoordinator
    @State private var sessions: [StrengthSession] = []
    @State private var routineNames: [String: String] = [:]
    @State private var volumes: [String: (volumeKg: Double, setCount: Int)] = [:]
    /// Trailing-30-day muscle set events for the compact «Volume per muscle» summary (FER-719 math).
    @State private var muscleEvents: [MuscleFatigueMap.MuscleSetEvent] = []
    /// Progression signals (raised / waiting / stalled) for exercises with progression enabled.
    @State private var progressionRows: [ProgressionRow] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                header
                if loaded {
                    if sessions.isEmpty {
                        emptyState
                    } else {
                        // Handoff v2 order: «Tu mes» (bars then totals) → progression → volume per muscle.
                        weeklyBars
                        monthlyTotal
                        progressionBlock
                        muscleVolumeInline
                        list
                        savedTicketsEntry
                    }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        // The detail push (`WorkoutSessionRoute`) is registered once on the Entrenar NavigationStack in
        // RootTabView (alongside the other train routes), so it isn't re-declared here.
        // «Undo» toast after a delete (FER-527), now seeded by the list OR the detail via the coordinator.
        .overlay(alignment: .bottom) { if let d = coordinator.pendingUndo { undoBanner(d) } }
        .sensoryFeedback(trigger: coordinator.pendingUndo?.id) { _, new in new != nil ? .warning : nil }
        // Reloads on first appear (token 0) and whenever a delete/edit deeper in the stack bumps it.
        .task(id: coordinator.reloadToken) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            InstrumentoFlowTitle(Text("On the rise"))
            // Handoff v2: sessions this month, plus the count of load raises when any (from progression).
            Group {
                if raisedThisMonth > 0 {
                    Text("\(monthAggregate.count) sessions this month · \(raisedThisMonth) load raises")
                } else {
                    Text("\(monthAggregate.count) sessions this month")
                }
            }
            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            // «Volumen por músculo» (Entrenar v3 · 3d, FER-719) — the history's stats view.
            NavigationLink(value: MuscleVolumeRoute()) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis").font(StrandFont.glyph(.chevron, weight: .semibold))
                    Text("Volume per muscle").font(StrandFont.caption).fontWeight(.semibold)
                    StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                }
                .foregroundStyle(theme.inkSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    // MARK: - Monthly total (v3 · 1m) — sessions · hours · kg · kcal, this calendar month

    private var monthlyTotal: some View {
        let m = monthAggregate
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("This month").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                if let delta = monthVolumeDeltaPercent {
                    let up = delta >= 0
                    let n = Int(delta.rounded())
                    HStack(spacing: 3) {
                        Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                        Text("\(up ? "+" : "")\(n)% vs last month")
                    }
                    .font(StrandFont.caption)
                    .foregroundStyle(up ? theme.dataRecovery : theme.warning)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) { monthCells(m) }
                VStack(alignment: .leading, spacing: 10) { monthCells(m) }
            }
        }
    }

    @ViewBuilder
    private func monthCells(_ m: MonthAggregate) -> some View {
        stat("Sessions", "\(m.count)", color: theme.ink)
        if m.hours > 0 { stat("Hours", String(format: "%.1f", m.hours), color: theme.ink) }
        if m.volumeKg > 0 { stat("Volume", StrengthHistoryFormat.volume(m.volumeKg, system: system), color: theme.ink) }
        // kcal only when at least one session in the month carries it (never a fabricated 0).
        if let kcal = m.energyKcal { stat("Energy", StrandFormat.groupedInt(kcal), unit: "kcal", color: theme.ink) }
    }

    // MARK: - Weekly volume bars (v3 · 1m) — last 8 weeks, the current week in `dataRecovery`

    @ViewBuilder
    private var weeklyBars: some View {
        let weeks = weeklyVolumes
        if weeks.contains(where: { $0.volumeKg > 0 }) {
            let peak = max(weeks.map(\.volumeKg).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("Volume per week").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(weeks) { w in
                        RoundedRectangle(cornerRadius: 3, style: .continuous) // token-exempt: geometría de dato
                            .fill(w.isCurrent ? theme.dataRecovery : theme.hairlineStrong)
                            .frame(height: max(3, CGFloat(w.volumeKg / peak) * 54))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 54)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Volume over the last 8 weeks"))
            }
        }
    }

    // MARK: - Volume per muscle (compact inline summary, trailing 30 d)

    @ViewBuilder
    private var muscleVolumeInline: some View {
        let volumes = MuscleFatigueMap.weeklyVolumes(events: muscleEvents, days: 30)
        if !volumes.isEmpty {
            let railTop = MuscleFatigueMap.weeklyVolumeRailTop
            VStack(alignment: .leading, spacing: 8) {
                Text("Volume per muscle").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                VStack(spacing: 0) {
                    ForEach(volumes, id: \.muscle) { v in
                        let below = v.band == .below
                        HStack(spacing: 12) {
                            Text(MuscleAtlas.name(v.muscle))
                                .font(StrandFont.body).foregroundStyle(theme.ink)
                                .lineLimit(1).minimumScaleFactor(0.85)
                                .frame(width: 96, alignment: .leading)
                            GeometryReader { geo in
                                let w = geo.size.width
                                let lo = MuscleFatigueMap.weeklyBandLow / railTop
                                let hi = MuscleFatigueMap.weeklyBandHigh / railTop
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(theme.hairline)  // token-exempt: geometría de dato
                                        .frame(width: w * (hi - lo), height: 14)
                                        .offset(x: w * lo)
                                    RoundedRectangle(cornerRadius: 3)  // token-exempt: geometría de dato
                                        .fill(below ? theme.warning : theme.ink)
                                        .frame(width: max(4, w * min(v.setsPerWeek, railTop) / railTop), height: 6)
                                }
                                .frame(height: 14, alignment: .leading)
                            }
                            .frame(height: 14)
                            Text(MuscleFatigueMap.formattedSets(v.setsPerWeek))
                                .font(StrandFont.captionNumber)
                                .fontWeight(below ? .semibold : .regular)
                                .foregroundStyle(below ? theme.warning : theme.ink)
                                .frame(width: 34, alignment: .trailing)
                        }
                        .frame(minHeight: 40)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(MuscleAtlas.name(v.muscle)))
                        .accessibilityValue(Text("\(MuscleFatigueMap.formattedSets(v.setsPerWeek)) sets per week"))
                    }
                }
            }
        }
    }

    // MARK: - Your progression (raised / waiting / stalled signals)

    @ViewBuilder
    private var progressionBlock: some View {
        if !progressionRows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your progression").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                ForEach(progressionRows) { row in
                    HStack(spacing: 10) {
                        Text(row.name)
                            .font(StrandFont.body).foregroundStyle(theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: 8)
                        switch row.kind {
                        case .raised(let kg):
                            HStack(spacing: 4) {
                                StrandIcon.up.image
                                Text(StrengthDisplay.weight(kg, system: system))
                            }
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.dataRecovery)
                            .monospacedDigit()
                        case .deferred(let kg):
                            HStack(spacing: 4) {
                                Text("…")
                                Text(StrengthDisplay.weight(kg, system: system))
                            }
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkTertiary)
                            .monospacedDigit()
                        case .stalled:
                            Text("=")
                                .font(StrandFont.caption)
                                .foregroundStyle(theme.warning)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(sessions) { session in
                NavigationLink(value: route(for: session)) {
                    sessionCard(session)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) { delete(session) } label: {
                        Label("Delete workout", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Saved tickets entry (thermal receipts peek)

    private var savedTicketsEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: SavedTicketsRoute()) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                        .fill(theme.hairline)
                        .frame(width: 38, height: 38)
                        .overlay(
                            Image(systemName: "doc.plaintext")
                                .font(StrandFont.glyph(.inline, weight: .semibold))
                                .foregroundStyle(theme.ink)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My saved tickets").font(StrandFont.title2).foregroundStyle(theme.ink)
                        Text("\(sessions.count) receipts · today's on top")
                            .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    StrandIcon.disclosure.image
                        .font(StrandFont.glyph(.chevron, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary)
                }
                .padding(CenitMetrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
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

            BarraAncla(
                String(localized: "Each session saves its receipt. Open them to reprint or share."),
                color: theme.dataStrain,
                theme: theme
            )
        }
    }

    private func sessionCard(_ session: StrengthSession) -> some View {
        let vol = volumes[session.id]
        return VStack(alignment: .leading, spacing: 0) {
            Text(StrengthHistoryFormat.dateTime(session.startTs)).instrumentoOverline()
                .foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name(for: session)).font(StrandFont.title2).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                StrandIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.top, 3)

            // The numbers reflow to a column at large Dynamic Type so nothing clips.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) { statCells(session, vol) }
                VStack(alignment: .leading, spacing: 10) { statCells(session, vol) }
            }
            .padding(.top, 12)
        }
        .padding(CenitMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private func statCells(_ session: StrengthSession, _ vol: (volumeKg: Double, setCount: Int)?) -> some View {
        if let mins = StrengthHistoryFormat.durationMinutes(start: session.startTs, end: session.endTs) {
            stat("Duration", StrengthHistoryFormat.durationText(mins), color: theme.ink)
        }
        if let vol, vol.volumeKg > 0 {
            stat("Volume", StrengthHistoryFormat.volume(vol.volumeKg, system: system), color: theme.ink)
        }
        // The physiological datum carries the only color (Instrumento). Omitted — never faked — when
        // the session was logged without a strap.
        if let strain = session.strain {
            stat("Effort", StrengthHistoryFormat.strain(strain), color: theme.dataStrain)
        }
        if let hr = session.avgHr {
            stat("Avg HR", "\(hr)", unit: "bpm", color: theme.dataStrain)
        }
        // kcal per session (FER-715/718): omitted cleanly for a pre-v26 session (nil), never shown as 0.
        if let k = session.energyKcal {
            stat("Energy", StrandFormat.groupedInt(k), unit: "kcal", color: theme.ink)
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: String,
                      unit: LocalizedStringKey? = nil, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(StrandFont.number(18, weight: .semibold)).foregroundStyle(color)
                    .monospacedDigit()
                if let unit { Text(unit).font(StrandFont.caption).foregroundStyle(theme.inkTertiary) }
            }
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "clock.arrow.circlepath")
                .font(StrandFont.glyph(.empty)).foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text("No workouts yet").font(StrandFont.title2).foregroundStyle(theme.ink)
            Text("When you finish a strength session, it shows up here with its breakdown, volume and effort.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    // MARK: - Monthly + weekly aggregates (v3 · 1m)

    private struct MonthAggregate { let count: Int; let hours: Double; let volumeKg: Double; let energyKcal: Double? }

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

    /// Count of exercises whose cycle just raised (the hero's «N subidas de carga»), from the same
    /// progression signals the «Your progression» block shows.
    private var raisedThisMonth: Int {
        progressionRows.filter { if case .raised = $0.kind { return true }; return false }.count
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

    private struct WeekVolume: Identifiable { let id: Int; let volumeKg: Double; let isCurrent: Bool }

    /// Total volume per week over the last 8 weeks (oldest→newest), Monday-anchored. The last bucket is
    /// the current week (drawn in `dataRecovery`).
    private var weeklyVolumes: [WeekVolume] {
        var cal = Calendar.current; cal.firstWeekday = 2
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        var buckets = [Double](repeating: 0, count: 8)
        for s in sessions where s.endTs != nil {
            let date = Date(timeIntervalSince1970: TimeInterval(s.startTs))
            guard let ws = cal.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            let weeksAgo = cal.dateComponents([.weekOfYear], from: ws, to: thisWeekStart).weekOfYear ?? 0
            guard weeksAgo >= 0, weeksAgo < 8 else { continue }
            buckets[7 - weeksAgo] += volumes[s.id]?.volumeKg ?? 0
        }
        return buckets.enumerated().map { WeekVolume(id: $0.offset, volumeKg: $0.element, isCurrent: $0.offset == 7) }
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

    /// Read the session's sets (so an undo can restore them), delete it (the store recomputes the affected
    /// PRs), reload, then show «Undo» via the coordinator.
    private func delete(_ session: StrengthSession) {
        Task {
            let sets = await repo.sessionSets(sessionId: session.id)
            try? await repo.deleteSession(id: session.id)
            await load()
            withAnimation { coordinator.pendingUndo = .init(session: session, sets: sets) }
        }
    }

    private func undoDelete(_ d: WorkoutHistoryCoordinator.DeletedSession) {
        Task {
            try? await repo.saveSession(d.session, sets: d.sets)   // re-saving re-derives its PRs
            await load()
            withAnimation { coordinator.pendingUndo = nil }
        }
    }

    private func undoBanner(_ d: WorkoutHistoryCoordinator.DeletedSession) -> some View {
        HStack(spacing: 12) {
            Text("Workout deleted").font(StrandFont.subhead).foregroundStyle(theme.surface)
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
            withAnimation { if coordinator.pendingUndo?.id == d.id { coordinator.pendingUndo = nil } }
        }
    }

    private func load() async {
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
        let (sessions, routines, volumes, muscleEvents) = await (s, r, v, muscle)
        self.sessions = sessions
        self.routineNames = Dictionary(routines.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        self.volumes = volumes
        self.muscleEvents = muscleEvents
        self.loaded = true
        // Progression can take a beat (routines × exercises); paint the rest of the screen first.
        self.progressionRows = await loadProgressionRows()
    }

    /// Exercises with progression enabled (deduped by exerciseId, first routine slot wins — same rule as
    /// ExerciseDetailScreen), classified into raised / deferred / stalled. Cap ~6 rows.
    private func loadProgressionRows() async -> [ProgressionRow] {
        let inventory = await MainActor.run { PlatesStore().inventory }
        let recovery = repo.today?.recovery
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
            let seed = await repo.sessionSeed(re: re, exercise: ex, inventory: inventory, recovery: recovery)
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
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var coordinator: WorkoutHistoryCoordinator
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    /// Drives «Duplicar como rutina» — a routine builder pre-filled with this session's exercises (2A).
    @State private var showDuplicate = false
    /// The routine the duplicate-builder just created; pushed onto «Rutina» when its sheet finishes
    /// dismissing (pushing mid-dismiss stacks transitions, FER-171 lesson).
    @State private var savedRoutineId: String? = nil

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                heading
                hero
                Divider().overlay(theme.hairline)
                secondaries
                if loaded {
                    ForEach(Array(groups.enumerated()), id: \.element.exerciseId) { idx, g in
                        Divider().overlay(theme.hairline)
                        exerciseBlock(g, index: idx)
                    }
                    Divider().overlay(theme.hairline)
                    actions
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        // «Editar» / «Borrar entrenamiento» — visible from the detail, so deleting no longer needs the
        // list's long-press, and editing a saved session is finally possible (FER-556).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMoreMenu = true } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(theme.ink)
                }
                .accessibilityLabel(Text("More options"))
                .paperMenu(isPresented: $showMoreMenu, items: [
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
        .instrumentoConfirm(
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
                        Button("Done") { detailExercise = nil }.foregroundStyle(theme.ink)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
            }
            .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .sheet(isPresented: $showEdit) {
            if let s = fullSession {
                WorkoutEditSheet(session: s, sets: allSets) { await onEdited() }
                    .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
            }
        }
        // «Duplicar como rutina» (2A): a routine builder pre-filled with this session's exercises. Saving
        // creates a NEW routine (never touches this session) and opens it on «Rutina» once the sheet is
        // down (FER-840). Theme/repo passed explicitly across the sheet.
        .sheet(isPresented: $showDuplicate, onDismiss: {
            if let id = savedRoutineId { savedRoutineId = nil; openRoutine?(id) }
        }) {
            RoutineBuilderScreen(seedName: duplicateName, seed: duplicateSeed) { id in savedRoutineId = id }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .task { await load() }
    }

    // MARK: - Parity actions (v3 · 2A) — «Duplicar como rutina» + «Repetir hoy»

    private var actions: some View {
        VStack(spacing: 10) {
            StrandCTAButton("Repeat today") { repeatToday() }
                .disabled(groups.isEmpty)
            StrandCTAButton("Duplicate as routine", kind: .outline) { showDuplicate = true }
                .disabled(groups.isEmpty)
        }
    }

    /// This session's exercises re-based onto builder items for «Duplicar como rutina». Each exercise gets
    /// as many sets as it had work sets in the session, carrying the logged reps/weight as the targets.
    private var duplicateSeed: [(re: RoutineExercise, exercise: Exercise)] {
        groups.compactMap { g in
            guard let ex = exercisesByID[g.exerciseId] else { return nil }
            let work = g.sets.filter { $0.kind == .work }
            let sets = work.enumerated().map { i, s in
                RoutineSet(position: i, kind: .work, reps: s.reps, weightKg: s.weightKg)
            }
            let re = RoutineExercise(routineId: "", exerciseId: g.exerciseId, position: 0,
                                     targetSets: max(1, sets.count),
                                     targetReps: work.first?.reps, targetWeightKg: work.first?.weightKg,
                                     supersetGroup: supersetGroup(g.exerciseId), sets: sets)
            return (re, ex)
        }
    }

    private var duplicateName: String {
        dispRoutineName == String(localized: "Strength workout") ? String(localized: "New routine") : dispRoutineName
    }

    /// «Repetir hoy» (2A): start a fresh guided session from this session's exercises. Reuses each
    /// exercise's logged sets as its plan (targets + «la última vez» reference).
    private func repeatToday() {
        // The plan comes from each exercise's re.sets (targets); `lastSets` is the «la última vez» prefill,
        // left empty here so the session model seeds straight from the planned sets.
        let slots: [StrengthSessionModel.PlanSlot] = duplicateSeed.map { item in
            StrengthSessionModel.PlanSlot(re: item.re, exercise: item.exercise, lastSets: [])
        }
        guard !slots.isEmpty else { return }
        model.startStrengthSession(routineId: dispRoutineId, routineName: dispRoutineName, slots: slots)
    }

    /// Delete from the detail: read the sets (so an undo can restore them), delete (the store recomputes
    /// the affected PRs), seed the coordinator's «Undo» + reload, then pop back to the list (FER-556).
    private func performDelete() {
        Task {
            let sets = allSets.isEmpty ? await repo.sessionSets(sessionId: route.id) : allSets
            try? await repo.deleteSession(id: route.id)
            let session = fullSession ?? StrengthSession(id: route.id, startTs: route.startTs,
                                                         endTs: route.endTs, strain: route.strain, avgHr: route.avgHr)
            coordinator.pendingUndo = .init(session: session, sets: sets)
            coordinator.bumpReload()
            dismiss()
        }
    }

    /// After the edit sheet saves: reload the detail in place and bump the list so its row reflects the
    /// new date/routine/volume when popped back to.
    private func onEdited() async {
        await load()
        coordinator.bumpReload()
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 3) {
            InstrumentoFlowTitle(overline: Text(StrengthHistoryFormat.dateTime(dispStart)),
                                 Text(verbatim: dispRoutineName))
        }
    }

    // Effort (strain) is the hero in the effort hue, or duration in ink when the session had no HR —
    // the same rule as the post-session receipt (FER-409).
    @ViewBuilder
    private var hero: some View {
        if let strain = dispStrain {
            heroStat("Effort", StrengthHistoryFormat.strain(strain), unit: nil,
                     color: theme.dataStrain, caption: "What this session cost your body.")
        } else if let mins = StrengthHistoryFormat.durationMinutes(start: dispStart, end: dispEnd) {
            heroStat("Duration", "\(mins)", unit: "min",
                     color: theme.ink, caption: "No heart rate this session.")
        }
    }

    private func heroStat(_ label: LocalizedStringKey, _ value: String, unit: String?,
                          color: Color, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).instrumentoHero(54).foregroundStyle(color)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                if let unit { Text(unit).font(StrandFont.unit).foregroundStyle(theme.inkTertiary) }
            }
            Text(caption).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var secondaries: some View {
        let cells = Group {
            if volumeKg > 0 { detailStat("Volume", StrengthHistoryFormat.volume(volumeKg, system: system)) }
            detailStat("Sets", "\(setCount)")
            // Duration is the hero when there's no strain → don't repeat it as a secondary.
            if dispStrain != nil,
               let mins = StrengthHistoryFormat.durationMinutes(start: dispStart, end: dispEnd) {
                detailStat("Duration", StrengthHistoryFormat.durationText(mins))
            }
            if let hr = dispAvgHr { detailStat("Avg HR", "\(hr)") }
            // Energy only when the session actually carries it (FER-715/718): a pre-v26 session leaves
            // `energyKcal` nil → the cell is omitted (never a fabricated 0).
            if let k = dispEnergyKcal { detailStat("Energy", StrandFormat.groupedInt(k)) }
        }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) { cells; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 12) { cells }
        }
    }

    private func detailStat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(StrandFont.number(19, weight: .semibold)).foregroundStyle(theme.ink)
                .monospacedDigit()
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
        }
        .frame(minWidth: 60, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func exerciseBlock(_ g: (exerciseId: String, name: String, sets: [SetEntry]), index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // A superset tag when this exercise shares its routine's `supersetGroup` with an adjacent one
            // in performed order (v3 · 2A). The datum here is anatomical/structural, so it stays in ink.
            if isInSuperset(index) {
                Text("Superset").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .padding(.bottom, 4)
            }
            exerciseTitle(g)
                .padding(.bottom, 6)
            ForEach(Array(g.sets.enumerated()), id: \.element.id) { idx, set in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Set \(idx + 1)").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                    if isPRSet(set, exerciseId: g.exerciseId) {
                        Text("PR").font(StrandFont.captionNumber).foregroundStyle(theme.dataStrain)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(theme.dataStrain.opacity(0.5), lineWidth: 1)) // token-exempt: stroke chip PR 0.5 (alfa propio)
                            .accessibilityLabel(Text("Personal record"))
                    }
                    Spacer(minLength: 8)
                    Text(StrengthHistoryFormat.setLine(set, system: system))
                        .font(StrandFont.subhead).foregroundStyle(theme.ink).monospacedDigit()
                }
                .padding(.vertical, 5)
                .overlay(alignment: .top) {
                    if idx > 0 { Divider().overlay(theme.hairline) }
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
                HStack(spacing: 6) {
                    Text(g.name).font(StrandFont.headline).foregroundStyle(theme.ink)
                    StrandIcon.disclosure.image
                        .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the exercise"))
        } else {
            Text(g.name).font(StrandFont.headline).foregroundStyle(theme.ink)
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

    /// Total volume in the user's unit, with thousands grouping: "3,325 kg" / "7,330 lb".
    static func volume(_ kg: Double, system: UnitSystem) -> String {
        let value = system == .imperial ? UnitFormatter.kgToPounds(kg) : kg
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let num = f.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
        return "\(num) \(StrengthDisplay.weightUnit(system))"
    }

    static func strain(_ v: Double) -> String { String(format: "%.1f", v) }

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
