import XCTest
@testable import StrandAnalytics

/// FER-682 — nightly respiratory rate as a personal trend/deviation channel.
///
/// Method: personal baseline via the shipped `Baselines` EWMA (`resp` config), then a deviation is
/// flagged only when the recent nights clear BOTH an absolute floor (`minAbsoluteDeltaRpm`) AND the
/// personal robust-σ gate (`zThreshold`), SUSTAINED for ≥ `minSustainedNights` consecutive nights,
/// on a TRUSTED baseline. Somnofy (PMC11041471): nightly resp is very stable and a personalized
/// reference cuts its variance ~56% vs a universal one, so a small-but-sustained personal drift is
/// the informative signal.
///
/// A flat baseline of 35 identical nights pins the spread to the mature σ floor
/// (σ = 1.253 × floorSpread = 1.253 × 0.5 ≈ 0.6265 rpm), so the z of a chosen Δ is deterministic and
/// the two gates can be isolated.
final class RespirationTrendWatchTests: XCTestCase {

    /// 35 identical baseline nights (→ σ at the floor, trusted) + a 5-night recent window.
    private func series(baselineNights: Int = 35, base: Double = 14.0, recent: [Double?]) -> [Double?] {
        Array(repeating: Double?.some(base), count: baselineNights) + recent
    }

    /// A sustained elevation (2 nights at +3 rpm) on a trusted baseline flags `elevated`.
    func testSustainedElevationFlags() {
        let r = RespirationTrendWatch.evaluate(nightly: series(recent: [14, 14, 14, 17, 17]))
        XCTAssertTrue(r.flagged)
        XCTAssertEqual(r.direction, .elevated)
        XCTAssertEqual(r.sustainedNights, 2)
        XCTAssertEqual(r.deltaRpm, 3.0, accuracy: 0.2)
        XCTAssertGreaterThanOrEqual(r.z, RespirationTrendWatch.zThreshold)
        XCTAssertTrue(r.baselineTrusted)
    }

    /// A SINGLE elevated night is noise, not a sustained deviation — never flags.
    func testSingleNightNeverFlags() {
        let r = RespirationTrendWatch.evaluate(nightly: series(recent: [14, 14, 14, 14, 17.5]))
        XCTAssertFalse(r.flagged)
        XCTAssertEqual(r.sustainedNights, 1)
    }

    /// Untrusted (cold-start) baseline stays silent even with a clear sustained run.
    func testUntrustedBaselineStaysSilent() {
        let r = RespirationTrendWatch.evaluate(nightly: series(baselineNights: 8, recent: [14, 14, 14, 17, 17]))
        XCTAssertFalse(r.baselineTrusted)
        XCTAssertFalse(r.flagged)
        XCTAssertTrue(r.copy.lowercased().contains("learning"))
    }

    /// The absolute-rpm floor blocks a run that is σ-significant but physiologically trivial. The Δ of
    /// 1.5 rpm clears the σ gate (z ≥ 2 at the floor spread) yet stays under `minAbsoluteDeltaRpm`, so
    /// the abs gate — not the σ gate — is proven to be the blocker.
    func testAbsoluteFloorBlocksTrivialButSignificantDrift() {
        let nightly = series(recent: [14, 14, 14, 15.5, 15.5])
        // Prove the σ gate WOULD have passed at Δ = 1.5 on this baseline.
        let base = Baselines.foldHistory(Array(nightly.dropLast(5)), cfg: Baselines.respCfg)
        XCTAssertGreaterThanOrEqual(Baselines.deviation(15.5, state: base).z, RespirationTrendWatch.zThreshold,
                                    "precondition: 1.5 rpm is ≥2σ at the floor spread")
        let r = RespirationTrendWatch.evaluate(nightly: nightly)
        XCTAssertFalse(r.flagged, "abs floor (2 rpm) blocks the σ-significant 1.5 rpm drift")
        XCTAssertEqual(r.sustainedNights, 0)
    }

    /// A missing night breaks the run: the newest night alone, after a gap, doesn't sustain.
    func testGapBreaksTheRun() {
        let r = RespirationTrendWatch.evaluate(nightly: series(recent: [17, 17, 17, nil, 17]))
        XCTAssertEqual(r.sustainedNights, 1)
        XCTAssertFalse(r.flagged)
    }

    /// A sustained DROP flags `depressed` but is NOT illness-ward, so it is not handed to the composite.
    func testSustainedDropFlagsDepressedButNotIllnessWard() {
        let r = RespirationTrendWatch.evaluate(nightly: series(recent: [14, 14, 14, 11, 11]))
        XCTAssertTrue(r.flagged)
        XCTAssertEqual(r.direction, .depressed)
        XCTAssertNil(RespirationTrendWatch.asIllnessSignal(r))
    }

    /// A flagged elevation is handed to `IllnessSignalEngine` as respiration's oriented-z contribution.
    func testElevationFeedsCompositeAsSecondChannel() {
        let r = RespirationTrendWatch.evaluate(nightly: series(recent: [14, 14, 14, 17, 17]))
        let signal = RespirationTrendWatch.asIllnessSignal(r)
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.zIllnessward, r.z)
        XCTAssertTrue(signal?.present ?? false)
    }

    /// Copy is non-clinical: talks about "breathing" vs "normal", never names a condition.
    func testCopyIsNonClinical() {
        let r = RespirationTrendWatch.evaluate(nightly: series(recent: [14, 14, 14, 17, 17]))
        let c = r.copy.lowercased()
        XCTAssertTrue(c.contains("breathing"))
        for banned in ["illness", "infection", "fever", "sick", "disease", "covid", "flu"] {
            XCTAssertFalse(c.contains(banned), "copy must not name a condition: found \(banned)")
        }
    }
}
