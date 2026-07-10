import Foundation
import WhoopProtocol

// DFAAlpha1.swift — the short-scale detrended-fluctuation-analysis exponent (α1) of the R-R series, as
// an EXPERIMENTAL proxy for the aerobic/anaerobic thresholds. Pure, deterministic, DB-free. The riskier
// half of FER-683 — gated hard behind an experimental flag AND a signal-quality check.
//
// METHOD (Peng et al., "Mosaic organization of DNA nucleotides", Phys Rev E 1994;49:1685 — the origin
// of DFA). Over the R-R interval series:
//   1. integrate the mean-removed series into a profile,
//   2. for each short box size n (beats), split the profile into non-overlapping boxes, least-squares
//      detrend each box, and take the RMS of the residuals → F(n),
//   3. α1 = slope of log F(n) vs log n over the SHORT scales n ∈ [4, 16] beats.
// As exercise intensity rises, α1 falls from ~1.0 (correlated, easy) toward ~0.5 (uncorrelated) and
// below. The intensity landmarks used as a PROXY: α1 ≈ 0.75 ↔ the first ventilatory/aerobic threshold
// (VT1), α1 ≈ 0.5 ↔ the second/anaerobic threshold (VT2). The VT1 landmark is from Rogers B, Giles D,
// Draper N, Hoos O, Gronwald T, "A New Detection Method Defining the Aerobic Threshold… Based on
// Fractal Correlation Properties of Heart Rate Variability", Front Physiol 2021;11:596567 (DOI
// 10.3389/fphys.2020.596567); the α1 ≈ 0.5 ↔ VT2 landmark is from the same group's anaerobic-threshold
// work. Presented strictly as a DESCRIPTIVE proxy, never a measured threshold or a prescription.
//
// HONESTY — WHY THIS IS EXPERIMENTAL (the load-bearing caveat). DFA-α1 was validated against ECG R-R at
// ~1000 Hz. α1 is EXQUISITELY sensitive to R-R artifacts, and wrist PPG DURING MOTION — exactly the
// exercising window where α1 matters — loses beat-to-beat accuracy and injects artifacts, so a
// PPG-derived α1 can read a FALSE threshold. The PPG↔ECG equivalence is explicitly UNRESOLVED in the
// literature. Therefore this engine:
//   • is inert unless the caller passes `experimentalEnabled = true`,
//   • refuses to output α1 unless the cleaned R-R series clears a strict artifact gate (ideally the
//     input is a chest-strap / arm R-R stream, not wrist PPG),
//   • always carries a visible `caveat` that it is experimental and not an ECG-grade measurement.
// It never claims a VO2max, a fitness verdict, or a medical threshold.
public enum DFAAlpha1 {

    // MARK: - Tuning constants (pinned by test)

    /// Short-scale box sizes (beats) for α1. The canonical DFA-α1 window (Peng; used by Rogers/Gronwald).
    public static let scaleMin: Int = 4
    public static let scaleMax: Int = 16

    /// Minimum CLEAN beats before α1 is computed. Rogers/Gronwald use ~2-minute R-R windows; at ~1 beat/s
    /// that is ~120 beats, enough for a stable short-scale slope over several boxes at n = 16.
    public static let minCleanBeats: Int = 120

    /// Maximum tolerated artifact fraction (beats removed by range/ectopic cleaning ÷ input). α1 degrades
    /// fast with artifacts: Rogers B, Giles D, Draper N, Mourot L, Gronwald T, "Detrended Fluctuation
    /// Analysis of Heart Rate Variability… Effect of Beat Correction", Sensors 2021;21(3):821 (DOI
    /// 10.3390/s21030821) shows even 1/3/6% missed beats materially bias α1. The 5% ceiling is a
    /// PRODUCT-CALIBRATION knob chosen between their published 3% and 6% points (not a derived threshold);
    /// above it the window is REFUSED, not reported best-effort.
    public static let maxArtifactFraction: Double = 0.05

    /// Minimum distinct scales that must yield a positive F(n) before a slope is fit.
    public static let minScales: Int = 4

    /// Standing caveat surfaced on every result (verbatim, so the surface can't drop it).
    public static let caveat = "Experimental - from wrist R-R, not an ECG. Reliable only on a clean signal (chest strap)."

    // MARK: - Threshold proxy

    /// α1 landmarks as an intensity proxy. Descriptive, NOT a prescription or a measured threshold.
    public enum Intensity: String, Equatable, Sendable, Codable {
        case easy              // α1 ≳ 0.75 — below the aerobic threshold (VT1)
        case aroundAerobic     // α1 ≈ 0.75 — near VT1
        case moderate          // 0.5 < α1 < 0.75 — between the thresholds
        case aroundAnaerobic   // α1 ≈ 0.5 — near VT2
        case hard              // α1 < 0.5 — at/above the anaerobic threshold (VT2)
    }

    /// Map an α1 value to the descriptive intensity band, with a small ± band around each landmark.
    public static func intensity(for alpha1: Double) -> Intensity {
        if alpha1 >= 0.80 { return .easy }
        if alpha1 >= 0.70 { return .aroundAerobic }
        if alpha1 > 0.55 { return .moderate }
        if alpha1 >= 0.45 { return .aroundAnaerobic }
        return .hard
    }

    // MARK: - Output

    public struct Result: Equatable, Sendable {
        /// The α1 exponent, or nil when gated off (disabled / too few beats / too many artifacts /
        /// degenerate fit).
        public let alpha1: Double?
        /// Descriptive intensity band, nil when α1 is nil.
        public let intensity: Intensity?
        /// True iff experimental is on AND the signal cleared the artifact + count gates.
        public let signalOk: Bool
        /// Fraction of input beats removed by cleaning (range + ectopic).
        public let artifactFraction: Double
        /// Clean beats that survived.
        public let nClean: Int
        /// Always present, non-optional — the experimental caveat.
        public let caveat: String

        public init(alpha1: Double?, intensity: Intensity?, signalOk: Bool,
                    artifactFraction: Double, nClean: Int, caveat: String) {
            self.alpha1 = alpha1; self.intensity = intensity; self.signalOk = signalOk
            self.artifactFraction = artifactFraction; self.nClean = nClean; self.caveat = caveat
        }
    }

    // MARK: - Evaluate

    /// Evaluate α1 for a window of raw R-R intervals (ms). Gated: returns α1 == nil (but a populated,
    /// caveat-bearing result) unless `experimentalEnabled` is true AND the cleaned series clears the
    /// artifact fraction and minimum-beat gates. Cleaning reuses `HRVAnalyzer.cleanRR` (range +
    /// Malik ectopic rejection), so the artifact fraction is measured the same way as elsewhere.
    public static func evaluate(rawRR: [Double], experimentalEnabled: Bool) -> Result {
        let nInput = rawRR.count
        let clean = HRVAnalyzer.cleanRR(rawRR)
        let nClean = clean.count
        let artifactFraction = nInput > 0 ? Double(nInput - nClean) / Double(nInput) : 1.0

        func gatedOff() -> Result {
            Result(alpha1: nil, intensity: nil, signalOk: false,
                   artifactFraction: artifactFraction, nClean: nClean, caveat: caveat)
        }

        guard experimentalEnabled else { return gatedOff() }
        guard nClean >= minCleanBeats, artifactFraction <= maxArtifactFraction else { return gatedOff() }
        guard let a = alpha1(clean) else { return gatedOff() }

        return Result(alpha1: a, intensity: intensity(for: a), signalOk: true,
                      artifactFraction: artifactFraction, nClean: nClean, caveat: caveat)
    }

    // MARK: - DFA core

    /// The short-scale DFA exponent α1 of a series (Peng 1994). Returns nil if the series is too short
    /// or the fit is degenerate (fewer than `minScales` usable scales / zero variance in log n).
    /// Exposed for testing on synthetic series with a known correlation structure.
    public static func alpha1(_ series: [Double]) -> Double? {
        let N = series.count
        guard N >= scaleMax * 2 else { return nil }

        // 1. Integrated profile of the mean-removed series.
        let mean = series.reduce(0, +) / Double(N)
        var profile = [Double](repeating: 0, count: N)
        var running = 0.0
        for i in 0..<N { running += series[i] - mean; profile[i] = running }

        // 2. F(n) over each short scale.
        var logN: [Double] = []
        var logF: [Double] = []
        for n in scaleMin...scaleMax {
            let boxes = N / n
            guard boxes >= 1 else { continue }
            var sumSq = 0.0
            for b in 0..<boxes {
                let start = b * n
                sumSq += boxResidualSumSq(profile, start: start, n: n)
            }
            let f = (sumSq / Double(boxes * n)).squareRoot()
            guard f > 1e-12 else { continue }
            logN.append(Foundation.log(Double(n)))
            logF.append(Foundation.log(f))
        }

        guard logN.count >= minScales else { return nil }

        // 3. Slope of log F vs log n by ordinary least squares.
        return olsSlope(x: logN, y: logF)
    }

    /// Sum of squared residuals of a least-squares line fit to `profile[start ..< start+n]` over the
    /// local index 0..<n. This is the per-box detrending step of DFA.
    static func boxResidualSumSq(_ profile: [Double], start: Int, n: Int) -> Double {
        let nD = Double(n)
        // x = 0..<n; precompute the symmetric sums.
        let sumX = nD * (nD - 1) / 2.0
        let sumXX = (nD - 1) * nD * (2 * nD - 1) / 6.0
        var sumY = 0.0, sumXY = 0.0
        for i in 0..<n {
            let y = profile[start + i]
            sumY += y
            sumXY += Double(i) * y
        }
        let denom = nD * sumXX - sumX * sumX
        guard abs(denom) > 1e-12 else { return 0 }
        let slope = (nD * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / nD
        var ss = 0.0
        for i in 0..<n {
            let fit = intercept + slope * Double(i)
            let r = profile[start + i] - fit
            ss += r * r
        }
        return ss
    }

    /// Ordinary-least-squares slope of y on x; nil if x has zero variance.
    static func olsSlope(x: [Double], y: [Double]) -> Double? {
        let n = Double(x.count)
        let sumX = x.reduce(0, +), sumY = y.reduce(0, +)
        var sumXX = 0.0, sumXY = 0.0
        for i in 0..<x.count { sumXX += x[i] * x[i]; sumXY += x[i] * y[i] }
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 1e-12 else { return nil }
        return (n * sumXY - sumX * sumY) / denom
    }
}
