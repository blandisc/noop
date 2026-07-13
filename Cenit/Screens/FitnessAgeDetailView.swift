#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Fitness Age detail (FER-141)
//
// The light «Instrumento diurno» sheet you reach by tapping the «Edad física» row in Cuerpo. It
// presents the headline number honestly in all three states the engine distinguishes:
//
//   • ready / estimate — HeroInvertido (longevity green) with always-on ESTIMATE capsule, delta +
//     non-clinical disclaimer as the verdict, «What moves it» tiles, measured VO₂max (Apple), and
//     PieMetodo with the transparency checklist + Nes/HUNT method.
//   • notReady — no made-up number: an honest empty well + the checklist of what's still missing.
//
// Esqueleto Final (misma forma que `MetricDetailScreen.narrativeBodyFinal` / `SkinTempDetailScreen`):
// HeroInvertido → SeccionBloque… → PieMetodo. Full-bleed (franjas edge-to-edge). The theme is passed
// EXPLICITLY — it does not propagate through `.sheet`. Math and copy are preserved; this is a reskin.
// The VO₂max block (FER-215) shows Apple Health's MEASURED VO₂max (when present) as a complementary,
// source-labeled datum — it does NOT feed the Nes Fitness Age (that stays the model's own comparison).

struct FitnessAgeDetailView: View {
    let snapshot: FitnessAgeSnapshot
    /// Chronological age + sex from the profile (the snapshot carries the derived values, not these).
    let chronoAge: Int
    let sex: String
    /// VO₂max measured by Apple Health (ml/kg/min), `nil` if none. Independent of the Nes Fitness Age —
    /// a complementary, source-labeled datum. (FER-215)
    var appleVO2max: Double? = nil
    /// When there's no Apple VO₂max AND Apple Health isn't connected → show a quiet connect nudge;
    /// when connected-but-no-reading, the block hides entirely. (FER-215)
    var appleConnectHint: Bool = false
    /// The fitness TRAJECTORY over weeks (rising / stable / falling) from `VO2maxTrend` (FER-679), plus
    /// the raw VO₂max series for the context sparkline. `nil` below the data minimum → block hidden. (FER-833)
    /// Kept on the API so call sites are unchanged; the Final «Edad física» layout does not surface the
    /// trend block (see `vo2TrendBlock` retirement note in the reskin report).
    var vo2Trend: VO2maxTrend.Result? = nil
    /// The raw measured VO₂max series (values only, oldest→newest) behind the trend, for the context line.
    var vo2Series: [Double] = []
    /// The active «Instrumento» theme, passed explicitly (does NOT propagate through `.sheet`).
    var theme: InstrumentoTheme = .base

    @State private var contentHeight: CGFloat = 0

    /// Longevity green for the inverted hero field (`#2E7D57`).
    private var longevityHue: Color { theme.dataRejuvenates }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let result = snapshot.result {
                    readyBody(result)
                } else {
                    notReadyBody
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { g in
                Color.clear.preference(key: FitnessAgeSheetHeightKey.self, value: g.size.height)
            })
        }
        .onPreferenceChange(FitnessAgeSheetHeightKey.self) { contentHeight = $0 }
        .background(theme.paper)
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight)] : [.large])
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
    }

    // MARK: - Ready / estimate (Final skeleton)

    @ViewBuilder private func readyBody(_ result: FitnessAgeResult) -> some View {
        heroFinal(result)
        SeccionBloque(String(localized: "What moves it"), theme: theme) {
            leversFinalContent
        }
        if showsVO2maxSection {
            SeccionBloque(String(localized: "VO₂max"), pista: String(localized: "Apple"), theme: theme) {
                vo2maxFinalContent
            }
        }
        pieMetodoFinal
    }

    // MARK: - Hero Final (HeroInvertido · dataRejuvenates · always-on Estimate capsule)

    private func heroFinal(_ result: FitnessAgeResult) -> some View {
        let ageNum = Int(result.fitnessAge.rounded())
        return HeroInvertido(
            glyph: .fitnessAge,
            title: "Physical age",
            hue: longevityHue,
            theme: theme,
            numeral: {
                HeroNumeral("\(ageNum)", suffix: String(localized: "years"), size: 60, theme: theme) {
                    Text("Estimate")
                        .font(InstrumentoType.grotesk(11, weight: .semibold))
                        .foregroundStyle(theme.paper)
                        .heroCapsule(theme: theme)
                }
            },
            verdict: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(deltaSubtitle(result))
                        .font(InstrumentoType.grotesk(15, weight: .semibold))
                        .foregroundStyle(theme.paper)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("An estimate with a ±\(Int(result.bandYears.rounded()))-year margin.")
                        .font(InstrumentoType.grotesk(14))
                        .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                    // Non-clinical disclaimer lives in the hero reading (moved from disclaimerStrip).
                    Text("It's a comparison of your fitness, not your biological age or a medical diagnosis.")
                        .font(InstrumentoType.grotesk(14))
                        .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        )
    }

    // MARK: - What moves it (QueLaMueveHeader + TileSurface × 2 + BarraAncla)

    private var leversFinalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            QueLaMueveHeader("What moves it", chip: "trend, not cause", theme: theme)
            HStack(alignment: .top, spacing: 8) {
                TileSurface(
                    label: String(localized: "Resting heart rate"),
                    value: snapshot.restingHR.map { "\(Int($0.rounded())) bpm" } ?? "—",
                    valueColor: theme.dataHeart,
                    caption: String(localized: "The lower it is, the younger."),
                    swatch: theme.dataHeart,
                    theme: theme
                )
                TileSurface(
                    label: String(localized: "Recent activity"),
                    value: "\(snapshot.activeDays) / 7 days",
                    valueColor: theme.dataStrain,
                    caption: String(localized: "More active days also bring it down."),
                    swatch: theme.dataStrain,
                    theme: theme
                )
            }
            BarraAncla(String(localized: "Nes/HUNT model (2011)"), color: longevityHue, theme: theme)
        }
    }

    // MARK: - VO₂max (Apple Health, measured · FER-215) — simple SeccionBloque

    private var showsVO2maxSection: Bool {
        appleVO2max != nil || appleConnectHint
    }

    @ViewBuilder private var vo2maxFinalContent: some View {
        if let vo2 = appleVO2max {
            vo2maxSimple(vo2)
        } else if appleConnectHint {
            vo2maxConnectNudgeContent
        }
    }

    private func vo2maxSimple(_ vo2: Double) -> some View {
        let expected = Int(VO2maxReference.expected(age: chronoAge, sex: sex).rounded())
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "\(Int(vo2.rounded()))")
                    .font(InstrumentoType.groteskNumber(28, weight: .bold))
                    .foregroundStyle(theme.dataSpO2)
                Text(verbatim: "ml/kg/min")
                    .font(InstrumentoType.grotesk(13))
                    .foregroundStyle(theme.inkTertiary)
            }
            Text("Measured by your Apple Watch during exercise.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            BarraAncla(
                String(localized: "The average for your age is around \(expected)."),
                color: theme.dataSpO2,
                theme: theme
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// No Apple reading + not connected: a quiet, no-number invite. No action button — connecting lives in Today / Settings.
    private var vo2maxConnectNudgeContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StrandIcon.heart.image
                .font(StrandFont.glyph(.chevron))
                .foregroundStyle(theme.dataHeart)
            Text("Connect Apple Health to see your VO₂max.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - PieMetodo (checklist + disclaimer + Nes/HUNT prose + origin seal)

    @ViewBuilder private var pieMetodoFinal: some View {
        PieMetodo(theme: theme) {
            Metodo(title: String(localized: "How it's calculated"), theme: theme) {
                VStack(alignment: .leading, spacing: 12) {
                    // Transparency checklist (was usingSection) — preserved verbatim inside method.
                    Text("What we're using")
                        .font(InstrumentoType.grotesk(10, weight: .semibold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.inkTertiary)
                    VStack(spacing: 0) {
                        usingRow(status: profileStatus, label: "Age and sex", detail: ageSexDetail)
                        Divider().overlay(theme.hairline).padding(.leading, 38)
                        usingRow(status: status("rhr"), label: "Resting heart rate",
                                 detail: "\(snapshot.rhrNights) of 7 nights")
                        Divider().overlay(theme.hairline).padding(.leading, 38)
                        usingRow(status: status("activity"), label: "Recent activity",
                                 detail: "\(snapshot.activeDays) of 7 days")
                    }
                    .instrumentoCard(.control, theme: theme, fill: theme.surface)

                    Text("Based on the Nes/HUNT model (2011): it estimates your aerobic capacity from your resting heart rate and activity, and compares it with the average for your age.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    // disclaimerStrip content (moved into method for calculation transparency).
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        StrandIcon.info.image
                            .font(StrandFont.glyph(.chevron))
                            .foregroundStyle(theme.inkTertiary)
                        Text("It's a comparison of your fitness, not your biological age or a medical diagnosis.")
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } sello: {
            OriginStamp(origin: .computed, when: String(localized: "today"), theme: theme)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    // MARK: - Not ready (no number — honest empty state, Final wrappers)

    @ViewBuilder private var notReadyBody: some View {
        HeroInvertido(
            glyph: .fitnessAge,
            title: "Physical age",
            hue: longevityHue,
            theme: theme,
            numeral: {
                Text(verbatim: "—")
                    .font(InstrumentoType.groteskNumber(60, weight: .bold))
                    .tracking(-2)
                    .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
            },
            verdict: {
                Text("We can't calculate your physical age yet.")
                    .font(InstrumentoType.grotesk(15, weight: .semibold))
                    .foregroundStyle(theme.paper)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )

        SeccionBloque(String(localized: "What we need"), theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 0) {
                    usingRow(status: profileStatus, label: "Age and sex", detail: ageSexDetail)
                    Divider().overlay(theme.hairline).padding(.leading, 38)
                    usingRow(status: status("rhr"), label: "Resting heart rate",
                             detail: "\(snapshot.rhrNights) of 4 nights needed")
                }
                .instrumentoCard(.control, theme: theme, fill: theme.surface)
                Text("Keep wearing your band overnight and this fills in on its own.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if showsVO2maxSection {
            SeccionBloque(String(localized: "VO₂max"), pista: String(localized: "Apple"), theme: theme) {
                vo2maxFinalContent
            }
        }

        pieMetodoFinal
    }

    // MARK: - Checklist rows (shared ready / not-ready / method)

    private func usingRow(status: FitnessReadinessStatus, label: LocalizedStringKey,
                          detail: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon(status)).font(StrandFont.glyph(.inline))
                .foregroundStyle(statusColor(status)).frame(width: 20)
            Text(label).font(StrandFont.subhead).foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            Text(detail).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Direction + copy

    private func deltaSubtitle(_ result: FitnessAgeResult) -> LocalizedStringKey {
        let yrs = Int(abs(result.deltaYears).rounded())
        switch result.direction {
        case .younger: return "\(yrs) years younger than your age of \(chronoAge)."
        case .older:   return "\(yrs) years above your age of \(chronoAge)."
        case .even:    return "Right at your age of \(chronoAge)."
        }
    }

    // MARK: - Checklist status helpers

    private func status(_ key: String) -> FitnessReadinessStatus {
        snapshot.readiness.items.first { $0.key == key }?.status ?? .missing
    }

    /// Age + sex share one row: both come from the profile, so the row is satisfied unless one is unset.
    private var profileStatus: FitnessReadinessStatus {
        (status("age") == .satisfied && status("sex") == .satisfied) ? .satisfied : .missing
    }

    private var ageSexDetail: LocalizedStringKey {
        switch sex.lowercased() {
        case "female":    return "\(chronoAge), woman"
        case "nonbinary": return "\(chronoAge), non-binary"
        default:          return "\(chronoAge), man"
        }
    }

    private func statusIcon(_ s: FitnessReadinessStatus) -> String {
        switch s {
        case .satisfied: return "checkmark.circle.fill"
        case .partial:   return "circle.lefthalf.filled"
        case .missing:   return "circle"
        }
    }

    private func statusColor(_ s: FitnessReadinessStatus) -> Color {
        switch s {
        case .satisfied: return theme.dataRecovery   // verde = we have it
        case .partial:   return theme.warning         // ámbar = partial
        case .missing:   return theme.inkTertiary     // quiet, no alarm
        }
    }
}

// MARK: - Sheet plumbing (private clones of MetricInfoSheet's, so that file stays untouched)

/// Carries the sheet content's measured natural height up to size the detent to content.
private struct FitnessAgeSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Preview

#if DEBUG
private func previewSnapshot(rhr: Int, strainActiveDays: Int, age: Int, sex: String = "male")
    -> FitnessAgeSnapshot {
    let rhrArr: [Int?] = Array(repeating: rhr, count: 7)
    var strainArr: [Double?] = Array(repeating: nil, count: 7)
    for i in 0..<min(strainActiveDays, 7) { strainArr[i] = 12 }
    return FitnessAgeEngine.snapshot(rhrLast7: rhrArr, strainLast7: strainArr,
                                     age: age, sex: sex, hasHeightWeight: true)
}

#Preview("Fitness Age: younger (ready)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FitnessAgeDetailView(snapshot: previewSnapshot(rhr: 50, strainActiveDays: 7, age: 36),
                             chronoAge: 36, sex: "male")
    }
}

#Preview("Fitness Age: older (estimate)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FitnessAgeDetailView(snapshot: previewSnapshot(rhr: 72, strainActiveDays: 4, age: 36),
                             chronoAge: 36, sex: "male")
    }
}

#Preview("Fitness Age: not ready") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FitnessAgeDetailView(
            snapshot: FitnessAgeEngine.snapshot(
                rhrLast7: [50, 52] + Array(repeating: nil, count: 5),
                strainLast7: Array(repeating: nil, count: 7),
                age: 36, sex: "male", hasHeightWeight: false),
            chronoAge: 36, sex: "male")
    }
}
#endif
#endif
