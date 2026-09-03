import Foundation

// SessionRPELoad.swift — load from MINUTES × EFFORT, on the same 0–21 strain scale (ola 1 · E2).
//
// Why it exists: heart rate does not discriminate intensity in strength training (Falk Neto 2020),
// and a Cénit session logged without a watch produced NO load at all — the day fell through
// `AppleLoadEstimator.classify` as `.rest`, a zero. Perceived effort does discriminate it
// (Day 2004, Sweet 2004, Haddad 2017), so a session the user rates gets a load.
//
// Method — «carga por esfuerzo: minutos × RPE de sesión (escala RIR mapeada a CR-10), calibrada
// contra el TRIMP de FC; INSPIRADO en session-RPE (Foster 2001), no literal». Three deliberate
// departures from Foster, each named:
//   1. Foster captures the rating ~30 min AFTER the session on a 0–10 CR-10 scale. Cénit asks in the
//      receipt, on the app's 6–10 RIR-anchored row (Zourdos 2016: 10 = 0 reps in reserve).
//   2. That row is NOT CR-10: its dynamic range is 10/6 = 1.67×, Foster's is ≥ 2.5×. A multiplicative
//      constant cannot absorb an ADDITIVE scale offset, so the map is explicit and affine:
//      `cr10 = 1.5·rpe − 5` (6→4 «algo duro», 8→7 «muy duro», 10→10 «máximo»).
//   3. Foster's AU are not TRIMP. `trimpPerAU` is the bridge onto the Edwards-TRIMP axis the 0–21
//      scale is built on, so an estimated session and a measured one land on ONE ruler.
//
// APPROXIMATE, documented, and not a clinical claim. Every knob below is a calibration default —
// /estadistico owns them (gate estadístico ola 1, H2/H3/H4/H9/H10, 2026-09-02).
public enum SessionRPELoad {

    // MARK: - Constants (calibration defaults, /estadistico owns)

    /// Lowest rating the session-effort row offers (RIR-anchored: 6 ≈ 4 reps in reserve).
    public static let rpeMin: Double = 6.0
    /// Highest rating the row offers (10 = 0 reps in reserve, «al fallo»).
    public static let rpeMax: Double = 10.0
    /// Below this a session is too short to estimate at all (seconds).
    public static let minDurationS: Int = 300
    /// Ceiling used when estimating (seconds): a session left open for hours is capped at 3 h rather
    /// than billed linearly (H10). Not a rejection — the minutes above the cap simply don't count.
    public static let maxDurationS: Int = 3 * 3600
    /// TRIMP per arbitrary unit. Default 0.29 — calibration default, NOT validated; /estadistico owns.
    /// Anchor: 50 min at RPE 8 → cr10 7 → 350 AU → 101.5 TRIMP → strain 10.95, the band a 50-minute
    /// zone-1/2 session lands in (test band 10–12).
    public static let defaultTrimpPerAU: Double = 0.29
    /// Pairs needed before the personal fit replaces the default (H3).
    public static let minCalibrationPairs: Int = 5
    /// Hard bounds on any fitted `trimpPerAU` (H3).
    public static let trimpPerAUBounds: ClosedRange<Double> = 0.05...1.0
    /// A refit is only ACCEPTED when it moves the scale by more than this (H4: a k that jumps
    /// linearly rescales the whole ACWR — 0.25→0.5 turned a stable 0.75 into 0.92 «Ramping fast»
    /// with an unchanged routine).
    public static let refitMinRelativeChange: Double = 0.15

    /// Affine map from the app's 6–10 RIR row onto Foster's CR-10 (H2). Slope/intercept named so the
    /// anchors are readable: 6→4, 8→7, 10→10.
    static let cr10Slope: Double = 1.5
    static let cr10Intercept: Double = -5.0

    // MARK: - The map

    /// The session rating on Foster's CR-10 scale; `nil` outside [`rpeMin`, `rpeMax`] — never clamped
    /// upward, an out-of-range rating is a missing rating.
    public static func cr10(_ rpe: Double) -> Double? {
        guard rpe >= rpeMin, rpe <= rpeMax else { return nil }
        return cr10Slope * rpe + cr10Intercept
    }

    /// Foster arbitrary units: minutes × CR-10. `nil` for a session under `minDurationS` or an
    /// out-of-range rating. Minutes above `maxDurationS` don't count.
    public static func arbitraryUnits(durationS: Int, rpe: Double) -> Double? {
        guard durationS >= minDurationS, let c = cr10(rpe) else { return nil }
        return Double(min(durationS, maxDurationS)) / 60.0 * c
    }

    /// The session's load on the SAME 0–21 scale `StrainScorer` puts heart rate on. `nil` when the
    /// session can't be estimated (too short, or no usable rating).
    public static func strain(durationS: Int, rpe: Double,
                              trimpPerAU: Double = defaultTrimpPerAU) -> Double? {
        guard let au = arbitraryUnits(durationS: durationS, rpe: rpe) else { return nil }
        return StrainScorer.trimpToStrain(trimpPerAU * au)
    }

    // MARK: - Personal calibration

    /// Fit `trimpPerAU` from (AU, measured TRIMP) pairs — sessions that carry BOTH a rating and a
    /// pulse series good enough to measure (`HRCoverage.isMeasured`).
    ///
    /// Estimator = MEDIAN OF RATIOS (Theil–Sen through the origin), not least squares: OLS weights
    /// each pair by AU², so one 3-hour session at RPE 10 dragged k from 0.258 to 0.111 (−57 %) while
    /// the median held at 0.250, and the clamp does not catch a number that far inside it (H3).
    /// `nil` under `minCalibrationPairs` usable pairs → the caller keeps the default.
    public static func fitTrimpPerAU(pairs: [(au: Double, trimp: Double)]) -> Double? {
        let ratios = pairs.filter { $0.au > 0 && $0.trimp > 0 }.map { $0.trimp / $0.au }.sorted()
        guard ratios.count >= minCalibrationPairs else { return nil }
        let mid = ratios.count / 2
        let m = ratios.count.isMultiple(of: 2) ? (ratios[mid - 1] + ratios[mid]) / 2 : ratios[mid]
        return min(max(m, trimpPerAUBounds.lowerBound), trimpPerAUBounds.upperBound)
    }

    /// Whether a freshly fitted scale may REPLACE the one in use (H4). Two gates, both required:
    /// the evidence has to have DOUBLED since the last fit (5 → 10 → 20 → 40 …), and the new scale
    /// has to differ by more than `refitMinRelativeChange`. Anything else keeps the current k, so a
    /// user's ACWR doesn't drift band by band on noise.
    /// `lastFitPairCount == nil` = never fitted: only the pair floor applies.
    public static func shouldAcceptRefit(pairCount: Int, lastFitPairCount: Int?,
                                         currentTrimpPerAU: Double, candidateTrimpPerAU: Double) -> Bool {
        guard pairCount >= max(minCalibrationPairs, 2 * (lastFitPairCount ?? 0)) else { return false }
        guard currentTrimpPerAU > 0 else { return true }
        return abs(candidateTrimpPerAU - currentTrimpPerAU) / currentTrimpPerAU > refitMinRelativeChange
    }
}
