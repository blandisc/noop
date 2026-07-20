import Foundation

/// NocturnalHRV — turn one civil night's worth of Apple wrist NN intervals into a single,
/// honest RMSSD or nothing at all.
///
/// The nightly Apple heartbeat series (HKHeartbeatSeriesSample) is opportunistic wrist PPG:
/// sparse, gappy, taken while the user shifts position. This engine never pretends a thin
/// night is a measurement. It counts the clean beats (in range) and the genuinely successive
/// pairs (segmented, gap < 3 s), and only emits an RMSSD when the night is DENSE on both
/// counts and the value is positive. Every threshold here is a product-calibration gate, NOT
/// a validated clinical threshold — labelled as such.
public enum NocturnalHRV {

    /// Minimum in-range NN intervals for a night to count as dense. Product-calibration
    /// knob (NOT literature-validated) — a floor on how much of the night was actually sampled.
    public static let minCleanBeats: Int = 60

    /// Minimum successive (gap < 3 s) valid pairs for a night to count as dense. STRICTER than
    /// `HRVAnalyzer.minBeats` (20) on purpose: RMSSD needs real beat-to-beat pairs, and a sparse
    /// wrist night can clear 60 clean beats while offering far fewer true successive pairs. Do
    /// NOT reuse the 20 here. Product-calibration knob.
    public static let minSuccessivePairs: Int = 30

    /// One night's outcome.
    public struct NightResult: Sendable, Equatable {
        /// RMSSD (ms) for the night, or nil unless the night is dense AND rmssd > 0.
        public let rmssdMs: Double?
        /// Count of NN intervals in [rrMinMs, rrMaxMs] within the window.
        public let nClean: Int
        /// Count of valid successive pairs (gap < 3 s, both in range) — from rmssdSegmented.
        public let nPairs: Int
        /// True iff an RMSSD was emitted (rmssdMs != nil).
        public var dense: Bool { rmssdMs != nil }

        public init(rmssdMs: Double?, nClean: Int, nPairs: Int) {
            self.rmssdMs = rmssdMs
            self.nClean = nClean
            self.nPairs = nPairs
        }
    }

    /// Compute the night result over the NN intervals whose `ts` falls in
    /// [windowStart, windowEnd] (inclusive; pass nil bounds to use all intervals — in
    /// production R2 the caller has already clipped to the union-of-asleep window).
    ///
    /// nClean counts in-range intervals in the window; (rmssd, nPairs) come from
    /// `HRVAnalyzer.rmssdSegmented` over the SAME windowed intervals (which enforces the range
    /// per-pair, so out-of-range beats are excluded but never bridged across). dense ⇔
    /// nClean ≥ minCleanBeats && nPairs ≥ minSuccessivePairs && rmssd > 0.
    public static func night(intervals: [TimedNN], windowStart: Double?, windowEnd: Double?) -> NightResult {
        let windowed = intervals.filter { s in
            if let a = windowStart, s.ts < a { return false }
            if let b = windowEnd, s.ts > b { return false }
            return true
        }
        let nClean = windowed.reduce(into: 0) { acc, s in
            if s.nnMs >= HRVAnalyzer.rrMinMs && s.nnMs <= HRVAnalyzer.rrMaxMs { acc += 1 }
        }
        let (rmssd, nPairs) = HRVAnalyzer.rmssdSegmented(windowed, gapSeconds: 3)
        let dense = nClean >= minCleanBeats && nPairs >= minSuccessivePairs && (rmssd ?? 0) > 0
        return NightResult(rmssdMs: dense ? rmssd : nil, nClean: nClean, nPairs: nPairs)
    }
}
