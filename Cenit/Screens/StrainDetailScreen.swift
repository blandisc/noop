#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

/// Measured-width key for the 90-day calendar heat grid (FER-830).
private struct StrainCalWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - StrainDetailScreen — el «Detalle de Esfuerzo» en «Instrumento» (FER-238)
//
// Hermana de `MetricDetailScreen` (FER-185), `RecoveryDetailScreen` (FER-225) y `SleepDetailScreen`
// (FER-212): REUSA su lenguaje visual (hero, `InfoAccordion`, `theme: InstrumentoTheme` explícito,
// `sheetPaper`, `ScrollView`→`VStack`, `methodDisclosure`, los wells, la window-math de la
// tendencia) pero con su propio modelo. NO extiende `MetricDetailScreen`/`MetricDetailSpec` (esos son
// para vitales de serie ESCALAR única — HRV/FC/Respiración, con hero = promedio móvil 7d y rango normal
// personal). El esfuerzo es una métrica COMPUESTA con forma propia: el hero es el valor de HOY en escala
// fija 0–21, su visualización firma es la CURVA INTRADÍA acumulada del día, y su referencia son ZONAS
// fijas (no un rango rolling). Reemplaza, para Esfuerzo en Cuerpo, la vieja `MetricInfoSheet`. Hoy
// (TodayView) NO cambia: sigue abriendo `MetricInfo.strain`/`MetricInfoSheet`.
//
// Se presenta vía `.sheet(item:)` con el tema vivo pasado EXPLÍCITO (no propaga por `.sheet`, FER-162) y
// SIN `NavigationStack` anidado (un stack anidado cruzando el path de la tab crasheaba SwiftUI, FER-171).
//
// Bloques, cada uno con su ⓘ (`InfoAccordion`) salvo el método (DisclosureGroup): 1) Hero (valor de hoy
// en `theme.dataStrain`, lectura por nivel) · 2) Cómo se acumuló hoy (curva intradía, async) · 3) Niveles
// (la tabla de las 4 bandas fijas de `MetricInfo.strain`, la activa marcada) · 4) «Ver tu historial»
// (tendencia con selector + «Media · periodo · Δ%» neutral + qué lo mueve, plegado) · 5) Ver el método.
// Consume `StrandAnalytics`/la curva de `CuerpoView.loadStrainCurve()` TAL CUAL: no crea math.
//
// FER-597 lo alinea al handoff «Detalle · Esfuerzo»: UNA sola tabla de Niveles + la tendencia de vuelta en
// «Ver tu historial» (revierte el `MetricLevelsExplorer` de FER-572, que duplicaba los niveles y ocupaba el
// lugar de la tendencia). El explorer sigue vivo para las pantallas hermanas — solo deja de usarse aquí.

/// Light «Instrumento» Detalle de Esfuerzo. Built once from a `StrainDetailModel` (the caller injects the
/// model so the screen stays DB-free); the intraday curve is loaded async (it reads HR samples from the
/// DB) the same way `MetricDetailScreen` injects its `seriesLoader`. Themed explicitly for the sheet.
struct StrainDetailScreen: View {
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    /// Everything the screen draws from the in-memory dashboard, derived ONCE by the caller (no DB here).
    let model: StrainDetailModel
    /// Today's accumulated-strain curve, loaded async (it reads HR samples — DB I/O, not pure). Returns
    /// `[]` when there's no score / too little activity yet. Injected by the caller (`loadStrainCurve`).
    var curveLoader: () async -> [TrendPoint] = { [] }

    /// The trend block's period window (W/M/3M/6M/1Y/ALL). Defaults to a month.
    @State private var range: ExploreRange = .month
    /// The strain series with each `day` string parsed to a `Date` exactly ONCE (not per slice / per
    /// render) — the window math reads `date` straight from here. Built in `.task`. (FER-216 lesson)
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    /// Measured width so the 90-day heat grid fills it; the tapped day for the read-out. (FER-830)
    @State private var calWidth: CGFloat = 0
    @State private var selectedStrainDay: RecoveryDay? = nil
    /// Today's intraday curve, loaded in `.task` (loading well until then).
    @State private var curve: [TrendPoint] = []
    @State private var curveLoaded = false
    /// The in-progress day's LIVE strain = the curve's LAST point, captured when the curve loads so the
    /// hero equals the end of the curve BY CONSTRUCTION (they read the same array — FER-650). nil until the
    /// curve loads, or when there's too little activity today; the hero then falls back to the settled score.
    @State private var liveToday: Double?
    @State private var methodExpanded = false
    /// Level-3 disclosure: the period trend (+ «Media · periodo · Δ%») and «What moves your strain» live
    /// under «See your history», collapsed on open. Strain is the LIGHT cut — no Level 2 — so this is the
    /// only re-sequencing state, and it folds just those blocks for consistency. (Detalles escalonados)
    @State private var historyExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Level 1 · the answer: hero + today's intraday curve + the fixed zones. Already the
                // daily check; Strain needed no condensing (light cut).
                hero
                if !model.loaded {
                    ChartWell(theme).loading(height: 160)
                } else {
                    // The intraday curve needs a score / activity today; it's hidden when there's none.
                    if model.hasData {
                        blockDivider
                        curveBlock
                    }
                    // Niveles · the handoff's single reference table (the 4 fixed bands of `MetricInfo.strain`,
                    // the active one marked). FIXED reference, so it shows even on a brand-new empty screen —
                    // the hero's "—" reading is honest about the missing score. The FER-572 level explorer was
                    // a SECOND copy of these same bands AND took the trend's place; it's gone. (FER-597)
                    blockDivider
                    levelsTable
                    // Level 3 · «Ver tu historial»: the period trend + «Media · periodo · Δ%» (neutral) + what
                    // moves your strain, collapsed by default — the handoff's history, restored here. (FER-597)
                    if model.hasData {
                        blockDivider
                        historySection
                    }
                    if model.hasData {
                        blockDivider
                        strainCalendarBlock
                    }
                    blockDivider
                    methodDisclosure
                    // Standardized origin seal (FER-803): strain is a score computed on-device, live today.
                    OriginStamp(origin: .computed, when: String(localized: "today, in progress"), theme: theme)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
        .task {
            range = .month
            parsed = model.series.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
            curve = await curveLoader()
            // The hero shows the curve's LAST point (the live in-progress-day value) so «ends on your score
            // above» holds exactly — same array, no second derivation (FER-650). `.last` is the real endpoint
            // (the prepended midnight anchor is `.first`).
            liveToday = curve.last?.value
            curveLoaded = true
        }
    }

    /// A subtle 1px rule between blocks (token-only). Mirrors the sibling screens' `blockDivider`.
    private var blockDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    // MARK: - 1. Hero — el valor de hoy (0–21) en color del dato

    /// The value shown as today's strain: the live curve endpoint once the curve loads (so hero == the
    /// curve's last point by construction, FER-650), falling back to the settled `repo.today.strain` before
    /// the curve loads or when there's too little activity to draw one. Drives the hero number, its plain-
    /// language reading, and the highlighted level — one value, never a contradiction on-screen.
    private var shownToday: Double? { liveToday ?? model.today }

    private var hero: some View {
        let v = shownToday
        // Serif in-screen title + ⓘ (the «Instrumento» detail identity, FER-581). Explanation stays behind
        // the ⓘ exactly as the old InfoAccordion had it.
        return VStack(alignment: .leading, spacing: 6) {
            InstrumentoScreenTitle("Day Strain", theme: theme,
                explanation: "Day Strain is your cardiovascular load on a 0–21 scale. Each second your heart rate is recorded, it's placed in an intensity zone (1–5); higher zones weigh more, and the total is compressed logarithmically so 21 is a theoretical maximum — a full day at peak intensity. (Edwards 1993; Banister 1991)",
                glyph: .strain)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(v.map { fmt($0) } ?? "—")
                        .instrumentoHero(46)
                        .foregroundStyle(v == nil ? theme.inkTertiary : theme.dataStrain)
                    if v != nil {
                        Text("/ 21").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    }
                }
                Text(heroReading)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // FER-676: how much of the active day the strap actually covered — the score's
                // trust grade, shown only when there IS a score to grade. Calibrating never
                // reaches here (no score → no sello), so the chip has two states.
                if v != nil, let tier = model.confidence {
                    tier.sello(theme: theme)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// A plain-language reading of today's strain by zone, or an honest "no strain yet" when there's no
    /// score (strain is strap-only; Apple Health doesn't compute it). The zone is derived from the SAME
    /// `MetricInfo.strain` bands the zones block shows, so the reading and the highlighted zone can never
    /// disagree if a boundary is ever retuned (single source of truth — no second copy of the thresholds).
    /// Source strings are English; the es values live in `Localizable.xcstrings`.
    private var heroReading: LocalizedStringKey {
        guard let v = shownToday else {
            if !model.series.isEmpty { return "No strain from today yet — your recent history is below." }
            return "No strain yet. Wear your strap through the day and open this again after it syncs."
        }
        switch MetricInfo.strain(v).bands.firstIndex(where: \.isActive) ?? 0 {
        case 0:  return "Light load today — plenty left in the tank."
        case 1:  return "Moderate effort today."
        case 2:  return "Hard effort today — solid work."
        default: return "All-out day — about as much strain as you carry."
        }
    }

    // MARK: - 2. Cómo se acumuló hoy (curva intradía acumulada)

    private var curveBlock: some View {
        InfoAccordion(
            title: "How today added up",
            explanation: "The line shows how your strain piled up through the day — each second of heart rate adds to the running total, so it only ever rises. It ends on today's score above.",
            accessibilityLabel: "Information about how today's strain added up",
            theme: theme
        ) {
            Group {
                if curve.count > 1 {
                    TrendChart(
                        points: curve,
                        gradient: chartGradient,
                        valueRange: 0...max((curve.map(\.value).max() ?? 1) * 1.15, 1),
                        showsArea: true,
                        height: 160,
                        showsScrub: true,
                        valueFormat: { fmt($0) },
                        dateFormat: { Self.hourString($0) },
                        axisLabelColor: theme.inkTertiary,
                        gridLineColor: theme.hairline
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text("Accumulated day strain, rising through the day."))
                } else if !curveLoaded {
                    ChartWell(theme).loading(height: 160)
                } else {
                    ChartWell(theme).empty(text: "Not enough activity yet today to chart.")
                }
            }
        }
    }

    // MARK: - 3. Niveles (las 4 bandas fijas, la activa marcada) — la tabla de referencia del handoff

    /// The handoff's «Niveles» reference table: the 4 fixed bands (Rest/Light · Moderate · Hard · Extreme,
    /// the active one flagged for today's value) straight from the shared `MetricInfo.strain` factory — the
    /// same source of truth the hero reading uses, so the table and the highlighted band can never disagree.
    /// This is now the SOLE levels block; the FER-572 `MetricLevelsExplorer` duplicated it. (FER-597)
    private var levelsTable: some View {
        let bands = MetricInfo.strain(shownToday).bands
        return InfoAccordion(
            title: "Levels",
            explanation: "Your heart rate falls into one of four intensity zones through the day. The highlighted row is where today's score lands on the 0–21 scale.",
            accessibilityLabel: "Information about the strain levels",
            theme: theme
        ) {
            VStack(spacing: 0) {
                ForEach(Array(bands.enumerated()), id: \.offset) { i, band in
                    zoneRow(band)
                    if i < bands.count - 1 {
                        Divider().overlay(theme.hairline).padding(.leading, 22)
                    }
                }
            }
        }
    }

    /// One zone row: a dot (active → the strain hue, else quiet ink) + label + its range, with a subtle
    /// active highlight. Token-only (no hex/spacing literals beyond the layout paddings the siblings use).
    private func zoneRow(_ band: MetricInfo.Band) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(band.isActive ? theme.dataStrain : theme.inkTertiary.opacity(StrandOpacity.dim))
                .frame(width: 8, height: 8)
            Text(band.label)
                .font(StrandFont.subhead)
                .foregroundStyle(band.isActive ? theme.ink : theme.inkSecondary)
            Spacer(minLength: 8)
            Text(band.range)
                .font(StrandFont.captionNumber)
                .foregroundStyle(band.isActive ? theme.dataStrain : theme.inkTertiary)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(band.isActive ? theme.dataStrain.opacity(StrandOpacity.tintFill) : Color.clear)
    }

    // MARK: - 4. Tendencia (selector + «Media · periodo · Δ%») — vive en «Ver tu historial»

    /// The handoff's trend: a period selector (`MetricTrendChart`) over the daily strain series, drawn as a
    /// 7-day moving average (strain is a noisy day-to-day composite), in the strain hue. No ⓘ — the smoothing
    /// is named in the caption right below and the TRIMP math lives in «See the method». Replaces FER-572's
    /// level explorer, which doubled the Niveles table AND took this trend's place. The `window` is derived
    /// once by the caller (`expandedHistory`) and shared with `averageCaption` — the FER-216 rule. (FER-597)
    private func trendBlock(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MetricTrendChart(
                range: $range,
                window: window,
                theme: theme,
                style: .init(
                    smoothing: 7,
                    gradient: chartGradient,
                    height: 160,
                    valueRange: { chartRange($0) },
                    valueFormat: { fmt($0) },
                    accessibilityLabel: "Day strain, 7-day moving average"
                )
            ) {
                ChartWell(theme).empty(text: "Not enough days in this range to draw a trend.")
            }
            if window.values.count > 1 {
                Text("7-day moving average")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
    }

    /// The handoff's period-average caption: «Media · periodo · valor · Δ% vs previo» + the window's range,
    /// from the SAME `ComparisonEngine` figures as the trend. Effort is NEUTRAL (no good direction → no colour
    /// on the Δ); shown on the 0–21 scale, no unit. Sits right under the trend in «Ver tu historial», sharing
    /// the same `window` the trend already derived. (FER-587)
    @ViewBuilder private func averageCaption(_ window: MetricWindow) -> some View {
        if window.values.count > 1 {
            let s = ComparisonEngine.stat(window.values)
            DynamicAverageCaption(
                windowName: range.name,
                average: fmt(s.mean),
                pctChange: range.periodComparison(of: model.series)?.pctChange,
                polarity: .neutral,
                rangeText: "\(fmt(s.min))–\(fmt(s.max))",
                theme: theme)
        }
    }

    // MARK: - 4.5 Qué mueve tu esfuerzo (correlación direccional, gated — FER-239)

    /// Documented, DIRECTIONAL drivers of strain (same-day recovery, the prior day's strain), computed from
    /// the user's OWN history in `StrandAnalytics` and degraded to a direction — never a coefficient, never
    /// a causal claim (hence the "tendencia, no causa" chip). Mirrors `MetricDetailScreen`'s block. When no
    /// relationship clears the gate it renders an honest empty state instead of vanishing (FER-246).
    private var whatMovesBlock: some View {
        // The ⓘ discloses the correlation method + the sufficiency gate (FER-220 pattern); the chip and the
        // directional sentences live inside the accordion's content.
        InfoAccordion(
            title: "What moves your strain",
            explanation: "We line up your day strain against your own recovery and the prior day's strain, day by day across your history, and read which way it leans (Pearson correlation). We only show a direction once there are enough paired days (about six weeks) and the link is strong enough to be unlikely to be chance — never the number, and never as a cause. (Plews 2013; Vesterinen 2016)",
            accessibilityLabel: "Information about what moves your strain",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if model.drivers.isEmpty {
                    // Too few paired days yet, or none strong enough — honest, neutral empty state (FER-246).
                    Text("Not enough data yet — keep wearing your strap and check back in a few weeks.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    InlineFlagChip("trend, not cause", color: theme.inkTertiary)
                    ForEach(model.drivers, id: \.driver) { finding in
                        Text(Self.driverPhrase(finding))
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The directional sentence for a driver. The direction comes from the user's data; no number is ever
    /// shown. Source strings are English; the es-MX values live in `Localizable.xcstrings`.
    private static func driverPhrase(_ f: StrainDriverFinding) -> LocalizedStringKey {
        switch (f.driver, f.trend) {
        case (.sameDayRecovery, .rises): return "Tends to run higher on days you start more recovered."
        case (.sameDayRecovery, .falls): return "Tends to run lower on days you start more recovered."
        case (.priorDayStrain, .rises):  return "Tends to run higher the day after a hard effort."
        case (.priorDayStrain, .falls):  return "Tends to ease off the day after a hard effort."
        }
    }

    // MARK: - Level 3 · «See your history» — trend + what moves your strain, collapsed by default
    //
    // The analyst's view, one tap down. An in-place disclosure (NOT a navigation push); the chevron and
    // copy mirror «See the method». Holds the period-selector trend and the directional drivers that used
    // to sit always-open in the daily scroll. Strain is the light cut, so this is its only fold and there
    // is no Level 2. (Detalles escalonados)

    @ViewBuilder private var historySection: some View {
        VStack(alignment: .leading, spacing: historyExpanded ? 22 : 0) {
            historyDisclosureHeader(caption: "Trend · what moves it")
            if historyExpanded { expandedHistory }
        }
    }

    /// «Ver tu historial» expanded: the period trend + «Media · periodo · Δ%» (neutral), then the gated
    /// directional drivers. The window is derived ONCE here and handed to both the chart and the caption
    /// (the FER-216 «compute the window once» rule), instead of each re-deriving it. The trend needs ≥2
    /// days; «what moves it» carries its own sufficiency gate. The section only renders under `model.hasData`
    /// (see `body`), so `whatMovesBlock` is unconditional here. (FER-597)
    private var expandedHistory: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        return VStack(alignment: .leading, spacing: 22) {
            if model.series.count >= 2 {
                trendBlock(window)
                averageCaption(window)
                blockDivider
            }
            whatMovesBlock
        }
    }

    /// The «See your history» row: a tappable header toggling the Level-3 disclosure in place. The
    /// chevron rotates with the house interactive spring. Shared shape across the four detail screens.
    private func historyDisclosureHeader(caption: LocalizedStringKey) -> some View {
        Button {
            withAnimation(StrandMotion.interactive) { historyExpanded.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("See your history").instrumentoOverline().foregroundStyle(theme.ink)
                    Text(caption).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
                    .rotationEffect(.degrees(historyExpanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(historyExpanded ? "expanded" : "collapsed"))
    }

    // MARK: - Calendario · 90 días (handoff v2, FER-830) — heatmap en el hue de esfuerzo por nivel

    private static let calDayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")!; f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let calReadoutFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()

    /// The trailing 90 days as `RecoveryDay` (score = strain 0–21, nil where there's no reading).
    private var strainHeat: [RecoveryDay] {
        var vals: [String: Double] = [:]
        for r in parsed { vals[r.day] = r.value }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.startOfDay(for: Date())
        return stride(from: 89, through: 0, by: -1).compactMap { off -> RecoveryDay? in
            guard let date = cal.date(byAdding: .day, value: -off, to: today) else { return nil }
            return RecoveryDay(date: date.addingTimeInterval(12 * 3600), score: vals[Self.calDayFmt.string(from: date)])
        }
    }

    /// Strain is descriptive (not evaluative), so the heat is one hue at three intensities.
    private func strainHeatTint(_ v: Double) -> Color {
        if v >= 14 { return theme.dataStrain }
        if v >= 8 { return theme.dataStrain.opacity(0.6) }  // token-exempt: rampa de calor (3 intensidades)
        return theme.dataStrain.opacity(0.32)  // token-exempt: rampa de calor (3 intensidades)
    }

    @ViewBuilder private var strainCalendarBlock: some View {
        if parsed.contains(where: { $0.value > 0 }) {
            DetailBlock("Calendar · 90 days", theme: theme) {
                VStack(alignment: .leading, spacing: 10) {
                    let cols = Swift.max(1, YearHeatStrip.weekColumns(for: strainHeat))
                    let spacing: CGFloat = 4
                    let cell: CGFloat = calWidth > 0
                        ? Swift.max(8, Swift.min(22, (calWidth - 24 - spacing - CGFloat(cols - 1) * spacing) / CGFloat(cols)))
                        : 14
                    YearHeatStrip(
                        days: strainHeat, cellSize: cell, spacing: spacing, showsScrub: false,
                        tint: strainHeatTint, emptyFill: theme.hairline, emptyStroke: theme.hairlineStrong,
                        labelColor: theme.inkTertiary, onSelect: { selectedStrainDay = $0 }, selectionColor: theme.ink
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { g in Color.clear
                        .preference(key: StrainCalWidthKey.self, value: g.size.width) })
                    .onPreferenceChange(StrainCalWidthKey.self) { calWidth = $0 }
                    if let d = selectedStrainDay {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Self.calReadoutFmt.string(from: d.date)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                            Spacer(minLength: 8)
                            if let v = d.score {
                                Text(String(format: "%.1f", v)).font(StrandFont.number(20)).foregroundStyle(theme.dataStrain)
                            } else {
                                Text("—").font(StrandFont.number(20)).foregroundStyle(theme.inkTertiary)
                                Text("no reading").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        Text("Tap a day to see its strain.").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Ver el método (DisclosureGroup, patrón de las otras pantallas)

    private var methodDisclosure: some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                Text("Each second of heart rate is mapped to one of five intensity zones; time in the higher zones counts for much more. The weighted total is compressed onto a 0–21 scale through a logarithmic curve, so the top of the scale represents a theoretical full day at peak intensity.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Heart-rate-zone load (TRIMP), compressed logarithmically. (Edwards 1993; Banister 1991)")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("How it's calculated")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
        }
        .tint(theme.inkTertiary)
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
    }

    // MARK: - Colour + format

    private var chartGradient: Gradient { ChartWell.fillGradient(theme.dataStrain) }

    /// The trend chart's Y domain: the smoothed line's own min/max with a little breath, clamped to the
    /// fixed 0–21 strain scale so the axis never runs past the metric's range. (FER-597)
    private func chartRange(_ smoothed: [Double]) -> ClosedRange<Double> {
        let lo = smoothed.min() ?? 0
        let hi = smoothed.max() ?? 21
        if hi <= lo { return Swift.max(0, lo - 1)...Swift.min(21, hi + 1) }
        let pad = (hi - lo) * 0.15
        return Swift.max(0, lo - pad)...Swift.min(21, hi + pad)
    }

    /// Strain reads to one decimal (0–21), like the row and the hero.
    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    // MARK: - Chart axis

    /// Locale-aware hour label for the intraday curve's x-axis (12/24h per region).
    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j")
        return f
    }()

    private static func hourString(_ date: Date) -> String { hourFormatter.string(from: date) }
}

// MARK: - Sheet item

/// Identifiable wrapper so the light «Instrumento» Detalle de Esfuerzo can ride `.sheet(item:)` (the
/// model itself isn't Identifiable). Opened from Cuerpo's «Day Strain» row. (FER-238)
struct StrainDetailItem: Identifiable {
    let id = UUID()
    let model: StrainDetailModel
}

// MARK: - StrainDetailModel — every derivation the screen draws, built ONCE from the repo
//
// The data layer of the strain detail, lifted out of the view. `StrainDetailScreen` is pure presentation
// over this; the caller (Cuerpo) builds it with `StrainDetailModel.build(...)` from the in-memory
// dashboard so the screen stays DB-free. It CONSUMES `StrandAnalytics` as-is (no new math): today's score
// from `repo.today.strain`, the 14d+ series from `repo.days`. The intraday curve is NOT here — it reads HR
// samples (DB I/O) and is injected as an async `curveLoader` instead.

struct StrainDetailModel {
    /// Today's Day Strain (0–21), or nil while there's no score yet (strap-only, no Apple fallback).
    let today: Double?
    /// The full strain series (oldest → newest), `(day "yyyy-MM-dd", value)`, for the trend + stats.
    let series: [(day: String, value: Double)]
    /// Whether the repo finished its first load (drives loading vs empty hero copy).
    let loaded: Bool
    /// The gated, directional drivers of strain ("Qué mueve tu esfuerzo"), computed from the user's own
    /// history (FER-239). Empty when nothing clears the sufficiency gate → the block stays hidden.
    let drivers: [StrainDriverFinding]
    /// Today's effort-confidence tier (FER-676), from the persisted `effortConfidence` — how much of the
    /// active day HR actually covered. nil when today has no score (nothing to grade → no sello).
    var confidence: ScoreConfidence? = nil

    /// True when there's a score today or any stored strain history to draw (the rich path); false → empty.
    var hasData: Bool { today != nil || !series.isEmpty }

    /// Build the whole model from the repo's in-memory dashboard. Pure (no DB). `days` is the strap +
    /// on-device dashboard (`repo.days`, the baseline source — FER-149); `today` is `repo.today`. The
    /// drivers are computed here off the same `days` (which carry recovery) via `StrandAnalytics`, keeping
    /// the screen DB-free presentation over a ready-made model.
    static func build(days: [DailyMetric], today: DailyMetric?, loaded: Bool) -> StrainDetailModel {
        let series = days
            .compactMap { d in d.strain.map { (day: d.day, value: $0) } }
            .sorted { $0.day < $1.day }
        let recovery = days
            .compactMap { d in d.recovery.map { (day: d.day, value: $0) } }
            .sorted { $0.day < $1.day }
        let drivers = WhatMovesStrainEngine.drivers(strain: series, recovery: recovery)
        return StrainDetailModel(today: today?.strain, series: series, loaded: loaded, drivers: drivers,
                                 confidence: today?.effortConfidence.flatMap(ScoreConfidence.init(rawValue:)))
    }
}

// MARK: - Preview

#if DEBUG
private func sampleStrainSeries(days: Int = 60) -> [(day: String, value: Double)] {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let f = DayKey.utcFormatter
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = 11 + 5 * sin(Double(i) / 5.0) + Double((i * 7) % 5) - 2
        return (f.string(from: date), Swift.max(1, Swift.min(21, v)))
    }
}

private func sampleCurve() -> [TrendPoint] {
    let cal = Calendar(identifier: .gregorian)
    let midnight = cal.startOfDay(for: Date())
    var acc = 0.0
    return (0...16).map { h in
        acc += Double((h * 13) % 4) * 0.25 + 0.6
        return TrendPoint(date: midnight.addingTimeInterval(Double(h) * 3600), value: Swift.min(21, acc))
    }
}

#Preview("Strain detail — con datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StrainDetailScreen(
            model: StrainDetailModel(today: 14.2, series: sampleStrainSeries(), loaded: true,
                                     drivers: [.init(driver: .sameDayRecovery, trend: .rises),
                                               .init(driver: .priorDayStrain, trend: .falls)]),
            curveLoader: { sampleCurve() })
    }
}

#Preview("Strain detail — sin datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StrainDetailScreen(
            model: StrainDetailModel(today: nil, series: [], loaded: true, drivers: []),
            curveLoader: { [] })
    }
}
#endif
#endif
