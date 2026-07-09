#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import Foundation

// MARK: - MetricLevelsExplorer — the F6b «level pattern» as a reusable block (FER-572 / F6c)
//
// F6b (FER-571) gave the five `usesLevels` vitals in `MetricDetailScreen` a signature instrument:
// a RAW-value line chart with the active level's band shaded, a «{level} · N de tus últimos M días»
// phrase, and a TAPPABLE levels list (tap a row → highlight its band, dim the rest, re-read the
// phrase; today keeps a ring while you explore). That logic lives PRIVATELY inside `MetricDetailScreen`,
// which F6c may not touch (it's out of scope). So F6c extracts the same instrument into one reusable
// view the four own-screens (Recovery / Strain / Stress / Sleep's duration block) drop in BELOW their
// existing hero — the owner kept each screen's dominant numeral and rich content, and adds this block
// (not a full-screen replacement). It reuses F6a (`MetricLevels`) for the levels + counts and the
// shared `MetricTrendChart` for the line, so the band the chart shades and the count the list reads
// always agree.
//
// The host owns `@State range` + the parsed series and computes the `MetricWindow` once (same contract
// as `MetricDetailScreen`); this view owns only the explore selection.

struct MetricLevelsExplorer: View {
    let theme: InstrumentoTheme
    @Binding var range: ExploreRange
    /// The window the host computed once from its parsed series (`MetricWindowMath.make`).
    let window: MetricWindow
    /// The ordered levels (low→high, half-open `[lower, upper)`) from F6a — fixed or relative-to-base.
    let levels: [MetricLevels.Level]
    /// Today's active value (sets the «· today» row + ring). nil → no active level. The four F6c metrics
    /// are all daily-final (no running total like steps), so the host passes its latest reading.
    let todayValue: Double?
    /// The metric's hue (the band fill, the highlighted phrase/row). Recovery green, strain orange, etc.
    let hue: Color
    let unit: String
    /// Formats a level threshold / chart value (e.g. steps → "8k", sleep → "7.5", recovery → "78").
    let valueFormat: (Double) -> String
    /// A fixed Y domain (recovery 0…100, strain 0…21, stress 0…3); nil auto-fits to the levels + line.
    var domain: ClosedRange<Double>? = nil
    /// Count overnight readings as «nights» rather than «days» in the phrase + the per-level counts. Sleep's
    /// duration block sets this true; the others read daily. (FER-572)
    var nightly: Bool = false
    /// Bolder «ink thumb» selector (the active pill is a solid ink capsule with paper text) — the same
    /// segmented look the Carga sheet uses. The summary sheets (`MetricInfoSheet`) opt in so every Today
    /// card's selector reads identically; the Recuperación detail keeps the quiet surface thumb. (default false)
    var inkThumb: Bool = false
    /// The «Media ⇄ Rangos» toggle (handoff v2, FER-803). When bound, the block shows the compact toggle
    /// inline with the period selector and SWAPS the moving-average line («Media») for the population lanes
    /// list («Rangos»). nil → legacy behavior: line AND lanes shown together, no toggle.
    var mode: Binding<TrendMode>? = nil
    let accessibilityLabel: LocalizedStringKey

    /// The level the user is exploring — nil shows today's. Tapping a row highlights its band and re-reads
    /// the phrase; tapping the highlighted row clears back to today. (mirrors F6b)
    @State private var selectedLevelIndex: Int? = nil

    // MARK: Classification (F6a)

    private struct LevelData {
        let levels: [MetricLevels.Level]
        let counts: [Int]
        let total: Int
        let todayIndex: Int?
    }

    private var data: LevelData {
        let c = MetricLevels.classification(values: window.values, today: todayValue, levels: levels)
        return LevelData(levels: c.levels, counts: c.counts, total: c.total, todayIndex: c.activeIndex)
    }

    /// The level the chart + phrase highlight: the user's selection, else today's. (FER-571)
    private func displayLevelIndex(_ d: LevelData) -> Int? {
        if let s = selectedLevelIndex, d.levels.indices.contains(s) { return s }
        return d.todayIndex
    }

    private var gradient: Gradient { ChartWell.fillGradient(hue) }

    // MARK: Body

    var body: some View {
        let d = data
        // With the toggle bound: «Media» → the line only, «Rangos» → the lanes list only. Without it
        // (legacy): both. The phrase (the active level + count) always shows — it's the shared summary.
        let showChart = mode.map { $0.wrappedValue == .media } ?? true
        let showList = mode.map { $0.wrappedValue == .rangos } ?? true
        return VStack(alignment: .leading, spacing: 14) {
            rangeControl
            phrase(d)
            if showChart { chart(d) }
            if showList { list(d) }
        }
    }

    private var rangeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme, inkThumb: inkThumb) { $0.label }
                .onChange(of: range) { _ in selectedLevelIndex = nil }
            if let mode {
                HStack {
                    Spacer(minLength: 0)
                    CompactTrendToggle(mode: mode, theme: theme)
                }
            }
            if window.fellBack {
                Text("Showing the last \(window.rows.count) days")
                    .font(StrandFont.footnote).foregroundStyle(theme.warning)
            }
        }
    }

    @ViewBuilder private func phrase(_ d: LevelData) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let i = displayLevelIndex(d) {
                Text(label(d.levels[i].key)).font(StrandFont.title1).foregroundStyle(hue)
                    .fixedSize(horizontal: false, vertical: true)
                Text(nightly ? "\(d.counts[i]) of your last \(d.total) nights"
                             : "\(d.counts[i]) of your last \(d.total) days")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            } else {
                Text("No reading today").font(StrandFont.title1).foregroundStyle(theme.inkTertiary)
                Text(nightly ? "\(d.total) nights with data in this range"
                             : "\(d.total) days with data in this range")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    @ViewBuilder private func chart(_ d: LevelData) -> some View {
        let highlight = displayLevelIndex(d)
        MetricTrendChart(
            range: $range, window: window, theme: theme, showsSelector: false,
            style: .init(
                smoothing: nil,                          // RAW daily values so the dots fall in the counted bands
                gradient: gradient,
                showsArea: false,
                height: 168,
                valueRange: { chartDomain(d, values: $0) },
                valueFormat: { "\(valueFormat($0)) \(unit)".trimmingCharacters(in: .whitespaces) },
                bands: { _ in chartBands(d, highlight: highlight) },
                bandColor: { _ in hue },
                yAxisValues: yTicks(d),
                yTickCount: 5,
                marksLastPoint: d.todayIndex != nil,
                markedPointHollow: selectedLevelIndex != nil && selectedLevelIndex != d.todayIndex,
                markedPointRingFill: theme.paper,
                bandLabelsHidden: true,                  // the levels are named in the list, not on the plot
                accessibilityLabel: accessibilityLabel
            )
        ) {
            ChartWell(theme).note(text: "No readings in this range.")
        }
    }

    private func chartBands(_ d: LevelData, highlight: Int?) -> [TrendBand] {
        d.levels.enumerated().map { i, l in
            TrendBand(label: "", lower: l.lower, upper: l.upper, isActive: i == highlight)
        }
    }

    /// The chart's Y domain: a caller-fixed domain, else the level thresholds + the line's own min/max
    /// with a little breath. (mirrors F6b `levelChartDomain`)
    private func chartDomain(_ d: LevelData, values: [Double]) -> ClosedRange<Double> {
        if let dom = domain { return dom }
        let bounds = d.levels.flatMap { [$0.lower, $0.upper].compactMap { $0 } }
        let pool = bounds + values
        guard let lo0 = pool.min(), let hi0 = pool.max(), hi0 > lo0 else {
            let v = values.first ?? bounds.first ?? 0
            return (v - 1)...(v + 1)
        }
        let span = max(hi0 - lo0, 0.0001)
        return (lo0 - span * 0.1)...(hi0 + span * 0.12)
    }

    private func yTicks(_ d: LevelData) -> [Double]? {
        let t = Set(d.levels.flatMap { [$0.lower, $0.upper].compactMap { $0 } }).sorted()
        return t.isEmpty ? nil : t
    }

    // MARK: Levels list

    private func list(_ d: LevelData) -> some View {
        let highlight = displayLevelIndex(d)
        return VStack(spacing: 0) {
            ForEach(Array(d.levels.enumerated()), id: \.offset) { i, level in
                row(index: i, level: level, data: d, highlight: highlight)
                if i < d.levels.count - 1 {
                    Divider().overlay(theme.hairline).padding(.leading, 34)
                }
            }
        }
    }

    private func row(index i: Int, level: MetricLevels.Level, data d: LevelData, highlight: Int?) -> some View {
        let isHighlight = i == highlight
        let isToday = i == d.todayIndex
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedLevelIndex = (selectedLevelIndex == i) ? nil : i   // tap the highlighted row → back to today
            }
        } label: {
            HStack(spacing: 10) {
                dot(isHighlight: isHighlight, isToday: isToday)
                Text(label(level.key)).font(StrandFont.subhead)
                    .foregroundStyle(isHighlight ? theme.ink : theme.inkSecondary)
                if isToday {
                    Text("· today").font(StrandFont.footnote).foregroundStyle(hue)
                }
                Spacer(minLength: 8)
                Text(rangeText(level)).font(StrandFont.captionNumber)
                    .foregroundStyle(isHighlight ? hue : theme.inkTertiary)
                Text(BandSummaryCopy.countLabel(d.counts[i], nightly: nightly))
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(isHighlight ? hue : theme.inkTertiary.opacity(0.85)) // token-exempt: >0.70
                    .frame(minWidth: 50, alignment: .trailing)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(isHighlight ? hue.opacity(StrandOpacity.tintFill) : Color.clear,
                        in: RoundedRectangle(cornerRadius: NoopMetrics.insetRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Highlights this level on the chart"))
    }

    /// Filled hue dot when highlighted; a hollow RING when it's today's level but you're exploring another
    /// (matching the chart's hollow head); else a quiet dot. (FER-571 · option A)
    @ViewBuilder private func dot(isHighlight: Bool, isToday: Bool) -> some View {
        if isToday && !isHighlight {
            Circle().strokeBorder(hue, lineWidth: 2).frame(width: 8, height: 8)
        } else {
            Circle().fill(isHighlight ? hue : theme.inkTertiary.opacity(StrandOpacity.dim)).frame(width: 8, height: 8)
        }
    }

    /// A level's numeric range, half-open `[lower, upper)`: «< hi», «≥ lo», «lo–hi». (mirrors F6b)
    private func rangeText(_ level: MetricLevels.Level) -> String {
        switch (level.lower, level.upper) {
        case let (nil, hi?):  return "< \(valueFormat(hi))"
        case let (lo?, nil):  return "≥ \(valueFormat(lo))"
        case let (lo?, hi?):  return "\(valueFormat(lo))–\(valueFormat(hi))"
        case (nil, nil):      return ""
        }
    }

    /// The es-MX/en label for any F6a level key (fixed metrics + relative-to-base). The English name is
    /// the single source (`MetricLevels.name(for:)`, FER-731 — including the FER-638 rule that `primed`
    /// reads «Alto»/"High", never «A punto»); it doubles as the `Localizable.xcstrings` key, so es-MX
    /// resolves at render. (FER-572)
    private func label(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(MetricLevels.name(for: key))
    }
}
#endif
