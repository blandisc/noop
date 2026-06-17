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

    enum Depth { case focus, full }

    /// Companion vitals for the night block.
    struct NightVitals: Equatable {
        var respiration: Double?
        var restingHR: Double?
    }

    @State private var range: ExploreRange = .month
    @State private var series: [(day: String, value: Double)] = []
    @State private var nightVitals: NightVitals = NightVitals(respiration: nil, restingHR: nil)
    @State private var loaded = false

    // MARK: - Depth → visible blocks

    /// `.full` shows everything the spec declares; `.focus` shows only the day-photo subset.
    private var visibleBlocks: BlockSet {
        switch depth {
        case .full:  return spec.blocks
        case .focus: return spec.blocks.intersection([.seriesChartBand, .normalRange, .method, .nightVitals])
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
                    if enoughHistory {
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
            series = await seriesLoader()
            // Parse every day string to a Date ONCE per series (not per slice / per render). (FER-216)
            parsedSeries = series.map { ($0.day, Self.dayParser.date(from: $0.day), $0.value) }
            if let loader = nightVitalsLoader { nightVitals = await loader() }
            loaded = true
        }
    }

    /// The blocks the spec declares, separated by a hairline divider so they don't read as one slab.
    /// The window is computed once in `body` and threaded through. (FER-216)
    @ViewBuilder private func content(_ window: Window) -> some View {
        let hasMethod = visibleBlocks.contains(.method) && spec.info.method != nil
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
        if visibleBlocks.contains(.trend) {
            blockDivider
            trendBlock(window)
        }
        if visibleBlocks.contains(.nightVitals) {
            blockDivider
            nightVitalsBlock
        }
        // "Qué la mueve" → FER-209 (correlación real + gate de datos)
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
        case .movingAverage7: return SeriesShape.latestMovingAverage(allValues, window: 7)
        case .latest:         return series.last?.value
        }
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
            if loaded, let today = todayValue {
                Text(heroContext(today))
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reading = readingCopy(for: .header) {
                Text(reading)
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroOverline: LocalizedStringKey {
        switch spec.descriptor.key {
        case "hrv":       return "Heart rate variability · 7-day average"
        case "rhr":       return "Resting HR · 7-day average"
        case "resp_rate": return "Respiratory rate · 7-day average"
        default:          return "7-day average"
        }
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
                let smoothed = SeriesShape.movingAverage(window.values, window: 7)
                // Decimate to ~80 points for DRAWING only (a year is 365 days → 365 marks Charts must
                // stroke + animate, which is what made the chart stick on long ranges). The hero/stats
                // above still read the FULL series; this only thins what the line draws. Short ranges
                // (≤80 days: week/month) pass through untouched, so they look identical. (FER-219)
                let points = Self.decimatedPoints(rows: window.rows, values: smoothed, maxPoints: 80)
                TrendChart(
                    points: points,
                    gradient: chartGradient,
                    valueRange: chartRange(smoothed),
                    showsArea: true,
                    height: 200,
                    showsHover: true,
                    valueFormat: { "\(fmt($0)) \(unit)" },
                    axisLabelColor: theme.inkTertiary,
                    gridLineColor: theme.hairline
                )
                .accessibilityElement()
                .accessibilityLabel(Text("7-day moving average"))
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
        effectiveRange == .all
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
            let steady = cv <= 0.10 ? String(localized: "steady") : String(localized: "variable")
            // The ⓘ discloses the coefficient-of-variation math (FER-220); the block's overline + datum +
            // plain-language reading (FER-216) stay exactly as before, inside the accordion's content.
            InfoAccordion(
                title: "Consistency (CV)",
                explanation: "Coefficient of variation = standard deviation ÷ the mean of your last few weeks. It measures how spread out your values are around your average. Low = steady. In HRV, a rising CV can precede fatigue even while the value still looks high. (Plews 2013)",
                accessibilityLabel: "Information about consistency",
                theme: theme
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    // Resolve the steady/variable word to a String first so the nested phrase localizes
                    // (interpolating a LocalizedStringKey into another doesn't translate the inner key).
                    Text("±\(pct)% week to week · \(steady)")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(theme.ink)
                    if let reading = readingCopy(for: .consistency) {
                        Text(reading)
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
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
                    Text(trendHeadline(mom: mom))
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    trendStrip(s)
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

    private func trendHeadline(mom: PeriodComparison) -> LocalizedStringKey {
        let slope = mom.current.slopePerDay
        // A slope that rounds to "0"/"0.0" at the metric's precision is no movement — say so in words
        // instead of "+0 ms/day". Same for a sub-1% month-over-month change. (FER-211)
        let slopeMagnitude = fmt(abs(slope))
        let slopeIsFlat = Double(slopeMagnitude) == 0
        let slopeStr = (slope >= 0 ? "+" : "−") + slopeMagnitude

        if let pct = mom.pctChange {
            let pctIsFlat = abs(pct) < 1
            switch (slopeIsFlat, pctIsFlat) {
            case (true, true):
                return "Stable this month"
            case (true, false):
                let pctStr = "\(pct >= 0 ? "+" : "−")\(String(format: "%.0f", abs(pct)))%"
                return "\(pctStr) vs last month"
            case (false, true):
                return "\(slopeStr) \(unit)/day this month"
            case (false, false):
                let pctStr = "\(pct >= 0 ? "+" : "−")\(String(format: "%.0f", abs(pct)))%"
                return "\(slopeStr) \(unit)/day this month · \(pctStr) vs last month"
            }
        }
        // No month-over-month %: just the slope, or "Stable" when it's flat.
        return slopeIsFlat ? "Stable this month" : "\(slopeStr) \(unit)/day this month"
    }

    /// Three plain-language statistics — Average · Lowest · Highest — instead of the old five
    /// (Avg · Median · Min · Max · σ). Median and σ are still computed (the headline's slope reads
    /// from the same stat), just no longer shown. (FER-216)
    private func trendStrip(_ s: SeriesStat) -> some View {
        HStack(alignment: .top) {
            statCell("Average", fmt(s.mean))
            Spacer()
            statCell("Lowest", fmt(s.min))
            Spacer()
            statCell("Highest", fmt(s.max))
        }
    }

    private func statCell(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).textCase(.uppercase)
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Text(value).font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
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
        return VStack(alignment: .leading, spacing: 12) {
            Text("Not enough history yet")
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
            HStack(alignment: .firstTextBaseline) {
                Text("Calibrating").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("\(nights) / 7 nights")
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
            Text("We need a few more nights to show your 7-day average, your normal range and the trend.")
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
        default:                  return theme.dataRecovery
        }
    }

    private var chartGradient: Gradient { Gradient(colors: [metricHue.opacity(0.5), metricHue]) }

    /// Format a value with the descriptor's own decimal precision.
    private func fmt(_ v: Double) -> String {
        spec.descriptor.decimals == 0 ? "\(Int(v.rounded()))" : String(format: "%.\(spec.descriptor.decimals)f", v)
    }

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
