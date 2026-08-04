#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import CenitStore
import Foundation
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - RecoveryDetailScreen — el «Detalle de Recuperación» en «Instrumento» (FER-225)
//
// Hermana de `MetricDetailScreen` (FER-185), igual que `SleepDetailScreen` (FER-212): REUSA su lenguaje
// visual (el scaffold `DetailBlock`, el hero, `InfoAccordion`, `theme: InstrumentoTheme` explícito,
// `sheetPaper`, `ScrollView`→`VStack`, `methodDisclosure`, los wells) pero con su propio modelo.
// NO extiende `MetricDetailScreen`/`MetricDetailSpec` (esos son para vitales de serie ESCALAR única —
// HRV/FC/Respiración); la recuperación es un SCORE COMPUESTO con bloques propios (desglose por driver,
// calendario, carga). Reemplaza, para recovery, la vieja `MetricInfoSheet` que abrían Cuerpo y Hoy.
//
// Se presenta vía `.sheet(item:)` con el tema vivo pasado EXPLÍCITO (no propaga por `.sheet`, FER-162) y
// SIN `NavigationStack` anidado (un stack anidado cruzando el path de la tab crasheaba SwiftUI, FER-171).
//
// Ocho bloques, cada uno con su ⓘ (`InfoAccordion`) salvo el método (DisclosureGroup): 1) Hero (score en
// color de banda) · 2) Qué lo explica (estado por driver vs tu base + peso) · 3) Tu rango normal · 4)
// Selector de periodo + Tendencia (+ Prom/Mediana/Mín/Máx/σ) · 5) Consistencia (CV) · 6) Calendario 90d
// (`YearHeatStrip` re-tintado, a todo el ancho) · 7) Carga reciente (ACWR/monotonía como CONTEXTO, sin
// claim de lesión — Impellizzeri 2020) · 8) Ver el método.
//
// Consume `StrandAnalytics` TAL CUAL: el score y la banda de `RecoveryScorer`, el estado por driver y la
// carga de `ReadinessEngine` (sus señales comparten la misma línea base que el scorer, así que recovery y
// readiness nunca cuentan dos historias distintas), la calibración de `RecoveryScorer.calibrationNights`,
// y las estadísticas de `ComparisonEngine`. No crea matemática nueva (el pronóstico es FER-188).

extension ReadinessEngine.Flag {
    /// The one flag → «Instrumento» color mapping, shared by every recovery surface (the Detalle's
    /// driver rows and the summary's «Qué la movió hoy», FER-628): good → verdict, neutral → quiet
    /// ink, watch → warning, bad → critical.
    func color(_ theme: InstrumentoTheme) -> Color {
        switch self {
        case .good:    return theme.verdict
        case .neutral: return theme.inkSecondary
        case .watch:   return theme.warning
        case .bad:     return theme.critical
        }
    }
}

/// Light «Instrumento» Detalle de Recuperación. Built once from a `RecoveryDetailModel` (the caller injects
/// the model so the screen stays DB-free), themed explicitly for the sheet boundary.
struct RecoveryDetailScreen: View {
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    /// Everything the screen draws, derived ONCE by the caller from `repo` (no DB access here).
    let model: RecoveryDetailModel

    /// The trend block's period window (W/M/3M/6M/1Y/ALL). Defaults to a month.
    @State private var range: ExploreRange = .month
    /// The recovery series with each `day` string parsed to a `Date` exactly ONCE (not per slice / per
    /// render) — the window math reads `date` straight from here. Built in `.task`. (FER-216 lesson)
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    /// The calendar day the user tapped, for the read-out below the grid (touch — FER-235).
    @State private var selectedHeatDay: RecoveryDay? = nil
    /// The hero's ⓘ toggles the «Qué medimos» card right under the inverted field. (FER-857)
    @State private var infoOpen = false
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    // MARK: - Body — el esqueleto estándar del handoff «Detalle de Tendencias Final» (FER-857)
    //
    // Héroe invertido → «Hoy, vs tu normal» (instrumento firma) → «Qué cambió desde ayer» →
    // Panorama → Tendencia (PeriodSelector + GraficaRangos + tiles) → Calendario 90 días →
    // Método + sello. Cada sección abre con `SeccionFranja` a sangre; ningún caption flota
    // (todo `BarraAncla`); nada plegado salvo el método.

    var body: some View {
        ScrollView {
            // FER-964: Lazy so the model reveal (FER-954 swap) only builds the visible sections —
            // an eager VStack laid out the whole fold (charts + Calendario 90 + método) in one frame.
            LazyVStack(alignment: .leading, spacing: 0) {
                if !model.loaded {
                    Group {
                        heroFlat
                        ChartWell(theme).loading(height: 160).padding(.top, 22)
                    }
                    .padding(CenitMetrics.screenPadding)
                } else if model.calibration != nil {
                    VStack(alignment: .leading, spacing: 22) {
                        heroFlat
                        calibrationBlock
                        metodoBlock
                        sourceFooter
                    }
                    .padding(CenitMetrics.screenPadding)
                } else if model.hasData {
                    if model.score != nil {
                        heroField
                    } else {
                        heroFlat.padding(CenitMetrics.screenPadding)
                    }
                    if infoOpen { whatWeMeasureCard }
                    if hasPanorama {
                        seccion(String(localized: "Panorama")) { panoramaContent }
                    }
                    if model.series.count >= 2 {
                        seccion(String(localized: "Trend")) { trendContent }
                    }
                    seccion(String(localized: "Calendar · 90 days")) { calendarContent }
                    PieMetodo(theme: theme) {
                        metodoBlock
                    } sello: {
                        sourceFooter
                    }
                } else {
                    // Empty (loaded, no calibration, no data): the flat hero's reading says it.
                    heroFlat.padding(CenitMetrics.screenPadding)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
        // FER-954: re-run when the placeholder model is replaced by the real one (same seam as
        // Sueño, FER-953); the parse hop is small here (the 90-day heat is already built off-main
        // inside `buildDetached`), but it stays consistent with the rest of the pattern.
        .task(id: model.loaded) {
            range = .month
            guard model.loaded else { return }   // placeholder pass — nothing to parse yet (FER-954)
            let series = model.series
            parsed = await Task.detached(priority: .userInitiated) {
                series.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
            }.value
        }
        .enableInjection()
    }

    /// One skeleton section: shared `SeccionBloque` (franja + handoff padding 14 · 20 · 22).
    private func seccion(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        SeccionBloque(title, theme: theme, content: content)
    }

    // MARK: - 1. Héroe invertido — el estado pinta el campo (FER-857)

    /// The inverted hero: the ONE field saturated at 100% of the day's band hue. Overline + ⓘ,
    /// 60pt Grotesk numeral (recRise), «+N vs tu base» capsule, verdict line. Text is paper on hue.
    private var heroField: some View {
        let score = model.score ?? 0
        return HeroInvertido(
            glyph: .recovery,
            title: "Recovery",
            hue: bandColor,
            theme: theme,
            onInfo: { withAnimation(StrandMotion.interactive) { infoOpen.toggle() } },
            numeral: {
                HeroNumeral("\(score)", suffix: "/100", theme: theme) {
                    if let base = baseValue {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: (score - base) >= 0 ? "+\(score - base)" : "\(score - base)")
                                .font(InstrumentoType.groteskNumber(13, weight: .semibold))
                                .foregroundStyle(theme.paper)
                            Text("vs your base")
                                .font(InstrumentoType.grotesk(11))
                                .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                        }
                        .heroCapsule(theme: theme)
                    }
                }
            },
            verdict: {
                HeroVeredictoBicolor(word: heroVerdictWord, clause: heroVerdictClause, theme: theme)
            }
        )
    }

    /// The ⓘ card under the hero: what the score measures, in plain language.
    private var whatWeMeasureCard: some View {
        QueMedimosCard(title: "What we measure", explanation: heroExplanation, theme: theme)
    }

    /// The flat hero for score-less states (loading / calibrating / empty / offline-with-history):
    /// the pre-handoff identity — no inverted field for a number we don't have.
    private var heroFlat: some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentoScreenTitle("Recovery", theme: theme, explanation: heroExplanation, glyph: .recovery)
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "—")
                    .instrumentoHero(46)
                    .foregroundStyle(theme.inkTertiary)
                Text(heroReading)
                    .font(StrandFont.headline)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The hero verdict word by band (short — the datum already spoke).
    private var heroVerdictWord: LocalizedStringKey {
        switch RecoveryScorer.band(Double(model.score ?? 0)) {
        case "green":  return "Ready to train"
        case "yellow": return "Recovering"
        default:       return "Prioritize rest"
        }
    }

    /// The verdict's quiet second clause.
    private var heroVerdictClause: LocalizedStringKey {
        switch RecoveryScorer.band(Double(model.score ?? 0)) {
        case "green":  return "above your baseline"
        case "yellow": return "train, but keep it controlled"
        default:       return "rest comes first today"
        }
    }

    /// Your base: the 30-day mean of the recovery series (the same stat the normal range uses) —
    /// feeds the hero capsule and the trend's reference line. No new math. (FER-857)
    private var baseValue: Int? {
        normalRange.map { (r: (lo: Int, hi: Int, n: Int)) -> Int in
            let mid: Double = (Double(r.lo) + Double(r.hi)) / 2.0
            return Int(mid.rounded())
        }
    }

    /// The hero ⓘ copy: recovery blends HRV, resting HR, sleep and breathing vs your baseline.
    private var heroExplanation: LocalizedStringKey {
        return "Recovery blends several signals from your nervous system, your HRV above all, plus resting heart rate, sleep and breathing, and compares them with your own baseline from recent weeks. It's an estimate of how ready your body is today, not a diagnosis. (Buchheit 2014)"
    }

    /// The score's band color: green ≥67 → verdict, yellow 34–67 → warning, red <34 → critical. The hero
    /// numeral is the datum, so it's the one element that carries saturated hue.
    private var bandColor: Color {
        guard let s = model.score else { return theme.inkTertiary }
        switch RecoveryScorer.band(Double(s)) {
        case "green":  return theme.verdict
        case "yellow": return theme.warning
        default:       return theme.critical
        }
    }

    private var heroReading: LocalizedStringKey {
        if let s = model.score {
            switch RecoveryScorer.band(Double(s)) {
            case "green":  return "Above your baseline: your body is ready for a strong day."
            case "yellow": return "Recovering: train, but keep it controlled."
            default:       return "Low: prioritize rest today."
            }
        }
        if model.calibration != nil { return "Calibrating: we need a few more nights of sleep." }
        // Offline / no reading today but history exists: be honest the day's number is missing without
        // implying a brand-new user (the trend and calendar below are populated). (FER-225, QA O1)
        if !model.series.isEmpty { return "No reading from last night yet: your recent history is below." }
        return "No recovery yet. Wear your Apple Watch to sleep and open this again after it syncs."
    }

    /// The flag → theme color (used by the Panorama load cell).
    private func flagColor(_ flag: ReadinessEngine.Flag) -> Color { flag.color(theme) }

    // MARK: - 2.5 Panorama — pronóstico + rango normal + estabilidad + carga, en un grid 2×2 (handoff v2, FER-831)
    //
    // Fuses the former «Tomorrow, if you rest the same» (forecast) and «Your patterns» (normal range +
    // steadiness + load) blocks into one 2×2 «Panorama» grid, per the Tendencias v2 handoff. No new math:
    // the forecast is `RecoveryForecast` (presentation-only), the range is `ComparisonEngine.stat` ± σ,
    // steadiness is the CV word, the load cell is `model.load.bandLabel`. The σ/CV/ACWR jargon that lived in
    // the «Your patterns» ⓘ is dropped from the face; «See the method» remains its home.

    /// Whether there's anything to show in the Panorama (otherwise the whole block is skipped).
    private var hasPanorama: Bool {
        model.forecast != nil || normalRange != nil || consistency != nil || model.load != nil
    }

    private var panoramaContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let f = model.forecast {
                forecastStrip(f)
            }
            HStack(alignment: .top, spacing: 8) {
                TileSurface(label: String(localized: "Usually"),
                            value: normalRange.map { "\($0.lo)–\($0.hi)" } ?? "—",
                            theme: theme)
                TileSurface(label: String(localized: "Steadiness"),
                            value: consistency.map { consistencyWord($0) } ?? "—",
                            theme: theme)
                // Sin ~2 semanas de esfuerzo la carga no se puede leer, y un «—» mudo no
                // distingue «no tengo dato» de «todavía te estoy conociendo». Dice la misma
                // palabra que el resto de la app (FER-33 · F5.4).
                TileSurface(label: String(localized: "Load"),
                            value: model.load?.bandLabel ?? String(localized: "Calibrating"),
                            valueColor: model.load.map { flagColor($0.bandFlag) },
                            theme: theme)
            }
            BarraAncla(String(localized: "A forecast is a projection, not a guarantee."),
                       color: theme.verdict, theme: theme)
        }
    }

    /// The forecast strip — dato primero: «↗ ~73» (22pt Grotesk, verdict hue) + «mañana, al alza» +
    /// the «proyección» tag, on a verdict-tinted wash. `RecoveryForecast` untouched. (FER-831/857)
    private func forecastStrip(_ f: RecoveryForecast.Result) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: forecastDatum(f))
                .font(InstrumentoType.groteskNumber(22, weight: .bold))
                .foregroundStyle(theme.verdict)
            Text(forecastPhrase(f.direction))
                .font(InstrumentoType.grotesk(14, weight: .semibold))
                .foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            Text("projection")
                .font(InstrumentoType.grotesk(10, weight: .medium))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(theme.inkTertiary)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.control, theme: theme,
                         fill: theme.tint(theme.verdict),
                         stroke: theme.verdict.opacity(StrandOpacity.tintFillStrong))
        .accessibilityElement(children: .combine)
    }

    /// «↗ ~73» — the direction arrow + the center of your normal range (arrow only when no range yet).
    private func forecastDatum(_ f: RecoveryForecast.Result) -> String {
        let arrow: String
        switch f.direction {
        case .rising:  arrow = "↗"
        case .steady:  arrow = "→"
        case .falling: arrow = "↘"
        }
        guard let r = normalRange else { return arrow }
        let mid = Int(((Double(r.lo) + Double(r.hi)) / 2).rounded())
        return "\(arrow) ~\(mid)"
    }

    /// «mañana, al alza / estable / a la baja».
    private func forecastPhrase(_ d: RecoveryForecast.Direction) -> LocalizedStringKey {
        switch d {
        case .rising:  return "tomorrow, rising"
        case .steady:  return "tomorrow, steady"
        case .falling: return "tomorrow, falling"
        }
    }

    /// The normal-range pair (lo, hi, n) over the last 30 days, or nil when there aren't enough days.
    private var normalRange: (lo: Int, hi: Int, n: Int)? {
        let vals = Array(model.series.suffix(30)).map(\.value)
        let s = ComparisonEngine.stat(vals)
        guard s.n >= 2 else { return nil }
        return (Int(Swift.max(0, s.mean - s.stdev).rounded()),
                Int(Swift.min(100, s.mean + s.stdev).rounded()),
                s.n)
    }

    /// A plain word for steadiness from the CV percent (the number itself stays in «See the method»).
    private func consistencyWord(_ pct: Int) -> String {
        switch pct {
        case ..<8:   return String(localized: "Very steady")
        case 8..<15: return String(localized: "Steady")
        default:     return String(localized: "Variable")
        }
    }

    // MARK: - 4. Recuperación por nivel (línea + niveles tocables + «N de tus últimos M días» + «Media …»)
    //
    // FER-703 collapsed the two recovery line charts into one. The separate 7-day-MA «Trend» block was
    // removed (redundant second line of the same metric, and its moving average clashed with this block's
    // period-average caption — «average of what?»). This is now the ONLY recovery line; it carries the
    // period-average caption («Media …») that used to sit with the trend. (FER-572 · FER-594 · FER-703)

    /// The trend block per the handoff (FER-857): the W/M/3M/6M/1Y/ALL `SegmentedPillControl` +
    /// `GraficaRangos` (Media ⇄ Rangos over the FIXED recovery levels, wash 70–88, «tu base» reference)
    /// + the MEDIA/RANGO/HOY tiles. Thresholds come from `MetricLevels.levels(for: .recovery)` — the
    /// same source as everywhere else; the base is the same 30-day mean the hero capsule uses.
    private var trendContent: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        let stat = ComparisonEngine.stat(window.values)
        let pct = range.periodComparison(of: model.series)?.pctChange
        return VStack(alignment: .leading, spacing: 8) {
            SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme) { $0.label }
            GraficaRangos(
                points: window.values,
                bands: Self.recoveryBands(theme),
                ticks: [.init(v: 88, label: "88"), .init(v: 70, label: "70"),
                        .init(v: 50, label: "50"), .init(v: 25, label: "25")],
                wash: .init(lo: 70, hi: 88),
                refLine: baseValue.map { .init(v: Double($0), label: String(localized: "your base · \($0)")) },
                hue: bandColor, ymin: 20, ymax: 95,
                startLabel: window.rows.first.flatMap { MetricWindowMath.axisLabel($0.day) } ?? "",
                endLabel: window.rows.last.flatMap { MetricWindowMath.axisLabel($0.day) } ?? "",
                mediaValue: window.values.count > 1 ? Self.levelWord(stat.mean) : "—",
                mediaNote: String(localized: "your typical band this \(range.name)"),
                mediaDelta: pct.map { $0 >= 0 ? "+\(Int($0.rounded()))%" : "\(Int($0.rounded()))%" },
                deltaColor: pct.map { $0 >= 0 ? theme.positiveText : theme.warning },
                countUnit: "d",
                anchorRangos: String(localized: "How many days of the period fell in each band. Tap one to see its days on the chart."),
                scrub: true,
                labels: window.rows.map { MetricWindowMath.axisLabel($0.day) ?? "" },
                theme: theme)
                .padding(.top, 6)
                .id(range)  // fresh entrance (recFade) when the period changes
            HStack(alignment: .top, spacing: 8) {
                TileSurface(label: String(localized: "Average"),
                            value: window.values.count > 1 ? "\(Int(stat.mean.rounded()))" : "—",
                            theme: theme)
                TileSurface(label: String(localized: "Range"),
                            value: window.values.count > 1
                                ? "\(Int(stat.min.rounded()))–\(Int(stat.max.rounded()))" : "—",
                            theme: theme)
                TileSurface(label: String(localized: "Today"),
                            value: model.score.map { "\($0)" } ?? "—",
                            valueColor: model.score != nil ? bandColor : nil,
                            theme: theme)
            }
            .padding(.top, 4)
        }
    }

    /// The five fixed recovery lanes for `GraficaRangos`, colored low→high with the deep-red /
    /// red / amber / green / deep-green ladder. Thresholds from `MetricLevels` — never restated.
    static func recoveryBands(_ theme: InstrumentoTheme) -> [GraficaRangos.Banda] {
        let colors: [String: Color] = [
            "depleted": theme.criticalDeep,
            "low":      theme.critical,
            "moderate": theme.warning,
            "primed":   theme.verdict,
            "peak":     theme.verdictDeep,
        ]
        // Lanes list high→low (the chart wash order is value-based, so list order only affects rows).
        return MetricLevels.levels(for: .recovery).reversed().map { level in
            GraficaRangos.Banda(
                label: String(localized: String.LocalizationValue(MetricLevels.name(for: level.key))),
                lo: level.lower, hi: level.upper,
                color: colors[level.key] ?? theme.ink,
                range: Self.rangeText(level))
        }
    }

    /// «≥ 88» / «70–88» / «< 25» from a level's half-open bounds.
    private static func rangeText(_ level: MetricLevels.Level) -> String {
        switch (level.lower, level.upper) {
        case let (lo?, hi?): return "\(Int(lo))–\(Int(hi))"
        case let (lo?, nil): return "≥ \(Int(lo))"
        case let (nil, hi?): return "< \(Int(hi))"
        default:             return ""
        }
    }

    /// The band word for a score («A punto» for the period mean in the chart header).
    private static func levelWord(_ value: Double) -> String {
        let key = MetricLevels.levels(for: .recovery).first {
            ($0.lower == nil || value >= $0.lower!) && ($0.upper == nil || value < $0.upper!)
        }?.key ?? "moderate"
        return String(localized: String.LocalizationValue(MetricLevels.name(for: key)))
    }

    // MARK: - 5. Consistencia (coeficiente de variación)

    /// CV of the full recovery series (nil when there aren't enough points). Feeds the «Your patterns»
    /// steadiness line; the standalone «Consistency» block folded into it (Detalles escalonados).
    private var consistency: Int? {
        SeriesShape.coefficientOfVariation(model.series.map(\.value), window: 7).map { Int(($0 * 100).rounded()) }
    }

    // MARK: - Level 3 · «See your history» — the 90-day calendar, collapsed by default
    //
    // The analyst's view, one tap down. An in-place disclosure (NOT a navigation push); the chevron and
    // copy mirror «See the method». Holds the 90-day calendar. (The period-selector trend that used to sit
    // here alongside it was removed in FER-703.)

    // MARK: - Calendario · 90 días (HeatCalendarSection compartido) — FER-857/FER-975

    private var calendarContent: some View {
        HeatCalendarSection(
            days: model.heat,
            selected: $selectedHeatDay,
            tint: heatTint,
            readoutValue: { "\(Int($0.rounded()))" },
            readoutWord: { bandWord($0) },
            emptyHint: "Tap a day to see its recovery.",
            legend: [(theme.verdict, String(localized: "ready")),
                     (theme.warning, String(localized: "recovering")),
                     (theme.critical, String(localized: "Low").lowercased()),
                     (theme.rangeBand, String(localized: "no data"))],
            theme: theme
        )
    }

    /// A short band word for the calendar read-out (matches the hero's band coloring).
    private func bandWord(_ score: Double) -> LocalizedStringKey {
        switch RecoveryScorer.band(score) {
        case "green":  return "Ready"
        case "yellow": return "Recovering"
        default:       return "Low"
        }
    }

    /// The cell tint in «Instrumento» colors: the same three band roles the hero uses (green/amber/red),
    /// so the calendar and the hero never disagree, and only theme tokens carry color. (FER-225)
    private func heatTint(_ score: Double) -> Color {
        switch RecoveryScorer.band(score) {
        case "green":  return theme.verdict
        case "yellow": return theme.warning
        default:       return theme.critical
        }
    }

    // MARK: - Ver el método (DisclosureGroup, patrón de las otras pantallas)

    private var metodoBlock: some View {
        Metodo(title: String(localized: "How it's calculated"), theme: theme) {
            Text("Each signal becomes a score of how far above or below your personal average it sits (a z-score, in σ). They're combined with the weights shown and mapped onto a 0–100 scale through a logistic curve, calibrated so a typical day lands near 58. It's an estimate, not a diagnosis.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("The «vs your base» bars show each signal's deviation in σ (above your base = right). HRV, resting heart rate and respiration are z-scored that way; sleep and skin temperature carry no σ, so they show their state, not a position. Your base and normal range are your recent average ± one σ. Steadiness is the coefficient of variation (CV). Training load is the acute:chronic workload ratio (ACWR): context for recovery, never an injury claim.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("A composite of z-scores through a logistic curve. HRV via RMSSD (Task Force, 1996; Plews 2013; Buchheit 2014; Impellizzeri 2020).")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Calibrando (no hay score todavía)

    private var calibrationBlock: some View {
        let n = model.calibration ?? 0
        let needed = model.nightsNeeded
        return VStack(alignment: .leading, spacing: 12) {
            Text("Not enough history yet")
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
            HStack(alignment: .firstTextBaseline) {
                Text("Calibrating").groteskOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("\(n) / \(needed) nights")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline).frame(height: 6)
                    Capsule().fill(theme.dataRecovery)
                        .frame(width: max(6, geo.size.width * CGFloat(n) / CGFloat(max(needed, 1))), height: 6)
                }
            }
            .frame(height: 6)
            Text("We need a few more nights of sleep to learn your baseline before we score your recovery. We'd rather not show a made-up number.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
    }

    // MARK: - Source footer

    private var sourceFooter: some View {
        // Recovery is a score computed on-device from your signals → «Calculado». (FER-803)
        OriginStamp(origin: .computed, when: String(localized: "today"), theme: theme)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    /// The canonical UTC day-key formatter — read side of the day-key contract (FER-754).
    static let dayParser = DayKey.utcFormatter

}

// MARK: - Sheet item

/// Identifiable wrapper so the light «Instrumento» Detalle de Recuperación can ride `.sheet(item:)` (the
/// model itself isn't Identifiable). Shared by Cuerpo (the hero) and Hoy (the verdict numeral). (FER-225)
struct RecoveryDetailItem: Identifiable {
    let id: UUID
    let model: RecoveryDetailModel
    /// FER-954: an explicit `id` lets the built model swap in under the SAME presentation identity
    /// (same pattern as `SleepDetailItem`, FER-953).
    init(id: UUID = UUID(), model: RecoveryDetailModel) { self.id = id; self.model = model }
}

// MARK: - RecoveryDetailModel — every derivation the screen draws, built ONCE from the repo
//
// The data layer of the recovery detail, lifted out of the view. `RecoveryDetailScreen` is pure
// presentation over this; the caller (Cuerpo / Hoy) builds it with `RecoveryDetailModel.build(...)` from
// the in-memory dashboard so the screen stays DB-free. It CONSUMES `StrandAnalytics` as-is: the score from
// `repo.today.recovery`, the band from `RecoveryScorer`, the per-driver state and load from `ReadinessEngine`
// (whose signals share the recovery scorer's baseline, so they never disagree), the calibration progress
// from `RecoveryScorer.calibrationNights`. No new math (the forecast is FER-188).

struct RecoveryDetailModel {

    /// Recent training load, as honest context (never an injury claim — Impellizzeri 2020).
    struct LoadState: Equatable {
        let acwr: Double
        let monotony: Double?
        /// The load-band's short label (localized) + the flag that colors it.
        let bandLabel: String
        let bandFlag: ReadinessEngine.Flag
    }

    /// Today's recovery score (0–100, rounded), or nil while calibrating / offline with no reading.
    let score: Int?
    /// Cold-start progress: nights banked toward the seed gate (1..<seed) while recovery is unscored; nil
    /// once recovery exists or there's no night data yet. Drives the calibrating state.
    let calibration: Int?
    /// The seed gate (`Baselines.minNightsSeed`), for the "N / seed nights" copy.
    let nightsNeeded: Int
    /// The full recovery series (oldest → newest), `(day "yyyy-MM-dd", value)`, for trend / normal range / CV.
    let series: [(day: String, value: Double)]
    /// The trailing 90 calendar days as `RecoveryDay` (score nil for days with no reading) for the heat grid.
    let heat: [RecoveryDay]
    /// Recent load context (nil when there isn't enough strain history for an ACWR).
    let load: LoadState?
    /// Whether the repo finished its first load (drives the loading vs empty hero copy).
    let loaded: Bool
    /// Whether today's reading is Apple-sourced (for the source footer).
    let isAppleHealth: Bool
    /// Tomorrow's one-day recovery projection (estimate + range + direction), or nil while there isn't
    /// enough base (< ~2 weeks of valid days) — then the block shows its "still calibrating" state. (FER-277)
    let forecast: RecoveryForecast.Result?

    /// True when there's a score or any stored recovery history to draw (the rich path); false → empty.
    var hasData: Bool { score != nil || !series.isEmpty }

    // MARK: - Build

    /// Runs `build` off the MainActor (FER-954, same seam as `SleepDetailModel.buildDetached` /
    /// FER-953): snapshots the inputs from `repo` on the MainActor (value-type copies), then hops the pure
    /// derivation to a background executor; only the finished model returns to main. Supersedes the
    /// synchronous `build(repo:)`. Hoy, Cuerpo and Entrenar all open the recovery detail through this.
    @MainActor
    static func buildDetached(repo: Repository) async -> RecoveryDetailModel {
        let key = Repository.localDayKey(Date())
        let days = repo.days, today = repo.today, appleHealthDays = repo.appleHealthDays
        let loaded = repo.loaded, importedSleep = repo.importedSleep
        return await Task.detached(priority: .userInitiated) {
            build(days: days, today: today, todayKey: key,
                  appleHealthDays: appleHealthDays, loaded: loaded,
                  importedSleep: importedSleep)
        }.value
    }

    /// Placeholder while `buildDetached` runs: renders the screen's existing `!model.loaded` loading
    /// state (FER-954).
    static let loading: RecoveryDetailModel = build(
        days: [], today: nil, todayKey: "", appleHealthDays: [], loaded: false)

    /// Build the whole model from the repo's in-memory dashboard. Pure (no DB). `days` is the strap +
    /// on-device dashboard (`repo.days`, the baseline source — FER-149); `today` is `repo.today`; `todayKey`
    /// is the device's local day key.
    static func build(days: [DailyMetric],
                      today: DailyMetric?,
                      todayKey: String,
                      appleHealthDays: Set<String>,
                      loaded: Bool,
                      importedSleep: [String: ImportedSleepFigures] = [:]) -> RecoveryDetailModel {
        let hasRecovery = today?.recovery != nil
        let score = today?.recovery.map { Int($0.rounded()) }
        let calibration = RecoveryScorer.calibrationNights(
            nightlyHrv: days.map(\.avgHrv), hasRecovery: hasRecovery)

        // Sort once; both the UI series (nils dropped) and the forecast input (nils kept for spacing) read it.
        let sortedDays = days.sorted { $0.day < $1.day }
        let series = sortedDays.compactMap { d in d.recovery.map { (day: d.day, value: $0) } }

        // FER-632: score the detail's σ against the BAND-only baseline — the same cross-source clearing the
        // recovery SCORE relies on (`SourceLens.clearBandColumns`). Raw `days` measured HRV/RHR/resp against a
        // baseline contaminated with Apple SDNN/offsets, so the σ the user saw (e.g. HRV −0.72σ, RHR
        // «normal») diverged from the score's own (−3.56σ, +3.05σ). `clearBandColumns` (FER-631) clears
        // those cross-source columns before the fold — pinned to the same z by test. On an Apple-only
        // day today's own row is masked too (the band didn't measure it), so no band σ is invented for a
        // reading the band never took.
        let bandDays = SourceLens.clearBandColumns(days)
        let readiness = ReadinessEngine.evaluate(days: bandDays, today: todayKey)
        let load: LoadState? = readiness.acwr.map { acwr in
            LoadState(acwr: acwr,
                      monotony: readiness.monotony,
                      bandLabel: readiness.loadBand?.shortLabel ?? "",
                      bandFlag: readiness.loadBand?.flag ?? .neutral)
        }

        let heat = buildHeat(days: days, todayKey: todayKey)

        // Tomorrow's projection: the recovery series (oldest → newest, nils kept so the engine respects
        // missing-day spacing) plus any imported WHOOP sleep debt for today. The engine filters/gates and
        // returns nil below ~2 weeks of base; we never recompute its math here. (FER-277, FER-188)
        let forecast = RecoveryForecast.compute(
            recovery: sortedDays.map(\.recovery),
            sleepDebtMin: importedSleep[todayKey]?.debtMin)

        return RecoveryDetailModel(
            score: score,
            calibration: calibration,
            nightsNeeded: Baselines.minNightsSeed,
            series: series,
            heat: heat,
            load: load,
            loaded: loaded,
            isAppleHealth: appleHealthDays.contains(todayKey),
            forecast: forecast)
    }

    /// The trailing 90 calendar days as `RecoveryDay`, one per day (score nil where there's no reading), so
    /// the heat grid is contiguous and `YearHeatStrip.weekColumns` is deterministic. Dates are stamped at
    /// noon UTC so the weekday never crosses a day boundary across time zones.
    static func buildHeat(days: [DailyMetric], todayKey: String) -> [RecoveryDay] {
        var rec: [String: Double] = [:]
        for d in days { if let r = d.recovery { rec[d.day] = r } }
        guard let today = Repository.parseDayKey(todayKey) else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var out: [RecoveryDay] = []
        out.reserveCapacity(90)
        for offset in stride(from: 89, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = RecoveryDetailScreen.dayParser.string(from: date)
            out.append(RecoveryDay(date: date.addingTimeInterval(12 * 3600), score: rec[key]))
        }
        return out
    }
}

// MARK: - Preview

#if DEBUG
private func sampleRecoverySeries(days: Int = 120) -> [(day: String, value: Double)] {
    let cal: Calendar = Calendar(identifier: .gregorian)
    let today: Date = cal.startOfDay(for: Date())
    let f: DateFormatter = RecoveryDetailScreen.dayParser
    return (0..<days).map { (i: Int) -> (day: String, value: Double) in
        let date: Date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let wave: Double = 24.0 * sin(Double(i) / 9.0)
        let jitter: Double = Double((i * 17) % 13) - 6.0
        let v: Double = 62.0 + wave + jitter
        let clamped: Double = Swift.max(8.0, Swift.min(98.0, v))
        return (day: f.string(from: date), value: clamped)
    }
}

private func sampleModel(score: Int?, calibration: Int?,
                         isAppleHealth: Bool = false) -> RecoveryDetailModel {
    let series: [(day: String, value: Double)] = score == nil && calibration != nil ? [] : sampleRecoverySeries()
    let cal: Calendar = Calendar(identifier: .gregorian)
    let today: Date = cal.startOfDay(for: Date())
    let heat: [RecoveryDay] = (0..<90).reversed().map { (off: Int) -> RecoveryDay in
        let date: Date = cal.date(byAdding: .day, value: -off, to: today)!
        let wave: Double = 26.0 * sin(Double(off) / 8.0)
        let jitter: Double = Double((off * 13) % 17) - 8.0
        let v: Double = 60.0 + wave + jitter
        let scoreVal: Double? = (off % 16 == 0) ? nil : Swift.max(8.0, Swift.min(98.0, v))
        return RecoveryDay(date: date, score: scoreVal)
    }
    let recoveryVals: [Double] = series.map { (p: (day: String, value: Double)) -> Double in p.value }
    return RecoveryDetailModel(
        score: score,
        calibration: calibration,
        nightsNeeded: 4,
        series: series,
        heat: calibration != nil ? [] : heat,
        load: calibration != nil ? nil : .init(acwr: 1.05, monotony: 1.4, bandLabel: "In balance", bandFlag: .good),
        loaded: true,
        isAppleHealth: isAppleHealth,
        forecast: RecoveryForecast.compute(recovery: recoveryVals))
}

#Preview("Recovery detail: con datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RecoveryDetailScreen(model: sampleModel(score: 78, calibration: nil))
    }
}

#Preview("Recovery detail: calibrando") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RecoveryDetailScreen(model: sampleModel(score: nil, calibration: 3))
    }
}

#Preview("Recovery detail: sin datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RecoveryDetailScreen(model: RecoveryDetailModel(
            score: nil, calibration: nil, nightsNeeded: 4,
            series: [], heat: [], load: nil, loaded: true, isAppleHealth: false, forecast: nil))
    }
}
#endif
#endif
