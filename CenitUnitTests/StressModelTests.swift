import XCTest
import WhoopStore
@testable import Cenit

/// Pins FER-224: `StressModel` must anchor "today" to the device's LOCAL day and ignore a
/// future-dated daily row (the UTC-bucketed ghost row of FER-226) — otherwise `days.last` reads that
/// empty row and the tile falls to "—" even when today has RHR/HRV. It must also derive from whatever
/// the layered `displayDays` provides (Apple-health fallback) on a strap-partial night.
final class StressModelTests: XCTestCase {

    private func dm(_ day: String, rhr: Int? = nil, hrv: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    /// 10 past days with a little spread so the baseline mean/SD are well-defined.
    private func baseline() -> [DailyMetric] {
        (1...10).map { i in dm(String(format: "2026-06-%02d", i), rhr: 58 + i % 4, hrv: 48 + Double(i % 5)) }
    }

    /// The reported bug: a future-dated row (e.g. a UTC "2026-06-18" while it's still the 17th
    /// locally) must NOT stand in for today. Today (17) has RHR/HRV, so the model derives.
    func testFutureRowIsIgnoredAndTodayDerives() {
        var days = baseline()
        days.append(dm("2026-06-17", rhr: 58, hrv: 38))   // real local "today"
        days.append(dm("2026-06-18", rhr: nil, hrv: nil)) // UTC ghost "tomorrow", empty
        let model = StressModel(days: days, stored: [], todayKey: "2026-06-17")
        XCTAssertNotNil(model, "the empty future row (18) must be ignored; today (17) has signal")
        XCTAssertEqual(model?.rhrToday, 58)
        XCTAssertEqual(model?.hrvToday, 38)
    }

    /// Strap-partial night where the layered row (displayDays) carries Apple's RHR/HRV: the tile
    /// must show a value, like HRV / resting-HR do — not "—".
    func testPartialTodayWithFallbackDerives() {
        var days = baseline()
        days.append(dm("2026-06-17", rhr: 57, hrv: 41))   // value present via the Apple-backed twin
        let model = StressModel(days: days, stored: [], todayKey: "2026-06-17")
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.hrvToday, 41)
    }

    /// No RHR/HRV anywhere and no stored value → honest nil (the tile renders "—").
    func testNoSignalReturnsNil() {
        let days = [dm("2026-06-16"), dm("2026-06-17")]   // every field nil
        XCTAssertNil(StressModel(days: days, stored: [], todayKey: "2026-06-17"))
    }

    /// Only future rows exist (none at or before today) → nil, never a future read.
    func testAllFutureReturnsNil() {
        let days = [dm("2026-06-18", rhr: 60, hrv: 50)]
        XCTAssertNil(StressModel(days: days, stored: [], todayKey: "2026-06-17"))
    }
}
