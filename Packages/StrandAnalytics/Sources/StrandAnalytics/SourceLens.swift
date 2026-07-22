import Foundation
import StrandModels

// SourceLens.swift — clear cross-source columns so a baseline fold stays single-construct (FER-623 · FER-631).
//
// THE PROBLEM (load-bearing — do NOT remove the clearing)
// -------------------------------------------------------
// A daily row on Apple Health carries **SDNN** in `avgHrv` (total variability, all-day ~60 s windows),
// while the recovery/readiness engines were tuned on the band's **RMSSD** (vagally-mediated, sleep-windowed).
// The two are DIFFERENT time-domain constructs with **no published conversion** (Task Force 1996,
// Circulation 93(5):1043–1065; Shaffer & Ginsberg 2017, Front Public Health 5:258). Resting HR, respiration
// and the sleep stages carry their own measured band↔Apple offsets (FER-629). Folding a raw Apple `avgHrv`
// (SDNN) into a band-domain baseline biases every z-score taken against it — the classic contamination bug
// (FER-519: mixed base meanHRV ≈ 43.8 ms vs single-source ≈ 49.6 ms).
//
// THE FIX — clear the cross-source columns before a band-domain engine folds them
// -------------------------------------------------------------------------------
// A cleared column reads as a "missing" night to the skip-and-hold folds — never a zero — so nothing enters
// a baseline it doesn't belong in. This is Apple-only (greenfield): every row is an Apple row, so the clearing
// is UNCONDITIONAL (no source selection). The autonomic trend — the one HRV number the app shows — does NOT
// come through here: it reads real nocturnal **RMSSD** (`apple_rmssd_night`) via `SourceFusion.autonomicTrend`,
// which never touches `avgHrv`/SourceLens.
public enum SourceLens {

    /// Clear EVERY cross-source column — `avgHrv`, `restingHr`, `respRateBpm`, the sleep stages
    /// `deepMin`/`remMin`/`lightMin`, and `skinTempDevC` — on every row, leaving single-source and
    /// cross-source-comparable columns (`totalSleepMin`, `efficiency`, `strain`, `spo2Pct`, `steps`, …)
    /// intact. For band-domain baseline consumers (readiness/ACWR σ, Body Age/Vitality, insights, cycle
    /// skin-temp): passing a raw Apple `avgHrv` (SDNN) here instead would reintroduce FER-519/629.
    public static func clearBandColumns(_ days: [DailyMetric]) -> [DailyMetric] {
        days.map { $0.crossSourceMasked() }
    }

    /// Clear ONLY `avgHrv`, leaving the night's other Apple signals (RHR/resp/skin-temp) intact for
    /// consumers that z-score them within-source (verdict, Daily Brief σ, StressModel). Same rationale:
    /// an Apple SDNN value must not fold into a band-RMSSD baseline.
    public static func clearBandHrv(_ days: [DailyMetric]) -> [DailyMetric] {
        days.map { $0.hrvMasked() }
    }
}

private extension DailyMetric {
    /// Rebuild the row with `avgHrv` nilled, every other column intact (the struct is immutable and has
    /// no `copy()`). A cleared day reads as a "missing HRV night" to a fold — skip-and-hold, not a zero.
    func hrvMasked() -> DailyMetric {
        with(avgHrv: .set(nil))
    }

    /// Rebuild the row with every CROSS-SOURCE column nilled — `avgHrv`, `restingHr`, `respRateBpm`, the
    /// sleep stages `deepMin`/`remMin`/`lightMin`, and `skinTempDevC` (FER-882) — and everything else
    /// (duration, disturbances, efficiency, recovery, strain, single-source signals) intact. Each nilled
    /// column reads as "missing" to a fold, so the baseline is built single-construct. Duration survives
    /// because it's comparable across sources (it feeds the engine's short-night confidence honestly); the
    /// STAGES don't (measured offsets). Skin-temp Δ is source-specific (band and Apple each fold their own
    /// absolute °C baseline, so the stored Δs are not interchangeable).
    func crossSourceMasked() -> DailyMetric {
        with(deepMin: .set(nil), remMin: .set(nil), lightMin: .set(nil),
             restingHr: .set(nil), avgHrv: .set(nil), skinTempDevC: .set(nil), respRateBpm: .set(nil))
    }
}
