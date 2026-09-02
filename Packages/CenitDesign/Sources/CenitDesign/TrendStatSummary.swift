import SwiftUI

// MARK: - Trend stat summary (FER-250)
//
// The single, shared replacement for the per-screen "Average · Lowest · Highest"
// strip (and Recovery's five-column Avg · Median · Min · Max · σ). That egalitarian
// row read as a generic dashboard: three co-equal numbers with technical labels and
// no good/bad meaning — "Lowest 0.1" tells a non-technical user nothing.
//
// This applies the «Instrumento» hierarchy instead:
//   • the AVERAGE is the one protagonist number (still subordinate to the screen's
//     own hero), because the typical value matters more than a single day's extreme;
//   • the month-over-month change becomes a coloured CHIP — green when the change
//     moves in the metric's good direction, amber when bad, quiet ink when the metric
//     has no good/bad direction (strain) or the month is flat;
//   • the extremes collapse into one quiet "Varied between X and Y" range line.
//
// Polarity is the one piece of domain knowledge the caller supplies: stress / resting
// HR fall (lowerIsBetter), HRV / sleep / recovery rise (higherIsBetter), strain is
// neutral. Color only ever lands on the chip (the measured change), never on chrome.
// Paints with `LiquidColor` (FER-320).

public struct TrendStatSummary: View {

    /// Which direction of change is "good" for this metric — drives the chip colour.
    public enum Polarity: Sendable {
        case higherIsBetter   // HRV, sleep duration, recovery
        case lowerIsBetter    // stress, resting HR
        case neutral          // strain — more isn't inherently good or bad
    }

    /// The length of the period the change compares against — drives the chip wording ("vs last week" /
    /// "vs last quarter" …) so it tracks the selected range instead of always saying "month". (FER-264)
    public enum ComparisonPeriod: Sendable {
        case week, month, quarter, halfYear, year
    }

    private let average: String
    private let unit: String?
    private let pctChange: Double?
    private let absoluteChange: Double?
    private let polarity: Polarity
    private let period: ComparisonPeriod
    private let rangeLow: String
    private let rangeHigh: String

    /// - Parameters:
    ///   - average: the period mean, already formatted to the metric's precision (no unit).
    ///   - unit: optional unit shown small next to the number (e.g. "ms", "h"); nil for unitless indices.
    ///   - pctChange: signed period-over-period % change in the mean; nil when there's no previous period.
    ///   - absoluteChange: opt-in alternative to `pctChange` — a signed period-over-period change expressed
    ///     in the metric's OWN units (rendered at one decimal + `unit`, e.g. "0.1 °C vs last month"). Use it
    ///     for metrics whose mean sits near zero, where a percentage is unstable/misleading (e.g. a skin-
    ///     temperature deviation). When non-nil it drives the chip and `pctChange` is ignored. (FER-256)
    ///   - polarity: which direction of change is good — colours the chip.
    ///   - period: the length of the period being compared, which drives the chip wording ("vs last week"
    ///     / "vs last quarter" …). Defaults to `.month`. (FER-264)
    ///   - rangeLow / rangeHigh: the period min and max, already formatted (bake the unit into rangeHigh
    ///     when you want it shown, e.g. "62 ms").
    ///   - theme: ignored for painting (LiquidColor). Kept for call-site compatibility (FER-320).
    public init(average: String,
                unit: String? = nil,
                pctChange: Double?,
                absoluteChange: Double? = nil,
                polarity: Polarity,
                period: ComparisonPeriod = .month,
                rangeLow: String,
                rangeHigh: String,
                theme: InstrumentoTheme = .base) {
        self.average = average
        self.unit = unit
        self.pctChange = pctChange
        self.absoluteChange = absoluteChange
        self.polarity = polarity
        self.period = period
        self.rangeLow = rangeLow
        self.rangeHigh = rangeHigh
        _ = theme
    }

    /// The signed change that drives the chip — the absolute delta when given, else the percentage.
    private var changeValue: Double? { absoluteChange ?? pctChange }

    /// A change too small to matter reads as no movement — say "Stable" instead of "0". Thresholds differ
    /// by mode: under ±1% for a percentage, under ±0.05 (rounds to 0.0) for a one-decimal absolute delta.
    /// When there's no previous month at all the chip is hidden entirely rather than faking "Stable".
    private var isFlat: Bool {
        if let absoluteChange { return abs(absoluteChange) < 0.05 }
        return pctChange.map { abs($0) < 1 } ?? false
    }

    /// Green when the change moves the good way, amber when the bad way; quiet ink when flat or neutral.
    private var changeColor: Color {
        guard !isFlat, let v = changeValue else { return LiquidColor.tinta700 }
        switch polarity {
        case .neutral:        return LiquidColor.tinta700
        case .higherIsBetter: return v > 0 ? LiquidColor.verdePrimario : LiquidColor.atencionTexto
        case .lowerIsBetter:  return v < 0 ? LiquidColor.verdePrimario : LiquidColor.atencionTexto
        }
    }

    /// "10% vs last week" / "0.1 °C vs last quarter" (String-interpolated so each key is "%@ vs last …",
    /// which localizes — the arrow already carries the sign, FER-247), or "Stable this …" when flat. The
    /// period suffix tracks the selected range instead of always saying "month". (FER-264)
    private var chipText: LocalizedStringKey {
        guard !isFlat, let v = changeValue else { return flatText }
        let magnitude: String
        if absoluteChange != nil {
            let mag = String(format: "%.1f", abs(v))
            magnitude = unit.map { "\(mag) \($0)" } ?? mag
        } else {
            magnitude = "\(Int(abs(v).rounded()))%"
        }
        switch period {
        case .week:     return "\(magnitude) vs last week"
        case .month:    return "\(magnitude) vs last month"
        case .quarter:  return "\(magnitude) vs last quarter"
        case .halfYear: return "\(magnitude) vs the previous 6 months"
        case .year:     return "\(magnitude) vs last year"
        }
    }

    /// "Stable this week / month / quarter / …" — the no-movement copy, period-aware like the chip. (FER-264)
    private var flatText: LocalizedStringKey {
        switch period {
        case .week:     return "Stable this week"
        case .month:    return "Stable this month"
        case .quarter:  return "Stable this quarter"
        case .halfYear: return "Stable these 6 months"
        case .year:     return "Stable this year"
        }
    }

    private var rangeText: LocalizedStringKey { "Varied between \(rangeLow) and \(rangeHigh)" }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Your average").instrumentoOverline().foregroundStyle(LiquidColor.tinta500)
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(average).instrumentoHero(28).foregroundStyle(LiquidColor.tinta900)
                    if let unit {
                        Text(unit).font(StrandFont.unit).foregroundStyle(LiquidColor.tinta500)
                    }
                }
                if changeValue != nil { chip }
            }
            Text(rangeText).font(StrandFont.footnote).foregroundStyle(LiquidColor.tinta700)
        }
        .accessibilityElement(children: .combine)
    }

    private var chip: some View {
        HStack(spacing: 3) {
            if !isFlat, let v = changeValue {
                Image(systemName: v >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(chipText).font(StrandFont.captionNumber)
        }
        .foregroundStyle(changeColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(changeColor.opacity(0.12)))
    }
}

#if DEBUG
#Preview("Trend stat summary") {
    VStack(alignment: .leading, spacing: 22) {
        // Stress — lower is better, fell → green
        TrendStatSummary(average: "1.5", unit: nil, pctChange: -10,
                         polarity: .lowerIsBetter, rangeLow: "0.1", rangeHigh: "2.9")
        // HRV — higher is better, rose → green
        TrendStatSummary(average: "48", unit: "ms", pctChange: 6,
                         polarity: .higherIsBetter, rangeLow: "31", rangeHigh: "62 ms")
        // Resting HR — lower is better, rose → amber
        TrendStatSummary(average: "54", unit: "bpm", pctChange: 4,
                         polarity: .lowerIsBetter, rangeLow: "48", rangeHigh: "61 bpm")
        // Strain — neutral, any change → quiet ink
        TrendStatSummary(average: "11.2", unit: nil, pctChange: 8,
                         polarity: .neutral, rangeLow: "4.1", rangeHigh: "17.8")
        // Flat month → "Stable this month"
        TrendStatSummary(average: "65", unit: nil, pctChange: 0.4,
                         polarity: .higherIsBetter, rangeLow: "40", rangeHigh: "88")
        // Skin-temp deviation — absolute-delta chip in °C (mean near zero, % would be misleading); neutral
        TrendStatSummary(average: "+0.1", unit: "°C", pctChange: nil, absoluteChange: 0.1,
                         polarity: .neutral, rangeLow: "−0.4", rangeHigh: "+0.5 °C")
    }
    .padding(24)
    .background(LiquidColor.fondoAlto)
}
#endif
