import Foundation

// ScoreConfidence.swift — per-result certainty tier.
//
// A small, dependency-free 3-tier ladder a descriptive engine can ride so a thin
// result reads truthfully instead of faking precision. Ordered lowest → highest:
//
//   .calibrating — not enough input to compute at all (the number, if any, is a placeholder).
//   .building    — usable but thin: enough to compute, but the sample is small / provisional.
//   .solid       — full inputs present and the result is trusted.
//
// The tiers are a minimal port from upstream NoopApp/noop; the Charge / Effort /
// Rest derivers below are ADAPTED to this fork's own scoring types (DailyMetric,
// StrainScorer output, SleepMath) rather than copied — the upstream helpers depend
// on scoring types this fork packages differently (see FER-123). Derived in FER-676.
public enum ScoreConfidence: String, Equatable, Sendable, Codable {
    case calibrating
    case building
    case solid

    /// One tier lower, floored at `.calibrating` (solid → building → calibrating).
    /// Used to down-grade a result when one input is thin even though the baseline
    /// is otherwise trusted (e.g. AppleRecoveryEstimator: trusted baseline but poor
    /// overnight coverage). Keeps the ladder ordered without a numeric raw value.
    public var lowered: ScoreConfidence {
        switch self {
        case .solid:       return .building
        case .building:    return .calibrating
        case .calibrating: return .calibrating
        }
    }

    // MARK: - Derivers (FER-676)
    //
    // Three pure derivations, one per daily score, plus the H9 staging guard. Only
    // the H9 threshold has published physiological backing; every count/duration
    // cut-off below is a PRODUCT-CALIBRATION KNOB (data-completeness gate), NOT a
    // value derived from literature — labelled as such so the code never disguises a
    // knob as a derived constant (CSO honesty discipline).

    /// Recovery (`charge`) confidence from how many HRV-baseline nights back the
    /// estimate. Coverage is already a hard gate upstream (short nights are omitted,
    /// not downgraded), so this only tracks how settled the baseline is.
    /// `solidNights`/`buildingNights` are the caller's baseline-trust knobs (14 / 7
    /// in `AppleRecoveryEstimator`, matching `Baselines.minNightsTrust`).
    public static func charge(hrvBaselineNights nValid: Int,
                              solidNights: Int = 14,
                              buildingNights: Int = 7) -> ScoreConfidence {
        nValid >= solidNights ? .solid
      : nValid >= buildingNights ? .building
      : .calibrating
    }

    /// Strain (`effort`) confidence from HR coverage of the active day. Sparse HR
    /// (strap gaps / non-wear) → strain integrates over less time → under-estimate →
    /// lower confidence. `hasEnoughData` is `StrainScorer.hasEnoughData` (the same
    /// floor that gates whether strain is scored at all); pass the day's sorted HR
    /// sample seconds (`HRSample.ts`).
    ///
    /// - `calibrating` — not enough data to score at all.
    /// - `building`    — scored, but coverage < `minCoverageFrac` OR the sampled span
    ///                   is shorter than `minSpanSeconds` (a barely-sampled day).
    /// - `solid`       — coverage ≥ `minCoverageFrac` AND span ≥ `minSpanSeconds`.
    ///
    /// `minCoverageFrac` (0.70), `windowSeconds` (30 min) and `minSpanSeconds` (4 h)
    /// are product-calibration knobs, not validated — the 30-min window tolerates the
    /// 5/MG's ~30 s live-HR cadence; the span floor stops a short gym-only block from
    /// scoring `solid` on a near-empty day. (CDO to validate against real data.)
    public static func effort(hasEnoughData: Bool,
                              hrSampleSecondsSorted ts: [Int],
                              minCoverageFrac: Double = 0.70,
                              windowSeconds: Int = 1800,
                              minSpanSeconds: Int = 14_400) -> ScoreConfidence {
        guard hasEnoughData else { return .calibrating }
        guard let first = ts.first, let last = ts.last, last - first >= minSpanSeconds else { return .building }
        let coverage = hrCoverageFraction(secondsSorted: ts, windowSeconds: windowSeconds)
        return coverage >= minCoverageFrac ? .solid : .building
    }

    /// Fraction of `windowSeconds`-wide buckets — spanning the first-to-last sample —
    /// that hold ≥ 1 HR sample. 1.0 = uninterrupted coverage; gaps drop it. Pure;
    /// `ts` must be sorted ascending. Returns 0 for < 2 samples or a zero span.
    static func hrCoverageFraction(secondsSorted ts: [Int], windowSeconds: Int) -> Double {
        guard windowSeconds > 0, let first = ts.first, let last = ts.last, last > first else { return 0 }
        let totalWindows = (last - first) / windowSeconds + 1
        // `ts` is ascending, so the window index is monotonic non-decreasing — count the
        // transitions in one pass instead of hashing every sample into a Set.
        var occupied = 0, lastWindow = -1
        for t in ts {
            let w = (t - first) / windowSeconds
            if w != lastWindow { occupied += 1; lastWindow = w }
        }
        return Double(occupied) / Double(totalWindows)
    }

    /// Sleep (`rest`) confidence from night duration and whether stages resolved.
    /// `efficiency` alone is not enough — a total can arrive without a stage breakdown.
    ///
    /// - `calibrating` — no total, or `totalSleepMin` < `minNightMin` (a nap/fragment,
    ///                   not a night: fewer than two ~90-min NREM-REM cycles, so stage
    ///                   percentages aren't representative).
    /// - `building`    — a real night in duration, but stages unresolved
    ///                   (`deepMin` or `remMin` nil).
    /// - `solid`       — `totalSleepMin` ≥ `solidNightMin` AND both stages resolved.
    ///
    /// `minNightMin` (180) and `solidNightMin` (240) are product-calibration knobs,
    /// not validated — there is no published minimum-duration-to-stage threshold.
    public static func rest(totalSleepMin: Double?,
                            deepMin: Double?,
                            remMin: Double?,
                            minNightMin: Double = 180,
                            solidNightMin: Double = 240) -> ScoreConfidence {
        guard let total = totalSleepMin, total >= minNightMin else { return .calibrating }
        let stagesResolved = deepMin != nil && remMin != nil
        return (total >= solidNightMin && stagesResolved) ? .solid : .building
    }

    /// H9 — suspicious staging. High sleep efficiency but deep+REM ≈ 0 is
    /// physiologically impossible (deep ~15-20% + REM ~20-25% ≈ 35-45% of TST in
    /// healthy adults; efficiency ≥ 0.85 means substantial real sleep), so it signals
    /// the stager failed (everything fell to light), not a real night. When true, the
    /// caller lowers that night's `rest` confidence one tier (`.lowered`) — it never
    /// fabricates stages. `nil` stages count as 0 so "no breakdown at high efficiency"
    /// also trips. Refs: ISSR / Harvard Healthy Sleep (stage architecture); 85% is the
    /// clinical floor for non-fragmented sleep.
    public static func suspiciousStaging(efficiency: Double?,
                                         deepMin: Double?,
                                         remMin: Double?,
                                         minEfficiency: Double = 0.85,
                                         maxStageMin: Double = 1.0) -> Bool {
        guard let eff = efficiency, eff >= minEfficiency else { return false }
        return (deepMin ?? 0) + (remMin ?? 0) <= maxStageMin
    }
}
