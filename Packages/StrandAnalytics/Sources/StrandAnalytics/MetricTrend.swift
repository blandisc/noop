import Foundation

// MetricTrend.swift — turning a correlation into a *direction only*, gated. (FER-209)
//
// The "Qué la mueve" block tells the user whether one daily metric tends to move WITH
// or AGAINST another (e.g. HRV vs sleep) — but NEVER a coefficient and NEVER a causal
// claim. Wrist wearables measure day-to-day deviation from your own baseline well and
// absolute values poorly, and a precise r on a short, noisy daily series overstates
// certainty (Plews 2013; the redesign's evidence note). So we degrade the Pearson r to
// a single bit of direction, and only surface it once the relationship clears a
// sufficiency + strength gate. Below the gate we return nil → the caller HIDES the
// block; it never invents a trend.

/// The direction a metric tends to move as the *other* variable increases.
public enum MetricTrend: Equatable, Sendable {
    /// Moves together — the metric tends to be higher when the other variable is higher (r ≥ 0).
    case rises
    /// Moves opposite — the metric tends to be lower when the other variable is higher (r < 0).
    case falls
}

extension CorrelationEngine {

    /// The bar a correlation must clear before we'll surface a direction.
    ///
    /// - `minPairs`: aligned daily observations required. 42 ≈ six weeks of paired
    ///   nights — the low end of FER-209's 6–8 week window, so the block appears as
    ///   soon as it's trustworthy while the strength tests below still guard noise.
    /// - `minAbsR`: a |r| floor of 0.20 — stricter than Cohen's (1988) 0.10 "small"-effect
    ///   cut, so we don't claim a direction on trivially small relationships even when n is
    ///   large enough to make a tiny r statistically significant.
    /// - `maxP`: significance ceiling (two-sided, read from `Correlation.pApprox`). 0.05
    ///   rejects relationships that could plausibly be chance on this much data.
    public struct TrendGate: Equatable, Sendable {
        public let minPairs: Int
        public let minAbsR: Double
        public let maxP: Double
        public init(minPairs: Int = 42, minAbsR: Double = 0.20, maxP: Double = 0.05) {
            self.minPairs = minPairs
            self.minAbsR = minAbsR
            self.maxP = maxP
        }
        /// The default FER-209 gate: ≥42 pairs, |r| ≥ 0.20, p < 0.05.
        public static let `default` = TrendGate()
    }

    /// Translate a correlation into a gated direction, or `nil` when it doesn't clear the
    /// gate (too little data, too weak, or plausibly chance). `nil` ⇒ hide the block.
    /// Returns only the sign — never a number, never an implied cause.
    public static func trend(_ c: Correlation?, gate: TrendGate = .default) -> MetricTrend? {
        guard let c,
              c.n >= gate.minPairs,
              abs(c.r) >= gate.minAbsR,
              c.pApprox < gate.maxP else { return nil }
        return c.r >= 0 ? .rises : .falls
    }
}
