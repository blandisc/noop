#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandTraining

// MARK: - Mapa muscular (Cuerpo) — FER-350
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                header
                if loaded {
                    if loads.isEmpty {
                        emptyState
                    } else {
                        windowPicker
                        BodyFiguresView(theme: theme, loadByMuscle: loadByMuscle,
                                        maxLoad: loads.first?.load ?? 0) { selected = MuscleSelection(muscle: $0) }
                        legend
                        recommendationCard
                        ranking
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
            .presentationDetents([.large])
            .preferredColorScheme(.light)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Muscle map").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text("What to train today")
                        .font(StrandFont.title1).foregroundStyle(theme.ink)
                }
                Spacer()
                if let r = recovery { recoveryChip(r) }
            }
            Text("Recent load per muscle, crossed with your recovery.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func recoveryChip(_ r: Double) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("Recovery").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            Text("\(Int(r.rounded()))")
                .font(StrandFont.number(20)).foregroundStyle(recoveryColor(r))
        }
    }

    private func recoveryColor(_ r: Double) -> Color {
        if r < MuscleFatigueMap.recoveryRedMax { return theme.critical }
        if r < MuscleFatigueMap.recoveryYellowMax { return theme.warning }
        return theme.verdict
    }

    // MARK: - Window picker

    private var windowPicker: some View {
        HStack(spacing: 6) {
            ForEach(MuscleFatigueMap.Window.allCases, id: \.rawValue) { w in
                Button { window = w } label: {
                    Text("\(w.days) d")
                        .font(StrandFont.subhead)
                        .fontWeight(window == w ? .semibold : .regular)
                        .foregroundStyle(window == w ? theme.ink : theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(window == w ? theme.paper : .clear)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(window == w ? theme.hairlineStrong : .clear, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Window \(w.days) days"))
            }
        }
        .padding(3)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(spacing: 5) {
            LinearGradient(colors: theme.muscleLoadRamp, startPoint: .leading, endPoint: .trailing)
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            HStack {
                Text("Fresh").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Spacer()
                Text("Loaded").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    // MARK: - Recommendation

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(recommendationLead)
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            recommendationHeadline
        }
        .padding(NoopMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    private var recommendationLead: LocalizedStringKey {
        if recommendation.gatedBySystemic { return "Your recovery is low today." }
        if recommendation.readyMuscles.isEmpty { return "Everything you train is still loaded." }
        return "Recovery is clear and these muscles are fresh."
    }

    @ViewBuilder private var recommendationHeadline: some View {
        if recommendation.gatedBySystemic {
            Text("Take it easy — recover first.")
                .font(StrandFont.headline).foregroundStyle(theme.ink)
        } else if recommendation.readyMuscles.isEmpty {
            Text("Give it a day or train light.")
                .font(StrandFont.headline).foregroundStyle(theme.ink)
        } else {
            let ready = Array(recommendation.readyMuscles.prefix(3))
            ready.indices.reduce(Text("Ready for ").font(StrandFont.headline).foregroundColor(theme.ink)) { acc, i in
                let sep = i == 0 ? Text("") : Text(", ").font(StrandFont.headline).foregroundColor(theme.ink)
                return acc + sep + Text(MuscleAtlas.name(ready[i])).font(StrandFont.headline).foregroundColor(theme.verdict)
            } + Text(".").font(StrandFont.headline).foregroundColor(theme.ink)
        }
    }

    // MARK: - Ranking

    private var ranking: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Most loaded").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            ForEach(loads, id: \.muscle) { m in
                Button { selected = MuscleSelection(muscle: m.muscle) } label: {
                    HStack(spacing: 10) {
                        Text(MuscleAtlas.name(m.muscle))
                            .font(StrandFont.body).foregroundStyle(theme.ink)
                            .frame(width: 96, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(theme.hairline)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(theme.muscleLoadColor(m.relative))
                                    .frame(width: max(6, geo.size.width * m.relative))
                            }
                        }
                        .frame(height: 7)
                        Text(lastText(m.daysSinceLast))
                            .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
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
                    hits[inv.muscle, default: [:]][ex.id] = MuscleHit(exerciseId: ex.id, name: ex.name, primary: primary)
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

// MARK: - Body figures

private struct BodyFiguresView: View {
    let theme: InstrumentoTheme
    let loadByMuscle: [String: MuscleFatigueMap.MuscleLoad]
    let maxLoad: Double
    let onSelect: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            figure(.front)
            figure(.back)
        }
    }

    private func figure(_ side: MuscleAtlas.Side) -> some View {
        VStack(spacing: 6) {
            ZStack {
                BodyOutlineShape(side: side).stroke(theme.hairline, lineWidth: 1.2)
                ForEach(MuscleAtlas.regions.filter { $0.side == side }) { region in
                    let shape = RegionShape(region: region)
                    shape
                        .fill(color(for: region.muscle))
                        .overlay(shape.stroke(theme.hairline.opacity(0.6), lineWidth: 0.5))
                        .contentShape(shape)
                        .onTapGesture { onSelect(region.muscle) }
                        .accessibilityLabel(Text(MuscleAtlas.name(region.muscle)))
                        .accessibilityValue(Text(stateText(region.muscle)))
                }
            }
            .aspectRatio(100.0 / 220.0, contentMode: .fit)
            Text(side == .front ? "Front" : "Back")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func color(for muscle: String) -> Color {
        guard let m = loadByMuscle[muscle], maxLoad > 0 else { return theme.hairline }
        return theme.muscleLoadColor(m.relative)
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
        }
        .background(theme.paper.ignoresSafeArea())
    }

    private var stateColor: Color {
        switch state {
        case .fresh: return theme.verdict
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
