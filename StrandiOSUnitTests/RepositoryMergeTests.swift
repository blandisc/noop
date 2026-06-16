import XCTest
import WhoopStore
@testable import NOOP

/// Pins the FER-62 dashboard merge: Apple Health is the lowest-precedence base, on-device computed
/// rows fill its gaps, and imported strap rows win over everything — so the strap always beats Apple
/// Health. `appleDays` tracks only the days that stayed Apple-sourced, for the source badge.
@MainActor
final class RepositoryMergeTests: XCTestCase {

    private func dm(_ day: String, hrv: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    func testImportedStrapBeatsComputedAndApple() {
        let r = Repository.mergeDaily(imported: [dm("2026-06-10", hrv: 50)],
                                      computed: [dm("2026-06-10", hrv: 99)],
                                      apple: [dm("2026-06-10", hrv: 77)])
        XCTAssertEqual(r.days.count, 1)
        XCTAssertEqual(r.days[0].avgHrv, 50)                 // imported strap wins
        XCTAssertFalse(r.appleDays.contains("2026-06-10"))   // strap-covered → not an Apple day
    }

    func testComputedStrapBeatsAppleWhenNoImport() {
        let r = Repository.mergeDaily(imported: [], computed: [dm("2026-06-10", hrv: 60)],
                                      apple: [dm("2026-06-10", hrv: 77)])
        XCTAssertEqual(r.days[0].avgHrv, 60)                 // on-device strap beats Apple
        XCTAssertFalse(r.appleDays.contains("2026-06-10"))
    }

    func testAppleFillsOnlyDaysNoStrapCovers() {
        let r = Repository.mergeDaily(imported: [dm("2026-06-10", hrv: 50)], computed: [],
                                      apple: [dm("2026-06-09", hrv: 70), dm("2026-06-10", hrv: 77)])
        XCTAssertEqual(r.days.count, 2)
        XCTAssertEqual(r.days.first(where: { $0.day == "2026-06-09" })?.avgHrv, 70)  // apple-only day
        XCTAssertTrue(r.appleDays.contains("2026-06-09"))
        XCTAssertFalse(r.appleDays.contains("2026-06-10"))   // strap day, even though Apple had it too
    }

    func testResultSortedByDayAscending() {
        let r = Repository.mergeDaily(imported: [], computed: [],
                                      apple: [dm("2026-06-12"), dm("2026-06-10"), dm("2026-06-11")])
        XCTAssertEqual(r.days.map(\.day), ["2026-06-10", "2026-06-11", "2026-06-12"])
        XCTAssertEqual(r.appleDays, ["2026-06-10", "2026-06-11", "2026-06-12"])
    }
}
