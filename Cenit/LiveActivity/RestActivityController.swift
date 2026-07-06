// FER-721 · Entrenar v3 · F6 — the app-side lifecycle manager for the rest Live Activity.
//
// The single owner of the `Activity<RestActivityAttributes>` on the app side. `AppModel` feeds it a
// snapshot whenever the session state that matters changes (rest starts/ends, the set advances,
// heart rate ticks); the controller starts / updates / ends exactly one Activity from that. It also
// drains the shared inbox the lock-screen intents write to, and forwards each action to a handler
// `AppModel` installs (which mutates the session, closing the loop).
//
// Heart rate is throttled: the countdown itself ticks locally in the widget (`Text(timerInterval:)`),
// so the ONLY reason to push an update is a changed pulse — and ActivityKit throttles apps that
// update too often, so HR-only changes are coalesced to at most one push every `hrPushInterval`
// seconds. Structural changes (a new rest window, a different set, mode) always push immediately.
// (Cadence per Apple's ActivityKit guidance — favor local timer text over frequent pushes.)

#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// The snapshot `AppModel` hands the controller. Everything is already display-ready.
struct RestActivitySnapshot: Equatable {
    var sessionId: String
    var routineName: String
    var setNumber: Int
    var setTotal: Int
    var exerciseName: String
    var returnDetail: String
    var restStartedAt: Date
    var restEndsAt: Date
    var isHRMode: Bool
    var hrTarget: Int?
    var bpm: Int?
}

@MainActor
final class RestActivityController {
    /// The one running Activity, if any.
    private var activity: Activity<RestActivityAttributes>?
    /// The structural part of the last pushed state (everything but `bpm`) — a push is forced when it
    /// changes. Used to decide whether a change is "HR-only" (throttleable) or structural (immediate).
    private var lastStructural: RestActivityAttributes.ContentState?
    private var lastHRPush: Date?
    private let hrPushInterval: TimeInterval = 8   // seconds between HR-only pushes

    /// Installed by `AppModel`: applies a lock-screen action (+30 s / Saltar) to the live session.
    var onAction: ((RestActivityBridge.Action) -> Void)?

    private var darwinObserverInstalled = false

    // MARK: Reconcile

    /// The single entry point. `nil` = not resting (or no session) → end any running Activity. A
    /// snapshot → start one if needed, else update it (HR-throttled).
    func reconcile(_ snapshot: RestActivitySnapshot?, now: Date = Date()) {
        installDarwinObserverIfNeeded()
        // Apply anything the lock screen queued before we touch the Activity, so its effect is already
        // reflected in the snapshot the caller computed on the next pass.
        drainInbox()

        guard let snapshot else { end(); return }
        let state = contentState(from: snapshot)

        guard let activity else { start(snapshot: snapshot, state: state, now: now); return }

        let structural = withoutHR(state)
        let structuralChanged = structural != lastStructural
        if !structuralChanged, let last = lastHRPush, now.timeIntervalSince(last) < hrPushInterval {
            return   // HR-only change within the throttle window — skip the push
        }
        Task { await activity.update(ActivityContent(state: state, staleDate: snapshot.restEndsAt)) }
        lastStructural = structural
        if !structuralChanged { lastHRPush = now } else { lastHRPush = nil }
    }

    /// End and forget the running Activity (return to set, session end, «Listo», or app relaunch with
    /// no session). Idempotent — safe to call when nothing is running.
    func end() {
        guard let activity else { return }
        self.activity = nil
        lastStructural = nil
        lastHRPush = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// End any Activity of our type that outlived its process (e.g. the app was killed mid-rest and the
    /// session is gone). Called at launch so no rest Activity is ever orphaned.
    func endOrphans() {
        for activity in Activity<RestActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        self.activity = nil
    }

    // MARK: Start

    private func start(snapshot: RestActivitySnapshot, state: RestActivityAttributes.ContentState, now: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Never run two at once: adopt an existing one (survived a quick relaunch) or make a fresh one.
        if let existing = Activity<RestActivityAttributes>.activities.first {
            activity = existing
            Task { await existing.update(ActivityContent(state: state, staleDate: snapshot.restEndsAt)) }
        } else {
            let attributes = RestActivityAttributes(sessionId: snapshot.sessionId)
            activity = try? Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: snapshot.restEndsAt),
                pushType: nil)
        }
        lastStructural = withoutHR(state)
        lastHRPush = nil
    }

    // MARK: Inbox (lock-screen actions)

    private func drainInbox() {
        let pending = RestActivityBridge.drain()
        guard !pending.isEmpty, let onAction else { return }
        for item in pending { onAction(item.action) }
    }

    private func installDarwinObserverIfNeeded() {
        guard !darwinObserverInstalled else { return }
        darwinObserverInstalled = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center, observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let controller = Unmanaged<RestActivityController>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in controller.drainInbox() }
            },
            RestActivityBridge.darwinNotification as CFString,
            nil, .deliverImmediately)
    }

    // MARK: State mapping

    private func contentState(from s: RestActivitySnapshot) -> RestActivityAttributes.ContentState {
        RestActivityAttributes.ContentState(
            routineName: s.routineName, setNumber: s.setNumber, setTotal: s.setTotal,
            exerciseName: s.exerciseName, returnDetail: s.returnDetail,
            restStartedAt: s.restStartedAt, restEndsAt: s.restEndsAt,
            isHRMode: s.isHRMode, hrTarget: s.hrTarget, bpm: s.bpm)
    }

    /// The state with heart rate zeroed out — the structural fingerprint used to tell an HR-only
    /// change (throttleable) from a structural one (push now).
    private func withoutHR(_ state: RestActivityAttributes.ContentState) -> RestActivityAttributes.ContentState {
        var s = state; s.bpm = nil; return s
    }
}
#endif
