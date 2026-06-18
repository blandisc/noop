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

public struct TrendStatSummary: View {

    /// Which direction of change is "good" for this metric — drives the chip colour.
    public enum Polarity: Sendable {
        case higherIsBetter   // HRV, sleep duration, recovery
        case lowerIsBetter    // stress, resting HR
        case neutral          // strain — more isn't inherently good or bad
    }

    private let average: String
    private let unit: String?
    private let pctChange: Double?
    private let polarity: Polarity
    private let rangeLow: String
    private let rangeHigh: String
    private let theme: InstrumentoTheme

    /// - Parameters:
    ///   - average: the period mean, already formatted to the metric's precision (no unit).
    ///   - unit: optional unit shown small next to the number (e.g. "ms", "h"); nil for unitless indices.
    ///   - pctChange: signed month-over-month % change in the mean; nil when there's no previous month.
    ///   - polarity: which direction of change is good — colours the chip.
    ///   - rangeLow / rangeHigh: the period min and max, already formatted (bake the unit into rangeHigh
    ///     when you want it shown, e.g. "62 ms").
    ///   - theme: the active «Instrumento» theme (it does not propagate through `.sheet`, so pass it).
    public init(average: String,
                unit: String? = nil,
                pctChange: Double?,
                polarity: Polarity,
                rangeLow: String,
                rangeHigh: String,
                theme: InstrumentoTheme) {
        self.average = average
        self.unit = unit
        self.pctChange = pctChange
        self.polarity = polarity
        self.rangeLow = rangeLow
        self.rangeHigh = rangeHigh
        self.theme = theme
    }

    /// A change present but under ±1% reads as no movement — say "Stable" instead of "0%". When there's
    /// no previous month at all (`pctChange == nil`), the chip is hidden entirely rather than faking "Stable".
    private var isFlat: Bool { pctChange.map { abs($0) < 1 } ?? false }

    /// Green when the change moves the good way, amber when the bad way; quiet ink when flat or neutral.
    private var changeColor: Color {
        guard !isFlat, let pct = pctChange else { return theme.inkSecondary }
        switch polarity {
        case .neutral:        return theme.inkSecondary
        case .higherIsBetter: return pct > 0 ? theme.verdict : theme.warning
        case .lowerIsBetter:  return pct < 0 ? theme.verdict : theme.warning
        }
    }

    /// "10% vs last month" (String-interpolated so the key is "%@ vs last month", which localizes —
    /// the arrow already carries the sign, FER-247), or "Stable this month" when flat.
    private var chipText: LocalizedStringKey {
        guard !isFlat, let pct = pctChange else { return "Stable this month" }
        let pctStr = "\(Int(abs(pct).rounded()))%"
        return "\(pctStr) vs last month"
    }

    private var rangeText: LocalizedStringKey { "Varied between \(rangeLow) and \(rangeHigh)" }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Your average").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(average).instrumentoHero(28).foregroundStyle(theme.ink)
                    if let unit {
                        Text(unit).font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    }
                }
                if pctChange != nil { chip }
            }
            Text(rangeText).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var chip: some View {
        HStack(spacing: 3) {
            if !isFlat, let pct = pctChange {
                Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
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
    let t = InstrumentoTheme.base
    return VStack(alignment: .leading, spacing: 22) {
        // Stress — lower is better, fell → green
        TrendStatSummary(average: "1.5", unit: nil, pctChange: -10,
                         polarity: .lowerIsBetter, rangeLow: "0.1", rangeHigh: "2.9", theme: t)
        // HRV — higher is better, rose → green
        TrendStatSummary(average: "48", unit: "ms", pctChange: 6,
                         polarity: .higherIsBetter, rangeLow: "31", rangeHigh: "62 ms", theme: t)
        // Resting HR — lower is better, rose → amber
        TrendStatSummary(average: "54", unit: "bpm", pctChange: 4,
                         polarity: .lowerIsBetter, rangeLow: "48", rangeHigh: "61 bpm", theme: t)
        // Strain — neutral, any change → quiet ink
        TrendStatSummary(average: "11.2", unit: nil, pctChange: 8,
                         polarity: .neutral, rangeLow: "4.1", rangeHigh: "17.8", theme: t)
        // Flat month → "Stable this month"
        TrendStatSummary(average: "65", unit: nil, pctChange: 0.4,
                         polarity: .higherIsBetter, rangeLow: "40", rangeHigh: "88", theme: t)
    }
    .padding(24)
    .background(t.paper)
}
#endif
