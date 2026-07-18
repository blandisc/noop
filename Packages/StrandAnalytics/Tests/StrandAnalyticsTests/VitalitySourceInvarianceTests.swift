import XCTest
import CenitStore
@testable import StrandAnalytics

/// FER-640 — Vitality / Body Age must feed its «nocturnal RMSSD» (and nocturnal resting HR) from the
/// BAND source only. `CuerpoView` builds the inputs off `repo.displayDays`, which back-fills Apple
/// **SDNN** on band-less nights (FER-149); `VitalityInputsBuilder` then takes the MEDIAN and
/// `VitalityEngine` scores it against an RMSSD-by-age norm — mixing two constructs with no published
/// conversion (Task Force 1996; Shaffer & Ginsberg 2017). The fix masks the window with
/// `SourceLens.maskForBaseline(keep:.band)` (FER-631) before building. These tests pin that composition.
final class VitalitySourceInvarianceTests: XCTestCase {

    private func key(_ i: Int) -> String { String(format: "2026-06-%02d", i) }

    private func dm(_ day: String, hrv: Double?, rhr: Int?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 420, efficiency: 0.9, deepMin: 90, remMin: 90,
                    lightMin: 240, disturbances: 2, restingHr: rhr, avgHrv: hrv, recovery: 60,
                    strain: 10, exerciseCount: 1, spo2Pct: 97, skinTempDevC: 0.1, respRateBpm: 14)
    }

    private func build(_ window: [DailyMetric], chronoAge: Double = 40) -> VitalityEngine.Inputs {
        VitalityInputsBuilder.build(.init(
            chronoAge: chronoAge,
            nightlyRestingHR: window.compactMap { $0.restingHr.map(Double.init) },
            nightlyRMSSD: window.compactMap { $0.avgHrv },
            nightlySleepHours: window.compactMap { $0.totalSleepMin.map { $0 / 60 } },
            dailySteps: window.compactMap { $0.steps.map(Double.init) }))
    }

    // MARK: The nocturnal RMSSD/RHR the engine scores is the band-only median, Apple nights ignored

    /// A window of band nights (RMSSD ~50, RHR ~52) plus interleaved Apple SDNN nights (~90, RHR ~44).
    /// After masking to the band, the median RMSSD and RHR the engine sees must equal the band-only
    /// window's — and must NOT equal the contaminated (raw-window) median.
    func testNocturnalInputsAreBandOnly() {
        var window: [DailyMetric] = []
        var apple: Set<String> = []
        for i in 1...6 { window.append(dm(key(i), hrv: 50, rhr: 52)) }          // band nights
        for i in 7...12 { let k = key(i); apple.insert(k); window.append(dm(k, hrv: 90, rhr: 44)) }  // Apple SDNN

        let masked = SourceLens.maskForBaseline(window, keep: .band, appleDays: apple)
        let got = build(masked)
        let bandOnly = build(window.filter { !apple.contains($0.day) })
        let raw = build(window)

        XCTAssertEqual(got.rmssd, bandOnly.rmssd,
                       "the RMSSD factor must use the band-only median, unaffected by Apple SDNN nights")
        XCTAssertEqual(got.restingHR, bandOnly.restingHR,
                       "the resting-HR factor must use the band-only median too (same cross-source lens)")
        XCTAssertNotNil(got.rmssd)
        XCTAssertNotEqual(got.rmssd, raw.rmssd,
                          "the contaminated (mixed) median differs — proving the source mask is load-bearing")
    }

    // MARK: An Apple-only user scores with the HRV/RHR factors ABSENT, never SDNN-vs-band-norm

    /// If every night is Apple-only, masking to the band leaves no nocturnal RMSSD/RHR: the coverage
    /// gate drops both factors (rmssd/rmssdNorm nil) rather than comparing SDNN to the band RMSSD norm.
    /// Sleep + steps still carry Vitality, so the score is present — just without the HRV/RHR terms.
    func testAppleOnlyUserDropsHrvAndRhrFactors() {
        var window: [DailyMetric] = []
        var apple: Set<String> = []
        for i in 1...14 { let k = key(i); apple.insert(k); window.append(dm(k, hrv: 90, rhr: 44)) }

        let masked = SourceLens.maskForBaseline(window, keep: .band, appleDays: apple)
        var inputs = build(masked)
        inputs.steps = 9000                       // a non-band daily signal keeps the score alive
        inputs.sleepConsistency = 0.8

        XCTAssertNil(inputs.rmssd, "no band RMSSD → the HRV factor is absent, not SDNN scored vs the band norm")
        XCTAssertNil(inputs.rmssdNorm)
        XCTAssertNil(inputs.restingHR, "no band RHR → the resting-HR factor is absent too")

        let result = VitalityEngine.compute(inputs)
        XCTAssertNotNil(result, "sleep + steps + regularity still meet the honesty gate")
        XCTAssertFalse(result!.contributions.contains { $0.key == "hrv" }, "no HRV contribution on an Apple-only user")
        XCTAssertFalse(result!.contributions.contains { $0.key == "rhr" }, "no resting-HR contribution either")
    }

    // MARK: A strap-only user is the identity (bit-for-bit unchanged)

    func testStrapOnlyUserIsIdentity() {
        var window: [DailyMetric] = []
        for i in 1...14 { window.append(dm(key(i), hrv: 50, rhr: 52)) }
        let masked = SourceLens.maskForBaseline(window, keep: .band, appleDays: [])
        XCTAssertEqual(build(masked), build(window), "no Apple days → inputs are unchanged")
    }
}
