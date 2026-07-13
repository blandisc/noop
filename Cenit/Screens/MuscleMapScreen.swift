#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandTraining

// MARK: - Mapa muscular (Cuerpo) — FER-350 · rediseño «la respuesta lidera»
//
// The jewel of the loop: front/back silhouettes tinted by each muscle's recent training load, CROSSED
// with the strap's systemic recovery — what to train today. A tracker without a strap (Fitbod) can't
// cross in recovery; a strap without set logging (WHOOP) has no per-muscle load. NOOP has both.
//
// Light «Instrumento diurno» language (warm paper, color ONLY on the datum, hierarchy by space). The
// math is the pure, cited `MuscleFatigueMap` (StrandAnalytics): load = Σ involvement·decay(daysAgo) with
// a 2-day half-life (MPS time course), a 3/7/14-day window that filters which sets count, freshness
// relative to the user's own most-loaded muscle, weekly volume vs the Schoenfeld 10–20 band, and a
// recovery gate. THIS screen is the glue: it reads work sets from the store, expands each over its
// exercise's `muscleInvolvement`, computes whole-day ages in the local calendar, and draws the result.
//
// Entrenar v3 · 1n (FER-719) — the handoff skin («Rediseño Hoy» voice):
//   • A grotesk VERDICT headline leads (what's fresh, what still carries load), with the recovery
//     bullet right under it — the old hero card and gate bar collapse into these two lines.
//   • The 3/7/14-day lens is RETIRED: the decay itself carries time (see `MuscleFatigueMap`), so a
//     window filter double-encoded recency. The ranking is fixed to the last 7 days, showing each
//     muscle's weekly sets.
//   • The figures stay the detailed anatomical silhouettes tinted by the 5-stop fresh→loaded ramp,
//     with the continuous legend under them.
//   • The foot states the method in one line and expands into the cited paragraph («Ver el método»).
//   • The manual «mark all recovered» reset (FER-525) is PRESERVED: it filters which sets feed the
//     map (nothing deleted), which is orthogonal to the decay math.
//
// Presented as a light `.sheet` from Cuerpo (theme passed explicitly — it doesn't cross the `.sheet`
// boundary, FER-162); the per-muscle detail rides a nested `.sheet(item:)`, NO nested NavigationStack
// (FER-171).

struct MuscleMapScreen: View {
    let theme: InstrumentoTheme
    @EnvironmentObject var repo: Repository

    /// All completed work sets in the trailing 84 days, expanded to per-muscle events (one fetch). The
    /// decay carries recency (no window, FER-719); the detail's weekly trend buckets the whole span.
    @State private var events: [MuscleFatigueMap.MuscleSetEvent] = []
    /// muscle → the exercises the user actually did that hit it (dedup, strongest involvement kept).
    @State private var hitsByMuscle: [String: [MuscleHit]] = [:]
    @State private var loaded = false
    @State private var selected: MuscleSelection? = nil
    @State private var showMethod = false
    /// The muscle the user tapped once — the «peek» (highlighted + a mini load indicator). A second tap
    /// on the same muscle (or on the peek card) opens the full detail. `nil` = no peek; the figure falls
    /// back to highlighting the most-loaded muscle.
    @State private var peeked: String? = nil
    /// Manual recovery reset (FER-525): epoch seconds. Work sets before this are ignored, so the map reads
    /// «all fresh» as if the user had rested — without deleting any history. 0 = never reset.
    @AppStorage("muscleRecoveryResetAt") private var recoveryResetAt: Double = 0
    /// Whether the user has ANY logged work set in the window — separates «no data yet» (onboarding empty
    /// state) from «all recovered» (the green map). (FER-525)
    @State private var hasHistory = false
    @State private var showResetConfirm = false

    private static let trendDays = 84

    /// Today's systemic recovery (0–100), nil until a score exists — the gate the recommendation crosses.
    private var recovery: Double? { repo.today?.recovery }

    private var loads: [MuscleFatigueMap.MuscleLoad] {
        MuscleFatigueMap.loads(events: events)
    }
    /// The «Más cargados» ranking is fixed to the last 7 days (the mock), independent of how far back
    /// the decayed tint reaches. `weeklySets` is the engine's 7-day count — the same window the row
    /// displays — so membership and the shown number are single-sourced.
    private var rankingLoads: [MuscleFatigueMap.MuscleLoad] {
        loads.filter { $0.weeklySets > 0 }
    }
    private var loadByMuscle: [String: MuscleFatigueMap.MuscleLoad] {
        Dictionary(loads.map { ($0.muscle, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var recommendation: MuscleFatigueMap.Recommendation {
        MuscleFatigueMap.recommendation(loads: loads, recovery: recovery)
    }
    /// The most-loaded muscle (loads come back sorted by load, desc) — labels & outlines the figure.
    private var topMuscle: MuscleFatigueMap.MuscleLoad? { loads.first }
    /// The muscle the floating label & figure outline point at: the active peek, else the most-loaded.
    private var focused: MuscleFatigueMap.MuscleLoad? {
        if let p = peeked { return loadByMuscle[p] ?? MuscleFatigueMap.MuscleLoad(muscle: p, load: 0, relative: 0, daysSinceLast: 0, state: .fresh, weeklySets: 0, band: .below) }
        return topMuscle
    }
    /// The muscles still in the loaded band — the hero's «still loaded today» line (most-loaded first).
    private var loadedMuscles: [MuscleFatigueMap.MuscleLoad] { loads.filter { $0.state == .loaded } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                header
                if loaded {
                    if loads.isEmpty && !hasHistory {
                        emptyState
                    } else {
                        figures
                        if !rankingLoads.isEmpty { ranking }
                        method
                    }
                }
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, 20)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task { await load() }
        .sheet(item: $selected) { sel in
            MuscleDetailView(
                theme: theme,
                muscle: sel.muscle,
                load: loadByMuscle[sel.muscle],
                weeklyTrend: weeklyTrend(for: sel.muscle),
                hits: hitsByMuscle[sel.muscle] ?? [],
                recovery: recovery
            )
            .preferredColorScheme(.light)
        }
    }

    // MARK: - Header — the grotesk verdict leads, the recovery bullet explains the gate

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Muscle map").groteskOverline().foregroundStyle(theme.inkTertiary)
            verdictHeadline
                .padding(.top, 4)
            if loaded && !(loads.isEmpty && !hasHistory) {
                recoveryBullet
                    .padding(.top, 10)
            }
        }
    }

    /// The two-line verdict in the handoff's grotesk voice: what's fresh to train, what still
    /// carries load. Ink only — the color lives in the figures (Instrumento).
    @ViewBuilder private var verdictHeadline: some View {
        Group {
            if !loaded || (loads.isEmpty && !hasHistory) {
                Text("What to train today")
            } else if recommendation.gatedBySystemic {
                Text("Today calls for rest.\nRecover first.")
            } else if loads.isEmpty || recommendation.readyMuscles.count == loads.count {
                Text("All fresh.\nTrain what you like.")
            } else if recommendation.readyMuscles.isEmpty {
                Text("Everything still carries load.\nGive it a day or go light.")
            } else {
                freshLine + Text("\n") + stillLoadedLine
            }
        }
        .font(InstrumentoType.grotesk(25, weight: .bold, relativeTo: .title2))
        .foregroundStyle(theme.ink)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// «Fresh: Chest · Shoulders.» — the ready muscles, most-fresh first.
    private var freshLine: Text {
        let ready = Array(recommendation.readyMuscles.prefix(2))
        let names = ready.indices.reduce(Text(verbatim: "")) { acc, i in
            let sep = i == 0 ? Text(verbatim: "") : Text(verbatim: " · ")
            return acc + sep + Text(MuscleAtlas.name(ready[i]))
        }
        return Text("Fresh: ") + names + Text(verbatim: ".")
    }

    /// «Glutes still carries load.» — the most-loaded muscle; or a neutral tail when nothing is
    /// in the loaded band.
    private var stillLoadedLine: Text {
        guard let top = loadedMuscles.first else { return Text("The rest can wait.") }
        return Text(MuscleAtlas.name(top.muscle)) + Text(" still carries load.")
    }

    /// The recovery bullet — dot in the band's color, one honest line. Replaces the old gate bar.
    private var recoveryBullet: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle().fill(recovery.map(recoveryColor) ?? theme.inkTertiary)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
            Text(recoveryBulletText)
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var recoveryBulletText: LocalizedStringKey {
        guard let r = recovery else {
            return "No recovery reading today · the map shows muscle load only."
        }
        let score = Int(r.rounded())
        if r < MuscleFatigueMap.recoveryRedMax { return "Recovery \(score) · today calls for rest." }
        if r < MuscleFatigueMap.recoveryYellowMax { return "Recovery \(score) · keep it moderate today." }
        return "Recovery \(score) · today's gate doesn't hold you back."
    }

    private func recoveryColor(_ r: Double) -> Color {
        if r < MuscleFatigueMap.recoveryRedMax { return theme.critical }
        if r < MuscleFatigueMap.recoveryYellowMax { return theme.warning }
        return theme.verdict
    }

    // MARK: - Figures (detailed anatomical silhouettes)

    private var figures: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                BodyFiguresView(theme: theme, loadByMuscle: loadByMuscle,
                                maxLoad: loads.first?.load ?? 0,
                                highlight: focused?.muscle) { tapMuscle($0) }
                    .padding(.top, 10)
                if let f = focused { floatingLabel(f) }
            }
            if let p = peeked {
                peekCard(p).padding(.top, 4)
                resetRow.padding(.top, 7)
            } else {
                legend.padding(.top, 6)
                Text("Tap a muscle to see its load")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .padding(.top, 10)
                if !loads.isEmpty {
                    markRecoveredButton.padding(.top, 12)
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 10, bottom: 12, trailing: 10))
        .frame(maxWidth: .infinity)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
        .instrumentoConfirm(
            isPresented: $showResetConfirm,
            title: String(localized: "Mark all muscles as recovered?"),
            context: String(localized: "MUSCLE MAP"),
            message: String(localized: "The map resets to fresh. Your workout history isn't deleted: logging a new workout loads that muscle again."),
            actions: [
                .init(String(localized: "Mark recovered"), role: .primary) { markAllRecovered() },
                .init(String(localized: "Leave the map as is"), role: .secondary)
            ]
        )
    }

    /// First tap on a muscle peeks it (highlight + mini indicator); a second tap on the same muscle
    /// opens the full detail.
    private func tapMuscle(_ muscle: String) {
        if peeked == muscle {
            selected = MuscleSelection(muscle: muscle)
        } else {
            withAnimation(StrandMotion.interactive) { peeked = muscle }
        }
    }

    private func floatingLabel(_ m: MuscleFatigueMap.MuscleLoad) -> some View {
        HStack(spacing: 7) {
            Circle().fill(theme.muscleStateColor(m.relative))
                .frame(width: 7, height: 7)
            Text(MuscleAtlas.name(m.muscle)).font(StrandFont.caption).fontWeight(.semibold).foregroundStyle(theme.paper)
            Text(stateSuffix(m.state)).font(StrandFont.caption).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
        }
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The mini load indicator for the peeked muscle — a tap target into the full detail.
    private func peekCard(_ muscle: String) -> some View {
        let load = loadByMuscle[muscle]
        let relative = load?.relative ?? 0
        let state = load?.state ?? .fresh
        return Button { selected = MuscleSelection(muscle: muscle) } label: {
            HStack(spacing: 10) {
                Circle().fill(theme.muscleStateColor(relative))
                    .frame(width: 9, height: 9)
                VStack(spacing: 5) {
                    HStack {
                        Text(MuscleAtlas.name(muscle)).font(StrandFont.body).fontWeight(.semibold).foregroundStyle(theme.ink)
                        Spacer()
                        Text(stateWord(state)).font(StrandFont.caption).fontWeight(.semibold)
                            .foregroundStyle(stateColor(state))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(theme.hairline)  // token-exempt: geometría de dato
                            RoundedRectangle(cornerRadius: 3).fill(theme.muscleStateColor(relative))  // token-exempt: geometría de dato
                                .frame(width: max(load != nil ? 6 : 0, geo.size.width * relative))
                        }
                    }
                    .frame(height: 6)
                }
                StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .instrumentoCard(.inset, theme: theme, fill: theme.paper, stroke: theme.hairlineStrong)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityHint(Text("Opens the full detail"))
    }

    private var resetRow: some View {
        HStack {
            Text("Tap again to see everything").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            Spacer()
            Button { withAnimation(StrandMotion.interactive) { peeked = nil } } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.uturn.backward").font(StrandFont.glyph(.chevron, weight: .semibold))
                    Text("Deselect").font(StrandFont.caption)
                }
                .foregroundStyle(theme.inkSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    /// «Mark all recovered» — sets the recovery-reset point so the map reads all-fresh, without deleting
    /// any workout history. (FER-525)
    private var markRecoveredButton: some View {
        Button { showResetConfirm = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise").font(StrandFont.glyph(.chevron, weight: .semibold))
                Text("Mark all recovered").font(StrandFont.caption)
            }
            .foregroundStyle(theme.inkSecondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Marks every muscle as recovered"))
    }

    private func markAllRecovered() {
        recoveryResetAt = Date().timeIntervalSince1970
        withAnimation(StrandMotion.interactive) { peeked = nil }
        Task { await load() }
    }

    private func stateWord(_ s: MuscleFatigueMap.LoadState) -> LocalizedStringKey {
        switch s {
        case .fresh: return "fresh"
        case .moderate: return "moderate"
        case .loaded: return "loaded"
        }
    }

    private func stateColor(_ s: MuscleFatigueMap.LoadState) -> Color {
        switch s {
        case .fresh: return theme.verdict
        case .moderate: return theme.warning
        case .loaded: return theme.muscleLoadColor(1)
        }
    }

    private func stateSuffix(_ s: MuscleFatigueMap.LoadState) -> LocalizedStringKey {
        switch s {
        case .fresh: return "· fresh"
        case .moderate: return "· moderate"
        case .loaded: return "· loaded"
        }
    }

    private var legend: some View {
        VStack(spacing: 6) {
            LinearGradient(colors: theme.muscleLoadRamp, startPoint: .leading, endPoint: .trailing)
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))  // token-exempt: geometría de dato
            HStack {
                Text("Fresh").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Spacer()
                Text("relative to your load").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("Loaded").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Ranking

    /// «Más cargados · 7 días» — fixed to the last 7 days (the mock); each row carries its weekly
    /// sets, the raw number the Schoenfeld band judges.
    private var ranking: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Most loaded · 7 days").groteskOverline().foregroundStyle(theme.inkTertiary)
            ForEach(rankingLoads, id: \.muscle) { m in
                Button { selected = MuscleSelection(muscle: m.muscle) } label: {
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(MuscleAtlas.name(m.muscle))
                                .font(StrandFont.body)
                                .fontWeight(m.state == .fresh ? .semibold : .regular)
                                .foregroundStyle(m.state == .fresh ? theme.verdict : theme.ink)
                                .lineLimit(1).minimumScaleFactor(0.85)
                            Spacer(minLength: 8)
                            if m.state == .fresh {
                                Text("fresh").font(StrandFont.caption).fontWeight(.semibold).foregroundStyle(theme.verdict)
                            } else {
                                Text("\(setsText(m.weeklySets)) sets")
                                    .font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
                            }
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(theme.hairline)  // token-exempt: geometría de dato
                                RoundedRectangle(cornerRadius: 4)  // token-exempt: geometría de dato
                                    .fill(theme.muscleStateColor(m.relative))
                                    .frame(width: max(6, geo.size.width * m.relative))
                            }
                        }
                        .frame(height: 7)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Method foot — the one-line method with its cite, expanding into the full paragraph

    private var method: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(StrandMotion.interactive) { showMethod.toggle() } } label: {
                (Text("Each set loads the muscles it works and fades by half every 2 days · ")
                    .font(StrandFont.caption).foregroundColor(theme.inkTertiary)
                 + Text("See the method ›")
                    .font(StrandFont.caption).fontWeight(.semibold).foregroundColor(theme.inkSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("See the method"))
            .accessibilityAddTraits(showMethod ? [.isSelected] : [])
            if showMethod {
                Text("Each set adds load to the muscles it works, decaying by half every two days: the time course of muscle protein synthesis (MacDougall 1995; Damas 2015). Color is relative to your most-loaded muscle, so it reads which of your muscles are hot right now. Weekly volume is judged against the 10–20 sets-per-week band (Schoenfeld 2017), a hypertrophy guide per muscle group; the volume shown is weighted by involvement, so secondary muscles count less. The recommendation crosses this with your strap recovery: a low-recovery day gates everything to rest.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            AnatomyBaseShape()
                .stroke(theme.hairline, lineWidth: 1.2)
                .aspectRatio(200.0 / 430.0, contentMode: .fit)
                .frame(maxHeight: 220)
                .padding(.top, 8)
            Text("Train to fill your map")
                .font(StrandFont.title2).foregroundStyle(theme.ink)
            Text("Log your sets and you'll see which muscles are loaded and which are fresh to train today.")
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: - Data

    /// Weekly involvement-weighted volume for one muscle, oldest→newest, over the trailing 12 weeks —
    /// the detail's trend. Bucketed straight from the events (week = daysAgo / 7).
    private func weeklyTrend(for muscle: String) -> [Double] {
        let weeks = Self.trendDays / 7
        var buckets = [Double](repeating: 0, count: weeks)
        for e in events where e.muscle == muscle {
            let w = min(e.daysAgo / 7, weeks - 1)
            buckets[weeks - 1 - w] += e.involvement
        }
        return buckets
    }

    private func setsText(_ v: Double) -> String { MuscleFatigueMap.formattedSets(v) }

    private func load() async {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        guard let since = cal.date(byAdding: .day, value: -Self.trendDays, to: startToday) else {
            loaded = true; return
        }
        let rawSets = await repo.recentWorkSets(sinceTs: Int(since.timeIntervalSince1970))
        hasHistory = !rawSets.isEmpty
        let resetTs = Int(recoveryResetAt)
        let exercises = await repo.allExercises()
        let byId = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var ev: [MuscleFatigueMap.MuscleSetEvent] = []
        var hits: [String: [String: MuscleHit]] = [:]
        for set in rawSets where set.startTs >= resetTs {
            guard let ex = byId[set.exerciseId] else { continue }
            let setDay = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(set.startTs)))
            let daysAgo = cal.dateComponents([.day], from: setDay, to: startToday).day ?? 0
            for inv in ex.muscleInvolvement {
                ev.append(.init(muscle: inv.muscle, involvement: inv.weight, daysAgo: daysAgo))
                let primary = inv.weight >= Exercise.primaryWeight
                let existing = hits[inv.muscle]?[ex.id]
                if existing == nil || (primary && existing?.primary == false) {
                    hits[inv.muscle, default: [:]][ex.id] = MuscleHit(exerciseId: ex.id, name: StrengthDisplay.name(ex), primary: primary)
                }
            }
        }
        events = ev
        hitsByMuscle = hits.mapValues { dict in
            dict.values.sorted { ($0.primary ? 0 : 1, $0.name) < ($1.primary ? 0 : 1, $1.name) }
        }
        loaded = true
    }
}

// MARK: - Selection wrapper (sheet item)

private struct MuscleSelection: Identifiable {
    let muscle: String
    var id: String { muscle }
}

/// One exercise the user did that works a muscle.
struct MuscleHit: Hashable {
    let exerciseId: String
    let name: String
    let primary: Bool
}

// MARK: - Body figures (anatomical)

private struct BodyFiguresView: View {
    let theme: InstrumentoTheme
    let loadByMuscle: [String: MuscleFatigueMap.MuscleLoad]
    let maxLoad: Double
    /// The most-loaded muscle — outlined to tie the figure to the floating label.
    let highlight: String?
    let onSelect: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            figure(.front)
            figure(.back)
        }
    }

    private func figure(_ side: MuscleAtlas.Side) -> some View {
        VStack(spacing: 5) {
            ZStack {
                // The silhouette is stroke-only (fill:none) so the body reads as paper and color
                // lives only in the tinted muscles — the «Instrumento» rule (owner-approved, FER-781).
                AnatomyBaseShape()
                    .stroke(theme.hairline, lineWidth: 1.2)
                ForEach(MuscleAnatomy.paths(for: side)) { item in
                    let shape = SVGPath(item.d)
                    let isTop = highlight == item.muscle
                    shape
                        .fill(color(for: item.muscle))
                        .overlay(shape.stroke(isTop ? theme.ink : theme.hairlineStrong.opacity(StrandOpacity.dim),
                                              lineWidth: isTop ? 2 : 0.6))
                        .contentShape(shape)
                        .onTapGesture { onSelect(item.muscle) }
                        .accessibilityLabel(Text(MuscleAtlas.name(item.muscle)))
                        .accessibilityValue(Text(stateText(item.muscle)))
                }
            }
            .aspectRatio(200.0 / 430.0, contentMode: .fit)
            Text(side == .front ? "Front" : "Back")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func color(for muscle: String) -> Color {
        guard let m = loadByMuscle[muscle], maxLoad > 0 else { return theme.muscleStateColor(0) }
        return theme.muscleStateColor(m.relative)
    }

    private func stateText(_ muscle: String) -> LocalizedStringKey {
        guard let m = loadByMuscle[muscle] else { return "fresh" }
        switch m.state {
        case .fresh: return "fresh"
        case .moderate: return "moderate"
        case .loaded: return "loaded"
        }
    }
}

// MARK: - Muscle detail

private struct MuscleDetailView: View {
    let theme: InstrumentoTheme
    let muscle: String
    let load: MuscleFatigueMap.MuscleLoad?
    let weeklyTrend: [Double]
    let hits: [MuscleHit]
    let recovery: Double?

    private var weeklySets: Double { load?.weeklySets ?? 0 }
    private var state: MuscleFatigueMap.LoadState { load?.state ?? .fresh }

    /// The measured content height — drives a fitted sheet detent so the sheet rises only as far as the
    /// content needs (with `.large` as a fallback when the content is taller than the fitted height, e.g.
    /// large Dynamic Type).
    @State private var contentHeight: CGFloat = 420

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text(MuscleAtlas.name(muscle)).instrumentoOverlineProminent().foregroundStyle(theme.inkSecondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MuscleFatigueMap.formattedSets(weeklySets))
                        .font(StrandFont.number(52)).foregroundStyle(stateColor)
                    Text("sets · 7 d").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }

                volumeBand
                statTiles
                if weeklyTrend.contains(where: { $0 > 0 }) { trend }
                if !hits.isEmpty { exercises }
                recommendation
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, 24)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in
                Color.clear.onAppear { contentHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, h in contentHeight = h }
            })
        }
        .background(theme.paper.ignoresSafeArea())
        .presentationDetents([.height(contentHeight), .large])
        .presentationDragIndicator(.visible)
    }

    /// The state hue. «Fresh» uses the map's sage (the head of `muscleLoadRamp`) so the fresh→loaded
    /// color chain is a SINGLE scale across the map and the detail (FER-350 redesign · #6).
    private var stateColor: Color {
        switch state {
        case .fresh: return theme.muscleLoadColor(0)
        case .moderate: return theme.warning
        case .loaded: return theme.muscleLoadColor(1)
        }
    }

    // Weekly volume vs the Schoenfeld 10–20 band, scaled to a 0–30 track.
    private var volumeBand: some View {
        let lo = MuscleFatigueMap.weeklyBandLow, hi = MuscleFatigueMap.weeklyBandHigh
        let top = MuscleFatigueMap.weeklyVolumeRailTop
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(theme.hairline).frame(height: 8)  // token-exempt: geometría de dato
                    Rectangle().fill(theme.hairlineStrong)
                        .frame(width: w * (hi - lo) / top, height: 8)
                        .offset(x: w * lo / top)
                    RoundedRectangle(cornerRadius: 1).fill(stateColor)  // token-exempt: geometría de dato
                        .frame(width: 2, height: 16)
                        .offset(x: min(w - 2, w * min(weeklySets, top) / top))
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack {
                Text("0").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("band 10–20").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("30+").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Text(bandText).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bandText: LocalizedStringKey {
        switch load?.band ?? .below {
        case .below: return "Below the recommended band: room for more volume this week."
        case .within: return "Within the recommended weekly band."
        case .above: return "Above the recommended band: a lot of volume this week."
        }
    }

    private var statTiles: some View {
        HStack(spacing: 10) {
            tile(title: "Last time", value: lastText)
            tile(title: "State", value: stateText, color: stateColor)
        }
    }

    private func tile(title: LocalizedStringKey, value: LocalizedStringKey, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            Text(value).font(StrandFont.headline).foregroundStyle(color ?? theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .instrumentoCard(.control, theme: theme)
    }

    private var lastText: LocalizedStringKey {
        guard let d = load?.daysSinceLast else { return "—" }
        return d == 0 ? "today" : "\(d) d ago"
    }

    private var stateText: LocalizedStringKey {
        switch state {
        case .fresh: return "Fresh"
        case .moderate: return "Moderate"
        case .loaded: return "Loaded"
        }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trend · sets/week").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            TrendLine(values: weeklyTrend, color: stateColor)
                .frame(height: 48)
        }
    }

    private var exercises: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Exercises that work it").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .padding(.bottom, 8)
            ForEach(Array(hits.prefix(6)), id: \.exerciseId) { hit in
                HStack {
                    Text(hit.name).font(StrandFont.body).foregroundStyle(theme.ink)
                    Spacer()
                    Text(hit.primary ? "primary" : "secondary")
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                }
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) {
                    if hit.exerciseId != hits.prefix(6).last?.exerciseId {
                        Rectangle().fill(theme.hairline).frame(height: 0.5)
                    }
                }
            }
        }
    }

    private var recommendation: some View {
        let readiness = MuscleFatigueMap.readiness(state: state, recovery: recovery)
        return Text(recommendationText(readiness))
            .font(StrandFont.headline).foregroundStyle(theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(CenitMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func recommendationText(_ r: MuscleFatigueMap.Readiness) -> LocalizedStringKey {
        switch r {
        case .rest: return "Your recovery is low: rest or train light today."
        case .caution: return "Still loaded: give it a day or two before training it again."
        case .ready: return "Fresh and ready: a good muscle to train today."
        }
    }
}

// MARK: - Tiny trend line (self-contained, no shared component coupling)

private struct TrendLine: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 1, 1)
            let n = max(values.count - 1, 1)
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(n)
                    let y = geo.size.height * (1 - CGFloat(v / maxV))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        }
    }
}

// MARK: - Fatigue-state colour

private extension InstrumentoTheme {
    /// Maps a muscle's relative load (0…1) onto `muscleLoadRamp` by fatigue STATE, so a fresh muscle reads
    /// green, a moderate one amber and a loaded one red. The raw ramp puts its green only near 0, so a muscle
    /// classified «fresh» (relative < `freshBelow`) painted at its raw fraction came out amber — contradicting
    /// the recommendation card. Each state band maps to its own slice of the ramp, keeping a gentle gradient
    /// within the band so the ranking still reads. (FER-516)
    func muscleStateColor(_ relative: Double) -> Color {
        let fresh = MuscleFatigueMap.freshBelow
        let loaded = MuscleFatigueMap.loadedAbove
        let position: Double
        if relative < fresh {
            position = relative / fresh * 0.06
        } else if relative < loaded {
            position = 0.45 + (relative - fresh) / (loaded - fresh) * 0.10
        } else {
            position = 0.80 + (relative - loaded) / (1 - loaded) * 0.20
        }
        return muscleLoadColor(position)
    }
}
#endif
