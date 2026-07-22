import Foundation

// BehaviorInsights.swift — does a logged behavior move an outcome?
//
// Pure, deterministic, DB-free. The headline data-interrogation feature: split the
// days where a behavior was logged (e.g. "Alcohol", "Late meal", "Meditation")
// from the days it was not, then compare the outcome metric (e.g. Recovery, HRV,
// sleep performance) between the two groups.
//
// For each behavior/outcome we report:
//   - meanWith / meanWithout : group means of the outcome.
//   - delta = meanWith − meanWithout, and pctChange relative to meanWithout.
//   - cohensD : standardised effect size using the POOLED standard deviation
//       sp = sqrt( ((n1−1)·s1² + (n2−1)·s2²) / (n1+n2−2) ),  d = (meanWith − meanWithout)/sp.
//   - pApprox : a two-sided p-value from Welch's t-test (unequal variances),
//       t  = (m1 − m2) / sqrt(s1²/n1 + s2²/n2),
//       df = (s1²/n1 + s2²/n2)² / ( (s1²/n1)²/(n1−1) + (s2²/n2)²/(n2−1) )  [Welch–Satterthwaite],
//     converted to the EXACT Student-t tail at that df (via the regularised
//     incomplete beta in CorrelationEngine) — NOT a normal approximation. The df is
//     the one this header always documented but the code previously ignored; the
//     normal tail it used understated p at small samples.
//   - significant : computed by `rank` only, via Benjamini-Hochberg FDR across the
//     whole ranked family (NOT per test) AND min(nWith, nWithout) ≥ 5. `effect`
//     alone sets a provisional single-test flag (p < 0.05 AND the group floor);
//     never display that one directly — display `rank`'s, which controls for the
//     multiple comparisons a screen makes at once (Benjamini-Hochberg 1995).
//
// Effect direction is carried by the SIGN of delta / cohensD: a behavior that
// lowers the outcome yields negative values. `rank` orders behaviors by |cohensD|
// descending with significant effects first; `sentence` renders one in plain
// English for the UI.

/// The measured effect of one behavior on one outcome metric.
public struct BehaviorEffect: Equatable, Sendable {
    /// The behavior label (e.g. "Alcohol").
    public let behavior: String
    /// The outcome metric label (e.g. "Recovery").
    public let outcome: String
    /// Mean outcome on days the behavior WAS logged.
    public let meanWith: Double
    /// Mean outcome on days the behavior was NOT logged.
    public let meanWithout: Double
    /// meanWith − meanWithout (signed).
    public let delta: Double
    /// Percent change of meanWith relative to meanWithout, or nil when
    /// meanWithout is 0 (ratio undefined).
    public let pctChange: Double?
    /// Number of behavior-present days with an outcome value.
    public let nWith: Int
    /// Number of behavior-absent days with an outcome value.
    public let nWithout: Int
    /// Cohen's d using the pooled SD (signed; sign matches delta).
    public let cohensD: Double
    /// Two-sided p-value (Welch t-test, exact Student-t tail at the Welch df).
    public let pApprox: Double
    /// Whether this effect cleared the significance bar. From `effect` this is the
    /// provisional single-test flag (pApprox < 0.05 AND min group ≥ 5); `rank`
    /// REPLACES it with the FDR-corrected verdict — display only the latter.
    public let significant: Bool

    public init(behavior: String, outcome: String, meanWith: Double, meanWithout: Double,
                delta: Double, pctChange: Double?, nWith: Int, nWithout: Int,
                cohensD: Double, pApprox: Double, significant: Bool) {
        self.behavior = behavior
        self.outcome = outcome
        self.meanWith = meanWith
        self.meanWithout = meanWithout
        self.delta = delta
        self.pctChange = pctChange
        self.nWith = nWith
        self.nWithout = nWithout
        self.cohensD = cohensD
        self.pApprox = pApprox
        self.significant = significant
    }
}

public enum BehaviorInsights {

    /// Minimum group size (each side) for an effect to be flagged significant.
    public static let minGroupForSignificance: Int = 5
    /// Significance threshold on the approximate p-value.
    public static let alpha: Double = 0.05

    // MARK: - Single behavior effect

    /// Compute the effect of `behavior` on `outcome`. Days are partitioned into
    /// "with" (day ∈ behaviorDays) and "without" (day ∉ behaviorDays), restricted
    /// to days that have an outcome value in `outcomeByDay`.
    ///
    /// Returns nil unless BOTH groups are non-empty AND the total is large enough
    /// to form a variance estimate (at least 1 value per side and ≥ 3 total).
    ///
    /// `eligibleDays` (FER-385) is the universe of days on which the behavior is even *measured*.
    /// `nil` (the default) keeps the legacy split: every day with an outcome is eligible, so absence
    /// of a log means "without" — correct for journal behaviors, where not logging «Alcohol» means
    /// "didn't drink". For diet adherence it's the set of days that have a `diet-adherence` record:
    /// a day with no record is *unknown*, not non-adherent, and must fall into NEITHER group.
    public static func effect(behaviorDays: Set<String>,
                              outcomeByDay: [String: Double],
                              behavior: String,
                              outcome: String,
                              eligibleDays: Set<String>? = nil) -> BehaviorEffect? {
        var withVals: [Double] = []
        var withoutVals: [Double] = []
        for (day, value) in outcomeByDay {
            if let eligibleDays, !eligibleDays.contains(day) { continue }   // unknown day → neither group
            if behaviorDays.contains(day) { withVals.append(value) }
            else { withoutVals.append(value) }
        }

        let n1 = withVals.count
        let n2 = withoutVals.count
        // Need both groups present, and enough total points for a variance estimate.
        guard n1 >= 1, n2 >= 1, n1 + n2 >= 3 else { return nil }

        let m1 = withVals.reduce(0, +) / Double(n1)
        let m2 = withoutVals.reduce(0, +) / Double(n2)
        let delta = m1 - m2

        let pct: Double? = m2 != 0 ? (delta / abs(m2) * 100.0) : nil

        let v1 = sampleVariance(withVals, mean: m1)   // ddof=1; 0 when n==1
        let v2 = sampleVariance(withoutVals, mean: m2)

        let d = cohensD(m1: m1, m2: m2, n1: n1, v1: v1, n2: n2, v2: v2)
        let p = welchP(m1: m1, v1: v1, n1: n1, m2: m2, v2: v2, n2: n2)

        // Provisional single-test flag — `rank` overrides it with the FDR-corrected
        // verdict. Never display this one (it ignores the multiple comparisons a
        // screen makes at once).
        let sig = p < alpha && Swift.min(n1, n2) >= minGroupForSignificance

        return BehaviorEffect(behavior: behavior, outcome: outcome,
                              meanWith: m1, meanWithout: m2, delta: delta,
                              pctChange: pct, nWith: n1, nWithout: n2,
                              cohensD: d, pApprox: p, significant: sig)
    }

    // MARK: - Ranking

    /// Compute effects for every behavior in `behaviors` against one outcome and
    /// return them sorted by |cohensD| descending, with significant effects first.
    /// Behaviors that don't yield a computable effect are dropped.
    ///
    /// Significance is decided HERE, across the whole family at once: ranking K
    /// behaviors is K simultaneous hypothesis tests, so at α = 0.05 a few would test
    /// "significant" by chance. We rescale every effect's p with Benjamini-Hochberg
    /// (`MultipleComparisons`) into an FDR q-value and flag an effect significant only
    /// when q < α AND its smaller group clears the floor — overwriting the provisional
    /// single-test flag `effect` set. (Benjamini-Hochberg 1995.)
    public static func rank(behaviors: [String: Set<String>],
                            outcomeByDay: [String: Double],
                            outcome: String) -> [BehaviorEffect] {
        var raw: [BehaviorEffect] = []
        for (name, days) in behaviors {
            if let e = effect(behaviorDays: days, outcomeByDay: outcomeByDay,
                              behavior: name, outcome: outcome) {
                raw.append(e)
            }
        }

        // FDR-correct the family, then re-stamp `significant` from the q-value.
        let q = MultipleComparisons.benjaminiHochberg(raw.map(\.pApprox))
        let effects: [BehaviorEffect] = zip(raw, q).map { e, qVal in
            let sig = qVal < alpha && Swift.min(e.nWith, e.nWithout) >= minGroupForSignificance
            guard sig != e.significant else { return e }
            return BehaviorEffect(behavior: e.behavior, outcome: e.outcome,
                                  meanWith: e.meanWith, meanWithout: e.meanWithout,
                                  delta: e.delta, pctChange: e.pctChange,
                                  nWith: e.nWith, nWithout: e.nWithout,
                                  cohensD: e.cohensD, pApprox: e.pApprox, significant: sig)
        }

        return effects.sorted { a, b in
            if a.significant != b.significant { return a.significant }  // significant first
            let la = abs(a.cohensD), lb = abs(b.cohensD)
            if la != lb { return la > lb }                              // bigger effect first
            return a.behavior < b.behavior                             // stable tiebreak
        }
    }

    // MARK: - Sentence

    /// Render an effect as a plain-English sentence for the UI, e.g.
    /// "On days you logged ‘Alcohol’, Recovery was 12% lower (avg 61 vs 69, n=140 vs 498)."
    /// Falls back to absolute units when pctChange is unavailable.
    public static func sentence(_ e: BehaviorEffect) -> String {
        // appLocalized resolves against the app's String Catalog, which lives in the app, not
        // this package (same convention as ReadinessEngine; see AppLocalized.swift).
        let directionWord: String
        if e.delta > 0 { directionWord = appLocalized("higher") }
        else if e.delta < 0 { directionWord = appLocalized("lower") }
        else { directionWord = appLocalized("unchanged") }

        let magnitude: String
        if e.delta == 0 {
            magnitude = appLocalized("no different")
        } else if let pct = e.pctChange {
            magnitude = "\(roundedInt(abs(pct)))% \(directionWord)"
        } else {
            magnitude = "\(round1(abs(e.delta))) \(directionWord)"
        }

        let avgWith = roundedInt(e.meanWith)
        let avgWithout = roundedInt(e.meanWithout)

        return appLocalized("On days you logged ‘\(e.behavior)’, \(e.outcome) was \(magnitude) (avg \(avgWith) vs \(avgWithout), n=\(e.nWith) vs \(e.nWithout)).")
    }

    // MARK: - Statistics helpers

    /// Sample variance (ddof = 1). 0 for fewer than 2 values.
    static func sampleVariance(_ values: [Double], mean: Double) -> Double {
        let n = values.count
        guard n >= 2 else { return 0 }
        var ss = 0.0
        for v in values { let d = v - mean; ss += d * d }
        return ss / Double(n - 1)
    }

    /// Cohen's d with the pooled SD. Falls back to 0 when the pooled SD is 0
    /// (no within-group spread) and the means are equal; when means differ but
    /// pooled SD is 0 the effect is undefined → reported as 0 (no spread to scale).
    static func cohensD(m1: Double, m2: Double, n1: Int, v1: Double,
                        n2: Int, v2: Double) -> Double {
        let df = n1 + n2 - 2
        guard df > 0 else { return 0 }
        let pooledVar = (Double(n1 - 1) * v1 + Double(n2 - 1) * v2) / Double(df)
        let sp = pooledVar.squareRoot()
        guard sp > 0 else { return 0 }
        return (m1 - m2) / sp
    }

    /// Two-sided Welch t-test p-value using the EXACT Student-t tail at the
    /// Welch–Satterthwaite df. Returns 1.0 (no evidence) when neither group has a
    /// usable standard error.
    static func welchP(m1: Double, v1: Double, n1: Int,
                       m2: Double, v2: Double, n2: Int) -> Double {
        let se1 = v1 / Double(n1)
        let se2 = v2 / Double(n2)
        let seSum = se1 + se2
        guard seSum > 0 else {
            // No spread anywhere: identical means → p=1; differing means → p≈0.
            return m1 == m2 ? 1.0 : 0.0
        }
        let t = (m1 - m2) / seSum.squareRoot()
        // Welch–Satterthwaite degrees of freedom (fractional). A group with n=1
        // contributes no variance term (its se is 0), so the surviving group sets df.
        let d1 = n1 > 1 ? (se1 * se1) / Double(n1 - 1) : 0
        let d2 = n2 > 1 ? (se2 * se2) / Double(n2 - 1) : 0
        let denom = d1 + d2
        guard denom > 0 else { return m1 == m2 ? 1.0 : 0.0 }
        let df = (seSum * seSum) / denom
        return CorrelationEngine.studentTTwoSided(t: t, df: df)
    }

    // MARK: - Formatting helpers

    /// Round to nearest integer, returned as Int (for clean display).
    static func roundedInt(_ x: Double) -> Int { Int((x).rounded()) }

    /// Round to one decimal place.
    static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
}
