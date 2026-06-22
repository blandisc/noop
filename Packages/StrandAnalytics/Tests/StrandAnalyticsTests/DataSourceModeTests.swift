import XCTest
import WhoopStore
@testable import StrandAnalytics

/// Pins the FER-484 data-source policy: the mode flags decide which sources are read, and
/// `DataSourcePolicy.filter` empties the excluded ones while `combined` stays the identity (so the merge
/// it feeds is byte-for-byte the historical result — regression zero).
final class DataSourceModeTests: XCTestCase {

    private func dm(_ day: String) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    func testModeFlags() {
        XCTAssertTrue(DataSourceMode.combined.usesWhoop)
        XCTAssertTrue(DataSourceMode.combined.usesAppleHealth)
        XCTAssertTrue(DataSourceMode.whoopOnly.usesWhoop)
        XCTAssertFalse(DataSourceMode.whoopOnly.usesAppleHealth)
        XCTAssertFalse(DataSourceMode.appleHealthOnly.usesWhoop)
        XCTAssertTrue(DataSourceMode.appleHealthOnly.usesAppleHealth)
    }

    func testCombinedIsIdentity() {
        let i = [dm("2026-06-10")], c = [dm("2026-06-11")], a = [dm("2026-06-12")]
        let f = DataSourcePolicy.filter(.combined, imported: i, computed: c, apple: a)
        XCTAssertEqual(f.imported, i)   // identity → mergeDaily sees exactly today's input
        XCTAssertEqual(f.computed, c)
        XCTAssertEqual(f.apple, a)
    }

    func testWhoopOnlyDropsApple() {
        let i = [dm("2026-06-10")], c = [dm("2026-06-11")], a = [dm("2026-06-12")]
        let f = DataSourcePolicy.filter(.whoopOnly, imported: i, computed: c, apple: a)
        XCTAssertEqual(f.imported, i)
        XCTAssertEqual(f.computed, c)
        XCTAssertTrue(f.apple.isEmpty)  // Apple never enters the merge or the baseline
    }

    func testAppleHealthOnlyDropsStrap() {
        let i = [dm("2026-06-10")], c = [dm("2026-06-11")], a = [dm("2026-06-12")]
        let f = DataSourcePolicy.filter(.appleHealthOnly, imported: i, computed: c, apple: a)
        XCTAssertTrue(f.imported.isEmpty)   // no strap row enters the merge
        XCTAssertTrue(f.computed.isEmpty)
        XCTAssertEqual(f.apple, a)
    }

    /// Persistence (`SourceModeStore`) round-trips through these raw strings — pin them so a rename
    /// can't silently reset a user's stored mode to the default.
    func testRawValuesStable() {
        XCTAssertEqual(DataSourceMode.combined.rawValue, "combined")
        XCTAssertEqual(DataSourceMode.whoopOnly.rawValue, "whoopOnly")
        XCTAssertEqual(DataSourceMode.appleHealthOnly.rawValue, "appleHealthOnly")
        XCTAssertEqual(DataSourceMode(rawValue: "whoopOnly"), .whoopOnly)
    }
}
