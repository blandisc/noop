import Foundation

// StarterTemplates.swift — bundled, offline starter routines (FER-386).
//
// A small, curated set of proven routines the user can copy into «My routines» as a normal,
// editable `Routine` — a one-time copy, never a live link, never a network call. Each slot
// references a real `ExerciseCatalog` id, and `makeRoutine` materializes a template into the same
// `Routine` + `RoutineExercise` rows the builder (FER-346) writes, so a copied template is
// indistinguishable from a hand-built one (and edits/deletes the same way).
//
// Pure data + pure transform (no DB, no UIKit). The display names live in the app layer (localized
// via the string catalog); here a template carries only its id, program group, and slots.

/// One bundled starter routine: an ordered list of catalog exercises with a target scheme and rest.
public struct StarterTemplate: Identifiable, Sendable, Equatable {

    /// The program a template belongs to — drives the section grouping in the picker.
    public enum Group: String, Sendable, CaseIterable {
        case pushPullLegs
        case fullBody
        case upperLower
        case home
        case mobility
    }

    /// One planned slot: a catalog exercise id with its target sets/reps and fixed rest (seconds).
    public struct Slot: Sendable, Equatable {
        public let exerciseId: String
        public let sets: Int
        public let reps: Int?
        public let restSeconds: Int

        public init(_ exerciseId: String, sets: Int, reps: Int?, rest: Int) {
            self.exerciseId = exerciseId
            self.sets = sets
            self.reps = reps
            self.restSeconds = rest
        }
    }

    public let id: String
    public let group: Group
    public let slots: [Slot]

    public init(id: String, group: Group, slots: [Slot]) {
        self.id = id
        self.group = group
        self.slots = slots
    }
}

public extension StarterTemplate {
    /// How many exercises this template plans.
    var exerciseCount: Int { slots.count }

    /// Materialize this template into a saveable routine + its ordered exercises — the «copy». Pure:
    /// the caller supplies the localized `name`, a timestamp, and (optionally) the new routine id, so
    /// the copy is a fresh routine with no link back to the template. Rest stays the template's fixed
    /// seconds; everything else mirrors the builder's defaults, so it edits like any user routine.
    func makeRoutine(name: String, now: Int,
                     routineId: String = UUID().uuidString) -> (Routine, [RoutineExercise]) {
        let routine = Routine(id: routineId, name: name, createdTs: now, updatedTs: now)
        let exercises = slots.enumerated().map { index, slot in
            RoutineExercise(routineId: routineId, exerciseId: slot.exerciseId, position: index,
                            targetSets: slot.sets, targetReps: slot.reps, targetWeightKg: nil,
                            restSeconds: slot.restSeconds)
        }
        return (routine, exercises)
    }
}

/// The bundled catalog of starter templates. Curated compound-first routines drawn from the seed
/// exercise catalog (`ExerciseCatalog`); schemes are conventional starting points the user edits.
public enum StarterTemplates {

    // Slots reference native ExerciseDB ids (FER-779); re-curated from the new catalog by movement.
    public static let all: [StarterTemplate] = [
        // — Push / Pull / Legs — the classic 3-day split, each day its own copyable routine.
        StarterTemplate(id: "ppl-push", group: .pushPullLegs, slots: [
            .init("EIeI8Vf", sets: 4, reps: 6, rest: 150),   // barbell bench press
            .init("znQUdHY", sets: 3, reps: 8, rest: 120),   // dumbbell seated shoulder press
            .init("ns0SIbU", sets: 3, reps: 10, rest: 90),   // dumbbell incline bench press
            .init("DsgkuIt", sets: 3, reps: 12, rest: 60),   // dumbbell lateral raise
            .init("gAwDzB3", sets: 3, reps: 12, rest: 60),   // cable triceps pushdown (v-bar)
        ]),
        StarterTemplate(id: "ppl-pull", group: .pushPullLegs, slots: [
            .init("ila4NZS", sets: 3, reps: 5, rest: 180),   // barbell deadlift
            .init("lBDjFxJ", sets: 3, reps: 8, rest: 120),   // pull-up
            .init("eZyBC3j", sets: 3, reps: 8, rest: 120),   // barbell bent over row
            .init("LEprlgG", sets: 3, reps: 10, rest: 90),   // cable lat pulldown
            .init("wqNPGCg", sets: 3, reps: 15, rest: 60),   // cable rear delt row (face-pull)
            .init("25GPyDY", sets: 3, reps: 10, rest: 60),   // barbell curl
        ]),
        StarterTemplate(id: "ppl-legs", group: .pushPullLegs, slots: [
            .init("qXTaZnJ", sets: 4, reps: 6, rest: 150),   // barbell full squat
            .init("wQ2c4XD", sets: 3, reps: 8, rest: 120),   // barbell romanian deadlift
            .init("V07qpXy", sets: 3, reps: 10, rest: 90),   // lever leg press
            .init("17lJ1kr", sets: 3, reps: 12, rest: 60),   // lever lying leg curl
            .init("ykUOVze", sets: 4, reps: 15, rest: 45),   // lever standing calf raise
        ]),

        // — Full body — one balanced session, low frequency-friendly.
        StarterTemplate(id: "full-body", group: .fullBody, slots: [
            .init("qXTaZnJ", sets: 3, reps: 5, rest: 150),   // barbell full squat
            .init("EIeI8Vf", sets: 3, reps: 5, rest: 150),   // barbell bench press
            .init("eZyBC3j", sets: 3, reps: 8, rest: 120),   // barbell bent over row
            .init("znQUdHY", sets: 3, reps: 10, rest: 90),   // dumbbell seated shoulder press
            .init("25GPyDY", sets: 3, reps: 12, rest: 60),   // barbell curl
        ]),

        // — Upper / Lower — the 2-day split, each half its own routine.
        StarterTemplate(id: "upper", group: .upperLower, slots: [
            .init("EIeI8Vf", sets: 4, reps: 6, rest: 150),   // barbell bench press
            .init("eZyBC3j", sets: 4, reps: 6, rest: 150),   // barbell bent over row
            .init("znQUdHY", sets: 3, reps: 10, rest: 90),   // dumbbell seated shoulder press
            .init("LEprlgG", sets: 3, reps: 10, rest: 90),   // cable lat pulldown
            .init("25GPyDY", sets: 3, reps: 12, rest: 60),   // barbell curl
            .init("gAwDzB3", sets: 3, reps: 12, rest: 60),   // cable triceps pushdown (v-bar)
        ]),
        StarterTemplate(id: "lower", group: .upperLower, slots: [
            .init("qXTaZnJ", sets: 4, reps: 6, rest: 150),   // barbell full squat
            .init("wQ2c4XD", sets: 3, reps: 8, rest: 120),   // barbell romanian deadlift
            .init("V07qpXy", sets: 3, reps: 12, rest: 90),   // lever leg press
            .init("Zg3XY7P", sets: 3, reps: 12, rest: 60),   // lever seated leg curl
            .init("ykUOVze", sets: 4, reps: 15, rest: 45),   // lever standing calf raise
        ]),

        // — At home — bodyweight only, no equipment.
        StarterTemplate(id: "home", group: .home, slots: [
            .init("I4hDWkc", sets: 3, reps: 12, rest: 60),   // push-up
            .init("9E25EOx", sets: 3, reps: 15, rest: 60),   // split squats (bodyweight)
            .init("RJgzwny", sets: 3, reps: 20, rest: 45),   // mountain climber
            .init("TFqbd8t", sets: 3, reps: 15, rest: 45),   // crunch floor
            .init("hCjGsRQ", sets: 3, reps: 30, rest: 45),   // plank
        ]),

        // — Mobility & light cardio — the «softer day» the planner suggests on low recovery (FER-554).
        // Bodyweight only: warm the shoulders, mobilize hips/spine, a touch of light cardio, then cool
        // down. ~20 min. Not a clinical protocol — a gentle reset, never a substitute for real rest.
        StarterTemplate(id: "mobility", group: .mobility, slots: [
            .init("Uto7l43", sets: 2, reps: 20, rest: 20),   // chest & front-of-shoulder stretch
            .init("K9VL0Jq", sets: 2, reps: 8, rest: 30),    // lunge with twist (world's greatest)
            .init("JbC2iaV", sets: 2, reps: 10, rest: 20),   // spine stretch (cat-cow)
            .init("IZVHb27", sets: 3, reps: 12, rest: 30),   // walking lunge
            .init("RJgzwny", sets: 3, reps: 20, rest: 30),   // mountain climber
            .init("99rWm7w", sets: 2, reps: 30, rest: 20),   // hamstring stretch (child's-pose-like)
        ]),
    ]

    /// Templates in one program group, in declaration order.
    public static func inGroup(_ group: StarterTemplate.Group) -> [StarterTemplate] {
        all.filter { $0.group == group }
    }

    /// A template by id, or nil.
    public static func byID(_ id: String) -> StarterTemplate? { all.first { $0.id == id } }
}
