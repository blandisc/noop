// FER-95 · E14 — the cross-process signal for the home-screen «Empezar» button.
//
// Shared source: compiled into BOTH the app and the widget extension, mirroring `RestActivityBridge`
// (App-Group inbox, drained by the app) — but simpler, since there's only one action to queue: the
// widget extension's `StartTodayRoutineIntent` writes a flag here; the app drains it on activation
// (`CenitApp`'s `scenePhase == .active`, alongside `PendingIntents.drain()`) and turns a `true` into
// the SAME `TabRouter.startTodayTraining()` the Daily Brief's «Empezar» already uses — so tapping the
// widget opens Cénit straight into today's guided session, no second tap inside the app.
import Foundation

public enum StartRoutineBridge {
    private static let key = "train.widget.startRequested"
    private static var defaults: UserDefaults { AppGroup.sharedDefaults() }

    /// Called from the widget extension's `StartTodayRoutineIntent`.
    public static func request() {
        defaults.set(true, forKey: key)
    }

    /// Called by the app on activation. Returns whether a start was requested, and clears the flag
    /// either way (so a `false` read never re-fires on the next activation).
    public static func drain() -> Bool {
        let requested = defaults.bool(forKey: key)
        if requested { defaults.removeObject(forKey: key) }
        return requested
    }
}
