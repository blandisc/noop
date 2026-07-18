import XCTest
import CenitStore
@testable import StrandAnalytics

/// FER-709 — «las cinco reglas»: the mark rows must carry the engine's REAL weights and their lit
/// total must equal the displayed numeral exactly, including missing-signal renormalization.
final class RecoveryRulesTests: XCTestCase {

    private func impact(_ terms: [(key: String, orientedZ: Double, rawWeight: Double)]) -> RecoveryImpact.Result {
        let total = terms.reduce(0) { $0 + $1.rawWeight }
        return RecoveryImpact.Result(signals: terms.map {
            RecoveryImpact.Signal(key: $0.key, z: $0.orientedZ, orientedZ: $0.orientedZ,
                                  weight: $0.rawWeight / total)
        })
    }

    private let allFive: [(key: String, orientedZ: Double, rawWeight: Double)] = [
        ("hrv", 0.8, RecoveryScorer.wHRV),
        ("rhr", 0.3, RecoveryScorer.wRHR),
        ("sleep", -0.4, RecoveryScorer.wSleep),
        ("skinTemp", 0.1, RecoveryScorer.wTemp),
        ("respRate", -0.2, RecoveryScorer.wResp),
    ]

    // MARK: - Row lengths = real weights

    func testMarksMatchRenormalizedWeightsAllSignals() {
        let rules = RecoveryRules.rules(impact: impact(allFive), score: 74)
        XCTAssertEqual(rules.map(\.key), ["hrv", "rhr", "sleep", "skinTemp", "respRate"])
        // 0.60/0.20/0.15/0.10/0.05 over 1.10 → 54.5/18.2/13.6/9.1/4.5 of 100 marks (largest
        // remainder; hrv/resp tie at .5454… resolves by the float's last bit toward resp).
        XCTAssertEqual(rules.map(\.marks), [54, 18, 14, 9, 5])
        XCTAssertEqual(rules.map(\.marks).reduce(0, +), 100)
    }

    func testMarksRenormalizeWhenSignalsMissing() {
        // Only the three primary drivers (Apple-less temp/resp): 0.60/0.20/0.15 over 0.95.
        let rules = RecoveryRules.rules(impact: impact([
            ("hrv", 0.5, RecoveryScorer.wHRV),
            ("rhr", 0.2, RecoveryScorer.wRHR),
            ("sleep", 0.1, RecoveryScorer.wSleep),
        ]), score: 62)
        XCTAssertEqual(rules.map(\.marks), [63, 21, 16])
        XCTAssertEqual(rules.map(\.marks).reduce(0, +), 100)
    }

    // MARK: - Lit total == numeral, always

    func testLitTotalEqualsScoreExactly() {
        for score in [0, 1, 17, 42, 58, 74, 88, 99, 100] {
            let rules = RecoveryRules.rules(impact: impact(allFive), score: score)
            XCTAssertEqual(rules.map(\.lit).reduce(0, +), score, "score \(score)")
            for r in rules {
                XCTAssertGreaterThanOrEqual(r.lit, 0, "\(r.key) @ \(score)")
                XCTAssertLessThanOrEqual(r.lit, r.marks, "\(r.key) @ \(score)")
            }
        }
    }

    func testLitTotalEqualsScoreWithMissingSignals() {
        for score in [0, 25, 58, 74, 100] {
            let rules = RecoveryRules.rules(impact: impact([
                ("hrv", -1.2, RecoveryScorer.wHRV),
                ("sleep", 0.9, RecoveryScorer.wSleep),
            ]), score: score)
            XCTAssertEqual(rules.map(\.lit).reduce(0, +), score, "score \(score)")
            for r in rules { XCTAssertLessThanOrEqual(r.lit, r.marks) }
        }
    }

    func testExtremeZStillLandsOnScore() {
        // A saturated driver (huge z) must pin at its row cap and push the rest elsewhere,
        // never overshoot the numeral.
        let rules = RecoveryRules.rules(impact: impact([
            ("hrv", 8.0, RecoveryScorer.wHRV),
            ("rhr", -6.0, RecoveryScorer.wRHR),
            ("sleep", 0.0, RecoveryScorer.wSleep),
        ]), score: 91)
        XCTAssertEqual(rules.map(\.lit).reduce(0, +), 91)
        for r in rules { XCTAssertLessThanOrEqual(r.lit, r.marks) }
    }

    func testScoreEdgesFillNothingOrEverything() {
        let zero = RecoveryRules.rules(impact: impact(allFive), score: 0)
        XCTAssertTrue(zero.allSatisfy { $0.lit == 0 })
        let full = RecoveryRules.rules(impact: impact(allFive), score: 100)
        XCTAssertTrue(full.allSatisfy { $0.lit == $0.marks })
    }

    func testScoreClampsOutOfRange() {
        XCTAssertEqual(RecoveryRules.rules(impact: impact(allFive), score: 140).map(\.lit).reduce(0, +), 100)
        XCTAssertEqual(RecoveryRules.rules(impact: impact(allFive), score: -5).map(\.lit).reduce(0, +), 0)
    }

    func testEmptyImpactYieldsNoRules() {
        XCTAssertTrue(RecoveryRules.rules(impact: RecoveryImpact.Result(signals: []), score: 74).isEmpty)
    }

    // MARK: - Reglas × banners: el numeral == la suma visible en TODOS los estados (FER-711)

    /// F3's core invariant for «reglas × banners»: the five-rules graph always squares with the
    /// numeral. The banners F3 ships (batería crítica, banda desconectada, base envejecida) are
    /// PRESENTATIONAL — they never touch the recovery decomposition — so for every displayed numeral,
    /// across full and missing-signal impacts, Σ lit must still equal the numeral EXACTLY. (The one
    /// banner that would move the numeral, «siesta», is deferred to its own /pm issue precisely
    /// because it needs new detection + a re-score; when it lands, this same invariant must hold on
    /// its re-scored numeral.)
    func testNumeralEqualsVisibleSumAcrossStates() {
        // Numerals representative of the verdict states the screen can show (low/strained → high/primed,
        // plus the calibrating/estimated edges where a numeral is present).
        let stateScores = [12, 28, 45, 58, 71, 74, 82, 91, 96]
        let impacts: [RecoveryImpact.Result] = [
            impact(allFive),                                        // full band night
            impact(Array(allFive.prefix(3))),                       // HRV+RHR+Sleep only (Apple-less)
            impact([("hrv", -1.4, RecoveryScorer.wHRV),             // an estimated-ish two-signal day
                    ("sleep", 0.6, RecoveryScorer.wSleep)]),
        ]
        for imp in impacts {
            for score in stateScores {
                let rules = RecoveryRules.rules(impact: imp, score: score)
                XCTAssertEqual(rules.map(\.lit).reduce(0, +), score, "score \(score)")
                XCTAssertEqual(rules.map(\.marks).reduce(0, +), 100, "marks @ \(score)")
                for r in rules { XCTAssertLessThanOrEqual(r.lit, r.marks) }
            }
        }
    }

    // MARK: - Integration with the real decomposition

    func testRealImpactDecompositionSumsToScore() {
        // Synthetic band history: 20 stable nights, then a today row; the impact and the score
        // come from the same engines the app uses.
        var days: [DailyMetric] = []
        for i in 0..<20 {
            days.append(DailyMetric(
                day: String(format: "2026-06-%02d", i + 1), totalSleepMin: 420,
                efficiency: 0.88, deepMin: 90, remMin: 100, lightMin: 230, disturbances: 3,
                restingHr: 50, avgHrv: 60 + Double(i % 5), recovery: nil, strain: 8,
                exerciseCount: 0, spo2Pct: 97, skinTempDevC: 0.0, respRateBpm: 14.0))
        }
        days.append(DailyMetric(
            day: "2026-06-21", totalSleepMin: 400, efficiency: 0.85, deepMin: 85, remMin: 95,
            lightMin: 220, disturbances: 4, restingHr: 48, avgHrv: 70, recovery: nil,
            strain: 8, exerciseCount: 0, spo2Pct: 97, skinTempDevC: 0.1, respRateBpm: 14.2))

        guard let impact = RecoveryImpact.compute(days: days, todayKey: "2026-06-21") else {
            return XCTFail("expected a decomposition")
        }
        // Whatever numeral the screen would show, the rules must sum to it.
        for score in [34, 58, 71, 86] {
            let rules = RecoveryRules.rules(impact: impact, score: score)
            XCTAssertEqual(rules.map(\.lit).reduce(0, +), score)
            XCTAssertEqual(rules.map(\.marks).reduce(0, +), 100)
        }
    }
}
