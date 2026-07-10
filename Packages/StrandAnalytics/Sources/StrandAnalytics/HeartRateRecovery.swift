import Foundation
import WhoopProtocol

// HeartRateRecovery.swift — post-session 60-second heart-rate recovery (HRR-60s). Pure, deterministic,
// DB-free. The safer half of FER-683's athlete pair (the strap is still and PPG is clean once the
// effort stops, unlike the in-motion window DFA-α1 needs).
//
// WHAT IT IS. HRR-60s is how many bpm the heart rate falls in the first minute after a hard effort
// ends — a window dominated by parasympathetic (vagal) REACTIVATION. A faster drop reflects better
// autonomic recovery; a blunted drop tracks fatigue / incomplete recovery.
//
// HONESTY: INTRA-USER TREND, NOT COLE'S CUTOFF. The clinical literature (Cole et al., NEJM 1999;
// abnormal ≤ 12 bpm at 1 min as a mortality predictor; Qiu et al., JAHA 2017, meta-analysis HR ~1.68)
// derives POPULATION cut-offs from graded treadmill tests with a fixed recovery protocol. A wrist
// strap after an arbitrary workout is NOT that protocol, so this engine NEVER applies the 12-bpm cut-off
// or any mortality framing. It reports the bpm drop and compares it ONLY to the user's OWN prior
// sessions (a personal trend). WELLNESS / TRAINING awareness — APPROXIMATE, not a diagnosis.
public enum HeartRateRecovery {

    // MARK: - Tuning constants (pinned by test)

    /// The recovery horizon: HRR at 60 s post-effort.
    public static let horizonS: Int = 60

    /// Half-width (s) of the window around each anchor over which HR is taken as a MEDIAN, so a single
    /// noisy beat at the exact anchor second doesn't swing the drop. The end anchor looks BACK from
    /// cessation (HR is still near peak); the recovery anchor is centered on end + horizon.
    public static let anchorHalfWidthS: Int = 10

    /// Personal-trend z at/below which a session's HRR reads as "blunted vs your normal" (a slower drop
    /// than usual). Same 2σ convention as the other personal-baseline engines. Lower HRR is the
    /// concerning direction.
    public static let bluntedZThreshold: Double = 2.0

    // MARK: - Single-session HRR

    public struct Result: Equatable, Sendable {
        /// bpm the HR fell from cessation to +60 s (positive = it recovered). nil when either anchor
        /// had no HR coverage.
        public let hrrBpm: Double?
        /// Median HR at cessation (the window ending at `sessionEnd`).
        public let hrAtEndBpm: Double?
        /// Median HR at +60 s.
        public let hrAt60sBpm: Double?
        /// True iff both anchors had at least one HR sample (so `hrrBpm` is defined).
        public let covered: Bool

        public init(hrrBpm: Double?, hrAtEndBpm: Double?, hrAt60sBpm: Double?, covered: Bool) {
            self.hrrBpm = hrrBpm; self.hrAtEndBpm = hrAtEndBpm
            self.hrAt60sBpm = hrAt60sBpm; self.covered = covered
        }
    }

    /// HRR-60s for a session that ended at `sessionEnd` (unix seconds — e.g. `ExerciseSession.end` from
    /// `WorkoutDetector`), from the surrounding HR stream. The end HR is the median over
    /// [end − 2·halfWidth, end] (looking back into the effort); the recovery HR is the median over
    /// [end + 60 − halfWidth, end + 60 + halfWidth]. Returns an uncovered result when either window is
    /// empty (a gap in the HR stream), so a missing tail never fabricates a drop.
    public static func hrr60s(sessionEnd: Int, hr: [HRSample]) -> Result {
        let endLo = sessionEnd - 2 * anchorHalfWidthS
        let endHi = sessionEnd
        let recLo = sessionEnd + horizonS - anchorHalfWidthS
        let recHi = sessionEnd + horizonS + anchorHalfWidthS

        let endSamples = hr.filter { $0.ts >= endLo && $0.ts <= endHi }.map { Double($0.bpm) }
        let recSamples = hr.filter { $0.ts >= recLo && $0.ts <= recHi }.map { Double($0.bpm) }

        guard let endHR = median(endSamples), let recHR = median(recSamples) else {
            return Result(hrrBpm: nil,
                          hrAtEndBpm: median(endSamples),
                          hrAt60sBpm: median(recSamples),
                          covered: false)
        }
        return Result(hrrBpm: endHR - recHR, hrAtEndBpm: endHR, hrAt60sBpm: recHR, covered: true)
    }

    // MARK: - Personal trend

    public struct Trend: Equatable, Sendable {
        /// Signed z of the latest HRR vs the user's prior sessions (+ = faster/better than normal,
        /// − = slower/blunted). nil when the history is too small/flat to estimate dispersion.
        public let z: Double?
        /// Personal mean HRR (bpm) over the prior sessions.
        public let baselineBpm: Double?
        /// True iff the latest HRR is at least `bluntedZThreshold` σ BELOW the personal mean.
        public let bluntedVsNormal: Bool
        /// Prior sessions backing the trend.
        public let nPrior: Int
        /// One-line non-clinical, intra-user copy.
        public let note: String

        public init(z: Double?, baselineBpm: Double?, bluntedVsNormal: Bool, nPrior: Int, note: String) {
            self.z = z; self.baselineBpm = baselineBpm; self.bluntedVsNormal = bluntedVsNormal
            self.nPrior = nPrior; self.note = note
        }
    }

    /// Place the `latest` HRR against the user's OWN prior HRR values (bpm). Lower is the concerning
    /// direction (blunted vagal reactivation). Uses the robust σ estimator shared with `IllnessWatch`
    /// (1.253 × mean-abs-dev); returns a nil z when the history can't support a dispersion estimate.
    /// Explicitly an intra-user comparison — never Cole's population cut-off.
    public static func trend(latest: Double, priorHRR: [Double]) -> Trend {
        guard priorHRR.count >= 2 else {
            return Trend(z: nil, baselineBpm: priorHRR.first, bluntedVsNormal: false, nPrior: priorHRR.count,
                         note: "Still learning your usual recovery - keep logging sessions.")
        }
        let mean = priorHRR.reduce(0, +) / Double(priorHRR.count)
        let sigma = IllnessWatch.robustSigma(priorHRR)
        guard sigma > 1e-9 else {
            return Trend(z: nil, baselineBpm: mean, bluntedVsNormal: false, nPrior: priorHRR.count,
                         note: "Your recovery has been very steady - not enough spread to trend yet.")
        }
        let z = (latest - mean) / sigma
        let blunted = z <= -bluntedZThreshold
        let note: String
        if blunted {
            note = "Your heart came down slower than your usual after this one - a sign to watch recovery."
        } else if z >= bluntedZThreshold {
            note = "Your heart came down faster than usual - strong recovery after this session."
        } else {
            note = "Your recovery after this session looks like your normal."
        }
        return Trend(z: z, baselineBpm: mean, bluntedVsNormal: blunted, nPrior: priorHRR.count, note: note)
    }

    // MARK: - Helpers

    /// Median of the values, or nil when empty.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0
    }
}
