import Foundation

/// The display-ready snapshot of an active rest window, produced by `AppModel` on every relevant
/// change. It feeds two surfaces from one shape:
///   • the rest **Live Activity** (`RestActivityController`, lock screen + Dynamic Island, FER-721), and
///   • the **Apple Watch** mirrored session (`CenitWatch`, FER-740), which paints the same countdown.
///
/// It lived inside `#if canImport(ActivityKit)` in `RestActivityController`; FER-740 moved it here to
/// `CenitShared` and made it `Codable` because ActivityKit does not exist on watchOS, so the snapshot
/// can't stay trapped behind that gate — it now crosses the pairing as a `WorkoutMirrorMessage.rest`
/// payload. Everything is already formatted for display; the receiver just renders it.
public struct RestActivitySnapshot: Equatable, Codable {
    public var sessionId: String
    public var routineName: String
    public var setNumber: Int
    public var setTotal: Int
    public var exerciseName: String
    public var returnDetail: String
    public var restStartedAt: Date
    public var restEndsAt: Date
    public var isHRMode: Bool
    public var hrTarget: Int?
    public var bpm: Int?

    // FER-789 — enrich the rest Live Activity's lock-screen card. Kept as plain types (a raw String
    // for the phase, not the `RestPhase` enum) so `CenitShared` stays free of the widget-only contract
    // and the watch target — which also decodes this snapshot — compiles without it. All Optional and
    // defaulted, so existing construction sites (incl. the watch) are unchanged.
    /// Raw value of the widget's `RestPhase` (midExercise / lastSetOfExercise / lastSetOfRoutine); nil
    /// = pre-FER-789 → the card falls back to the check action.
    public var phaseRaw: String?
    /// The next exercise's name, only when `phaseRaw == "lastSetOfExercise"` (the card's «Sigue: …» line).
    public var nextExerciseName: String?
    /// File name of the exercise thumbnail in the shared App Group; nil = no image (the card omits it).
    public var thumbnailName: String?
    /// Whether the session is paused (FER-823). Exposed so the full-session Live Activity (FER-806) can
    /// paint the «En pausa» state; the current rest Live Activity simply isn't produced while paused.
    /// Defaulted, so existing construction sites (incl. the watch) are unchanged.
    public var paused: Bool

    // FER-806 — full-session Live Activity. Same shape as the widget's `ContentState` additions, kept as
    // plain types (a raw String for `sessionPhase`, not the widget-only `SessionPhase` enum) so
    // `CenitShared` and the watch target compile without the widget contract. All Optional/defaulted, so
    // existing construction sites (incl. the watch, which ignores what it doesn't understand) are unchanged.
    /// Raw value of the widget's `SessionPhase` (active / resting / paused); nil = pre-FER-806 → the card
    /// falls back to the rest layout.
    public var sessionPhaseRaw: String?
    /// The effective session-stopwatch anchor (`now − activeElapsed`, excluding paused time) for the
    /// active-phase count-up; nil in rest phase.
    public var sessionStartedAt: Date?
    /// Global session progress «N/M series» — sets logged so far / total planned.
    public var setsDone: Int?
    public var setsTotal: Int?

    public init(sessionId: String, routineName: String, setNumber: Int, setTotal: Int,
                exerciseName: String, returnDetail: String, restStartedAt: Date, restEndsAt: Date,
                isHRMode: Bool, hrTarget: Int?, bpm: Int?,
                phaseRaw: String? = nil, nextExerciseName: String? = nil, thumbnailName: String? = nil,
                paused: Bool = false,
                sessionPhaseRaw: String? = nil, sessionStartedAt: Date? = nil,
                setsDone: Int? = nil, setsTotal: Int? = nil) {
        self.sessionId = sessionId
        self.routineName = routineName
        self.setNumber = setNumber
        self.setTotal = setTotal
        self.exerciseName = exerciseName
        self.returnDetail = returnDetail
        self.restStartedAt = restStartedAt
        self.restEndsAt = restEndsAt
        self.isHRMode = isHRMode
        self.hrTarget = hrTarget
        self.bpm = bpm
        self.phaseRaw = phaseRaw
        self.nextExerciseName = nextExerciseName
        self.thumbnailName = thumbnailName
        self.paused = paused
        self.sessionPhaseRaw = sessionPhaseRaw
        self.sessionStartedAt = sessionStartedAt
        self.setsDone = setsDone
        self.setsTotal = setsTotal
    }
}
