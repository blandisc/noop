import Foundation
import BiometricStreams

// ThermalStabilityEngine.swift — nocturnal distal (wrist) warming magnitude + its night-to-night
// stability. Pure, deterministic, DB-free. The NIGHT-TIME arm of the circadian thermal oscillation —
// the only arm an at-sleep wrist sensor can honestly see (FER-681).
//
// SENSOR HONESTY (the load-bearing constraint). NOOP has skin temperature only WHILE ASLEEP (the band
// is worn to bed), so it CANNOT fit a 24 h cosinor and MUST NOT claim a "24 h circadian amplitude".
// What it can measure is the distal WARMING that accompanies sleep onset — wrist skin temperature
// rises as core temperature falls and distal vasodilation dumps heat (Kräuchi et al., "Warm feet
// promote the rapid onset of sleep", Nature 1999;401:36–37; the distal-minus-proximal gradient as the
// sleep-onset thermoregulatory signal). This engine reports (a) the MAGNITUDE of that nightly warming
// and (b) how CONSISTENT it is night-to-night — framed strictly as "nocturnal thermal stability",
// never a 24 h amplitude, and never translated into a disease hazard ratio.
//
// EVIDENCE, framed as association. A flattened 24 h wrist-temperature amplitude is ASSOCIATED with
// higher future risk of cardiometabolic disease in UK Biobank — a −2 SD (−1.8 °C) amplitude carried
// hazard ratios of ~1.91 (NAFLD) and ~1.69 (type-2 diabetes): Brooks TG, Lahens NF, Grant GR,
// Sheline YI, FitzGerald GA, Skarke C, "Diurnal rhythms of wrist temperature are associated with
// future disease risk in the UK Biobank", Nat Commun 2023;14:5172 (DOI 10.1038/s41467-023-40977-5;
// peer-reviewed, with an earlier differently-titled medRxiv preprint in 2023). That is a 24 h,
// population-level ASSOCIATION (never causal, never a diagnosis), NOT our nocturnal-only signal — so
// this engine deliberately describes night-to-night CONSISTENCY of the nocturnal warming, not a risk
// score, and the copy never invokes the disease link.
//
// WHAT IT COMPUTES. Given the ordered per-night warming magnitudes, it reuses the shipped `Baselines`
// EWMA to get a robust personal CENTER (typical nightly warming) and SPREAD (the EWMA-of-abs-deviation
// dispersion = the night-to-night stability), then reports a scale-free coefficient of variation and a
// purely DESCRIPTIVE 3-band stability label. The bands are descriptive cutoffs (pinned by test), not
// clinical thresholds.
public enum ThermalStabilityEngine {

    /// Onset → plateau warming (°C) for ONE night's in-bed skin-temp samples (ordered by ts), or
    /// nil with too few (< 60). Onset = mean of the first ~15% of the window (falling asleep),
    /// plateau = mean of the 40–90% window (the settled night) — the distal-warming shape of
    /// Kräuchi & Wirz-Justice (see FER-850 / ANALYTICS). The value is a DIFFERENCE of raw ADC
    /// means (/128 to °C), so any additive raw→°C band calibration cancels exactly.
    /// Moved verbatim from the app layer (FER-972 · P-05) so the nightly pass can persist it
    /// per night and the skin-temp sheet stops re-reading raw samples on open.
    public static func warmingMagnitudeC(inBedRaw samples: [SkinTempSample]) -> Double? {
        let n = samples.count
        guard n >= 60 else { return nil }
        let onsetHi = max(1, n * 15 / 100)
        let plateauLo = n * 40 / 100
        let plateauHi = max(plateauLo + 1, n * 90 / 100)
        func meanRaw(_ r: ArraySlice<SkinTempSample>) -> Double {
            Double(r.reduce(0) { $0 + $1.raw }) / Double(r.count)
        }
        let onset = meanRaw(samples[0..<onsetHi])
        let plateau = meanRaw(samples[plateauLo..<plateauHi])
        return (plateau - onset) / 128.0
    }

    // MARK: - Tuning constants (pinned by test)

    /// Minimum valid nights before a stability read is offered (a week of nights, matching the other
    /// rhythm reads). Below this the label is `.learning`.
    public static let minNightsForStability: Int = 7

    /// The typical nightly warming must be at least this (°C) to form a meaningful coefficient of
    /// variation; below it the ratio is ill-defined (near-zero denominator) and we stay `.learning`.
    public static let minTypicalWarmingC: Double = 0.2

    /// Coefficient-of-variation cutoffs for the DESCRIPTIVE stability band. Not clinical — a
    /// consistency descriptor of the user's own nightly warming. CV = σ / typical. PRODUCT-CALIBRATION,
    /// NOT VALIDATED: these cutoffs (and `warmingCfg.floorSpread` below, which claims to resolve
    /// ~0.1 °C of night-to-night dispersion) are chosen for a sensible descriptor, not validated against
    /// the WHOOP skin-temp sensor's real noise floor. Before this band is ever SHOWN, the floor and
    /// cutoffs must be checked against the strap's actual skin-temp resolution (see FER-681 follow-up).
    public static let consistentMaxCV: Double = 0.20
    public static let variableMinCV: Double = 0.40

    /// Baseline config for the WARMING MAGNITUDE series (°C rise, onset → nocturnal plateau). Distinct
    /// from the absolute `skin_temp` config: a magnitude, not a temperature, so its bounds and floor
    /// differ. Bounds allow a slightly negative night (no warming) without hard-rejecting it; the floor
    /// (0.1 °C) is the finest night-to-night dispersion we'll claim to resolve.
    public static let warmingCfg = MetricCfg(minVal: -2.0, maxVal: 5.0, floorSpread: 0.1,
                                             halfLifeB: 14.0, halfLifeS: 21.0)

    // MARK: - Per-night magnitude

    /// The distal warming magnitude for one night: the rise from the sleep-onset wrist temperature to
    /// the nocturnal plateau, in °C (positive = warmed, the physiological norm). A trivial helper so the
    /// definition lives in one place; callers pass already-worn, in-bed °C values.
    public static func warmingMagnitude(onsetTempC: Double, plateauTempC: Double) -> Double {
        plateauTempC - onsetTempC
    }

    // MARK: - Output

    public enum Stability: String, Equatable, Sendable, Codable {
        case learning     // < minNightsForStability nights, or an ill-defined ratio — no read yet
        case consistent   // CV ≤ consistentMaxCV — your nightly warming is steady night-to-night
        case moderate     // between the two cutoffs
        case variable     // CV ≥ variableMinCV — your nightly warming swings a lot
    }

    public struct Result: Equatable, Sendable {
        /// Valid nights backing the read.
        public let nights: Int
        /// Typical nightly distal warming (°C), the personal EWMA center.
        public let typicalWarmingC: Double
        /// Night-to-night dispersion of the warming (°C), robust σ = 1.253 × EWMA-abs-dev spread.
        public let nightToNightSigmaC: Double
        /// Scale-free consistency: σ / typical (0 when not computable).
        public let coefficientOfVariation: Double
        public let stability: Stability
        /// One-line non-clinical, non-24 h-amplitude copy.
        public let copy: String

        public init(nights: Int, typicalWarmingC: Double, nightToNightSigmaC: Double,
                    coefficientOfVariation: Double, stability: Stability, copy: String) {
            self.nights = nights; self.typicalWarmingC = typicalWarmingC
            self.nightToNightSigmaC = nightToNightSigmaC
            self.coefficientOfVariation = coefficientOfVariation
            self.stability = stability; self.copy = copy
        }
    }

    // MARK: - Evaluate

    /// Assess the nocturnal thermal stability from the ordered per-night warming magnitudes
    /// (oldest → newest). `nil` entries are missing nights (skip-and-hold in the baseline).
    public static func evaluate(magnitudes: [Double?]) -> Result {
        let base = Baselines.foldHistory(magnitudes, cfg: warmingCfg)
        let typical = base.baseline
        let sigma = 1.253 * base.spread
        let nights = base.nValid

        // Cold start, or a near-zero typical that makes the CV ill-defined → learning.
        guard nights >= minNightsForStability, typical >= minTypicalWarmingC else {
            return Result(nights: nights, typicalWarmingC: typical, nightToNightSigmaC: sigma,
                          coefficientOfVariation: 0,
                          stability: .learning,
                          copy: "Still learning how consistent your nightly warming is - keep wearing it to bed.")
        }

        let cv = sigma / typical
        let stability: Stability = cv <= consistentMaxCV ? .consistent
                                 : cv >= variableMinCV ? .variable
                                 : .moderate
        let typicalStr = String(format: "%.1f", typical)
        let copy: String
        switch stability {
        case .consistent:
            copy = "Your body's warming as you fall asleep is consistent night-to-night "
                + "(about \(typicalStr) °C). A steady nightly descent into sleep."
        case .moderate:
            copy = "Your nightly warming into sleep (about \(typicalStr) °C) varies a moderate amount "
                + "night-to-night."
        case .variable:
            copy = "Your nightly warming into sleep swings a fair amount night-to-night. A more "
                + "consistent wind-down routine tends to steady it."
        case .learning:
            copy = ""  // unreachable (handled above)
        }
        return Result(nights: nights, typicalWarmingC: typical, nightToNightSigmaC: sigma,
                      coefficientOfVariation: cv, stability: stability, copy: copy)
    }
}
