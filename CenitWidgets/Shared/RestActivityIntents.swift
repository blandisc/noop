// FER-721 · Entrenar v3 · F6 — the «+30 s» and «Saltar» buttons' App Intents.
//
// Shared source: compiled into BOTH the app and the widget extension (the Live Activity view
// references these types, and the app runs them). Conforming to `LiveActivityIntent` tells the
// system to run `perform()` in the app's process rather than a detached extension, and marks the
// intent as safe to invoke from a Live Activity. Each just enqueues the action onto the shared inbox
// (see `RestActivityBridge`); the running app applies it to the session and the reconcile loop
// reflects it back onto the Activity.

#if canImport(AppIntents)
import AppIntents

/// Adds 30 seconds to the current rest — moves the ceiling, never the floor (see `extendRest`).
struct RestAddThirtyIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add 30 seconds"
    static var description = IntentDescription("Extends the current rest by 30 seconds.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.addThirty)
        return .result()
    }
}

/// Removes 30 seconds from the current rest — floored at «now», so it never goes negative (see `extendRest`).
struct RestRemoveThirtyIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Remove 30 seconds"
    static var description = IntentDescription("Shortens the current rest by 30 seconds.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.removeThirty)
        return .result()
    }
}

/// Ends the current rest immediately and returns focus to the set — does NOT log the set (FER-789).
struct RestSkipIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip rest"
    static var description = IntentDescription("Ends the current rest without logging the set.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.skip)
        return .result()
    }
}

/// Registers the upcoming set as done (planned values) and starts its rest — the card's primary action (FER-789).
struct RestCompleteSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Complete set"
    static var description = IntentDescription("Logs the upcoming set and starts the next rest.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.completeSet)
        return .result()
    }
}

/// Resumes a paused session — the primary action on the «En pausa» card (FER-806/823).
struct RestResumeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume workout"
    static var description = IntentDescription("Resumes the paused workout.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.resume)
        return .result()
    }
}

/// Registers the routine's last set and ends the workout — the primary action on the final rest (FER-789).
struct RestFinishWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Finish workout"
    static var description = IntentDescription("Logs the last set and ends the workout.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.finishWorkout)
        return .result()
    }
}
#endif
