import XCTest
import StrandModels
@testable import StrandAnalytics

/// FER-339 — the single source of truth for sleep need + debt, shared by the coach (InsightEngine)
/// and the Sleep Detail screen so they never disagree.
final class SleepMathTests: XCTestCase {

    private func day(_ i: Int) -> String { String(format: "2026-06-%02d", i + 1) }

    private func metric(_ i: Int, sleep: Double?) -> DailyMetric {
        DailyMetric(day: day(i), totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    private func days(_ sleeps: [Double?]) -> [DailyMetric] {
        sleeps.enumerated().map { metric($0.offset, sleep: $0.element) }
    }

    // MARK: needMinutes

    func testNeedFloorsAt7point5h() {
        XCTAssertEqual(SleepMath.needMinutes([]), 450)                       // no data → floor
        XCTAssertEqual(SleepMath.needMinutes(days([360, 360, 360])), 450)    // chronic short → floor, not 360
    }

    func testNeedIsMeanWhenAboveFloor() {
        XCTAssertEqual(SleepMath.needMinutes(days([520, 540, 560])), 540, accuracy: 0.001)
    }

    // MARK: debtMinutes

    func testNoDebtWhenAllAtOrAboveNeed() {
        // mean = need = 540; every night meets it → zero debt.
        XCTAssertEqual(SleepMath.debtMinutes(days([540, 540, 540])), 0, accuracy: 0.001)
    }

    func testDebtSumsPerNightShortfallVsNeed() {
        // need = max(450, mean[480,420]=450) = 450. debt = (450-480→0) + (450-420→30) = 30.
        XCTAssertEqual(SleepMath.debtMinutes(days([480, 420])), 30, accuracy: 0.001)
    }

    func testLongNightDoesNotPayOffShortNight() {
        // need = max(450, mean[600,300]=450) = 450. Per-night floored: 0 + 150 = 150 (surplus ignored).
        XCTAssertEqual(SleepMath.debtMinutes(days([600, 300])), 150, accuracy: 0.001)
    }

    func testOnlyTrailingWindowCounts() {
        // 10 nights: a huge deficit 8 nights ago must NOT count; only the last 7 do.
        var s: [Double?] = Array(repeating: 450, count: 10)
        s[0] = 0           // night 1 (off-window) — would add 450 of debt if counted
        XCTAssertEqual(SleepMath.debtMinutes(days(s)), 0, accuracy: 0.001)
    }

    // MARK: the whole point — engine and SleepMath agree

    func testEngineDebtEqualsSleepMath() {
        let d = days([300, 600, 420, 480, 510, 360, 450, 400])
        XCTAssertEqual(InsightEngine.sleepDebtMinutes(d), SleepMath.debtMinutes(d), accuracy: 0.001)
    }
}
