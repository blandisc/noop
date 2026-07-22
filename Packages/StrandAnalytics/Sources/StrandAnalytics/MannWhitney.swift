import Foundation

// MannWhitney.swift — the exact/approximate Wilcoxon rank-sum (Mann-Whitney U) test (FER-1034).
//
// Pure, deterministic, Foundation-only. The N-of-1 tag-experiment path (Preparación Capa 2) compares
// two INDEPENDENT samples — the outcome on days the user tagged a behavior "yes" vs days tagged "no" —
// so the paired signed-rank test does not apply; this is the two-sample rank-sum. Distribution-free,
// which is the point: the outcomes (HRV especially) are right-skewed/log-normal (Plews 2013), and at
// n ≈ 5–10 per arm a normal-theory t-test is fragile. A rank test needs no distributional assumption.
//
// Two-sided only: the tag templates carry no prior directional hypothesis. Exact p (dynamic program
// over the U null distribution, Mann & Whitney 1947) when the combined sample has NO ties and
// n1+n2 ≤ 30; otherwise the tie-corrected normal approximation with a continuity correction
// (Lehmann 1975). Effect for display is the Hodges-Lehmann shift (median of pairwise differences,
// Hodges & Lehmann 1963) in the outcome's native units, plus the rank-biserial correlation.
//
// References: Wilcoxon 1945 (Biometrics Bulletin 1(6):80); Mann & Whitney 1947 (Ann Math Statist
// 18(1):50); Hodges & Lehmann 1963 (Ann Math Statist 34(2):598); Lehmann 1975 (Nonparametrics,
// Holden-Day). APPROXIMATE, no clinical claim.

public struct MannWhitneyResult: Sendable, Equatable {
    /// U statistic of group 1 relative to group 2: #{x>y} + 0.5·#{ties}. U ∈ [0, n1·n2].
    public let u: Double
    /// Two-sided p-value, capped at 1.
    public let p: Double
    public let method: Method
    /// Hodges-Lehmann shift (group1 − group2), median of all pairwise differences, native units.
    public let hlShift: Double
    /// Rank-biserial r = 2·P(X>Y) − 1 ∈ [−1, 1]; + means group 1 tends to exceed group 2.
    public let rankBiserial: Double
    public let n1: Int
    public let n2: Int

    public enum Method: String, Sendable, Equatable { case exact, approx }

    public init(u: Double, p: Double, method: Method, hlShift: Double,
                rankBiserial: Double, n1: Int, n2: Int) {
        self.u = u; self.p = p; self.method = method; self.hlShift = hlShift
        self.rankBiserial = rankBiserial; self.n1 = n1; self.n2 = n2
    }
}

public enum MannWhitney {

    /// Exact-p validity ceiling on the combined sample size. Above it (or with ties) we use the
    /// normal approximation — the DP is still O(n1·n2·(n1·n2)) but past ~30 it buys nothing.
    public static let exactMaxN = 30

    /// Two-sample rank-sum test. Returns nil if either group is empty.
    public static func test(_ x: [Double], _ y: [Double]) -> MannWhitneyResult? {
        let n1 = x.count, n2 = y.count
        guard n1 > 0, n2 > 0 else { return nil }

        let u = uStat(x, y)
        let hl = hodgesLehmann(x, y)
        let f = u / Double(n1 * n2)          // P(X > Y) "common-language" effect
        let r = 2 * f - 1

        let ties = hasTies(x + y)
        if !ties && n1 + n2 <= exactMaxN {
            let p = exactTwoSidedP(u: u, m: n1, n: n2)
            return MannWhitneyResult(u: u, p: p, method: .exact, hlShift: hl,
                                     rankBiserial: r, n1: n1, n2: n2)
        } else {
            let p = approxTwoSidedP(u: u, x: x, y: y)
            return MannWhitneyResult(u: u, p: p, method: .approx, hlShift: hl,
                                     rankBiserial: r, n1: n1, n2: n2)
        }
    }

    // MARK: - Statistic

    /// U for x vs y: #{(i,j): x_i > y_j} + 0.5·#{x_i == y_j}.
    static func uStat(_ x: [Double], _ y: [Double]) -> Double {
        var u = 0.0
        for xi in x { for yj in y {
            if xi > yj { u += 1 } else if xi == yj { u += 0.5 }
        }}
        return u
    }

    /// Hodges-Lehmann shift: median of all pairwise differences x_i − y_j.
    static func hodgesLehmann(_ x: [Double], _ y: [Double]) -> Double {
        var diffs: [Double] = []
        diffs.reserveCapacity(x.count * y.count)
        for xi in x { for yj in y { diffs.append(xi - yj) } }
        diffs.sort()
        let k = diffs.count
        guard k > 0 else { return 0 }
        return k % 2 == 1 ? diffs[k / 2] : (diffs[k / 2 - 1] + diffs[k / 2]) / 2
    }

    private static func hasTies(_ values: [Double]) -> Bool {
        Set(values).count != values.count
    }

    // MARK: - Exact null distribution (no ties)

    /// Counts of arrangements with U == u for group sizes m, n, via the recurrence
    /// f(m,n,u) = f(m−1,n,u−n) + f(m,n−1,u) (Mann & Whitney 1947). Index u = 0...m·n.
    static func exactUCounts(m: Int, n: Int) -> [Double] {
        let maxU = m * n
        var dp = Array(repeating: Array(repeating: [Double](), count: n + 1), count: m + 1)
        for i in 0...m { for j in 0...n {
            if i == 0 || j == 0 { dp[i][j] = [1.0] + Array(repeating: 0.0, count: maxU); continue }
            var row = Array(repeating: 0.0, count: maxU + 1)
            for u in 0...maxU {
                let a = (u - j >= 0) ? dp[i - 1][j][u - j] : 0.0
                let b = dp[i][j - 1][u]
                row[u] = a + b
            }
            dp[i][j] = row
        }}
        return dp[m][n]
    }

    /// Exact two-sided p = min(1, 2·min(P(U≤u), P(U≥u))). Valid only with no ties.
    static func exactTwoSidedP(u: Double, m: Int, n: Int) -> Double {
        let counts = exactUCounts(m: m, n: n)
        let total = counts.reduce(0, +)
        guard total > 0 else { return 1 }
        let uInt = Int(u.rounded())
        let clamped = Swift.min(Swift.max(uInt, 0), m * n)
        let lower = counts[0...clamped].reduce(0, +) / total
        let upper = counts[clamped...].reduce(0, +) / total
        return Swift.min(1.0, 2.0 * Swift.min(lower, upper))
    }

    // MARK: - Normal approximation (ties / large n)

    /// Tie-corrected normal approximation with a continuity correction (Lehmann 1975).
    static func approxTwoSidedP(u: Double, x: [Double], y: [Double]) -> Double {
        let n1 = Double(x.count), n2 = Double(y.count)
        let N = n1 + n2
        let muU = n1 * n2 / 2.0

        // Tie term Σ(t³ − t) over tie groups in the combined sample.
        var tieTerm = 0.0
        var groups: [Double: Int] = [:]
        for v in (x + y) { groups[v, default: 0] += 1 }
        for (_, t) in groups where t > 1 {
            let td = Double(t); tieTerm += td * td * td - td
        }

        let varU = (n1 * n2 / 12.0) * ((N + 1) - tieTerm / (N * (N - 1)))
        guard varU > 0 else { return 1 }   // degenerate: all values identical

        let diff = abs(u - muU) - 0.5      // continuity correction toward the mean
        let z = Swift.max(0, diff) / varU.squareRoot()
        // p = 2·(1 − Φ(z)) = erfc(z/√2), capped at 1.
        return Swift.min(1.0, erfc(z / 2.0.squareRoot()))
    }
}
