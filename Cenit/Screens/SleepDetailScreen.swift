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

    /// The metric whose info card is open (tap a Tonight's-metrics tile). (FER-227)
    @State private var metricInfo: MetricInfo?
    /// Whether the combined "Sleep stages" explainer card is open (the ⓘ by "Last night"). (FER-227)
    @State private var showStages = false

    var body: some View {
        ScrollView {
            // Rhythm by space: sections breathe on `sectionGap`, with NO rule between them — the
            // hairline only divides WITHIN a group now (DESIGN.md §8: hierarchy by space, not boxes).
            // (FER-227)
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                if let night = model.night {
                    hero(night)
                    lastNightBlock(night)
                    regularityBlock
                    stagesVsTypicalBlock(night)
                    durationTrendBlock
                    weeklyDebtBlock
                    nightMetricsBlock(night)
                    methodDisclosure
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
        // Tap a tile → its MetricInfoSheet; tap the ⓘ by "Last night" → the stages explainer. Both are
        // nested sheets themed EXPLICITLY (the theme doesn't propagate through `.sheet`, FER-162) and
        // with NO nested NavigationStack (FER-171). (FER-227)
        .sheet(item: $metricInfo) { info in
            MetricInfoSheet(info: info, theme: theme, trendLoader: trendLoader(for: info.id))
        }
        .sheet(isPresented: $showStages) {
            SleepStagesInfoSheet(theme: theme)
        }
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
        // The ⓘ opens the combined "what the stages mean" card — it absorbs the old always-visible
        // "Approximate stages / Proportions, not minutes…" caption, decluttering the screen. (FER-227)
        block(title: "Last night", info: { showStages = true }) {
            VStack(alignment: .leading, spacing: 14) {
                if model.intervals.count >= 2 {
                    Hypnogram(intervals: model.intervals,
                              height: 150,
                              showsStageAxis: true,
                              showsHover: true,   // finger-drag scrub → stage + clock range + duration (FER-234)
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
                    if model.excludedNapCount > 0 {
                        Divider().overlay(theme.hairline)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "zzz")
                                .font(StrandFont.footnote)
                                .foregroundStyle(theme.inkTertiary)
                            Text(napNotice)
                                .font(StrandFont.footnote)
                                .foregroundStyle(theme.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
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

    // MARK: - 5. Tendencia de duración (14 noches + 4 bandas de clasificación)
    //
    // Misma lectura que la hoja de Sueño en Hoy (`MetricInfoSheet`, FER-244): 14 noches, las bandas
    // Short/Adequate/Optimal/Extended con la activa resaltada, un encabezado de conteo y ticks en los
    // umbrales 6/7/9 h. Unifica las dos gráficas de sueño que antes divergían (Hoy 14d/4-bandas vs.
    // Cuerpo 30d/1-banda). (FER-249 v2)

    @ViewBuilder
    private var durationTrendBlock: some View {
        let pts = model.trendPoints
        block(title: "Duration trend") {
            VStack(alignment: .leading, spacing: 10) {
                if pts.count >= 2, let bt = bandedDuration(pts) {
                    // Active-band header: which band the latest nights sit in, and how many of the
                    // window land there — the same one-liner the Today sheet shows.
                    HStack(spacing: 6) {
                        Text(bt.activeLabel).foregroundStyle(theme.dataSleep)
                        Text(verbatim: "·").foregroundStyle(theme.inkTertiary)
                        Text("\(bt.count) of the last \(bt.total) nights in this range")
                            .foregroundStyle(theme.inkSecondary)
                    }
                    .font(StrandFont.subhead)
                    TrendChart(
                        points: pts,
                        gradient: Gradient(colors: [theme.dataSleep.opacity(0.5), theme.dataSleep]),
                        valueRange: bt.range,
                        // No area fill: the soft gradient under the line muddied the classification
                        // bands so you couldn't tell which one you were in. The line alone reads the
                        // band cleanly. (FER-249 v3)
                        showsArea: false,
                        height: 160,
                        showsHover: true,
                        valueFormat: bt.valueFormat,
                        axisLabelColor: theme.inkTertiary,
                        gridLineColor: theme.hairline,
                        bands: bt.bands,
                        bandColor: theme.dataSleep,
                        yAxisValues: bt.yTicks
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text("Hours asleep per night, last 14 nights, with classification bands"))
                    durationStats(pts)
                } else {
                    emptyWell(text: "Not enough nights yet to draw a trend.")
                }
            }
        }
    }

    // MARK: - 5b. Deuda semanal (cifra dominante + barras por noche)
    //
    // La deuda dejó de ser una línea de texto suelta: ahora es su propio bloque con la cifra acumulada
    // de la semana como dato dominante (en `warning`) y, debajo, una barra por noche que muestra qué
    // noche se quedó corta (`warning`, abajo de tu necesidad) o la superó (`verdict`, arriba). Se oculta
    // cuando no hay deuda significativa que mostrar. (FER-249 v2)

    @ViewBuilder
    private var weeklyDebtBlock: some View {
        if let debt = model.weeklyDebtMinutes, debt >= 15, model.weeklyDebtNights.count >= 2 {
            block(title: "Weekly debt") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(hoursMinutes(debt))
                            .font(StrandFont.number(30))
                            .foregroundStyle(theme.warning)
                        Text("behind this week")
                            .font(StrandFont.subhead)
                            .foregroundStyle(theme.inkTertiary)
                    }
                    weeklyDebtBars
                    Text("What you missed versus what your body needs. One good night won't clear it.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// One bar per night for the trailing week: hours above (`verdict`) or below (`warning`) your need,
    /// with the need itself as the zero rule. Scrubbable like every other chart — drag to read a night's
    /// debt and how much you slept (`DebtBars`). The dates are UTC day-keys (FER-226), so the weekday
    /// label formats in UTC to avoid an off-by-one shift. (FER-249 v3)
    private var weeklyDebtBars: some View {
        DebtBars(
            nights: model.weeklyDebtNights.map {
                DebtNightBar(date: $0.date, vsNeedMin: $0.vsNeedMin, sleptMin: $0.sleptMin)
            },
            deficitColor: theme.warning,
            surplusColor: theme.verdict,
            ruleColor: theme.hairlineStrong,
            axisLabelColor: theme.inkTertiary,
            height: 96,
            ruleLabel: String(localized: "your need"),
            weekdayLabel: Self.weekdayNarrow,
            valueFormat: { vsNeedMin in
                vsNeedMin < 0 ? "−\(hoursMinutes(-vsNeedMin))" : "+\(hoursMinutes(vsNeedMin))"
            },
            sleptFormat: { slept in String(localized: "slept \(hoursMinutes(slept))") }
        )
        .accessibilityElement()
        .accessibilityLabel(Text("Hours above or below your sleep need, each of the last 7 nights"))
    }

    /// Single-letter weekday in UTC (matches the UTC day-keys the model stores). "L M M J V S D" in es-MX.
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()
    private static func weekdayNarrow(_ date: Date) -> String { weekdayFormatter.string(from: date) }

    /// The shared «Instrumento» trend summary — average as the protagonist + the night range — in hours.
    /// Sleep's duration trend is a fixed 30-night view with no month-over-month series, so no trend chip
    /// (`pctChange: nil` hides it); higher sleep is better, which colours the chip on the screens that have it.
    @ViewBuilder
    private func durationStats(_ pts: [TrendPoint]) -> some View {
        let vals = pts.map(\.value)
        let avg = vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        TrendStatSummary(
            average: avg.map { String(format: "%.1f", $0) } ?? "—",
            unit: "h",
            pctChange: nil,
            polarity: .higherIsBetter,
            rangeLow: vals.min().map { String(format: "%.1f", $0) } ?? "—",
            rangeHigh: vals.max().map { String(format: "%.1f h", $0) } ?? "—",
            theme: theme
        )
    }

    // MARK: - 6. Métricas de la noche (grid 2-col)

    @ViewBuilder
    private func nightMetricsBlock(_ night: SleepDetailModel.Night) -> some View {
        block(title: "Tonight's metrics") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: NoopMetrics.gap), GridItem(.flexible(), spacing: NoopMetrics.gap)],
                      alignment: .leading, spacing: NoopMetrics.gap) {
                // Performance: asleep / need, capped at 100%, with the shortfall in real hours.
                metricTile(
                    label: "Performance",
                    value: model.performancePct.map { "\(Int(min(100, $0).rounded()))%" } ?? "—",
                    caption: performanceCaption,
                    color: model.performancePct != nil ? theme.dataSleep : theme.inkTertiary,
                    info: .sleepPerformance(model.performancePct))
                metricTile(
                    label: "Efficiency",
                    value: efficiencyPct(night).map { "\(Int($0.rounded()))%" } ?? "—",
                    caption: "vs time in bed",
                    color: efficiencyPct(night) != nil ? theme.dataSleep : theme.inkTertiary,
                    info: .sleepEfficiency(efficiencyPct(night)))
                // Restorative = (deep + REM) / asleep, the literal WHOOP definition.
                metricTile(
                    label: "Restorative",
                    value: restorativePct(night.stages).map { "\(Int($0.rounded()))%" } ?? "—",
                    caption: "Deep + REM",
                    color: restorativePct(night.stages) != nil ? theme.dataSleep : theme.inkTertiary,
                    info: .sleepRestorative(restorativePct(night.stages)))
                // Latency: the cache carries no onset-latency, so omit the tile rather than show a permanent "—".
                if let latency = model.latencyMin {
                    metricTile(
                        label: "Latency",
                        value: "\(Int(latency.rounded())) min",
                        caption: "10–20 healthy",
                        color: theme.dataSleep,
                        info: .sleepLatency(latency))
                }
                metricTile(
                    label: "Respiration",
                    value: night.respRate.map { String(format: "%.1f", $0) } ?? "—",
                    caption: "rpm",
                    color: night.respRate != nil ? theme.dataSpO2 : theme.inkTertiary,
                    info: .respiratory(night.respRate))
                metricTile(
                    label: "Awakenings",
                    value: model.awakenings.map { "\($0)" } ?? "—",
                    caption: "times",
                    color: model.awakenings != nil ? theme.dataSleep : theme.inkTertiary,
                    info: .sleepAwakenings(model.awakenings))
            }
        }
    }

    /// One metric tile in Instrumento: label overline · value in its data hue · quiet caption. The whole
    /// tile is a button that opens the metric's `MetricInfoSheet` (like Today); a quiet ⓘ in the corner
    /// signals "tap to learn what this means". Never the dark `StatTile`. (FER-227)
    private func metricTile(label: LocalizedStringKey, value: String,
                            caption: LocalizedStringKey, color: Color, info: MetricInfo) -> some View {
        Button {
            metricInfo = info
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(value).font(StrandFont.number(22)).foregroundStyle(color)
                Text(caption).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NoopMetrics.cardPadding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.inkTertiary)
                    .padding(11)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Shows what this means"))
    }

    /// The precomputed 14-day mini-trend for a metric sheet, wrapped as the loader `MetricInfoSheet`
    /// expects (it runs lazily on appear). nil for ids we don't chart; an empty series makes the sheet
    /// show its "no data" well rather than a fake line. (FER-227)
    private func trendLoader(for id: String) -> (() async -> [TrendPoint])? {
        let pts: [TrendPoint]
        switch id {
        case "sleep_performance": pts = model.performanceTrend
        case "sleep_efficiency":  pts = model.efficiencyTrend
        case "sleep_restorative": pts = model.restorativeTrend
        case "resp_rate":         pts = model.respirationTrend
        case "sleep_awakenings":  pts = model.awakeningsTrend
        default:                  return nil
        }
        return { pts }
    }

    // MARK: - 7. Ver el método (DisclosureGroup, patrón de MetricDetailScreen)

    @State private var methodExpanded = false

    private var methodDisclosure: some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                Text("Regularity is the night-to-night variability of your mid-sleep point (the midpoint between falling asleep and waking) — a steadier schedule predicts health more strongly than how long you sleep. Naps don't count: only your main night (at least 3 h) feeds regularity. Stages are estimated from movement, heart rate and HRV, so they're approximate; deep sleep repairs the body, REM consolidates memory and emotion. \"Need\" is a 7–9 h population target, not a measurement of you.")
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
        .padding(NoopMetrics.cardPadding)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
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
    /// When `info` is set, the overline gets a trailing ⓘ button (iOS-native "more info") — used by
    /// "Last night" to open the stages explainer. (FER-227)
    @ViewBuilder
    private func block<Content: View>(title: LocalizedStringKey, info: (() -> Void)? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer(minLength: 8)
                    Button(action: info) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(theme.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("What the stages mean"))
                }
            } else {
                Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
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
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
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

    /// The disclosure line shown under the regularity figure when the window dropped one or more naps
    /// (FER-310): names the duration for a single nap, generic otherwise. The "main night" threshold
    /// comes from `SleepMainNight`, so the copy never hardcodes 3 h.
    private var napNotice: LocalizedStringKey {
        if let minutes = model.excludedNapMinutes {
            return "We didn't count your \(napDurationText(minutes)) nap — regularity uses only your main night."
        }
        return "We didn't count your naps (under \(napDurationText(Int(SleepMainNight.minDurationMinutes)))) — regularity uses only your main night."
    }

    /// A minutes count as natural-language duration with no trailing zero minutes: "3 h", "1 h 30 min",
    /// "45 min" — for the nap-disclosure copy.
    private func napDurationText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h) h \(m) min" }
        if h > 0 { return "\(h) h" }
        return "\(m) min"
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

    /// The 4-band classification config for the duration trend — the same reading as the Today sleep
    /// sheet (`MetricInfoSheet.bandedTrend`, FER-244): Short/Adequate/Optimal/Extended, the active band
    /// the latest night sits in, the Y range anchored to the 6/7/9 h thresholds, ticks at those
    /// thresholds, and an hours-and-minutes value format. `nil` when the latest value matches no band,
    /// so the chart falls back to its empty well. (FER-249 v2)
    private struct BandedDuration {
        var bands: [TrendBand]
        var range: ClosedRange<Double>
        var yTicks: [Double]
        var valueFormat: (Double) -> String
        var activeLabel: LocalizedStringKey
        var count: Int
        var total: Int
    }

    private func bandedDuration(_ pts: [TrendPoint]) -> BandedDuration? {
        let values = pts.map(\.value)
        // Half-open bounds [lower, upper) match TrendBand.contains and the Today sheet's bands exactly.
        var bands: [TrendBand] = [
            TrendBand(label: "Short",    lower: nil, upper: 6),
            TrendBand(label: "Adequate", lower: 6,   upper: 7),
            TrendBand(label: "Optimal",  lower: 7,   upper: 9),
            TrendBand(label: "Extended", lower: 9,   upper: nil),
        ]
        guard let active = TrendBands.activeBand(values: values, bands: bands) else { return nil }
        bands[active.index].isActive = true
        let thresholds: [Double] = [6, 7, 9]
        let lo = Swift.min(values.min() ?? 6, 6)
        let hi = Swift.max(values.max() ?? 9, 9)
        let pad = Swift.max((hi - lo) * 0.08, 0.25)
        let range = Swift.max(0, lo - pad)...(hi + pad)
        let fmt: (Double) -> String = { v in
            let m = Int((v * 60).rounded())
            return m % 60 > 0 ? "\(m / 60)h \(m % 60)m" : "\(m / 60)h"
        }
        return BandedDuration(bands: bands, range: range, yTicks: thresholds, valueFormat: fmt,
                              activeLabel: bands[active.index].label, count: active.count, total: values.count)
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

// MARK: - SleepStagesInfoSheet — the combined "what the stages mean" card (FER-227)
//
// One bottom sheet explaining all four sleep stages + why they're approximate, opened from the ⓘ next
// to "Last night". It mirrors the `MetricInfoSheet` visual language (warm paper, title, lede, rows,
// footnote) but its content is a list of stages rather than a banded value — so it's its own small
// view, not a contorted `MetricInfo`. Theme passed EXPLICITLY (it doesn't propagate through `.sheet`,
// FER-162); no nested `NavigationStack` (FER-171). The stage hues are the fixed `StrandPalette` sleep
// colors, the same dots the legend uses (color only in the datum).

struct SleepStagesInfoSheet: View {
    var theme: InstrumentoTheme = .base

    private struct StageRow: Identifiable {
        let id = UUID()
        let stage: SleepStage
        let name: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    private let rows: [StageRow] = [
        StageRow(stage: .rem,   name: "REM",   detail: "Dreams and memory. It consolidates what you learned and processes emotion."),
        StageRow(stage: .deep,  name: "Deep",  detail: "Physical repair. Your body restores itself and releases growth hormone."),
        StageRow(stage: .light, name: "Light", detail: "Most of the night. A transition in which your body winds down."),
        StageRow(stage: .awake, name: "Awake", detail: "Brief awakenings. They're normal and don't mean a bad night."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sleep stages")
                    .font(StrandFont.title2)
                    .foregroundStyle(theme.ink)
                Text("Your night moves through four phases. The watch estimates them from your movement and heart rate, so they're approximate — it gets about 2 of 3 right.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        stageRow(row)
                        if i < rows.count - 1 {
                            Divider().overlay(theme.hairline)
                        }
                    }
                }
                Text("Proportions, not minutes. A clinical measurement needs a sleep study.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .modifier(SleepSheetPaperBackground(paper: theme.paper))
    }

    private func stageRow(_ row: StageRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(StrandPalette.sleepStageColor(row.stage))
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(StrandFont.headline).foregroundStyle(theme.ink)
                Text(row.detail)
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
    /// Strap naps (shorter than a main night) excluded from the regularity window, so the UI can
    /// disclose that they didn't count (FER-310). 0 when none.
    let excludedNapCount: Int
    /// Duration (minutes) of the single excluded nap when `excludedNapCount == 1`, for the "your 2 h
    /// nap" copy; `nil` otherwise (0 naps, or ≥2 → generic copy).
    let excludedNapMinutes: Int?

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
    /// Per-night sleep-vs-need for the trailing 7 days, feeding the debt bars. `vsNeedMin` is signed:
    /// negative = fell short of need (debt), positive = beat it (surplus). (FER-249 v2)
    let weeklyDebtNights: [DebtNight]

    /// One night's sleep relative to your personal need, in minutes (signed). Drives a single debt bar.
    /// `sleptMin` is the night's total sleep, for the scrub tooltip's "slept …" line. (FER-249 v3)
    struct DebtNight: Equatable {
        let date: Date
        let vsNeedMin: Double
        let sleptMin: Double
    }

    // Per-metric 14-day mini-trends for the metric info cards (FER-227). Derived from `repo.days`;
    // empty when there's no series, so the sheet shows its "no data" well rather than a fake line.
    let performanceTrend: [TrendPoint]
    let efficiencyTrend: [TrendPoint]
    let restorativeTrend: [TrendPoint]
    let respirationTrend: [TrendPoint]
    let awakeningsTrend: [TrendPoint]

    // MARK: - Build

    /// Personal sleep need (minutes): mean asleep, never below a 7.5 h floor. Single source of truth
    /// shared with the coach/InsightEngine via `SleepMath` (FER-339), so both show the same debt.
    private static func sleepNeedMin(_ days: [DailyMetric]) -> Double {
        SleepMath.needMinutes(days)
    }

    /// Build the whole model from the repo's in-memory dashboard. Pure (no DB); call from the caller's
    /// view, once per data change. `appleHealthDays` flags which day rows are Apple-sourced (no clock).
    static func build(days: [DailyMetric],
                      sleeps: [CachedSleepSession],
                      importedSleep: [String: ImportedSleepFigures],
                      appleHealthDays: Set<String>,
                      loaded: Bool,
                      todayKey: String) -> SleepDetailModel {
        // Ignore any future-dated row: a daily can be bucketed under "tomorrow" in UTC (FER-226),
        // and a `.last` read would surface that empty row as "last night". Anchor to the device's
        // local day, mirroring StressModel (FER-224) / ReadinessEngine.
        let days = days.filter { $0.day <= todayKey }
        // --- Latest night: strap session wins, else Apple Health stage minutes (FER-62). ---
        // Respiration for the strap night comes from the latest daily metric (the session doesn't
        // carry it), so the Respiration tile shows anoche's value instead of "—". (FER-234)
        let strap = latestStrapNight(sleeps, respRate: days.last?.respRateBpm)
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

        // --- Naps excluded from the regularity window, for the disclosure line (FER-310). ---
        // The engine keeps only "main nights" (≥ SleepMainNight threshold) and scores the most recent
        // `windowNights` of them. A nap counts as excluded only if it onset at/after the oldest night
        // in that window — older naps are off-window and irrelevant to the current read.
        let napThresholdSec = Int(SleepMainNight.minDurationMinutes * 60)
        let strapSessions = sleeps.filter { $0.endTs > $0.startTs }   // excludes Apple-only (start == end)
        let mainNightWindow = strapSessions
            .filter { $0.endTs - $0.startTs >= napThresholdSec }
            .sorted { $0.startTs > $1.startTs }
            .prefix(SleepRegularity.windowNights)
        let windowStart = mainNightWindow.last?.startTs ?? 0
        let excludedNaps = mainNightWindow.isEmpty ? [] : strapSessions.filter {
            $0.endTs - $0.startTs < napThresholdSec && $0.startTs >= windowStart
        }
        let excludedNapCount = excludedNaps.count
        let excludedNapMinutes = excludedNapCount == 1
            ? (excludedNaps[0].endTs - excludedNaps[0].startTs) / 60 : nil

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
        // Per-night sleep-vs-need for the debt bars (signed: < 0 = short of need). Derived on-device from
        // total sleep so it carries surplus too; the headline total above still honours imported debt.
        let debtNights: [DebtNight] = days.suffix(7).compactMap { d in
            guard let asleep = d.totalSleepMin, asleep > 0, need > 0,
                  let date = Repository.parseDayKey(d.day) else { return nil }
            return DebtNight(date: date, vsNeedMin: asleep - need, sleptMin: asleep)
        }

        // --- Per-metric 14-day mini-trends for the info cards (FER-227). Same derivations as the tiles,
        // over history; each skips nights missing that value. ---
        let performanceTrend = metricTrend(days) { d in
            if let p = importedSleep[d.day]?.performancePct { return p }
            guard let asleep = d.totalSleepMin, asleep > 0, need > 0 else { return nil }
            return Swift.min(100, asleep / need * 100)
        }
        let efficiencyTrend = metricTrend(days) { d in
            d.efficiency.map { $0 <= 1.0 ? $0 * 100 : $0 }
        }
        let restorativeTrend = metricTrend(days) { d in
            guard let deep = d.deepMin, let rem = d.remMin, let light = d.lightMin else { return nil }
            let asleep = deep + rem + light
            return asleep > 0 ? (deep + rem) / asleep * 100 : nil
        }
        let respirationTrend = metricTrend(days) { $0.respRateBpm }
        let awakeningsTrend = metricTrend(days) { $0.disturbances.map(Double.init) }

        return SleepDetailModel(
            night: night,
            intervals: intervals,
            isAppleHealth: isApple,
            loaded: loaded,
            regularity: regularity,
            regularityNights: regularityNights,
            excludedNapCount: excludedNapCount,
            excludedNapMinutes: excludedNapMinutes,
            typicalDeepPct: mean(deepPcts),
            typicalRemPct: mean(remPcts),
            typicalLightPct: mean(lightPcts),
            performancePct: performancePct,
            shortfallMinutes: shortfall,
            latencyMin: nil,
            awakenings: awakenings,
            trendPoints: trend,
            weeklyDebtMinutes: weeklyDebt,
            weeklyDebtNights: debtNights,
            performanceTrend: performanceTrend,
            efficiencyTrend: efficiencyTrend,
            restorativeTrend: restorativeTrend,
            respirationTrend: respirationTrend,
            awakeningsTrend: awakeningsTrend)
    }

    /// Trailing 14 nights of a metric, in whatever unit `pick` returns, as `TrendPoint`s. Skips nights
    /// where the value is missing; empty when there's nothing to chart. (FER-227)
    private static func metricTrend(_ days: [DailyMetric], _ pick: (DailyMetric) -> Double?) -> [TrendPoint] {
        let pts = days.compactMap { d -> TrendPoint? in
            guard let v = pick(d), let date = Repository.parseDayKey(d.day) else { return nil }
            return TrendPoint(date: date, value: v)
        }
        return Array(pts.suffix(14))
    }

    // MARK: - Night resolution (ported from the old sleep screen)

    /// The most recent strap sleep, decoded into stage durations + (when on-device) its real timeline.
    /// `respRate` is the night's mean respiration, taken from the matching daily metric — the cached
    /// sleep session itself doesn't carry it, so without this the "Respiration" tile read "—" even
    /// though the 14-day trend (sourced from `repo.days`) had data. (FER-234)
    private static func latestStrapNight(_ sleeps: [CachedSleepSession], respRate: Double?) -> Night? {
        guard let s = sleeps.last, s.endTs > s.startTs else { return nil }
        if let stages = decodeStages(s.stagesJSON), stages.total > 0 {
            return Night(startTs: s.startTs, endTs: s.endTs, efficiency: s.efficiency,
                         respRate: respRate, stages: stages)
        }
        if let seg = decodeSegments(s.stagesJSON, sessionStart: s.startTs), seg.stages.total > 0 {
            return Night(startTs: s.startTs, endTs: s.endTs, efficiency: s.efficiency,
                         respRate: respRate, stages: seg.stages)
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
        let startTs = Int((Repository.parseDayKey(d.day) ?? Date()).timeIntervalSince1970) + 12 * 3600
        return Night(startTs: startTs, endTs: startTs, efficiency: d.efficiency,
                     respRate: d.respRateBpm, stages: stages)
    }

    /// Trailing 14 nights of total sleep, in HOURS — the same window the Today sleep sheet charts, so
    /// both screens read identically (FER-249 v2). Falls back to all nights when the window is sparse.
    private static func durationTrendPoints(_ days: [DailyMetric]) -> [TrendPoint] {
        func build(_ slice: ArraySlice<DailyMetric>) -> [TrendPoint] {
            slice.compactMap { d -> TrendPoint? in
                guard let mins = d.totalSleepMin, mins > 0,
                      let date = Repository.parseDayKey(d.day) else { return nil }
                return TrendPoint(date: date, value: mins / 60.0)
            }
        }
        let recent = build(days.suffix(14))
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
