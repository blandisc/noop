import Foundation

// TrajectorySimulator.swift — project a goal metric's daily series onto two futures. (FER-311)
//
// The Bucle's simulator asks: given how a metric (recovery, sleep, HRV, resting HR…) has been
// trending, where does it land over the next N days if I keep going as I am — vs. if I adopt one
// PROVEN lever? Two paths, "como vas" and "si cambias X", each inside a confidence band that widens
// with the horizon. The gap between them at the goal date is the cost of not changing. This is a
// TREND PROJECTION WITH A RANGE, never a guarantee; what you actually do still dominates the outcome.
//
// Metric-agnostic on purpose
// --------------------------
// The engine knows nothing about "goals" or which metric it is projecting. The app passes a daily
// series, a clamp `bounds`, and (optionally) a signed `leverDelta` — the measured steady-state effect
// of one proven lever, already oriented toward "better" (positive for higher-is-better metrics like
// recovery/HRV, negative for lower-is-better metrics like resting HR). So a single projector serves
// every focus, and the lever path is just the baseline shifted by that delta. The same value types
// (`DailyMetric` fields) feed it whether the source is the strap, backfill, or an import.
//
// The model (simple on purpose, honest by the band)
// -------------------------------------------------
//   level  = recency-weighted center of the recent series (mean of the last `levelDays` valid days)
//   slope  = ordinary least-squares slope over the trailing `window`, damped and capped to ±`stepCapSDs`·σ
//            (the cap is scale-RELATIVE — a metric-agnostic projector can't use absolute points)
//   D(h)   = step · φ·(1−φ^h)/(1−φ)   — a DAMPED trend (Gardner–McKenzie 1985): each day's increment
//            is discounted by φ, so the projection flattens to a finite plateau instead of
//            extrapolating in a straight line over 30–90 days. φ = `trendDamping`.
//   base(h)= clamp(level + D(h), bounds)                              — the "como vas" path
//   lever(h)= clamp(base(h) + leverDelta · ramp(h), bounds)           — the "si cambias X" path
//            ramp(h) = min(1, h/`leverRampDays`): the lever's effect accrues gradually, not in one day.
//   half(h)= max(`bandFloorSDs`·σ, `bandK`·σ·√h)                       — the band, growing with √h
//            (random-walk forecast error grows with the horizon; the wide band IS the honesty).
//   gap    = lever(H).estimate − base(H).estimate                     — the cost of not changing.
//
// Honest gate
// -----------
// `project` returns `nil` when fewer than `minDays` valid days exist in the window (≈ two weeks of
// base). The caller then HIDES the simulator — it never invents a trajectory.
//
// Methods / citations
// -------------------
//   • Damped trend: Gardner & McKenzie, "Forecasting Trends in Time Series", *Management Science*
//     31(10), 1985 — the discounted-trend method that keeps long horizons from over-extrapolating.
//   • Simple ≥ complex for short-horizon univariate wearable forecasting: De Sabbata & Simonini,
//     *Journal of Healthcare Informatics Research*, 2025 (PMC12037944) — the same evidence that keeps
//     `RecoveryForecast` a damped level+slope model rather than something heavier.
//   • Forecast error grows with the horizon (√h for a random-walk level): standard ARIMA / random-walk
//     result (e.g. Hyndman & Athanasopoulos, *Forecasting: Principles and Practice*). The widening band
//     is the projection's humility.
//
// Reuses `RecoveryForecast.olsSlope` / `RecoveryForecast.sampleSD` (same module) so the OLS/SD math
// lives in one place. Pure + DB-free; all constants below are product-calibration knobs, not validated
// quantities. No clinical claims — "si tus patrones se mantienen".

public enum TrajectorySimulator {

    // MARK: - Tunables

    /// Trailing days inspected for level + slope (≈ three weeks).
    public static let window = 21
    /// Minimum valid days required to project at all (≈ two weeks of base). Below this → `nil`.
    public static let minDays = 14
    /// Days averaged for the recency-weighted level (today's anchor).
    static let levelDays = 7
    /// Fraction of the raw OLS slope carried into the projection (anti-over-extrapolation).
    static let slopeDamping = 0.5
    /// Cap on the per-day step, in units of the recent SD (scale-relative, metric-agnostic).
    static let stepCapSDs = 0.5
    /// Trend damping φ ∈ (0,1): each horizon day's increment is discounted by φ, so far-out days plateau.
    static let trendDamping = 0.85
    /// Confidence half-band in units of recent SD, scaled by √h.
    static let bandK = 1.15
    /// Minimum confidence half-band in units of recent SD, so the band never looks falsely precise.
    static let bandFloorSDs = 0.4
    /// Days over which a lever's effect ramps from 0 to its full measured delta.
    static let leverRampDays = 7.0
    /// Step magnitude (in units of SD) below which the trend reads "steady".
    static let steadyEpsSDs = 0.02

    // MARK: - Output

    /// Which way the metric is trending, by the sign of the damped step.
    public enum Direction: Equatable, Sendable {
        case rising, steady, falling
    }

    /// One projected day: the central estimate and its confidence range. `dayOffset` is days from today
    /// (1…horizon).
    public struct Point: Equatable, Sendable {
        public let dayOffset: Int
        public let estimate: Double
        public let low: Double
        public let high: Double

        public init(dayOffset: Int, estimate: Double, low: Double, high: Double) {
            self.dayOffset = dayOffset
            self.estimate = estimate
            self.low = low
            self.high = high
        }
    }

    /// A two-path trajectory projection. `withLever` is `nil` when no proven lever was supplied (the
    /// "con meta, sin palancas" state — only "como vas" is shown).
    public struct Projection: Equatable, Sendable {
        /// "Como vas": the extended trend. Always present (length == `horizonDays`).
        public let baseline: [Point]
        /// "Si cambias X": the trend plus a proven lever's effect. `nil` without a lever.
        public let withLever: [Point]?
        /// Today's anchor — where both paths start (the recency-weighted level).
        public let level: Double
        /// Horizon length in days.
        public let horizonDays: Int
        /// `withLever.last.estimate − baseline.last.estimate` (signed; the cost of not changing). `nil`
        /// without a lever.
        public let gap: Double?
        /// Valid days that fed the projection (the effective basis).
        public let basisDays: Int
        /// Direction of the (damped) recent trend.
        public let direction: Direction

        public init(baseline: [Point], withLever: [Point]?, level: Double, horizonDays: Int,
                    gap: Double?, basisDays: Int, direction: Direction) {
            self.baseline = baseline
            self.withLever = withLever
            self.level = level
            self.horizonDays = horizonDays
            self.gap = gap
            self.basisDays = basisDays
            self.direction = direction
        }
    }

    // MARK: - Compute

    /// Project a daily metric series onto two futures, or `nil` if there isn't enough base to be honest.
    ///
    /// - Parameters:
    ///   - series: daily values, **oldest → newest**. `nil` entries (missing days) and values outside
    ///     `bounds` are dropped; only the trailing `window` are inspected. (Pass generous, physiological
    ///     `bounds` so real measurements are never silently dropped.)
    ///   - horizonDays: how many days ahead to project (≥ 1). The caller derives it from the goal date.
    ///   - leverDelta: the signed steady-state effect of one PROVEN lever, in the metric's units, already
    ///     oriented toward "better". `nil` → only the baseline path is produced.
    ///   - bounds: the clamp range for every projected value (e.g. `0...100` recovery, `0...720` sleep
    ///     minutes). Also filters out-of-range inputs.
    ///   - minDays: the honest-gate threshold (defaults to `minDays`).
    /// - Returns: a two-path `Projection`, or `nil` when fewer than `minDays` valid days exist.
    public static func project(series: [Double?],
                               horizonDays: Int,
                               leverDelta: Double? = nil,
                               bounds: ClosedRange<Double>,
                               minDays: Int = minDays) -> Projection? {
        guard horizonDays >= 1 else { return nil }

        // Trailing window, keeping valid (non-nil, in-range) points with their real day index so the
        // slope reflects true spacing even when some days are missing (mirrors RecoveryForecast).
        let recent = Array(series.suffix(window))
        let points: [(x: Double, y: Double)] = recent.enumerated().compactMap { idx, v in
            guard let v, bounds.contains(v) else { return nil }
            return (Double(idx), v)
        }
        guard points.count >= minDays else { return nil }

        let ys = points.map(\.y)

        // Level: recency-weighted center — mean of the last `levelDays` valid values.
        let levelSlice = ys.suffix(levelDays)
        let level = clamp(levelSlice.reduce(0, +) / Double(levelSlice.count), bounds)

        // Slope: OLS over the window (reused), damped and capped to a scale-relative one-day step.
        let sd = RecoveryForecast.sampleSD(ys)
        let rawSlope = RecoveryForecast.olsSlope(points)
        let cap = stepCapSDs * sd
        let step = min(cap, max(-cap, rawSlope * slopeDamping))

        let eps = steadyEpsSDs * sd
        let direction: Direction
        if step > eps { direction = .rising }
        else if step < -eps { direction = .falling }
        else { direction = .steady }

        // Damped-trend cumulative offset at horizon day h (Gardner–McKenzie). φ ∈ (0,1) ⇒ a finite
        // plateau as h grows, never a straight-line blow-up.
        let phi = trendDamping
        func dampedOffset(_ h: Int) -> Double {
            step * phi * (1 - pow(phi, Double(h))) / (1 - phi)
        }
        // Band half-width grows with √h, floored relative to the recent SD.
        func halfBand(_ h: Int) -> Double {
            max(bandFloorSDs * sd, bandK * sd * Double(h).squareRoot())
        }

        var baseline: [Point] = []
        baseline.reserveCapacity(horizonDays)
        var lever: [Point] = []
        if leverDelta != nil { lever.reserveCapacity(horizonDays) }

        for h in 1...horizonDays {
            let est = clamp(level + dampedOffset(h), bounds)
            let hf = halfBand(h)
            baseline.append(Point(dayOffset: h, estimate: est,
                                  low: clamp(est - hf, bounds), high: clamp(est + hf, bounds)))
            if let d = leverDelta {
                let ramp = Swift.min(1.0, Double(h) / leverRampDays)
                let le = clamp(est + d * ramp, bounds)
                lever.append(Point(dayOffset: h, estimate: le,
                                   low: clamp(le - hf, bounds), high: clamp(le + hf, bounds)))
            }
        }

        let withLever: [Point]? = leverDelta == nil ? nil : lever
        let gap: Double? = withLever.map { $0[$0.count - 1].estimate - baseline[baseline.count - 1].estimate }

        return Projection(baseline: baseline, withLever: withLever, level: level,
                          horizonDays: horizonDays, gap: gap,
                          basisDays: points.count, direction: direction)
    }

    private static func clamp(_ v: Double, _ bounds: ClosedRange<Double>) -> Double {
        Swift.min(bounds.upperBound, Swift.max(bounds.lowerBound, v))
    }
}
