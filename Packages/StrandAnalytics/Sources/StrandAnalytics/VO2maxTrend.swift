import Foundation

// VO2maxTrend.swift — the TRAJECTORY of cardiorespiratory fitness, not a point (FER-679). Pure, DB-free.
//
// `FitnessAgeEngine` already estimates VO₂max, but a single value is noisy: the Nes 2011 non-exercise
// model carries a standard error of estimate (SEE) of ~5.7 ml·kg⁻¹·min⁻¹. Day-to-day, that jitter
// swamps real change, so the honest read is the DIRECTION over weeks — "subiendo / estable / bajando" —
// with a noise floor that refuses to call a trend the estimator can't actually resolve.
//
// METHOD (independent implementation of standard robust methods):
//   • Slope: the Theil–Sen estimator — the MEDIAN of all pairwise slopes (yⱼ−yᵢ)/(xⱼ−xᵢ). It ignores
//     outlier estimates (a single bad night) that would tilt an ordinary least-squares line
//     (Sen, "Estimates of the regression coefficient based on Kendall's tau", JASA 1968;63:1379–1389).
//   • Band: the 25th/75th percentiles of those same pairwise slopes give a robust, distribution-free
//     interval on the slope; projected over the observed span they bound the change.
//   • Noise floor: a declared trend must clear ~SEE/√n ml·kg⁻¹·min⁻¹ of change over the window. This is a
//     product-calibration knob, NOT a derived standard error: the √n shape borrows the intuition that
//     averaging more estimates resolves smaller real moves, but the weekly VO₂max estimates are NOT
//     independent replicates (they share slowly-moving inputs — age, WHR, resting HR — so a true SE would
//     shrink slower than √n). We keep √n as a deliberately simple, conservative-leaning floor and let it
//     stop us reacting to the SEE ~5.7 jitter of any one estimate; the exact shape is for the CDO
//     (`/estadistico`) to validate, not a claim of statistical exactness.
//   A direction is reported only when BOTH gates pass: the slope band excludes zero AND the projected
//   change beats the floor. Otherwise → `.stable` (or, below the data minimum, `nil` → hide).
//
// HONEST HEDGING: fitness is among the strongest mortality predictors (Mandsager 2018, JAMA Netw Open
// 1(6):e183605, HR 5.04 low-vs-elite), but we show a DIRECTION only — never a longevity promise, never
// "years of life". APPROXIMATION, not a clinical measurement.
public enum VO2maxTrend {

    // MARK: - Tuning constants (pinned by test)

    /// Standard error of the VO₂max estimate (ml·kg⁻¹·min⁻¹) — Nes 2011 non-exercise model, the engine
    /// `FitnessAgeEngine` uses. Drives the noise floor.
    public static let seeMlKgMin: Double = 5.7
    /// Minimum estimates before a trajectory is trustworthy enough to show.
    public static let minPoints: Int = 6
    /// Minimum span (days) the estimates must cover — a trend over < 3 weeks is premature.
    public static let minSpanDays: Int = 21
    /// Points at/above which the trajectory reads as full-confidence.
    public static let solidPoints: Int = 12

    /// The change-over-window floor (ml·kg⁻¹·min⁻¹) below which we won't claim a direction: ~SEE/√n. A
    /// product-calibration knob (NOT a derived standard error — the estimates aren't independent
    /// replicates; see the file header). Deliberately simple and conservative-leaning; shrinks with data.
    public static func noiseFloor(pointCount n: Int) -> Double {
        guard n > 0 else { return seeMlKgMin }
        return seeMlKgMin / Double(n).squareRoot()
    }

    // MARK: - Output

    public enum Direction: String, Equatable, Sendable, Codable {
        case rising    // improving beyond the noise floor
        case stable    // no move the estimator can resolve
        case falling   // declining beyond the noise floor
    }

    public enum Confidence: String, Equatable, Sendable, Codable {
        case unreadable   // below the data minimum — hide
        case estimate     // enough to read, thin
        case solid        // a stable trajectory over enough estimates
    }

    public struct Result: Equatable, Sendable {
        /// Robust (Theil–Sen) slope in ml·kg⁻¹·min⁻¹ per WEEK.
        public let slopePerWeek: Double
        /// Projected change over the observed window (ml·kg⁻¹·min⁻¹) = slope · span.
        public let changeOverWindow: Double
        /// Half-width of the robust band on that change (±), from the pairwise-slope IQR.
        public let changeBand: Double
        /// The noise floor that had to be cleared (ml·kg⁻¹·min⁻¹).
        public let noiseFloor: Double
        public let direction: Direction
        public let confidence: Confidence
        /// Honest es-MX one-liner — a direction, never a longevity claim.
        public let note: String
        public init(slopePerWeek: Double, changeOverWindow: Double, changeBand: Double,
                    noiseFloor: Double, direction: Direction, confidence: Confidence, note: String) {
            self.slopePerWeek = slopePerWeek; self.changeOverWindow = changeOverWindow
            self.changeBand = changeBand; self.noiseFloor = noiseFloor
            self.direction = direction; self.confidence = confidence; self.note = note
        }
    }

    // MARK: - Input

    /// One VO₂max estimate placed in time. `day` is any monotone day index (e.g. days since epoch);
    /// only differences matter. `value` is the estimate in ml·kg⁻¹·min⁻¹.
    public struct Point: Equatable, Sendable {
        public let day: Int
        public let value: Double
        public init(day: Int, value: Double) { self.day = day; self.value = value }
    }

    // MARK: - API

    /// Assess the fitness trajectory. Returns `nil` (hide the block) below the data minimum: fewer than
    /// `minPoints` distinct-day estimates or a span under `minSpanDays`.
    public static func assess(_ points: [Point]) -> Result? {
        // Collapse duplicate days to their mean, then sort by day.
        var byDay: [Int: (sum: Double, n: Int)] = [:]
        for p in points {
            let e = byDay[p.day] ?? (0, 0)
            byDay[p.day] = (e.sum + p.value, e.n + 1)
        }
        let pts = byDay.map { Point(day: $0.key, value: $0.value.sum / Double($0.value.n)) }
                       .sorted { $0.day < $1.day }
        guard pts.count >= minPoints else { return nil }
        let spanDays = pts.last!.day - pts.first!.day
        guard spanDays >= minSpanDays else { return nil }

        // Pairwise slopes (per day) over all distinct-day pairs.
        var slopes: [Double] = []
        slopes.reserveCapacity(pts.count * (pts.count - 1) / 2)
        for i in 0..<pts.count {
            for j in (i + 1)..<pts.count {
                let dx = Double(pts[j].day - pts[i].day)
                if dx != 0 { slopes.append((pts[j].value - pts[i].value) / dx) }
            }
        }
        guard !slopes.isEmpty else { return nil }
        slopes.sort()

        let slopePerDay = HRVAnalyzer.median(slopes)
        let slopeLo = percentile(slopes, 0.25)   // robust band on the per-day slope
        let slopeHi = percentile(slopes, 0.75)

        let span = Double(spanDays)
        let changeMid = slopePerDay * span
        let changeLo = slopeLo * span
        let changeHi = slopeHi * span
        let changeBand = abs(changeHi - changeLo) / 2.0

        let floor = noiseFloor(pointCount: pts.count)

        // Two gates: the slope band must exclude zero AND the projected change must beat the floor.
        let direction: Direction
        if changeMid >= floor && changeLo > 0 {
            direction = .rising
        } else if changeMid <= -floor && changeHi < 0 {
            direction = .falling
        } else {
            direction = .stable
        }

        let confidence: Confidence = pts.count >= solidPoints ? .solid : .estimate
        let note = phrase(direction: direction)

        return Result(slopePerWeek: slopePerDay * 7.0, changeOverWindow: changeMid,
                      changeBand: changeBand, noiseFloor: floor,
                      direction: direction, confidence: confidence, note: note)
    }

    // MARK: - Internals

    /// Linear-interpolated percentile of a SORTED array (q in [0,1]).
    static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        if sorted.count == 1 { return sorted[0] }
        let pos = q * Double(sorted.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = Int(pos.rounded(.up))
        if lo == hi { return sorted[lo] }
        let frac = pos - Double(lo)
        return sorted[lo] * (1 - frac) + sorted[hi] * frac
    }

    /// Honest es-MX one-liner — a direction, never a longevity claim.
    static func phrase(direction: Direction) -> String {
        switch direction {
        case .rising:  return "Tu condición cardiorrespiratoria viene subiendo en las últimas semanas."
        case .falling: return "Tu condición cardiorrespiratoria viene bajando en las últimas semanas."
        case .stable:  return "Tu condición cardiorrespiratoria se ve estable — sin cambios que el estimador pueda distinguir del ruido."
        }
    }
}
