import Foundation
import WhoopStore

// InsightEngine.swift — the single, pure, deterministic source of on-device findings.
//
// The heart of the redesigned Coach ("el Bucle"). It receives data ALREADY READ from
// the store (it never touches the DB) and runs a catalog of detectors, each one a thin
// wrapper over an existing pure engine — it orchestrates, it does not re-implement math.
// Every number an `Insight` carries is computed here; the LLM step (issue E) only
// rewrites the es-MX templates, never produces a figure.
//
// Statistical hygiene is the whole point. The dashboard probes N behaviors × M outcomes
// plus a grid of metric correlations at once — dozens of simultaneous hypothesis tests.
// Left uncorrected, α = 0.05 manufactures false discoveries by the handful. So every
// inferential detector feeds ONE Benjamini-Hochberg family (`MultipleComparisons`): a
// finding is "significant" only when its FDR-adjusted q-value clears α AND it passes the
// per-side sample floor (`minGroup`, reused from `BehaviorInsights`) AND a minimum
// effect-size floor (so trivially-small-but-significant effects stay hidden). The
// synthetic test suite proves a planted effect is recovered and pure noise is not.
//
// Descriptive detectors (trend, forecast, night anomaly, sleep debt, regularity,
// activity cost, training load, fitness age) describe a real datum rather than test a
// hypothesis: they report `significant == false` and confidence `.medium`.

public enum InsightEngine {

    // MARK: - Tunables

    /// Family-wise significance threshold applied to FDR-adjusted q-values.
    public static let alpha = 0.05
    /// Minimum |Cohen's d| for a behavior effect to count (small-effect floor — below
    /// this an effect is statistically detectable but not worth surfacing).
    public static let minCohensD = 0.30
    /// Minimum |Pearson r| for a correlation to count.
    public static let minAbsR = 0.30
    /// Per-side minimum sample for an association (reuses BehaviorInsights' bar).
    public static var minGroup: Int { BehaviorInsights.minGroupForSignificance }
    /// Nightly sleep target (min) the sleep-debt detector measures deficits against.
    static let sleepTargetMin = 480.0
    /// Trailing nights the sleep-debt detector accumulates over.
    static let sleepDebtWindow = 7

    // MARK: - Inputs

    /// Optional inputs for the Fitness-Age detector. Omit to skip that detector.
    public struct FitnessInputs: Sendable, Equatable {
        public var age: Double
        public var sex: String
        public var paIndex: Double
        public var waistCm: Double?
        public init(age: Double, sex: String, paIndex: Double, waistCm: Double? = nil) {
            self.age = age; self.sex = sex; self.paIndex = paIndex; self.waistCm = waistCm
        }
    }

    /// Everything the detectors need, all already read from the store by the caller.
    /// Most fields default to empty so a caller (or a test) supplies only what it has.
    /// (Not `Sendable`: `DailyMetric` / `CachedSleepSession` from WhoopStore aren't, and
    /// the engine is a synchronous pure function — it never crosses an actor boundary.)
    public struct Inputs {
        /// Daily rows; any order (the engine sorts).
        public var days: [DailyMetric]
        /// Logged behavior → the set of "yyyy-MM-dd" days it was logged.
        public var behaviors: [String: Set<String>]
        /// Sport → the set of "yyyy-MM-dd" days it was performed.
        public var activityDaysBySport: [String: Set<String>]
        /// Cached sleep sessions for the regularity index.
        public var sleepSessions: [CachedSleepSession]
        /// The "today" day key for trend/load windows; defaults to the latest day.
        public var referenceDay: String?
        /// Optional fitness-age inputs.
        public var fitness: FitnessInputs?

        public init(days: [DailyMetric],
                    behaviors: [String: Set<String>] = [:],
                    activityDaysBySport: [String: Set<String>] = [:],
                    sleepSessions: [CachedSleepSession] = [],
                    referenceDay: String? = nil,
                    fitness: FitnessInputs? = nil) {
            self.days = days
            self.behaviors = behaviors
            self.activityDaysBySport = activityDaysBySport
            self.sleepSessions = sleepSessions
            self.referenceDay = referenceDay
            self.fitness = fitness
        }
    }

    // MARK: - Outcomes (the M metrics behaviors & correlations are tested against)

    /// A daily outcome metric: a label, unit, and how to read it off a DailyMetric.
    private struct Metric {
        let label: String
        let unit: String
        let value: (DailyMetric) -> Double?
    }

    private static let outcomes: [Metric] = [
        Metric(label: "Recuperación", unit: "pts", value: { $0.recovery }),
        Metric(label: "HRV", unit: "ms", value: { $0.avgHrv }),
        Metric(label: "Sueño", unit: "min", value: { $0.totalSleepMin }),
        Metric(label: "FC en reposo", unit: "lpm", value: { $0.restingHr.map(Double.init) }),
    ]

    // MARK: - Generate

    /// Run every detector and return findings ranked by relevance (significant
    /// associations first, then by effect size and recency). Deterministic: the same
    /// inputs always yield the same ordered list.
    public static func generate(_ inputs: Inputs) -> [Insight] {
        let days = inputs.days.sorted { $0.day < $1.day }
        let refDay = inputs.referenceDay ?? days.last?.day

        // Sleep debt is computed once: it's both its own insight and a forecast input.
        let debtMin = sleepDebtMinutes(days)

        var insights: [Insight] = []
        insights += associationInsights(days, behaviors: inputs.behaviors)  // FDR family (behaviors × M + correlations)
        insights += nightAnomalyInsights(days)
        insights += trendInsights(days, referenceDay: refDay)
        if let f = forecastInsight(days, sleepDebtMin: debtMin) { insights.append(f) }
        if let s = sleepRegularityInsight(inputs.sleepSessions) { insights.append(s) }
        if let d = sleepDebtInsight(debtMin: debtMin, nights: min(days.count, sleepDebtWindow)) { insights.append(d) }
        insights += activityCostInsights(days, activityDaysBySport: inputs.activityDaysBySport)
        if let l = trainingLoadInsight(days, today: refDay) { insights.append(l) }
        if let a = fitnessAgeInsight(days, fitness: inputs.fitness) { insights.append(a) }

        return insights.sorted { a, b in
            if a.relevance != b.relevance { return a.relevance > b.relevance }
            if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
            return a.title < b.title
        }
    }

    // MARK: - Association family (FDR-corrected): behaviors × outcomes + correlations

    /// A pending inferential finding, built lazily once its FDR-adjusted q is known.
    private struct Candidate {
        let pRaw: Double
        let effect: Double      // signed Cohen's d or Pearson r
        let effectRef: Double   // scale for the relevance effect term
        let passesFloors: Bool  // sample + effect-size floors (FDR is applied later)
        let build: (_ pAdj: Double, _ significant: Bool) -> Insight
    }

    private static func associationInsights(_ days: [DailyMetric],
                                            behaviors: [String: Set<String>]) -> [Insight] {
        var candidates: [Candidate] = []
        candidates += behaviorCandidates(days, behaviors: behaviors)
        candidates += correlationCandidates(days)
        guard !candidates.isEmpty else { return [] }

        // ONE Benjamini-Hochberg family over every association test run this pass.
        let qValues = MultipleComparisons.benjaminiHochberg(candidates.map(\.pRaw))

        var out: [Insight] = []
        for (cand, q) in zip(candidates, qValues) {
            let significant = cand.passesFloors && q < alpha
            out.append(cand.build(q, significant))
        }
        return out
    }

    private static func behaviorCandidates(_ days: [DailyMetric],
                                           behaviors: [String: Set<String>]) -> [Candidate] {
        guard !days.isEmpty, !behaviors.isEmpty else { return [] }
        var cands: [Candidate] = []
        for metric in outcomes {
            // outcomeByDay for this metric.
            var outcomeByDay: [String: Double] = [:]
            for d in days { if let v = metric.value(d) { outcomeByDay[d.day] = v } }
            guard outcomeByDay.count >= 2 * minGroup else { continue }

            for behavior in behaviors.keys.sorted() {
                let bdays = behaviors[behavior]!
                guard let e = BehaviorInsights.effect(behaviorDays: bdays,
                                                      outcomeByDay: outcomeByDay,
                                                      behavior: behavior,
                                                      outcome: metric.label) else { continue }
                let nMin = Swift.min(e.nWith, e.nWithout)
                let passes = nMin >= minGroup && abs(e.cohensD) >= minCohensD
                let n = e.nWith + e.nWithout
                cands.append(Candidate(pRaw: e.pApprox, effect: e.cohensD, effectRef: 0.8,
                                       passesFloors: passes) { q, sig in
                    behaviorInsight(e, metric: metric, qAdjusted: q, significant: sig, n: n)
                })
            }
        }
        return cands
    }

    private static func correlationCandidates(_ days: [DailyMetric]) -> [Candidate] {
        // A small, curated grid of meaningful pairs — not every metric × every metric
        // (that would inflate the family with physiologically meaningless tests).
        let pairs: [(x: Metric, y: Metric)] = [
            (outcomes[2], outcomes[0]),   // Sueño → Recuperación
            (outcomes[1], outcomes[0]),   // HRV → Recuperación
            (outcomes[3], outcomes[0]),   // FC en reposo → Recuperación
        ]
        var cands: [Candidate] = []
        for pair in pairs {
            let xs: [(day: String, value: Double)] = days.compactMap { d in
                pair.x.value(d).map { (d.day, $0) }
            }
            let ys: [(day: String, value: Double)] = days.compactMap { d in
                pair.y.value(d).map { (d.day, $0) }
            }
            let aligned = CorrelationEngine.alignByDay(xs, ys)
            guard let c = CorrelationEngine.pearson(aligned) else { continue }
            let passes = c.n >= 2 * minGroup && abs(c.r) >= minAbsR
            cands.append(Candidate(pRaw: c.pApprox, effect: c.r, effectRef: 1.0,
                                   passesFloors: passes) { q, sig in
                correlationInsight(c, x: pair.x, y: pair.y, qAdjusted: q, significant: sig)
            })
        }
        return cands
    }

    // MARK: - Insight builders for the association family

    private static func behaviorInsight(_ e: BehaviorEffect, metric: Metric,
                                        qAdjusted: Double, significant: Bool, n: Int) -> Insight {
        let dir = e.delta < 0 ? "baja" : "sube"
        let pct = e.pctChange.map { abs($0) } ?? 0
        let title = "‘\(e.behavior)’ y tu \(metric.label)"
        let reading = "En los días con ‘\(e.behavior)’, tu \(metric.label) \(dir) \(Int(pct.rounded()))% (n=\(e.nWith) vs \(e.nWithout))."
        let datum = InsightDatum(value: round1(e.delta), unit: metric.unit, metric: metric.label)
        let evidence = InsightEvidence(n: n, pValue: e.pApprox, pAdjusted: qAdjusted,
                                       effectSize: e.cohensD, significant: significant)
        return Insight(kind: .behavior, title: title, reading: reading, datum: datum,
                       evidence: evidence,
                       confidence: significant ? .candidate : .medium,
                       relevance: relevance(significant: significant, qAdjusted: qAdjusted,
                                            effectMag: abs(e.cohensD), effectRef: 0.8, recency: 0.5))
    }

    private static func correlationInsight(_ c: Correlation, x: Metric, y: Metric,
                                           qAdjusted: Double, significant: Bool) -> Insight {
        let rel = c.r < 0 ? "inversa" : "directa"
        let title = "\(x.label) y \(y.label) van juntos"
        let reading = "Relación \(rel) entre \(x.label) y \(y.label) (r=\(round2(c.r)), n=\(c.n))."
        let datum = InsightDatum(value: round2(c.r), unit: "r", metric: "\(x.label)·\(y.label)")
        let evidence = InsightEvidence(n: c.n, pValue: c.pApprox, pAdjusted: qAdjusted,
                                       effectSize: c.r, significant: significant)
        return Insight(kind: .correlation, title: title, reading: reading, datum: datum,
                       evidence: evidence,
                       confidence: significant ? .candidate : .medium,
                       relevance: relevance(significant: significant, qAdjusted: qAdjusted,
                                            effectMag: abs(c.r), effectRef: 1.0, recency: 0.5))
    }

    // MARK: - Night anomaly (Baselines z-score)

    private static func nightAnomalyInsights(_ days: [DailyMetric]) -> [Insight] {
        guard let latest = days.last else { return [] }
        let history = Array(days.dropLast())
        guard history.count >= Baselines.minNightsSeed else { return [] }

        struct Probe { let key: String; let label: String; let unit: String
                       let cfg: MetricCfg; let value: (DailyMetric) -> Double? }
        let probes: [Probe] = [
            Probe(key: "hrv", label: "HRV", unit: "ms", cfg: Baselines.hrvCfg, value: { $0.avgHrv }),
            Probe(key: "resting_hr", label: "FC en reposo", unit: "lpm",
                  cfg: Baselines.restingHRCfg, value: { $0.restingHr.map(Double.init) }),
            Probe(key: "resp", label: "Respiración", unit: "rpm",
                  cfg: Baselines.respCfg, value: { $0.respRateBpm }),
        ]

        var out: [Insight] = []
        for p in probes {
            guard let value = p.value(latest) else { continue }
            let state = Baselines.foldHistory(history.map { p.value($0) }, cfg: p.cfg)
            guard state.usable else { continue }
            let dev = Baselines.deviation(value, state: state)
            guard abs(dev.z) >= 2.0 else { continue }   // anomaly only
            let dir = dev.z < 0 ? "por debajo" : "por encima"
            let title = "\(p.label) fuera de lo normal anoche"
            let reading = "Anoche tu \(p.label) estuvo \(dir) de tu base (z=\(round1(dev.z)), base \(Int(state.baseline.rounded()))\(p.unit))."
            let datum = InsightDatum(value: round1(value), unit: p.unit, metric: p.label)
            let evidence = InsightEvidence(n: state.nValid, pValue: nil, pAdjusted: nil,
                                           effectSize: dev.z, significant: false)
            out.append(Insight(kind: .nightAnomaly, title: title, reading: reading, datum: datum,
                               evidence: evidence, confidence: .medium,
                               relevance: relevance(significant: false, qAdjusted: nil,
                                                    effectMag: abs(dev.z), effectRef: 4.0, recency: 1.0)))
        }
        return out
    }

    // MARK: - Trend (ComparisonEngine, 7 and 30 day)

    private static func trendInsights(_ days: [DailyMetric], referenceDay: String?) -> [Insight] {
        guard let ref = referenceDay else { return [] }
        let recovery: [(day: String, value: Double)] = days.compactMap { d in
            d.recovery.map { (d.day, $0) }
        }
        guard !recovery.isEmpty else { return [] }

        var out: [Insight] = []
        for window in [7, 30] {
            let cmp = ComparisonEngine.periodOverPeriod(byDay: recovery, windowDays: window, referenceDay: ref)
            guard cmp.current.n >= max(3, window / 2), cmp.previous.n >= max(3, window / 2) else { continue }
            let pct = cmp.pctChange ?? 0
            guard abs(pct) >= 5 else { continue }   // ignore trivial drift
            let dir = cmp.direction < 0 ? "bajando" : "subiendo"
            let title = "Tu Recuperación viene \(dir) (\(window) días)"
            let reading = "Los últimos \(window) días tu Recuperación promedió \(Int(cmp.current.mean.rounded())) vs \(Int(cmp.previous.mean.rounded())) antes (\(Int(pct.rounded()))%)."
            let datum = InsightDatum(value: round1(cmp.delta), unit: "pts", metric: "Recuperación")
            let evidence = InsightEvidence(n: cmp.current.n + cmp.previous.n, pValue: nil,
                                           pAdjusted: nil, effectSize: nil, significant: false)
            out.append(Insight(kind: .trend, title: title, reading: reading, datum: datum,
                               evidence: evidence, confidence: .medium,
                               relevance: relevance(significant: false, qAdjusted: nil,
                                                    effectMag: abs(pct), effectRef: 25.0,
                                                    recency: window == 7 ? 1.0 : 0.8)))
        }
        return out
    }

    // MARK: - Forecast (RecoveryForecast)

    private static func forecastInsight(_ days: [DailyMetric], sleepDebtMin: Double) -> Insight? {
        let recovery = days.map { $0.recovery }
        guard let r = RecoveryForecast.compute(recovery: recovery, sleepDebtMin: sleepDebtMin) else { return nil }
        let word: String
        let step: Double   // signed direction for the test to read off evidence.effectSize
        switch r.direction {
        case .rising:  word = "al alza"; step = 1
        case .falling: word = "a la baja"; step = -1
        case .steady:  word = "estable"; step = 0
        }
        let title = "Mañana tu Recuperación pinta \(word)"
        let reading = "Proyección para mañana: \(Int(r.estimate.rounded())) (rango \(Int(r.low.rounded()))–\(Int(r.high.rounded())), \(r.basisDays) días)."
        let datum = InsightDatum(value: round1(r.estimate), unit: "pts", metric: "Recuperación")
        let evidence = InsightEvidence(n: r.basisDays, pValue: nil, pAdjusted: nil,
                                       effectSize: step, significant: false)
        return Insight(kind: .forecast, title: title, reading: reading, datum: datum,
                       evidence: evidence, confidence: .medium,
                       relevance: relevance(significant: false, qAdjusted: nil,
                                            effectMag: abs(r.estimate - 50), effectRef: 50.0, recency: 1.0))
    }

    // MARK: - Sleep regularity (SleepRegularityIndex)

    private static func sleepRegularityInsight(_ sessions: [CachedSleepSession]) -> Insight? {
        guard let sri = SleepRegularityIndex.fromSessions(sessions) else { return nil }
        guard sri < 80 else { return nil }   // surface only when timing is irregular
        let title = "Tus horarios de sueño van irregulares"
        let reading = "Tu regularidad de sueño está en \(Int(sri.rounded()))/100; dormir y despertar a horas más parejas ayuda."
        let datum = InsightDatum(value: round1(sri), unit: "/100", metric: "Regularidad de sueño")
        let evidence = InsightEvidence(n: sessions.count, pValue: nil, pAdjusted: nil,
                                       effectSize: nil, significant: false)
        return Insight(kind: .sleepRegularity, title: title, reading: reading, datum: datum,
                       evidence: evidence, confidence: .medium,
                       relevance: relevance(significant: false, qAdjusted: nil,
                                            effectMag: 80 - sri, effectRef: 40.0, recency: 0.9))
    }

    // MARK: - Sleep debt (DailyMetric)

    /// Accumulated deficit (min) over the trailing window vs `sleepTargetMin`.
    /// Pure aggregation over DailyMetric — no engine, no new model.
    static func sleepDebtMinutes(_ days: [DailyMetric]) -> Double {
        let recent = days.suffix(sleepDebtWindow).compactMap { $0.totalSleepMin }
        return recent.reduce(0.0) { $0 + max(0.0, sleepTargetMin - $1) }
    }

    private static func sleepDebtInsight(debtMin: Double, nights: Int) -> Insight? {
        guard debtMin >= 60, nights >= 3 else { return nil }   // < 1h debt isn't worth a card
        let hours = debtMin / 60.0
        let title = "Llevas deuda de sueño"
        let reading = "En las últimas noches acumulas \(round1(hours)) h por debajo de tu meta; la deuda no se salda de un jalón."
        let datum = InsightDatum(value: round1(hours), unit: "h", metric: "Deuda de sueño")
        let evidence = InsightEvidence(n: nights, pValue: nil, pAdjusted: nil,
                                       effectSize: nil, significant: false)
        return Insight(kind: .sleepDebt, title: title, reading: reading, datum: datum,
                       evidence: evidence, confidence: .medium,
                       relevance: relevance(significant: false, qAdjusted: nil,
                                            effectMag: hours, effectRef: 7.0, recency: 1.0))
    }

    // MARK: - Activity cost (ActivityCostEngine)

    private static func activityCostInsights(_ days: [DailyMetric],
                                             activityDaysBySport: [String: Set<String>]) -> [Insight] {
        guard !activityDaysBySport.isEmpty else { return [] }
        var recoveryByDay: [String: Double] = [:]
        for d in days { if let r = d.recovery { recoveryByDay[d.day] = r } }
        guard !recoveryByDay.isEmpty else { return [] }

        let costs = ActivityCostEngine.evaluate(activityDaysBySport: activityDaysBySport,
                                                 recoveryByDay: recoveryByDay)
        var out: [Insight] = []
        for c in costs where abs(c.delta) >= ActivityCostEngine.barelyMovesPoints {
            let title = "\(c.sport) te cuesta Recuperación"
            let reading = "Tras \(c.sport), tu Recuperación del día siguiente cae ~\(Int(c.delta.rounded())) pts vs tus días de descanso (n=\(c.n))."
            let datum = InsightDatum(value: round1(c.delta), unit: "pts", metric: "Recuperación")
            let evidence = InsightEvidence(n: c.n, pValue: nil, pAdjusted: nil,
                                           effectSize: nil, significant: false)
            out.append(Insight(kind: .activityCost, title: title, reading: reading, datum: datum,
                               evidence: evidence, confidence: .medium,
                               relevance: relevance(significant: false, qAdjusted: nil,
                                                    effectMag: abs(c.delta),
                                                    effectRef: 15.0,
                                                    recency: c.confidence == .solid ? 0.8 : 0.6)))
        }
        return out
    }

    // MARK: - Training load (ReadinessEngine)

    private static func trainingLoadInsight(_ days: [DailyMetric], today: String?) -> Insight? {
        let r = ReadinessEngine.evaluate(days: days, today: today)
        guard let acwr = r.acwr, let band = r.loadBand, band != .sweetSpot else { return nil }
        let title = "Tu carga de entrenamiento: \(band.shortLabel)"
        let datum = InsightDatum(value: round2(acwr), unit: "", metric: "Carga (ACWR)")
        let evidence = InsightEvidence(n: days.count, pValue: nil, pAdjusted: nil,
                                       effectSize: nil, significant: false)
        return Insight(kind: .trainingLoad, title: title, reading: r.summary, datum: datum,
                       evidence: evidence, confidence: .medium,
                       relevance: relevance(significant: false, qAdjusted: nil,
                                            effectMag: abs(acwr - 1.0), effectRef: 0.5, recency: 1.0))
    }

    // MARK: - Fitness age (FitnessAgeEngine)

    private static func fitnessAgeInsight(_ days: [DailyMetric], fitness: FitnessInputs?) -> Insight? {
        guard let f = fitness else { return nil }
        let rhrs = days.suffix(14).compactMap { $0.restingHr.map(Double.init) }
        guard !rhrs.isEmpty else { return nil }
        let restingHR = HRVAnalyzer.median(rhrs)
        guard let res = FitnessAgeEngine.compute(age: f.age, sex: f.sex, restingHR: restingHR,
                                                 paIndex: f.paIndex, waistCm: f.waistCm) else { return nil }
        let younger = res.deltaYears >= 0
        let title = younger ? "Tu edad fitness es menor que tu edad" : "Tu edad fitness va por encima de tu edad"
        let reading = "Tu edad fitness es \(Int(res.fitnessAge.rounded())) años (±\(Int(res.bandYears.rounded()))), \(abs(Int(res.deltaYears.rounded()))) \(younger ? "menos" : "más") que tu edad real."
        let datum = InsightDatum(value: round1(res.fitnessAge), unit: "años", metric: "Edad fitness")
        let evidence = InsightEvidence(n: rhrs.count, pValue: nil, pAdjusted: nil,
                                       effectSize: nil, significant: false)
        return Insight(kind: .fitnessAge, title: title, reading: reading, datum: datum,
                       evidence: evidence, confidence: .medium,
                       relevance: relevance(significant: false, qAdjusted: nil,
                                            effectMag: abs(res.deltaYears), effectRef: 10.0, recency: 0.4))
    }

    // MARK: - Relevance & formatting

    /// Ranking score: significant findings always outrank descriptive ones, then by
    /// statistical strength (1 − q), effect magnitude (clamped to a scale), and recency.
    static func relevance(significant: Bool, qAdjusted: Double?,
                          effectMag: Double, effectRef: Double, recency: Double) -> Double {
        let sig = significant ? 2.0 : 0.0
        let qScore = qAdjusted.map { 1.0 - Swift.min(1.0, $0) } ?? 0.0
        let eScore = Swift.min(1.0, effectMag / Swift.max(effectRef, 1e-9))
        return sig + qScore + eScore + Swift.min(1.0, Swift.max(0.0, recency))
    }

    static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
    static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}
