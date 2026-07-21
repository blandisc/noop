import XCTest
import CenitStore
import StrandAnalytics
@testable import Cenit

/// Pins `SourceLens.strapOnlyHistory` (FER-519): Apple SDNN must never enter the RMSSD baseline.
/// Relocated from the retired IntelligenceEngine; the applePrior/fold helpers are gone with it.
final class IntelligenceBaselinePriorTests: XCTestCase {

    /// Minimal DailyMetric carrying just the fields the prior reads.
    private func dm(_ day: String, hrv: Double? = nil, rhr: Int? = nil, resp: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, respRateBpm: resp)
    }

    // MARK: - strapOnlyHistory (FER-519): Apple SDNN must never enter the RMSSD baseline

    func testStrapOnlyHistoryExcludesAppleOnlyDaysAndIsIdentityWhenEmpty() {
        // hist holds two strap nights and one Apple-only night (band-less, its avgHrv is SDNN).
        let hist = [dm("2026-06-09", hrv: 80), dm("2026-06-10", hrv: 45), dm("2026-06-11", hrv: 46)]
        let appleOnly: Set<String> = ["2026-06-09"]

        let strap = SourceLens.strapOnlyHistory(hist, appleHealthDays: appleOnly)
        XCTAssertEqual(strap.map(\.day), ["2026-06-10", "2026-06-11"], "Apple-only day dropped")
        XCTAssertFalse(strap.contains { $0.day == "2026-06-09" })

        // Regression zero: no Apple-only days ⇒ identity (the strap-only / whoopOnly user is untouched).
        XCTAssertEqual(SourceLens.strapOnlyHistory(hist, appleHealthDays: []).map(\.day),
                       hist.map(\.day))
    }

    func testAppleOnlyDaysDoNotMoveTheRmssdBaseline() {
        // Strap RMSSD nights (~45 ms) interleaved with Apple-only SDNN nights (~80 ms — a different,
        // higher-scale construct). The fix must fold the strap-only slice; folding `hist` raw would drag
        // the RMSSD center toward the SDNN values.
        let strapNights = [dm("2026-06-10", hrv: 45), dm("2026-06-11", hrv: 46),
                           dm("2026-06-12", hrv: 44), dm("2026-06-13", hrv: 45)]
        let appleOnlyNights = [dm("2026-06-06", hrv: 80), dm("2026-06-07", hrv: 82),
                               dm("2026-06-08", hrv: 78), dm("2026-06-09", hrv: 81)]
        let hist = appleOnlyNights + strapNights            // chronological (oldest→newest)
        let appleOnly = Set(appleOnlyNights.map(\.day))

        let cleanFold = Baselines.foldHistory(
            SourceLens.strapOnlyHistory(hist, appleHealthDays: appleOnly).map { $0.avgHrv },
            cfg: Baselines.hrvCfg)
        // A user who never had any Apple-only days — the regression-zero reference.
        let referenceFold = Baselines.foldHistory(strapNights.map { $0.avgHrv }, cfg: Baselines.hrvCfg)
        // The buggy path: fold everything, Apple SDNN included.
        let contaminatedFold = Baselines.foldHistory(hist.map { $0.avgHrv }, cfg: Baselines.hrvCfg)

        XCTAssertEqual(cleanFold.baseline, referenceFold.baseline, accuracy: 1e-9,
                       "excluding Apple-only days == never having had them (regression zero)")
        XCTAssertEqual(cleanFold.nValid, 4, "only the 4 strap nights feed the RMSSD baseline")
        XCTAssertGreaterThan(contaminatedFold.baseline, cleanFold.baseline + 0.5,
                             "without the fix, Apple SDNN drags the RMSSD center upward — the bug")
    }
}
