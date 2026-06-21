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

    // FER-330: the guard protects the user's OWN metrics, not normal coaching numbers.
    func testValidateAllowsGeneralAdviceNumbers() {
        let ins = [insight(.trend, reading: "Recuperación 70%.", value: 70, unit: "%",
                           metric: "Recuperación", relevance: 1)]
        let g = CoachGrounding.from(insights: ins, readiness: nil, recovery: 70, referenceDay: "d")
        // Sleep-hour ranges, zones, intensity splits carry no user-metric unit → never flagged.
        XCTAssertTrue(g.validate(answer: "Procura dormir entre 7 y 9 horas, en zona 2, con 80/20.").isEmpty)
    }

    func testValidateStillFlagsFabricatedMetricUnit() {
        let ins = [insight(.trend, reading: "Tu HRV es 65 ms.", value: 65, unit: "ms",
                           metric: "HRV", relevance: 1)]
        let g = CoachGrounding.from(insights: ins, readiness: nil, recovery: nil, referenceDay: "d")
        XCTAssertEqual(g.validate(answer: "Tu HRV es 80 ms, excelente."), ["80"])
        XCTAssertTrue(g.validate(answer: "Tu HRV es 65 ms, excelente.").isEmpty)
    }

    // FER-331: seeded conversation.
    func testOpenerLeadsWithTopFact() {
        let ins = [insight(.sleepRegularity, reading: "Tu sueño llegó 1.4 h más tarde de lo normal.",
                           value: 1.4, unit: "h", metric: "Sueño", relevance: 5)]
        let g = CoachGrounding.from(insights: ins, readiness: nil, recovery: 60, referenceDay: "d")
        XCTAssertTrue(g.opener().contains("1.4 h más tarde"))
    }

    func testOpenerColdStartInvitesSync() {
        // Source language is English; without the app catalog (test bundle) the localized
        // cold-start opener resolves to its English source ("…sync your strap…").
        let g = CoachGrounding.from(insights: [], readiness: nil, recovery: nil, referenceDay: "d")
        XCTAssertTrue(g.opener().localizedCaseInsensitiveContains("sync"))
    }

    func testSuggestedChipsLeadWithStandoutTopic() {
        let sleepLed = [insight(.sleepRegularity, reading: "s", value: 1, unit: "h", metric: "Sueño", relevance: 9)]
        let g = CoachGrounding.from(insights: sleepLed, readiness: nil, recovery: 70, referenceDay: "d")
        let chips = g.suggestedChips()
        XCTAssertEqual(chips.count, 3)
        XCTAssertEqual(chips.first, .sleep)            // standout leads
        XCTAssertEqual(Set(chips).count, 3)            // no duplicates
    }

    func testFollowUpsNeverRepeatAsked() {
        let g = CoachGrounding.from(insights: [], readiness: nil, recovery: 70, referenceDay: "d")
        let ups = g.followUpChips(after: .today)
        XCTAssertEqual(ups.count, 2)
        XCTAssertFalse(ups.contains(.today))
    }

    // FER-332: query-aware retrieval + topic classification.
    func testTopicClassifierMapsSpanishQuestions() {
        XCTAssertEqual(CoachTopic.classify("¿cuánto debería dormir?"), .sleep)
        XCTAssertEqual(CoachTopic.classify("¿por qué amanecí cansado?"), .recovery)
        XCTAssertEqual(CoachTopic.classify("¿cómo viene mi recuperación?"), .recovery)
        XCTAssertEqual(CoachTopic.classify("¿me afecta el alcohol?"), .behavior)
        XCTAssertEqual(CoachTopic.classify("¿cómo está mi HRV?"), .hrv)
        XCTAssertEqual(CoachTopic.classify("¿traigo mucha carga?"), .load)
        XCTAssertEqual(CoachTopic.classify("hola"), .general)
    }

    func testFactsForTopicAreFocused() {
        let mixed = [
            insight(.sleepRegularity, reading: "Sueño tarde.", value: 1, unit: "h", metric: "Sueño", relevance: 5),
            insight(.behavior, reading: "Alcohol baja recuperación.", value: 8, unit: "pts", metric: "Recuperación", relevance: 4),
        ]
        let g = CoachGrounding.from(insights: mixed, readiness: nil, recovery: 70, referenceDay: "d")
        XCTAssertEqual(g.facts(for: .sleep).count, 1)
        XCTAssertEqual(g.facts(for: .sleep).first?.kind, .sleepRegularity)
        XCTAssertEqual(g.facts(for: .behavior).first?.kind, .behavior)
    }

    func testDeterministicAnswerByTopicIsOnTopic() {
        let mixed = [
            insight(.sleepRegularity, reading: "Tu sueño llegó 1.4 h más tarde de lo normal.",
                    value: 1.4, unit: "h", metric: "Sueño", relevance: 5),
        ]
        let g = CoachGrounding.from(insights: mixed, readiness: nil, recovery: 56, referenceDay: "d")
        let sleepAns = g.deterministicAnswer(forTopic: .sleep)
        XCTAssertTrue(sleepAns.contains("1.4 h más tarde"))
        XCTAssertFalse(sleepAns.contains("56"))        // a sleep question doesn't lead with recovery
        // chip delegates to topic
        XCTAssertEqual(g.deterministicAnswer(forChip: .sleep), sleepAns)
    }

    // FER-333: grounded what-if + confidence caveat.
    private func behaviorInsight(_ behavior: String, outcome: String, meanWith: Double,
                                 meanWithout: Double, n: Int) -> Insight {
        Insight(kind: .behavior, title: "t", reading: "\(behavior) y \(outcome)",
                datum: InsightDatum(value: meanWith - meanWithout, unit: "pts", metric: outcome),
                evidence: InsightEvidence(n: n, pValue: 0.01, pAdjusted: 0.02, effectSize: 0.5, significant: true),
                confidence: .candidate, relevance: 5,
                lever: Lever(behavior: behavior, outcome: outcome),
                behaviorBreakdown: BehaviorBreakdown(meanWith: meanWith, meanWithout: meanWithout,
                                                     nWith: n / 2, nWithout: n - n / 2))
    }

    func testWhatIfReturnsHistoricalContrast() {
        let g = CoachGrounding.from(insights: [behaviorInsight("Alcohol", outcome: "Recuperación",
                                                               meanWith: 63, meanWithout: 71, n: 24)],
                                    readiness: nil, recovery: nil, referenceDay: "d")
        let wi = g.whatIf("¿y si dejo el alcohol?")
        XCTAssertNotNil(wi)
        XCTAssertEqual(wi?.behavior, "Alcohol")
        XCTAssertEqual(wi?.outcome, "Recuperación")
        XCTAssertEqual(wi?.expectedSign, -1)            // with(63) < without(71) → keeping it hurts
        XCTAssertTrue(wi?.statement.contains("63") ?? false)
        XCTAssertTrue(wi?.statement.contains("71") ?? false)
    }

    func testWhatIfRespectsLowerIsBetterMetric() {
        // FER fix: for "FC en reposo" (lower is better), a behavior linked to a HIGHER resting HR is
        // WORSE, so the verdict must advise dropping it — not "keeping it helps". expectedSign stays the
        // raw-delta direction (+1); it only drives the experiment's reproduction check, not good/bad.
        let g = CoachGrounding.from(insights: [behaviorInsight("Alcohol", outcome: "FC en reposo",
                                                               meanWith: 58, meanWithout: 54, n: 24)],
                                    readiness: nil, recovery: nil, referenceDay: "d")
        let wi = g.whatIf("¿y si dejo el alcohol?")
        XCTAssertNotNil(wi)
        XCTAssertEqual(wi?.outcome, "FC en reposo")
        XCTAssertEqual(wi?.expectedSign, 1)   // raw delta +4 → reproduction sign, unchanged by direction
        XCTAssertTrue(wi?.statement.contains("Dropping it could help you") ?? false,
                      "higher resting HR is worse → advise dropping, not keeping")
        XCTAssertFalse(wi?.statement.contains("Keeping it seems to help you") ?? true)
    }

    func testWhatIfNilWhenNotAWhatIf() {
        let g = CoachGrounding.from(insights: [behaviorInsight("Alcohol", outcome: "Recuperación",
                                                               meanWith: 63, meanWithout: 71, n: 24)],
                                    readiness: nil, recovery: nil, referenceDay: "d")
        XCTAssertNil(g.whatIf("¿cómo viene mi recuperación?"))
    }

    func testWhatIfNilWhenBehaviorNotKnown() {
        let g = CoachGrounding.from(insights: [behaviorInsight("Alcohol", outcome: "Recuperación",
                                                               meanWith: 63, meanWithout: 71, n: 24)],
                                    readiness: nil, recovery: nil, referenceDay: "d")
        XCTAssertNil(g.whatIf("¿y si dejo el azúcar?"))   // no azúcar lever → honest nil
    }

    func testConfidenceCaveatHedgesWhenThin() {
        // English source in the test bundle: "With just 5 days, take it as a hint, not certainty."
        XCTAssertTrue(CoachGrounding.confidenceCaveat(n: 5)?.localizedCaseInsensitiveContains("hint") ?? false)
        XCTAssertNil(CoachGrounding.confidenceCaveat(n: 25))
    }

    func testMetricNumbersOnlyCatchesUnitedNumbers() {
        let found = CoachGrounding.metricNumbers(in: "91% y 80 ms, pero 9 horas y 80/20")
        XCTAssertEqual(found, ["91", "80"])
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
