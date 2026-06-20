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
// Se presenta SOLO desde Cuerpo vía `.sheet(item:)` (el tile de Estrés en Hoy NO cambia — sigue simplificado)
// con el tema vivo pasado EXPLÍCITO (no propaga por `.sheet`, FER-162) y SIN `NavigationStack` anidado (un
// stack anidado cruzando el path de la tab crasheaba SwiftUI, FER-171).
//
// Consume `StressModel` (de `StressView.swift`) TAL CUAL — no crea matemática nueva: el score/banda 0–3, la
// explicación, los marcadores RHR/HRV vs base, la serie completa y el «tiempo en calma» ya los deriva el
// modelo (z-score logístico; bandas 0–1/1–2/2–3). El hero muestra el VALOR DE HOY (no la media 7d) porque el
// índice ya viene normalizado a la base de cada quien; las bandas son fijas por la misma razón.
//
// Bloques, cada uno con su ⓘ (`InfoAccordion`) salvo el método: 1) Hero (valor de hoy en
// color de banda) · 2) Selector de periodo + Tendencia (línea 0–3 sobre las bandas) · 3) Rango normal (bandas
// universales) · 4) Qué lo mueve (RHR/HRV vs base) · 5) Consistencia (CV) · 6) Tiempo en calma · 7) Estrés a lo
// largo del día (el «mapa del día»: carril vertical + cruce con el calendario, `StressDayMapBlock`, FER-377) ·
// 8) Ver el método.

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

    /// The trend block's period window (W/M/3M/6M/1Y/ALL). Defaults to a month.
    @State private var range: ExploreRange = .month
    /// The stress series with each point's `Date` already parsed (from `fullTrend`) — the window math reads
    /// `date` straight from here (no string re-parsing). Built in `.task`. (FER-216 lesson)
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    @State private var methodExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let model {
                    hero(model)
                    if model.fullTrend.count >= 2 {
                        blockDivider
                        trendBlock(model)
                    }
                    blockDivider
                    normalRangeBlock(model)
                    blockDivider
                    calmTimeBlock(model)
                    blockDivider
                    whatMovesItBlock(model)
                    if consistency(model) != nil {
                        blockDivider
                        consistencyBlock(model)
                    }
                    if let dayMap {
                        blockDivider
                        StressDayMapBlock(model: dayMap, theme: theme)
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
        }
    }

    /// A subtle 1px rule between blocks (token-only). Mirrors MetricDetailScreen's `blockDivider`.
    private var blockDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    // MARK: - 1. Hero — el valor de HOY en color de banda (+ palabra de banda + lectura)

    private func hero(_ model: StressModel) -> some View {
        InfoAccordion(
            title: "Stress",
            explanation: "Your autonomic load for the day: how activated your body is. We take today's resting heart rate and HRV, compare each with your own 30-day baseline as a z-score, and map the combined shift onto a 0–3 scale through a logistic curve (0 calm · 1.5 your baseline · 3 highly activated). It's an estimate, not a diagnosis.",
            accessibilityLabel: "Information about stress",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(fmt(model.score))
                        .instrumentoHero(46)
                        .foregroundStyle(bandColor(model.band))
                    Text("/ 3").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                }
                Text(bandWord(model.band))
                    .font(StrandFont.subhead)
                    .foregroundStyle(bandColor(model.band))
                Text(model.explanation)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The empty hero: no usable signal yet. Honest "—" + a line on how to get data (mirrors the siblings).
    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stress").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("—").instrumentoHero(46).foregroundStyle(theme.inkTertiary)
            Text("No stress reading yet. Wear your strap overnight and open this again after it syncs — or import your WHOOP history in Data Sources. Stress is read from your resting heart rate and HRV.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The band color: low → verdict (green), medium → warning (amber), high → critical (red). The hero
    /// numeral is the datum, so it's the one element that carries saturated hue. (DESIGN.md: color in the datum)
    private func bandColor(_ band: StressBand) -> Color {
        band.dataColor(theme)
    }

    /// Sentence-case band word for the hero / legend ("Low" / "Moderate" / "High"). Distinct from
    /// `StressBand.title` (which is ALL-CAPS, for the dark legacy gauge).
    private func bandWord(_ band: StressBand) -> LocalizedStringKey {
        switch band {
        case .low:    return "Low"
        case .medium: return "Moderate"
        case .high:   return "High"
        }
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

    // MARK: - 3. Rango normal — bandas UNIVERSALES (no baseline personal)

    private func normalRangeBlock(_ model: StressModel) -> some View {
        InfoAccordion(
            title: "Normal range",
            explanation: "These bands are the same for everyone because the index is already adjusted to your own baseline, not to the population — a 1.5 sits at YOUR normal. So there's no personal ± range to compute: what's worth watching is drifting into «High» for several days in a row.",
            accessibilityLabel: "Information about the normal range",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 8) {
                bandRow("Low", "0 – 1", color: theme.verdict, isCurrent: model.band == .low)
                bandRow("Moderate", "1 – 2", color: theme.warning, isCurrent: model.band == .medium)
                bandRow("High", "2 – 3", color: theme.critical, isCurrent: model.band == .high)
            }
        }
    }

    private func bandRow(_ label: LocalizedStringKey, _ range: LocalizedStringKey, color: Color, isCurrent: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(isCurrent ? StrandFont.subhead.weight(.semibold) : StrandFont.subhead)
                .foregroundStyle(isCurrent ? theme.ink : theme.inkSecondary)
            if isCurrent {
                Text("· today").font(StrandFont.footnote).foregroundStyle(color)
            }
            Spacer(minLength: 8)
            Text(range).font(StrandFont.captionNumber).foregroundStyle(theme.inkTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 4. Qué lo mueve — RHR / HRV de hoy vs tu base

    private func whatMovesItBlock(_ model: StressModel) -> some View {
        InfoAccordion(
            title: "What moves it",
            explanation: "Stress rises when your resting heart rate runs higher than usual OR your HRV drops below usual — both are classic signs your nervous system is activated. We measure each against your own 30-day baseline. RMSSD for HRV (Task Force, 1996).",
            accessibilityLabel: "Information about what moves stress",
            theme: theme
        ) {
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

    // MARK: - 5. Consistencia (coeficiente de variación)

    /// CV of the full stress series (nil when there aren't enough points), so the block can be skipped.
    private func consistency(_ model: StressModel) -> Int? {
        SeriesShape.coefficientOfVariation(model.fullTrend.map(\.value), window: 7).map { Int(($0 * 100).rounded()) }
    }

    @ViewBuilder private func consistencyBlock(_ model: StressModel) -> some View {
        if let pct = consistency(model) {
            InfoAccordion(
                title: "Consistency",
                explanation: "Coefficient of variation = how spread out your daily stress is around its own average, as a percentage. Low = steady. A steadier signal usually means your load and recovery are in balance. (Plews 2013)",
                accessibilityLabel: "Information about consistency",
                theme: theme
            ) {
                ConsistencySummary(cvPercent: pct,
                                   reading: "How steady your stress stays from one week to the next.",
                                   theme: theme)
            }
        }
    }

    // MARK: - 6. Tiempo en calma — % de días en banda baja (últimos 30d)

    private func calmTimeBlock(_ model: StressModel) -> some View {
        InfoAccordion(
            title: "Calm time",
            explanation: "The share of your recent days that sat in the Low band (under 1.0). Higher is better — it means your body had room to recover. It's a count of days, not a measure of how low any single day went.",
            accessibilityLabel: "Information about calm time",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.calmTimeValue)
                    .font(StrandFont.number(28))
                    .foregroundStyle(theme.verdict)
                // The window / needs-history note lives in this localized reading line — we deliberately
                // do NOT render `model.calmTimeCaption` (an English-only String built in the model) so
                // nothing leaks English under es/de. (FER-241, QA D1)
                Text("How much of the last month you spent with low autonomic load.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 8. Ver el método (DisclosureGroup, patrón de las otras pantallas)

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
                Text("Combined resting-HR / HRV z-score through a logistic curve. HRV via RMSSD (Task Force, 1996). An estimate, not a diagnosis.")
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
