import Foundation
import StrandModels

// SourceLens.swift — keep a baseline pure by SOURCE (FER-623 · FER-631).
//
// THE PROBLEM
// -----------
// The band and Apple Health report the same-named vitals with DIFFERENT instruments, and none of the
// cross-source pairs is interchangeable without a correction:
//   • HRV: the band reports **RMSSD** (vagally-mediated, sleep-windowed); Apple reports **SDNN** (total
//     variability, all-day ~60 s windows) — two time-domain constructs with **no published conversion**
//     (Task Force 1996, Circulation 93(5):1043–1065; Shaffer & Ginsberg 2017, Front Public Health 5:258).
//   • Resting HR (band −12.7 bpm vs Apple), respiration (band +2.3 bpm), and the sleep stages
//     (deep/REM/light, up to −3.1σ) all carry measured band↔Apple offsets (FER-629).
// Folding an Apple night into a band-anchored baseline mixes the two and biases every z-score taken
// against it — «HRV vs your base» reads further from baseline than it is (FER-623: mixed base meanHRV
// ≈ 43.8 ms vs band-only ≈ 49.6 ms), resting-HR σ collapses toward «normal», and so on.
// `spo2Pct`, `steps`, `efficiency` are single-source (one instrument) → no lens needed.
// `skinTempDevC` was single-source until FER-882 (Apple now writes its own wrist-temp Δ); it is
// cross-source and must be masked so a band-Δ night and an Apple-Δ night never share a baseline fold.
//
// THE FIX — one row classification, two lenses
// --------------------------------------------
// Both lenses split the merged history into «this source's rows» vs «the other source's rows» with the
// SAME predicate, then blank the other source's columns before a consumer folds them. A folded night that
// went to nil reads as a "missing" night to the skip-and-hold folds — never a zero — so each reading is
// z-scored against the baseline of ITS OWN source. The **z-score is the common currency** across sources
// (relative, scale-invariant in the log domain); raw ms are never compared, and there is no conversion.
//
//   • `maskHrv` (FER-623) nils ONLY `avgHrv` on the other source's rows — for consumers that still want the
//     Apple night's OTHER signals (verdict / Daily Brief σ, StressModel): the brief adds an estimated SDNN
//     bullet on a band-less day, Stress scores each reading against its own source.
//   • `maskForBaseline` (FER-631 / FER-882) nils EVERY cross-source column — `avgHrv`, `restingHr`,
//     `respRateBpm`, `deepMin`/`remMin`/`lightMin`, and `skinTempDevC` — for band-anchored consumers
//     (Recovery detail σ, FER-632+; illness/cycle skin-temp routing). It is the column-level equivalent of
//     `IntelligenceEngine.strapOnlyHistory` (which drops the whole row): under the engine's skip-and-hold
//     folds both yield the SAME single-source baseline (pinned by test — the folds treat a nil column and
//     an absent row identically). The row-windowed respiration/Stress baselines (`suffix(30)`) are the one
//     place the two differ past 30 rows of history: masking keeps fewer, more recent band nights in-window
//     rather than reaching further back. Both stay 100% band-pure — masking is simply the more conservative
//     of the two — so it never reintroduces contamination.
//
// `appleDays` is the set of day-keys the app surfaced from Apple Health (`repo.appleHealthDays`) — source is
// app knowledge, so the caller passes the set and this package stays pure (no store/actor state).
// `keep: .band, appleDays == []` (a strap-only user, or whoopOnly mode) is the IDENTITY for both lenses: the
// same array is returned untouched, so nothing about an existing strap user's output changes bit-for-bit.
public enum SourceLens {

    /// Which source's data to keep. `.band` = strap nights (RMSSD HRV); `.apple` = Apple-only nights (SDNN).
    public enum Source: Sendable, Equatable { case band, apple }

    /// Does this row belong to the source we're keeping? `.band` keeps every non-Apple day; `.apple` keeps
    /// only the Apple days. The single classification both lenses share, so they can never diverge on a row.
    private static func keeps(_ day: String, keep: Source, appleDays: Set<String>) -> Bool {
        let isApple = appleDays.contains(day)
        return (keep == .band) ? !isApple : isApple
    }

    /// Return `days` with `avgHrv` preserved ONLY on the rows belonging to `keep`, and nil elsewhere.
    /// All other columns are untouched. `keep: .band, appleDays: []` returns `days` verbatim (identity).
    /// The FER-623 column lens (HRV-only): consumers that still want the other source's RHR/resp/sleep.
    /// - Parameters:
    ///   - days: the merged daily history (any order; the lens is positional, not sorted).
    ///   - keep: the source whose `avgHrv` survives; the other source's `avgHrv` becomes nil.
    ///   - appleDays: the day-keys surfaced from Apple Health (`repo.appleHealthDays`), i.e. the SDNN rows.
    public static func maskHrv(_ days: [DailyMetric], keep: Source,
                               appleDays: Set<String>) -> [DailyMetric] {
        mask(days, keep: keep, appleDays: appleDays) { $0.hrvMasked() }
    }

    /// Return `days` with EVERY cross-source column — `avgHrv`, `restingHr`, `respRateBpm`, the sleep
    /// stages `deepMin`/`remMin`/`lightMin`, and `skinTempDevC` — preserved ONLY on the rows belonging to
    /// `keep`, and nil on the rest. Single-source and cross-source-comparable columns (`totalSleepMin`,
    /// `disturbances`, `efficiency`, `recovery`, `strain`, `spo2Pct`, `steps`, `activeKcalEst`,
    /// `exerciseCount`) are left intact. `skinTempDevC` is cross-source as of FER-882 (Apple writes its own
    /// wrist-temp Δ vs its own baseline; never fold a band-Δ night with an Apple-Δ night). This is the
    /// column-level twin of `IntelligenceEngine.strapOnlyHistory` (whole-row drop): under the readiness
    /// engine's skip-and-hold folds, the resulting single-source baseline is identical (FER-631).
    /// `keep: .band, appleDays: []` returns `days` verbatim (identity — a strap-only user is unchanged).
    public static func maskForBaseline(_ days: [DailyMetric], keep: Source,
                                       appleDays: Set<String>) -> [DailyMetric] {
        mask(days, keep: keep, appleDays: appleDays) { $0.crossSourceMasked() }
    }

    /// Shared body for both lenses: the identity fast-path plus the positional map. `blank` is the only thing
    /// that differs — `hrvMasked` (HRV only) vs `crossSourceMasked` (every cross-source column).
    /// Fast path: a strap-only user (no Apple days) keeping the band source is the identity — the array is
    /// returned untouched so an existing user's output is bit-for-bit unchanged.
    private static func mask(_ days: [DailyMetric], keep: Source, appleDays: Set<String>,
                             blank: (DailyMetric) -> DailyMetric) -> [DailyMetric] {
        if keep == .band && appleDays.isEmpty { return days }
        return days.map { keeps($0.day, keep: keep, appleDays: appleDays) ? $0 : blank($0) }
    }

    /// Whole-row baseline lens: drop every Apple-sourced day, keep the rest of the history verbatim.
    /// `appleHealthDays == []` is the identity. The ROW sibling of `maskForBaseline` (that nils
    /// cross-source columns in place; this drops the whole row). Used by illness detection to fold a
    /// single-source baseline (FER-634). Relocated from the retired IntelligenceEngine; the identity
    /// collapse is deferred to the read-model phase (science gate).
    public static func strapOnlyHistory(_ hist: [DailyMetric],
                                        appleHealthDays: Set<String>) -> [DailyMetric] {
        appleHealthDays.isEmpty ? hist : hist.filter { !appleHealthDays.contains($0.day) }
    }
}

private extension DailyMetric {
    /// Rebuild the row with `avgHrv` nilled, every other column intact (the struct is immutable and has
    /// no `copy()`). A masked day reads as a "missing HRV night" to a fold — skip-and-hold, not a zero.
    func hrvMasked() -> DailyMetric {
        with(avgHrv: .set(nil))
    }

    /// Rebuild the row with every CROSS-SOURCE column nilled — `avgHrv`, `restingHr`, `respRateBpm`, the
    /// sleep stages `deepMin`/`remMin`/`lightMin`, and `skinTempDevC` (FER-882) — and everything else
    /// (duration, disturbances, efficiency, recovery, strain, single-source signals) intact. Each nilled
    /// column reads as "missing" to a fold, so the baseline is built from the kept source only. Duration
    /// survives because it's comparable across sources (it feeds the engine's short-night confidence
    /// honestly); the STAGES don't (measured offsets). Skin-temp Δ is source-specific: band and Apple each
    /// fold their own absolute °C baseline, so the stored Δs are not interchangeable.
    func crossSourceMasked() -> DailyMetric {
        with(deepMin: .set(nil), remMin: .set(nil), lightMin: .set(nil),
             restingHr: .set(nil), avgHrv: .set(nil), skinTempDevC: .set(nil), respRateBpm: .set(nil))
    }
}
