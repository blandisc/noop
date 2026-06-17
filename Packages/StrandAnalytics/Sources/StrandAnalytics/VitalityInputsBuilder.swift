import Foundation

// MARK: - Vitality inputs builder (FER-145 — orchestration, pure half)
//
// Aggregates a window of raw nightly/daily NOOP signals into a `VitalityEngine.Inputs`, so the app
// layer only has to EXTRACT the arrays from `repo.days` and hand them over (the database-touching half
// stays in the app; this stays pure and testable, like the rest of StrandAnalytics).
//
// Aggregation choices, each deliberate:
//   • Resting HR / RMSSD / sleep hours → MEDIAN over the window (robust to a bad night), not mean.
//   • RMSSD is GATED: it only scores with at least `minHRVNights` valid nights (the requirement's
//     "coverage gating" — a couple of noisy PPG nights shouldn't move a longevity number). Below the
//     gate the HRV factor is simply absent and the engine's honesty gate handles the rest.
//   • Sleep regularity uses the engine's INTERIM proxy `sleepConsistency` (1 − CV of duration). The
//     real Sleep Regularity Index (timing, epoch-by-epoch) is FER-214; when it lands the app passes a
//     real SRI/100 through the same field and this proxy is dropped — no UI change.
//   • VO₂max is left nil: the absolute Nes VO₂max needs a WAIST measurement the profile doesn't
//     collect, so the cardiovascular signal flows through resting HR (a direct, validated Nes
//     predictor) instead. The vo2max factor activates automatically if a waist field is ever added.
//   • Steps → MEAN (a count, not a level); 0 is a real value, so only negatives are filtered.

public enum VitalityInputsBuilder {

    /// RMSSD only scores with at least this many valid nights in the window (coverage gate).
    public static let minHRVNights = 5

    /// Raw signals over a recent window (most callers pass ~28 nights). Order doesn't matter.
    public struct Signals: Equatable, Sendable {
        public var chronoAge: Double
        public var nightlyRestingHR: [Double]   // bpm, nocturnal
        public var nightlyRMSSD: [Double]       // ms, nocturnal HRV
        public var nightlySleepHours: [Double]  // hours per night
        public var dailySteps: [Double]         // steps per day
        /// A real Sleep Regularity Index on 0–1 (SRI/100, FER-214); when present it OVERRIDES the
        /// duration proxy below. nil → fall back to the `1 − CV` proxy.
        public var sleepRegularity: Double?

        public init(chronoAge: Double,
                    nightlyRestingHR: [Double] = [],
                    nightlyRMSSD: [Double] = [],
                    nightlySleepHours: [Double] = [],
                    dailySteps: [Double] = [],
                    sleepRegularity: Double? = nil) {
            self.chronoAge = chronoAge
            self.nightlyRestingHR = nightlyRestingHR
            self.nightlyRMSSD = nightlyRMSSD
            self.nightlySleepHours = nightlySleepHours
            self.dailySteps = dailySteps
            self.sleepRegularity = sleepRegularity
        }
    }

    /// Build the engine inputs from a window of raw signals (medians + the HRV coverage gate + the
    /// interim regularity proxy). The caller then runs `VitalityEngine.compute(_:)`.
    public static func build(_ s: Signals) -> VitalityEngine.Inputs {
        let restingHR = median(s.nightlyRestingHR.filter { $0 > 0 })

        let rmssdNights = s.nightlyRMSSD.filter { $0 > 0 }
        let rmssd = rmssdNights.count >= minHRVNights ? median(rmssdNights) : nil
        let rmssdNorm = rmssd != nil ? VitalityEngine.rmssdNorm(forAge: s.chronoAge) : nil

        let sleepHours = median(s.nightlySleepHours.filter { $0 > 0 })
        // A real SRI (FER-214) wins when present; otherwise the documented duration proxy.
        let consistency = s.sleepRegularity ?? VitalityEngine.sleepConsistency(nightlyHours: s.nightlySleepHours)

        let steps = mean(s.dailySteps.filter { $0 >= 0 })

        return VitalityEngine.Inputs(
            chronoAge: s.chronoAge,
            restingHR: restingHR,
            vo2max: nil,
            expectedVO2max: nil,
            sleepHours: sleepHours,
            sleepConsistency: consistency,
            rmssd: rmssd,
            rmssdNorm: rmssdNorm,
            steps: steps)
    }

    // MARK: - Aggregation helpers

    // Delegate the math to the module's canonical reducers; the `nil`-on-empty is load-bearing here
    // (it feeds VitalityEngine's honesty gate), so keep the guard the shared helpers don't have.
    static func median(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : HRVAnalyzer.median(xs) }
    static func mean(_ xs: [Double]) -> Double? { ReadinessEngine.mean(xs) }
}
