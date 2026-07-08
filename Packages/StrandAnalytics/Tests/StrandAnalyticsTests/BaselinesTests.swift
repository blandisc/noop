import XCTest
@testable import StrandAnalytics

final class BaselinesTests: XCTestCase {

    func testFirstNightSeeds() {
        let s = Baselines.update(nil, value: 50, cfg: Baselines.hrvCfg)
        XCTAssertEqual(s.baseline, 50.0, accuracy: 1e-9)
        XCTAssertEqual(s.spread, Baselines.hrvCfg.floorSpread, accuracy: 1e-9)
        XCTAssertEqual(s.nValid, 1)
        XCTAssertEqual(s.status, .calibrating)
    }

    func testColdStartStatusProgression() {
        // 3 nights → calibrating; 4 → provisional; 14 → trusted.
        var s = Baselines.foldHistory(Array(repeating: 50.0, count: 3), cfg: Baselines.hrvCfg)
        XCTAssertEqual(s.status, .calibrating)
        XCTAssertFalse(s.usable)

        s = Baselines.foldHistory(Array(repeating: 50.0, count: 4), cfg: Baselines.hrvCfg)
        XCTAssertEqual(s.status, .provisional)
        XCTAssertTrue(s.usable)

        s = Baselines.foldHistory(Array(repeating: 50.0, count: 14), cfg: Baselines.hrvCfg)
        XCTAssertEqual(s.status, .trusted)
        XCTAssertTrue(s.trusted)
    }

    func testMissingNightSkipAndHold() {
        let seed = Baselines.update(nil, value: 50, cfg: Baselines.hrvCfg)
        let after = Baselines.update(seed, value: nil, cfg: Baselines.hrvCfg)
        XCTAssertEqual(after.baseline, seed.baseline, accuracy: 1e-9)
        XCTAssertEqual(after.spread, seed.spread, accuracy: 1e-9)
        XCTAssertEqual(after.nValid, seed.nValid)            // not incremented
        XCTAssertEqual(after.nightsSinceUpdate, 1)
    }

    func testConstantSeriesConvergesToValue() {
        let s = Baselines.foldHistory(Array(repeating: 50.0, count: 30), cfg: Baselines.hrvCfg)
        XCTAssertEqual(s.baseline, 50.0, accuracy: 1e-6)     // EWMA of constant = constant
        XCTAssertEqual(s.spread, Baselines.hrvCfg.floorSpread, accuracy: 1e-9)
    }

    func testHardOutlierRejected() {
        // Establish a TRUSTED baseline (≥ minNightsTrust), then feed a huge outlier (>5σ).
        // The hard-outlier gate is mature-only (FER-673), so the baseline must be trusted
        // for the rejection to apply.
        var values = Array(repeating: 50.0, count: 16)
        let stable = Baselines.foldHistory(values, cfg: Baselines.hrvCfg)
        XCTAssertEqual(stable.status, .trusted)
        values.append(200.0)  // way out (within physiological max 250, but >5*spread)
        let after = Baselines.foldHistory(values, cfg: Baselines.hrvCfg)
        // Baseline should barely move (outlier was rejected, not folded).
        XCTAssertEqual(after.baseline, stable.baseline, accuracy: 1.0)
    }

    func testOutOfRangeValueSkipped() {
        let seed = Baselines.update(nil, value: 50, cfg: Baselines.hrvCfg)
        // 300 > hrv max 250 → skip-and-hold.
        let after = Baselines.update(seed, value: 300, cfg: Baselines.hrvCfg)
        XCTAssertEqual(after.nValid, seed.nValid)
        XCTAssertEqual(after.nightsSinceUpdate, 1)
    }

    func testDeviationDirectionAndZero() {
        let s = Baselines.foldHistory(Array(repeating: 50.0, count: 14), cfg: Baselines.hrvCfg)
        let atBaseline = Baselines.deviation(50.0, state: s)
        XCTAssertEqual(atBaseline.z, 0.0, accuracy: 1e-6)
        XCTAssertEqual(atBaseline.delta, 0.0, accuracy: 1e-6)
        XCTAssertTrue(atBaseline.inNormalRange)

        let above = Baselines.deviation(70.0, state: s)
        XCTAssertGreaterThan(above.z, 0)
        XCTAssertEqual(above.delta, 20.0, accuracy: 1e-6)

        let below = Baselines.deviation(30.0, state: s)
        XCTAssertLessThan(below.z, 0)
    }

    func testRollingMeanSD() {
        // HRV is log-domain (Plews 2013): the center of [40, 50, 60] is the GEOMETRIC
        // mean exp((ln40+ln50+ln60)/3) ≈ 49.32 ms, NOT the arithmetic mean 50.
        let s = Baselines.rollingMeanSD([40, 50, 60], cfg: Baselines.hrvCfg)
        let geo = exp((log(40.0) + log(50.0) + log(60.0)) / 3.0)
        XCTAssertEqual(s.baseline, geo, accuracy: 1e-9)
        XCTAssertEqual(s.baseline, 49.324, accuracy: 1e-3)
        // spread is SD(ln)/1.253, so deviation() recovers σ_ln; z is on ln(value).
        let sdLn = (( pow(log(40.0) - log(geo), 2) + pow(log(50.0) - log(geo), 2)
                    + pow(log(60.0) - log(geo), 2)) / 2.0).squareRoot()
        let dev = Baselines.deviation(60.0, state: s)
        XCTAssertEqual(dev.z, (log(60.0) - log(geo)) / sdLn, accuracy: 1e-6)
    }

    /// Fixed-vector test for the log-domain HRV baseline.
    /// Method: RMSSD per Task Force 1996 (HRV measurement standard); baselined and
    /// z-scored in ln(RMSSD) because nightly HRV is ~log-normal (Plews et al. 2013).
    func testHrvLogDomainGeometricCenterAndSymmetricZ() {
        // A log-SYMMETRIC series around 50 ms (×/÷ 1.2 and ×/÷ 1.5) has geometric mean
        // exactly 50 — the arithmetic mean (≈51.3) would sit above it. This is the
        // acceptance criterion: the center lands on the geometric mean, not the arithmetic.
        let series: [Double?] = [50.0 / 1.5, 50.0 / 1.2, 50.0, 50.0 * 1.2, 50.0 * 1.5]
        let s = Baselines.rollingMeanSD(series, cfg: Baselines.hrvCfg)
        XCTAssertTrue(s.logDomain)
        XCTAssertEqual(s.baseline, 50.0, accuracy: 1e-9)             // geometric mean
        let arithmetic = series.compactMap { $0 }.reduce(0, +) / 5.0
        XCTAssertGreaterThan(arithmetic, s.baseline)                 // arithmetic is biased up

        // z is symmetric in the log domain: a multiplicative drop scores the mirror of
        // the matching rise. A linear z would underweight the low night (the audit's bug).
        let up = Baselines.deviation(50.0 * 1.3, state: s).z
        let down = Baselines.deviation(50.0 / 1.3, state: s).z
        XCTAssertEqual(up, -down, accuracy: 1e-9)
        XCTAssertEqual(Baselines.deviation(50.0, state: s).z, 0.0, accuracy: 1e-9)
    }

    func testRollingMeanSDWindowTruncates() {
        // 35 values; window 30 keeps the last 30. Last 30 are all 50 → mean 50.
        var vals: [Double?] = Array(repeating: 100.0, count: 5)
        vals.append(contentsOf: Array(repeating: 50.0, count: 30))
        let s = Baselines.rollingMeanSD(vals, cfg: Baselines.hrvCfg, window: 30)
        XCTAssertEqual(s.baseline, 50.0, accuracy: 1e-9)
        XCTAssertEqual(s.nValid, 30)
    }

    func testRollingMeanSDDropsOutOfRangeAndNil() {
        let s = Baselines.rollingMeanSD([nil, 50, 300, 50, 50], cfg: Baselines.hrvCfg)
        XCTAssertEqual(s.nValid, 3)  // nil + 300(>250) dropped
        XCTAssertEqual(s.baseline, 50.0, accuracy: 1e-9)
    }

    func testEmptyHistoryCalibrating() {
        let s = Baselines.rollingMeanSD([], cfg: Baselines.hrvCfg)
        XCTAssertEqual(s.status, .calibrating)
        XCTAssertEqual(s.nValid, 0)
    }

    func testRollingMeanSDFloorsSpreadInSameSpaceAsEWMA() {
        // A flat HRV series: rollingMeanSD (display band) must floor the spread in the SAME internal
        // abs-dev space as foldHistory/update (scoring baseline), so they agree near the floor. Before
        // the fix rollingMeanSD floored σ at floorSpread (0.08) while the EWMA path floored it at
        // floorSpread·1.253 (0.10) — a 1.253× mismatch.
        // Uses a long, settled MATURE series: while the baseline is young the EWMA path
        // inflates the spread floor (FER-673 anti-anchoring), so the two paths only meet at
        // the bare floor once the baseline is fully trusted and settled.
        let rolling = Baselines.rollingMeanSD(Array(repeating: 50.0, count: 50), cfg: Baselines.hrvCfg)
        let ewma = Baselines.foldHistory(Array(repeating: 50.0, count: 50), cfg: Baselines.hrvCfg)
        XCTAssertEqual(rolling.spread, ewma.spread, accuracy: 1e-9)
        XCTAssertEqual(rolling.spread, Baselines.hrvCfg.floorSpread, accuracy: 1e-9)   // 0.08, not 0.0638
    }

    // MARK: - Cold-start anti-anchoring (FER-673)

    /// Repro of the cold-start anchoring bug (documents that the log domain alone does
    /// NOT fix it). The first nights read artificially high; the seed fixes the center
    /// high; then the genuine (lower) nights arrive. In ln-space the z is symmetric, but
    /// that does nothing for the two mechanisms that actually anchor the baseline: the
    /// slow 14-night half-life and the hard-outlier gate rejecting the low nights the
    /// instant nValid ≥ seed. After the fix (fast early half-life + gate suspended while
    /// young) the center converges toward the true low within a week.
    func testColdStartConvergesToTrueCenterWithinAWeek() {
        // 4 artificially-high seed nights (~65 ms) then genuine nights at ~40 ms.
        let seedHigh: [Double?] = Array(repeating: 65.0, count: 4)
        let trueLow: [Double?] = Array(repeating: 40.0, count: 7)
        let s = Baselines.foldHistory(seedHigh + trueLow, cfg: Baselines.hrvCfg)
        // Within a week of genuine nights the center must have converged near 40, not
        // stayed anchored near 65 (the pre-fix behavior would sit >55 ms).
        XCTAssertLessThan(s.baseline, 45.0, "baseline should converge toward the true 40 ms, not stay anchored high")
        XCTAssertGreaterThan(s.baseline, 38.0)
    }

    /// The genuine low nights must actually FOLD during cold-start — the hard-outlier
    /// gate is suspended while the baseline is young, so a lower-but-real night after a
    /// high seed is not rejected as an outlier.
    func testColdStartOutlierGateSuspendedWhileYoung() {
        // Seed high, then one genuine low night that WOULD trip the mature 5σ gate.
        var s = Baselines.foldHistory(Array(repeating: 65.0, count: 4), cfg: Baselines.hrvCfg)
        let before = s.baseline
        s = Baselines.update(s, value: 40.0, cfg: Baselines.hrvCfg)
        XCTAssertLessThan(s.baseline, before, "young baseline must fold the genuine low night, not reject it")
    }

    // MARK: - Confidence shrinkage (FER-13)

    func testConfidenceRampEndpoints() {
        // Seed (and below) → floor; trust (and above) → 1.0.
        XCTAssertEqual(Baselines.confidence(nValid: 0), Baselines.confidenceFloor, accuracy: 1e-12)
        XCTAssertEqual(Baselines.confidence(nValid: Baselines.minNightsSeed),
                       Baselines.confidenceFloor, accuracy: 1e-12)
        XCTAssertEqual(Baselines.confidence(nValid: Baselines.minNightsTrust), 1.0, accuracy: 1e-12)
        XCTAssertEqual(Baselines.confidence(nValid: 100), 1.0, accuracy: 1e-12)
    }

    func testConfidenceRampMidpointAndMonotonic() {
        // Midpoint of [4, 14] = 9 → halfway between floor and 1.0.
        let mid = Baselines.confidenceFloor + (1.0 - Baselines.confidenceFloor) * 0.5
        XCTAssertEqual(Baselines.confidence(nValid: 9), mid, accuracy: 1e-12)
        // Strictly increasing across the provisional window.
        var prev = Baselines.confidence(nValid: Baselines.minNightsSeed)
        for n in (Baselines.minNightsSeed + 1)...Baselines.minNightsTrust {
            let c = Baselines.confidence(nValid: n)
            XCTAssertGreaterThan(c, prev)
            XCTAssertLessThanOrEqual(c, 1.0)
            prev = c
        }
    }
}
