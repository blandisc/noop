import Foundation
import StrandTraining

// MARK: - noop.workout.v1 — LLM-generated workout-program interchange format (FER-496)
//
// A strength program a user builds by asking their own LLM (the "bring-your-own-LLM" path, mirroring
// noop.diet.v1 / FER-370): NOOP hands out a prompt, the user runs it in their AI with their plan
// (text / photo / PDF), and brings back this file. NOOP never calls the network — the user runs the
// LLM step (same as importing a CSV). This is import-only: the file is produced outside NOOP.
//
// The wire keys are fixed Spanish (the interchange contract — one importer regardless of the plan's
// language); Swift identifiers are English (repo convention). Exercise names are kept VERBATIM in the
// plan's own language — never translated; the app reconciles them against the on-device catalog
// (`WorkoutExerciseReconciler`), which is the one piece this format can't carry.
//
// Parsing is intentionally manual (JSONSerialization, not synthesized Decodable) so each validation
// failure maps to a precise `WorkoutProgramParseError` and unknown fields are ignored for
// forward-compatibility. Only template data (targets), never history — sessions/PRs live on-device.

/// The content language of a program, set by the producer. Not the app's UI language.
public enum WorkoutPlanLanguage: String, Codable, Sendable, Equatable, CaseIterable {
    case es
    case en
}

/// The unit the plan's weights are written in. The importer normalizes everything to kilograms
/// (`RoutineExercise.targetWeightKg`); `lb` weights are converted, `kg` pass through.
public enum WorkoutWeightUnit: String, Codable, Sendable, Equatable, CaseIterable {
    case kg
    case lb

    /// Pounds → kilograms (the international avoirdupois pound).
    public static let lbToKg = 0.45359237

    func toKilograms(_ value: Double) -> Double {
        switch self {
        case .kg: return value
        case .lb: return value * Self.lbToKg
        }
    }
}

/// One exercise slot of a routine: the LLM's exercise name (matched to the catalog later) plus its
/// target scheme. Optional fields are nil when the plan doesn't declare them — never invented.
public struct WorkoutExercise: Codable, Sendable, Equatable {
    /// The catalog id the LLM picked from NOOP's list (FER-521). `nil` when the plan didn't carry one
    /// (older plans, or an exercise the LLM couldn't place). When set, the importer matches by this id
    /// first — exact and language-proof — and only falls back to the name. An unknown id is ignored.
    public let id: String?                  // wire: "id"
    public let name: String                 // wire: "nombre" (verbatim; the reconciliation key)
    public let type: ExerciseType           // wire: "tipo" (default .weightReps)
    public let sets: Int                     // wire: "series" (≥1; a routine slot needs at least one set)
    public let reps: Int?                    // wire: "reps"
    public let weightKg: Double?            // wire: "peso" (normalized to kg via the program's unidad)
    public let restSeconds: Int?            // wire: "descanso_seg"
    public let warmupPercents: [Double]     // wire: "calentamiento_pcts" (fractions in (0,1])
    public let supersetGroup: Int?          // wire: "superset" (opaque grouping within a routine)

    public init(id: String? = nil, name: String, type: ExerciseType = .weightReps, sets: Int, reps: Int? = nil,
                weightKg: Double? = nil, restSeconds: Int? = nil, warmupPercents: [Double] = [],
                supersetGroup: Int? = nil) {
        self.id = id; self.name = name; self.type = type; self.sets = sets; self.reps = reps
        self.weightKg = weightKg; self.restSeconds = restSeconds
        self.warmupPercents = warmupPercents; self.supersetGroup = supersetGroup
    }
}

/// One routine of the program (a day of a split, e.g. "Empuje"): a name, an optional informational
/// tag (e.g. "Lunes"), and an ordered list of exercises.
public struct WorkoutRoutine: Codable, Sendable, Equatable {
    public let name: String                 // wire: "nombre"
    public let tag: String?                 // wire: "etiqueta" (informational only — no scheduling)
    public let exercises: [WorkoutExercise] // wire: "ejercicios" (≥1)

    public init(name: String, tag: String? = nil, exercises: [WorkoutExercise]) {
        self.name = name; self.tag = tag; self.exercises = exercises
    }
}

/// A workout program in the `noop.workout.v1` format: one or more routines (a multi-day split).
public struct WorkoutProgram: Codable, Sendable, Equatable {
    public let schema: String
    public let language: WorkoutPlanLanguage // wire: "idioma"
    public let name: String                  // wire: "programa"
    public let routines: [WorkoutRoutine]    // wire: "rutinas" (≥1)

    public init(schema: String = WorkoutProgram.currentSchema,
                language: WorkoutPlanLanguage, name: String, routines: [WorkoutRoutine]) {
        self.schema = schema; self.language = language; self.name = name; self.routines = routines
    }

    /// The only schema this importer accepts.
    public static let currentSchema = "noop.workout.v1"
}

// MARK: - Errors

/// Why a candidate `noop.workout.v1` payload was rejected. Dedicated (like `DietPlanParseError`): every
/// case is an actionable schema-validation reason the import screen can surface. `description` is a
/// diagnostic string; the UI localizes per case.
public enum WorkoutProgramParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case notJSON
    case unsupportedSchema(found: String)
    case unsupportedIdioma(found: String)
    case unsupportedUnidad(found: String)
    case unsupportedTipo(found: String)
    case noRoutines
    case routineWithoutExercises(name: String)
    case exerciseWithoutName(routine: String)

    public var description: String {
        switch self {
        case .notJSON:                       return "Input is not a valid JSON object."
        case .unsupportedSchema(let f):      return "Unsupported schema: \"\(f)\" (expected \(WorkoutProgram.currentSchema))."
        case .unsupportedIdioma(let f):      return "Unsupported idioma: \"\(f)\" (expected es or en)."
        case .unsupportedUnidad(let f):      return "Unsupported unidad: \"\(f)\" (expected kg or lb)."
        case .unsupportedTipo(let f):        return "Unsupported tipo: \"\(f)\" (expected weightReps, bodyweight, time or distance)."
        case .noRoutines:                    return "The program has no rutinas."
        case .routineWithoutExercises(let n):return "Routine \"\(n)\" has no ejercicios."
        case .exerciseWithoutName(let r):    return "An exercise in routine \"\(r)\" has no nombre."
        }
    }
}

// MARK: - Importer

/// Parses and validates a `noop.workout.v1` payload into a `WorkoutProgram`. Parse-only — it does not
/// touch the database or the exercise catalog (matching is a separate step, `WorkoutExerciseReconciler`).
/// Mirrors `DietPlanImporter`.
public struct WorkoutProgramImporter {

    public init() {}

    /// Parse a UTF-8 JSON payload. Throws a `WorkoutProgramParseError` for any validation failure.
    public func parse(_ data: Data) throws -> WorkoutProgram {
        let any: Any
        do { any = try JSONSerialization.jsonObject(with: data, options: []) }
        catch { throw WorkoutProgramParseError.notJSON }
        guard let root = any as? [String: Any] else { throw WorkoutProgramParseError.notJSON }

        // schema — must match exactly.
        let schema = root["schema"] as? String ?? ""
        guard schema == WorkoutProgram.currentSchema else {
            throw WorkoutProgramParseError.unsupportedSchema(found: schema)
        }

        // idioma — required, es | en.
        let idiomaRaw = root["idioma"] as? String ?? ""
        guard let language = WorkoutPlanLanguage(rawValue: idiomaRaw) else {
            throw WorkoutProgramParseError.unsupportedIdioma(found: idiomaRaw)
        }

        // unidad — defaults to kg when absent; kg | lb accepted, anything else rejected.
        let unidadRaw = root["unidad"] as? String ?? WorkoutWeightUnit.kg.rawValue
        guard let unit = WorkoutWeightUnit(rawValue: unidadRaw) else {
            throw WorkoutProgramParseError.unsupportedUnidad(found: unidadRaw)
        }

        let name = root["programa"] as? String ?? ""

        // rutinas — ≥1, each with ≥1 exercise, each exercise with a non-empty name (the match key).
        guard let rawRoutines = root["rutinas"] as? [[String: Any]], !rawRoutines.isEmpty else {
            throw WorkoutProgramParseError.noRoutines
        }
        var routines: [WorkoutRoutine] = []
        routines.reserveCapacity(rawRoutines.count)
        for (idx, r) in rawRoutines.enumerated() {
            let routineName = r["nombre"] as? String ?? ""
            let routineLabel = routineName.isEmpty ? "rutina-\(idx + 1)" : routineName
            guard let rawExercises = r["ejercicios"] as? [[String: Any]], !rawExercises.isEmpty else {
                throw WorkoutProgramParseError.routineWithoutExercises(name: routineLabel)
            }
            var exercises: [WorkoutExercise] = []
            exercises.reserveCapacity(rawExercises.count)
            for e in rawExercises {
                let exName = (e["nombre"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !exName.isEmpty else {
                    throw WorkoutProgramParseError.exerciseWithoutName(routine: routineLabel)
                }
                // id — optional catalog id the LLM picked from NOOP's list (FER-521). Empty → nil. Its
                // validity (exists in the catalog) is checked at reconciliation, not here.
                let idTrimmed = (e["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let exId = (idTrimmed?.isEmpty == false) ? idTrimmed : nil
                // tipo — optional, defaults to weightReps; an explicit unknown value is rejected.
                let type: ExerciseType
                if let tipoRaw = e["tipo"] as? String {
                    guard let t = ExerciseType(rawValue: tipoRaw) else {
                        throw WorkoutProgramParseError.unsupportedTipo(found: tipoRaw)
                    }
                    type = t
                } else {
                    type = .weightReps
                }
                // series — a routine slot needs ≥1 set; clamp a missing/odd value up to 1 (structural,
                // not invented metric data — reps/weight/rest stay nil when the plan omits them).
                let sets = max(1, Self.intValue(e["series"]) ?? 1)
                let reps = Self.intValue(e["reps"]).flatMap { $0 > 0 ? $0 : nil }
                let weightKg = Self.nonNegativeNumber(e["peso"]).map { unit.toKilograms($0) }
                let rest = Self.intValue(e["descanso_seg"]).flatMap { $0 >= 0 ? $0 : nil }
                // calentamiento_pcts — fractions in (0,1]; drop anything else.
                let warmups: [Double] = (e["calentamiento_pcts"] as? [Any] ?? [])
                    .compactMap { Self.nonNegativeNumber($0) }
                    .filter { $0 > 0 && $0 <= 1 }
                let superset = Self.intValue(e["superset"])
                exercises.append(WorkoutExercise(
                    id: exId, name: exName, type: type, sets: sets, reps: reps, weightKg: weightKg,
                    restSeconds: rest, warmupPercents: warmups, supersetGroup: superset))
            }
            routines.append(WorkoutRoutine(name: routineName,
                                           tag: (r["etiqueta"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                           exercises: exercises))
        }

        return WorkoutProgram(schema: schema, language: language, name: name, routines: routines)
    }

    /// Convenience for the "paste JSON" path.
    public func parse(text: String) throws -> WorkoutProgram {
        try parse(Data(text.utf8))
    }

    /// A finite, non-negative number — rejecting JSON booleans (which bridge to NSNumber) and NaN/∞.
    private static func nonNegativeNumber(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() { return nil }
        guard let n = value as? NSNumber else { return nil }
        let d = n.doubleValue
        return (d.isFinite && d >= 0) ? d : nil
    }

    /// A JSON integer — rejecting booleans and non-integers (1.5), accepting whole-valued doubles.
    private static func intValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() { return nil }
        guard let n = value as? NSNumber else { return nil }
        let d = n.doubleValue
        guard d.isFinite, d == d.rounded() else { return nil }
        return Int(d)
    }
}

// MARK: - Exercise reconciliation (the one piece the format can't carry)

/// Matches the LLM's free-text exercise names against the on-device exercise catalog (the bundled
/// seed + the user's custom exercises). The format keeps names verbatim, so the same movement may be
/// written many ways ("Press de banca con barra" vs "Barbell Bench Press"); here we only do a
/// conservative exact match on a normalized name (lowercased, accent-stripped, whitespace-collapsed).
/// Anything that doesn't match is surfaced to the user to map or create — NOOP never silently guesses.
/// Pure (takes the known exercises in), so it's swift-testable without a database.
public struct WorkoutExerciseReconciler {
    private let byNormalizedName: [String: Exercise]
    private let byId: [String: Exercise]
    private let byLearned: [String: Exercise]
    /// Content-key index (FER-794): normalized name minus es/en stopwords, tokens sorted — so
    /// "Press banca con barra" and "Press de banca con barra" collapse to one key. First wins.
    private let byContentKey: [String: Exercise]
    /// Derived alias table (FER-794): normalized common gym name → exercise. Restores the bridge the
    /// retired synonym table (FER-522) provided, now derived from `Tools/bake-exercisedb`.
    private let byAlias: [String: Exercise]
    /// Each known exercise's per-name content-token sets (the EN name and, when present, the ES name —
    /// kept separate so one language's extra words don't dilute the other's similarity), for fuzzy
    /// suggestions. Content tokens (stopwords stripped, FER-794) so "de/con/the/with" don't count.
    private let tokenized: [(exercise: Exercise, tokenSets: [Set<String>])]

    /// Build from the known exercises (catalog + custom). Indexes each exercise by its `id` (FER-521,
    /// now the native ExerciseDB id), by BOTH its English `name` and Spanish `nameES` (FER-501), by its
    /// content key (FER-794), by the derived aliases (`aliases`: common-name → exercise-id, FER-794),
    /// and by the user's learned aliases (FER-523, `learned`: normalized-name → exercise-id). On a
    /// key collision the first wins — deterministic.
    public init(known: [Exercise], learned: [String: String] = [:], aliases: [String: String] = [:]) {
        var map: [String: Exercise] = [:]
        var ids: [String: Exercise] = [:]
        var content: [String: Exercise] = [:]
        var tokens: [(Exercise, [Set<String>])] = []
        for ex in known {
            ids[ex.id] = ex
            var sets: [Set<String>] = []
            for name in [ex.name, ex.nameES].compactMap({ $0 }) {
                let key = Self.normalize(name)
                if map[key] == nil { map[key] = ex }
                let ckey = Self.contentKey(name)
                if !ckey.isEmpty, content[ckey] == nil { content[ckey] = ex }
                sets.append(Self.contentTokens(name))
            }
            tokens.append((ex, sets))
        }
        // Derived aliases (FER-794) and learned aliases (FER-523): normalize the keys defensively;
        // keep only those still pointing at a known exercise.
        var aliasMap: [String: Exercise] = [:]
        for (name, id) in aliases {
            guard let ex = ids[id] else { continue }
            aliasMap[Self.normalize(name)] = ex
        }
        var learnedMap: [String: Exercise] = [:]
        for (name, id) in learned {
            guard let ex = ids[id] else { continue }
            learnedMap[Self.normalize(name)] = ex
        }
        byNormalizedName = map
        byId = ids
        byLearned = learnedMap
        byContentKey = content
        byAlias = aliasMap
        tokenized = tokens
    }

    /// The catalog exercise whose name matches `name` after pre-clean + normalization, or nil if none does.
    public func match(_ name: String) -> Exercise? {
        byNormalizedName[Self.normalize(Self.preClean(name))]
    }

    /// Resolve an imported exercise to a known one, in cascade: declared catalog `id` (FER-521) >
    /// normalized name EN/ES (FER-501) > learned alias (FER-523). An unknown/invalid id is ignored,
    /// degrading to the next step. Returns nil only when none resolves (→ the user maps it, and that
    /// choice becomes a learned alias for next time).
    public func resolve(_ exercise: WorkoutExercise) -> Exercise? {
        if let id = exercise.id, let hit = byId[id] { return hit }
        let key = Self.normalize(Self.preClean(exercise.name))
        return byNormalizedName[key] ?? byLearned[key]
    }

    /// Resolve a name that `resolve` couldn't, WITHOUT the user (FER-794) — the auto-match tier the
    /// import screen pre-fills and marks as "matched automatically" (always visible and reversible
    /// there; never imported silently). Three strict sub-tiers, in order:
    ///  1. content-key equality — same words minus stopwords ("Press banca con barra" ==
    ///     "Press de banca con barra"), deterministic;
    ///  2. derived alias — the common gym name maps to the movement's basic variant;
    ///  3. confident fuzzy — top suggestion scores ≥ 0.8 with ≥ 0.15 separation from the runner-up,
    ///     and the query has ≥ 2 content tokens (a bare "press" can never auto-match).
    /// Anything below that bar returns nil → the user maps it, as before.
    public func autoMatch(_ name: String) -> Exercise? {
        let cleaned = Self.preClean(name)
        let ckey = Self.contentKey(cleaned)
        if !ckey.isEmpty, let hit = byContentKey[ckey] { return hit }
        if let hit = byAlias[Self.normalize(cleaned)] { return hit }
        guard Self.contentTokens(cleaned).count >= 2 else { return nil }
        let scored = scoredSuggestions(for: name)
        guard let top = scored.first, top.score >= 0.8 else { return nil }
        if scored.count > 1, scored[1].score > top.score - 0.15 { return nil }
        return top.exercise
    }

    /// Up to `limit` catalog/custom exercises whose name is closest to `name` by token-set overlap
    /// (Jaccard over content tokens — stopwords stripped, FER-794), above a minimum similarity. The
    /// "did you mean…?" suggestions the import screen offers for a name that didn't resolve (FER-523).
    /// Ranked by similarity, then name for a stable order. Never auto-applied — the user confirms.
    public func suggestions(for name: String, limit: Int = 3) -> [Exercise] {
        scoredSuggestions(for: name).prefix(limit).map { $0.exercise }
    }

    /// The scored fuzzy matches (exercise, Jaccard 0…1) above the minimum similarity, ranked best-first —
    /// what `suggestions` returns before it drops the scores and truncates. Internal (not public API):
    /// the adversarial test (FER-542) uses the scores to assert that trap names surface no high-confidence
    /// match, so loosening coverage can't quietly start auto-suggesting garbage.
    func scoredSuggestions(for name: String) -> [(exercise: Exercise, score: Double)] {
        let query = Self.contentTokens(Self.preClean(name))
        guard !query.isEmpty else { return [] }
        return tokenized.compactMap { entry -> (exercise: Exercise, score: Double)? in
            // Best Jaccard over the exercise's name variants (EN / ES), so a long name in the OTHER
            // language doesn't dilute the match.
            let score = entry.tokenSets.map { set -> Double in
                let inter = query.intersection(set).count
                guard inter > 0 else { return 0 }
                return Double(inter) / Double(query.union(set).count)
            }.max() ?? 0
            return score >= 0.34 ? (entry.exercise, score) : nil
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.exercise.name < $1.exercise.name }
    }

    /// The unique exercise names across the program that DON'T resolve (by id or name), in first-seen
    /// order, deduped by normalized name. These are exactly the names the import screen asks the user to
    /// map or create. An exercise carrying a valid id is resolved and never listed here.
    public func unmatchedNames(in program: WorkoutProgram) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for routine in program.routines {
            for ex in routine.exercises {
                guard resolve(ex) == nil else { continue }
                let key = Self.normalize(ex.name)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(ex.name)
            }
        }
        return result
    }

    /// Lowercased, diacritic-stripped, whitespace-collapsed — so "Press de Banca" and "press de banca"
    /// (and accented variants) collapse to one key.
    public static func normalize(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let parts = folded.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    /// es/en function words that carry no exercise identity — stripped for content matching (FER-794)
    /// so "Press banca con barra" and "Press de banca con barra" compare equal. Deliberately excludes
    /// quantity words ("una", "dos", "one", "two"): "a una pierna" (single-leg) must stay distinct.
    private static let stopwords: Set<String> = [
        "de", "del", "la", "el", "los", "las", "con", "en", "al", "a", "y", "o", "u", "para", "por",
        "the", "with", "on", "in", "an", "and", "to", "of", "for", "at",
    ]

    /// The name's identity-bearing tokens: normalized, split, stopwords removed. Falls back to the
    /// full token set if everything was a stopword (degenerate input like "de la a").
    static func contentTokens(_ name: String) -> Set<String> {
        let all = Self.normalize(name).split(separator: " ").map(String.init)
        let content = all.filter { !stopwords.contains($0) }
        return Set(content.isEmpty ? all : content)
    }

    /// Order-independent equality key over the content tokens ("banca barra press") — the index key
    /// for the content-exact tier of `autoMatch`.
    static func contentKey(_ name: String) -> String {
        contentTokens(name).sorted().joined(separator: " ")
    }

    /// Strip the formatting noise an LLM (or a user pasting its output) wraps around an exercise name,
    /// BEFORE matching (FER-544): a leading list bullet/enumerator ("- ", "• ", "1. ", "2) ") and a
    /// trailing volume annotation ("4x8", "3 x 10", "4 series", "12 reps"). Applied only to the imported
    /// NAME on the lookup path (resolve / match / suggestions) — never to how the catalog, aliases, or
    /// learned aliases are indexed — so it can't shift the catalog identity guard or the persisted
    /// learned-alias key. Anchored and single-shot, so it never erodes a legitimate name: internal hyphens
    /// ("Close-Grip"), "3/4 Sit-Up", "21s", "Farmer's Walk", and "cardio 30 minutos" are all left intact.
    static func preClean(_ name: String) -> String {
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 1) one leading list bullet or enumerator ("- ", "* ", "• ", "1. ", "2) "), followed by a space.
        s = s.replacingOccurrences(of: #"^([-*•‣◦·]+|\d+[.)])\s+"#, with: "", options: .regularExpression)
        // 2) one trailing volume annotation: "NxM" / "N x M" …
        s = s.replacingOccurrences(of: #"\s+\d+\s*[xX×]\s*\d+$"#, with: "", options: .regularExpression)
        // … or "N series" / "N reps" / "N repeticiones" (case-insensitive).
        s = s.replacingOccurrences(of: #"(?i)\s+\d+\s*(series|serie|sets|set|reps|rep|repeticiones)$"#,
                                   with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
