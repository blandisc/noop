#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - StressDetailScreen — el «Detalle de Estrés» en «Instrumento» (FER-241)
//
// Hermana de `MetricDetailScreen` (FER-185), igual que `RecoveryDetailScreen` (FER-225) y
// `SleepDetailScreen` (FER-212): REUSA su lenguaje visual (el scaffold `block(title:)`, el hero,
// `InfoAccordion`, `theme: InstrumentoTheme` explícito, `SheetPaperBackground`, `ScrollView`→`VStack`,
// `methodDisclosure`, los wells) pero con su propio modelo. NO extiende `MetricDetailScreen`/`MetricDetailSpec`
// (esos son para vitales de serie ESCALAR única — HRV/FC/Respiración); el estrés es un ÍNDICE DERIVADO 0–3
// con BANDAS UNIVERSALES y bloques propios (qué lo mueve = RHR/HRV, tiempo en calma, placeholder de
// calendario). Reemplaza, para el estrés, la vieja `MetricInfoSheet` ligera que abría Cuerpo.
//
// Se presenta desde Cuerpo Y desde Hoy vía `.sheet(item:)` (FER-452 unificó el detalle: el «ver más» de
// Estrés en Hoy abre esta MISMA pantalla completa, con el «mapa del día» cableado por el factory compartido
// `StressDayMapPresenter`), con el tema vivo pasado EXPLÍCITO (no propaga por `.sheet`, FER-162) y SIN
// `NavigationStack` anidado (un stack anidado cruzando el path de la tab crasheaba SwiftUI, FER-171).
//
// Consume `StressModel` (de `StressView.swift`) TAL CUAL — no crea matemática nueva: el score/banda 0–3, la
// explicación, los marcadores RHR/HRV vs base, la serie completa y el «tiempo en calma» ya los deriva el
// modelo (z-score logístico; bandas 0–1/1–2/2–3). El hero muestra el VALOR DE HOY (no la media 7d) porque el
// índice ya viene normalizado a la base de cada quien; las bandas son fijas por la misma razón.
//
// Bloques, cada uno con su ⓘ (`InfoAccordion`) salvo el método: 1) Hero (valor de hoy en color de banda) ·
// 1.5) Estrés a lo largo del día — el «mapa del día» en «Momentos primero» (titular del pico + barras de
// apoyo + momentos rankeados cruzados con el calendario, `StressDayMapBlock`, FER-433), ahora a PRIMER
// NIVEL (antes vivía bajo «See your history») · 2) Qué lo mueve (RHR/HRV vs base) · 3) Tus patrones (tiempo
// en calma + consistencia) · 4) Ver tu historial (Tendencia 0–3 sobre las bandas) · 5) Ver el método.

/// Light «Instrumento» Detalle de Estrés. Built from a `StressModel` (the caller injects it so the screen
/// stays DB-free), themed explicitly for the sheet boundary. `model == nil` → the honest empty state.
struct StressDetailScreen: View {
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    /// The transparent 0–3 stress model, built by the caller from `repo.displayDays` + the stored series.
    /// `nil` when there's no usable signal at all → the empty hero.
    let model: StressModel?
    /// The «mapa del día» driver (EventKit permission + intraday stress curve + calendar cross), built
    /// by the caller. `nil` in previews / when the block shouldn't show. (FER-377)
    var dayMap: CalendarDayMap? = nil
    /// Loads the cross-day «moment of day» patterns (persists the daily summaries, then detects).
    /// Injected so the screen stays DB-free. `nil` → no pattern line. (FER-378)
    var patternsLoader: (() async -> [StressTimeOfDayPatterns.Pattern])? = nil
    /// Loads the cross-day «by calendar-event» patterns (one on-device EventKit read, nothing persisted).
    /// Runs after `patternsLoader` so the daily summaries it reads are already backfilled. (FER-388)
    var eventPatternsLoader: (() async -> [StressEventPatterns.Pattern])? = nil

    /// The trend block's period window (W/M/3M/6M/1Y/ALL). Defaults to a month.
    @State private var range: ExploreRange = .month
    /// The stress series with each point's `Date` already parsed (from `fullTrend`) — the window math reads
    /// `date` straight from here (no string re-parsing). Built in `.task`. (FER-216 lesson)
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    @State private var methodExpanded = false
    /// Level-3 disclosure: the daily trend (over the fixed Low/Mod/High bands) + the «mapa del día» live
    /// under «See your history», collapsed on open. The only new state the re-sequencing adds. (Detalles
    /// escalonados)
    @State private var historyExpanded = false
    /// Detected cross-day «moment of day» patterns (loaded in `.task`). Empty → no line. (FER-378)
    @State private var patterns: [StressTimeOfDayPatterns.Pattern] = []
    /// Detected cross-day «by calendar-event» patterns (loaded in `.task`). Empty → no line. (FER-388)
    @State private var eventPatterns: [StressEventPatterns.Pattern] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let model {
                    // Level 1 · the answer. The hero falls back to yesterday's reading (dated) when
                    // today is still incomplete; if even that's missing it shows the empty hero — but
                    // either way the history below still renders, so the screen is never blanked. (FER-397)
                    if model.heroIsFresh {
                        hero(model)
                        blockDivider
                        whatMovesItBlock(model)
                        blockDivider
                    } else {
                        noRecentHero
                        blockDivider
                    }
                    // Level 1.5 · «Stress through the day» — the «Momentos primero» block, now FIRST-CLASS
                    // (FER-433): promoted out of «See your history» so the day's most-activated moments and
                    // the calendar cross are visible without expanding anything.
                    if let dayMap {
                        StressDayMapBlock(model: dayMap, theme: theme)
                        blockDivider
                    }
                    // Level 2 · «Your patterns»: calm time + consistency, fused to plain lines. The
                    // former «Normal range» block is gone from the daily scroll — those Low/Mod/High
                    // bands are already drawn behind the trend line as its legend (one dispersion read).
                    patternsBlock(model)
                    // Level 3 · «See your history»: the daily trend over the fixed bands (the mapa del día
                    // moved up to Level 1.5).
                    if model.fullTrend.count >= 2 {
                        blockDivider
                        historySection(model)
                    }
                    blockDivider
                    methodDisclosure(model)
                } else {
                    emptyHero
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .modifier(StressSheetPaperBackground(paper: theme.paper))
        .task {
            range = .month
            parsed = (model?.fullTrend ?? []).map {
                (Self.dayParser.string(from: $0.date), $0.date, $0.value)
            }
            if let patternsLoader { patterns = await patternsLoader() }
            if let eventPatternsLoader { eventPatterns = await eventPatternsLoader() }
        }
    }

    /// A subtle 1px rule between blocks (token-only). Mirrors MetricDetailScreen's `blockDivider`.
    private var blockDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    // MARK: - 1. Hero — el valor de HOY en color de banda (+ palabra de banda + lectura)

    private func hero(_ model: StressModel) -> some View {
        // Serif in-screen title + ⓘ (the «Instrumento» detail identity, FER-581). Explanation stays behind
        // the ⓘ exactly as the old InfoAccordion had it.
        VStack(alignment: .leading, spacing: 14) {
            InstrumentoScreenTitle("Stress", theme: theme,
                explanation: "Your autonomic load for the day: how activated your body is. We take today's resting heart rate and HRV, compare each with your own 30-day baseline as a z-score, and map the combined shift onto a 0–3 scale through a logistic curve (0 calm · 1.5 your baseline · 3 highly activated). It's an estimate, not a diagnosis.")
            VStack(alignment: .leading, spacing: 14) {
                // When the reading isn't today's (fell back to yesterday at the midnight boundary), date
                // it so it's never passed off as today's. (FER-397)
                if !model.anchorIsToday {
                    heroDateChip(model.anchorDayKey)
                }
                // The band WORD leads — you understand «Moderate» before «1.8/3». The 0–3 value backs it
                // up, quiet, to the right. The saturated hue lives in the word (it's the datum). (Pase v2 #2)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bandWord(model.band))
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(bandColor(model.band))
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(fmt(model.score)).font(StrandFont.bodyNumber)
                        Text("/ 3").font(StrandFont.caption)
                    }
                    .foregroundStyle(theme.inkTertiary)
                }
                .accessibilityElement(children: .combine)
                // Anchor the abstract 0–3 in something felt: a Calm·Base·Activated scale with a marker at
                // today's value — the same «vs your base» idea as the other three sheets. (Pase v2 #1)
                bandScale(model.score)
                Text(model.explanation)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A small dated qualifier for a fallback hero (always yesterday — freshness is capped there). Reads
    /// "ayer · sáb 20 jun". Formatted in UTC to match the day key's zone so it never drifts a day at the
    /// boundary. (FER-397)
    private func heroDateChip(_ dayKey: String) -> some View {
        let formatted = Self.dayParser.date(from: dayKey).map { Self.chipDateFormatter.string(from: $0) } ?? ""
        return HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath").font(StrandFont.footnote)
            Text("Yesterday · \(formatted)")
        }
        .font(StrandFont.footnote)
        .foregroundStyle(theme.inkTertiary)
        .accessibilityElement(children: .combine)
    }

    /// The cold-start empty hero: no usable signal anywhere. Honest "—" + how to get data.
    private var emptyHero: some View {
        emptyHeroShell("No stress reading yet. Wear your strap overnight and open this again after it syncs — or import your WHOOP history in Data Sources. Stress is read from your resting heart rate and HRV.")
    }

    /// Has history, but no reading in the last couple of days (anchor older than yesterday). Honest "—",
    /// and the trend + patterns below STILL render — the screen is never blanked. (FER-397)
    private var noRecentHero: some View {
        emptyHeroShell("No reading in the last couple of days. Wear your strap overnight and it'll refresh after it syncs — your history is below.")
    }

    /// Shared shell for the two empty-hero states: the «Stress» overline, a tertiary "—", and a line.
    private func emptyHeroShell(_ message: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stress").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("—").instrumentoHero(46).foregroundStyle(theme.inkTertiary)
            Text(message)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The band color: low → verdict (green), medium → warning (amber), high → critical (red). The band
    /// word is the datum, so it's the element that carries saturated hue. (DESIGN.md: color in the datum)
    ///
    /// SEMANTIC TRAFFIC-LIGHT, ON PURPOSE (Pase v2 #5): stress is EVALUATIVE — less is better — so it
    /// reads green→amber→red, unlike the other detail sheets, which tint by their METRIC's own hue
    /// (HRV teal, heart rose). Don't "fix" this to a single hue when you see the sheets side by side:
    /// the semaphore is what tells the user calm is good and activated is not.
    private func bandColor(_ band: StressBand) -> Color {
        band.dataColor(theme)
    }

    /// Sentence-case band word for the hero / legend — delegates to the single source on `StressBand`.
    private func bandWord(_ band: StressBand) -> LocalizedStringKey { band.displayWord }

    // MARK: - Mini-escala Calma·Base·Activado (Pase v2 #1)
    //
    // A three-third semaphore gradient (calm→base→activated) with a marker at today's 0–3 value, so the
    // abstract index sits on something the user can feel. No new math — the marker is `score / 3` across
    // the track, the gradient is the same band colors the hero word already uses.

    private func bandScale(_ score: Double) -> some View {
        let frac = CGFloat(max(0, min(3, score)) / 3)
        let gradient = LinearGradient(
            stops: [
                .init(color: theme.verdict,  location: 0),
                .init(color: theme.verdict,  location: 1.0 / 3),
                .init(color: theme.warning,  location: 1.0 / 3),
                .init(color: theme.warning,  location: 2.0 / 3),
                .init(color: theme.critical, location: 2.0 / 3),
                .init(color: theme.critical, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        return VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(gradient).opacity(0.85).frame(height: 8)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(theme.ink)
                        .frame(width: 3, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(theme.surface, lineWidth: 2))
                        .offset(x: geo.size.width * frac - 1.5)
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack(spacing: 0) {
                Text("Calm").foregroundStyle(theme.verdict)
                Spacer(minLength: 6)
                Text("Your base").foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 6)
                Text("Activated").foregroundStyle(theme.critical)
            }
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
        }
        .accessibilityHidden(true)
    }

    // MARK: - 2. Selector de periodo + Tendencia (línea diaria 0–3 sobre las bandas)

    private func trendBlock(_ model: StressModel) -> some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        let stat = ComparisonEngine.stat(window.values)
        let pairs = seriesPairs(model)
        // Compare the selected window against the equally-long window before it, not always the calendar
        // month. `.all` has no previous period, so no chip. (FER-264)
        let comparison = window.range.periodComparison(of: pairs)
        return InfoAccordion(
            title: "Trend",
            explanation: "Each point is your daily stress index. The bands behind it are the fixed Low / Moderate / High zones (0–1 / 1–2 / 2–3). The percentage compares this period's average with the previous period of the same length; Average, Lowest and Highest come from the range you selected. What matters isn't a single day — it's several days in a row drifting into a higher band.",
            accessibilityLabel: "Information about the stress trend",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // The daily 0–3 line over the three fixed band zones (Low / Moderate / High), drawn by
                // `TrendChart`'s native bands (FER-244) with explicit Y ticks at 0/1/2/3. Raw daily values,
                // not a moving average — the stress signal is read day to day.
                MetricTrendChart(
                    range: $range,
                    window: window,
                    theme: theme,
                    style: .init(
                        gradient: Gradient(colors: [theme.inkSecondary.opacity(0.5), theme.inkSecondary]),
                        showsArea: false,
                        valueRange: { _ in 0...3 },
                        valueFormat: { String(format: "%.1f", $0) },
                        bands: { stressBands(activeValue: $0) },
                        bandColor: { bandColor(band(forValue: $0)) },
                        yAxisValues: [0, 1, 2, 3],
                        accessibilityLabel: "Daily stress index, 0 to 3"
                    )
                ) {
                    emptyWell(text: "Not enough days in this range to draw a trend.")
                }
                if window.values.count > 1 {
                    TrendStatSummary(
                        average: fmt(stat.mean),
                        pctChange: comparison?.pctChange,
                        polarity: .lowerIsBetter,
                        period: window.range.comparisonPeriod ?? .month,
                        rangeLow: fmt(stat.min),
                        rangeHigh: fmt(stat.max),
                        theme: theme
                    )
                }
            }
        }
    }

    /// The three fixed stress zones as `TrendBand`s, with the one holding `activeValue` shaded as the bracket.
    private func stressBands(activeValue v: Double) -> [TrendBand] {
        [
            TrendBand(label: "Low", lower: nil, upper: 1, isActive: v < 1),
            TrendBand(label: "Moderate", lower: 1, upper: 2, isActive: v >= 1 && v < 2),
            TrendBand(label: "High", lower: 2, upper: nil, isActive: v >= 2),
        ]
    }

    /// Map a 0–3 value to its band (mirrors the model's fixed 0–1 / 1–2 / 2–3 thresholds).
    private func band(forValue v: Double) -> StressBand {
        v < 1 ? .low : (v < 2 ? .medium : .high)
    }

    // MARK: - Level 2 · «Your patterns» — calm time + consistency, fused to plain lines
    //
    // The re-sequencing (Detalles escalonados) folds «Calm time» and «Consistency» into one condensed
    // strip, and drops the standalone «Normal range» block: the Low/Moderate/High bands are already the
    // legend behind the trend line one level down, so the screen carries ONE dispersion read, not three.
    // The CV jargon stays in the ⓘ; the face is plain. No new math — calm time and the CV come straight
    // from the model.

    private func patternsBlock(_ model: StressModel) -> some View {
        // No ⓘ here (Pase v2 #4): the calm-time / steadiness (CV) jargon moved to «See the method».
        DetailBlock("Your patterns", theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
                patternLine(label: "Calm time",
                            value: model.calmTimeValue,
                            valueColor: theme.verdict,
                            note: "of last month")
                if let pct = consistency(model) {
                    patternLine(label: "Steadiness",
                                value: consistencyWord(pct),
                                note: "week to week")
                }
                // Cross-day observational lines, their natural home under «Your patterns»: the moment
                // of day (FER-378) and the recurring calendar event (FER-388). Non-causal; shown only
                // when the stats clear the bar. Read-only — the «Explore it in the Coach» handoff was
                // removed (Pase v2 #7): the insight stays a reading, not an entry point to a query.
                if patterns.first != nil || eventPatterns.first != nil {
                    Rectangle().fill(theme.hairline).frame(height: 1).padding(.vertical, 2)
                    if let p = patterns.first {
                        patternSentence(p)
                            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let e = eventPatterns.first {
                        eventPatternSentence(e)
                            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The localized, NON-causal sentence for a «moment of day» pattern ("tends to run", never
    /// "causes"). The structured `Pattern` is locale-free; the wording lives here. (FER-378)
    private func patternSentence(_ p: StressTimeOfDayPatterns.Pattern) -> Text {
        switch p.family {
        case .partOfDay(let part):
            let noun = partNoun(part)
            return p.higher ? Text("Your stress tends to run higher in the \(noun).")
                            : Text("Your stress tends to run lower in the \(noun).")
        case .weekday(let wd):
            let name = Calendar.current.weekdaySymbols[max(0, min(6, wd - 1))]
            return p.higher ? Text("Your stress tends to run higher on \(name).")
                            : Text("Your stress tends to run lower on \(name).")
        case .peakHour(let h):
            let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
            return Text("Your stress usually peaks around \(d.formatted(.dateTime.hour())).")
        }
    }

    private func partNoun(_ part: PartOfDay) -> String {
        switch part {
        case .morning:   return String(localized: "mornings")
        case .afternoon: return String(localized: "afternoons")
        case .evening:   return String(localized: "evenings")
        case .night:     return String(localized: "late nights")
        }
    }

    /// The localized, NON-causal sentence for a recurring-event pattern ("tends to coincide with", never
    /// "causes"). The event title is the user's own, interpolated verbatim. (FER-388)
    private func eventPatternSentence(_ e: StressEventPatterns.Pattern) -> Text {
        e.higher ? Text("«\(e.title)» tends to coincide with higher stress.")
                 : Text("«\(e.title)» tends to coincide with lower stress.")
    }

    /// One «Your patterns» line: a quiet overline label, a plain value (the datum), an optional note.
    private func patternLine(label: LocalizedStringKey, value: String,
                             valueColor: Color? = nil, note: LocalizedStringKey?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 8)
            Text(value).font(StrandFont.bodyNumber).foregroundStyle(valueColor ?? theme.ink)
            if let note {
                Text(note).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A plain word for steadiness from the CV percent (the number itself stays in the ⓘ).
    private func consistencyWord(_ pct: Int) -> String {
        switch pct {
        case ..<8:   return String(localized: "Very steady")
        case 8..<15: return String(localized: "Steady")
        default:     return String(localized: "Variable")
        }
    }

    // MARK: - Level 3 · «See your history» — the daily trend over the bands
    //
    // The analyst's view, one tap down. An in-place disclosure (NOT a navigation push). Holds just the
    // period-selector trend (the daily 0–3 line over the fixed Low/Mod/High bands + its legend). The
    // «mapa del día» (StressDayMapBlock) used to live here too, but FER-433 promoted it to Level 1.5.

    @ViewBuilder
    private func historySection(_ model: StressModel) -> some View {
        VStack(alignment: .leading, spacing: historyExpanded ? 22 : 0) {
            historyDisclosureHeader(caption: "trend · bands")
            if historyExpanded, model.fullTrend.count >= 2 {
                trendBlock(model)
            }
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
                    .font(.system(size: 13, weight: .semibold))
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

    // MARK: - Qué lo mueve — RHR / HRV de hoy vs tu base

    private func whatMovesItBlock(_ model: StressModel) -> some View {
        // No ⓘ here (Pase v2 #4): the jargon (z-score, RMSSD) lives once under «See the method» at the
        // foot; only the hero keeps an info button.
        DetailBlock("What moves it", theme: theme) {
            HStack(alignment: .top, spacing: NoopMetrics.gap) {
                markerCard(
                    label: "Resting HR",
                    value: model.rhrToday.map { "\($0)" } ?? "—",
                    delta: model.rhrDelta,
                    accent: theme.dataHeart,
                    higherIsStress: true)
                markerCard(
                    label: "HRV",
                    value: model.hrvToday.map { "\(Int($0.rounded()))" } ?? "—",
                    delta: model.hrvDelta,
                    accent: theme.dataHrv,
                    higherIsStress: false)
            }
        }
    }

    /// One marker as a surface card: today's value in its data hue, a signed delta vs baseline tinted by
    /// whether the move is TOWARD stress (warning) or recovery (verdict), and a quiet caption.
    private func markerCard(label: LocalizedStringKey, value: String,
                            delta: Double?, accent: Color, higherIsStress: Bool) -> some View {
        let deltaText: LocalizedStringKey
        let deltaColor: Color
        let caption: LocalizedStringKey
        if let delta, abs(delta) >= 0.5 {
            let up = delta > 0
            let isStressful = (up == higherIsStress)
            let mag = Int(abs(delta).rounded())
            deltaText = up ? "▲ +\(mag)" : "▼ −\(mag)"
            deltaColor = isStressful ? theme.warning : theme.verdict
            caption = up ? "above your base" : "below your base"
        } else {
            deltaText = "at base"
            deltaColor = theme.inkTertiary
            caption = "at your base"
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(StrandFont.number(22)).foregroundStyle(accent)
                Text(deltaText).font(StrandFont.footnote).foregroundStyle(deltaColor)
            }
            Text(caption).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NoopMetrics.cardPadding)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Consistencia (coeficiente de variación) — folded into «Your patterns»

    /// CV of the full stress series (nil when there aren't enough points). Feeds the «Your patterns»
    /// steadiness line; the standalone «Consistency» block folded into it (Detalles escalonados).
    private func consistency(_ model: StressModel) -> Int? {
        SeriesShape.coefficientOfVariation(model.fullTrend.map(\.value), window: 7).map { Int(($0 * 100).rounded()) }
    }

    // MARK: - Ver el método (DisclosureGroup, patrón de las otras pantallas)

    private func methodDisclosure(_ model: StressModel) -> some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                Text(model.usingStored
                     ? "Today's value is your recorded daily stress score (0–3). The trend, bands and markers are derived the same way."
                     : "We compare today's resting heart rate and HRV with your own 30-day baseline. A higher-than-usual resting HR and a lower-than-usual HRV both push the score up — classic signs the body is activated. The combined shift becomes a z-score sum, squashed onto 0–3 by a logistic curve: 0 calm, 1.5 at your baseline, 3 highly activated.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("«Calm time» is the share of the last month that sat in the Low band; «steadiness» is how much your daily index varies week to week (its coefficient of variation — lower is steadier). The Low / Moderate / High bands (0–1 / 1–2 / 2–3) are the same for everyone because the index is already adjusted to your own baseline. (Plews 2013)")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Combined resting-HR / HRV z-score through a logistic curve. HRV via RMSSD (Task Force, 1996). An estimate, not a diagnosis.")
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
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Wells

    private func emptyWell(text: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
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

    // MARK: - Series + format

    /// The full daily proxy series as `(day "yyyy-MM-dd", value)`, oldest→newest — for `ComparisonEngine`
    /// (which keys by day). Derived from `fullTrend`'s parsed dates.
    private func seriesPairs(_ model: StressModel) -> [(day: String, value: Double)] {
        model.fullTrend.map { (Self.dayParser.string(from: $0.date), $0.value) }
    }

    /// Format a 0–3 stress value at one decimal (the index's precision).
    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Short localized date for the fallback-hero chip ("sáb 20 jun"). UTC zone matches the day key so
    /// the rendered day never drifts at the midnight boundary; the format template localizes per the
    /// current locale. (FER-397)
    static let chipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()
}

// MARK: - Sheet item

/// Identifiable wrapper so the light «Instrumento» Detalle de Estrés can ride `.sheet(item:)` (the model
/// itself isn't Identifiable). Built fresh on tap in Cuerpo. (FER-241)
struct StressDetailItem: Identifiable {
    let id = UUID()
    let model: StressModel?
}

// MARK: - Sheet paper background (iOS 16.4+ presentationBackground)

private struct StressSheetPaperBackground: ViewModifier {
    let paper: Color
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(paper)
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
private func sampleStressModel(score: Double) -> StressModel? {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let f = StressDetailScreen.dayParser
    // 60 days of stored 0–3 stress so the model takes the stored path deterministically.
    let stored: [(day: String, value: Double)] = (0..<60).map { i in
        let date = cal.date(byAdding: .day, value: -(59 - i), to: today)!
        let v = i == 59 ? score : 1.4 + 0.8 * sin(Double(i) / 3.0)
        return (f.string(from: date), Swift.max(0, Swift.min(3, v)))
    }
    let days: [DailyMetric] = stored.map { row in
        DailyMetric(day: row.day, totalSleepMin: nil, efficiency: nil, deepMin: nil,
                    remMin: nil, lightMin: nil, disturbances: nil,
                    restingHr: 54 + Int((row.value - 1.5) * 4),
                    avgHrv: 60 - (row.value - 1.5) * 8,
                    recovery: nil, strain: nil, exerciseCount: nil)
    }
    return StressModel(days: days, stored: stored, todayKey: f.string(from: today))
}

#Preview("Stress detail — moderate") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StressDetailScreen(model: sampleStressModel(score: 1.8))
    }
}

#Preview("Stress detail — empty") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StressDetailScreen(model: nil)
    }
}
#endif
#endif
