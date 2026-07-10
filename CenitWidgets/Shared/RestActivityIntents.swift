// FER-721 · Entrenar v3 · F6 — the «+30 s» and «Saltar» buttons' App Intents.
//
// Compiled into the WIDGET EXTENSION ONLY (excluded from the app target in project.yml): the app never
// instantiates these types — it only drains the shared inbox they write to (see `RestActivityBridge`).
// Compiling them into both targets registered the SAME intent identifier in two bundles, and on the lock
// screen `appintentsd` could resolve the auth policy from the app-side record and fall back to requiring
// an unlock — so every tap bounced to Face ID even with `.alwaysAllowed` set (FER-844).
//
// They are plain `AppIntent`, NOT `LiveActivityIntent`. A `LiveActivityIntent` runs `perform()` in the
// APP's process, which forces iOS to background-launch the app — a path it gates behind device unlock on
// the lock screen, so the tap demanded Face ID no matter the auth policy. A plain `AppIntent` button in a
// Live Activity runs `perform()` INSIDE the widget-extension process (the same path interactive lock-screen
// widgets use), which executes while locked and honours `.alwaysAllowed`. Our `perform()`s don't need the
// app at all — each just enqueues the action onto the shared App-Group inbox and posts a Darwin
// notification; the running app (kept alive by the live BLE session) drains it and its reconcile loop
// reflects the change back onto the Activity. `openAppWhenRun = false` keeps the tap in the extension.
//
// `authenticationPolicy = .alwaysAllowed` (a `static var`, matching the protocol requirement, so the
// build-time App Intents metadata extractor records it): these are benign session controls (log a set,
// nudge a rest) with no data exposure, so they run with the phone locked.

#if canImport(AppIntents)
import AppIntents

/// Adds 30 seconds to the current rest — moves the ceiling, never the floor (see `extendRest`).
struct RestAddThirtyIntent: AppIntent {
    static var title: LocalizedStringResource = "Add 30 seconds"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun = false
    static var description = IntentDescription("Extends the current rest by 30 seconds.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.addThirty)
        return .result()
    }
}

/// Removes 30 seconds from the current rest — floored at «now», so it never goes negative (see `extendRest`).
struct RestRemoveThirtyIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove 30 seconds"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun = false
    static var description = IntentDescription("Shortens the current rest by 30 seconds.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.removeThirty)
        return .result()
    }
}

/// Ends the current rest immediately and returns focus to the set — does NOT log the set (FER-789).
struct RestSkipIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip rest"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun = false
    static var description = IntentDescription("Ends the current rest without logging the set.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.skip)
        return .result()
    }
}

/// Registers the upcoming set as done (planned values) and starts its rest — the card's primary action (FER-789).
struct RestCompleteSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete set"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun = false
    static var description = IntentDescription("Logs the upcoming set and starts the next rest.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.completeSet)
        return .result()
    }
}

/// Resumes a paused session — the primary action on the «En pausa» card (FER-806/823).
struct RestResumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume workout"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun = false
    static var description = IntentDescription("Resumes the paused workout.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.resume)
        return .result()
    }
}

/// Registers the routine's last set and ends the workout — the primary action on the final rest (FER-789).
struct RestFinishWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Finish workout"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun = false
    static var description = IntentDescription("Logs the last set and ends the workout.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.finishWorkout)
        return .result()
    }
}
#endif
