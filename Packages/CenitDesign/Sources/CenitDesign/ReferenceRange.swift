import Foundation

// MARK: - Reference range for trend bands (FER-155)
//
// The "typical recent range" band drawn behind a Sparkline in «Métricas clave»
// (FER-135): the interquartile range (p25–p75) of the visible window, so today's
// value reads in context — inside / above / below your usual.
//
// Pure arithmetic over `[Double]`. It lives in CenitDesign (the dependency-free
// leaf of the package graph) so the chart can use it WITHOUT importing
// StrandAnalytics — same reason FER-132/133 inject `SolarWindow`/`SleepWindow` by
// value instead of importing. The percentile is the same linear-interpolated method
// (numpy.percentile default; Hyndman & Fan 1996, type 7) that `StrainScorer` and
// `SleepStager` already use in StrandAnalytics — replicated here, not imported.

enum ReferenceRange {

    /// Linear-interpolated percentile (numpy.percentile default; Hyndman & Fan 1996,
    /// type 7). `pct` is 0...100; `sorted` must be ascending. Returns 0 for an empty
    /// array and the lone element for a single-value array.
    static func percentile(_ sorted: [Double], _ pct: Double) -> Double {
        let n = sorted.count
        if n == 0 { return 0 }
        if n == 1 { return sorted[0] }
        let position = (pct / 100.0) * Double(n - 1)
        let lower = Int(position)
        let upper = Swift.min(lower + 1, n - 1)
        let frac = position - Double(lower)
        return sorted[lower] + frac * (sorted[upper] - sorted[lower])
    }

    /// The interquartile band p25...p75 ("typical recent range") of `values`. Drops
    /// non-finite values, sorts ascending, and returns `nil` when nothing usable
    /// remains. Short or constant series still yield a valid (possibly zero-width)
    /// range — it never crashes and never inverts (`lowerBound <= upperBound`).
    static func interquartile(_ values: [Double]) -> ClosedRange<Double>? {
        let clean = values.filter { $0.isFinite }.sorted()
        guard !clean.isEmpty else { return nil }
        let lo = percentile(clean, 25)
        let hi = percentile(clean, 75)
        return Swift.min(lo, hi)...Swift.max(lo, hi)
    }
}
