import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// Unit tests for the WHOOP 5.0/MG skin-temperature pipeline in AnalyticsEngine
/// (macOS parity with the Android SkinTempAnalyticsTest).
///
/// Two parts:
///  1. `AnalyticsEngine.wornNightlySkinTempC` — the wear-gated nightly-mean logic (the part
///     that turns raw skin_temp_raw@73 samples into a trustworthy per-night value).
///  2. The seed→deviation flow over `Baselines.foldHistory`/`Baselines.deviation` with the
///     standard `skin_temp` config — pinning the honest cold-start gate (<4 nights ⇒ no
///     skinTempDevC) and that a real elevation surfaces as a positive deviation once seeded.
///
/// SCALE NOTE: the Swift WHOOP5 decoder defines °C = raw/128 (the AS6221's native
/// 7.8125 m°C/LSB; see Interpreter.swift skin_temp_raw@73) — the fixtures here therefore
/// encode raw = °C × 128, NOT the ×100 the Android decoder/tests use for the same register.
/// Worn nightly values seen on real hardware were ~33–35 °C, off-wrist/charging ~22–27 °C —
/// which is exactly the contamination the wear-gate excludes. All values APPROXIMATE.
final class SkinTempAnalyticsTests: XCTestCase {

    private func session(start: Int, durSec: Int) -> SleepSession {
        SleepSession(start: start, end: start + durSec, efficiency: 0.9,
                     stages: [], restingHR: 50, avgHRV: 60.0)
    }

    private func hr(_ ts: Int, bpm: Int = 55) -> HRSample { HRSample(ts: ts, bpm: bpm) }
    /// raw = °C × 128 (Swift decoder scale): 34 °C → 4352, 36 °C → 4608, 22 °C → 2816.
    private func skin(_ ts: Int, rawX128: Int) -> SkinTempSample { SkinTempSample(ts: ts, raw: rawX128) }

    // MARK: - wornNightlySkinTempC

    func testMeanOverWornInBedSamples() throws {
        let start = 1_000_000
        let sess = [session(start: start, durSec: 600)]
        let hrs = (0..<600).map { hr(start + $0) }
        let temps = (0..<600).map { skin(start + $0, rawX128: 4352) }  // 34.00 °C
        let mean = try XCTUnwrap(AnalyticsEngine.wornNightlySkinTempC(sess, hr: hrs, skinTemp: temps))
        XCTAssertEqual(mean, 34.0, accuracy: 1e-9)
    }

    func testExcludesSamplesWithoutConcurrentWornHr() {
        // The strap streams HR only on-wrist; skin-temp samples with no concurrent worn BPM drop.
        let start = 2_000_000
        let sess = [session(start: start, durSec: 600)]
        let temps = (0..<600).map { skin(start + $0, rawX128: 4352) }
        XCTAssertNil(AnalyticsEngine.wornNightlySkinTempC(sess, hr: [], skinTemp: temps))
    }

    func testExcludesDaytimeSamplesOutsideTheSleepSession() throws {
        // Daytime samples are in worn range (36 °C) AND have worn HR, but fall OUTSIDE the in-bed
        // session window, so only the in-bed 34 °C samples count. Isolates the session-window gate.
        let night = 3_000_000
        let sess = [session(start: night, durSec: 600)]
        let inBedHr = (0..<600).map { hr(night + $0) }
        let inBedTemp = (0..<600).map { skin(night + $0, rawX128: 4352) }
        let day = night + 10_000
        let dayHr = (0..<600).map { hr(day + $0) }
        let dayTemp = (0..<600).map { skin(day + $0, rawX128: 4608) }  // 36 °C, worn-range, daytime
        let mean = try XCTUnwrap(AnalyticsEngine.wornNightlySkinTempC(
            sess, hr: inBedHr + dayHr, skinTemp: inBedTemp + dayTemp))
        XCTAssertEqual(mean, 34.0, accuracy: 1e-9)
    }

    func testExcludesOnChargerAmbientEvenInBed() {
        // Mid-night on charger: HR still has stray worn-range values but skin temp drifts to
        // ambient (~22 °C) — which passes the strap's looser decode gate but is below the worn
        // floor of 28 °C.
        let start = 4_000_000
        let sess = [session(start: start, durSec: 600)]
        let hrs = (0..<600).map { hr(start + $0) }
        let temps = (0..<600).map { skin(start + $0, rawX128: 2816) }  // 22 °C ambient
        XCTAssertNil(AnalyticsEngine.wornNightlySkinTempC(sess, hr: hrs, skinTemp: temps))
    }

    func testBelowMinSamplesIsNil() {
        let start = 5_000_000
        let sess = [session(start: start, durSec: 100)]
        let hrs = (0..<100).map { hr(start + $0) }
        let temps = (0..<100).map { skin(start + $0, rawX128: 4352) }  // 100 < minSkinTempSamples
        XCTAssertNil(AnalyticsEngine.wornNightlySkinTempC(sess, hr: hrs, skinTemp: temps))
    }

    func testEmptyInputsAreNil() {
        XCTAssertNil(AnalyticsEngine.wornNightlySkinTempC([], hr: [], skinTemp: []))
    }

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

    // MARK: - WHOOP 4.0 offset (FER-240)

    /// The raw distribution from a real WHOOP 4.0 backup's worn sleep window (p05=559, p50=652,
    /// p95=907). The 4.0's v24 record drops the integer part of the AS6221 register, so raw/128 ≈ 5 °C
    /// — under the 28 °C gate — and the un-offset path discards every sample. A representative spread
    /// repeated past minSkinTempSamples.
    private func whoop4WornNight(start: Int)
        -> (sessions: [SleepSession], hr: [HRSample], skin: [SkinTempSample]) {
        let raws = [559, 600, 624, 652, 690, 762, 850, 907]  // spans the real p05…p95
        let n = 600  // > minSkinTempSamples (300)
        let sess = [session(start: start, durSec: n)]
        let hrs = (0..<n).map { hr(start + $0) }
        let skins = (0..<n).map { SkinTempSample(ts: start + $0, raw: raws[$0 % raws.count]) }
        return (sess, hrs, skins)
    }

    func testWhoop4RawIsDiscardedWithoutOffset() {
        // Bug state: with offset 0 (the 5.0 path), every 4.0 sample converts to ~5 °C and falls under
        // the 28 °C floor → nil → skinTempDevC never computes. This is what the user saw.
        let night = whoop4WornNight(start: 6_000_000)
        XCTAssertNil(AnalyticsEngine.wornNightlySkinTempC(
            night.sessions, hr: night.hr, skinTemp: night.skin, skinTempOffsetC: 0))
    }

    func testWhoop4OffsetRestoresPhysiologicalMean() throws {
        // Fix: +28.5 °C lands the worn night in the physiological 32–36 °C band, so it survives the
        // gate and the nightly mean (hence skinTempDevC) is non-nil.
        let night = whoop4WornNight(start: 7_000_000)
        let mean = try XCTUnwrap(AnalyticsEngine.wornNightlySkinTempC(
            night.sessions, hr: night.hr, skinTemp: night.skin, skinTempOffsetC: 28.5))
        XCTAssertGreaterThanOrEqual(mean, 32.0)
        XCTAssertLessThanOrEqual(mean, 36.0)
    }

    func testWhoop5PathUnchangedAtOffsetZero() throws {
        // The 5.0 streams the full register → offset 0 must reproduce the existing 34.0 °C result,
        // so the default keeps the 5.0 path identical.
        let start = 8_000_000
        let sess = [session(start: start, durSec: 600)]
        let hrs = (0..<600).map { hr(start + $0) }
        let temps = (0..<600).map { skin(start + $0, rawX128: 4352) }  // 34.00 °C
        let mean = try XCTUnwrap(AnalyticsEngine.wornNightlySkinTempC(
            sess, hr: hrs, skinTemp: temps, skinTempOffsetC: 0))
        XCTAssertEqual(mean, 34.0, accuracy: 1e-9)
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
