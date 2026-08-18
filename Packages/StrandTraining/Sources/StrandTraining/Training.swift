import Foundation

// Value models for the strength tracker. Pure (Codable, Sendable) — CenitStore adds
// GRDB persistence by extension (so GRDB never enters this package); the app and
// StrandAnalytics consume them directly. Ids are UUID strings (user-authored,
// relational data — unlike the sensor streams keyed by (deviceId, ts)). (FER-345)

/// How the rest between sets is timed: by heart-rate recovery from the strap
/// (the NOOP differentiator, FER-348) or a fixed countdown.
public enum RestMode: String, Codable, Sendable {
    case heartRate   // «por FC» — ready when your pulse drops (FER-348)
    case fixed       // «tiempo fijo»
}

/// How the per-exercise HR rest target (the "ready" bpm) is computed when `restMode == .heartRate`.
/// (FER-495) `.restingMargin` is the FER-348 default — target = round(restingHR) + 20; the migration
/// writes it for every existing heartRate row, so old routines keep FER-348 behavior exactly.
/// `hrRestValue` (on `RoutineExercise`) is interpreted per case: a fraction 0…1 for `.peakDrop` /
/// `.karvonenReserve`, bpm for `.fixedBpm`, unused for `.restingMargin`.
public enum HRRestReference: String, Codable, Sendable {
    case restingMargin    // FER-348 default: restingHR + fixed margin
    case peakDrop         // target = peakHR · (1 − value)
    case karvonenReserve  // target = restingHR + value·(maxHR − restingHR)  (Karvonen 1957)
    case fixedBpm         // target = value (bpm)
}

/// The four rest knobs (mode, seconds, HR reference, HR value) as one value (FER-715). The handoff
/// moves rest from the exercise down to the individual set; `RoutineExercise` keeps carrying its four
/// flat fields (the shipped schema + call sites), so this shared shape is the currency of the *new*
/// per-set APIs. SQL stays flat: `routineSet` gains the same four nullable columns, not JSON.
public struct RestConfig: Codable, Sendable, Equatable {
    public var mode: RestMode
    public var seconds: Int
    public var hrReference: HRRestReference
    public var hrValue: Double

    public init(mode: RestMode = .heartRate, seconds: Int = 90,
                hrReference: HRRestReference = .restingMargin, hrValue: Double = 0) {
        self.mode = mode; self.seconds = seconds
        self.hrReference = hrReference; self.hrValue = hrValue
    }
}

/// Where a persisted session-energy figure came from (FER-715). `bandCalculated` = Keytel 2005 over
/// ≥ `Calories.strengthEnergyMinSamples` strap HR samples; `estimated` = the MET fallback (Ainsworth
/// 2011 compendium) when the band wasn't worn. The raw values match the strings the DB stores.
public enum EnergySource: String, Codable, Sendable {
    case bandCalculated = "band_calculated"
    case estimated
}

/// Which rows a rest edit applies to (FER-715, generalizing FER-540's mid-session edit). Consumed by
/// the F1/F2 UI: `.set` touches one planned set, `.exercise` touches the exercise default *and* all
/// its sets.
public enum RestEditScope: Sendable, Equatable {
    case set(routineSetId: String)   // solo esta serie
    case exercise                    // el default del ejercicio + todas sus series
}

/// Where a rest edit lands (FER-715): only the live session, or persisted back to the routine.
public enum RestEditPersistence: Sendable, Equatable {
    case sessionOnly
    case routine
}

/// A user-created folder grouping routines in «Mis rutinas» (FER-494). Flat — no nesting; a routine
/// carries an optional `folderId` referencing one of these. Deleting a folder NULLs its routines'
/// `folderId` (they fall to «Sin carpeta») — it never deletes routines.
public struct RoutineFolder: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var sortOrder: Int

    public init(id: String = UUID().uuidString, name: String, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.sortOrder = sortOrder
    }
}

/// A reusable routine: a name, an optional tag, an optional folder, and an ordered list of exercises
/// (stored as `RoutineExercise` rows referencing this routine's id).
public struct Routine: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var tag: String?
    /// The folder this routine lives in (FER-494); `nil` = «Sin carpeta».
    public var folderId: String?
    public var createdTs: Int
    public var updatedTs: Int
    public var sortOrder: Int

    public init(id: String = UUID().uuidString, name: String, tag: String? = nil,
                folderId: String? = nil, createdTs: Int, updatedTs: Int, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.tag = tag; self.folderId = folderId
        self.createdTs = createdTs; self.updatedTs = updatedTs; self.sortOrder = sortOrder
    }
}

/// One day of the weekly split (FER-531): which routine is planned for a given weekday. `weekday`
/// uses `Calendar.component(.weekday)`'s convention (1 = Sunday … 7 = Saturday) — the same numbering
/// the rest of StrandAnalytics already uses — so there is at most one routine per day (`weekday` is the
/// identity). A weekday with no row is a rest day. There is no foreign key to `routine`: when a routine
/// is deleted the app clears its schedule rows (mirroring how deleting a folder NULLs `folderId`), and a
/// dangling `routineId` derives to a rest day honestly rather than crashing.
public struct RoutineSchedule: Codable, Sendable, Identifiable, Equatable {
    public var weekday: Int        // 1…7 (Calendar weekday convention: 1 = Sunday, 2 = Monday, … 7 = Saturday)
    public var routineId: String
    /// Exactly one routine per weekday → the weekday is the row's identity.
    public var id: Int { weekday }

    public init(weekday: Int, routineId: String) {
        self.weekday = weekday; self.routineId = routineId
    }
}

/// One planned set inside a `RoutineExercise` — the per-set prescription the user builds (FER-492).
/// Mirrors `SetEntry`'s grain (the *performed* set) so the plan and the log line up: a relational row
/// with identity (it reorders and deletes), not a value buried in an array. The guided session (FER-347)
/// seeds its working sets from these. `kind` is always `.work` today — warm-ups stay as `warmupPercents`,
/// expanded at runtime — but the field exists so a future warm-up materialization needs no migration.
public struct RoutineSet: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var position: Int
    public var kind: SetKind
    public var reps: Int?
    /// The top of this set's rep range (E13/FER-94): `nil` = a single fixed target, today's behavior
    /// bit-for-bit. Non-nil prescribes "reps-repsRangeTop" (e.g. 8-12) — `reps` stays the floor,
    /// unchanged. `ProgressionPlanner.evaluate` advances the weight only once every work set touches
    /// the TOP, not the floor. Only meaningful for `kind == .work`: nothing writes it on a warm-up
    /// because the one write path (E7/FER-88, `RoutineEditorScreen`) only offers it there.
    public var repsRangeTop: Int?
    public var weightKg: Double?
    /// This set's own rest override (FER-715); `nil` = inherit the exercise's rest. The v26 migration
    /// materializes existing sets by copying the exercise's rest, so old data reads back identically;
    /// sets added afterward stay `nil` and fall back to the exercise at runtime.
    public var rest: RestConfig?

    public init(id: String = UUID().uuidString, position: Int, kind: SetKind = .work,
                reps: Int? = nil, weightKg: Double? = nil, repsRangeTop: Int? = nil,
                rest: RestConfig? = nil) {
        self.id = id; self.position = position; self.kind = kind
        self.reps = reps; self.weightKg = weightKg; self.repsRangeTop = repsRangeTop; self.rest = rest
    }

    /// Texto de reps para la receta: "piso" cuando no hay techo, "piso-techo" cuando sí — nil cuando la
    /// serie no tiene piso (tipos sin reps, p.ej. tiempo/distancia). Un techo igual o menor al piso se
    /// trata como dato inválido y cae a solo el piso (defensivo: la UI que captura el techo vive fuera
    /// de esta fase, en E7/FER-88).
    public var repsRangeLabel: String? {
        guard let reps else { return nil }
        guard let top = repsRangeTop, top > reps else { return "\(reps)" }
        return "\(reps)-\(top)"
    }
}

/// What to do when an exercise stalls (progression, FER-A). `propose` pre-populates a deload; `warn`
/// only surfaces the stall and leaves the weight untouched.
public enum DeloadPolicy: String, Codable, Sendable {
    case propose
    case warn
}

/// One exercise slot inside a routine: its per-set scheme, warm-up ramp, and rest rule.
public struct RoutineExercise: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var routineId: String
    public var exerciseId: String
    public var position: Int
    /// The per-set prescription — the source of truth for reps/weight since FER-492. Each work set
    /// carries its own reps and weight (Hevy-style). `targetSets/targetReps/targetWeightKg` below are
    /// kept as derived compatibility fields (CenitStore mirrors the first work set + count into them).
    public var sets: [RoutineSet]
    public var targetSets: Int
    public var targetReps: Int?
    public var targetWeightKg: Double?
    /// Warm-up ramp as fractions of the working weight (e.g. [0.4, 0.6, 0.8]); empty = none.
    public var warmupPercents: [Double]
    public var restMode: RestMode
    public var restSeconds: Int
    /// How the HR rest target is computed when `restMode == .heartRate` (FER-495). `.restingMargin`
    /// (default) = FER-348's resting+margin; the other cases use `hrRestValue`.
    public var hrRestReference: HRRestReference
    /// Value for `hrRestReference`: a fraction 0…1 (peakDrop/karvonenReserve), bpm (fixedBpm), unused
    /// for restingMargin. Default 0.
    public var hrRestValue: Double
    /// Superset grouping (FER-346): `nil` = a standalone exercise; the same `Int` within a routine =
    /// one superset, performed in `position` order with rest taken only after the group's last
    /// exercise. The label is opaque (the builder assigns "next free" per routine, not the user) —
    /// grouping is by equality, so gaps in the numbering don't matter. The guided session (FER-347)
    /// reads it to cycle a group and skip the between-exercise rest.
    public var supersetGroup: Int?
    /// Load progression (FER-A). OFF by default — the user turns it on per exercise. When on, hitting
    /// the rep goal on all work sets for `progressionSessions` consecutive sessions bumps the weight.
    public var progressionEnabled: Bool
    /// How many consecutive qualifying sessions before the weight goes up (default 2 = double progression).
    public var progressionSessions: Int
    /// Manual per-session increment in kg; `nil` = derive from the plate/dumbbell inventory (FER-C).
    public var progressionIncrementKg: Double?
    /// What to do on a stall (3 sessions stuck): propose a deload or only warn.
    public var progressionDeload: DeloadPolicy
    /// `true` = raise even on a low-recovery day (skip the TrainingRegulation gate). Default `false`:
    /// a `recoveryLow` day DEFERS an earned raise to the next session (2c's "Recuperación baja" row).
    public var progressionIgnoreRecovery: Bool

    public init(id: String = UUID().uuidString, routineId: String, exerciseId: String,
                position: Int, targetSets: Int, targetReps: Int? = nil,
                targetWeightKg: Double? = nil, warmupPercents: [Double] = [],
                restMode: RestMode = .heartRate, restSeconds: Int = 90,
                supersetGroup: Int? = nil, sets: [RoutineSet] = [],
                hrRestReference: HRRestReference = .restingMargin, hrRestValue: Double = 0,
                progressionEnabled: Bool = false, progressionSessions: Int = 2,
                progressionIncrementKg: Double? = nil, progressionDeload: DeloadPolicy = .propose,
                progressionIgnoreRecovery: Bool = false) {
        self.id = id; self.routineId = routineId; self.exerciseId = exerciseId
        self.position = position; self.targetSets = targetSets; self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg; self.warmupPercents = warmupPercents
        self.restMode = restMode; self.restSeconds = restSeconds
        self.supersetGroup = supersetGroup; self.sets = sets
        self.hrRestReference = hrRestReference; self.hrRestValue = hrRestValue
        self.progressionEnabled = progressionEnabled; self.progressionSessions = progressionSessions
        self.progressionIncrementKg = progressionIncrementKg; self.progressionDeload = progressionDeload
        self.progressionIgnoreRecovery = progressionIgnoreRecovery
    }

    /// The per-set plan to act on: the authored `sets` when present, else a 1:1 expansion of the legacy
    /// target* columns (one work set per `targetSets`, carrying `targetReps`/`targetWeightKg`). Never
    /// empty — the single source for the "sets ↔ target*" fallback shared by persistence, the builder
    /// and the guided session, so the rule lives in one place.
    public var plannedSets: [RoutineSet] {
        sets.isEmpty
            ? (0..<max(targetSets, 1)).map {
                RoutineSet(position: $0, kind: .work, reps: targetReps, weightKg: targetWeightKg) }
            : sets
    }

    /// This exercise's rest, as the shared `RestConfig` shape (FER-715). Bridges the four flat shipped
    /// fields so per-set APIs speak one currency; setting it writes the four fields back.
    public var restConfig: RestConfig {
        get { RestConfig(mode: restMode, seconds: restSeconds,
                         hrReference: hrRestReference, hrValue: hrRestValue) }
        set {
            restMode = newValue.mode; restSeconds = newValue.seconds
            hrRestReference = newValue.hrReference; hrRestValue = newValue.hrValue
        }
    }

    /// The rest to actually apply for a planned set (FER-715): the set's own override, else this
    /// exercise's default. The one fallback rule, pure and testable.
    public func effectiveRest(for set: RoutineSet) -> RestConfig { set.rest ?? restConfig }
}

/// A performed strength session. Optionally linked to a routine and to the strap
/// (`deviceId`) that supplied heart rate / strain.
public struct StrengthSession: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var routineId: String?
    public var startTs: Int
    public var endTs: Int?
    public var deviceId: String?
    public var strain: Double?
    public var avgHr: Int?
    public var notes: String?
    /// Energy spent this session in kcal (FER-715), computed and persisted at close: Keytel 2005 with
    /// strap HR, else the MET fallback. `nil` = a pre-v26 session (the UI shows nothing, never a guess).
    public var energyKcal: Double?
    /// Where `energyKcal` came from (FER-715). `nil` alongside a non-nil `energyKcal` shouldn't occur;
    /// both are written together at close.
    public var energySource: EnergySource?

    public init(id: String = UUID().uuidString, routineId: String? = nil, startTs: Int,
                endTs: Int? = nil, deviceId: String? = nil, strain: Double? = nil,
                avgHr: Int? = nil, notes: String? = nil,
                energyKcal: Double? = nil, energySource: EnergySource? = nil) {
        self.id = id; self.routineId = routineId; self.startTs = startTs; self.endTs = endTs
        self.deviceId = deviceId; self.strain = strain; self.avgHr = avgHr; self.notes = notes
        self.energyKcal = energyKcal; self.energySource = energySource
    }
}

/// Whether a logged set is a warm-up (doesn't count toward PR/volume) or a work set.
public enum SetKind: String, Codable, Sendable {
    case work
    case warmup
}

/// A single logged set. Which measure is filled depends on the exercise's `ExerciseType`
/// (weight+reps / reps / time / distance).
public struct SetEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var sessionId: String
    public var exerciseId: String
    public var position: Int
    public var kind: SetKind
    public var weightKg: Double?
    public var reps: Int?
    public var timeS: Double?
    public var distanceM: Double?
    public var done: Bool
    public var ts: Int
    /// Perceived effort (RPE), 6-10 scale with half-steps (FER-930). Optional: nil means "not captured",
    /// never a default of 0 — marking a set done never requires an RPE.
    public var rpe: Double?

    public init(id: String = UUID().uuidString, sessionId: String, exerciseId: String,
                position: Int, kind: SetKind = .work, weightKg: Double? = nil,
                reps: Int? = nil, timeS: Double? = nil, distanceM: Double? = nil,
                done: Bool = false, ts: Int, rpe: Double? = nil) {
        self.id = id; self.sessionId = sessionId; self.exerciseId = exerciseId
        self.position = position; self.kind = kind; self.weightKg = weightKg; self.reps = reps
        self.timeS = timeS; self.distanceM = distanceM; self.done = done; self.ts = ts; self.rpe = rpe
    }
}

/// A durable snapshot of a strength session **in progress** (FER-798) — everything the app needs to
/// rebuild the live session after a crash/kill so the Apple Watch's `.end` still finds it and the
/// receipt is saved. Pure/`Codable` (lives here, not in the app) so `CenitStore` can persist it without
/// importing the UI model. Captures only what can't be recomputed: the plan, the logged sets, the focus,
/// and the in-flight rest/stopwatch. Deliberately omits `hrSamples` (memory-only by design), the receipt
/// (once there's a summary the session is already saved), and the phase (derivable from `restEndsAt`).
public struct StrengthSessionSnapshot: Codable, Sendable, Equatable {
    /// One logged/planned set, mirroring the app model's working set.
    public struct SetSnapshot: Codable, Sendable, Equatable {
        public var id: String
        public var weightKg: Double
        public var reps: Int
        public var timeS: Int?
        public var distanceM: Double?
        public var done: Bool
        public var doneTs: Int?
        public var rest: RestConfig?
        public var kind: SetKind
        /// Perceived effort (RPE), 6-10 with half-steps (FER-930). Legacy JSON without the key decodes
        /// to nil (Codable default via the memberwise init below, not a `decode(forKey:)` path).
        public var rpe: Double?
        /// Set-scoped note text (FER-932). Legacy JSON without the key decodes to nil, same pattern as `rpe`.
        public var note: String?
        /// El usuario YA editó esta celda (modelo fantasma FER-952): una fila sin tocar muestra su
        /// semilla («la última vez») en tinta tenue y palomearla la registra tal cual. Legacy → nil.
        public var touched: Bool?

        public init(id: String, weightKg: Double, reps: Int, timeS: Int? = nil,
                    distanceM: Double? = nil, done: Bool = false, doneTs: Int? = nil,
                    rest: RestConfig? = nil, kind: SetKind = .work, rpe: Double? = nil,
                    note: String? = nil, touched: Bool? = nil) {
            self.id = id; self.weightKg = weightKg; self.reps = reps; self.timeS = timeS
            self.distanceM = distanceM; self.done = done; self.doneTs = doneTs
            self.rest = rest; self.kind = kind; self.rpe = rpe; self.note = note
            self.touched = touched
        }
    }
    /// One exercise's run within the session.
    public struct RunSnapshot: Codable, Sendable, Equatable {
        public var id: String
        public var exerciseId: String
        public var name: String
        public var type: ExerciseType
        public var restSeconds: Int
        public var restMode: RestMode
        public var hrRestReference: HRRestReference
        public var hrRestValue: Double
        public var lastWeightKg: Double?
        public var lastReps: Int?
        public var lastTimeS: Int?
        public var lastDistanceM: Double?
        public var sets: [SetSnapshot]
        public var currentSet: Int
        public var skipped: Bool
        /// «Volver a X» was tapped for this exercise (FER-835). Optional so a pre-FER-835 snapshot
        /// (key absent) still decodes; nil means false.
        public var raiseOptedOut: Bool?
        /// Superset grouping (FER-931), mirroring `RoutineExercise.supersetGroup`. Optional so a
        /// pre-FER-931 snapshot (key absent) still decodes; nil = standalone exercise.
        public var supersetGroup: Int?
        /// Exercise-scoped note text (FER-932). Optional so a pre-FER-932 snapshot (key absent)
        /// still decodes; nil means no note, never confused with an empty string.
        public var note: String?
        /// An earned raise today's verdict is HOLDING (FER-82): the cells opened at last time's
        /// weight and the session offers it one tap away, so it has to survive a crash like anything
        /// else the athlete can still act on. An APPLIED raise is not carried — its weights are
        /// already in the cells. Optional so a pre-FER-82 snapshot (key absent) still decodes.
        public var heldRaise: HeldRaise?

        /// The three facts a held raise needs to be re-offered after a restore: where it comes from,
        /// where it goes, and the arithmetic sentence that justifies it with real dates.
        public struct HeldRaise: Codable, Sendable, Equatable {
            public var fromKg: Double
            public var toKg: Double
            public var phrase: String
            public init(fromKg: Double, toKg: Double, phrase: String) {
                self.fromKg = fromKg; self.toKg = toKg; self.phrase = phrase
            }
        }

        public init(id: String, exerciseId: String, name: String, type: ExerciseType,
                    restSeconds: Int, restMode: RestMode, hrRestReference: HRRestReference,
                    hrRestValue: Double, lastWeightKg: Double? = nil, lastReps: Int? = nil,
                    lastTimeS: Int? = nil, lastDistanceM: Double? = nil, sets: [SetSnapshot],
                    currentSet: Int, skipped: Bool, raiseOptedOut: Bool? = nil,
                    supersetGroup: Int? = nil, note: String? = nil, heldRaise: HeldRaise? = nil) {
            self.id = id; self.exerciseId = exerciseId; self.name = name; self.type = type
            self.restSeconds = restSeconds; self.restMode = restMode
            self.hrRestReference = hrRestReference; self.hrRestValue = hrRestValue
            self.lastWeightKg = lastWeightKg; self.lastReps = lastReps
            self.lastTimeS = lastTimeS; self.lastDistanceM = lastDistanceM
            self.sets = sets; self.currentSet = currentSet; self.skipped = skipped
            self.raiseOptedOut = raiseOptedOut
            self.supersetGroup = supersetGroup
            self.note = note
            self.heldRaise = heldRaise
        }
    }
    public var id: String
    public var routineId: String?
    public var routineName: String
    public var startTs: Int
    public var runs: [RunSnapshot]
    public var currentIndex: Int
    /// The in-flight rest, preserved so a crash mid-rest doesn't drop the countdown/target.
    public var restEndsAt: Date?
    public var restStartedAt: Date?
    public var currentRestTarget: Int?
    public var currentRestMode: RestMode
    /// The running stopwatch anchor for time/distance sets; nil when not running.
    public var timerStart: Date?
    /// Pause state (FER-823), so a crash mid-pause restores paused with the right accumulated pause time.
    public var paused: Bool
    public var pausedAccumulatedS: Int
    public var pausedAt: Date?
    /// When this snapshot was taken — for debugging / picking the newest if two ever exist.
    public var updatedTs: Int

    public init(id: String, routineId: String?, routineName: String, startTs: Int,
                runs: [RunSnapshot], currentIndex: Int, restEndsAt: Date? = nil,
                restStartedAt: Date? = nil, currentRestTarget: Int? = nil,
                currentRestMode: RestMode = .fixed, timerStart: Date? = nil,
                paused: Bool = false, pausedAccumulatedS: Int = 0, pausedAt: Date? = nil,
                updatedTs: Int) {
        self.id = id; self.routineId = routineId; self.routineName = routineName
        self.startTs = startTs; self.runs = runs; self.currentIndex = currentIndex
        self.restEndsAt = restEndsAt; self.restStartedAt = restStartedAt
        self.currentRestTarget = currentRestTarget; self.currentRestMode = currentRestMode
        self.timerStart = timerStart
        self.paused = paused; self.pausedAccumulatedS = pausedAccumulatedS; self.pausedAt = pausedAt
        self.updatedTs = updatedTs
    }
}

/// A free-text note attached to an exercise's run within a session (FER-932), primarily scoped to
/// `(sessionId, exerciseId)`; `setPosition` non-nil narrows it to one set. Distinct from
/// `StrengthSession.notes` (whole-session, feeds the receipt) — this is per-exercise and cross-session
/// history ("NOTAS ANTERIORES"), not a single field on the session row.
public struct ExerciseNote: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var sessionId: String
    public var exerciseId: String
    /// `nil` = scoped to the whole exercise; non-nil = scoped to that one set (0-based, mirrors `SetEntry.position`).
    public var setPosition: Int?
    public var text: String
    public var ts: Int

    public init(id: String = UUID().uuidString, sessionId: String, exerciseId: String,
                setPosition: Int? = nil, text: String, ts: Int) {
        self.id = id; self.sessionId = sessionId; self.exerciseId = exerciseId
        self.setPosition = setPosition; self.text = text; self.ts = ts
    }
}

/// Which kind of personal record. (The estimated-1RM record is FER-349's analytics, not here.)
public enum PRMetric: String, Codable, Sendable {
    case maxWeight   // heaviest work set
    case maxReps     // most reps at any load
    case maxVolume   // best weight×reps in one set
}

/// The best observed work set for an exercise on a given metric. Derived/updated by
/// CenitStore when a session is saved; read cheaply by the library/detail screens.
public struct PersonalRecord: Codable, Sendable, Identifiable, Equatable {
    /// "<exerciseId>:<metric>" so there is exactly one PR row per exercise per metric.
    public var id: String
    public var exerciseId: String
    public var metric: PRMetric
    public var valueKg: Double?
    public var reps: Int?
    public var ts: Int

    public init(exerciseId: String, metric: PRMetric, valueKg: Double? = nil,
                reps: Int? = nil, ts: Int) {
        self.id = "\(exerciseId):\(metric.rawValue)"
        self.exerciseId = exerciseId; self.metric = metric
        self.valueKg = valueKg; self.reps = reps; self.ts = ts
    }
}
