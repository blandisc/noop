import Foundation

// SeriesShape.swift — shape descriptors for a daily series (no DB, no SwiftUI).
//
// The presentation layer for the unified Métrica detail (FER-185) reads a vital
// (HRV / resting HR / respiration) as a 7-day *shape*, not a single day: the
// 7-day moving average is the hero, and a coefficient of variation reports how
// steady the signal has been week-to-week. Both are documented approximations —
// no clinical claim.
//
// Methods
// -------
//   • Simple moving average (SMA): the unweighted mean of the trailing `window`
//     points, aligned to the END of the series so output[i] is the mean of the
//     window ending at i. The head (the first `window-1` points, which have no
//     full window behind them) uses the shortest available prefix instead of
//     dropping points, so the result is the SAME length as the input.
//   • Coefficient of variation (CV = σ / |μ|): the sample standard deviation
//     (ddof = 1) over the TAIL `window` divided by the absolute mean of that
//     same tail. Reported as a FRACTION (multiply by 100 for a percent). CV is a
//     unitless measure of relative dispersion — Everitt & Skrondal, *The
//     Cambridge Dictionary of Statistics* (Cambridge University Press, 2010).

public enum SeriesShape {

    /// Trailing simple moving average of `values`, aligned to the end and the SAME
    /// length as the input. `output[i]` is the mean of `values[max(0, i-window+1)...i]`,
    /// so the head uses the shortest available prefix rather than being dropped.
    /// An empty input returns an empty array; `window <= 1` returns `values` unchanged.
    public static func movingAverage(_ values: [Double], window: Int = 7) -> [Double] {
        guard window > 1 else { return values }
        guard !values.isEmpty else { return [] }
        var out = [Double](repeating: 0, count: values.count)
        for i in values.indices {
            let lo = Swift.max(0, i - window + 1)
            let slice = values[lo...i]
            out[i] = slice.reduce(0, +) / Double(slice.count)
        }
        return out
    }

    /// The latest moving-average point: the mean of the last `≤window` values.
    /// `nil` when the input is empty. (Cheaper than building the full series when
    /// only the trailing average — the metric hero — is needed.)
    public static func latestMovingAverage(_ values: [Double], window: Int = 7) -> Double? {
        guard !values.isEmpty else { return nil }
        let n = Swift.max(window, 1)
        let tail = values.suffix(n)
        return tail.reduce(0, +) / Double(tail.count)
    }

    /// Downsample `values` to at most `maxPoints` by bucket-averaging: split the input into
    /// `maxPoints` contiguous buckets and return the mean of each. A pure DRAWING aid — it
    /// shrinks a long series so a chart doesn't stroke a mark per raw sample — NOT for analysis;
    /// the bucket means smooth the signal, so they preserve the broad shape but lose day-level
    /// detail. Compute statistics (median, σ, trend) on the full series, never on this.
    ///
    /// Passes the input through unchanged when `values.count <= maxPoints` (nothing to shrink),
    /// when `maxPoints <= 1`, or when the input is empty/degenerate. With more points than
    /// buckets, contiguous index ranges of near-equal size partition the input (so every value
    /// lands in exactly one bucket and order is preserved), and each bucket collapses to its mean.
    public static func decimate(_ values: [Double], maxPoints: Int) -> [Double] {
        guard maxPoints > 1 else { return values }
        guard values.count > maxPoints else { return values }
        let n = values.count
        var out = [Double]()
        out.reserveCapacity(maxPoints)
        for b in 0..<maxPoints {
            // Contiguous, near-equal partition: bucket b spans [lo, hi). Using n*b/maxPoints for
            // both edges keeps every index covered exactly once with no rounding gaps.
            let lo = (n * b) / maxPoints
            let hi = (n * (b + 1)) / maxPoints
            let slice = values[lo..<hi]
            out.append(slice.reduce(0, +) / Double(slice.count))
        }
        return out
    }

    /// Coefficient of variation over the trailing `window`: the sample standard
    /// deviation (ddof = 1) divided by the absolute mean, returned as a FRACTION.
    /// `nil` when fewer than 2 values are available in the tail or the absolute
    /// mean is ~0 (the ratio is undefined). CV = σ / |μ| (Everitt & Skrondal,
    /// Cambridge Dictionary of Statistics, 2010).
    public static func coefficientOfVariation(_ values: [Double], window: Int = 7) -> Double? {
        let tail = Array(values.suffix(Swift.max(window, 1)))
        let n = tail.count
        guard n >= 2 else { return nil }
        let mean = tail.reduce(0, +) / Double(n)
        guard abs(mean) > 1e-9 else { return nil }
        var ss = 0.0
        for v in tail { let d = v - mean; ss += d * d }
        let sd = (ss / Double(n - 1)).squareRoot()
        return sd / abs(mean)
    }
}
