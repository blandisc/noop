import SwiftUI
import StrandAnalytics
import StrandDesign

/// FER-670 / FER-254: the quiet source-agreement read under a fused single-construct metric
/// (steps / sleep total / active kcal). Shows each source's value VERBATIM plus whether they
/// match — a conflict is flagged and both values stay visible, never averaged away. Rendered
/// only when ≥2 sources reported the displayed day (`Repository.fusionPoint` is nil otherwise);
/// the cross-source vitals (HRV/RHR/resp/stages) never reach here — `FusionResolver` refuses
/// them (SourceLens governs those).
///
/// Liquid Glass · El Eje: delegates chrome to `LiquidNotaLine(verdict:values:tono:)`.
struct FusionAgreementRow: View {
    let point: FusedMetricPoint
    /// Formats a contributor's value in the metric's display unit (grouped steps, "7 h 05 m", kcal).
    var format: (Double) -> String = { "\(Int($0.rounded()))" }

    var body: some View {
        if point.agreement != .single {
            LiquidNotaLine(verdict: verdict,
                           values: values,
                           tono: point.agreement == .conflict ? .atencion : .ok)
        }
    }

    private var verdict: String {
        switch point.agreement {
        case .agree:      return String(localized: "Sources match")
        case .minorDelta: return String(localized: "Sources differ slightly")
        case .conflict:   return String(localized: "Sources in conflict")
        case .single:     return ""   // never rendered (the body guard)
        }
    }

    /// "Apple Health 8,100 · Band 6,000" — winner first (the resolver's order), values verbatim.
    private var values: String {
        point.contributors.map { "\(name($0.source)) \(format($0.value))" }.joined(separator: " · ")
    }

    private func name(_ source: FusionSource) -> String {
        switch source {
        case .whoopImport:  return String(localized: "Imported")
        case .noopComputed: return String(localized: "Band")
        case .appleHealth:  return String(localized: "Apple Health")
        }
    }
}

#if DEBUG
#Preview("FusionAgreementRow: states") {
    VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        FusionAgreementRow(
            point: FusedMetricPoint(
                metric: "steps", value: 8100, winningSource: .appleHealth,
                contributors: [
                    ContributingSource(source: .appleHealth, value: 8100, tier: 0, sourcePriority: 2, reason: "counts directly"),
                    ContributingSource(source: .noopComputed, value: 8420, tier: 3, sourcePriority: 1, reason: "motion estimate"),
                ],
                agreement: .agree),
            format: { $0.formatted(.number.grouping(.automatic)) })
        FusionAgreementRow(
            point: FusedMetricPoint(
                metric: "active_kcal", value: 612, winningSource: .appleHealth,
                contributors: [
                    ContributingSource(source: .appleHealth, value: 612, tier: 0, sourcePriority: 2, reason: "active energy"),
                    ContributingSource(source: .whoopImport, value: 588, tier: 0, sourcePriority: 0, reason: "imported kcal"),
                ],
                agreement: .minorDelta),
            format: { "\(Int($0.rounded()))" })
        FusionAgreementRow(
            point: FusedMetricPoint(
                metric: "sleep_total_min", value: 432, winningSource: .whoopImport,
                contributors: [
                    ContributingSource(source: .whoopImport, value: 432, tier: 0, sourcePriority: 0, reason: "band sleep timeline"),
                    ContributingSource(source: .appleHealth, value: 120, tier: 2, sourcePriority: 2, reason: "phone sleep buckets"),
                ],
                agreement: .conflict),
            format: { "\(Int($0 / 60)) h \(String(format: "%02d", Int($0.truncatingRemainder(dividingBy: 60)))) m" })
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelAlto)
}
#endif
