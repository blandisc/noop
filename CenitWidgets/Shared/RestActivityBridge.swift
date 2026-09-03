// FER-721 · Entrenar v3 · F6 — the cross-process channel for the lock-screen actions.
//
// Shared source: compiled into BOTH the app and the widget extension. The «+30 s» and «Saltar»
// buttons in the Live Activity fire App Intents (`RestActivityIntents`) that run INSIDE the widget
// extension (plain `AppIntent`, so they execute while the phone is locked — FER-844). The extension
// has no access to the in-memory strength session, so instead the intent writes the action to a
// durable inbox in the shared App Group and posts a Darwin notification; the running app (kept alive
// by the live BLE session) drains the inbox (on the notification, and again whenever it reconciles or
// re-activates), applies it to the live `StrengthSessionModel`, and lets the normal reconcile loop
// update/end the Activity.

import Foundation

enum RestActivityBridge {
    /// The App Group both targets already share (see NOOP.entitlements / CenitWidgets.entitlements).
    /// Read from `AppGroup` rather than repeated as a literal here — the two used to be independent
    /// declarations and drifted apart, which nothing caught (an unentitled suite fails silently).
    static let appGroup = AppGroup.suiteName

    /// The lock-screen actions the Live Activity can request. FER-789 adds `removeThirty` (−30 s),
    /// `completeSet` (register the upcoming set and rest again) and `finishWorkout` (register the last
    /// set and end the session). FER-806 adds `resume` (leave the «En pausa» state). New raw values
    /// decode as-is; older payloads never carry them.
    enum Action: String, Codable { case addThirty, removeThirty, skip, completeSet, finishWorkout, resume }

    /// Darwin notification the extension posts and the app observes (cross-process, unlike
    /// `NotificationCenter`). Named, not payload-carrying — the payload is the App Group inbox.
    static let darwinNotification = "com.feriracheta.cenit.rest.action"

    private static let inboxKey = "rest.activity.pendingActions"
    private static let currentSessionKey = "rest.activity.currentSessionId"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// One queued action with the time it was requested (so the app can ignore stale ones if it wants).
    /// P0-3: `sessionId` seals the action to whichever strength session was live when it was enqueued —
    /// OPTIONAL so a payload written before this field existed decodes as `nil` (Swift's synthesized
    /// `Decodable` treats a missing key on an `Optional` property as `nil`, no migration needed). The
    /// app treats `nil` as an old payload and falls back to the pre-existing `lastRestStartedAt` guard,
    /// same as before this fix.
    struct PendingAction: Codable { var action: Action; var ts: Date; var sessionId: String? }

    /// Append an action to the inbox and wake the app. Called from the intent (any process). Sealed with
    /// whatever session the app last recorded as current (see `setCurrentSession`), so a late drain can
    /// never misapply the action to a DIFFERENT session that happens to be live by the time it's read
    /// (P0-3: a stale ±30/Saltar/Completar/Terminar from session A landing on session B).
    static func enqueue(_ action: Action, now: Date = Date()) {
        guard let defaults else { return }
        var queue = readQueue()
        queue.append(PendingAction(action: action, ts: now, sessionId: currentSessionId()))
        if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: inboxKey)
        }
        postDarwin()
    }

    /// Read and clear the inbox. Called by the app when it wakes to apply the queued actions in order.
    static func drain() -> [PendingAction] {
        guard let defaults else { return [] }
        let queue = readQueue()
        defaults.removeObject(forKey: inboxKey)
        return queue
    }

    private static func readQueue() -> [PendingAction] {
        guard let data = defaults?.data(forKey: inboxKey),
              let queue = try? JSONDecoder().decode([PendingAction].self, from: data) else { return [] }
        return queue
    }

    // MARK: Current session (P0-3)

    /// The strength session the app considers live right now, written by the app only — the extension
    /// has no access to the in-memory `StrengthSessionModel`, so this is how `enqueue` (running in the
    /// widget process) still seals its action with the right id. `nil` means no session is running
    /// (cleared on end/discard) — the honest state to seal a stray tap with.
    static func setCurrentSession(_ id: String?) {
        guard let defaults else { return }
        if let id {
            defaults.set(id, forKey: currentSessionKey)
        } else {
            defaults.removeObject(forKey: currentSessionKey)
        }
    }

    /// The id that gets sealed onto a freshly enqueued action, or nil if the app hasn't recorded one
    /// (no session running, or an unentitled App Group).
    static func currentSessionId() -> String? { defaults?.string(forKey: currentSessionKey) }

    // MARK: Darwin notification

    private static func postDarwin() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinNotification as CFString),
            nil, nil, true)
    }
}
