#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

/// Measured-width key for the 90-day calendar heat grid (handoff v2, FER-832 / FER-860).
private struct StressCalWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - StressDetailScreen — el «Detalle de Estrés» en «Instrumento» (FER-241 · FER-860)
//
// Hermana de `StrainDetailScreen` (FER-859) y `RecoveryDetailScreen` (FER-857): reutiliza el esqueleto
// del handoff «Detalle de Tendencias Final» — héroe invertido (semáforo evaluativo) → mini-escala →
// mapa del día (instrumento firma, FER-433) → qué lo mueve → patrones → historial siempre abierto
// (`GraficaRangos`, serie diaria cruda) → calendario 90 días → método + sello. NO extiende
// `MetricDetailScreen`/`MetricDetailSpec`.
//
// Se presenta desde Cuerpo Y desde Hoy vía `.sheet(item:)` (FER-452), con el tema vivo pasado
// EXPLÍCITO (FER-162) y SIN `NavigationStack` anidado (FER-171). Consume `StressModel` TAL CUAL:
// cero matemática nueva. El semáforo (verde/ámbar/rojo) es a propósito: menos estrés es mejor.

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
    /// The stress series with each point's `Date` already parsed (from `fullTrend`) — the window math
    /// reads `date` straight from here. Built in `.task`. (FER-216 lesson)
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    /// The 90-day heat grid, built ONCE in `.task` (90 `DateFormatter` passes) instead of on every body
    /// eval — the recompute was jank on open. (FER-878+)
    @State private var stressHeatCache: [RecoveryDay] = []
    /// Detected cross-day «moment of day» patterns (loaded in `.task`). Empty → no line. (FER-378)
    @State private var patterns: [StressTimeOfDayPatterns.Pattern] = []
    /// Detected cross-day «by calendar-event» patterns (loaded in `.task`). Empty → no line. (FER-388)
    @State private var eventPatterns: [StressEventPatterns.Pattern] = []
    /// Measured available width for the 90-day calendar, so the heat grid sizes its cells to fill it.
    @State private var calWidth: CGFloat = 0
    /// The calendar day the user tapped, for the read-out below the grid. (FER-832)
    @State private var selectedStressDay: RecoveryDay? = nil
    /// The hero's ⓘ toggles the «Qué medimos» card right under the inverted field. (FER-860)
    @State private var infoOpen = false

    // MARK: - Body — el esqueleto estándar del handoff «Detalle de Tendencias Final» (FER-860)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let model {
                    // Level 1 · hero. Falls back to yesterday's reading (dated chip) when today is still
                    // incomplete; never blanks the screen. (FER-397)
                    if model.heroIsFresh {
                        heroField(model)
                        bandScale(model.score)
                    } else {
                        heroFlat(message: "No reading in the last couple of days. Wear your strap overnight and it'll refresh after it syncs: your history is below.")
                            .padding(NoopMetrics.screenPadding)
                    }
                    if infoOpen { whatWeMeasureCard }
                    // Level 1.5 · mapa del día BEFORE «qué lo mueve» (FER-433).
                    if let dayMap {
                        seccion(String(localized: "Stress through the day")) {
                            StressDayMapBlock(model: dayMap, theme: theme)
                        }
                    }
                    if model.heroIsFresh {
                        seccion(String(localized: "What moves it")) { whatMovesContent(model) }
                    }
                    if hasPatternsSection(model) {
                        seccion(String(localized: "Your patterns")) { patternsContent(model) }
                    }
                    if model.fullTrend.count >= 2 {
                        seccion(String(localized: "See your history")) { historyContent(model) }
                    }
                    if parsed.contains(where: { $0.value > 0 }) {
                        seccion(String(localized: "Calendar · 90 days")) { calendarContent }
                    }
                    Rectangle().fill(theme.hairline).frame(height: 1).padding(.horizontal, 20)
                    VStack(alignment: .leading, spacing: 10) {
                        metodoBlock(model)
                        OriginStamp(origin: .computed, when: originWhen(model), theme: theme)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                    .padding(EdgeInsets(top: 16, leading: 20, bottom: 26, trailing: 20))
                } else {
                    heroFlat(message: "No stress reading yet. Wear your strap overnight and open this again after it syncs, or import your WHOOP history in Data Sources. Stress is read from your resting heart rate and HRV.")
                        .padding(NoopMetrics.screenPadding)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
        .task {
            range = .month
            parsed = (model?.fullTrend ?? []).map {
                (Self.dayParser.string(from: $0.date), $0.date, $0.value)
            }
            stressHeatCache = buildStressHeat()
            if let patternsLoader { patterns = await patternsLoader() }
            if let eventPatternsLoader { eventPatterns = await eventPatternsLoader() }
        }
    }

    /// One skeleton section: a full-bleed `SeccionFranja` + content with handoff padding (14 · 20 · 22).
    private func seccion(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SeccionFranja(title, theme: theme)
            content()
                .padding(EdgeInsets(top: 14, leading: 20, bottom: 22, trailing: 20))
        }
    }

    // MARK: - 1. Héroe invertido — semáforo a propósito (evaluativo, menos es mejor)

    /// The inverted hero: the ONE field saturated at 100% of the day's band hue. Overline + ⓘ,
    /// 60pt Grotesk numeral (recRise), «/ 3», band-word capsule, two-tone verdict. Text is paper on hue.
    private func heroField(_ model: StressModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: MetricGlyph.stress.sfSymbol)
                    .font(StrandFont.glyph(.chevron))
                    .foregroundStyle(theme.paper)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text("Stress")
                    .font(InstrumentoType.grotesk(12, weight: .bold))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.paper)
                Spacer()
                Button {
                    withAnimation(StrandMotion.interactive) { infoOpen.toggle() }
                } label: {
                    Image(systemName: "info.circle")
                        .font(StrandFont.glyph(.chevron, weight: .regular))
                        .foregroundStyle(theme.paper.opacity(OnFieldOpacity.dimChrome))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What we measure")
            }
            if !model.anchorIsToday {
                heroDateChip(model.anchorDayKey)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(fmt(model.score))
                    .font(InstrumentoType.groteskNumber(60, weight: .bold))
                    .tracking(-2)
                    .foregroundStyle(theme.paper)
                    .recRise()
                Text(verbatim: "/ 3")
                    .font(InstrumentoType.grotesk(13))
                    .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                Text(bandWord(model.band))
                    .font(InstrumentoType.grotesk(13, weight: .semibold))
                    .foregroundStyle(theme.paper)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(theme.paper.opacity(OnFieldOpacity.capsule), in: Capsule())
            }
            // Keep `model.explanation` as one localized sentence from StressModel (content source of
            // truth). Two-tone mock split is secondary to not inventing new copy. (FER-860)
            Text(verbatim: model.explanation)
                .font(InstrumentoType.grotesk(15, weight: .semibold))
                .foregroundStyle(theme.paper)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 22, trailing: 20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bandColor(model.band))
        .accessibilityElement(children: .combine)
    }

    /// The ⓘ card under the hero: what the score measures, in plain language (mock copy, English source).
    private var whatWeMeasureCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What we measure")
                .font(InstrumentoType.grotesk(13, weight: .semibold))
                .foregroundStyle(theme.ink)
            Text(heroExplanation)
                .font(InstrumentoType.grotesk(12))
                .lineSpacing(3)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.control, theme: theme)
        // Aire estándar antes de la siguiente franja (igual que Recuperación). (FER-878+)
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 14, trailing: 20))
    }

    /// Flat hero for empty / no-recent states: no inverted field without a number.
    private func heroFlat(message: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentoScreenTitle("Stress", theme: theme, explanation: heroExplanation, glyph: .stress)
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "—")
                    .instrumentoHero(46)
                    .foregroundStyle(theme.inkTertiary)
                Text(message)
                    .font(StrandFont.headline)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Dated qualifier for a fallback hero (yesterday). UTC zone matches the day key. (FER-397)
    private func heroDateChip(_ dayKey: String) -> some View {
        let formatted = Self.dayParser.date(from: dayKey).map { Self.chipDateFormatter.string(from: $0) } ?? ""
        return HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath").font(StrandFont.footnote)
            Text("Yesterday · \(formatted)")
        }
        .font(StrandFont.footnote)
        .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
        .accessibilityElement(children: .combine)
    }

    /// Hero ⓘ copy — autonomic load on 0–3 (mock wording; no em-dash).
    private var heroExplanation: LocalizedStringKey {
        "Your autonomic load for the day: how activated your body is. We compare today's resting heart rate and HRV with your own 30-day baseline and map the combined shift onto a 0–3 scale (0 calm, 1.5 your baseline, 3 highly activated). It's an estimate, not a diagnosis."
    }

    /// SEMANTIC TRAFFIC-LIGHT ON PURPOSE: stress is evaluative (less is better). low→verdict,
    /// medium→warning, high→critical. Do not unify to a single hue. (Pase v2 #5 · FER-860)
    private func bandColor(_ band: StressBand) -> Color { band.dataColor(theme) }
    private func bandWord(_ band: StressBand) -> LocalizedStringKey { band.displayWord }

    // MARK: - Mini-escala Calma · Base · Activado (bajo el héroe)

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
                    RoundedRectangle(cornerRadius: 4, style: .continuous) // token-exempt: geometría de dato
                        .fill(gradient)
                        .opacity(0.85) // token-exempt: geometría de dato (barra de gradiente)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 2, style: .continuous) // token-exempt: geometría de dato
                        .fill(theme.ink)
                        .frame(width: 3, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous) // token-exempt: geometría de dato (marcador 3×16)
                            .strokeBorder(theme.paper, lineWidth: 2))
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
            .font(InstrumentoType.grotesk(10, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 6, trailing: 20))
        .accessibilityHidden(true)
    }

    // MARK: - 3. Qué lo mueve — FC reposo + VFC vs base

    private func whatMovesContent(_ model: StressModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                markerTile(
                    label: String(localized: "Resting HR"),
                    value: model.rhrToday.map { "\($0)" } ?? "—",
                    delta: model.rhrDelta,
                    accent: theme.dataHeart,
                    higherIsStress: true)
                markerTile(
                    label: String(localized: "HRV"),
                    value: model.hrvToday.map { "\(Int($0.rounded()))" } ?? "—",
                    delta: model.hrvDelta,
                    accent: theme.dataHrv,
                    higherIsStress: false)
            }
            BarraAncla(whatMovesAnchor(model), color: theme.warning, theme: theme)
        }
    }

    /// One marker as `TileSurface`: today's value in its data hue, signed delta tinted by whether the
    /// move is toward stress (amber) or calm (`positiveText`). |Δ| < 0.5 → neutral «at your base»
    /// (same threshold the previous presentation used — no new math).
    private func markerTile(label: String, value: String, delta: Double?,
                            accent: Color, higherIsStress: Bool) -> some View {
        let deltaStr: String?
        let deltaColor: Color?
        let caption: String
        if let delta, abs(delta) >= 0.5 {
            let up = delta > 0
            let isStressful = (up == higherIsStress)
            let mag = Int(abs(delta).rounded())
            deltaStr = up ? "▲ +\(mag)" : "▼ −\(mag)"
            deltaColor = isStressful ? theme.warning : theme.positiveText
            caption = up
                ? String(localized: "above your base")
                : String(localized: "below your base")
        } else {
            deltaStr = nil
            deltaColor = nil
            caption = String(localized: "at your base")
        }
        return TileSurface(label: label, value: value, valueColor: accent, valueSize: 21,
                           caption: caption, delta: deltaStr, deltaColor: deltaColor, theme: theme)
    }

    /// Short anchor from the same RHR/HRV deltas the tiles already show (presentation only).
    private func whatMovesAnchor(_ model: StressModel) -> String {
        let rhrOff = (model.rhrDelta.map { abs($0) >= 0.5 } ?? false)
        let hrvOff = (model.hrvDelta.map { abs($0) >= 0.5 } ?? false)
        let rhrUp = (model.rhrDelta ?? 0) > 0
        let hrvDn = (model.hrvDelta ?? 0) < 0
        if rhrOff && hrvOff && rhrUp && hrvDn {
            return String(localized: "Resting HR up and HRV down from your base: classic signs of activation.")
        }
        if rhrOff || hrvOff {
            return String(localized: "Markers vs your base: toward stress in amber, toward calm in green.")
        }
        return String(localized: "Both markers near your base today.")
    }

    // MARK: - 4. Tus patrones — calma + regularidad + observaciones (FER-378/388)

    /// Calm time / steadiness always when the model has them; observations card only when a pattern
    /// clears its sufficiency gate. If neither tiles nor observations have anything, the section hides.
    private func hasPatternsSection(_ model: StressModel) -> Bool {
        model.calmTimeValue != "—"
            || consistency(model) != nil
            || patterns.first != nil
            || eventPatterns.first != nil
    }

    private func patternsContent(_ model: StressModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                TileSurface(label: String(localized: "Calm time"),
                            value: model.calmTimeValue,
                            valueColor: theme.verdict,
                            valueSize: 21,
                            caption: String(localized: "of last month"),
                            theme: theme)
                TileSurface(label: String(localized: "Steadiness"),
                            value: consistency(model).map { consistencyWord($0) } ?? "—",
                            valueSize: 21,
                            caption: String(localized: "week to week"),
                            theme: theme)
            }
            if patterns.first != nil || eventPatterns.first != nil {
                observationsCard
            }
        }
    }

    /// Surface card: «LO QUE VEMOS EN TU HISTORIAL» + chip «TENDENCIA, NO CAUSA» + non-causal lines.
    private var observationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("What we see in your history")
                    .font(InstrumentoType.grotesk(10, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.inkTertiary)
                InlineFlagChip("trend, not cause", color: theme.inkTertiary)
            }
            if let p = patterns.first {
                patternSentence(p)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let e = eventPatterns.first {
                eventPatternSentence(e)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.card, theme: theme)
    }

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

    private func eventPatternSentence(_ e: StressEventPatterns.Pattern) -> Text {
        e.higher ? Text("«\(e.title)» tends to coincide with higher stress.")
                 : Text("«\(e.title)» tends to coincide with lower stress.")
    }

    private func consistencyWord(_ pct: Int) -> String {
        switch pct {
        case ..<8:   return String(localized: "Very steady")
        case 8..<15: return String(localized: "Steady")
        default:     return String(localized: "Variable")
        }
    }

    private func consistency(_ model: StressModel) -> Int? {
        SeriesShape.coefficientOfVariation(model.fullTrend.map(\.value), window: 7)
            .map { Int(($0 * 100).rounded()) }
    }

    // MARK: - 5. Ver tu historial — PeriodSelector + GraficaRangos (serie cruda) + tiles

    private func historyContent(_ model: StressModel) -> some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        let stat = ComparisonEngine.stat(window.values)
        let seriesPairs = parsed.map { ($0.day, $0.value) }
        let pct = range.periodComparison(of: seriesPairs)?.pctChange
        // Lower is better: green when stress drops, amber when it rises.
        let deltaHue: Color? = pct.map { $0 <= 0 ? theme.positiveText : theme.warning }
        return VStack(alignment: .leading, spacing: 8) {
            SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme) { $0.label }
            if window.values.count > 1 {
                GraficaRangos(
                    points: window.values, // raw daily, never smoothed
                    bands: Self.stressBands(theme),
                    ticks: [.init(v: 3, label: "3"), .init(v: 2, label: "2"),
                            .init(v: 1, label: "1"), .init(v: 0, label: "0")],
                    hue: theme.verdict, ymin: 0, ymax: 3,
                    startLabel: window.rows.first.flatMap { RecoveryDetailScreen.axisLabel($0.day) } ?? "",
                    endLabel: window.rows.last.flatMap { RecoveryDetailScreen.axisLabel($0.day) } ?? "",
                    mediaValue: fmt(stat.mean),
                    mediaNote: String(localized: "average of the \(range.name)"),
                    mediaDelta: pct.map { $0 >= 0 ? "+\(Int($0.rounded()))%" : "\(Int($0.rounded()))%" },
                    deltaColor: deltaHue,
                    countUnit: "d",
                    anchorMedia: String(localized: "Raw daily values, no smoothing: stress is read day to day. Lower is better."),
                    anchorRangos: String(localized: "How many days of the period fell in each band. Tap one to see its days on the chart."),
                    scrub: true,
                    labels: window.rows.map { RecoveryDetailScreen.axisLabel($0.day) ?? "" },
                    fmt: { String(format: "%.1f", $0) },
                    theme: theme)
                    .padding(.top, 6)
                    .id(range)
                HStack(alignment: .top, spacing: 8) {
                    TileSurface(label: String(localized: "Average"),
                                value: fmt(stat.mean),
                                theme: theme)
                    TileSurface(label: String(localized: "Range"),
                                value: "\(fmt(stat.min))–\(fmt(stat.max))",
                                theme: theme)
                    TileSurface(label: String(localized: "Today"),
                                value: model.heroIsFresh ? fmt(model.score) : "—",
                                valueColor: model.heroIsFresh ? bandColor(model.band) : nil,
                                theme: theme)
                }
                .padding(.top, 4)
            } else {
                ChartWell(theme).empty(text: "Not enough days in this range to draw a trend.")
                    .padding(.top, 6)
            }
        }
    }

    /// The three fixed stress lanes for `GraficaRangos` — same 0–1 / 1–2 / 2–3 cuts as `StressBand`.
    static func stressBands(_ theme: InstrumentoTheme) -> [GraficaRangos.Banda] {
        [
            .init(label: String(localized: "Activated"), lo: 2, hi: nil,
                  color: theme.critical, range: "2–3"),
            .init(label: String(localized: "Base"), lo: 1, hi: 2,
                  color: theme.warning, range: "1–2"),
            .init(label: String(localized: "Low"), lo: 0, hi: 1,
                  color: theme.verdict, range: "0–1"),
        ]
    }

    // MARK: - 6. Calendario · 90 días (semáforo evaluativo)

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            heatGrid
            heatReadout
            HeatLegend([(theme.critical, String(localized: "Activated").lowercased()),
                        (theme.warning, String(localized: "Moderate").lowercased()),
                        (theme.verdict, String(localized: "Calm").lowercased()),
                        (theme.rangeBand, String(localized: "no data"))], theme: theme)
        }
    }

    private func buildStressHeat() -> [RecoveryDay] {
        var vals: [String: Double] = [:]
        for r in parsed { vals[r.day] = r.value }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        // Ancla la ventana de 90 dias al dia LOCAL, igual que Recovery.buildHeat. Anclar al dia UTC
        // hace que en husos negativos, por la tarde, la ventana empiece en otro dia de la semana que
        // Recovery y el grid dibuje 13 vs 14 columnas, con celdas de otro tamano. Asi los cuatro
        // calendarios (Recuperacion, Sueno, Esfuerzo, Estres) miden igual. (FER calendarios mismo tamano)
        guard let today = Repository.parseDayKey(Repository.localDayKey(Date())) else { return [] }
        return stride(from: 89, through: 0, by: -1).compactMap { off -> RecoveryDay? in
            guard let date = cal.date(byAdding: .day, value: -off, to: today) else { return nil }
            return RecoveryDay(date: date.addingTimeInterval(12 * 3600),
                               score: vals[Self.dayParser.string(from: date)])
        }
    }

    /// ≥2 critical · 1–2 warning · <1 verdict — same cuts as the hero band.
    private func stressHeatTint(_ v: Double) -> Color {
        if v >= 2 { return theme.critical }
        if v >= 1 { return theme.warning }
        return theme.verdict
    }

    private var heatGrid: some View {
        // Celda dimensionada a 14 columnas FIJAS (helper compartido), no al conteo vivo, para que mida lo
        // mismo en las cuatro pantallas y todos los días (ver YearHeatStrip.rollingCellSize). (FER estable)
        let spacing: CGFloat = 4
        let cell = YearHeatStrip.rollingCellSize(width: calWidth, spacing: spacing)
        return YearHeatStrip(
            days: stressHeatCache,
            cellSize: cell,
            spacing: spacing,
            showsScrub: false,
            tint: stressHeatTint,
            emptyFill: theme.hairline,
            emptyStroke: theme.hairlineStrong,
            labelColor: theme.inkTertiary,
            onSelect: { selectedStressDay = $0 },
            selectionColor: theme.ink
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { g in
            Color.clear.preference(key: StressCalWidthKey.self, value: g.size.width)
        })
        .onPreferenceChange(StressCalWidthKey.self) { calWidth = $0 }
    }

    @ViewBuilder private var heatReadout: some View {
        if let d = selectedStressDay {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.chipDateFormatter.string(from: d.date))
                    .instrumentoOverline()
                    .foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                if let v = d.score {
                    Text(String(format: "%.1f", v))
                        .font(StrandFont.number(20))
                        .foregroundStyle(stressHeatTint(v))
                    Text(bandWord(StressBand(score: v)))
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkSecondary)
                } else {
                    Text("—")
                        .font(StrandFont.number(20))
                        .foregroundStyle(theme.inkTertiary)
                    Text("no reading")
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Tap a day to see its stress.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Método + sello

    private func metodoBlock(_ model: StressModel) -> some View {
        Metodo(title: String(localized: "How it's calculated"), theme: theme) {
            Text(model.usingStored
                 ? "Today's value is your recorded daily stress score (0–3). The trend, bands and markers are derived the same way."
                 : "We compare today's resting heart rate and HRV with your own 30-day baseline. A higher-than-usual resting HR and a lower-than-usual HRV both push the score up: classic signs the body is activated. The combined shift becomes a z-score sum, squashed onto 0–3 by a logistic curve: 0 calm, 1.5 at your baseline, 3 highly activated.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("«Calm time» is the share of the last month that sat in the Low band; «steadiness» is how much your daily index varies week to week (its coefficient of variation: lower is steadier). The Low / Moderate / High bands (0–1 / 1–2 / 2–3) are the same for everyone because the index is already adjusted to your own baseline. (Plews 2013)")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Combined resting-HR / HRV z-score through a logistic curve. HRV via RMSSD (Task Force, 1996). An estimate, not a diagnosis.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Origin stamp «when» — the day's anchor the screen already computes (today / yesterday).
    private func originWhen(_ model: StressModel) -> String {
        if model.anchorIsToday {
            return String(localized: "today")
        }
        let formatted = Self.dayParser.date(from: model.anchorDayKey)
            .map { Self.chipDateFormatter.string(from: $0) } ?? ""
        return String(localized: "Yesterday · \(formatted)")
    }

    // MARK: - Format

    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    /// The canonical UTC day-key formatter — read side of the day-key contract (FER-754).
    static let dayParser = DayKey.utcFormatter

    /// Short localized date for the fallback-hero chip ("sáb 20 jun"). UTC zone matches the day key. (FER-397)
    static let chipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()
}

// MARK: - Sheet item

/// Identifiable wrapper so the light «Instrumento» Detalle de Estrés can ride `.sheet(item:)`. (FER-241)
struct StressDetailItem: Identifiable {
    let id = UUID()
    let model: StressModel?
}

// MARK: - Preview

#if DEBUG
private func sampleStressModel(score: Double) -> StressModel? {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let f = StressDetailScreen.dayParser
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

#Preview("Stress detail: moderate") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StressDetailScreen(model: sampleStressModel(score: 1.8))
    }
}

#Preview("Stress detail: empty") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StressDetailScreen(model: nil)
    }
}
#endif
#endif
