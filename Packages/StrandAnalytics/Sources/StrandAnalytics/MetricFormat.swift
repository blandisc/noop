import Foundation

/// The ONE place a metric's number is turned into text — value, unit, band edges — so the hero,
/// the axis, the scrub pop and the levels table can never disagree again (FER-29 · contrato 5).
///
/// Before this, the same night of sleep read «7h 12m» in the catalog, «7:12» in the rich variant
/// and «7:00» in the levels axis; strain showed «10.0» in the hero but «10» on the axis. A single
/// `MetricFormat` per metric closes that: `numeral(_:)` renders the hero value, `full(_:)` hangs the
/// unit, and `range(lower:upper:)` renders a band edge in the SAME grammar — the source the app's
/// `MetricLevels.displayBands` reads so the levels table can't restate a different number.
///
/// Pure and Foundation-only: no `import` of SwiftUI / UIKit / HealthKit, no locale surprises (the
/// thousands grouping is inserted by hand so a test reads the same on any device). Units are the raw
/// symbols the app already localises at the call site (`String(localized: "bpm")`); this type carries
/// the source symbol, never a translated string.
///
/// Domain note: a metric's value AND its `MetricLevels` cuts must be in the SAME unit for the edges to
/// line up — sleep in MINUTES (the engine's unit), not hours; skin temperature in °C of deviation.
public struct MetricFormat: Sendable, Equatable {

    /// How a number is rendered. The hero value and the band edges can differ (strain's hero is a
    /// decimal «10.0» while its edges are whole «6 – 10»), so a format carries one of each.
    public enum Style: Sendable, Equatable {
        /// Rounded to a whole number: 96.7 → «97».
        case integer
        /// Whole number with thousands grouping: 8240 → «8,240».
        case integerGrouped
        /// One decimal place: 10 → «10.0», 14.24 → «14.2».
        case decimal1
        /// One decimal place, always signed: 0.4 → «+0.4», −0.4 → «−0.4» (skin-temp deviation).
        case signedDecimal1
        /// Minutes rendered as clock time: 432 → «7:12», 360 → «6:00» (sleep).
        case clockFromMinutes
    }

    /// The style for the hero numeral (e.g. strain «10.0»).
    public let valueStyle: Style
    /// The style for band edges (e.g. strain «6 – 10»); usually the same, coarser for strain/resp.
    public let boundaryStyle: Style
    /// The raw unit symbol hung after the number, or `nil` when the numeral carries its own meaning
    /// (sleep's clock, strain's bare score). The app localises this symbol at the call site.
    public let unit: String?
    /// Whether the unit sits flush against the number («97%») or spaced («58 bpm»). Only «%» is tight.
    public let unitTight: Bool
    /// An optional scale suffix shown next to the hero only (strain «/ 21», stress «/ 3»); never part
    /// of a band edge.
    public let scaleSuffix: String?

    public init(valueStyle: Style,
                boundaryStyle: Style,
                unit: String?,
                unitTight: Bool = false,
                scaleSuffix: String? = nil) {
        self.valueStyle = valueStyle
        self.boundaryStyle = boundaryStyle
        self.unit = unit
        self.unitTight = unitTight
        self.scaleSuffix = scaleSuffix
    }

    // MARK: - Rendering

    /// The hero numeral, without unit: sleep 432 → «7:12», strain 10 → «10.0», spo2 97 → «97».
    public func numeral(_ value: Double) -> String { Self.render(value, style: valueStyle) }

    /// The hero numeral with its unit hung: spo2 97 → «97%», resting HR 58 → «58 bpm», sleep → «7:12».
    public func full(_ value: Double) -> String { attach(unit, to: numeral(value)) }

    /// A band edge, without unit, in the (possibly coarser) boundary style: strain 18 → «18».
    public func boundary(_ value: Double) -> String { Self.render(value, style: boundaryStyle) }

    /// A band edge with its unit hung: spo2 95 → «95%», resting HR 50 → «50 bpm».
    public func boundaryFull(_ value: Double) -> String { attach(unit, to: boundary(value)) }

    /// The reference-range text for one band, from its half-open `[lower, upper)` bounds (the same
    /// convention as `MetricLevels.Level`). Open below → «< upper»; open above → «≥ lower»; otherwise
    /// «lower – upper» with the unit hung once, on the right. Examples: spo2 low «< 95%», resting HR
    /// normal «60 – 80 bpm», strain extreme «≥ 18», sleep optimal «7:00 – 8:30».
    public func range(lower: Double?, upper: Double?) -> String {
        switch (lower, upper) {
        case let (nil, u?):  return "< " + boundaryFull(u)
        case let (l?, nil):  return "≥ " + boundaryFull(l)
        case let (l?, u?):   return boundary(l) + " – " + boundaryFull(u)
        case (nil, nil):     return ""   // a band open on both sides has no printable range
        }
    }

    // MARK: - Internals

    private func attach(_ unit: String?, to numeral: String) -> String {
        guard let unit else { return numeral }
        return unitTight ? numeral + unit : numeral + " " + unit
    }

    private static func render(_ value: Double, style: Style) -> String {
        switch style {
        case .integer:
            return String(Int(value.rounded()))
        case .integerGrouped:
            return grouped(Int(value.rounded()))
        case .decimal1:
            return String(format: "%.1f", value)
        case .signedDecimal1:
            // Force the sign, then normalise the minus to a real «−» so the guard/typography match.
            return String(format: "%+.1f", value).replacingOccurrences(of: "-", with: "−")
        case .clockFromMinutes:
            let total = Int(value.rounded())
            let h = total / 60, m = total % 60
            return "\(h):" + String(format: "%02d", m)
        }
    }

    /// Thousands grouping with a plain comma, inserted by hand so the result is identical on every
    /// device regardless of the current locale (a `NumberFormatter` would follow the user's region).
    private static func grouped(_ value: Int) -> String {
        let negative = value < 0
        var digits = String(abs(value))
        var out = ""
        while digits.count > 3 {
            let tail = String(digits.suffix(3))
            out = "," + tail + out
            digits = String(digits.dropLast(3))
        }
        out = digits + out
        return negative ? "−" + out : out
    }

    // MARK: - Per-metric formatters (the single source)

    /// The formatter for a fixed-level metric. This is the one home each surface reads, so the hero,
    /// the axis, the scrub and the levels table all speak the same grammar. Units are the raw symbols
    /// the app localises at the call site.
    public static func forMetric(_ metric: MetricLevels.FixedMetric) -> MetricFormat {
        switch metric {
        case .recovery:
            // 0–100 score, whole number, no unit. (No sheet in FER-29, but kept total for the engine.)
            return MetricFormat(valueStyle: .integer, boundaryStyle: .integer, unit: nil)
        case .sleep:
            // MINUTES in, clock out: 432 → «7:12». Edges are clock too so «6:00 – 7:00» lines up.
            return MetricFormat(valueStyle: .clockFromMinutes, boundaryStyle: .clockFromMinutes, unit: nil)
        case .strain:
            // Hero is a decimal «10.0 / 21»; edges are whole «6 – 10 … ≥ 18».
            return MetricFormat(valueStyle: .decimal1, boundaryStyle: .integer, unit: nil, scaleSuffix: "/ 21")
        case .restingHR:
            return MetricFormat(valueStyle: .integer, boundaryStyle: .integer, unit: "bpm")
        case .bloodOxygen:
            return MetricFormat(valueStyle: .integer, boundaryStyle: .integer, unit: "%", unitTight: true)
        case .steps:
            return MetricFormat(valueStyle: .integerGrouped, boundaryStyle: .integerGrouped, unit: nil)
        case .stress:
            // 0–3 score; hero «1.4 / 3», edges whole «1 – 2».
            return MetricFormat(valueStyle: .decimal1, boundaryStyle: .integer, unit: nil, scaleSuffix: "/ 3")
        case .respiration:
            // Hero «14.2»; edges whole «≥ 20 rpm» (kills the residual closed-interval «<= 18» bug).
            return MetricFormat(valueStyle: .decimal1, boundaryStyle: .integer, unit: "rpm")
        case .skinTemp:
            // Deviation from the personal baseline in °C, always signed: «+0.4 °C», edge «−0.4 – +0.4 °C».
            return MetricFormat(valueStyle: .signedDecimal1, boundaryStyle: .signedDecimal1, unit: "°C")
        }
    }
}
