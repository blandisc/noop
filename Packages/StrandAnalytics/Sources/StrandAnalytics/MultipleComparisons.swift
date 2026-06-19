import Foundation

// MultipleComparisons.swift — Benjamini-Hochberg false-discovery-rate control.
//
// Pure, deterministic, DB-free. When the InsightEngine probes N behaviors × M
// outcomes (and a grid of metric-pair correlations) it runs dozens of independent
// hypothesis tests at once. At α = 0.05 a family of 40 *pure-noise* tests yields,
// on average, two "significant" hits by chance — exactly the false discoveries the
// engine must not surface. Benjamini-Hochberg (1995) rescales each raw p-value into
// a q-value so that calling everything with q < α "significant" keeps the EXPECTED
// proportion of false discoveries among the rejections at or below α.
//
// Procedure (step-up): sort the m p-values ascending p₍₁₎ ≤ … ≤ p₍ₘ₎, then
//   q₍ᵢ₎ = min over k ≥ i of ( p₍ₖ₎ · m / k ),   capped at 1.
// The inner running-minimum enforces monotonicity (a q-value never drops below a
// smaller raw p's adjustment) and makes the transform order-preserving.
//
// Under the global null (every test a true null) BH at level α also bounds the
// family-wise error rate at α, so the engine's noise test can assert that the
// fraction of random seeds producing ANY "significant" hit stays ≈ α.

public enum MultipleComparisons {

    /// Benjamini-Hochberg adjusted p-values (q-values) for `pValues`, returned in
    /// the SAME order as the input. Each q is in [0, 1]. Empty input → empty output;
    /// a single p is returned unchanged (capped at 1).
    ///
    /// q-values are monotonic in the raw p ordering: if pᵢ ≤ pⱼ then qᵢ ≤ qⱼ.
    public static func benjaminiHochberg(_ pValues: [Double]) -> [Double] {
        let m = pValues.count
        guard m > 1 else { return pValues.map { min(1.0, max(0.0, $0)) } }

        // Indices sorted by ascending p so rank k = position+1.
        let order = (0..<m).sorted { pValues[$0] < pValues[$1] }
        let mD = Double(m)

        var adjusted = [Double](repeating: 0, count: m)
        // Walk from the largest p (rank m) down to rank 1, carrying the running
        // minimum so each q₍ᵢ₎ = min(prev, p₍ᵢ₎ · m / i).
        var runningMin = 1.0
        for rank in stride(from: m, through: 1, by: -1) {
            let idx = order[rank - 1]
            let raw = pValues[idx] * mD / Double(rank)
            runningMin = Swift.min(runningMin, raw)
            adjusted[idx] = Swift.min(1.0, Swift.max(0.0, runningMin))
        }
        return adjusted
    }
}
