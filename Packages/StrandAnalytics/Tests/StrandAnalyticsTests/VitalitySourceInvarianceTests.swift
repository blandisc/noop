import XCTest
import StrandModels
@testable import StrandAnalytics

/// FER-640 / F6 — Vitality / Body Age must not fold an Apple **SDNN** value into its nocturnal-RMSSD
/// factor (two constructs, no published conversion — Task Force 1996; Shaffer & Ginsberg 2017). The
/// cross-source columns are cleared (`SourceLens.clearBandColumns`) before building, so on Apple-only
/// data the coverage gate drops the HRV/RHR factors rather than scoring SDNN against the RMSSD-by-age norm.
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

    /// Apple-only: clearing the cross-source columns leaves no nocturnal RMSSD/RHR, so the coverage gate
    /// drops both factors (rmssd/rmssdNorm nil) rather than comparing an Apple SDNN to the band RMSSD norm.
    /// Sleep + steps still carry Vitality, so the score is present — just without the HRV/RHR terms.
    func testAppleOnlyUserDropsHrvAndRhrFactors() {
        var window: [DailyMetric] = []
        for i in 1...14 { window.append(dm(key(i), hrv: 90, rhr: 44)) }

        let masked = SourceLens.clearBandColumns(window)
        var inputs = build(masked)
        inputs.steps = 9000                       // a non-band daily signal keeps the score alive
        inputs.sleepConsistency = 0.8

        XCTAssertNil(inputs.rmssd, "cleared HRV → the HRV factor is absent, not SDNN scored vs the band norm")
        XCTAssertNil(inputs.rmssdNorm)
        XCTAssertNil(inputs.restingHR, "cleared RHR → the resting-HR factor is absent too")

        let result = VitalityEngine.compute(inputs)
        XCTAssertNotNil(result, "sleep + steps + regularity still meet the honesty gate")
        XCTAssertFalse(result!.contributions.contains { $0.key == "hrv" }, "no HRV contribution on an Apple-only user")
        XCTAssertFalse(result!.contributions.contains { $0.key == "rhr" }, "no resting-HR contribution either")
    }
}
