import Foundation

// MARK: - FusionResolver (FER-670 — port of upstream v5, single-construct subset)
//
// Pure, deterministic display arbitration for metrics where every source measures the SAME construct
// (a step count, a night's total sleep minutes, an active-energy figure). Given the per-source values
// for ONE (metric, day), it:
//   1. ranks sources by trust tier (`MetricArbitrationPolicy`), stable tiebreak, and picks the winner's
//      value VERBATIM (best signal wins — never an average);
//   2. cross-validates the other sources against the winner and classifies agreement as
//      single / agree / minorDelta / conflict — a conflict is SHOWN, never merged away.
//
// Deliberately narrower than the upstream original: `resolve` refuses (returns nil) any metric key
// `MetricArbitrationPolicy.kind(forKey:)` doesn't map — HRV/RHR/respiration/sleep stages carry
// measured band↔Apple instrument offsets (RMSSD vs SDNN has no published conversion), so they are
// governed by `SourceLens` (FER-629), not by a tolerance table. This engine is ADDITIVE display
// transparency on top of `DataSourceMode`; it never feeds a baseline.
//
// No I/O — the Repository feeds it rows it already loads.
public enum FusionResolver {

    /// Resolve one metric for one day from each source's value. `metricKey` is the resolver series key
    /// ("steps", "sleep_total_min", "active_kcal"); it picks the trust tiers and tolerance via
    /// `MetricArbitrationPolicy`. Returns nil when `inputs` is empty, or when the key is not a
    /// single-construct metric this engine arbitrates (the FER-670 exclusion — see the policy).
    ///
    /// The winner is the lowest-tier source, ties broken by `sourcePriority` (stable, deterministic).
    /// Its value passes through unchanged. The agreement state classifies how far the OTHER sources sit
    /// from the winning value, per the metric's tolerance band.
    public static func resolve(metricKey: String, inputs: [FusionInput]) -> FusedMetricPoint? {
        guard !inputs.isEmpty else { return nil }
        // The exclusion gate: an unmapped key (hrv, rhr, resp_rate, spo2, skin_temp, sleep stages…)
        // is NOT arbitrated here — nil, never a fallback tier.
        guard let kind = MetricArbitrationPolicy.kind(forKey: metricKey) else { return nil }

        // Build a contributor for every source, tagged with its trust tier + reason.
        let contributorsUnsorted: [ContributingSource] = inputs.map { input in
            ContributingSource(
                source: input.source,
                value: input.value,
                tier: MetricArbitrationPolicy.tier(metric: kind, source: input.source),
                sourcePriority: MetricArbitrationPolicy.sourcePriority(input.source),
                reason: MetricArbitrationPolicy.reason(metric: kind, source: input.source)
            )
        }

        // Winner = lowest tier, then lowest source-priority. Stable: equal keys keep input order via a
        // final index tiebreak so the result is fully deterministic.
        let ranked = contributorsUnsorted.enumerated().sorted { lhs, rhs in
            if lhs.element.tier != rhs.element.tier { return lhs.element.tier < rhs.element.tier }
            if lhs.element.sourcePriority != rhs.element.sourcePriority {
                return lhs.element.sourcePriority < rhs.element.sourcePriority
            }
            return lhs.offset < rhs.offset
        }.map { $0.element }

        let winner = ranked[0]
        let agreement = classify(metric: kind, winningValue: winner.value, contributors: ranked)

        return FusedMetricPoint(
            metric: metricKey,
            value: winner.value,
            winningSource: winner.source,
            contributors: ranked,
            agreement: agreement
        )
    }

    /// Classify how the non-winning sources agree with `winningValue`, using the metric's tolerance.
    /// Worst case across all other sources wins (one conflicting source makes the point a conflict).
    /// One source ⇒ `.single` (nothing to cross-check).
    static func classify(metric: MetricArbitrationPolicy.MetricKind,
                         winningValue: Double,
                         contributors: [ContributingSource]) -> AgreementState {
        // Only one source reported the metric → nothing to compare against.
        guard contributors.count >= 2 else { return .single }

        let tol = MetricArbitrationPolicy.tolerance(metric: metric)
        var worst: AgreementState = .agree

        for c in contributors.dropFirst() {  // skip the winner (index 0)
            let delta = abs(c.value - winningValue)
            let agreeEdge: Double
            let minorEdge: Double
            if tol.isPercent {
                // Percentage band relative to the winning value's magnitude. With a zero winner the
                // edges collapse to 0, so any non-zero second value classifies as a conflict — honest:
                // "one source says nothing happened, the other says something did".
                let base = abs(winningValue)
                agreeEdge = tol.agree * base
                minorEdge = tol.minorDelta * base
            } else {
                agreeEdge = tol.agree
                minorEdge = tol.minorDelta
            }

            let state: AgreementState
            if delta <= agreeEdge {
                state = .agree
            } else if delta <= minorEdge {
                state = .minorDelta
            } else {
                state = .conflict
            }
            worst = worse(worst, state)
        }
        return worst
    }

    /// Order of severity for the worst-case fold: agree < minorDelta < conflict. (`single` never
    /// enters here — it's the >= 2 guard's job.)
    private static func severity(_ s: AgreementState) -> Int {
        switch s {
        case .single:     return 0
        case .agree:      return 1
        case .minorDelta: return 2
        case .conflict:   return 3
        }
    }

    /// The more-severe of two agreement states.
    private static func worse(_ a: AgreementState, _ b: AgreementState) -> AgreementState {
        severity(a) >= severity(b) ? a : b
    }
}

// MARK: - Fusion value types

/// Where a fused number came from — the three sources this app actually writes. A future extra
/// source (another band, another importer) is a new case + policy table entries, not a redesign.
public enum FusionSource: String, Equatable, Sendable, CaseIterable, Codable {
    /// Imported WHOOP record (CSV/zip export under the strap's raw deviceId).
    case whoopImport
    /// On-device computed row derived from the raw strap streams (the "-noop" sibling deviceId).
    case noopComputed
    /// Apple Health aggregate ("apple-health").
    case appleHealth
}

/// How well a metric's value agrees across the sources that reported it on the same day.
/// `agree` → quiet note; `minorDelta` → show both, neutral; `conflict` → flag, never merge.
/// Deterministic threshold output; see `MetricArbitrationPolicy.tolerance(metric:)`.
public enum AgreementState: String, Equatable, Sendable, CaseIterable, Codable {
    /// Only one source reported the metric — nothing to cross-check, nothing shown.
    case single
    /// Within the metric's tolerance — sources agree.
    case agree
    /// Outside tolerance but inside the plausible-spread band — show both, no alarm.
    case minorDelta
    /// Large divergence — flag prominently, keep both, never silently average.
    case conflict
}

/// One source's value for a `(metric, day)`, with the trust tier the policy assigned it. The winner
/// is the lowest `tier` (most trusted), ties broken by `sourcePriority` (stable). `reason` is the
/// published, plain-English justification ("counts directly", "band sleep timeline") — the honesty
/// contract: never "accurate"/"correct"/"clinical".
public struct ContributingSource: Equatable, Sendable {
    public let source: FusionSource
    public let value: Double
    /// Trust tier (lower = more trusted); from `MetricArbitrationPolicy.tier(metric:source:)`.
    public let tier: Int
    /// Stable tiebreak within a tier (lower wins); from the policy's source ordering.
    public let sourcePriority: Int
    /// The visible "best signal" reason for this source on this metric.
    public let reason: String

    public init(source: FusionSource, value: Double, tier: Int, sourcePriority: Int, reason: String) {
        self.source = source
        self.value = value
        self.tier = tier
        self.sourcePriority = sourcePriority
        self.reason = reason
    }
}

/// The fused result for one `(metric, day)`: the winning value, the source that supplied it, every
/// contributor (for the compare row), and the agreement classification. Pure data.
public struct FusedMetricPoint: Equatable, Sendable {
    /// The metric key this point resolves ("steps", "sleep_total_min", "active_kcal").
    public let metric: String
    /// The chosen value (verbatim from `winningSource`'s row — never an average).
    public let value: Double
    /// The source that supplied `value` (highest trust, stable tiebreak).
    public let winningSource: FusionSource
    /// Every source that reported this metric for the day, winner first, then by tier/priority.
    public let contributors: [ContributingSource]
    /// Cross-validation outcome across `contributors`.
    public let agreement: AgreementState

    public init(metric: String, value: Double, winningSource: FusionSource,
                contributors: [ContributingSource], agreement: AgreementState) {
        self.metric = metric
        self.value = value
        self.winningSource = winningSource
        self.contributors = contributors
        self.agreement = agreement
    }
}

/// A single source's raw input to the fusion engine: a value for a metric on a day. The Repository
/// builds these from rows it already reads (it does the I/O); the engine stays pure.
public struct FusionInput: Equatable, Sendable {
    public let source: FusionSource
    public let value: Double
    public init(source: FusionSource, value: Double) {
        self.source = source
        self.value = value
    }
}
