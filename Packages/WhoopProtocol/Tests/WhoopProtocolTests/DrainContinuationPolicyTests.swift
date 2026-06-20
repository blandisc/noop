import XCTest
@testable import WhoopProtocol

/// Pins `DrainContinuationPolicy` — the pure decision behind FER-287 ("auto-continue the offload until
/// the backlog drains, so the user doesn't tap Sync dozens of times"). A cleanly-closed session that
/// delivered a large type-47 batch ⇒ keep draining; a small or caught-up session ⇒ stop; a timeout /
/// cap close ⇒ never chain; and `maxChain` guarantees termination.
final class DrainContinuationPolicyTests: XCTestCase {

    /// A large, cleanly-closed session still has backlog → continue.
    func testLargeCleanSessionContinues() {
        var p = DrainContinuationPolicy(largeSessionFrames: 100, maxChain: 120)
        XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 270))
        XCTAssertEqual(p.chainLength, 1)
    }

    /// A small cleanly-closed session is the live drip → stop (backlog drained).
    func testSmallCleanSessionStops() {
        var p = DrainContinuationPolicy(largeSessionFrames: 100, maxChain: 120)
        XCTAssertFalse(p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 30))
        XCTAssertEqual(p.chainLength, 0)
    }

    /// A caught-up session is drained by definition → never continue, even with many frames.
    func testCaughtUpNeverContinues() {
        var p = DrainContinuationPolicy(largeSessionFrames: 100, maxChain: 120)
        XCTAssertFalse(p.shouldContinue(completedCleanly: true, caughtUp: true, sessionBiometricFrames: 5000))
    }

    /// A non-clean close (idle timeout / session cap) means an unhealthy link → never chain (don't hammer
    /// it; the rate-limited path retries), even if a lot of frames came in.
    func testInterruptedSessionNeverContinues() {
        var p = DrainContinuationPolicy(largeSessionFrames: 100, maxChain: 120)
        XCTAssertFalse(p.shouldContinue(completedCleanly: false, caughtUp: false, sessionBiometricFrames: 5000))
    }

    /// The boundary is exclusive: exactly `largeSessionFrames` counts as small → stop.
    func testBoundaryIsExclusive() {
        var p = DrainContinuationPolicy(largeSessionFrames: 100, maxChain: 120)
        XCTAssertFalse(p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 100))
        XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 101))
    }

    /// Termination guarantee: even if every session stays large, the chain stops at `maxChain`.
    func testChainTerminatesAtMaxChain() {
        var p = DrainContinuationPolicy(largeSessionFrames: 100, maxChain: 3)
        XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 270))
        XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 270))
        XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 270))
        XCTAssertFalse(p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 270)) // capped
        XCTAssertEqual(p.chainLength, 3)
    }

    /// `reset()` re-arms the chain for a fresh (rate-limited) drain start.
    func testResetReArmsChain() {
        var p = DrainContinuationPolicy(largeSessionFrames: 100, maxChain: 3)
        _ = p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 270)
        _ = p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 270)
        XCTAssertEqual(p.chainLength, 2)
        p.reset()
        XCTAssertEqual(p.chainLength, 0)
        XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 270))
    }

    /// A full disconnected night (~19,400 frames in ~270-frame sessions ≈ 72 sessions) drains in one
    /// chain — every backlog session continues, the small tail stops it, and it never hits the cap.
    func testFullNightDrainConvergesAndStops() {
        var p = DrainContinuationPolicy(largeSessionFrames: 100, maxChain: 120)
        var drained = 0
        var sessions = 0
        // 72 full sessions of 270 frames each (~19,440), then a small tail session.
        while drained < 19_400 {
            sessions += 1
            XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 270),
                          "should keep draining at session \(sessions)")
            drained += 270
        }
        // The tail: the live drip is all that's left → stop, drained, never reached the cap.
        XCTAssertFalse(p.shouldContinue(completedCleanly: true, caughtUp: false, sessionBiometricFrames: 20))
        XCTAssertLessThan(p.chainLength, 120, "a full night must drain without hitting the safety cap")
        XCTAssertEqual(p.chainLength, sessions)
    }
}
