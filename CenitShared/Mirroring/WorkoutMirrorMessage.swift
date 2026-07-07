import Foundation

/// The single contract for the strength-session **workout mirroring** channel between the iPhone and
/// the Apple Watch (FER-740, F1.1 of the Apple Watch epic FER-391). Both processes share this one
/// definition, so the wire shape can never drift.
///
/// Transport (decided by `/arquitecto`): control messages that must arrive (`start`, `end`,
/// `watchDidSaveWorkout`, `watchWillNotSave`) go over `WatchConnectivity` (`WCSession`, guaranteed +
/// acked); best-effort, high-frequency updates (`rest`, pulse) ride HealthKit's mirror payload
/// (`sendToRemoteWorkoutSession`, tolerant of loss — the watch runs its own local countdown). Each is
/// JSON-encoded to `Data`; the HealthKit payload wraps it under `WorkoutMirrorKey.payloadKey`.
///
/// The iPhone stays the single source of truth and the only one that persists to `WhoopStore`; the
/// watch is a control + display surface in F1.1 and owns only its own `HKWorkout`.
public enum WorkoutMirrorMessage: Codable, Equatable {
    /// iPhone → watch: start the mirrored session. Carries the iPhone's `sessionId` so both devices
    /// derive the **same** idempotency key (`WorkoutMirrorKey.externalUUID(for:)`).
    case start(sessionId: String, routineName: String, startedAt: Date)

    /// iPhone → watch: a rest window opened / changed. Reuses the existing `RestActivitySnapshot`.
    case rest(RestActivitySnapshot)

    /// iPhone → watch: the rest window ended without ending the session. `recovered == true` means the
    /// pulse dropped back to target (FER-758) → the watch fires the «ready» buzz + banner; `false` means
    /// the user simply returned to the set → the watch cancels its local timer silently, no buzz.
    case restEnded(sessionId: String, recovered: Bool)

    /// iPhone → watch: end the session. `save == false` = the session was discarded (nothing logged)
    /// → the watch ends WITHOUT saving a workout. `externalUUID` is the shared idempotency key.
    case end(sessionId: String, endedAt: Date, save: Bool, externalUUID: String)

    /// watch → iPhone: "I saved the HKWorkout under this `externalUUID`." The iPhone then OMITS its own
    /// `saveStrengthWorkoutIfEnabled` (the one-workout invariant).
    case watchDidSaveWorkout(sessionId: String, externalUUID: String)

    /// watch → iPhone: the watch could not / will not save (no permission, error, mirror lost) → the
    /// iPhone takes over and saves its estimated workout as it does today.
    case watchWillNotSave(sessionId: String, reason: WatchSaveFailure)

    /// watch → iPhone: the user logged the current set from the wrist (FER-808). The iPhone runs the
    /// SAME path as the Live Activity's `RestCompleteSetIntent` (`registerCurrentSet`) and re-emits the
    /// next snapshot — the wrist and the lock screen share one source of truth, no duplicated logic.
    case completeSet(sessionId: String)

    /// watch → iPhone: skip the current rest from the wrist (FER-808). Same path as the LA's `RestSkipIntent`.
    case skipRest(sessionId: String)

    /// watch → iPhone: nudge the current rest ceiling by `deltaS` (±30) from the wrist (FER-808). Same path
    /// as the LA's `RestAddThirtyIntent` / `RestRemoveThirtyIntent`. A negative delta is gated by the
    /// sender (the «−30» affordance is hidden once the rest has expired), and `extendRest` floors at «now».
    case adjustRest(sessionId: String, deltaS: Int)
}

/// A wrist-initiated action on the live strength session (FER-808), decoded from the three watch→iPhone
/// control messages above. The iPhone maps each to the exact same session mutator the Live Activity uses,
/// so «Registrar serie / Saltar / ±30 s» behave identically whether they come from the lock screen or the
/// wrist. Defined here (the shared contract) so both the mirroring bridge and `AppModel` see one type.
public enum WatchWorkoutAction: Equatable {
    case completeSet
    case skipRest
    case adjustRest(deltaS: Int)
}

/// Why the watch won't be the one to save the `HKWorkout` — the iPhone reads this to decide whether to
/// take over the save.
public enum WatchSaveFailure: String, Codable, Equatable {
    case noPermission
    case sessionError
    case mirroringLost
}

/// Shared constants for the mirroring channel — the idempotency-key format and the HealthKit payload
/// key — defined once so the iPhone and the watch can never disagree.
public enum WorkoutMirrorKey {
    /// The deterministic `HKMetadataKeyExternalUUID` for a strength session. Identical on both devices
    /// (same `sessionId`), so whichever device writes, the write is idempotent (delete-by-key + save)
    /// and never produces two workouts. Must match `HealthKitBridge.saveStrengthWorkoutIfEnabled`.
    public static func externalUUID(for sessionId: String) -> String { "noop:strength:\(sessionId)" }

    /// The single dictionary key the HealthKit mirror payload (`[String: Any]`) carries the encoded
    /// `WorkoutMirrorMessage` under.
    public static let payloadKey = "noop.mirror"
}

public extension WorkoutMirrorMessage {
    /// JSON-encode for the wire. Non-throwing at the call site is convenient for best-effort sends.
    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// Decode a message received over either channel.
    static func decode(_ data: Data) -> WorkoutMirrorMessage? {
        try? JSONDecoder().decode(WorkoutMirrorMessage.self, from: data)
    }
}

/// The **one-HKWorkout invariant** gate, as a pure function so the 4 scenarios are unit-testable.
///
/// The rule is "omit only on positive confirmation": the iPhone writes its own (estimated) workout by
/// default and abstains **only** when the watch has acked `watchDidSaveWorkout`. That keeps a
/// missing/absent watch regression-free, and the shared `externalUUID` idempotency is the hard backstop
/// if both ever race.
///
/// | Scenario | watch acked save? | iPhone saves? |
/// |---|---|---|
/// | A. watch recorded OK | yes | **no** (watch owns the real workout) |
/// | B. mirror failed / lost | no | yes (estimate) |
/// | C. watch lacks permission | no | yes (estimate) |
/// | D. ended out of range | no | yes (estimate) |
public enum WorkoutSaveGate {
    /// Whether the iPhone should run `saveStrengthWorkoutIfEnabled` for this session.
    public static func iPhoneShouldSaveWorkout(watchDidSaveWorkout: Bool) -> Bool {
        !watchDidSaveWorkout
    }
}
