import XCTest
@testable import StrandAnalytics

/// FER-149 — «Mejor volumen en una sesión»: grouped by `sessionId`, never by calendar day.
final class SessionVolumeTests: XCTestCase {

    private typealias Row = (sessionId: String, startTs: Int, weightKg: Double, reps: Int)

    func testPicksTheHeavierSession() {
        let sets: [Row] = [
            ("s1", 1_000, 100, 5), ("s1", 1_001, 100, 5), ("s1", 1_002, 100, 5),   // 1500
            ("s2", 2_000, 60, 10), ("s2", 2_001, 80, 8),                          // 1240
        ]
        let best = SessionVolume.best(sets)
        XCTAssertEqual(best?.sessionId, "s1")
        XCTAssertEqual(best?.volumeKg ?? 0, 1500, accuracy: 0.0001)
    }

    func testTieBreaksToTheMostRecentSession() {
        let sets: [Row] = [
            ("older", 1_000, 100, 15),   // 1500, earlier
            ("newer", 5_000, 100, 15),   // 1500, later
        ]
        XCTAssertEqual(SessionVolume.best(sets)?.sessionId, "newer")
    }

    func testTwoSessionsTheSameDayDoNotMerge() {
        // Same calendar day, two distinct sessionIds — the record is the bigger SESSION (1500),
        // never the day's total (2500).
        let sets: [Row] = [
            ("morning", 1_000, 100, 5), ("morning", 1_001, 100, 5), ("morning", 1_002, 100, 5), // 1500
            ("evening", 1_100, 100, 10),                                                        // 1000
        ]
        let best = SessionVolume.best(sets)
        XCTAssertEqual(best?.sessionId, "morning")
        XCTAssertEqual(best?.volumeKg ?? 0, 1500, accuracy: 0.0001)
    }

    func testAllZeroHidesTheRecord() {
        let sets: [Row] = [("s1", 1_000, 0, 5), ("s2", 2_000, 100, 0)]
        XCTAssertNil(SessionVolume.best(sets))
    }

    func testEmptyHistoryHidesTheRecord() {
        XCTAssertNil(SessionVolume.best([Row]()))
    }
}
