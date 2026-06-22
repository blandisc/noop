#if os(iOS)
import SwiftUI
import StrandDesign
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

// MARK: - List

struct WorkoutHistoryScreen: View {
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State private var sessions: [StrengthSession] = []
    @State private var routineNames: [String: String] = [:]
    @State private var volumes: [String: (volumeKg: Double, setCount: Int)] = [:]
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header
                if loaded {
                    if sessions.isEmpty { emptyState } else { list }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        // The detail push (`WorkoutSessionRoute`) is registered once on the Entrenar NavigationStack in
        // RootTabView (alongside the other train routes), so it isn't re-declared here.
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("My workouts").font(StrandFont.title1).foregroundStyle(theme.ink)
            Text("The strength sessions you've finished.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sessions) { session in
                NavigationLink(value: route(for: session)) {
                    sessionCard(session)
                }
                .buttonStyle(.plain)
            }
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.top, 3)

            // The numbers reflow to a column at large Dynamic Type so nothing clips.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) { statCells(session, vol) }
                VStack(alignment: .leading, spacing: 10) { statCells(session, vol) }
            }
            .padding(.top, 12)
        }
        .padding(NoopMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
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
                .font(.system(size: 32, weight: .regular)).foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text("No workouts yet").font(StrandFont.title2).foregroundStyle(theme.ink)
            Text("When you finish a strength session, it shows up here with its breakdown, volume and effort.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    // MARK: - Derived

    private func name(for session: StrengthSession) -> String {
        session.routineId.flatMap { routineNames[$0] } ?? String(localized: "Strength workout")
    }

    private func route(for session: StrengthSession) -> WorkoutSessionRoute {
        WorkoutSessionRoute(id: session.id, startTs: session.startTs, endTs: session.endTs,
                            strain: session.strain, avgHr: session.avgHr, routineName: name(for: session))
    }

    private func load() async {
        async let s = repo.recentSessions()
        async let r = repo.routines()
        async let v = repo.sessionVolumes()
        let (sessions, routines, volumes) = await (s, r, v)
        self.sessions = sessions
        self.routineNames = Dictionary(routines.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        self.volumes = volumes
        self.loaded = true
    }
}

// MARK: - Detail (per-exercise breakdown of one session)

struct WorkoutSessionDetailScreen: View {
    let route: WorkoutSessionRoute

    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    /// Work sets grouped by exercise, in the order they were performed.
    @State private var groups: [(exerciseId: String, name: String, sets: [SetEntry])] = []
    /// Resolved exercises by id, so tapping a block opens its detail (FER-517).
    @State private var exercisesByID: [String: Exercise] = [:]
    /// The exercise whose detail sheet is open (nil = none).
    @State private var detailExercise: Exercise?
    @State private var volumeKg: Double = 0
    @State private var setCount = 0
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading
                hero
                Divider().overlay(theme.hairline)
                secondaries
                if loaded {
                    ForEach(Array(groups.enumerated()), id: \.element.exerciseId) { _, g in
                        Divider().overlay(theme.hairline)
                        exerciseBlock(g)
                    }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
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
        .task { await load() }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(StrengthHistoryFormat.dateTime(route.startTs)).instrumentoOverline()
                .foregroundStyle(theme.inkTertiary)
            Text(route.routineName).font(StrandFont.title1).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Effort (strain) is the hero in the effort hue, or duration in ink when the session had no HR —
    // the same rule as the post-session receipt (FER-409).
    @ViewBuilder
    private var hero: some View {
        if let strain = route.strain {
            heroStat("Effort", StrengthHistoryFormat.strain(strain), unit: nil,
                     color: theme.dataStrain, caption: "What this session cost your body.")
        } else if let mins = StrengthHistoryFormat.durationMinutes(start: route.startTs, end: route.endTs) {
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
            if route.strain != nil,
               let mins = StrengthHistoryFormat.durationMinutes(start: route.startTs, end: route.endTs) {
                detailStat("Duration", StrengthHistoryFormat.durationText(mins))
            }
            if let hr = route.avgHr { detailStat("Avg HR", "\(hr)") }
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

    private func exerciseBlock(_ g: (exerciseId: String, name: String, sets: [SetEntry])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            exerciseTitle(g)
                .padding(.bottom, 6)
            ForEach(Array(g.sets.enumerated()), id: \.element.id) { idx, set in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Set \(idx + 1)").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
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

    /// The exercise's name — a tappable row (name + chevron) that opens its detail when the exercise
    /// resolves (FER-517); plain text otherwise, so there's no dead tap on an unknown id.
    @ViewBuilder
    private func exerciseTitle(_ g: (exerciseId: String, name: String, sets: [SetEntry])) -> some View {
        if let ex = exercisesByID[g.exerciseId] {
            Button { detailExercise = ex } label: {
                HStack(spacing: 6) {
                    Text(g.name).font(StrandFont.headline).foregroundStyle(theme.ink)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.inkTertiary)
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
