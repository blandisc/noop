import Foundation

// AnalysisScheduler.swift — pure day-dirtiness arithmetic for the incremental analyzeRecent pass
// (FER-868). The engine re-reads ~21 nights × 8 streams every 15 minutes; almost always only the
// current night changed. Dirtiness is detected by a COUNT-per-local-day SIGNATURE per raw stream:
// the stream writers only ever `INSERT … ON CONFLICT DO NOTHING` (never UPDATE in place), so a
// day's COUNT(*) grows iff genuinely-new rows landed — a backfill that fills a gap moves the COUNT
// even when it doesn't move MAX(ts) — and the safe-trim that deletes rows LOWERS it: both directions
// read as dirty. Pure and DB-free: the counts come from `WhoopStore.streamDayCounts`.
public enum AnalysisScheduler {

    /// The dirtiness signature of one night's read window: for every (stream, local epoch-day) the
    /// window overlaps, the stored row count. Equal signatures ⟺ no raw data changed under the night.
    public struct NightSignature: Equatable, Sendable {
        /// Keyed "stream#epochDay" (e.g. "hr#20643") so a count MOVING between days inside the
        /// window — not just the window total changing — still flips the signature.
        public let counts: [String: Int]
        public init(counts: [String: Int]) { self.counts = counts }
    }

    /// Floor division (rounds toward −∞), so a pre-1970/negative local timestamp still lands on the
    /// correct civil day. For the non-negative values real unix timestamps produce this equals `/`.
    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    /// Local civil epoch-day of a unix timestamp: floor((ts + tzOffset) / 86 400).
    public static func epochDay(_ ts: Int, tzOffsetSeconds: Int) -> Int {
        floorDiv(ts + tzOffsetSeconds, 86_400)
    }

    /// The LOCAL epoch-days the night read window of the day `offset` days back overlaps. The window
    /// is exactly the one `analyzeRecent` reads per night: [dayStart − 30 h, dayStart + 12 h] with
    /// dayStart = now − offset·86 400 (the stager finds the actual sleep span inside it). Inclusive
    /// on both ends, ascending.
    public static func windowEpochDays(now: Int, offset: Int, tzOffsetSeconds: Int) -> [Int] {
        let dayStart = now - offset * 86_400
        let from = dayStart - 30 * 3_600
        let to = dayStart + 12 * 3_600
        let lo = epochDay(from, tzOffsetSeconds: tzOffsetSeconds)
        let hi = epochDay(to, tzOffsetSeconds: tzOffsetSeconds)
        return Array(lo...hi)
    }

    /// Project the full per-stream day-count map onto one night's window. Days with no rows simply
    /// contribute no key (COUNT 0 and "no key" are the same absence, on both sides of the compare).
    public static func signature(dayCounts: [String: [Int: Int]], epochDays: [Int]) -> NightSignature {
        var counts: [String: Int] = [:]
        for (stream, byDay) in dayCounts {
            for d in epochDays {
                if let c = byDay[d], c != 0 { counts["\(stream)#\(d)"] = c }
            }
        }
        return NightSignature(counts: counts)
    }

    /// A night must be re-analyzed when it has no cached signature (first pass / cache reset), when
    /// its signature changed (rows arrived OR were trimmed anywhere under its window), or when it is
    /// the in-progress day (today's strain/night keeps moving even between offloads).
    public static func isDirty(cached: NightSignature?, current: NightSignature, isToday: Bool) -> Bool {
        if isToday { return true }
        guard let cached else { return true }
        return cached != current
    }
}
