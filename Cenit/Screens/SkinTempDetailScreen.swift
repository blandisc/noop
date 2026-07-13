#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - SkinTempDetailScreen — el «Detalle de Temperatura de la piel» en «Instrumento» (FER-256)
//
// Hermana de `StrainDetailScreen` (FER-238) y `StressDetailScreen` (FER-241): REUSA su lenguaje visual
// (hero con `HeroInvertido`, `theme: InstrumentoTheme` explícito, `sheetPaper`,
// `ScrollView`→`VStack` full-bleed Final, `PieMetodo`, los wells) pero
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
// Por eso NO trae «rango normal» con umbrales fijos ni placeholder de calendario.
//
// Esqueleto Final (misma forma que `MetricDetailScreen.narrativeBodyFinal`): HeroInvertido →
// SeccionBloque «Today, vs your range» → «Your story» → (opcional thermal) → «Your pattern» → PieMetodo.
// Consume `repo.displayDays` TAL CUAL: no crea matemática.

/// Light «Instrumento» Detalle de Temperatura de la piel. Built once from a `SkinTempDetailModel` (the
/// caller injects it so the screen stays DB-free), themed explicitly for the sheet boundary.
struct SkinTempDetailScreen: View {
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    /// Everything the screen draws from the in-memory dashboard, derived ONCE by the caller (no DB here).
    let model: SkinTempDetailModel
    /// Loads the recent per-night distal warming magnitudes (°C) for the nocturnal thermal-stability read
    /// (FER-850), behind the experimental toggle. The heavy multi-night skin-temp read lives in the repo.
    var loadWarmingMagnitudes: () async -> [Double?] = { [] }

    /// The trend block's period window (W/M/3M/6M/1Y/ALL). Defaults to a month.
    @State private var range: ExploreRange = .month
    /// The series with each `day` string parsed to a `Date` exactly ONCE (not per slice / per render) — the
    /// window math reads `date` straight from here. Built in `.task`. (FER-216 lesson)
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    /// Which inline disclosure is open (one at a time): `"band"`. (Detalle de Vital)
    @State private var openDisclosure: String? = nil
    /// The nocturnal thermal-stability read (typical warming + night-to-night consistency), loaded async
    /// behind the experimental toggle; `nil` until loaded or when off. (FER-850)
    @State private var thermal: ThermalStabilityEngine.Result? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroFinal
                // Streak chip sits on paper below the inverted hero (warning tint reads on paper, not on
                // the saturated dataStrain field). Does not map into HeroInvertido's three slots cleanly.
                if let s = streak {
                    streakChip(s)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                }
                if !model.loaded {
                    ChartWell(theme).loading(height: 160)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                } else {
                    SeccionBloque(String(localized: "Today, vs your range"), theme: theme) {
                        inlineBandSection
                    }
                    if model.series.count >= 2 {
                        SeccionBloque(String(localized: "Your story"), theme: theme) {
                            historiaFinalContent
                        }
                    }
                    if WhitespaceMetricsExperiment.isEnabled, let t = thermal {
                        SeccionBloque(String(localized: "Nightly thermal stability"), theme: theme) {
                            thermalBlock(t)
                        }
                    }
                    SeccionBloque(String(localized: "Your pattern"), theme: theme) {
                        patronFinalContent
                    }
                    pieMetodoFinal
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
        .task {
            range = .month
            parsed = model.series.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
        }
        // Load the nocturnal thermal-stability read once, only when the experimental toggle is on. The
        // heavy multi-night skin-temp read lives behind `loadWarmingMagnitudes`. (FER-850)
        .task {
            guard WhitespaceMetricsExperiment.isEnabled else { return }
            let mags = await loadWarmingMagnitudes()
            thermal = mags.isEmpty ? nil : ThermalStabilityEngine.evaluate(magnitudes: mags)
        }
    }

    private func toggle(_ key: String) { openDisclosure = (openDisclosure == key) ? nil : key }

    // MARK: - Hero Final (HeroInvertido · neutral polarity · dataStrain hue)

    /// Inverted hero: signed °C deviation as the numeral, plain-language reading as the verdict.
    /// Hue is `theme.dataStrain` (ember/amber) — neutral identity, not a good/bad verdict color.
    private var heroFinal: some View {
        let v = model.today
        return HeroInvertido(
            glyph: .skinTemp,
            title: "Skin temp",
            hue: theme.dataStrain,
            theme: theme,
            numeral: {
                if let v {
                    HeroNumeral(fmt(v), suffix: "°C", size: 60, theme: theme)
                } else {
                    Text(verbatim: "—")
                        .font(InstrumentoType.groteskNumber(60, weight: .bold))
                        .tracking(-2)
                        .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                }
            },
            verdict: {
                Text(heroReading)
                    .font(InstrumentoType.grotesk(15, weight: .semibold))
                    .foregroundStyle(theme.paper)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }

    // MARK: - Estabilidad térmica nocturna (FER-850) — tras el toggle experimental

    /// The «Nightly thermal stability» block: the typical distal warming (°C) into sleep as the datum, a
    /// night-to-night consistency word, and an honest one-liner. Framed as an ASSOCIATION — never a full
    /// 24-hour circadian amplitude (we only have the night). Only shown with the experimental toggle on.
    @ViewBuilder private func thermalBlock(_ t: ThermalStabilityEngine.Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nightly thermal stability").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if t.stability == .learning {
                Text("Still learning how consistent your nightly warming is: keep wearing it to bed.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: String(format: "%.1f", t.typicalWarmingC))
                        .instrumentoHero(44)
                        .foregroundStyle(theme.ink)
                    Text(verbatim: "°C").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    Text("typical warming into sleep")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("night to night").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text(thermalWord(t.stability))
                        .font(StrandFont.number(21, weight: .semibold))
                        .foregroundStyle(thermalColor(t.stability))
                }
                Text(thermalCopy(t))
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thermalWord(_ s: ThermalStabilityEngine.Stability) -> LocalizedStringKey {
        switch s {
        case .consistent: return "Consistent"
        case .moderate:   return "Moderate"
        case .variable:   return "Variable"
        case .learning:   return "Learning"
        }
    }

    private func thermalColor(_ s: ThermalStabilityEngine.Stability) -> Color {
        switch s {
        case .consistent: return theme.dataRecovery
        case .moderate:   return theme.ink
        case .variable:   return theme.warning
        case .learning:   return theme.inkTertiary
        }
    }

    /// Honest, localized one-liner — composed in the UI (not the engine's English `copy`) so it localizes
    /// with the app catalog. ASSOCIATION framing, never a 24-hour circadian-amplitude claim. (FER-850)
    private func thermalCopy(_ t: ThermalStabilityEngine.Result) -> LocalizedStringKey {
        switch t.stability {
        case .consistent: return "Your body's warming as you fall asleep is steady night-to-night. A consistent wind-down: an association, not a full 24-hour rhythm."
        case .moderate:   return "Your nightly warming into sleep varies a moderate amount night-to-night. An association, not a full 24-hour rhythm."
        case .variable:   return "Your nightly warming into sleep swings a fair amount night-to-night. A steadier wind-down tends to settle it. An association, not a full 24-hour rhythm."
        case .learning:   return ""
        }
    }

    // MARK: - Streak chip (nights warmer / cooler)

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
            Image(systemName: s.warmer ? "arrow.up" : "arrow.down").font(.system(size: 9, weight: .semibold)) // token-exempt: microtexto <10pt
            Text(text).font(StrandFont.footnote)
        }
        .foregroundStyle(theme.warning)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(theme.warning.opacity(StrandOpacity.tintFill)))
    }

    // MARK: Inline «typical swing» band (±1 SD around 0 = your baseline), tappable
    // Content of SeccionBloque «Today, vs your range» — math/geometry/disclosure VERBATIM.

    @ViewBuilder private var inlineBandSection: some View {
        if model.typicalSD > 0.01, let today = model.today {
            let sd = model.typicalSD
            let axisLo = -sd * 2.2, axisHi = sd * 2.2, span = axisHi - axisLo
            let bandLo = CGFloat((-sd - axisLo) / span), bandHi = CGFloat((sd - axisLo) / span)
            let zero = CGFloat((0 - axisLo) / span)
            let mark = CGFloat(min(max((today - axisLo) / span, 0.02), 0.98))
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.easeInOut(duration: 0.25)) { toggle("band") } } label: {
                    inlineBandBar(bandLo: bandLo, bandHi: bandHi, zero: zero, mark: mark, sd: sd, today: today)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Your nightly baseline"))
                if openDisclosure == "band" {
                    inlineDisclosure(
                        label: "Your nightly baseline",
                        text: "How far last night's skin temperature ran from your own recent baseline, in °C. We learn your normal over recent nights, so 0 is your usual and the number is the shift up or down. A single warm or cool night rarely means much: what's worth noticing is several nights in a row drifting the same way. It's a comfort signal, not a thermometer or a diagnosis."
                    ).padding(.top, 9)
                }
            }
        }
    }

    private func inlineBandBar(bandLo: CGFloat, bandHi: CGFloat, zero: CGFloat, mark: CGFloat, sd: Double, today: Double) -> some View {
        let open = openDisclosure == "band"
        let outside = today < -sd || today > sd
        return VStack(spacing: 6) {
            // The ±SD edge numbers sit under the band's ACTUAL edges (not the bar's ends, which left them
            // floating away from the band), and last night's deviation is rotulated above the mark — amber
            // when it ran past the typical swing. `.position` anchors each by fraction, clamped off the edge.
            // (Detalle de Vital — rótulos desalineados, mismo fix que la barra de los vitales)
            GeometryReader { geo in
                let w = geo.size.width
                let clampX: (CGFloat) -> CGFloat = { x in min(max(x, 14), w - 14) }
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.hairline)
                        Capsule().fill(theme.dataStrain.opacity(StrandOpacity.tintFillStrong))
                            .frame(width: max(0, w * (bandHi - bandLo)))
                            .offset(x: w * bandLo)
                        Rectangle().fill(theme.hairlineStrong).frame(width: 1, height: 14)
                            .offset(x: w * zero - 0.5)
                        ZStack {
                            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(theme.paper).frame(width: 7, height: 16) // token-exempt: geometría de dato
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(theme.ink).frame(width: 3, height: 14) // token-exempt: geometría de dato
                        }
                        .offset(x: w * mark - 3.5)
                    }
                    .frame(width: w, height: 8)
                    .position(x: w / 2, y: 23)

                    Text(fmt(today)).font(StrandFont.footnote).monospacedDigit()
                        .foregroundStyle(outside ? theme.warning : theme.ink).fixedSize()
                        .position(x: clampX(w * mark), y: 8)

                    Text(fmt(-sd)).font(StrandFont.footnote).monospacedDigit()
                        .foregroundStyle(theme.inkTertiary).fixedSize()
                        .position(x: clampX(w * bandLo), y: 38)
                    Text(fmt(sd)).font(StrandFont.footnote).monospacedDigit()
                        .foregroundStyle(theme.inkTertiary).fixedSize()
                        .position(x: clampX(w * bandHi), y: 38)
                }
            }
            .frame(height: 46)
            HStack(spacing: 5) {
                Text("typical swing · 0 = your baseline").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                StrandIcon.info.image.font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
            }
        }
        .padding(4)
        // Warm paper tint when open, not the near-white `surface`. (Detalle de Vital fix)
        .background(open ? theme.hairline : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous)) // token-exempt: fondo condicional
        .contentShape(Rectangle())
    }

    /// A plain-language, NON-clinical reading of last night's deviation, or an honest "no reading yet" when
    /// there's none. Thresholds are deliberately soft (≈±0.3 °C ≈ a typical night-to-night swing): we never
    /// claim fever or illness — just whether the night sat near, above or below the user's own baseline.
    /// Source strings are English; the es values live in `Localizable.xcstrings`.
    private var heroReading: LocalizedStringKey {
        guard let v = model.today else {
            if !model.series.isEmpty { return "No reading from last night yet: your recent history is below." }
            return "No skin-temperature reading yet. Wear your strap overnight and open this again after it syncs."
        }
        if abs(v) < 0.3 { return "Right around your usual nighttime baseline." }
        return v > 0 ? "A touch warmer than your baseline last night."
                     : "A touch cooler than your baseline last night."
    }

    // MARK: - Your story — period selector + GraficaRangos + TileSurface strip

    @ViewBuilder private var historiaFinalContent: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        let stat = ComparisonEngine.stat(window.values)
        let comparison = window.range.periodComparison(of: model.series)
        // Absolute °C delta vs the previous period — only when there IS one. A percentage would be unstable
        // on a near-zero mean, so we never compute one. (FER-264 / FER-256)
        let periodDelta: Double? = (comparison?.previous.n ?? 0) > 0 ? comparison?.delta : nil
        VStack(alignment: .leading, spacing: 8) {
            SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme) { $0.label }
            if window.values.count > 1 {
                graficaRangosBlock(window: window, mean: stat.mean, periodDelta: periodDelta)
                    .padding(.top, 6)
                    .id(range)
                tileStripFinal(mean: stat.mean, sd: model.consistencySD ?? 0, change: periodDelta)
                    .padding(.top, 4)
            } else {
                ChartWell(theme).empty(text: "Not enough days in this range to draw a trend.")
            }
        }
    }

    /// GraficaRangos over the windowed nightly deviations: personal ±SD wash, 0 = baseline ref line,
    /// HRV-style personal Rangos lanes (no clinical bands), absolute °C period delta (neutral color).
    @ViewBuilder private func graficaRangosBlock(window: MetricWindow, mean: Double, periodDelta: Double?) -> some View {
        let typical = model.typicalSD
        let domain = chartRange(window.values, typical: typical)
        let bands = graficaRangosBands()
        let wash: GraficaRangos.Wash? = typical > 0.01
            ? .init(lo: -typical, hi: typical)
            : nil
        let labels = window.rows.map { RecoveryDetailScreen.axisLabel($0.day) ?? "" }
        GraficaRangos(
            points: window.values,
            bands: bands,
            ticks: graficaTicks(domain: domain),
            wash: wash,
            refLine: .init(v: 0, label: nil),
            hue: theme.dataStrain,
            ymin: domain.lowerBound,
            ymax: domain.upperBound,
            startLabel: window.rows.first.flatMap { RecoveryDetailScreen.axisLabel($0.day) } ?? "",
            endLabel: window.rows.last.flatMap { RecoveryDetailScreen.axisLabel($0.day) } ?? "",
            mediaValue: fmt(mean),
            mediaNote: String(localized: "average of the \(window.range.name)"),
            mediaDelta: periodDelta.map { fmt($0) },
            deltaColor: theme.inkSecondary,
            countUnit: "n",
            anchorMedia: String(localized: "Each night's deviation · the band is your typical swing (±your variation) · 0 is your baseline."),
            anchorRangos: bands.isEmpty ? nil
                : String(localized: "How many days of the period fell in each band. Tap one to see its days on the chart."),
            scrub: true,
            labels: labels,
            fmt: { fmt($0) },
            theme: theme
        )
    }

    /// Personal ±σ lanes for Rangos mode (mirror MetricDetailScreen HRV: no clinical bands).
    private func graficaRangosBands() -> [GraficaRangos.Banda] {
        let sd = model.typicalSD
        guard sd > 0.01 else { return [] }
        let lo = -sd, hi = sd
        return [
            .init(label: String(localized: "Unusual for you"), lo: hi.nextUp, hi: nil,
                  color: theme.warning, range: "≥ \(fmt(hi))"),
            .init(label: String(localized: "Normal for you"), lo: lo, hi: hi.nextUp,
                  color: theme.dataStrain, range: "\(fmt(lo))–\(fmt(hi))"),
            .init(label: String(localized: "Unusual for you"), lo: nil, hi: lo,
                  color: theme.warning, range: "< \(fmt(lo))")
        ]
    }

    private func graficaTicks(domain: ClosedRange<Double>) -> [GraficaRangos.Tick] {
        let lo = domain.lowerBound, hi = domain.upperBound
        guard hi > lo else { return [] }
        let mid = (lo + hi) / 2
        return [
            .init(v: hi, label: fmt(hi)),
            .init(v: mid, label: fmt(mid)),
            .init(v: lo, label: fmt(lo))
        ]
    }

    /// Stat strip as display-only TileSurface tiles (Final). The old tappable Average / Variation /
    /// Change disclosures do not map 1:1 onto TileSurface, so they are not recreated here.
    @ViewBuilder private func tileStripFinal(mean: Double, sd: Double, change: Double?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            TileSurface(label: String(localized: "Average"),
                        value: fmt(mean),
                        caption: "°C",
                        theme: theme)
            TileSurface(label: String(localized: "Variation"),
                        value: "±\(String(format: "%.1f", sd))",
                        caption: "°C",
                        theme: theme)
            TileSurface(label: String(localized: "Change"),
                        value: change.map { fmt($0) } ?? "—",
                        caption: change != nil ? "°C" : nil,
                        theme: theme)
        }
    }

    // MARK: - Your pattern — static prose (no findings engine for skin temp)

    private var patronFinalContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            QueLaMueveHeader("What moves it", chip: "trend, not cause", theme: theme)
            Text("Tends to rise with alcohol, fever, and ambient heat.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Disclosure panel (band bar only) + method foot

    @ViewBuilder private func disclosurePanel<C: View>(@ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(theme.hairlineStrong).frame(width: 2)
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        // Fade in place (no slide) — smoother than flying in from the top. (Detalle de Vital fix)
        .transition(.opacity)
    }

    private func inlineDisclosure(label: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        disclosurePanel {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(text).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// PieMetodo: method disclosure + origin seal (origin `.band`, when «last night»).
    @ViewBuilder private var pieMetodoFinal: some View {
        PieMetodo(theme: theme) {
            Metodo(title: String(localized: "How it's calculated"), theme: theme) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Each night your strap records skin temperature. We compare it with a rolling baseline of your own recent nights and report the difference in °C: so the value is always relative to you, not an absolute temperature. The trend and the spread are computed from that same nightly deviation.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Nightly skin-temperature deviation from a personal rolling baseline. A comfort signal, not a thermometer or a diagnosis.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } sello: {
            if !model.series.isEmpty {
                OriginStamp(origin: .band, when: String(localized: "last night"), theme: theme)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Format + window math (mirror the sibling screens, scoped to this screen)

    /// Skin-temp reads as a SIGNED deviation at one decimal (e.g. "+0.3", "−0.2"), like the row and hero.
    private func fmt(_ v: Double) -> String { String(format: "%+.1f", v) }

    /// Auto-fit the chart's axis to the data, always including 0 and the ±typical band so the band reads as
    /// a band (not a clipped edge), with a little padding.
    private func chartRange(_ values: [Double], typical: Double) -> ClosedRange<Double> {
        // Open the axis around the ±typical band (≈ band ± 0.85× its full width) so it reads as a central
        // stripe with air above and below — not a full-bleed box. Always include 0 and the data. (Detalle de Vital)
        let edge = typical + Swift.max(typical * 1.7, 0.1)
        let lo = Swift.min(values.min() ?? 0, -edge, 0)
        let hi = Swift.max(values.max() ?? 0, edge, 0)
        let pad = Swift.max((hi - lo) * 0.06, 0.05)
        return (lo - pad)...(hi + pad)
    }

    /// The canonical UTC day-key formatter — read side of the day-key contract (FER-754).
    static let dayParser = DayKey.utcFormatter
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

#Preview("Skin temp detail: con datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        SkinTempDetailScreen(
            model: SkinTempDetailModel.build(latest: 0.3, series: sampleSkinTempSeries(), loaded: true))
    }
}

#Preview("Skin temp detail: sin datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        SkinTempDetailScreen(
            model: SkinTempDetailModel.build(latest: nil, series: [], loaded: true))
    }
}
#endif
#endif
