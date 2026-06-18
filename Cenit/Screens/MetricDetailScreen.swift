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

    enum Depth { case focus, full }

    /// Companion vitals for the night block.
    struct NightVitals: Equatable {
        var respiration: Double?
        var restingHR: Double?
    }

    @State private var range: ExploreRange = .month
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
        let window = makeWindow()
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if loaded {
                    // Heart Rate's intraday path has no "N/7 nights" calibration — each block shows its
                    // own honest empty state (no readings yet today). (FER-253)
                    if isIntraday {
                        content(window)
                    } else if enoughHistory {
                        content(window)
                    } else {
                        calibrationBlock
                    }
                } else {
                    loadingWell(height: 160)
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
            parsedSeries = series.map { ($0.day, Self.dayParser.date(from: $0.day), $0.value) }
            if let loader = nightVitalsLoader { nightVitals = await loader() }
            if visibleBlocks.contains(.whatMovesIt), let loader = whatMovesItLoader {
                whatMovesItFindings = await loader()
            }
            loaded = true
        }
    }

    /// The blocks the spec declares, separated by a hairline divider so they don't read as one slab.
    /// The window is computed once in `body` and threaded through. (FER-216)
    @ViewBuilder private func content(_ window: Window) -> some View {
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
        if visibleBlocks.contains(.normalRange) {
            blockDivider
            normalRangeBlock
        }
        if visibleBlocks.contains(.consistency) {
            blockDivider
            consistencyBlock
        }
        if visibleBlocks.contains(.fixedBands) {
            blockDivider
            fixedBandsBlock
        }
        if visibleBlocks.contains(.lowNightsCount) {
            blockDivider
            lowNightsBlock
        }
        if visibleBlocks.contains(.trend) {
            blockDivider
            trendBlock(window)
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
        if hasMethod, let method = spec.info.method {
            blockDivider
            methodDisclosure(method)
        }
    }

    /// A subtle 1px rule between blocks (token-only, no hex). (FER-216)
    private var blockDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    // MARK: - Derived series

    private var unit: String { spec.info.unit ?? "" }

    private var allValues: [Double] { series.map(\.value) }

    /// One render's worth of window derivation — the active range, its rows, their values and whether the
    /// selection auto-widened — computed ONCE in `body` and handed to every block. Previously each block
    /// re-derived `effectiveRange`/`windowed`/`windowValues` independently, and each re-ran `slice(for:)`,
    /// which re-parsed every day string with a `DateFormatter` (thousands of parses per redraw on long
    /// ranges). (FER-216)
    struct Window {
        let range: ExploreRange
        let rows: [(day: String, value: Double)]
        let values: [Double]
        let fellBack: Bool
    }

    /// The series with each `day` string parsed to a `Date` exactly ONCE per series (not per slice,
    /// not per render). The window math reads `date` straight from here instead of re-parsing. Built in
    /// `.task` alongside `series`. (FER-216)
    @State private var parsedSeries: [(day: String, date: Date?, value: Double)] = []

    /// The effective range: the selected range when its window holds ≥1 point, else the smallest larger
    /// range that does (Explorer's auto-widen). Taken RELATIVE TO THE LATEST point, not "now".
    private func effectiveRange() -> ExploreRange {
        guard !parsedSeries.isEmpty else { return range }
        for r in range.widening where !slice(for: r).isEmpty { return r }
        return .all
    }

    /// Trailing-N-days slice for `r`, taken relative to the latest point. Reads the memoized `date`
    /// from `parsedSeries` — no `DateFormatter` work here.
    private func slice(for r: ExploreRange) -> [(day: String, value: Double)] {
        guard let days = r.days else { return parsedSeries.map { ($0.day, $0.value) } }
        guard let last = parsedSeries.last?.date else { return [] }
        let cutoff = last.addingTimeInterval(-Double(days - 1) * 86_400)
        return parsedSeries.compactMap { row in
            guard let d = row.date, d >= cutoff else { return nil }
            return (row.day, row.value)
        }
    }

    /// Compute the whole window ONCE per render and pass it to the blocks.
    private func makeWindow() -> Window {
        let eff = effectiveRange()
        let rows = slice(for: eff)
        return Window(range: eff, rows: rows, values: rows.map(\.value), fellBack: eff != range)
    }

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
            return "It's the average of your heart rate variability over the last week. Higher usually goes hand in hand with better recovery."
        case ("hrv", .normalRange):
            return "Where your HRV usually lands when you're well. Only worth noting when a day falls outside it."
        case ("hrv", .consistency):
            return "How even it stays from one week to the next. Steadier usually means better rest; very uneven can be fatigue."
        case ("hrv", .trend):
            return "Where your HRV is headed this month compared with last month."
        case ("hrv", .nightVitals):
            return nightVitals

        case ("rhr", .header):
            return "It's your lowest heart rate while you sleep. Lower usually points to better fitness and rest."
        case ("rhr", .normalRange):
            return "Where your resting HR usually lands when you're well. Take note when a day falls outside it."
        case ("rhr", .trend):
            return "Where your resting HR is headed this month compared with last month."

        case ("resp_rate", .header):
            return "It's your average breathing rate while you sleep. It's usually very steady; if it rises above your normal, it can be an early sign that something is taxing you."
        case ("resp_rate", .normalRange):
            return "Where your nightly breathing usually lands. Take note when a day falls outside it."
        case ("resp_rate", .trend):
            return "Where your breathing is headed this month compared with last month."
        case ("resp_rate", .nightVitals):
            return nightVitals

        case ("spo2", .header):
            return "It's the average oxygen saturation read at your wrist while you sleep, over the last week. A healthy adult usually stays at 95% or above."

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

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heroOverline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
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

    /// The secondary line under the hero numeral. For the vitals (hero = 7-day average) it frames TODAY's
    /// single reading against the band. For steps the hero IS today's count, so the secondary instead
    /// carries the 7-day daily average — the stable context for a noisy daily count. (FER-254)
    @ViewBuilder private var heroSecondary: some View {
        if let text = heroSecondaryText {
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

    private var heroOverline: LocalizedStringKey {
        switch spec.descriptor.key {
        case "hrv":        return "Heart rate variability · 7-day average"
        case "rhr":        return "Resting HR · 7-day average"
        case "resp_rate":  return "Respiratory rate · 7-day average"
        case "spo2":       return "Blood oxygen · 7-day average"
        case "heart_rate": return "Heart rate · today"
        case "steps":      return "Steps · today"
        default:           return "7-day average"
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

    private func periodSelector(_ window: Window) -> some View {
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

    @ViewBuilder private func chartBlock(_ window: Window) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if window.values.count > 1 {
                // Clinically-anchored metrics (SpO₂) plot RAW nightly values behind a fixed band so a
                // single low night stays visible; the noisy vitals (HRV/RHR/resp) plot the 7-day MA. (FER-252)
                let lineValues = spec.clinicalBands ? window.values : SeriesShape.movingAverage(window.values, window: 7)
                // Decimate to ~80 points for DRAWING only (a year is 365 days → 365 marks Charts must
                // stroke + animate, which is what made the chart stick on long ranges). The hero/stats
                // above still read the FULL series; this only thins what the line draws. Short ranges
                // (≤80 days: week/month) pass through untouched, so they look identical. (FER-219)
                let points = Self.decimatedPoints(rows: window.rows, values: lineValues, maxPoints: 80)
                TrendChart(
                    points: points,
                    gradient: chartGradient,
                    valueRange: spec.chartDomain ?? chartRange(lineValues),
                    showsArea: true,
                    height: 200,
                    showsHover: true,
                    valueFormat: { "\(fmt($0)) \(unit)" },
                    axisLabelColor: theme.inkTertiary,
                    gridLineColor: theme.hairline,
                    bands: clinicalChartBands,
                    bandColor: theme.verdict,
                    yAxisValues: clinicalYAxisValues,
                    alertThreshold: spec.clinicalBands ? spec.lowThreshold : nil,
                    alertColor: theme.critical
                )
                .accessibilityElement()
                .accessibilityLabel(Text(spec.clinicalBands ? "Nightly readings" : "7-day moving average"))
                Text(chartCaption(window.range))
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            } else if let only = window.values.first {
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
    }

    /// Build the chart's `[TrendPoint]`, decimating long series to ≤`maxPoints` for DRAWING only. Both the
    /// values and their dates are bucketed with the SAME contiguous `n*b/maxPoints` partition that
    /// `SeriesShape.decimate` uses, so each averaged value keeps a representative date (the bucket's
    /// CENTER day) and the date↔value pairing stays consistent. When `rows.count <= maxPoints` nothing is
    /// thinned — every day maps to its own point exactly as before — so short ranges are unchanged. (FER-219)
    private static func decimatedPoints(rows: [(day: String, value: Double)], values: [Double], maxPoints: Int) -> [TrendPoint] {
        let n = min(rows.count, values.count)
        guard n > maxPoints, maxPoints > 1 else {
            // Short series (or degenerate maxPoints): one point per day, like before decimation existed.
            return zip(rows, values).compactMap { row, value in
                dayParser.date(from: row.day).map { TrendPoint(date: $0, value: value) }
            }
        }
        let decimated = SeriesShape.decimate(Array(values.prefix(n)), maxPoints: maxPoints)
        var out: [TrendPoint] = []
        out.reserveCapacity(decimated.count)
        for b in 0..<decimated.count {
            // The SAME partition decimate uses: bucket b spans indices [lo, hi). Pick the bucket's center
            // row for the representative date so the x-position sits in the middle of what it averages.
            let lo = (n * b) / maxPoints
            let hi = (n * (b + 1)) / maxPoints
            let mid = min(lo + (hi - lo) / 2, n - 1)
            if let date = dayParser.date(from: rows[mid].day) {
                out.append(TrendPoint(date: date, value: decimated[b]))
            }
        }
        return out
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

    /// The chart's caption: the 7-day-average note, suffixed with the window ("· last month") for a
    /// bounded range and left bare for ALL. The window name is already localized, so it's interpolated
    /// as a `String` (a `%@` placeholder), not re-localized as a key. (FER-211)
    private func chartCaption(_ effectiveRange: ExploreRange) -> LocalizedStringKey {
        if spec.clinicalBands {
            // Raw nightly values, not a moving average; the green band is the healthy 95–100% zone.
            return effectiveRange == .all
                ? "Nightly values · the shaded band is the healthy range."
                : "Nightly values · last \(effectiveRange.name) · the shaded band is the healthy range."
        }
        return effectiveRange == .all
            ? "7-day moving average."
            : "7-day moving average · last \(effectiveRange.name)."
    }

    // MARK: - Normal range (rolling mean ± SD)

    @ViewBuilder private var normalRangeBlock: some View {
        if let baseline = baselineState, baseline.nValid >= 1 {
            let lo = baseline.baseline - sigma(baseline)
            let hi = baseline.baseline + sigma(baseline)
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

    /// Convert the baseline's internal abs-dev spread to a Gaussian σ for the displayed ± band.
    private func sigma(_ s: BaselineState) -> Double { 1.253 * s.spread }

    /// The ±1σ "normal range" used to frame today's reading (nil when no baseline yet).
    private var normalRange: ClosedRange<Double>? {
        guard let s = baselineState else { return nil }
        let lo = s.baseline - sigma(s), hi = s.baseline + sigma(s)
        return Swift.min(lo, hi)...Swift.max(lo, hi)
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

    // MARK: - Fixed clinical bands (population range table) — SpO₂ (FER-252)

    /// The metric's fixed population bands (Normal / Borderline / Low) as a table, with the band
    /// today's value falls in marked "· today". Unlike `normalRangeBlock` (a personal rolling ±SD),
    /// this is the same clinical reference for everyone — what matters for SpO₂ is the population floor.
    @ViewBuilder private var fixedBandsBlock: some View {
        block(title: "Normal range") {
            VStack(spacing: 0) {
                ForEach(Array(spec.info.bands.enumerated()), id: \.offset) { i, band in
                    bandRow(band)
                    if i < spec.info.bands.count - 1 {
                        Rectangle().fill(theme.hairline).frame(height: 1).padding(.leading, 36)
                    }
                }
            }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func bandRow(_ band: MetricInfo.Band) -> some View {
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
                Text("· today")
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
            let recent = slice(for: .month)
            let low = recent.reduce(0) { $0 + ($1.value < threshold ? 1 : 0) }
            block(title: "Nights below \(fmt(threshold))\(unit)") {
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
                    showsHover: true,
                    valueFormat: { "\(Int($0.rounded())) \(unit)" },
                    dateFormat: { Self.hrClock.string(from: $0) },
                    axisLabelColor: theme.inkTertiary,
                    gridLineColor: theme.hairline,
                    referenceLine: restingHR,
                    referenceLineColor: theme.inkTertiary.opacity(0.7),
                    markedPoint: peakPoint
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
        return block(title: "Time in zones · today") {
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

    @ViewBuilder private func trendBlock(_ window: Window) -> some View {
        let mom = ComparisonEngine.monthOverMonth(byDay: series, referenceDay: series.last?.day ?? "")
        let s = ComparisonEngine.stat(window.values)
        if s.n > 0 {
            // The ⓘ discloses how the slope, the month-over-month % and the stats are computed (FER-220);
            // the block's overline + headline + stat strip + plain-language reading (FER-216) are unchanged.
            InfoAccordion(
                title: "Trend",
                explanation: "The slope is how much it rises or falls on average per day, by linear regression over the period. The percentage vs last month compares this month's average against the previous one. Average, Lowest and Highest are from the range you selected.",
                accessibilityLabel: "Information about the trend",
                theme: theme
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    TrendStatSummary(
                        average: fmt(s.mean),
                        unit: unit.isEmpty ? nil : unit,
                        pctChange: mom.pctChange,
                        polarity: trendPolarity,
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
            block(title: "Last night's vitals") {
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
            Text("See the method")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
        }
        .tint(theme.inkTertiary)
        .padding(14)
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

    // MARK: - Shared block scaffold + wells

    /// A titled block on the paper: a quiet overline + content (no card-in-card; surface used sparingly).
    @ViewBuilder
    private func block<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
