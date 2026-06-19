import Foundation

// CorrelationEngine.swift — relationships between two daily series.
//
// Pure, deterministic, DB-free. Computes the Pearson product-moment correlation r,
// a simple ordinary-least-squares regression line (slope/intercept of y on x), and
// an approximate two-sided p-value for r.
//
//   r = Σ(x−x̄)(y−ȳ) / sqrt( Σ(x−x̄)² · Σ(y−ȳ)² )         (Pearson)
//   slope     = Σ(x−x̄)(y−ȳ) / Σ(x−x̄)²                     (OLS, y on x)
//   intercept = ȳ − slope·x̄
//
// The p-value uses the standard t-statistic for a correlation,
//   t = r · sqrt( (n−2) / (1−r²) ),
// converted to a two-sided tail probability with the EXACT Student-t distribution
// (n−2 degrees of freedom), evaluated through the regularised incomplete beta
// function Iₓ(a,b):
//   p = Iₓ(df/2, 1/2),  x = df / (df + t²)             (Student 1908)
// This replaces the earlier NORMAL approximation (2·(1−Φ(|t|))), which understated
// p badly at small n — the Student-t tails are heavier, e.g. at n=5 the normal
// tail gave p≈0.034 where the true t tail is p≈0.124 (a 3.66× understatement).
// Iₓ is computed with the Lentz continued fraction (Numerical Recipes §6.4),
// deterministic and dependency-free (only `lgamma`/`exp` from the C math library).
//
// `alignByDay` inner-joins two "yyyy-MM-dd"-keyed series on the day key, returning
// (x, y) pairs sorted by day. `lagged` shifts y forward by `lagDays` relative to x
// (x on day D paired with y on day D+lag) and correlates the result, which lets a
// caller probe directional / delayed effects (e.g. today's strain vs tomorrow's
// recovery).

/// The result of correlating two aligned series.
public struct Correlation: Equatable, Sendable {
    /// Pearson correlation coefficient in [-1, 1].
    public let r: Double
    /// Number of paired observations used.
    public let n: Int
    /// Two-sided p-value for H0: r = 0 (exact Student-t, df = n−2).
    public let pApprox: Double
    /// OLS slope of y on x.
    public let slope: Double
    /// OLS intercept of y on x.
    public let intercept: Double

    public init(r: Double, n: Int, pApprox: Double, slope: Double, intercept: Double) {
        self.r = r
        self.n = n
        self.pApprox = pApprox
        self.slope = slope
        self.intercept = intercept
    }
}

public enum CorrelationEngine {

    // MARK: - Pearson + regression

    /// Pearson r plus an OLS regression line and approximate p-value for the pairs.
    /// Returns nil when fewer than 3 pairs, or when either variable has zero
    /// variance (r undefined).
    public static func pearson(_ xy: [(Double, Double)]) -> Correlation? {
        let n = xy.count
        guard n >= 3 else { return nil }
        let nD = Double(n)

        var sumX = 0.0, sumY = 0.0
        for p in xy { sumX += p.0; sumY += p.1 }
        let meanX = sumX / nD
        let meanY = sumY / nD

        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in xy {
            let dx = p.0 - meanX
            let dy = p.1 - meanY
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }

        // Zero variance in either variable → correlation undefined.
        guard sxx > 0 && syy > 0 else { return nil }

        var r = sxy / (sxx.squareRoot() * syy.squareRoot())
        // Clamp tiny floating-point overshoot so |r| ≤ 1 exactly.
        if r > 1.0 { r = 1.0 }
        if r < -1.0 { r = -1.0 }

        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        let p = pValue(r: r, n: n)

        return Correlation(r: r, n: n, pApprox: p, slope: slope, intercept: intercept)
    }

    // MARK: - Day alignment

    /// Inner-join two "yyyy-MM-dd"-keyed series on the day key, returning the (x, y)
    /// value pairs for days present in BOTH, sorted ascending by day. Later entries
    /// for a duplicated day in either series win (last-write).
    public static func alignByDay(_ a: [(day: String, value: Double)],
                                  _ b: [(day: String, value: Double)]) -> [(Double, Double)] {
        var mapA: [String: Double] = [:]
        for row in a { mapA[row.day] = row.value }
        var mapB: [String: Double] = [:]
        for row in b { mapB[row.day] = row.value }

        let commonDays = mapA.keys.filter { mapB[$0] != nil }.sorted()
        return commonDays.map { (mapA[$0]!, mapB[$0]!) }
    }

    // MARK: - Lagged correlation

    /// Correlate x[day] against y[day + lagDays]. A positive lag asks "does x today
    /// predict y `lagDays` later?"; a negative lag looks backward. Days are matched
    /// on the calendar by offsetting x's day key by `lagDays` and joining to y.
    ///
    /// Returns nil when fewer than 3 lag-matched pairs survive or when `pearson`
    /// rejects them (zero variance).
    public static func lagged(x: [(day: String, value: Double)],
                              y: [(day: String, value: Double)],
                              lagDays: Int) -> Correlation? {
        var mapY: [String: Double] = [:]
        for row in y { mapY[row.day] = row.value }

        var pairs: [(Double, Double)] = []
        // Sort x by day for deterministic ordering of the pair list.
        let sortedX = x.sorted { $0.day < $1.day }
        for row in sortedX {
            guard let shifted = shiftDay(row.day, by: lagDays) else { continue }
            if let yv = mapY[shifted] {
                pairs.append((row.value, yv))
            }
        }
        return pearson(pairs)
    }

    // MARK: - p-value

    /// Two-sided p-value for H0: r = 0 via t = r·sqrt((n−2)/(1−r²)) and the EXACT
    /// Student-t tail (df = n−2). n ≤ 2 → 1.0 (no evidence); |r| = 1 → 0.0.
    static func pValue(r: Double, n: Int) -> Double {
        guard n > 2 else { return 1.0 }
        let oneMinusR2 = 1.0 - r * r
        if oneMinusR2 <= 0 { return 0.0 }  // |r| == 1
        let t = r * (Double(n - 2) / oneMinusR2).squareRoot()
        return studentTTwoSided(t: t, df: Double(n - 2))
    }

    // MARK: - Student-t two-sided tail (exact, via regularised incomplete beta)

    /// Two-sided tail probability P(|T| ≥ |t|) for a Student-t with `df` degrees of
    /// freedom: p = Iₓ(df/2, 1/2) with x = df/(df + t²). Exact (not a normal
    /// approximation); df may be fractional (Welch–Satterthwaite). df ≤ 0 → 1.0,
    /// t = 0 → 1.0. (Student 1908.)
    static func studentTTwoSided(t: Double, df: Double) -> Double {
        guard df > 0 else { return 1.0 }
        let t2 = t * t
        guard t2 > 0 else { return 1.0 }
        let x = df / (df + t2)
        return min(1.0, max(0.0, incompleteBeta(x, df / 2.0, 0.5)))
    }

    /// Regularised incomplete beta Iₓ(a,b) for x∈[0,1], a,b>0 — Lentz continued
    /// fraction (Numerical Recipes §6.4), accurate to ~1e-10. Used for the Student-t
    /// tail; no external tables.
    static func incompleteBeta(_ x: Double, _ a: Double, _ b: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // Front factor x^a·(1−x)^b / B(a,b), via lgamma for stability.
        let lbeta = lgamma(a + b) - lgamma(a) - lgamma(b)
        let front = exp(lbeta + a * log(x) + b * log(1 - x))
        // The continued fraction converges fast for x < (a+1)/(a+b+2); else use the
        // symmetry Iₓ(a,b) = 1 − I₁₋ₓ(b,a).
        if x < (a + 1) / (a + b + 2) {
            return front * betaCF(x, a, b) / a
        } else {
            return 1 - front * betaCF(1 - x, b, a) / b
        }
    }

    /// Continued fraction for the incomplete beta (modified Lentz). Helper for
    /// `incompleteBeta`; not called directly.
    private static func betaCF(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let tiny = 1e-30
        let qab = a + b, qap = a + 1, qam = a - 1
        var c = 1.0
        var d = 1.0 - qab * x / qap
        if abs(d) < tiny { d = tiny }
        d = 1.0 / d
        var h = d
        for m in 1...200 {
            let mD = Double(m)
            let m2 = 2.0 * mD
            // even step
            var aa = mD * (b - mD) * x / ((qam + m2) * (a + m2))
            d = 1.0 + aa * d; if abs(d) < tiny { d = tiny }
            c = 1.0 + aa / c; if abs(c) < tiny { c = tiny }
            d = 1.0 / d; h *= d * c
            // odd step
            aa = -(a + mD) * (qab + mD) * x / ((a + m2) * (qap + m2))
            d = 1.0 + aa * d; if abs(d) < tiny { d = tiny }
            c = 1.0 + aa / c; if abs(c) < tiny { c = tiny }
            d = 1.0 / d
            let del = d * c
            h *= del
            if abs(del - 1.0) < 1e-12 { break }   // converged
        }
        return h
    }

    // MARK: - Day arithmetic

    /// Shift a "yyyy-MM-dd" day string by `delta` days (can be negative), returning
    /// a normalised "yyyy-MM-dd" string. Uses a fixed UTC calendar so it is
    /// deterministic and timezone-free. Returns nil if the input can't be parsed.
    static func shiftDay(_ day: String, by delta: Int) -> String? {
        if delta == 0 { return day }
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1 else { return nil }

        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let base = cal.date(from: comps),
              let shifted = cal.date(byAdding: .day, value: delta, to: base) else { return nil }
        let out = cal.dateComponents([.year, .month, .day], from: shifted)
        guard let oy = out.year, let om = out.month, let od = out.day else { return nil }
        return String(format: "%04d-%02d-%02d", oy, om, od)
    }
}
