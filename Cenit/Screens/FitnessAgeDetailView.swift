#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Fitness Age detail (FER-141)
//
// The light «Instrumento diurno» sheet you reach by tapping the «Edad física» row in Cuerpo. It
// presents the headline number honestly in all three states the engine distinguishes:
//
//   • ready / estimate — the dominant numeral (tinted by DIRECTION: verde when younger, ámbar when
//     older, ink when even), the delta vs chronological age, the ±band, an inviolable "fitness
//     comparison, not a diagnosis" disclaimer, the two levers that move it (resting HR · activity),
//     a transparency checklist of what we're using, and the method footnote.
//   • notReady — no made-up number: an honest empty well + the checklist of what's still missing.
//
// Visual vocabulary mirrors `MetricInfoSheet` (surface blocks separated by space, color only on the
// datum, paper background). The theme is passed EXPLICITLY — it does not propagate through `.sheet`.
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
    var vo2Trend: VO2maxTrend.Result? = nil
    /// The raw measured VO₂max series (values only, oldest→newest) behind the trend, for the context line.
    var vo2Series: [Double] = []
    /// The active «Instrumento» theme, passed explicitly (does NOT propagate through `.sheet`).
    var theme: InstrumentoTheme = .base

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let result = snapshot.result {
                    readyBody(result)
                } else {
                    notReadyBody
                }
            }
            .padding(20)
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

    // MARK: - Ready / estimate

    @ViewBuilder private func readyBody(_ result: FitnessAgeResult) -> some View {
        let estimate = snapshot.readiness.confidence == .estimate
        overline(estimate: estimate)
        hero(result)
        disclaimerStrip
        vo2maxSection
        leversSection
        usingSection
        methodFootnote
        // Standardized origin seal (FER-805): fitness age is computed on-device.
        OriginStamp(origin: .computed, when: String(localized: "today"), theme: theme)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    private func overline(estimate: Bool) -> some View {
        // §8.7 header (FER-805): metric icon + ALL-CAPS overline instead of serif.
        HStack(alignment: .center, spacing: 7) {
            MetricOverline(.fitnessAge, "Physical age", theme: theme)
            if estimate { InlineFlagChip("Estimate", color: theme.warning) }
        }
    }

    private func hero(_ result: FitnessAgeResult) -> some View {
        let ageNum = Int(result.fitnessAge.rounded())
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(ageNum)").instrumentoHero(64).foregroundStyle(directionColor(result.direction))
                Text("years").font(StrandFont.title2).foregroundStyle(theme.inkTertiary)
            }
            Text(deltaSubtitle(result))
                .font(StrandFont.subhead).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("An estimate with a ±\(Int(result.bandYears.rounded()))-year margin.")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    /// The inviolable disclaimer — a quiet surface strip, never fine print. Icon is chrome (ink), not
    /// color. Clones `MetricInfoSheet.appleConnectLine`.
    private var disclaimerStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
            Text("It's a comparison of your fitness, not your biological age or a medical diagnosis.")
                .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.control, theme: theme, fill: theme.surface, stroke: theme.hairline, lineWidth: 0.5)
    }

    // MARK: "What moves it" — the two levers (resting HR drives, activity supports)

    // Handoff v2 (reconciliación): «Qué la mueve» en DOS tiles separados (no dos filas en un contenedor).
    private var leversSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What moves it").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .top, spacing: 8) {
                leverTile(icon: "heart", label: "Resting heart rate",
                          note: "The lower it is, the younger.",
                          value: snapshot.restingHR.map { "\(Int($0.rounded()))" } ?? "—",
                          unit: "bpm", hue: theme.dataHeart)
                leverTile(icon: "flame", label: "Recent activity",
                          note: "More active days also bring it down.",
                          value: "\(snapshot.activeDays)", unit: "/ 7 days", hue: theme.dataStrain)
            }
        }
    }

    /// One «what moves it» tile (icon + label · value·unit · note) — the handoff's two-tile layout.
    private func leverTile(icon: String, label: LocalizedStringKey, note: LocalizedStringKey,
                           value: String, unit: LocalizedStringKey, hue: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(StrandFont.glyph(.chevron)).foregroundStyle(hue).frame(width: 16)
                Text(label).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(InstrumentoType.groteskNumber(21)).foregroundStyle(theme.ink)
                Text(unit).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Text(note).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.control, theme: theme, fill: theme.surface)
    }

    // MARK: "What we're using" — transparency checklist (drivesAge items only; VO₂max is out of scope)

    private var usingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What we're using").instrumentoOverline().foregroundStyle(theme.inkTertiary)
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
        }
    }

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

    private var methodFootnote: some View {
        Text("Based on the Nes/HUNT model (2011): it estimates your aerobic capacity from your resting heart rate and activity, and compares it with the average for your age.")
            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Not ready (no number — an honest empty state)

    @ViewBuilder private var notReadyBody: some View {
        Text("Physical age").instrumentoOverline().foregroundStyle(theme.inkTertiary)
        VStack(spacing: 10) {
            Image(systemName: "hourglass").font(StrandFont.glyph(.lead)).foregroundStyle(theme.inkTertiary)
            Text("We can't calculate your physical age yet.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
        .instrumentoCard(.control, theme: theme, fill: theme.surface)

        VStack(alignment: .leading, spacing: 8) {
            Text("What we need").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(spacing: 0) {
                usingRow(status: profileStatus, label: "Age and sex", detail: ageSexDetail)
                Divider().overlay(theme.hairline).padding(.leading, 38)
                usingRow(status: status("rhr"), label: "Resting heart rate",
                         detail: "\(snapshot.rhrNights) of 4 nights needed")
            }
            .instrumentoCard(.control, theme: theme, fill: theme.surface)
            Text("Keep wearing your band overnight and this fills in on its own.")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        disclaimerStrip
        vo2maxSection
    }

    // MARK: - VO₂max (Apple Health, measured · FER-215)

    /// Apple's MEASURED VO₂max, as a complementary source-labeled block. Independent of the Nes Fitness
    /// Age. Hidden entirely when there's no reading and Apple Health is already connected.
    @ViewBuilder private var vo2maxSection: some View {
        if let vo2 = appleVO2max {
            vo2maxCard(vo2)
        } else if appleConnectHint {
            vo2maxConnectNudge
        }
        if let trend = vo2Trend {
            vo2TrendBlock(trend)
        }
    }

    // MARK: - VO₂max · tendencia (FER-833) — la trayectoria, no el punto

    /// The «VO₂max · tendencia» block: the direction word as the coloured datum (subordinate to the age
    /// hero), the raw measured series as a quiet context line, and honest copy. Direction, never a
    /// longevity claim. Rendered only when the trend cleared its data minimum. (FER-833)
    @ViewBuilder private func vo2TrendBlock(_ trend: VO2maxTrend.Result) -> some View {
        let color = trendColor(trend.direction)
        VStack(alignment: .leading, spacing: 12) {
            Text("VO₂max · trend").instrumentoOverline().foregroundStyle(theme.inkTertiary)

            HStack(spacing: 8) {
                Image(systemName: trendSymbol(trend.direction))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(color)
                Text(trendWord(trend.direction))
                    .font(StrandFont.number(30, weight: .semibold))
                    .foregroundStyle(color)
            }

            if vo2Series.count >= 2 {
                Sparkline(values: vo2Series,
                          gradient: Gradient(colors: [theme.inkMuted, theme.inkMuted]),
                          lineWidth: 2, showsArea: false, showsHead: false, showsScrub: false)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }

            Text("We show you the direction, not an exact number — the estimate jumps day to day, the trend is more honest.")
                .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.control, theme: theme, fill: theme.surface, stroke: theme.hairline, lineWidth: 0.5)
    }

    private func trendColor(_ dir: VO2maxTrend.Direction) -> Color {
        switch dir {
        case .rising:  return theme.dataRecovery   // verde — mejora
        case .falling: return theme.critical        // rojo ladrillo — baja
        case .stable:  return theme.ink             // sin color — sin cambio distinguible
        }
    }

    private func trendSymbol(_ dir: VO2maxTrend.Direction) -> String {
        switch dir {
        case .rising:  return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .stable:  return "arrow.right"
        }
    }

    private func trendWord(_ dir: VO2maxTrend.Direction) -> LocalizedStringKey {
        switch dir {
        case .rising:  return "Rising"
        case .falling: return "Falling"
        case .stable:  return "Steady"
        }
    }

    private func vo2maxCard(_ vo2: Double) -> some View {
        let expected = Int(VO2maxReference.expected(age: chronoAge, sex: sex).rounded())
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(verbatim: "VO₂max").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                appleSourceBadge
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "\(Int(vo2.rounded()))")
                    .font(StrandFont.number(28)).foregroundStyle(theme.dataSpO2)
                Text(verbatim: "ml/kg/min").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Text("Measured by your Apple Watch during exercise.")
                .font(StrandFont.subhead).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("The average for your age is around \(expected).")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.control, theme: theme, fill: theme.surface, stroke: theme.hairline, lineWidth: 0.5)
        .accessibilityElement(children: .combine)
    }

    /// Tiny "Apple Health" source chip (heart glyph + label), mirroring the fromApple flag elsewhere.
    private var appleSourceBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill").font(.system(size: 8)) // token-exempt: microtexto <10pt
            Text("Apple Health").textCase(.uppercase)
        }
        .font(.system(size: 8.5, weight: .semibold)).tracking(0.3) // token-exempt: microtexto <10pt
        .foregroundStyle(theme.dataHeart)
        .padding(.horizontal, 4).padding(.vertical, 1)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.dataHeart.opacity(0.4), lineWidth: 1)) // token-exempt: geometría de dato (radio 4) + opacidad 0.40 fuera de banda
    }

    /// No Apple reading + not connected: a quiet, no-number invite (mirrors MetricInfoSheet's
    /// appleConnectLine). No action button — connecting lives in Today / Settings.
    private var vo2maxConnectNudge: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "VO₂max").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "heart.fill").font(StrandFont.glyph(.chevron)).foregroundStyle(theme.dataHeart)
                Text("Connect Apple Health to see your VO₂max.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .instrumentoCard(.control, theme: theme, fill: theme.surface, stroke: theme.hairline, lineWidth: 0.5)
        }
    }

    // MARK: - Direction + copy

    private func directionColor(_ dir: FitnessAgeResult.Direction) -> Color {
        switch dir {
        case .younger: return theme.dataRecovery   // verde
        case .older:   return theme.warning         // ámbar
        case .even:    return theme.ink
        }
    }

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

#Preview("Fitness Age — younger (ready)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FitnessAgeDetailView(snapshot: previewSnapshot(rhr: 50, strainActiveDays: 7, age: 36),
                             chronoAge: 36, sex: "male")
    }
}

#Preview("Fitness Age — older (estimate)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FitnessAgeDetailView(snapshot: previewSnapshot(rhr: 72, strainActiveDays: 4, age: 36),
                             chronoAge: 36, sex: "male")
    }
}

#Preview("Fitness Age — not ready") {
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
