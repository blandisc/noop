import XCTest
import WhoopStore
@testable import Cenit

/// Pins FER-228: `SleepDetailModel.build` must anchor "last night" to the device's LOCAL day and
/// ignore a future-dated daily row (the UTC-bucketed ghost row of FER-226). Otherwise `days.last`
/// reads that empty row and the detail shows "no data last night" even when today has a night.
@MainActor
final class SleepDetailModelTests: XCTestCase {

    private func dm(_ day: String, sleep: Double? = nil, disturbances: Int? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: disturbances, restingHr: nil, avgHrv: nil,
                    recovery: nil, strain: nil, exerciseCount: nil)
    }

    /// The reported risk: a future row (UTC "tomorrow") must NOT stand in for last night. Awakenings
    /// come from the `days` row, so they're the clean signal of which row was picked.
    func testFutureRowIgnored_awakeningsFromToday() {
        let today = dm("2026-06-17", sleep: 400, disturbances: 2)
        let future = dm("2026-06-18")   // empty UTC ghost row
        let model = SleepDetailModel.build(days: [today, future], sleeps: [], importedSleep: [:],
                                           appleHealthDays: [], loaded: true, todayKey: "2026-06-17")
        XCTAssertEqual(model.awakenings, 2, "must read today's row, not the empty future one")
    }

    /// Without a future row, behavior is unchanged.
    func testNoFutureRow_unchanged() {
        let today = dm("2026-06-17", sleep: 400, disturbances: 2)
        let model = SleepDetailModel.build(days: [today], sleeps: [], importedSleep: [:],
                                           appleHealthDays: [], loaded: true, todayKey: "2026-06-17")
        XCTAssertEqual(model.awakenings, 2)
    }
}
