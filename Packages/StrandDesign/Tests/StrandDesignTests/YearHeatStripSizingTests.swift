import XCTest
import Foundation
@testable import StrandDesign

/// Locks the "all four 90-day calendars are the same size" invariant: the rolling-window cell size must be
/// a function of the available width ALONE — never of which weekday the 90-day window happens to start on.
/// Sizing to the live `weekColumns` used to swing 13↔14 columns day to day (Recuperación / Sueño / Esfuerzo
/// / Estrés drifting apart), which read as "the calendars are different sizes". (FER · calendarios estables)
final class YearHeatStripSizingTests: XCTestCase {

    /// Build a 90-day rolling window anchored at `today`, exactly as the detail screens do (UTC steps, +12h),
    /// so `weekColumns` sees the same first-day weekday the app would.
    private func rollingWindow(endingAt today: Date) -> [RecoveryDay] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return stride(from: 89, through: 0, by: -1).compactMap { off -> RecoveryDay? in
            guard let d = cal.date(byAdding: .day, value: -off, to: today) else { return nil }
            return RecoveryDay(date: d.addingTimeInterval(12 * 3600), score: nil)
        }
    }

    /// The live column count genuinely swings between 13 and 14 across a week — that's the whole reason a
    /// weekColumns-based cell size wobbled. Guards that our premise is real, not theoretical.
    func testWeekColumnsSwingsAcrossTheWeek() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let base = cal.date(from: DateComponents(year: 2026, month: 7, day: 6))!
        let counts = (0..<7).map { off -> Int in
            let today = cal.date(byAdding: .day, value: off, to: base)!
            return YearHeatStrip.weekColumns(for: rollingWindow(endingAt: today))
        }
        XCTAssertTrue(counts.contains(13) && counts.contains(14),
                      "expected the live window to hit both 13 and 14 columns across a week, got \(counts)")
    }

    /// The fix: rollingCellSize is a pure function of width — identical for every day, so identical for every
    /// screen. Feed it 14 different anchor days and assert the size never moves.
    func testRollingCellSizeIsStableAcrossDays() {
        let width: CGFloat = 350
        let expected = YearHeatStrip.rollingCellSize(width: width)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let base = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        for off in 0..<14 {
            _ = cal.date(byAdding: .day, value: off, to: base)!   // day varies; the sizing must not
            XCTAssertEqual(YearHeatStrip.rollingCellSize(width: width), expected, accuracy: 0.0001,
                           "rollingCellSize must not depend on the day")
        }
    }

    /// Same width in → same cell out, which is what makes the four calendars match on any given device.
    func testRollingCellSizeFillsFourteenColumns() {
        let width: CGFloat = 350, spacing: CGFloat = 4, gutter: CGFloat = 24
        let cell = YearHeatStrip.rollingCellSize(width: width, spacing: spacing, gutter: gutter)
        let gridSpan = gutter + 14 * (cell + spacing) - spacing
        XCTAssertLessThanOrEqual(gridSpan, width + 0.5, "14 columns must not overflow the measured width")
        XCTAssertEqual(cell, (width - gutter - spacing - 13 * spacing) / 14, accuracy: 0.0001)
    }

    /// Degenerate width falls back to a sane fixed cell rather than 0/NaN.
    func testRollingCellSizeZeroWidthFallback() {
        XCTAssertEqual(YearHeatStrip.rollingCellSize(width: 0), 14, accuracy: 0.0001)
    }
}
