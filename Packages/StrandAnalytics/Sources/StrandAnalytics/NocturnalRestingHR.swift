import Foundation

/// NocturnalRestingHR — estimate one night's true nocturnal resting heart rate (bpm)
/// from wrist HR samples, or return nil when there isn't enough signal.
///
/// Apple's HealthKit `restingHeartRate` is a wake-sedentary aggregate: it deliberately
/// EXCLUDES sleep. That makes it useful as a daytime resting floor, but it is NOT the
/// nocturnal nadir — the lowest sustained rate the heart reaches overnight, which lives
/// in deep sleep. This engine fills that gap with an on-device estimate over one night's
/// wrist PPG samples.
///
/// METHOD (robust low quantile, never the raw minimum):
///   1. ARTIFACT FILTER — discard bpm outside [30, 120]. Optical PPG routinely produces
///      brief spikes and dropouts; those must not enter the count or the quantile.
///   2. DEEP-SLEEP PREFERENCE — if ≥ `minSamples` of the surviving samples fall in deep
///      sleep, compute only over that subset (where the true nadir lives). Otherwise fall
///      back to the whole filtered window with the same quantile.
///   3. QUANTILE p12.5 (R type-7 / numpy "linear") — a robust "low" that sits below the
///      median without collapsing to the single noisiest sample. Index = q·(n−1), linear
///      interpolation between the bracketing sorted values.
///
/// HONEST FRAMING: approximation from wrist PPG, not a clinical resting-HR protocol.
/// Nil means "not enough clean signal tonight" — never fabricate a number from thin data.
public enum NocturnalRestingHR {

    /// One wrist HR sample tagged with whether it fell inside a deep-sleep stage.
    public struct Sample: Sendable, Equatable {
        /// Unix seconds.
        public let ts: Int
        /// Heart rate in beats per minute.
        public let bpm: Double
        /// True if this sample falls within deep sleep (the preferred subset for the nadir).
        public let deep: Bool

        public init(ts: Int, bpm: Double, deep: Bool) {
            self.ts = ts
            self.bpm = bpm
            self.deep = deep
        }
    }

    /// Low quantile used by default (p12.5 — "robust low", neither the min nor the median).
    /// Chosen so a handful of low PPG glitches can't drag the estimate to the floor the way
    /// a raw minimum would, while still tracking the lower tail of the night's distribution.
    public static let quantile: Double = 0.125

    /// Minimum number of samples (after filtering) required to emit a result; fewer → nil.
    /// Product-calibration floor: enough points for a stable low-quantile on wrist PPG
    /// without waiting for a full night's density (deep sleep alone is often sparse).
    public static let minSamples: Int = 20

    /// Nocturnal resting HR (bpm) for one night, or nil if there isn't enough signal.
    ///
    /// Order of operations is load-bearing:
    ///   1. Artifact-filter first (bpm ∉ [30, 120] discarded before any count).
    ///   2. If filtered count < `minSamples` → nil (never fabricate).
    ///   3. Prefer deep-sleep subset when it alone clears `minSamples`; else whole window.
    ///   4. Emit R type-7 quantile at `quantile` over the chosen set.
    public static func estimate(_ samples: [Sample]) -> Double? {
        // Optical PPG artifacts: brief spikes/dropouts land outside a physiological night
        // band. Filter BEFORE counting against minSamples so junk never pads a thin night.
        let filtered = samples.filter { $0.bpm >= 30 && $0.bpm <= 120 }
        guard filtered.count >= minSamples else { return nil }

        // Prefer deep sleep when dense enough: the true nocturnal nadir lives there.
        // Falling back to the whole window keeps a usable estimate on nights with sparse
        // stage labels, without lowering the density gate.
        let deep = filtered.filter(\.deep)
        let pool = deep.count >= minSamples ? deep : filtered
        let values = pool.map(\.bpm)
        return type7Quantile(values, q: quantile)
    }

    // MARK: - Quantile (R type-7 / numpy linear)

    /// R's type-7 quantile (default in R; numpy `method="linear"`):
    ///   index = q · (n − 1)
    ///   result = sorted[floor] + frac · (sorted[ceil] − sorted[floor])
    /// Pinned by NocturnalRestingHRTests A6 (hand-computed vector). Do not switch to
    /// nearest-rank or other Hyndman–Fan types without updating that pin.
    private static func type7Quantile(_ values: [Double], q: Double) -> Double? {
        let n = values.count
        guard n > 0 else { return nil }
        let sorted = values.sorted()
        if n == 1 { return sorted[0] }
        let index = q * Double(n - 1)
        let lo = Int(index.rounded(.down))
        let hi = Int(index.rounded(.up))
        if lo == hi { return sorted[lo] }
        let frac = index - Double(lo)
        return sorted[lo] + frac * (sorted[hi] - sorted[lo])
    }
}
