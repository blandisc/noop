import Foundation

// VitalityEngine.swift — a transparent 0–100 "Vitality" wellness score + a "Body Age in years".
//
// INDEPENDENT implementation of the published method WHOOP's "Healthspan / WHOOP Age" also uses
// (NOT medical advice; a WELLNESS comparison, never a clinical/biological age): map each wearable-
// measurable input to its published ALL-CAUSE-MORTALITY hazard ratio relative to a population
// reference, sum the log-hazards with an overlap correction (the inputs are correlated, so the naive
// sum overstates), and convert that combined hazard into a "years of aging" offset via the Gompertz
// mortality-rate doubling time (mortality roughly doubles every ~8 years, so 1 doubling of hazard ≈
// 8 years of age). Body Age = chronological age + Δage; an average-for-their-age person nets ~0 and
// reads at their own age. Gated on ≥ `minFactors` inputs, presented with a ±band and a hard
// "wellness trend, not a biological/clinical age" disclaimer.
//
// Differentiation from `FitnessAgeEngine`: Fitness Age is a cardiorespiratory number (Nes/HUNT, RHR +
// activity). Body Age is a WHOLE-BODY composite that adds sleep duration, sleep regularity, HRV and
// steps. They deliberately share RHR/VO₂max signal — the presentation layer (FER-145) keeps the two
// distinct; the overlap *among Vitality's own factors* is handled by the shrink below.
//
// ── NOOP corrections (FER-124) ──────────────────────────────────────────────────────────────────
// An expert review of the upstream coefficients against current primary literature (logged on the
// FER-124 issue) found the model portable but NOT verbatim. Six corrections keep it honest; each is
// documented at its call site and verified by a test:
//
//   1. RESTING-HR DOMAIN [= FER-122]. The upstream reference (65 bpm) is SEATED/clinical RHR; WHOOP
//      reports NOCTURNAL RHR, ~7 bpm lower (Fenland 2023, PMC10174582: seated 64.5–67.6 vs sleep
//      55.2–56.9). Against a seated 65, every user reads younger. Fix: re-anchor to the nocturnal
//      domain by REUSING `FitnessAgeEngine.restingHRReference` (58) — one constant shared between the
//      two engines so they never drift. Slope kept (≈+10%/10 bpm — Zhang 2016 RR 1.09; Aune 2017 1.17,
//      the conservative floor). A lower clamp avoids unbounded credit for athletic nocturnal RHR.
//
//   2. SLEEP DURATION — asymmetric. The upstream 0.110/h is SYMMETRIC, but the mortality U-curve is
//      not: short sleep ≈0.058 ln-HR/h (RR 1.06), long ≈0.122 (RR 1.13) — Yin 2017 (PMID 28889101);
//      Cappuccio 2010 (PMID 20469800) puts long ≈2.5× short. A single 0.110 over-penalizes SHORT
//      sleep (the dominant case). Fix: anchor the optimum at 7.0 h (±0.5 neutral) and split the arms —
//      0.060 short / 0.120 long.
//
//   3. OVERLAP SHRINK — input-count-dependent. The factors are correlated (Jayedi 2022: steps lose
//      ~35% of their effect when adjusted for intensity/fitness), so a naive log-hazard sum double-
//      counts. The upstream FIXED 0.75 also unfairly penalizes a user with FEW signals (e.g. steps
//      only, no strap — nothing to de-overlap, yet still cut 25%). Fix: derive the shrink from how
//      many factors are present — `1/(1 + 0.35·(n−1))` → n=1: 1.0, n=2: 0.74, n=3: 0.59, n=4: 0.49.
//
//   4. HRV — attenuated + honest. The per-factor HR comes from SHORT-TERM CLINICAL ECG (Jarczok 2022;
//      Hillebrand 2013; Dekker/ARIC 2000), NOT nocturnal PPG; and the age-norm table is daytime-
//      calibrated, so nocturnal RMSSD (≈20–40% higher) reads at/above norm and the factor is already
//      conservative. Fix: attenuate the weight (0.160 → 0.110) for domain uncertainty, use the LOG
//      form `ln(norm/rmssd)` (aligns with Hillebrand's log-linear "+1% RMSSD ≈ −1% risk") instead of
//      the old fraction-of-mean, and require adequate nocturnal coverage upstream (orchestration,
//      FER-145). No mortality HR has ever been validated for nocturnal-PPG RMSSD — a soft, capped input.
//
//   5. SLEEP REGULARITY — reference. Slope kept (0.450; Windred 2024, Sleep 47(1):zsad253, SRI p5-vs-median
//      HR 1.53 — regularity predicts mortality MORE strongly than duration). But the upstream ref 0.75
//      is the ~p95, not the population median: on an SRI/100 scale the typical value is ≈0.60. Fix:
//      ref 0.75 → 0.60 so the average user is neutral. NOTE: `sleepConsistency(nightlyHours:)` below
//      (1 − CV of durations) is an INTERIM proxy, not the real Sleep Regularity Index the HR is drawn
//      from — the orchestrator passes a real SRI/100 (FER-145, done; CV proxy is the cold-start fallback).
//
//   6. STEPS — age-aware threshold. The benefit plateau is age-dependent (Paluch 2022, PMC9289978:
//      ≥60 yr 6–8k, <60 yr 8–10k); a fixed 7,000 under-penalizes younger users. Fix: reference
//      `age ≥ 60 ? 7000 : 8500`. Per-1,000 weight (0.064) and the 11k cap are kept — conservative vs
//      Jayedi 2022 (HR 0.88/1,000 ≈ 0.128 crude).
//
// Kept VERBATIM (well-centered; documented, not changed):
//   • VO₂max: 0.130/MET below the age/sex-expected value (HR 0.878 — Kodama 2009 RR 0.87; Singh 2025
//     RR 0.86, 0.83–0.88; estimated ≈ measured). Fitter than expected is protective.
//   • Gompertz MRDT 8 yr (ln2/8): within the human range b = 0.07–0.09 (MRDT 7.7–9.9; Gavrilov);
//     a global ±~15% scale on the whole "years" output.
//
// Per-factor hazard ratios are deliberately CONSERVATIVE and clamped — a wellness estimate, not a
// diagnosis. Per-factor sources are cited at each call site in `contributions`.
public enum VitalityEngine {

    // Gompertz: mortality-rate doubling time ≈ 8 years → ln(hazard) per year of age = ln(2)/8. Within
    // the published human range (rate-of-aging b ≈ 0.07–0.09 ⇒ MRDT 7.7–9.9; Gavrilov); a global ±~15%
    // scale on the whole "years" output. Kept verbatim from upstream.
    static let lnHazardPerYear = 0.6931471805599453 / 8.0   // ≈ 0.0866
    /// Mean correlation among the factors' log-hazards, used to derive the overlap shrink (correction
    /// #3). ≈0.35 matches the ~35% attenuation of the step effect once adjusted for intensity/fitness
    /// (Jayedi 2022) — these signals are moderately, not fully, redundant.
    static let overlapRho = 0.35
    /// Body Age is clamped to a sane band; Vitality maps Δage linearly around 50 (= "at your age").
    static let minBodyAge = 20.0, maxBodyAge = 90.0
    static let vitalityPerYear = 2.5   // each year younger than your age = +2.5 Vitality points

    /// The wearable inputs Vitality reads. All optional — the score uses whatever is present (≥ minFactors).
    public struct Inputs: Equatable, Sendable {
        public var chronoAge: Double
        public var restingHR: Double?          // bpm, NOCTURNAL (WHOOP domain — see correction #1)
        public var vo2max: Double?             // ml/kg/min (e.g. from FitnessAgeEngine)
        public var expectedVO2max: Double?     // age/sex-expected ml/kg/min (the reference for vo2max)
        public var sleepHours: Double?         // mean nightly sleep
        public var sleepConsistency: Double?   // 0–1 regularity (1 = perfectly regular); a real SRI/100
        public var rmssd: Double?              // ms, nocturnal HRV
        public var rmssdNorm: Double?          // age/sex-normative RMSSD (the reference)
        public var steps: Double?              // mean daily steps
        public init(chronoAge: Double, restingHR: Double? = nil, vo2max: Double? = nil,
                    expectedVO2max: Double? = nil, sleepHours: Double? = nil,
                    sleepConsistency: Double? = nil, rmssd: Double? = nil,
                    rmssdNorm: Double? = nil, steps: Double? = nil) {
            self.chronoAge = chronoAge; self.restingHR = restingHR; self.vo2max = vo2max
            self.expectedVO2max = expectedVO2max; self.sleepHours = sleepHours
            self.sleepConsistency = sleepConsistency; self.rmssd = rmssd
            self.rmssdNorm = rmssdNorm; self.steps = steps
        }
    }

    /// One factor's contribution: its label and signed log-hazard vs the population reference
    /// (positive = ages you, negative = protective).
    public struct Contribution: Equatable, Sendable {
        public let key: String
        public let label: String
        public let lnHazard: Double
        public init(key: String, label: String, lnHazard: Double) {
            self.key = key; self.label = label; self.lnHazard = lnHazard
        }
        /// This factor's contribution expressed in YEARS (positive ages you, negative rejuvenates) — the
        /// unshrunk per-factor view for the "what's driving this" breakdown. The displayed Body Age
        /// applies the overlap shrink to the SUM, so these need not add up to the exact delta.
        public var years: Double { lnHazard / VitalityEngine.lnHazardPerYear }
    }

    public struct Result: Equatable, Sendable {
        public let vitality: Double        // 0–100 (50 = typical for your age)
        public let bodyAge: Double         // years, clamped
        public let chronoAge: Double
        public let deltaYears: Double      // chronoAge − bodyAge (positive = younger than your age)
        public let bandYears: Double
        public let contributions: [Contribution]   // for the "what's driving this" breakdown
        public let factorsUsed: Int
        public init(vitality: Double, bodyAge: Double, chronoAge: Double, deltaYears: Double,
                    bandYears: Double, contributions: [Contribution], factorsUsed: Int) {
            self.vitality = vitality; self.bodyAge = bodyAge; self.chronoAge = chronoAge
            self.deltaYears = deltaYears; self.bandYears = bandYears
            self.contributions = contributions; self.factorsUsed = factorsUsed
        }
    }

    /// Minimum distinct factors before we'll show a number (honesty gate).
    public static let minFactors = 3
    public static let bandYears = 5.0

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    /// Correction #3: overlap shrink derived from how many factors are present. With correlated factors
    /// (mean ρ ≈ `overlapRho`) the naive log-hazard sum over-counts shared signal; `1/(1+ρ·(n−1))`
    /// deflates it — and reduces to 1.0 (no shrink) when only one signal is present, so a user with few
    /// inputs isn't unfairly cut the way the upstream fixed 0.75 did.
    public static func overlapShrink(forFactors n: Int) -> Double {
        guard n > 1 else { return 1.0 }
        return 1.0 / (1.0 + overlapRho * Double(n - 1))
    }

    /// Nocturnal RMSSD ~50th-percentile by age (ms), piecewise-linear between decade anchors. NOTE
    /// (correction #4): these anchors track published SHORT-TERM / daytime RMSSD norms (Umetani 1998;
    /// Kubios/Welltory); true nocturnal RMSSD runs ≈20–40% higher, so scoring nocturnal RMSSD against
    /// this table is deliberately conservative (most users read at/above norm). The reference for the
    /// HRV factor: a person at the age norm contributes 0.
    public static func rmssdNorm(forAge age: Double) -> Double {
        let anchors: [(Double, Double)] = [(20, 47), (30, 40), (40, 33), (50, 29), (60, 25), (70, 22), (80, 20)]
        if age <= anchors[0].0 { return anchors[0].1 }
        if age >= anchors[anchors.count - 1].0 { return anchors[anchors.count - 1].1 }
        for i in 1..<anchors.count where age <= anchors[i].0 {
            let (a0, v0) = anchors[i - 1]; let (a1, v1) = anchors[i]
            return v0 + (v1 - v0) * (age - a0) / (a1 - a0)
        }
        return anchors[anchors.count - 1].1
    }

    /// INTERIM proxy for sleep regularity (0–1) from a window of nightly sleep durations (hours):
    /// 1 − coefficient of variation, clamped. This is NOT the Sleep Regularity Index the regularity
    /// hazard ratio is drawn from (correction #5) — it only sees durations, not timing — so the
    /// orchestrator should prefer a real SRI/100 when available (FER-145). Fewer than 3 nights → nil.
    public static func sleepConsistency(nightlyHours: [Double]) -> Double? {
        let xs = nightlyHours.filter { $0 > 0 }
        guard xs.count >= 3 else { return nil }
        let mean = xs.reduce(0, +) / Double(xs.count)
        guard mean > 0 else { return nil }
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
        let cv = variance.squareRoot() / mean
        return clamp(1 - cv, 0, 1)
    }

    /// Compute the per-factor log-hazard contributions present in `inputs`. Each references a population
    /// value, so an average person nets ~0. Published per-unit hazard ratios (conservative, clamped) —
    /// see the file header (corrections #1, #2, #4, #5, #6) for the per-factor sources.
    public static func contributions(_ inputs: Inputs) -> [Contribution] {
        var out: [Contribution] = []
        if let rhr = inputs.restingHR {
            // Correction #1: reference re-anchored to the nocturnal domain by reusing FitnessAge's
            // constant (one shared anchor). Slope ≈ +10%/10 bpm (Zhang 2016 / Aune 2017, conservative
            // floor); lower clamp caps the credit for athletic nocturnal RHR where the linear model
            // would over-reward (the mortality benefit flattens at very low RHR).
            let perDecade = clamp((rhr - FitnessAgeEngine.restingHRReference) / 10, -1.5, 4)
            out.append(Contribution(key: "rhr", label: "Resting heart rate",
                                    lnHazard: perDecade * 0.100))
        }
        if let vo2 = inputs.vo2max, let exp = inputs.expectedVO2max, exp > 0 {
            // Verbatim: ~13% per MET (3.5 ml/kg/min) below the age/sex-expected value (Kodama 2009 /
            // Singh 2025). Fitter than expected → negative → protective.
            out.append(Contribution(key: "vo2max", label: "Cardio fitness",
                                    lnHazard: clamp((exp - vo2) / 3.5, -4, 4) * 0.130))
        }
        if let sh = inputs.sleepHours {
            // Correction #2: optimum 7.0 h (±0.5 neutral), asymmetric arms — short 0.060 / long 0.120
            // (Yin 2017; Cappuccio 2010). The old symmetric 0.110 over-penalized short sleep.
            let dev = max(0, abs(sh - 7.0) - 0.5)
            let slope = sh < 7.0 ? 0.060 : 0.120
            out.append(Contribution(key: "sleep", label: "Sleep duration",
                                    lnHazard: clamp(dev, 0, 3) * slope))
        }
        if let c = inputs.sleepConsistency {
            // Correction #5: slope kept (Windred 2024 SRI); reference 0.75 → 0.60 (the population median
            // on an SRI/100 scale, not the p95). Less regular than the median ages you.
            out.append(Contribution(key: "consistency", label: "Sleep regularity",
                                    lnHazard: (0.60 - clamp(c, 0, 1)) * 0.450))
        }
        if let h = inputs.rmssd, h > 0, let norm = inputs.rmssdNorm, norm > 0 {
            // Correction #4: attenuated (0.160 → 0.110) for ECG→nocturnal-PPG domain uncertainty, in log
            // form (Hillebrand 2013 log-linear) instead of fraction-of-mean. Lower HRV than the age norm
            // ages you; clamped to ±~2× ratio.
            out.append(Contribution(key: "hrv", label: "Heart-rate variability",
                                    lnHazard: clamp(log(norm / h), -0.7, 0.7) * 0.110))
        }
        if let s = inputs.steps {
            // Correction #6: age-aware reference (Paluch 2022 — <60 yr plateau ~8–10k, ≥60 yr ~6–8k).
            // Per-1,000 weight 0.064 and the 11k protection cap kept (conservative vs Jayedi 2022).
            let stepReference = inputs.chronoAge >= 60 ? 7000.0 : 8500.0
            let deficit = (stepReference - clamp(s, 0, 11000)) / 1000
            out.append(Contribution(key: "steps", label: "Daily steps",
                                    lnHazard: clamp(deficit, -4, 4) * 0.064))
        }
        return out
    }

    /// Full Vitality + Body Age. Returns nil until at least `minFactors` inputs are present.
    public static func compute(_ inputs: Inputs) -> Result? {
        guard inputs.chronoAge > 0 else { return nil }
        let contribs = contributions(inputs)
        guard contribs.count >= minFactors else { return nil }
        let shrink = overlapShrink(forFactors: contribs.count)   // correction #3
        let sumLn = contribs.reduce(0) { $0 + $1.lnHazard } * shrink
        let deltaAge = sumLn / lnHazardPerYear              // +ve = ages you
        let bodyAge = clamp(inputs.chronoAge + deltaAge, minBodyAge, maxBodyAge)
        let delta = inputs.chronoAge - bodyAge              // +ve = younger than your age
        let vitality = clamp(50 + delta * vitalityPerYear, 0, 100)
        return Result(vitality: vitality, bodyAge: bodyAge, chronoAge: inputs.chronoAge,
                      deltaYears: delta, bandYears: bandYears, contributions: contribs,
                      factorsUsed: contribs.count)
    }
}
