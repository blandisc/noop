import XCTest
import StrandAnalytics
@testable import Cenit

/// Pins Spec L1b (A3): the Apple workout-HR window for estimated «Carga del día» is the local
/// civil day of `now` only — from local midnight through `now` — so a years-deep history cannot
/// flood the refresh path or get truncated by ORDER BY ts ASC LIMIT.
final class StrainEstimateWindowTests: XCTestCase {

    func testAppleHrWindowIsLocalMidnightThroughNow() {
        // 2026-03-15 15:30:00 UTC with CDMX fixed offset (−6 h) → local 09:30 on the 15th.
        // A sample just before local midnight (previous civil day) must fall outside `from`.
        let tz = -6 * 3_600
        let nowTs = 1_773_588_600 // 2026-03-15 15:30:00 UTC
        let now = Date(timeIntervalSince1970: TimeInterval(nowTs))
        let window = Repository.appleHrWindow(now: now, tzOffsetSeconds: tz)

        let expectedFrom = AnalyticsEngine.localMidnight(nowTs, tzOffsetSeconds: tz)
        XCTAssertEqual(Int(window.from.timeIntervalSince1970), expectedFrom)
        XCTAssertGreaterThanOrEqual(window.to.timeIntervalSince1970, now.timeIntervalSince1970)
        XCTAssertEqual(window.to.timeIntervalSince1970, now.timeIntervalSince1970)

        // Synthetic samples straddling local midnight: only post-midnight stays in-window.
        let justBeforeMidnight = expectedFrom - 1
        let justAfterMidnight = expectedFrom
        let midAfternoon = nowTs
        XCTAssertLessThan(justBeforeMidnight, Int(window.from.timeIntervalSince1970))
        XCTAssertGreaterThanOrEqual(justAfterMidnight, Int(window.from.timeIntervalSince1970))
        XCTAssertLessThanOrEqual(midAfternoon, Int(window.to.timeIntervalSince1970))
    }

    func testAppleHrWindowUTCOffsetZero() {
        let nowTs = 1_700_000_000 // fixed instant
        let now = Date(timeIntervalSince1970: TimeInterval(nowTs))
        let window = Repository.appleHrWindow(now: now, tzOffsetSeconds: 0)
        XCTAssertEqual(Int(window.from.timeIntervalSince1970),
                       AnalyticsEngine.localMidnight(nowTs, tzOffsetSeconds: 0))
        XCTAssertEqual(window.to, now)
    }
}
