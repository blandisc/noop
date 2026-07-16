#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - StrainDetailScreen — el «Detalle de Esfuerzo» en «Instrumento» (FER-238 · FER-859)
//
// Hermana de `RecoveryDetailScreen` (FER-857): reutiliza el esqueleto del handoff «Detalle de
// Tendencias Final» — héroe invertido → instrumento firma → niveles → historial siempre abierto
// (`GraficaRangos`) → calendario 90 días → método + sello. NO extiende `MetricDetailScreen`/
// `MetricDetailSpec` (esos son para vitales de serie escalar). El esfuerzo es una métrica
// compuesta: el hero es el valor de HOY en escala fija 0–21 (último punto de la curva intradía,
// FER-650), su visualización firma es la curva acumulada del día, y su referencia son zonas fijas.
//
// Se presenta vía `.sheet(item:)` con el tema vivo pasado EXPLÍCITO (no propaga por `.sheet`, FER-162)
// y SIN `NavigationStack` anidado (FER-171). Consume `StrandAnalytics` y la curva de
// `CuerpoView.loadStrainCurve()` TAL CUAL: no crea math.

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
    /// FER-885: today's «Day load» is an Apple workout-HR estimate (Apple-only mode, FER-883), not a
    /// band-measured Day Strain. Flips the footer to the Apple seal and adds the honest under-count hedge.
    var estimated: Bool = false

    /// The trend block's period window (W/M/3M/6M/1Y/ALL). Defaults to a month.
    @State private var range: ExploreRange = .month
    /// The strain series with each `day` string parsed to a `Date` exactly ONCE (not per slice / per
    /// render) — the window math reads `date` straight from here. Built in `.task`. (FER-216 lesson)
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    /// The tapped day for the calendar read-out. (FER-830)
    @State private var selectedStrainDay: RecoveryDay? = nil
    /// Today's intraday curve, loaded in `.task` (loading well until then).
    @State private var curve: [TrendPoint] = []
    @State private var curveLoaded = false
    /// The in-progress day's LIVE strain = the curve's LAST point, captured when the curve loads so the
    /// hero equals the end of the curve BY CONSTRUCTION (they read the same array — FER-650). nil until the
    /// curve loads, or when there's too little activity today; the hero then falls back to the settled score.
    @State private var liveToday: Double?
    /// The hero's ⓘ toggles the «Qué medimos» card right under the inverted field. (FER-859)
    @State private var infoOpen = false

    // MARK: - Body — el esqueleto estándar del handoff «Detalle de Tendencias Final» (FER-859)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !model.loaded {
                    Group {
                        heroFlat
                        ChartWell(theme).loading(height: 160).padding(.top, 22)
                    }
                    .padding(CenitMetrics.screenPadding)
                } else if model.hasData {
                    if shownToday != nil {
                        heroField
                    } else {
                        heroFlat.padding(CenitMetrics.screenPadding)
                    }
                    if infoOpen { whatWeMeasureCard }
                    seccion(String(localized: "How today added up")) { howTodayContent }
                    seccion(String(localized: "Levels")) { levelsContent }
                    seccion(String(localized: "See your history")) { historyContent }
                    if parsed.contains(where: { $0.value > 0 }) {
                        seccion(String(localized: "Calendar · 90 days")) { calendarContent }
                    }
                    PieMetodo(theme: theme) {
                        metodoBlock
                    } sello: {
                        sourceFooter
                    }
                } else {
                    heroFlat.padding(CenitMetrics.screenPadding)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
        // FER-954: re-run when the placeholder model is replaced by the real one (same seam as
        // Sueño/Recuperación, FER-953) and hop the day-key parse off-main. The placeholder pass
        // bails early so `curveLoader` runs exactly once, on the real model.
        .task(id: model.loaded) {
            guard model.loaded else { return }   // placeholder pass — nothing to parse yet (FER-954)
            range = .month
            let series = model.series
            parsed = await Task.detached(priority: .userInitiated) {
                series.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
            }.value
            curve = await curveLoader()
            // The hero shows the curve's LAST point (the live in-progress-day value) so «ends on your score
            // above» holds exactly — same array, no second derivation (FER-650). `.last` is the real endpoint
            // (the prepended midnight anchor is `.first`).
            liveToday = curve.last?.value
            curveLoaded = true
        }
    }

    /// One skeleton section: shared `SeccionBloque` (franja + handoff padding 14 · 20 · 22).
    private func seccion(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        SeccionBloque(title, theme: theme, content: content)
    }

    // MARK: - 1. Héroe invertido — siempre `dataStrain` (descriptivo, sin semáforo)

    /// The value shown as today's strain: the live curve endpoint once the curve loads (so hero == the
    /// curve's last point by construction, FER-650), falling back to the settled `repo.today.strain` before
    /// the curve loads or when there's too little activity to draw one. Drives the hero number, its plain-
    /// language reading, and the highlighted level — one value, never a contradiction on-screen.
    private var shownToday: Double? { liveToday ?? model.today }

    /// The inverted hero: the ONE field saturated at 100% of `theme.dataStrain`. Overline + ⓘ,
    /// 60pt Grotesk numeral (recRise), «en curso» capsule, verdict line. Text is paper on hue.
    private var heroField: some View {
        let v = shownToday ?? 0
        return HeroInvertido(
            glyph: .strain,
            title: "Day Strain",
            hue: theme.dataStrain,
            theme: theme,
            onInfo: { withAnimation(StrandMotion.interactive) { infoOpen.toggle() } },
            numeral: {
                HeroNumeral(fmt(v), suffix: "/ 21", theme: theme) {
                    Text("in progress")
                        .font(InstrumentoType.grotesk(13, weight: .semibold))
                        .foregroundStyle(theme.paper)
                        .heroCapsule(theme: theme)
                }
            },
            verdict: {
                // Keep `heroReading` as ONE localized sentence (existing String Catalog keys). Splitting the
                // four zone strings cleanly into short-clause + secondary clause is awkward for "Moderate
                // effort today." Visual fidelity to the mock's two-tone verdict is secondary to not inventing
                // new copy. (FER-859)
                Text(heroReading)
                    .font(InstrumentoType.grotesk(15, weight: .semibold))
                    .foregroundStyle(theme.paper)
                    .fixedSize(horizontal: false, vertical: true)
            },
            trailing: {
                if let tier = model.confidence {
                    tier.sello(theme: theme, onField: true)
                        .padding(.top, 2)
                }
            }
        )
    }

    /// The ⓘ card under the hero: what the score measures, in plain language.
    private var whatWeMeasureCard: some View {
        QueMedimosCard(title: "What we measure", explanation: heroExplanation, theme: theme)
    }

    /// The flat hero for score-less states (loading / empty / history-only): the pre-handoff identity —
    /// no inverted field for a number we don't have.
    private var heroFlat: some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentoScreenTitle("Day Strain", theme: theme, explanation: heroExplanation, glyph: .strain)
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

    /// The hero ⓘ copy — the standard day-strain explanation (Edwards/Banister).
    private var heroExplanation: LocalizedStringKey {
        "Day Strain is your cardiovascular load on a 0–21 scale. Each second your heart rate is recorded, it's placed in an intensity zone (1–5); higher zones weigh more, and the total is compressed logarithmically so 21 is a theoretical maximum: a full day at peak intensity. (Edwards 1993; Banister 1991)"
    }

    /// A plain-language reading of today's strain by zone, or an honest "no strain yet" when there's no
    /// score (strain is strap-only; Apple Health doesn't compute it). The zone is derived from the SAME
    /// `MetricInfo.strain` bands the levels block shows, so the reading and the highlighted zone can never
    /// disagree if a boundary is ever retuned (single source of truth — no second copy of the thresholds).
    /// Source strings are English; the es values live in `Localizable.xcstrings`.
    private var heroReading: LocalizedStringKey {
        guard let v = shownToday else {
            if !model.series.isEmpty { return "No strain from today yet: your recent history is below." }
            return "No strain yet. Wear your strap through the day and open this again after it syncs."
        }
        switch MetricInfo.strain(v).bands.firstIndex(where: \.isActive) ?? 0 {
        case 0:  return "Light load today: plenty left in the tank."
        case 1:  return "Moderate effort today."
        case 2:  return "Hard effort today: solid work."
        default: return "All-out day: about as much strain as you carry."
        }
    }

    // MARK: - 2. Cómo se acumuló hoy (curva intradía acumulada)

    private var howTodayContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text("Only rises")
                .font(InstrumentoType.grotesk(16, weight: .semibold))
                .foregroundColor(theme.ink)
             + Text(verbatim: " · ")
                .font(InstrumentoType.grotesk(14))
                .foregroundColor(theme.inkSecondary)
             + Text("every second of pulse adds to the total")
                .font(InstrumentoType.grotesk(14))
                .foregroundColor(theme.inkSecondary))
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if curve.count > 1 {
                    TrendChart(
                        points: curve,
                        gradient: chartGradient,
                        valueRange: 0...21,
                        showsArea: true,
                        height: 160,
                        showsScrub: true,
                        valueFormat: { fmt($0) },
                        dateFormat: { Self.hourString($0) },
                        axisLabelColor: theme.inkTertiary,
                        gridLineColor: theme.hairline,
                        yAxisValues: [10, 21]
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text("Accumulated day strain, rising through the day."))
                    BarraAncla(
                        String(localized: "Ends on your score today: it's the same number as the hero."),
                        color: theme.dataStrain, theme: theme)
                } else if !curveLoaded {
                    ChartWell(theme).loading(height: 160)
                } else {
                    ChartWell(theme).empty(text: "Not enough activity yet today to chart.")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.card, theme: theme)
    }

    // MARK: - 3. Niveles (las 4 bandas fijas de `MetricInfo.strain`, la activa marcada)

    private var levelsContent: some View {
        let bands = MetricInfo.strain(shownToday).bands
        return VStack(alignment: .leading, spacing: 8) {
            if let v = shownToday, let active = bands.first(where: \.isActive) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(fmt(v))
                        .font(InstrumentoType.groteskNumber(24, weight: .bold))
                        .foregroundStyle(theme.dataStrain)
                    (Text("falls in ")
                     + Text(active.label)
                     + Text(" · fixed scale from 0 to 21"))
                        .font(InstrumentoType.grotesk(13))
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                    zoneRow(band)
                }
            }
            .padding(.top, 2)
        }
    }

    /// One zone row: a dot (active → the strain hue, else quiet ink) + label + its range, with a subtle
    /// active highlight. Token-only.
    private func zoneRow(_ band: MetricInfo.Band) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(band.isActive ? theme.dataStrain : theme.inkTertiary.opacity(StrandOpacity.dim))
                .frame(width: 8, height: 8)
            Text(band.label)
                .font(band.isActive
                      ? InstrumentoType.grotesk(13, weight: .semibold)
                      : InstrumentoType.grotesk(13))
                .foregroundStyle(band.isActive ? theme.ink : theme.inkSecondary)
            Spacer(minLength: 8)
            Text(band.range)
                .font(InstrumentoType.groteskNumber(12))
                .foregroundStyle(band.isActive ? theme.dataStrain : theme.inkTertiary)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
                .fill(band.isActive ? theme.tint(theme.dataStrain) : Color.clear)
        )
    }

    // MARK: - 4. Ver tu historial (SIEMPRE abierto) — PeriodSelector + GraficaRangos + tiles + drivers

    private var historyContent: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        let smoothed = SeriesShape.movingAverage(window.values, window: 7)
        let mediaStat = ComparisonEngine.stat(smoothed)
        let rawStat = ComparisonEngine.stat(window.values)
        let pct = range.periodComparison(of: model.series)?.pctChange
        return VStack(alignment: .leading, spacing: 8) {
            SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme) { $0.label }
            if window.values.count > 1 {
                GraficaRangos(
                    points: smoothed,
                    bands: Self.strainBands(theme),
                    ticks: [.init(v: 18, label: "18"), .init(v: 13, label: "13"), .init(v: 8, label: "8")],
                    hue: theme.dataStrain, ymin: 6, ymax: 19,
                    startLabel: window.rows.first.flatMap { RecoveryDetailScreen.axisLabel($0.day) } ?? "",
                    endLabel: window.rows.last.flatMap { RecoveryDetailScreen.axisLabel($0.day) } ?? "",
                    mediaValue: fmt(mediaStat.mean),
                    mediaNote: String(localized: "average of the \(range.name)"),
                    mediaDelta: pct.map { $0 >= 0 ? "+\(Int($0.rounded()))%" : "\(Int($0.rounded()))%" },
                    deltaColor: theme.inkSecondary,
                    countUnit: "d",
                    anchorMedia: String(localized: "7-day moving average: day-to-day strain is noisy."),
                    anchorRangos: String(localized: "How many days of the period fell in each band. Tap one to see its days on the chart."),
                    scrub: true,
                    labels: window.rows.map { RecoveryDetailScreen.axisLabel($0.day) ?? "" },
                    theme: theme)
                    .padding(.top, 6)
                    .id(range)
                HStack(alignment: .top, spacing: 8) {
                    TileSurface(label: String(localized: "Average"),
                                value: fmt(mediaStat.mean),
                                theme: theme)
                    TileSurface(label: String(localized: "Range"),
                                value: "\(fmt(rawStat.min))–\(fmt(rawStat.max))",
                                theme: theme)
                    TileSurface(label: String(localized: "Today"),
                                value: shownToday.map { fmt($0) } ?? "—",
                                valueColor: shownToday != nil ? theme.dataStrain : nil,
                                theme: theme)
                }
                .padding(.top, 4)
            } else {
                ChartWell(theme).empty(text: "Not enough days in this range to draw a trend.")
                    .padding(.top, 6)
            }
            if !model.drivers.isEmpty {
                whatMovesCard
                    .padding(.top, 10)
            }
        }
    }

    /// The four fixed strain lanes for `GraficaRangos`, derived from `MetricInfo.strain` (its bands now
    /// carry numeric bounds) — the SAME ladder the hero verdict and the Niveles table read, never
    /// restated as a second math source. Colors rest→extreme: low / mid / full / deep amber; list
    /// order high→low mirrors Recovery.
    static func strainBands(_ theme: InstrumentoTheme) -> [GraficaRangos.Banda] {
        let ramp = [theme.strainRampLow, theme.strainRampMid, theme.dataStrain, theme.strainDeep]
        // Display words per lane (rest→extreme); bounds/ranges come from the ladder itself.
        let words = [String(localized: "Rest / Light"), String(localized: "Moderate"),
                     String(localized: "Hard"), String(localized: "Extreme")]
        return MetricInfo.strain(nil).bands.enumerated().reversed().map { i, band in
            GraficaRangos.Banda(label: words[Swift.min(i, words.count - 1)],
                                lo: band.lower, hi: band.upper,
                                color: ramp[Swift.min(i, ramp.count - 1)],
                                range: band.range)
        }
    }

    /// «Qué mueve tu esfuerzo» — directional drivers, gated (FER-239). Card disappears entirely when
    /// nothing clears the sufficiency gate (FER-246 / mock: no empty-state message).
    private var whatMovesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            QueLaMueveHeader("What moves your strain", chip: "trend, not cause", theme: theme)
            ForEach(model.drivers, id: \.driver) { finding in
                Text(Self.driverPhrase(finding))
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.card, theme: theme)
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

    // MARK: - 5. Calendario · 90 días (YearHeatStrip re-tint + leyenda + read-out)

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            heatGrid
            heatReadout
            HeatLegend([(theme.dataStrain, String(localized: "hard")),
                        (theme.strainRampMid, String(localized: "moderate")),
                        (theme.strainRampLow, String(localized: "light")),
                        (theme.hairline, String(localized: "no data"))], theme: theme)
        }
    }

    private static let calDayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")!; f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let calReadoutFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEdMMM"); return f
    }()

    /// The trailing 90 days as `RecoveryDay` (score = strain 0–21, nil where there's no reading).
    private var strainHeat: [RecoveryDay] {
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
            return RecoveryDay(date: date.addingTimeInterval(12 * 3600), score: vals[Self.calDayFmt.string(from: date)])
        }
    }

    /// Strain is descriptive (not evaluative), so the heat is one hue at three intensities — tokens for
    /// the mid/low rungs (FER-859).
    private func strainHeatTint(_ v: Double) -> Color {
        if v >= 14 { return theme.dataStrain }
        if v >= 8 { return theme.strainRampMid }
        return theme.strainRampLow
    }

    /// A short state word for the calendar read-out (matches the legend rungs and the tint thresholds).
    private func strainWord(_ v: Double) -> LocalizedStringKey {
        if v >= 14 { return "hard" }
        if v >= 8 { return "moderate" }
        return "light"
    }

    private var heatGrid: some View {
        Calendario90(
            days: strainHeat,
            tint: strainHeatTint,
            onSelect: { selectedStrainDay = $0 },
            theme: theme
        )
    }

    @ViewBuilder private var heatReadout: some View {
        if let d = selectedStrainDay {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.calReadoutFmt.string(from: d.date))
                    .instrumentoOverline()
                    .foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                if let v = d.score {
                    Text(String(format: "%.1f", v))
                        .font(StrandFont.number(20))
                        .foregroundStyle(strainHeatTint(v))
                    Text(strainWord(v))
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
            Text("Tap a day to see its strain.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Método + sello

    private var metodoBlock: some View {
        Metodo(title: String(localized: "How it's calculated"), theme: theme) {
            Text("Each second of heart rate is mapped to one of five intensity zones; time in the higher zones counts for much more. The weighted total is compressed onto a 0–21 scale through a logarithmic curve, so the top of the scale represents a theoretical full day at peak intensity.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Heart-rate-zone load (TRIMP), compressed logarithmically. (Edwards 1993; Banister 1991)")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            // FER-885: honest hedge when the load is an Apple workout-HR estimate (no strap).
            if estimated {
                Text("Estimated from your Apple Watch workout heart rate. It doesn't include activity outside those workouts, so it can read a little low.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sourceFooter: some View {
        OriginStamp(origin: estimated ? .apple : .computed,
                    when: String(localized: "today, in progress"), inProgress: true, theme: theme)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    // MARK: - Colour + format

    private var chartGradient: Gradient { ChartWell.fillGradient(theme.dataStrain) }

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
    let id: UUID
    let model: StrainDetailModel
    /// FER-885: today's load is an Apple workout-HR estimate (Apple-only mode), captured when the sheet opens.
    var estimated: Bool = false
    /// FER-954: an explicit `id` lets the built model swap in under the SAME presentation identity
    /// (same pattern as `SleepDetailItem`, FER-953).
    init(id: UUID = UUID(), model: StrainDetailModel, estimated: Bool = false) {
        self.id = id; self.model = model; self.estimated = estimated
    }
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

    /// Runs `build` off the MainActor (FER-954, same seam as `SleepDetailModel.buildDetached` /
    /// FER-953): snapshots `repo.days`/`repo.today`/`repo.loaded` on the MainActor (value-type
    /// copies), then hops the pure derivation to a background executor; only the finished model
    /// returns to main.
    @MainActor
    static func buildDetached(repo: Repository) async -> StrainDetailModel {
        let days = repo.days, today = repo.today, loaded = repo.loaded
        return await Task.detached(priority: .userInitiated) {
            build(days: days, today: today, loaded: loaded)
        }.value
    }

    /// Placeholder while `buildDetached` runs: renders the screen's existing `!model.loaded` loading
    /// state (FER-954).
    static let loading: StrainDetailModel = build(days: [], today: nil, loaded: false)
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

#Preview("Strain detail: con datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StrainDetailScreen(
            model: StrainDetailModel(today: 14.2, series: sampleStrainSeries(), loaded: true,
                                     drivers: [.init(driver: .sameDayRecovery, trend: .rises),
                                               .init(driver: .priorDayStrain, trend: .falls)]),
            curveLoader: { sampleCurve() })
    }
}

#Preview("Strain detail: sin datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StrainDetailScreen(
            model: StrainDetailModel(today: nil, series: [], loaded: true, drivers: []),
            curveLoader: { [] })
    }
}
#endif
#endif
