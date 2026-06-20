import SwiftUI
import Charts

// MARK: - Trajectory chart (FER-311)
//
// The goal simulator's protagonist: two projected paths over a horizon —"como vas" (the extended
// trend) and "si cambias X" (the trend plus a proven lever's effect)— inside a confidence band that
// widens with the horizon. It is the trajectory cousin of `TrendChart`: a line+area Swift Charts plot,
// but forward-looking and uncertainty-first.
//
// Instrumento §8.4 discipline:
//   • COLOR ONLY ON THE LEVER PATH. "Si cambias" carries the metric hue (the actionable datum); the
//     "como vas" baseline is ink (dashed), the band is faint ink, the goal rule is ink. Without a lever
//     the chart is entirely ink — color escalates with actionability. The caller passes the hue.
//   • The band, not the line, is the honesty — it dominates far-right, where the projection is least sure.
//   • `higherIsBetter` only orients the "↑/↓ mejor" hint; the goal sits wherever its value is (high for
//     recovery/HRV, low for resting HR), so an inverted-axis metric reads as a descent to the goal.
//
// StrandDesign stays the dependency-free leaf: this takes plain `Point` values (the app maps
// `TrajectorySimulator.Projection` into them), never an analytics type. Tokens-only; reads
// `InstrumentoTheme`. Baseline is dashed and the lever solid, so the two paths separate without relying
// on color alone (color-blind safe). Charts' 5 pillars: line marks for trend, an area for uncertainty,
// a labeled goal rule, a sparse hoy→horizonte axis, color as enhancement.

public struct TrajectoryChart: View {

    /// One projected day. `x` is days from today (0 = today's anchor).
    public struct Point: Equatable, Sendable {
        public let x: Double
        public let estimate: Double
        public let low: Double
        public let high: Double
        public init(x: Double, estimate: Double, low: Double, high: Double) {
            self.x = x; self.estimate = estimate; self.low = low; self.high = high
        }
    }

    /// "Como vas" — the extended trend (always present).
    public let baseline: [Point]
    /// "Si cambias X" — trend + lever effect. `nil` → only the baseline is drawn (the "sin palancas" state).
    public let withLever: [Point]?
    /// Today's anchor value, where both paths start (x = 0).
    public let startValue: Double
    /// The goal threshold, drawn as a labeled rule. `nil` hides it.
    public let goal: Double?
    /// Label on the goal rule (e.g. "meta 80").
    public let goalLabel: String?
    /// The metric hue — applied ONLY to the lever path + its endpoint.
    public let accent: Color
    /// Whether higher is better (orients the corner hint only).
    public let higherIsBetter: Bool
    /// Quiet axis end labels (e.g. "hoy" and "+22 d").
    public let xStartLabel: String
    public let xEndLabel: String
    /// One-sentence VoiceOver description (the app builds it; StrandDesign has no catalog).
    public let accessibilityText: String

    @Environment(\.instrumentoTheme) private var theme

    public init(baseline: [Point], withLever: [Point]?, startValue: Double,
                goal: Double?, goalLabel: String?, accent: Color, higherIsBetter: Bool,
                xStartLabel: String, xEndLabel: String, accessibilityText: String) {
        self.baseline = baseline
        self.withLever = withLever
        self.startValue = startValue
        self.goal = goal
        self.goalLabel = goalLabel
        self.accent = accent
        self.higherIsBetter = higherIsBetter
        self.xStartLabel = xStartLabel
        self.xEndLabel = xEndLabel
        self.accessibilityText = accessibilityText
    }

    // The "today" anchor (x = 0) prepended so both paths visibly start from the present.
    private var anchored: [Point] {
        [Point(x: 0, estimate: startValue, low: startValue, high: startValue)] + baseline
    }
    private var anchoredLever: [Point]? {
        withLever.map { [Point(x: 0, estimate: startValue, low: startValue, high: startValue)] + $0 }
    }

    private var xMax: Double { baseline.last?.x ?? 1 }

    private var yDomain: ClosedRange<Double> {
        var lo = startValue, hi = startValue
        for p in baseline + (withLever ?? []) {
            lo = Swift.min(lo, p.low); hi = Swift.max(hi, p.high)
        }
        if let goal { lo = Swift.min(lo, goal); hi = Swift.max(hi, goal) }
        let pad = Swift.max((hi - lo) * 0.12, 1)
        return (lo - pad)...(hi + pad)
    }

    public var body: some View {
        Chart {
            // Confidence band — the honesty, faint ink, widening right.
            ForEach(Array(anchored.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("día", p.x),
                         yStart: .value("low", p.low),
                         yEnd: .value("high", p.high))
            }
            .foregroundStyle(theme.inkTertiary.opacity(0.12))
            .interpolationMethod(.monotone)

            // Goal rule — ink, dashed, labeled.
            if let goal {
                RuleMark(y: .value("meta", goal))
                    .foregroundStyle(theme.ink.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        if let goalLabel {
                            Text(goalLabel).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        }
                    }
            }

            // "Como vas" — ink, dashed (separates from the lever path without color).
            ForEach(Array(anchored.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("día", p.x), y: .value("valor", p.estimate),
                         series: .value("camino", "base"))
            }
            .foregroundStyle(theme.inkSecondary)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3]))
            .interpolationMethod(.monotone)

            // "Si cambias X" — the only colored element. Solid, with an endpoint mark.
            if let lever = anchoredLever {
                ForEach(Array(lever.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("día", p.x), y: .value("valor", p.estimate),
                             series: .value("camino", "lever"))
                }
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)

                if let last = lever.last {
                    PointMark(x: .value("día", last.x), y: .value("valor", last.estimate))
                        .foregroundStyle(accent)
                        .symbolSize(60)
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: 0...xMax)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: [0, xMax]) { value in
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(d == 0 ? xStartLabel : xEndLabel)
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                }
                AxisGridLine().foregroundStyle(theme.hairline)
            }
        }
        .chartPlotStyle { $0.background(theme.paper) }
        .overlay(alignment: higherIsBetter ? .topLeading : .bottomLeading) {
            Text(higherIsBetter ? "↑ mejor" : "↓ mejor")
                .font(StrandFont.footnote)
                .foregroundStyle(higherIsBetter ? theme.dataRecovery : theme.dataHeart)
                .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

#if DEBUG
#Preview("Trajectory — con palanca / sin palanca") {
    // A rising HRV-like trend; the lever lifts the path toward the goal.
    func pts(_ base: [Double], lever: Double?) -> ([TrajectoryChart.Point], [TrajectoryChart.Point]?) {
        let b = base.enumerated().map { i, v in
            TrajectoryChart.Point(x: Double(i + 1), estimate: v, low: v - Double(i) * 0.4 - 2,
                                  high: v + Double(i) * 0.4 + 2)
        }
        guard let d = lever else { return (b, nil) }
        let l = base.enumerated().map { i, v in
            let r = min(1.0, Double(i + 1) / 7)
            let e = v + d * r
            return TrajectoryChart.Point(x: Double(i + 1), estimate: e, low: e - Double(i) * 0.4 - 2,
                                         high: e + Double(i) * 0.4 + 2)
        }
        return (b, l)
    }
    let trend = (1...22).map { 65 + Double($0) * 0.22 }
    let full = pts(trend, lever: 8)
    let bare = pts(trend, lever: nil)

    return VStack(spacing: 28) {
        TrajectoryChart(baseline: full.0, withLever: full.1, startValue: 65,
                        goal: 80, goalLabel: "meta 80", accent: InstrumentoTheme.base.dataHrv,
                        higherIsBetter: true, xStartLabel: "hoy", xEndLabel: "+22 d",
                        accessibilityText: "Como vas llegas a 70. Si cambias, 78.")
            .frame(height: 180)
        TrajectoryChart(baseline: bare.0, withLever: bare.1, startValue: 65,
                        goal: 80, goalLabel: "meta 80", accent: InstrumentoTheme.base.dataHrv,
                        higherIsBetter: true, xStartLabel: "hoy", xEndLabel: "+22 d",
                        accessibilityText: "Como vas llegas a 70.")
            .frame(height: 180)
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .environment(\.instrumentoTheme, .base)
}
#endif
