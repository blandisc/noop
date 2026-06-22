import XCTest
@testable import StrandAnalytics

final class StreakMathTests: XCTestCase {

    private func day(_ i: Int) -> String { String(format: "2026-06-%02d", i) }
    private func days(_ range: ClosedRange<Int>) -> [String] { range.map(day) }

    // MARK: - Basic runs

    func testEmptyIsZero() {
        let s = StreakMath.streaks(eligibleDays: [], adherent: [])
        XCTAssertEqual(s.current, 0)
        XCTAssertEqual(s.best, 0)
    }

    func testAllAdherent() {
        let elig = days(1...5)
        let s = StreakMath.streaks(eligibleDays: elig, adherent: Set(elig))
        XCTAssertEqual(s.current, 5)
        XCTAssertEqual(s.best, 5)
    }

    func testNoneAdherent() {
        let s = StreakMath.streaks(eligibleDays: days(1...5), adherent: [])
        XCTAssertEqual(s.current, 0)
        XCTAssertEqual(s.best, 0)
    }

    // MARK: - Breaks & gaps

    /// A gap in the middle resets the run; the trailing run is what's current, the longest is best.
    func testBreakResetsCurrentButKeepsBest() {
        // adherent: 1,2,3,4  (miss 5)  6,7   → best 4, current 2
        let elig = days(1...7)
        let adherent: Set<String> = [day(1), day(2), day(3), day(4), day(6), day(7)]
        let s = StreakMath.streaks(eligibleDays: elig, adherent: adherent)
        XCTAssertEqual(s.best, 4)
        XCTAssertEqual(s.current, 2)
        XCTAssertGreaterThanOrEqual(s.best, s.current)
    }

    /// A miss on the last eligible day zeroes the current streak even though earlier runs existed.
    func testMissOnLastDayZeroesCurrent() {
        let elig = days(1...5)
        let adherent: Set<String> = [day(1), day(2), day(3), day(4)]   // miss 5
        let s = StreakMath.streaks(eligibleDays: elig, adherent: adherent)
        XCTAssertEqual(s.current, 0)
        XCTAssertEqual(s.best, 4)
    }

    /// Pending today is modeled by leaving it out of `eligibleDays`: the trailing run is yesterday's,
    /// so an unmarked today never reads as a break.
    func testPendingTodayExcludedKeepsCurrent() {
        // Marked through day 4 (all adherent); day 5 (today) is pending → not in eligibleDays.
        let elig = days(1...4)
        let s = StreakMath.streaks(eligibleDays: elig, adherent: Set(elig))
        XCTAssertEqual(s.current, 4)
        XCTAssertEqual(s.best, 4)
    }

    /// Multiple runs: the best is the longest, current is the last.
    func testMultipleRunsPickLongestAndTrailing() {
        // 1,2,3 (miss 4) 5,6,7,8,9 (miss 10) 11  → runs 3, 5, 1 → best 5, current 1
        let elig = days(1...11)
        let adherent: Set<String> = [day(1), day(2), day(3),
                                     day(5), day(6), day(7), day(8), day(9),
                                     day(11)]
        let s = StreakMath.streaks(eligibleDays: elig, adherent: adherent)
        XCTAssertEqual(s.best, 5)
        XCTAssertEqual(s.current, 1)
    }

    /// An adherent day outside the eligible window doesn't count (the caller scopes the window).
    func testAdherentOutsideEligibleIgnored() {
        let elig = days(3...5)
        let adherent: Set<String> = [day(1), day(2), day(3), day(4), day(5)]
        let s = StreakMath.streaks(eligibleDays: elig, adherent: adherent)
        XCTAssertEqual(s.current, 3)
        XCTAssertEqual(s.best, 3)
    }
}
