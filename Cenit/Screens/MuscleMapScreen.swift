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
// Redesign (no math change — only how it's presented):
//   • The ANSWER leads — a hero card right under the header (ready muscles + the recovery gate, anchored
//     with bands), so the actionable line is first, not fourth. The map is the proof, the hero the
//     conclusion.
//   • The window picker is relabeled «Lens · tint recency» (it only recolors freshness; the weekly band
//     stays fixed at 7 d).
//   • The figures are detailed anatomical silhouettes (front/back muscle groups) with a floating label
//     naming the most-loaded muscle.
//   • A «See the method» disclosure at the foot.
//
// Presented as a light `.sheet` from Cuerpo (theme passed explicitly — it doesn't cross the `.sheet`
// boundary, FER-162); the per-muscle detail rides a nested `.sheet(item:)`, NO nested NavigationStack
// (FER-171).

struct MuscleMapScreen: View {
    let theme: InstrumentoTheme
    @EnvironmentObject var repo: Repository

    @State private var window: MuscleFatigueMap.Window = .d7
    /// All completed work sets in the trailing 84 days, expanded to per-muscle events (one fetch). The
    /// map slices by `window`; the detail's weekly trend buckets the whole span.
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

    private static let trendDays = 84

    /// Today's systemic recovery (0–100), nil until a score exists — the gate the recommendation crosses.
    private var recovery: Double? { repo.today?.recovery }

    private var loads: [MuscleFatigueMap.MuscleLoad] {
        MuscleFatigueMap.loads(events: events, window: window)
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
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                header
                if loaded {
                    if loads.isEmpty {
                        emptyState
                    } else {
                        hero
                        figures
                        ranking
                        method
                        lensFooter
                    }
                }
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 20)
            .padding(.bottom, NoopMetrics.screenPadding)
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Muscle map").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("What to train today")
                .font(StrandFont.title1).foregroundStyle(theme.ink)
        }
    }

    // MARK: - Hero — the recommendation leads, with the recovery gate anchored

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heroLead)
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            heroAnswer
                .padding(.top, 6)
            if recovery != nil {
                recoveryGate
                    .padding(.top, 17)
            }
            if !loadedMuscles.isEmpty {
                Rectangle().fill(theme.hairline).frame(height: 1)
                    .padding(.vertical, 14)
                stillLoadedLine
            }
        }
        .padding(NoopMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    /// The lead line, honest about the recovery band (or its absence).
    private var heroLead: LocalizedStringKey {
        if recommendation.gatedBySystemic { return "Your recovery is low today." }
        if recommendation.readyMuscles.isEmpty { return "Everything you train is still loaded." }
        guard let r = recovery else { return "Fresh to train today:" }
        if r >= MuscleFatigueMap.recoveryYellowMax { return "Your recovery is clear — fresh to train:" }
        return "Your recovery is moderate — fresh to train:"
    }

    @ViewBuilder private var heroAnswer: some View {
        if recommendation.gatedBySystemic {
            Text("Take it easy — recover first.")
                .font(StrandFont.title2).foregroundStyle(theme.ink)
        } else if recommendation.readyMuscles.isEmpty {
            Text("Give it a day or train light.")
                .font(StrandFont.title2).foregroundStyle(theme.ink)
        } else {
            let ready = Array(recommendation.readyMuscles.prefix(3))
            ready.indices.reduce(Text("")) { acc, i in
                let sep = i == 0 ? Text("") : Text("  ·  ").font(StrandFont.title2).foregroundColor(theme.inkTertiary)
                return acc + sep + Text(MuscleAtlas.name(ready[i])).font(StrandFont.title2).fontWeight(.bold).foregroundColor(theme.verdict)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The recovery gate, anchored with bands — the «why» behind the whole recommendation.
    @ViewBuilder private var recoveryGate: some View {
        if let r = recovery {
            let score = Int(r.rounded())
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Recovery · today's gate").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text(gateLabel(r, score)).font(StrandFont.captionNumber).fontWeight(.semibold)
                        .foregroundStyle(recoveryColor(r))
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        gateTrack
                        // marker at the score's position (0…100)
                        RoundedRectangle(cornerRadius: 2).fill(theme.ink)
                            .frame(width: 3, height: 16)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(theme.surface, lineWidth: 2))
                            .offset(x: max(0, min(w - 3, w * min(max(r, 0), 100) / 100)) - 1.5, y: -4)
                    }
                    .frame(height: 8)
                }
                .frame(height: 8)
                HStack {
                    Text(String(localized: "muscleMap.gateTick.low")).font(StrandFont.footnote).fontWeight(.semibold).foregroundStyle(theme.critical)
                    Spacer()
                    Text(String(localized: "muscleMap.gateTick.base")).font(StrandFont.footnote).fontWeight(.semibold).foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text(String(localized: "muscleMap.gateTick.clear")).font(StrandFont.footnote).fontWeight(.semibold).foregroundStyle(theme.verdict)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Recovery \(score), today's gate"))
            .accessibilityValue(Text(gateBand(r)))
        }
    }

    /// The tricolor gate bar with hard band cuts at the model's recovery thresholds (34 / 67).
    private var gateTrack: some View {
        let red = MuscleFatigueMap.recoveryRedMax / 100      // 0.34
        let yellow = MuscleFatigueMap.recoveryYellowMax / 100 // 0.67
        return LinearGradient(
            stops: [
                .init(color: theme.critical, location: 0),
                .init(color: theme.critical, location: red),
                .init(color: theme.warning, location: red),
                .init(color: theme.warning, location: yellow),
                .init(color: theme.verdict, location: yellow),
                .init(color: theme.verdict, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .opacity(0.9)
    }

    @ViewBuilder private var stillLoadedLine: some View {
        let names = loadedMuscles.prefix(2).map { MuscleAtlas.name($0.muscle) }
        let lead = Text("Still loaded today: ").font(StrandFont.subhead).foregroundColor(theme.inkSecondary)
        let muscles: Text = {
            if names.count >= 2 {
                return Text(names[0]).font(StrandFont.subhead).fontWeight(.semibold).foregroundColor(theme.ink)
                    + Text(" and ").font(StrandFont.subhead).foregroundColor(theme.inkSecondary)
                    + Text(names[1]).font(StrandFont.subhead).fontWeight(.semibold).foregroundColor(theme.ink)
            } else {
                return Text(names[0]).font(StrandFont.subhead).fontWeight(.semibold).foregroundColor(theme.ink)
            }
        }()
        (lead + muscles
            + Text(" — give it a day before training them again.").font(StrandFont.subhead).foregroundColor(theme.inkSecondary))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func recoveryColor(_ r: Double) -> Color {
        if r < MuscleFatigueMap.recoveryRedMax { return theme.critical }
        if r < MuscleFatigueMap.recoveryYellowMax { return theme.warning }
        return theme.verdict
    }

    /// The score + band word as one interpolated key (e.g. "72 · Clear") — unique keys so the band word
    /// localizes in this context (avoiding the standalone "Clear" → "Limpiar" collision).
    private func gateLabel(_ r: Double, _ score: Int) -> LocalizedStringKey {
        if r < MuscleFatigueMap.recoveryRedMax { return "\(score) · Low" }
        if r < MuscleFatigueMap.recoveryYellowMax { return "\(score) · Base" }
        return "\(score) · Clear"
    }

    /// The recovery band, spelled out for VoiceOver (unique keys, AA-irrelevant — text-to-speech).
    private func gateBand(_ r: Double) -> LocalizedStringKey {
        if r < MuscleFatigueMap.recoveryRedMax { return "Recovery is low" }
        if r < MuscleFatigueMap.recoveryYellowMax { return "Recovery is at base" }
        return "Recovery is clear"
    }

    // MARK: - Lens (recency of the tint) — discreet, at the foot

    /// A quiet inline control at the foot: the 3/7/14-day lens only recolors the figure's tint recency
    /// (the weekly band stays fixed at 7 d), so it lives out of the main path — the sheet leads with
    /// today's state, not a control.
    private var lensFooter: some View {
        HStack {
            Text("Tint lens").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
            Spacer()
            HStack(spacing: 5) {
                ForEach(MuscleFatigueMap.Window.allCases, id: \.rawValue) { w in
                    Button { withAnimation(StrandMotion.interactive) { window = w } } label: {
                        Text("\(w.days) d")
                            .font(StrandFont.caption)
                            .fontWeight(window == w ? .semibold : .regular)
                            .foregroundStyle(window == w ? theme.ink : theme.inkTertiary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(window == w ? theme.paper : .clear)
                                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(window == w ? theme.hairlineStrong : .clear, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Window \(w.days) days"))
                }
            }
        }
        .padding(.top, 11)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
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
            }
        }
        .padding(EdgeInsets(top: 16, leading: 10, bottom: 12, trailing: 10))
        .frame(maxWidth: .infinity)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
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
            Circle().fill(loadByMuscle[m.muscle] != nil ? theme.muscleLoadColor(m.relative) : theme.hairlineStrong)
                .frame(width: 7, height: 7)
            Text(MuscleAtlas.name(m.muscle)).font(StrandFont.caption).fontWeight(.semibold).foregroundStyle(theme.paper)
            Text(stateSuffix(m.state)).font(StrandFont.caption).foregroundStyle(theme.paper.opacity(0.7))
        }
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(theme.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The mini load indicator for the peeked muscle — a tap target into the full detail.
    private func peekCard(_ muscle: String) -> some View {
        let load = loadByMuscle[muscle]
        let relative = load?.relative ?? 0
        let state = load?.state ?? .fresh
        return Button { selected = MuscleSelection(muscle: muscle) } label: {
            HStack(spacing: 10) {
                Circle().fill(load != nil ? theme.muscleLoadColor(relative) : theme.hairlineStrong)
                    .frame(width: 9, height: 9)
                VStack(spacing: 5) {
                    HStack {
                        Text(MuscleAtlas.name(muscle)).font(StrandFont.body).fontWeight(.semibold).foregroundStyle(theme.ink)
                        Spacer()
                        Text(stateWord(state)).font(StrandFont.caption).fontWeight(.semibold)
                            .foregroundStyle(load != nil ? stateColor(state) : theme.inkTertiary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(theme.hairline)
                            RoundedRectangle(cornerRadius: 3).fill(theme.muscleLoadColor(relative))
                                .frame(width: max(load != nil ? 6 : 0, geo.size.width * relative))
                        }
                    }
                    .frame(height: 6)
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(theme.paper, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
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
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold))
                    Text("Reset").font(StrandFont.caption)
                }
                .foregroundStyle(theme.inkSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
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
                .clipShape(RoundedRectangle(cornerRadius: 4))
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

    private var ranking: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Most loaded").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            ForEach(loads, id: \.muscle) { m in
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
                                Text(lastText(m.daysSinceLast)).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                            }
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(theme.hairline)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(theme.muscleLoadColor(m.relative))
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

    // MARK: - Method disclosure

    private var method: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(StrandMotion.interactive) { showMethod.toggle() } } label: {
                HStack {
                    Text("See the method").font(StrandFont.body).foregroundStyle(theme.ink)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                        .rotationEffect(.degrees(showMethod ? 180 : 0))
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("See the method"))
            .accessibilityAddTraits(showMethod ? [.isSelected] : [])
            if showMethod {
                Text("Each set adds load to the muscles it works, decaying by half every two days — the time course of muscle protein synthesis (MacDougall 1995). Color is relative to your most-loaded muscle, so it reads which of your muscles are hot right now. Weekly volume is judged against a 10–20 sets-per-muscle band (Schoenfeld 2017). The recommendation crosses this with your strap recovery: a low-recovery day gates everything to rest.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 0, leading: 14, bottom: 14, trailing: 14))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            BodyOutlineShape(side: .front)
                .stroke(theme.hairlineStrong, lineWidth: 1.4)
                .aspectRatio(100.0 / 220.0, contentMode: .fit)
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

    private func lastText(_ days: Int) -> String {
        days == 0 ? String(localized: "today") : String(localized: "\(days) d ago")
    }

    private func load() async {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        guard let since = cal.date(byAdding: .day, value: -Self.trendDays, to: startToday) else {
            loaded = true; return
        }
        let rawSets = await repo.recentWorkSets(sinceTs: Int(since.timeIntervalSince1970))
        let exercises = await repo.allExercises()
        let byId = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var ev: [MuscleFatigueMap.MuscleSetEvent] = []
        var hits: [String: [String: MuscleHit]] = [:]
        for set in rawSets {
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
                AnatomyBaseShape()
                    .fill(theme.hairline)
                AnatomyBaseShape()
                    .stroke(theme.hairlineStrong, lineWidth: 0.9)
                ForEach(MuscleAnatomy.paths(for: side)) { item in
                    let shape = SVGPath(item.d)
                    let isTop = highlight == item.muscle
                    shape
                        .fill(color(for: item.muscle))
                        .overlay(shape.stroke(isTop ? theme.ink : theme.hairlineStrong.opacity(0.5),
                                              lineWidth: isTop ? 2 : 0.6))
                        .contentShape(shape)
                        .onTapGesture { onSelect(item.muscle) }
                        .accessibilityLabel(Text(MuscleAtlas.name(item.muscle)))
                        .accessibilityValue(Text(stateText(item.muscle)))
                }
            }
            .aspectRatio(160.0 / 340.0, contentMode: .fit)
            Text(side == .front ? "Front" : "Back")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func color(for muscle: String) -> Color {
        guard let m = loadByMuscle[muscle], maxLoad > 0 else { return theme.hairlineStrong.opacity(0.55) }
        return theme.muscleLoadColor(m.relative)
    }

    private func stateText(_ muscle: String) -> LocalizedStringKey {
        guard let m = loadByMuscle[muscle] else { return "untrained" }
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
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                Text(MuscleAtlas.name(muscle)).instrumentoOverlineProminent().foregroundStyle(theme.inkSecondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(weeklySets.formatted(.number.precision(.fractionLength(weeklySets == weeklySets.rounded() ? 0 : 1))))
                        .font(StrandFont.number(52)).foregroundStyle(stateColor)
                    Text("sets · 7 d").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }

                volumeBand
                statTiles
                if weeklyTrend.contains(where: { $0 > 0 }) { trend }
                if !hits.isEmpty { exercises }
                recommendation
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 24)
            .padding(.bottom, NoopMetrics.screenPadding)
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
        let lo = MuscleFatigueMap.weeklyBandLow, hi = MuscleFatigueMap.weeklyBandHigh, top = 30.0
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(theme.hairline).frame(height: 8)
                    Rectangle().fill(theme.hairlineStrong)
                        .frame(width: w * (hi - lo) / top, height: 8)
                        .offset(x: w * lo / top)
                    RoundedRectangle(cornerRadius: 1).fill(stateColor)
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
        case .below: return "Below the recommended band — room for more volume this week."
        case .within: return "Within the recommended weekly band."
        case .above: return "Above the recommended band — a lot of volume this week."
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
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
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
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func recommendationText(_ r: MuscleFatigueMap.Readiness) -> LocalizedStringKey {
        switch r {
        case .rest: return "Your recovery is low — rest or train light today."
        case .caution: return "Still loaded — give it a day or two before training it again."
        case .ready: return "Fresh and ready — a good muscle to train today."
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
#endif
