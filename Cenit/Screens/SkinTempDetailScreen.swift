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
    /// Which inline disclosure is open (one at a time): `"band"` or `"stat:<slot>"`. (Detalle de Vital)
    @State private var openDisclosure: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if !model.loaded {
                    loadingWell(height: 160)
                } else {
                    if model.series.count >= 2 {
                        blockDivider
                        historiaSection
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
            parsed = model.series.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
        }
    }

    private func toggle(_ key: String) { openDisclosure = (openDisclosure == key) ? nil : key }

    /// A subtle 1px rule between blocks (token-only). Mirrors the sibling screens' `blockDivider`.
    private var blockDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    // MARK: - 1. Hoy — la última lectura (±°C) en ink neutral (la temperatura no es buena ni mala)

    /// The Hoy section: a warm overline, today's signed deviation in neutral ink (it's not good or bad), a
    /// streak chip when several nights have drifted the same way (the signal is a run, not one night), the
    /// plain reading, and the inline «typical swing (±1 SD), 0 = your baseline» bar (tappable). (Detalle de Vital)
    private var hero: some View {
        let v = model.today
        return VStack(alignment: .leading, spacing: 10) {
            Text("Skin temperature · last night").instrumentoOverline().foregroundStyle(theme.warning)
            HStack(alignment: .top) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(v.map { fmt($0) } ?? "—")
                        .instrumentoHero(44)
                        .foregroundStyle(v == nil ? theme.inkTertiary : theme.ink)
                    if v != nil {
                        Text("°C").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    }
                }
                Spacer(minLength: 8)
                if let s = streak { streakChip(s).padding(.top, 4) }
            }
            Text(heroReading)
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.loaded { inlineBandSection }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A run of recent nights drifting the same side of the baseline — the signal skin temp actually
    /// carries. nil when last night sat near baseline (|dev| < 0.3 °C) or there's no reading.
    private var streak: (count: Int, warmer: Bool)? {
        guard let today = model.today, abs(today) >= 0.3 else { return nil }
        let warmer = today > 0
        var n = 0
        for v in model.series.map(\.value).reversed() {
            if (warmer && v > 0) || (!warmer && v < 0) { n += 1 } else { break }
        }
        return n >= 1 ? (n, warmer) : nil
    }

    private func streakChip(_ s: (count: Int, warmer: Bool)) -> some View {
        let text: LocalizedStringKey = {
            switch (s.count, s.warmer) {
            case (1, true):  return "First night warmer"
            case (_, true):  return "\(s.count) nights warmer"
            case (1, false): return "First night cooler"
            default:         return "\(s.count) nights cooler"
            }
        }()
        return HStack(spacing: 3) {
            Image(systemName: s.warmer ? "arrow.up" : "arrow.down").font(.system(size: 9, weight: .semibold))
            Text(text).font(StrandFont.footnote)
        }
        .foregroundStyle(theme.warning)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(theme.warning.opacity(0.12)))
    }

    // MARK: Inline «typical swing» band (±1 SD around 0 = your baseline), tappable

    @ViewBuilder private var inlineBandSection: some View {
        if model.typicalSD > 0.01, let today = model.today {
            let sd = model.typicalSD
            let axisLo = -sd * 2.2, axisHi = sd * 2.2, span = axisHi - axisLo
            let bandLo = CGFloat((-sd - axisLo) / span), bandHi = CGFloat((sd - axisLo) / span)
            let zero = CGFloat((0 - axisLo) / span)
            let mark = CGFloat(min(max((today - axisLo) / span, 0.02), 0.98))
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(StrandMotion.interactive) { toggle("band") } } label: {
                    inlineBandBar(bandLo: bandLo, bandHi: bandHi, zero: zero, mark: mark, sd: sd)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Your nightly baseline"))
                if openDisclosure == "band" {
                    inlineDisclosure(
                        label: "Your nightly baseline",
                        text: "How far last night's skin temperature ran from your own recent baseline, in °C. We learn your normal over recent nights, so 0 is your usual and the number is the shift up or down. A single warm or cool night rarely means much — what's worth noticing is several nights in a row drifting the same way. It's a comfort signal, not a thermometer or a diagnosis."
                    ).padding(.top, 9)
                }
            }
        }
    }

    private func inlineBandBar(bandLo: CGFloat, bandHi: CGFloat, zero: CGFloat, mark: CGFloat, sd: Double) -> some View {
        let open = openDisclosure == "band"
        return VStack(spacing: 5) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline)
                    Capsule().fill(theme.dataStrain.opacity(0.16))
                        .frame(width: max(0, w * (bandHi - bandLo)))
                        .offset(x: w * bandLo)
                    Rectangle().fill(theme.hairlineStrong).frame(width: 1, height: 14)
                        .offset(x: w * zero - 0.5)
                    ZStack {
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(theme.paper).frame(width: 7, height: 16)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(theme.ink).frame(width: 3, height: 14)
                    }
                    .offset(x: w * mark - 3.5)
                }
            }
            .frame(height: 8)
            HStack {
                Text(fmt(-sd)).font(StrandFont.footnote).monospacedDigit().foregroundStyle(theme.inkTertiary)
                Spacer()
                HStack(spacing: 5) {
                    Text("typical swing · 0 = your baseline").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(theme.inkTertiary)
                }
                Spacer()
                Text(fmt(sd)).font(StrandFont.footnote).monospacedDigit().foregroundStyle(theme.inkTertiary)
            }
        }
        .padding(4)
        .background(open ? theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
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

    // MARK: - 2. Tu historia — selector + línea de desviación (±SD, 0 punteado, hoy marcado) + tira de stats

    private var historiaSection: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        let stat = ComparisonEngine.stat(window.values)
        let comparison = window.range.periodComparison(of: model.series)
        // Absolute °C delta vs the previous period — only when there IS one. A percentage would be unstable
        // on a near-zero mean, so we never compute one. (FER-264 / FER-256)
        let periodDelta: Double? = (comparison?.previous.n ?? 0) > 0 ? comparison?.delta : nil
        let typical = model.typicalSD
        return VStack(alignment: .leading, spacing: 12) {
            Text("Your story").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme) { $0.label }
            // The daily deviation line over a subtle «typical swing» band (±1 SD around 0), with 0 dashed and
            // tonight's point marked. The band carries no in-plot label (it's named below). (Detalle de Vital)
            MetricTrendChart(
                range: $range,
                window: window,
                theme: theme,
                showsSelector: false,
                style: .init(
                    gradient: Gradient(colors: [theme.inkSecondary.opacity(0.5), theme.inkSecondary]),
                    showsArea: false,
                    valueRange: { chartRange($0, typical: typical) },
                    valueFormat: { "\(fmt($0)) °C" },
                    bands: { _ in
                        typical > 0.01
                            ? [TrendBand(label: "", lower: -typical, upper: typical, isActive: true)]
                            : []
                    },
                    bandColor: { _ in theme.dataStrain },
                    marksLastPoint: true,
                    bandLabelsHidden: true,
                    referenceLine: 0,
                    referenceLineColor: theme.inkTertiary.opacity(0.6),
                    accessibilityLabel: "Nightly skin-temperature deviation, in degrees Celsius"
                )
            ) {
                emptyWell(text: "Not enough days in this range to draw a trend.")
            }
            Text("Each night's deviation · the band is your typical swing (±your variation) · 0 is your baseline.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if window.values.count > 1 {
                statStrip(mean: stat.mean, sd: model.consistencySD ?? 0, change: periodDelta)
            }
        }
    }

    // MARK: Stat strip — Promedio · Variación · Cambio, each tappable into its disclosure

    @ViewBuilder private func statStrip(mean: Double, sd: Double, change: Double?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                statCell(slot: "promedio", label: "Average", value: fmt(mean),
                         disclosure: EX_ST_TREND)
                statCell(slot: "variacion", label: "Variation", value: "±\(String(format: "%.1f", sd))",
                         disclosure: EX_ST_CONSIST)
                statCell(slot: "cambio", label: "Change", value: change.map { fmt($0) } ?? "—",
                         disclosure: change == nil ? nil : EX_ST_TREND)
            }
            if let open = openDisclosure, open.hasPrefix("stat:") {
                let slot = String(open.dropFirst("stat:".count))
                switch slot {
                case "promedio", "cambio": inlineDisclosure(label: "Average and change", text: EX_ST_TREND)
                case "variacion":          inlineDisclosure(label: "Variation", text: EX_ST_CONSIST)
                default:                   EmptyView()
                }
            }
        }
    }

    private func statCell(slot: String, label: LocalizedStringKey, value: String, disclosure: LocalizedStringKey?) -> some View {
        let isOpen = openDisclosure == "stat:\(slot)"
        let tappable = disclosure != nil
        return Button {
            withAnimation(StrandMotion.interactive) { toggle("stat:\(slot)") }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(label).textCase(.uppercase).font(StrandFont.footnote)
                        .foregroundStyle(theme.inkTertiary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 2)
                    if tappable {
                        Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(theme.inkTertiary)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(StrandFont.number(14)).foregroundStyle(theme.ink)
                    Text("°C").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isOpen ? theme.dataStrain : theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
    }

    // MARK: Disclosure panel (mirrors MetricDetailScreen's) + the reused explanation copy

    @ViewBuilder private func disclosurePanel<C: View>(@ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(theme.hairlineStrong).frame(width: 2)
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func inlineDisclosure(label: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        disclosurePanel {
            Text(label).instrumentoOverline().foregroundStyle(theme.warning)
            Text(text).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var EX_ST_TREND: LocalizedStringKey { "Each point is one night's deviation from your baseline. The shaded band is your own typical night-to-night swing (±1 SD around 0) — inside it is business as usual; a run of nights poking out the same side is the signal. Average and the range come from the period you pick; the chip compares this period's average with the previous period of the same length, in °C." }
    private var EX_ST_CONSIST: LocalizedStringKey { "The standard deviation of your nightly deviations — how much your skin temperature wanders around your baseline from night to night, in °C. A small number means steady thermoregulation; a larger one means more night-to-night swing. (We show the spread in °C rather than a percentage because the average sits near zero, where a percentage would be meaningless.)" }

    // MARK: - 3. Ver el método (DisclosureGroup, patrón de las otras pantallas)

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
