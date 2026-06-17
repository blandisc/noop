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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if loaded {
                    if enoughHistory {
                        content
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
            if let loader = nightVitalsLoader { nightVitals = await loader() }
            loaded = true
        }
    }

    @ViewBuilder private var content: some View {
        if visibleBlocks.contains(.periodSelector) { periodSelector }
        if visibleBlocks.contains(.seriesChartBand) { chartBlock }
        if visibleBlocks.contains(.normalRange) { normalRangeBlock }
        if visibleBlocks.contains(.consistency) { consistencyBlock }
        if visibleBlocks.contains(.trend) { trendBlock }
        if visibleBlocks.contains(.nightVitals) { nightVitalsBlock }
        if visibleBlocks.contains(.whatMovesIt) { whatMovesItBlock }
        if visibleBlocks.contains(.method), let method = spec.info.method { methodDisclosure(method) }
    }

    // MARK: - Derived series

    private var unit: String { spec.info.unit ?? "" }

    private var allValues: [Double] { series.map(\.value) }

    /// The effective window: the selected range when it holds ≥1 point, else the smallest larger range
    /// that does (Explorer's auto-widen). Taken RELATIVE TO THE LATEST point, not "now".
    private var effectiveRange: ExploreRange {
        guard !series.isEmpty else { return range }
        for r in range.widening where !slice(for: r).isEmpty { return r }
        return .all
    }

    private var windowFellBack: Bool { effectiveRange != range }

    private func slice(for r: ExploreRange) -> [(day: String, value: Double)] {
        guard let days = r.days else { return series }
        guard let lastDay = series.last?.day, let last = Self.dayParser.date(from: lastDay) else { return [] }
        let cutoff = last.addingTimeInterval(-Double(days - 1) * 86_400)
        return series.filter { row in
            guard let d = Self.dayParser.date(from: row.day) else { return false }
            return d >= cutoff
        }
    }

    private var windowed: [(day: String, value: Double)] { slice(for: effectiveRange) }
    private var windowValues: [Double] { windowed.map(\.value) }

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

    private var periodSelector: some View {
        HStack {
            Text(rangeCaption)
                .font(StrandFont.footnote)
                .foregroundStyle(windowFellBack ? theme.warning : theme.inkTertiary)
            Spacer(minLength: 8)
            SegmentedPillControl(ExploreRange.allCases, selection: $range) { $0.label }
                .tint(metricHue)
        }
    }

    private var rangeCaption: LocalizedStringKey {
        let n = windowed.count
        if windowFellBack {
            return "Showing the last \(n) days"
        }
        return n == 1 ? "1 reading" : "\(n) readings"
    }

    // MARK: - Chart + band (7-day moving average · normal-variation band)

    @ViewBuilder private var chartBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if windowValues.count > 1 {
                let smoothed = SeriesShape.movingAverage(windowValues, window: 7)
                let band = ReferenceRange.interquartile(windowValues)
                Sparkline(
                    values: smoothed,
                    gradient: chartGradient,
                    range: chartRange(smoothed, band: band),
                    referenceBand: band,
                    bandColor: theme.hairlineStrong,
                    lineWidth: 2.5,
                    showsArea: true,
                    showsHead: true,
                    showsHover: true,
                    valueFormat: { "\(fmt($0)) \(unit)" }
                )
                .frame(height: 132)
                .accessibilityElement()
                .accessibilityLabel(Text("7-day moving average with normal-variation band"))
                Text("7-day moving average · normal-variation band.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            } else if let only = windowValues.first {
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

    /// Auto-fit the chart's value axis to the smoothed line AND the band so neither clips.
    private func chartRange(_ smoothed: [Double], band: ClosedRange<Double>?) -> ClosedRange<Double> {
        var lo = smoothed.min() ?? 0
        var hi = smoothed.max() ?? 1
        if let band {
            lo = Swift.min(lo, band.lowerBound)
            hi = Swift.max(hi, band.upperBound)
        }
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.15
        return (lo - pad)...(hi + pad)
    }

    // MARK: - Normal range (rolling mean ± SD)

    @ViewBuilder private var normalRangeBlock: some View {
        if let baseline = baselineState, baseline.nValid >= 1 {
            let lo = baseline.baseline - sigma(baseline)
            let hi = baseline.baseline + sigma(baseline)
            block(title: "Your normal range") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(fmt(lo))–\(fmt(hi)) \(unit) · \(baseline.nValid) nights")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(theme.ink)
                    Text("A change counts only when it leaves the band.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            block(title: "Consistency (CV)") {
                VStack(alignment: .leading, spacing: 6) {
                    // Resolve the steady/variable word to a String first so the nested phrase localizes
                    // (interpolating a LocalizedStringKey into another doesn't translate the inner key).
                    Text("±\(pct)% week to week · \(steady)")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(theme.ink)
                    Text("A high HRV that swings a lot can be fatigue, not rest.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Trend (month over month)

    @ViewBuilder private var trendBlock: some View {
        let mom = ComparisonEngine.monthOverMonth(byDay: series, referenceDay: series.last?.day ?? "")
        let s = ComparisonEngine.stat(windowValues)
        if s.n > 0 {
            block(title: "Trend") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(trendHeadline(mom: mom))
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    trendStrip(s)
                }
            }
        }
    }

    private func trendHeadline(mom: PeriodComparison) -> LocalizedStringKey {
        let slope = mom.current.slopePerDay
        let slopeStr = (slope >= 0 ? "+" : "−") + fmt(abs(slope))
        if let pct = mom.pctChange {
            let pctStr = "\(pct >= 0 ? "+" : "−")\(String(format: "%.0f", abs(pct)))%"
            return "\(slopeStr) \(unit)/day this month · \(pctStr) vs last month"
        }
        return "\(slopeStr) \(unit)/day this month"
    }

    private func trendStrip(_ s: SeriesStat) -> some View {
        HStack(alignment: .top) {
            statCell("Avg", fmt(s.mean))
            Spacer()
            statCell("Median", fmt(s.median))
            Spacer()
            statCell("Min", fmt(s.min))
            Spacer()
            statCell("Max", fmt(s.max))
            Spacer()
            statCell("σ", fmt(s.stdev))
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
                    Text("When they rise together, your body is under load.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var nightVitalsLine: LocalizedStringKey {
        let resp = nightVitals.respiration.map { String(format: "%.1f", $0) } ?? "—"
        let rhr = nightVitals.restingHR.map { "\(Int($0.rounded()))" } ?? "—"
        return "Respiration \(resp) · Resting HR \(rhr)"
    }

    // MARK: - What moves it

    private var whatMovesItBlock: some View {
        block(title: "What moves it") {
            VStack(alignment: .leading, spacing: 8) {
                InlineFlagChip("trend, not cause", color: theme.inkTertiary)
                Text("Tends to dip on nights with less than 7 h of sleep.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
