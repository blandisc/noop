import Foundation

// Insight.swift — the value types the InsightEngine emits.
//
// Pure, deterministic, DB-free. An `Insight` is one finding: a typed, ranked,
// es-MX statement backed by a real datum and its statistical evidence. The engine
// computes EVERY number here; the LLM step (issue E) only rewrites the `title` /
// `reading` templates — it never produces a figure. The `confidence` field is left
// at `.candidate` / `.medium` by this issue; the N-of-1 experiment flow (issue D)
// is what later promotes a candidate to `.proven`.

/// Which detector produced an insight, each mapped 1:1 to an existing pure engine.
public enum InsightKind: String, Sendable, Equatable, CaseIterable {
    case behavior          // BehaviorInsights — a logged behavior moves an outcome
    case correlation       // CorrelationEngine — two metrics move together
    case nightAnomaly      // Baselines (z-score) — last night broke from baseline
    case trend             // ComparisonEngine — 7/30-day shift
    case forecast          // RecoveryForecast — tomorrow's projection
    case sleepRegularity   // SleepRegularityIndex — irregular sleep timing
    case sleepDebt         // DailyMetric — accumulated sleep deficit
    case activityCost      // ActivityCostEngine — a sport's recovery cost
    case trainingLoad      // ReadinessEngine — ACWR / monotony load state
    case fitnessAge        // FitnessAgeEngine — fitness vs chronological age
}

/// How much we trust a finding as actionable guidance.
public enum InsightConfidence: String, Sendable, Equatable {
    /// A statistically significant association, but no experiment has confirmed it
    /// is causal/repeatable for this user. The starting tier for behavior &
    /// correlation findings that survive FDR.
    case candidate
    /// Promoted by an N-of-1 experiment (issue D). This engine never sets it; the
    /// field exists so the experiment flow has somewhere to write.
    case proven
    /// A real, observed datum that isn't an association claim at all — a trend, a
    /// night anomaly, a forecast, a debt total. Informational, not "try changing X".
    case medium
}

/// The headline figure a finding is about.
public struct InsightDatum: Equatable, Sendable {
    /// The number to show (already rounded/shaped by the detector).
    public let value: Double
    /// Its unit, es-MX or symbol: "%", "pts", "ms", "min", "años", "h".
    public let unit: String
    /// The metric label, es-MX: "Recuperación", "HRV", "Sueño".
    public let metric: String

    public init(value: Double, unit: String, metric: String) {
        self.value = value
        self.unit = unit
        self.metric = metric
    }
}

/// The statistical backing for a finding. Non-inferential detectors (trend,
/// forecast, debt) leave `pValue` / `pAdjusted` / `effectSize` nil and report
/// `significant == false` (they describe, they don't test a hypothesis).
public struct InsightEvidence: Equatable, Sendable {
    /// Sample size behind the finding (days, pairs, sessions…).
    public let n: Int
    /// Raw two-sided p-value, when the detector ran a hypothesis test.
    public let pValue: Double?
    /// FDR-adjusted q-value (Benjamini-Hochberg) within the multiple-comparison
    /// family the finding belongs to. nil when the detector isn't part of a family.
    public let pAdjusted: Double?
    /// Standardised effect size (Cohen's d, Pearson r, z…), signed.
    public let effectSize: Double?
    /// Whether the finding cleared the engine's significance bar (FDR + sample +
    /// effect-size floors). Always false for purely descriptive detectors.
    public let significant: Bool

    public init(n: Int, pValue: Double?, pAdjusted: Double?,
                effectSize: Double?, significant: Bool) {
        self.n = n
        self.pValue = pValue
        self.pAdjusted = pAdjusted
        self.effectSize = effectSize
        self.significant = significant
    }
}

/// One ranked finding from the InsightEngine.
public struct Insight: Equatable, Sendable {
    public let kind: InsightKind
    /// Short es-MX title (template; the LLM may rewrite it).
    public let title: String
    /// One-line es-MX read of what the datum means (template; the LLM may rewrite).
    public let reading: String
    public let datum: InsightDatum
    public let evidence: InsightEvidence
    public let confidence: InsightConfidence
    /// Ranking score (higher = more relevant): significance × effect size × recency.
    /// Used only to order the list; not shown to the user.
    public let relevance: Double

    public init(kind: InsightKind, title: String, reading: String,
                datum: InsightDatum, evidence: InsightEvidence,
                confidence: InsightConfidence, relevance: Double) {
        self.kind = kind
        self.title = title
        self.reading = reading
        self.datum = datum
        self.evidence = evidence
        self.confidence = confidence
        self.relevance = relevance
    }
}
