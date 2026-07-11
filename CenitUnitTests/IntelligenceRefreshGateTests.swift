import XCTest
import WhoopStore
@testable import Cenit

/// FER-881: pins `IntelligenceEngine.computedDailiesChanged`, the pure seam that gates `repo.refresh()`
/// after `analyzeRecent`. The invariant that matters: a recurring-user relaunch that recomputes
/// byte-identical scores must return `false` (skip the redundant rebuild), while ANY new or changed
/// day must return `true` (the fresh score surfaces). Over-reporting is safe; under-reporting would
/// hide a score, so these cases guard the asymmetry.
final class IntelligenceRefreshGateTests: XCTestCase {

    private func dm(_ day: String, recovery: Double? = nil, strain: Double? = nil,
                    hrv: Double? = nil, rhr: Int? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: recovery,
                    strain: strain, exerciseCount: nil)
    }

    func testIdenticalRowsAreNotAChange() {
        let rows = [dm("2026-07-09", recovery: 61, strain: 12.4), dm("2026-07-10", recovery: 55, strain: 9.1)]
        XCTAssertFalse(IntelligenceEngine.computedDailiesChanged(rows, vsStored: rows))
    }

    func testANewDayIsAChange() {
        let stored = [dm("2026-07-09", recovery: 61)]
        let fresh = [dm("2026-07-09", recovery: 61), dm("2026-07-10", recovery: 55)]
        XCTAssertTrue(IntelligenceEngine.computedDailiesChanged(fresh, vsStored: stored))
    }

    func testAChangedValueOnAnExistingDayIsAChange() {
        let stored = [dm("2026-07-10", recovery: 55, strain: 9.1)]
        let fresh = [dm("2026-07-10", recovery: 58, strain: 9.1)]   // recovery moved
        XCTAssertTrue(IntelligenceEngine.computedDailiesChanged(fresh, vsStored: stored))
    }

    func testAStalePriorOnlyDayIsNotAChange() {
        // The engine no longer scores 07-08 (out of window); it stays in the store but must not force a refresh.
        let stored = [dm("2026-07-08", recovery: 70), dm("2026-07-10", recovery: 55)]
        let fresh = [dm("2026-07-10", recovery: 55)]
        XCTAssertFalse(IntelligenceEngine.computedDailiesChanged(fresh, vsStored: stored))
    }

    func testEmptyStoreIsAChange() {
        XCTAssertTrue(IntelligenceEngine.computedDailiesChanged([dm("2026-07-10", recovery: 55)], vsStored: []))
    }

    func testEmptyFreshIsNotAChange() {
        XCTAssertFalse(IntelligenceEngine.computedDailiesChanged([], vsStored: [dm("2026-07-10", recovery: 55)]))
    }
}
