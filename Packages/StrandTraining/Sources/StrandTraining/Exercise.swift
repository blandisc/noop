import Foundation

/// How a set is measured — drives which fields the logger captures and which «Foco»
/// variant the guided session shows (FER-347/FER-351).
public enum ExerciseType: String, Codable, Sendable, CaseIterable {
    case weightReps   // peso × reps (barbell, dumbbell, machine, cable…)
    case bodyweight   // reps (+ optional lastre)
    case time         // held/timed (plank, stretch, some cardio)
    case distance     // distance + time (cardio)
}

/// A single exercise. The same value type backs both the bundled read-only catalog
/// (`ExerciseCatalog`) and user-created exercises (persisted by WhoopStore). Pure —
/// no DB, no UIKit.
public struct Exercise: Codable, Sendable, Identifiable, Equatable, Hashable {
    /// Stable id: the dataset slug for catalog entries, a UUID string for user-created.
    public let id: String
    public let name: String
    public let type: ExerciseType
    /// Free-form equipment label (e.g. "barbell", "dumbbell", "body only"). Optional.
    public let equipment: String?
    /// Normalized (lowercased) muscle names. Primary = directly targeted.
    public let primaryMuscles: [String]
    /// Secondary = assisting muscles.
    public let secondaryMuscles: [String]
    /// Step-by-step "how to" cues (offline; the bundled instructions). FER-351 adds media.
    public let cues: [String]

    public init(id: String, name: String, type: ExerciseType, equipment: String?,
                primaryMuscles: [String], secondaryMuscles: [String], cues: [String]) {
        self.id = id; self.name = name; self.type = type; self.equipment = equipment
        self.primaryMuscles = primaryMuscles; self.secondaryMuscles = secondaryMuscles
        self.cues = cues
    }
}

public extension Exercise {
    /// Muscle-involvement weights for load math (FER-350). A **convention**, not a
    /// measurement: a primary mover counts fully, a secondary at half. Documented here
    /// so the muscle-fatigue map stays transparent (no black box).
    static let primaryWeight: Double = 1.0
    static let secondaryWeight: Double = 0.5

    /// (muscle, weight) pairs for this exercise — primaries at 1.0, secondaries at 0.5.
    var muscleInvolvement: [(muscle: String, weight: Double)] {
        primaryMuscles.map { ($0, Self.primaryWeight) }
            + secondaryMuscles.map { ($0, Self.secondaryWeight) }
    }
}

/// The bundled, read-only seed catalog of exercises.
///
/// Source: **free-exercise-db** (https://github.com/yuhonas/free-exercise-db), released
/// into the public domain under the Unlicense. Normalized at build time into our schema
/// (id, name, type, equipment, primary/secondary muscles, cues) and shipped as a package
/// resource so it works fully offline. User-created exercises live in WhoopStore and are
/// merged with this catalog by the app's library.
public enum ExerciseCatalog {
    /// Every bundled exercise, decoded once and cached.
    public static let all: [Exercise] = load()

    /// O(1) lookup by id, over the bundled catalog.
    public static let index: [String: Exercise] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// A bundled exercise by id, or nil if it isn't in the seed catalog (e.g. a
    /// user-created exercise, which the app resolves from WhoopStore instead).
    public static func byID(_ id: String) -> Exercise? { index[id] }

    private static func load() -> [Exercise] {
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Exercise].self, from: data)
        else { return [] }
        return list
    }
}
