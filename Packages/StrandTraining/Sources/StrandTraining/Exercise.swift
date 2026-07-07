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
    /// Stable id: the native ExerciseDB id for catalog entries (e.g. "01qpYSe"), a UUID
    /// string for user-created. Since FER-779 the catalog IS ExerciseDB, so the id is the
    /// media/data key directly — no name matching.
    public let id: String
    public let name: String
    /// Spanish display name, for bundled catalog entries. `nil` for user-created exercises
    /// (the user types their own, in their own language) — the `es` overlay only covers the
    /// seed catalog. Optional so previously-persisted custom rows decode unchanged.
    public let nameES: String?
    public let type: ExerciseType
    /// Free-form equipment label (e.g. "barbell", "dumbbell", "body weight"). Optional.
    public let equipment: String?
    /// ExerciseDB coarse body-part regions (e.g. "chest", "upper legs", "waist"). Library filter
    /// input (FER-779). Distinct from `primaryMuscles`, which drive the muscle map / load math.
    public let bodyParts: [String]
    /// Muscle names, normalized to NOOP's 17 canonical `MuscleAtlas` keys at bake time. Primary =
    /// directly targeted.
    public let primaryMuscles: [String]
    /// Secondary = assisting muscles.
    public let secondaryMuscles: [String]
    /// Step-by-step "how to" instructions (offline; from ExerciseDB, `Step:N ` prefix stripped).
    public let instructions: [String]
    /// Spanish instructions, for bundled catalog entries (LLM-translated at bake). `nil` for
    /// user-created exercises. Optional so older rows decode unchanged.
    public let instructionsES: [String]?
    /// Remote ExerciseDB GIF (thumbnail + looping clip). A string only — the binary is fetched
    /// lazily via the opt-in media flow (FER-722), never at catalog load. `nil` for custom.
    public let gifUrl: String?

    public init(id: String, name: String, nameES: String? = nil, type: ExerciseType, equipment: String?,
                bodyParts: [String] = [], primaryMuscles: [String], secondaryMuscles: [String],
                instructions: [String], instructionsES: [String]? = nil, gifUrl: String? = nil) {
        self.id = id; self.name = name; self.nameES = nameES; self.type = type; self.equipment = equipment
        self.bodyParts = bodyParts
        self.primaryMuscles = primaryMuscles; self.secondaryMuscles = secondaryMuscles
        self.instructions = instructions; self.instructionsES = instructionsES; self.gifUrl = gifUrl
    }

    /// The name to show: Spanish when asked for the localized form and a translation exists,
    /// otherwise the canonical English name. Pure — the *caller* (app layer) decides `localized`
    /// from the device language, so this package stays UI-agnostic. (FER-501)
    public func displayName(localized: Bool) -> String {
        (localized ? nameES : nil) ?? name
    }

    /// The "how to" steps to show: the Spanish steps when asked for the localized form and a
    /// translation exists, otherwise the English ones. Pure — caller decides `localized`.
    public func displayInstructions(localized: Bool) -> [String] {
        (localized ? instructionsES : nil) ?? instructions
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
/// Source: **ExerciseDB OSS** (https://oss.exercisedb.dev), ~1500 exercises with native ids
/// (FER-779). Baked offline by `Tools/bake-exercisedb/` into our schema (native id, name, derived
/// `ExerciseType`, equipment, body parts, muscles normalized to our 17 canonical keys, offline
/// instructions, and a remote `gifUrl`) and shipped as a package resource so it works fully
/// offline. The es-MX overlay (name + instructions) is LLM-translated at bake into
/// `exercises.es.json`. User-created exercises live in WhoopStore and are merged with this catalog
/// by the app's library.
public enum ExerciseCatalog {
    /// Every bundled exercise, decoded once and cached.
    public static let all: [Exercise] = load()

    /// O(1) lookup by id, over the bundled catalog.
    public static let index: [String: Exercise] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// A bundled exercise by id, or nil if it isn't in the seed catalog (e.g. a
    /// user-created exercise, which the app resolves from WhoopStore instead).
    public static func byID(_ id: String) -> Exercise? { index[id] }

    /// The baked row-thumbnail still for an exercise, or nil if none was baked (FER-800). Each still
    /// is the first frame of that exercise's ExerciseDB GIF, extracted at build time into
    /// `Resources/exercise-stills/{id}.jpg` (~1324 of them). This is the OFFLINE, always-available
    /// image for exercise rows — no network, no opt-in toggle. Exercises with no baked still (dead
    /// CDN media, or user-created ones) return nil → the caller shows the paper placeholder.
    public static func stillURL(id: String) -> URL? {
        Bundle.module.url(forResource: id, withExtension: "jpg", subdirectory: "exercise-stills")
    }

    private static func load() -> [Exercise] {
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Exercise].self, from: data)
        else { return [] }
        let es = loadSpanishOverlay()           // id → Spanish name + instructions
        guard !es.isEmpty else { return list }
        return list.map { ex in
            guard let entry = es[ex.id] else { return ex }
            return Exercise(id: ex.id, name: ex.name, nameES: entry.name, type: ex.type,
                            equipment: ex.equipment, bodyParts: ex.bodyParts,
                            primaryMuscles: ex.primaryMuscles, secondaryMuscles: ex.secondaryMuscles,
                            instructions: ex.instructions, instructionsES: entry.instructions,
                            gifUrl: ex.gifUrl)
        }
    }

    /// One Spanish-overlay entry, keyed by the catalog id: the Spanish name and, optionally, the
    /// Spanish instructions. Tolerant of extra fields for forward-compat.
    private struct SpanishEntry: Decodable { let id: String; let name: String?; let instructions: [String]? }

    /// Load the bundled `exercises.es.json` overlay → id → (Spanish name, Spanish instructions). A
    /// separate file (not inline in `exercises.json`) so the English catalog stays a clean mirror of
    /// the upstream dataset and the Spanish diff is reviewable on its own. Missing/empty → English.
    private static func loadSpanishOverlay() -> [String: SpanishEntry] {
        guard let url = Bundle.module.url(forResource: "exercises.es", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SpanishEntry].self, from: data)
        else { return [:] }
        return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
