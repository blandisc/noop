import XCTest
@testable import StrandAnalytics

final class ExperimentVerdictTests: XCTestCase {

    private func day(_ i: Int) -> String { String(format: "2026-06-%02d", i) }

    // MARK: - Planted effect → sustained

    /// A clean planted effect: 40 baseline days at ~60 and 8 adherent days at ~75. The lever raises
    /// the outcome (positive delta), the candidate expected +1, and the gap is well separated → the
    /// verdict reproduces it as `.sustained`.
    func testPlantedEffectIsSustained() {
        var outcomeByDay: [String: Double] = [:]
        var adherent: Set<String> = []
        // Baseline: days 1–40, alternating 58/62 (mean 60, real spread).
        for i in 1...40 { outcomeByDay[day(i)] = (i % 2 == 0) ? 62 : 58 }
        // Adherent window: days 41–48, alternating 73/77 (mean 75).
        for i in 41...48 {
            let d = day(i); outcomeByDay[d] = (i % 2 == 0) ? 77 : 73; adherent.insert(d)
        }

        let res = ExperimentVerdict.evaluate(behavior: "Meditación", outcome: "Recuperación",
                                             expectedSign: 1, adherentDays: adherent,
                                             outcomeByDay: outcomeByDay)
        XCTAssertEqual(res.verdict, .sustained)
        XCTAssertNotNil(res.effect)
        XCTAssertGreaterThan(res.effect!.delta, 0)
        XCTAssertTrue(res.effect!.significant)
    }

    /// Same planted (positive) effect, but the candidate expected the lever to LOWER the outcome
    /// (expectedSign −1). The effect is significant but in the wrong direction → not a reproduction.
    func testSignificantButOppositeDirectionIsNotSustained() {
        var outcomeByDay: [String: Double] = [:]
        var adherent: Set<String> = []
        for i in 1...40 { outcomeByDay[day(i)] = (i % 2 == 0) ? 62 : 58 }
        for i in 41...48 {
            let d = day(i); outcomeByDay[d] = (i % 2 == 0) ? 77 : 73; adherent.insert(d)
        }
        let res = ExperimentVerdict.evaluate(behavior: "Meditación", outcome: "Recuperación",
                                             expectedSign: -1, adherentDays: adherent,
                                             outcomeByDay: outcomeByDay)
        XCTAssertEqual(res.verdict, .notSustained)
    }

    // MARK: - Noise → not sustained

    /// No real effect: adherent days are drawn from the same distribution as baseline. A deterministic
    /// pseudo-random sequence keeps both groups centered on the same mean → no significance.
    func testNoiseIsNotSustained() {
        var outcomeByDay: [String: Double] = [:]
        var adherent: Set<String> = []
        // Deterministic LCG so the test is reproducible without Math.random.
        var seed: UInt64 = 12345
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 1000) / 1000.0   // [0,1)
        }
        for i in 1...48 {
            let d = day(i)
            outcomeByDay[d] = 60 + (next() - 0.5) * 10      // 55–65, same dist for all
            if i >= 41 { adherent.insert(d) }
        }
        let res = ExperimentVerdict.evaluate(behavior: "Café", outcome: "Recuperación",
                                             expectedSign: 1, adherentDays: adherent,
                                             outcomeByDay: outcomeByDay)
        XCTAssertEqual(res.verdict, .notSustained)
        XCTAssertFalse(res.effect?.significant ?? true)
    }

    // MARK: - Low adherence → insufficient

    /// Fewer than `minAdherentDays` adherent days → `.insufficient` regardless of the data, with no
    /// effect computed.
    func testLowAdherenceIsInsufficient() {
        var outcomeByDay: [String: Double] = [:]
        for i in 1...40 { outcomeByDay[day(i)] = 60 }
        // Only 3 adherent days (below the floor of 5), even with a huge gap.
        var adherent: Set<String> = []
        for i in 41...43 { let d = day(i); outcomeByDay[d] = 90; adherent.insert(d) }

        XCTAssertLessThan(adherent.count, ExperimentVerdict.minAdherentDays)
        let res = ExperimentVerdict.evaluate(behavior: "Siesta", outcome: "Recuperación",
                                             expectedSign: 1, adherentDays: adherent,
                                             outcomeByDay: outcomeByDay)
        XCTAssertEqual(res.verdict, .insufficient)
        XCTAssertNil(res.effect)
    }

    /// Enough adherent days but no outcome overlap (the baseline side is empty) → no computable
    /// effect → `.insufficient`.
    func testNoComputableEffectIsInsufficient() {
        var outcomeByDay: [String: Double] = [:]
        var adherent: Set<String> = []
        // Every day with an outcome is adherent ⇒ the "without" group is empty.
        for i in 41...48 { let d = day(i); outcomeByDay[d] = 70; adherent.insert(d) }
        let res = ExperimentVerdict.evaluate(behavior: "Siesta", outcome: "Recuperación",
                                             expectedSign: 1, adherentDays: adherent,
                                             outcomeByDay: outcomeByDay)
        XCTAssertEqual(res.verdict, .insufficient)
        XCTAssertNil(res.effect)
    }
}
