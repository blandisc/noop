import Foundation
import WhoopProtocol

// SleepStager.swift — sleep/wake detection + APPROXIMATE 4-class staging.
//
// Ported from server/ingest/app/analysis/sleep.py and sleep_features.py.
//
// HONEST HEDGING: these stages are APPROXIMATIONS, not PSG-validated, not medical
// advice. The EEG-free 4-class ceiling is ~65–73% epoch agreement (Walch 2019).
// Light/deep separation is the weakest link — deep-minute estimates are the least
// reliable output.
//
// Pipeline (30 s epochs):
//   Stage 0  gravity-stillness sleep/wake spine → in-bed sessions. Cole–Kripke
//            (te Lindert 30 s) computed as a citable cross-check; HR confirms runs.
//   Stage 1  per-epoch cardiorespiratory features over a rolling 5-min window
//            (mean HR, DoG-HR variability, RMSSD/SDNN from RR, resp rate + RRV).
//   Stage 2  transparent percentile-band classifier → {wake, light, deep, rem}.
//   Stage 3  median smoothing + physiology re-imposition (no early REM, deep in
//            the first third of the night).
//
// NOTE: the Python source computes RMSSD/SDNN/HF/LF/LFHF via neurokit2 per epoch.
// On-device we have no neurokit2/scipy, so frequency-domain features (HF, LF/HF)
// are omitted and the parasympathetic-tone signal is RMSSD only. Respiration rate
// + RRV are derived from the raw 1 Hz resp channel with a simple peak detector
// (the Python source explicitly derives these "robustly ourselves" too, so this
// path is a faithful port rather than an approximation). The classifier seam,
// percentile bands, smoothing, and physiology rules are reproduced exactly.

// MARK: - Public output shapes

/// A contiguous sleep-stage segment. Times are wall-clock unix seconds.
public struct StageSegment: Equatable, Sendable, Codable {
    public var start: Int
    public var end: Int
    public var stage: String  // "wake" | "light" | "deep" | "rem"
    public init(start: Int, end: Int, stage: String) {
        self.start = start; self.end = end; self.stage = stage
    }
}

/// A detected sleep session (in-bed span) with APPROXIMATE staging.
public struct SleepSession: Equatable, Sendable {
    public let start: Int
    public let end: Int
    /// asleep / in-bed in [0, 1] (AASM TST/TIB; asleep = in-bed − wake).
    public let efficiency: Double
    public let stages: [StageSegment]
    /// Lowest 5-min rolling-mean HR during the session (bpm), or nil.
    public let restingHR: Int?
    /// Mean RMSSD over 5-min windows across the session (ms), or nil.
    public let avgHRV: Double?

    public init(start: Int, end: Int, efficiency: Double, stages: [StageSegment],
                restingHR: Int?, avgHRV: Double?) {
        self.start = start; self.end = end; self.efficiency = efficiency
        self.stages = stages; self.restingHR = restingHR; self.avgHRV = avgHRV
    }
}

public enum SleepStager {

    // MARK: - Stage 0 constants (sleep.py)

    /// Per-sample gravity change (g) at/below which a sample is "still".
    public static let gravityStillThresholdG: Double = 0.01
    /// Rolling stillness window (minutes).
    public static let stillWindowMin: Int = 15
    /// Fraction of still samples to call the window-center "sleep".
    public static let stillFraction: Double = 0.70
    /// Data gap (minutes) that always breaks a run.
    public static let maxGapMin: Int = 20
    /// Runs shorter than this (minutes) are absorbed into neighbours.
    public static let mergeMin: Int = 15
    /// A sleep run must exceed this (minutes) to count as a session.
    public static let minSleepMin: Int = 60
    /// Assumed sample interval (seconds) when not inferable.
    public static let defaultIntervalS: Double = 60.0

    // MARK: - Daytime false-sleep guard (#90)

    // A long, still, sedentary daytime stretch (reading, a desk, a sofa) is gravity-
    // indistinguishable from a real nap, so the gravity spine alone misclassifies it as
    // sleep. The fix is NOT to drop daytime sleep — real naps are legitimate sessions —
    // but to hold a window whose CENTER falls in the local daytime band to a stricter bar:
    // it must be long enough to be a real nap AND show a genuine cardiac dip (a sedentary
    // stretch keeps a near-baseline HR). Overnight windows are UNCHANGED.

    /// Local hour (inclusive) at which the stricter daytime bar begins.
    public static let daytimeBandStartHour: Int = 11
    /// Local hour (exclusive) at which the stricter daytime bar ends. A window whose center
    /// is in [start, end) local hours is "daytime"; everything else is "overnight".
    public static let daytimeBandEndHour: Int = 20
    /// A still sleep run that resumes within this gap of an overnight sleep chain is the
    /// night's TAIL — a late wake past the daytime-band start, or a brief morning stir then
    /// back to sleep — not an isolated daytime nap, so it skips the daytime guard. Without
    /// this, a real sleep that ran past ~11:00 local had its tail rejected as a "nap" and the
    /// displayed wake time was truncated to late morning (late sleepers / shift workers).
    // Reimplemented from @vulnix0x4's PR #353.
    public static let nightContinuationGapMin: Int = 90
    /// A daytime window must run at least this long (minutes) to count — short still
    /// daytime stretches are the dominant false-positive and are rejected outright.
    public static let daytimeMinSleepMin: Int = 90
    /// A daytime window's resting HR (lowest 5-min rolling mean) must be at or below
    /// baseline × this to confirm a real cardiac dip. Stricter than the overnight 1.05:
    /// a true nap dips BELOW the waking-day median, sedentary stillness does not.
    public static let daytimeRestingHRMult: Double = 0.95
    /// Seconds in a calendar day (for local-hour-of-day arithmetic).
    static let secondsPerDay: Int = 86_400
    /// Floor on the rolling-window size in samples.
    public static let minWindowSamples: Int = 3
    /// A run is HR-confirmed only if mean HR ≤ baseline × this.
    public static let hrSleepBaselineMult: Double = 1.05
    /// Skip HR refinement (trust gravity) when fewer than this many HR samples.
    public static let hrRefineMinSamples: Int = 30
    /// Consecutive sleep epochs required to declare onset.
    public static let onsetPersistEpochs: Int = 3

    // MARK: - H4 physiological in-bed span cap (#547 / #531 / #509 / tail)

    /// Maximum plausible in-bed span (seconds) for a SINGLE assembled main-sleep run. No real single night
    /// runs longer than this: a 12 h+ "sleep" is a bad-clock artefact (a stale/duplicated timestamp range,
    /// or a strap that banked one frozen still stretch under a wrong clock) reading as one enormous still
    /// block — which then reports a 12 h sleep and poisons Rest / the debt ledger / the headline. 16 h is
    /// well above any genuine night (incl. recovery/illness sleeps and late weekend lie-ins) yet below the
    /// clock-artefact range. A run whose span exceeds this is DROPPED (not silently truncated to 16 h, which
    /// would fabricate a wake time): an over-long block is not trustworthy enough to assert a span for at
    /// all. (#547 / #531 / #509 tail)
    public static let maxMainSleepSpanS: Int = 16 * 60 * 60

    // MARK: - H7 morning-stillness nap suppression (#531)

    // After a real overnight wake the wrist is often still (sitting with coffee, back in bed scrolling, a
    // sofa) for a stretch the gravity spine reads as a fresh "nap" — #531's 9 am phantom nap right after
    // the night ended. It is NOT a night-tail continuation (that is handled by `nightContinuationGapMin` and
    // exempted), and it can clear the ordinary daytime guard (it is long + the post-wake HR is still low), so
    // it slipped through. H7 holds a daytime block that BEGINS within `morningStillnessWindowMin` of the
    // just-detected overnight wake to a STRONGER bar than an ordinary daytime nap: it must show a genuine
    // SUSTAINED re-onset — a real second sleep dips clearly below the day median, not merely near it.

    /// A daytime block whose onset falls within this many minutes AFTER an overnight chain's wake is treated
    /// as suspected morning residual stillness and held to the stronger re-onset bar below. ~3 h covers the
    /// post-wake window where residual stillness masquerades as a nap; a genuine afternoon nap (hours later)
    /// is past it and faces only the ordinary daytime guard. (#531)
    public static let morningStillnessWindowMin: Int = 180

    /// The stronger resting-HR bar (× day baseline) a suspected-morning-stillness block must clear to be kept
    /// as a real re-onset. Stricter than the ordinary daytime `daytimeRestingHRMult` (0.95): residual waking
    /// stillness keeps a near-waking HR, so only a block that dips clearly (a true second sleep) survives.
    public static let morningReonsetRestingHRMult: Double = 0.90

    /// The persisted v18 BAND sleep_state value that means "asleep" (Interpreter's `(sb>>4)&3`: 0 wake /
    /// 1 still / 2 asleep / 3 up). The strap's OWN scored band state — an independent anchor we CONSUME to
    /// confirm a borderline morning re-onset (H7) without re-deriving anything. (#531 / H8 consume)
    public static let bandStateAsleep: Int = 2

    /// Fraction of a suspected-morning-stillness block's epochs whose persisted band sleep_state must read
    /// "asleep" (`bandStateAsleep`) for the strap's OWN signal to CONFIRM a genuine re-onset and KEEP the
    /// block even when its HR dip is borderline. A real second sleep the strap itself scored asleep is a
    /// strong, honest anchor; a residual-stillness false nap reads "still"/"up", not "asleep". ≥0.6 keeps
    /// this conservative. (H8 consume)
    public static let morningReonsetBandAsleepFrac: Double = 0.6

    // MARK: - Off-wrist backstop (#500)

    // A wrist-OFF stretch reads as perfectly still gravity with no contrary motion, so the gravity spine
    // classifies it as sleep — and because the off-wrist epochs carry zero/missing HR the daytime guard
    // treats them as "missing data" and lets them through (a daytime desk-off strap logged a phantom sleep).
    // The backstop measures OFF-WRIST COVERAGE: while the strap is worn it emits ~1 Hz HR, so a long
    // CONTIGUOUS gap in the HR samples spanning part of a candidate sleep run is a strong off-wrist proxy
    // that works even when explicit WRIST_OFF events are absent; explicit WRIST_OFF→WRIST_ON intervals (when
    // the store surfaces them) sharpen it. A run is dropped only when that coverage reaches
    // maxOffWristSleepFraction of its duration (the FRACTIONAL rule from j0b-dev's #504), so a real night
    // that over-extends into a SHORT off-wrist tail survives. This is independent of the daytime band, and a
    // night-tail continuation does NOT exempt it.

    /// A contiguous HR-sample gap of at least this many minutes contributes to a candidate run's off-wrist
    /// coverage. Sized at maxGapMin so a real worn night (dense ~1 Hz HR, or PPG-derived HR on a 5/MG)
    /// contributes ~no gap, but a wrist-off stretch (HR flatlines to no samples) contributes its whole span.
    public static let offWristHRGapMin: Int = 20

    /// FRACTIONAL off-wrist rejection (#500), design credited to j0b-dev's #504 analysis. A candidate sleep
    /// run is dropped ONLY when its off-wrist coverage — the UNION of its long HR-gap spans and any
    /// WRIST_OFF→WRIST_ON intervals overlapping it — is at least this fraction of its duration. 0.5 keeps a
    /// real night that over-extends into a SHORT (<50%) off-wrist morning tail while still dropping an
    /// all-day desk strap (≈100% gap) or a session genuinely spent off-wrist.
    public static let maxOffWristSleepFraction: Double = 0.5

    /// Minimum average HR-stream density for the off-wrist HR-gap proxy to be trusted (#507). The proxy reads
    /// a >`offWristHRGapMin`-minute hole in HR as "off the wrist" — valid only when HR is otherwise dense
    /// (live 5/MG, or a worn night with continuous HR), so a real gap is anomalous. A WHOOP 4.0's SYNCED
    /// night is reconstructed mostly from MOTION with sparse, derived HR, whose natural gaps would otherwise
    /// read as off-wrist and wrongly DROP a real night. So if the HR stream averages fewer than one sample
    /// per this many seconds, we don't assert off-wrist from gaps at all (WRIST_OFF events still apply).
    static let hrDenseSpacingS: Int = 600   // one HR sample per 10 minutes, averaged over the stream

    // MARK: - Sparse-gravity robustness (#308)

    // On an un-unlocked WHOOP 5.0 the strap backfills mostly v18/v26 records where gravity is sparse/clumped
    // (~25% coverage), so the gravity-only Stage-0 spine fragments the night at every >maxGapMin gravity gap
    // and detectSleep drops every <minSleepMin fragment — collapsing a ~6 h night to ~1 h. The fix lets a
    // pure gravity gap NOT break a sleep run when HR stays in the sleep band across it, and bridges runs
    // fragmented by such gaps, GATED ENTIRELY behind a "gravity is sparse" condition so dense WHOOP-4.0
    // nights stay BYTE-IDENTICAL (a 4.0 regression is unacceptable).

    /// Gravity is "sparse" when its timespan covers less than this fraction of the HR-sample timespan. A
    /// dense 4.0 night has gravity spanning the whole HR window (≈1.0) and never trips this; a 5.0 backfill
    /// clumps gravity into a fraction of the night.
    public static let sparseGravitySpanFrac: Double = 0.5
    /// When sparse, HR drives the in-bed spine: an HR sample is "sleep-band" when its bpm ≤ baseline × this.
    /// Reuses the overnight HR-confirmation multiplier so the band is the same one detectSleep already
    /// trusts to confirm a run.
    public static let hrSleepBandMult: Double = hrSleepBaselineMult
    /// When sparse, two adjacent sleep runs separated ONLY by a gravity gap up to this many minutes are
    /// merged if the intervening HR stays in the sleep band — so a real night is not shredded into
    /// sub-minSleepMin fragments by gravity dropouts. Sized at the daytime-nap floor (a real continuous night
    /// never has a true >90 min wake bridge mid-sleep).
    public static let sparseBridgeGapMin: Int = 90

    // MARK: - Stage 1–3 constants (sleep_features.py)

    public static let epochS: Double = 30.0
    public static let featureWindowS: Double = 5 * 60.0
    public static let ckCountDivisor: Double = 100.0
    public static let ckCountClip: Double = 300.0
    public static let moveDeltaThresholdG: Double = 0.01
    public static let hrDogSigma1S: Double = 120.0
    public static let hrDogSigma2S: Double = 600.0

    public static let stageHRLowPct: Double = 25.0
    public static let stageHRHighPct: Double = 70.0
    public static let stageHRVHighPct: Double = 70.0
    public static let stageHRVarHighPct: Double = 65.0
    public static let stageRRVHighPct: Double = 65.0
    public static let stageRRVLowPct: Double = 50.0
    public static let stageWakeMoveFrac: Double = 0.15
    public static let stageStillMoveFrac: Double = 0.10

    public static let smoothEpochs: Int = 5
    public static let noREMAfterOnsetMin: Double = 15.0
    public static let deepFirstFraction: Double = 1.0 / 3.0

    /// Cole–Kripke weights, 30 s variant [A₋₄..A₊₂] (Cole et al. 1992, Sleep 15(5):461–469; 30 s
    /// rescaling: te Lindert & Van Someren 2013, Sleep 36(5):781–789). SI = 0.001·Σ wᵢ·Aᵢ; sleep iff SI<1.
    public static let ckWeights: [Double] = [106.0, 54.0, 58.0, 76.0, 230.0, 74.0, 67.0]
    public static let ckScale: Double = 0.001
    public static let ckBack: Int = 4
    public static let ckFwd: Int = 2

    // MARK: - Gravity deltas

    /// Per-record movement proxy = L2 magnitude of the gravity change vs the
    /// previous record. First record → 0. (No dropout sentinel needed: GravitySample
    /// always carries finite x/y/z.)
    static func gravityDeltas(_ grav: [GravitySample]) -> [Double] {
        var deltas: [Double] = []
        deltas.reserveCapacity(grav.count)
        var prev: GravitySample? = nil
        for (i, r) in grav.enumerated() {
            if i == 0 {
                deltas.append(0.0)
            } else if let p = prev {
                let dx = p.x - r.x, dy = p.y - r.y, dz = p.z - r.z
                deltas.append((dx * dx + dy * dy + dz * dz).squareRoot())
            } else {
                deltas.append(0.0)
            }
            prev = r
        }
        return deltas
    }

    /// Median spacing between consecutive timestamps, restricted to (0, 300 s).
    static func medianIntervalS(_ times: [Int]) -> Double {
        guard times.count >= 2 else { return defaultIntervalS }
        var gaps: [Double] = []
        for i in 0..<(times.count - 1) {
            let g = Double(times[i + 1] - times[i])
            if g > 0 && g < 300 { gaps.append(g) }
        }
        guard !gaps.isEmpty else { return defaultIntervalS }
        gaps.sort()
        return max(gaps[gaps.count / 2], 1.0)
    }

    static func windowSize(_ times: [Int]) -> Int {
        let interval = medianIntervalS(times)
        return max(minWindowSamples, Int(Double(stillWindowMin * 60) / interval))
    }

    // MARK: - Sparse-gravity gate (#308)

    /// Largest spacing between consecutive timestamps (seconds), NO upper cap; 0 for <2 samples.
    /// Used to detect clumped/sparse gravity where the dropouts themselves are the signal: a few
    /// long dropouts in otherwise-dense (clumped) motion keep the MEDIAN gap small but still break
    /// runs, so the largest gap — not the median — is the right signal (#28).
    static func largestGapS(_ times: [Int]) -> Double {
        guard times.count >= 2 else { return 0 }
        var mx = 0.0
        for i in 0..<(times.count - 1) {
            let g = Double(times[i + 1] - times[i])
            if g > mx { mx = g }
        }
        return mx
    }

    /// True when gravity is too sparse for the gravity-only spine to be trusted across gaps:
    /// the gravity timespan covers < sparseGravitySpanFrac of the HR-sample timespan, OR the
    /// LARGEST gravity inter-sample gap exceeds maxGapMin. The largest-gap test (not just the
    /// median) catches CLUMPED motion — dense bursts split by a few long dropouts, the typical
    /// WHOOP 4.0 backfill (#28) — whose median gap stays small yet which still hides run-breaking
    /// gaps. Requires a real HR span to compare against — with no/degenerate HR the dense path is
    /// kept (false), so a 4.0 with absent HR is never reclassified as sparse.
    static func isGravitySparse(_ grav: [GravitySample], hr: [HRSample]) -> Bool {
        if grav.count < 2 || hr.count < 2 { return false }
        let hrSpan = Double(hr[hr.count - 1].ts - hr[0].ts)
        if hrSpan <= 0 { return false }
        let gravSpan = Double(grav[grav.count - 1].ts - grav[0].ts)
        if gravSpan < sparseGravitySpanFrac * hrSpan { return true }
        // #28: clumped 4.0 motion keeps a SMALL median gap yet still contains >maxGapMin dropouts
        // the gravity-only spine shreds the night on. The largest gap catches what a median would
        // miss (largest ≥ median, so this subsumes the old median check). Flagging sparse only
        // ENABLES buildRuns' HR-vouched bridge — a real wake (HR above the sleep band) still breaks.
        return largestGapS(grav.map { $0.ts }) > Double(maxGapMin * 60)
    }

    /// True when HR stays in the sleep band (≤ baseline × hrSleepBandMult) across (a, b], used to
    /// decide whether a pure gravity gap is a real wake or just a dropout. With no baseline or no
    /// HR in the interval, the answer is false (cannot vouch for the gap → treat as a real break).
    static func hrSleepBandAcross(_ a: Int, _ b: Int, hr: [HRSample], baseline: Double?) -> Bool {
        guard let baseline = baseline else { return false }
        let seg = hr.filter { $0.ts > a && $0.ts <= b }
        if seg.isEmpty { return false }
        let meanHR = Double(seg.reduce(0) { $0 + $1.bpm }) / Double(seg.count)
        return meanHR <= baseline * hrSleepBandMult
    }

    /// Per-record sleep flags from a rolling fraction of "still" samples.
    static func classifyStill(_ grav: [GravitySample], _ deltas: [Double]) -> [Bool] {
        let n = grav.count
        if n < 2 { return [Bool](repeating: false, count: n) }
        let half = windowSize(grav.map { $0.ts }) / 2
        // Prefix sum of "still" samples so the window count is prefix[hi]-prefix[lo] in O(1):
        // the whole pass is O(n) instead of O(n·window). Same count, same denominator (hi-lo),
        // same threshold — bit-identical to the per-sample rescan (FER-323).
        var prefix = [Int](repeating: 0, count: n + 1)
        for j in 0..<n { prefix[j + 1] = prefix[j] + (deltas[j] < gravityStillThresholdG ? 1 : 0) }
        var flags: [Bool] = []
        flags.reserveCapacity(n)
        for i in 0..<n {
            let lo = max(0, i - half)
            let hi = min(n, i + half + 1)
            let stillCount = prefix[hi] - prefix[lo]
            flags.append(Double(stillCount) / Double(hi - lo) >= stillFraction)
        }
        return flags
    }

    struct Period { var stage: String; var start: Int; var end: Int }

    /// Collapse per-record flags into contiguous runs, breaking on class change
    /// or a gap > maxGapMin minutes.
    ///
    /// When `sparse` (gravity is too clumped to bridge gaps — #308), a PURE gravity data-gap
    /// (no contrary motion) does NOT close a SLEEP run while HR stays in the sleep band across
    /// the gap: the strap simply banked no motion there, not a wake. A class change always still
    /// closes the run, and the dense path (`sparse == false`) is byte-identical to the original.
    static func buildRuns(_ grav: [GravitySample], _ flags: [Bool],
                          sparse: Bool = false, hr: [HRSample] = [], baseline: Double? = nil) -> [Period] {
        let n = grav.count
        if n == 0 { return [] }
        let times = grav.map { $0.ts }
        let maxGapS = maxGapMin * 60
        var periods: [Period] = []
        var runStart = 0
        for i in 1...n {
            let atEnd = (i == n)
            let close: Bool
            if atEnd {
                close = true
            } else {
                let classChanged = flags[i] != flags[runStart]
                var gapExceeded = (times[i] - times[i - 1]) > maxGapS
                // Sparse override: a pure gravity gap (no class change) does not break a sleep
                // run when HR stays in the sleep band across it — the gap is a dropout, not a wake.
                if sparse && gapExceeded && !classChanged && flags[runStart]
                    && hrSleepBandAcross(times[i - 1], times[i], hr: hr, baseline: baseline) {
                    gapExceeded = false
                }
                close = classChanged || gapExceeded
            }
            if close {
                periods.append(Period(stage: flags[runStart] ? "sleep" : "active",
                                      start: times[runStart], end: times[i - 1]))
                runStart = i
            }
        }
        return periods
    }

    /// Absorb runs shorter than mergeMin minutes into their neighbours.
    static func mergePeriods(_ periods: [Period], mergeMinutes: Int = mergeMin) -> [Period] {
        if periods.isEmpty { return [] }
        var pending = periods
        let thresholdS = mergeMinutes * 60
        var merged: [Period] = []
        var i = 0
        while i < pending.count {
            let current = pending[i]
            let tooShort = (current.end - current.start) < thresholdS
            if !tooShort { merged.append(current); i += 1; continue }

            let hasPrev = i > 0 && !merged.isEmpty
            let hasNext = i + 1 < pending.count
            let bridgesSame = hasPrev && hasNext && pending[i - 1].stage == pending[i + 1].stage

            if bridgesSame {
                let prev = merged.removeLast()
                merged.append(Period(stage: prev.stage, start: prev.start, end: pending[i + 1].end))
                i += 2
            } else if hasNext {
                pending[i + 1] = Period(stage: pending[i + 1].stage,
                                        start: current.start, end: pending[i + 1].end)
                i += 1
            } else if hasPrev {
                let prev = merged.removeLast()
                merged.append(Period(stage: prev.stage, start: prev.start, end: current.end))
                i += 1
            } else {
                i += 1
            }
        }
        return merged
    }

    /// Sparse-gravity bridge (#308): merge two adjacent SLEEP runs separated ONLY by a gap up to
    /// sparseBridgeGapMin minutes when the intervening HR stays in the sleep band — so a real night
    /// fragmented by gravity dropouts is re-stitched into one continuous in-bed span BEFORE the
    /// minSleepMin gate drops the pieces. Active runs and over-threshold gaps are left untouched;
    /// the span between two bridged sleep runs (an "active"/gap run, if present) is absorbed.
    /// A no-op when `sparse == false`, so the dense 4.0 path is unchanged.
    static func bridgeSparseSleep(_ periods: [Period], sparse: Bool,
                                  hr: [HRSample], baseline: Double?) -> [Period] {
        if !sparse || periods.isEmpty { return periods }
        let bridgeGapS = sparseBridgeGapMin * 60
        var out: [Period] = []
        for p in periods {
            if let last = out.last, last.stage == "sleep", p.stage == "sleep" {
                let gap = p.start - last.end
                if gap >= 0 && gap <= bridgeGapS
                    && hrSleepBandAcross(last.end, p.start, hr: hr, baseline: baseline) {
                    out[out.count - 1] = Period(stage: "sleep", start: last.start, end: p.end)
                    continue
                }
            }
            out.append(p)
        }
        return out
    }

    // MARK: - HR refinement

    static func rowsBetween<T>(_ rows: [T], start: Int, end: Int, ts: (T) -> Int) -> [T] {
        rows.filter { ts($0) >= start && ts($0) <= end }
    }

    /// Day HR baseline = median bpm over all HR samples; nil if none.
    static func hrBaseline(_ hr: [HRSample]) -> Double? {
        let vals = hr.map { Double($0.bpm) }
        guard !vals.isEmpty else { return nil }
        return HRVAnalyzer.median(vals)
    }

    static func confirmSleepWithHR(_ p: Period, hr: [HRSample], baseline: Double?) -> Bool {
        guard let baseline = baseline else { return true }
        let seg = rowsBetween(hr, start: p.start, end: p.end) { $0.ts }
        if seg.count < hrRefineMinSamples { return true }
        let meanHR = Double(seg.reduce(0) { $0 + $1.bpm }) / Double(seg.count)
        return meanHR <= baseline * hrSleepBaselineMult
    }

    /// True when the run's CENTER, shifted to LOCAL time by tzOffsetSeconds, lands in the
    /// daytime band [daytimeBandStartHour, daytimeBandEndHour). The center (not the edges)
    /// is used so a window straddling a band edge is classified once, by where it mostly is.
    /// `((x % d) + d) % d` is a floored modulo so a negative local-shifted time still maps
    /// into [0, secondsPerDay).
    static func isDaytimeCenter(_ p: Period, tzOffsetSeconds: Int) -> Bool {
        // Int overflow-safe: starts/ends are unix seconds; midpoint via average of the two.
        let center = p.start + (p.end - p.start) / 2
        let local = center + tzOffsetSeconds
        let secOfDay = ((local % secondsPerDay) + secondsPerDay) % secondsPerDay
        let hour = secOfDay / 3_600
        return hour >= daytimeBandStartHour && hour < daytimeBandEndHour
    }

    /// Stricter bar for a daytime-centered window (#90). A real daytime nap clears it; a
    /// long sedentary still stretch (the false-positive this guards) does not, because it
    /// is either too short or never shows a genuine cardiac dip below the day median.
    /// Overnight windows never reach here. Returns true = keep, false = reject.
    ///
    /// `restingHR` is the window's own lowest 5-min rolling-mean HR (the sleep-depth proxy
    /// detectSleep already computes); `baseline` is the day's median HR. With no usable HR
    /// evidence (nil baseline OR nil restingHR) a daytime stretch cannot be confirmed as a
    /// real nap, so it is rejected — sedentary daytime stillness without a measured HR dip
    /// is far more likely than an unmonitored nap, and this path can never touch the night.
    static func passesDaytimeGuard(_ p: Period, restingHR: Int?, baseline: Double?) -> Bool {
        let daytimeMinSleepS = daytimeMinSleepMin * 60
        if (p.end - p.start) < daytimeMinSleepS { return false }
        guard let baseline = baseline, let resting = restingHR else { return false }
        return Double(resting) <= baseline * daytimeRestingHRMult
    }

    /// True when a run's ONSET (start), in LOCAL time, falls OUTSIDE the daytime band — i.e.
    /// the sleep began at night, not during the day. Anchors a continuous-sleep chain: only a
    /// chain that began overnight may carry its tail past the daytime-band start (a late wake).
    static func isOvernightOnset(_ start: Int, tzOffsetSeconds: Int) -> Bool {
        let local = start + tzOffsetSeconds
        let secOfDay = ((local % secondsPerDay) + secondsPerDay) % secondsPerDay
        let hour = secOfDay / 3_600
        return !(hour >= daytimeBandStartHour && hour < daytimeBandEndHour)
    }

    /// H7 morning-stillness nap suppression (#531). Returns true = KEEP, false = REJECT, for a daytime block
    /// `p` that begins shortly after a real overnight wake. `morningWakeEnd` is the end of the just-detected
    /// OVERNIGHT chain (nil when the prior chain was not overnight, or there was none) — when `p.start` is
    /// within `morningStillnessWindowMin` of it, the block is suspected morning residual stillness and must
    /// clear the ORDINARY daytime guard AND show a SUSTAINED re-onset: its resting HR must dip below the
    /// stronger `morningReonsetRestingHRMult × baseline` bar (a true second sleep, not near-waking stillness).
    /// Outside the morning window this is a no-op (returns the plain daytime-guard result), so a genuine
    /// afternoon nap is unaffected. (#531)
    static func passesMorningStillnessGuard(_ p: Period, restingHR: Int?, baseline: Double?,
                                            morningWakeEnd: Int?,
                                            bandSleepState: [(ts: Int, state: Int)] = []) -> Bool {
        // Only a daytime block beginning within the post-wake window of an overnight chain is suspected.
        guard let wakeEnd = morningWakeEnd, p.start >= wakeEnd,
              (p.start - wakeEnd) <= morningStillnessWindowMin * 60 else {
            return passesDaytimeGuard(p, restingHR: restingHR, baseline: baseline)
        }
        // Suspected morning stillness needs at least the ordinary daytime guard (long enough + a real dip).
        if !passesDaytimeGuard(p, restingHR: restingHR, baseline: baseline) { return false }
        // CONSUME the strap's OWN banked band sleep_state (#531 / H8): if the strap itself scored this block
        // predominantly "asleep", that is a strong independent re-onset anchor — KEEP it even on a borderline
        // HR dip. This only ever RESCUES a block the strap says was real sleep; it never fabricates one.
        if bandStateConfirmsAsleep(p, bandSleepState: bandSleepState) { return true }
        // Otherwise require the clearly-deeper cardiac dip of a true second sleep.
        guard let baseline = baseline, let resting = restingHR else { return false }
        return Double(resting) <= baseline * morningReonsetRestingHRMult
    }

    /// CONSUME-side helper (#531 / H8): true when the strap's OWN persisted v18 band sleep_state over the
    /// block `[p.start, p.end]` reads predominantly "asleep" (`bandStateAsleep`), at/above
    /// `morningReonsetBandAsleepFrac` of the in-block samples — an independent confirmation of a real
    /// re-onset. Empty/absent band state → false (no anchor → fall back to the HR bar); we never invent a
    /// "asleep" reading the strap did not bank. Pure + deterministic. (#531 / H8 consume)
    ///
    /// NOTE (FER-662): NOOP does not decode the v18 BAND sleep_state yet, so the only live call site passes
    /// `[]` and this returns false — the function is a wired-up anchor that becomes active the day the decode
    /// lands, with no change here. Its logic is pinned by tests with synthetic band state.
    static func bandStateConfirmsAsleep(_ p: Period, bandSleepState: [(ts: Int, state: Int)]) -> Bool {
        let inBlock = bandSleepState.filter { $0.ts >= p.start && $0.ts <= p.end }
        guard !inBlock.isEmpty else { return false }
        let asleep = inBlock.reduce(0) { $0 + ($1.state == bandStateAsleep ? 1 : 0) }
        return Double(asleep) / Double(inBlock.count) >= morningReonsetBandAsleepFrac
    }

    /// Off-wrist HR-gap spans (#500). The contiguous HR-coverage gaps of at least `offWristHRGapMin`
    /// minutes WITHIN [p.start, p.end], as concrete `[start, end)` sub-intervals — a strong wrist-OFF
    /// proxy. Worn, the strap streams ~1 Hz HR (or PPG-derived HR on a 5/MG), so a real night yields no
    /// long gap; an off-wrist stretch flatlines to no HR samples and yields a span. The leading edge
    /// (`p.start` → first in-run sample) and trailing edge (last in-run sample → `p.end`) count too,
    /// and a run with NO in-run HR at all is one full-period gap. With NO HR data at all (no stream)
    /// this returns [] (the gravity-only path is left to the existing guards — we can't assert
    /// off-wrist without HR). These spans are UNIONed with the WRIST_OFF intervals by `offWristFraction`.
    static func offWristHRGapSpans(_ p: Period, hr: [HRSample]) -> [(start: Int, end: Int)] {
        if hr.isEmpty || p.end <= p.start { return [] }
        // Density gate (#507): only trust the HR-gap off-wrist proxy when the HR STREAM is dense enough
        // that a long gap is anomalous. A WHOOP 4.0 synced night is motion-reconstructed with sparse HR,
        // so its natural gaps must NOT read as off-wrist (that wrongly dropped a real night). Judge over
        // the whole stream so an off-wrist HOLE inside an otherwise dense, worn day (#500) is still caught.
        let sortedAll = hr.sorted { $0.ts < $1.ts }
        let streamSpan = sortedAll[sortedAll.count - 1].ts - sortedAll[0].ts
        if streamSpan >= hrDenseSpacingS && hr.count < streamSpan / hrDenseSpacingS { return [] }
        let gapS = offWristHRGapMin * 60
        let seg = hr.filter { $0.ts >= p.start && $0.ts <= p.end }.sorted { $0.ts < $1.ts }
        // No HR anywhere inside a run long enough to matter → the whole period is one gap.
        if seg.isEmpty { return (p.end - p.start) >= gapS ? [(start: p.start, end: p.end)] : [] }
        var spans: [(start: Int, end: Int)] = []
        // Leading edge: run start to first sample.
        if seg[0].ts - p.start >= gapS { spans.append((start: p.start, end: seg[0].ts)) }
        // Interior: any gap between consecutive in-run samples.
        for i in 1..<seg.count where seg[i].ts - seg[i - 1].ts >= gapS {
            spans.append((start: seg[i - 1].ts, end: seg[i].ts))
        }
        // Trailing edge: last sample to run end.
        if p.end - seg[seg.count - 1].ts >= gapS { spans.append((start: seg[seg.count - 1].ts, end: p.end)) }
        return spans
    }

    /// Fractional off-wrist coverage of a candidate run [p.start, p.end] in [0, 1] (#500).
    /// Design credited to j0b-dev's #504 analysis: instead of a binary drop on ANY HR gap or ANY single
    /// WRIST_OFF blip, we measure how much of the run is off-wrist and let the caller drop it only past
    /// `maxOffWristSleepFraction`. Coverage = (length of the UNION of) the HR-gap spans (`offWristHRGapSpans`)
    /// AND the supplied WRIST_OFF→WRIST_ON `wristOff` intervals, clipped to the run, divided by duration.
    /// Unioning avoids double-counting overlapping gap+event time. A real night with a small (<50%)
    /// off-wrist tail scores low and is kept; an all-day desk strap (HR-gap ≈100%, no events needed) or a
    /// session genuinely spent off the wrist scores high and is dropped.
    static func offWristFraction(_ p: Period, hr: [HRSample], wristOff: [(start: Int, end: Int)]) -> Double {
        let dur = p.end - p.start
        if dur <= 0 { return 0 }
        // Collect every off-wrist span, clipped to the run: HR-gap proxy spans + explicit wrist-off events.
        var spans = offWristHRGapSpans(p, hr: hr)
        for w in wristOff {
            let s = max(w.start, p.start), e = min(w.end, p.end)
            if e > s { spans.append((start: s, end: e)) }
        }
        if spans.isEmpty { return 0 }
        // Union the spans so overlapping gap+event time is counted once, then sum the covered length.
        spans.sort { $0.start < $1.start }
        var covered = 0, curStart = spans[0].start, curEnd = spans[0].end
        for sp in spans.dropFirst() {
            if sp.start <= curEnd {
                curEnd = max(curEnd, sp.end)              // overlapping/adjacent → extend
            } else {
                covered += curEnd - curStart             // disjoint → bank the run
                curStart = sp.start; curEnd = sp.end
            }
        }
        covered += curEnd - curStart
        return Double(covered) / Double(dur)
    }

    // MARK: - detectSleep (public)

    /// Detect sleep sessions from biometric streams. Empty/absent gravity → [].
    /// Gravity-only input degrades gracefully (HR/RR/resp refinements skipped).
    ///
    /// `tzOffsetSeconds` is the wall-clock UTC offset (TimeZone.current.secondsFromGMT)
    /// used ONLY to place each window's center on a LOCAL clock for the daytime
    /// false-sleep guard (#90). It defaults to 0 so the pure function and its tests stay
    /// UTC; the live call site (IntelligenceEngine) passes the device's real offset.
    ///
    /// `wristOff` and `bandSleepState` are OPTIONAL robustness inputs (FER-662, default empty). When
    /// absent, the off-wrist backstop falls back to its HR-gap proxy and the morning-stillness guard to
    /// its HR bar — so every existing caller keeps identical behavior. The sparse-gravity robustness
    /// (#308), the 16 h span cap, the off-wrist backstop and the night-tail / morning-stillness handling
    /// are all gated behind `sparse`/flags so a dense WHOOP 4.0 night is byte-identical.
    public static func detectSleep(hr: [HRSample] = [],
                                   rr: [RRInterval] = [],
                                   resp: [RespSample] = [],
                                   gravity: [GravitySample],
                                   tzOffsetSeconds: Int = 0,
                                   wristOff: [(start: Int, end: Int)] = [],
                                   bandSleepState: [(ts: Int, state: Int)] = []) -> [SleepSession] {
        let grav = gravity.sorted { $0.ts < $1.ts }
        if grav.count < 2 { return [] }

        let hrS = hr.sorted { $0.ts < $1.ts }
        let rrS = rr.sorted { $0.ts < $1.ts }
        let respS = resp.sorted { $0.ts < $1.ts }

        let baseline = hrBaseline(hrS)
        // Sparse-gravity gate (#308): an un-unlocked WHOOP 5.0 backfills mostly v18/v26 records where
        // gravity is clumped (~25% coverage), so the gravity-only spine fragments the night. ONLY when
        // sparse do the sparse robustness branches engage; a dense 4.0 night is `false` here and follows
        // the exact original path (byte-identical).
        let sparse = isGravitySparse(grav, hr: hrS)

        let deltas = gravityDeltas(grav)
        let flags = classifyStill(grav, deltas)
        var runs = buildRuns(grav, flags, sparse: sparse, hr: hrS, baseline: baseline)
        runs = mergePeriods(runs)
        // Re-stitch sleep runs fragmented by pure gravity dropouts (sparse only) before minSleepMin.
        runs = bridgeSparseSleep(runs, sparse: sparse, hr: hrS, baseline: baseline)

        let minSleepS = minSleepMin * 60

        var sessions: [SleepSession] = []
        // Continuous-sleep chain tracking so a real overnight sleep that runs PAST the daytime-band
        // start (a late wake, or a brief morning stir then back to sleep that leaves the tail as its own
        // daytime-centered run) is NOT mistaken for an isolated daytime nap and rejected. A daytime run
        // skips the nap guard ONLY when it directly continues (≤ nightContinuationGap) a chain that BEGAN
        // overnight; isolated daytime stillness (hours after waking) still faces the full guard.
        // Reimplemented from @vulnix0x4's PR #353.
        let continuationGapS = nightContinuationGapMin * 60
        var chainPrevEnd: Int? = nil       // end of the last accepted sleep run
        var chainFromOvernight = false     // did the current contiguous chain begin overnight?
        for p in runs {
            if p.stage != "sleep" { continue }
            if (p.end - p.start) <= minSleepS { continue }
            // H4 physiological in-bed span cap (#547/#531/#509 tail): a single assembled main-sleep run
            // longer than ~16 h is a bad-clock artefact (a frozen still stretch banked under a stale/wrong
            // clock), not a real night. Drop it rather than report (or truncate to) a 12 h+ "sleep".
            if (p.end - p.start) > maxMainSleepSpanS { continue }
            if !confirmSleepWithHR(p, hr: hrS, baseline: baseline) { continue }
            // Off-wrist backstop (#500), FRACTIONAL rule: a wrist-OFF stretch is still gravity with no HR,
            // so it slips past both the gravity spine and the daytime guard's "missing data" path. Measure
            // off-wrist COVERAGE — the union of the run's long HR-coverage gaps and any WRIST_OFF intervals
            // overlapping it — and drop the run only when that reaches maxOffWristSleepFraction. Checked
            // BEFORE the night-tail exemption: off-wrist time is off-wrist day or night and must NOT ride a
            // continuation chain. It does NOT re-anchor the chain (the run is simply skipped).
            let offFrac = offWristFraction(p, hr: hrS, wristOff: wristOff)
            if offFrac >= maxOffWristSleepFraction { continue }
            // Daytime false-sleep guard (#90) + H7 morning-stillness suppression (#531): a window centered
            // in the local daytime band must clear a stricter bar. Overnight windows skip this entirely.
            // restingHR is computed here (reused below).
            let resting = sessionRestingHR(start: p.start, end: p.end, hr: hrS)
            let continuesChain = chainPrevEnd.map { p.start - $0 <= continuationGapS } ?? false
            let isNightTail = continuesChain && chainFromOvernight   // the night's tail, not a nap
            // When the prior accepted chain BEGAN overnight, its wake (`chainPrevEnd`) anchors the
            // morning-stillness window; a daytime block within it that is NOT a night-tail must clear the
            // STRONGER re-onset bar. Outside the window the guard is the ordinary daytime bar.
            let morningWakeEnd = chainFromOvernight ? chainPrevEnd : nil
            let isDaytime = isDaytimeCenter(p, tzOffsetSeconds: tzOffsetSeconds)
            let passesMorning = isDaytime
                ? passesMorningStillnessGuard(p, restingHR: resting, baseline: baseline,
                                              morningWakeEnd: morningWakeEnd,
                                              bandSleepState: bandSleepState)
                : true
            if isDaytime, !passesMorning, !isNightTail { continue }
            let stages = stageSession(start: p.start, end: p.end, grav: grav,
                                      hr: hrS, rr: rrS, resp: respS)
            let eff = efficiency(start: p.start, end: p.end, stages: stages)
            let avgHrv = sessionAvgHRV(start: p.start, end: p.end, rr: rrS, stages: stages)
            sessions.append(SleepSession(start: p.start, end: p.end, efficiency: eff,
                                         stages: stages, restingHR: resting, avgHRV: avgHrv))
            // A run that does NOT continue the chain re-anchors it on this run's onset.
            if !continuesChain { chainFromOvernight = isOvernightOnset(p.start, tzOffsetSeconds: tzOffsetSeconds) }
            chainPrevEnd = p.end
        }
        sessions.sort { $0.start < $1.start }
        return sessions
    }

    /// asleep / in-bed in [0, 1]; asleep = in-bed − wake.
    static func efficiency(start: Int, end: Int, stages: [StageSegment]) -> Double {
        let inBed = Double(end - start)
        if inBed <= 0 { return 0 }
        let wake = stages.filter { $0.stage == "wake" }.reduce(0.0) { $0 + Double($1.end - $1.start) }
        let asleep = max(0.0, inBed - wake)
        return min(1.0, asleep / inBed)
    }

    // MARK: - Stage 1–3: staging over a 30 s epoch grid

    /// First persistent-sleep epoch (onset) and last sleep epoch (final wake).
    static func onsetAndFinalWake(_ ckFlags: [Bool]) -> (Int, Int) {
        let n = ckFlags.count
        if n == 0 { return (0, 0) }
        var onset: Int? = nil
        var run = 0
        for (i, s) in ckFlags.enumerated() {
            run = s ? run + 1 : 0
            if run >= onsetPersistEpochs { onset = i - onsetPersistEpochs + 1; break }
        }
        var final: Int? = nil
        for i in stride(from: n - 1, through: 0, by: -1) where ckFlags[i] { final = i; break }
        let o = onset ?? 0
        var f = final ?? (n - 1)
        if f < o { f = n - 1 }
        return (o, f)
    }

    /// Build a 30 s hypnogram for [start, end] and return StageSegments.
    static func stageSession(start: Int, end: Int, grav: [GravitySample],
                             hr: [HRSample], rr: [RRInterval], resp: [RespSample]) -> [StageSegment] {
        let gSeg = rowsBetween(grav, start: start, end: end) { $0.ts }
        if gSeg.count < 2 { return [StageSegment(start: start, end: end, stage: "light")] }

        let gDeltas = gravityDeltas(gSeg)
        let gTimes = gSeg.map { $0.ts }

        let hrSeg = rowsBetween(hr, start: start, end: end) { $0.ts }
        let rrSeg = rowsBetween(rr, start: start, end: end) { $0.ts }
        let respSeg = rowsBetween(resp, start: start, end: end) { $0.ts }

        let grid = buildEpochGrid(start: Double(start), end: Double(end),
                                  gravTimes: gTimes, gravDeltas: gDeltas,
                                  hr: hrSeg, rr: rrSeg, resp: respSeg)
        if grid.nEpochs == 0 { return [StageSegment(start: start, end: end, stage: "light")] }

        let rescaled = rescaleCounts(grid.counts)
        let ckFlags = coleKripke(rescaled)
        let (onsetIdx, finalWakeIdx) = onsetAndFinalWake(ckFlags)

        let dogHR = dogHRVariability(grid.hr)
        let feats = extractFeatures(grid: grid, ckFlags: ckFlags, dogHR: dogHR,
                                    onsetIdx: onsetIdx, finalWakeIdx: finalWakeIdx)

        var labels = classifyEpochs(feats)
        labels = smoothLabels(labels)
        labels = reimposePhysiology(labels, features: feats,
                                    onsetIdx: onsetIdx, finalWakeIdx: finalWakeIdx)

        // Pre-onset and post-final-wake epochs are not sleep → force wake.
        for i in 0..<labels.count where i < onsetIdx || i > finalWakeIdx { labels[i] = "wake" }

        // Merge consecutive same-stage epochs into segments tiling [start, end].
        var segments: [StageSegment] = []
        for (i, stage) in labels.enumerated() {
            let segStart = Int(grid.edges[i].rounded())
            let segEnd = Int(grid.edges[i + 1].rounded())
            if let last = segments.last, last.stage == stage {
                segments[segments.count - 1].end = segEnd
            } else {
                segments.append(StageSegment(start: segStart, end: segEnd, stage: stage))
            }
        }
        if !segments.isEmpty { segments[segments.count - 1].end = end }
        return segments
    }

    // MARK: - Epoch grid

    struct EpochGrid {
        let start: Double
        let end: Double
        let edges: [Double]
        let counts: [Double]      // per-epoch summed |Δgravity| (raw, pre-rescale)
        let moveFrac: [Double]    // scale-robust per-epoch moving-sample fraction
        let hr: [Double]          // per-epoch mean HR (bpm) or NaN
        let rr: [[Double]]        // per-epoch RR intervals (ms)
        let resp: [[Double]]      // per-epoch raw respiration samples
        var nEpochs: Int { counts.count }
        func epochMid(_ i: Int) -> Double { edges[i] + epochS / 2.0 }
    }

    static func buildEpochGrid(start: Double, end: Double,
                               gravTimes: [Int], gravDeltas: [Double],
                               hr: [HRSample], rr: [RRInterval], resp: [RespSample]) -> EpochGrid {
        if end <= start {
            return EpochGrid(start: start, end: end, edges: [start], counts: [],
                             moveFrac: [], hr: [], rr: [], resp: [])
        }
        let nEpochs = max(1, Int(ceil((end - start) / epochS)))
        var edges = (0...nEpochs).map { start + Double($0) * epochS }
        edges[nEpochs] = max(edges[nEpochs], end)

        var counts = [Double](repeating: 0, count: nEpochs)
        var moveN = [Int](repeating: 0, count: nEpochs)
        var gravN = [Int](repeating: 0, count: nEpochs)
        var hrSum = [Double](repeating: 0, count: nEpochs)
        var hrCnt = [Int](repeating: 0, count: nEpochs)
        var rrBuckets = [[Double]](repeating: [], count: nEpochs)
        var respBuckets = [[Double]](repeating: [], count: nEpochs)

        func idx(_ ts: Double) -> Int? {
            if ts < start || ts >= end {
                if ts == end { return nEpochs - 1 }
                return nil
            }
            let i = Int((ts - start) / epochS)
            return min(i, nEpochs - 1)
        }

        for (t, d) in zip(gravTimes, gravDeltas) {
            guard let i = idx(Double(t)) else { continue }
            counts[i] += d
            gravN[i] += 1
            if d >= moveDeltaThresholdG { moveN[i] += 1 }
        }
        for r in hr {
            guard let i = idx(Double(r.ts)) else { continue }
            hrSum[i] += Double(r.bpm); hrCnt[i] += 1
        }
        for r in rr {
            guard let i = idx(Double(r.ts)) else { continue }
            rrBuckets[i].append(Double(r.rrMs))
        }
        for r in resp {
            guard let i = idx(Double(r.ts)) else { continue }
            respBuckets[i].append(Double(r.raw))
        }

        let hrMean = (0..<nEpochs).map { hrCnt[$0] > 0 ? hrSum[$0] / Double(hrCnt[$0]) : Double.nan }
        // No gravity coverage → 1.0 (treat as moving; conservative).
        let moveFrac = (0..<nEpochs).map { gravN[$0] > 0 ? Double(moveN[$0]) / Double(gravN[$0]) : 1.0 }

        return EpochGrid(start: start, end: end, edges: edges, counts: counts,
                         moveFrac: moveFrac, hr: hrMean, rr: rrBuckets, resp: respBuckets)
    }

    // MARK: - Cole–Kripke

    static func rescaleCounts(_ counts: [Double]) -> [Double] {
        counts.map { min($0 / ckCountDivisor, ckCountClip) }
    }

    static func coleKripke(_ rescaled: [Double]) -> [Bool] {
        let n = rescaled.count
        var flags: [Bool] = []
        flags.reserveCapacity(n)
        for i in 0..<n {
            var si = 0.0
            for (k, w) in ckWeights.enumerated() {
                let j = i - ckBack + k
                let a = (j >= 0 && j < n) ? rescaled[j] : 0.0
                si += w * a
            }
            si *= ckScale
            flags.append(si < 1.0)
        }
        return flags
    }

    // MARK: - Walch difference-of-Gaussians HR variability

    static func gaussianKernel(sigmaS: Double, dtS: Double = epochS) -> [Double] {
        let sigma = max(sigmaS / dtS, 1e-6)  // σ in epochs
        let radius = max(1, Int(ceil(3 * sigma)))
        var k = [Double]()
        for x in -radius...radius { k.append(exp(-0.5 * pow(Double(x) / sigma, 2))) }
        let sum = k.reduce(0, +)
        return k.map { $0 / sum }
    }

    /// Same-length convolution with reflect padding (edge-stable).
    static func convolveReflect(_ x: [Double], _ kernel: [Double]) -> [Double] {
        let r = kernel.count / 2
        if r == 0 || x.isEmpty { return x }
        // Reflect padding: numpy 'reflect' mirrors WITHOUT repeating the edge sample.
        var padded = [Double]()
        padded.reserveCapacity(x.count + 2 * r)
        for i in 0..<r { padded.append(x[r - i]) }            // x[r], x[r-1], ... x[1]
        padded.append(contentsOf: x)
        for i in 0..<r { padded.append(x[x.count - 2 - i]) }  // x[n-2], x[n-3], ...
        // Valid convolution, then take the first x.count outputs.
        var out = [Double]()
        out.reserveCapacity(x.count)
        let m = kernel.count
        // np.convolve(padded, kernel, 'valid') has length padded.count - m + 1.
        for i in 0...(padded.count - m) {
            var acc = 0.0
            for j in 0..<m { acc += padded[i + j] * kernel[m - 1 - j] }
            out.append(acc)
            if out.count == x.count { break }
        }
        return out
    }

    /// DoG-filtered HR (σ1=120 s minus σ2=600 s). NaNs linearly interpolated first;
    /// all-NaN → zeros.
    static func dogHRVariability(_ hrPerEpoch: [Double]) -> [Double] {
        let n = hrPerEpoch.count
        if n == 0 { return [] }
        let maskIdx = (0..<n).filter { !hrPerEpoch[$0].isNaN }
        if maskIdx.isEmpty { return [Double](repeating: 0, count: n) }

        // Linear interpolation over the grid (numpy.interp semantics: clamp at edges).
        var filled = [Double](repeating: 0, count: n)
        for i in 0..<n {
            if !hrPerEpoch[i].isNaN { filled[i] = hrPerEpoch[i]; continue }
            // find surrounding known points
            if i <= maskIdx.first! { filled[i] = hrPerEpoch[maskIdx.first!]; continue }
            if i >= maskIdx.last! { filled[i] = hrPerEpoch[maskIdx.last!]; continue }
            var lo = maskIdx.first!, hi = maskIdx.last!
            for m in maskIdx { if m <= i { lo = m } ; if m >= i { hi = m; break } }
            if hi == lo { filled[i] = hrPerEpoch[lo] }
            else {
                let frac = Double(i - lo) / Double(hi - lo)
                filled[i] = hrPerEpoch[lo] + frac * (hrPerEpoch[hi] - hrPerEpoch[lo])
            }
        }

        let k1 = gaussianKernel(sigmaS: hrDogSigma1S)
        let k2 = gaussianKernel(sigmaS: hrDogSigma2S)
        let g1 = convolveReflect(filled, k1)
        let g2 = convolveReflect(filled, k2)
        return (0..<n).map { g1[$0] - g2[$0] }
    }

    // MARK: - Respiration rate + RRV (raw 1 Hz)

    /// Estimate respiratory rate (breaths/min) and RRV (s) from a raw resp window.
    /// Detrend → peak-pick (≥2 s apart) → breath intervals (1.5–12 s) → rate =
    /// 60/median interval, RRV = std of intervals. (nan, nan) when too few samples.
    ///
    /// NOTE: faithful port of sleep_features.resp_rate_and_rrv (which the Python
    /// source derives without neurokit), using a simple local-maxima peak finder.
    static func respRateAndRRV(_ respRaw: [Double], dtS: Double = 1.0) -> (Double, Double) {
        let nan = Double.nan
        if respRaw.count < 8 { return (nan, nan) }
        let mean = respRaw.reduce(0, +) / Double(respRaw.count)
        let x = respRaw.map { $0 - mean }
        if x.allSatisfy({ abs($0) < 1e-12 }) { return (nan, nan) }

        let std = standardDeviation(x)
        if std <= 0 { return (nan, nan) }

        let minDistance = max(2, Int((2.0 / dtS).rounded()))
        let peaks = findPeaks(x, distance: minDistance, height: 0.0)
        if peaks.count < 3 { return (nan, nan) }

        var intervals: [Double] = []
        for i in 1..<peaks.count {
            let iv = Double(peaks[i] - peaks[i - 1]) * dtS
            if iv >= 1.5 && iv <= 12.0 { intervals.append(iv) }
        }
        if intervals.count < 2 { return (nan, nan) }
        let rate = 60.0 / HRVAnalyzer.median(intervals)
        let rrv = standardDeviation(intervals)  // population std (numpy default)
        return (rate, rrv)
    }

    /// Local-maxima peak finder mirroring scipy.find_peaks(distance, height):
    /// a sample is a peak if strictly greater than both neighbours and ≥ height;
    /// peaks closer than `distance` are resolved by keeping the taller.
    static func findPeaks(_ x: [Double], distance: Int, height: Double) -> [Int] {
        let n = x.count
        if n < 3 { return [] }
        var candidates: [Int] = []
        var i = 1
        while i < n - 1 {
            if x[i] > x[i - 1] && x[i] >= height {
                // handle flat plateaus: find right edge of the plateau
                var j = i
                while j + 1 < n && x[j + 1] == x[i] { j += 1 }
                if j + 1 < n && x[j + 1] < x[i] {
                    candidates.append((i + j) / 2)  // plateau midpoint
                }
                i = j + 1
            } else {
                i += 1
            }
        }
        if distance <= 1 || candidates.isEmpty { return candidates }
        // Enforce minimum distance: greedily keep tallest, scipy-style.
        let byHeight = candidates.sorted { x[$0] > x[$1] }
        var keep = [Bool](repeating: true, count: candidates.count)
        let indexOf = Dictionary(uniqueKeysWithValues: candidates.enumerated().map { ($1, $0) })
        for p in byHeight {
            guard let pi = indexOf[p], keep[pi] else { continue }
            for (qi, q) in candidates.enumerated() where qi != pi && keep[qi] {
                if abs(q - p) < distance { keep[qi] = false }
            }
        }
        return candidates.enumerated().filter { keep[$0.offset] }.map { $0.element }.sorted()
    }

    // MARK: - Respiration rate from R-R (RSA) — WHOOP5 on-wire path

    /// RSA tachogram resample rate (Hz). 4 Hz is the standard HRV resample grid.
    static let rsaResampleHz = 4.0

    /// Moving-mean detrend window for the RSA tachogram (seconds).
    static let rsaDetrendWindowS = 8.0

    /// Minimum spacing between breath peaks on the tachogram (seconds) → ≤24 bpm.
    static let rsaMinPeakDistanceS = 2.5

    /// Per-window length for the per-window rate estimate (seconds).
    static let rsaWindowS = 300.0

    /// Physiologic breath-interval band (seconds): 0.1–0.4 Hz = 6–24 breaths/min.
    static let rsaMinBreathIntervalS = 2.5   // 24 bpm
    static let rsaMaxBreathIntervalS = 10.0  // 6 bpm

    /// THE canonical plausible sleeping-respiratory-rate band (bpm). The RSA peak-pick below can
    /// yield 6–8 bpm at its noise floor, but every consumer (illness/readiness gates) only acts on
    /// 8–25 — so respRateFromRR clamps its output to this band (NaN outside it) and the stored
    /// value can never disagree with what's acted on. Mirrors Android SleepStager.
    public static let respPlausibleRangeBpm: ClosedRange<Double> = 8.0...25.0

    /// APPROXIMATE respiratory rate (breaths/min) from the R-R interval stream via
    /// respiratory sinus arrhythmia (RSA), for use when no raw resp ADC channel is
    /// available (WHOOP5 v18 wire is RR-only; resp ADC is WHOOP4 / cloud-only).
    ///
    /// This is an ON-DEVICE ESTIMATE, NOT a cloud/clinical respiration measurement.
    /// It recovers the breathing-modulation of beat-to-beat timing, which tracks but
    /// does not equal a chest-band / capnography rate.
    ///
    /// Pipeline (per matched in-bed session [start, end], unix SECONDS):
    ///   1. Restrict RR rows to ts in [start, end]; range-filter the RR values
    ///      (HRVAnalyzer.rangeFilter) to drop dropouts/ectopics.
    ///   2. Reconstruct beat times by cumulatively summing the kept RR intervals
    ///      from the first in-bed beat, yielding an (irregular) tachogram.
    ///   3. Resample the tachogram onto a uniform ~4 Hz grid by linear interpolation.
    ///   4. Detrend: subtract a centered moving mean (rsaDetrendWindowS).
    ///   5. Per ~5-min window: findPeaks (min distance rsaMinPeakDistanceS) on the
    ///      detrended grid, keep peak-to-peak intervals in the 6–24 bpm band, rate =
    ///      60 / median(intervals). Take the median across windows.
    /// Returns NaN when too few intervals survive (honest no-data).
    static func respRateFromRR(_ rr: [RRInterval], start: Int, end: Int) -> Double {
        let nan = Double.nan
        if end <= start { return nan }

        // 1. In-bed RR rows in chronological order, range-filtered.
        let inBed = rr.filter { $0.ts >= start && $0.ts <= end }
            .sorted { $0.ts < $1.ts }
            .map { Double($0.rrMs) }
        let filtered = HRVAnalyzer.rangeFilter(inBed)
        if filtered.count < 30 { return nan }  // need enough beats for any RSA estimate

        // 2. Reconstruct beat times (seconds from session start) by cumulative sum.
        var beatTimes = [Double](repeating: 0, count: filtered.count)
        var acc = 0.0
        for i in filtered.indices {
            acc += filtered[i] / 1000.0
            beatTimes[i] = acc
        }
        let totalSpanS = beatTimes[beatTimes.count - 1]
        if totalSpanS < rsaWindowS / 2.0 { return nan }  // < ~2.5 min of beats

        // 3. Resample onto a uniform grid by linear interpolation.
        let dt = 1.0 / rsaResampleHz
        let nGrid = Int(totalSpanS / dt) + 1
        if nGrid < 8 { return nan }
        var grid = [Double](repeating: 0, count: nGrid)
        var seg = 0
        for g in 0..<nGrid {
            let t = Double(g) * dt
            // advance segment so beatTimes[seg] <= t <= beatTimes[seg+1]
            while seg < beatTimes.count - 2 && beatTimes[seg + 1] < t { seg += 1 }
            let t0 = beatTimes[seg]
            let t1 = beatTimes[seg + 1]
            let v0 = filtered[seg]
            let v1 = filtered[seg + 1]
            grid[g] = t1 <= t0 ? v0 : v0 + min(max((t - t0) / (t1 - t0), 0), 1) * (v1 - v0)
        }

        // 4. Detrend: subtract a centered moving mean (removes slow LF/baseline drift).
        let halfW = max(1, Int((rsaDetrendWindowS * rsaResampleHz / 2.0).rounded()))
        var detrended = [Double](repeating: 0, count: nGrid)
        for i in 0..<nGrid {
            let lo = max(0, i - halfW)
            let hi = min(nGrid - 1, i + halfW)
            var sum = 0.0
            for j in lo...hi { sum += grid[j] }
            detrended[i] = grid[i] - sum / Double(hi - lo + 1)
        }
        if standardDeviation(detrended) <= 1e-9 { return nan }  // flat → no RSA

        // 5. Per ~5-min window peak-pick → 60/median(breath interval); median across.
        let minDistSamples = max(2, Int((rsaMinPeakDistanceS * rsaResampleHz).rounded()))
        let windowSamples = max(minDistSamples * 3, Int((rsaWindowS * rsaResampleHz).rounded()))
        var perWindowRates: [Double] = []
        var w = 0
        while w < nGrid {
            let wEnd = min(nGrid, w + windowSamples)
            if wEnd - w >= minDistSamples * 3 {
                let winSeg = Array(detrended[w..<wEnd])
                // findPeaks with height = 0.0 selects the positive RSA peaks (one per
                // breath) on the zero-mean detrended tachogram.
                let peaks = findPeaks(winSeg, distance: minDistSamples, height: 0.0)
                if peaks.count >= 3 {
                    var intervals: [Double] = []
                    for i in 1..<peaks.count {
                        let ivS = Double(peaks[i] - peaks[i - 1]) * dt
                        if ivS >= rsaMinBreathIntervalS && ivS <= rsaMaxBreathIntervalS {
                            intervals.append(ivS)
                        }
                    }
                    if intervals.count >= 2 {
                        let med = HRVAnalyzer.median(intervals)
                        if med > 0.0 { perWindowRates.append(60.0 / med) }
                    }
                }
            }
            w += windowSamples
        }
        if perWindowRates.isEmpty { return nan }
        // Reject estimates outside the canonical consumer band (NaN = "no usable estimate") so the
        // persisted value never silently disagrees with the illness/readiness plausibility gate.
        let median = HRVAnalyzer.median(perWindowRates)
        return respPlausibleRangeBpm.contains(median) ? median : nan
    }

    // MARK: - Per-epoch features

    struct EpochFeatures {
        let index: Int
        let midTs: Double
        let count: Double      // rescaled Cole–Kripke activity count
        let moveFrac: Double
        let ckSleep: Bool
        let hr: Double         // mean HR over the feature window
        let hrVar: Double      // Walch DoG-HR windowed std
        let rmssd: Double      // ms
        let sdnn: Double       // ms
        let respRate: Double   // breaths/min
        let rrv: Double        // respiratory-rate variability (s)
        let clock: Double      // normalized time since onset, 0..1
    }

    static func extractFeatures(grid: EpochGrid, ckFlags: [Bool], dogHR: [Double],
                                onsetIdx: Int, finalWakeIdx: Int) -> [EpochFeatures] {
        let n = grid.nEpochs
        let rescaled = rescaleCounts(grid.counts)
        let halfW = Int((featureWindowS / epochS / 2).rounded())
        let span = Double(max(1, finalWakeIdx - onsetIdx))

        var feats: [EpochFeatures] = []
        feats.reserveCapacity(n)
        for i in 0..<n {
            let lo = max(0, i - halfW)
            let hi = min(n, i + halfW + 1)

            let winHR = (lo..<hi).map { grid.hr[$0] }.filter { !$0.isNaN }
            let hrMean = winHR.isEmpty ? Double.nan : winHR.reduce(0, +) / Double(winHR.count)

            let winDog = (lo..<hi).map { dogHR.isEmpty ? 0.0 : dogHR[$0] }
            let hrVar = winDog.count >= 2 ? standardDeviation(winDog) : Double.nan

            // RMSSD/SDNN over the pooled RR window (range-filtered, like the
            // Python per-epoch hrv_from_rr which uses RAW range-filtered RR).
            var winRR: [Double] = []
            for j in lo..<hi { winRR.append(contentsOf: grid.rr[j]) }
            let filteredRR = HRVAnalyzer.rangeFilter(winRR)
            let rmssd = filteredRR.count >= 5 ? (HRVAnalyzer.rmssdRaw(filteredRR) ?? Double.nan) : Double.nan
            let sdnn = filteredRR.count >= 5 ? (HRVAnalyzer.sdnnRaw(filteredRR) ?? Double.nan) : Double.nan

            var winResp: [Double] = []
            for j in lo..<hi { winResp.append(contentsOf: grid.resp[j]) }
            let (respRate, rrv) = respRateAndRRV(winResp)

            let clock = min(1.0, max(0.0, Double(i - onsetIdx) / span))

            feats.append(EpochFeatures(
                index: i, midTs: grid.epochMid(i), count: rescaled[i],
                moveFrac: grid.moveFrac[i],
                ckSleep: i < ckFlags.count ? ckFlags[i] : true,
                hr: hrMean, hrVar: hrVar, rmssd: rmssd, sdnn: sdnn,
                respRate: respRate, rrv: rrv, clock: clock))
        }
        return feats
    }

    // MARK: - Percentile helper

    /// numpy-style linear-interpolated percentile over finite values; nil if none.
    static func percentile(_ values: [Double], _ pct: Double) -> Double? {
        let vals = values.filter { $0.isFinite }.sorted()
        if vals.isEmpty { return nil }
        return StrainScorer.percentile(vals, pct)
    }

    // MARK: - Classifier seam (Stage 2)

    static func classifyEpochs(_ features: [EpochFeatures]) -> [String] {
        let n = features.count
        if n == 0 { return [] }

        // Session-relative reference distributions over SLEEP-PERIOD epochs.
        let sleepFeats = features.contains { $0.ckSleep } ? features.filter { $0.ckSleep } : features
        let hrLo = percentile(sleepFeats.map { $0.hr }, stageHRLowPct)
        let hrHi = percentile(sleepFeats.map { $0.hr }, stageHRHighPct)
        let rmssdHi = percentile(sleepFeats.map { $0.rmssd }, stageHRVHighPct)
        let hrvarHi = percentile(sleepFeats.map { $0.hrVar }, stageHRVarHighPct)
        let rrvHi = percentile(sleepFeats.map { $0.rrv }, stageRRVHighPct)
        let rrvLo = percentile(sleepFeats.map { $0.rrv }, stageRRVLowPct)

        return features.map {
            classifyOne($0, hrLo: hrLo, hrHi: hrHi, rmssdHi: rmssdHi,
                        hrvarHi: hrvarHi, rrvHi: rrvHi, rrvLo: rrvLo)
        }
    }

    static func classifyOne(_ f: EpochFeatures, hrLo: Double?, hrHi: Double?,
                            rmssdHi: Double?, hrvarHi: Double?, rrvHi: Double?, rrvLo: Double?) -> String {
        let hasHR = f.hr.isFinite
        let hrLow = hasHR && hrLo != nil && f.hr <= hrLo!
        let hrHigh = hasHR && hrHi != nil && f.hr >= hrHi!

        // NOTE: HF omitted (no neurokit2). Parasympathetic tone = RMSSD only.
        let parasympHigh = f.rmssd.isFinite && rmssdHi != nil && f.rmssd >= rmssdHi!

        let hrvarHigh = f.hrVar.isFinite && hrvarHi != nil && f.hrVar >= hrvarHi!
        let cardiacActivated = hrHigh || hrvarHigh

        let rrvIrregular = f.rrv.isFinite && rrvHi != nil && f.rrv >= rrvHi!
        // Missing respiration (NaN RRV) treated as "regular" (pro-deep bias).
        let rrvRegular = (!f.rrv.isFinite) || (rrvLo != nil && f.rrv <= rrvLo!)

        let still = f.moveFrac <= stageStillMoveFrac
        let moving = f.moveFrac >= stageWakeMoveFrac

        // WAKE: sustained motion + activated cardiac (or no HR to vet motion).
        if moving && (cardiacActivated || !hasHR) { return "wake" }
        // DEEP: still + high parasympathetic tone + low HR + regular respiration.
        if still && parasympHigh && hrLow && rrvRegular { return "deep" }
        // REM: still body + activated cardiac + irregular respiration.
        if still && cardiacActivated && rrvIrregular { return "rem" }
        // REM fallback when respiration unavailable: require BOTH cardiac signals.
        if still && hrHigh && hrvarHigh && !f.rrv.isFinite { return "rem" }
        return "light"
    }

    // MARK: - Post-processing (Stage 3)

    static func smoothLabels(_ labels: [String], window: Int = smoothEpochs) -> [String] {
        let n = labels.count
        if n == 0 || window <= 1 { return labels }
        var w = window
        if w % 2 == 0 { w += 1 }
        let half = w / 2
        var out: [String] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let lo = max(0, i - half)
            let hi = min(n, i + half + 1)
            var counts: [String: Int] = [:]
            var order: [String] = []
            for s in labels[lo..<hi] {
                if counts[s] == nil { order.append(s) }
                counts[s, default: 0] += 1
            }
            guard let best = counts.values.max() else { out.append(labels[i]); continue }
            let winners = order.filter { counts[$0] == best }  // insertion order preserved
            out.append(winners.contains(labels[i]) ? labels[i] : winners[0])
        }
        return out
    }

    static func reimposePhysiology(_ labels: [String], features: [EpochFeatures],
                                   onsetIdx: Int, finalWakeIdx: Int) -> [String] {
        var out = labels
        let noREMEpochs = Int((noREMAfterOnsetMin * 60.0 / epochS).rounded())
        for (i, f) in features.enumerated() {
            if i < onsetIdx || i > finalWakeIdx { continue }
            if out[i] == "rem" && (i - onsetIdx) < noREMEpochs { out[i] = "light" }
            if out[i] == "deep" && f.clock > deepFirstFraction { out[i] = "light" }
        }
        return out
    }

    // MARK: - Per-session HR / HRV

    /// Lowest 5-min rolling-mean HR during the session (bpm), or nil.
    static func sessionRestingHR(start: Int, end: Int, hr: [HRSample]) -> Int? {
        let seg = hr.filter { $0.ts >= start && $0.ts <= end }
        guard !seg.isEmpty else { return nil }
        let windowS = 5 * 60
        // Count the 5-min windows the original loop would visit (t = start, +windowS, while t < end).
        var windowCount = 0
        var t = start
        while t < end { windowCount += 1; t += windowS }
        // Bucket each sample into its window in ONE O(n) pass instead of re-filtering seg per window.
        // A sample at ts lands in window w = (ts - start)/windowS, counted iff that window is visited
        // (w < windowCount ⇔ start + w·windowS < end) — exactly the original's inclusion rule, incl.
        // the ts==end edge. No ordering assumption on `seg`. Same per-window mean (FER-323).
        var sums = [Int](repeating: 0, count: windowCount)
        var counts = [Int](repeating: 0, count: windowCount)
        for s in seg {
            let w = (s.ts - start) / windowS
            if w < windowCount { sums[w] += s.bpm; counts[w] += 1 }
        }
        var minMean: Double? = nil
        for i in 0..<windowCount where counts[i] > 0 {
            let mean = Double(sums[i]) / Double(counts[i])
            if minMean == nil || mean < minMean! { minMean = mean }
        }
        if let m = minMean { return Int(m.rounded()) }
        let all = Double(seg.reduce(0) { $0 + $1.bpm }) / Double(seg.count)
        return Int(all.rounded())
    }

    /// Median RMSSD over 5-min tumbling windows across the session (ms), or nil.
    /// Each window is range-filtered AND ectopic-rejected (Malik) before RMSSD —
    /// the same cleaning hrv.analyze() applies — so a stray ectopic beat can't
    /// inflate the night's headline HRV (the 60%-weight recovery driver). Windows
    /// are aggregated with the median (robust to the odd corrupted window), the
    /// same central-tendency choice the nightly respiratory rate already uses.
    ///
    /// When a hypnogram is supplied, windows whose midpoint falls in a "wake" span
    /// are dropped: HRV measured across awakenings is noisier and sympathetically
    /// skewed, so excluding wake tracks WHOOP/Oura, which sample HRV during sleep
    /// only — a more reproducible parasympathetic read night to night. With no
    /// hypnogram (pure-function callers / tests) every window counts, as before.
    static func sessionAvgHRV(start: Int, end: Int, rr: [RRInterval],
                              stages: [StageSegment] = []) -> Double? {
        let seg = rr.filter { $0.ts >= start && $0.ts <= end }
        guard !seg.isEmpty else { return nil }
        let windowS = 5 * 60
        var vals: [Double] = []
        var t = start
        while t < end {
            // Skip windows centered in a scored wake span (only when a hypnogram is given).
            if !stages.isEmpty, stageAt(t + windowS / 2, stages) == "wake" { t += windowS; continue }
            let bucket = seg.filter { $0.ts >= t && $0.ts < t + windowS }.map { Double($0.rrMs) }
            let filtered = HRVAnalyzer.cleanRR(bucket)
            if filtered.count >= 2, let r = HRVAnalyzer.rmssdRaw(filtered) { vals.append(r) }
            t += windowS
        }
        guard !vals.isEmpty else { return nil }
        return HRVAnalyzer.median(vals)
    }

    /// Stage label of the segment whose [start, end) contains `ts`, or "" if none.
    static func stageAt(_ ts: Int, _ stages: [StageSegment]) -> String {
        for s in stages where ts >= s.start && ts < s.end { return s.stage }
        return ""
    }

    // MARK: - AASM hypnogram metrics

    /// AASM-style metrics from a session's stage segments.
    public struct HypnogramMetrics: Equatable, Sendable {
        public let tibS: Double
        public let tstS: Double
        public let sptS: Double
        public let solS: Double
        public let remLatencyS: Double  // NaN if no REM
        public let wasoS: Double
        public let efficiency: Double
        public let disturbances: Int
        public let deepMin: Double
        public let remMin: Double
        public let lightMin: Double
        public let deepPct: Double
        public let remPct: Double
        public let lightPct: Double
    }

    public static func hypnogramMetrics(_ session: SleepSession) -> HypnogramMetrics {
        let segs = session.stages.sorted { $0.start < $1.start }
        let tib = max(0.0, Double(session.end - session.start))

        func dur(_ s: StageSegment) -> Double { Double(s.end - s.start) }
        let sleepSegs = segs.filter { $0.stage == "light" || $0.stage == "deep" || $0.stage == "rem" }
        let tst = sleepSegs.reduce(0.0) { $0 + dur($1) }
        let deepS = segs.filter { $0.stage == "deep" }.reduce(0.0) { $0 + dur($1) }
        let remS = segs.filter { $0.stage == "rem" }.reduce(0.0) { $0 + dur($1) }
        let lightS = segs.filter { $0.stage == "light" }.reduce(0.0) { $0 + dur($1) }

        let onset: Double, sptEnd: Double, sol: Double
        if let first = sleepSegs.first, let last = sleepSegs.last {
            onset = Double(first.start)
            sptEnd = Double(last.end)
            sol = max(0.0, onset - Double(session.start))
        } else {
            onset = Double(session.end)
            sptEnd = Double(session.end)
            sol = tib
        }

        let remSegs = segs.filter { $0.stage == "rem" }
        let remLatency = remSegs.first.map { Double($0.start) - onset } ?? Double.nan

        var waso = 0.0
        var disturbances = 0
        for s in segs where s.stage == "wake" {
            let w0 = max(Double(s.start), onset)
            let w1 = min(Double(s.end), sptEnd)
            if w1 > w0 { waso += (w1 - w0); disturbances += 1 }
        }

        let se = tib > 0 ? tst / tib : 0.0
        func pct(_ x: Double) -> Double { tst > 0 ? x / tst * 100.0 : 0.0 }

        return HypnogramMetrics(
            tibS: tib, tstS: tst, sptS: max(0.0, sptEnd - onset), solS: sol,
            remLatencyS: remLatency, wasoS: waso, efficiency: min(1.0, se),
            disturbances: disturbances, deepMin: deepS / 60.0, remMin: remS / 60.0,
            lightMin: lightS / 60.0, deepPct: pct(deepS), remPct: pct(remS), lightPct: pct(lightS))
    }

    // MARK: - Small stats helpers

    /// Population standard deviation (numpy default, ddof=0).
    static func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        var ss = 0.0
        for v in values { let d = v - mean; ss += d * d }
        return (ss / Double(values.count)).squareRoot()
    }
}
