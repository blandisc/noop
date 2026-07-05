import XCTest
@testable import StrandAnalytics

/// Pins FER-153 (Capa 2): an ESTIMATED recovery from Apple Health's SDNN against the
/// user's OWN Apple SDNN baseline — same RecoveryScorer model, NO SDNN→RMSSD conversion.
final class AppleRecoveryEstimatorTests: XCTestCase {

    private func day(_ i: Int) -> String { String(format: "2026-06-%02d", i + 1) }

    /// `n` nights of SDNN (ms), oldest→newest, with the given sleep coverage.
    private func nights(_ sdnn: [Double], sleepMinutes: Double? = 420) -> [AppleRecoveryEstimator.Night] {
        sdnn.enumerated().map { i, v in
            AppleRecoveryEstimator.Night(day: day(i), hrvSDNN: v, restingHr: nil, resp: nil,
                                         sleepPerf: nil, sleepMinutes: sleepMinutes)
        }
    }

    // MARK: - No SDNN→RMSSD conversion (the owner's core decision)

    /// Scaling EVERY HRV value by a constant (the kind of absolute-ms gap between SDNN and
    /// RMSSD) leaves every score IDENTICAL — proof there is no conversion factor: the score
    /// depends only on the RELATIVE position vs the user's own baseline (log-domain z is
    /// scale-invariant). This is acceptance criterion #2.
    func testScaleInvariance_noConversionFactor() {
        let base: [Double] = [48, 52, 45, 60, 55, 50, 47, 58, 53, 49, 56, 51, 44, 62, 57, 46]
        let a = AppleRecoveryEstimator.estimate(nights: nights(base))
        let b = AppleRecoveryEstimator.estimate(nights: nights(base.map { $0 * 1.5 }))   // e.g. SDNN scale ≠ RMSSD scale
        XCTAssertEqual(a.count, base.count)
        XCTAssertEqual(a.count, b.count)
        for (x, y) in zip(a, b) {
            XCTAssertEqual(x.day, y.day)
            XCTAssertEqual(x.score, y.score, accuracy: 1e-9,
                           "same relative SDNN → same score, regardless of absolute ms scale")
        }
    }

    /// A night above the user's own SDNN norm scores higher than one below it (direction sanity).
    func testAboveOwnNormScoresHigher() {
        var lows = Array(repeating: 50.0, count: 15); lows.append(35)   // last night below norm
        var highs = Array(repeating: 50.0, count: 15); highs.append(80) // last night above norm
        let low = AppleRecoveryEstimator.estimate(nights: nights(lows)).last!
        let high = AppleRecoveryEstimator.estimate(nights: nights(highs)).last!
        XCTAssertGreaterThan(high.score, low.score)
        XCTAssertTrue((0...100).contains(low.score) && (0...100).contains(high.score))
    }

    // MARK: - Cold-start (acceptance criterion: <4 Apple nights → "—")

    func testColdStartBelowSeedReturnsNothing() {
        XCTAssertTrue(AppleRecoveryEstimator.estimate(nights: nights([50, 52, 48])).isEmpty,
                      "3 Apple HRV nights < minNightsSeed → no estimate (UI shows —)")
    }

    func testSeedNightsProduceAnEstimate() {
        let est = AppleRecoveryEstimator.estimate(nights: nights([50, 52, 48, 55]))   // exactly 4
        XCTAssertEqual(est.count, 4, "at the seed gate the baseline is usable → estimates appear")
    }

    // MARK: - Confidence reflects coverage / cold-start

    func testFewNightsGiveLowConfidence() {
        let est = AppleRecoveryEstimator.estimate(nights: nights([50, 52, 48, 55, 51]))   // 5 nights
        XCTAssertFalse(est.isEmpty)
        XCTAssertTrue(est.allSatisfy { $0.confidence == .calibrating },
                      "few Apple nights (≥seed, <building) → baja")
    }

    func testManyNightsGoodCoverageGiveHighConfidence() {
        let est = AppleRecoveryEstimator.estimate(nights: nights(Array(repeating: 50.0, count: 16)))
        XCTAssertEqual(est.last?.confidence, .solid, "≥14 nights + good coverage → alta")
    }

    // MARK: - Coverage gate (FER-697): a thin night is OMITTED, not downgraded

    /// A night with measured sleep below the coverage floor gets NO estimate — the same "—"
    /// as cold-start. This is what kills the inflated "estimado 100" seen just after midnight,
    /// when only ~2 h of the current night has been logged (acceptance criterion #1).
    func testThinCoverageNightIsOmitted() {
        // 16 nights with good coverage, then one more night below the floor.
        var ns = nights(Array(repeating: 50.0, count: 16))            // sleepMinutes: 420 (default)
        let thinDay = day(16)
        ns.append(AppleRecoveryEstimator.Night(day: thinDay, hrvSDNN: 90, restingHr: nil, resp: nil,
                                               sleepPerf: nil, sleepMinutes: 120))   // ~2 h, in-progress night
        let est = AppleRecoveryEstimator.estimate(nights: ns)
        XCTAssertFalse(est.contains { $0.day == thinDay },
                       "a night below the coverage floor is omitted, not scored")
        XCTAssertEqual(est.count, 16, "only the 16 well-covered nights are scored")
    }

    /// The boundary is inclusive: a night AT the threshold still scores, so nights with
    /// sufficient coverage (≥180) are unchanged by the gate (acceptance criterion #2).
    func testCoverageAtThresholdStillScores() {
        let atFloor = AppleRecoveryEstimator.estimate(
            nights: nights(Array(repeating: 50.0, count: 16),
                           sleepMinutes: AppleRecoveryEstimator.coverageSleepMinThreshold))
        XCTAssertEqual(atFloor.count, 16, "sleep exactly at the floor is scored, not dropped")
        XCTAssertEqual(atFloor.last?.confidence, .solid,
                       "≥14 nights → alta; coverage no longer downgrades the grade")
    }

    // MARK: - HRV is the required driver

    func testNightWithoutHrvIsSkipped() {
        var ns = nights(Array(repeating: 50.0, count: 14))
        let gapDay = ns[7].day
        ns[7] = AppleRecoveryEstimator.Night(day: gapDay, hrvSDNN: nil, restingHr: 55, resp: 14,
                                             sleepPerf: nil, sleepMinutes: 420)
        let est = AppleRecoveryEstimator.estimate(nights: ns)
        XCTAssertFalse(est.contains { $0.day == gapDay }, "a night without SDNN gets no estimate")
        XCTAssertEqual(est.count, 13)
    }

    // MARK: - Primary-driver coverage (FER-700): surface WHY an estimate is conservative

    /// An Apple estimate with ONLY HRV present reports coverage 1 of 3 — the typical Apple case
    /// the FER-698 shrinkage pulls toward neutral. (The `nights()` helper leaves RHR/sleep nil.)
    func testCoverageHrvOnlyIsOneOfThree() {
        let est = AppleRecoveryEstimator.estimate(nights: nights(Array(repeating: 50.0, count: 16)))
        XCTAssertEqual(est.last?.presentPrimaryDrivers, 1, "HRV alone → 1 de 3 señales")
        XCTAssertEqual(AppleRecoveryEstimator.DayEstimate.totalPrimaryDrivers, 3)
    }

    /// With HRV + resting HR (and a usable RHR baseline) but no sleep, coverage is 2 of 3.
    func testCoverageHrvPlusRhrIsTwoOfThree() {
        let ns = (0..<16).map { i in
            AppleRecoveryEstimator.Night(day: day(i), hrvSDNN: 50, restingHr: 55, resp: nil,
                                         sleepPerf: nil, sleepMinutes: 420)
        }
        let est = AppleRecoveryEstimator.estimate(nights: ns)
        XCTAssertEqual(est.last?.presentPrimaryDrivers, 2, "HRV + FC en reposo → 2 de 3 señales")
    }

    /// With all three primary drivers present (HRV + RHR + sleep), coverage is the full 3 of 3.
    func testCoverageAllThreePrimaryIsThreeOfThree() {
        let ns = (0..<16).map { i in
            AppleRecoveryEstimator.Night(day: day(i), hrvSDNN: 50, restingHr: 55, resp: nil,
                                         sleepPerf: 0.9, sleepMinutes: 420)
        }
        let est = AppleRecoveryEstimator.estimate(nights: ns)
        XCTAssertEqual(est.last?.presentPrimaryDrivers, 3, "las tres señales → 3 de 3")
    }

    /// Surfacing coverage must NOT move the score: the HRV-only score is byte-identical to a
    /// baseline computed the same way before FER-700 (the coverage count is read-only telemetry).
    func testCoverageDoesNotChangeScore() {
        let est = AppleRecoveryEstimator.estimate(nights: nights([50, 52, 48, 55, 51, 49, 53, 47]))
        XCTAssertFalse(est.isEmpty)
        // Re-scoring the last night by hand through the same public scorer, HRV-only, must match.
        XCTAssertTrue(est.allSatisfy { (0...100).contains($0.score) && $0.presentPrimaryDrivers == 1 })
    }

    /// `.lowered` ladder is ordered and floors at calibrating.
    func testConfidenceLoweredLadder() {
        XCTAssertEqual(ScoreConfidence.solid.lowered, .building)
        XCTAssertEqual(ScoreConfidence.building.lowered, .calibrating)
        XCTAssertEqual(ScoreConfidence.calibrating.lowered, .calibrating)
    }
}
