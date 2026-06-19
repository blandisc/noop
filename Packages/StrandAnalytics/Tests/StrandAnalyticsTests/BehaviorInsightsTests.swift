import XCTest
@testable import StrandAnalytics

final class BehaviorInsightsTests: XCTestCase {

    // MARK: - effect core computation

    func testEffectMeansDeltaAndSign() {
        // With-days outcome mean 60.5, without-days mean 70.125 → delta -9.625,
        // pct ≈ -13.7255%. Behavior lowers the outcome → negative delta & cohensD.
        let outcome: [String: Double] = [
            "d01": 60, "d02": 62, "d03": 58, "d04": 61, "d05": 59, "d06": 63,   // with
            "d07": 70, "d08": 72, "d09": 68, "d10": 71, "d11": 69, "d12": 73,   // without
            "d13": 70, "d14": 68,
        ]
        let behaviorDays: Set<String> = ["d01", "d02", "d03", "d04", "d05", "d06"]
        let e = BehaviorInsights.effect(behaviorDays: behaviorDays, outcomeByDay: outcome,
                                        behavior: "Alcohol", outcome: "Recovery")!
        XCTAssertEqual(e.nWith, 6)
        XCTAssertEqual(e.nWithout, 8)
        XCTAssertEqual(e.meanWith, 60.5, accuracy: 1e-9)
        XCTAssertEqual(e.meanWithout, 70.125, accuracy: 1e-9)
        XCTAssertEqual(e.delta, -9.625, accuracy: 1e-9)
        XCTAssertEqual(e.pctChange!, -13.725490196078432, accuracy: 1e-9)
        XCTAssertLessThan(e.cohensD, 0)                  // lower outcome → negative
        XCTAssertEqual(e.cohensD, -5.247290322400142, accuracy: 1e-6)
        XCTAssertTrue(e.significant)                     // big separation, n≥5 both sides
    }

    func testEffectPositiveDirection() {
        // Behavior RAISES the outcome → positive delta.
        let outcome: [String: Double] = [
            "a": 80, "b": 82, "c": 78, "d": 81, "e": 79,   // with (mean 80)
            "f": 70, "g": 72, "h": 68, "i": 71, "j": 69,   // without (mean 70)
        ]
        let e = BehaviorInsights.effect(behaviorDays: ["a", "b", "c", "d", "e"],
                                        outcomeByDay: outcome,
                                        behavior: "Meditation", outcome: "Recovery")!
        XCTAssertEqual(e.delta, 10.0, accuracy: 1e-9)
        XCTAssertGreaterThan(e.cohensD, 0)
        XCTAssertEqual(e.pctChange!, 100.0 * 10.0 / 70.0, accuracy: 1e-9)
        XCTAssertTrue(e.significant)
    }

    func testEffectNilWhenOneGroupEmpty() {
        // Behavior logged every day → no "without" group.
        let outcome: [String: Double] = ["a": 60, "b": 61, "c": 62]
        XCTAssertNil(BehaviorInsights.effect(behaviorDays: ["a", "b", "c"],
                                             outcomeByDay: outcome,
                                             behavior: "X", outcome: "Recovery"))
        // Behavior never logged → no "with" group.
        XCTAssertNil(BehaviorInsights.effect(behaviorDays: [],
                                             outcomeByDay: outcome,
                                             behavior: "X", outcome: "Recovery"))
    }

    func testEffectIgnoresBehaviorDaysWithNoOutcome() {
        // "z" is in behaviorDays but has no outcome value → not counted in nWith.
        let outcome: [String: Double] = ["a": 60, "b": 62, "c": 70, "d": 72]
        let e = BehaviorInsights.effect(behaviorDays: ["a", "b", "z"],
                                        outcomeByDay: outcome,
                                        behavior: "X", outcome: "Recovery")!
        XCTAssertEqual(e.nWith, 2)        // a, b only
        XCTAssertEqual(e.nWithout, 2)     // c, d
    }

    // MARK: - significance flips

    func testSignificanceFlipsWithGroupSize() {
        // SAME clear separation (≈60 vs ≈70), but only 4 days per group → even
        // with a tiny p-value the min-group guard (≥5) blocks significance.
        let smallOutcome: [String: Double] = [
            "w1": 60, "w2": 61, "w3": 59, "w4": 60,
            "o1": 70, "o2": 71, "o3": 69, "o4": 70,
        ]
        let small = BehaviorInsights.effect(behaviorDays: ["w1", "w2", "w3", "w4"],
                                            outcomeByDay: smallOutcome,
                                            behavior: "X", outcome: "Recovery")!
        XCTAssertLessThan(small.pApprox, 0.05)       // strong evidence numerically…
        XCTAssertEqual(Swift.min(small.nWith, small.nWithout), 4)
        XCTAssertFalse(small.significant)            // …but n too small → not flagged

        // Add a 5th day per group with the same separation → now significant.
        let bigOutcome: [String: Double] = [
            "w1": 60, "w2": 61, "w3": 59, "w4": 60, "w5": 60,
            "o1": 70, "o2": 71, "o3": 69, "o4": 70, "o5": 70,
        ]
        let big = BehaviorInsights.effect(behaviorDays: ["w1", "w2", "w3", "w4", "w5"],
                                          outcomeByDay: bigOutcome,
                                          behavior: "X", outcome: "Recovery")!
        XCTAssertEqual(Swift.min(big.nWith, big.nWithout), 5)
        XCTAssertTrue(big.significant)
    }

    func testSignificanceFlipsWithSeparation() {
        // Big groups but NO real separation (heavily overlapping) → not significant.
        let outcome: [String: Double] = [
            "w1": 65, "w2": 71, "w3": 60, "w4": 75, "w5": 66, "w6": 70,
            "o1": 64, "o2": 72, "o3": 61, "o4": 74, "o5": 67, "o6": 69,
        ]
        let e = BehaviorInsights.effect(behaviorDays: ["w1", "w2", "w3", "w4", "w5", "w6"],
                                        outcomeByDay: outcome,
                                        behavior: "X", outcome: "Recovery")!
        XCTAssertGreaterThan(e.pApprox, 0.05)    // no separation → weak evidence
        XCTAssertFalse(e.significant)
    }

    // MARK: - ranking

    func testRankOrdersByEffectSizeSignificantFirst() {
        // Three behaviors over a shared outcome series of 12 days.
        let outcome: [String: Double] = [
            "d1": 50, "d2": 52, "d3": 48, "d4": 51, "d5": 49, "d6": 53,
            "d7": 70, "d8": 72, "d9": 68, "d10": 71, "d11": 69, "d12": 73,
        ]
        // Strong: cleanly splits the low half (d1..d6) vs high half → big |d|, significant.
        let strong: Set<String> = ["d1", "d2", "d3", "d4", "d5", "d6"]
        // Weak: a scattered 3-day set, small + not enough per-group for significance.
        let weak: Set<String> = ["d1", "d7", "d2"]
        // Tiny-but-significant-impossible: 2 days only.
        let tiny: Set<String> = ["d3", "d9"]

        let ranked = BehaviorInsights.rank(behaviors: ["Strong": strong, "Weak": weak, "Tiny": tiny],
                                           outcomeByDay: outcome, outcome: "Recovery")
        XCTAssertEqual(ranked.count, 3)
        XCTAssertEqual(ranked.first?.behavior, "Strong")   // significant + largest |d|
        XCTAssertTrue(ranked.first!.significant)
        // Non-significant entries trail the significant one.
        XCTAssertFalse(ranked[1].significant)
        XCTAssertFalse(ranked[2].significant)
        // Among the non-significant, larger |cohensD| comes first.
        XCTAssertGreaterThanOrEqual(abs(ranked[1].cohensD), abs(ranked[2].cohensD))
    }

    func testRankDropsUncomputableBehaviors() {
        let outcome: [String: Double] = ["a": 60, "b": 62, "c": 70, "d": 72]
        // "AllDays" covers every day → no without group → dropped.
        let ranked = BehaviorInsights.rank(behaviors: [
            "AllDays": ["a", "b", "c", "d"],
            "Half": ["a", "b"],
        ], outcomeByDay: outcome, outcome: "Recovery")
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.behavior, "Half")
    }

    // MARK: - Welch p-value (exact Student-t at the Welch df)

    func testWelchPUsesStudentTAtWelchDf() {
        // with=[60,62,58] (m=60, v=4), without=[70,72,68] (m=70, v=4). Equal groups
        // → Welch df = 4, t = −6.1237. Cross-checked vs SciPy
        // ttest_ind(equal_var=False) → p ≈ 0.0036022. The old normal tail returned a
        // much smaller p here (it ignored the df the header always documented).
        let p = BehaviorInsights.welchP(m1: 60, v1: 4, n1: 3, m2: 70, v2: 4, n2: 3)
        XCTAssertEqual(p, 0.0036022326091, accuracy: 1e-9)
    }

    func testWelchPNoSpreadEdgeCases() {
        // No variance anywhere: identical means → p = 1; differing means → p = 0.
        XCTAssertEqual(BehaviorInsights.welchP(m1: 5, v1: 0, n1: 4, m2: 5, v2: 0, n2: 4), 1.0)
        XCTAssertEqual(BehaviorInsights.welchP(m1: 5, v1: 0, n1: 4, m2: 9, v2: 0, n2: 4), 0.0)
    }

    // MARK: - multiple-comparisons (FDR) correction in rank

    func testRankAppliesFDRSoSignificanceDependsOnFamilySize() {
        // ‘B’ separates the outcome modestly: single-test p ≈ 0.022 (< 0.05), n≥5
        // both sides — significant when tested ALONE.
        let outcome: [String: Double] = [
            "b1": 66, "b2": 71, "b3": 64, "b4": 70, "b5": 67,                       // with B
            "x1": 72, "x2": 74, "x3": 70, "x4": 73, "x5": 71,
            "x6": 75, "x7": 69, "x8": 72, "x9": 74, "x10": 70,                       // without
        ]
        let B = Set(["b1", "b2", "b3", "b4", "b5"])

        let alone = BehaviorInsights.rank(behaviors: ["B": B], outcomeByDay: outcome, outcome: "Rec")
        XCTAssertLessThan(alone[0].pApprox, 0.05)
        XCTAssertTrue(alone[0].significant, "a single test with p<0.05 and n≥5 is significant alone")

        // Same ‘B’, but now ranked inside a family of 10 simultaneous behaviour tests.
        // Benjamini-Hochberg raises the bar → the SAME effect no longer clears it.
        let all = Array(outcome.keys).sorted()
        var family: [String: Set<String>] = ["B": B]
        for k in 0..<9 {
            family["N\(k)"] = Set((0..<7).map { all[(k * 5 + $0 * 2) % all.count] })
        }
        let ranked = BehaviorInsights.rank(behaviors: family, outcomeByDay: outcome, outcome: "Rec")
        let bInFamily = ranked.first { $0.behavior == "B" }!
        XCTAssertEqual(bInFamily.pApprox, alone[0].pApprox, accuracy: 1e-12)   // same raw p…
        XCTAssertFalse(bInFamily.significant, "…but FDR over the family demotes it")

        // The displayed `significant` matches a hand-applied Benjamini-Hochberg on the
        // raw p-values (proving rank corrects, not single-tests).
        let q = MultipleComparisons.benjaminiHochberg(ranked.map(\.pApprox))
        for (e, qVal) in zip(ranked, q) {
            let expected = qVal < BehaviorInsights.alpha
                && Swift.min(e.nWith, e.nWithout) >= BehaviorInsights.minGroupForSignificance
            XCTAssertEqual(e.significant, expected, "‘\(e.behavior)’ significance must equal its FDR verdict")
        }
    }

    // MARK: - sentence

    func testSentenceLowerWithPercent() {
        // Integer means avoid half-rounding ambiguity: with=60, without=80 →
        // delta -20, pct -25% → "25% lower (avg 60 vs 80, n=5 vs 5)".
        let outcome: [String: Double] = [
            "w1": 58, "w2": 62, "w3": 60, "w4": 59, "w5": 61,   // mean 60
            "o1": 78, "o2": 82, "o3": 80, "o4": 79, "o5": 81,   // mean 80
        ]
        let e = BehaviorInsights.effect(behaviorDays: ["w1", "w2", "w3", "w4", "w5"],
                                        outcomeByDay: outcome,
                                        behavior: "Alcohol", outcome: "Recovery")!
        let s = BehaviorInsights.sentence(e)
        XCTAssertEqual(s, "On days you logged ‘Alcohol’, Recovery was 25% lower (avg 60 vs 80, n=5 vs 5).")
    }

    func testSentenceHigherWithPercent() {
        let outcome: [String: Double] = [
            "w1": 79, "w2": 81, "w3": 80,    // mean 80
            "o1": 49, "o2": 51, "o3": 50,    // mean 50
        ]
        let e = BehaviorInsights.effect(behaviorDays: ["w1", "w2", "w3"],
                                        outcomeByDay: outcome,
                                        behavior: "Meditation", outcome: "Recovery")!
        let s = BehaviorInsights.sentence(e)
        // delta +30, pct +60% → "60% higher (avg 80 vs 50, n=3 vs 3)".
        XCTAssertEqual(s, "On days you logged ‘Meditation’, Recovery was 60% higher (avg 80 vs 50, n=3 vs 3).")
    }

    func testSentenceFallsBackToUnitsWhenPctUndefined() {
        // meanWithout 0 → pctChange nil → sentence uses absolute units.
        let outcome: [String: Double] = [
            "w1": 5, "w2": 5, "w3": 5,
            "o1": 0, "o2": 0, "o3": 0,
        ]
        let e = BehaviorInsights.effect(behaviorDays: ["w1", "w2", "w3"],
                                        outcomeByDay: outcome,
                                        behavior: "X", outcome: "HRV")!
        XCTAssertNil(e.pctChange)
        let s = BehaviorInsights.sentence(e)
        XCTAssertEqual(s, "On days you logged ‘X’, HRV was 5.0 higher (avg 5 vs 0, n=3 vs 3).")
    }
}
