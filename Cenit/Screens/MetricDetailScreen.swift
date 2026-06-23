#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import Foundation

// MARK: - MetricDetailScreen — the unified, reusable Detalle de Métrica (FER-185)
//
// One light «Instrumento» screen that replaces, FOR THE THREE VITALS (HRV / FC en reposo /
// Frecuencia respiratoria), both the old `MetricInfoSheet` (from Hoy) and the dark
// `MetricDetailView` (from Cuerpo's Explorer bridge). It is parameterised by a `MetricDetailSpec`
// (which blocks, how the hero reads, the baseline config) and a `Depth`:
//
//   • `.focus` (from Hoy) — a quick "photo of the day": a short window and only the chart+band,
//     normal range, night vitals (where the spec has them) and method.
//   • `.full`  (from Cuerpo) — every block the spec declares.
//
// It is ONE view tree filtered by depth, never two screens. The theme is passed EXPLICITLY (it does
// NOT propagate through `.sheet`'s fresh environment — FER-162) and it is presented via `.sheet(item:)`
// WITHOUT a nested NavigationStack (a nested stack crossing the tab's path crashed SwiftUI — FER-171).
//
// Data: the three vitals come from `repo.displayDays` for a BLE user (computed scores live under
// `my-whoop-noop`, so `series("my-whoop")` is empty) — the caller injects the loaders. The hero is the
// 7-day moving average (`SeriesShape.latestMovingAverage`), not today's single reading; today is shown
// as secondary context.

struct MetricDetailScreen: View {
    let spec: MetricDetailSpec
    /// Hoy opens `.focus`; Cuerpo opens `.full`.
    var depth: Depth = .full
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    /// When the metric is Apple-sourced and there's no reading + no permission, the empty state adds a
    /// quiet "Connect Apple Health" line. Only used by the sparse VO₂max empty state today. (FER-257)
    var appleConnectHint: Bool = false
    /// True when TODAY's reading (the «Hoy» datum) came from Apple Health rather than the band — the
    /// caller already resolves this per reading (`appleSource` in TodayView, `resolveMeasured.fromApple`
    /// in CuerpoView). Drives the «Apple» provenance seal on the narrative vitals so a band-less Apple
    /// reading never reads identical to a band one (FER-487). Never set for Heart Rate (band intraday).
    var todayFromApple: Bool = false

    /// Loads the full daily series for this metric (oldest → newest), as `(day "yyyy-MM-dd", value)`.
    /// Injected so the screen stays DB-free and the caller controls the source (`displayDays` for BLE,
    /// Apple-Health series as a fallback).
    var seriesLoader: () async -> [(day: String, value: Double)]
    /// Loads last night's companion vitals for the "Vitales de la noche" block: respiration + resting HR.
    /// Only used when the spec declares `.nightVitals`.
    var nightVitalsLoader: (() async -> NightVitals)? = nil
    /// Loads the gated directional findings for the "Qué la mueve" block (FER-209). Only used when the
    /// spec declares `.whatMovesIt`; the caller computes them from `repo.displayDays` (DB-free here).
    var whatMovesItLoader: (() async -> [WhatMovesItFinding])? = nil
    /// Loads today's intraday HR curve (5-minute buckets). Injected only for Heart Rate (the spec
    /// declares `.intradayCurve`); the caller reuses the same `hrPoints` the summary sheet uses. (FER-253)
    var intradayCurveLoader: (() async -> [TrendPoint])? = nil
    /// The user's estimated max HR (bpm), for the "time in zones" block. 0 disables zones. (FER-253)
    var hrMax: Double = 0
    /// Last night's resting HR (bpm), drawn as a quiet reference line under the day's curve. (FER-253)
    var restingHR: Double? = nil
    /// Today's local day key ("yyyy-MM-dd"), passed by the caller (it uses `Repository.localDayKey`, which
    /// the DB-free screen can't reproduce timezone-for-timezone). Lets the trend figures drop the
    /// in-progress current day for a cumulative metric (steps). nil → nothing is dropped. (FER-264)
    var todayKey: String? = nil
    /// «See more in Trends» action for the F6b level pattern (FER-571). The caller routes to the Tendencias
    /// tab (`tabRouter.select(.body)`) or, when the detail is already opened FROM Tendencias, a no-op (the
    /// link just dismisses back to it). `nil` hides the link. The screen dismisses itself after calling it.
    var onSeeTrends: (() -> Void)? = nil

    enum Depth { case focus, full }

    /// The «Tu historia» chart view for metrics with population ranges. (Detalle de Vital)
    enum ChartMode: Hashable, CaseIterable { case movingAverage, ranges }

    /// Companion vitals for the night block.
    struct NightVitals: Equatable {
        var respiration: Double?
        var restingHR: Double?
    }

    /// Dismisses the sheet from the F6b nav close button and the «See more in Trends» link. (FER-571)
    @Environment(\.dismiss) private var dismiss
    /// The level the user is exploring in the F6b levels list — `nil` shows today's level. Tapping a row
    /// highlights its band on the chart, dims the rest and re-reads the phrase; tapping it again clears. (FER-571)
    @State private var selectedLevelIndex: Int? = nil
    @State private var range: ExploreRange = .month
    /// Which inline disclosure is open (one at a time per sheet): `"band"`, `"stat:<slot>"` or `"quemueve"`.
    /// nil = none. Replaces the per-block ⓘ `InfoAccordion`s for the redesigned vitals — the whole datum is
    /// the tap target now, and tapping toggles a panel that reuses the SAME `explanation` copy. (Detalle de Vital)
    @State private var openDisclosure: String? = nil
    /// «Tu historia» chart mode for metrics that carry labeled population ranges (Resting HR / Respiration /
    /// Steps): your 7-day moving average + personal band, OR the classification ranges (athlete / excellent /
    /// normal / elevated …) showing where you fall. HRV (personal only) and SpO₂ (already clinical) don't
    /// toggle. The «what does this number mean» view the owner asked back for. (Detalle de Vital)
    @State private var chartMode: ChartMode = .movingAverage
    @State private var series: [(day: String, value: Double)] = []
    @State private var nightVitals: NightVitals = NightVitals(respiration: nil, restingHR: nil)
    @State private var whatMovesItFindings: [WhatMovesItFinding] = []
    @State private var intradayCurve: [TrendPoint] = []
    /// Minutes per HR zone for today, computed once when the curve loads (see `computeZoneMinutes`). (FER-253)
    @State private var cachedZoneMinutes: [Double]? = nil
    @State private var loaded = false

    /// Heart Rate routes through a separate, intraday path (today's curve at minute resolution) rather
    /// than the daily-series machinery the vitals use. (FER-253)
    private var isIntraday: Bool { spec.blocks.contains(.intradayCurve) }

    /// The five vitals the «Detalle de Vital» narrative redesign covers — HRV, Resting HR, Respiratory
    /// rate, Blood oxygen (SpO₂) and Heart Rate. They render the Hoy → Tu historia → (Tu patrón) → Método
    /// narrative with the inline range band, the tappable stat strip and per-datum disclosures. Steps and
    /// VO₂max also ride this screen but keep their existing block layout (out of the handoff's scope).
    private var isNarrative: Bool {
        ["hrv", "rhr", "resp_rate", "spo2", "heart_rate"].contains(spec.descriptor.key)
    }

    /// The five metrics the F6b level pattern (FER-571) covers — the four narrative vitals MINUS Heart Rate
    /// (which keeps its intraday curve) PLUS Steps. They render nav → range → line chart → «{level} · N días»
    /// → tappable levels list → «See more in Trends», dropping the prom/mín/máx/último stat strip and the
    /// old hero/inline-band. Recovery/Strain/Stress/Sleep have their own screens → F6c. (FER-571)
    private var usesLevels: Bool {
        ["hrv", "rhr", "spo2", "resp_rate", "steps"].contains(spec.descriptor.key)
    }

    // MARK: - Depth → visible blocks

    /// `.full` shows everything the spec declares; `.focus` shows only the day-photo subset.
    private var visibleBlocks: BlockSet {
        switch depth {
        case .full:  return spec.blocks
        case .focus: return spec.blocks.intersection([.seriesChartBand, .normalRange, .method, .nightVitals, .intradayCurve, .hrZones])
        }
    }

    /// The default window: a short week in focus, a month at full depth.
    private var defaultRange: ExploreRange { depth == .focus ? .week : .month }

    // MARK: - Body

    var body: some View {
        // Derive the window ONCE here, then hand it to every block — instead of each block
        // re-deriving `effectiveRange`/`windowed`/`windowValues` and re-parsing the whole
        // history on every redraw. (FER-216)
        let window = MetricWindowMath.make(parsedSeries, selected: range)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if usesLevels {
                    levelPatternBody(window)
                } else {
                hero
                if loaded {
                    // Heart Rate's intraday path has no "N/7 nights" calibration — each block shows its
                    // own honest empty state (no readings yet today). (FER-253)
                    if isIntraday {
                        content(window)
                    } else if spec.sparseMeasured {
                        // A sparsely-measured metric (VO₂max): one reading is enough to render; zero
                        // readings show a dedicated explanatory empty state, not the nights-calibration. (FER-257)
                        if series.isEmpty {
                            sparseEmptyState
                        } else {
                            content(window)
                        }
                    } else if enoughHistory {
                        content(window)
                    } else {
                        calibrationBlock
                    }
                } else {
                    loadingWell(height: 160)
                }
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .modifier(SheetPaperBackground(paper: theme.paper))
        .task {
            range = defaultRange
            if let loader = intradayCurveLoader {
                intradayCurve = await loader()
                cachedZoneMinutes = computeZoneMinutes()
            }
            series = await seriesLoader()
            // Parse every day string to a Date ONCE per series (not per slice / per render). (FER-216)
            parsedSeries = series.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
            if let loader = nightVitalsLoader { nightVitals = await loader() }
            if visibleBlocks.contains(.whatMovesIt), let loader = whatMovesItLoader {
                whatMovesItFindings = await loader()
            }
            loaded = true
        }
    }

    /// The body below the hero. The redesigned five vitals get the Hoy → Tu historia → (Tu patrón) →
    /// Método narrative; Steps / VO₂max keep the original divider-separated block stack. (Detalle de Vital)
    @ViewBuilder private func content(_ window: MetricWindow) -> some View {
        if isNarrative {
            narrativeContent(window)
        } else {
            legacyContent(window)
        }
    }

    /// The original block stack (kept verbatim for Steps / VO₂max, which the redesign doesn't touch).
    @ViewBuilder private func legacyContent(_ window: MetricWindow) -> some View {
        let hasMethod = visibleBlocks.contains(.method) && spec.info.method != nil
        // Heart Rate's intraday blocks (curve always renders something; zones only when there's
        // elevation to report, so its divider is gated to avoid a dangling rule). (FER-253)
        if visibleBlocks.contains(.intradayCurve) {
            blockDivider
            intradayBlock
        }
        if visibleBlocks.contains(.hrZones), let mins = cachedZoneMinutes, mins[1...].contains(where: { $0 > 0 }) {
            blockDivider
            hrZonesBlock(mins)
        }
        if visibleBlocks.contains(.periodSelector) {
            blockDivider
            periodSelector(window)
        }
        if visibleBlocks.contains(.seriesChartBand) {
            blockDivider
            chartBlock(window)
        }
        if visibleBlocks.contains(.normalRange), spec.descriptor.key != "hrv" {
            blockDivider
            normalRangeBlock
        }
        if visibleBlocks.contains(.consistency) {
            blockDivider
            consistencyBlock
        }
        if visibleBlocks.contains(.lowNightsCount) {
            blockDivider
            lowNightsBlock
        }
        if visibleBlocks.contains(.trend) {
            blockDivider
            trendBlock(window)
        }
        if visibleBlocks.contains(.normalRange), spec.descriptor.key == "hrv" {
            blockDivider
            normalRangeBlock
        }
        if visibleBlocks.contains(.nightVitals) {
            blockDivider
            nightVitalsBlock
        }
        // Shown whenever there's series data — when no relationship clears the gate it renders an honest
        // empty state instead of vanishing (FER-246). Stays hidden on a cold-start/empty screen.
        if visibleBlocks.contains(.whatMovesIt), !series.isEmpty {
            blockDivider
            whatMovesItBlock
        }
        // VO₂max's age/sex-anchored extras (change over the period · fitness category · cardiorespiratory-
        // equivalent age · why it matters) sit between the chart and the method. (FER-257)
        if spec.descriptor.key == "vo2max" {
            vo2maxExtras(window)
        }
        if hasMethod, let method = spec.info.method {
            blockDivider
            methodDisclosure(method)
        }
    }

    /// A subtle 1px rule between blocks (token-only, no hex). (FER-216)
    private var blockDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    // MARK: - Detalle de Métrica · level pattern (FER-571 / F6b)
    //
    // The five `usesLevels` metrics (HRV / Resting HR / Blood oxygen / Respiration / Steps) replace the old
    // hero + inline band + prom/mín/máx/último stat strip with: a nav (close · serif name · ⓘ method · source
    // chip), a range control, a RAW-value line chart (head point = today, the highlighted level's band shaded),
    // a «{level} · N días» phrase, a TAPPABLE levels list (tap a row → highlight its band, dim the rest, re-read
    // the phrase; today keeps a ring while you explore), and a «See more in Trends» link. Levels + counts come
    // from F6a (`MetricLevels`); HRV uses its personal, log-aware cut points (multiplicative band in ms).

    /// One render's level classification: the ordered levels, per-level day counts, the total counted, and
    /// the level today's reading sits in (the «· today» row + ring). (FER-571)
    private struct LevelData {
        let levels: [MetricLevels.Level]
        let counts: [Int]
        let total: Int
        let todayIndex: Int?
    }

    /// The F6a fixed metric for this key, or nil for HRV (which uses personal relative levels). (FER-571)
    private var fixedMetricForKey: MetricLevels.FixedMetric? {
        switch spec.descriptor.key {
        case "rhr":       return .restingHR
        case "spo2":      return .bloodOxygen
        case "resp_rate": return .respiration
        case "steps":     return .steps
        default:          return nil
        }
    }

    /// The ordered levels for this metric: F6a's fixed thresholds, or HRV's personal cut points. HRV is
    /// log-normal, so the cuts are derived in LOG space via `Baselines.normalRange` (which back-transforms
    /// exp(lnBaseline ± σ) to ms) — the band is multiplicative, not a raw linear ±SD, exactly as F6a's
    /// `relativeLevels` note prescribes. nil for HRV until there's a baseline. (FER-571 · Plews 2013)
    private var levelLevels: [MetricLevels.Level]? {
        if let fm = fixedMetricForKey { return MetricLevels.levels(for: fm) }
        guard spec.descriptor.key == "hrv", let s = baselineState, s.nValid >= 1 else { return nil }
        let band = Baselines.normalRange(s)
        return [
            MetricLevels.Level(key: "below",  lower: nil, upper: band.lowerBound),
            MetricLevels.Level(key: "inBase", lower: band.lowerBound, upper: band.upperBound),
            MetricLevels.Level(key: "above",  lower: band.upperBound, upper: nil),
        ]
    }

    /// The value that sets today's active level: the latest reading for the vitals; the latest COMPLETED day
    /// for steps (today is still a running total). nil when there's no reading. (FER-571)
    private var levelTodayValue: Double? {
        // Steps' today is a running total → use the latest COMPLETED day (the same `dropsIncompleteToday`
        // rule `trendStatRows`/`trendComparisonSeries` apply); every other metric's today is final. (FER-571)
        spec.currentDayIncomplete ? trendComparisonSeries.last?.value : todayValue
    }

    private func levelData(_ window: MetricWindow) -> LevelData? {
        guard let levels = levelLevels else { return nil }
        let values = trendStatRows(window).map(\.value)   // completed days (steps drops the in-progress today)
        let today = levelTodayValue
        // Fixed metrics use F6a's per-metric thresholds; HRV passes its own log-derived levels. Both go
        // through the same F6a classifier (half-open [lower, upper), counts sum to the window). (FER-571)
        let c = fixedMetricForKey.map { MetricLevels.classification(for: $0, values: values, today: today) }
            ?? MetricLevels.classification(values: values, today: today, levels: levels)
        return LevelData(levels: c.levels, counts: c.counts, total: c.total, todayIndex: c.activeIndex)
    }

    /// The level the chart + phrase highlight: the user's selection, else today's. (FER-571)
    private func displayLevelIndex(_ data: LevelData) -> Int? {
        if let s = selectedLevelIndex, data.levels.indices.contains(s) { return s }
        return data.todayIndex
    }

    // MARK: Level pattern — views

    @ViewBuilder private func levelPatternBody(_ window: MetricWindow) -> some View {
        levelNav
        if loaded {
            if let data = levelData(window) {
                VStack(alignment: .leading, spacing: 22) {
                    levelRangeControl(window)
                    levelPhrase(data)
                    levelChart(window, data)
                    levelList(data)
                    if spec.descriptor.key == "hrv" { hrvBaseNote }
                    if let onSeeTrends { levelSeeMore(onSeeTrends) }
                    if visibleBlocks.contains(.method), let method = spec.info.method {
                        methodDisclosure(method)
                    }
                }
            } else {
                // HRV with no baseline yet (or no levels): the same calibration well the rest of the screen uses.
                calibrationBlock
            }
        } else {
            loadingWell(height: 200)
        }
    }

    private var levelNav: some View {
        HStack(spacing: NoopMetrics.space2) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.inkSecondary).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            Text(levelNavTitle).font(StrandFont.serif(24)).foregroundStyle(theme.ink)
            if spec.info.method != nil {
                Button { withAnimation(.easeInOut(duration: 0.25)) { methodExpanded.toggle() } } label: {
                    Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How it's calculated")
            }
            Spacer(minLength: 8)
            levelSourceChip
        }
    }

    /// The nav source chip (F4 / FER-552): Apple when today's datum came from Apple Health, else the band —
    /// Steps are always Apple-sourced. The «calculated» mode is for the derived metrics (none of the five here).
    @ViewBuilder private var levelSourceChip: some View {
        if loaded {
            if todayFromApple || spec.descriptor.key == "steps" {
                InlineFlagChip("Apple", color: theme.dataSpO2)
            } else {
                InlineFlagChip("Band", color: theme.dataRecovery)
            }
        }
    }

    private var levelNavTitle: LocalizedStringKey {
        switch spec.descriptor.key {
        case "hrv":        return "HRV"
        case "rhr":        return "Resting HR"
        case "spo2":       return "Blood oxygen"
        case "resp_rate":  return "Respiratory rate"
        case "steps":      return "Steps"
        default:           return ""
        }
    }

    private func levelRangeControl(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme) { $0.label }
                .onChange(of: range) { _ in selectedLevelIndex = nil }
            if window.fellBack {
                Text("Showing the last \(window.rows.count) days")
                    .font(StrandFont.footnote).foregroundStyle(theme.warning)
            }
        }
    }

    @ViewBuilder private func levelPhrase(_ data: LevelData) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let i = displayLevelIndex(data) {
                Text(levelLabel(data.levels[i].key)).font(StrandFont.title1).foregroundStyle(metricHue)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(data.counts[i]) of your last \(data.total) days")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            } else {
                Text("No reading today").font(StrandFont.title1).foregroundStyle(theme.inkTertiary)
                Text("\(data.total) days with data in this range")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    @ViewBuilder private func levelChart(_ window: MetricWindow, _ data: LevelData) -> some View {
        let highlight = displayLevelIndex(data)
        MetricTrendChart(
            range: $range, window: window, theme: theme, showsSelector: false,
            style: .init(
                smoothing: nil,                          // RAW daily values so the dots fall in the bands the counts read
                gradient: chartGradient,
                showsArea: false,
                height: 168,
                valueRange: { levelChartDomain(data, values: $0) },
                valueFormat: { "\(fmt($0)) \(unit)" },
                bands: { _ in levelChartBands(data, highlight: highlight) },
                bandColor: { _ in metricHue },
                yAxisValues: levelYTicks(data),
                yTickCount: 5,
                marksLastPoint: data.todayIndex != nil,
                markedPointHollow: selectedLevelIndex != nil && selectedLevelIndex != data.todayIndex,
                markedPointRingFill: theme.paper,
                bandLabelsHidden: true,                  // the levels are named in the list, not on the plot
                accessibilityLabel: chartAccessibilityLabel
            )
        ) {
            emptyWell(text: "No readings in this range.")
        }
        if spec.currentDayIncomplete, window.values.count > 1 {
            Text("The line includes today, still in progress; the figures below use completed days only.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func levelChartBands(_ data: LevelData, highlight: Int?) -> [TrendBand] {
        data.levels.enumerated().map { i, l in
            TrendBand(label: "", lower: l.lower, upper: l.upper, isActive: i == highlight)
        }
    }

    /// The chart's Y domain: SpO₂'s fixed clinical 88…100, else the level thresholds + the plotted line's
    /// own min/max with a little breath (steps anchor at 0 — an absolute count). (FER-571)
    private func levelChartDomain(_ data: LevelData, values: [Double]) -> ClosedRange<Double> {
        if let d = spec.chartDomain { return d }
        let bounds = data.levels.flatMap { [$0.lower, $0.upper].compactMap { $0 } }
        let pool = bounds + values
        guard let lo0 = pool.min(), let hi0 = pool.max(), hi0 > lo0 else {
            let v = values.first ?? bounds.first ?? 0
            return (v - 1)...(v + 1)
        }
        let steps = spec.descriptor.key == "steps"
        let lo = steps ? 0 : lo0
        let span = max(hi0 - lo, 0.0001)
        return (lo - (steps ? 0 : span * 0.1))...(hi0 + span * 0.12)
    }

    private func levelYTicks(_ data: LevelData) -> [Double]? {
        let t = Set(data.levels.flatMap { [$0.lower, $0.upper].compactMap { $0 } }).sorted()
        return t.isEmpty ? nil : t
    }

    private func levelList(_ data: LevelData) -> some View {
        let highlight = displayLevelIndex(data)
        return VStack(spacing: 0) {
            ForEach(Array(data.levels.enumerated()), id: \.offset) { i, level in
                levelRow(index: i, level: level, data: data, highlight: highlight)
                if i < data.levels.count - 1 {
                    Divider().overlay(theme.hairline).padding(.leading, 34)
                }
            }
        }
    }

    private func levelRow(index i: Int, level: MetricLevels.Level, data: LevelData, highlight: Int?) -> some View {
        let isHighlight = i == highlight
        let isToday = i == data.todayIndex
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedLevelIndex = (selectedLevelIndex == i) ? nil : i   // tap the highlighted row → back to today
            }
        } label: {
            HStack(spacing: 10) {
                levelDot(isHighlight: isHighlight, isToday: isToday)
                Text(levelLabel(level.key)).font(StrandFont.subhead)
                    .foregroundStyle(isHighlight ? theme.ink : theme.inkSecondary)
                if isToday {
                    Text("· today").font(StrandFont.footnote).foregroundStyle(metricHue)
                }
                Spacer(minLength: 8)
                Text(levelRangeText(level)).font(StrandFont.captionNumber)
                    .foregroundStyle(isHighlight ? metricHue : theme.inkTertiary)
                Text(BandSummaryCopy.countLabel(data.counts[i], nightly: false))
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(isHighlight ? metricHue : theme.inkTertiary.opacity(0.85))
                    .frame(minWidth: 50, alignment: .trailing)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(isHighlight ? metricHue.opacity(0.10) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Highlights this level on the chart"))
    }

    /// The row's dot: filled in the metric hue when highlighted, a hollow RING when it's today's level but
    /// you're exploring another (matching the chart's hollow head), else a quiet dot. (FER-571 · option A)
    @ViewBuilder private func levelDot(isHighlight: Bool, isToday: Bool) -> some View {
        if isToday && !isHighlight {
            Circle().strokeBorder(metricHue, lineWidth: 2).frame(width: 8, height: 8)
        } else {
            Circle().fill(isHighlight ? metricHue : theme.inkTertiary.opacity(0.45)).frame(width: 8, height: 8)
        }
    }

    private var hrvBaseNote: some View {
        Text("Your levels come from your own baseline, not a table.")
            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func levelSeeMore(_ action: @escaping () -> Void) -> some View {
        Button {
            action(); dismiss()
        } label: {
            HStack(spacing: 5) {
                Text("See more in Trends").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    /// A level's numeric range, half-open `[lower, upper)`: «< hi» (open below), «≥ lo» (open above), «lo–hi».
    private func levelRangeText(_ level: MetricLevels.Level) -> String {
        switch (level.lower, level.upper) {
        case let (nil, hi?):  return "< \(fmt(hi))"
        case let (lo?, nil):  return "≥ \(fmt(lo))"
        case let (lo?, hi?):  return "\(fmt(lo))–\(fmt(hi))"
        case (nil, nil):      return ""
        }
    }

    /// The es-MX/en label for an F6a level key. (FER-571)
    private func levelLabel(_ key: String) -> LocalizedStringKey {
        switch key {
        case "athlete":    return "Athlete"
        case "excellent":  return "Excellent"
        case "normal":     return "Normal"
        case "elevated":   return "Elevated"
        case "low":        return "Low"
        case "sedentary":  return "Sedentary"
        case "active":     return "Active"
        case "veryActive": return "Very active"
        case "below":      return "Below your base"
        case "inBase":     return "In your base"
        case "above":      return "Above your base"
        default:           return LocalizedStringKey(key)
        }
    }

    // MARK: - Derived series

    private var unit: String { spec.info.unit ?? "" }

    private var allValues: [Double] { series.map(\.value) }

    /// The series with each `day` string parsed to a `Date` exactly ONCE per series (not per slice,
    /// not per render). The shared window math (`MetricWindowMath`) reads `date` straight from here instead
    /// of re-parsing. Built in `.task` alongside `series`. (FER-216 / FER-269)
    @State private var parsedSeries: [(day: String, date: Date?, value: Double)] = []

    /// The hero figure: the 7-day moving average over the FULL series (not just the window), so it
    /// reads as "your current 7-day level" regardless of the selected range. `.latest` falls back to
    /// the last reading for specs that prefer it.
    private var heroValue: Double? {
        switch spec.hero {
        case .movingAverage7:  return SeriesShape.latestMovingAverage(allValues, window: 7)
        case .latest:          return series.last?.value
        case .intradayAverage: return intradayAverage
        }
    }

    /// The mean of today's intraday curve (the Heart Rate hero). nil when there are no readings. (FER-253)
    private var intradayAverage: Double? {
        let v = intradayCurve.map(\.value)
        guard !v.isEmpty else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }

    /// Today's (most recent) single reading, shown as secondary context under the hero.
    private var todayValue: Double? { series.last?.value }

    /// "Enough history" gate: at least 2 points to draw a line / band / trend. Below that we show the
    /// calibration block instead of charts.
    private var enoughHistory: Bool { series.count >= 2 }

    // MARK: - Plain-language reading copy (FER-216)

    /// The blocks that carry a plain-language "what this means" sentence under their datum.
    enum BlockKind { case header, normalRange, consistency, trend, nightVitals }

    /// One es-MX sentence in plain language under a block's datum (`inkSecondary`), per metric. Returns
    /// `nil` when a block has no reading for this metric (e.g. RHR has no consistency block). The night-
    /// vitals sentence is shared by HRV and respiration on purpose (it describes the same companion
    /// signals), so it localizes from a single key. Source strings are English; the es values live in
    /// `Localizable.xcstrings`. (FER-216)
    private func readingCopy(for block: BlockKind) -> LocalizedStringKey? {
        let nightVitals: LocalizedStringKey =
            "Other signals from your body while you sleep. When they all rise together, something is taxing you (illness, alcohol, hard effort)."
        switch (spec.descriptor.key, block) {
        case ("hrv", .header):
            return "Higher HRV usually means better recovery. What matters is your trend, not any single day's number."
        case ("hrv", .normalRange):
            return "Where your HRV usually lands when you're well. Only worth noting when a day falls outside it."
        case ("hrv", .consistency):
            return "How even it stays from one week to the next. Steadier usually means better rest; very uneven can be fatigue."
        case ("hrv", .trend):
            return "Where your HRV is headed this month compared with last month."
        case ("hrv", .nightVitals):
            return nightVitals

        case ("rhr", .header):
            return "Your pulse when your body is calm. Lower usually means better fitness; a rise above your normal can be fatigue."
        case ("rhr", .normalRange):
            return "Where your resting HR usually lands when you're well. Take note when a day falls outside it."
        case ("rhr", .trend):
            return "Where your resting HR is headed this month compared with last month."

        case ("resp_rate", .header):
            return "One of your steadiest signals. A rise above your own normal can be an early sign that something is taxing you."
        case ("resp_rate", .normalRange):
            return "Where your nightly breathing usually lands. Take note when a day falls outside it."
        case ("resp_rate", .trend):
            return "Where your breathing is headed this month compared with last month."
        case ("resp_rate", .nightVitals):
            return nightVitals

        case ("spo2", .header):
            return "The oxygen in your blood, read at your wrist while you sleep. A healthy adult usually stays at 95% or above."

        case ("heart_rate", .header):
            return "Your heart rate across the day, in 5-minute averages. Your resting heart rate — the low while you sleep — is its own metric."

        case ("steps", .header):
            return "Your step count for today. Steady activity — even a short walk — supports your heart, your mood and your recovery."
        case ("steps", .trend):
            return "Where your steps are headed this month compared with last month."

        default:
            return nil
        }
    }

    // MARK: - Hero

    /// The redesigned vitals lead with TODAY's reading (the «Hoy» section); Steps / VO₂max keep the
    /// original hero (7-day average / latest reading). (Detalle de Vital)
    @ViewBuilder private var hero: some View {
        if isNarrative { narrativeHero } else { legacyHero }
    }

    private var legacyHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Serif in-screen title (FER-581). The "· 7-day average / · today" context the old overline
            // carried now lives in `heroSecondary` below the numeral; the title is just the metric name.
            InstrumentoScreenTitle(legacyHeroTitle, theme: theme)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(heroValue.map { fmt($0) } ?? "—")
                    .instrumentoHero(44)
                    .foregroundStyle(heroValue == nil ? theme.inkTertiary : metricHue)
                if heroValue != nil, !unit.isEmpty {
                    Text(unit).font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                }
            }
            if loaded { heroSecondary }
            if let reading = readingCopy(for: .header) {
                Text(reading)
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The secondary line(s) under the hero numeral. VO₂max reads its latest value against its age/sex
    /// peers across up to three lines (comparison · expected · measured-ago — FER-257); every other metric
    /// shows the single `heroSecondaryText` (vitals frame today against the band, steps show the 7-day
    /// average, Heart Rate shows today's range — FER-253/254).
    @ViewBuilder private var heroSecondary: some View {
        if spec.descriptor.key == "vo2max" {
            if heroValue != nil {
                Text(vo2maxComparison)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let expected = vo2maxExpectedLine {
                    Text(expected)
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let ago = vo2maxMeasuredAgoLine {
                    Text(ago)
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.inkTertiary)
                }
            }
        } else if let text = heroSecondaryText {
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Heart Rate (intraday) → today's range + resting floor; steps → its 7-day daily average; the
    /// vitals → today's reading framed against the band.
    private var heroSecondaryText: LocalizedStringKey? {
        if isIntraday { return intradayHeroContext }
        if spec.descriptor.key == "steps" {
            guard let avg = SeriesShape.latestMovingAverage(allValues, window: 7) else { return nil }
            return "7-day average · \(fmt(avg)) steps"
        }
        guard let today = todayValue else { return nil }
        return heroContext(today)
    }

    /// The serif in-screen title for the legacy hero (Steps / VO₂max) — the metric's short name. (FER-581)
    private var legacyHeroTitle: LocalizedStringKey {
        switch spec.descriptor.key {
        case "steps":  return "Steps"
        case "vo2max": return "VO₂ Max"
        default:       return "Today"
        }
    }

    /// The Heart Rate hero context: today's average is the hero, so frame it with the day's range and
    /// the night's resting floor. nil until there are at least two readings. (FER-253)
    private var intradayHeroContext: LocalizedStringKey? {
        let v = intradayCurve.map(\.value)
        guard v.count > 1, let lo = v.min(), let hi = v.max() else { return nil }
        let minS = "\(Int(lo.rounded()))", maxS = "\(Int(hi.rounded()))"
        if let rest = restingHR {
            return "Average today · min \(minS) · max \(maxS) bpm · resting \(Int(rest.rounded()))"
        }
        return "Average today · min \(minS) · max \(maxS) bpm"
    }

    /// "Today {v} {u} · within your normal variation" — frames the single reading against the band.
    private func heroContext(_ today: Double) -> LocalizedStringKey {
        let v = fmt(today)
        let u = unit
        if let band = normalRange, band.contains(today) {
            return "Today \(v) \(u) · within your normal variation"
        }
        return "Today \(v) \(u)"
    }

    // MARK: - Period selector

    private func periodSelector(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The selector owns its own full-width row (the night count lives in "Your normal range",
            // so no "N readings" label crowds it). (FER-211)
            SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme) { $0.label }
            if window.fellBack {
                // Only the auto-widen fallback survives, as a quiet caption in warning ink.
                Text("Showing the last \(window.rows.count) days")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.warning)
            }
        }
    }

    // MARK: - Chart (7-day moving average · area + date axes)

    @ViewBuilder private func chartBlock(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Metrics with population ranges (Resting HR / Respiration / Steps) offer a «media móvil ⇄
            // rangos» toggle: your trend + personal band, or the classification ranges showing where you
            // fall. The period picker lives in `periodSelector` above. (Detalle de Vital)
            if hasRangesMode {
                SegmentedPillControl(ChartMode.allCases, selection: $chartMode, theme: theme) { chartModeLabel($0) }
            }
            MetricTrendChart(
                range: $range,
                window: window,
                theme: theme,
                showsSelector: false,
                style: .init(
                    smoothing: chartPlotsRaw ? nil : 7,
                    gradient: chartGradient,
                    // No area fill when a band is drawn: the band + clean line read sharply; the area was
                    // a second teal wash that muddied the overlap. A shorter chart keeps it proportionate
                    // to the period selector above. «Ranges» mode is a touch taller to fit the band labels. (Detalle de Vital)
                    showsArea: effectiveChartBands(window).isEmpty,
                    height: rangesModeActive ? 184 : (isNarrative ? 156 : 200),
                    valueRange: { rangesModeActive ? (rangesValueRange($0) ?? narrativeChartValueRange($0)) : narrativeChartValueRange($0) },
                    valueFormat: { "\(fmt($0)) \(unit)" },
                    // SpO₂ shades its clinical healthy zone; the personal vitals shade your ±SD «normal range»;
                    // «Ranges» mode shades the active classification band, labels shown. (Detalle de Vital)
                    bands: { _ in effectiveChartBands(window) },
                    bandColor: { _ in spec.clinicalBands ? theme.verdict : metricHue },
                    yAxisValues: rangesModeActive ? rangesYTicks(window) : clinicalYAxisValues,
                    // «Media móvil» auto-ticks: ask for more so a wide range (e.g. steps 0–15k) reads at finer
                    // increments instead of just 5k/10k/15k. Ignored when ticks are explicit («Rangos» bands,
                    // SpO₂'s clinical thresholds), and the compact summary/strain cards keep the default 4. (Detalle)
                    yTickCount: 6,
                    alertThreshold: spec.clinicalBands ? spec.lowThreshold : nil,
                    alertColor: theme.critical,
                    // Mark today's point for the personal-band vitals and in «Ranges» mode (shows where today
                    // sits among the classifications); SpO₂ marks its low nights via the alert threshold. (Detalle de Vital)
                    marksLastPoint: (isNarrative && !spec.clinicalBands) || rangesModeActive,
                    // Labels off for the quiet personal/clinical band; ON in «Ranges» mode (athlete / normal / …).
                    bandLabelsHidden: !rangesModeActive,
                    accessibilityLabel: chartAccessibilityLabel
                )
            ) {
                if let only = window.values.first {
                    // A single point in the window: no line. Show the value plainly with a note.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(fmt(only)) \(unit)")
                            .font(StrandFont.bodyNumber)
                            .foregroundStyle(metricHue)
                        Text("Only one reading in this range — not enough to draw a line yet.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(theme.inkTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    emptyWell(text: "No readings in this range.")
                }
            }
            if window.values.count > 1 {
                Text(chartCaption(window.range))
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                dynamicAverageCaption(window)
                if spec.currentDayIncomplete {
                    // The line includes today (still adding up), so its right edge can dip; the figures
                    // below read only completed days — so the two may not line up exactly. (FER-264)
                    Text("The line includes today, still in progress; the figures below use completed days only.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The fixed clinical bands drawn behind the line (FER-244 mechanism), built from the metric's own
    /// `MetricInfo.bands`. The HEALTHY band (the one whose lower bound is the clinical floor) is forced
    /// active so the green floor is ALWAYS shaded — not just when today's value lands in it. Empty for
    /// the non-clinical vitals, so their chart stays band-less. (FER-252)
    private var clinicalChartBands: [TrendBand] {
        guard spec.clinicalBands else { return [] }
        return spec.info.bands.map {
            TrendBand(label: $0.label, lower: $0.lower, upper: $0.upper,
                      isActive: $0.lower == spec.lowThreshold)
        }
    }

    /// The band drawn behind the chart line in the redesigned vitals: SpO₂'s clinical healthy zone, or the
    /// personal ±SD «normal range» for HRV / Resting HR / Respiration. The label is empty (the band is named
    /// in the caption and the inline «Hoy» bar, not on the plot). Empty for non-narrative metrics. (Detalle de Vital)
    private var narrativeChartBands: [TrendBand] {
        if spec.clinicalBands { return clinicalChartBands }
        guard isNarrative, let band = normalRange else { return [] }
        return [TrendBand(label: "", lower: band.lowerBound, upper: band.upperBound, isActive: true)]
    }

    // MARK: - Chart mode: media móvil ⇄ rangos (Resting HR / Respiration / Steps) (Detalle de Vital)

    /// Metrics that carry labeled population ranges the chart can toggle to. HRV has none (personal only);
    /// SpO₂ already shows its clinical band, so it doesn't toggle.
    private var hasRangesMode: Bool {
        !spec.clinicalBands && spec.descriptor.key != "hrv"
            && spec.info.bands.contains { $0.lower != nil || $0.upper != nil }
    }

    private var rangesModeActive: Bool { hasRangesMode && chartMode == .ranges }

    /// The bands drawn on the chart: the labeled classification ranges in «Ranges» mode (active one shaded),
    /// else the personal/clinical band. The active band is the SAME one the ranges table highlights —
    /// today's band (`isActive`), falling back to the latest completed reading — so the shaded band and the
    /// table agree. Without the fallback the chart shaded nothing whenever `isActive` wasn't set (e.g. a
    /// partial step day), even though the table still highlighted a band. (FER-471)
    private func effectiveChartBands(_ window: MetricWindow) -> [TrendBand] {
        guard rangesModeActive else { return narrativeChartBands }
        let banded = spec.info.bands.filter { $0.lower != nil || $0.upper != nil }
        guard !banded.isEmpty else { return [] }
        let tbands = banded.map { TrendBand(label: $0.label, lower: $0.lower, upper: $0.upper) }
        let values = trendStatRows(window).map(\.value)
        let activeIndex = banded.firstIndex(where: { $0.isActive })
            ?? TrendBands.activeBand(values: values, bands: tbands)?.index
        return banded.enumerated().map { i, b in
            TrendBand(label: b.label, lower: b.lower, upper: b.upper, isActive: i == activeIndex)
        }
    }

    /// In «Ranges» mode, span every classification threshold so all bands read, AND include the plotted
    /// line's own min/max — the line can climb past the top band (e.g. steps well over «Muy activo»), and a
    /// band-only range let the peak shoot off the top. The TOP margin is wider than the bottom: the chart's
    /// Y-scale has no top inset, so without headroom the peak hugged the plot's top edge and — with the
    /// «Media móvil ⇄ Rangos» selector just above — read as overlapping it. (Detalle de Vital · FER-471)
    private func rangesValueRange(_ smoothed: [Double]) -> ClosedRange<Double>? {
        let bounds = spec.info.bands.flatMap { [$0.lower, $0.upper].compactMap { $0 } }
        guard let tLo = bounds.min(), let tHi = bounds.max(), tHi > tLo else { return nil }
        let hi = Swift.max(tHi, smoothed.max() ?? tHi)
        let lo = Swift.min(tLo, smoothed.min() ?? tLo)
        let span = hi - lo
        // Modest top headroom: the range already includes the data peak, so a small margin clears the
        // «Media móvil ⇄ Rangos» selector above without leaving a big empty band over the line. (Detalle)
        return (lo - span * 0.1)...(hi + span * 0.15)
    }

    /// «Ranges» Y ticks: the band thresholds, plus round ticks above the top band when the line climbs past
    /// it (e.g. steps over «Muy activo») so the upper chart still has labels. Bounded to the chart's actual
    /// domain top — Charts EXPANDS the y-scale to fit any explicit tick, so a tick above the domain would
    /// stretch the axis into a big empty band over the line. Extend only up to where the line reaches. (Detalle)
    private func rangesYTicks(_ window: MetricWindow) -> [Double]? {
        let thresholds = Set(spec.info.bands.flatMap { [$0.lower, $0.upper].compactMap { $0 } }).sorted()
        guard let maxT = thresholds.last else { return nil }
        let plotted = chartPlotsRaw ? window.values : SeriesShape.movingAverage(window.values, window: 7)
        guard let top = rangesValueRange(plotted)?.upperBound, top > maxT else { return thresholds }
        let step = Swift.max((maxT / 4).rounded(), 1)
        var ticks = thresholds
        var v = maxT + step
        while v < top { ticks.append(v); v += step }
        return ticks
    }

    private func chartModeLabel(_ m: ChartMode) -> String {
        m == .movingAverage ? String(localized: "Moving average") : String(localized: "Ranges")
    }

    /// Y-axis ticks at the band thresholds (e.g. SpO₂ 90/95/100) for the clinical chart; `nil` otherwise
    /// so the vitals keep automatic ticks. (FER-252)
    private var clinicalYAxisValues: [Double]? {
        guard spec.clinicalBands, let domain = spec.chartDomain else { return nil }
        let thresholds = Set(spec.info.bands.flatMap { [$0.lower, $0.upper].compactMap { $0 } })
        return ([domain.lowerBound, domain.upperBound] + thresholds).sorted()
    }

    /// Auto-fit the chart's value axis to the smoothed line, with a small margin so it doesn't clip.
    private func chartRange(_ smoothed: [Double]) -> ClosedRange<Double> {
        let lo = smoothed.min() ?? 0
        let hi = smoothed.max() ?? 1
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.15
        return (lo - pad)...(hi + pad)
    }

    /// The chart's Y domain. SpO₂ keeps its fixed clinical domain. The redesigned personal-band vitals
    /// (HRV / Resting HR / Respiration) OPEN the axis around the «normal range» band — domain = band ±
    /// ~0.85× its width — so the band reads as a central stripe with air above and below, not a full-bleed
    /// box that fills the whole plot. Everything else auto-fits to the line. (Detalle de Vital — fix «caja»)
    private func narrativeChartValueRange(_ smoothed: [Double]) -> ClosedRange<Double> {
        if let domain = spec.chartDomain { return domain }
        if isNarrative, !spec.clinicalBands, let band = normalRange {
            let span = band.upperBound - band.lowerBound
            let pad = Swift.max(span * 0.6, 1)
            let lo = Swift.min(band.lowerBound - pad, smoothed.min() ?? band.lowerBound)
            let hi = Swift.max(band.upperBound + pad, smoothed.max() ?? band.upperBound)
            return lo...hi
        }
        return chartRange(smoothed)
    }

    /// The chart's caption: the 7-day-average note, suffixed with the window ("· last month") for a
    /// bounded range and left bare for ALL. The window name is already localized, so it's interpolated
    /// as a `String` (a `%@` placeholder), not re-localized as a key. (FER-211)
    /// Whether the chart plots RAW measured points (clinical SpO₂ band, or sparse VO₂max readings) rather
    /// than the 7-day moving average the noisy nightly vitals smooth. (FER-252 / FER-257)
    private var plotsRawValues: Bool { spec.clinicalBands || spec.sparseMeasured }

    /// Whether THIS render plots raw daily points instead of the 7-day MA. Adds «Ranges» mode to
    /// `plotsRawValues`: that mode classifies each DAY against the population bands (the shaded band +
    /// the «X of N days in …» count both read the raw value), so the line must be raw too — otherwise the
    /// smoothed endpoint lands in a different band than the one highlighted from today's reading. Steps are
    /// excluded (`currentDayIncomplete`): their «today» is a running partial total and their raw range can
    /// overflow the band-pinned Y axis, so they keep the smoothed line. (Detalle de Vital — punto vs. rango)
    private var chartPlotsRaw: Bool {
        plotsRawValues || (rangesModeActive && !spec.currentDayIncomplete)
    }

    private var chartAccessibilityLabel: LocalizedStringKey {
        if spec.sparseMeasured { return "Measured readings" }
        if chartPlotsRaw && !spec.clinicalBands { return "Daily readings" }
        return spec.clinicalBands ? "Nightly readings" : "7-day moving average"
    }

    /// The caption under the chart. It no longer appends "· last {range}" — the period selector right above
    /// already says the range, and the interpolated form mis-agreed in Spanish ("últimos mes"). The smoothing
    /// is ALWAYS a 7-day moving average regardless of the selected range, so the caption says so plainly.
    private func chartCaption(_ effectiveRange: ExploreRange) -> LocalizedStringKey {
        if rangesModeActive { return "Where you fall against the typical ranges." }
        if spec.sparseMeasured { return "Measured values." }
        if spec.clinicalBands { return "Nightly values · the shaded band is the healthy range." }
        // Name the shaded band so the horizontal lines on the chart read as «your normal range». (Detalle de Vital)
        if isNarrative, normalRange != nil { return "7-day moving average · the band is your normal range." }
        return "7-day moving average."
    }

    /// «Average · {window} · {value} · {Δ%} vs previous» — the period average recomputed for the SELECTED
    /// window, with its change vs the immediately-preceding equal window coloured by the metric's good
    /// direction (HRV↑, resting HR↓, respiration↓, SpO₂↑, steps↑). Reuses the SAME `ComparisonEngine`
    /// figures + polarity as the trend block, so the caption and the stat strip never disagree. Hidden in
    /// «Ranges» mode and for sparsely-measured metrics (VO₂max); when there's no previous window of equal
    /// length (e.g. ALL, or too little history) it shows the average alone, never an invented Δ. (FER-563)
    @ViewBuilder private func dynamicAverageCaption(_ window: MetricWindow) -> some View {
        let rows = trendStatRows(window)
        if !rangesModeActive, !spec.sparseMeasured, rows.count > 1 {
            let mean = ComparisonEngine.stat(rows.map(\.value)).mean
            let valueStr = unit.isEmpty ? fmt(mean) : "\(fmt(mean)) \(unit)"
            let head = Text("Average") + Text(verbatim: " · \(window.range.name) · \(valueStr)")
            Group {
                if let pct = window.range.periodComparison(of: trendComparisonSeries)?.pctChange {
                    let rounded = Int(abs(pct).rounded())
                    let arrow = rounded == 0 ? "" : (pct >= 0 ? "▲ " : "▼ ")
                    head
                        + Text(verbatim: " · \(arrow)\(rounded)% ").foregroundColor(trendDeltaColor(pct))
                        + Text("vs previous")
                } else {
                    head
                }
            }
            .font(StrandFont.footnote)
            .foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Normal range (rolling mean ± SD)

    @ViewBuilder private var normalRangeBlock: some View {
        if let baseline = baselineState, baseline.nValid >= 1 {
            // log-aware ±1σ band (multiplicative in ms for HRV; plain ± for linear metrics).
            let band = Baselines.normalRange(baseline)
            let lo = band.lowerBound
            let hi = band.upperBound
            // The ⓘ discloses the rolling-baseline math (FER-220); the block's overline + datum +
            // plain-language reading (FER-216) stay exactly as before, inside the accordion's content.
            InfoAccordion(
                title: "Your normal range",
                explanation: "Your personal baseline: a moving average of your recent nights (weighted toward the latest) ± a band of your own variation. A value outside the band is unusual for you, not for the population. It becomes reliable after about 14 nights. (Buchheit 2014)",
                accessibilityLabel: "Information about your normal range",
                theme: theme
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(fmt(lo))–\(fmt(hi)) \(unit) · \(baseline.nValid) nights")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(theme.ink)
                    if let reading = readingCopy(for: .normalRange) {
                        Text(reading)
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The personal rolling baseline (trailing mean/SD), or nil when no config / no valid nights.
    private var baselineState: BaselineState? {
        guard let cfg = spec.baselineCfg else { return nil }
        let state = Baselines.rollingMeanSD(allValues.map { Optional($0) }, cfg: cfg, window: 30)
        return state.nValid >= 1 ? state : nil
    }

    /// The ±1σ "normal range" used to frame today's reading (nil when no baseline yet).
    /// log-aware (multiplicative band in ms for HRV) via `Baselines.normalRange`.
    private var normalRange: ClosedRange<Double>? {
        guard let s = baselineState else { return nil }
        return Baselines.normalRange(s)
    }

    // MARK: - Consistency (coefficient of variation)

    @ViewBuilder private var consistencyBlock: some View {
        if let cv = SeriesShape.coefficientOfVariation(allValues, window: 7) {
            let pct = Int((cv * 100).rounded())
            // The ⓘ discloses the coefficient-of-variation math (FER-220); the block now leads with the
            // word (Steady/Variable) as the protagonist and demotes the ±% below it (FER-255).
            InfoAccordion(
                title: "Consistency",
                explanation: "Coefficient of variation = standard deviation ÷ the mean of your last few weeks. It measures how spread out your values are around your average. Low = steady. In HRV, a rising CV can precede fatigue even while the value still looks high. (Plews 2013)",
                accessibilityLabel: "Information about consistency",
                theme: theme
            ) {
                ConsistencySummary(cvPercent: pct, reading: readingCopy(for: .consistency), theme: theme)
            }
        }
    }

    // MARK: - Band table helpers (population range rows) — SpO₂ / VO₂max (FER-252 / FER-257)

    /// A hairline between rows of a band table, inset past the indicator dot. Shared by the SpO₂ fixed
    /// bands and the VO₂max category table. (FER-252 / FER-257)
    private var bandTableDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1).padding(.leading, 36)
    }

    /// One row of a population-band table: an indicator dot (active → metric hue), the band label, its
    /// range, and a `badge` ("· today" for SpO₂, "· you" for the VO₂max level) on the active row. (FER-252)
    private func bandRow(_ band: MetricInfo.Band, badge: LocalizedStringKey = "· today") -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(band.isActive ? metricHue : theme.inkTertiary.opacity(0.45))
                .frame(width: 8, height: 8)
                .padding(.leading, 14)
            Text(band.label)
                .font(StrandFont.subhead)
                .foregroundStyle(band.isActive ? theme.ink : theme.inkSecondary)
            Spacer()
            Text(band.range)
                .font(StrandFont.captionNumber)
                .foregroundStyle(band.isActive ? metricHue : theme.inkTertiary)
            if band.isActive {
                Text(badge)
                    .font(StrandFont.footnote)
                    .foregroundStyle(metricHue)
                    .padding(.trailing, 14)
            } else {
                Spacer().frame(width: 14)
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(band.isActive ? metricHue.opacity(0.12) : Color.clear)
    }

    // MARK: - Nights below the clinical floor — SpO₂ (FER-252)

    /// How many of the recent nights fell under the clinical floor (SpO₂ < 95%). Replaces the
    /// consistency block for clinically-anchored metrics, where the CV is near-zero and a low-night
    /// count is the figure that actually reads.
    @ViewBuilder private var lowNightsBlock: some View {
        if let threshold = spec.lowThreshold {
            let recent = MetricWindowMath.slice(parsedSeries, for: .month)
            let low = recent.reduce(0) { $0 + ($1.value < threshold ? 1 : 0) }
            DetailBlock("Nights below \(fmt(threshold))\(unit)", theme: theme) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(low)")
                            .instrumentoHero(34)
                            .foregroundStyle(low == 0 ? theme.verdict : theme.ink)
                        Text("of the last \(recent.count) nights")
                            .font(StrandFont.subhead)
                            .foregroundStyle(theme.inkSecondary)
                    }
                    Text(lowNightsReading(low: low))
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func lowNightsReading(low: Int) -> LocalizedStringKey {
        low == 0
            ? "Every recent night sat in the healthy range."
            : "Isolated low nights are usually noise (altitude, a cold, sensor fit). A sustained run is worth a look with a finger pulse oximeter."
    }

    // MARK: - Intraday HR curve (FER-253)

    /// Today's continuous HR curve — the protagonist block for Heart Rate. Reuses the same render the
    /// summary sheet used (BPM chart + min/avg/max), now with the day's peak marked and the night's
    /// resting HR as a quiet dashed reference line. Empty curve → an honest "no readings yet" well.
    @ViewBuilder private var intradayBlock: some View {
        if intradayCurve.count > 1 {
            let v = intradayCurve.map(\.value)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Beats per minute").font(StrandFont.headline).foregroundStyle(theme.ink)
                        Text("5-minute average · since midnight")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                    Spacer()
                    if let last = v.last {
                        Text("\(Int(last.rounded())) bpm")
                            .font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
                    }
                }
                TrendChart(
                    points: intradayCurve,
                    gradient: chartGradient,
                    valueRange: Self.hrRange(v, resting: restingHR),
                    showsArea: true,
                    height: 240,
                    showsScrub: true,
                    valueFormat: { "\(Int($0.rounded())) \(unit)" },
                    dateFormat: { Self.hrClock.string(from: $0) },
                    axisLabelColor: theme.inkTertiary,
                    gridLineColor: theme.hairline,
                    referenceLine: restingHR,
                    referenceLineColor: theme.inkTertiary.opacity(0.7),
                    markedPoint: peakPoint,
                    tightTrailing: true
                )
                .accessibilityElement()
                .accessibilityLabel(Text("Today's heart rate, 5-minute averages"))
                peakRestingCaption
                intradayFooter(v)
            }
        } else {
            emptyWell(text: "No readings yet today.")
        }
    }

    /// The peak of the day (max bpm), marked on the curve.
    private var peakPoint: TrendPoint? { intradayCurve.max { $0.value < $1.value } }

    /// "Peak {v} bpm · {time}" plus the resting reference, in the chart's two legend hues. Built once.
    @ViewBuilder private var peakRestingCaption: some View {
        if let peak = peakPoint {
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Circle().fill(metricHue).frame(width: 7, height: 7)
                    Text("Peak \(Int(peak.value.rounded())) bpm · \(Self.hrClock.string(from: peak.date))")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                }
                if let rest = restingHR {
                    Text("Resting \(Int(rest.rounded()))")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
            }
        }
    }

    private func intradayFooter(_ v: [Double]) -> some View {
        let lo = Int((v.min() ?? 0).rounded())
        let avg = Int((v.reduce(0, +) / Double(max(v.count, 1))).rounded())
        let hi = Int((v.max() ?? 0).rounded())
        return HStack {
            intradayStat("Min", "\(lo)")
            Spacer()
            intradayStat("Avg", "\(avg)")
            Spacer()
            intradayStat("Max", "\(hi)")
        }
    }

    private func intradayStat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).textCase(.uppercase)
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Text(value).font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
        }
    }

    /// Padded HR axis so the line never sits flush against an edge; widens to include the resting
    /// reference if it falls below the curve's floor. (mirrors MetricInfoSheet.hrRange)
    private static func hrRange(_ v: [Double], resting: Double?) -> ClosedRange<Double> {
        var lo = v.min() ?? 40, hi = v.max() ?? 120
        if let r = resting { lo = Swift.min(lo, r) }
        if hi <= lo { return (lo - 5)...(hi + 5) }
        let span = hi - lo
        return (lo - span * 0.12)...(hi + span * 0.12)
    }

    private static let hrClock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h a"; return f
    }()

    // MARK: - Time in zones · today (FER-253)

    /// The five %HRmax zones (Tanaka), or nil when no max HR is configured.
    private var zoneSet: HRZoneSet? {
        guard hrMax > 0 else { return nil }
        return HRZones.zones(maxHR: hrMax, source: "tanaka")
    }

    /// The dominant bucket spacing in minutes — derived from the curve so the "minutes in zone" math
    /// doesn't hard-code the 5-minute bucket size. Gaps (no wear) aren't counted: each reading is
    /// credited one bucket, never the gap to the next. (FER-253)
    private var bucketMinutes: Double {
        let ts = intradayCurve.map { $0.date.timeIntervalSince1970 }.sorted()
        guard ts.count >= 2 else { return 5 }
        var gaps: [Double] = []
        for i in 1..<ts.count { let g = ts[i] - ts[i - 1]; if g > 0 { gaps.append(g) } }
        guard !gaps.isEmpty else { return 5 }
        gaps.sort()
        return Swift.max(gaps[gaps.count / 2] / 60.0, 0.5)
    }

    /// Minutes in [rest, Z1, Z2, Z3, Z4, Z5] from today's curve (index 0 = below Zone 1). nil when
    /// there's no max HR or too little curve to bucket. Computed ONCE when the curve loads (it sorts +
    /// buckets the whole curve), then cached — the same discipline the daily path uses for
    /// `parsedSeries`. (FER-253 / FER-216 pattern)
    private func computeZoneMinutes() -> [Double]? {
        guard let zs = zoneSet, intradayCurve.count > 1 else { return nil }
        let per = bucketMinutes
        var mins = [Double](repeating: 0, count: 6)
        for p in intradayCurve { mins[zs.zoneNumber(forBPM: p.value)] += per }
        return mins
    }

    private func hrZonesBlock(_ mins: [Double]) -> some View {
        let elevated = Int((mins[3] + mins[4] + mins[5]).rounded())
        let total = Swift.max(mins.reduce(0, +), 1)
        return DetailBlock("Time in zones · today", theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(elevated)").instrumentoHero(30).foregroundStyle(metricHue)
                    Text("min elevated (zone 3+)")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { i in
                            Rectangle()
                                .fill(zoneFill(i))
                                .frame(width: geo.size.width * CGFloat(mins[i] / total))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                VStack(alignment: .leading, spacing: 7) {
                    ForEach((1...5).filter { mins[$0] >= 1 }, id: \.self) { i in
                        HStack(spacing: 8) {
                            Circle().fill(zoneFill(i)).frame(width: 8, height: 8)
                            Text(zoneLabel(i)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            Spacer()
                            Text("\(Int(mins[i].rounded())) min")
                                .font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
                        }
                    }
                }
                Text("Zones as a percentage of your max heart rate (\(Int(hrMax.rounded())) bpm, Tanaka). The rest of the day you were resting or very light.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Rest (below Zone 1) reads in quiet ink; the five training zones grade up the metric hue so a
    /// harder zone reads darker. The bar segments ARE the datum, so hue is allowed here. (FER-253)
    private func zoneFill(_ i: Int) -> Color {
        switch i {
        case 0:  return theme.hairlineStrong
        case 1:  return metricHue.opacity(0.35)
        case 2:  return metricHue.opacity(0.5)
        case 3:  return metricHue.opacity(0.65)
        case 4:  return metricHue.opacity(0.82)
        default: return metricHue
        }
    }

    private func zoneLabel(_ n: Int) -> LocalizedStringKey {
        switch n {
        case 1:  return "Zone 1 · very light"
        case 2:  return "Zone 2 · light"
        case 3:  return "Zone 3 · moderate"
        case 4:  return "Zone 4 · hard"
        default: return "Zone 5 · max"
        }
    }

    // MARK: - Trend (month over month)

    @ViewBuilder private func trendBlock(_ window: MetricWindow) -> some View {
        // Figures read over COMPLETED days: for a running daily total (steps) drop the in-progress
        // current day, else it's always the floor of the range and drags the average. (FER-264)
        let s = ComparisonEngine.stat(trendStatRows(window).map(\.value))
        // Compare the selected window against the equally-long window before it (not always the calendar
        // month), over completed days. `.all` has no previous period, so no chip. (FER-264)
        let comparison = window.range.periodComparison(of: trendComparisonSeries)
        if s.n > 0 {
            // The ⓘ discloses how the slope, the period comparison and the stats are computed (FER-220).
            InfoAccordion(
                title: "Trend",
                explanation: "The slope is how much it rises or falls on average per day, by linear regression over the period. The percentage compares this period's average against the previous period of the same length. Average, Lowest and Highest are from the range you selected.",
                accessibilityLabel: "Information about the trend",
                theme: theme
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    TrendStatSummary(
                        average: fmt(s.mean),
                        unit: unit.isEmpty ? nil : unit,
                        pctChange: comparison?.pctChange,
                        polarity: trendPolarity,
                        period: window.range.comparisonPeriod ?? .month,
                        rangeLow: fmt(s.min),
                        rangeHigh: unit.isEmpty ? fmt(s.max) : "\(fmt(s.max)) \(unit)",
                        theme: theme
                    )
                    if let reading = readingCopy(for: .trend) {
                        Text(reading)
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// True when the latest series point is TODAY and this metric's day is still accumulating (steps) —
    /// then the trend figures exclude it so they read over completed days only. (FER-264)
    private var dropsIncompleteToday: Bool {
        spec.currentDayIncomplete && todayKey != nil && series.last?.day == todayKey
    }

    /// The window's rows used for the range/average, with the in-progress current day removed for a
    /// cumulative metric. (FER-264)
    private func trendStatRows(_ window: MetricWindow) -> [(day: String, value: Double)] {
        dropsIncompleteToday ? window.rows.filter { $0.day != todayKey } : window.rows
    }

    /// The full series the period comparison splits, with the in-progress current day removed for a
    /// cumulative metric (so "this period" and "the previous period" are both completed-day means). (FER-264)
    private var trendComparisonSeries: [(day: String, value: Double)] {
        dropsIncompleteToday ? series.filter { $0.day != todayKey } : series
    }

    /// Whether a rise is good for this metric, from the catalog's `higherIsBetter` — drives the trend
    /// chip's colour in `TrendStatSummary`. HRV rises = good, resting HR rises = bad, respiration neutral.
    private var trendPolarity: TrendStatSummary.Polarity {
        switch spec.descriptor.higherIsBetter {
        case .some(true):  return .higherIsBetter
        case .some(false): return .lowerIsBetter
        case .none:        return .neutral
        }
    }

    // MARK: - Night vitals

    @ViewBuilder private var nightVitalsBlock: some View {
        if nightVitals.respiration != nil || nightVitals.restingHR != nil {
            DetailBlock("Last night's vitals", theme: theme) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(nightVitalsLine)
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(theme.ink)
                    if let reading = readingCopy(for: .nightVitals) {
                        Text(reading)
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var nightVitalsLine: LocalizedStringKey {
        let resp = nightVitals.respiration.map { String(format: "%.1f", $0) } ?? "—"
        let rhr = nightVitals.restingHR.map { "\(Int($0.rounded()))" } ?? "—"
        return "Respiration \(resp) · Resting HR \(rhr)"
    }

    // MARK: - What moves it (FER-209)

    /// A documented, DIRECTIONAL tendency between this vital and another signal (same-night sleep,
    /// the prior day's strain), computed from the user's OWN history and degraded to a direction —
    /// never a coefficient, never a causal claim (hence the "tendencia, no causa" chip). Rendered only
    /// when at least one relationship clears the sufficiency gate (see `WhatMovesItEngine` /
    /// `CorrelationEngine.trend`); otherwise the whole block is absent.
    private var whatMovesItBlock: some View {
        // The ⓘ discloses the correlation method + the sufficiency gate (FER-220 pattern); the chip and
        // the directional sentences stay inside the accordion's content.
        InfoAccordion(
            title: "What moves it",
            explanation: "We line up this vital against your own sleep and the prior day's strain, night by night across your history, and read which way it leans (Pearson correlation). We only show a direction once there are enough paired nights (about six weeks) and the link is strong enough to be unlikely to be chance — never the number, and never as a cause. (Plews 2013)",
            accessibilityLabel: "Information about what moves it",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if whatMovesItFindings.isEmpty {
                    // No relationship cleared the gate yet (too few paired nights, or none strong enough).
                    // Honest empty state instead of vanishing — neutral wording true in both cases (FER-246).
                    Text("Not enough data yet — keep wearing your strap and check back in a few weeks.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    InlineFlagChip("trend, not cause", color: theme.inkTertiary)
                    ForEach(whatMovesItFindings) { finding in
                        Text(Self.whatMovesItPhrase(finding))
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The directional sentence for a finding. Shared by HRV and resting HR — both "la variabilidad"
    /// and "la frecuencia" are feminine, so the same es-MX wording agrees in gender. The direction
    /// comes from the user's data; no number is ever shown.
    private static func whatMovesItPhrase(_ f: WhatMovesItFinding) -> LocalizedStringKey {
        switch (f.relationship, f.trend) {
        case (.sleepDuration, .rises): return "Tends to run higher on nights you sleep more."
        case (.sleepDuration, .falls): return "Tends to run lower on nights you sleep more."
        case (.priorStrain, .rises):   return "Tends to rise the day after a hard effort."
        case (.priorStrain, .falls):   return "Tends to dip the day after a hard effort."
        }
    }

    // MARK: - Method disclosure (ported from MetricInfoSheet)

    @State private var methodExpanded = false

    private func methodDisclosure(_ method: MetricInfo.Method) -> some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                Text(method.prose)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let citation = method.citation {
                    Text(citation)
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("How it's calculated")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
        }
        .tint(theme.inkTertiary)
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - VO₂max (Apple Health, measured · FER-257)

    /// The population median VO₂max for the user's age & sex (the reference the hero reads against).
    private var vo2maxExpected: Double? {
        spec.vo2maxProfile.map { VO2maxReference.expected(age: $0.age, sex: $0.sex) }
    }

    /// Where the latest measured value sits versus the age/sex median — the hero's headline reading. A
    /// small ±1.5 deadband keeps a value right at the median reading "in line", not flip-flopping.
    private var vo2maxComparison: LocalizedStringKey {
        guard let v = heroValue, let exp = vo2maxExpected else { return " " }
        if v > exp + 1.5 { return "Above what's expected for your age." }
        if v < exp - 1.5 { return "Below what's expected for your age." }
        return "In line with what's expected for your age."
    }

    /// "Expected for your age: ~N" — the median value, so the headline comparison is legible.
    private var vo2maxExpectedLine: LocalizedStringKey? {
        guard let exp = vo2maxExpected else { return nil }
        return "Expected for your age: ~\(Int(exp.rounded()))"
    }

    /// "Measured today / yesterday / N days ago" — three legible cases so the count never reads "1 days".
    /// Apple measures VO₂max sparsely, so freshness is worth surfacing. `nil` when there's no parseable reading.
    private var vo2maxMeasuredAgoLine: LocalizedStringKey? {
        guard let day = series.last?.day, let date = Repository.parseDayKey(day) else { return nil }
        let cal = Calendar.current
        guard let d = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day,
              d >= 0 else { return nil }
        switch d {
        case 0:  return "Measured today"
        case 1:  return "Measured yesterday"
        default: return "Measured \(d) days ago"
        }
    }

    /// The age/sex-anchored extras the user asked for, between the chart and the method (FER-257): how it
    /// changed over the period (≥2 readings), the fitness category, the cardiorespiratory-equivalent age,
    /// and why VO₂max matters. Each emits its own leading divider only when it renders.
    @ViewBuilder private func vo2maxExtras(_ window: MetricWindow) -> some View {
        if window.values.count >= 2 {
            blockDivider
            vo2maxChangeBlock(window)
        }
        if let v = heroValue, let profile = spec.vo2maxProfile {
            blockDivider
            vo2maxCategoryBlock(value: v, profile: profile)
            blockDivider
            vo2maxEquivalentAgeBlock(value: v, profile: profile)
        }
        blockDivider
        vo2maxWhyBlock
    }

    /// How much VO₂max moved across the selected window (last − first measured value). Framed as a long-run
    /// change ("up since your first reading"), NOT a noisy month-over-month %, because the data is sparse.
    @ViewBuilder private func vo2maxChangeBlock(_ window: MetricWindow) -> some View {
        if let first = window.values.first, let last = window.values.last {
            let delta = Int((last - first).rounded())
            let color = delta > 0 ? theme.dataRecovery : (delta < 0 ? theme.warning : theme.ink)
            DetailBlock("Change", theme: theme) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(delta > 0 ? "+\(delta)" : "\(delta)")
                            .instrumentoHero(30)
                            .foregroundStyle(color)
                        Text(unit).font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    }
                    Text(vo2maxChangeReading(delta))
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func vo2maxChangeReading(_ delta: Int) -> LocalizedStringKey {
        if delta > 0 { return "Up since your first reading in this range. VO₂max responds to training." }
        if delta < 0 { return "Down since your first reading in this range." }
        return "About the same across this range."
    }

    /// Where the latest value lands among healthy peers of the same age & sex — a four-band table
    /// (Low / Average / Good / Excellent) with the active band marked, built from `VO2maxReference`.
    /// Reuses the shared `bandRow` / `bandTableDivider` (the SpO₂ table) with a "· you" badge. (FER-257)
    private func vo2maxCategoryBlock(value v: Double, profile: VO2maxProfile) -> some View {
        let t = VO2maxReference.categoryThresholds(age: profile.age, sex: profile.sex)
        let active = VO2maxReference.category(value: v, age: profile.age, sex: profile.sex)
        let lo = Int(t.low.rounded()), gd = Int(t.good.rounded()), ex = Int(t.excellent.rounded())
        let bands: [MetricInfo.Band] = [
            MetricInfo.Band(label: "Low", range: "< \(lo)", isActive: active == .low),
            MetricInfo.Band(label: "Average", range: "\(lo) – \(gd)", isActive: active == .average),
            MetricInfo.Band(label: "Good", range: "\(gd) – \(ex)", isActive: active == .good),
            MetricInfo.Band(label: "Excellent", range: "> \(ex)", isActive: active == .excellent),
        ]
        return DetailBlock("Your level for your age", theme: theme) {
            VStack(spacing: 0) {
                ForEach(Array(bands.enumerated()), id: \.offset) { i, band in
                    bandRow(band, badge: "· you")
                    if i < bands.count - 1 { bandTableDivider }
                }
            }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// The age whose median VO₂max matches the latest measured value — an intuitive "cardiorespiratory
    /// age". Different basis from the Nes «Edad física», so the copy says so to avoid confusion.
    private func vo2maxEquivalentAgeBlock(value v: Double, profile: VO2maxProfile) -> some View {
        let eq = VO2maxReference.equivalentAge(value: v, sex: profile.sex)
        return DetailBlock("Cardiorespiratory age", theme: theme) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(eq)").instrumentoHero(30).foregroundStyle(metricHue)
                    Text("years").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                }
                Text("Your VO₂max matches the median for someone aged \(eq). It's a different basis from your Physical age.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Why the number is worth caring about — VO₂max's all-cause-mortality association, with citations.
    private var vo2maxWhyBlock: some View {
        DetailBlock("Why it matters", theme: theme) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A higher VO₂max is associated with a lower risk of all-cause mortality. It's one of the best-evidenced predictors of long-term health.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Mandsager 2018 (JAMA) · Kodama 2009")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
    }

    /// Zero-reading state for VO₂max: an explanatory card (no chart), plus a quiet "Connect Apple Health"
    /// line when nothing's connected. (FER-257)
    private var sparseEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No VO₂max yet")
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
            Text("Your Apple Watch estimates VO₂max during outdoor walks and runs with a good GPS signal — it isn't recorded by the WHOOP strap.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if appleConnectHint {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(theme.dataHeart)
                    Text("Connect Apple Health to see your VO₂max.")
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Calibration (not enough history)

    private var calibrationBlock: some View {
        let nights = series.count
        // Steps are an Apple-sourced daily count, not a calibrated night vital: its empty state speaks in
        // "days" and omits the "normal range" the vitals promise (steps carries none). (FER-254)
        let isSteps = spec.descriptor.key == "steps"
        return VStack(alignment: .leading, spacing: 12) {
            Text("Not enough history yet")
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
            HStack(alignment: .firstTextBaseline) {
                Text(isSteps ? "Gathering" : "Calibrating").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text(isSteps ? "\(nights) / 7 days" : "\(nights) / 7 nights")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline).frame(height: 6)
                    Capsule().fill(metricHue)
                        .frame(width: max(6, geo.size.width * CGFloat(min(nights, 7)) / 7), height: 6)
                }
            }
            .frame(height: 6)
            Text(isSteps
                 ? "Connect Apple Salud and walk a few days to see your daily average and your trend."
                 : "We need a few more nights to show your 7-day average, your normal range and the trend.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Detalle de Vital · narrative redesign (Hoy → Tu historia → (Tu patrón) → Método)
    //
    // The five vitals lead with TODAY's reading, draw the personal/clinical range inline AND behind the
    // chart line, and fold the old per-block ⓘ accordions into a tappable stat strip + per-datum disclosures
    // that reuse the SAME `explanation` copy. Steps / VO₂max keep `legacyHero` / `legacyContent`.

    private func toggle(_ key: String) { openDisclosure = (openDisclosure == key) ? nil : key }

    // MARK: Hoy (hero)

    private var narrativeHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Serif in-screen title (the «Instrumento» detail identity, FER-581). No ⓘ: the dueño chose to
            // keep the plain-language reading always visible below the hero, so a disclosure is redundant.
            InstrumentoScreenTitle(narrativeHeroTitle, theme: theme)
            if isIntraday {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(heroTodayValue.map { fmt($0) } ?? "—")
                        .instrumentoHero(44)
                        .foregroundStyle(heroTodayValue == nil ? theme.inkTertiary : theme.ink)
                    if heroTodayValue != nil {
                        Text("bpm average").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    }
                }
                if loaded, let ctx = intradayHeroContextLine {
                    Text(ctx).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
            }
            // Plain-language reading, kept always visible below the hero (FER-216 readability + the dueño's
            // choice in FER-581). The serif title carries the identity; this stays put.
            if let reading = readingCopy(for: .header) {
                Text(reading)
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The serif in-screen title — the metric's SHORT name (matching the Cuerpo tile labels), not the
    /// "{metric} · today" overline it replaces. (FER-581)
    private var narrativeHeroTitle: LocalizedStringKey {
        switch spec.descriptor.key {
        case "hrv":        return "HRV"
        case "rhr":        return "Resting HR"
        case "resp_rate":  return "Respiratory"
        case "spo2":       return "Blood Oxygen"
        case "heart_rate": return "Heart Rate"
        default:           return "Today"
        }
    }

    /// The hero numeral: today's reading for the vitals, today's average bpm for Heart Rate.
    private var heroTodayValue: Double? { isIntraday ? intradayAverage : todayValue }

    /// "min 51 · max 142 · resting 52 bpm" under the Heart Rate hero (the day's spread). nil < 2 readings.
    private var intradayHeroContextLine: LocalizedStringKey? {
        let v = intradayCurve.map(\.value)
        guard v.count > 1, let lo = v.min(), let hi = v.max() else { return nil }
        let minS = "\(Int(lo.rounded()))", maxS = "\(Int(hi.rounded()))"
        if let rest = restingHR {
            let restS = "\(Int(rest.rounded()))"
            return "min \(minS) · max \(maxS) · resting \(restS) bpm"
        }
        return "min \(minS) · max \(maxS) bpm"
    }

    // MARK: Narrative body

    @ViewBuilder private func narrativeContent(_ window: MetricWindow) -> some View {
        if isIntraday {
            narrativeIntraday(window)
        } else {
            if hasPatron {
                blockDivider
                patronSection
            }
            if visibleBlocks.contains(.method), let method = spec.info.method {
                blockDivider
                methodDisclosure(method)
            }
        }
    }

    /// Whether the «Tu patrón» section has anything to show (HRV / Resting HR have «what moves it»; HRV /
    /// Respiration have last night's companion signals). SpO₂ and Heart Rate have no pattern section.
    private var hasPatron: Bool {
        let qm = visibleBlocks.contains(.whatMovesIt) && !series.isEmpty
        let nv = visibleBlocks.contains(.nightVitals)
            && (nightVitals.respiration != nil || nightVitals.restingHR != nil)
        return qm || nv
    }

    /// Colour for a period-over-period % change, by this metric's polarity: the good direction → verdict,
    /// against → warning, flat (rounds to 0%) or a neutral metric → quiet ink. Shared by the trend stat
    /// cell and the dynamic-average caption so the two never disagree. (FER-563)
    private func trendDeltaColor(_ pct: Double) -> Color {
        if Int(abs(pct).rounded()) == 0 { return theme.inkSecondary }
        switch trendPolarity {
        case .higherIsBetter: return pct > 0 ? theme.verdict : theme.warning
        case .lowerIsBetter:  return pct < 0 ? theme.verdict : theme.warning
        case .neutral:        return theme.inkSecondary
        }
    }

    // MARK: Disclosure panels (reuse the same explanation copy the old ⓘ accordions showed)

    @ViewBuilder private func disclosurePanel<C: View>(@ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(theme.hairlineStrong).frame(width: 2)
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        // Fade in place (no slide): with the gentle spring this lets the content below settle smoothly
        // instead of the panel flying in from the top and shoving everything down. (Detalle de Vital fix)
        .transition(.opacity)
    }

    private func inlineDisclosure(label: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        disclosurePanel {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(text).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Tu patrón (what moves it + last night's companion signals)

    private var patronSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your pattern").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if visibleBlocks.contains(.whatMovesIt), !series.isEmpty { quemueveView }
            if visibleBlocks.contains(.nightVitals),
               nightVitals.respiration != nil || nightVitals.restingHR != nil {
                nightSignalsView
            }
        }
    }

    private var quemueveView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.25)) { toggle("quemueve") } } label: {
                HStack(spacing: 7) {
                    Text("What moves it").font(StrandFont.subhead).fontWeight(.semibold).foregroundStyle(theme.ink)
                    InlineFlagChip("trend, not cause", color: theme.inkTertiary)
                    Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if openDisclosure == "quemueve" {
                inlineDisclosure(label: "What moves it", text: EX_QUEMUEVE)
            }
            if whatMovesItFindings.isEmpty {
                Text("Not enough data yet — keep wearing your strap and check back in a few weeks.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(whatMovesItFindings) { f in
                    HStack(alignment: .top, spacing: 8) {
                        Text(Self.whatMovesArrow(f)).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(whatMovesColor(f))
                        Text(Self.whatMovesItPhrase(f)).font(StrandFont.caption)
                            .foregroundStyle(theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private static func whatMovesArrow(_ f: WhatMovesItFinding) -> String { f.trend == .rises ? "↑" : "↓" }
    private func whatMovesColor(_ f: WhatMovesItFinding) -> Color {
        f.relationship == .sleepDuration ? theme.verdict : theme.dataStrain
    }

    private var nightSignalsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Other signals from last night").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Spacer(minLength: 8)
                Text(narrativeNightLine).font(StrandFont.captionNumber).foregroundStyle(theme.ink)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            if let reading = readingCopy(for: .nightVitals) {
                Text(reading).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// «Otras señales de anoche»: respiration is dropped for the Respiratory-rate detail (it's the hero), so
    /// only the companion Resting HR shows; the other vitals show both. (Detalle de Vital)
    private var narrativeNightLine: LocalizedStringKey {
        if spec.descriptor.key == "resp_rate" {
            let rhr = nightVitals.restingHR.map { "\(Int($0.rounded()))" } ?? "—"
            return "Resting HR \(rhr)"
        }
        return nightVitalsLine
    }

    // MARK: Tu día (Heart Rate intraday)

    @ViewBuilder private func narrativeIntraday(_ window: MetricWindow) -> some View {
        blockDivider
        VStack(alignment: .leading, spacing: 12) {
            Text("Your day").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if intradayCurve.count > 1 {
                let v = intradayCurve.map(\.value)
                TrendChart(
                    points: intradayCurve,
                    gradient: chartGradient,
                    valueRange: Self.hrRange(v, resting: restingHR),
                    showsArea: true,
                    height: 240,
                    showsScrub: true,
                    valueFormat: { "\(Int($0.rounded())) \(unit)" },
                    dateFormat: { Self.hrClock.string(from: $0) },
                    axisLabelColor: theme.inkTertiary,
                    gridLineColor: theme.hairline,
                    referenceLine: restingHR,
                    referenceLineColor: theme.inkTertiary.opacity(0.7),
                    markedPoint: peakPoint,
                    tightTrailing: true
                )
                .accessibilityElement()
                .accessibilityLabel(Text("Today's heart rate, 5-minute averages"))
                peakRestingCaption
                HStack(spacing: 9) {
                    hrStatCell("Min", "\(Int((v.min() ?? 0).rounded()))")
                    hrStatCell("Average", "\(Int((v.reduce(0, +) / Double(max(v.count, 1))).rounded()))")
                    hrStatCell("Max", "\(Int((v.max() ?? 0).rounded()))")
                }
            } else {
                emptyWell(text: "No readings yet today.")
            }
        }
        if let mins = cachedZoneMinutes, mins[1...].contains(where: { $0 > 0 }) {
            blockDivider
            hrZonesBlock(mins)
        }
        if visibleBlocks.contains(.method), let method = spec.info.method {
            blockDivider
            methodDisclosure(method)
        }
    }

    private func hrStatCell(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).textCase(.uppercase).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Text(value).font(StrandFont.number(14)).foregroundStyle(theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: Disclosure copy (verbatim from the old ⓘ accordions, single-sourced here)

    private var EX_QUEMUEVE: LocalizedStringKey { "We line up this vital against your own sleep and the prior day's strain, night by night across your history, and read which way it leans (Pearson correlation). We only show a direction once there are enough paired nights (about six weeks) and the link is strong enough to be unlikely to be chance — never the number, and never as a cause. (Plews 2013)" }

    // MARK: - Wells

    private func loadingWell(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(theme.surface)
            .frame(height: height)
            .overlay { ProgressView().tint(theme.inkTertiary) }
    }

    private func emptyWell(text: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 22))
                .foregroundStyle(theme.inkTertiary)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Colour + format

    private var metricHue: Color {
        switch spec.descriptor.key {
        case "hrv":               return theme.dataHrv
        case "rhr":               return theme.dataHeart
        case "resp_rate":         return theme.dataSpO2
        case "spo2":              return theme.dataSpO2
        case "heart_rate":        return theme.dataHeart
        case "steps":             return theme.dataSteps
        case "vo2max":            return theme.dataSpO2
        default:                  return theme.dataRecovery
        }
    }

    private var chartGradient: Gradient { Gradient(colors: [metricHue.opacity(0.5), metricHue]) }

    /// Format a value with the descriptor's own decimal precision. Integers get locale grouping so a
    /// four-figure step count reads "9,210", not "9210"; the vitals stay under 1,000 so they're
    /// visually unchanged. (FER-254)
    private func fmt(_ v: Double) -> String {
        guard spec.descriptor.decimals == 0 else { return String(format: "%.\(spec.descriptor.decimals)f", v) }
        return Self.groupedInt.string(from: NSNumber(value: Int(v.rounded()))) ?? "\(Int(v.rounded()))"
    }

    private static let groupedInt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()

    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Sheet paper background (iOS 16.4+ presentationBackground)

private struct SheetPaperBackground: ViewModifier {
    let paper: Color
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(paper)
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
private func sampleVitalSeries(base: Double, swing: Double, days: Int = 40) -> [(day: String, value: Double)] {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let f = MetricDetailScreen.dayParser
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = base + swing * sin(Double(i) / 4.0) + Double((i * 13) % 5) - 2
        return (f.string(from: date), max(1, v))
    }
}

#Preview("MetricDetailScreen — HRV (full)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .hrv(64),
            depth: .full,
            seriesLoader: { sampleVitalSeries(base: 58, swing: 12) },
            nightVitalsLoader: { .init(respiration: 14.6, restingHR: 52) }
        )
    }
}

#Preview("MetricDetailScreen — HRV (focus)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .hrv(64),
            depth: .focus,
            seriesLoader: { sampleVitalSeries(base: 58, swing: 12) },
            nightVitalsLoader: { .init(respiration: 14.6, restingHR: 52) }
        )
    }
}

#Preview("MetricDetailScreen — Resting HR (full)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .restingHR(54),
            depth: .full,
            seriesLoader: { sampleVitalSeries(base: 54, swing: 4) }
        )
    }
}

#Preview("MetricDetailScreen — Respiratory (full)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .respiratory(14.8),
            depth: .full,
            seriesLoader: { sampleVitalSeries(base: 14.5, swing: 1.2) },
            nightVitalsLoader: { .init(respiration: 14.8, restingHR: 54) }
        )
    }
}

private func sampleHRCurve() -> [TrendPoint] {
    let cal = Calendar(identifier: .gregorian)
    let midnight = cal.startOfDay(for: Date())
    return (0..<200).map { i in
        let t = midnight.addingTimeInterval(Double(i) * 300)
        let base = 60.0 + 26.0 * sin(Double(i) / 18.0) + Double((i * 7) % 9)
        let spike = (i > 150 && i < 162) ? 60.0 : 0
        return TrendPoint(date: t, value: max(48, base + spike))
    }
}

#Preview("MetricDetailScreen — Heart Rate (full)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .heartRate(68),
            depth: .full,
            seriesLoader: { [] },
            intradayCurveLoader: { sampleHRCurve() },
            hrMax: 188,
            restingHR: 52
        )
    }
}

#Preview("MetricDetailScreen — Heart Rate (no readings)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .heartRate(nil),
            depth: .full,
            seriesLoader: { [] },
            intradayCurveLoader: { [] },
            hrMax: 188
        )
    }
}

#Preview("MetricDetailScreen — HRV (calibrating)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .hrv(nil),
            depth: .full,
            seriesLoader: { Array(sampleVitalSeries(base: 58, swing: 12).suffix(1)) }
        )
    }
}
#endif
#endif
