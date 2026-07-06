// FER-721 · Entrenar v3 · F6 — the ActivityKit contract for the rest Live Activity.
//
// Shared source: this file is compiled into BOTH the app (Cenit) and the widget extension
// (CenitWidgets) via project.yml, so the two processes agree on the exact shape of the state
// ActivityKit serializes between them. Pure value types — no UIKit, no app-layer imports — so it
// stays trivially portable across the target boundary.

#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// The state ActivityKit shows on the lock screen and in the Dynamic Island while the lifter is
/// resting between sets. Everything the surfaces render lives in `ContentState` (it changes as the
/// rest progresses, the set advances, or heart rate ticks); the attributes carry only the session
/// identity, which is stable for the whole session.
struct RestActivityAttributes: ActivityAttributes {
    /// The dynamic slice ActivityKit diff-updates. Kept small and preformatted so the widget never
    /// needs the app's unit prefs or catalogs — the app builds the display strings before pushing.
    struct ContentState: Codable, Hashable {
        /// «{Rutina} · serie N de M» — the routine name and the set the lifter will come back to.
        var routineName: String
        var setNumber: Int
        var setTotal: Int
        /// The exercise the returning set belongs to (the caption's subject).
        var exerciseName: String
        /// Preformatted «{peso} × {reps}» for the return caption, already in the user's unit
        /// («62.5 kg × 8»). Empty for exercises with no weight×reps datum (time/distance) — the
        /// widget then shows just the set line.
        var returnDetail: String

        /// The rest window. The widget draws the countdown and progress bar from these two dates with
        /// `Text(timerInterval:)` / `ProgressView(timerInterval:)`, so the clock ticks locally without
        /// any push updates — only heart rate needs periodic updates.
        var restStartedAt: Date
        var restEndsAt: Date

        /// Heart-rate rest mode (FER-495/506): the card frames the pulse falling toward the target
        /// instead of leading with the countdown.
        var isHRMode: Bool
        /// The «ready» heart rate (bpm) for HR-mode rests; nil when there's no honest target.
        var hrTarget: Int?
        /// Live heart rate (bpm). **nil = no band data** → the surfaces show only the timer, never a
        /// dashed placeholder (acceptance criterion 4).
        var bpm: Int?
    }

    /// Stable for the life of the session — lets the app find and end its own Activity unambiguously.
    var sessionId: String
}
#endif
