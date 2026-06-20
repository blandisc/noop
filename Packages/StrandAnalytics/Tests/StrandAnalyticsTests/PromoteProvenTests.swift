import XCTest
@testable import StrandAnalytics

final class PromoteProvenTests: XCTestCase {

    private func behaviorInsight(behavior: String, outcome: String,
                                 confidence: InsightConfidence) -> Insight {
        Insight(kind: .behavior, title: "\(behavior) y \(outcome)", reading: "…",
                datum: InsightDatum(value: 5, unit: "pts", metric: outcome),
                evidence: InsightEvidence(n: 40, pValue: 0.01, pAdjusted: 0.02,
                                          effectSize: 0.5, significant: confidence == .candidate),
                confidence: confidence, relevance: 3.0,
                lever: Lever(behavior: behavior, outcome: outcome))
    }

    func testPromotesMatchingCandidate() {
        let candidate = behaviorInsight(behavior: "Meditación", outcome: "Recuperación",
                                        confidence: .candidate)
        let proven: Set<Lever> = [Lever(behavior: "Meditación", outcome: "Recuperación")]

        let out = InsightEngine.promoteProven([candidate], provenLevers: proven)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].confidence, .proven)
        // Everything else is preserved.
        XCTAssertEqual(out[0].lever, candidate.lever)
        XCTAssertEqual(out[0].relevance, candidate.relevance)
        XCTAssertEqual(out[0].title, candidate.title)
    }

    func testLeavesUnmatchedAndNonCandidateUntouched() {
        let matchedCandidate = behaviorInsight(behavior: "Meditación", outcome: "Recuperación",
                                               confidence: .candidate)
        let otherCandidate = behaviorInsight(behavior: "Café", outcome: "HRV",
                                             confidence: .candidate)
        // A `.medium` finding that didn't survive FDR this run — must NOT be promoted even if its
        // lever is in the proven set.
        let mediumSameLever = behaviorInsight(behavior: "Meditación", outcome: "Recuperación",
                                              confidence: .medium)
        let proven: Set<Lever> = [Lever(behavior: "Meditación", outcome: "Recuperación")]

        let out = InsightEngine.promoteProven([matchedCandidate, otherCandidate, mediumSameLever],
                                              provenLevers: proven)
        XCTAssertEqual(out[0].confidence, .proven)   // matched candidate
        XCTAssertEqual(out[1].confidence, .candidate) // different lever
        XCTAssertEqual(out[2].confidence, .medium)    // not a candidate → not promoted
    }

    /// Promotion keys by the lever's RAW identity (the journal question, verbatim) — exact and
    /// case-sensitive. A lowercase behavior must still promote when the proven set carries the same
    /// raw string. Guards the FER-307 class of bug where a capitalized display name was persisted
    /// instead of the raw lever key, so the two `Lever`s never matched.
    func testPromotionKeysByRawLeverIdentityCaseSensitive() {
        let candidate = behaviorInsight(behavior: "siesta", outcome: "Recuperación",
                                        confidence: .candidate)
        // Same raw key promotes…
        let proven = InsightEngine.promoteProven([candidate],
                                                 provenLevers: [Lever(behavior: "siesta", outcome: "Recuperación")])
        XCTAssertEqual(proven[0].confidence, .proven)
        // …a capitalized variant is a DIFFERENT lever and must NOT promote.
        let notProven = InsightEngine.promoteProven([candidate],
                                                    provenLevers: [Lever(behavior: "Siesta", outcome: "Recuperación")])
        XCTAssertEqual(notProven[0].confidence, .candidate)
    }

    func testEmptyProvenSetIsNoOp() {
        let candidate = behaviorInsight(behavior: "Meditación", outcome: "Recuperación",
                                        confidence: .candidate)
        let out = InsightEngine.promoteProven([candidate], provenLevers: [])
        XCTAssertEqual(out, [candidate])
    }

    func testNonBehaviorInsightWithoutLeverIsUntouched() {
        let trend = Insight(kind: .trend, title: "Recuperación subiendo", reading: "…",
                            datum: InsightDatum(value: 5, unit: "pts", metric: "Recuperación"),
                            evidence: InsightEvidence(n: 14, pValue: nil, pAdjusted: nil,
                                                      effectSize: nil, significant: false),
                            confidence: .medium, relevance: 2.0)
        let proven: Set<Lever> = [Lever(behavior: "Meditación", outcome: "Recuperación")]
        let out = InsightEngine.promoteProven([trend], provenLevers: proven)
        XCTAssertEqual(out, [trend])
    }
}
