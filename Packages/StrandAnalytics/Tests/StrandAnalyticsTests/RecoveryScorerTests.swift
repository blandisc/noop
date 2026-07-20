import XCTest
@testable import StrandAnalytics
import BiometricStreams

final class RecoveryScorerTests: XCTestCase {

    /// A usable (trusted) baseline with a given mean and σ (Gaussian).
    private func baseline(mean: Double, sigma: Double, nValid: Int = 14) -> BaselineState {
        // spread is internal abs-dev units; deviation() multiplies by 1.253 → σ.
        BaselineState(baseline: mean, spread: sigma / 1.253, nValid: nValid,
                      nightsSinceUpdate: 0, status: nValid >= 14 ? .trusted : .provisional)
    }

    func testRecoveryAtBaselineNearPopulationMean() {
        // HRV at baseline, RHR at baseline, no resp, sleepPerf at center → Z≈0 → ~58%.
        let r = RecoveryScorer.recovery(
            hrv: 50, rhr: 55, resp: nil,
            hrvBaseline: baseline(mean: 50, sigma: 6),
            rhrBaseline: baseline(mean: 55, sigma: 3),
            respBaseline: nil,
            sleepPerf: RecoveryScorer.sleepPerfCenter)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!, 57.93, accuracy: 0.5)
    }

    func testRecoveryHigherWhenHRVAboveAndRHRBelow() {
        let good = RecoveryScorer.recovery(
            hrv: 65, rhr: 50, resp: nil,
            hrvBaseline: baseline(mean: 50, sigma: 6.265),
            rhrBaseline: baseline(mean: 55, sigma: 2.506),
            respBaseline: nil,
            sleepPerf: 0.90)!
        let bad = RecoveryScorer.recovery(
            hrv: 40, rhr: 62, resp: nil,
            hrvBaseline: baseline(mean: 50, sigma: 6.265),
            rhrBaseline: baseline(mean: 55, sigma: 2.506),
            respBaseline: nil,
            sleepPerf: 0.70)!
        XCTAssertGreaterThan(good, bad)
        XCTAssertGreaterThan(good, 90)   // matches Python golden ~97
        XCTAssertLessThan(bad, 15)       // matches Python golden ~7
    }

    func testRecoveryClampedToRange() {
        let r = RecoveryScorer.recovery(
            hrv: 200, rhr: 30, resp: nil,
            hrvBaseline: baseline(mean: 50, sigma: 5),
            rhrBaseline: baseline(mean: 55, sigma: 2),
            respBaseline: nil,
            sleepPerf: 1.0)!
        XCTAssertLessThanOrEqual(r, 100.0)
        XCTAssertGreaterThanOrEqual(r, 0.0)
    }

    func testColdStartReturnsNil() {
        let coldHRV = BaselineState(baseline: 50, spread: 5, nValid: 2,
                                    nightsSinceUpdate: 0, status: .calibrating)
        let r = RecoveryScorer.recovery(
            hrv: 60, rhr: 50, resp: nil,
            hrvBaseline: coldHRV, rhrBaseline: nil, respBaseline: nil, sleepPerf: 0.9)
        XCTAssertNil(r)
    }

    func testRespTermDropAndRenormalize() {
        // With resp present vs nil but everything else equal at baseline, the score
        // stays near population mean either way (no driver pushes Z off zero).
        let withResp = RecoveryScorer.recovery(
            hrv: 50, rhr: 55, resp: 100,
            hrvBaseline: baseline(mean: 50, sigma: 6),
            rhrBaseline: baseline(mean: 55, sigma: 3),
            respBaseline: baseline(mean: 100, sigma: 5),
            sleepPerf: RecoveryScorer.sleepPerfCenter)!
        let withoutResp = RecoveryScorer.recovery(
            hrv: 50, rhr: 55, resp: nil,
            hrvBaseline: baseline(mean: 50, sigma: 6),
            rhrBaseline: baseline(mean: 55, sigma: 3),
            respBaseline: baseline(mean: 100, sigma: 5),
            sleepPerf: RecoveryScorer.sleepPerfCenter)!
        XCTAssertEqual(withResp, withoutResp, accuracy: 1e-6)
    }

    func testRespAboveBaselineLowersAndBelowRaisesRecovery() {
        // Pins the resp-into-recovery wiring direction (mirrors the Android BaselineSeedingTest
        // addition): with HRV/RHR pinned at baseline, a nightly respiratory rate above the resp
        // baseline must LOWER recovery and one below it must RAISE it. A nil resp renormalizes
        // to the no-resp score (testRespTermDropAndRenormalize already pins that).
        func score(_ resp: Double?) -> Double {
            RecoveryScorer.recovery(
                hrv: 50, rhr: 55, resp: resp,
                hrvBaseline: baseline(mean: 50, sigma: 6),
                rhrBaseline: baseline(mean: 55, sigma: 3),
                respBaseline: baseline(mean: 14.5, sigma: 1),
                sleepPerf: 0.9)!
        }
        let neutral = score(nil)
        let elevated = score(17.5)
        let lowered = score(12.0)
        XCTAssertLessThan(elevated, neutral, "resp above baseline must lower recovery")
        XCTAssertGreaterThan(lowered, neutral, "resp below baseline must raise recovery")
    }

    func testSkinTempAboveBaselineLowersRecovery() {
        // Pins the skin-temp-into-recovery wiring: with HRV/RHR/sleep at baseline, a nightly
        // skin temp at baseline must not move the score off the no-temp value, and an elevated
        // temp (illness / overreaching) must LOWER recovery.
        func score(temp: Double?, base: Bool) -> Double {
            RecoveryScorer.recovery(
                hrv: 50, rhr: 55, resp: nil,
                hrvBaseline: baseline(mean: 50, sigma: 6),
                rhrBaseline: baseline(mean: 55, sigma: 3),
                respBaseline: nil,
                sleepPerf: RecoveryScorer.sleepPerfCenter,
                skinTemp: temp,
                skinTempBaseline: base ? baseline(mean: 33.5, sigma: 0.3) : nil)!
        }
        let neutralNoTemp = score(temp: nil, base: false)
        let atBaseline = score(temp: 33.5, base: true)
        let elevated = score(temp: 34.3, base: true)
        XCTAssertEqual(atBaseline, neutralNoTemp, accuracy: 1e-6, "temp at baseline must not move the score")
        XCTAssertLessThan(elevated, neutralNoTemp, "elevated skin temp must lower recovery")
    }

    func testSleepEfficiencyPersonalizedVsFixedCenter() {
        // A habitual low sleeper (personal efficiency ~0.78). Against the fixed population
        // center (0.85) that night reads "below center" and drags recovery DOWN; against the
        // user's OWN baseline (mean 0.78) the same night is neutral and isn't penalized.
        func score(personal: Bool) -> Double {
            RecoveryScorer.recovery(
                hrv: 50, rhr: 55, resp: nil,
                hrvBaseline: baseline(mean: 50, sigma: 6),
                rhrBaseline: baseline(mean: 55, sigma: 3),
                respBaseline: nil,
                sleepPerf: 0.78,
                sleepPerfBaseline: personal ? baseline(mean: 0.78, sigma: 0.05) : nil)!
        }
        XCTAssertGreaterThan(score(personal: true), score(personal: false),
                             "own-baseline sleep must not penalize a habitual low sleeper")
    }

    func testBandThresholds() {
        XCTAssertEqual(RecoveryScorer.band(20), "red")
        XCTAssertEqual(RecoveryScorer.band(33.9), "red")
        XCTAssertEqual(RecoveryScorer.band(34), "yellow")
        XCTAssertEqual(RecoveryScorer.band(50), "yellow")
        XCTAssertEqual(RecoveryScorer.band(66.9), "yellow")
        XCTAssertEqual(RecoveryScorer.band(67), "green")
        XCTAssertEqual(RecoveryScorer.band(90), "green")
    }

    func testRestingHRLowestRollingMean() {
        // Two 5-min blocks: first averages 60, second averages 50 → resting = 50.
        var hr: [HRSample] = []
        let start = 1000
        for i in 0..<300 { hr.append(HRSample(ts: start + i, bpm: 60)) }        // 0..299 s
        for i in 0..<300 { hr.append(HRSample(ts: start + 300 + i, bpm: 50)) }  // 300..599 s
        let r = RecoveryScorer.restingHR(hr, start: start, end: start + 600)
        XCTAssertEqual(r, 50)
    }

    func testRestingHRNilWhenNoSamples() {
        XCTAssertNil(RecoveryScorer.restingHR([], start: 0, end: 1000))
    }

    // MARK: - Resting-HR anti-artefact hardening (FER-674)

    func testRestingHRSparseBinCannotWinFloor() {
        // A dense, physiological bin at 55 bpm, then a SPARSE dropout bin (3 samples) that
        // averages a lower 40 bpm. The sparse bin has < restingHRMinBinSamples samples, so
        // it cannot win the floor: the resting HR stays 55, not the unreliable 40.
        var hr: [HRSample] = []
        let start = 1000
        for i in 0..<300 { hr.append(HRSample(ts: start + i, bpm: 55)) }             // dense bin → 55
        for i in 0..<3   { hr.append(HRSample(ts: start + 300 + i, bpm: 40)) }        // sparse bin (3) → ignored
        let r = RecoveryScorer.restingHR(hr, start: start, end: start + 600)
        XCTAssertEqual(r, 55)
    }

    func testRestingHRSubPhysiologicalBinCannotWinFloor() {
        // A dense bin at 58 bpm, then a dense but SUB-PHYSIOLOGICAL bin averaging 15 bpm
        // (below restingHRMinBpm). The impossible bin must not win the floor → stays 58.
        var hr: [HRSample] = []
        let start = 2000
        for i in 0..<300 { hr.append(HRSample(ts: start + i, bpm: 58)) }
        for i in 0..<300 { hr.append(HRSample(ts: start + 300 + i, bpm: 15)) }
        let r = RecoveryScorer.restingHR(hr, start: start, end: start + 600)
        XCTAssertEqual(r, 58)
    }

    func testRestingHRDropoutNightReturnsNilNotImpossibleValue() {
        // A whole night of nothing but a sparse dropout (3 samples): no bin qualifies, so
        // the estimate is nil (honest) rather than a fabricated RHR from a handful of beats.
        let start = 3000
        let hr = (0..<3).map { HRSample(ts: start + $0, bpm: 42) }
        XCTAssertNil(RecoveryScorer.restingHR(hr, start: start, end: start + 600))
    }

    func testRestingHRNormalNightUnchanged() {
        // A normal night (two dense physiological bins) scores exactly as before the
        // hardening: the lowest sustained bin mean.
        var hr: [HRSample] = []
        let start = 4000
        for i in 0..<300 { hr.append(HRSample(ts: start + i, bpm: 62)) }
        for i in 0..<300 { hr.append(HRSample(ts: start + 300 + i, bpm: 51)) }
        XCTAssertEqual(RecoveryScorer.restingHR(hr, start: start, end: start + 600), 51)
    }

    // MARK: - Confidence shrinkage (FER-13)

    /// Same night, identical baseline mean/σ — only the number of valid nights differs.
    /// A thin (provisional) baseline shrinks the z toward neutral, so both a bad day
    /// and a great day land closer to 50 than when scored against a trusted baseline.
    func testThinBaselinePullsScoreTowardNeutral() {
        func score(nValid: Int, hrv: Double, rhr: Double, sleep: Double) -> Double {
            RecoveryScorer.recovery(
                hrv: hrv, rhr: rhr, resp: nil,
                hrvBaseline: baseline(mean: 50, sigma: 6, nValid: nValid),
                rhrBaseline: baseline(mean: 55, sigma: 3, nValid: nValid),
                respBaseline: nil, sleepPerf: sleep)!
        }
        // Bad day: suppressed HRV, elevated RHR, poor sleep.
        let badThin = score(nValid: Baselines.minNightsSeed, hrv: 38, rhr: 63, sleep: 0.70)
        let badTrusted = score(nValid: Baselines.minNightsTrust, hrv: 38, rhr: 63, sleep: 0.70)
        XCTAssertGreaterThan(badThin, badTrusted)                       // less punishing on thin evidence
        XCTAssertLessThan(abs(badThin - 50), abs(badTrusted - 50))      // closer to neutral

        // Great day: high HRV, low RHR, good sleep.
        let goodThin = score(nValid: Baselines.minNightsSeed, hrv: 66, rhr: 48, sleep: 0.95)
        let goodTrusted = score(nValid: Baselines.minNightsTrust, hrv: 66, rhr: 48, sleep: 0.95)
        XCTAssertLessThan(goodThin, goodTrusted)                        // less flattering on thin evidence
        XCTAssertLessThan(abs(goodThin - 50), abs(goodTrusted - 50))    // closer to neutral
    }

    /// A trusted baseline (nValid ≥ minNightsTrust) gets confidence 1.0 → no shrinkage,
    /// so established users' scores are byte-for-byte unchanged by FER-13.
    func testTrustedBaselineUnchanged() {
        let viaState = RecoveryScorer.recovery(
            hrv: 65, rhr: 50, resp: nil,
            hrvBaseline: baseline(mean: 50, sigma: 6.265, nValid: 20),
            rhrBaseline: baseline(mean: 55, sigma: 2.506, nValid: 20),
            respBaseline: nil, sleepPerf: 0.90)!
        // DriverBaseline built directly (no nValid) defaults to trusted → identical score.
        let viaDriver = RecoveryScorer.recovery(
            hrv: 65, rhr: 50, resp: nil,
            hrvBaseline: RecoveryScorer.DriverBaseline(mean: 50, spread: 6.265 / 1.253),
            rhrBaseline: RecoveryScorer.DriverBaseline(mean: 55, spread: 2.506 / 1.253),
            respBaseline: nil, sleepPerf: 0.90)!
        XCTAssertEqual(viaState, viaDriver, accuracy: 1e-9)
    }

    // MARK: - Missing-driver shrinkage (FER-698)

    /// A single strong driver must NOT saturate the score as if the whole picture agreed.
    /// Before FER-698, HRV alone renormalized to full weight and the logistic ran toward
    /// ~100; now the composite is pulled toward neutral by the coverage factor
    /// (present 0.60 / reference 0.95). This is acceptance criterion #1.
    func testSingleDriverDoesNotSaturate() {
        let hrvB = baseline(mean: 50, sigma: 6)     // linear baseline → a clean +2σ
        let hrvAt2Sigma = 50.0 + 2.0 * 6.0          // (x−μ)/σ = 2
        let hrvOnly = RecoveryScorer.recovery(
            hrv: hrvAt2Sigma, rhr: 0, resp: nil,
            hrvBaseline: hrvB, rhrBaseline: nil, respBaseline: nil, sleepPerf: nil)!

        // The old, unshrunk single-term score for the very same z=+2σ.
        let unshrunk = 100.0 / (1.0 + exp(-RecoveryScorer.logisticK * (2.0 - RecoveryScorer.logisticZ0)))
        XCTAssertGreaterThan(unshrunk, 95, "sanity: an unshrunk lone +2σ driver WOULD saturate")
        XCTAssertLessThan(hrvOnly, unshrunk - 3,
                          "a lone driver no longer saturates like the full picture")
        XCTAssertLessThan(hrvOnly, 93, "HRV alone at +2σ stays below the saturation ceiling")

        // The point of the shape: a missing driver now behaves like a NEUTRAL one, not an
        // amplifier. HRV at +2σ alone == HRV at +2σ with RHR & sleep sitting at baseline.
        let withNeutralOthers = RecoveryScorer.recovery(
            hrv: hrvAt2Sigma, rhr: 55, resp: nil,
            hrvBaseline: hrvB, rhrBaseline: baseline(mean: 55, sigma: 3), respBaseline: nil,
            sleepPerf: RecoveryScorer.sleepPerfCenter)!
        XCTAssertEqual(hrvOnly, withNeutralOthers, accuracy: 1e-9,
                       "missing drivers behave like neutral ones, not amplifiers")
    }

    /// With the three PRIMARY drivers present (HRV+RHR+sleep = referenceCoverageWeight), the
    /// coverage factor is capped at 1.0, so the score is byte-identical to the pre-FER-698
    /// (un-shrunk) formula — no regression for band users. This is acceptance criterion #2.
    func testFullPrimaryDriversUnaffectedByShrinkage() {
        let hrvB = baseline(mean: 50, sigma: 6)
        let rhrB = baseline(mean: 55, sigma: 3)
        let score = RecoveryScorer.recovery(
            hrv: 62, rhr: 52, resp: nil,
            hrvBaseline: hrvB, rhrBaseline: rhrB, respBaseline: nil, sleepPerf: 0.92)!

        // Recompute the pre-698 way: renormalize to present weight, NO coverage shrink
        // (baselines are trusted → per-term Baselines.confidence == 1.0).
        let zHRV = RecoveryScorer.zScore(62, mean: 50, spread: 6 / 1.253)
        let zRHR = RecoveryScorer.zScore(55, mean: 52, spread: 3 / 1.253)     // (μ−x)/σ, lower is better
        let zSleep = (0.92 - RecoveryScorer.sleepPerfCenter) / RecoveryScorer.sleepPerfScale
        let w = RecoveryScorer.wHRV + RecoveryScorer.wRHR + RecoveryScorer.wSleep   // 0.95 = reference
        let meanZ = (zHRV * RecoveryScorer.wHRV + zRHR * RecoveryScorer.wRHR
                     + zSleep * RecoveryScorer.wSleep) / w
        let expected = 100.0 / (1.0 + exp(-RecoveryScorer.logisticK * (meanZ - RecoveryScorer.logisticZ0)))
        XCTAssertEqual(score, expected, accuracy: 1e-9,
                       "primary-driver score is unchanged by the shrinkage")
    }

    // MARK: - Degenerate logistic guard (FER-36)

    /// A non-finite driver (NaN/±inf) yields a non-finite composite z; the engine
    /// must return nil rather than pushing NaN through the logistic.
    func testRecoveryNonFiniteDriverReturnsNil() {
        let b = baseline(mean: 50, sigma: 6)
        XCTAssertNil(RecoveryScorer.recovery(
            hrv: .nan, rhr: 55, resp: nil,
            hrvBaseline: b, rhrBaseline: baseline(mean: 55, sigma: 3),
            respBaseline: nil, sleepPerf: 0.85))
        XCTAssertNil(RecoveryScorer.recovery(
            hrv: .infinity, rhr: 55, resp: nil,
            hrvBaseline: b, rhrBaseline: baseline(mean: 55, sigma: 3),
            respBaseline: nil, sleepPerf: 0.85))
    }

    // MARK: - RHR sentinel is inert without a baseline (FER-698 follow-up)

    /// When `rhrBaseline` is nil the RHR term is skipped entirely, so the value passed as
    /// `rhr` must not touch the score. Callers may pass a sentinel (`?? .nan`) for nights
    /// without a resting-HR baseline. This pins the invariant so a future refactor that starts
    /// reading `rhr` outside the baseline gate (which would let 0/NaN bpm leak into the
    /// composite) fails here.
    func testRHRSentinelInertWhenBaselineNil() {
        let hrvB = baseline(mean: 50, sigma: 6)
        let withZeroRHR = RecoveryScorer.recovery(
            hrv: 50, rhr: 0, resp: nil,
            hrvBaseline: hrvB, rhrBaseline: nil, respBaseline: nil, sleepPerf: nil)
        let withRealRHR = RecoveryScorer.recovery(
            hrv: 50, rhr: 45, resp: nil,
            hrvBaseline: hrvB, rhrBaseline: nil, respBaseline: nil, sleepPerf: nil)
        XCTAssertEqual(withZeroRHR, withRealRHR,
                       "rhr must be inert when rhrBaseline is nil — the sentinel must not change the score")
    }
}
