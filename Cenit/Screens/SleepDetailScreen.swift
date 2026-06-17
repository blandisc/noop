#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - SleepDetailScreen — el «Detalle de Sueño» en lenguaje «Instrumento» (FER-212)
//
// Hermana de `MetricDetailScreen` (FER-185): REUSA su lenguaje visual (el scaffold `block(title:)`, el
// patrón `hero`, `theme: InstrumentoTheme` explícito, `SheetPaperBackground`, `ScrollView`→`VStack`,
// `methodDisclosure`) pero con su propio modelo rico. REEMPLAZA la vieja pantalla de sueño oscura (ya
// retirada) y es un SUPERSET de ella + un bloque NUEVO de regularidad del horario.
//
// NO extiende `MetricDetailScreen`/`MetricDetailSpec` (esos son para vitales de serie única). Se presenta
// desde Cuerpo vía `.sheet(item:)` con el tema vivo del landing pasado EXPLÍCITO (no propaga por `.sheet`,
// FER-162) y SIN `NavigationStack` anidado (un stack anidado cruzando el path de la tab crasheaba SwiftUI,
// FER-171).
//
// Las 8 secciones (orden exacto): 1) Hero · 2) Anoche (hipnograma + etapas en %) · 3) Regularidad del
// horario (destacado, `SleepRegularity`) · 4) Anoche vs lo típico (por etapa, en %) · 5) Tendencia de
// duración (`TrendChart` 30d + deuda) · 6) Métricas de la noche (grid) · 7) Ver el método · 8) Footer.
//
// La ciencia por métrica está documentada en `sleep-detail-science` (memoria): regularidad = SD del
// punto medio (Windred 2024) > duración; etapas en % aproximadas (Miller 2020); una sola suficiencia +
// faltante en horas; la deuda no se salda con una sola noche.

/// Light «Instrumento» Detalle de Sueño. Built once from a `SleepDetailModel` (the caller injects the
/// model so the screen stays DB-free), themed explicitly for the sheet boundary.
struct SleepDetailScreen: View {
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    /// Everything the screen draws, derived ONCE by the caller from `repo` (no DB access here).
    let model: SleepDetailModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let night = model.night {
                    hero(night)
                    blockDivider
                    lastNightBlock(night)
                    blockDivider
                    regularityBlock
                    blockDivider
                    stagesVsTypicalBlock(night)
                    blockDivider
                    durationTrendBlock
                    blockDivider
                    nightMetricsBlock(night)
                    blockDivider
                    methodDisclosure
                    sourceFooter
                } else {
                    emptyState
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .modifier(SleepSheetPaperBackground(paper: theme.paper))
    }

    /// A subtle 1px rule between blocks (token-only, no hex). Mirrors MetricDetailScreen's `blockDivider`.
    private var blockDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    // MARK: - 1. Hero — horas dormidas anoche

    @ViewBuilder
    private func hero(_ night: SleepDetailModel.Night) -> some View {
        let s = night.stages
        VStack(alignment: .leading, spacing: 6) {
            Text("Sleep").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(hoursOnly(s.asleep)).instrumentoHero(44).foregroundStyle(theme.dataSleep)
                Text("h asleep").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
            }
            Text(heroContext(night))
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "0:48 – 7:12 · 92% efficiency" for a strap night; "from Apple Health" when there's no real clock.
    private func heroContext(_ night: SleepDetailModel.Night) -> LocalizedStringKey {
        if model.isAppleHealth {
            return "\(night.dateLabel) · from Apple Health"
        }
        if let eff = efficiencyPct(night) {
            return "\(night.onsetText) – \(night.wakeText) · \(Int(eff.rounded()))% efficiency"
        }
        return "\(night.onsetText) – \(night.wakeText)"
    }

    // MARK: - 2. Anoche — hipnograma + etapas en %

    @ViewBuilder
    private func lastNightBlock(_ night: SleepDetailModel.Night) -> some View {
        let s = night.stages
        block(title: "Last night") {
            VStack(alignment: .leading, spacing: 14) {
                if model.intervals.count >= 2 {
                    Hypnogram(intervals: model.intervals,
                              height: 150,
                              showsStageAxis: true,
                              showsHover: false,
                              nightStart: night.onsetDate)
                } else {
                    // Apple Health / no per-epoch timeline → proportional stacked bar.
                    stageBar(s)
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(theme.dataSpO2)
                        Text("Apple Health").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                }
                // Stage breakdown in PERCENT (not exact minutes — wrist staging is ~2/3 accurate).
                stagePercents(s)
                Text("Approximate stages")
                    .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Proportions, not minutes — the watch gets about 2 of 3 stages right.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Full-width proportional stacked stage bar (fallback when there are no epoch segments).
    @ViewBuilder
    private func stageBar(_ s: SleepDetailModel.Stages) -> some View {
        let total = max(1, s.total)
        GeometryReader { geo in
            HStack(spacing: 2) {
                stageSegment(.deep, s.deep, total, geo.size.width)
                stageSegment(.light, s.light, total, geo.size.width)
                stageSegment(.rem, s.rem, total, geo.size.width)
                stageSegment(.awake, s.awake, total, geo.size.width)
            }
        }
        .frame(height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep stages: deep \(pct(s.deep, s.total)) percent, light \(pct(s.light, s.total)) percent, REM \(pct(s.rem, s.total)) percent, awake \(pct(s.awake, s.total)) percent"))
    }

    @ViewBuilder
    private func stageSegment(_ stage: SleepStage, _ minutes: Double, _ total: Double, _ width: CGFloat) -> some View {
        Rectangle()
            .fill(StrandPalette.sleepStageColor(stage))
            .frame(width: max(0, CGFloat(minutes / total) * width))
    }

    /// REM / Deep / Light / Awake as a row of "color dot · LABEL · NN%" — percentages, never minutes.
    @ViewBuilder
    private func stagePercents(_ s: SleepDetailModel.Stages) -> some View {
        HStack(alignment: .top, spacing: 0) {
            stagePercentCell(.rem, "REM", s.rem, s.total)
            Spacer(minLength: 0)
            stagePercentCell(.deep, "Deep", s.deep, s.total)
            Spacer(minLength: 0)
            stagePercentCell(.light, "Light", s.light, s.total)
            Spacer(minLength: 0)
            stagePercentCell(.awake, "Awake", s.awake, s.total)
        }
    }

    @ViewBuilder
    private func stagePercentCell(_ stage: SleepStage, _ label: LocalizedStringKey, _ minutes: Double, _ total: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(StrandPalette.sleepStageColor(stage))
                    .frame(width: 8, height: 8)
                Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
            Text("\(pct(minutes, total))%")
                .font(StrandFont.bodyNumber)
                .foregroundStyle(theme.ink)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 3. Regularidad del horario (destacado, en surface)

    @ViewBuilder
    private var regularityBlock: some View {
        block(title: "Schedule regularity") {
            VStack(alignment: .leading, spacing: 8) {
                if let r = model.regularity {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(r.score)").font(StrandFont.number(30)).foregroundStyle(theme.dataSleep)
                        Text("/100").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                        Spacer(minLength: 8)
                        Text(regularityWord(r.score))
                            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    }
                    Text("How alike your mid-sleep point is night to night — it predicts your health better than total hours.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let shift = r.weekendShiftMinutes, shift >= 1 {
                        Divider().overlay(theme.hairline)
                        HStack(alignment: .firstTextBaseline) {
                            Text("Weekend shift").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                            Spacer()
                            Text(weekendShiftText(shift))
                                .font(StrandFont.captionNumber)
                                .foregroundStyle(theme.inkSecondary)
                        }
                    }
                    if r.preliminary {
                        Text("Still settling")
                            .font(StrandFont.footnote)
                            .foregroundStyle(theme.warning)
                    }
                } else {
                    // < minNights timing nights: honest calibration, no fake number.
                    let missing = max(0, SleepRegularity.minNights - model.regularityNights)
                    Text("Settling in · \(missing) nights to go")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(theme.inkSecondary)
                    Text("How alike your mid-sleep point is night to night — it predicts your health better than total hours.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 4. Anoche vs lo típico (por etapa, en %)

    @ViewBuilder
    private func stagesVsTypicalBlock(_ night: SleepDetailModel.Night) -> some View {
        let s = night.stages
        block(title: "Last night vs your typical") {
            VStack(alignment: .leading, spacing: 14) {
                stageVsTypicalRow("Deep", lastMin: s.deep, total: s.total,
                                  typicalPct: model.typicalDeepPct, color: StrandPalette.sleepDeep)
                Divider().overlay(theme.hairline)
                stageVsTypicalRow("REM", lastMin: s.rem, total: s.total,
                                  typicalPct: model.typicalRemPct, color: StrandPalette.sleepREM)
                Divider().overlay(theme.hairline)
                stageVsTypicalRow("Light", lastMin: s.light, total: s.total,
                                  typicalPct: model.typicalLightPct, color: StrandPalette.sleepLight)
            }
        }
    }

    /// One stage as a % of last night, with the delta in points vs the typical and a bar carrying a
    /// marker at the personal average. Everything is in PERCENT (porting `stageRow` to Instrumento + %).
    @ViewBuilder
    private func stageVsTypicalRow(_ label: LocalizedStringKey, lastMin: Double, total: Double,
                                   typicalPct: Double?, color: Color) -> some View {
        let lastPct = total > 0 ? lastMin / total * 100 : 0
        // Scale against a shared per-row max so the marker reads meaningfully.
        let scaleMax = max(lastPct, typicalPct ?? 0) * 1.18
        let denom = scaleMax > 0 ? scaleMax : 1
        let deltaText: LocalizedStringKey? = {
            guard let typicalPct else { return nil }
            let diff = Int((lastPct - typicalPct).rounded())
            // Two explicit signed keys so each localizes cleanly (no "%@%lld pts" nested-sign key).
            return diff >= 0 ? "+\(abs(diff)) pts" : "−\(abs(diff)) pts"
        }()
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("\(Int(lastPct.rounded()))%")
                    .font(StrandFont.captionNumber).foregroundStyle(theme.ink)
                if let deltaText {
                    Text(deltaText)
                        .font(StrandFont.footnote)
                        .foregroundStyle(lastPct >= (typicalPct ?? lastPct) ? theme.verdict : theme.warning)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous).fill(theme.hairline)
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: w * CGFloat(min(1, lastPct / denom)))
                    if let typicalPct, typicalPct > 0 {
                        Rectangle()
                            .fill(theme.ink)
                            .frame(width: 2, height: 14)
                            .position(x: w * CGFloat(min(1, typicalPct / denom)), y: 5)
                    }
                }
            }
            .frame(height: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stageAccessibilityLabel(label, lastPct: lastPct, typicalPct: typicalPct))
        }
    }

    /// VoiceOver label for a stage row: "{stage}, {last}% last night" plus a "typical {x}%" clause when
    /// there's a personal average. Two clean keys (no nested optional interpolation).
    private func stageAccessibilityLabel(_ label: LocalizedStringKey, lastPct: Double, typicalPct: Double?) -> Text {
        let head = Text("\(Text(label)), \(Int(lastPct.rounded()))% last night")
        guard let typicalPct else { return head }
        return head + Text(", typical \(Int(typicalPct.rounded()))%")
    }

    // MARK: - 5. Tendencia de duración (30d + banda objetivo + deuda)

    @ViewBuilder
    private var durationTrendBlock: some View {
        let pts = model.trendPoints
        block(title: "Duration trend") {
            VStack(alignment: .leading, spacing: 10) {
                if pts.count >= 2 {
                    TrendChart(
                        points: pts,
                        gradient: Gradient(colors: [theme.dataSleep.opacity(0.5), theme.dataSleep]),
                        valueRange: trendRange(pts),
                        showsArea: true,
                        height: 200,
                        showsHover: true,
                        valueFormat: { String(format: "%.1f h", $0) },
                        axisLabelColor: theme.inkTertiary,
                        gridLineColor: theme.hairline
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text("Hours asleep per night, last 30 days"))
                    Text("Hours asleep per night · target band 7–9 h.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.inkTertiary)
                    durationStats(pts)
                } else {
                    emptyWell(text: "Not enough nights yet to draw a trend.")
                }
                if let debt = model.weeklyDebtMinutes, debt >= 15 {
                    Divider().overlay(theme.hairline)
                    Text("\(debtText(debt)) this week · one good night won't clear it.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Avg · Min · Max · Nights, in hours — ported from the old sleep screen's ChartFooter to Instrumento ink.
    @ViewBuilder
    private func durationStats(_ pts: [TrendPoint]) -> some View {
        let vals = pts.map(\.value)
        let avg = vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        HStack(alignment: .top) {
            statCell("Avg", avg.map { String(format: "%.1f h", $0) } ?? "—")
            Spacer()
            statCell("Min", vals.min().map { String(format: "%.1f h", $0) } ?? "—")
            Spacer()
            statCell("Max", vals.max().map { String(format: "%.1f h", $0) } ?? "—")
            Spacer()
            statCell("Nights", "\(pts.count)")
        }
    }

    private func statCell(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).textCase(.uppercase)
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Text(value).font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
        }
    }

    // MARK: - 6. Métricas de la noche (grid 2-col)

    @ViewBuilder
    private func nightMetricsBlock(_ night: SleepDetailModel.Night) -> some View {
        block(title: "Tonight's metrics") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      alignment: .leading, spacing: 12) {
                // Performance: asleep / need, capped at 100%, with the shortfall in real hours.
                metricTile(
                    label: "Performance",
                    value: model.performancePct.map { "\(Int(min(100, $0).rounded()))%" } ?? "—",
                    caption: performanceCaption,
                    color: model.performancePct != nil ? theme.dataSleep : theme.inkTertiary)
                metricTile(
                    label: "Efficiency",
                    value: efficiencyPct(night).map { "\(Int($0.rounded()))%" } ?? "—",
                    caption: "vs time in bed",
                    color: efficiencyPct(night) != nil ? theme.dataSleep : theme.inkTertiary)
                // Restorative = (deep + REM) / asleep, the literal WHOOP definition.
                metricTile(
                    label: "Restorative",
                    value: restorativePct(night.stages).map { "\(Int($0.rounded()))%" } ?? "—",
                    caption: "Deep + REM",
                    color: restorativePct(night.stages) != nil ? theme.dataSleep : theme.inkTertiary)
                // Latency: the cache carries no onset-latency, so omit the tile rather than show a permanent "—".
                if let latency = model.latencyMin {
                    metricTile(
                        label: "Latency",
                        value: "\(Int(latency.rounded())) min",
                        caption: "10–20 healthy",
                        color: theme.dataSleep)
                }
                metricTile(
                    label: "Respiration",
                    value: night.respRate.map { String(format: "%.1f", $0) } ?? "—",
                    caption: "rpm",
                    color: night.respRate != nil ? theme.dataSpO2 : theme.inkTertiary)
                metricTile(
                    label: "Awakenings",
                    value: model.awakenings.map { "\($0)" } ?? "—",
                    caption: "times",
                    color: model.awakenings != nil ? theme.dataSleep : theme.inkTertiary)
            }
        }
    }

    /// One metric tile in Instrumento: label overline · value in its data hue · quiet caption. Never the
    /// dark `StatTile`; surface + hairline like the Cuerpo tiles.
    private func metricTile(label: LocalizedStringKey, value: String,
                            caption: LocalizedStringKey, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(value).font(StrandFont.number(22)).foregroundStyle(color)
            Text(caption).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 7. Ver el método (DisclosureGroup, patrón de MetricDetailScreen)

    @State private var methodExpanded = false

    private var methodDisclosure: some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                Text("Regularity is the night-to-night variability of your mid-sleep point (the midpoint between falling asleep and waking) — a steadier schedule predicts health more strongly than how long you sleep. Stages are estimated from movement, heart rate and HRV, so they're approximate; deep sleep repairs the body, REM consolidates memory and emotion. \"Need\" is a 7–9 h population target, not a measurement of you.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Windred et al., Sleep 2024 (regularity); Miller et al., J Sports Sci 2020 (wrist staging vs PSG); Hirshkowitz et al., 2015 (sleep need).")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("See the method")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
        }
        .tint(theme.inkTertiary)
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 8. Footer de fuente

    private var sourceFooter: some View {
        Text(model.isAppleHealth ? "Source · Apple Health" : "Source · your strap, on device")
            .font(StrandFont.footnote)
            .foregroundStyle(theme.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    // MARK: - Empty state (ported from the old sleep screen)

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("—").instrumentoHero(44).foregroundStyle(theme.inkTertiary)
            Text(model.loaded
                 ? "No nights yet. Import your WHOOP export — or connect Apple Health — in Data Sources to see your sleep stages and trends. Or wear the strap to bed and open it again after the strap syncs."
                 : "Loading your sleep history…")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shared block scaffold + wells (mirrors MetricDetailScreen)

    /// A titled block on the paper: a quiet overline + content (no card-in-card; surface used sparingly).
    @ViewBuilder
    private func block<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyWell(text: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 22))
                .foregroundStyle(theme.inkTertiary)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Formatting helpers

    private func pct(_ minutes: Double, _ total: Double) -> Int {
        total > 0 ? Int((minutes / total * 100).rounded()) : 0
    }

    /// Hours-and-minutes as a hero figure ("7:24") so the dominant numeral reads like a clock read-out.
    private func hoursOnly(_ minutes: Double) -> String {
        let m = Swift.max(0, Int(minutes.rounded()))
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    private func regularityWord(_ score: Int) -> LocalizedStringKey {
        switch score {
        case 80...:  return "very regular"
        case 55..<80: return "regular"
        default:     return "variable"
        }
    }

    /// A minutes count as a compact duration: "1h 20m" past the hour, "45 min" under it.
    private func hoursMinutes(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min"
    }

    /// "+1h 20m later" / "+45 min later" — the weekend's mid-sleep lag vs weekdays.
    private func weekendShiftText(_ minutes: Double) -> LocalizedStringKey {
        "+\(hoursMinutes(minutes)) later"
    }

    private var performanceCaption: LocalizedStringKey {
        guard let missing = model.shortfallMinutes, missing >= 5 else { return "vs your need" }
        return "−\(hoursMinutes(missing)) vs your need"
    }

    private func debtText(_ minutes: Double) -> LocalizedStringKey {
        "−\(hoursMinutes(minutes))"
    }

    /// Restorative % = (deep + REM) / asleep — the share of the night that does the work.
    private func restorativePct(_ s: SleepDetailModel.Stages) -> Double? {
        guard s.asleep > 0 else { return nil }
        return (s.deep + s.rem) / s.asleep * 100
    }

    /// Efficiency in percent. Prefer the stored session value, else asleep / time-in-bed.
    private func efficiencyPct(_ night: SleepDetailModel.Night) -> Double? {
        if let stored = night.efficiency {
            return stored <= 1.0 ? stored * 100 : stored
        }
        let bed = night.stages.total
        guard bed > 0 else { return nil }
        return Swift.min(100, night.stages.asleep / bed * 100)
    }

    private func trendRange(_ pts: [TrendPoint]) -> ClosedRange<Double> {
        let vals = pts.map(\.value)
        let lo = Swift.max(0, (vals.min() ?? 0) - 1)
        let hi = (vals.max() ?? 9) + 1
        return lo...Swift.max(hi, lo + 1)
    }
}

// MARK: - Sheet paper background (iOS 16.4+ presentationBackground)

private struct SleepSheetPaperBackground: ViewModifier {
    let paper: Color
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(paper)
        } else {
            content
        }
    }
}

// MARK: - SleepDetailModel — every derivation the screen draws, built ONCE from the repo
//
// The data layer of the old dark sleep screen, lifted out of the view and merged with the new
// `SleepRegularity` engine. `SleepDetailScreen` is pure presentation over this; the caller (Cuerpo)
// builds it with `SleepDetailModel.build(...)` so the screen stays DB-free. Stage minutes come from
// `stagesJSON` (imported = dict of minutes; on-device = segment array); the "typical" is the mean over
// `repo.days`; the regularity read is computed from `repo.sleeps`' onset/wake, excluding Apple-only
// nights (which have no real clock).

struct SleepDetailModel {

    struct Stages: Equatable {
        var awake: Double
        var light: Double
        var deep: Double
        var rem: Double
        /// All stages (includes awake) — total time-in-bed minutes.
        var total: Double { awake + light + deep + rem }
        /// Asleep time = total minus awake.
        var asleep: Double { light + deep + rem }
    }

    struct Night: Equatable {
        let startTs: Int
        let endTs: Int
        let efficiency: Double?
        let respRate: Double?
        let stages: Stages

        var onsetDate: Date { Date(timeIntervalSince1970: TimeInterval(startTs)) }
        var onsetText: String { Self.timeFmt.string(from: Date(timeIntervalSince1970: TimeInterval(startTs))) }
        var wakeText: String { Self.timeFmt.string(from: Date(timeIntervalSince1970: TimeInterval(endTs))) }
        var dateLabel: String { Self.dateFmt.string(from: Date(timeIntervalSince1970: TimeInterval(startTs))) }

        private static let timeFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "H:mm"; return f
        }()
        private static let dateFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
        }()
    }

    /// The latest night (strap session preferred, else Apple Health fallback). `nil` → empty state.
    let night: Night?
    /// Stage intervals for the hypnogram (empty for Apple-only → proportional bar).
    let intervals: [SleepInterval]
    /// The night came from Apple Health (no clock, no per-epoch timeline). Hides the onset–wake clock.
    let isAppleHealth: Bool
    /// Whether the repo finished its first load (drives the empty-state copy: loading vs no-data).
    let loaded: Bool

    // Regularity (FER-218 engine)
    let regularity: SleepRegularity.Result?
    /// How many timing nights fed (or would feed) the regularity read — for the "N to go" calibration.
    let regularityNights: Int

    // "Typical" stage shares (percent of asleep, mean over history) for the vs-typical block.
    let typicalDeepPct: Double?
    let typicalRemPct: Double?
    let typicalLightPct: Double?

    // Night metrics
    /// Sleep performance %: imported WHOOP figure when present, else asleep / personal need (capped 100).
    let performancePct: Double?
    /// Need − asleep for last night, in minutes (the "performance" shortfall), floored at 0.
    let shortfallMinutes: Double?
    /// Sleep latency (minutes) — currently nil (the cache carries no onset-latency); shown as "—".
    let latencyMin: Double?
    /// Awakenings count (disturbances) for the latest night.
    let awakenings: Int?

    // Duration trend + debt
    let trendPoints: [TrendPoint]
    /// Accumulated sleep debt over the trailing 7 days, in minutes (sum of per-night need − asleep,
    /// floored per night). `nil` when there's nothing to sum.
    let weeklyDebtMinutes: Double?

    // MARK: - Build

    /// yyyy-MM-dd → Date (en_US_POSIX, UTC).
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Personal sleep need (minutes): mean asleep, never below a 7.5 h floor.
    private static func sleepNeedMin(_ days: [DailyMetric]) -> Double {
        let totals = days.compactMap { $0.totalSleepMin }.filter { $0 > 0 }
        let avg = totals.isEmpty ? nil : totals.reduce(0, +) / Double(totals.count)
        return Swift.max(450, avg ?? 450)   // 450 min = 7.5 h
    }

    /// Build the whole model from the repo's in-memory dashboard. Pure (no DB); call from the caller's
    /// view, once per data change. `appleHealthDays` flags which day rows are Apple-sourced (no clock).
    static func build(days: [DailyMetric],
                      sleeps: [CachedSleepSession],
                      importedSleep: [String: ImportedSleepFigures],
                      appleHealthDays: Set<String>,
                      loaded: Bool) -> SleepDetailModel {
        // --- Latest night: strap session wins, else Apple Health stage minutes (FER-62). ---
        let strap = latestStrapNight(sleeps)
        let night: Night? = strap ?? appleHealthNight(days: days, appleHealthDays: appleHealthDays)
        let isApple = (strap == nil) && (night != nil)
        let intervals: [SleepInterval] = {
            guard !isApple, let s = sleeps.last else { return [] }
            return decodeSegments(s.stagesJSON, sessionStart: s.startTs)?.intervals ?? []
        }()

        // --- Regularity: onset/wake from real strap sessions only (exclude Apple-only nights). ---
        let timing: [SleepRegularity.NightTiming] = sleeps.compactMap { s in
            guard s.endTs > s.startTs else { return nil }   // Apple fallback uses startTs == endTs
            return SleepRegularity.NightTiming(onset: s.startTs, wake: s.endTs)
        }
        let regularity = SleepRegularity.compute(timing)
        // The effective window size the engine would use (so the calibration says "N nights to go").
        let regularityNights = min(timing.count, SleepRegularity.windowNights)

        // --- Typical stage shares (percent of asleep), mean over days that carry all three stages. ---
        var deepPcts: [Double] = [], remPcts: [Double] = [], lightPcts: [Double] = []
        for d in days {
            guard let deep = d.deepMin, let rem = d.remMin, let light = d.lightMin else { continue }
            let asleep = deep + rem + light
            guard asleep > 0 else { continue }
            deepPcts.append(deep / asleep * 100)
            remPcts.append(rem / asleep * 100)
            lightPcts.append(light / asleep * 100)
        }

        // --- Night metrics for the latest night. ---
        let need = sleepNeedMin(days)
        let latestDay = days.last
        let imported = latestDay.flatMap { importedSleep[$0.day] }
        let asleepLast = night?.stages.asleep
        let performancePct: Double? = {
            if let p = imported?.performancePct { return p }
            guard let asleep = asleepLast, asleep > 0, need > 0 else { return nil }
            return Swift.min(100, asleep / need * 100)
        }()
        let shortfall: Double? = {
            guard let asleep = asleepLast, asleep > 0 else { return nil }
            return Swift.max(0, need - asleep)
        }()
        let awakenings = latestDay?.disturbances

        // --- Duration trend (trailing 30 nights, in hours) + 7-day accumulated debt. ---
        let trend = durationTrendPoints(days)
        let weeklyDebt: Double? = {
            let last7 = days.suffix(7)
            let debts = last7.compactMap { d -> Double? in
                if let debt = importedSleep[d.day]?.debtMin { return debt }
                guard let asleep = d.totalSleepMin, asleep > 0, need > 0 else { return nil }
                return Swift.max(0, need - asleep)
            }
            return debts.isEmpty ? nil : debts.reduce(0, +)
        }()

        return SleepDetailModel(
            night: night,
            intervals: intervals,
            isAppleHealth: isApple,
            loaded: loaded,
            regularity: regularity,
            regularityNights: regularityNights,
            typicalDeepPct: mean(deepPcts),
            typicalRemPct: mean(remPcts),
            typicalLightPct: mean(lightPcts),
            performancePct: performancePct,
            shortfallMinutes: shortfall,
            latencyMin: nil,
            awakenings: awakenings,
            trendPoints: trend,
            weeklyDebtMinutes: weeklyDebt)
    }

    // MARK: - Night resolution (ported from the old sleep screen)

    /// The most recent strap sleep, decoded into stage durations + (when on-device) its real timeline.
    private static func latestStrapNight(_ sleeps: [CachedSleepSession]) -> Night? {
        guard let s = sleeps.last, s.endTs > s.startTs else { return nil }
        if let stages = decodeStages(s.stagesJSON), stages.total > 0 {
            return Night(startTs: s.startTs, endTs: s.endTs, efficiency: s.efficiency,
                         respRate: nil, stages: stages)
        }
        if let seg = decodeSegments(s.stagesJSON, sessionStart: s.startTs), seg.stages.total > 0 {
            return Night(startTs: s.startTs, endTs: s.endTs, efficiency: s.efficiency,
                         respRate: nil, stages: seg.stages)
        }
        return nil
    }

    /// Fallback Night from the most recent Apple Health day carrying sleep-stage minutes (FER-62). No
    /// real clock (startTs == endTs at noon-UTC), so the screen draws a proportional bar.
    private static func appleHealthNight(days: [DailyMetric], appleHealthDays: Set<String>) -> Night? {
        guard let d = days.last(where: {
            appleHealthDays.contains($0.day) && ($0.totalSleepMin ?? 0) > 0
        }) else { return nil }
        let deep = d.deepMin ?? 0, rem = d.remMin ?? 0, light = d.lightMin ?? 0
        guard deep + rem + light > 0 else { return nil }
        let stages = Stages(awake: 0, light: light, deep: deep, rem: rem)
        let startTs = Int((dayParser.date(from: d.day) ?? Date()).timeIntervalSince1970) + 12 * 3600
        return Night(startTs: startTs, endTs: startTs, efficiency: d.efficiency,
                     respRate: d.respRateBpm, stages: stages)
    }

    /// Trailing 30 nights of total sleep, in HOURS. Falls back to all nights when the window is sparse.
    private static func durationTrendPoints(_ days: [DailyMetric]) -> [TrendPoint] {
        func build(_ slice: ArraySlice<DailyMetric>) -> [TrendPoint] {
            slice.compactMap { d -> TrendPoint? in
                guard let mins = d.totalSleepMin, mins > 0,
                      let date = dayParser.date(from: d.day) else { return nil }
                return TrendPoint(date: date, value: mins / 60.0)
            }
        }
        let recent = build(days.suffix(30))
        if recent.count >= 2 { return recent }
        return build(days[...])
    }

    // MARK: - Stage decoding (ported from the old sleep screen)

    /// Decode the imported stagesJSON dict of MINUTES {"light","deep","rem","awake"}.
    private static func decodeStages(_ json: String?) -> Stages? {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return nil }
        func val(_ key: String) -> Double {
            if let n = dict[key] as? NSNumber { return n.doubleValue }
            if let d = dict[key] as? Double { return d }
            if let i = dict[key] as? Int { return Double(i) }
            return 0
        }
        let s = Stages(awake: val("awake"), light: val("light"), deep: val("deep"), rem: val("rem"))
        return s.total > 0 ? s : nil
    }

    /// Decode the COMPUTED stagesJSON segment array [{start,end,stage}] into stage totals + the real
    /// timeline (seconds relative to the session start). The on-device SleepStager calls awake "wake".
    private static func decodeSegments(_ json: String?, sessionStart: Int) -> (stages: Stages, intervals: [SleepInterval])? {
        guard let json, let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              !arr.isEmpty else { return nil }
        var stages = Stages(awake: 0, light: 0, deep: 0, rem: 0)
        var intervals: [SleepInterval] = []
        for seg in arr {
            guard let start = (seg["start"] as? NSNumber)?.intValue,
                  let end = (seg["end"] as? NSNumber)?.intValue, end > start,
                  let name = seg["stage"] as? String else { continue }
            let minutes = Double(end - start) / 60.0
            let stage: SleepStage
            switch name {
            case "wake", "awake": stage = .awake; stages.awake += minutes
            case "light": stage = .light; stages.light += minutes
            case "deep": stage = .deep; stages.deep += minutes
            case "rem": stage = .rem; stages.rem += minutes
            default: continue
            }
            intervals.append(SleepInterval(stage: stage,
                                           start: TimeInterval(start - sessionStart),
                                           end: TimeInterval(end - sessionStart)))
        }
        return stages.total > 0 ? (stages, intervals) : nil
    }

    private static func mean(_ vals: [Double]) -> Double? {
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }
}
#endif
