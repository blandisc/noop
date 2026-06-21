import Foundation

// MARK: - noop.diet.v1 — prescribed-diet interchange format (FER-370)
//
// A nutritionist's plan, captured once and tracked for adherence (NOT a calorie
// counter). Three producers fill the SAME format and converge on one importer: an
// external LLM (the "copy prompt" path), a future on-device parse, and manual entry.
//
// The wire keys are fixed Spanish (the interchange contract — one importer regardless
// of the plan's language); Swift identifiers are English (repo convention) and bridge
// via CodingKeys. Values (food / meal names) are kept VERBATIM in the plan's own
// language — never translated; `language` only records which language that is.
//
// Parsing is intentionally manual (JSONSerialization, not synthesized Decodable) so each
// validation failure maps to a precise `DietPlanParseError` and unknown fields are ignored
// for forward-compatibility. The Codable conformance is used only to RE-ENCODE a validated
// plan into the canonical payload that WhoopStore persists.

/// The content language of a plan, detected by the producer. Not the app's UI language.
public enum DietPlanLanguage: String, Codable, Sendable, Equatable, CaseIterable {
    case es
    case en
}

/// The plan's repetition cycle. `diario` = the same plan every day; `semanal` = per-weekday variation,
/// where each meal declares its `dias` (FER-431).
public enum DietPlanCycle: String, Codable, Sendable, Equatable, CaseIterable {
    case diario
    case semanal
}

/// One interchangeable option for a meal (an "equivalente"): you comply by eating any one.
public struct DietOption: Codable, Sendable, Equatable {
    public let foods: [String]            // wire: "alimentos" (≥1)
    public init(foods: [String]) { self.foods = foods }
    enum CodingKeys: String, CodingKey { case foods = "alimentos" }
}

/// One meal of the daily plan (desayuno, comida, …).
public struct DietMeal: Codable, Sendable, Equatable {
    public let id: String
    public let name: String               // wire: "nombre"
    public let suggestedTime: String?     // wire: "hora_sugerida" ("HH:MM", 24h)
    public let options: [DietOption]      // wire: "opciones" (≥1)
    public let notes: String?             // wire: "notas"
    /// ISO weekdays (1=Mon…7=Sun) this meal applies to, for `semanal` plans (FER-431). `nil` = every day
    /// (a `diario` plan, or a meal that repeats all week). The importer validates + normalizes (sorted,
    /// deduped); the wire key is `dias`.
    public let days: [Int]?               // wire: "dias"

    public init(id: String, name: String, suggestedTime: String?, options: [DietOption],
                notes: String?, days: [Int]? = nil) {
        self.id = id; self.name = name; self.suggestedTime = suggestedTime
        self.options = options; self.notes = notes; self.days = days
    }

    /// Whether this meal is planned on a given ISO weekday (1=Mon…7=Sun). `days == nil` → every day.
    public func applies(toISOWeekday isoWeekday: Int) -> Bool {
        days?.contains(isoWeekday) ?? true
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name = "nombre"
        case suggestedTime = "hora_sugerida"
        case options = "opciones"
        case notes = "notas"
        case days = "dias"
    }
}

/// A prescribed diet plan in the `noop.diet.v1` format.
public struct DietPlan: Codable, Sendable, Equatable {
    /// The schema identifier. Always `noop.diet.v1` for a validated plan.
    public let schema: String
    public let language: DietPlanLanguage     // wire: "idioma"
    public let name: String                   // wire: "nombre"
    public let cycle: DietPlanCycle           // wire: "ciclo"
    public let meals: [DietMeal]              // wire: "comidas" (≥1)
    /// Declared daily targets only (e.g. `calorias_kcal`, `proteina_g`). `nil` when the plan
    /// declares none — never synthesized. Values are non-negative finite numbers.
    public let dailyTargets: [String: Double]?  // wire: "objetivos_diarios"
    public let rules: [String]?               // wire: "reglas"

    public init(schema: String = DietPlan.currentSchema,
                language: DietPlanLanguage,
                name: String,
                cycle: DietPlanCycle = .diario,
                meals: [DietMeal],
                dailyTargets: [String: Double]? = nil,
                rules: [String]? = nil) {
        self.schema = schema; self.language = language; self.name = name; self.cycle = cycle
        self.meals = meals; self.dailyTargets = dailyTargets; self.rules = rules
    }

    /// The only schema this importer accepts.
    public static let currentSchema = "noop.diet.v1"

    enum CodingKeys: String, CodingKey {
        case schema
        case language = "idioma"
        case name = "nombre"
        case cycle = "ciclo"
        case meals = "comidas"
        case dailyTargets = "objetivos_diarios"
        case rules = "reglas"
    }
}

// MARK: - Weekday mapping (FER-431)

/// Bridges Apple's `Calendar` weekday to the wire's ISO weekday, so a `semanal` plan's `dias` (1=Mon…
/// 7=Sun — the human/nutritionist convention an LLM produces) line up with the day the app is showing.
/// Defined once, pure: the app passes its already-computed `Calendar` weekday and gets the ISO one.
public enum DietWeekday {
    /// Apple `Calendar` weekday (1=Sun…7=Sat) → wire ISO weekday (1=Mon…7=Sun).
    public static func isoWeekday(forCalendarWeekday calendarWeekday: Int) -> Int {
        ((calendarWeekday + 5) % 7) + 1
    }

    /// Wire ISO weekday (1=Mon…7=Sun) → Apple `Calendar` weekday (1=Sun…7=Sat). Inverse of the above —
    /// used to set `DateComponents.weekday` for per-day notification triggers (FER-431).
    public static func calendarWeekday(forISOWeekday isoWeekday: Int) -> Int {
        (isoWeekday % 7) + 1
    }
}

public extension DietPlan {
    /// The meals planned on a given ISO weekday (1=Mon…7=Sun). A `diario` plan (meals without `dias`)
    /// returns every meal; a `semanal` plan returns only the meals that apply that day. (FER-431)
    func meals(forISOWeekday isoWeekday: Int) -> [DietMeal] {
        meals.filter { $0.applies(toISOWeekday: isoWeekday) }
    }
}

// MARK: - Errors

/// Why a candidate `noop.diet.v1` payload was rejected. Dedicated (not `ImportError`, which is
/// about files / zips): every case is an actionable schema-validation reason the capture screen
/// (FER-371) can surface. `description` is a diagnostic string; the UI localizes per case.
public enum DietPlanParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case notJSON
    case unsupportedSchema(found: String)
    case unsupportedIdioma(found: String)
    case unsupportedCiclo(found: String)
    case noMeals
    case mealWithoutOptions(id: String)
    case emptyOption(id: String)
    case invalidDailyTargets
    case invalidDias(id: String)
    case semanalWithoutDias

    public var description: String {
        switch self {
        case .notJSON:                    return "Input is not a valid JSON object."
        case .unsupportedSchema(let f):   return "Unsupported schema: \"\(f)\" (expected \(DietPlan.currentSchema))."
        case .unsupportedIdioma(let f):   return "Unsupported idioma: \"\(f)\" (expected es or en)."
        case .unsupportedCiclo(let f):    return "Unsupported ciclo: \"\(f)\" (expected diario or semanal)."
        case .noMeals:                    return "The plan has no comidas."
        case .mealWithoutOptions(let id): return "Meal \"\(id)\" has no opciones."
        case .emptyOption(let id):        return "Meal \"\(id)\" has an option with no alimentos."
        case .invalidDailyTargets:        return "objetivos_diarios must be an object of non-negative numbers."
        case .invalidDias(let id):        return "Meal \"\(id)\" has invalid dias (expected a non-empty array of weekdays 1–7)."
        case .semanalWithoutDias:         return "A semanal plan needs at least one meal with dias."
        }
    }
}

// MARK: - Importer

/// Parses and validates a `noop.diet.v1` payload (from any producer) into a `DietPlan`.
/// Parse-only — it does not touch the database (mirrors `WhoopExportImporter`). Persistence
/// is wired separately (see `makeDietPlanRow` + WhoopStore).
public struct DietPlanImporter {

    public init() {}

    /// Parse a UTF-8 JSON payload. Throws a `DietPlanParseError` for any validation failure.
    public func parse(_ data: Data) throws -> DietPlan {
        let any: Any
        do { any = try JSONSerialization.jsonObject(with: data, options: []) }
        catch { throw DietPlanParseError.notJSON }
        guard let root = any as? [String: Any] else { throw DietPlanParseError.notJSON }

        // schema — must match exactly.
        let schema = root["schema"] as? String ?? ""
        guard schema == DietPlan.currentSchema else {
            throw DietPlanParseError.unsupportedSchema(found: schema)
        }

        // idioma — required, es | en.
        let idiomaRaw = root["idioma"] as? String ?? ""
        guard let language = DietPlanLanguage(rawValue: idiomaRaw) else {
            throw DietPlanParseError.unsupportedIdioma(found: idiomaRaw)
        }

        // ciclo — defaults to diario when absent; diario | semanal accepted, anything else rejected (FER-431).
        let cicloRaw = root["ciclo"] as? String ?? DietPlanCycle.diario.rawValue
        guard let cycle = DietPlanCycle(rawValue: cicloRaw) else {
            throw DietPlanParseError.unsupportedCiclo(found: cicloRaw)
        }

        let name = root["nombre"] as? String ?? ""

        // comidas — ≥1, each with ≥1 option, each option with ≥1 food (kept verbatim).
        guard let rawMeals = root["comidas"] as? [[String: Any]], !rawMeals.isEmpty else {
            throw DietPlanParseError.noMeals
        }
        var meals: [DietMeal] = []
        meals.reserveCapacity(rawMeals.count)
        for (idx, m) in rawMeals.enumerated() {
            let mealId = (m["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "comida-\(idx + 1)"
            guard let rawOptions = m["opciones"] as? [[String: Any]], !rawOptions.isEmpty else {
                throw DietPlanParseError.mealWithoutOptions(id: mealId)
            }
            var options: [DietOption] = []
            options.reserveCapacity(rawOptions.count)
            for o in rawOptions {
                guard let foods = o["alimentos"] as? [String], !foods.isEmpty else {
                    throw DietPlanParseError.emptyOption(id: mealId)
                }
                options.append(DietOption(foods: foods))   // verbatim, no translation
            }
            // dias (FER-431) — optional per-meal weekdays for `semanal`; a non-empty set of 1…7,
            // normalized sorted+deduped. Absent → nil (applies every day). Kept even on a diario plan
            // (forward-compat — a producer that over-tags is harmless).
            var days: [Int]? = nil
            if let rawDias = m["dias"] {
                guard let arr = rawDias as? [Any], !arr.isEmpty else {
                    throw DietPlanParseError.invalidDias(id: mealId)
                }
                var set = Set<Int>()
                for v in arr {
                    guard let n = Self.weekdayInt(v) else { throw DietPlanParseError.invalidDias(id: mealId) }
                    set.insert(n)
                }
                days = set.sorted()
            }
            meals.append(DietMeal(
                id: mealId,
                name: m["nombre"] as? String ?? "",
                suggestedTime: m["hora_sugerida"] as? String,
                options: options,
                notes: m["notas"] as? String,
                days: days))
        }

        // A semanal plan must actually vary by day — at least one meal with `dias` (else it's a
        // mislabeled diario, which the producer should fix). (FER-431)
        if cycle == .semanal, !meals.contains(where: { $0.days != nil }) {
            throw DietPlanParseError.semanalWithoutDias
        }

        // objetivos_diarios — optional; only declared non-negative numbers, never invented. An
        // empty object normalizes to nil ("no targets").
        var dailyTargets: [String: Double]? = nil
        if let raw = root["objetivos_diarios"] {
            guard let dict = raw as? [String: Any] else { throw DietPlanParseError.invalidDailyTargets }
            if !dict.isEmpty {
                var targets: [String: Double] = [:]
                targets.reserveCapacity(dict.count)
                for (key, value) in dict {
                    guard let n = Self.nonNegativeNumber(value) else { throw DietPlanParseError.invalidDailyTargets }
                    targets[key] = n
                }
                dailyTargets = targets
            }
        }

        let rules = root["reglas"] as? [String]

        return DietPlan(schema: schema, language: language, name: name, cycle: cycle,
                        meals: meals, dailyTargets: dailyTargets, rules: rules)
    }

    /// Convenience for the "paste JSON" path.
    public func parse(text: String) throws -> DietPlan {
        try parse(Data(text.utf8))
    }

    /// A finite, non-negative number — rejecting JSON booleans (which bridge to NSNumber) and NaN/∞.
    private static func nonNegativeNumber(_ value: Any) -> Double? {
        if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() { return nil }
        guard let n = value as? NSNumber else { return nil }
        let d = n.doubleValue
        return (d.isFinite && d >= 0) ? d : nil
    }

    /// A JSON integer in 1…7 — rejecting booleans, non-integers (1.5), strings, and out-of-range. (FER-431)
    private static func weekdayInt(_ value: Any) -> Int? {
        if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() { return nil }
        guard let n = value as? NSNumber else { return nil }
        let d = n.doubleValue
        guard d == d.rounded(), (1.0...7.0).contains(d) else { return nil }
        return Int(d)
    }
}
