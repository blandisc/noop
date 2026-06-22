import Foundation

/// What prompted a sync attempt. Mirrors WHOOP (15-min periodic floor + event-triggered "process now"
/// syncs + the strap's own prompt events + manual), adapted to iOS.
enum BackfillTrigger {
    case periodic    // the repeating timer while connected+bonded
    case connect     // a (re)connect / bond confirmation
    case foreground  // the app became active (scenePhase .active)
    case manual      // the user tapped "Sync now"
    case strap       // an incoming strap EVENT packet (WHOOP's HighFreqSyncPrompt analog)
    case drain       // FER-287: auto-continue while a backlog remains — bypasses the floor on purpose
}

/// Pure rate-limiter for historical-offload kicks. No BLE/store deps. Floors match WHOOP
/// (observed: ~15-min periodic + expedited event syncs).
enum BackfillPolicy {
    static let periodicFloorSeconds: TimeInterval = 900   // 15 min
    static let eventFloorSeconds: TimeInterval = 90       // absorbs reconnect-flaps / event bursts
    /// Consecutive empty offloads before the AUTOMATIC floors start stretching (FER-481).
    static let emptyBackoffThreshold = 3
    /// Cap on the floor multiplier — ~6-min event / ~1-hr periodic ceiling.
    static let maxEmptyBackoff: Double = 4

    /// `emptyStreak` = consecutive COMPLETED offloads that banked no sensor records (`EmptySyncTracker`).
    /// Past the threshold the AUTOMATIC triggers (`.periodic`/`.strap`) stretch their floor — each further
    /// empty doubles it, capped — so an off-wrist / not-banking strap that still emits EVENT packets every
    /// 90 s isn't re-offloaded console-only every 90 s, draining its battery and ours (FER-481, mirrors
    /// upstream #580). `.manual`/`.connect`/`.foreground`/`.drain` never back off, and the first real record
    /// resets the streak, so baseline cadence resumes instantly — a user- or connection-driven sync is
    /// never delayed. `emptyStreak` defaults to 0 so non-updated call sites behave exactly as before.
    static func shouldRun(trigger: BackfillTrigger, now: TimeInterval,
                          lastBackfillAt: TimeInterval?, emptyStreak: Int = 0) -> Bool {
        guard let last = lastBackfillAt else { return true }
        let elapsed = now - last
        let backoff: Double = emptyStreak >= emptyBackoffThreshold
            ? min(pow(2.0, Double(emptyStreak - emptyBackoffThreshold + 1)), maxEmptyBackoff)
            : 1.0
        switch trigger {
        case .manual, .drain:        return true   // .drain is gated by DrainContinuationPolicy, not time (FER-287)
        case .connect, .foreground:  return elapsed >= eventFloorSeconds        // user/connection-driven — no backoff
        case .strap:                 return elapsed >= eventFloorSeconds * backoff
        case .periodic:              return elapsed >= periodicFloorSeconds * backoff
        }
    }
}
