import Foundation

// ActivityCostEngine.swift — "what each activity is associated with for your recovery".
//
// Pure, deterministic, DB-free. Given which days you tagged each SPORT on and your
// daily Charge (recovery, 0–100) history, this describes, per sport: how far your
// next-morning Charge tends to sit BELOW your rest-day baseline after a session, and
// roughly how long it tends to take to climb back.
//
// This is a descriptive ASSOCIATION over your own history, not a measurement of any
// single session and NOT a causal "cost". It leans on the levers actually in the data
// (the day a session was tagged, and the Charge values on the days after) and stays
// explainable line by line — nothing here is learned; it is plain medians over aligned
// day keys. Several confounders mean the gap is association, not cause (see the doc
// note at the bottom of this file): regression to the mean, non-random rest days, and
// day-of-week / same-day overlapping sessions. The narrative is framed accordingly.
//
// Per sport S:
//
//   restDays      = days with a Charge value that are neither tagged with ANY sport NOR inside a
//                   session's forward recovery window (D+1…D+maxLookahead) — your UNTOUCHED days.
//   baselineCenter = MEDIAN Charge over restDays. This is your "untouched" recovery — the
//                   bar each sport is measured against. (Shared across all sports.)
//
//   For each tagged day D of sport S that HAS a Charge value on D+1:
//     nextMorning(D) = Charge[D+1]
//   nextMorningCenter = MEDIAN of those nextMorning(D).
//   n                 = how many tagged days contributed a D+1 value.
//
//   delta           = baselineCenter − nextMorningCenter.
//                     POSITIVE → the morning after this sport your Charge tends to sit
//                     BELOW your rest baseline; negative → you tend to wake higher.
//
//   daysToBaseline  = how long recovery tends to take to climb back. Build an averaged
//                     (median) forward trajectory traj[k] = median over tagged days D
//                     (that have a Charge on D+k) of Charge[D+k], for k = 1…maxLookahead.
//                     daysToBaseline is the smallest k whose traj[k] ≥ baselineCenter − tol
//                     (tol = 3 pts). ONLY computed for .solid results (it is the most
//                     fragile output — the trajectory is a composite over different day
//                     subsets per horizon and tol sits near the day-to-day noise floor);
//                     nil for .building, or when it never recovers inside the window.
//
// Confidence (reuses ScoreConfidence): a sport with fewer than minSessions tagged
// next-morning pairs is OMITTED entirely (too thin to say anything honest);
// minSessions…<solidSessions → .building; ≥ solidSessions → .solid.
//
// Ranking: biggest |delta| first (the sports your recovery moves most with), .solid
// ahead of .building on a tie, then sport name ascending — a fully deterministic order.
//
// Method note — this is plain descriptive statistics (medians over aligned day keys),
// in the spirit of HRV-/recovery-guided training monitoring (e.g. Plews et al. 2013;
// Task Force 1996 for the HRV that backs Charge). The MEDIAN (not the mean) is used so
// a single off night doesn't dominate a thin sample, matching the robust-center house
// style of Baselines.swift. All day arithmetic goes through CorrelationEngine.shiftDay
// (fixed UTC calendar).

// MARK: - Result

/// One sport's recovery association: how far below your rest baseline your next-morning
/// Charge tends to sit after a session of this sport, and how long it tends to take to
/// climb back. Descriptive association over your own history — not a causal cost.
public struct ActivityCost: Equatable, Sendable {
    /// The sport key (raw WHOOP sport / activity name, as tagged on the day).
    public let sport: String
    /// Signed gap in Charge points: baselineCenter − nextMorningCenter. Positive = the
    /// morning after tends to sit BELOW your rest baseline. Association, not a causal cost.
    public let delta: Double
    /// Median next-morning (D+1) Charge over tagged days that had a D+1 value, 0–100.
    public let nextMorningCenter: Double
    /// Median rest-day Charge this sport is measured against (shared across sports), 0–100.
    public let baselineCenter: Double
    /// Days for the median forward trajectory to climb back within `tolerance` of the
    /// baseline. Only populated for `.solid` results; nil for `.building`, or when it
    /// never recovers inside the lookahead window.
    public let daysToBaseline: Int?
    /// Number of tagged days that contributed a D+1 Charge value.
    public let n: Int
    /// Per-result certainty tier (reuses the shared confidence ladder).
    public let confidence: ScoreConfidence

    public init(sport: String, delta: Double, nextMorningCenter: Double, baselineCenter: Double,
                daysToBaseline: Int?, n: Int, confidence: ScoreConfidence) {
        self.sport = sport
        self.delta = delta
        self.nextMorningCenter = nextMorningCenter
        self.baselineCenter = baselineCenter
        self.daysToBaseline = daysToBaseline
        self.n = n
        self.confidence = confidence
    }

    /// Plain-English summary, framed as ASSOCIATION (not cause). Degrades gracefully:
    /// drops the bounce-back clause when `daysToBaseline` is nil, and says "barely
    /// linked" when the gap is under `barelyMovesPoints` in either direction.
    public func sentence() -> String {
        let mag = abs(delta)
        let points = ActivityCostEngine.roundToInt(mag)
        if mag < ActivityCostEngine.barelyMovesPoints {
            return "Sessions like this are barely linked to any change in your next-day Charge (n=\(n))."
        }
        let direction = delta >= 0 ? "lower" : "higher"
        let head = "Sessions like this are typically followed by a Charge about \(points) "
            + "point\(points == 1 ? "" : "s") \(direction) the next morning"
        if let days = daysToBaseline {
            return head + ", climbing back in about \(days) day\(days == 1 ? "" : "s") (n=\(n))."
        }
        return head + " (n=\(n))."
    }
}

// MARK: - Engine

public enum ActivityCostEngine {

    // MARK: Tunables (documented, deterministic — NOT learned)

    /// Tagged next-morning pairs below which a sport is OMITTED (too thin to report).
    /// Raised from the upstream's 4: at n≈4 the standard error of the center (~5 pts for
    /// SD≈10) is the same order as the gap itself, so a result that thin is mostly noise.
    public static let minSessions: Int = 6
    /// Pairs at/above which a sport's confidence is `.solid` (else `.building`).
    public static let solidSessions: Int = 8
    /// How many days forward the bounce-back trajectory is probed (D+1 … D+maxLookahead).
    /// 7 days is a defensible upper bound: recovery from a single bout is largely done in
    /// 24–72 h, with DOMS / eccentric damage trailing to ~5–7 days.
    public static let maxLookahead: Int = 7
    /// Charge points within the baseline that count as "recovered" for daysToBaseline.
    public static let tolerance: Double = 3.0
    /// |delta| under this (points) reads as "barely linked" in `sentence()`. Set to 3 to
    /// stay above the day-to-day test-retest noise floor of Charge (~±5–7 pts) so the
    /// narrative never sells a sub-noise gap as a real effect.
    public static let barelyMovesPoints: Double = 3.0

    // MARK: - Evaluate

    /// Compute each sport's recovery association from tagged activity days and daily Charge.
    ///
    /// - Parameters:
    ///   - activityDaysBySport: per sport, the SET of "yyyy-MM-dd" day keys that sport
    ///     was tagged on. Using a Set means same-day duplicates are already collapsed.
    ///   - recoveryByDay: daily Charge (recovery, 0–100) keyed by "yyyy-MM-dd".
    /// - Returns: one `ActivityCost` per sport that cleared `minSessions`, ranked by
    ///   |delta| desc, `.solid` before `.building`, sport name ascending on a tie.
    ///   Empty input (or no sport thick enough, or no untouched rest day) → empty array.
    public static func evaluate(activityDaysBySport: [String: Set<String>],
                                recoveryByDay: [String: Double]) -> [ActivityCost] {
        guard !activityDaysBySport.isEmpty, !recoveryByDay.isEmpty else { return [] }

        // Rest days = days WITH a Charge value that are neither tagged with ANY sport NOR sit inside
        // the forward recovery window (D+1 … D+maxLookahead) of any tagged day. Excluding the
        // after-effect window matters: the mornings *after* a session are exactly the days the gap
        // suppresses, so counting them as "rest" would contaminate the baseline with the very thing
        // we're measuring (understating every gap). The baseline must be your genuinely UNTOUCHED days.
        var activeUnion: Set<String> = []
        for (_, days) in activityDaysBySport { activeUnion.formUnion(days) }
        var affected = activeUnion
        for day in activeUnion {
            for k in 1...maxLookahead {
                if let d = CorrelationEngine.shiftDay(day, by: k) { affected.insert(d) }
            }
        }
        var restValues: [Double] = []
        for (day, value) in recoveryByDay where !affected.contains(day) {
            restValues.append(value)
        }
        // No untouched days → no baseline to measure against → nothing honest to say.
        guard !restValues.isEmpty else { return [] }
        let baselineCenter = median(restValues)

        var results: [ActivityCost] = []
        // Sort sports up front so the build order (and any downstream tie behaviour) is
        // deterministic regardless of dictionary iteration order.
        for sport in activityDaysBySport.keys.sorted() {
            let taggedDays = activityDaysBySport[sport]!

            // Collect next-morning (D+1) Charge for each tagged day that has one.
            var nextMornings: [Double] = []
            for day in taggedDays {
                guard let d1 = CorrelationEngine.shiftDay(day, by: 1),
                      let v = recoveryByDay[d1] else { continue }
                nextMornings.append(v)
            }
            let n = nextMornings.count
            // Thin sports are omitted entirely — better silent than fabricated.
            if n < minSessions { continue }

            let nextMorningCenter = median(nextMornings)
            let delta = baselineCenter - nextMorningCenter
            let confidence: ScoreConfidence = n >= solidSessions ? .solid : .building
            // daysToBaseline is the most fragile output (composite trajectory, tol near the
            // noise floor) — only surface it where the sample is solid enough to trust it.
            let daysToBaseline: Int? = confidence == .solid
                ? forwardDaysToBaseline(taggedDays: taggedDays,
                                        recoveryByDay: recoveryByDay,
                                        baselineCenter: baselineCenter)
                : nil

            results.append(ActivityCost(sport: sport, delta: delta,
                                        nextMorningCenter: nextMorningCenter,
                                        baselineCenter: baselineCenter,
                                        daysToBaseline: daysToBaseline,
                                        n: n, confidence: confidence))
        }

        return rank(results)
    }

    // MARK: - Bounce-back trajectory

    /// Smallest k in 1…maxLookahead where the MEDIAN forward Charge trajectory
    /// traj[k] = median over tagged days D (with a Charge on D+k) of Charge[D+k] climbs to
    /// within `tolerance` of `baselineCenter`. nil if it never does inside the window or no
    /// day contributed a value at that horizon.
    static func forwardDaysToBaseline(taggedDays: Set<String>,
                                      recoveryByDay: [String: Double],
                                      baselineCenter: Double) -> Int? {
        let target = baselineCenter - tolerance
        for k in 1...maxLookahead {
            var vals: [Double] = []
            for day in taggedDays {
                guard let dk = CorrelationEngine.shiftDay(day, by: k),
                      let v = recoveryByDay[dk] else { continue }
                vals.append(v)
            }
            guard !vals.isEmpty else { continue }
            if median(vals) >= target { return k }
        }
        return nil
    }

    // MARK: - Ranking

    /// Stable rank: |delta| desc, then .solid before .building, then sport name asc.
    static func rank(_ items: [ActivityCost]) -> [ActivityCost] {
        items.sorted { a, b in
            let da = abs(a.delta), db = abs(b.delta)
            if da != db { return da > db }
            let ra = confidenceRank(a.confidence), rb = confidenceRank(b.confidence)
            if ra != rb { return ra > rb }   // higher rank (solid) first
            return a.sport < b.sport
        }
    }

    /// Ordinal so .solid sorts ahead of .building (and .calibrating last).
    static func confidenceRank(_ c: ScoreConfidence) -> Int {
        switch c {
        case .solid: return 2
        case .building: return 1
        case .calibrating: return 0
        }
    }

    // MARK: - Stats

    /// Robust center, reusing the shared median helper (matches Baselines.swift's
    /// robust-center house style; a single off night doesn't dominate a thin sample).
    static func median(_ values: [Double]) -> Double {
        HRVAnalyzer.median(values)
    }

    /// Round half away from zero to an Int — matches Kotlin's roundToInt for the
    /// non-negative magnitudes used in `sentence()`.
    static func roundToInt(_ x: Double) -> Int {
        Int(x.rounded())
    }
}

// Confounders — why this is ASSOCIATION, not a causal "cost" (surfaced in the narrative
// and docs/ANALYTICS.md):
//   • Regression to the mean — you tend to train on days you wake up feeling good (high
//     Charge), so the next morning drifts back down regardless of the session.
//   • Non-random rest days — you rest when tired / sick / travelling, so "untouched" days
//     are not a clean counterfactual for "what your Charge would have been without the session".
//   • Day-of-week & overlapping sessions — a sport done mostly on weekends conflates the
//     sport with weekend behaviour; two sports on the same day both inherit that D+1 morning.
