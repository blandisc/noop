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

    public init(sessionId: String, routineName: String, setNumber: Int, setTotal: Int,
                exerciseName: String, returnDetail: String, restStartedAt: Date, restEndsAt: Date,
                isHRMode: Bool, hrTarget: Int?, bpm: Int?) {
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
    }
}
