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
/// Which set the rest precedes, so the enriched lock-screen card can pick its primary action
/// (FER-789): a check when there's a set to complete, a flag when the routine's last set is next.
/// Codable/String-backed so it survives the ActivityKit snapshot and decodes safely across an app
/// update. `nil` (absent) means the pre-FER-789 contract → the card falls back to the check.
enum RestPhase: String, Codable, Hashable, Sendable {
    case midExercise         // more pending sets remain in the focused exercise
    case lastSetOfExercise   // the next set is this exercise's last; then a different exercise
    case lastSetOfRoutine    // the next set is the whole workout's last → primary action = «Terminar entreno»
}

struct RestActivityAttributes: ActivityAttributes {
    /// The dynamic slice ActivityKit diff-updates. Kept small and preformatted so the widget never
    /// needs the app's unit prefs or catalogs — the app builds the display strings before pushing.
    /// FER-789 additive fields are all Optional, so an Activity started under the old contract still
    /// decodes (missing keys → nil) and the card degrades to its pre-FER-789 look.
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

        // MARK: FER-789 — enriched lock-screen card (all Optional for back-compat)

        /// File name of the exercise thumbnail copied into the shared App Group by `RestThumbnailProvider`
        /// (never the image bytes). **nil = no thumbnail** → the card omits the circle entirely, no
        /// placeholder. Resolved by the widget against the App Group container.
        var thumbnailName: String? = nil
        /// Which set the rest precedes — picks the primary action (check vs «Terminar entreno» flag).
        var phase: RestPhase? = nil
        /// The exercise that comes next when `phase == .lastSetOfExercise` — the card's «Sigue: …» line.
        var nextExerciseName: String? = nil
    }

    /// Stable for the life of the session — lets the app find and end its own Activity unambiguously.
    var sessionId: String
}
#endif
