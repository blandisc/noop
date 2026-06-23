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

    public static let all: [StarterTemplate] = [
        // — Push / Pull / Legs — the classic 3-day split, each day its own copyable routine.
        StarterTemplate(id: "ppl-push", group: .pushPullLegs, slots: [
            .init("Barbell_Bench_Press_-_Medium_Grip", sets: 4, reps: 6, rest: 150),
            .init("Seated_Dumbbell_Press", sets: 3, reps: 8, rest: 120),
            .init("Incline_Dumbbell_Press", sets: 3, reps: 10, rest: 90),
            .init("Side_Lateral_Raise", sets: 3, reps: 12, rest: 60),
            .init("Triceps_Pushdown", sets: 3, reps: 12, rest: 60),
        ]),
        StarterTemplate(id: "ppl-pull", group: .pushPullLegs, slots: [
            .init("Barbell_Deadlift", sets: 3, reps: 5, rest: 180),
            .init("Pullups", sets: 3, reps: 8, rest: 120),
            .init("Bent_Over_Barbell_Row", sets: 3, reps: 8, rest: 120),
            .init("Wide-Grip_Lat_Pulldown", sets: 3, reps: 10, rest: 90),
            .init("Face_Pull", sets: 3, reps: 15, rest: 60),
            .init("Barbell_Curl", sets: 3, reps: 10, rest: 60),
        ]),
        StarterTemplate(id: "ppl-legs", group: .pushPullLegs, slots: [
            .init("Barbell_Squat", sets: 4, reps: 6, rest: 150),
            .init("Romanian_Deadlift", sets: 3, reps: 8, rest: 120),
            .init("Leg_Press", sets: 3, reps: 10, rest: 90),
            .init("Lying_Leg_Curls", sets: 3, reps: 12, rest: 60),
            .init("Standing_Calf_Raises", sets: 4, reps: 15, rest: 45),
        ]),

        // — Full body — one balanced session, low frequency-friendly.
        StarterTemplate(id: "full-body", group: .fullBody, slots: [
            .init("Barbell_Squat", sets: 3, reps: 5, rest: 150),
            .init("Barbell_Bench_Press_-_Medium_Grip", sets: 3, reps: 5, rest: 150),
            .init("Bent_Over_Barbell_Row", sets: 3, reps: 8, rest: 120),
            .init("Seated_Dumbbell_Press", sets: 3, reps: 10, rest: 90),
            .init("Barbell_Curl", sets: 3, reps: 12, rest: 60),
        ]),

        // — Upper / Lower — the 2-day split, each half its own routine.
        StarterTemplate(id: "upper", group: .upperLower, slots: [
            .init("Barbell_Bench_Press_-_Medium_Grip", sets: 4, reps: 6, rest: 150),
            .init("Bent_Over_Barbell_Row", sets: 4, reps: 6, rest: 150),
            .init("Seated_Dumbbell_Press", sets: 3, reps: 10, rest: 90),
            .init("Wide-Grip_Lat_Pulldown", sets: 3, reps: 10, rest: 90),
            .init("Barbell_Curl", sets: 3, reps: 12, rest: 60),
            .init("Triceps_Pushdown", sets: 3, reps: 12, rest: 60),
        ]),
        StarterTemplate(id: "lower", group: .upperLower, slots: [
            .init("Barbell_Squat", sets: 4, reps: 6, rest: 150),
            .init("Romanian_Deadlift", sets: 3, reps: 8, rest: 120),
            .init("Leg_Press", sets: 3, reps: 12, rest: 90),
            .init("Seated_Leg_Curl", sets: 3, reps: 12, rest: 60),
            .init("Standing_Calf_Raises", sets: 4, reps: 15, rest: 45),
        ]),

        // — At home — bodyweight only, no equipment.
        StarterTemplate(id: "home", group: .home, slots: [
            .init("Pushups", sets: 3, reps: 12, rest: 60),
            .init("Bodyweight_Squat", sets: 3, reps: 15, rest: 60),
            .init("Mountain_Climbers", sets: 3, reps: 20, rest: 45),
            .init("Crunches", sets: 3, reps: 15, rest: 45),
            .init("Plank", sets: 3, reps: 30, rest: 45),
        ]),

        // — Mobility & light cardio — the «softer day» the planner suggests on low recovery (FER-554).
        // Bodyweight only: warm the shoulders, mobilize hips/spine, a touch of light cardio, then cool
        // down. ~20 min. Not a clinical protocol — a gentle reset, never a substitute for real rest.
        StarterTemplate(id: "mobility", group: .mobility, slots: [
            .init("Arm_Circles", sets: 2, reps: 20, rest: 20),
            .init("Worlds_Greatest_Stretch", sets: 2, reps: 8, rest: 30),
            .init("Cat_Stretch", sets: 2, reps: 10, rest: 20),
            .init("Bodyweight_Walking_Lunge", sets: 3, reps: 12, rest: 30),
            .init("Mountain_Climbers", sets: 3, reps: 20, rest: 30),
            .init("Childs_Pose", sets: 2, reps: 30, rest: 20),
        ]),
    ]

    /// Templates in one program group, in declaration order.
    public static func inGroup(_ group: StarterTemplate.Group) -> [StarterTemplate] {
        all.filter { $0.group == group }
    }

    /// A template by id, or nil.
    public static func byID(_ id: String) -> StarterTemplate? { all.first { $0.id == id } }
}
