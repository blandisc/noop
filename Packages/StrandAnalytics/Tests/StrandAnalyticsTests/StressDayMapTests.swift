import XCTest
@testable import StrandAnalytics

final class StressDayMapTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ minutes: Int) -> Date { t0.addingTimeInterval(TimeInterval(minutes * 60)) }
    private func pt(_ minutes: Int, _ stress: Double?) -> StressEngine.StressPoint {
        StressEngine.StressPoint(date: at(minutes), stress: stress)
    }
    private func ev(_ title: String, _ from: Int, _ to: Int, allDay: Bool = false) -> StressDayMap.DayEvent {
        StressDayMap.DayEvent(title: title, start: at(from), end: at(to), isAllDay: allDay)
    }

    func testPeakMatchesContainingEvent() {
        let curve = [pt(0, 0.4), pt(60, 1.2), pt(180, 2.6), pt(300, 0.8)] // peak at +180
        let events = [ev("Standup", 50, 70), ev("Revisión Q3", 170, 230)]
        let c = StressDayMap.peakCoincidence(curve, events: events)
        XCTAssertNotNil(c)
        XCTAssertEqual(c!.peakDate, at(180))
        XCTAssertEqual(c!.peakStress, 2.6, accuracy: 1e-9)
        XCTAssertEqual(c!.event?.title, "Revisión Q3")
    }

    func testAllDayEventNeverMatchesPeak() {
        let curve = [pt(0, 1.0), pt(180, 2.6)]
        // An all-day event spanning the whole window must NOT be credited with the peak.
        let c = StressDayMap.peakCoincidence(curve, events: [ev("Cumpleaños", -100, 600, allDay: true)])
        XCTAssertNotNil(c)
        XCTAssertNil(c!.event, "all-day events have no instant to cross")
    }

    func testPeakInOpenTimeHasNoEvent() {
        let curve = [pt(0, 1.0), pt(180, 2.6)]
        let c = StressDayMap.peakCoincidence(curve, events: [ev("Comida", 300, 360)])
        XCTAssertNotNil(c)
        XCTAssertNil(c!.event, "peak fell outside every event window")
    }

    func testNilWhenNoReadings() {
        let curve = [pt(0, nil), pt(180, nil)]
        XCTAssertNil(StressDayMap.peakCoincidence(curve, events: [ev("X", 0, 200)]))
        XCTAssertNil(StressDayMap.peakCoincidence([], events: []))
    }

    func testTieKeepsEarliestPeak() {
        let curve = [pt(60, 2.5), pt(180, 2.5)] // equal peaks → earliest wins (strict >)
        let c = StressDayMap.peakCoincidence(curve, events: [])
        XCTAssertEqual(c!.peakDate, at(60))
    }

    func testAverageStressDuringEvent() {
        let curve = [pt(170, 2.0), pt(200, 3.0), pt(400, 0.5)] // two readings inside [170,230]
        let avg = StressDayMap.averageStress(during: ev("Revisión Q3", 170, 230), in: curve)
        XCTAssertEqual(avg!, 2.5, accuracy: 1e-9)
    }

    func testAverageStressNilWhenNoOverlapOrAllDay() {
        let curve = [pt(0, 1.0), pt(60, 2.0)]
        XCTAssertNil(StressDayMap.averageStress(during: ev("Tarde", 300, 360), in: curve))
        XCTAssertNil(StressDayMap.averageStress(during: ev("Todo el día", 0, 600, allDay: true), in: curve))
    }
}
