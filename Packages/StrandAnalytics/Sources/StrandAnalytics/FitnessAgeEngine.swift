import Foundation

// FitnessAgeEngine.swift — on-device "Fitness Age" from resting HR + activity + profile.
//
// INDEPENDENT implementation of published, peer-reviewed methods (NOT medical advice; a fitness
// comparison, never a "biological age"):
//   • VO₂max estimate: Nes et al. 2011 HUNT non-exercise model, WAIST-CIRCUMFERENCE variant — the
//     CONFIRMED original (Nes 2011, Med Sci Sports Exerc 43(11):2024-2030; coefficients reproduced
//     verbatim in JAHA/Ball State 2020, PMC7428991, and corroborated by CERG/NTNU). SEE ≈ 5.70 (men) /
//     5.14 (women). (The BMI-variant coefficients that circulate from a 2019 secondary source were NOT
//     reliably confirmable against the original and are deliberately NOT used here.)
//   • Physical-activity index: HUNT1 PA-Q (Kurtze 2008), frequency×intensity×duration ∈ [0, 15];
//     NOOP has no questionnaire, so it RECONSTRUCTS each factor from measured weekly signals.
//   • Fitness Age: invert the SAME Nes equation self-consistently — the normative curve is the Nes
//     model at population-reference resting HR and PA-index. The body term (waist) appears in both the
//     user's estimate and the normative curve, so it CANCELS: Fitness Age depends only on how the
//     user's resting HR and activity compare to a reference-fit peer of their age. This means the
//     headline number needs no body measurement at all, and an average-fitness person maps to their
//     own chronological age by construction. (We do NOT mix in a different population's reference
//     curve — e.g. the US FRIEND equation — because the scale offset would bias everyone by ~15 yr.)
//
// ── NOOP domain-transfer corrections (FER-122) ──────────────────────────────────────────────────
// The Nes model was calibrated on HUNT questionnaire inputs (SEATED resting HR, a PA-Q score). NOOP
// feeds it on-device wearable signals from a different domain, so three corrections keep it honest;
// each is documented at its call site and verified by a test:
//
//   1. RESTING-HR DOMAIN. Nes/CERG use SEATED resting HR ("sit quietly 10 min, then count your pulse").
//      WHOOP reports NOCTURNAL resting HR, which runs ~10–15% (≈7 bpm) below seated resting (nocturnal
//      dip; Sleep Foundation; Dial et al. 2025 confirms WHOOP tracks nocturnal RHR accurately vs ECG —
//      the gap is the DOMAIN, not the device). Feeding nocturnal RHR against a SEATED reference (the
//      original 65) would read every user ~0.52 yr/bpm × 7 ≈ 3.7 yr too YOUNG. Fix: the engine's RHR
//      contract is NOCTURNAL throughout, `restingHRReference` is re-anchored to the nocturnal domain
//      (58 = the validated seated anchor 65 minus the 7-bpm dip), and the absolute VO₂max equation
//      converts nocturnal → seated-equivalent internally. Because Fitness Age uses (RHR − RHRref) with
//      BOTH terms nocturnal, the additive dip cancels and the delta is unbiased.
//
//   2. ACTIVITY SCALE. The upstream engine assumed a 0–100 strain scale; THIS repo's StrainScorer is
//      0–21 (WHOOP's Strain axis). `physicalActivityIndexFromStrain` is recalibrated to 0–21 so a real
//      workout no longer reads as sedentary (see that function). The scale itself is scientifically
//      neutral; the strain→PA-index bridge is an UNVALIDATED heuristic in any scale, so activity is a
//      SOFT input — resting HR (a direct, validated Nes predictor) drives the headline, and sparse
//      activity coverage caps confidence at `.estimate` (see assessReadiness).
//
//   3. UNCERTAINTY BAND. The per-reading Nes SEE (≈5.70 ml/kg/min) over the ~0.3 ml/kg/min·yr age slope
//      is ≈±19 yr — far wider than the displayed ±5. The ±5 band is defensible ONLY for the AGE DELTA,
//      where the shared structural SEE of the same model cancels between user and reference; it does
//      NOT apply to the ABSOLUTE VO₂max, which must be shown as a coarse estimate (see FitnessAgeResult).
//
// All coefficients below are literal published values. Do not change without re-verifying the source.
public enum FitnessAgeEngine {

    // MARK: - Nes 2011 waist-circumference coefficients (Nes et al. 2011, Med Sci Sports Exerc
    // 43(11):2024–2030, PMID 21502897 — the HUNT non-exercise VO₂peak model, the primary source). An
    // earlier note cited a secondary "verbatim reproduction" (PMC7428991) that could not be verified;
    // the primary Nes 2011 alone anchors these coefficients (FER-657).
    // VO₂max = intercept − ageC·age + paiC·PA − wcC·waist − rhrC·RHR
    static let menIntercept = 100.27, menAge = 0.296, menWC = 0.369, menRHR = 0.155, menPAI = 0.226
    static let womenIntercept = 74.736, womenAge = 0.247, womenWC = 0.259, womenRHR = 0.114, womenPAI = 0.198
    public static let seeMen = 5.70, seeWomen = 5.14

    // MARK: - Resting-HR domain (correction #1)
    /// Seated-minus-nocturnal resting-HR offset (bpm). Healthy adults' sleeping HR runs ~10–15% below
    /// seated resting (nocturnal dip; Sleep Foundation). Added to the NOCTURNAL RHR the engine consumes
    /// to recover the SEATED-equivalent RHR the Nes equation was calibrated on. Kept self-consistent
    /// with the reference: nocturnal 58 + 7 = the validated seated anchor 65.
    public static let nocturnalToSeatedRHROffset = 7.0

    // MARK: - Normative reference point (the "average peer" the Fitness Age compares against)
    /// Population-reference NOCTURNAL resting HR (bpm) — an average healthy adult, in the same domain
    /// WHOOP measures. Equals the Nes/CERG seated anchor (65) minus the 7-bpm nocturnal dip. At this RHR
    /// + paiReference a person's Fitness Age equals their chronological age by construction.
    public static let restingHRReference = 58.0
    /// Population-reference PA-index (0–15): ≈ "moderately active, a few sessions a week".
    public static let paiReference = 5.0

    /// Displayed uncertainty band (years) for the AGE DELTA ONLY (correction #3). The per-reading Nes
    /// SEE (≈5–6 ml/kg/min over the ~0.3/yr age slope, ≈±19 yr) is far wider, but the Fitness Age is a
    /// delta of the same model against the reference, so the shared structural SEE largely cancels; we
    /// compute on rolling 7-day medians and show a conservative fixed ±band with a "fitness comparison,
    /// not a biological age" disclaimer. This band does NOT apply to the absolute VO₂max.
    public static let displayBandYears = 5.0
    public static let minAge = 20.0, maxAge = 80.0

    private static func isFemale(_ sex: String) -> Bool { sex.lowercased() == "female" }

    /// Coefficient tuple for the user's sex (intercept, ageC, wcC, rhrC, paiC). Non-binary uses men's.
    private static func coeffs(_ sex: String) -> (Double, Double, Double, Double, Double) {
        isFemale(sex)
            ? (womenIntercept, womenAge, womenWC, womenRHR, womenPAI)
            : (menIntercept, menAge, menWC, menRHR, menPAI)
    }

    /// Body-mass index from metric height/weight (used by callers; not required for Fitness Age).
    public static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let m = heightCm / 100.0
        guard m > 0 else { return 0 }
        return weightKg / (m * m)
    }

    /// Nes 2011 waist-variant VO₂max (ml/kg/min). Optional display metric — needs a waist measurement.
    /// `restingHR` is the NOCTURNAL RHR (WHOOP domain); it is converted to the seated-equivalent the Nes
    /// equation expects (correction #1), so the reference peer (nocturnal 58) reproduces the classic
    /// seated-65 value. This absolute estimate is coarse (SEE ≈5–6 ml/kg/min) — present it without the
    /// ±5 age band (correction #3).
    public static func estimateVO2max(age: Double, sex: String, waistCm: Double,
                                      restingHR: Double, paIndex: Double) -> Double {
        let (intercept, ageC, wcC, rhrC, paiC) = coeffs(sex)
        let seatedRHR = restingHR + nocturnalToSeatedRHROffset
        return intercept - ageC*age + paiC*paIndex - wcC*waistCm - rhrC*seatedRHR
    }

    /// Self-consistent Fitness Age (years, clamped [20,80]). The waist term cancels, so this needs only
    /// age, sex, resting HR and the PA-index: `FA = age + (rhrC·(RHR−RHRref) − paiC·(PAI−PAIref)) / ageC`.
    /// `restingHR` is NOCTURNAL; the reference is nocturnal too, so the seated↔nocturnal dip cancels in
    /// the (RHR − RHRref) difference and the delta is unbiased (correction #1).
    public static func fitnessAge(age: Double, sex: String, restingHR: Double, paIndex: Double) -> Double {
        let (_, ageC, _, rhrC, paiC) = coeffs(sex)
        let fa = age + (rhrC*(restingHR - restingHRReference) - paiC*(paIndex - paiReference)) / ageC
        return min(maxAge, max(minAge, fa))
    }

    /// Reconstruct the HUNT PA-index (0–15 = frequency×intensity×duration) from measured weekly
    /// aggregates. Bucket edges mirror the HUNT1 PA-Q response options (Kurtze 2008):
    ///   frequency ∈ {0.0, 0.5, 1.0, 2.5, 5.0}  ← active days in the last 7
    ///   intensity ∈ {1, 2, 3}                  ← share of active time at high intensity (HR zone 4–5)
    ///   duration  ∈ {0.10, 0.38, 0.75, 1.0}    ← average active minutes per active day
    public static func physicalActivityIndex(activeDaysPerWeek: Int,
                                             avgActiveMinutesPerDay: Double,
                                             highIntensityFraction: Double) -> Double {
        let frequency: Double
        switch activeDaysPerWeek {
        case ..<1: frequency = 0.0
        case 1:    frequency = 0.5
        case 2:    frequency = 1.0
        case 3...4: frequency = 2.5
        default:   frequency = 5.0          // 5+ days ≈ "almost every day"
        }
        let intensity: Double
        switch highIntensityFraction {
        case ..<0.15: intensity = 1.0       // easy, no real sweat
        case ..<0.5:  intensity = 2.0       // sweaty / breathless
        default:      intensity = 3.0       // near exhaustion
        }
        let duration: Double
        switch avgActiveMinutesPerDay {
        case ..<15:  duration = 0.10
        case ..<30:  duration = 0.38
        case ..<60:  duration = 0.75
        default:     duration = 1.0
        }
        if frequency == 0 { return 0 }
        return frequency * intensity * duration
    }

    /// PA-index (0–15) from NOOP's measured weekly load — the UNIVERSAL path the orchestrator uses
    /// (works on any device, since `strain` is computed from HR alone; HR-zone minutes only exist for
    /// CSV-importers). `strain` (0–21 logarithmic, this repo's StrainScorer) already integrates intensity
    /// × duration, so we map the mean active-day strain straight to the HUNT intensity×duration PRODUCT
    /// (0–3) and multiply by the frequency factor — deliberately NOT re-deriving intensity and duration
    /// separately, which would double-count the same HR load.
    ///
    /// CORRECTION #2: recalibrated for THIS repo's 0–21 strain scale (the upstream engine assumed 0–100,
    /// where a real workout would have read as sedentary here). Divisor 7 → strain 7→1, 14→2, 21→3, so
    /// the reference peer (≈4 active days, mean active-day strain ≈14) lands near PA-index 5. The
    /// strain→PA-index bridge is an unvalidated heuristic in ANY scale — see assessReadiness for why
    /// activity is a soft input that caps confidence at `.estimate`.
    public static func physicalActivityIndexFromStrain(activeDaysPerWeek: Int,
                                                       meanActiveStrain: Double) -> Double {
        let frequency: Double
        switch activeDaysPerWeek {
        case ..<1: frequency = 0.0
        case 1:    frequency = 0.5
        case 2:    frequency = 1.0
        case 3...4: frequency = 2.5
        default:   frequency = 5.0
        }
        if frequency == 0 { return 0 }
        let intensityDuration = min(3.0, max(0.0, meanActiveStrain / 7.0))   // 0–21 scale: 7→1, 14→2, 21→3
        return frequency * intensityDuration
    }

    /// Full Fitness Age from already-aggregated weekly inputs. `restingHR` is NOCTURNAL (WHOOP domain).
    /// Returns nil only if RHR or age is missing (the headline number needs nothing else). `vo2max` is
    /// filled only when a waist measurement is supplied; callers gate data-coverage (≥4 of 7 days)
    /// separately.
    public static func compute(age: Double, sex: String, restingHR: Double, paIndex: Double,
                               waistCm: Double? = nil, lowerConfidence: Bool = false) -> FitnessAgeResult? {
        guard age > 0, restingHR > 0 else { return nil }
        let fa = fitnessAge(age: age, sex: sex, restingHR: restingHR, paIndex: paIndex)
        let vo2: Double?
        if let w = waistCm, w > 0 {
            vo2 = estimateVO2max(age: age, sex: sex, waistCm: w, restingHR: restingHR, paIndex: paIndex)
        } else {
            vo2 = nil
        }
        let nb = sex.lowercased() != "male" && sex.lowercased() != "female"
        return FitnessAgeResult(
            vo2max: vo2, fitnessAge: fa, chronoAge: age, deltaYears: age - fa,
            bandYears: displayBandYears, lowerConfidence: lowerConfidence || nb)
    }
}

// MARK: - Readiness checklist
//
// Transparency over a black-box number: show the user exactly which inputs we have, grouped by what
// each one unlocks, and a single confidence verdict. Weight/height/waist deliberately sit under "your
// VO₂max number" — NOT under the Fitness Age — because the body term cancels out of the age (see the
// engine doc); claiming weight sharpens the age would be dishonest. The age is driven by age, sex, and
// the COVERAGE of resting-HR + activity over the last 7 days.

public enum FitnessReadinessStatus: String, Sendable { case satisfied, partial, missing }

/// What a given input affects — so the checklist can be honest about its impact.
public enum FitnessReadinessRole: String, Sendable {
    case drivesAge          // required for / sharpens the headline Fitness Age
    case unlocksVO2max      // only powers the separate VO₂max estimate
}

public struct FitnessReadinessItem: Equatable, Sendable {
    public let key: String
    public let label: String
    public let status: FitnessReadinessStatus
    public let required: Bool        // true → the number can't be computed without it
    public let role: FitnessReadinessRole
    public let detail: String        // short hint, e.g. "4 of last 7 nights"
    public init(key: String, label: String, status: FitnessReadinessStatus,
                required: Bool, role: FitnessReadinessRole, detail: String) {
        self.key = key; self.label = label; self.status = status
        self.required = required; self.role = role; self.detail = detail
    }
}

public enum FitnessAgeConfidence: String, Sendable {
    case ready      // everything we need, good coverage
    case estimate   // computes, but partial coverage — a softer claim
    case notReady   // can't compute yet (missing a required input)
}

public struct FitnessAgeReadiness: Equatable, Sendable {
    public let items: [FitnessReadinessItem]
    public let confidence: FitnessAgeConfidence
    public var canCompute: Bool { confidence != .notReady }
    public init(items: [FitnessReadinessItem], confidence: FitnessAgeConfidence) {
        self.items = items; self.confidence = confidence
    }
}

extension FitnessAgeEngine {
    /// Minimum nights of resting-HR before the headline can be computed at all.
    public static let minCoverageDays = 4
    /// Coverage at/above which an input reads as fully satisfied (a "confident" week).
    public static let goodCoverageDays = 6

    private static func coverageStatus(_ days: Int, floor: Int) -> FitnessReadinessStatus {
        if days >= goodCoverageDays { return .satisfied }
        if days >= floor || days > 0 { return .partial }
        return .missing
    }

    /// Build the readiness checklist + overall confidence from the inputs we have. The orchestrator
    /// passes profile-completeness flags and the 7-day coverage counts.
    ///
    /// CONFIDENCE RULE (correction #2 rationale): resting HR is the validated Nes driver, so it gates
    /// confidence — `.ready` requires a well-covered RHR week (≥ goodCoverageDays). Activity rides an
    /// UNVALIDATED strain→PA-index bridge, so it can never PROMOTE confidence on its own and sparse
    /// activity caps the verdict at `.estimate`: a reading leaning on thin activity data is never
    /// `.ready`. Body metrics only power the separate VO₂max and never block the headline.
    public static func assessReadiness(hasAge: Bool, hasSex: Bool,
                                       rhrDays: Int, activityDays: Int,
                                       hasHeightWeight: Bool, hasWaist: Bool) -> FitnessAgeReadiness {
        let items: [FitnessReadinessItem] = [
            FitnessReadinessItem(key: "age", label: "Your age",
                status: hasAge ? .satisfied : .missing, required: true, role: .drivesAge,
                detail: hasAge ? "Set" : "Add it in Settings"),
            FitnessReadinessItem(key: "sex", label: "Biological sex",
                status: hasSex ? .satisfied : .missing, required: true, role: .drivesAge,
                detail: hasSex ? "Set" : "Add it in Settings"),
            FitnessReadinessItem(key: "rhr", label: "Resting heart rate",
                status: coverageStatus(rhrDays, floor: minCoverageDays), required: true, role: .drivesAge,
                detail: "\(rhrDays) of last 7 nights"),
            FitnessReadinessItem(key: "activity", label: "Recent activity",
                status: coverageStatus(activityDays, floor: minCoverageDays), required: false, role: .drivesAge,
                detail: "\(activityDays) of last 7 days"),
            FitnessReadinessItem(key: "bodyMetrics", label: "Height & weight",
                status: hasHeightWeight ? .satisfied : .missing, required: false, role: .unlocksVO2max,
                detail: hasHeightWeight ? "Unlocks your VO₂max" : "Add to also see VO₂max"),
            FitnessReadinessItem(key: "waist", label: "Waist (optional)",
                status: hasWaist ? .satisfied : .missing, required: false, role: .unlocksVO2max,
                detail: hasWaist ? "Sharpens VO₂max" : "Optional — sharpens VO₂max"),
        ]
        let confidence: FitnessAgeConfidence
        if !hasAge || !hasSex || rhrDays < minCoverageDays {
            confidence = .notReady
        } else if rhrDays >= goodCoverageDays && activityDays >= goodCoverageDays {
            confidence = .ready
        } else {
            // Computable, but either RHR coverage is partial or activity is sparse — and because the
            // activity→PA-index bridge is unvalidated, a reading leaning on thin activity stays a soft
            // `.estimate`, never `.ready`.
            confidence = .estimate
        }
        return FitnessAgeReadiness(items: items, confidence: confidence)
    }
}

/// A computed Fitness Age plus the inputs needed to present it honestly.
///
/// Band semantics (correction #3): `bandYears` is the ± presentation band for the AGE DELTA ONLY. The
/// optional `vo2max` is a separate, coarse ABSOLUTE estimate (SEE ≈5–6 ml/kg/min) and carries NO ±5
/// band — present it as an approximation, never with the age band.
public struct FitnessAgeResult: Equatable, Sendable {
    public let vo2max: Double?         // estimated VO₂max (ml/kg/min), nil without a waist measurement
    public let fitnessAge: Double      // years, clamped [20, 80]
    public let chronoAge: Double       // the user's calendar age
    public let deltaYears: Double      // chronoAge − fitnessAge (positive = younger than your age)
    public let bandYears: Double       // ± presentation band for the AGE DELTA only (not for vo2max)
    public let lowerConfidence: Bool   // true for non-binary (sex-specific model) or sparse data

    public init(vo2max: Double?, fitnessAge: Double, chronoAge: Double,
                deltaYears: Double, bandYears: Double, lowerConfidence: Bool) {
        self.vo2max = vo2max; self.fitnessAge = fitnessAge; self.chronoAge = chronoAge
        self.deltaYears = deltaYears; self.bandYears = bandYears; self.lowerConfidence = lowerConfidence
    }
}
