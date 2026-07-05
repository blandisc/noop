import Foundation

/// «Las cinco reglas» — the mark-per-point presentation of TODAY's recovery score (FER-709).
///
/// The «Hoy» redesign explains the score as rows of marks, one row per driver: the row's LENGTH
/// is the driver's real `RecoveryScorer` weight (renormalized over the signals present, exactly
/// like the scorer drops missing terms), and its LIT marks are the signal's share of the
/// displayed score — so Σ lit across rows == the numeral EXACTLY (arithmetic transparency).
///
/// The per-signal share is a documented APPROXIMATION: the score is a logistic of the summed
/// composite z, which has no exact additive decomposition into points. Each present signal is
/// read through the score's own logistic (on its oriented, confidence-shrunk z — the same term
/// `RecoveryImpact` exposes), giving the row an honest 0…1 fill; the fills are then rescaled to
/// absorb the logistic's nonlinearity so the lit total lands on the numeral, redistributing any
/// row overflow across the remaining headroom. Pure, deterministic, no clock or store.
public enum RecoveryRules {

    /// One row of the instrument.
    public struct Rule: Equatable, Sendable, Identifiable {
        public let key: String   // "hrv" | "rhr" | "sleep" | "skinTemp" | "respRate"
        /// Total marks in the row — the signal's renormalized weight share of 100.
        public let marks: Int
        /// Lit marks, 0…`marks`. Σ lit across all rows == the displayed score.
        public let lit: Int
        public var id: String { key }
        public init(key: String, marks: Int, lit: Int) {
            self.key = key; self.marks = marks; self.lit = lit
        }
    }

    /// Canonical display order — descending engine weight (RecoveryScorer's documented table).
    public static let displayOrder = ["hrv", "rhr", "sleep", "skinTemp", "respRate"]

    /// Decompose the displayed score into rows of marks. Empty when the impact has no signals.
    ///
    /// - Parameters:
    ///   - impact: today's per-signal decomposition (`RecoveryImpact.compute`); its weights are
    ///     already renormalized over the present terms.
    ///   - score: the numeral the screen shows (the rounded persisted recovery). Clamped to 0…100.
    public static func rules(impact: RecoveryImpact.Result, score: Int) -> [Rule] {
        let signals = displayOrder.compactMap { impact.signal($0) }
        guard !signals.isEmpty else { return [] }
        let target = max(0, min(100, score))

        // Row lengths: one mark per point of renormalized weight, largest-remainder so the five
        // rows always total exactly 100 marks.
        let marks = apportion(signals.map(\.weight), total: 100)

        // Row fill: the signal's own read through the score's logistic (0…1), then rescaled so
        // the lit total == the numeral.
        let fills = signals.map { s in
            1.0 / (1.0 + exp(-RecoveryScorer.logisticK * (s.orientedZ - RecoveryScorer.logisticZ0)))
        }
        let lit = distribute(raw: zip(fills, marks).map { $0 * Double($1) }, caps: marks, target: target)

        return signals.indices.map { Rule(key: signals[$0].key, marks: marks[$0], lit: lit[$0]) }
    }

    // MARK: - Integer apportionment

    /// Largest-remainder apportionment of `total` units proportional to `weights`. Ties break
    /// toward the earlier (heavier, by display order) row so the result is deterministic.
    static func apportion(_ weights: [Double], total: Int) -> [Int] {
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return weights.map { _ in 0 } }
        let quotas = weights.map { $0 / sum * Double(total) }
        var out = quotas.map { Int($0.rounded(.down)) }
        var remainder = total - out.reduce(0, +)
        let byFraction = quotas.indices.sorted {
            let (fa, fb) = (quotas[$0] - quotas[$0].rounded(.down), quotas[$1] - quotas[$1].rounded(.down))
            return fa == fb ? $0 < $1 : fa > fb
        }
        for i in byFraction where remainder > 0 { out[i] += 1; remainder -= 1 }
        return out
    }

    /// Scale `raw` (per-row lit estimates) so the integer result sums to exactly `target`, with
    /// each row capped at its `caps` length. Water-fill: rows that would overflow are pinned at
    /// their cap and the excess re-scales over the remaining headroom; then a capped
    /// largest-remainder rounding lands the exact integer total.
    static func distribute(raw: [Double], caps: [Int], target: Int) -> [Int] {
        var scaled = [Double](repeating: 0, count: raw.count)
        var active = Set(raw.indices)
        var remaining = Double(min(target, caps.reduce(0, +)))

        // Pin overflowing rows at their cap until every active row fits under scaling. `apportion`
        // always hands ≥1 row a positive length and every fill is a logistic in (0,1), so `rawSum`
        // is positive whenever there's still fill to place; the guard just keeps a degenerate all-zero
        // input (target 0, or every row capped out) from dividing by zero — the rounding pass below
        // still lands the exact total.
        while !active.isEmpty {
            let rawSum = active.reduce(0.0) { $0 + raw[$1] }
            guard rawSum > 0 else { break }
            var overflowed = false
            for i in active { scaled[i] = raw[i] * remaining / rawSum }
            for i in active where scaled[i] > Double(caps[i]) {
                scaled[i] = Double(caps[i])
                remaining -= Double(caps[i])
                active.remove(i)
                overflowed = true
            }
            if !overflowed { break }
        }

        // Capped largest-remainder rounding to the exact target.
        var out = scaled.map { Int($0.rounded(.down)) }
        var deficit = min(target, caps.reduce(0, +)) - out.reduce(0, +)
        let byFraction = scaled.indices.sorted {
            let (fa, fb) = (scaled[$0] - scaled[$0].rounded(.down), scaled[$1] - scaled[$1].rounded(.down))
            return fa == fb ? $0 < $1 : fa > fb
        }
        for i in byFraction where deficit > 0 && out[i] < caps[i] { out[i] += 1; deficit -= 1 }
        // Degenerate float leftovers: top up any row with headroom.
        if deficit > 0 {
            for i in out.indices where deficit > 0 {
                let room = caps[i] - out[i]
                let add = min(room, deficit)
                out[i] += add; deficit -= add
            }
        }
        return out
    }
}
