import XCTest
@testable import StrandAnalytics

/// Unit tests for the skin-temperature baseline flow (macOS parity with the Android
/// SkinTempAnalyticsTest): the seed→deviation flow over `Baselines.foldHistory` /
/// `Baselines.deviation` with the standard `skin_temp` config — pinning the honest cold-start
/// gate (<4 nights ⇒ no skinTempDevC) and that a real elevation surfaces as a positive deviation
/// once seeded. All values APPROXIMATE.
final class SkinTempAnalyticsTests: XCTestCase {

    // MARK: - seed → deviation (skin_temp baseline)

    private let skinCfg = Baselines.metricCfg["skin_temp"]!

    func testColdStartBelowSeedBaselineNotUsable() {
        // 3 nightly means (< minNightsSeed = 4): still CALIBRATING → skinTempDevC stays nil.
        let nights: [Double?] = [33.5, 33.6, 33.4]
        XCTAssertFalse(Baselines.foldHistory(nights, cfg: skinCfg).usable)
    }

    func testAtSeedUsableElevationShowsPositiveDeviation() {
        // 4 baseline nights ~33.5 °C; a +0.8 °C night surfaces as a clearly positive deviation —
        // the signal the illness watch reads as its skin-temp flag (fires at ≥ +0.6 °C).
        let nights: [Double?] = [33.5, 33.4, 33.6, 33.5]
        let base = Baselines.foldHistory(nights, cfg: skinCfg)
        XCTAssertTrue(base.usable, "4 valid nights must seed a usable skin-temp baseline")
        let dev = Baselines.deviation(34.3, state: base).delta
        XCTAssertGreaterThan(dev, 0.5, "a +0.8 °C night must read as a clear positive deviation")
    }

    func testConstantOffsetCancelsInDeviation() {
        // The UI shows deviation (nightly − baseline). A constant per-band offset added to BOTH the
        // night and the baseline cancels, so the displayed value is robust to the exact offset — its
        // only job is to clear the gate. The cancellation is linear (independent of magnitude); we use
        // a small in-band shift so both baselines stay inside foldHistory's plausibility band and are
        // seeded identically (a large shift like +28.5 would push the base nights to ~62 °C, outside
        // that band — a test artifact, not the production path, where the offset keeps nights ~33–35 °C).
        let nights: [Double?] = [33.5, 33.4, 33.6, 33.5]
        let tonight = 34.3
        let devNoOffset = Baselines.deviation(
            tonight, state: Baselines.foldHistory(nights, cfg: skinCfg)).delta
        let k = 0.5
        let devShifted = Baselines.deviation(
            tonight + k, state: Baselines.foldHistory(nights.map { $0.map { $0 + k } }, cfg: skinCfg)).delta
        XCTAssertEqual(devNoOffset, devShifted, accuracy: 1e-9,
                       "a constant offset must cancel in the baseline deviation")
    }
}
