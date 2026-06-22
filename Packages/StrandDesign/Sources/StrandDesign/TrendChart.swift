import SwiftUI
import Charts

// MARK: - Trend Chart (§9.4 Trends)
//
// A line/area chart whose line is gradient-stroked by value — reusable for
// recovery / HRV / RHR / strain trends. The gradient defaults to the recovery
// scale (so a recovery-over-time line travels indigo → mint by daily score), but
// any gradient + value-range can be supplied for HRV/RHR/etc.

/// One point on a trend line.
public struct TrendPoint: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

// MARK: - Classification bands (FER-244)

/// One classification band drawn behind a trend line — e.g. sleep "Optimal 7–9 h" or stress "Medium".
/// Bounds are a half-open interval `[lower, upper)`; `nil` = open on that side. Only the band the latest
/// value falls into is shaded (the "active" bracket); the rest are hinted by the axis grid lines.
public struct TrendBand: Identifiable, Equatable {
    public let id = UUID()
    public var label: LocalizedStringKey
    public var lower: Double?
    public var upper: Double?
    public var isActive: Bool

    public init(label: LocalizedStringKey, lower: Double?, upper: Double?, isActive: Bool = false) {
        self.label = label
        self.lower = lower
        self.upper = upper
        self.isActive = isActive
    }

    /// True when `value` falls in this band's half-open interval `[lower, upper)`.
    public func contains(_ value: Double) -> Bool {
        (lower == nil || value >= lower!) && (upper == nil || value < upper!)
    }
}

/// Pure band math, kept free of SwiftUI so it can be unit-tested (FER-244).
public enum TrendBands {
    /// Index of the band containing `value`, or `nil` if none does.
    public static func index(containing value: Double, in bands: [TrendBand]) -> Int? {
        bands.firstIndex { $0.contains(value) }
    }

    /// The band the **last** value falls into, plus how many of `values` land in that same band.
    /// `nil` when there are no values or the last value matches no band.
    public static func activeBand(values: [Double], bands: [TrendBand]) -> (index: Int, count: Int)? {
        guard let last = values.last, let idx = index(containing: last, in: bands) else { return nil }
        let band = bands[idx]
        let count = values.reduce(0) { $0 + (band.contains($1) ? 1 : 0) }
        return (idx, count)
    }
}

public struct TrendChart: View {

    public var points: [TrendPoint]
    /// The gradient the line/area is stroked with (defaults to the recovery scale).
    public var gradient: Gradient
    /// The value range mapped onto the gradient (0 → bottom color, max → top color).
    public var valueRange: ClosedRange<Double>
    /// Whether to draw the soft area fill below the line.
    public var showsArea: Bool
    public var height: CGFloat
    /// Whether hovering reveals a crosshair + tooltip for the nearest point.
    public var showsScrub: Bool
    /// Formats a point's value for the tooltip's bold line (default: rounded int).
    public var valueFormat: (Double) -> String
    /// Formats a point's date for the tooltip's secondary line.
    public var dateFormat: (Date) -> String
    /// Axis tick-label color. Defaults to the dark palette's tertiary text; light-theme callers
    /// (the «Instrumento» metric sheet) pass a paper-legible ink so the labels clear contrast on
    /// warm paper. (FER-162)
    public var axisLabelColor: Color
    /// Axis grid-line color (drawn at 0.4 opacity). Defaults to the dark hairline. (FER-162)
    public var gridLineColor: Color
    /// Classification bands to draw behind the line; the active one is shaded. Empty = no bands (the
    /// chart behaves exactly as before). (FER-244)
    public var bands: [TrendBand]
    /// The hue of the active band's shading, label and edge lines. (FER-244)
    public var bandColor: Color
    /// Explicit Y-axis tick values (e.g. the band thresholds). `nil` = automatic ticks. (FER-244)
    public var yAxisValues: [Double]?
    /// When set, point marks whose value is BELOW this threshold are drawn in `alertColor` instead of
    /// the gradient — to flag clinically-low readings (e.g. SpO₂ nights under 95%). `nil` = off, every
    /// point keeps its gradient colour. (FER-252)
    public var alertThreshold: Double?
    /// The hue for sub-`alertThreshold` point marks. (FER-252)
    public var alertColor: Color
    /// A dashed horizontal reference line at this value (e.g. the night's resting HR under the day's
    /// HR curve). `nil` = no line. (FER-253)
    public var referenceLine: Double?
    /// The hue for the dashed reference line. (FER-253)
    public var referenceLineColor: Color
    /// A single point to emphasise with a larger filled dot (e.g. the day's peak HR). `nil` = none. (FER-253)
    public var markedPoint: TrendPoint?
    /// When true, bands are drawn (shaded fill + edge lines) WITHOUT their right-aligned text label, and
    /// the wide right gutter that label needs is dropped. For the redesigned vital detail, where the band
    /// is a quiet «your normal range» context behind the line and is named in the caption / inline bar, not
    /// on the plot. (Detalle de Vital · narrativa)
    public var bandLabelsHidden: Bool

    public init(
        points: [TrendPoint],
        gradient: Gradient = StrandPalette.recoveryGradient,
        valueRange: ClosedRange<Double> = 0...100,
        showsArea: Bool = true,
        height: CGFloat = 220,
        showsScrub: Bool = true,
        valueFormat: @escaping (Double) -> String = { String(Int($0.rounded())) },
        dateFormat: @escaping (Date) -> String = { TrendChart.defaultDateString($0) },
        axisLabelColor: Color = InstrumentoTheme.base.inkTertiary,
        gridLineColor: Color = InstrumentoTheme.base.hairline,
        bands: [TrendBand] = [],
        bandColor: Color = .clear,
        yAxisValues: [Double]? = nil,
        alertThreshold: Double? = nil,
        alertColor: Color = .clear,
        referenceLine: Double? = nil,
        referenceLineColor: Color = .clear,
        markedPoint: TrendPoint? = nil,
        bandLabelsHidden: Bool = false
    ) {
        self.points = points.sorted { $0.date < $1.date }
        self.gradient = gradient
        self.valueRange = valueRange
        self.showsArea = showsArea
        self.height = height
        self.showsScrub = showsScrub
        self.valueFormat = valueFormat
        self.dateFormat = dateFormat
        self.axisLabelColor = axisLabelColor
        self.gridLineColor = gridLineColor
        self.bands = bands
        self.bandColor = bandColor
        self.yAxisValues = yAxisValues
        self.alertThreshold = alertThreshold
        self.alertColor = alertColor
        self.referenceLine = referenceLine
        self.referenceLineColor = referenceLineColor
        self.markedPoint = markedPoint
        self.bandLabelsHidden = bandLabelsHidden
    }

    /// The x-position the cursor is hovering, in chart-local coordinates.
    @State private var hoverX: CGFloat? = nil

    private static let sharedDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()

    /// Default tooltip date format ("EEE d MMM"), exposed so it can seed the
    /// `dateFormat` default argument.
    public static func defaultDateString(_ date: Date) -> String {
        sharedDateFormatter.string(from: date)
    }

    /// The point nearest a given chart-local x, using the proxy to map back.
    private func nearestPoint(toX x: CGFloat, proxy: ChartProxy, plot: CGRect) -> TrendPoint? {
        guard !points.isEmpty else { return nil }
        // Map the cursor x (relative to the plot area) back to a Date.
        let relX = x - plot.minX
        guard let date: Date = proxy.value(atX: relX) else { return nil }
        // Find the TrendPoint whose date is closest.
        return points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    // Map data values onto the unit interval for gradient stops.
    private func unit(_ value: Double) -> Double {
        let lo = valueRange.lowerBound, hi = valueRange.upperBound
        guard hi > lo else { return 0 }
        return min(max((value - lo) / (hi - lo), 0), 1)
    }

    // A vertical gradient keyed to the value axis so the stroke color tracks value.
    private var valueGradient: LinearGradient {
        LinearGradient(gradient: gradient, startPoint: .bottom, endPoint: .top)
    }

    public var body: some View {
        Chart {
            // A quiet dashed rule under the curve (e.g. the night's resting HR). Drawn first so the
            // line/area sit on top of it. (FER-253)
            if let ref = referenceLine {
                RuleMark(y: .value("Reference", ref))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(referenceLineColor)
            }
            if showsArea {
                ForEach(points) { p in
                    AreaMark(
                        x: .value("Date", p.date),
                        // Anchor the fill's floor to the value domain's lower bound, NOT the implicit
                        // zero baseline. With a tight domain (e.g. HR 64…145) zero sits below the
                        // domain, so a plain `y:` AreaMark fills clear to the plot's bottom edge —
                        // straight behind the X-axis hour labels, tinting them. Pinning yStart to the
                        // floor stops the fill at the data region; the Y-scale's startPadding then
                        // leaves a clean band below it for the labels. (FER-82)
                        yStart: .value("Floor", valueRange.lowerBound),
                        yEnd: .value("Value", p.value)
                    )
                    // monotone, NOT catmullRom: Catmull-Rom overshoots past the data on
                    // tightly-oscillating daily signals (resting HR 50↔55, strain), dipping the
                    // curve below the value domain so the area/line bled out the bottom of the
                    // plot and dripped over the footer (#trends-bleed). Monotone cubic stays
                    // within each segment's endpoints — same smooth look, no overshoot.
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                StrandPalette.sample(stops: gradient.toStops(), at: unit(averageValue)).opacity(0.28),
                                Color.clear
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            }
            ForEach(points) { p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Value", p.value)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(valueGradient)
            }
            // Per-point dots only on short series. On a dense line (a long range — months/year, up to
            // ~365 days) a mark per point both clutters the line and costs Charts a draw per sample, so
            // long ranges show line + area only. Short ranges (week/month) keep the dots unchanged. (FER-219)
            if points.count <= 60 {
                ForEach(points) { p in
                    PointMark(
                        x: .value("Date", p.date),
                        y: .value("Value", p.value)
                    )
                    .symbolSize(18)
                    // Flag clinically-low points (e.g. SpO₂ < 95%) in the alert hue; everything at or
                    // above the threshold keeps its gradient colour. (FER-252)
                    .foregroundStyle(
                        (alertThreshold.map { p.value < $0 } ?? false)
                            ? alertColor
                            : StrandPalette.sample(stops: gradient.toStops(), at: unit(p.value))
                    )
                }
            }
            // A single emphasised dot at a caller-chosen point (e.g. the day's peak). Larger than the
            // per-point dots, in the line's hue, so it reads as "this is the moment". (FER-253)
            if let peak = markedPoint {
                PointMark(
                    x: .value("Date", peak.date),
                    y: .value("Value", peak.value)
                )
                .symbolSize(70)
                .foregroundStyle(StrandPalette.sample(stops: gradient.toStops(), at: unit(peak.value)))
            }
        }
        // No draw-on / interpolation animation when the data changes (switching period rebuilds the
        // whole series): the new range should snap in, not morph point-by-point — that interpolation is
        // what made the chart "stick" while it rebuilt long ranges. (FER-219)
        .animation(.none, value: points)
        // Reserve a clean band below the fill for the X-axis labels (startPadding on the Y-scale's
        // bottom), and inset the X-scale's trailing edge so the last label isn't clipped. (FER-82)
        .chartYScale(domain: valueRange, range: .plotDimension(startPadding: NoopMetrics.chartXLabelBand, endPadding: 0))
        // With LABELLED bands, reserve a wider right gutter so the band labels sit clear of the line; when
        // band labels are hidden (the vital-detail context band) keep the normal trailing inset. (FER-244)
        .chartXScale(range: .plotDimension(startPadding: 0, endPadding: (bands.isEmpty || bandLabelsHidden) ? NoopMetrics.chartXTrailingInset : 64))
        .chartXAxis {
            // Explicit ticks evenly spread across the ACTUAL data span — not Charts' `.automatic`, which
            // snaps dates to calendar boundaries (e.g. weekly Sundays) and so bunched the only two ticks
            // that fell inside a 14-day window into the right half, leaving the left blank. Three ticks
            // at 0 / 50 / 100 % of the span always span the full width and read evenly. (FER-458)
            AxisMarks(values: xAxisTicks) { value in
                AxisGridLine().foregroundStyle(gridLineColor.opacity(0.4))
                AxisValueLabel(anchor: xLabelAnchor(value.index, count: value.count)) {
                    if let d = value.as(Date.self) {
                        Text(xAxisLabel(d))
                    }
                }
                .foregroundStyle(axisLabelColor)
                .font(StrandFont.footnote)
            }
        }
        .chartYAxis {
            // Explicit ticks at the band thresholds when bands are present (the grid lines double as the
            // soft "neighbour" hints); automatic ticks otherwise. (FER-244)
            if let yv = yAxisValues {
                AxisMarks(position: .leading, values: yv) { _ in
                    AxisGridLine().foregroundStyle(gridLineColor.opacity(0.4))
                    AxisValueLabel().foregroundStyle(axisLabelColor)
                        .font(StrandFont.footnote)
                }
            } else {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(gridLineColor.opacity(0.4))
                    AxisValueLabel().foregroundStyle(axisLabelColor)
                        .font(StrandFont.footnote)
                }
            }
        }
        .chartBackground { proxy in
            GeometryReader { geo in
                let plot = geo[proxy.plotAreaFrame]
                ZStack(alignment: .topLeading) {
                    ForEach(bands) { band in
                        bandLayer(band, proxy: proxy, plot: plot)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = geo[proxy.plotAreaFrame]
                // The datum currently under the finger (nil when not scrubbing). Drives the selection
                // haptic: `.onChange` fires once per snap onto a new point (FER-131 handoff · 10).
                let snappedIndex: Int? = (showsScrub ? hoverX : nil).flatMap { hx in
                    nearestPoint(toX: hx, proxy: proxy, plot: plot).flatMap { points.firstIndex(of: $0) }
                }
                ZStack(alignment: .topLeading) {
                    // A full-bleed transparent layer so the overlay (and its scrub gesture) covers the
                    // WHOLE plot from the first touch. Without it the ZStack only has the
                    // crosshair+tooltip as children — which exist solely WHILE scrubbing — so before
                    // the first touch the ZStack is 0×0 and `.contentShape` had no hittable area, so
                    // the drag never started (the "scrub does nothing on iOS" bug). Color.clear is
                    // greedy and fills the GeometryReader, giving the gesture a full-size target. (#118)
                    Color.clear
                        .onChange(of: snappedIndex) { idx in if idx != nil { ChartHaptics.datumChanged() } }

                    if showsScrub,
                       let hx = hoverX,
                       let p = nearestPoint(toX: hx, proxy: proxy, plot: plot),
                       let px = proxy.position(forX: p.date),
                       let py = proxy.position(forY: p.value) {
                        let cx = px + plot.minX
                        let cy = py + plot.minY
                        let color = StrandPalette.sample(stops: gradient.toStops(), at: unit(p.value))

                        // Vertical crosshair at the nearest x.
                        CrosshairRule(x: cx, height: geo.size.height)

                        // Highlighted dot on the line.
                        HighlightDot(color: color)
                            .position(x: cx, y: cy)

                        // Tooltip near the point, kept in bounds.
                        PositionedTooltip(
                            anchor: CGPoint(x: cx, y: cy),
                            container: geo.size,
                            tooltip: ChartTooltip(
                                value: valueFormat(p.value),
                                label: dateFormat(p.date),
                                accent: color
                            )
                        )
                    }
                }
                .animation(StrandMotion.fade, value: hoverX)
                .contentShape(Rectangle())
                .scrubGesture(enabled: showsScrub, hoverX: $hoverX)
            }
        }
        .frame(height: height)
    }

    private var averageValue: Double {
        guard !points.isEmpty else { return valueRange.lowerBound }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    // MARK: - X-axis ticks (FER-457 fix)

    /// Three tick dates at 0 / 50 / 100 % of the data's actual time span. Anchored to the data — not the
    /// calendar — so the labels always span the chart's full width and read evenly, whatever the range.
    private var xAxisTicks: [Date] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        let span = last.timeIntervalSince(first)
        guard span > 0 else { return [first] }
        return [0.0, 0.5, 1.0].map { first.addingTimeInterval(span * $0) }
    }

    /// Keep the first label leading-aligned and the last trailing-aligned so neither clips at the plot
    /// edge (the centre one stays centred); the gridline still sits exactly on the tick.
    private func xLabelAnchor(_ index: Int, count: Int) -> UnitPoint {
        if index == 0 { return .topLeading }
        if index == count - 1 { return .topTrailing }
        return .top
    }

    /// Label text for an x tick, formatted by how wide the window is: intraday → hour, up to a few months
    /// → day + month, longer → month + year. (`Date.FormatStyle` would localise ordering, but a cached
    /// formatter keeps it cheap across the three ticks.)
    private func xAxisLabel(_ date: Date) -> String {
        let span = (points.last?.date.timeIntervalSince(points.first?.date ?? date)) ?? 0
        let f = TrendChart.axisFormatter
        if span <= 36 * 3600 {
            f.setLocalizedDateFormatFromTemplate("ha")
        } else if span <= 300 * 86_400 {
            f.setLocalizedDateFormatFromTemplate("dMMM")
        } else {
            f.setLocalizedDateFormatFromTemplate("MMMyy")
        }
        return f.string(from: date)
    }

    private static let axisFormatter = DateFormatter()

    /// Draws one classification band behind the line: the active band gets a soft fill + coloured edge
    /// lines (the "bracket"); every band wide enough gets a right-aligned label (active in the band hue,
    /// the rest in quiet ink). Open bounds clamp to the value domain. (FER-244)
    @ViewBuilder
    private func bandLayer(_ band: TrendBand, proxy: ChartProxy, plot: CGRect) -> some View {
        let topV = min(band.upper ?? valueRange.upperBound, valueRange.upperBound)
        let botV = max(band.lower ?? valueRange.lowerBound, valueRange.lowerBound)
        if let pTop = proxy.position(forY: topV), let pBot = proxy.position(forY: botV) {
            let yTop = plot.minY + min(pTop, pBot)
            let h = abs(pBot - pTop)
            if band.isActive {
                Rectangle()
                    .fill(bandColor.opacity(0.16))
                    .frame(width: plot.width, height: h)
                    .offset(x: plot.minX, y: yTop)
                Rectangle()
                    .fill(bandColor.opacity(0.5))
                    .frame(width: plot.width, height: 1)
                    .offset(x: plot.minX, y: yTop)
                Rectangle()
                    .fill(bandColor.opacity(0.5))
                    .frame(width: plot.width, height: 1)
                    .offset(x: plot.minX, y: yTop + h - 1)
            }
            // Every band tall enough gets a label; the ACTIVE band always gets one even when it's too
            // thin to clear the height test (e.g. sleep's 1-hour "Adequate" 6–7 h band) — otherwise the
            // one band you most need named is the one that goes unlabelled. The active label is also
            // weightier so "which band am I in" reads at a glance. (FER-249)
            if !bandLabelsHidden, h >= 16 || band.isActive {
                Text(band.label)
                    .font(StrandFont.footnote)
                    .fontWeight(band.isActive ? .semibold : .regular)
                    .lineLimit(1)
                    .foregroundStyle(band.isActive ? bandColor : axisLabelColor.opacity(0.8))
                    .frame(width: plot.width - 6, alignment: .trailing)
                    .offset(x: plot.minX, y: yTop + h / 2 - 8)
            }
        }
    }
}

// MARK: - Platform scrub gesture

// Internal (not file-private) so sibling charts in the package — e.g. `DebtBars` — share the exact
// same finger-drag / hover affordance instead of re-implementing it. (FER-249)
extension View {
    /// Attaches the chart-scrub affordance: `DragGesture` on iOS (finger drag, no minimum
    /// distance so the crosshair appears on first touch), `onContinuousHover` on macOS
    /// (pointer hover). Both update the `hoverX` binding so the same crosshair + tooltip
    /// overlay renders on both platforms without duplication.
    ///
    /// On iOS, `.highPriorityGesture()` is intentional: these charts live inside the sheet's
    /// ScrollView, and a plain `.gesture()` loses the touch to the ScrollView's vertical pan, so
    /// the scrub never started. `.highPriorityGesture` makes the scrub win the touch over the
    /// parent scroll while the finger is on the chart (the user can still scroll from anywhere
    /// else in the sheet). With `minimumDistance: 0` the crosshair appears on first contact. (#118)
    ///
    /// Position updates use a non-animating Transaction to prevent SwiftUI Charts from
    /// re-running its draw-on animation when `hoverX` changes mid-gesture (#104).
    @ViewBuilder
    func scrubGesture(enabled: Bool, hoverX: Binding<CGFloat?>) -> some View {
        #if os(iOS)
        self.highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard enabled else { return }
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) { hoverX.wrappedValue = v.location.x }
                }
                .onEnded { _ in
                    guard enabled else { return }
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) { hoverX.wrappedValue = nil }
                }
        )
        #else
        self.onContinuousHover(coordinateSpace: .local) { phase in
            guard enabled else { return }
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                switch phase {
                case .active(let location): hoverX.wrappedValue = location.x
                case .ended:               hoverX.wrappedValue = nil
                }
            }
        }
        #endif
    }
}

// MARK: - Gradient → stops bridge

extension Gradient {
    /// Reconstruct ordered stops from a Gradient. SwiftUI does not expose `.stops`
    /// directly on all paths, so we use the public `stops` mirror when present.
    func toStops() -> [Gradient.Stop] {
        // `Gradient.stops` is public on macOS 13+; expose for our sampler.
        self.stops
    }
}

#if DEBUG
private func sampleTrend(days: Int, base: Double, swing: Double) -> [TrendPoint] {
    let cal = Calendar.current
    let today = Date()
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = base + swing * sin(Double(i) / 3.0) + Double((i * 17) % 9) - 4
        return TrendPoint(date: date, value: max(0, v))
    }
}

#Preview("TrendChart — recovery") {
    VStack(alignment: .leading, spacing: 12) {
        Text("Recovery — 30 days").strandOverline()
        Text("Hover the line: crosshair + dot + date/value tooltip.")
            .font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
        TrendChart(points: sampleTrend(days: 30, base: 62, swing: 22))
    }
    .padding(28)
    .frame(width: 720, height: 340)
    .background(InstrumentoTheme.base.paper)
    .preferredColorScheme(.dark)
}

#Preview("TrendChart — HRV") {
    VStack(alignment: .leading, spacing: 12) {
        Text("HRV (ms) — 30 days").strandOverline()
        Text("Hover to read each day's HRV in ms.")
            .font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
        TrendChart(
            points: sampleTrend(days: 30, base: 58, swing: 14),
            gradient: StrandPalette.recoveryGradient,
            valueRange: 20...100,
            showsArea: true,
            valueFormat: { "\(Int($0.rounded())) ms" }
        )
    }
    .padding(28)
    .frame(width: 720, height: 340)
    .background(InstrumentoTheme.base.paper)
    .preferredColorScheme(.dark)
}
#endif
