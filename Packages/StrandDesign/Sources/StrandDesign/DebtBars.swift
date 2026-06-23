import SwiftUI
import Charts

// MARK: - DebtBars (per-night sleep-debt bars)
//
// A sibling of `TrendChart` for a signed, per-night quantity: one bar per night measured against your
// sleep need (the zero rule). Bars below the rule are a debt (you slept less than you need); bars above
// are a surplus. It scrubs exactly like `TrendChart` — drag a finger (iOS) or hover (macOS) to highlight
// a night and read a tooltip with how much you slept and that night's debt — by reusing the shared
// `scrubGesture` + `CrosshairRule` + `ChartTooltip` toolkit, so the affordance feels identical. (FER-249)
//
// Design tokens only: the caller passes the data hues (`deficitColor` / `surplusColor`), rule and axis
// inks. Number/date formatting is injected as closures (like TrendChart) so locale + units stay out of
// the design system.

/// One night for `DebtBars`.
public struct DebtNightBar: Identifiable, Equatable {
    public let id = UUID()
    public var date: Date
    /// Sleep minus need, in minutes (signed): `< 0` = fell short (debt), `>= 0` = beat it (surplus).
    public var vsNeedMin: Double
    /// Total minutes asleep that night — feeds the tooltip's "slept …" line.
    public var sleptMin: Double

    public init(date: Date, vsNeedMin: Double, sleptMin: Double) {
        self.date = date
        self.vsNeedMin = vsNeedMin
        self.sleptMin = sleptMin
    }
}

public struct DebtBars: View {

    public var nights: [DebtNightBar]
    /// Hue for bars below the rule (a debt) and above it (a surplus).
    public var deficitColor: Color
    public var surplusColor: Color
    /// The zero-rule (your need) line colour.
    public var ruleColor: Color
    /// Axis tick-label + optional rule-label ink.
    public var axisLabelColor: Color
    public var height: CGFloat
    /// Optional label drawn at the rule (e.g. "your need"); `nil` draws the bare line.
    public var ruleLabel: String?
    /// X-axis weekday label for a night's date (e.g. the narrow "M").
    public var weekdayLabel: (Date) -> String
    /// Tooltip's bold line — the night's debt/surplus, formatted from `vsNeedMin`.
    public var valueFormat: (Double) -> String
    /// Tooltip's secondary line — how much you slept, formatted from `sleptMin`.
    public var sleptFormat: (Double) -> String

    public init(
        nights: [DebtNightBar],
        deficitColor: Color,
        surplusColor: Color,
        ruleColor: Color,
        axisLabelColor: Color,
        height: CGFloat = 96,
        ruleLabel: String? = nil,
        weekdayLabel: @escaping (Date) -> String,
        valueFormat: @escaping (Double) -> String,
        sleptFormat: @escaping (Double) -> String
    ) {
        self.nights = nights.sorted { $0.date < $1.date }
        self.deficitColor = deficitColor
        self.surplusColor = surplusColor
        self.ruleColor = ruleColor
        self.axisLabelColor = axisLabelColor
        self.height = height
        self.ruleLabel = ruleLabel
        self.weekdayLabel = weekdayLabel
        self.valueFormat = valueFormat
        self.sleptFormat = sleptFormat
    }

    @State private var hoverX: CGFloat? = nil

    public var body: some View {
        Chart {
            RuleMark(y: .value("Need", 0))
                .foregroundStyle(ruleColor)
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                    if let ruleLabel {
                        Text(ruleLabel)
                            .font(StrandFont.footnote)
                            .foregroundStyle(axisLabelColor)
                    }
                }
            ForEach(nights) { n in
                BarMark(
                    x: .value("Night", n.date, unit: .day),
                    y: .value("vs need", n.vsNeedMin / 60)
                )
                .foregroundStyle(n.vsNeedMin < 0 ? deficitColor : surplusColor)
                .cornerRadius(2)
            }
        }
        // Snap, don't morph, when the week's data changes (mirrors TrendChart). (FER-249)
        .animation(.none, value: nights)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                if let d = value.as(Date.self) {
                    AxisValueLabel {
                        Text(weekdayLabel(d))
                            .font(StrandFont.footnote)
                            .foregroundStyle(axisLabelColor)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = geo[proxy.plotAreaFrame]
                ZStack(alignment: .topLeading) {
                    // Full-bleed transparent hit target so the scrub starts on first touch (same fix as
                    // TrendChart, #118).
                    Color.clear

                    if let hx = hoverX,
                       let n = nearestNight(toX: hx, proxy: proxy, plot: plot),
                       let px = proxy.position(forX: n.date) {
                        let cx = px + plot.minX
                        let accent = n.vsNeedMin < 0 ? deficitColor : surplusColor

                        CrosshairRule(x: cx, height: geo.size.height)

                        PositionedTooltip(
                            anchor: CGPoint(x: cx, y: plot.minY + 8),
                            container: geo.size,
                            tooltip: ChartTooltip(
                                value: valueFormat(n.vsNeedMin),
                                label: sleptFormat(n.sleptMin),
                                accent: accent
                            )
                        )
                    }
                }
                .animation(StrandMotion.fade, value: hoverX)
                .contentShape(Rectangle())
                .scrubGesture(enabled: true, hoverX: $hoverX)
            }
        }
        .frame(height: height)
    }

    /// The night whose bar x-position is nearest the cursor. `position(forX:)` is plot-relative, so the
    /// cursor is compared in the same space (`hoverX - plot.minX`). (FER-249)
    private func nearestNight(toX x: CGFloat, proxy: ChartProxy, plot: CGRect) -> DebtNightBar? {
        guard !nights.isEmpty else { return nil }
        let relX = x - plot.minX
        return nights.min(by: { a, b in
            let ax = proxy.position(forX: a.date) ?? 0
            let bx = proxy.position(forX: b.date) ?? 0
            return abs(ax - relX) < abs(bx - relX)
        })
    }
}

#if DEBUG
#Preview("DebtBars") {
    let cal = Calendar(identifier: .gregorian)
    let base = Date(timeIntervalSince1970: 1_718_000_000)
    let week: [DebtNightBar] = (0..<7).map { i in
        let vs = [-30.0, -132, 18, -66, -24, -36, -30][i]
        return DebtNightBar(date: cal.date(byAdding: .day, value: i, to: base)!,
                            vsNeedMin: vs, sleptMin: 450 + vs)
    }
    func hm(_ m: Double) -> String {
        let v = Int(abs(m).rounded()); return v >= 60 ? "\(v / 60)h \(v % 60)m" : "\(v)m"
    }
    return DebtBars(
        nights: week,
        deficitColor: StrandPalette.strainColor(14),
        surplusColor: StrandPalette.recoveryColor(88),
        ruleColor: InstrumentoTheme.base.hairlineStrong,
        axisLabelColor: InstrumentoTheme.base.inkTertiary,
        ruleLabel: "your need",
        weekdayLabel: { d in let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEEE"); return f.string(from: d) },
        valueFormat: { $0 < 0 ? "−\(hm($0))" : "+\(hm($0))" },
        sleptFormat: { "slept \(hm($0))" }
    )
    .padding(24)
    .frame(width: 340, height: 160)
    .background(InstrumentoTheme.base.paper)
    .preferredColorScheme(.light)
}
#endif
