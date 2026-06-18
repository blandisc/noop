#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - SkinTempDetailScreen — el «Detalle de Temperatura de la piel» en «Instrumento» (FER-256)
//
// Hermana de `StrainDetailScreen` (FER-238) y `StressDetailScreen` (FER-241): REUSA su lenguaje visual
// (hero con `InfoAccordion`, `theme: InstrumentoTheme` explícito, `SheetPaperBackground`,
// `ScrollView`→`VStack`, `blockDivider`, la window-math de la tendencia, `methodDisclosure`, los wells) pero
// con su propio modelo. Reemplaza, para la temperatura de piel en Cuerpo, la vieja hoja OSCURA del catálogo
// (`MetricExplorerView`). Se presenta vía `.sheet(item:)` con el tema vivo pasado EXPLÍCITO (no propaga por
// `.sheet`, FER-162) y SIN `NavigationStack` anidado (FER-171).
//
// La temperatura de piel es una DESVIACIÓN (±°C) respecto a la base nocturna de cada quien, centrada en ~0,
// y de polaridad NEUTRAL (más no es bueno ni malo — como el esfuerzo). Eso dicta qué bloques aplican
// honestamente y cuáles NO:
//  · Hero = la ÚLTIMA lectura con signo (no la media 7d): es una señal puntual y así coincide con la fila.
//  · El chip mes-vs-mes del `TrendStatSummary` va en DELTA ABSOLUTO (°C), no en %: sobre una media ≈0 el
//    porcentaje se dispara (de +0.05 a +0.10 °C ⇒ «+100%») y miente. (TrendStatSummary.absoluteChange)
//  · Consistencia = la DESVIACIÓN ESTÁNDAR en °C, no el CV%: dividir entre una media ≈0 no significa nada.
//  · La gráfica lleva una BANDA sutil de «variación típica» (±tu SD) alrededor de 0 — el contexto de qué es
//    mucho/poco PARA TI, sin inventar umbrales clínicos (skin temp no tiene bandas validadas citables).
// Por eso NO trae «rango normal» con umbrales fijos, ni «qué lo mueve», ni placeholder de calendario.
//
// Bloques, cada uno con su ⓘ (`InfoAccordion`) salvo el método: 1) Hero (última lectura ±°C, ink neutral)
// · 2) Selector de periodo + Tendencia (línea diaria sobre la banda ±típica) + `TrendStatSummary` · 3)
// Consistencia (SD en °C) · 4) Ver el método. Consume `repo.displayDays` TAL CUAL: no crea matemática.

/// Light «Instrumento» Detalle de Temperatura de la piel. Built once from a `SkinTempDetailModel` (the
/// caller injects it so the screen stays DB-free), themed explicitly for the sheet boundary.
struct SkinTempDetailScreen: View {
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    /// Everything the screen draws from the in-memory dashboard, derived ONCE by the caller (no DB here).
    let model: SkinTempDetailModel

    /// The trend block's period window (W/M/3M/6M/1Y/ALL). Defaults to a month.
    @State private var range: ExploreRange = .month
    /// The series with each `day` string parsed to a `Date` exactly ONCE (not per slice / per render) — the
    /// window math reads `date` straight from here. Built in `.task`. (FER-216 lesson)
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    @State private var methodExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if !model.loaded {
                    loadingWell(height: 160)
                } else {
                    if model.series.count >= 2 {
                        blockDivider
                        trendBlock
                    }
                    if model.consistencySD != nil {
                        blockDivider
                        consistencyBlock
                    }
                    blockDivider
                    methodDisclosure
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .modifier(SkinTempSheetPaperBackground(paper: theme.paper))
        .task {
            range = .month
            parsed = model.series.map { ($0.day, Self.dayParser.date(from: $0.day), $0.value) }
        }
    }

    /// A subtle 1px rule between blocks (token-only). Mirrors the sibling screens' `blockDivider`.
    private var blockDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    // MARK: - 1. Hero — la última lectura (±°C) en ink neutral (la temperatura no es buena ni mala)

    private var hero: some View {
        let v = model.today
        return InfoAccordion(
            title: "Skin Temperature",
            explanation: "How far last night's skin temperature ran from your own recent baseline, in °C. We learn your normal over recent nights, so 0 is your usual and the number is the shift up or down. A single warm or cool night rarely means much — what's worth noticing is several nights in a row drifting the same way. It's a comfort signal, not a thermometer or a diagnosis.",
            accessibilityLabel: "Information about skin temperature",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(v.map { fmt($0) } ?? "—")
                        .instrumentoHero(46)
                        .foregroundStyle(v == nil ? theme.inkTertiary : theme.ink)
                    if v != nil {
                        Text("°C").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    }
                }
                Text(heroReading)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A plain-language, NON-clinical reading of last night's deviation, or an honest "no reading yet" when
    /// there's none. Thresholds are deliberately soft (≈±0.3 °C ≈ a typical night-to-night swing): we never
    /// claim fever or illness — just whether the night sat near, above or below the user's own baseline.
    /// Source strings are English; the es values live in `Localizable.xcstrings`.
    private var heroReading: LocalizedStringKey {
        guard let v = model.today else {
            if !model.series.isEmpty { return "No reading from last night yet — your recent history is below." }
            return "No skin-temperature reading yet. Wear your strap overnight and open this again after it syncs."
        }
        if abs(v) < 0.3 { return "Right around your usual nighttime baseline." }
        return v > 0 ? "A touch warmer than your baseline last night."
                     : "A touch cooler than your baseline last night."
    }

    // MARK: - 2. Selector de periodo + Tendencia (línea diaria sobre la banda ±típica) + TrendStatSummary

    private var trendBlock: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        let stat = ComparisonEngine.stat(window.values)
        // Compare the selected window against the equally-long window before it, not always the calendar
        // month. `.all` has no previous period, so no chip. (FER-264)
        let comparison = window.range.periodComparison(of: model.series)
        // Absolute °C delta vs the previous period — and only when there IS one (previous.n > 0). A
        // percentage would be unstable on a near-zero mean, so we never pass one.
        let periodDelta: Double? = (comparison?.previous.n ?? 0) > 0 ? comparison?.delta : nil
        let typical = model.typicalSD
        return InfoAccordion(
            title: "Trend",
            explanation: "Each point is one night's deviation from your baseline. The shaded band is your own typical night-to-night swing (±1 SD around 0) — inside it is business as usual; a run of nights poking out the same side is the signal. Average and the range come from the period you pick; the chip compares this period's average with the previous period of the same length, in °C.",
            accessibilityLabel: "Information about the skin temperature trend",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // The daily deviation line (raw, not a moving average — the night-to-night signal is read
                // day to day) over a subtle «typical variation» band (±1 SD around 0), drawn by `TrendChart`'s
                // native bands in the strain hue at low opacity so the line stays the protagonist.
                MetricTrendChart(
                    range: $range,
                    window: window,
                    theme: theme,
                    style: .init(
                        gradient: Gradient(colors: [theme.inkSecondary.opacity(0.5), theme.inkSecondary]),
                        showsArea: false,
                        valueRange: { chartRange($0, typical: typical) },
                        valueFormat: { "\(fmt($0)) °C" },
                        bands: { _ in
                            typical > 0.01
                                ? [TrendBand(label: "typical", lower: -typical, upper: typical, isActive: true)]
                                : []
                        },
                        bandColor: { _ in theme.dataStrain },
                        accessibilityLabel: "Nightly skin-temperature deviation, in degrees Celsius"
                    )
                ) {
                    emptyWell(text: "Not enough days in this range to draw a trend.")
                }
                if window.values.count > 1 {
                    TrendStatSummary(
                        average: fmt(stat.mean),
                        unit: "°C",
                        pctChange: nil,
                        absoluteChange: periodDelta,
                        polarity: .neutral,
                        period: window.range.comparisonPeriod ?? .month,
                        rangeLow: fmt(stat.min),
                        rangeHigh: "\(fmt(stat.max)) °C",
                        theme: theme)
                }
            }
        }
    }

    // MARK: - 3. Consistencia — la desviación estándar en °C (NO el CV%: la media ≈0 lo haría absurdo)

    private var consistencyBlock: some View {
        InfoAccordion(
            title: "Consistency",
            explanation: "The standard deviation of your nightly deviations — how much your skin temperature wanders around your baseline from night to night, in °C. A small number means steady thermoregulation; a larger one means more night-to-night swing. (We show the spread in °C rather than a percentage because the average sits near zero, where a percentage would be meaningless.)",
            accessibilityLabel: "Information about consistency",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("±\(String(format: "%.1f", model.consistencySD ?? 0))")
                        .font(StrandFont.title2)
                        .foregroundStyle(theme.ink)
                    Text("°C").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                }
                Text("How much your nightly temperature swings around your baseline. Lower is steadier.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - 4. Ver el método (DisclosureGroup, patrón de las otras pantallas)

    private var methodDisclosure: some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                Text("Each night your strap records skin temperature. We compare it with a rolling baseline of your own recent nights and report the difference in °C — so the value is always relative to you, not an absolute temperature. The trend and the spread are computed from that same nightly deviation.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Nightly skin-temperature deviation from a personal rolling baseline. A comfort signal, not a thermometer or a diagnosis.")
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

    // MARK: - Format + window math (mirror the sibling screens, scoped to this screen)

    /// Skin-temp reads as a SIGNED deviation at one decimal (e.g. "+0.3", "−0.2"), like the row and hero.
    private func fmt(_ v: Double) -> String { String(format: "%+.1f", v) }

    /// Auto-fit the chart's axis to the data, always including 0 and the ±typical band so the band reads as
    /// a band (not a clipped edge), with a little padding.
    private func chartRange(_ values: [Double], typical: Double) -> ClosedRange<Double> {
        let lo = Swift.min(values.min() ?? 0, -typical, 0)
        let hi = Swift.max(values.max() ?? 0, typical, 0)
        let pad = Swift.max((hi - lo) * 0.15, 0.1)
        return (lo - pad)...(hi + pad)
    }

    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - SkinTempDetailModel — the data the screen draws, built ONCE from the repo (DB-free presentation)

struct SkinTempDetailModel {
    /// The latest skin-temperature deviation (°C) — today's if present, else the most recent (Apple
    /// fallback resolved by the caller). Drives the hero; nil → the empty hero.
    let today: Double?
    /// The full nightly deviation series (oldest → newest), `(day "yyyy-MM-dd", value °C)`.
    let series: [(day: String, value: Double)]
    /// Whether the repo finished its first load (drives loading vs empty hero copy).
    let loaded: Bool

    /// Sample standard deviation of the whole series in °C — the «Consistency» datum. nil with <2 points so
    /// the block is skipped (mirrors how the siblings gate consistency).
    var consistencySD: Double? {
        let vals = series.map(\.value)
        guard vals.count >= 2 else { return nil }
        return ComparisonEngine.stat(vals).stdev
    }

    /// The typical night-to-night swing (±1 SD) used for the chart's «typical variation» band; 0 when there
    /// isn't enough history (then no band is drawn).
    var typicalSD: Double { consistencySD ?? 0 }

    /// True when there's a reading or any stored history to draw (the rich path); false → empty.
    var hasData: Bool { today != nil || !series.isEmpty }

    /// Build the whole model from the repo's in-memory dashboard. Pure (no DB). `latest` is the resolved
    /// most-recent deviation (the caller runs `resolveMeasured`); `series` is the full `displayDays` series.
    static func build(latest: Double?, series: [(day: String, value: Double)], loaded: Bool) -> SkinTempDetailModel {
        SkinTempDetailModel(today: latest, series: series.sorted { $0.day < $1.day }, loaded: loaded)
    }
}

// MARK: - Sheet item

/// Identifiable wrapper so the light «Instrumento» Detalle de Temperatura de la piel can ride `.sheet(item:)`
/// (the model itself isn't Identifiable). Built fresh on tap in Cuerpo. (FER-256)
struct SkinTempDetailItem: Identifiable {
    let id = UUID()
    let model: SkinTempDetailModel
}

// MARK: - Sheet paper background (iOS 16.4+ presentationBackground)

private struct SkinTempSheetPaperBackground: ViewModifier {
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
private func sampleSkinTempSeries(days: Int = 60) -> [(day: String, value: Double)] {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let f = SkinTempDetailScreen.dayParser
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = 0.25 * sin(Double(i) / 4.0) + Double((i * 7) % 3 - 1) * 0.08
        return (f.string(from: date), v)
    }
}

#Preview("Skin temp detail — con datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        SkinTempDetailScreen(
            model: SkinTempDetailModel.build(latest: 0.3, series: sampleSkinTempSeries(), loaded: true))
    }
}

#Preview("Skin temp detail — sin datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        SkinTempDetailScreen(
            model: SkinTempDetailModel.build(latest: nil, series: [], loaded: true))
    }
}
#endif
#endif
