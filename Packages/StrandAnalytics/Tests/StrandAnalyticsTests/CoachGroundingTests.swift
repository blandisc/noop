import XCTest
@testable import StrandAnalytics

/// FER-308 — the pure grounding layer behind "Pregúntale a tus datos". These run with no app,
/// strap, or device: they prove the determinism and the testable half of the golden rule
/// ("the model never produces a figure that didn't come from the engine").
final class CoachGroundingTests: XCTestCase {

    // MARK: Fixtures

    private func insight(_ kind: InsightKind, reading: String, value: Double, unit: String,
                         metric: String, relevance: Double, n: Int = 30, significant: Bool = true,
                         confidence: InsightConfidence = .candidate) -> Insight {
        Insight(kind: kind, title: "t", reading: reading,
                datum: InsightDatum(value: value, unit: unit, metric: metric),
                evidence: InsightEvidence(n: n, pValue: 0.01, pAdjusted: 0.02, effectSize: 0.5,
                                          significant: significant),
                confidence: confidence, relevance: relevance,
                lever: kind == .behavior ? Lever(behavior: "X", outcome: metric) : nil)
    }

    // MARK: Determinism + ranking + cap

    func testDeterministic() {
        let ins = [insight(.trend, reading: "Recuperación subiendo 5 pts.", value: 5, unit: "pts",
                           metric: "Recuperación", relevance: 2)]
        let a = CoachGrounding.from(insights: ins, readiness: nil, recovery: 70, referenceDay: "2026-06-19")
        let b = CoachGrounding.from(insights: ins, readiness: nil, recovery: 70, referenceDay: "2026-06-19")
        XCTAssertEqual(a, b)
    }

    func testCapsAtMaxFactsRankedByRelevance() {
        let many = (0..<20).map {
            insight(.trend, reading: "h\($0)", value: Double($0), unit: "pts", metric: "M",
                    relevance: Double($0))
        }
        let g = CoachGrounding.from(insights: many, readiness: nil, recovery: nil, referenceDay: "d")
        XCTAssertEqual(g.facts.count, CoachGrounding.maxFacts)
        // Highest relevance first; the top fact is relevance 19.
        XCTAssertEqual(g.facts.first?.figure, 19)
        XCTAssertEqual(g.facts.first?.id, 0)
        // The lowest-ranked retained fact is relevance 8 (20 - 12).
        XCTAssertEqual(g.facts.last?.figure, 8)
    }

    // MARK: allowedNumbers

    func testAllowedNumbersCoversEngineFiguresAndRecovery() {
        let ins = [insight(.trend, reading: "Tu HRV subió a 65 ms.", value: 65, unit: "ms",
                           metric: "HRV", relevance: 1)]
        let g = CoachGrounding.from(insights: ins, readiness: nil, recovery: 72, referenceDay: "d")
        XCTAssertTrue(g.allowedNumbers.contains("65"))
        XCTAssertTrue(g.allowedNumbers.contains("72"))
    }

    // MARK: Golden rule — Level 1 only restates engine numbers

    func testDeterministicAnswerOnlyUsesEngineNumbers() {
        let ins = [insight(.behavior, reading: "Con meditación tu recuperación sube 8 pts.", value: 8,
                           unit: "pts", metric: "Recuperación", relevance: 3)]
        let g = CoachGrounding.from(insights: ins, readiness: nil, recovery: nil, referenceDay: "d")
        let answer = g.deterministicAnswer(forChip: .whatWorks)
        // Every numeric token in the Level-1 answer must be an allowed (engine) number.
        XCTAssertTrue(g.validate(answer: answer).isEmpty, "Level-1 answer must never invent a figure")
        XCTAssertTrue(answer.contains("8"))
    }

    // MARK: validate guard

    func testValidateFlagsFabricatedFigure() {
        let ins = [insight(.trend, reading: "Recuperación 70%.", value: 70, unit: "%",
                           metric: "Recuperación", relevance: 1)]
        let g = CoachGrounding.from(insights: ins, readiness: nil, recovery: 70, referenceDay: "d")
        // 91 never came from the engine → must be flagged.
        let bad = g.validate(answer: "Tu recuperación es 91% hoy.")
        XCTAssertEqual(bad, ["91"])
    }

    func testValidatePassesEngineOnlyAnswer() {
        let ins = [insight(.trend, reading: "Recuperación 70%.", value: 70, unit: "%",
                           metric: "Recuperación", relevance: 1)]
        let g = CoachGrounding.from(insights: ins, readiness: nil, recovery: 70, referenceDay: "d")
        XCTAssertTrue(g.validate(answer: "Vas en 70%, sigue así.").isEmpty)
    }

    func testValidateToleratesStructuralSmallInts() {
        let g = CoachGrounding.from(insights: [], readiness: nil, recovery: nil, referenceDay: "d")
        XCTAssertTrue(g.validate(answer: "Te doy 2 ideas: 1 sobre sueño.").isEmpty)
    }

    // MARK: Cold start

    func testColdStartProducesValidGroundingAndChipFallbacks() {
        let g = CoachGrounding.from(insights: [], readiness: nil, recovery: nil, referenceDay: "d")
        XCTAssertTrue(g.facts.isEmpty)
        for chip in CoachChip.allCases {
            let ans = g.deterministicAnswer(forChip: chip)
            XCTAssertFalse(ans.isEmpty, "every chip must degrade to a non-empty message")
        }
        XCTAssertTrue(g.toolContextString().contains("Aún no hay hallazgos"))
    }

    // MARK: Number extraction edge cases

    func testNumberFormsAndExtraction() {
        XCTAssertEqual(CoachGrounding.normalize("7.0"), "7")
        XCTAssertEqual(CoachGrounding.normalize("6,5"), "6.5")
        XCTAssertEqual(CoachGrounding.extractNumbers(from: "sube 6.5 h y baja 3."), ["6.5", "3"])
        XCTAssertTrue(CoachGrounding.numberForms(6.5).contains("6.5"))
    }
}
