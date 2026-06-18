#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - RecoveryDetailScreen — el «Detalle de Recuperación» en «Instrumento» (FER-225)
//
// Hermana de `MetricDetailScreen` (FER-185), igual que `SleepDetailScreen` (FER-212): REUSA su lenguaje
// visual (el scaffold `block(title:)`, el hero, `InfoAccordion`, `theme: InstrumentoTheme` explícito,
// `SheetPaperBackground`, `ScrollView`→`VStack`, `methodDisclosure`, los wells) pero con su propio modelo.
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
    /// Measured available width for the calendar, so the heat grid can size its cells to fill it. (FER-225)
    @State private var calWidth: CGFloat = 0
    @State private var methodExpanded = false
    /// The calendar day the user tapped, for the read-out below the grid (touch — FER-235).
    @State private var selectedHeatDay: RecoveryDay? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if !model.loaded {
                    loadingWell(height: 160)
                } else if model.calibration != nil {
                    blockDivider
                    calibrationBlock
                    blockDivider
                    methodDisclosure
                    sourceFooter
                } else if model.hasData {
                    blockDivider
                    whatExplainsItBlock
                    blockDivider
                    normalRangeBlock
                    // Calendar reads in the trend's old spot; the trend moves to the bottom (FER-237).
                    blockDivider
                    calendarBlock
                    if consistency != nil {
                        blockDivider
                        consistencyBlock
                    }
                    if model.load != nil {
                        blockDivider
                        loadBlock
                    }
                    if model.series.count >= 2 {
                        blockDivider
                        trendBlock
                    }
                    blockDivider
                    methodDisclosure
                    sourceFooter
                }
                // Empty (loaded, no calibration, no data): the hero's reading already says it.
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .modifier(RecoverySheetPaperBackground(paper: theme.paper))
        .task {
            range = .month
            parsed = model.series.map { ($0.day, Self.dayParser.date(from: $0.day), $0.value) }
        }
    }

    /// A subtle 1px rule between blocks (token-only). Mirrors MetricDetailScreen's `blockDivider`.
    private var blockDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    // MARK: - 1. Hero — el score en color de banda

    private var hero: some View {
        InfoAccordion(
            title: "Recovery",
            explanation: "Recovery blends several signals from your nervous system — your HRV above all, plus resting heart rate, sleep and breathing — and compares them with your own baseline from recent weeks. It's an estimate of how ready your body is today, not a diagnosis. (Buchheit 2014)",
            accessibilityLabel: "Information about recovery",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(model.score.map { "\($0)" } ?? "—")
                        .instrumentoHero(46)
                        .foregroundStyle(model.score == nil ? theme.inkTertiary : bandColor)
                    if model.score != nil {
                        Text("/ 100").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    }
                }
                Text(heroReading)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
            case "green":  return "Above your baseline — your body is ready for a strong day."
            case "yellow": return "Recovering — train, but keep it controlled."
            default:       return "Low — prioritize rest today."
            }
        }
        if model.calibration != nil { return "Calibrating — we need a few more nights of your strap." }
        // Offline / no reading today but history exists: be honest the day's number is missing without
        // implying a brand-new user (the trend and calendar below are populated). (FER-225, QA O1)
        if !model.series.isEmpty { return "No reading from last night yet — your recent history is below." }
        return "No recovery yet. Wear your strap overnight and open this again after it syncs — or import your WHOOP history in Data Sources."
    }

    // MARK: - 2. Qué lo explica — estado por driver vs tu base + su peso

    private var whatExplainsItBlock: some View {
        InfoAccordion(
            title: "What explains your recovery",
            explanation: "HRV carries the most weight — it's the best window onto your autonomic nervous system. What matters is the average of your recent nights, not a single day. If a signal is missing on a given night, its weight is shared among the others. (Plews 2013; Buchheit 2014)",
            accessibilityLabel: "Information about what explains your recovery",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.drivers) { driverRow($0) }
            }
        }
    }

    /// One driver: its label + state word (in the flag color) + weight on the title line, and a thin track
    /// whose fill length is the weight (relative to HRV's 60%) tinted by the same flag — so a glance reads
    /// both "how it's doing" (color + word) and "how much it weighs" (bar length).
    private func driverRow(_ d: RecoveryDetailModel.DriverState) -> some View {
        let color = flagColor(d.flag)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(d.label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                Text(Self.driverWord(key: d.key, flag: d.flag))
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(color)
                Text(verbatim: "\(d.weightPct)%")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkTertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline).frame(height: 5)
                    Capsule().fill(d.flag == .neutral ? theme.inkTertiary.opacity(0.5) : color)
                        .frame(width: max(5, geo.size.width * CGFloat(d.weightPct) / 60), height: 5)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }

    /// The flag → theme color: good → verdict, neutral → quiet ink, watch → warning, bad → critical.
    private func flagColor(_ flag: ReadinessEngine.Flag) -> Color {
        switch flag {
        case .good:    return theme.verdict
        case .neutral: return theme.inkSecondary
        case .watch:   return theme.warning
        case .bad:     return theme.critical
        }
    }

    /// A short es-MX state word per driver and flag (the source strings are English; es/de live in the
    /// String Catalog). Phrased per metric so each reads naturally ("HRV above your base", "Resting HR
    /// running high"). Neutral always means "in your normal range" for that signal.
    private static func driverWord(key: String, flag: ReadinessEngine.Flag) -> LocalizedStringKey {
        switch (key, flag) {
        case ("hrv", .good):       return "above your base"
        case ("hrv", .watch):      return "a touch low"
        case ("hrv", .bad):        return "suppressed"
        case ("rhr", .good):       return "low, in your base"
        case ("rhr", .watch):      return "running high"
        case ("rhr", .bad):        return "elevated"
        case ("sleep", .good):     return "solid"
        case ("sleep", .watch):    return "light"
        case ("sleep", .bad):      return "very short"
        case ("skinTemp", .good):  return "steady"
        case ("skinTemp", .watch): return "running warm"
        case ("skinTemp", .bad):   return "elevated"
        case ("respRate", .good):  return "steady"
        case ("respRate", .watch): return "slightly raised"
        case ("respRate", .bad):   return "elevated"
        default:                   return "in your normal range"
        }
    }

    // MARK: - 3. Tu rango normal (media ± σ de tu recuperación reciente)

    @ViewBuilder private var normalRangeBlock: some View {
        let vals = Array(model.series.suffix(30)).map(\.value)
        let s = ComparisonEngine.stat(vals)
        if s.n >= 2 {
            let lo = Int(Swift.max(0, s.mean - s.stdev).rounded())
            let hi = Int(Swift.min(100, s.mean + s.stdev).rounded())
            InfoAccordion(
                title: "Your normal range",
                explanation: "Your personal baseline: the average of your recent recovery days ± a band of your own variation. A day outside the band is unusual for you, not for the population. (Buchheit 2014)",
                accessibilityLabel: "Information about your normal range",
                theme: theme
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(lo)–\(hi) · \(s.n) days")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(theme.ink)
                    Text("Where your recovery usually lands when you're well. Worth noting when a day falls outside it.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 4. Selector de periodo + Tendencia (+ Prom/Mediana/Mín/Máx/σ)

    private var trendBlock: some View {
        let window = makeWindow()
        let stat = ComparisonEngine.stat(window.values)
        let mom = ComparisonEngine.monthOverMonth(byDay: model.series, referenceDay: model.series.last?.day ?? "")
        return InfoAccordion(
            title: "Trend",
            explanation: "The line is your 7-day moving average over the period you pick. The percentage compares this month's average with last month's. The average and range come from the range you selected.",
            accessibilityLabel: "Information about the trend",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme) { $0.label }
                if window.fellBack {
                    Text("Showing the last \(window.rows.count) days")
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.warning)
                }
                if window.values.count > 1 {
                    let smoothed = SeriesShape.movingAverage(window.values, window: 7)
                    TrendChart(
                        points: Self.decimatedPoints(rows: window.rows, values: smoothed, maxPoints: 80),
                        gradient: Gradient(colors: [theme.dataRecovery.opacity(0.5), theme.dataRecovery]),
                        valueRange: chartRange(smoothed),
                        showsArea: true,
                        height: 200,
                        showsHover: true,
                        valueFormat: { "\(Int($0.rounded()))" },
                        axisLabelColor: theme.inkTertiary,
                        gridLineColor: theme.hairline
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text("Recovery, 7-day moving average"))
                    TrendStatSummary(
                        average: "\(Int(stat.mean.rounded()))",
                        pctChange: mom.pctChange,
                        polarity: .higherIsBetter,
                        rangeLow: "\(Int(stat.min.rounded()))",
                        rangeHigh: "\(Int(stat.max.rounded()))",
                        theme: theme
                    )
                } else {
                    emptyWell(text: "Not enough days in this range to draw a trend.")
                }
            }
        }
    }

    // MARK: - 5. Consistencia (coeficiente de variación)

    /// CV of the full recovery series (nil when there aren't enough points), so the block can be skipped.
    private var consistency: Int? {
        SeriesShape.coefficientOfVariation(model.series.map(\.value), window: 7).map { Int(($0 * 100).rounded()) }
    }

    @ViewBuilder private var consistencyBlock: some View {
        if let pct = consistency {
            InfoAccordion(
                title: "Consistency",
                explanation: "Coefficient of variation = how spread out your recovery is around its own average, as a percentage. Low = steady. A steadier recovery usually means your body is coping well with your load. (Plews 2013)",
                accessibilityLabel: "Information about consistency",
                theme: theme
            ) {
                ConsistencySummary(cvPercent: pct,
                                   reading: "How steady your recovery stays from one week to the next.",
                                   theme: theme)
            }
        }
    }

    // MARK: - 6. Calendario · 90 días (YearHeatStrip re-tintado, a todo el ancho)

    private var calendarBlock: some View {
        InfoAccordion(
            title: "Calendar · 90 days",
            explanation: "Each square is a day, tinted by your recovery — red when low, amber in the middle, green when high. Empty squares are days with no reading. It's the at-a-glance shape of your last three months. (Buchheit 2014)",
            accessibilityLabel: "Information about the 90-day calendar",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 10) {
                heatGrid
                heatReadout
            }
        }
    }

    /// The read-out under the calendar: the tapped day's date + score (in its band color) + state word,
    /// or an honest "no reading" for an in-range gap; a quiet hint until the user taps a day. (FER-235)
    @ViewBuilder private var heatReadout: some View {
        if let day = selectedHeatDay {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.heatDateFmt.string(from: day.date))
                    .instrumentoOverline()
                    .foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                if let score = day.score {
                    Text("\(Int(score.rounded()))")
                        .font(StrandFont.number(20))
                        .foregroundStyle(heatTint(score))
                    Text(bandWord(score))
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
            Text("Tap a day to see its recovery.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A short band word for the calendar read-out (matches the hero's band coloring).
    private func bandWord(_ score: Double) -> LocalizedStringKey {
        switch RecoveryScorer.band(score) {
        case "green":  return "Ready"
        case "yellow": return "Recovering"
        default:       return "Low"
        }
    }

    /// The 90-day heat strip, sized to fill the available width: measure the content width once, then
    /// pick a cell size so the week columns span it (re-tinted to warm paper). (FER-225)
    private var heatGrid: some View {
        let cols = Swift.max(1, YearHeatStrip.weekColumns(for: model.heat))
        let spacing: CGFloat = 4
        let gutter: CGFloat = 24
        let cell: CGFloat = calWidth > 0
            ? Swift.max(8, Swift.min(22, (calWidth - gutter - spacing - CGFloat(cols - 1) * spacing) / CGFloat(cols)))
            : 14
        return YearHeatStrip(
            days: model.heat,
            cellSize: cell,
            spacing: spacing,
            showsHover: false,
            tint: heatTint,
            emptyFill: theme.hairline,
            emptyStroke: theme.hairlineStrong,
            labelColor: theme.inkTertiary,
            onSelect: { selectedHeatDay = $0 },
            selectionColor: theme.ink
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { g in
            Color.clear.preference(key: CalWidthKey.self, value: g.size.width)
        })
        .onPreferenceChange(CalWidthKey.self) { calWidth = $0 }
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

    // MARK: - 7. Carga reciente (ACWR + monotonía como CONTEXTO, sin claim de lesión)

    @ViewBuilder private var loadBlock: some View {
        if let load = model.load {
            InfoAccordion(
                title: "Recent load",
                explanation: "The acute:chronic workload ratio (your last week vs your last month) and training monotony describe how your load is trending. They are context for your recovery — they do NOT predict injuries; that evidence doesn't hold up. (Impellizzeri 2020)",
                accessibilityLabel: "Information about recent load",
                theme: theme
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(load.bandLabel)
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(flagColor(load.bandFlag))
                    if let mono = load.monotony, mono >= 2.0 {
                        Text("Similar effort most days — a little variety helps.")
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    InlineFlagChip("context, not injury risk", color: theme.inkTertiary)
                }
            }
        }
    }

    // MARK: - 8. Ver el método (DisclosureGroup, patrón de las otras pantallas)

    private var methodDisclosure: some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                Text("Each signal becomes a score of how far above or below your personal average it sits (a z-score). They're combined with the weights above and mapped onto a 0–100 scale through a logistic curve, calibrated so a typical day lands near 58. It's an estimate, not a diagnosis.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A composite of z-scores through a logistic curve. HRV via RMSSD (Task Force, 1996).")
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

    // MARK: - Calibrando (no hay score todavía)

    private var calibrationBlock: some View {
        let n = model.calibration ?? 0
        let needed = model.nightsNeeded
        return VStack(alignment: .leading, spacing: 12) {
            Text("Not enough history yet")
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
            HStack(alignment: .firstTextBaseline) {
                Text("Calibrating").instrumentoOverline().foregroundStyle(theme.inkTertiary)
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
            Text("We need a few more nights with your strap to learn your baseline before we score your recovery. We'd rather not show a made-up number.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Source footer + wells

    private var sourceFooter: some View {
        Text(model.isAppleHealth ? "Source · Apple Health" : "Source · your strap, on device")
            .font(StrandFont.footnote)
            .foregroundStyle(theme.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    private func loadingWell(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(theme.surface)
            .frame(height: height)
            .overlay { ProgressView().tint(theme.inkTertiary) }
    }

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

    // MARK: - Window math (mirror MetricDetailScreen, scoped to this screen)

    struct Window {
        let range: ExploreRange
        let rows: [(day: String, value: Double)]
        let values: [Double]
        let fellBack: Bool
    }

    /// Trailing-N-days slice for `r`, taken relative to the latest point (reads the memoized `date`).
    private func slice(for r: ExploreRange) -> [(day: String, value: Double)] {
        guard let days = r.days else { return parsed.map { ($0.day, $0.value) } }
        guard let last = parsed.last?.date else { return [] }
        let cutoff = last.addingTimeInterval(-Double(days - 1) * 86_400)
        return parsed.compactMap { row in
            guard let d = row.date, d >= cutoff else { return nil }
            return (row.day, row.value)
        }
    }

    /// The selected range, or the smallest larger range whose window holds ≥1 point (Explorer auto-widen).
    private func effectiveRange() -> ExploreRange {
        guard !parsed.isEmpty else { return range }
        for r in range.widening where !slice(for: r).isEmpty { return r }
        return .all
    }

    private func makeWindow() -> Window {
        let eff = effectiveRange()
        let rows = slice(for: eff)
        return Window(range: eff, rows: rows, values: rows.map(\.value), fellBack: eff != range)
    }

    /// Build the chart's points, decimating long series to ≤`maxPoints` for DRAWING only (FER-219). Short
    /// ranges pass through one point per day.
    private static func decimatedPoints(rows: [(day: String, value: Double)], values: [Double], maxPoints: Int) -> [TrendPoint] {
        let n = Swift.min(rows.count, values.count)
        guard n > maxPoints, maxPoints > 1 else {
            return zip(rows, values).compactMap { row, value in
                dayParser.date(from: row.day).map { TrendPoint(date: $0, value: value) }
            }
        }
        let decimated = SeriesShape.decimate(Array(values.prefix(n)), maxPoints: maxPoints)
        var out: [TrendPoint] = []
        out.reserveCapacity(decimated.count)
        for b in 0..<decimated.count {
            let lo = (n * b) / maxPoints
            let hi = (n * (b + 1)) / maxPoints
            let mid = Swift.min(lo + (hi - lo) / 2, n - 1)
            if let date = dayParser.date(from: rows[mid].day) {
                out.append(TrendPoint(date: date, value: decimated[b]))
            }
        }
        return out
    }

    /// Auto-fit the chart's axis to the smoothed line, clamped to the 0–100 recovery scale.
    private func chartRange(_ smoothed: [Double]) -> ClosedRange<Double> {
        let lo = smoothed.min() ?? 0
        let hi = smoothed.max() ?? 100
        if hi <= lo { return Swift.max(0, lo - 5)...Swift.min(100, hi + 5) }
        let pad = (hi - lo) * 0.15
        return Swift.max(0, lo - pad)...Swift.min(100, hi + pad)
    }

    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Locale-aware "Wed 14 May" for the calendar read-out (orders/abbreviates per device locale). (FER-235)
    static let heatDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()
}

// MARK: - Width preference (size the calendar to fill the content width)

private struct CalWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Sheet item

/// Identifiable wrapper so the light «Instrumento» Detalle de Recuperación can ride `.sheet(item:)` (the
/// model itself isn't Identifiable). Shared by Cuerpo (the hero) and Hoy (the verdict numeral). (FER-225)
struct RecoveryDetailItem: Identifiable {
    let id = UUID()
    let model: RecoveryDetailModel
}

// MARK: - Sheet paper background (iOS 16.4+ presentationBackground)

private struct RecoverySheetPaperBackground: ViewModifier {
    let paper: Color
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(paper)
        } else {
            content
        }
    }
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

    /// One driver of the recovery composite: its weight (mirrored from `RecoveryScorer`) and its current
    /// state vs the user's baseline, as a `ReadinessEngine.Flag` (good / neutral / watch / bad).
    struct DriverState: Identifiable {
        let id = UUID()
        let key: String                 // "hrv" | "rhr" | "sleep" | "skinTemp" | "respRate"
        let label: LocalizedStringKey
        let weightPct: Int
        let flag: ReadinessEngine.Flag
    }

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
    /// The five weighted drivers with their current state.
    let drivers: [DriverState]
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

    /// True when there's a score or any stored recovery history to draw (the rich path); false → empty.
    var hasData: Bool { score != nil || !series.isEmpty }

    // MARK: - Build

    /// Build the whole model from the repo's in-memory dashboard. Pure (no DB). `days` is the strap +
    /// on-device dashboard (`repo.days`, the baseline source — FER-149); `today` is `repo.today`; `todayKey`
    /// is the device's local day key.
    static func build(days: [DailyMetric],
                      today: DailyMetric?,
                      todayKey: String,
                      appleHealthDays: Set<String>,
                      loaded: Bool) -> RecoveryDetailModel {
        let hasRecovery = today?.recovery != nil
        let score = today?.recovery.map { Int($0.rounded()) }
        let calibration = RecoveryScorer.calibrationNights(
            nightlyHrv: days.map(\.avgHrv), hasRecovery: hasRecovery)

        let series = days
            .compactMap { d in d.recovery.map { (day: d.day, value: $0) } }
            .sorted { $0.day < $1.day }

        let readiness = ReadinessEngine.evaluate(days: days, today: todayKey)
        let drivers = deriveDrivers(readiness: readiness, today: today)
        let load: LoadState? = readiness.acwr.map { acwr in
            LoadState(acwr: acwr,
                      monotony: readiness.monotony,
                      bandLabel: readiness.loadBand?.shortLabel ?? "",
                      bandFlag: readiness.loadBand?.flag ?? .neutral)
        }

        let heat = buildHeat(days: days, todayKey: todayKey)

        return RecoveryDetailModel(
            score: score,
            calibration: calibration,
            nightsNeeded: Baselines.minNightsSeed,
            drivers: drivers,
            series: series,
            heat: heat,
            load: load,
            loaded: loaded,
            isAppleHealth: appleHealthDays.contains(todayKey))
    }

    /// Map the recovery composite's five drivers to their current state. HRV / FC / Respiración /
    /// Temperatura read their flag from `ReadinessEngine.signals` (whose z-scores share the recovery
    /// scorer's baseline); when no signal is emitted the signal is in its normal range (`.neutral`). Sleep
    /// has no readiness signal, so its state is derived from last night's efficiency vs the scorer's
    /// sleep-performance center — the same constant the score uses. Weights come straight from
    /// `RecoveryScorer`, never hardcoded.
    static func deriveDrivers(readiness: ReadinessEngine.Readiness, today: DailyMetric?) -> [DriverState] {
        var byKey: [String: ReadinessEngine.Flag] = [:]
        for s in readiness.signals { byKey[s.key] = s.flag }

        let sleepFlag: ReadinessEngine.Flag = {
            guard let raw = today?.efficiency else { return .neutral }
            let eff = raw > 1 ? raw / 100 : raw         // stored as % or fraction
            if eff >= RecoveryScorer.sleepPerfCenter { return .good }
            if eff >= RecoveryScorer.sleepPerfCenter - RecoveryScorer.sleepPerfScale { return .neutral }
            return .watch
        }()

        func pct(_ w: Double) -> Int { Int((w * 100).rounded()) }
        return [
            DriverState(key: "hrv",      label: "HRV",               weightPct: pct(RecoveryScorer.wHRV),   flag: byKey["hrv"] ?? .neutral),
            DriverState(key: "rhr",      label: "Resting HR",        weightPct: pct(RecoveryScorer.wRHR),   flag: byKey["rhr"] ?? .neutral),
            DriverState(key: "sleep",    label: "Sleep",             weightPct: pct(RecoveryScorer.wSleep), flag: sleepFlag),
            DriverState(key: "skinTemp", label: "Skin temperature",  weightPct: pct(RecoveryScorer.wTemp),  flag: byKey["skinTemp"] ?? .neutral),
            DriverState(key: "respRate", label: "Respiration",       weightPct: pct(RecoveryScorer.wResp),  flag: byKey["respRate"] ?? .neutral),
        ]
    }

    /// The trailing 90 calendar days as `RecoveryDay`, one per day (score nil where there's no reading), so
    /// the heat grid is contiguous and `YearHeatStrip.weekColumns` is deterministic. Dates are stamped at
    /// noon UTC so the weekday never crosses a day boundary across time zones.
    static func buildHeat(days: [DailyMetric], todayKey: String) -> [RecoveryDay] {
        var rec: [String: Double] = [:]
        for d in days { if let r = d.recovery { rec[d.day] = r } }
        guard let today = RecoveryDetailScreen.dayParser.date(from: todayKey) else { return [] }
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
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let f = RecoveryDetailScreen.dayParser
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = 62 + 24 * sin(Double(i) / 9.0) + Double((i * 17) % 13) - 6
        return (f.string(from: date), Swift.max(8, Swift.min(98, v)))
    }
}

private func sampleModel(score: Int?, calibration: Int?) -> RecoveryDetailModel {
    let series = score == nil && calibration != nil ? [] : sampleRecoverySeries()
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let heat: [RecoveryDay] = (0..<90).reversed().map { off in
        let date = cal.date(byAdding: .day, value: -off, to: today)!
        let v = 60 + 26 * sin(Double(off) / 8.0) + Double((off * 13) % 17) - 8
        return RecoveryDay(date: date, score: (off % 16 == 0) ? nil : Swift.max(8, Swift.min(98, v)))
    }
    return RecoveryDetailModel(
        score: score,
        calibration: calibration,
        nightsNeeded: 4,
        drivers: [
            .init(key: "hrv", label: "HRV", weightPct: 60, flag: .good),
            .init(key: "rhr", label: "Resting HR", weightPct: 20, flag: .neutral),
            .init(key: "sleep", label: "Sleep", weightPct: 15, flag: .good),
            .init(key: "skinTemp", label: "Skin temperature", weightPct: 10, flag: .neutral),
            .init(key: "respRate", label: "Respiration", weightPct: 5, flag: .neutral),
        ],
        series: series,
        heat: calibration != nil ? [] : heat,
        load: calibration != nil ? nil : .init(acwr: 1.05, monotony: 1.4, bandLabel: "Ideal load", bandFlag: .good),
        loaded: true,
        isAppleHealth: false)
}

#Preview("Recovery detail — con datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RecoveryDetailScreen(model: sampleModel(score: 78, calibration: nil))
    }
}

#Preview("Recovery detail — calibrando") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RecoveryDetailScreen(model: sampleModel(score: nil, calibration: 3))
    }
}

#Preview("Recovery detail — sin datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RecoveryDetailScreen(model: RecoveryDetailModel(
            score: nil, calibration: nil, nightsNeeded: 4, drivers: [],
            series: [], heat: [], load: nil, loaded: true, isAppleHealth: false))
    }
}
#endif
#endif
