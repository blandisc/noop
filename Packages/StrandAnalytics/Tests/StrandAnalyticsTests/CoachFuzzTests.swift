import XCTest
@testable import StrandAnalytics

/// FER-336 — property-based + fuzz tests for the pure coach logic. Thousands of random questions and
/// groundings are thrown at `CoachGrounding`; each loop asserts an INVARIANT that must hold for ANY
/// input. Reproducible: a seeded PRNG, no `Date`/system randomness. If one fails, the seed + index
/// pinpoint the offending case.
final class CoachFuzzTests: XCTestCase {

    // MARK: Seeded PRNG (SplitMix64 — deterministic, reproducible)

    private struct LCG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    // MARK: Word banks for synthetic questions

    private static let tokens: [String] = [
        // sleep
        "dormir", "duermo", "dormí", "sueño", "siesta", "acostarme", "descansar", "cama", "recámara",
        // recovery / energy
        "recuperación", "recupero", "listo", "entreno", "entrenar", "cansado", "amanecí", "energía",
        "agotado", "fatiga", "descanso",
        // hrv / load
        "hrv", "variabilidad", "carga", "encargas", "descarga", "esfuerzo", "volumen", "monotonía",
        // behavior
        "alcohol", "café", "cafeína", "azúcar", "meditar", "meditación", "pantalla", "estrés",
        "funciona", "afecta", "ayuda", "cuesta",
        // what-if markers & connectors
        "y", "si", "qué", "pasa", "dejo", "quito", "tomo", "valdría", "la", "pena", "debería",
        "hoy", "más", "menos", "por", "que", "cómo", "cuánto", "mi", "el", "tu",
        // numbers & units (adversarial)
        "100%", "90 %", "11.4", "7", "8h", "65 ms", "63", "noventa", "0", "-5",
        // garbage / unicode / symbols
        "🤔", "😴", "💤", "!!!", "???", "...", "@#$", "ñ", "  ", "\n", "a\u{0301}",
    ]

    private func randomQuestion(_ rng: inout LCG) -> String {
        let n = Int.random(in: 0...7, using: &rng)
        var parts: [String] = []
        for _ in 0..<n { parts.append(Self.tokens.randomElement(using: &rng)!) }
        let q = parts.joined(separator: " ")
        // Sometimes wrap like a real question.
        switch Int.random(in: 0...3, using: &rng) {
        case 0: return "¿\(q)?"
        case 1: return q + "?"
        default: return q
        }
    }

    // MARK: Synthetic groundings

    private static let metrics = ["Recuperación", "HRV", "Sueño", "Carga", "Pulso"]
    private static let units = ["%", "ms", "bpm", "h", "pts", "min", ""]

    private func randomReading(_ rng: inout LCG) -> String {
        var s = ["tu", "número", "subió", "bajó", "anoche", "en", "tus", "noches"]
            .shuffled(using: &rng).prefix(Int.random(in: 1...4, using: &rng)).joined(separator: " ")
        // Add 0–2 positive number+unit tokens (real readings never show signed percentages).
        for _ in 0..<Int.random(in: 0...2, using: &rng) {
            let v = Double(Int.random(in: 0...120, using: &rng)) + (Bool.random(using: &rng) ? 0.5 : 0)
            let unit = Self.units.randomElement(using: &rng)!
            s += " \(CoachGrounding.normalize(String(format: "%.1f", v)))\(unit.isEmpty ? "" : " " + unit)"
        }
        return s + "."
    }

    private func randomInsight(_ rng: inout LCG, id: Int) -> Insight {
        let kind = InsightKind.allCases.randomElement(using: &rng)!
        let metric = Self.metrics.randomElement(using: &rng)!
        let value = Double(Int.random(in: -20...120, using: &rng))
        let unit = Self.units.randomElement(using: &rng)!
        let n = Int.random(in: 0...60, using: &rng)
        var lever: Lever?
        var breakdown: BehaviorBreakdown?
        if kind == .behavior {
            let beh = ["Alcohol", "Cafeína", "Meditación", "Pantalla en cama", "Estrés", "Té"]
                .randomElement(using: &rng)!
            lever = Lever(behavior: beh, outcome: metric)
            // Random group sizes incl. zero on a side (must be handled, not crash).
            let nw = Int.random(in: 0...20, using: &rng)
            let nwo = Int.random(in: 0...20, using: &rng)
            // Realistic outcome means (recovery/HRV-ish); a side count may still be 0 (must be guarded).
            breakdown = BehaviorBreakdown(meanWith: Double(Int.random(in: 35...95, using: &rng)),
                                          meanWithout: Double(Int.random(in: 35...95, using: &rng)),
                                          nWith: nw, nWithout: nwo)
        }
        return Insight(kind: kind, title: "t", reading: randomReading(&rng),
                       datum: InsightDatum(value: value, unit: unit, metric: metric),
                       evidence: InsightEvidence(n: n, pValue: nil, pAdjusted: nil, effectSize: nil,
                                                 significant: Bool.random(using: &rng)),
                       confidence: [.candidate, .proven, .medium].randomElement(using: &rng)!,
                       relevance: Double.random(in: 0...10, using: &rng),
                       lever: lever, behaviorBreakdown: breakdown)
    }

    private func randomGrounding(_ rng: inout LCG) -> CoachGrounding {
        let count = Int.random(in: 0...16, using: &rng)
        let insights = (0..<count).map { randomInsight(&rng, id: $0) }
        let readiness: ReadinessEngine.Readiness? = Bool.random(using: &rng)
            ? ReadinessEngine.Readiness(level: [.primed, .balanced, .strained, .rundown, .insufficient]
                                            .randomElement(using: &rng)!,
                                        headline: "h", summary: randomReading(&rng),
                                        signals: [], acwr: nil, monotony: nil)
            : nil
        let recovery: Double? = Bool.random(using: &rng) ? Double(Int.random(in: 0...100, using: &rng)) : nil
        return CoachGrounding.from(insights: insights, readiness: readiness,
                                   recovery: recovery, referenceDay: "2026-06-19")
    }

    // MARK: - Invariants over random QUESTIONS

    func testFuzz_classifyIsTotalAndDeterministic() {
        var rng = LCG(seed: 0xC0FFEE)
        for i in 0..<4000 {
            let q = randomQuestion(&rng)
            let a = CoachTopic.classify(q)
            let b = CoachTopic.classify(q)
            XCTAssertEqual(a, b, "classify not deterministic at #\(i): \(q.debugDescription)")
        }
    }

    func testFuzz_validateNeverCrashesAndIsWellFormed() {
        var rng = LCG(seed: 0xBEEF)
        let g = CoachGrounding.from(insights: [], readiness: nil, recovery: 70, referenceDay: "d")
        for i in 0..<4000 {
            let s = randomQuestion(&rng) + " " + randomReading(&rng)
            let flagged = Set(g.validate(answer: s))
            let metric = CoachGrounding.metricNumbers(in: s)
            let all = CoachGrounding.extractNumbers(from: s)
            // validate ⊆ metricNumbers ⊆ extractNumbers, and validate is disjoint from allowedNumbers.
            XCTAssertTrue(flagged.isSubset(of: metric), "validate⊄metricNumbers #\(i): \(s.debugDescription)")
            XCTAssertTrue(metric.isSubset(of: all), "metricNumbers⊄extractNumbers #\(i): \(s.debugDescription)")
            XCTAssertTrue(flagged.isDisjoint(with: g.allowedNumbers), "flagged an allowed number #\(i)")
        }
    }

    // MARK: - Invariants over random GROUNDINGS

    func testFuzz_groundingInvariants() {
        var rng = LCG(seed: 0x1234_5678)
        for i in 0..<2500 {
            let g = randomGrounding(&rng)

            // Opener + tool dump are always usable and never trip the golden rule.
            XCTAssertFalse(g.opener().isEmpty, "empty opener #\(i)")
            XCTAssertTrue(g.validate(answer: g.opener()).isEmpty, "opener tripped validate #\(i)")
            XCTAssertTrue(g.validate(answer: g.toolContextString()).isEmpty, "toolContext tripped validate #\(i)")

            // Suggested chips: exactly 3, unique.
            let chips = g.suggestedChips()
            XCTAssertEqual(chips.count, 3, "#\(i)")
            XCTAssertEqual(Set(chips).count, 3, "duplicate chips #\(i)")

            // Follow-ups: 2, unique, never repeat the asked chip.
            for asked in CoachChip.allCases {
                let ups = g.followUpChips(after: asked)
                XCTAssertEqual(ups.count, 2, "#\(i)")
                XCTAssertEqual(Set(ups).count, 2, "dup follow-ups #\(i)")
                XCTAssertFalse(ups.contains(asked), "follow-up repeats asked #\(i)")
            }

            // CRITICAL: the engine's OWN deterministic answer must never be flagged as fabricated,
            // for every topic — else the on-device path would discard a correct answer.
            for topic in CoachTopic.allCases {
                let base = g.deterministicAnswer(forTopic: topic)
                XCTAssertFalse(base.isEmpty, "empty base for \(topic) #\(i)")
                XCTAssertTrue(g.validate(answer: base).isEmpty,
                              "deterministic \(topic) tripped its own validate #\(i): \(base.debugDescription)")
            }
        }
    }

    func testFuzz_determinismOfFrom() {
        var rng = LCG(seed: 0xABCDEF)
        for _ in 0..<800 {
            // Rebuild the same grounding from the same insights twice → identical.
            let count = Int.random(in: 0...12, using: &rng)
            let insights = (0..<count).map { randomInsight(&rng, id: $0) }
            let rec = Double(Int.random(in: 0...100, using: &rng))
            let a = CoachGrounding.from(insights: insights, readiness: nil, recovery: rec, referenceDay: "d")
            let b = CoachGrounding.from(insights: insights, readiness: nil, recovery: rec, referenceDay: "d")
            XCTAssertEqual(a, b)
        }
    }

    // MARK: - Invariants over random GROUNDING × QUESTION

    func testFuzz_whatIfAlwaysWellFormed() {
        var rng = LCG(seed: 0x5EED)
        let behaviors = ["alcohol", "cafeína", "meditación", "pantalla", "estrés", "té"]
        for i in 0..<3000 {
            let g = randomGrounding(&rng)
            // Bias toward real what-if phrasings naming a behavior.
            let marker = ["y si dejo", "qué pasa si quito", "valdría la pena dejar", "y si tomo"]
                .randomElement(using: &rng)!
            let beh = behaviors.randomElement(using: &rng)!
            let q = Bool.random(using: &rng) ? "¿\(marker) el \(beh)?" : randomQuestion(&rng)

            guard let wi = g.whatIf(q) else { continue }
            XCTAssertGreaterThan(wi.n, 0, "whatIf n<=0 #\(i)")
            XCTAssertFalse(wi.behavior.isEmpty, "#\(i)")
            XCTAssertTrue(wi.expectedSign == 1 || wi.expectedSign == -1, "bad sign #\(i)")
            XCTAssertTrue(g.validate(answer: wi.statement).isEmpty,
                          "whatIf statement tripped validate #\(i): \(wi.statement.debugDescription)")
        }
    }

    func testFuzz_topicAnswerForClassifiedQuestion() {
        var rng = LCG(seed: 0x0DDBA11)
        for i in 0..<2500 {
            let g = randomGrounding(&rng)
            let q = randomQuestion(&rng)
            let topic = CoachTopic.classify(q)
            let ans = g.deterministicAnswer(forTopic: topic)
            XCTAssertFalse(ans.isEmpty, "empty answer #\(i): \(q.debugDescription)")
            XCTAssertTrue(g.validate(answer: ans).isEmpty, "answer tripped validate #\(i)")
        }
    }

    // MARK: - Number helpers properties

    func testFuzz_normalizeIdempotentAndExtractionStable() {
        var rng = LCG(seed: 0x99)
        for _ in 0..<2000 {
            let s = randomReading(&rng)
            let once = CoachGrounding.extractNumbers(from: s)
            for tok in once {
                XCTAssertEqual(CoachGrounding.normalize(tok), tok, "extractNumbers returned un-normalized \(tok)")
            }
        }
        XCTAssertEqual(CoachGrounding.normalize("7.0"), "7")
        XCTAssertEqual(CoachGrounding.normalize(CoachGrounding.normalize("6,50")), CoachGrounding.normalize("6,50"))
    }
}
