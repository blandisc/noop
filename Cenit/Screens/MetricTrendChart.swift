#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import Foundation

// MARK: - Reusable «selector de tiempo + gráfica» (FER-269)
//
// Every metric drill-down — the unified Detalle de Métrica (`MetricDetailScreen`), the sibling
// «Instrumento» screens (Strain / Recovery / Stress / Skin temp) and the Metric Explorer's detail —
// drew the SAME thing: a `SegmentedPillControl` (W/M/3M/6M/1Y/ALL) above a `TrendChart`, each screen
// re-deriving the identical window math (`Window` / `slice` / `effectiveRange` / `makeWindow` /
// `decimatedPoints`) and re-wiring the chart by hand. This file extracts both halves once:
//
//   • `MetricWindow` + `MetricWindowMath` — the window math, verbatim from the per-screen copies
//     (FER-216 / FER-219), now in one place. The parsed series (each `day` string → `Date` once) is
//     still owned and memoised by the screen; the math only reads it.
//   • `MetricTrendChart` — the view: the selector (optional) + the trend line, parameterised by a
//     style so each metric configures trace mode (raw vs. 7-day MA), domain, bands, alert, reference
//     line, etc. WITHOUT any `if metric == …` branch living inside the component.
//
// The screen still owns `@State range` (so blocks beyond the chart — the trend stat, VO₂max's change —
// can read the same selection) and computes the window ONCE in `body`; the component is handed that
// window and a binding to the range.

/// One render's window: the effective range, its rows/values, and whether it auto-widened because the
/// selected range held no points. Replaces the five identical per-screen `Window` structs. (FER-269)
struct MetricWindow {
    let range: ExploreRange
    let rows: [(day: String, value: Double)]
    let values: [Double]
    let fellBack: Bool
}

/// The shared W/M/3M/6M/1Y/ALL window math, lifted verbatim from the per-screen copies so every
/// drill-down derives its window identically (FER-216 auto-widen + FER-219 decimation). Pure: it reads
/// the screen's already-parsed series and never touches the database. (FER-269)
enum MetricWindowMath {
    /// One parsed series row: the `yyyy-MM-dd` key, its `Date` memoised once by the screen, and the value.
    typealias Parsed = [(day: String, date: Date?, value: Double)]

    /// Trailing-N-days slice for `r`, taken RELATIVE TO THE LATEST point (not "now"). Reads the memoized
    /// `date` from `parsed` — no `DateFormatter` work here.
    static func slice(_ parsed: Parsed, for r: ExploreRange) -> [(day: String, value: Double)] {
        guard let days = r.days else { return parsed.map { ($0.day, $0.value) } }
        guard let last = parsed.last?.date else { return [] }
        let cutoff = last.addingTimeInterval(-Double(days - 1) * 86_400)
        return parsed.compactMap { row in
            guard let d = row.date, d >= cutoff else { return nil }
            return (row.day, row.value)
        }
    }

    /// The selected range, or the smallest larger range whose window holds ≥1 point (Explorer auto-widen).
    static func effectiveRange(_ parsed: Parsed, selected: ExploreRange) -> ExploreRange {
        guard !parsed.isEmpty else { return selected }
        for r in selected.widening where !slice(parsed, for: r).isEmpty { return r }
        return .all
    }

    /// Compute the whole window ONCE per render and hand it to the blocks.
    static func make(_ parsed: Parsed, selected: ExploreRange) -> MetricWindow {
        let eff = effectiveRange(parsed, selected: selected)
        let rows = slice(parsed, for: eff)
        return MetricWindow(range: eff, rows: rows, values: rows.map(\.value), fellBack: eff != selected)
    }

    /// Build the chart's `[TrendPoint]`, decimating long series to ≤`maxPoints` for DRAWING only (FER-219):
    /// the stats above the chart still read the full series; this only thins what the line strokes. Short
    /// ranges (≤`maxPoints`) pass through one point per day, unchanged. Both value and date are bucketed
    /// with the SAME `n*b/maxPoints` partition `SeriesShape.decimate` uses, so each averaged value keeps a
    /// representative (bucket-center) date.
    static func decimatedPoints(rows: [(day: String, value: Double)], values: [Double], maxPoints: Int) -> [TrendPoint] {
        let n = Swift.min(rows.count, values.count)
        guard n > maxPoints, maxPoints > 1 else {
            return zip(rows, values).compactMap { row, value in
                // Anchor each day to NOON UTC (matching TodayView.loadTrend) so the local-zone axis/scrub
                // label doesn't slip to the previous day west of UTC — a 22-jun point read "21 jun" in CDMX
                // (UTC−6) because midnight-UTC fell on the prior local day. (date-mismatch detail vs summary)
                Repository.parseDayKey(row.day).map { TrendPoint(date: $0.addingTimeInterval(12 * 3600), value: value) }
            }
        }
        let decimated = SeriesShape.decimate(Array(values.prefix(n)), maxPoints: maxPoints)
        var out: [TrendPoint] = []
        out.reserveCapacity(decimated.count)
        for b in 0..<decimated.count {
            let lo = (n * b) / maxPoints
            let hi = (n * (b + 1)) / maxPoints
            let mid = Swift.min(lo + (hi - lo) / 2, n - 1)
            if let date = Repository.parseDayKey(rows[mid].day) {
                out.append(TrendPoint(date: date.addingTimeInterval(12 * 3600), value: decimated[b]))   // noon-UTC anchor (see above)
            }
        }
        return out
    }
}

// MARK: - The reusable view

/// The reusable «selector + gráfica»: an optional period picker above a `TrendChart`, driven by a
/// `MetricWindow` and a per-metric `Style`. The screen owns `@State range` and passes a binding; the
/// component renders the selector (when `showsSelector`), the auto-widen caption, and the line — or the
/// caller's `empty` content when the window holds ≤1 point. Everything that varies by metric (trace mode,
/// domain, bands, alert, reference line) is in `Style`, so there's no per-metric branch inside. (FER-269)
struct MetricTrendChart<Empty: View>: View {
    @Binding var range: ExploreRange
    let window: MetricWindow
    var theme: InstrumentoTheme
    /// Whether to draw the `SegmentedPillControl` + auto-widen caption above the chart. `MetricDetailScreen`
    /// keeps its selector in a separate (divider-separated) block, so it passes `false` here.
    var showsSelector: Bool = true
    let style: Style
    /// Shown in place of the chart when the window holds ≤1 point (each screen supplies its own well).
    @ViewBuilder var empty: () -> Empty

    /// Per-metric chart configuration — the knobs that used to be spelled out at each `TrendChart` call site.
    struct Style {
        /// Moving-average window for the plotted line; `nil` plots the raw values (SpO₂ / stress / skin temp).
        var smoothing: Int? = nil
        var gradient: Gradient
        var showsArea: Bool = true
        var height: CGFloat = 200
        /// Resolves the Y domain from the plotted (already-smoothed) line values; ignore the argument for a
        /// fixed domain (e.g. stress `0...3`).
        var valueRange: ([Double]) -> ClosedRange<Double>
        var valueFormat: (Double) -> String = { String(Int($0.rounded())) }
        /// Classification bands behind the line, resolved from the LAST plotted value so the active bracket
        /// matches what the chart actually draws (stress' Low/Moderate/High). Ignore the argument for fixed
        /// bands (skin temp's ±SD, SpO₂'s clinical zones).
        var bands: (Double) -> [TrendBand] = { _ in [] }
        /// The active band's hue, resolved from the same last plotted value.
        var bandColor: (Double) -> Color = { _ in .clear }
        var yAxisValues: [Double]? = nil
        /// Target automatic Y-tick count when `yAxisValues` is nil (band charts pass explicit ticks). Default
        /// 4; the detail «Media móvil» charts raise it so a wide range reads at finer increments. (Detalle)
        var yTickCount: Int = 4
        var alertThreshold: Double? = nil
        var alertColor: Color = .clear
        /// When true, the LAST plotted point (the right edge of the line = today / the most recent night)
        /// is emphasised with a larger filled dot — «el punto es hoy» in the redesigned vital detail. The
        /// caller can't pass an exact `TrendPoint` because the line is decimated internally, so the
        /// component marks `points.last` for it. (Detalle de Vital · narrativa)
        var marksLastPoint: Bool = false
        /// When true (and `marksLastPoint`), the last point is drawn as a HOLLOW ring rather than a filled
        /// dot — the F6b level pattern uses it to keep TODAY marked while you explore a level other than its
        /// own. (FER-571)
        var markedPointHollow: Bool = false
        /// The fill of a hollow marked point's centre — pass the sheet's paper so the ring reads cleanly. (FER-571)
        var markedPointRingFill: Color = .clear
        /// Draw bands without their in-plot label (and without the wide right gutter): the band reads as a
        /// quiet «your normal range» context behind the line, named in the caption / inline bar instead.
        var bandLabelsHidden: Bool = false
        /// A dashed horizontal reference line (e.g. skin-temp's «0 = your baseline»). `nil` = none.
        var referenceLine: Double? = nil
        var referenceLineColor: Color = .clear
        var accessibilityLabel: LocalizedStringKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsSelector {
                SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme) { $0.label }
                if window.fellBack {
                    Text("Showing the last \(window.rows.count) days")
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.warning)
                }
            }
            if window.values.count > 1 {
                chart
            } else {
                empty()
            }
        }
    }

    private var chart: some View {
        let lineValues = style.smoothing.map { SeriesShape.movingAverage(window.values, window: $0) } ?? window.values
        let points = MetricWindowMath.decimatedPoints(rows: window.rows, values: lineValues, maxPoints: 80)
        // The value the bands bracket against: the LAST plotted point (matching the old per-screen
        // `pts.last?.value ?? window.values.last`), so a decimated long range still highlights the right band.
        let lastPlotted = points.last?.value ?? lineValues.last ?? 0
        return TrendChart(
            points: points,
            gradient: style.gradient,
            valueRange: style.valueRange(lineValues),
            showsArea: style.showsArea,
            height: style.height,
            showsScrub: true,
            valueFormat: style.valueFormat,
            axisLabelColor: theme.inkTertiary,
            gridLineColor: theme.hairline,
            bands: style.bands(lastPlotted),
            bandColor: style.bandColor(lastPlotted),
            yAxisValues: style.yAxisValues,
            alertThreshold: style.alertThreshold,
            alertColor: style.alertColor,
            referenceLine: style.referenceLine,
            referenceLineColor: style.referenceLineColor,
            markedPoint: style.marksLastPoint ? points.last : nil,
            markedPointHollow: style.markedPointHollow,
            markedPointRingFill: style.markedPointRingFill,
            bandLabelsHidden: style.bandLabelsHidden,
            yTickCount: style.yTickCount
        )
        .accessibilityElement()
        .accessibilityLabel(Text(style.accessibilityLabel))
    }
}
#endif
