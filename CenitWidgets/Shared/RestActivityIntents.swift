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

/// Ends the current rest immediately and returns focus to the set.
struct RestSkipIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip rest"
    static var description = IntentDescription("Ends the current rest and returns to the set.")

    init() {}

    func perform() async throws -> some IntentResult {
        RestActivityBridge.enqueue(.skip)
        return .result()
    }
}
#endif
