#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - BodyAgeSheet — the «Edad corporal» longevity detail (FER-145)
//
// The light «Instrumento diurno» detail for `VitalityEngine`: Body Age (years) is the hero via
// HeroInvertido (longevity green), with an always-on ESTIMATE capsule; partial-estimate nuance
// moves into the hero reading. The reading is a RANGE (`BodyAgeBand`, ±5), not a point. Vitality
// 0–100 rides underneath as a quiet context strip — the SAME measure in another scale, never a second
// hero. Breakdown is `ContributionBars` inside SeccionBloque «What's moving it». PieMetodo carries
// the non-clinical disclaimer + computed origin seal.
//
// Esqueleto Final (misma forma que `MetricDetailScreen.narrativeBodyFinal` / `SkinTempDetailScreen`):
// HeroInvertido → SeccionBloque… → PieMetodo. Full-bleed. Theme is passed explicitly (it does NOT
// cross the `.sheet` environment boundary). Math and copy are preserved; this is a reskin. With no
// result yet (< 3 signals) it shows an honest checklist of what it's built from instead of a
// fabricated number.

struct BodyAgeSheet: View {
    /// The computed Body Age + Vitality, or nil when fewer than `minFactors` signals are present.
    let result: VitalityEngine.Result?
    /// The inputs that fed the engine — drives the "what's built from" checklist in the empty state.
    let inputs: VitalityEngine.Inputs
    /// The active «Instrumento diurno» theme, passed explicitly (doesn't cross the `.sheet` boundary).
    var theme: InstrumentoTheme = .base

    /// Longevity green for the inverted hero field (`#2E7D57`).
    private var longevityHue: Color { theme.dataRejuvenates }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let r = result {
                    withData(r)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
    }

    // MARK: - With data (Final skeleton)

    @ViewBuilder
    private func withData(_ r: VitalityEngine.Result) -> some View {
        heroFinal(r)

        SeccionBloque(String(localized: "Your band"), theme: theme) {
            bandFinalContent(r)
        }

        SeccionBloque(String(localized: "What's moving it"), theme: theme) {
            movesFinalContent(r)
        }

        pieMetodoFinal
    }

    // MARK: - Hero Final (HeroInvertido · dataRejuvenates · always-on Estimate capsule)

    private func heroFinal(_ r: VitalityEngine.Result) -> some View {
        let bodyAge = Int(r.bodyAge.rounded())
        return HeroInvertido(
            glyph: .bodyAge,
            title: "Body age",
            hue: longevityHue,
            theme: theme,
            numeral: {
                HeroNumeral("\(bodyAge)", suffix: String(localized: "years"), size: 60, theme: theme) {
                    Text("Estimate")
                        .font(InstrumentoType.grotesk(11, weight: .semibold))
                        .foregroundStyle(theme.paper)
                        .heroCapsule(theme: theme)
                }
            },
            verdict: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(deltaSentence(r))
                        .font(InstrumentoType.grotesk(15, weight: .semibold))
                        .foregroundStyle(theme.paper)
                        .fixedSize(horizontal: false, vertical: true)
                    // Partial nuance lives in the hero reading (was a separate chip + caption).
                    if r.isPartialEstimate {
                        Text(Self.partialCaveat(r))
                            .font(InstrumentoType.grotesk(14))
                            .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        )
    }

    // MARK: - Your band (BodyAgeBand + vitality context)

    private func bandFinalContent(_ r: VitalityEngine.Result) -> some View {
        let tint = Self.tint(forDelta: r.deltaYears, theme: theme)
        return VStack(alignment: .leading, spacing: 10) {
            BodyAgeBand(bodyAge: r.bodyAge, chronoAge: r.chronoAge, bandYears: r.bandYears, color: tint,
                        youLabel: String(localized: "you"),
                        accessibilityLabelText: String(localized: "Body age"),
                        accessibilityValueText: Self.bandAccessibility(r))
            Text("The band, not the exact point, is the reading.")
                .font(StrandFont.caption).italic().foregroundStyle(theme.inkTertiary)

            // Vitality — the same measure on a 0–100 scale (quiet, in ink, never a second hero).
            HStack(spacing: 8) {
                Text("The same measure, 0–100:").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Text("\(Int(r.vitality.rounded()))").font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
                Text("· 50 = typical").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - What's moving it (QueLaMueveHeader + ContributionBars + differentiator)

    private func movesFinalContent(_ r: VitalityEngine.Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            QueLaMueveHeader("What's moving it", chip: "trend, not cause", theme: theme)
            ContributionBars(items: Self.bars(r.contributions),
                             leftPole: String(localized: "← rejuvenates you"),
                             rightPole: String(localized: "ages you →"))

            // Differentiator vs the cardio-only Physical Age (FER-141) — verbatim, wrapped as-is.
            VStack(alignment: .leading, spacing: 4) {
                Text("This isn't your Physical age").font(StrandFont.subhead).foregroundStyle(theme.ink)
                Text("Physical age measures only the cardiorespiratory side. This one also weighs sleep, regularity, HRV and steps: so the two can differ.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
        }
    }

    // MARK: - PieMetodo (disclaimer + computed origin seal)

    @ViewBuilder private var pieMetodoFinal: some View {
        PieMetodo(theme: theme) {
            Metodo(title: String(localized: "How it's calculated"), theme: theme) {
                Text("A wellness comparison, not a biological age or a clinical diagnosis. HRV is estimated from nighttime PPG; the reference norm is conservative.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } sello: {
            OriginStamp(origin: .computed, when: String(localized: "today"), theme: theme)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    // MARK: - Empty (fewer than 3 signals)

    private var emptyState: some View {
        let present = presentFactors
        return VStack(alignment: .leading, spacing: 0) {
            HeroInvertido(
                glyph: .bodyAge,
                title: "Body age",
                hue: longevityHue,
                theme: theme,
                numeral: {
                    Text(verbatim: "—")
                        .font(InstrumentoType.groteskNumber(60, weight: .bold))
                        .tracking(-2)
                        .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                },
                verdict: {
                    Text("I need at least 3 signals to work this out without guessing. You have \(present.count).")
                        .font(InstrumentoType.grotesk(15, weight: .semibold))
                        .foregroundStyle(theme.paper)
                        .fixedSize(horizontal: false, vertical: true)
                }
            )

            SeccionBloque(String(localized: "What it's built from"), theme: theme) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(Self.factorChecklist.enumerated()), id: \.offset) { i, f in
                        if i > 0 { Divider().overlay(theme.hairline) }
                        checklistRow(f, ready: present.contains(f.key))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))

                Text("Keep wearing the band a few nights and it appears on its own: we don't show a half-finished number.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            pieMetodoFinal
        }
    }

    private func checklistRow(_ f: Factor, ready: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ready ? "checkmark" : "circle")
                .font(StrandFont.glyph(.inline))
                .foregroundStyle(ready ? theme.dataRecovery : theme.inkTertiary)
                .frame(width: 18)
            Text(f.label).font(StrandFont.body).foregroundStyle(ready ? theme.ink : theme.inkSecondary)
            Spacer(minLength: 8)
            Text(ready ? "ready" : f.reason).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Copy helpers

    private func deltaSentence(_ r: VitalityEngine.Result) -> LocalizedStringKey {
        let chrono = Int(r.chronoAge.rounded())
        let d = Int(r.deltaYears.rounded())
        if d > 0 { return "\(d) years younger than your age (\(chrono))" }
        if d < 0 { return "\(-d) years older than your age (\(chrono))" }
        return "Right at your chronological age (\(chrono))"
    }

    /// Names which heaviest factor(s) the reading is missing (FER-643), so the caveat is specific: an
    /// Apple-Health-only user misses both HRV and resting HR; a band user with sparse HRV nights misses
    /// only HRV. Not shown when both are present (`isPartialEstimate == false`).
    private static func partialCaveat(_ r: VitalityEngine.Result) -> LocalizedStringKey {
        let keys = Set(r.contributions.map(\.key))
        let noHRV = !keys.contains("hrv"), noRHR = !keys.contains("rhr")
        if noHRV && noRHR {
            return "Worked out without HRV or resting heart rate: the two heaviest signals. The number still holds, with less precision."
        }
        if noHRV {
            return "Worked out without HRV: one of the heaviest signals. The number still holds, with less precision."
        }
        return "Worked out without resting heart rate: one of the heaviest signals. The number still holds, with less precision."
    }

    // MARK: - Empty-state coverage

    private struct Factor { let key: String; let label: LocalizedStringKey; let reason: LocalizedStringKey }
    private static let factorChecklist: [Factor] = [
        .init(key: "rhr",         label: "Nighttime resting HR", reason: "needs nights"),
        .init(key: "sleep",       label: "Sleep",               reason: "needs nights"),
        .init(key: "consistency", label: "Sleep regularity",    reason: "needs nights"),
        .init(key: "hrv",         label: "HRV",                 reason: "needs valid nights"),
        .init(key: "steps",       label: "Steps",               reason: "connect Apple Health"),
    ]
    private var presentFactors: Set<String> {
        var s = Set<String>()
        if inputs.restingHR != nil { s.insert("rhr") }
        if inputs.sleepHours != nil { s.insert("sleep") }
        if inputs.sleepConsistency != nil { s.insert("consistency") }
        if inputs.rmssd != nil { s.insert("hrv") }
        if inputs.steps != nil { s.insert("steps") }
        return s
    }

    // MARK: - Shared helpers (also used by the Cuerpo row)

    /// The hero / marker / row tint, driven by the SIGN of the delta (younger → green, at-your-age →
    /// ink, older → amber, far-older → red). Mirrors how Recovery/Stress tint their numeral.
    static func tint(forDelta deltaYears: Double, theme: InstrumentoTheme) -> Color {
        if deltaYears > 0.5 { return theme.dataRecovery }
        if deltaYears >= -0.5 { return theme.ink }
        if deltaYears >= -8 { return theme.warning }
        return theme.critical
    }

    /// Map the engine contributions to diverging bars (years, ordered by weight, localized short labels
    /// + spoken accessibility value).
    static func bars(_ contribs: [VitalityEngine.Contribution]) -> [ContributionBars.Item] {
        contribs
            .map { ContributionBars.Item(label: shortLabel(for: $0.key), years: $0.years,
                                         accessibilityValue: barAccessibility($0.years)) }
            .sorted { abs($0.years) > abs($1.years) }
    }

    /// Localized spoken value for one contribution bar.
    private static func barAccessibility(_ years: Double) -> String {
        let mag = String(format: "%.1f", abs(years))
        if years < -0.05 { return String(localized: "rejuvenates you by \(mag) years") }
        if years > 0.05 { return String(localized: "ages you by \(mag) years") }
        return String(localized: "neutral")
    }

    /// Localized spoken value for the band (numbers only, three sign branches).
    private static func bandAccessibility(_ r: VitalityEngine.Result) -> String {
        let body = Int(r.bodyAge.rounded()), chrono = Int(r.chronoAge.rounded())
        let d = Int(r.deltaYears.rounded())
        let lo = Int((r.bodyAge - r.bandYears).rounded()), hi = Int((r.bodyAge + r.bandYears).rounded())
        // Announce reduced confidence first, so VoiceOver users hear it before the number (FER-643).
        let prefix = r.isPartialEstimate ? String(localized: "Partial estimate. ") : ""
        if d > 0 { return prefix + String(localized: "Body age \(body), \(d) years younger than your age \(chrono); estimated range \(lo) to \(hi)") }
        if d < 0 { return prefix + String(localized: "Body age \(body), \(-d) years older than your age \(chrono); estimated range \(lo) to \(hi)") }
        return prefix + String(localized: "Body age \(body), at your age \(chrono); estimated range \(lo) to \(hi)")
    }

    private static func shortLabel(for key: String) -> String {
        switch key {
        case "rhr":         return String(localized: "Resting HR")
        case "vo2max":      return String(localized: "VO₂max")
        case "sleep":       return String(localized: "Sleep")
        case "consistency": return String(localized: "Regularity")
        case "hrv":         return String(localized: "HRV")
        case "steps":       return String(localized: "Steps")
        default:            return key
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("BodyAgeSheet: con datos") {
    let inputs = VitalityInputsBuilder.build(.init(
        chronoAge: 34,
        nightlyRestingHR: Array(repeating: 54, count: 10),
        nightlyRMSSD: Array(repeating: 48, count: 10),
        nightlySleepHours: Array(repeating: 7.2, count: 10),
        dailySteps: Array(repeating: 8200, count: 10)))
    return Color.clear.sheet(isPresented: .constant(true)) {
        BodyAgeSheet(result: VitalityEngine.compute(inputs), inputs: inputs)
    }
}

#Preview("BodyAgeSheet: estimación parcial (solo Apple)") {
    // No band → no nocturnal RHR and HRV gated out; only sleep, regularity and steps remain → the
    // reading computes but flags «Partial estimate» (FER-643).
    let inputs = VitalityInputsBuilder.build(.init(
        chronoAge: 34,
        nightlySleepHours: Array(repeating: 7.2, count: 10),
        dailySteps: Array(repeating: 8200, count: 10)))
    return Color.clear.sheet(isPresented: .constant(true)) {
        BodyAgeSheet(result: VitalityEngine.compute(inputs), inputs: inputs)
    }
}

#Preview("BodyAgeSheet: sin señales") {
    let inputs = VitalityInputsBuilder.build(.init(chronoAge: 34, nightlyRestingHR: [55, 56]))
    return Color.clear.sheet(isPresented: .constant(true)) {
        BodyAgeSheet(result: VitalityEngine.compute(inputs), inputs: inputs)
    }
}
#endif
#endif
