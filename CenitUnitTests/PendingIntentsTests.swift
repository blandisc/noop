import XCTest
@testable import Cenit

/// The App-Intent queue has to carry *when* an action was requested, not just what it was. An intent
/// run from the lock screen (`MarkMomentIntent` deliberately doesn't foreground the app) sits in the
/// queue until the app next becomes active, so a moment stamped at drain time landed hours late —
/// silently defeating the one thing a "mark a moment" marker is for.
final class PendingIntentsTests: XCTestCase {

    /// Whole seconds on purpose: the queue serialises to ISO-8601 internet date-time, which carries
    /// no sub-second component, so a bare `Date()` would round-trip lossily and make equality flaky.
    private let queuedAt = Date(timeIntervalSince1970: 1_781_000_000)

    // The queue lives in the shared App-Group store, so start from empty and leave nothing behind
    // for the app or the next test.
    override func setUp() {
        super.setUp()
        _ = PendingIntents.drain()
    }

    override func tearDown() {
        _ = PendingIntents.drain()
        super.tearDown()
    }

    func testQueuedMomentKeepsItsOriginalTimestampWhenDrainedLater() {
        PendingIntents.append(.markMoment, at: queuedAt)

        let drained = PendingIntents.drain()

        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained.first?.action, .markMoment)
        XCTAssertEqual(drained.first?.date, queuedAt)
        // The regression itself: the moment must carry the instant it was requested, not the instant
        // the app happened to be opened.
        XCTAssertGreaterThan(Date().timeIntervalSince(drained[0].date), 60,
                             "drained moment was re-stamped at drain time")
    }

    func testDrainPreservesQueueOrderAndPerEntryTimestamps() {
        let buzzAt = queuedAt.addingTimeInterval(90)
        PendingIntents.append(.markMoment, at: queuedAt)
        PendingIntents.append(.buzz, at: buzzAt)

        let drained = PendingIntents.drain()

        XCTAssertEqual(drained.map(\.action), [.markMoment, .buzz])
        XCTAssertEqual(drained.map(\.date), [queuedAt, buzzAt])
    }

    func testDrainEmptiesTheQueue() {
        PendingIntents.append(.markMoment, at: queuedAt)

        XCTAssertEqual(PendingIntents.drain().count, 1)
        XCTAssertTrue(PendingIntents.drain().isEmpty)
    }
}
