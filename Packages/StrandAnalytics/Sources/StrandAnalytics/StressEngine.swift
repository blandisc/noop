import Foundation
import BiometricStreams

// StressEngine.swift — intraday "autonomic activation" (a.k.a. stress) curve, 0–3. APPROXIMATE.
//
// This is the INTRADAY counterpart to the daily `StressModel` (in the app layer). The daily score is
// built from resting HR + sleep HRV against a 30-day baseline — i.e. from the body's calmest, most
// controlled state. That recipe CANNOT be reused minute-by-minute during waking hours: HR rises and
// HRV (RMSSD) falls naturally when you move, talk, or stand, so normalizing the day against a
// resting/sleep baseline would read "maxed out all day", and exercise (effort, not stress) would look
// like peak stress. (Reviewed against the science; the daily-average-≈-daily-scalar idea was dropped.)
//
// The model here is deliberately RELATIVE TO THE PERSON'S OWN WAKING DAY — it answers "which moments
// of *your* day showed the most autonomic activation", not "is today more stressful than yesterday"
// (cross-day comparability is a later phase). It is honest about what it can't see: noisy or active
// windows return `nil` ("no reading") rather than a fabricated value.
//
// Pipeline (per ~windowSeconds bucket):
//   1. Clean RR + compute RMSSD via `HRVAnalyzer` (Task Force 1996 RMSSD; Malik 1989 ectopic cleaning).
//      A bucket whose clean coverage is too low → no reading.
//   2. Exclude ACTIVITY: derive HR from the clean mean NN; a bucket above ~`activeFraction` of HR
//      reserve is effort, not stress → no reading. (Analogous to Firstbeat excluding physical activity
//      before inferring stress.) The engine also accepts caller-supplied excluded spans (sleep and, in
//      FER-377, accelerometer-detected movement) — those buckets are no reading too.
//   3. Map the bucket's RMSSD onto 0–3 against a PERSONAL WAKING REFERENCE (robust percentile anchors
//      built from the recent ~7 days of waking buckets — high RMSSD = calm = 0, low RMSSD = activated
//      = 3), clamped to [0, 3]. Lower RMSSD ⇒ higher stress. The clamp is the absolute floor/ceiling
//      that keeps a genuinely calm day from being stretched into a fake peak (the min-max bug).
//
// The reference anchors come from HISTORY, never recomputed within the day (that would be min-max with
// a new hat). Without enough waking history the reference is `nil` — the caller shows "still learning
// your rhythm" instead of guessing. The reference is built from the SAME windows that pass the same
// gates as the intraday curve, so the scale and the curve agree (one source of truth).
//
// Pure + DB-free: the app layer reads `rrInterval` rows (FER-377) and feeds the arrays in; persisting
// a compact summary for performance and cross-day patterns is FER-378.

public enum StressEngine {

    // MARK: - Tunables
    //
    // Defensible defaults; the exact numbers are meant to be calibrated on device (FER-377) — the
    // model's correctness does not hinge on a specific value, only on the shape.

    /// Bucket width (s). ~3 min: ≥120 s is valid for RMSSD, and the Task Force (1996) short-term HRV
    /// standard is 5 min. Buckets are non-overlapping and epoch-aligned (like `cumulativeStrain`).
    public static let defaultWindowSeconds = 180
    /// Resting HR (bpm) for the HR-reserve activity gate. Caller passes the person's own value.
    public static let defaultRestingHR: Double = 60
    /// Max HR (bpm) for the HR-reserve activity gate. Caller passes the person's own value.
    public static let defaultMaxHR: Double = 190
    /// A bucket whose HR exceeds resting + `activeFraction` × HR-reserve (Karvonen reserve) is treated
    /// as ACTIVITY → no reading. ~35 % HRR is the analogue of Firstbeat's 20–30 % VO₂max "daily
    /// activity" cutoff above which stress/recovery is not inferred.
    public static let defaultActiveFraction: Double = 0.35
    /// Minimum share of a bucket's RR beats that must survive cleaning, else no reading. Guards against
    /// computing RMSSD off mostly-artifact windows (RMSSD is hyper-sensitive to artifacts).
    public static let defaultMinCleanFraction: Double = 0.7
    /// Percentile of waking RMSSD taken as the CALM anchor (high RMSSD ⇒ stress 0).
    public static let calmPercentile: Double = 0.80
    /// Percentile of waking RMSSD taken as the ACTIVATED anchor (low RMSSD ⇒ stress 3).
    public static let activatedPercentile: Double = 0.20
    /// Minimum number of valid waking buckets (across the supplied history) before a reference is
    /// trustworthy. Below this → cold start (`nil`). ~30 buckets needs several days of waking coverage.
    public static let defaultMinReferenceWindows = 30
    /// Minimum RMSSD spread (ms) between the calm and activated anchors. Below this the personal range
    /// is too flat to define a meaningful scale → no reference (avoids a hair-trigger curve).
    public static let defaultMinSpreadMs: Double = 3.0

    // MARK: - Types

    /// Personal waking anchors that define the 0–3 scale. Built from recent waking history, not from
    /// the day being scored.
    public struct WakingReference: Equatable, Sendable {
        /// RMSSD (ms) at `calmPercentile` of waking history — maps to stress 0.
        public let rmssdCalm: Double
        /// RMSSD (ms) at `activatedPercentile` of waking history — maps to stress 3.
        public let rmssdActivated: Double
        /// Number of valid waking buckets the anchors were built from (confidence).
        public let nWindows: Int

        public init(rmssdCalm: Double, rmssdActivated: Double, nWindows: Int) {
            self.rmssdCalm = rmssdCalm
            self.rmssdActivated = rmssdActivated
            self.nWindows = nWindows
        }

        /// Calm − activated RMSSD span (ms); the denominator of the 0–3 mapping. Always ≥ 0.
        public var spread: Double { rmssdCalm - rmssdActivated }
    }

    /// One point of the intraday curve. `stress == nil` means "no reading" for that bucket — too noisy,
    /// during activity, or in an excluded span — never a fabricated value.
    public struct StressPoint: Equatable, Sendable {
        /// Bucket end, wall-clock.
        public let date: Date
        /// Autonomic activation 0–3 (lower RMSSD ⇒ higher), or nil for no reading.
        public let stress: Double?

        public init(date: Date, stress: Double?) {
            self.date = date
            self.stress = stress
        }
    }

    // MARK: - Public API

    /// Build the personal waking reference from several days of RR. Each element of `daysRR` is one
    /// day's `[RRInterval]`; `excludedPerDay[i]` are spans to drop for that day (sleep, and in FER-377
    /// accelerometer-detected movement) as wall-clock epoch seconds — the SAME clock as `RRInterval.ts`.
    /// Returns `nil` on cold start (fewer than `minWindows` valid waking buckets) or when the personal
    /// range is degenerate (`spread` below `minSpreadMs`) — the caller then shows "still learning your
    /// rhythm", never a min-max fallback.
    ///
    /// Buckets are filtered by exactly the same coverage + activity gates as `intradayStress` (both go
    /// through `gatedRMSSD`), so the scale and the curve are one source of truth.
    public static func wakingReference(
        daysRR: [[RRInterval]],
        excludedPerDay: [[ClosedRange<Int>]] = [],
        windowSeconds: Int = defaultWindowSeconds,
        restingHR: Double = defaultRestingHR,
        maxHR: Double = defaultMaxHR,
        activeFraction: Double = defaultActiveFraction,
        minCleanFraction: Double = defaultMinCleanFraction,
        minWindows: Int = defaultMinReferenceWindows,
        minSpreadMs: Double = defaultMinSpreadMs
    ) -> WakingReference? {
        guard windowSeconds > 0 else { return nil }
        var samples: [Double] = []
        for (i, dayRR) in daysRR.enumerated() {
            let excluded = i < excludedPerDay.count ? excludedPerDay[i] : []
            for bucket in bucketize(dayRR, windowSeconds: windowSeconds) {
                if let rmssd = gatedRMSSD(bucket, excluded: excluded, restingHR: restingHR, maxHR: maxHR,
                                          activeFraction: activeFraction, minCleanFraction: minCleanFraction) {
                    samples.append(rmssd)
                }
            }
        }
        guard samples.count >= minWindows else { return nil }
        // Robust percentile anchors (not min/max, so one surviving artifact can't define the scale).
        // Sort once and reuse StrandAnalytics' canonical percentile (`StrainScorer`, pct in 0–100).
        let sorted = samples.sorted()
        let calm = StrainScorer.percentile(sorted, calmPercentile * 100)
        let activated = StrainScorer.percentile(sorted, activatedPercentile * 100)
        guard calm - activated >= minSpreadMs else { return nil }
        return WakingReference(rmssdCalm: calm, rmssdActivated: activated, nWindows: samples.count)
    }

    /// The day's intraday stress curve (0–3) against `reference`. Emits one `StressPoint` per bucket
    /// that has RR data, in time order; `stress` is `nil` for buckets that are too noisy, in activity,
    /// or in an `excluded` span (wall-clock epoch seconds, same clock as `RRInterval.ts`). Returns `[]`
    /// when there is no RR at all.
    public static func intradayStress(
        _ todayRR: [RRInterval],
        reference: WakingReference,
        excluded: [ClosedRange<Int>] = [],
        windowSeconds: Int = defaultWindowSeconds,
        restingHR: Double = defaultRestingHR,
        maxHR: Double = defaultMaxHR,
        activeFraction: Double = defaultActiveFraction,
        minCleanFraction: Double = defaultMinCleanFraction
    ) -> [StressPoint] {
        guard windowSeconds > 0 else { return [] }
        var points: [StressPoint] = []
        for bucket in bucketize(todayRR, windowSeconds: windowSeconds) {
            let date = Date(timeIntervalSince1970: TimeInterval(bucket.end))
            let rmssd = gatedRMSSD(bucket, excluded: excluded, restingHR: restingHR, maxHR: maxHR,
                                   activeFraction: activeFraction, minCleanFraction: minCleanFraction)
            points.append(StressPoint(date: date, stress: rmssd.map { stress(forRMSSD: $0, reference: reference) }))
        }
        return points
    }

    /// Map a clean bucket RMSSD onto 0–3 against the personal anchors, clamped. Lower RMSSD ⇒ higher
    /// stress. The clamp is the absolute floor/ceiling that keeps a calm day from inventing a peak.
    /// Exposed for testing.
    public static func stress(forRMSSD rmssd: Double, reference: WakingReference) -> Double {
        let span = reference.spread
        guard span > 0 else { return 1.5 }
        let s = 3.0 * (reference.rmssdCalm - rmssd) / span
        return min(3.0, max(0.0, s))
    }

    // MARK: - Internals

    /// A non-overlapping, epoch-aligned bucket of RR values (ms) plus its wall-clock bounds.
    struct Bucket { let start: Int; let end: Int; let values: [Double] }

    /// Group RR rows into non-overlapping `windowSeconds` buckets keyed by `ts / windowSeconds`
    /// (epoch-aligned, mirroring `StrainScorer.cumulativeStrain`). One pass; returned in time order.
    /// Buckets with no RR simply don't appear (natural gaps), so the caller renders them as no data.
    static func bucketize(_ rr: [RRInterval], windowSeconds: Int) -> [Bucket] {
        guard windowSeconds > 0 else { return [] }
        var byBucket: [Int: [Double]] = [:]
        for s in rr { byBucket[s.ts / windowSeconds, default: []].append(Double(s.rrMs)) }
        return byBucket.sorted { $0.key < $1.key }.map { k, values in
            Bucket(start: k * windowSeconds, end: (k + 1) * windowSeconds - 1, values: values)
        }
    }

    /// Valid RMSSD for a bucket after the exclusion + coverage/activity gates, else `nil` (no reading).
    /// The single source of truth for "what counts": `wakingReference` and `intradayStress` both go
    /// through here, so the personal scale and the day's curve can never drift apart.
    static func gatedRMSSD(_ bucket: Bucket, excluded: [ClosedRange<Int>],
                           restingHR: Double, maxHR: Double,
                           activeFraction: Double, minCleanFraction: Double) -> Double? {
        if overlapsExcluded(bucket.start, bucket.end, excluded) { return nil }
        return bucketRMSSD(bucket.values, restingHR: restingHR, maxHR: maxHR,
                           activeFraction: activeFraction, minCleanFraction: minCleanFraction)
    }

    /// Clean RMSSD for one bucket, or `nil` when it shouldn't count: too few/too noisy clean beats
    /// (coverage below `minCleanFraction`) or HR above the activity threshold (effort, not stress).
    /// Reuses `HRVAnalyzer` (Task Force 1996 RMSSD + Malik 1989 cleaning) — no HRV math reimplemented.
    static func bucketRMSSD(_ values: [Double], restingHR: Double, maxHR: Double,
                            activeFraction: Double, minCleanFraction: Double) -> Double? {
        let res = HRVAnalyzer.analyze(rawRR: values)
        guard let rmssd = res.rmssd, let meanNN = res.meanNN, meanNN > 0, res.nInput > 0 else { return nil }
        guard Double(res.nClean) / Double(res.nInput) >= minCleanFraction else { return nil }
        // Activity gate: HR from the clean mean NN vs Karvonen HR reserve.
        let hr = 60_000.0 / meanNN
        let reserve = max(1.0, maxHR - restingHR)
        if hr > restingHR + activeFraction * reserve { return nil }
        return rmssd
    }

    /// Whether the bucket `[a, b]` overlaps any excluded wall-clock span.
    static func overlapsExcluded(_ a: Int, _ b: Int, _ spans: [ClosedRange<Int>]) -> Bool {
        for sp in spans where a <= sp.upperBound && sp.lowerBound <= b { return true }
        return false
    }
}
