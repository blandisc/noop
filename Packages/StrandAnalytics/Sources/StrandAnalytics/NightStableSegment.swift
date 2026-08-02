import Foundation

/// NightStableSegment — locate the longest *stable* stretch of a night from the heart-rate
/// signal itself, WITHOUT trusting Apple's sleep-stage labels (FER-1048, plan v4 · fase 1b).
///
/// ## Why (and why not "deep sleep")
/// The nocturnal nadir — the lowest sustained resting rate — lives in the quiet, deep stretch of
/// the night. `NocturnalRestingHR` used to reach it via Apple's `deep` stage subset, but that label
/// is weak on Apple Watch: Schyvens 2025 (*SLEEP Adv* 6(2):zpaf021) measures N3 sensitivity of
/// **50.66 %** and κ=0.53 (S8). Herzig 2018 (*Front Physiol* 8:1100) motivates finding the stable
/// stretch from the signal instead — HRV is more reproducible in SWS (ICC 0.84) and an HRV-based
/// algorithm localised SWS 87 % of the time without PSG.
///
/// **We do NOT claim to reproduce that 87 %.** This detector is deliberately simpler (low rate +
/// low local variability) and its accuracy is UNMEASURED. Herzig justifies *why* to seek the stable
/// stretch, not *how well* we find it. The copy must call this the **"tramo estable"**, never
/// "sueño profundo".
///
/// ## What it returns
/// The `[start, end]` (unix seconds) of the longest run of "quiet" samples whose total span is at
/// least `minDurationSec`, or `nil` when the night never settles. It takes ONLY heart-rate samples —
/// no `stagesJSON`, no hypnogram — so the result cannot depend on Apple's staging (CA3).
///
/// ## Method (closed in the spec — do not change without re-gating the CAs)
///  1. Sort by `ts`; drop `bpm < 30 || bpm > 120` (optical-PPG artifacts, same gate as
///     `NocturnalRestingHR`).
///  2. Smooth with a **centered** moving average over a `smoothWindowSec` time window. Centered (not
///     trailing) because this is offline analysis over a whole night — there is no reason to add
///     phase lag to the segment boundaries. The window is **temporal**, not a fixed sample count,
///     because Apple samples HR irregularly during sleep (roughly every 5 min, the band far finer).
///  3. Median + MAD (median absolute deviation) of the SMOOTHED series — a robust center/spread that
///     a handful of restless minutes can't drag.
///  4. Mark a sample "quiet" when its smoothed value is `<= median` (in the lower half of the night)
///     AND its local step `|smoothed[i] − smoothed[i−1]|` is `<= MAD` (locally flat). The first
///     sample has no predecessor → local step 0.
///  5. Return the longest **time-contiguous** run of quiet samples with span `>= minDurationSec`. A
///     run breaks on a non-quiet sample OR on a time gap `> maxGapSec` (missing data must not be
///     bridged into a fake segment). Ties → the earliest run.
///
/// Pure and deterministic: Foundation-only, no `Date()`, no I/O (CA4). Same input → same output.
public enum NightStableSegment {

    /// One wrist HR sample (a timestamp and a rate). No stage label — by construction the detector
    /// cannot see, and so cannot depend on, Apple's hypnogram (CA3).
    public struct Sample: Sendable, Equatable {
        /// Unix seconds.
        public let ts: Int
        /// Heart rate in beats per minute.
        public let bpm: Double
        public init(ts: Int, bpm: Double) {
            self.ts = ts
            self.bpm = bpm
        }
    }

    /// Minimum span of a stable stretch (seconds). 20 min: below this the low quantile taken over the
    /// stretch has too few samples to be robust. Product-calibration, not a published value.
    public static let minDurationSec: Int = 1200

    /// Width of the centered moving average used to smooth the series before searching (seconds).
    public static let smoothWindowSec: Int = 300

    /// Largest gap (seconds) two consecutive quiet samples may have while still counting as one
    /// contiguous run. Beyond this the night has a data hole the smoothing window can't span, so it
    /// starts a new run rather than reporting a stable stretch that was never actually sampled. Set to
    /// twice `smoothWindowSec` so Apple's irregular ~5-min sleep sampling (occasional 300 s+ gaps)
    /// stays contiguous while a genuine multi-minute dropout breaks the run.
    public static let maxGapSec: Int = 600

    /// The `[start, end]` (unix s) of the longest stable stretch, or `nil` if the night never
    /// settles into one lasting at least `minDurationSec`. See the type doc for the full method.
    public static func find(_ samples: [Sample]) -> (start: Int, end: Int)? {
        // 1. Sort + artifact filter (same physiological band as NocturnalRestingHR).
        let clean = samples
            .filter { $0.bpm >= 30 && $0.bpm <= 120 }
            .sorted { $0.ts < $1.ts }
        guard clean.count >= 2 else { return nil }

        // 2. Centered moving average over a temporal window (half-width each side).
        let smoothed = centeredMovingAverage(clean, windowSec: smoothWindowSec)

        // 3. Median + MAD of the smoothed series.
        let med = median(smoothed)
        let mad = median(smoothed.map { abs($0 - med) })

        // 4. Quiet mask: in the lower half AND locally flat.
        var quiet = [Bool](repeating: false, count: clean.count)
        for i in clean.indices {
            let localStep = i == 0 ? 0 : abs(smoothed[i] - smoothed[i - 1])
            quiet[i] = smoothed[i] <= med && localStep <= mad
        }

        // 5. Longest time-contiguous quiet run whose span >= minDurationSec. A run breaks on a
        //    non-quiet sample or a time gap > maxGapSec. Earliest run wins ties.
        var best: (start: Int, end: Int)? = nil
        var bestSpan = -1
        var runStartIdx: Int? = nil
        func closeRun(_ endIdx: Int) {
            guard let s = runStartIdx else { return }
            let span = clean[endIdx].ts - clean[s].ts
            if span >= minDurationSec && span > bestSpan {
                bestSpan = span
                best = (clean[s].ts, clean[endIdx].ts)
            }
            runStartIdx = nil
        }
        for i in clean.indices {
            if !quiet[i] { closeRun(i - 1); continue }
            if runStartIdx == nil {
                runStartIdx = i
            } else if clean[i].ts - clean[i - 1].ts > maxGapSec {
                // Data hole: end the previous run, start a new one at this sample.
                closeRun(i - 1)
                runStartIdx = i
            }
        }
        closeRun(clean.count - 1)
        return best
    }

    // MARK: - Helpers (pure)

    /// Centered moving average: each output is the mean of every sample within `windowSec/2` seconds
    /// on either side of the sample's own timestamp. Irregular spacing is handled by comparing
    /// timestamps, not indices. Input must be sorted by `ts`.
    private static func centeredMovingAverage(_ s: [Sample], windowSec: Int) -> [Double] {
        let half = windowSec / 2
        var out = [Double](repeating: 0, count: s.count)
        var lo = 0, hi = 0
        for i in s.indices {
            let t = s[i].ts
            while lo < s.count && s[lo].ts < t - half { lo += 1 }
            if hi < i { hi = i }
            while hi + 1 < s.count && s[hi + 1].ts <= t + half { hi += 1 }
            var sum = 0.0
            var n = 0
            for j in lo...hi { sum += s[j].bpm; n += 1 }
            out[i] = sum / Double(n)
        }
        return out
    }

    /// Median of a non-empty array (type-7 midpoint for even counts). Empty → 0 (unreachable: callers
    /// guard `count >= 2`).
    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }
}
