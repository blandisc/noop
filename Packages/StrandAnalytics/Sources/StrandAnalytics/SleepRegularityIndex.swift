import Foundation
import CenitStore

// MARK: - Sleep Regularity Index (SRI) — FER-214
//
// The Sleep Regularity Index (Phillips et al. 2017, Sci Rep 7:3216) measures how REGULAR your
// sleep TIMING is, independent of how long or how well you sleep: the probability that you are in
// the same state (asleep vs awake) at two instants exactly 24 h apart, averaged over the window,
// rescaled `SRI = (2·P − 1)·100` so 100 = a perfectly repeated schedule and 0 = no better than
// chance (negatives, anti-phase, are clamped to 0). Windred et al. 2024 (Sleep 47(1):zsad253) showed the SRI
// predicts all-cause mortality ABOVE sleep duration — which is why `VitalityEngine`'s regularity
// hazard wants a real SRI, not the duration proxy it ships with.
//
// Pure, database-free. NOOP only records during sleep sessions (the strap is a night wearable, not
// 24/7 actigraphy), so this compares CONSECUTIVE nights over a ±12 h window around each night's
// onset — where coverage exists on both days — instead of a continuous round-the-clock timeline.
// Daytime (awake on both days → a match) and missing nights (the 24 h pairing is skipped) are
// handled by construction; the orchestration feeds the already-persisted hypnogram (fine, on-device
// nights) or the session's `[start, end]` interval (coarse, imported/Apple nights). See docs/ANALYTICS.md.

public enum SleepRegularityIndex {

    /// One contiguous asleep span, in absolute unix seconds.
    public struct AsleepInterval: Equatable, Sendable {
        public let start: Int
        public let end: Int
        public init(start: Int, end: Int) { self.start = start; self.end = end }
    }

    /// Minimum distinct nights in the window before we'll return a number (coverage gate).
    public static let minNights = 7

    static let nightGapSeconds = 8 * 3600     // intervals ≤ 8 h apart belong to the same night
    static let daySeconds = 86_400
    static let halfWindowSeconds = 12 * 3600  // ±12 h around each night's onset = its coverage

    /// SRI on a 0–100 scale, or `nil` when fewer than `minNights` nights are present (coverage gate).
    /// `epochSeconds` is the sampling grid (default 5 min). Walks a continuous asleep/awake timeline and
    /// counts, for every COVERED instant, whether the state 24 h later matches (so it aligns by clock
    /// time), then rescales `(2·P − 1)·100`. "Covered" = within ±12 h of a recorded night, so a missing
    /// night drops out of the 24 h pairing instead of reading as an all-awake day.
    public static func compute(asleepIntervals: [AsleepInterval],
                               epochSeconds: Int = 300) -> Double? {
        let intervals = asleepIntervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !intervals.isEmpty, epochSeconds > 0 else { return nil }

        // Night onsets: the first interval starts a night; thereafter a new night starts when the gap
        // from the previous interval's end exceeds nightGap. (`intervals` is non-empty here.)
        var anchors: [Int] = [intervals[0].start]
        var lastEnd = intervals[0].end
        for iv in intervals.dropFirst() {
            if iv.start - lastEnd > nightGapSeconds { anchors.append(iv.start) }
            lastEnd = max(lastEnd, iv.end)
        }
        guard anchors.count >= minNights else { return nil }

        let windowStart = anchors.first! - halfWindowSeconds
        let windowEnd = anchors.last! + halfWindowSeconds
        var matches = 0, total = 0
        var t = windowStart
        while t < windowEnd {
            if covered(t, anchors: anchors), covered(t + daySeconds, anchors: anchors) {
                if asleep(t, in: intervals) == asleep(t + daySeconds, in: intervals) { matches += 1 }
                total += 1
            }
            t += epochSeconds
        }
        guard total > 0 else { return nil }
        let p = Double(matches) / Double(total)
        return min(100, max(0, (2 * p - 1) * 100))
    }

    /// SRI (0–100) directly from a window of persisted sleep sessions: the stored hypnogram
    /// (`stagesJSON` segments → every non-`wake` span, the fine timeline) when present, else the
    /// session's whole `[startTs, endTs]` span (coarse — imported / Apple-Health nights that store only
    /// stage totals). nil → insufficient coverage. Pure: the app layer only supplies `repo.sleeps`.
    public static func fromSessions(_ sessions: [CachedSleepSession]) -> Double? {
        var intervals: [AsleepInterval] = []
        // Same "main night" gate as SleepRegularity (FER-298): a nap is near anti-phase to the
        // nocturnal sleep and must not count as a night when scoring schedule regularity. Filtered at
        // the SESSION level (one session = one night/nap), never inside `compute(asleepIntervals:)` —
        // that one receives sub-night hypnogram spans, which are legitimately short.
        for s in sessions where SleepMainNight.qualifies(startTs: s.startTs, endTs: s.endTs) {
            if let segs = AnalyticsEngine.decodeStages(s.stagesJSON) {
                for seg in segs where seg.stage != "wake" && seg.stage != "awake" && seg.end > seg.start {
                    intervals.append(.init(start: seg.start, end: seg.end))
                }
            } else {
                intervals.append(.init(start: s.startTs, end: s.endTs))   // coarse: whole session asleep
            }
        }
        return compute(asleepIntervals: intervals)
    }

    /// Is `t` within ±halfWindow of a recorded night onset? Binary search over the sorted anchors.
    static func covered(_ t: Int, anchors: [Int]) -> Bool {
        var lo = 0, hi = anchors.count - 1
        while lo <= hi {
            let m = (lo + hi) / 2
            if anchors[m] < t - halfWindowSeconds { lo = m + 1 }
            else if anchors[m] > t + halfWindowSeconds { hi = m - 1 }
            else { return true }
        }
        return false
    }

    /// Is instant `t` (unix seconds) inside any asleep interval? Binary search over the sorted,
    /// non-overlapping intervals (segments from one night are contiguous; nights are far apart).
    static func asleep(_ t: Int, in intervals: [AsleepInterval]) -> Bool {
        var lo = 0, hi = intervals.count - 1, idx = -1
        while lo <= hi {
            let m = (lo + hi) / 2
            if intervals[m].start <= t { idx = m; lo = m + 1 } else { hi = m - 1 }
        }
        return idx >= 0 && t < intervals[idx].end
    }
}
