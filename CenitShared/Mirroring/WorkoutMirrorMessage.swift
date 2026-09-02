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
/// The iPhone stays the single source of truth and the only one that persists to `CenitStore`; the
/// watch is a control + display surface in F1.1 and owns only its own `HKWorkout`.
public enum WorkoutMirrorMessage: Codable, Equatable {
    /// iPhone → watch: start the mirrored session. Carries the iPhone's `sessionId` so both devices
    /// derive the **same** idempotency key (`WorkoutMirrorKey.externalUUID(for:)`).
    case start(sessionId: String, routineName: String, startedAt: Date)

    /// iPhone → watch: a rest window opened / changed. Reuses the existing `RestActivitySnapshot`.
    case rest(RestActivitySnapshot)

    /// iPhone → watch: the capture context between rests (FER-809) — which set is up (N/M), the exercise
    /// and its «weight × reps», so the wrist face shows «qué toca» while the user is working the set (not
    /// only during a rest). Additive: a pre-FER-809 watch simply can't decode this case and drops it
    /// (`decode` is `try?`), so it degrades to the plain pulse face.
    case capture(WorkoutCaptureSnapshot)

    /// iPhone → watch: the lightweight routine plan (FER-810) for the read-only rotor page — each exercise's
    /// name, sets done / total, and which one is current. Additive; sent only when the plan changes.
    case plan(WorkoutPlanSnapshot)

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
    /// `ts` (Nancy · ronda 7) = cuándo tocó la usuaria en la muñeca. `transferUserInfo` es una cola
    /// DURABLE (entrega minutos después, o tras relanzar), así que el iPhone lo necesita para descartar
    /// un toque de un contexto ya cerrado — mismo candado que el inbox de la Live Activity. Opcional:
    /// un reloj viejo que no lo manda decodifica a nil y el iPhone aplica sin el candado (como antes).
    case completeSet(sessionId: String, ts: Date?)

    /// watch → iPhone: skip the current rest from the wrist (FER-808). Same path as the LA's `RestSkipIntent`.
    case skipRest(sessionId: String, ts: Date?)

    /// watch → iPhone: nudge the current rest ceiling by `deltaS` (±30) from the wrist (FER-808). Same path
    /// as the LA's `RestAddThirtyIntent` / `RestRemoveThirtyIntent`. A negative delta is gated by the
    /// sender (the «−30» affordance is hidden once the rest has expired), and `extendRest` floors at «now».
    case adjustRest(sessionId: String, deltaS: Int, ts: Date?)

    /// watch → iPhone: «Ver recibo en iPhone» on the wrist summary (FER-810) → the iPhone opens the saved
    /// workout's history detail (`WorkoutSessionDetailScreen`) for this session. The wrist summary stays
    /// minimal; the rich receipt lives on the phone.
    case openReceipt(sessionId: String)

    /// watch → iPhone: the watch's own live heart rate during the mirrored session (FER-1003 amputation —
    /// there's no band anymore, so the wrist's own HKWorkoutSession becomes the strength sheet's only
    /// live-HR source). Best-effort, same HealthKit mirror channel as `.rest`/`.capture`.
    case watchPulse(bpm: Int)

    /// iPhone → watch: the resting-face context (FER-96), OUTSIDE any active session — today's routine
    /// name and the SAME daily verdict word/tone/advice `EntrenarView.hiloDelVeredicto` shows on the
    /// iPhone, already resolved. Rides `WCSession.updateApplicationContext(_:)` (last-known-state,
    /// delivered even with no active mirror), not the session channels above.
    ///
    /// All four fields are optional so a reloj with none of this yet — or a phone that hasn't resolved a
    /// verdict — falls to the existing «sin lectura» face, never a decode failure.
    ///
    /// `toneRaw` is a plain `String` (one of `"clear"/"caution"/"ease"/"hollow"`), NOT
    /// `EntrenarHilo.Tone` embedded: that type is `Sendable, Hashable` but not `Codable`, and giving it
    /// `Codable` would force `CenitShared` to import `CenitDesign`, which it deliberately does not
    /// (`RestActivitySnapshot`'s `phaseRaw`/`sessionPhaseRaw` set this exact precedent — a raw String for
    /// an enum owned by another layer). `CenitWatch` — which already imports `CenitDesign` to paint —
    /// is the one that translates `toneRaw` back to `EntrenarHilo.Tone` on receipt, falling back to
    /// `.hollow` on anything unrecognized (never a crash).
    case idleContext(word: String?, toneRaw: String?, advice: String?, routineName: String?)

    /// watch → iPhone: «Empezar» from the wrist's idle face (FER-96), OUTSIDE any active session. Carries
    /// no routine/slots — the ONE-oracle invariant: the watch never resolves what «today» means: it only
    /// asks, and the iPhone resolves + starts through the exact same path `EntrenarView`'s «Empezar»
    /// button uses. `sessionId` is reserved (always nil today) for a future idempotency guard against a
    /// duplicate tap; not read yet.
    case startFromWrist(sessionId: String?)
}

/// The capture-phase context the iPhone mirrors to the wrist between rests (FER-809), so the watch's live
/// face shows «qué toca» — which set is up and its load — not only a bare pulse. Sibling of
/// `RestActivitySnapshot` (which covers the rest window); all display-ready, derived on the iPhone (the
/// source of truth) with the same formatting the Live Activity / rest snapshot use. `bpm` is nil with no
/// band → the wrist shows «--», never 0.
public struct WorkoutCaptureSnapshot: Equatable, Codable {
    public var sessionId: String
    public var routineName: String
    /// 1-based index of the set that is up, and the count of sets in the current exercise.
    public var setNumber: Int
    public var setTotal: Int
    public var exerciseName: String
    /// «60 kg × 8» for weight/reps work; empty for time/distance sets (no such datum), matching the rest
    /// snapshot's `returnDetail` rule.
    public var returnDetail: String
    public var bpm: Int?
    /// FER-810→811: the profile's max heart rate, so the wrist can label the effort zone (Z2/Z3…) next to
    /// the pulse. Optional — nil when there's no reliable max (the wrist then omits the zone, never guesses).
    public var hrMax: Int?

    public init(sessionId: String, routineName: String, setNumber: Int, setTotal: Int,
                exerciseName: String, returnDetail: String, bpm: Int?, hrMax: Int? = nil) {
        self.sessionId = sessionId
        self.routineName = routineName
        self.setNumber = setNumber
        self.setTotal = setTotal
        self.exerciseName = exerciseName
        self.returnDetail = returnDetail
        self.bpm = bpm
        self.hrMax = hrMax
    }
}

/// The lightweight routine plan the iPhone mirrors to the wrist for the read-only rotor page (FER-810):
/// each exercise's name, its sets done / total, and which one is current. The watch never edits the plan
/// (it's a glance), so this carries only what the rotor draws — done ✓ / current • / pending ○ + «N/M».
public struct WorkoutPlanSnapshot: Equatable, Codable {
    public struct Exercise: Equatable, Codable {
        public var name: String
        public var setsDone: Int
        public var setsTotal: Int
        public var isCurrent: Bool
        public init(name: String, setsDone: Int, setsTotal: Int, isCurrent: Bool) {
            self.name = name; self.setsDone = setsDone; self.setsTotal = setsTotal; self.isCurrent = isCurrent
        }
    }
    public var sessionId: String
    public var routineName: String
    public var exercises: [Exercise]
    public init(sessionId: String, routineName: String, exercises: [Exercise]) {
        self.sessionId = sessionId; self.routineName = routineName; self.exercises = exercises
    }

    /// A cheap change key so the iPhone only mirrors the plan when its visible state actually moves
    /// (a set completed or the current exercise advanced), not on every HR tick.
    public var signature: String {
        exercises.map { "\($0.setsDone)/\($0.setsTotal)\($0.isCurrent ? "*" : "")" }.joined(separator: ",")
    }
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
