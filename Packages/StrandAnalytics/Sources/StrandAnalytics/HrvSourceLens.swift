import Foundation
import WhoopStore

// HrvSourceLens.swift — keep an HRV baseline pure by SOURCE (FER-623).
//
// THE PROBLEM
// -----------
// The band reports HRV as **RMSSD** (vagally-mediated, sleep-windowed); Apple Health reports it as
// **SDNN** (total variability, all-day ~60 s windows). They are two different time-domain constructs
// with **no published conversion** (Task Force 1996, Circulation 93(5):1043–1065; Shaffer & Ginsberg
// 2017, Front Public Health 5:258). Folding Apple SDNN into the band's RMSSD baseline mixes the two and
// biases every z-score taken against it — the verdict's «HRV vs your base» reads further from baseline
// than it really is, and the Stress proxy is depressed (FER-623, owner DB: mixed base meanHRV ≈ 43.8 ms
// vs band-only ≈ 49.6 ms).
//
// THE FIX
// -------
// The same masking FER-519/FER-543 applied to Recovery and the illness sentinel, exposed as a pure,
// testable lens. `mask` keeps `avgHrv` only on the rows of the requested source and nils it on the rest;
// every other column (RHR, respiration, sleep, recovery, strain) is left intact — those are either the
// same physical metric across sources (RHR/resp) or untouched by this bug. A consumer then folds the
// masked rows to get a single-source baseline, and z-scores each reading against the baseline of ITS OWN
// source. The **z-score is the common currency** between sources (relative, scale-invariant in the
// log domain); raw ms are never compared across sources, and there is no conversion factor.
//
// `appleDays` is the set of day-keys the app surfaced from Apple Health (`repo.appleHealthDays`) — source
// is app knowledge, so the caller passes the set and this package stays pure (no store/actor state).
// `keep: .band, appleDays == []` (a strap-only user, or whoopOnly mode) is the IDENTITY: the same array
// is returned untouched, so nothing about an existing strap user's output changes.
public enum HrvSourceLens {

    /// Which source's HRV to keep. `.band` = RMSSD (strap nights); `.apple` = SDNN (Apple-only nights).
    public enum Source: Sendable, Equatable { case band, apple }

    /// Return `days` with `avgHrv` preserved ONLY on the rows belonging to `keep`, and nil elsewhere.
    /// All other columns are untouched. `keep: .band, appleDays: []` returns `days` verbatim (identity).
    /// - Parameters:
    ///   - days: the merged daily history (any order; the lens is positional, not sorted).
    ///   - keep: the source whose `avgHrv` survives; the other source's `avgHrv` becomes nil.
    ///   - appleDays: the day-keys surfaced from Apple Health (`repo.appleHealthDays`), i.e. the SDNN rows.
    public static func mask(_ days: [DailyMetric], keep: Source,
                            appleDays: Set<String>) -> [DailyMetric] {
        // Fast path: a strap-only user (no Apple days) keeping the band source is the identity — return
        // the array untouched so an existing user's verdict/stress output is bit-for-bit unchanged.
        if keep == .band && appleDays.isEmpty { return days }
        return days.map { d in
            let isApple = appleDays.contains(d.day)
            let keepHrv = (keep == .band) ? !isApple : isApple
            return keepHrv ? d : d.hrvMasked()
        }
    }
}

private extension DailyMetric {
    /// Rebuild the row with `avgHrv` nilled, every other column intact (the struct is immutable and has
    /// no `copy()`). A masked day reads as a "missing HRV night" to a fold — skip-and-hold, not a zero.
    func hrvMasked() -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: totalSleepMin, efficiency: efficiency, deepMin: deepMin,
                    remMin: remMin, lightMin: lightMin, disturbances: disturbances, restingHr: restingHr,
                    avgHrv: nil, recovery: recovery, strain: strain, exerciseCount: exerciseCount,
                    spo2Pct: spo2Pct, skinTempDevC: skinTempDevC, respRateBpm: respRateBpm,
                    steps: steps, activeKcalEst: activeKcalEst)
    }
}
