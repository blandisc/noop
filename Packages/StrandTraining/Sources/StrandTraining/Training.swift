import Foundation

// Value models for the strength tracker. Pure (Codable, Sendable) — WhoopStore adds
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
    public var weightKg: Double?

    public init(id: String = UUID().uuidString, position: Int, kind: SetKind = .work,
                reps: Int? = nil, weightKg: Double? = nil) {
        self.id = id; self.position = position; self.kind = kind
        self.reps = reps; self.weightKg = weightKg
    }
}

/// One exercise slot inside a routine: its per-set scheme, warm-up ramp, and rest rule.
public struct RoutineExercise: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var routineId: String
    public var exerciseId: String
    public var position: Int
    /// The per-set prescription — the source of truth for reps/weight since FER-492. Each work set
    /// carries its own reps and weight (Hevy-style). `targetSets/targetReps/targetWeightKg` below are
    /// kept as derived compatibility fields (WhoopStore mirrors the first work set + count into them).
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

    public init(id: String = UUID().uuidString, routineId: String, exerciseId: String,
                position: Int, targetSets: Int, targetReps: Int? = nil,
                targetWeightKg: Double? = nil, warmupPercents: [Double] = [],
                restMode: RestMode = .heartRate, restSeconds: Int = 90,
                supersetGroup: Int? = nil, sets: [RoutineSet] = [],
                hrRestReference: HRRestReference = .restingMargin, hrRestValue: Double = 0) {
        self.id = id; self.routineId = routineId; self.exerciseId = exerciseId
        self.position = position; self.targetSets = targetSets; self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg; self.warmupPercents = warmupPercents
        self.restMode = restMode; self.restSeconds = restSeconds
        self.supersetGroup = supersetGroup; self.sets = sets
        self.hrRestReference = hrRestReference; self.hrRestValue = hrRestValue
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

    public init(id: String = UUID().uuidString, routineId: String? = nil, startTs: Int,
                endTs: Int? = nil, deviceId: String? = nil, strain: Double? = nil,
                avgHr: Int? = nil, notes: String? = nil) {
        self.id = id; self.routineId = routineId; self.startTs = startTs; self.endTs = endTs
        self.deviceId = deviceId; self.strain = strain; self.avgHr = avgHr; self.notes = notes
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

    public init(id: String = UUID().uuidString, sessionId: String, exerciseId: String,
                position: Int, kind: SetKind = .work, weightKg: Double? = nil,
                reps: Int? = nil, timeS: Double? = nil, distanceM: Double? = nil,
                done: Bool = false, ts: Int) {
        self.id = id; self.sessionId = sessionId; self.exerciseId = exerciseId
        self.position = position; self.kind = kind; self.weightKg = weightKg; self.reps = reps
        self.timeS = timeS; self.distanceM = distanceM; self.done = done; self.ts = ts
    }
}

/// Which kind of personal record. (The estimated-1RM record is FER-349's analytics, not here.)
public enum PRMetric: String, Codable, Sendable {
    case maxWeight   // heaviest work set
    case maxReps     // most reps at any load
    case maxVolume   // best weight×reps in one set
}

/// The best observed work set for an exercise on a given metric. Derived/updated by
/// WhoopStore when a session is saved; read cheaply by the library/detail screens.
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
