#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - BodyAgeSheet — the «Edad corporal» longevity detail (FER-145)
//
// The light «Instrumento diurno» detail for `VitalityEngine`: Body Age (years) is the hero, tinted by
// the SIGN of the delta (younger → green, at-your-age → ink, older → amber, far-older → red), the
// same hue the Cuerpo row uses. The reading is a RANGE (`BodyAgeBand`, ±5), not a point. Vitality
// 0–100 rides underneath as a quiet context strip — the SAME measure in another scale, never a second
// hero or a toggle (a segmented control would re-materialise the "two ages?" confusion). The breakdown
// is `ContributionBars` ("what's moving it"). A differentiator names how this isn't the cardio-only
// Physical Age (FER-141), and two hard disclaimers keep it non-clinical.
//
// A sibling of `ActivityRecoverySheet` / `MetricInfoSheet` (same warm paper, header, surface blocks,
// disclaimer) — not a `MetricInfo` case nor the vitals `MetricDetailScreen`, because its body is a
// band + diverging bars, not a series chart. The theme is passed explicitly (it does NOT cross the
// `.sheet` environment boundary). With no result yet (< 3 signals) it shows an honest checklist of
// what it's built from instead of a fabricated number.

struct BodyAgeSheet: View {
    /// The computed Body Age + Vitality, or nil when fewer than `minFactors` signals are present.
    let result: VitalityEngine.Result?
    /// The inputs that fed the engine — drives the "what's built from" checklist in the empty state.
    let inputs: VitalityEngine.Inputs
    /// The active «Instrumento diurno» theme, passed explicitly (doesn't cross the `.sheet` boundary).
    var theme: InstrumentoTheme = .base

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Serif title, with a «Partial estimate» flag when a heaviest factor (HRV/RHR) is
                // missing — mirrors Physical age's `Estimate` chip (FER-643). Same warm-amber role.
                // §8.7 header (FER-805): metric icon + ALL-CAPS overline instead of serif.
                HStack(alignment: .center, spacing: 7) {
                    MetricOverline(.bodyAge, "Body age", theme: theme)
                    if result?.isPartialEstimate == true {
                        InlineFlagChip("Partial estimate", color: theme.warning)
                    }
                }
                if let r = result {
                    withData(r)
                    // Standardized origin seal (FER-805): body age is computed on-device.
                    OriginStamp(origin: .computed, when: String(localized: "today"), theme: theme)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                } else { emptyState }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
    }

    // MARK: - With data

    @ViewBuilder
    private func withData(_ r: VitalityEngine.Result) -> some View {
        let tint = Self.tint(forDelta: r.deltaYears, theme: theme)
        let bodyAge = Int(r.bodyAge.rounded())

        // Hero — the one dominant number, coloured by the sign of the delta.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(bodyAge)").instrumentoHero(64).foregroundStyle(tint)
            Text("years").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
        }
        Text(deltaSentence(r)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)

        // Honest confidence when a heaviest factor is absent (FER-643) — the band and number are
        // unchanged, we just name what it's leaning without.
        if r.isPartialEstimate {
            Text(Self.partialCaveat(r)).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        // The reading is the band, not the point.
        BodyAgeBand(bodyAge: r.bodyAge, chronoAge: r.chronoAge, bandYears: r.bandYears, color: tint,
                    youLabel: String(localized: "you"),
                    accessibilityLabelText: String(localized: "Body age"),
                    accessibilityValueText: Self.bandAccessibility(r))
            .padding(.top, 2)
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
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)

        Divider().overlay(theme.hairline).padding(.vertical, 2)

        // What's moving it — the diverging contribution breakdown.
        VStack(alignment: .leading, spacing: 12) {
            Text("What's moving it").font(StrandFont.headline).foregroundStyle(theme.ink)
            ContributionBars(items: Self.bars(r.contributions),
                             leftPole: String(localized: "← rejuvenates you"),
                             rightPole: String(localized: "ages you →"))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        // Differentiator vs the cardio-only Physical Age (FER-141).
        VStack(alignment: .leading, spacing: 4) {
            Text("This isn't your Physical age").font(StrandFont.subhead).foregroundStyle(theme.ink)
            Text("Physical age measures only the cardiorespiratory side. This one also weighs sleep, regularity, HRV and steps — so the two can differ.")
                .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        disclaimers
    }

    // MARK: - Empty (fewer than 3 signals)

    private var emptyState: some View {
        let present = presentFactors
        return VStack(alignment: .leading, spacing: 18) {
            Text("—").instrumentoHero(64).foregroundStyle(theme.inkSecondary)
            Text("I need at least 3 signals to work this out without guessing. You have \(present.count).")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                Text("What it's built from").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .padding(.bottom, 8)
                ForEach(Array(Self.factorChecklist.enumerated()), id: \.offset) { i, f in
                    if i > 0 { Divider().overlay(theme.hairline) }
                    checklistRow(f, ready: present.contains(f.key))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Keep wearing the band a few nights and it appears on its own — we don't show a half-finished number.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            disclaimers
        }
    }

    private func checklistRow(_ f: Factor, ready: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ready ? "checkmark" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(ready ? theme.dataRecovery : theme.inkTertiary)
                .frame(width: 18)
            Text(f.label).font(StrandFont.body).foregroundStyle(ready ? theme.ink : theme.inkSecondary)
            Spacer(minLength: 8)
            Text(ready ? "ready" : f.reason).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var disclaimers: some View {
        Text("A wellness comparison, not a biological age or a clinical diagnosis. HRV is estimated from nighttime PPG; the reference norm is conservative.")
            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
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
            return "Worked out without HRV or resting heart rate — the two heaviest signals. The number still holds, with less precision."
        }
        if noHRV {
            return "Worked out without HRV — one of the heaviest signals. The number still holds, with less precision."
        }
        return "Worked out without resting heart rate — one of the heaviest signals. The number still holds, with less precision."
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
#Preview("BodyAgeSheet — con datos") {
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

#Preview("BodyAgeSheet — estimación parcial (solo Apple)") {
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

#Preview("BodyAgeSheet — sin señales") {
    let inputs = VitalityInputsBuilder.build(.init(chronoAge: 34, nightlyRestingHR: [55, 56]))
    return Color.clear.sheet(isPresented: .constant(true)) {
        BodyAgeSheet(result: VitalityEngine.compute(inputs), inputs: inputs)
    }
}
#endif
#endif
