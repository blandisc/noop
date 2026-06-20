import Foundation

// CoachGrounding.swift — the pure, DB-free bridge between the InsightEngine and the
// "Pregúntale a tus datos" free-text coach (FER-308).
//
// It turns the engine's ranked `[Insight]` into a compact, token-bounded fact summary
// (≤ maxFacts, no raw series) that fits the on-device model's 4096-token window, plus:
//   • a deterministic Level-1 answer (chips → templated `reading`s straight from the engine),
//     used verbatim when there is no Apple Intelligence — so the no-AI path speaks the SAME
//     numbers as the AI path;
//   • a pure `validate(answer:)` guard that flags any figure NOT produced by the engine — the
//     testable half of the golden rule ("the model never invents a figure").
//
// Pure: Foundation only. No platform framework (UIKit/AppKit/CoreBluetooth/FoundationModels),
// no DB, no network. The on-device session (`FoundationModels`) lives in the app shell and only
// ever receives the text this file produces; it never sees raw data and never computes a number.

// MARK: - Fact

/// One ranked fact handed to the coach, derived 1:1 from an `Insight`. `id` is a stable index so
/// a reply can cite which facts it used.
public struct GroundingFact: Equatable, Sendable {
    public let id: Int
    public let kind: InsightKind
    /// The engine's es-MX one-liner (already carries the figure). The coach rewrites tone, not numbers.
    public let statement: String
    public let figure: Double
    public let unit: String
    public let metric: String
    public let n: Int
    public let significant: Bool
    public let confidence: InsightConfidence

    public init(id: Int, kind: InsightKind, statement: String, figure: Double, unit: String,
                metric: String, n: Int, significant: Bool, confidence: InsightConfidence) {
        self.id = id
        self.kind = kind
        self.statement = statement
        self.figure = figure
        self.unit = unit
        self.metric = metric
        self.n = n
        self.significant = significant
        self.confidence = confidence
    }
}

// MARK: - Chip

/// The finite catalog of pre-armed questions shown in "Modo esencial" (Level 1, no Apple
/// Intelligence). Each chip maps to a deterministic filter over the facts; nothing is generated.
public enum CoachChip: String, CaseIterable, Sendable {
    case today          // ¿Qué me conviene hoy?
    case recovery       // ¿Cómo viene mi recuperación?
    case sleep          // ¿Qué me está afectando el sueño?
    case whatWorks      // ¿Qué funciona en mí?

    /// The es-MX question text shown on the chip.
    public var question: String {
        switch self {
        case .today:     return "¿Qué me conviene hoy?"
        case .recovery:  return "¿Cómo viene mi recuperación?"
        case .sleep:     return "¿Qué me está afectando el sueño?"
        case .whatWorks: return "¿Qué funciona en mí?"
        }
    }
}

// MARK: - Grounding

/// The compact, token-bounded fact summary the coach is grounded on.
public struct CoachGrounding: Equatable, Sendable {
    /// Reference day (local day key, e.g. "2026-06-19").
    public let asOf: String
    /// One-line readiness read (es-MX), if available — the headline context for "hoy".
    public let readinessSummary: String?
    /// Readiness level label (es-MX short), if available.
    public let readinessLevel: String?
    /// Today's recovery %, if available (rounded).
    public let recovery: Int?
    /// The ranked facts, capped at `maxFacts`.
    public let facts: [GroundingFact]
    /// Every numeric token the coach is allowed to state, normalized. Anything else in a reply is
    /// a fabricated figure (see `validate`). Derived from the facts + readiness + recovery.
    public let allowedNumbers: Set<String>

    /// Hard cap on facts so the summary always fits the on-device 4096-token window.
    public static let maxFacts = 12

    public init(asOf: String, readinessSummary: String?, readinessLevel: String?,
                recovery: Int?, facts: [GroundingFact], allowedNumbers: Set<String>) {
        self.asOf = asOf
        self.readinessSummary = readinessSummary
        self.readinessLevel = readinessLevel
        self.recovery = recovery
        self.facts = facts
        self.allowedNumbers = allowedNumbers
    }

    // MARK: Builder

    /// Build the grounding from the engine's ranked insights (highest `relevance` first) plus the
    /// readiness read. Deterministic: same inputs → same grounding. Caps facts at `maxFacts`.
    public static func from(insights: [Insight],
                            readiness: ReadinessEngine.Readiness?,
                            recovery: Double?,
                            referenceDay: String) -> CoachGrounding {
        let ranked = insights.sorted { $0.relevance > $1.relevance }
        let top = Array(ranked.prefix(maxFacts))

        let facts: [GroundingFact] = top.enumerated().map { idx, ins in
            GroundingFact(id: idx,
                          kind: ins.kind,
                          statement: ins.reading,
                          figure: ins.datum.value,
                          unit: ins.datum.unit,
                          metric: ins.datum.metric,
                          n: ins.evidence.n,
                          significant: ins.evidence.significant,
                          confidence: ins.confidence)
        }

        let rec = recovery.map { Int($0.rounded()) }

        // The allowed-number set: every figure the engine actually stated. We harvest numbers from
        // (a) each datum value (in its rounded + one-decimal forms), (b) the recovery %, and
        // (c) the free numeric tokens that already appear in the engine's es-MX statements/summary —
        // those are engine-produced too. The model may restate any of these; nothing else.
        var allowed = Set<String>()
        for f in facts {
            allowed.formUnion(numberForms(f.figure))
            allowed.formUnion(extractNumbers(from: f.statement))
        }
        if let rec { allowed.insert(normalize("\(rec)")) }
        if let s = readiness?.summary { allowed.formUnion(extractNumbers(from: s)) }

        return CoachGrounding(asOf: referenceDay,
                              readinessSummary: readiness?.summary,
                              readinessLevel: readiness?.level.rawValue,
                              recovery: rec,
                              facts: facts,
                              allowedNumbers: allowed)
    }

    // MARK: Tool context (Level 2 grounding payload)

    /// The compact text the on-device `Tool` returns to the model. Plain, deterministic, bounded —
    /// `[id] statement` lines plus the readiness header. No raw series.
    public func toolContextString() -> String {
        var lines: [String] = ["HECHOS DEL MOTOR (día \(asOf)). Usa SOLO estas cifras; no inventes números."]
        if let rec = recovery {
            lines.append("Recuperación hoy: \(rec)%.")
        }
        if let s = readinessSummary {
            lines.append("Estado: \(s)")
        }
        if facts.isEmpty {
            lines.append("(Aún no hay hallazgos: faltan noches para calibrar.)")
        } else {
            for f in facts {
                lines.append("[\(f.id)] \(f.statement)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Level 1 — deterministic answer

    /// The Level-1 answer for a pre-armed chip: built ONLY by concatenating the engine's own
    /// readings/summary. No generation — by construction it can never contain a figure the engine
    /// didn't produce. This is what "Modo esencial" shows when Apple Intelligence is unavailable.
    public func deterministicAnswer(forChip chip: CoachChip) -> String {
        switch chip {
        case .today:
            var parts: [String] = []
            if let rec = recovery { parts.append("Tu recuperación hoy es \(rec)%.") }
            if let s = readinessSummary { parts.append(s) }
            let extra = facts.first { $0.kind == .forecast || $0.kind == .trend || $0.kind == .nightAnomaly }
            if let extra { parts.append(extra.statement) }
            return joined(parts, fallback: "Aún no hay datos suficientes para una lectura de hoy. Sincroniza tu strap y vuelve en unos días.")
        case .recovery:
            var parts: [String] = []
            if let rec = recovery { parts.append("Recuperación hoy: \(rec)%.") }
            if let lvl = readinessLevel { parts.append("Estado: \(lvl).") }
            if let s = readinessSummary { parts.append(s) }
            parts.append(contentsOf: facts.filter { $0.metric.localizedCaseInsensitiveContains("recuper") }.map(\.statement))
            return joined(parts, fallback: "Todavía no tengo una lectura de recuperación. Faltan noches para calibrar.")
        case .sleep:
            let sleepFacts = facts.filter { $0.kind == .sleepRegularity || $0.kind == .sleepDebt
                || $0.metric.localizedCaseInsensitiveContains("sueño") }
            return joined(sleepFacts.map(\.statement),
                          fallback: "Sin hallazgos de sueño por ahora. Cuando haya más noches registradas, aparecerán aquí.")
        case .whatWorks:
            let levers = facts.filter { $0.kind == .behavior }.prefix(3)
            return joined(levers.map(\.statement),
                          fallback: "Aún no encuentro un hábito con efecto claro en tus números. Sigue registrando tu día y lo detectaré.")
        }
    }

    private func joined(_ parts: [String], fallback: String) -> String {
        let clean = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return clean.isEmpty ? fallback : clean.joined(separator: " ")
    }

    // MARK: Golden-rule guard

    /// Return the numeric tokens in `answer` that the engine did NOT produce — i.e. fabricated
    /// figures. Empty means the reply only restates engine numbers (passes the golden rule). A
    /// non-empty result means the caller must discard the model's reply and fall back to Level 1.
    ///
    /// Structural small integers (0, 1, 2) are tolerated — they appear as list counts / "una hora"
    /// without being a claimed metric — as is any percentage/figure already in `allowedNumbers`.
    public func validate(answer: String) -> [String] {
        let structural: Set<String> = ["0", "1", "2"]
        return CoachGrounding.extractNumbers(from: answer)
            .filter { !allowedNumbers.contains($0) && !structural.contains($0) }
    }

    // MARK: - Number helpers (pure, deterministic)

    /// Canonical string forms a datum value may legitimately appear as: its rounded integer and its
    /// one-decimal form (e.g. 7.0 → {"7"}, 6.5 → {"6.5", "7"}).
    static func numberForms(_ v: Double) -> Set<String> {
        var s = Set<String>()
        s.insert(normalize(String(Int(v.rounded()))))
        s.insert(normalize(String(format: "%.1f", v)))
        return s
    }

    /// Extract every numeric token from text, normalized. Matches integers and decimals with either
    /// "." or "," as the decimal mark.
    static func extractNumbers(from text: String) -> Set<String> {
        var out = Set<String>()
        var current = ""
        func flush() {
            guard !current.isEmpty else { return }
            out.insert(normalize(current))
            current = ""
        }
        for ch in text {
            if ch.isNumber {
                current.append(ch)
            } else if (ch == "." || ch == ",") && !current.isEmpty {
                current.append(ch)
            } else {
                // Trim a trailing separator that wasn't followed by a digit ("3." → "3").
                while let last = current.last, last == "." || last == "," { current.removeLast() }
                flush()
            }
        }
        while let last = current.last, last == "." || last == "," { current.removeLast() }
        flush()
        return out
    }

    /// Normalize a numeric token for comparison: unify the decimal mark to ".", drop a trailing
    /// ".0" so 7 and 7.0 compare equal.
    static func normalize(_ token: String) -> String {
        var t = token.replacingOccurrences(of: ",", with: ".")
        if t.hasSuffix(".0") { t.removeLast(2) }
        return t
    }
}
