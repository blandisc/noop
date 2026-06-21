import XCTest
@testable import StrandAnalytics

final class StressMomentsTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ minutes: Int) -> Date { t0.addingTimeInterval(TimeInterval(minutes * 60)) }
    private func pt(_ minutes: Int, _ stress: Double?) -> StressEngine.StressPoint {
        StressEngine.StressPoint(date: at(minutes), stress: stress)
    }
    private func ev(_ title: String, _ from: Int, _ to: Int, allDay: Bool = false) -> StressDayMap.DayEvent {
        StressDayMap.DayEvent(title: title, start: at(from), end: at(to), isAllDay: allDay)
    }

    // A flat calm day never crosses the floor → no activated moments, but it still has a calmest reading.
    func testFlatCalmDayHasNoActivatedMoments() {
        let curve = (0..<20).map { pt($0 * 3, 0.5) }
        let m = StressMoments.detect(curve)
        XCTAssertTrue(m.activated.isEmpty)
        XCTAssertNotNil(m.calmest)
        XCTAssertEqual(m.calmest!.stress, 0.5, accuracy: 1e-9)
    }

    // One long episode (a plateau of close-together high buckets) is listed ONCE, not many times.
    func testSingleEpisodeListedOnce() {
        // 11 readings over 30 min, all high (one meeting). Only the single max should surface.
        let curve = (0...10).map { pt(100 + $0 * 3, 2.0 + Double($0 % 3) * 0.2) }
        let m = StressMoments.detect(curve)
        XCTAssertEqual(m.activated.count, 1, "buckets within 45 min are the same episode")
    }

    // Genuinely separate spikes (≥45 min apart) are listed separately, strongest first.
    func testSeparatePeaksRankedStrongestFirst() {
        let curve = [pt(0, 2.6), pt(60, 2.2), pt(180, 2.4), pt(240, 0.6)]
        let m = StressMoments.detect(curve)
        XCTAssertEqual(m.activated.map { $0.stress }, [2.6, 2.4, 2.2])
        XCTAssertEqual(m.activated.first!.date, at(0))
    }

    // Two close peaks (<45 min) collapse to the higher one only.
    func testMinSeparationCollapsesClosePeaks() {
        let curve = [pt(0, 2.6), pt(30, 2.5), pt(120, 1.4)]  // 0 and 30 are one episode
        let m = StressMoments.detect(curve)
        XCTAssertEqual(m.activated.map { $0.stress }, [2.6, 1.4])
    }

    // Caps at maxActivated even with many separated spikes.
    func testCapsAtTopThree() {
        let curve = [pt(0, 2.8), pt(60, 2.6), pt(120, 2.4), pt(180, 2.2), pt(240, 2.0)]
        let m = StressMoments.detect(curve)
        XCTAssertEqual(m.activated.count, 3)
        XCTAssertEqual(m.activated.map { $0.stress }, [2.8, 2.6, 2.4])
    }

    // No readings at all → empty / nil, never a fabricated moment.
    func testNoReadings() {
        let m = StressMoments.detect([pt(0, nil), pt(60, nil)])
        XCTAssertTrue(m.activated.isEmpty)
        XCTAssertNil(m.calmest)
    }

    // Gaps (nil) between readings don't break ranking.
    func testGapsAreSkipped() {
        let curve = [pt(0, 2.6), pt(30, nil), pt(120, 2.3), pt(150, nil)]
        let m = StressMoments.detect(curve)
        XCTAssertEqual(m.activated.map { $0.stress }, [2.6, 2.3])
    }

    // A moment is crossed with the timed event containing it; all-day events never cross.
    func testMomentCrossesContainingEvent() {
        let curve = [pt(0, 1.2), pt(180, 2.6)]
        let events = [ev("Standup", -10, 10), ev("Revisión", 170, 230), ev("PTO", -1000, 1000, allDay: true)]
        let m = StressMoments.detect(curve, events: events)
        XCTAssertEqual(m.activated.first!.event?.title, "Revisión")
        // The all-day PTO must never be credited, even though it spans the peak.
        XCTAssertFalse(m.activated.contains { $0.event?.title == "PTO" })
    }

    // Calmest is the global minimum waking reading.
    func testCalmestIsGlobalMin() {
        let curve = [pt(0, 1.8), pt(60, 0.4), pt(120, 2.6)]
        let m = StressMoments.detect(curve)
        XCTAssertEqual(m.calmest!.stress, 0.4, accuracy: 1e-9)
        XCTAssertEqual(m.calmest!.date, at(60))
    }
}
