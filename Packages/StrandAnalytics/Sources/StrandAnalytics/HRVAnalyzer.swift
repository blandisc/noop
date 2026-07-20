import Foundation
import BiometricStreams

// HRVAnalyzer.swift — RMSSD + SDNN from RR intervals with cleaning.
//
// Ported from server/ingest/app/analysis/hrv.py. The Task Force (1996) RMSSD and
// SDNN definitions are reproduced exactly:
//
//   RMSSD = sqrt( mean( (NN[i+1] − NN[i])^2 ) )           (Task Force 1996)
//   SDNN  = sample standard deviation of NN (ddof = 1)     (Task Force 1996)
//
// Cleaning pipeline:
//   1. Range filter: drop intervals outside [RR_MIN_MS, RR_MAX_MS] = [300, 2000] ms.
//   2. Ectopic rejection: drop beats whose RR deviates > ~20% from a local median
//      (Malik-style filter).
//   3. Require >= MIN_BEATS (20) valid intervals before a trustworthy result.
//
// NOTE: the Python source runs neurokit2's Kubios / Lipponen–Tarvainen (2019)
// artifact classifier, which is unavailable on-device. We substitute the
// classical Malik 20% local-median rule (Malik et al. 1989), the most widely
// cited ectopic-rejection heuristic. This is a simpler, fully-deterministic
// approximation of the same intent — remove physiologically impossible
// beat-to-beat jumps before computing HRV — at the cost of not modelling the
// missed/extra-beat insertion that Kubios does.

/// A single NN (normal-to-normal) interval stamped with the epoch SECOND it ends on.
/// Foundation-only; used by the segmented nocturnal RMSSD path where the temporal gap
/// between successive intervals decides whether a pair is truly beat-to-beat.
public struct TimedNN: Equatable, Sendable {
    public let ts: Double       // epoch seconds — FRACTIONAL. Apple's beat reader is sub-second; truncating
                                // to whole seconds would collapse two <1 s-apart beats onto the same tick
                                // (dt = 0) and silently drop valid successive pairs, HR-dependently.
    public let nnMs: Double     // NN interval in milliseconds
    public init(ts: Double, nnMs: Double) { self.ts = ts; self.nnMs = nnMs }
}

public enum HRVAnalyzer {

    /// Minimum plausible RR interval (ms) — 300 ms ≈ 200 bpm.
    public static let rrMinMs: Double = 300
    /// Maximum plausible RR interval (ms) — 2000 ms ≈ 30 bpm.
    public static let rrMaxMs: Double = 2000
    /// Minimum valid intervals required for a trustworthy RMSSD/SDNN.
    public static let minBeats: Int = 20
    /// Malik-style ectopic threshold: a beat deviating more than this fraction
    /// from the local median is rejected. 0.20 == 20%.
    public static let ectopicThreshold: Double = 0.20
    /// Half-width (in beats) of the local-median window used for ectopic rejection.
    /// A window of 2*radius+1 beats (5 beats at radius 2) matches the common
    /// Malik moving-window implementations.
    public static let ectopicWindowRadius: Int = 2

    /// Successive-difference artifact threshold for the SEGMENTED nocturnal path (FER-1003 science
    /// gate). A beat-to-beat change exceeding this fraction of the shorter interval is rejected as an
    /// artifact — a wrist-PPG missed/extra beat or ectopic — before it can dominate the L2 RMSSD sum.
    /// The segmented path runs on gappy, non-contiguous wrist beats where a 5-beat local-median (Malik)
    /// is unreliable, so this pairwise successive-difference rule is its artifact defense (Task Force
    /// 1996 requires artifact editing BEFORE RMSSD; RMSSD is L2, so one huge Δ dominates a whole night).
    /// Same 0.20 as `ectopicThreshold` by design — a >20% successive jump (>~240 ms at a bradycardic
    /// 1200 ms RR) is beyond physiological RSA even in sleep — but a DISTINCT filter (pairwise, not
    /// median). RELATIVE (not an absolute ms cap) so genuine high-RSA bradycardic nights are preserved.
    /// Validated on 46 real nights (R0 harness): idle on clean nights (ΔRMSSD=0 where no pair is
    /// rejected), corrects the ~7 artifact-flipped directions; 15% over-rejects (eats real RSA), 25%
    /// is ~equivalent. Rejected pairs are dropped, never bridged.
    public static let maxSuccessiveDeltaFraction: Double = 0.20

    /// Result of an HRV computation over a window.
    public struct HRVResult: Equatable, Sendable {
        /// RMSSD in milliseconds, or nil when too few valid beats.
        public let rmssd: Double?
        /// SDNN (sample SD, ddof=1) in milliseconds, or nil when too few valid beats.
        public let sdnn: Double?
        /// Mean NN interval (ms) over the cleaned beats, or nil.
        public let meanNN: Double?
        /// pNN50: % of successive |ΔNN| > 50 ms, or nil.
        public let pnn50: Double?
        /// Count of RR intervals supplied to the analysis (before cleaning).
        public let nInput: Int
        /// Count of clean NN intervals after range + ectopic filtering.
        public let nClean: Int

        public init(rmssd: Double?, sdnn: Double?, meanNN: Double?, pnn50: Double?,
                    nInput: Int, nClean: Int) {
            self.rmssd = rmssd
            self.sdnn = sdnn
            self.meanNN = meanNN
            self.pnn50 = pnn50
            self.nInput = nInput
            self.nClean = nClean
        }

        /// An empty/insufficient-data result that preserves the input count.
        static func empty(nInput: Int) -> HRVResult {
            HRVResult(rmssd: nil, sdnn: nil, meanNN: nil, pnn50: nil,
                      nInput: nInput, nClean: 0)
        }
    }

    // MARK: - Primitive Task Force statistics (no filtering)

    /// Task Force (1996) RMSSD over already-clean NN intervals (ms). Returns nil
    /// when fewer than 2 values (no successive differences). No filtering applied.
    public static func rmssdRaw(_ nn: [Double]) -> Double? {
        guard nn.count >= 2 else { return nil }
        var sumSq = 0.0
        for i in 1..<nn.count {
            let d = nn[i] - nn[i - 1]
            sumSq += d * d
        }
        return (sumSq / Double(nn.count - 1)).squareRoot()
    }

    /// Segmented RMSSD (Task Force 1996) that only counts a successive pair (i-1 → i)
    /// when it is genuinely beat-to-beat: the two NN intervals are adjacent in time
    /// (0 < ts[i] − ts[i-1] < gapSeconds) AND both lie in the plausible range
    /// [rrMinMs, rrMaxMs]. A pair that crosses a recording gap, or that touches an
    /// out-of-range (artefact) interval, is NOT beat-to-beat and is excluded — it is
    /// never bridged across (we do not remove the artefact and pair its neighbours).
    /// The divisor is the number of VALID pairs (not n−1), so a night stitched from many
    /// short asleep segments is scored only on its real successive differences. Malik
    /// ectopic rejection is deliberately NOT applied on the nocturnal path (sparse wrist
    /// PPG; a second local-median filter would eat real beats). Returns nil rmssd when
    /// fewer than 1 valid pair. Input is sorted by ts ascending (ties broken by nnMs, so
    /// the result is deterministic) before segmenting; a tie in ts yields Δ = 0 and is
    /// excluded (0 < Δ required).
    public static func rmssdSegmented(_ nn: [TimedNN], gapSeconds: Int = 3,
                                      deltaFraction: Double = maxSuccessiveDeltaFraction) -> (rmssd: Double?, nPairs: Int) {
        guard nn.count >= 2 else { return (nil, 0) }
        let sorted = nn.sorted { $0.ts != $1.ts ? $0.ts < $1.ts : $0.nnMs < $1.nnMs }
        var sumSq = 0.0
        var nPairs = 0
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let cur = sorted[i]
            let dt = cur.ts - prev.ts
            guard dt > 0 && dt < Double(gapSeconds) else { continue }
            guard prev.nnMs >= rrMinMs && prev.nnMs <= rrMaxMs else { continue }
            guard cur.nnMs >= rrMinMs && cur.nnMs <= rrMaxMs else { continue }
            let d = cur.nnMs - prev.nnMs
            // Artifact rejection (see `maxSuccessiveDeltaFraction`): a wrist-PPG missed/extra beat puts
            // one huge in-range Δ into this L2 sum and inflates the whole night's RMSSD. Reject the pair
            // when the beat-to-beat change exceeds `deltaFraction` of the shorter interval. Both pairs
            // touching an artifact beat exceed it, so the artifact's influence is dropped entirely; the
            // pair is not counted (it is not a valid successive pair) and never bridged.
            guard abs(d) <= deltaFraction * Swift.min(prev.nnMs, cur.nnMs) else { continue }
            sumSq += d * d
            nPairs += 1
        }
        guard nPairs >= 1 else { return (nil, nPairs) }
        return ((sumSq / Double(nPairs)).squareRoot(), nPairs)
    }

    /// Sample standard deviation (ddof = 1) of NN intervals (ms). Returns nil for
    /// fewer than 2 values. Matches neurokit2 HRV_SDNN. No filtering applied.
    public static func sdnnRaw(_ nn: [Double]) -> Double? {
        guard nn.count >= 2 else { return nil }
        let mean = nn.reduce(0, +) / Double(nn.count)
        var ss = 0.0
        for v in nn { let d = v - mean; ss += d * d }
        return (ss / Double(nn.count - 1)).squareRoot()
    }

    // MARK: - Cleaning

    /// Range filter: keep only intervals in [rrMinMs, rrMaxMs], preserving order.
    public static func rangeFilter(_ rr: [Double]) -> [Double] {
        rr.filter { $0 >= rrMinMs && $0 <= rrMaxMs }
    }

    /// Malik-style ectopic rejection: drop any beat that deviates from its local
    /// median by more than `ectopicThreshold` (20%). The local median is taken
    /// over a centered window of `2*ectopicWindowRadius+1` beats (excluding the
    /// beat under test). Beats with too small a neighbourhood are kept.
    ///
    /// NOTE: this replaces neurokit2's Kubios classifier (see file header).
    public static func rejectEctopic(_ nn: [Double]) -> [Double] {
        guard nn.count > ectopicWindowRadius else { return nn }
        var kept: [Double] = []
        kept.reserveCapacity(nn.count)
        for i in 0..<nn.count {
            let lo = max(0, i - ectopicWindowRadius)
            let hi = min(nn.count - 1, i + ectopicWindowRadius)
            var neighbours: [Double] = []
            neighbours.reserveCapacity(hi - lo)
            for j in lo...hi where j != i { neighbours.append(nn[j]) }
            guard neighbours.count >= 2 else { kept.append(nn[i]); continue }
            let med = median(neighbours)
            if med <= 0 { kept.append(nn[i]); continue }
            let deviation = abs(nn[i] - med) / med
            if deviation <= ectopicThreshold {
                kept.append(nn[i])
            }
            // else: drop this beat as ectopic.
        }
        return kept
    }

    /// Full clean: range filter → ectopic rejection. Returns the clean NN series.
    public static func cleanRR(_ rr: [Double]) -> [Double] {
        rejectEctopic(rangeFilter(rr))
    }

    // MARK: - Windowed analysis

    /// Compute HRV (RMSSD/SDNN/meanNN/pNN50) over the RR intervals whose ts falls
    /// in [windowStart, windowEnd] (inclusive). Pass nil bounds to use all rows.
    ///
    /// Applies the range filter, Malik ectopic rejection, then requires
    /// `minBeats` clean intervals; otherwise returns an empty result.
    public static func analyze(_ rr: [RRInterval],
                               windowStart: Int? = nil,
                               windowEnd: Int? = nil) -> HRVResult {
        let inWindow = rr.filter { sample in
            if let s = windowStart, sample.ts < s { return false }
            if let e = windowEnd, sample.ts > e { return false }
            return true
        }
        let raw = inWindow.map { Double($0.rrMs) }
        return analyze(rawRR: raw)
    }

    /// Compute HRV from raw RR-interval values (ms), applying the full cleaning
    /// pipeline. Returns an empty result when fewer than `minBeats` survive.
    public static func analyze(rawRR: [Double]) -> HRVResult {
        let nInput = rawRR.count
        let clean = cleanRR(rawRR)
        guard clean.count >= minBeats else {
            return .empty(nInput: nInput)
        }
        let rmssd = rmssdRaw(clean)
        let sdnn = sdnnRaw(clean)
        let mean = clean.reduce(0, +) / Double(clean.count)

        // pNN50 over the clean NN series. There are clean.count − 1 successive
        // pairs; the `minBeats` gate above keeps that ≥ 1, but guard the divisor
        // explicitly so the formula is safe regardless of `minBeats`.
        var nn50 = 0
        for i in 1..<clean.count where abs(clean[i] - clean[i - 1]) > 50.0 { nn50 += 1 }
        let nnPairs = clean.count - 1
        let pnn50 = nnPairs > 0 ? Double(nn50) / Double(nnPairs) * 100.0 : 0.0

        return HRVResult(rmssd: rmssd, sdnn: sdnn, meanNN: mean, pnn50: pnn50,
                         nInput: nInput, nClean: clean.count)
    }

    // MARK: - Helpers

    /// Median of a non-empty array. (Caller guarantees non-empty.)
    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        let n = s.count
        if n == 0 { return 0 }
        if n % 2 == 1 { return s[n / 2] }
        return (s[n / 2 - 1] + s[n / 2]) / 2.0
    }
}
