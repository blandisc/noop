import XCTest
@testable import StrandAnalytics
import StrandModels

final class StrainCeilingTests: XCTestCase {

    /// A day carrying only a strain value (the only field the ceiling reads).
    private func d(_ i: Int, strain: Double?) -> DailyMetric {
        DailyMetric(day: String(format: "2024-03-%02d", i), totalSleepMin: nil, efficiency: nil,
                    deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil,
                    avgHrv: nil, recovery: nil, strain: strain, exerciseCount: nil)
    }

    /// `n` days of a constant strain, so chronic load is well-defined.
    private func flat(_ n: Int, strain: Double) -> [DailyMetric] {
        (1...n).map { d($0, strain: strain) }
    }

    func testNilWithoutRecovery() {
        XCTAssertNil(StrainCeiling.recommend(days: flat(28, strain: 10), recovery: nil))
    }

    func testNilBelowMinChronic() {
        // 13 strain-days < minChronic (14) → no trustworthy chronic baseline.
        XCTAssertNil(StrainCeiling.recommend(days: flat(13, strain: 10), recovery: 60))
    }

    func testNilWhenNoStrainHistory() {
        let days = (1...20).map { d($0, strain: nil) }
        XCTAssertNil(StrainCeiling.recommend(days: days, recovery: 60))
    }

    func testRatioScalesWithRecovery() {
        let days = flat(28, strain: 10)
        let low  = StrainCeiling.recommend(days: days, recovery: 0)
        let mid  = StrainCeiling.recommend(days: days, recovery: 50)
        let high = StrainCeiling.recommend(days: days, recovery: 100)
        XCTAssertNotNil(low); XCTAssertNotNil(mid); XCTAssertNotNil(high)
        // Recovery maps linearly onto Gabbett's 0.8–1.3 sweet-spot band.
        XCTAssertEqual(low!.ratio,  0.8,  accuracy: 1e-9)
        XCTAssertEqual(mid!.ratio,  1.05, accuracy: 1e-9)
        XCTAssertEqual(high!.ratio, 1.3,  accuracy: 1e-9)
        // A higher ratio → a higher ceiling (monotone), and all share the same chronic base.
        XCTAssertLessThan(low!.strain, mid!.strain)
        XCTAssertLessThan(mid!.strain, high!.strain)
        XCTAssertEqual(low!.chronicLoad, high!.chronicLoad, accuracy: 1e-9)
    }

    func testCeilingIsRecoveryScaledMultipleOfChronic() {
        // With a flat strain history, chronic load == strainToLoad(that strain), and the ceiling
        // strain is trimpToStrain(chronic · ratio) — verify the whole chain end to end.
        let s = 10.0
        let rec = StrainCeiling.recommend(days: flat(28, strain: s), recovery: 100)!
        let chronic = ReadinessEngine.strainToLoad(s)
        XCTAssertEqual(rec.chronicLoad, chronic, accuracy: 1e-6)
        let expected = min(StrainScorer.maxStrain, StrainScorer.trimpToStrain(chronic * 1.3))
        XCTAssertEqual(rec.strain, expected, accuracy: 1e-6)
    }

    func testCeilingClampedTo21() {
        // A brutal chronic load with top recovery would overshoot 21 without the clamp.
        let rec = StrainCeiling.recommend(days: flat(28, strain: 20.9), recovery: 100)!
        XCTAssertLessThanOrEqual(rec.strain, StrainScorer.maxStrain)
    }

    func testTodayCapsAsOfReplay() {
        // Rows after `today` must not feed the chronic baseline.
        var days = flat(28, strain: 10)
        days.append(d(29, strain: 21))   // a future monster day
        let asOf28 = StrainCeiling.recommend(days: days, recovery: 60, today: "2024-03-28")!
        let all    = StrainCeiling.recommend(days: days, recovery: 60)!
        XCTAssertLessThan(asOf28.chronicLoad, all.chronicLoad)   // the spike lifts chronic only when included
    }
}
