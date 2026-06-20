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

    static func shouldRun(trigger: BackfillTrigger, now: TimeInterval,
                          lastBackfillAt: TimeInterval?) -> Bool {
        guard let last = lastBackfillAt else { return true }
        let elapsed = now - last
        switch trigger {
        case .manual, .drain:                return true   // .drain is gated by DrainContinuationPolicy, not time (FER-287)
        case .connect, .foreground, .strap:  return elapsed >= eventFloorSeconds
        case .periodic:                      return elapsed >= periodicFloorSeconds
        }
    }
}
