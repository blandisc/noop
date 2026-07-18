import XCTest
import CenitStore
@testable import Cenit

/// Pins the FER-486 sleep merge: strap (imported wins over computed on the same startTs) is the base,
/// and an Apple Health session is included only when no strap session overlaps its night — the band
/// wins per night. With no Apple sessions the merge is the prior strap-only behavior (regression zero).
@MainActor
final class SleepSessionMergeTests: XCTestCase {

    private func ses(_ start: Int, _ end: Int) -> CachedSleepSession {
        CachedSleepSession(startTs: start, endTs: end, efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: "[]")
    }

    /// Regression zero: with no Apple sessions, imported wins over computed on the same startTs, sorted.
    func testStrapOnlyUnchangedWhenNoApple() {
        let r = Repository.mergeSleepSessions(imported: [ses(100, 200)],
                                              computed: [ses(100, 999), ses(300, 400)],
                                              apple: [])
        XCTAssertEqual(r.map(\.startTs), [100, 300])
        XCTAssertEqual(r.first(where: { $0.startTs == 100 })?.endTs, 200)   // imported beat computed
    }

    /// Band wins per night: an Apple session overlapping a strap night (different startTs) is dropped.
    func testAppleDroppedWhenOverlapsStrap() {
        let r = Repository.mergeSleepSessions(imported: [ses(1000, 5000)],
                                              computed: [],
                                              apple: [ses(1100, 4900)])   // same night, later start
        XCTAssertEqual(r.map(\.startTs), [1000])                          // only the strap session survives
    }

    /// Apple fills a night with no strap coverage.
    func testAppleKeptWhenNoStrapOverlap() {
        let r = Repository.mergeSleepSessions(imported: [ses(1000, 5000)],
                                              computed: [],
                                              apple: [ses(90_000, 95_000)])
        XCTAssertEqual(r.map(\.startTs), [1000, 90_000])                  // strap night + Apple-only night
    }

    /// appleHealthOnly path (strap arrays empty by the mode gate) → only Apple sessions surface.
    func testAppleOnlyWhenStrapEmpty() {
        let r = Repository.mergeSleepSessions(imported: [], computed: [], apple: [ses(90_000, 95_000)])
        XCTAssertEqual(r.map(\.startTs), [90_000])
    }

    /// Boundary: a strap night ending exactly when the Apple session starts counts as overlap
    /// (inclusive `<=`/`>=`), so Apple is dropped — conservative, the band wins ties.
    func testTouchingBoundaryCountsAsOverlap() {
        let r = Repository.mergeSleepSessions(imported: [ses(1000, 5000)],
                                              computed: [],
                                              apple: [ses(5000, 9000)])   // shares the instant 5000
        XCTAssertEqual(r.map(\.startTs), [1000])                          // tie at the boundary → Apple dropped
    }
}
