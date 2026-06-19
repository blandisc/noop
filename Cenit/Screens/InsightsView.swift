import SwiftUI
import Foundation
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Insights
//
// The headline "interrogate what affects what" screen. Two halves:
//
//  1. BEHAVIOUR EFFECTS — split your logged journal answers (Alcohol, Caffeine,
//     Late meal, Meditation…) into the days each behaviour WAS logged vs NOT, then
//     compare a chosen outcome metric (Recovery / HRV / Sleep performance / RHR)
//     between the two groups. Ranked by effect size (Cohen's d) with significant
//     effects first; each card carries the plain-English sentence, the with/without
//     means, group counts, a significance pill, and the effect-size magnitude.
//     Tint is sign-aware: a behaviour that moves the outcome the "good" way
//     (respecting higherIsBetter) is positive/green, the "bad" way is critical/red.
//
//  2. METRIC RELATIONSHIPS — a curated set of Pearson correlations between daily
//     series (sleep ↔ recovery, today's strain ↔ next-day recovery via a 1-day lag,
//     HRV ↔ recovery, RHR ↔ recovery), each rendered as a one-line insight with r
//     and a plain-English reading of strength + direction.
//
// All math comes from StrandAnalytics (BehaviorInsights / CorrelationEngine); this
// view only loads the series, shapes them, and presents. Empty state via ComingSoon
// when there is no journal data to interrogate.

struct InsightsView: View {
    @EnvironmentObject var repo: Repository

    // MARK: Selected outcome (segmented)

    /// One interrogable outcome metric: how to fetch it and how to read its direction.
    enum Outcome: String, CaseIterable, Identifiable {
        case recovery, hrv, sleep, rhr
        var id: String { rawValue }

        /// Short segment label.
        var label: String {
            switch self {
            case .recovery: return String(localized: "Recovery")
            case .hrv:      return String(localized: "HRV")
            case .sleep:    return String(localized: "Sleep")
            case .rhr:      return String(localized: "RHR")
            }
        }
        /// The metricSeries key (source is always "my-whoop" for these).
        var key: String {
            switch self {
            case .recovery: return "recovery"
            case .hrv:      return "hrv"
            case .sleep:    return "sleep_performance"
            case .rhr:      return "rhr"
            }
        }
        /// The human outcome name used by BehaviorInsights.sentence.
        var outcomeName: String {
            switch self {
            case .recovery: return String(localized: "Recovery")
            case .hrv:      return String(localized: "HRV")
            case .sleep:    return String(localized: "Sleep performance")
            case .rhr:      return String(localized: "Resting HR")
            }
        }
        /// Whether a higher value is the "good" direction (drives tint).
        var higherIsBetter: Bool {
            switch self {
            case .recovery, .hrv, .sleep: return true
            case .rhr:                    return false
            }
        }
    }

    @State private var outcome: Outcome = .recovery

    // MARK: Loaded state

    /// behaviour question → set of days where it was answered yes.
    @State private var behaviours: [String: Set<String>] = [:]
    /// outcome key → [day: value].
    @State private var outcomeByKey: [String: [String: Double]] = [:]
    /// outcome key → ordered (day, value) series for correlations.
    @State private var seriesByKey: [String: [(day: String, value: Double)]] = [:]
    @State private var loaded = false

    // MARK: Memoized derived state
    //
    // The ranking and correlations are expensive (BehaviorInsights.rank +
    // four Pearson correlations) and were previously recomputed inside `body`
    // on EVERY render — including hover/animation/1Hz HR ticks. Cache them in
    // @State and recompute only when their inputs change.

    /// Ranked behaviour effects for the current outcome, recomputed via
    /// recomputeRanked() only when behaviours / outcomeByKey / outcome change.
    @State private var ranked: [BehaviorEffect] = []
    /// Curated metric relationships, recomputed via recomputeRelationships()
    /// only when the loaded series change.
    @State private var relationships: [Relationship] = []

    private let outcomeKeys = ["recovery", "hrv", "sleep_performance", "rhr"]

    // MARK: Native-logging state for the journal card

    /// Distinct imported question strings, so the card adopts the export's exact wording.
    @State private var importedQuestions: [String] = []
    /// The selected day's native answers (question → answeredYes) — drives the chip state.
    @State private var dayAnswers: [String: Bool] = [:]
    /// 0 = today, 1 = yesterday (late logging).
    @State private var journalDayOffset = 0

    var body: some View {
        ScreenScaffold(title: "Insights", subtitle: "Interrogate what affects what.") {
            if !loaded {
                ComingSoon(what: "Reading your journal and outcomes…")
            } else {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    // Native logging — always reachable: the account-free way into Insights.
                    JournalLogCard(importedQuestions: importedQuestions,
                                   answers: dayAnswers,
                                   dayOffset: $journalDayOffset,
                                   onChanged: { Task { await load() } })
                    if behaviours.isEmpty {
                        // No journal yet — explain, without dead-ending on a paid export.
                        NoopCard {
                            Text("Log behaviours above — after a few days of answers, Cénit ranks how each one moves your recovery, HRV and sleep. Importing a WHOOP export (which includes its journal) backfills history instantly.")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        behaviourSection
                    }
                    relationshipsSection
                }
            }
        }
        .task(id: repo.loaded) { await load() }
        // Recompute the cached ranking only when the outcome selection changes.
        // (behaviours / outcomeByKey change only at load, which calls
        //  recomputeRanked() directly, so keying on `outcome` is sufficient.)
        .onChange(of: outcome) { recomputeRanked() }
    }

    // MARK: - Load

    private func load() async {
        // Issue every independent read concurrently — was up to 7 serial awaits (the journal union,
        // imported questions, the selected day's native answers, and one full-history series per
        // outcome) that each round-tripped the main actor before the next. Full history is kept on
        // purpose: Insights ranks behaviour→outcome relationships across all logged days, so this
        // parallelizes the reads rather than windowing them (FER-27).
        let selectedDayKey = Repository.localDayKey(
            Calendar.current.date(byAdding: .day, value: -journalDayOffset, to: Date()) ?? Date())

        async let entriesTask = repo.journalEntries()
        async let importedTask = repo.importedJournalEntries()
        async let nativeTask = repo.nativeJournalAnswers(day: selectedDayKey)
        async let outcomeSeriesTask = loadOutcomeSeries()

        // journalEntries() is the imported ∪ native union (native wins per day+question).
        let entries = await entriesTask
        let imported = await importedTask
        let nativeAnswers = await nativeTask
        let outcomeSeries = await outcomeSeriesTask

        // Journal → behaviours map (only "yes" answers count as the behaviour occurring).
        var byBehaviour: [String: Set<String>] = [:]
        for e in entries where e.answeredYes {
            byBehaviour[e.question, default: []].insert(e.day)
        }

        // The logging card's inputs: the export's exact question strings (so logged days join
        // imported history). A targeted read, since the merged list carries no deviceId to filter on.
        let importedQs = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []

        // Daily metrics for the strap-only outcome fallback (merged, imported-wins). The view is
        // MainActor-isolated, so reading the published cache here is on the right actor.
        let mergedDays = repo.days

        // Outcome series (Whoop) → both [day:value] dictionaries and ordered series. The imported
        // metricSeries only exists after a CSV import; fill the days it doesn't cover from the
        // merged daily metrics so an account-free user's logging still gets effects
        // (recovery/hrv/rhr have daily columns; sleep_performance stays import-only).
        var byKey: [String: [String: Double]] = [:]
        var seriesMap: [String: [(day: String, value: Double)]] = [:]
        for key in outcomeKeys {
            let s = outcomeSeries[key] ?? []
            var dict: [String: Double] = [:]
            for row in s { dict[row.day] = row.value }
            for d in mergedDays where dict[d.day] == nil {
                if let v = Self.dailyOutcome(key: key, day: d) { dict[d.day] = v }
            }
            byKey[key] = dict
            seriesMap[key] = dict.sorted { $0.key < $1.key }.map { (day: $0.key, value: $0.value) }
        }

        await MainActor.run {
            self.behaviours = byBehaviour
            self.importedQuestions = importedQs
            self.dayAnswers = nativeAnswers
            self.outcomeByKey = byKey
            self.seriesByKey = seriesMap
            self.loaded = true
            // Seed the memoized derived state from the freshly loaded inputs.
            self.recomputeRanked()
            self.recomputeRelationships()
        }
    }

    /// Fetch every outcome metric's full Whoop series concurrently, keyed by metric key, so the four
    /// reads overlap instead of running back-to-back on the main actor (FER-27).
    private func loadOutcomeSeries() async -> [String: [(day: String, value: Double)]] {
        await withTaskGroup(of: (String, [(day: String, value: Double)]).self) { group in
            for key in outcomeKeys {
                group.addTask { (key, await repo.series(key: key, source: "my-whoop")) }
            }
            var out: [String: [(day: String, value: Double)]] = [:]
            for await (k, s) in group { out[k] = s }
            return out
        }
    }

    /// The merged DailyMetric column backing an outcome key, for days the imported metricSeries
    /// doesn't cover (strap-only users). sleep_performance has no daily column, so it stays
    /// import-only — never seeded here.
    private static func dailyOutcome(key: String, day d: DailyMetric) -> Double? {
        switch key {
        case "recovery": return d.recovery
        case "hrv":      return d.avgHrv
        case "rhr":      return d.restingHr.map(Double.init)
        default:         return nil
        }
    }

    // MARK: - Memoized recomputation

    /// Rebuild the cached behaviour ranking for the current inputs.
    /// Called at load and whenever `outcome` changes — NOT in `body`.
    private func recomputeRanked() {
        let outcomeDays = outcomeByKey[outcome.key] ?? [:]
        ranked = BehaviorInsights.rank(
            behaviors: behaviours,
            outcomeByDay: outcomeDays,
            outcome: outcome.outcomeName
        )
    }

    /// Rebuild the cached metric relationships from the loaded series.
    /// Called at load only — the series don't change after that.
    private func recomputeRelationships() {
        relationships = computeRelationships()
    }

    // MARK: - Behaviour effects section

    private var behaviourSection: some View {
        // `ranked` is memoized in @State (see recomputeRanked()); reading it
        // here does no expensive work per render.
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            // Header + the ONE segmented pill control for choosing the outcome.
            HStack(alignment: .center) {
                SectionHeader("Behaviour Effects",
                              overline: "What moves your \(outcome.outcomeName.lowercased())")
                Spacer()
                SegmentedPillControl(Outcome.allCases, selection: $outcome) { $0.label }
                    .accessibilityLabel("Outcome metric")
            }

            // Association, not cause; "significant" already controls for testing many
            // behaviours at once (FDR). (FER-299)
            Text("Association, not cause. ‘Significant’ accounts for testing every behaviour at once.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if ranked.isEmpty {
                noEffects
            } else {
                ForEach(ranked.indices, id: \.self) { i in
                    effectCard(ranked[i])
                }
            }
        }
    }

    private var noEffects: some View {
        NoopCard {
            Text("Not enough overlap between your journal answers and \(outcome.outcomeName.lowercased()) "
                + "to measure an effect yet. Keep logging — effects need days both with and without each behaviour.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One behaviour-effect card: sentence + with/without StatTiles + significance pill.
    private func effectCard(_ e: BehaviorEffect) -> some View {
        // Sign-aware tint: did this behaviour move the outcome the GOOD way?
        // good move = (delta > 0 when higherIsBetter) OR (delta < 0 when lower is better).
        let movedGood: Bool? = {
            if e.delta == 0 { return nil }
            let up = e.delta > 0
            return up == outcome.higherIsBetter
        }()
        let tint: StrandTone = {
            guard let good = movedGood else { return .neutral }
            // Only let strong-tint shine when significant; weak effects read muted.
            if e.significant { return good ? .positive : .critical }
            return good ? .positive : .warning
        }()
        let tintColor = toneColor(tint)
        let deltaText: String = {
            let arrow = e.delta > 0 ? "↑" : (e.delta < 0 ? "↓" : "→")
            if let pct = e.pctChange { return "\(arrow) \(Int(abs(pct).rounded()))%" }
            return "\(arrow) \(String(format: "%.1f", abs(e.delta)))"
        }()
        // Build the plain-English sentence ONCE and reuse it for both the visible
        // copy and the accessibility label (was computed twice per card).
        let sentence = BehaviorInsights.sentence(e)

        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {

                // Header: behaviour name + significance pill.
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 8) {
                        Circle().fill(tintColor).frame(width: 8, height: 8)
                        Text(e.behavior)
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    Spacer()
                    StatePill(e.significant ? "SIGNIFICANT" : "EXPLORATORY",
                              tone: e.significant ? .positive : .neutral,
                              showsDot: false)
                }

                // Plain-English sentence.
                Text(sentence)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // With / without means as uniform StatTiles.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 168), spacing: NoopMetrics.gap)],
                    alignment: .leading,
                    spacing: NoopMetrics.gap
                ) {
                    StatTile(label: "With",
                             value: formatOutcome(e.meanWith),
                             caption: "n = \(e.nWith)",
                             accent: tintColor,
                             delta: deltaText,
                             deltaColor: tintColor)
                    StatTile(label: "Without",
                             value: formatOutcome(e.meanWithout),
                             caption: "n = \(e.nWithout)",
                             accent: StrandPalette.textPrimary)
                }

                Divider().overlay(StrandPalette.hairline)

                // Effect-size footer: Cohen's d + interpretation.
                HStack {
                    Text("Effect size").strandOverline()
                    Spacer()
                    HStack(spacing: 6) {
                        Text(String(format: "d = %.2f", e.cohensD))
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(tintColor)
                        Text(effectMagnitudeWord(e.cohensD))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sentence
            + " Cohen's d \(String(format: "%.2f", e.cohensD)). "
            + (e.significant ? "Statistically significant." : "Exploratory, not yet significant."))
    }

    // MARK: - Metric relationships section

    private var relationshipsSection: some View {
        // `relationships` is memoized in @State (see recomputeRelationships());
        // the four Pearson correlations no longer run per render.
        let rels = relationships
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Metric Relationships", overline: "Pearson r")

            // Association, not cause: a correlation says two signals move together, not
            // that one drives the other. (FER-299)
            Text("Association, not cause — these signals move together; neither makes the other happen.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if rels.isEmpty {
                NoopCard {
                    Text("Not enough overlapping history to correlate your metrics yet.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                NoopCard {
                    VStack(spacing: 0) {
                        ForEach(Array(rels.enumerated()), id: \.element.id) { idx, rel in
                            relationshipRow(rel)
                            if idx < rels.count - 1 {
                                Divider().overlay(StrandPalette.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    /// A curated metric relationship plus its computed correlation.
    private struct Relationship: Identifiable {
        let id: String
        let title: String        // "Sleep → Recovery"
        let blurb: String        // what the pairing probes
        let corr: Correlation
        /// True when the pair correlates a series with a shifted copy of ITSELF
        /// (recovery → next-day recovery). The t-test assumes independent samples, so
        /// its p is invalid by construction — we never show a p for these. (FER-299)
        var isAutocorrelated: Bool = false
    }

    private func computeRelationships() -> [Relationship] {
        func series(_ key: String) -> [(day: String, value: Double)] { seriesByKey[key] ?? [] }
        var out: [Relationship] = []

        // Sleep performance ↔ recovery (same day).
        if let c = CorrelationEngine.pearson(
            CorrelationEngine.alignByDay(series("sleep_performance"), series("recovery"))) {
            out.append(.init(id: "sleep-rec",
                             title: "Sleep performance ↔ Recovery",
                             blurb: "How closely a good night tracks next-morning recovery.",
                             corr: c))
        }
        // HRV ↔ recovery (same day).
        if let c = CorrelationEngine.pearson(
            CorrelationEngine.alignByDay(series("hrv"), series("recovery"))) {
            out.append(.init(id: "hrv-rec",
                             title: "HRV ↔ Recovery",
                             blurb: "Heart-rate variability as the engine behind your recovery score.",
                             corr: c))
        }
        // Resting HR ↔ recovery (same day) — expected to be negative.
        if let c = CorrelationEngine.pearson(
            CorrelationEngine.alignByDay(series("rhr"), series("recovery"))) {
            out.append(.init(id: "rhr-rec",
                             title: "Resting HR ↔ Recovery",
                             blurb: "A lower resting heart rate usually means a higher recovery.",
                             corr: c))
        }
        // Today's recovery ↔ NEXT-day recovery (1-day lag) as a strain/carry-over proxy.
        // (Strain series isn't in the outcome set; recovery→next-day recovery shows
        //  how much yesterday carries into today.)
        if let c = CorrelationEngine.lagged(x: series("recovery"), y: series("recovery"), lagDays: 1) {
            out.append(.init(id: "rec-lag",
                             title: "Recovery → Next-day recovery",
                             blurb: "Carry-over: the same signal a day apart (autocorrelation), not an independent relationship.",
                             corr: c,
                             isAutocorrelated: true))
        }

        return out
    }

    private func relationshipRow(_ rel: Relationship) -> some View {
        let r = rel.corr.r
        let strength = correlationColor(r)
        // Build the reading sentence ONCE and reuse it for the visible copy and
        // the accessibility label (was computed twice per row).
        let sentence = relationshipSentence(rel)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(rel.title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Text(String(format: "r = %+.2f", r))
                    .font(StrandFont.number(16))
                    .foregroundStyle(strength)
                // No per-relationship significance stamp: marking each of K correlations
                // "p < 0.05" with no multiple-comparison control manufactures false
                // positives. Autocorrelated pairs get a label instead of a (meaningless)
                // p. (FER-299)
                if rel.isAutocorrelated {
                    StatePill("carry-over", tone: .neutral, showsDot: false)
                }
            }

            // r bar — visual magnitude/direction (hover reveals the exact value).
            rBar(r: r, color: strength, label: rel.title)

            Text(sentence)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(rel.blurb)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sentence)
    }

    /// A centred bar: zero in the middle, fills left (negative) or right (positive)
    /// proportional to |r|. Hovering reveals a tooltip with the exact r value, so the
    /// bar — like every Strand chart — is never an unexplained coloured shape.
    private func rBar(r: Double, color: Color, label: String) -> some View {
        RBar(r: r, color: color, label: label)
    }

    // MARK: - Formatting / interpretation helpers

    /// Map a tone to its public palette color (StrandTone.color is module-internal).
    private func toneColor(_ tone: StrandTone) -> Color {
        switch tone {
        case .neutral:  return StrandPalette.textSecondary
        case .accent:   return StrandPalette.accent
        case .positive: return StrandPalette.statusPositive
        case .warning:  return StrandPalette.statusWarning
        case .critical: return StrandPalette.statusCritical
        }
    }

    /// Format an outcome value with sensible units for the selected metric.
    private func formatOutcome(_ v: Double) -> String {
        switch outcome {
        case .recovery, .sleep: return "\(Int(v.rounded()))%"
        case .hrv:              return "\(Int(v.rounded())) ms"
        case .rhr:              return "\(Int(v.rounded())) \(String(localized: "bpm"))"
        }
    }

    /// Cohen's d → conventional magnitude word.
    private func effectMagnitudeWord(_ d: Double) -> String {
        switch abs(d) {
        case ..<0.2:  return String(localized: "negligible")
        case ..<0.5:  return String(localized: "small")
        case ..<0.8:  return String(localized: "moderate")
        default:      return String(localized: "large")
        }
    }

    /// |r| → strength word.
    private func strengthWord(_ r: Double) -> String {
        switch abs(r) {
        case ..<0.1:  return String(localized: "no")
        case ..<0.3:  return String(localized: "a weak")
        case ..<0.5:  return String(localized: "a moderate")
        case ..<0.7:  return String(localized: "a strong")
        default:      return String(localized: "a very strong")
        }
    }

    /// Tint a correlation by strength, keyed on the recovery gradient so strong
    /// positive reads mint and strong negative reads red.
    private func correlationColor(_ r: Double) -> Color {
        // Map r∈[-1,1] → 0…1 of the recovery scale (−1 red, 0 gold, +1 mint).
        StrandPalette.sample(stops: StrandPalette.recoveryStops, at: (r + 1) / 2)
    }

    private func relationshipSentence(_ rel: Relationship) -> String {
        let r = rel.corr.r
        // Autocorrelation: the signal vs a shifted copy of itself. Frame as day-to-day
        // persistence, never as an independent relationship with a p-value. (FER-299)
        if rel.isAutocorrelated {
            return String(localized: "Day-to-day persistence (r = \(String(format: "%.2f", r)), n = \(rel.corr.n)) — the same signal compared with itself, so there's no independent significance to report.")
        }
        let dir = r > 0 ? String(localized: "positive") : (r < 0 ? String(localized: "negative") : String(localized: "flat"))
        let strength = strengthWord(r)
        return String(localized: "\(strength.capitalizedFirst) \(dir) relationship (r = \(String(format: "%.2f", r)), n = \(rel.corr.n)).")
    }
}

// MARK: - Correlation magnitude bar (hover-aware)

/// A centred correlation bar (zero in the middle, fills left/negative or
/// right/positive by |r|). On hover it shows the locked ChartTooltip with the exact
/// r value, matching the hover affordance every other Strand chart provides.
private struct RBar: View {
    let r: Double
    let color: Color
    let label: String

    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let mag = CGFloat(min(abs(r), 1.0)) * half
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.surfaceInset)
                // centre tick
                Rectangle()
                    .fill(StrandPalette.hairlineStrong)
                    .frame(width: 1)
                    .position(x: half, y: geo.size.height / 2)
                // value fill
                Capsule()
                    .fill(color)
                    .frame(width: mag, height: geo.size.height)
                    .offset(x: r >= 0 ? half : half - mag)
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        // Tooltip floats above the bar without affecting layout (overlays aren't
        // clipped), so the exact r value reads on hover — same affordance as charts.
        .overlay(alignment: .center) {
            if hovering {
                ChartTooltip(
                    value: String(format: "r = %+.2f", r),
                    label: label,
                    accent: color
                )
                .fixedSize()
                .offset(y: -26)
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active: hovering = true
            case .ended:  hovering = false
            }
        }
        .animation(StrandMotion.fade, value: hovering)
        .accessibilityHidden(true)
    }
}

private extension String {
    /// Capitalise only the first letter (keeps "a weak" → "A weak").
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func insightsPreviewRepo() -> Repository {
    let repo = Repository(deviceId: "preview")
    repo.setDashboard()
    return repo
}

#Preview("Insights") {
    InsightsView()
        .environmentObject(insightsPreviewRepo())
        .frame(width: 920, height: 900)
        .preferredColorScheme(.dark)
}
#endif
