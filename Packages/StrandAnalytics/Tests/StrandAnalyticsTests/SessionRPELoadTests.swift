import XCTest
@testable import StrandAnalytics

/// Ola 1 · E2 — minutes × effort onto the same 0–21 ruler heart rate uses.
/// Gate estadístico H2 (affine map), H3 (median of ratios), H4 (refit hysteresis), H8 (relative
/// round-trip tolerance), H9 (default k), H10 (edges).
final class SessionRPELoadTests: XCTestCase {

    // MARK: H2 — the RIR row is NOT CR-10; the map is affine and explicit

    func testAffineMapAnchors() {
        XCTAssertEqual(SessionRPELoad.cr10(6)!, 4, accuracy: 1e-9)
        XCTAssertEqual(SessionRPELoad.cr10(8)!, 7, accuracy: 1e-9)
        XCTAssertEqual(SessionRPELoad.cr10(10)!, 10, accuracy: 1e-9)
        // The point of the map: it RESTORES the dynamic range the 6–10 row lost (10/6 = 1.67× → 2.5×).
        XCTAssertEqual(SessionRPELoad.cr10(10)! / SessionRPELoad.cr10(6)!, 2.5, accuracy: 1e-9)
    }

    // MARK: H9 — the default scale puts a real session in the band

    func testFiftyMinRPE8LandsInBand() {
        let s = SessionRPELoad.strain(durationS: 50 * 60, rpe: 8)!
        XCTAssertGreaterThanOrEqual(s, 10)
        XCTAssertLessThanOrEqual(s, 12)
    }

    // MARK: H8 — `trimpToStrain` rounds to 2 dp, so the inverse is exact only in RELATIVE terms

    func testRoundTripStrainToTrimpRelative() {
        for trimp in [10.0, 48.0, 100.0, 159.0, 450.0] {
            let back = StrainScorer.strainToTrimp(StrainScorer.trimpToStrain(trimp))
            XCTAssertEqual(back / trimp, 1.0, accuracy: 0.003, "TRIMP \(trimp)")
        }
    }

    /// The delegation must not have moved a single number: `ReadinessEngine.strainToLoad` IS the
    /// inverse, now in one place.
    func testReadinessEngineDelegatesToTheSameInverse() {
        for strain in [0.0, 1.0, 10.91, 21.0] {
            XCTAssertEqual(ReadinessEngine.strainToLoad(strain),
                           StrainScorer.strainToTrimp(strain), accuracy: 1e-12)
        }
    }

    // MARK: H10 — edges

    func testShortSessionYieldsNil() {
        XCTAssertNil(SessionRPELoad.strain(durationS: SessionRPELoad.minDurationS - 1, rpe: 8))
        XCTAssertNotNil(SessionRPELoad.strain(durationS: SessionRPELoad.minDurationS, rpe: 8))
    }

    func testDurationCapAtThreeHours() {
        let capped = SessionRPELoad.strain(durationS: SessionRPELoad.maxDurationS, rpe: 8)!
        let forgotten = SessionRPELoad.strain(durationS: 5 * 3600, rpe: 8)!
        XCTAssertEqual(forgotten, capped, accuracy: 1e-9)
    }

    func testRPEOutOfRangeYieldsNil() {
        XCTAssertNil(SessionRPELoad.strain(durationS: 3000, rpe: 5.9))
        XCTAssertNil(SessionRPELoad.strain(durationS: 3000, rpe: 10.1))
        XCTAssertNil(SessionRPELoad.cr10(0))
    }

    // MARK: H3 — median of ratios, not least squares

    func testFitUsesMedianOfRatiosAndIgnoresOneExtremePair() {
        // Four honest sessions at k ≈ 0.29 plus one 3-hour outlier whose TRIMP is 10× off. OLS
        // through the origin weights by au² and would follow the outlier; the median does not.
        var pairs: [(au: Double, trimp: Double)] = (0..<4).map { _ in (au: 350, trimp: 101.5) }
        pairs.append((au: 1800, trimp: 3000))
        let k = SessionRPELoad.fitTrimpPerAU(pairs: pairs)!
        XCTAssertEqual(k, 0.29, accuracy: 0.29 * 0.05)

        var ols = 0.0, sq = 0.0
        for p in pairs { ols += p.au * p.trimp; sq += p.au * p.au }
        XCTAssertGreaterThan(ols / sq, 0.29 * 1.5, "the extreme pair must be what the median rejects")
    }

    func testFitNeedsFivePairs() {
        let four: [(au: Double, trimp: Double)] = (0..<4).map { _ in (au: 350, trimp: 101.5) }
        XCTAssertNil(SessionRPELoad.fitTrimpPerAU(pairs: four))
        XCTAssertNotNil(SessionRPELoad.fitTrimpPerAU(pairs: four + [(au: 350, trimp: 101.5)]))
    }

    func testFitIsClampedToPlausibleScale() {
        let absurd: [(au: Double, trimp: Double)] = (0..<5).map { _ in (au: 10, trimp: 900) }
        XCTAssertEqual(SessionRPELoad.fitTrimpPerAU(pairs: absurd)!,
                       SessionRPELoad.trimpPerAUBounds.upperBound, accuracy: 1e-9)
    }

    // MARK: H4 — a refit only lands when the evidence doubled AND the scale really moved

    func testRefitOnlyWhenPairsDoubleAndDeltaOver15pct() {
        // First fit: the pair floor is the only gate on evidence, but the change still has to matter.
        XCTAssertTrue(SessionRPELoad.shouldAcceptRefit(pairCount: 5, lastFitPairCount: nil,
                                                       currentTrimpPerAU: 0.29, candidateTrimpPerAU: 0.20))
        XCTAssertFalse(SessionRPELoad.shouldAcceptRefit(pairCount: 5, lastFitPairCount: nil,
                                                        currentTrimpPerAU: 0.29, candidateTrimpPerAU: 0.30))
        XCTAssertFalse(SessionRPELoad.shouldAcceptRefit(pairCount: 4, lastFitPairCount: nil,
                                                        currentTrimpPerAU: 0.29, candidateTrimpPerAU: 0.20))
        // Fitted at 5: nothing is accepted again until the pairs DOUBLE, however different the k.
        XCTAssertFalse(SessionRPELoad.shouldAcceptRefit(pairCount: 7, lastFitPairCount: 5,
                                                        currentTrimpPerAU: 0.29, candidateTrimpPerAU: 0.10))
        XCTAssertTrue(SessionRPELoad.shouldAcceptRefit(pairCount: 10, lastFitPairCount: 5,
                                                       currentTrimpPerAU: 0.29, candidateTrimpPerAU: 0.10))
        XCTAssertFalse(SessionRPELoad.shouldAcceptRefit(pairCount: 20, lastFitPairCount: 10,
                                                        currentTrimpPerAU: 0.29, candidateTrimpPerAU: 0.31))
    }

    func testThresholdsAreNamedConstants() {
        XCTAssertEqual(SessionRPELoad.defaultTrimpPerAU, 0.29)
        XCTAssertEqual(SessionRPELoad.minCalibrationPairs, 5)
        XCTAssertEqual(SessionRPELoad.minDurationS, 300)
        XCTAssertEqual(SessionRPELoad.maxDurationS, 3 * 3600)
        XCTAssertEqual(SessionRPELoad.refitMinRelativeChange, 0.15)
        XCTAssertEqual(SessionRPELoad.trimpPerAUBounds, 0.05...1.0)
        XCTAssertEqual(HRCoverage.minCoverage, 0.8)
    }
}
