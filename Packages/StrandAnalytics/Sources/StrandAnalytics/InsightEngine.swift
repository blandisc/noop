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
    /// Trailing nights the sleep-debt detector accumulates over. (The nightly need it measures against
    /// lives in `SleepMath`, shared with the Sleep Detail — FER-339.)
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
        /// Behavior → the universe of days it is even *measured* on (FER-385). A behavior present here
        /// is restricted to that universe when split (days outside it land in NEITHER group); one absent
        /// keeps the legacy "absence = without" split. Only diet adherence sets it — see
        /// `BehaviorInsights.effect(... eligibleDays:)`. Keyed by the same behavior string as `behaviors`.
        public var eligibleDaysByBehavior: [String: Set<String>]
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
                    eligibleDaysByBehavior: [String: Set<String>] = [:],
                    activityDaysBySport: [String: Set<String>] = [:],
                    sleepSessions: [CachedSleepSession] = [],
                    referenceDay: String? = nil,
                    fitness: FitnessInputs? = nil) {
            self.days = days
            self.behaviors = behaviors
            self.eligibleDaysByBehavior = eligibleDaysByBehavior
            self.activityDaysBySport = activityDaysBySport
            self.sleepSessions = sleepSessions
            self.referenceDay = referenceDay
            self.fitness = fitness
        }
    }

    // MARK: - Outcomes (the M metrics behaviors & correlations are tested against)

    /// The daily outcome metrics every inferential detector tests against — and the single, typed source
    /// of the join key that a `Lever.outcome` carries, an N-of-1 experiment runs on, and a Bucle goal
    /// projects toward (`GoalMetric.outcome`). Minting each metric's label / unit / field-accessor in ONE
    /// place means a rename is a single edit and a new outcome is a compile-time `switch` obligation —
    /// there is no second, hand-typed copy of these es-MX strings to drift out of sync. (The bug this
    /// guards against: a silent rename used to leave `outcomeSeries` returning `[:]` and the goal
    /// simulator projecting an empty series, with nothing failing to compile.)
    ///
    /// Declaration order is also the order the FDR association family is built in (`behaviorCandidates`),
    /// so append new cases rather than reordering.
    public enum Outcome: String, CaseIterable, Sendable {
        case recovery, hrv, sleep, restingHr

        /// es-MX label — the string a `Lever.outcome` carries and `outcomeSeries(_:metric:)` matches.
        public var label: String {
            switch self {
            case .recovery:  return "Recuperación"
            case .hrv:       return "HRV"
            case .sleep:     return "Sueño"
            case .restingHr: return "FC en reposo"
            }
        }

        /// Whether a HIGHER daily value is the better/healthier direction. Resting HR is the lone
        /// lower-is-better outcome (the UI mirrors this as `metric != "FC en reposo"`). Used to orient
        /// "this helps / hurts you" verdicts so a lower-is-better metric isn't read upside-down.
        public var higherIsBetter: Bool { self != .restingHr }

        /// Direction looked up from the es-MX `label` a `Lever` / grounding fact carries; an unknown
        /// label defaults to higher-is-better.
        public static func higherIsBetter(outcomeLabel: String) -> Bool {
            allCases.first { $0.label == outcomeLabel }?.higherIsBetter ?? true
        }

        /// Localized DISPLAY name for readings/titles — distinct from `label`, which is the stable es-MX
        /// key that levers/experiments persist and `outcomeSeries`/the coach's topic filter match on.
        /// Reuses the catalog keys the rest of the app already carries (Recovery/HRV/Sleep/Resting HR).
        public var displayLabel: String {
            switch self {
            case .recovery:  return String(localized: "Recovery", bundle: .main)
            case .hrv:       return String(localized: "HRV", bundle: .main)
            case .sleep:     return String(localized: "Sleep", bundle: .main)
            case .restingHr: return String(localized: "Resting HR", bundle: .main)
            }
        }

        /// Native unit of the daily value (`min` for sleep — the goal screen converts to hours for display).
        public var unit: String {
            switch self {
            case .recovery:  return "pts"
            case .hrv:       return "ms"
            case .sleep:     return "min"
            case .restingHr: return "lpm"
            }
        }

        /// Read this outcome off a daily row; `nil` when that day lacks the value.
        func value(_ d: DailyMetric) -> Double? {
            switch self {
            case .recovery:  return d.recovery
            case .hrv:       return d.avgHrv
            case .sleep:     return d.totalSleepMin
            case .restingHr: return d.restingHr.map(Double.init)
            }
        }

        /// The outcome whose `label` matches, or `nil`. The persisted-string paths (a `Lever.outcome`, an
        /// experiment row's `outcome`) re-resolve to a case through here instead of comparing raw strings.
        public init?(label: String) {
            guard let m = Self.allCases.first(where: { $0.label == label }) else { return nil }
            self = m
        }
    }

    /// The "yyyy-MM-dd" → value series for one `Outcome`, read off `days`. Empty when no day carries the
    /// value. This is the typed join the goal simulator uses (`GoalMetric.outcome`), so it can never be
    /// handed a stale label.
    public static func outcomeSeries(_ days: [DailyMetric], _ outcome: Outcome) -> [String: Double] {
        var out: [String: Double] = [:]
        for d in days { if let v = outcome.value(d) { out[d.day] = v } }
        return out
    }

    /// Label-keyed sibling for the persisted-string paths: an experiment row's `outcome` (FER-307) or a
    /// `Lever.outcome` carry a `String`, not an `Outcome`. Re-resolves the label through `Outcome` and
    /// returns `[:]` for an unknown one, so the label→field mapping still lives in exactly one place.
    public static func outcomeSeries(_ days: [DailyMetric], metric: String) -> [String: Double] {
        guard let outcome = Outcome(label: metric) else { return [:] }
        return outcomeSeries(days, outcome)
    }

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
        insights += associationInsights(days, behaviors: inputs.behaviors,
                                         eligibleDaysByBehavior: inputs.eligibleDaysByBehavior)  // FDR family (behaviors × M + correlations)
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

    // MARK: - Candidate → proven overlay (N-of-1 experiments, issue D)

    /// Promote candidate findings whose lever an N-of-1 experiment has confirmed. The engine is
    /// stateless and recomputes confidence from the data every run, so "proven" can't live on the
    /// `Insight`; it lives in the experiment table and is projected back here. A finding is promoted
    /// only when it carries a `lever` in `provenLevers` AND is currently a `.candidate` (a finding
    /// that didn't survive FDR this run is `.medium` — it isn't shown as a lever, so it isn't
    /// promoted). Every other field, including `relevance`, is preserved.
    public static func promoteProven(_ insights: [Insight], provenLevers: Set<Lever>) -> [Insight] {
        guard !provenLevers.isEmpty else { return insights }
        return insights.map { i in
            guard i.confidence == .candidate, let lever = i.lever, provenLevers.contains(lever) else {
                return i
            }
            return Insight(kind: i.kind, title: i.title, reading: i.reading, datum: i.datum,
                           evidence: i.evidence, confidence: .proven, relevance: i.relevance,
                           lever: i.lever)
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
                                            behaviors: [String: Set<String>],
                                            eligibleDaysByBehavior: [String: Set<String>]) -> [Insight] {
        var candidates: [Candidate] = []
        candidates += behaviorCandidates(days, behaviors: behaviors,
                                         eligibleDaysByBehavior: eligibleDaysByBehavior)
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
                                           behaviors: [String: Set<String>],
                                           eligibleDaysByBehavior: [String: Set<String>]) -> [Candidate] {
        guard !days.isEmpty, !behaviors.isEmpty else { return [] }
        var cands: [Candidate] = []
        for metric in Outcome.allCases {
            // outcomeByDay for this metric — built once and shared across every behavior, so the
            // per-behavior universe restriction (FER-385) is applied inside `effect`, not here.
            var outcomeByDay: [String: Double] = [:]
            for d in days { if let v = metric.value(d) { outcomeByDay[d.day] = v } }
            guard outcomeByDay.count >= 2 * minGroup else { continue }

            for behavior in behaviors.keys.sorted() {
                let bdays = behaviors[behavior]!
                guard let e = BehaviorInsights.effect(behaviorDays: bdays,
                                                      outcomeByDay: outcomeByDay,
                                                      behavior: behavior,
                                                      outcome: metric.label,
                                                      eligibleDays: eligibleDaysByBehavior[behavior]) else { continue }
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
        let pairs: [(x: Outcome, y: Outcome)] = [
            (.sleep, .recovery),       // Sueño → Recuperación
            (.hrv, .recovery),         // HRV → Recuperación
            (.restingHr, .recovery),   // FC en reposo → Recuperación
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

    private static func behaviorInsight(_ e: BehaviorEffect, metric: Outcome,
                                        qAdjusted: Double, significant: Bool, n: Int) -> Insight {
        let pct = e.pctChange.map { abs($0) } ?? 0
        let pctInt = Int(pct.rounded())
        let title = String(localized: "‘\(e.behavior)’ and your \(metric.displayLabel)", bundle: .main)
        let reading = e.delta < 0
            ? String(localized: "On days with ‘\(e.behavior)’, your \(metric.displayLabel) drops \(pctInt)% (n=\(e.nWith) vs \(e.nWithout)).", bundle: .main)
            : String(localized: "On days with ‘\(e.behavior)’, your \(metric.displayLabel) rises \(pctInt)% (n=\(e.nWith) vs \(e.nWithout)).", bundle: .main)
        let datum = InsightDatum(value: round1(e.delta), unit: metric.unit, metric: metric.label)
        let evidence = InsightEvidence(n: n, pValue: e.pApprox, pAdjusted: qAdjusted,
                                       effectSize: e.cohensD, significant: significant)
        return Insight(kind: .behavior, title: title, reading: reading, datum: datum,
                       evidence: evidence,
                       confidence: significant ? .candidate : .medium,
                       relevance: relevance(significant: significant, qAdjusted: qAdjusted,
                                            effectMag: abs(e.cohensD), effectRef: 0.8, recency: 0.5),
                       lever: Lever(behavior: e.behavior, outcome: metric.label),
                       behaviorBreakdown: BehaviorBreakdown(meanWith: round1(e.meanWith),
                                                            meanWithout: round1(e.meanWithout),
                                                            nWith: e.nWith, nWithout: e.nWithout))
    }

    private static func correlationInsight(_ c: Correlation, x: Outcome, y: Outcome,
                                           qAdjusted: Double, significant: Bool) -> Insight {
        let rTxt = String(round2(c.r))
        let title = String(localized: "\(x.displayLabel) and \(y.displayLabel) go together", bundle: .main)
        let reading = c.r < 0
            ? String(localized: "Inverse relationship between \(x.displayLabel) and \(y.displayLabel) (r=\(rTxt), n=\(c.n)).", bundle: .main)
            : String(localized: "Direct relationship between \(x.displayLabel) and \(y.displayLabel) (r=\(rTxt), n=\(c.n)).", bundle: .main)
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

        // `label` stays es-MX — it's the stable key used for `datum.metric` and the coach's topic filter;
        // `displayLabel` is the localized name shown in the title/reading.
        struct Probe { let key: String; let label: String; let displayLabel: String; let unit: String
                       let cfg: MetricCfg; let value: (DailyMetric) -> Double? }
        let probes: [Probe] = [
            Probe(key: "hrv", label: "HRV", displayLabel: String(localized: "HRV", bundle: .main),
                  unit: "ms", cfg: Baselines.hrvCfg, value: { $0.avgHrv }),
            Probe(key: "resting_hr", label: "FC en reposo", displayLabel: String(localized: "Resting HR", bundle: .main),
                  unit: "lpm", cfg: Baselines.restingHRCfg, value: { $0.restingHr.map(Double.init) }),
            Probe(key: "resp", label: "Respiración", displayLabel: String(localized: "Respiration", bundle: .main),
                  unit: "rpm", cfg: Baselines.respCfg, value: { $0.respRateBpm }),
        ]

        var out: [Insight] = []
        for p in probes {
            guard let value = p.value(latest) else { continue }
            let state = Baselines.foldHistory(history.map { p.value($0) }, cfg: p.cfg)
            guard state.usable else { continue }
            let dev = Baselines.deviation(value, state: state)
            guard abs(dev.z) >= 2.0 else { continue }   // anomaly only
            let zTxt = String(round1(dev.z))
            let baseInt = Int(state.baseline.rounded())
            let title = String(localized: "\(p.displayLabel) was off last night", bundle: .main)
            let reading = dev.z < 0
                ? String(localized: "Last night your \(p.displayLabel) ran below your baseline (z=\(zTxt), baseline \(baseInt)\(p.unit)).", bundle: .main)
                : String(localized: "Last night your \(p.displayLabel) ran above your baseline (z=\(zTxt), baseline \(baseInt)\(p.unit)).", bundle: .main)
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
            let curMean = Int(cmp.current.mean.rounded())
            let prevMean = Int(cmp.previous.mean.rounded())
            let pctInt = Int(pct.rounded())
            let title = cmp.direction < 0
                ? String(localized: "Your Recovery is trending down (\(window) days)", bundle: .main)
                : String(localized: "Your Recovery is trending up (\(window) days)", bundle: .main)
            let reading = String(localized: "Over the last \(window) days your Recovery averaged \(curMean) vs \(prevMean) before (\(pctInt)%).", bundle: .main)
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
        let step: Double   // signed direction for the test to read off evidence.effectSize
        let title: String
        switch r.direction {
        case .rising:  step = 1;  title = String(localized: "Tomorrow your Recovery looks like it's heading up", bundle: .main)
        case .falling: step = -1; title = String(localized: "Tomorrow your Recovery looks like it's heading down", bundle: .main)
        case .steady:  step = 0;  title = String(localized: "Tomorrow your Recovery looks steady", bundle: .main)
        }
        let est = Int(r.estimate.rounded())
        let lo = Int(r.low.rounded())
        let hi = Int(r.high.rounded())
        let reading = String(localized: "Forecast for tomorrow: \(est) (range \(lo)–\(hi), \(r.basisDays) days).", bundle: .main)
        let datum = InsightDatum(value: round1(r.estimate), unit: "pts", metric: "Recuperación")
        let evidence = InsightEvidence(n: r.basisDays, pValue: nil, pAdjusted: nil,
                                       effectSize: step, significant: false)
        return Insight(kind: .forecast, title: title, reading: reading, datum: datum,
                       evidence: evidence, confidence: .medium,
                       relevance: relevance(significant: false, qAdjusted: nil,
                                            effectMag: abs(r.estimate - 50), effectRef: 50.0, recency: 1.0))
    }

    // MARK: - Sleep regularity (SleepRegularity — SD of mid-sleep, SAME engine as the Sleep Detail)

    // FER-339: the coach must report the SAME regularity the Sleep Detail shows. The detail uses
    // `SleepRegularity` (SD of the mid-sleep point → a 0–100 score); this used to use the older
    // `SleepRegularityIndex` (SRI), so the two surfaces showed two different "/100" numbers. Now both
    // read `SleepRegularity.score`. We only surface it as a finding when the schedule is genuinely
    // "variable" (score < 55), so the coach never calls "irregular" a night the detail labels "regular".
    private static func sleepRegularityInsight(_ sessions: [CachedSleepSession]) -> Insight? {
        let timing = sessions.compactMap { s -> SleepRegularity.NightTiming? in
            guard s.endTs > s.startTs else { return nil }   // exclude Apple-only nights (start == end)
            return SleepRegularity.NightTiming(onset: s.startTs, wake: s.endTs)
        }
        guard let r = SleepRegularity.compute(timing), r.score < 55 else { return nil }
        let title = String(localized: "Your sleep schedule is drifting", bundle: .main)
        let reading = String(localized: "Your sleep regularity is at \(r.score)/100 (how consistent your bedtime is); steadier hours help.", bundle: .main)
        let datum = InsightDatum(value: Double(r.score), unit: "/100", metric: "Regularidad de sueño")
        let evidence = InsightEvidence(n: r.nights, pValue: nil, pAdjusted: nil,
                                       effectSize: nil, significant: false)
        return Insight(kind: .sleepRegularity, title: title, reading: reading, datum: datum,
                       evidence: evidence, confidence: .medium,
                       relevance: relevance(significant: false, qAdjusted: nil,
                                            effectMag: Double(80 - r.score), effectRef: 40.0, recency: 0.9))
    }

    // MARK: - Sleep debt (DailyMetric)

    /// Accumulated sleep debt (min) over the trailing window. Single source of truth shared with the
    /// Sleep Detail screen (FER-339): `SleepMath` (per-night shortfall vs personal need, floored).
    static func sleepDebtMinutes(_ days: [DailyMetric]) -> Double {
        SleepMath.debtMinutes(days)
    }

    private static func sleepDebtInsight(debtMin: Double, nights: Int) -> Insight? {
        guard debtMin >= 60, nights >= 3 else { return nil }   // < 1h debt isn't worth a card
        let hours = debtMin / 60.0
        let hoursTxt = String(round1(hours))
        let title = String(localized: "You're carrying sleep debt", bundle: .main)
        let reading = String(localized: "Over recent nights you've built up \(hoursTxt) h below your need; debt isn't repaid in one go.", bundle: .main)
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
            let deltaInt = Int(c.delta.rounded())
            let title = String(localized: "\(c.sport) costs you Recovery", bundle: .main)
            let reading = String(localized: "After \(c.sport), your next-day Recovery drops ~\(deltaInt) pts vs your rest days (n=\(c.n)).", bundle: .main)
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
        let title = String(localized: "Your training load: \(band.shortLabel)", bundle: .main)
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
        let ageInt = Int(res.fitnessAge.rounded())
        let bandInt = Int(res.bandYears.rounded())
        let deltaInt = abs(Int(res.deltaYears.rounded()))
        let title = younger
            ? String(localized: "Your fitness age is lower than your age", bundle: .main)
            : String(localized: "Your fitness age is above your age", bundle: .main)
        let reading = younger
            ? String(localized: "Your fitness age is \(ageInt) years (±\(bandInt)), \(deltaInt) younger than your real age.", bundle: .main)
            : String(localized: "Your fitness age is \(ageInt) years (±\(bandInt)), \(deltaInt) older than your real age.", bundle: .main)
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
