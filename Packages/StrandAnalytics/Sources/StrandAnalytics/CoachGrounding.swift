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

/// The with/without group means behind a behavior fact — the raw material for a grounded what-if
/// ("on days WITH X, your recovery was A vs B"). Mirrors `BehaviorBreakdown` (FER-333).
public struct GroundingBreakdown: Equatable, Sendable {
    public let meanWith: Double
    public let meanWithout: Double
    public let nWith: Int
    public let nWithout: Int

    public init(meanWith: Double, meanWithout: Double, nWith: Int, nWithout: Int) {
        self.meanWith = meanWith
        self.meanWithout = meanWithout
        self.nWith = nWith
        self.nWithout = nWithout
    }
}

/// A grounded "what-if" answer: the historical contrast for a logged behavior, from the user's OWN
/// data — the differentiator only on-device history makes possible (FER-333). Carries what the
/// experiment handoff (FER-307) needs to start a 7-day test of the same lever.
public struct WhatIfResult: Equatable, Sendable {
    public let behavior: String
    public let outcome: String
    /// The es-MX contrast + recommendation, built only from engine figures (incl. a low-n caveat).
    public let statement: String
    /// Total days behind the contrast (nWith + nWithout).
    public let n: Int
    /// +1 if keeping the behavior is associated with a better outcome, -1 if worse — for the experiment.
    public let expectedSign: Int

    public init(behavior: String, outcome: String, statement: String, n: Int, expectedSign: Int) {
        self.behavior = behavior
        self.outcome = outcome
        self.statement = statement
        self.n = n
        self.expectedSign = expectedSign
    }
}

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
    /// For `.behavior` facts: the logged behavior name (the lever) and its outcome metric, plus the
    /// with/without breakdown — what a grounded what-if + experiment handoff need. nil otherwise.
    public let behavior: String?
    public let outcome: String?
    public let breakdown: GroundingBreakdown?

    public init(id: Int, kind: InsightKind, statement: String, figure: Double, unit: String,
                metric: String, n: Int, significant: Bool, confidence: InsightConfidence,
                behavior: String? = nil, outcome: String? = nil, breakdown: GroundingBreakdown? = nil) {
        self.id = id
        self.kind = kind
        self.statement = statement
        self.figure = figure
        self.unit = unit
        self.metric = metric
        self.n = n
        self.significant = significant
        self.confidence = confidence
        self.behavior = behavior
        self.outcome = outcome
        self.breakdown = breakdown
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
        case .today:     return String(localized: "What's good for me today?", bundle: .main)
        case .recovery:  return String(localized: "How's my recovery coming along?", bundle: .main)
        case .sleep:     return String(localized: "What's affecting my sleep?", bundle: .main)
        case .whatWorks: return String(localized: "What works for me?", bundle: .main)
        }
    }

    /// The subject a chip is about, so chip answers route through the same topic logic as free text.
    var topic: CoachTopic {
        switch self {
        case .today:     return .general
        case .recovery:  return .recovery
        case .sleep:     return .sleep
        case .whatWorks: return .behavior
        }
    }
}

// MARK: - Topic

/// What a question is about. Free text is classified into one of these so the engine retrieves the
/// RIGHT facts (a sleep question shouldn't be answered with recovery). es-MX keyword classifier.
public enum CoachTopic: String, CaseIterable, Sendable {
    case sleep
    case recovery
    case hrv
    case load
    case behavior
    case general

    /// Keyword STEMS, checked most-specific first. A stem matches when some WORD in the question starts
    /// with it — word-aware (not raw substring), so "encargas" doesn't match "carga" and "recámara"
    /// doesn't match "cama". Stems cover common es-MX conjugations ("dorm"+"duerm", "recuper", …).
    private static let keywords: [(CoachTopic, [String])] = [
        (.sleep,    ["dorm", "duerm", "sueno", "siesta", "acuest", "acost", "descans", "cama",
                     "despiert", "trasnoch", "desvel", "insomn"]),
        (.hrv,      ["hrv", "variabilidad"]),
        (.load,     ["carga", "sobrecarga", "sobreentren", "acwr", "monoton", "esfuerzo", "volumen"]),
        (.behavior, ["funciona", "habito", "alcohol", "cafe", "cafein", "afecta", "ayuda", "cuesta"]),
        (.recovery, ["recuper", "listo", "entren", "empuj", "descanso", "readiness",
                     "cansad", "amanec", "energia", "agotad", "fatig"]),
    ]

    /// Classify a free-text question into a topic. Word-aware (prefix match per word). Falls back to
    /// `.general`.
    public static func classify(_ question: String) -> CoachTopic {
        let words = CoachGrounding.words(question)
        for (topic, keys) in keywords
        where keys.contains(where: { key in words.contains { $0.hasPrefix(key) } }) {
            return topic
        }
        return .general
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
                          confidence: ins.confidence,
                          behavior: ins.lever?.behavior,
                          outcome: ins.lever?.outcome,
                          breakdown: ins.behaviorBreakdown.map {
                              GroundingBreakdown(meanWith: $0.meanWith, meanWithout: $0.meanWithout,
                                                 nWith: $0.nWith, nWithout: $0.nWithout)
                          })
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
            if let br = f.breakdown {   // with/without means a what-if may cite
                allowed.formUnion(numberForms(br.meanWith))
                allowed.formUnion(numberForms(br.meanWithout))
            }
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

    // MARK: Full fact dump (compact text)

    /// A compact, deterministic, bounded text dump of all facts — `[id] statement` lines plus the
    /// readiness header, no raw series. (FER-332 inverts the hierarchy so the model rewrites a
    /// per-topic deterministic answer rather than free-forming over this; kept as the canonical
    /// text view of the grounding.)
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

    /// The facts relevant to a topic — so a sleep question is answered with sleep facts, not recovery.
    public func facts(for topic: CoachTopic) -> [GroundingFact] {
        switch topic {
        case .sleep:
            return facts.filter { $0.kind == .sleepRegularity || $0.kind == .sleepDebt
                || $0.metric.localizedCaseInsensitiveContains("sueño") }
        case .recovery:
            return facts.filter { $0.metric.localizedCaseInsensitiveContains("recuper")
                || $0.kind == .nightAnomaly || $0.kind == .forecast || $0.kind == .trend }
        case .hrv:
            return facts.filter { $0.metric.localizedCaseInsensitiveContains("hrv") || $0.kind == .nightAnomaly }
        case .load:
            return facts.filter { $0.kind == .trainingLoad || $0.kind == .activityCost }
        case .behavior:
            return facts.filter { $0.kind == .behavior }
        case .general:
            return facts
        }
    }

    /// The deterministic, engine-only answer for a topic — the SOURCE of truth the model rewrites
    /// (FER-332). Built only from the engine's own readings/summary, so it can never contain a figure
    /// the engine didn't produce. This is also exactly what "Modo esencial" shows verbatim.
    public func deterministicAnswer(forTopic topic: CoachTopic) -> String {
        switch topic {
        case .general:
            var parts: [String] = []
            if let rec = recovery { parts.append(String(localized: "Your recovery today is \(rec)%.", bundle: .main)) }
            if let s = readinessSummary { parts.append(s) }
            if let extra = facts.first(where: { $0.kind == .forecast || $0.kind == .trend || $0.kind == .nightAnomaly }) {
                parts.append(extra.statement)
            }
            return joined(parts, fallback: String(localized: "There isn't enough data for a read today yet. Sync your strap and come back in a few days.", bundle: .main))
        case .recovery:
            var parts: [String] = []
            if let rec = recovery { parts.append(String(localized: "Recovery today: \(rec)%.", bundle: .main)) }
            if let lvl = readinessLevel { parts.append(String(localized: "Status: \(lvl).", bundle: .main)) }
            if let s = readinessSummary { parts.append(s) }
            parts.append(contentsOf: facts(for: .recovery).map(\.statement))
            return joined(parts, fallback: String(localized: "I don't have a recovery read yet. A few more nights are needed to calibrate.", bundle: .main))
        case .sleep:
            return joined(facts(for: .sleep).map(\.statement),
                          fallback: String(localized: "No sleep findings yet. They'll appear here once more nights are recorded.", bundle: .main))
        case .hrv:
            return joined(facts(for: .hrv).map(\.statement),
                          fallback: String(localized: "I don't have a clear read on your HRV yet. A few more nights are needed to calibrate.", bundle: .main))
        case .load:
            return joined(facts(for: .load).map(\.statement),
                          fallback: String(localized: "No training-load signals yet.", bundle: .main))
        case .behavior:
            return joined(facts(for: .behavior).prefix(3).map(\.statement),
                          fallback: String(localized: "I haven't found a habit with a clear effect on your numbers yet. Keep logging your day and I'll spot it.", bundle: .main))
        }
    }

    /// Convenience: the deterministic answer for a pre-armed chip, via its topic.
    public func deterministicAnswer(forChip chip: CoachChip) -> String {
        deterministicAnswer(forTopic: chip.topic)
    }

    // MARK: Seeded conversation (FER-331 — kill the blank box)

    /// The coach's opening line: the single most-relevant fact framed as an invitation. When there
    /// are no facts yet, it falls back to the readiness read, then to a cold-start nudge. This is what
    /// the coach "says first" so the user never faces an empty box.
    public func opener() -> String {
        if let top = facts.first {
            return String(localized: "What stands out most today: \(top.statement) Want to look at what to do?", bundle: .main)
        }
        if let s = readinessSummary {
            return String(localized: "\(s) How can I help today?", bundle: .main)
        }
        return String(localized: "I'm still gathering signal from your nights. Ask me anything, or sync your strap for more precise reads.", bundle: .main)
    }

    /// Up to three pre-armed questions to suggest, ordered by what stands out today (the standout
    /// fact's topic leads), padded with sensible defaults. Dynamic: a sleep-led day suggests the sleep
    /// question first. Returned as `CoachChip` so both tiers can answer them (templates or model).
    public func suggestedChips() -> [CoachChip] {
        var ordered: [CoachChip] = []
        func add(_ c: CoachChip) { if !ordered.contains(c) { ordered.append(c) } }

        if let top = facts.first {
            switch top.kind {
            case .sleepRegularity, .sleepDebt: add(.sleep)
            case .behavior:                    add(.whatWorks)
            default:                           add(.recovery)
            }
        }
        if facts.contains(where: { $0.kind == .sleepRegularity || $0.kind == .sleepDebt }) { add(.sleep) }
        if facts.contains(where: { $0.kind == .behavior }) { add(.whatWorks) }
        add(.today); add(.recovery); add(.whatWorks); add(.sleep)   // defaults pad to 3
        return Array(ordered.prefix(3))
    }

    /// Two follow-up questions to offer after answering `asked` — the most relevant remaining chips,
    /// never repeating what was just asked.
    public func followUpChips(after asked: CoachChip) -> [CoachChip] {
        let prioritized = suggestedChips() + CoachChip.allCases
        var out: [CoachChip] = []
        for c in prioritized where c != asked && !out.contains(c) {
            out.append(c)
            if out.count == 2 { break }
        }
        return out
    }

    // MARK: What-if (FER-333 — grounded counterfactual from the user's own history)

    /// Markers that a question is a counterfactual ("¿y si…?", "¿qué pasa si…?", "¿valdría la pena…?").
    private static let whatIfMarkers = ["y si", "que pasa si", "si dejo", "si quito", "si dejara",
                                        "si hiciera", "valdria la pena", "deberia dejar", "deberia quitar",
                                        "que tal si", "si tomo", "si no tomo"]

    /// If `question` is a what-if about a logged behavior we have a with/without breakdown for, return
    /// the historical contrast from the user's own data, plus what's needed to turn it into a 7-day
    /// experiment. Returns nil when it isn't a what-if, or no behavior with data matches (honest: the
    /// caller then answers normally, never inventing a contrast).
    public func whatIf(_ question: String) -> WhatIfResult? {
        let qWords = CoachGrounding.words(question)
        guard CoachGrounding.whatIfMarkers.contains(where: { CoachGrounding.containsPhrase(qWords, $0) })
        else { return nil }

        // Find the highest-ranked behavior fact whose behavior name (a 4+ char word) is in the question.
        let qSet = Set(qWords)
        let candidate = facts.first { fact in
            guard fact.kind == .behavior, fact.breakdown != nil, let b = fact.behavior else { return false }
            let tokens = CoachGrounding.words(b).filter { $0.count >= 4 }
            return tokens.contains { qSet.contains($0) }
        }
        guard let f = candidate, let br = f.breakdown, let behavior = f.behavior, let outcome = f.outcome
        else { return nil }
        // Both groups must actually have days, or the contrast is meaningless ("… contra 0 sin").
        guard br.nWith > 0, br.nWithout > 0 else { return nil }

        let withV = Int(br.meanWith.rounded())
        let withoutV = Int(br.meanWithout.rounded())
        let n = br.nWith + br.nWithout
        let diff = br.meanWith - br.meanWithout
        // Orient toward "better" by the outcome's direction: for a lower-is-better metric (resting HR) a
        // positive raw delta is actually WORSE, so the verdict word must flip. `expectedSign` stays the
        // RAW-delta direction — it only drives the experiment's reproduction check (ExperimentVerdict),
        // which tests that the same association recurs, not whether it's good.
        let higherIsBetter = InsightEngine.Outcome.higherIsBetter(outcomeLabel: outcome)
        let improvement = higherIsBetter ? diff : -diff
        let verdict: String
        if abs(diff) < 1 {                       // no meaningful difference either way
            verdict = String(localized: "I don't see a clear difference yet.", bundle: .main)
        } else if improvement > 0 {
            verdict = String(localized: "Keeping it seems to help you.", bundle: .main)
        } else {
            verdict = String(localized: "Dropping it could help you.", bundle: .main)
        }
        let sign: Int = abs(diff) < 1 ? 1 : (diff > 0 ? 1 : -1)
        var statement = String(localized: "On your days with \(behavior.lowercased()), your \(outcome.lowercased()) averaged \(withV) — versus \(withoutV) without.", bundle: .main)
            + " " + verdict
        if let caveat = CoachGrounding.confidenceCaveat(n: n) { statement += " " + caveat }

        return WhatIfResult(behavior: behavior, outcome: outcome, statement: statement,
                            n: n, expectedSign: sign)
    }

    /// A hedge to append when the sample is thin — honesty as the brand (FER-333). nil when n is solid.
    static func confidenceCaveat(n: Int) -> String? {
        if n < 10 { return String(localized: "With just \(n) days, take it as a hint, not certainty.", bundle: .main) }
        if n < 20 { return String(localized: "With \(n) days it's a reasonable signal, not yet definitive.", bundle: .main) }
        return nil
    }

    private func joined(_ parts: [String], fallback: String) -> String {
        let clean = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return clean.isEmpty ? fallback : clean.joined(separator: " ")
    }

    // MARK: Golden-rule guard

    /// Return the numeric tokens in `answer` that the model fabricated as one of the USER's own
    /// metrics — i.e. a number stated with a user-metric unit (`%`, `ms`, `bpm`, `rpm`, `pts`) that
    /// the engine never produced. Empty means the reply didn't misquote the user's data (passes the
    /// golden rule).
    ///
    /// Deliberately scoped (FER-330): the rule protects against the trust-killer — the model telling
    /// you a WRONG value for your own metric ("tu recuperación es 91%" when it's 56%). It does NOT
    /// flag free numbers in normal coaching ("duerme 7–9 horas", "zona 2", "80/20"); those carry no
    /// user-metric unit and are legitimate advice, not a claim about your data.
    public func validate(answer: String) -> [String] {
        CoachGrounding.metricNumbers(in: answer)
            .subtracting(allowedNumbers)
            .sorted()
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

    /// Units that mark a number as one of the USER's metrics (vs. free advice). A number immediately
    /// followed (optionally after one space) by one of these is a claim about the user's data.
    static let metricUnits = ["%", "ms", "bpm", "rpm", "lpm", "pts"]

    /// Numbers in `text` that are stated as a user metric — i.e. trailed by a `metricUnits` unit —
    /// normalized. "tu recuperación es 91%" → {"91"}; "duerme 7 a 9 horas" → {} (no metric unit).
    static func metricNumbers(in text: String) -> Set<String> {
        let chars = Array(text)
        var out = Set<String>()
        var i = 0
        while i < chars.count {
            guard chars[i].isNumber else { i += 1; continue }
            var num = ""
            var j = i
            while j < chars.count,
                  chars[j].isNumber || ((chars[j] == "." || chars[j] == ",")
                                        && j + 1 < chars.count && chars[j + 1].isNumber) {
                num.append(chars[j]); j += 1
            }
            // Skip any spaces, then read the trailing unit token (letters or %). Skipping ALL spaces
            // closes the "100  %" double-space evasion of the golden rule.
            var k = j
            while k < chars.count && chars[k] == " " { k += 1 }
            var unit = ""
            while k < chars.count && (chars[k].isLetter || chars[k] == "%") { unit.append(chars[k]); k += 1 }
            let u = unit.lowercased()
            if metricUnits.contains(where: { u == $0 }) {
                out.insert(normalize(num))
            }
            i = j
        }
        return out
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

    /// Fold text for keyword matching: lowercased and accent-insensitive ("Sueño" → "sueno").
    static func foldForMatch(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
    }

    /// The folded words of a string (split on anything that isn't a letter/number) — the unit of
    /// word-aware matching, so a stem matches a whole word's start, not a mid-word substring.
    static func words(_ s: String) -> [Substring] {
        foldForMatch(s).split { !$0.isLetter && !$0.isNumber }
    }

    /// True if `folded`'s word sequence contains `phrase` (1+ words) as consecutive whole words — so
    /// "y si" matches "¿y si duermo?" but NOT "hoy sí" or "y siento".
    static func containsPhrase(_ folded: [Substring], _ phrase: String) -> Bool {
        let p = phrase.split(separator: " ").map(String.init)
        guard !p.isEmpty, folded.count >= p.count else { return false }
        for start in 0...(folded.count - p.count) {
            if (0..<p.count).allSatisfy({ folded[start + $0] == p[$0][...] }) { return true }
        }
        return false
    }

    /// Normalize a numeric token for comparison: unify the decimal mark to ".", drop a trailing
    /// ".0" so 7 and 7.0 compare equal.
    static func normalize(_ token: String) -> String {
        var t = token.replacingOccurrences(of: ",", with: ".")
        if t.hasSuffix(".0") { t.removeLast(2) }
        return t
    }
}
