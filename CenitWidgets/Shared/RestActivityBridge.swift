// FER-721 · Entrenar v3 · F6 — the cross-process channel for the lock-screen actions.
//
// Shared source: compiled into BOTH the app and the widget extension. The «+30 s» and «Saltar»
// buttons in the Live Activity fire App Intents (`RestActivityIntents`). A `LiveActivityIntent`
// runs in the app's process, but that process may be a fresh background launch where the in-memory
// strength session no longer exists — so the action can't be applied inline with certainty. Instead
// the intent writes it to a durable inbox in the shared App Group and posts a Darwin notification;
// the running app drains the inbox (on the notification, and again whenever it reconciles), applies
// it to the live `StrengthSessionModel`, and lets the normal reconcile loop update/end the Activity.

import Foundation

enum RestActivityBridge {
    /// The App Group both targets already share (see NOOP.entitlements / CenitWidgets.entitlements).
    static let appGroup = "group.com.feriracheta.noop"

    /// The lock-screen actions the Live Activity can request.
    enum Action: String, Codable { case addThirty, skip }

    /// Darwin notification the extension posts and the app observes (cross-process, unlike
    /// `NotificationCenter`). Named, not payload-carrying — the payload is the App Group inbox.
    static let darwinNotification = "com.feriracheta.noop.rest.action"

    private static let inboxKey = "rest.activity.pendingActions"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// One queued action with the time it was requested (so the app can ignore stale ones if it wants).
    struct PendingAction: Codable { var action: Action; var ts: Date }

    /// Append an action to the inbox and wake the app. Called from the intent (any process).
    static func enqueue(_ action: Action, now: Date = Date()) {
        guard let defaults else { return }
        var queue = readQueue()
        queue.append(PendingAction(action: action, ts: now))
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

    // MARK: Darwin notification

    private static func postDarwin() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinNotification as CFString),
            nil, nil, true)
    }
}
