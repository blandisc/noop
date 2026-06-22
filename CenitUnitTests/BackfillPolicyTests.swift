import XCTest
@testable import Cenit

/// Pins `BackfillPolicy.shouldRun` — the pure offload rate-limiter — with focus on the FER-481 empty-streak
/// backoff: an off-wrist strap that only emits EVENT packets must stop being re-offloaded console-only every
/// 90 s, while user- and connection-driven syncs are never delayed.
final class BackfillPolicyTests: XCTestCase {

    private let now = 100_000.0   // arbitrary fixed clock; tests vary `lastBackfillAt` relative to it

    /// Below the threshold the floors are unchanged: `.strap` at 90 s, `.periodic` at 900 s.
    func testBelowThresholdNoBackoff() {
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .strap, now: now, lastBackfillAt: now - 100, emptyStreak: 2))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .periodic, now: now, lastBackfillAt: now - 1000, emptyStreak: 2))
    }

    /// `emptyStreak` defaulting to 0 ⇒ existing call sites that don't pass it behave exactly as before.
    func testDefaultStreakPreservesOldBehavior() {
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .strap, now: now, lastBackfillAt: now - 100))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .periodic, now: now, lastBackfillAt: now - 1000))
    }

    /// At the threshold (3) the multiplier is ×2: `.strap` floor becomes 180 s.
    func testStrapBacksOffAtThreshold() {
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .strap, now: now, lastBackfillAt: now - 100, emptyStreak: 3))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .strap, now: now, lastBackfillAt: now - 200, emptyStreak: 3))
    }

    /// `.periodic` backs off the same way: ×2 → 1800 s at streak 3.
    func testPeriodicBacksOffAtThreshold() {
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .periodic, now: now, lastBackfillAt: now - 1000, emptyStreak: 3))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .periodic, now: now, lastBackfillAt: now - 1900, emptyStreak: 3))
    }

    /// The multiplier is capped at `maxEmptyBackoff` (4): a huge streak floors `.strap` at 360 s, not higher.
    func testBackoffCaps() {
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .strap, now: now, lastBackfillAt: now - 350, emptyStreak: 50))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .strap, now: now, lastBackfillAt: now - 400, emptyStreak: 50))
    }

    /// User- and connection-driven triggers never back off — even with a huge empty streak.
    func testManualConnectForegroundDrainExempt() {
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .manual, now: now, lastBackfillAt: now - 1, emptyStreak: 50))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .drain, now: now, lastBackfillAt: now - 1, emptyStreak: 50))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .connect, now: now, lastBackfillAt: now - 100, emptyStreak: 50))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .foreground, now: now, lastBackfillAt: now - 100, emptyStreak: 50))
    }

    /// `.connect` is exempt from the BACKOFF but still respects the base 90 s event floor.
    func testConnectStillFlooredAtBase() {
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .connect, now: now, lastBackfillAt: now - 50, emptyStreak: 0))
    }

    /// First-ever sync (no prior timestamp) always runs, regardless of streak.
    func testFirstEverAlwaysRuns() {
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .periodic, now: now, lastBackfillAt: nil, emptyStreak: 50))
    }
}
