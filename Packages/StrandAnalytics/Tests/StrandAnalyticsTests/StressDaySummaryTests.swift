import XCTest
@testable import StrandAnalytics

final class StressDaySummaryTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func at(_ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2025, month: 6, day: 20, hour: hour, minute: 0))!
    }
    private func pt(_ hour: Int, _ s: Double?) -> StressEngine.StressPoint { .init(date: at(hour), stress: s) }

    func testBucketsByPartPeakAndMean() {
        let curve = [pt(9, 1.0), pt(9, 1.2), pt(15, 2.5), pt(20, 0.5), pt(10, nil)]
        let sum = StressEngine.daySummary(curve, calendar: cal)
        XCTAssertEqual(sum.partMeans[.morning]!, 1.1, accuracy: 1e-9)
        XCTAssertEqual(sum.partMeans[.afternoon]!, 2.5, accuracy: 1e-9)
        XCTAssertEqual(sum.partMeans[.evening]!, 0.5, accuracy: 1e-9)
        XCTAssertNil(sum.partMeans[.night])                 // no-reading bucket dropped
        XCTAssertEqual(sum.peakHour, 15)                    // the 2.5 reading
        XCTAssertEqual(sum.dayMean!, (1.0 + 1.2 + 2.5 + 0.5) / 4, accuracy: 1e-9)
        XCTAssertFalse(sum.isEmpty)
    }

    func testEmptyWhenNoReadings() {
        let sum = StressEngine.daySummary([pt(9, nil), pt(15, nil)], calendar: cal)
        XCTAssertTrue(sum.isEmpty)
        XCTAssertNil(sum.dayMean); XCTAssertNil(sum.peakHour); XCTAssertTrue(sum.partMeans.isEmpty)
    }

    func testPartOfDayBins() {
        XCTAssertEqual(PartOfDay(hour: 6), .morning)
        XCTAssertEqual(PartOfDay(hour: 11), .morning)
        XCTAssertEqual(PartOfDay(hour: 13), .afternoon)
        XCTAssertEqual(PartOfDay(hour: 19), .evening)
        XCTAssertEqual(PartOfDay(hour: 23), .night)
        XCTAssertEqual(PartOfDay(hour: 2), .night)
    }
}
