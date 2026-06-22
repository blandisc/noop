import Foundation

// RecoveryForecast.swift — an honest one-day-ahead projection of recovery. (FER-188)
//
// The "Mañana, si descansas igual: ~X" block on the Recovery detail asks a narrow question:
// given how my recovery has been trending, and assuming I rest about the same tonight, roughly
// where does tomorrow land? This engine answers it as a TREND PROJECTION WITH A RANGE — never a
// guarantee, never a clinical claim. What you actually do today still dominates tomorrow.
//
// What it forecasts, and why recovery itself is the signal
// --------------------------------------------------------
// We project the recovery score series directly, rather than forecasting HRV and resting HR
// separately and recomposing them. Recovery is already the HRV-dominant composite (HRV 0.60,
// resting HR 0.20, sleep, …; see `RecoveryScorer`), so its day-to-day series IS the autoregressive
// trend of those drivers — bundled, de-noised by the weighting, and already on the 0–100 output
// scale. Forecasting the composite avoids dragging personal baselines into a pure projector and
// keeps the model as simple as the evidence supports (below).
//
// The model (simple on purpose)
// -----------------------------
//   level  = recency-weighted center of the recent series (mean of the last `levelDays` valid days)
//   slope  = ordinary least-squares slope of recovery vs day index over the trailing `window`
//   step   = slope · `slopeDamping`, clamped to ±`maxDailyStep` (raw slopes over a short, noisy
//            daily series over-extrapolate; we damp and cap the one-day move)
//   debt   = a gentle, bounded drag from accumulated sleep debt — "si descansas igual" means you
//            won't repay it tomorrow, so a standing debt keeps pulling recovery down
//   strain = an optional, bounded drag from an acute session you did TODAY whose cost has NOT yet
//            landed in the recovery series (the series reflects last night). A hard session delays
//            parasympathetic reactivation, so tomorrow's recovery sits a little below the trend
//            alone. Off (0) unless the caller passes a session strain — the post-session "cost"
//            block (FER-442) does; the Recovery-detail trend (FER-277) does not.
//   estimate = clamp(level + step − debt − strain, 0…100)
//   range    = estimate ± (`bandK`·σ, floored at `bandFloorHalf`), clamped to 0…100, where σ is the
//              recent recovery dispersion. The band is deliberately wide: it is the honesty.
//
// Honest gate
// -----------
// `compute` returns `nil` when fewer than `minDays` valid recovery days exist in the window
// (≈ two weeks of baseline). The caller then HIDES the block — it never invents a number.
//
// Methods / citations
// -------------------
//   • Autoregressive forecasting of wearable signals, and that simple models rival complex ones:
//     De Sabbata & Simonini, "Real-Time Forecasting from Wearable-Monitored Heart Rate Data
//     Through Autoregressive Models", *Journal of Healthcare Informatics Research*, 2025
//     (PMC12037944). The paper finds that for UNIVARIATE, SHORT-TERM forecasting "refining model
//     complexity offers minimal benefit" and a random-walk baseline "remains competitive, if not
//     superior". A one-day-ahead recovery projection is exactly that regime — which is why this is a
//     damped level+slope model and not something heavier. (Note: the paper's scope is short-term,
//     not long-horizon; cited accordingly.)
//   • The sleep-debt drag is a PRODUCT HEURISTIC, not a peer-reviewed coefficient — a gentle,
//     bounded nudge that encodes "a standing debt you won't repay tonight keeps recovery down".
//   • The acute session-strain drag's DIRECTION is grounded — higher exercise load delays
//     post-exercise parasympathetic (HRV) reactivation, so next-morning recovery sits lower:
//     Stanley, Peake & Buckley, "Cardiac Parasympathetic Reactivation Following Exercise:
//     Implications for Training Prescription", *Sports Medicine* 43(12):1259–1277, 2013. Its
//     MAGNITUDE (the points of drag) is a product-calibration knob, not a validated coefficient.
//
// The constants below (window sizes, damping, caps, band width, debt scale) are product-calibration
// knobs, not validated quantities — tuned for an honest, humble readout, not WHOOP parity.

public enum RecoveryForecast {

    // MARK: - Tunables

    /// Trailing days inspected for the slope (≈ three weeks).
    public static let window = 21
    /// Minimum valid recovery days required to forecast at all (≈ two weeks of baseline).
    /// Below this `compute` returns `nil` and the UI hides the block.
    public static let minDays = 14
    /// Days averaged for the recency-weighted level (the "moving average" anchor).
    static let levelDays = 7
    /// Fraction of the raw OLS slope carried into the one-day projection (anti-over-extrapolation).
    static let slopeDamping = 0.5
    /// Hard cap on the projected one-day move (recovery points), either direction.
    static let maxDailyStep = 8.0
    /// Confidence half-band in units of recent SD.
    static let bandK = 1.15
    /// Minimum confidence half-band (points), so the range never looks falsely precise.
    static let bandFloorHalf = 5.0
    /// Slope magnitude (points/day, after damping) below which the trend reads "steady".
    static let steadyEps = 0.15

    // Sleep-debt drag (bounded, gentle): no drag until `debtFloorMin`, ramping linearly to
    // `maxDebtDrag` points at `debtFullMin`.
    static let debtFloorMin = 30.0
    static let debtFullMin = 420.0
    static let maxDebtDrag = 8.0

    // Acute session-strain drag (bounded, gentle): no drag below `strainDragFloor`, ramping linearly
    // to `maxStrainDrag` points at `strainDragFull`. A single resistance session sits well below the
    // 0–21 daily ceiling, so the ramp spans a realistic session range. Capped at `maxStrainDrag` to
    // stay inside the engine's ±8 one-day envelope (no single term dominates a one-day projection).
    // Calibration knobs, not validated quantities — tunable on-device without touching the logic.
    static let strainDragFloor = 4.0
    static let strainDragFull = 16.0
    static let maxStrainDrag = 8.0

    // MARK: - Output

    /// Which way recovery is trending, by the sign of the damped one-day step.
    public enum Direction: Equatable, Sendable {
        case rising, steady, falling
    }

    /// A one-day-ahead recovery projection with an honest range. Never a guarantee.
    public struct Result: Equatable, Sendable {
        /// Projected recovery for tomorrow, 0–100.
        public let estimate: Double
        /// Lower bound of the confidence range, 0–100 (≤ estimate).
        public let low: Double
        /// Upper bound of the confidence range, 0–100 (≥ estimate).
        public let high: Double
        /// Direction of the (damped) recent trend.
        public let direction: Direction
        /// Valid recovery days that fed the projection (the effective basis).
        public let basisDays: Int

        public init(estimate: Double, low: Double, high: Double,
                    direction: Direction, basisDays: Int) {
            self.estimate = estimate
            self.low = low
            self.high = high
            self.direction = direction
            self.basisDays = basisDays
        }
    }

    // MARK: - Compute

    /// Project tomorrow's recovery from a recent daily recovery series, or `nil` if there isn't
    /// enough base to be honest.
    ///
    /// - Parameters:
    ///   - recovery: daily recovery scores, **oldest → newest**. `nil` entries (missing days) and
    ///     out-of-range values (outside 0…100) are dropped; only the trailing `window` are inspected.
    ///   - sleepDebtMin: accumulated sleep debt in minutes (≥ 0), if known. A standing debt applies a
    ///     small bounded downward drag; `nil` or ≤ `debtFloorMin` applies none.
    ///   - sessionStrain: the 0–21 strain of a session done TODAY (not yet reflected in `recovery`),
    ///     if any. Applies a small bounded downward drag — a hard session pulls tomorrow below the
    ///     trend. `nil` or ≤ `strainDragFloor` applies none. It does NOT relax the honest gate below.
    /// - Returns: an `estimate` + confidence range, or `nil` when fewer than `minDays` valid days exist.
    public static func compute(recovery: [Double?],
                               sleepDebtMin: Double? = nil,
                               sessionStrain: Double? = nil) -> Result? {
        // Trailing window, then keep valid (non-nil, in-range) points with their day index so the
        // slope reflects real spacing even when some days are missing.
        let recent = Array(recovery.suffix(window))
        let points: [(x: Double, y: Double)] = recent.enumerated().compactMap { idx, v in
            guard let v, v >= 0, v <= 100 else { return nil }
            return (Double(idx), v)
        }
        guard points.count >= minDays else { return nil }

        let ys = points.map(\.y)

        // Level: recency-weighted center — mean of the last `levelDays` valid values.
        let levelSlice = ys.suffix(levelDays)
        let level = levelSlice.reduce(0, +) / Double(levelSlice.count)

        // Slope: OLS of y vs x over the window's valid points, damped and capped to one day.
        let rawSlope = olsSlope(points)
        let step = min(maxDailyStep, max(-maxDailyStep, rawSlope * slopeDamping))

        // Downward drags (bounded, gentle): a standing sleep debt + any acute session done today.
        let drag = debtDrag(sleepDebtMin)
        let acute = strainDrag(sessionStrain)

        let estimate = clampScore(level + step - drag - acute)

        // Range from recent dispersion, floored so it never looks falsely precise.
        let half = max(bandFloorHalf, bandK * sampleSD(ys))
        let low = clampScore(estimate - half)
        let high = clampScore(estimate + half)

        let direction: Direction
        if step > steadyEps { direction = .rising }
        else if step < -steadyEps { direction = .falling }
        else { direction = .steady }

        return Result(estimate: estimate, low: low, high: high,
                      direction: direction, basisDays: points.count)
    }

    // MARK: - Math helpers

    /// Ordinary-least-squares slope (Δy per unit x). `0` when x has no variance.
    static func olsSlope(_ points: [(x: Double, y: Double)]) -> Double {
        let n = Double(points.count)
        guard n >= 2 else { return 0 }
        let meanX = points.reduce(0) { $0 + $1.x } / n
        let meanY = points.reduce(0) { $0 + $1.y } / n
        var num = 0.0, den = 0.0
        for p in points {
            let dx = p.x - meanX
            num += dx * (p.y - meanY)
            den += dx * dx
        }
        return den > 1e-9 ? num / den : 0
    }

    /// Sample standard deviation (ddof = 1). `0` for fewer than two values.
    /// Single impl lives in `ReadinessEngine.sampleSD` (FER-322).
    static func sampleSD(_ values: [Double]) -> Double {
        ReadinessEngine.sampleSD(values) ?? 0
    }

    /// Bounded, gentle drag (recovery points) from accumulated sleep debt.
    static func debtDrag(_ sleepDebtMin: Double?) -> Double {
        guard let d = sleepDebtMin, d > debtFloorMin else { return 0 }
        let frac = min(1.0, (d - debtFloorMin) / (debtFullMin - debtFloorMin))
        return maxDebtDrag * frac
    }

    /// Bounded, gentle drag (recovery points) from an acute session done today (0–21 strain).
    static func strainDrag(_ sessionStrain: Double?) -> Double {
        guard let s = sessionStrain, s > strainDragFloor else { return 0 }
        let frac = min(1.0, (s - strainDragFloor) / (strainDragFull - strainDragFloor))
        return maxStrainDrag * frac
    }

    private static func clampScore(_ v: Double) -> Double { max(0, min(100, v)) }
}
