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
    /// Spanish display name, for bundled catalog entries (FER-501). `nil` for user-created
    /// exercises (the user types their own, in their own language) — the `es` overlay only
    /// covers the seed catalog. Optional so previously-persisted custom rows decode unchanged.
    public let nameES: String?
    public let type: ExerciseType
    /// Free-form equipment label (e.g. "barbell", "dumbbell", "body only"). Optional.
    public let equipment: String?
    /// Normalized (lowercased) muscle names. Primary = directly targeted.
    public let primaryMuscles: [String]
    /// Secondary = assisting muscles.
    public let secondaryMuscles: [String]
    /// Step-by-step "how to" cues (offline; the bundled instructions). FER-351 adds media.
    public let cues: [String]
    /// Spanish "how to" cues, for bundled catalog entries (FER-503). `nil` for user-created exercises
    /// (no overlay). Same step structure as `cues` when present. Optional so older rows decode unchanged.
    public let cuesES: [String]?

    public init(id: String, name: String, nameES: String? = nil, type: ExerciseType, equipment: String?,
                primaryMuscles: [String], secondaryMuscles: [String], cues: [String], cuesES: [String]? = nil) {
        self.id = id; self.name = name; self.nameES = nameES; self.type = type; self.equipment = equipment
        self.primaryMuscles = primaryMuscles; self.secondaryMuscles = secondaryMuscles
        self.cues = cues; self.cuesES = cuesES
    }

    /// The name to show: Spanish when asked for the localized form and a translation exists,
    /// otherwise the canonical English name. Pure — the *caller* (app layer) decides `localized`
    /// from the device language, so this package stays UI-agnostic. (FER-501)
    public func displayName(localized: Bool) -> String {
        (localized ? nameES : nil) ?? name
    }

    /// The "how to" cues to show: the Spanish steps when asked for the localized form and a translation
    /// exists, otherwise the English ones. Pure — caller decides `localized`. (FER-503)
    public func displayCues(localized: Bool) -> [String] {
        (localized ? cuesES : nil) ?? cues
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
        let es = loadSpanishOverlay()           // id → Spanish name + cues (FER-501/FER-503)
        guard !es.isEmpty else { return list }
        return list.map { ex in
            guard let entry = es[ex.id] else { return ex }
            return Exercise(id: ex.id, name: ex.name, nameES: entry.name, type: ex.type,
                            equipment: ex.equipment, primaryMuscles: ex.primaryMuscles,
                            secondaryMuscles: ex.secondaryMuscles, cues: ex.cues, cuesES: entry.cues)
        }
    }

    /// One Spanish-overlay entry, keyed by the catalog id: the Spanish name (FER-501) and, optionally,
    /// the Spanish cues (FER-503). Tolerant of extra fields for forward-compat.
    private struct SpanishEntry: Decodable { let id: String; let name: String?; let cues: [String]? }

    /// Load the bundled `exercises.es.json` overlay → id → (Spanish name, Spanish cues). A separate file
    /// (not inline in `exercises.json`) so the English catalog stays a clean mirror of the upstream
    /// dataset and the Spanish diff is reviewable on its own. Missing/empty → falls back to English.
    private static func loadSpanishOverlay() -> [String: SpanishEntry] {
        guard let url = Bundle.module.url(forResource: "exercises.es", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SpanishEntry].self, from: data)
        else { return [:] }
        return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
