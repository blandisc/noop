import XCTest
@testable import WhoopProtocol

/// Pins `ClockReassertPolicy` (FER-93): how many times NOOP re-asserts SET_CLOCK on an RTC-lost WHOOP 4.0
/// before resting on the honest diagnostic, and that a band which starts saving again clears the budget.
final class ClockReassertPolicyTests: XCTestCase {

    private let lost = RtcHealthPolicy.Verdict(savingHealthy: false, rtcLikelyLost: true, shouldReassertClock: true)
    private let healthy = RtcHealthPolicy.Verdict(savingHealthy: true, rtcLikelyLost: false, shouldReassertClock: false)
    private let idle = RtcHealthPolicy.Verdict(savingHealthy: false, rtcLikelyLost: false, shouldReassertClock: false)

    /// Re-asserts up to `maxPerConnect`, then gives up — a band that never latches can't loop forever.
    func testReassertsUpToMaxThenGivesUp() {
        var p = ClockReassertPolicy(maxPerConnect: 3)
        XCTAssertTrue(p.shouldReassert(lost))
        XCTAssertTrue(p.shouldReassert(lost))
        XCTAssertTrue(p.shouldReassert(lost))
        XCTAssertFalse(p.shouldReassert(lost))   // budget spent
        XCTAssertEqual(p.assertionsThisConnect, 3)
    }

    /// A healthy (saving) verdict never re-asserts and clears the budget, so a later relapse gets the full
    /// allowance again.
    func testHealthyClearsBudget() {
        var p = ClockReassertPolicy(maxPerConnect: 2)
        XCTAssertTrue(p.shouldReassert(lost))
        XCTAssertFalse(p.shouldReassert(healthy)) // saving now → no reassert, budget cleared
        XCTAssertEqual(p.assertionsThisConnect, 0)
        XCTAssertTrue(p.shouldReassert(lost))     // relapse → full allowance again
        XCTAssertTrue(p.shouldReassert(lost))
    }

    /// An idle verdict (nothing new, not lost) never re-asserts — only a positive "lost" signal does.
    func testIdleNeverReasserts() {
        var p = ClockReassertPolicy(maxPerConnect: 3)
        XCTAssertFalse(p.shouldReassert(idle))
        XCTAssertEqual(p.assertionsThisConnect, 0)
    }

    /// `reset()` (a fresh BLE connect) restores the per-connect budget.
    func testResetRestoresBudget() {
        var p = ClockReassertPolicy(maxPerConnect: 1)
        XCTAssertTrue(p.shouldReassert(lost))
        XCTAssertFalse(p.shouldReassert(lost)) // spent
        p.reset()
        XCTAssertTrue(p.shouldReassert(lost))  // fresh connect → allowed again
    }
}
