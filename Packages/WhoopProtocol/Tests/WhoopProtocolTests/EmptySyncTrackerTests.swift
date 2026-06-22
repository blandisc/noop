import XCTest
@testable import WhoopProtocol

/// Pins `EmptySyncTracker` (FER-481): the consecutive-empty-offload counter that drives `BackfillPolicy`'s
/// battery backoff. Empty completed sessions extend the streak; the first real banked row resets it.
final class EmptySyncTrackerTests: XCTestCase {

    func testStartsAtZero() {
        XCTAssertEqual(EmptySyncTracker().streak, 0)
    }

    func testEmptySessionsExtendStreak() {
        var t = EmptySyncTracker()
        XCTAssertEqual(t.record(rowsPersisted: 0), 1)
        XCTAssertEqual(t.record(rowsPersisted: 0), 2)
        XCTAssertEqual(t.record(rowsPersisted: 0), 3)
        XCTAssertEqual(t.streak, 3)
    }

    func testRealRowResetsStreak() {
        var t = EmptySyncTracker()
        t.record(rowsPersisted: 0)
        t.record(rowsPersisted: 0)
        XCTAssertEqual(t.streak, 2)
        XCTAssertEqual(t.record(rowsPersisted: 270), 0)   // a real banked row resets
        XCTAssertEqual(t.streak, 0)
    }

    func testEvenOneRowResets() {
        var t = EmptySyncTracker()
        t.record(rowsPersisted: 0)
        t.record(rowsPersisted: 1)                         // even a tiny real yield counts as progress
        XCTAssertEqual(t.streak, 0)
    }

    func testResetsThenCountsAgain() {
        var t = EmptySyncTracker()
        for _ in 0..<5 { t.record(rowsPersisted: 0) }
        XCTAssertEqual(t.streak, 5)                         // off-wrist for a while
        t.record(rowsPersisted: 42)                         // put back on → banks rows → reset
        XCTAssertEqual(t.streak, 0)
        t.record(rowsPersisted: 0)                          // off again → counts from scratch
        XCTAssertEqual(t.streak, 1)
    }
}
