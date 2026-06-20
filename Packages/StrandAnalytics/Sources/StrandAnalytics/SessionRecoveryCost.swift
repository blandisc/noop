import Foundation

// SessionRecoveryCost.swift — qualitative "recovery cost" of one strength session (FER-349).
//
// A TRANSPARENT, qualitative read of how much one session COST you cardiovascularly — Ligero /
// Moderado / Alto — not a number to chase. It reads a signal the strap ALREADY produces for the
// session (its strain, or mean %HRR as a fallback) and buckets it; it does NOT compute any new
// physiology, and it does NOT use mechanical load (weight × reps) — that is the 1RM's job
// (`OneRepMax`), and lifting heavy with little cardiac cost should read as light here.
//
// Method (the underlying quantities are already cited where they are computed):
//   • Edwards (1993) 5-zone TRIMP and Banister (1991) exponential TRIMP — what `StrainScorer.strain`
//     compresses into its 0–21 scale. The session's strain IS that quantity.
//   • Karvonen (1957) %HRR — the basis of the `avgHRRPct` fallback.
//   • Foster (1998) session-RPE / training monotony — the framework of "how much did this session
//     cost"; the Light/Moderate/High band is the qualitative session-load read, computed from the
//     objective HR signal instead of subjective RPE.
//
// The strain cuts (8 / 14) and the %HRR cuts (50 / 70) are PRODUCT CALIBRATION knobs, not validated
// quantities — exposed as `static let` so they can be tuned on-device without touching the logic.
// A full-day strain tops out at 21 (a sustained top-zone 24 h, see StrainScorer); a single lift
// session sits well below, so the cuts separate "low cardiac cost" from "a session that cost you".
//
// Honest degradation: no cardiac signal (no strap) → `nil`, and the UI does not invent a cost.
//
// NOT a clinical claim. Pure & database-free.

public enum SessionRecoveryCost {

    /// The qualitative cardiovascular cost band of one session.
    public enum Band: String, Equatable, Sendable {
        case light, moderate, high
    }

    /// Which signal the band was derived from (so UI/QA can trace it).
    public enum Basis: String, Equatable, Sendable {
        case sessionStrain  // used the session's 0–21 strain
        case meanHRR        // fallback: used mean %HRR
    }

    public struct Result: Equatable, Sendable {
        public let band: Band
        public let basis: Basis
        public init(band: Band, basis: Basis) {
            self.band = band
            self.basis = basis
        }
    }

    // Cuts on the session's 0–21 strain (Edwards/Banister TRIMP, compressed). Calibration knobs.
    public static let strainLightMax    = 8.0   // strain < 8  → light
    public static let strainModerateMax = 14.0  // 8 ≤ strain < 14 → moderate ; ≥ 14 → high

    // Fallback cuts on mean %HRR — the same Edwards zone thresholds StrainScorer already uses
    // (50/60/70/80/90 %HRR): < 50% sub-aerobic (light), 50–70% aerobic (moderate), ≥ 70% threshold+ (high).
    public static let hrrLightMax    = 50.0  // %HRR < 50 → light
    public static let hrrModerateMax = 70.0  // 50 ≤ %HRR < 70 → moderate ; ≥ 70 → high

    /// Qualitative cost of one session, or `nil` when there is no cardiac signal (no strap → the UI
    /// does not invent a cost).
    /// - Parameters:
    ///   - sessionStrain: the session's 0–21 strain (`StrainScorer.strain` over the session window,
    ///     or `ExerciseSession.strain`), or `nil`.
    ///   - meanHRRPct: mean %HRR of the session (fallback), optional.
    /// When both are present the strain WINS (it is the richer, zone-weighted signal).
    public static func cost(sessionStrain: Double?, meanHRRPct: Double? = nil) -> Result? {
        if let s = sessionStrain {
            let band: Band = s < strainLightMax ? .light : (s < strainModerateMax ? .moderate : .high)
            return Result(band: band, basis: .sessionStrain)
        }
        if let h = meanHRRPct {
            let band: Band = h < hrrLightMax ? .light : (h < hrrModerateMax ? .moderate : .high)
            return Result(band: band, basis: .meanHRR)
        }
        return nil
    }

    /// Convenience: derive both signals from an already-detected `ExerciseSession`.
    public static func cost(for session: ExerciseSession) -> Result? {
        cost(sessionStrain: session.strain, meanHRRPct: session.avgHRRPct)
    }
}
