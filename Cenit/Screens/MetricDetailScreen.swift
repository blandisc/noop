#if os(iOS)
import SwiftUI
import CenitStore
import StrandDesign
import StrandAnalytics
import Foundation

// MARK: - MetricDetailScreen — the unified, reusable Detalle de Métrica (FER-185)
//
// One light «Instrumento» screen that replaces, FOR THE THREE VITALS (HRV / FC en reposo /
// Frecuencia respiratoria), both the old `MetricInfoSheet` (from Hoy) and the dark
// `MetricDetailView` (from Cuerpo's Explorer bridge). It is parameterised by a `MetricDetailSpec`
// (which blocks, how the hero reads, the baseline config) and a `Depth`:
//
//   • `.focus` (from Hoy) — a quick "photo of the day": a short window and only the chart+band,
//     normal range, night vitals (where the spec has them) and method.
//   • `.full`  (from Cuerpo) — every block the spec declares.
//
// It is ONE view tree filtered by depth, never two screens. The theme is passed EXPLICITLY (it does
// NOT propagate through `.sheet`'s fresh environment — FER-162) and it is presented via `.sheet(item:)`
// WITHOUT a nested NavigationStack (a nested stack crossing the tab's path crashed SwiftUI — FER-171).
//
// Data: the three vitals come from `repo.displayDays` for a BLE user (computed scores live under
// `strap-noop`, so `series("strap")` is empty) — the caller injects the loaders. The hero is the
// 7-day moving average (`SeriesShape.latestMovingAverage`), not today's single reading; today is shown
// as secondary context.

struct MetricDetailScreen: View {
    let spec: MetricDetailSpec
    /// Hoy opens `.focus`; Cuerpo opens `.full`.
    var depth: Depth = .full
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    /// When the metric is Apple-sourced and there's no reading + no permission, the empty state adds a
    /// quiet "Connect Apple Health" line. Only used by the sparse VO₂max empty state today. (FER-257)
    var appleConnectHint: Bool = false
    /// True when TODAY's reading (the «Hoy» datum) came from Apple Health rather than the band — the
    /// caller already resolves this per reading (`appleSource` in TodayView, `resolveMeasured.fromApple`
    /// in CuerpoView). Drives the «Apple» provenance seal on the narrative vitals so a band-less Apple
    /// reading never reads identical to a band one (FER-487). Never set for Heart Rate (band intraday).
    var todayFromApple: Bool = false

    /// The day-keys ("yyyy-MM-dd") whose reading came from Apple Health rather than the band
    /// (`repo.appleHealthDays`). For the three cross-source vitals (HRV, resting HR, respiration) the band
    /// and Apple measure with DIFFERENT instruments (RMSSD≠SDNN, resting HR −12.7 bpm, resp +2.3 bpm — no
    /// published conversion), so folding both into one baseline/σ, consistency CV or period Δ% mixes two
    /// scales (FER-629). The screen keeps EVERY night on the today datum + hero (today may be an Apple
    /// night), but folds a SINGLE source into the statistics and the trend line — the band-level equivalent
    /// of `SourceLens.clearBandColumns` (FER-631), kept here as a plain day-key filter so the view stays
    /// DB-free. Empty (a strap-only user, or a single-source metric) → identity, nothing changes. (FER-635)
    var appleDays: Set<String> = []

    /// Loads the full daily series for this metric (oldest → newest), as `(day "yyyy-MM-dd", value)`.
    /// Injected so the screen stays DB-free and the caller controls the source (`displayDays` for BLE,
    /// Apple-Health series as a fallback).
    var seriesLoader: () async -> [(day: String, value: Double)]
    /// Loads last night's companion vitals for the "Vitales de la noche" block: respiration + resting HR.
    /// Only used when the spec declares `.nightVitals`.
    var nightVitalsLoader: (() async -> NightVitals)? = nil
    /// Loads the gated directional findings for the "Qué la mueve" block (FER-209). Only used when the
    /// spec declares `.whatMovesIt`; the caller computes them from `repo.displayDays` (DB-free here).
    var whatMovesItLoader: (() async -> [WhatMovesItFinding])? = nil
    /// Loads today's intraday HR curve (5-minute buckets). Injected only for Heart Rate (the spec
    /// declares `.intradayCurve`); the caller reuses the same `hrPoints` the summary sheet uses. (FER-253)
    var intradayCurveLoader: (() async -> [TrendPoint])? = nil
    /// Loads last night's frequency-domain HRV breakdown (LF/HF/total powers + per-band «your normal»
    /// label). Injected ONLY for the HRV vital by Cuerpo; nil elsewhere (so the section never shows on
    /// the Hoy focus view or the other vitals). Additive — reads `HRVFreqDomain` powers only. (FER-702)
    var spectralLoader: (() async -> SpectralHRV?)? = nil
    /// The user's estimated max HR (bpm), for the "time in zones" block. 0 disables zones. (FER-253)
    var hrMax: Double = 0
    /// Last night's resting HR (bpm), drawn as a quiet reference line under the day's curve. (FER-253)
    var restingHR: Double? = nil
    /// Today's local day key ("yyyy-MM-dd"), passed by the caller (it uses `Repository.localDayKey`, which
    /// the DB-free screen can't reproduce timezone-for-timezone). Lets the trend figures drop the
    /// in-progress current day for a cumulative metric (steps). nil → nothing is dropped. (FER-264)
    var todayKey: String? = nil
    /// `true` cuando Apple Salud NO está autorizado — el campo Liquid apagado lo explica y ofrece el
    /// CTA a Ajustes (calco `StrainDetailScreen.sinPermiso`, FER-101). Default `false`: los call
    /// sites existentes compilan sin cambios; el orquestador cablea TodayView/CuerpoView. (TND-20)
    var sinPermiso: Bool = false

    enum Depth { case focus, full }

    /// The «Tu historia» chart view for metrics with population ranges. (Detalle de Vital)
    enum ChartMode: Hashable, CaseIterable { case movingAverage, ranges }

    /// Companion vitals for the night block.
    struct NightVitals: Equatable {
        var respiration: Double?
        var restingHR: Double?
    }

    /// Last night's frequency-domain HRV breakdown for the «Tu HRV por frecuencia» section (FER-702).
    /// Descriptive band POWERS (ms²) compared to the user's own recent nights — never an autonomic-balance
    /// claim. `lf` is nil when last night's span was too short for the LF band (HF-only night).
    struct SpectralHRV: Equatable {
        struct Band: Equatable {
            var value: Double                        // band power, ms²
            var label: HRVSpectralBaseline.Label?    // vs your normal; nil while calibrating
        }
        var hf: Band
        var lf: Band?
        var total: Double
    }

    @Environment(\.dismiss) private var dismiss
    @State private var range: ExploreRange = .month
    /// «Tu historia» chart mode for metrics that carry labeled population ranges (Resting HR / Respiration /
    /// Steps): your 7-day moving average + personal band, OR the classification ranges (athlete / excellent /
    /// normal / elevated …) showing where you fall. HRV (personal only) and SpO₂ (already clinical) don't
    /// toggle. The «what does this number mean» view the owner asked back for. (Detalle de Vital)
    @State private var chartMode: ChartMode = .movingAverage
    @State private var series: [(day: String, value: Double)] = []
    @State private var nightVitals: NightVitals = NightVitals(respiration: nil, restingHR: nil)
    @State private var whatMovesItFindings: [WhatMovesItFinding] = []
    @State private var intradayCurve: [TrendPoint] = []
    /// Minutes per HR zone for today, computed once when the curve loads (see `computeZoneMinutesDetached`). (FER-253 / FER-976)
    @State private var cachedZoneMinutes: [Double]? = nil
    /// Last night's frequency-domain HRV breakdown (nil = no band-night spectrum → section hidden). (FER-702)
    @State private var spectral: SpectralHRV? = nil
    @State private var loaded = false
    /// The inverted hero's ⓘ toggles the «What we measure» card under the field (Final skeleton).
    @State private var infoOpen = false
    /// El carril del historial Liquid que el dedo explora; `nil` = ninguno (paridad
    /// Sueño/Esfuerzo/Temp de piel — TND-20).
    @State private var bandaExplorada: Int? = nil





    // MARK: - Body

    var body: some View {
        // Derive the window ONCE here, then hand it to every block — instead of each block
        // re-deriving `effectiveRange`/`windowed`/`windowValues` and re-parsing the whole
        // history on every redraw. (FER-216)
        let window = MetricWindowMath.make(parsedSeries, selected: range)
        // FER-103 · TND-20: the four scalar narrative vitals (HRV / rhr / resp_rate / SpO₂)
        // ride the Liquid body; TND-21 adds Steps, TND-22 VO₂max and TND-23 Heart Rate's
        // intraday path — the LAST paper body of the file — each on its own Liquid skeleton.
        // The fondo goes on BOTH presentation forms — `background` for Cuerpo's overlay layer
        // and `presentationBackground` for Hoy's sheet (same pair as SleepDetailScreen /
        // SkinTempDetailScreen, FER-102) — so neither call site changes. The paper trees
        // (`narrativeBodyFinal`, `stepsBodyFinal`, `vo2maxBodyFinal`, `narrativeIntradayFinal`)
        // stay compiled as the rollback, no longer called from here.
        return ScrollView {
            switch spec.descriptor.key {
            case "steps":      stepsBodyLiquid(window)
            case "vo2max":     vo2maxBodyLiquid(window)
            case "heart_rate": intradayBodyLiquid
            default:           narrativeBodyLiquid(window)
            }
        }
        .background { LiquidSheetFondo(tone: liquidTono).ignoresSafeArea() }
        .presentationBackground { LiquidSheetFondo(tone: liquidTono) }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(LiquidRadius.hoja)
        .task {
            range = defaultRange
            if let loader = intradayCurveLoader {
                intradayCurve = await loader()
                // FER-976: snapshot Sendable (Double + [TrendPoint], ambos Sendable) tomado en MainActor,
                // el bucketing/zone-math pesado corre off-main (mismo seam que SleepDetailScreen.buildSleepHeat).
                let maxHRSnapshot = hrMax
                let curveSnapshot = intradayCurve
                cachedZoneMinutes = await Task.detached(priority: .userInitiated) {
                    Self.computeZoneMinutesDetached(hrMax: maxHRSnapshot, intradayCurve: curveSnapshot)
                }.value
            }
            series = await seriesLoader()
            // Parse every day string to a Date ONCE per series (not per slice / per render). (FER-216)
            // The chart/window/trend read the SINGLE-source fold so the plotted line, its ±σ band and the
            // Δ% never mix band and Apple; `series` stays full for today's datum + the hero. (FER-635)
            // FER-976: `statSeries` (filter over `series`) is a cheap O(n) bool filter — stays on MainActor;
            // the DateFormatter parse per row (`Repository.parseDayKey`, the actually expensive part) hops
            // off-main via the Sendable snapshot below.
            let statSeriesSnapshot = statSeries
            parsedSeries = await Task.detached(priority: .userInitiated) {
                statSeriesSnapshot.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
            }.value
            if let loader = nightVitalsLoader { nightVitals = await loader() }
            if visibleBlocks.contains(.whatMovesIt), let loader = whatMovesItLoader {
                whatMovesItFindings = await loader()
            }
            if let loader = spectralLoader { spectral = await loader() }
            loaded = true
        }
    }

    // MARK: - Narrative Final skeleton (HRV / rhr / resp_rate / SpO₂)

    /// Full-bleed Final body for the four scalar vitals: HeroInvertido → SeccionBloque… → PieMetodo.
    /// No external screen padding (franjas go edge-to-edge); section content uses handoff padding.
    @ViewBuilder private func narrativeBodyFinal(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            narrativeHeroFinal
            if infoOpen { queMedimosCardFinal }
            if !loaded {
                ChartWell(theme).loading(height: 160)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            } else if !enoughHistory {
                calibrationBlock
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                if loaded, !series.isEmpty {
                    pieMetodoFinal
                }
            } else {
                SeccionBloque(String(localized: "Today, vs your normal"), theme: theme) {
                    hoyVsRangoContent
                }
                SeccionBloque(String(localized: "Your story"), theme: theme) {
                    historiaFinalContent(window)
                }
                if hasPatron {
                    SeccionBloque(String(localized: "Your pattern"), theme: theme) {
                        patronFinalContent
                    }
                }
                if spec.descriptor.key == "hrv", let s = spectral {
                    SeccionBloque(String(localized: "Your HRV by frequency"), theme: theme) {
                        spectralFinalContent(s)
                    }
                }
                pieMetodoFinal
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inverted hero for the four scalar vitals (Final). Heart Rate uses its own `narrativeHeroIntradayFinal`.
    private var narrativeHeroFinal: some View {
        let glyph = metricGlyph ?? .hrv
        let valueText = heroTodayValue.map { fmt($0) } ?? "—"
        let suffix: String? = (heroTodayValue != nil && !unit.isEmpty) ? unit : nil
        return HeroInvertido(
            glyph: glyph,
            title: narrativeHeroTitle,
            hue: metricHue,
            theme: theme,
            onInfo: { withAnimation(StrandMotion.interactive) { infoOpen.toggle() } },
            numeral: {
                if heroTodayValue == nil {
                    Text(verbatim: "—")
                        .font(InstrumentoType.groteskNumber(60, weight: .bold))
                        .tracking(-2)
                        .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                } else {
                    HeroNumeral(valueText, suffix: suffix, size: 60, theme: theme) {
                        if todayFromApple {
                            Text("Apple")
                                .font(InstrumentoType.grotesk(11, weight: .semibold))
                                .foregroundStyle(theme.paper)
                                .heroCapsule(theme: theme)
                        }
                    }
                }
            },
            verdict: {
                if let v = heroVerdict {
                    if let level = sevenDayLevelText {
                        HeroVeredictoBicolor(word: v.word, clause: level, theme: theme)
                    } else {
                        Text(v.word)
                            .font(InstrumentoType.grotesk(15, weight: .semibold))
                            .foregroundStyle(theme.paper)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let level = sevenDayLevelText {
                    Text(level)
                        .font(InstrumentoType.grotesk(14))
                        .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                }
            }
        )
    }

    /// ⓘ card under the inverted hero — same header reading copy the old narrative kept always visible.
    @ViewBuilder private var queMedimosCardFinal: some View {
        if let reading = readingCopy(for: .header) {
            QueMedimosCard(title: "What we measure", explanation: reading, theme: theme)
        }
    }

    /// «Hoy, vs tu rango»: large coloured datum + in-range pill + position slider (moved out of the hero).
    @ViewBuilder private var hoyVsRangoContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let today = heroTodayValue {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(fmt(today))
                        .font(InstrumentoType.groteskNumber(28, weight: .bold))
                        .foregroundStyle(metricHue)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(InstrumentoType.grotesk(13))
                            .foregroundStyle(theme.inkTertiary)
                    }
                    if let v = heroVerdict {
                        Text(v.word)
                            .font(InstrumentoType.grotesk(11, weight: .semibold))
                            .foregroundStyle(theme.inkSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(theme.patternBlock, in: Capsule())
                    }
                }
            } else {
                Text(verbatim: "—")
                    .font(InstrumentoType.groteskNumber(28, weight: .bold))
                    .foregroundStyle(theme.inkTertiary)
            }
            if let b = inlineBandData {
                positionSlider(b)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(b.disclosureTitle))
                    .accessibilityValue(Text(b.markLabel))
            }
        }
    }

    /// «Tu historia»: period selector + GraficaRangos + TileSurface strip.
    @ViewBuilder private func historiaFinalContent(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if visibleBlocks.contains(.periodSelector) {
                periodSelector(window)
            }
            if window.values.count > 1 {
                graficaRangosBlock(window)
                    .padding(.top, 6)
                    .id(range)
            } else if let only = window.values.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(fmt(only)) \(unit)")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(metricHue)
                    Text("Only one reading in this range: not enough to draw a line yet.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.inkTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
            } else {
                ChartWell(theme).empty(text: "No readings in this range.")
            }
            tileStripFinal(window)
                .padding(.top, 4)
        }
    }

    /// GraficaRangos over the windowed series (Media ⇄ Rangos + scrub + BarraAncla captions).
    @ViewBuilder private func graficaRangosBlock(_ window: MetricWindow) -> some View {
        let rows = trendStatRows(window)
        let raw = rows.map(\.value)
        // SpO₂ (clinical) plots raw nights; personal vitals smooth the noisy overnight series (same as Strain).
        let points: [Double] = spec.clinicalBands ? raw : SeriesShape.movingAverage(raw, window: 7)
        let plot = points.isEmpty ? raw : points
        let stat = ComparisonEngine.stat(plot)
        let pct = window.range.periodComparison(of: trendComparisonSeries)?.pctChange
        let domain = graficaDomain(plot: plot)
        let bands = graficaRangosBands()
        let mediaNote = spec.clinicalBands
            ? String(localized: "average of the \(window.range.name)")
            : String(localized: "7-day moving average")
        let anchorMedia: String? = {
            if spec.clinicalBands {
                return String(localized: "Nightly values · the shaded band is the healthy range.")
            }
            if normalRange != nil {
                return String(localized: "7-day moving average · the band is your normal range.")
            }
            return String(localized: "7-day moving average.")
        }()
        let labels = rows.map { MetricWindowMath.axisLabel($0.day) ?? "" }
        GraficaRangos(
            points: plot,
            bands: bands,
            ticks: graficaTicks(domain: domain),
            wash: graficaWash,
            refLine: graficaRefLine,
            hue: metricHue,
            ymin: domain.lowerBound,
            ymax: domain.upperBound,
            startLabel: rows.first.flatMap { MetricWindowMath.axisLabel($0.day) } ?? "",
            endLabel: rows.last.flatMap { MetricWindowMath.axisLabel($0.day) } ?? "",
            mediaValue: plot.count > 1 ? fmt(stat.mean) : "—",
            mediaNote: mediaNote,
            mediaDelta: pct.map { $0 >= 0 ? "+\(Int($0.rounded()))%" : "\(Int($0.rounded()))%" },
            deltaColor: pct.map { trendDeltaColor($0) },
            countUnit: "n",
            anchorMedia: anchorMedia,
            // FER-43 (gate /cso): el detalle rico dibuja las MISMAS bandas poblacionales que la hoja,
            // así que hereda su rótulo. Sin esto, «Ver más» presentaba la escalera de población sin
            // decir que no es el criterio del veredicto.
            anchorRangos: bands.isEmpty ? nil
                : [String(localized: "How many days of the period fell in each band. Tap one to see its days on the chart."),
                   spec.info.bandsCaption.map { String(localized: $0) }]
                    .compactMap { $0 }.joined(separator: " "),
            scrub: true,
            labels: labels,
            fmt: { fmt($0) },
            theme: theme
        )
    }

    /// Y domain for GraficaRangos: clinical chartDomain, else personal band air, else data fit.
    private func graficaDomain(plot: [Double]) -> ClosedRange<Double> {
        if let domain = spec.chartDomain { return domain }
        if let band = normalRange {
            let span = band.upperBound - band.lowerBound
            let pad = Swift.max(span * 0.6, 1)
            let lo = Swift.min(band.lowerBound - pad, plot.min() ?? band.lowerBound)
            let hi = Swift.max(band.upperBound + pad, plot.max() ?? band.upperBound)
            return lo...hi
        }
        let bounds = spec.info.bands.flatMap { [$0.lower, $0.upper].compactMap { $0 } }
        if let tLo = bounds.min(), let tHi = bounds.max(), tHi > tLo {
            let lo = Swift.min(tLo, plot.min() ?? tLo)
            let hi = Swift.max(tHi, plot.max() ?? tHi)
            let pad = (hi - lo) * 0.1
            return (lo - pad)...(hi + pad)
        }
        return chartRange(plot)
    }

    private func graficaTicks(domain: ClosedRange<Double>) -> [GraficaRangos.Tick] {
        if let clinical = clinicalYAxisValues {
            return clinical.map { .init(v: $0, label: fmt($0)) }
        }
        let lo = domain.lowerBound, hi = domain.upperBound
        guard hi > lo else { return [] }
        let mid = (lo + hi) / 2
        return [
            .init(v: hi, label: fmt(hi)),
            .init(v: mid, label: fmt(mid)),
            .init(v: lo, label: fmt(lo))
        ]
    }

    /// Optional wash: SpO₂ healthy zone, or personal normal range for the media mode.
    private var graficaWash: GraficaRangos.Wash? {
        if spec.descriptor.key == "spo2", let floor = spec.lowThreshold, let domain = spec.chartDomain {
            return .init(lo: floor, hi: domain.upperBound)
        }
        if let band = normalRange {
            return .init(lo: band.lowerBound, hi: band.upperBound)
        }
        return nil
    }

    private var graficaRefLine: GraficaRangos.RefLine? {
        guard let avg = SeriesShape.latestMovingAverage(allValues, window: 7) else { return nil }
        let label = unit.isEmpty
            ? String(localized: "7-day level · \(fmt(avg))")
            : String(localized: "7-day level · \(fmt(avg)) \(unit)")
        return .init(v: avg, label: label)
    }

    /// Lanes for Rangos mode. SpO₂ / rhr / resp from `spec.info.bands`; HRV from personal ±σ normal range.
    private func graficaRangosBands() -> [GraficaRangos.Banda] {
        switch spec.descriptor.key {
        case "hrv":
            guard let nr = normalRange else { return [] }
            let lo = nr.lowerBound, hi = nr.upperBound
            // Half-open lanes that cover the closed personal band: [lo, hi] → below / within / above.
            return [
                .init(label: String(localized: "Unusual for you"), lo: hi.nextUp, hi: nil,
                      color: theme.warning, range: "≥ \(fmt(hi))"),
                .init(label: String(localized: "Normal for you"), lo: lo, hi: hi.nextUp,
                      color: metricHue, range: "\(fmt(lo))–\(fmt(hi))"),
                .init(label: String(localized: "Unusual for you"), lo: nil, hi: lo,
                      color: theme.warning, range: "< \(fmt(lo))")
            ]
        default:
            return infoBandsAsGrafica()
        }
    }

    /// Population / clinical bands from `spec.info.bands` (SpO₂, rhr, resp_rate). High → low for lanes.
    private func infoBandsAsGrafica() -> [GraficaRangos.Banda] {
        let banded = spec.info.bands.filter { $0.lower != nil || $0.upper != nil }
        guard !banded.isEmpty else { return [] }
        // TND-19: colour by the band's engine KEY, never its index — a positional ramp is how SpO₂'s
        // «low» lane turned green when the ladder shrank to two bands.
        return banded.reversed().map { b in
            GraficaRangos.Banda(
                label: plainLocalizedLabel(b.label),
                lo: b.lower, hi: b.upper,
                color: bandLaneColor(key: b.key),
                range: b.range)
        }
    }


    /// Known stat-slot labels → catalog keys (avoids fragile LocalizedStringKey → String reflection).
    private func tileLabel(_ cell: StatCell) -> String {
        switch cell.slot {
        case "promedio":     return String(localized: "Average")
        case "tendencia":    return String(localized: "Trend")
        case "rango":        return String(localized: "Range")
        case "consistencia": return String(localized: "Consistency")
        case "lownights":    return String(localized: "Nights < 95%")
        default:             return plainLocalizedLabel(cell.label)
        }
    }

    /// Stat strip as TileSurface tiles (Final). Display-only: the old tappable disclosures (Average /
    /// Trend / Consistency ⓘ panels) do not map 1:1 onto TileSurface, so they are not recreated here.
    @ViewBuilder private func tileStripFinal(_ window: MetricWindow) -> some View {
        let cells = statCells(window)
        if !cells.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                ForEach(cells) { cell in
                    TileSurface(
                        label: tileLabel(cell),
                        value: cell.value,
                        valueColor: cell.color == theme.ink ? nil : cell.color,
                        unit: cell.unitSuffix,
                        caption: cell.note.map { plainLocalizedLabel($0) },
                        theme: theme
                    )
                }
            }
        }
    }


    /// «Tu patrón» content: QueLaMueveHeader + findings + night signals (hrv / resp_rate).
    @ViewBuilder private var patronFinalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if visibleBlocks.contains(.whatMovesIt), !series.isEmpty {
                quemueveFinalView
            }
            if visibleBlocks.contains(.nightVitals),
               nightVitals.respiration != nil || nightVitals.restingHR != nil {
                nightSignalsView
            }
        }
    }

    private var quemueveFinalView: some View {
        VStack(alignment: .leading, spacing: 8) {
            QueLaMueveHeader("What moves it", chip: "trend, not cause", theme: theme)
            if whatMovesItFindings.isEmpty {
                Text("Not enough data yet: keep wearing your Apple Watch and check back in a few weeks.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(whatMovesItFindings) { f in
                    HStack(alignment: .top, spacing: 8) {
                        Text(Self.whatMovesArrow(f)).font(StrandFont.subhead).fontWeight(.semibold)
                            .foregroundStyle(whatMovesColor(f))
                        Text(f.phrase).font(StrandFont.caption)
                            .foregroundStyle(theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Spectral HRV body without its own overline (SeccionBloque owns the franja title).
    @ViewBuilder private func spectralFinalContent(_ s: SpectralHRV) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            spectralBandRow(title: "Respiratory", tag: "HF",
                            subtitle: "your calm signal, tied to your breathing",
                            band: s.hf, accent: theme.dataHrv)
            if let lf = s.lf {
                Divider().overlay(theme.hairline)
                spectralBandRow(title: "Slow", tag: "LF",
                                subtitle: "slow waves; a mix of signals",
                                band: lf, accent: theme.ink)
            }
            Divider().overlay(theme.hairline)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total variation").font(StrandFont.subhead).foregroundStyle(theme.ink)
                    Text("everything together, the “volume” of your HRV")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                spectralValue(s.total, accent: theme.ink)
            }
            if s.lf == nil {
                spectralNote("Last night's reading was short, so it only covers the respiratory part: not the slow waves.")
            } else if s.hf.label == nil {
                spectralNote("Still learning your normal range. Once there are enough nights, I'll tell you whether a value is high or low for you.")
            }
            spectralNote("Computed from last night's heartbeats (Lomb-Scargle). These are descriptive band powers to compare against yourself: not a diagnosis or a “stress balance.”")
        }
    }

    /// PieMetodo: method disclosure + origin seal (replaces free-floating methodDisclosure + originFooter).
    @ViewBuilder private var pieMetodoFinal: some View {
        PieMetodo(theme: theme) {
            if visibleBlocks.contains(.method), let method = spec.info.method {
                Metodo(title: String(localized: "How it's calculated"), theme: theme) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(method.prose)
                            .font(StrandFont.subhead)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let citation = method.citation {
                            Text(citation)
                                .font(StrandFont.caption)
                                .foregroundStyle(theme.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        } sello: {
            if !series.isEmpty {
                OriginStamp(origin: footerOrigin, when: String(localized: "today"), theme: theme)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Steps Final skeleton

    /// Full-bleed Final body for Steps: HeroInvertido → Your story → optional Your pattern → PieMetodo.
    @ViewBuilder private func stepsBodyFinal(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            stepsHeroFinal
            if infoOpen { queMedimosCardFinal }
            if !loaded {
                ChartWell(theme).loading(height: 160)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            } else if !enoughHistory {
                // Calibration gate for non-sparse metrics (steps is not sparseMeasured).
                calibrationBlock
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            } else {
                SeccionBloque(String(localized: "Your story"), theme: theme) {
                    stepsHistoriaFinalContent(window)
                }
                if stepsMovers != nil {
                    SeccionBloque(String(localized: "Your pattern"), theme: theme) {
                        stepsPatronFinalContent
                    }
                }
                pieMetodoFinal
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepsHeroFinal: some View {
        let valueText = stepsToday.map { fmt($0) } ?? "—"
        return HeroInvertido(
            glyph: .steps,
            title: "Steps",
            hue: metricHue,
            theme: theme,
            onInfo: { withAnimation(StrandMotion.interactive) { infoOpen.toggle() } },
            numeral: {
                if stepsToday == nil {
                    Text(verbatim: "—")
                        .font(InstrumentoType.groteskNumber(60, weight: .bold))
                        .tracking(-2)
                        .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                } else {
                    // No unit suffix on the hero numeral (steps show none).
                    HeroNumeral(valueText, suffix: nil, size: 60, theme: theme) {
                        if todayFromApple {
                            Text("Apple")
                                .font(InstrumentoType.grotesk(11, weight: .semibold))
                                .foregroundStyle(theme.paper)
                                .heroCapsule(theme: theme)
                        }
                    }
                }
            },
            verdict: {
                if let text = heroSecondaryText {
                    Text(text)
                        .font(InstrumentoType.grotesk(15, weight: .semibold))
                        .foregroundStyle(theme.paper)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        )
    }

    /// «Your story» for steps: period selector + GraficaRangos + 3-tile strip.
    @ViewBuilder private func stepsHistoriaFinalContent(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if visibleBlocks.contains(.periodSelector) {
                periodSelector(window)
            }
            if window.values.count > 1 {
                graficaRangosBlock(window)
                    .padding(.top, 6)
                    .id(range)
            } else if let only = window.values.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(fmt(only)) \(unit)")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(metricHue)
                    Text("Only one reading in this range: not enough to draw a line yet.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.inkTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
            } else {
                ChartWell(theme).empty(text: "No readings in this range.")
            }
            stepsTileStripFinal
                .padding(.top, 4)
        }
    }

    /// TODAY / 7-DAY AVG / STREAK as TileSurface tiles (Final). Display-only, not tappable.
    @ViewBuilder private var stepsTileStripFinal: some View {
        HStack(alignment: .top, spacing: 8) {
            TileSurface(label: String(localized: "TODAY"),
                        value: stepsToday.map(fmt) ?? "—",
                        valueColor: metricHue, theme: theme)
            TileSurface(label: String(localized: "7-DAY AVG"),
                        value: stepsAvg7.map(fmt) ?? "—",
                        theme: theme)
            TileSurface(label: String(localized: "STREAK"),
                        value: stepsStreak.map { "\($0)" } ?? "—",
                        theme: theme)
        }
    }

    /// Weekend/weekday pattern for steps, reheaded with QueLaMueveHeader.
    @ViewBuilder private var stepsPatronFinalContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            QueLaMueveHeader("What moves your steps", chip: "trend, not cause", theme: theme)
            if let m = stepsMovers {
                let pctStr = "\(m.pct)%"
                Text(m.weekendHigher
                     ? "Your weekends average about \(fmt(m.weekendAvg)) steps: roughly \(pctStr) more than your weekdays."
                     : "Your weekends average about \(fmt(m.weekendAvg)) steps: roughly \(pctStr) fewer than your weekdays.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - VO2max Final skeleton

    /// Full-bleed Final body for VO₂max: HeroInvertido → Your story → Where you fall → PieMetodo.
    @ViewBuilder private func vo2maxBodyFinal(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            vo2maxHeroFinal
            if infoOpen { queMedimosCardFinal }
            if !loaded {
                ChartWell(theme).loading(height: 160)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            } else if series.isEmpty {
                // Sparse-measured empty gate (vo2max is sparseMeasured).
                sparseEmptyState
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            } else {
                SeccionBloque(String(localized: "Your story"), theme: theme) {
                    vo2maxHistoriaFinalContent(window)
                }
                SeccionBloque(String(localized: "Where you fall"), theme: theme) {
                    vo2maxDondeCaesFinalContent
                }
                pieMetodoFinal
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var vo2maxHeroFinal: some View {
        let valueText = heroValue.map { fmt($0) } ?? "—"
        let suffix: String? = (heroValue != nil && !unit.isEmpty) ? unit : nil
        return HeroInvertido(
            glyph: .vo2max,
            title: "VO₂ Max",
            hue: metricHue,
            theme: theme,
            onInfo: { withAnimation(StrandMotion.interactive) { infoOpen.toggle() } },
            numeral: {
                if heroValue == nil {
                    Text(verbatim: "—")
                        .font(InstrumentoType.groteskNumber(60, weight: .bold))
                        .tracking(-2)
                        .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                } else {
                    HeroNumeral(valueText, suffix: suffix, size: 60, theme: theme) {
                        if todayFromApple {
                            Text("Apple")
                                .font(InstrumentoType.grotesk(11, weight: .semibold))
                                .foregroundStyle(theme.paper)
                                .heroCapsule(theme: theme)
                        }
                    }
                }
            },
            verdict: {
                if heroValue != nil {
                    Text(vo2maxComparison)
                        .font(InstrumentoType.grotesk(15, weight: .semibold))
                        .foregroundStyle(theme.paper)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        )
    }

    /// Sparse measured readings chart + expected/measured-ago as BarraAncla captions.
    @ViewBuilder private func vo2maxHistoriaFinalContent(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if visibleBlocks.contains(.periodSelector) {
                periodSelector(window)
            }
            // chartBlock already handles sparseMeasured (raw points, "Measured values" caption).
            // Do not route through graficaRangosBlock (no Media↔Rangos toggle for vo2max).
            chartBlock(window)
            // Resolve with String(localized:) + interpolation (same pattern as graficaRefLine etc.).
            // Do NOT use plainLocalizedLabel on interpolated LocalizedStringKey — Mirror only yields
            // the unresolved format template (e.g. "~%lld"), not the substituted value.
            if let exp = vo2maxExpected {
                BarraAncla(String(localized: "Expected for your age: ~\(Int(exp.rounded()))"),
                           color: metricHue, theme: theme)
            }
            if let day = series.last?.day, let date = Repository.parseDayKey(day) {
                let cal = Calendar.current
                if let d = cal.dateComponents([.day],
                                              from: cal.startOfDay(for: date),
                                              to: cal.startOfDay(for: Date())).day,
                   d >= 0 {
                    let ago: String = {
                        switch d {
                        case 0:  return String(localized: "Measured today")
                        case 1:  return String(localized: "Measured yesterday")
                        default: return String(localized: "Measured \(d) days ago")
                        }
                    }()
                    BarraAncla(ago, color: metricHue, theme: theme)
                }
            }
        }
    }

    /// Fitness category + equivalent age tiles, plus the "why it matters" body (no DetailBlock chrome).
    @ViewBuilder private var vo2maxDondeCaesFinalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let v = heroValue, let profile = spec.vo2maxProfile {
                let active = VO2maxReference.category(value: v, age: profile.age, sex: profile.sex)
                let eq = VO2maxReference.equivalentAge(value: v, sex: profile.sex)
                HStack(alignment: .top, spacing: 8) {
                    TileSurface(label: String(localized: "FITNESS CATEGORY"),
                                value: vo2maxCategoryWord(active),
                                valueColor: metricHue, theme: theme)
                    TileSurface(label: String(localized: "EQUIVALENT AGE"),
                                value: "~\(eq)",
                                valueColor: metricHue, theme: theme)
                }
            }
            // The «why it matters» copy, without a DetailBlock title wrapper
            // (SeccionBloque already frames the section as "Where you fall").
            VStack(alignment: .leading, spacing: 6) {
                Text("A higher VO₂max is associated with a lower risk of all-cause mortality. It's one of the best-evidenced predictors of long-term health.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Mandsager 2018 (JAMA) · Kodama 2009")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
    }

    // MARK: - Narrative Final skeleton — Heart Rate (intraday)

    /// Full-bleed Final body for Heart Rate: HeroInvertido → SeccionBloque("Your day") → zones → PieMetodo.
    /// No nights-calibration gate (each section owns its empty state). No period selector / GraficaRangos.
    @ViewBuilder private func narrativeIntradayFinal(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            narrativeHeroIntradayFinal
            if infoOpen { queMedimosCardFinal }
            if !loaded {
                ChartWell(theme).loading(height: 160)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            } else {
                SeccionBloque(String(localized: "Your day"), theme: theme) {
                    intradayCurveFinalContent
                }
                if let mins = cachedZoneMinutes, mins[1...].contains(where: { $0 > 0 }) {
                    SeccionBloque(String(localized: "Time in zones · today"), theme: theme) {
                        hrZonesBlockContent(mins)
                    }
                }
                pieMetodoIntradayFinal
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inverted hero for Heart Rate (intraday Final): today's average bpm + "in progress" capsule.
    private var narrativeHeroIntradayFinal: some View {
        let valueText = heroTodayValue.map { fmt($0) } ?? "—"
        return HeroInvertido(
            glyph: metricGlyph ?? .heartRate,
            title: narrativeHeroTitle,
            hue: metricHue,
            theme: theme,
            onInfo: { withAnimation(StrandMotion.interactive) { infoOpen.toggle() } },
            numeral: {
                if heroTodayValue == nil {
                    Text(verbatim: "—")
                        .font(InstrumentoType.groteskNumber(60, weight: .bold))
                        .tracking(-2)
                        .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                } else {
                    HeroNumeral(valueText, suffix: "bpm", size: 60, theme: theme) {
                        Text("in progress")
                            .font(InstrumentoType.grotesk(13, weight: .semibold))
                            .foregroundStyle(theme.paper)
                            .heroCapsule(theme: theme)
                    }
                }
            },
            verdict: {
                if loaded, let ctx = intradayHeroContextLine {
                    Text(ctx)
                        .font(InstrumentoType.grotesk(15, weight: .semibold))
                        .foregroundStyle(theme.paper)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        )
    }

    /// Today's minute curve + Min/Average/Max row, in a SeccionBloque wrapper.
    /// Split for type-check cost (FER-981): chart + stats row are separate ViewBuilders.
    @ViewBuilder private var intradayCurveFinalContent: some View {
        if intradayCurve.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                intradayCurveChart
                peakRestingCaption
                intradayCurveStatsRow
            }
        } else {
            ChartWell(theme).empty(text: "No readings yet today.")
        }
    }

    /// TrendChart for today's HR curve (extracted so its long argument list type-checks alone).
    @ViewBuilder private var intradayCurveChart: some View {
        let values: [Double] = intradayCurve.map(\.value)
        let range: ClosedRange<Double> = Self.hrRange(values, resting: restingHR)
        let refColor: Color = theme.inkTertiary.opacity(StrandOpacity.muted)
        let axisColor: Color = theme.inkTertiary
        let gridColor: Color = theme.hairline
        let chartHeight: CGFloat = 240
        let unitSuffix: String = unit
        TrendChart(
            points: intradayCurve,
            gradient: chartGradient,
            valueRange: range,
            showsArea: true,
            height: chartHeight,
            showsScrub: true,
            valueFormat: { (v: Double) -> String in "\(Int(v.rounded())) \(unitSuffix)" },
            dateFormat: { (d: Date) -> String in Self.hrClock.string(from: d) },
            axisLabelColor: axisColor,
            gridLineColor: gridColor,
            referenceLine: restingHR,
            referenceLineColor: refColor,
            markedPoint: peakPoint,
            tightTrailing: true,
            accessibilityLabel: "Today's heart rate, 5-minute averages"
        )
    }

    /// Min / Average / Max cells under the intraday curve (precomputed strings cut inference cost).
    @ViewBuilder private var intradayCurveStatsRow: some View {
        let values: [Double] = intradayCurve.map(\.value)
        let minRaw: Double = values.min() ?? 0.0
        let maxRaw: Double = values.max() ?? 0.0
        let sum: Double = values.reduce(0.0, +)
        let count: Int = max(values.count, 1)
        let avgRaw: Double = sum / Double(count)
        let minText: String = "\(Int(minRaw.rounded()))"
        let avgText: String = "\(Int(avgRaw.rounded()))"
        let maxText: String = "\(Int(maxRaw.rounded()))"
        HStack(spacing: 9) {
            hrStatCell("Min", minText)
            hrStatCell("Average", avgText)
            hrStatCell("Max", maxText)
        }
    }

    /// PieMetodo for Heart Rate: method disclosure + in-progress origin seal (hollow ring).
    @ViewBuilder private var pieMetodoIntradayFinal: some View {
        PieMetodo(theme: theme) {
            if visibleBlocks.contains(.method), let method = spec.info.method {
                Metodo(title: String(localized: "How it's calculated"), theme: theme) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(method.prose)
                            .font(StrandFont.subhead)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let citation = method.citation {
                            Text(citation)
                                .font(StrandFont.caption)
                                .foregroundStyle(theme.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        } sello: {
            if intradayCurve.count > 1 {
                OriginStamp(origin: footerOrigin, when: String(localized: "today, in progress"), inProgress: true, theme: theme)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Steps extras (handoff v2, FER-824): 3 tiles + «Qué mueve tus pasos»

    /// Today's step count (the hero datum; may still be accumulating).
    private var stepsToday: Double? { series.last?.value }
    /// The 7-day moving average (same figure the hero context reads).
    private var stepsAvg7: Double? { SeriesShape.latestMovingAverage(allValues, window: 7) }
    /// «Active streak»: consecutive most-recent COMPLETED days (excluding today, which may be partial)
    /// at or above your own 7-day average. There's no step goal in the app, so the streak is measured
    /// against your own baseline, never a target. nil until there's enough history.
    private var stepsStreak: Int? {
        guard let avg = stepsAvg7, avg > 0, series.count >= 2 else { return nil }
        var n = 0
        for row in series.dropLast().reversed() {   // drop today (incomplete)
            if row.value >= avg { n += 1 } else { break }
        }
        return n
    }

    /// A weekend-vs-weekday reading of your steps, computed from the dated series — an honest «what moves
    /// it» with no extra engine. nil unless both groups have ≥3 completed days. (FER-824)
    /// Split for type-check cost (FER-981): bucketing + summary are separate pure helpers.
    private var stepsMovers: (weekendAvg: Double, pct: Int, weekendHigher: Bool)? {
        let buckets: (weekend: [Double], weekday: [Double]) = stepsWeekendWeekdayBuckets
        let weekend: [Double] = buckets.weekend
        let weekday: [Double] = buckets.weekday
        guard weekend.count >= 3, weekday.count >= 3 else { return nil }
        return stepsMoversSummary(weekend: weekend, weekday: weekday)
    }

    /// Completed-day steps split into weekend vs weekday buckets (UTC gregorian). (FER-981)
    private var stepsWeekendWeekdayBuckets: (weekend: [Double], weekday: [Double]) {
        var wkend: [Double] = []
        var wkday: [Double] = []
        var cal: Calendar = Calendar(identifier: .gregorian)
        let utc: TimeZone? = TimeZone(identifier: "UTC")
        cal.timeZone = utc ?? cal.timeZone
        let completed: ArraySlice<(day: String, date: Date?, value: Double)> = parsedSeries.dropLast()
        for row in completed {
            guard let d: Date = row.date else { continue }
            if cal.isDateInWeekend(d) {
                wkend.append(row.value)
            } else {
                wkday.append(row.value)
            }
        }
        let result: (weekend: [Double], weekday: [Double]) = (weekend: wkend, weekday: wkday)
        return result
    }

    /// Weekend average + % gap vs weekdays from pre-bucketed values. nil if weekday mean is 0 or gap < 5%.
    private func stepsMoversSummary(weekend: [Double], weekday: [Double])
        -> (weekendAvg: Double, pct: Int, weekendHigher: Bool)? {
        let we: Double = weekend.reduce(0.0, +) / Double(weekend.count)
        let wd: Double = weekday.reduce(0.0, +) / Double(weekday.count)
        guard wd > 0.0 else { return nil }
        let gapRatio: Double = abs(we - wd) / wd * 100.0
        let pct: Int = Int(gapRatio.rounded())
        guard pct >= 5 else { return nil }            // below ~noise, don't overclaim a pattern
        let weekendHigher: Bool = we >= wd
        let result: (weekendAvg: Double, pct: Int, weekendHigher: Bool) =
            (weekendAvg: we, pct: pct, weekendHigher: weekendHigher)
        return result
    }

    // MARK: - Derived series


    /// Which source the statistics fold: the band (the anchor) whenever the user has ANY band night for this
    /// metric, otherwise Apple — so an Apple-only user's chart is never emptied. Only meaningful for a
    /// cross-source metric with Apple days present; elsewhere the fold keeps every night (identity). (FER-635)
    private var statKeepsApple: Bool {
        guard isCrossSource, !appleDays.isEmpty else { return false }
        let hasBandNight = series.contains { !appleDays.contains($0.day) }
        return !hasBandNight
    }

    /// Does this day belong to the source the statistics fold? Identity (keeps every day) for a single-source
    /// metric or a strap-only user; otherwise keeps only the chosen source's nights — the same band↔Apple
    /// split the cross-source clearing draws on (non-Apple days are the band's). (FER-635)
    private func keepsForStats(_ day: String) -> Bool {
        guard isCrossSource, !appleDays.isEmpty else { return true }
        return appleDays.contains(day) == statKeepsApple
    }

    /// The full display series folded to a single source (for cross-source vitals) — what every statistic
    /// (baseline ±σ, consistency CV, moving average) and the trend line read, so none of them crosses band
    /// and Apple. `series` itself stays full for TODAY's datum + the hero (today may be an Apple night). (FER-635)
    private var statSeries: [(day: String, value: Double)] {
        guard isCrossSource, !appleDays.isEmpty else { return series }   // identity (same as keepsForStats)
        let keepApple = statKeepsApple                                    // O(n) once
        return series.filter { appleDays.contains($0.day) == keepApple }  // O(n)
    }

    private var allValues: [Double] { statSeries.map(\.value) }

    /// The series with each `day` string parsed to a `Date` exactly ONCE per series (not per slice,
    /// not per render). The shared window math (`MetricWindowMath`) reads `date` straight from here instead
    /// of re-parsing. Built in `.task` alongside `series`. (FER-216 / FER-269)
    @State private var parsedSeries: [(day: String, date: Date?, value: Double)] = []

    /// The hero figure: the 7-day moving average over the FULL series (not just the window), so it
    /// reads as "your current 7-day level" regardless of the selected range. `.latest` falls back to
    /// the last reading for specs that prefer it.
    private var heroValue: Double? {
        switch spec.hero {
        case .movingAverage7:  return SeriesShape.latestMovingAverage(allValues, window: 7)
        case .latest:          return series.last?.value
        case .intradayAverage: return intradayAverage
        }
    }

    /// The mean of today's intraday curve (the Heart Rate hero). nil when there are no readings. (FER-253)
    private var intradayAverage: Double? {
        let v = intradayCurve.map(\.value)
        guard !v.isEmpty else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }

    /// Today's (most recent) single reading, shown as secondary context under the hero.
    private var todayValue: Double? { series.last?.value }

    /// "Enough history" gate: at least 2 points to draw a line / band / trend. Below that we show the
    /// calibration block instead of charts.
    private var enoughHistory: Bool { series.count >= 2 }

    // MARK: - Plain-language reading copy (FER-216)

    /// The blocks that carry a plain-language "what this means" sentence under their datum.
    enum BlockKind { case header, normalRange, consistency, trend, nightVitals }

    /// One es-MX sentence in plain language under a block's datum (`inkSecondary`), per metric. Returns
    /// `nil` when a block has no reading for this metric (e.g. RHR has no consistency block). The night-
    /// vitals sentence is shared by HRV and respiration on purpose (it describes the same companion
    /// signals), so it localizes from a single key. Source strings are English; the es values live in
    /// `Localizable.xcstrings`. (FER-216)
    private func readingCopy(for block: BlockKind) -> LocalizedStringKey? {
        let nightVitals: LocalizedStringKey =
            "Other signals from your body while you sleep. When they all rise together, something is taxing you (illness, alcohol, hard effort)."
        switch (spec.descriptor.key, block) {
        case ("hrv", .header):
            return "Higher HRV usually means better recovery. What matters is your trend, not any single day's number."
        case ("hrv", .normalRange):
            return "Where your HRV usually lands when you're well. Only worth noting when a day falls outside it."
        case ("hrv", .consistency):
            return "How even it stays from one week to the next. Steadier usually means better rest; very uneven can be fatigue."
        case ("hrv", .trend):
            return "Where your HRV is headed this month compared with last month."
        case ("hrv", .nightVitals):
            return nightVitals

        case ("rhr", .header):
            return "Your pulse when your body is calm. Lower usually means better fitness; a rise above your normal can be fatigue."
        case ("rhr", .normalRange):
            return "Where your resting HR usually lands when you're well. Take note when a day falls outside it."
        case ("rhr", .trend):
            return "Where your resting HR is headed this month compared with last month."

        case ("resp_rate", .header):
            return "One of your steadiest signals. A rise above your own normal can be an early sign that something is taxing you."
        case ("resp_rate", .normalRange):
            return "Where your nightly breathing usually lands. Take note when a day falls outside it."
        case ("resp_rate", .trend):
            return "Where your breathing is headed this month compared with last month."
        case ("resp_rate", .nightVitals):
            return nightVitals

        case ("spo2", .header):
            return "The oxygen in your blood, read at your wrist while you sleep. A healthy adult usually stays at 95% or above."

        case ("heart_rate", .header):
            return "Your heart rate across the day, in 5-minute averages. Your resting heart rate, the low while you sleep, is its own metric."

        case ("steps", .header):
            return "Your step count for today. Steady activity, even a short walk, supports your heart, your mood and your recovery."
        case ("steps", .trend):
            return "Where your steps are headed this month compared with last month."

        case ("vo2max", .header):
            return "Your Apple Watch's estimate of your aerobic fitness: how well your body uses oxygen. Higher usually means better cardio shape; it's an estimate, not a lab test."

        default:
            return nil
        }
    }

    // MARK: - Hero

    /// Heart Rate (intraday) → today's range + resting floor; steps → its 7-day daily average; the
    /// vitals → today's reading framed against the band.
    private var heroSecondaryText: LocalizedStringKey? {
        if isIntraday { return intradayHeroContext }
        if spec.descriptor.key == "steps" {
            guard let avg = SeriesShape.latestMovingAverage(allValues, window: 7) else { return nil }
            return "7-day average · \(fmt(avg)) steps"
        }
        guard let today = todayValue else { return nil }
        return heroContext(today)
    }

    /// The Heart Rate hero context: today's average is the hero, so frame it with the day's range and
    /// the night's resting floor. nil until there are at least two readings. (FER-253)
    private var intradayHeroContext: LocalizedStringKey? {
        let v = intradayCurve.map(\.value)
        guard v.count > 1, let lo = v.min(), let hi = v.max() else { return nil }
        let minS = "\(Int(lo.rounded()))", maxS = "\(Int(hi.rounded()))"
        if let rest = restingHR {
            return "Average today · min \(minS) · max \(maxS) bpm · resting \(Int(rest.rounded()))"
        }
        return "Average today · min \(minS) · max \(maxS) bpm"
    }

    /// "Today {v} {u} · within your normal variation" — frames the single reading against the band.
    private func heroContext(_ today: Double) -> LocalizedStringKey {
        let v = fmt(today)
        let u = unit
        if let band = normalRange, band.contains(today) {
            return "Today \(v) \(u) · within your normal variation"
        }
        return "Today \(v) \(u)"
    }

    // MARK: - Period selector

    private func periodSelector(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The selector owns its own full-width row (the night count lives in "Your normal range",
            // so no "N readings" label crowds it). (FER-211)
            SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme) { $0.label }
            if window.fellBack {
                // Only the auto-widen fallback survives, as a quiet caption in warning ink.
                Text("Showing the last \(window.rows.count) days")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.warning)
            }
        }
    }

    // MARK: - Chart (7-day moving average · area + date axes)

    @ViewBuilder private func chartBlock(_ window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Metrics with population ranges (Resting HR / Respiration / Steps) offer a «media móvil ⇄
            // rangos» toggle: your trend + personal band, or the classification ranges showing where you
            // fall. The period picker lives in `periodSelector` above. (Detalle de Vital)
            if hasRangesMode {
                // Compact «Media ⇄ Rangos» toggle, right-aligned (handoff v2, FER-804) — replaces the
                // full-width pill. The period picker lives in `periodSelector` above.
                HStack {
                    Spacer(minLength: 0)
                    CompactTrendToggle(mode: chartModeBridge, theme: theme)
                }
            }
            MetricTrendChart(
                range: $range,
                window: window,
                theme: theme,
                showsSelector: false,
                style: .init(
                    smoothing: chartPlotsRaw ? nil : 7,
                    gradient: chartGradient,
                    // No area fill when a band is drawn: the band + clean line read sharply; the area was
                    // a second teal wash that muddied the overlap. A shorter chart keeps it proportionate
                    // to the period selector above. «Ranges» mode is a touch taller to fit the band labels. (Detalle de Vital)
                    showsArea: effectiveChartBands(window).isEmpty,
                    height: rangesModeActive ? 184 : (isNarrative ? 156 : 200),
                    valueRange: { rangesModeActive ? (rangesValueRange($0) ?? narrativeChartValueRange($0)) : narrativeChartValueRange($0) },
                    valueFormat: { "\(fmt($0)) \(unit)" },
                    // SpO₂ shades its clinical healthy zone; the personal vitals shade your ±SD «normal range»;
                    // «Ranges» mode shades the active classification band, labels shown. (Detalle de Vital)
                    bands: { _ in effectiveChartBands(window) },
                    bandColor: { _ in spec.clinicalBands ? theme.verdict : metricHue },
                    yAxisValues: rangesModeActive ? rangesYTicks(window) : clinicalYAxisValues,
                    // «Media móvil» auto-ticks: ask for more so a wide range (e.g. steps 0–15k) reads at finer
                    // increments instead of just 5k/10k/15k. Ignored when ticks are explicit («Rangos» bands,
                    // SpO₂'s clinical thresholds), and the compact summary/strain cards keep the default 4. (Detalle)
                    yTickCount: 6,
                    alertThreshold: spec.clinicalBands ? spec.lowThreshold : nil,
                    alertColor: theme.critical,
                    // Mark today's point for the personal-band vitals and in «Ranges» mode (shows where today
                    // sits among the classifications); SpO₂ marks its low nights via the alert threshold. (Detalle de Vital)
                    marksLastPoint: (isNarrative && !spec.clinicalBands) || rangesModeActive,
                    // Labels off for the quiet personal/clinical band; ON in «Ranges» mode (athlete / normal / …).
                    bandLabelsHidden: !rangesModeActive,
                    accessibilityLabel: chartAccessibilityLabel
                )
            ) {
                if let only = window.values.first {
                    // A single point in the window: no line. Show the value plainly with a note.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(fmt(only)) \(unit)")
                            .font(StrandFont.bodyNumber)
                            .foregroundStyle(metricHue)
                        Text("Only one reading in this range: not enough to draw a line yet.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(theme.inkTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
                } else {
                    ChartWell(theme).empty(text: "No readings in this range.")
                }
            }
            if window.values.count > 1 {
                Text(chartCaption(window.range))
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                dynamicAverageCaption(window)
                if spec.currentDayIncomplete {
                    // The line includes today (still adding up), so its right edge can dip; the figures
                    // below read only completed days — so the two may not line up exactly. (FER-264)
                    Text("The line includes today, still in progress; the figures below use completed days only.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The fixed clinical bands drawn behind the line (FER-244 mechanism), built from the metric's own
    /// `MetricInfo.bands`. The HEALTHY band (the one whose lower bound is the clinical floor) is forced
    /// active so the green floor is ALWAYS shaded — not just when today's value lands in it. Empty for
    /// the non-clinical vitals, so their chart stays band-less. (FER-252)
    private var clinicalChartBands: [TrendBand] {
        guard spec.clinicalBands else { return [] }
        return spec.info.bands.map {
            TrendBand(label: $0.label, lower: $0.lower, upper: $0.upper,
                      isActive: $0.lower == spec.lowThreshold)
        }
    }

    /// The band drawn behind the chart line in the redesigned vitals: SpO₂'s clinical healthy zone, or the
    /// personal ±SD «normal range» for HRV / Resting HR / Respiration. The label is empty (the band is named
    /// in the caption and the inline «Hoy» bar, not on the plot). Empty for non-narrative metrics. (Detalle de Vital)
    private var narrativeChartBands: [TrendBand] {
        if spec.clinicalBands { return clinicalChartBands }
        guard isNarrative, let band = normalRange else { return [] }
        return [TrendBand(label: "", lower: band.lowerBound, upper: band.upperBound, isActive: true)]
    }

    // MARK: - Chart mode: media móvil ⇄ rangos (Resting HR / Respiration / Steps) (Detalle de Vital)

    /// Metrics that carry labeled population ranges the chart can toggle to. HRV has none (personal only);
    /// SpO₂ already shows its clinical band, so it doesn't toggle.
    private var hasRangesMode: Bool {
        !spec.clinicalBands && spec.descriptor.key != "hrv"
            && spec.info.bands.contains { $0.lower != nil || $0.upper != nil }
    }

    private var rangesModeActive: Bool { hasRangesMode && chartMode == .ranges }

    /// The bands drawn on the chart: the labeled classification ranges in «Ranges» mode (active one shaded),
    /// else the personal/clinical band. The active band is the SAME one the ranges table highlights —
    /// today's band (`isActive`), falling back to the latest completed reading — so the shaded band and the
    /// table agree. Without the fallback the chart shaded nothing whenever `isActive` wasn't set (e.g. a
    /// partial step day), even though the table still highlighted a band. (FER-471 · mirrors `rangesData`)
    private func effectiveChartBands(_ window: MetricWindow) -> [TrendBand] {
        guard rangesModeActive else { return narrativeChartBands }
        let banded = spec.info.bands.filter { $0.lower != nil || $0.upper != nil }
        guard !banded.isEmpty else { return [] }
        let tbands = banded.map { TrendBand(label: $0.label, lower: $0.lower, upper: $0.upper) }
        let values = trendStatRows(window).map(\.value)
        let activeIndex = banded.firstIndex(where: { $0.isActive })
            ?? TrendBands.activeBand(values: values, bands: tbands)?.index
        return banded.enumerated().map { i, b in
            TrendBand(label: b.label, lower: b.lower, upper: b.upper, isActive: i == activeIndex)
        }
    }

    /// In «Ranges» mode, span every classification threshold so all bands read, AND include the plotted
    /// line's own min/max — the line can climb past the top band (e.g. steps well over «Muy activo»), and a
    /// band-only range let the peak shoot off the top. The TOP margin is wider than the bottom: the chart's
    /// Y-scale has no top inset, so without headroom the peak hugged the plot's top edge and — with the
    /// «Media móvil ⇄ Rangos» selector just above — read as overlapping it. (Detalle de Vital · FER-471)
    private func rangesValueRange(_ smoothed: [Double]) -> ClosedRange<Double>? {
        let bounds = spec.info.bands.flatMap { [$0.lower, $0.upper].compactMap { $0 } }
        guard let tLo = bounds.min(), let tHi = bounds.max(), tHi > tLo else { return nil }
        let hi = Swift.max(tHi, smoothed.max() ?? tHi)
        let lo = Swift.min(tLo, smoothed.min() ?? tLo)
        let span = hi - lo
        // Modest top headroom: the range already includes the data peak, so a small margin clears the
        // «Media móvil ⇄ Rangos» selector above without leaving a big empty band over the line. (Detalle)
        return (lo - span * 0.1)...(hi + span * 0.15)
    }

    /// «Ranges» Y ticks: the band thresholds, plus round ticks above the top band when the line climbs past
    /// it (e.g. steps over «Muy activo») so the upper chart still has labels. Bounded to the chart's actual
    /// domain top — Charts EXPANDS the y-scale to fit any explicit tick, so a tick above the domain would
    /// stretch the axis into a big empty band over the line. Extend only up to where the line reaches. (Detalle)
    private func rangesYTicks(_ window: MetricWindow) -> [Double]? {
        let thresholds = Set(spec.info.bands.flatMap { [$0.lower, $0.upper].compactMap { $0 } }).sorted()
        guard let maxT = thresholds.last else { return nil }
        let plotted = chartPlotsRaw ? window.values : SeriesShape.movingAverage(window.values, window: 7)
        guard let top = rangesValueRange(plotted)?.upperBound, top > maxT else { return thresholds }
        let step = Swift.max((maxT / 4).rounded(), 1)
        var ticks = thresholds
        var v = maxT + step
        while v < top { ticks.append(v); v += step }
        return ticks
    }

    /// Bridges the compact toggle's `TrendMode` to the existing `chartMode` state (FER-804).
    private var chartModeBridge: Binding<TrendMode> {
        Binding(
            get: { chartMode == .ranges ? .rangos : .media },
            set: { chartMode = ($0 == .rangos) ? .ranges : .movingAverage }
        )
    }

    /// Y-axis ticks at the band thresholds (e.g. SpO₂ 90/95/100) for the clinical chart; `nil` otherwise
    /// so the vitals keep automatic ticks. (FER-252)
    private var clinicalYAxisValues: [Double]? {
        guard spec.clinicalBands, let domain = spec.chartDomain else { return nil }
        let thresholds = Set(spec.info.bands.flatMap { [$0.lower, $0.upper].compactMap { $0 } })
        return ([domain.lowerBound, domain.upperBound] + thresholds).sorted()
    }

    /// Auto-fit the chart's value axis to the smoothed line, with a small margin so it doesn't clip.
    private func chartRange(_ smoothed: [Double]) -> ClosedRange<Double> {
        let lo = smoothed.min() ?? 0
        let hi = smoothed.max() ?? 1
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.15
        return (lo - pad)...(hi + pad)
    }

    /// The chart's Y domain. SpO₂ keeps its fixed clinical domain. The redesigned personal-band vitals
    /// (HRV / Resting HR / Respiration) OPEN the axis around the «normal range» band — domain = band ±
    /// ~0.85× its width — so the band reads as a central stripe with air above and below, not a full-bleed
    /// box that fills the whole plot. Everything else auto-fits to the line. (Detalle de Vital — fix «caja»)
    private func narrativeChartValueRange(_ smoothed: [Double]) -> ClosedRange<Double> {
        if let domain = spec.chartDomain { return domain }
        if isNarrative, !spec.clinicalBands, let band = normalRange {
            let span = band.upperBound - band.lowerBound
            let pad = Swift.max(span * 0.6, 1)
            let lo = Swift.min(band.lowerBound - pad, smoothed.min() ?? band.lowerBound)
            let hi = Swift.max(band.upperBound + pad, smoothed.max() ?? band.upperBound)
            return lo...hi
        }
        return chartRange(smoothed)
    }


    /// Whether THIS render plots raw daily points instead of the 7-day MA. Adds «Ranges» mode to
    /// `plotsRawValues`: that mode classifies each DAY against the population bands (the shaded band +
    /// the «X of N days in …» count both read the raw value), so the line must be raw too — otherwise the
    /// smoothed endpoint lands in a different band than the one highlighted from today's reading. Steps are
    /// excluded (`currentDayIncomplete`): their «today» is a running partial total and their raw range can
    /// overflow the band-pinned Y axis, so they keep the smoothed line. (Detalle de Vital — punto vs. rango)
    private var chartPlotsRaw: Bool {
        plotsRawValues || (rangesModeActive && !spec.currentDayIncomplete)
    }

    private var chartAccessibilityLabel: LocalizedStringKey {
        if spec.sparseMeasured { return "Measured readings" }
        if chartPlotsRaw && !spec.clinicalBands { return "Daily readings" }
        return spec.clinicalBands ? "Nightly readings" : "7-day moving average"
    }

    /// The caption under the chart. It no longer appends "· last {range}" — the period selector right above
    /// already says the range, and the interpolated form mis-agreed in Spanish ("últimos mes"). The smoothing
    /// is ALWAYS a 7-day moving average regardless of the selected range, so the caption says so plainly.
    private func chartCaption(_ effectiveRange: ExploreRange) -> LocalizedStringKey {
        if rangesModeActive { return "Where you fall against the typical ranges." }
        if spec.sparseMeasured { return "Measured values." }
        if spec.clinicalBands { return "Nightly values · the shaded band is the healthy range." }
        // Name the shaded band so the horizontal lines on the chart read as «your normal range». (Detalle de Vital)
        if isNarrative, normalRange != nil { return "7-day moving average · the band is your normal range." }
        return "7-day moving average."
    }

    /// «Average · {window} · {value} · {Δ%} vs previous» — the period average recomputed for the SELECTED
    /// window, with its change vs the immediately-preceding equal window coloured by the metric's good
    /// direction (HRV↑, resting HR↓, respiration↓, SpO₂↑, steps↑). Reuses the SAME `ComparisonEngine`
    /// figures + polarity as the trend block, so the caption and the stat strip never disagree. Hidden in
    /// «Ranges» mode and for sparsely-measured metrics (VO₂max); when there's no previous window of equal
    /// length (e.g. ALL, or too little history) it shows the average alone, never an invented Δ. (FER-563)
    @ViewBuilder private func dynamicAverageCaption(_ window: MetricWindow) -> some View {
        let rows = trendStatRows(window)
        if !rangesModeActive, !spec.sparseMeasured, rows.count > 1 {
            let mean = ComparisonEngine.stat(rows.map(\.value)).mean
            let valueStr = unit.isEmpty ? fmt(mean) : "\(fmt(mean)) \(unit)"
            let head = Text("Average") + Text(verbatim: " · \(window.range.name) · \(valueStr)")
            Group {
                if let pct = window.range.periodComparison(of: trendComparisonSeries)?.pctChange {
                    let rounded = Int(abs(pct).rounded())
                    let arrow = rounded == 0 ? "" : (pct >= 0 ? "▲ " : "▼ ")
                    head
                        + Text(verbatim: " · \(arrow)\(rounded)% ").foregroundColor(trendDeltaColor(pct))
                        + Text("vs previous")
                } else {
                    head
                }
            }
            .font(StrandFont.footnote)
            .foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Normal range (rolling mean ± SD)

    /// The personal rolling baseline (trailing mean/SD), or nil when no config / no valid nights.
    private var baselineState: BaselineState? {
        guard let cfg = spec.baselineCfg else { return nil }
        let state = Baselines.rollingMeanSD(allValues.map { Optional($0) }, cfg: cfg, window: 30)
        return state.nValid >= 1 ? state : nil
    }

    /// The ±1σ "normal range" used to frame today's reading (nil when no baseline yet).
    /// log-aware (multiplicative band in ms for HRV) via `Baselines.normalRange`.
    private var normalRange: ClosedRange<Double>? {
        guard let s = baselineState else { return nil }
        return Baselines.normalRange(s)
    }

    // MARK: - Consistency (coefficient of variation)

    // MARK: - Fixed clinical bands (population range table) — SpO₂ (FER-252)

    // MARK: - Intraday HR curve (FER-253)

    /// The peak of the day (max bpm), marked on the curve.
    private var peakPoint: TrendPoint? { intradayCurve.max { $0.value < $1.value } }

    /// "Peak {v} bpm · {time}" plus the resting reference, in the chart's two legend hues. Built once.
    @ViewBuilder private var peakRestingCaption: some View {
        if let peak = peakPoint {
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Circle().fill(metricHue).frame(width: 7, height: 7)
                    Text("Peak \(Int(peak.value.rounded())) bpm · \(Self.hrClock.string(from: peak.date))")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                }
                if let rest = restingHR {
                    Text("Resting \(Int(rest.rounded()))")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
            }
        }
    }

    /// Padded HR axis so the line never sits flush against an edge; widens to include the resting
    /// reference if it falls below the curve's floor. (mirrors MetricInfoSheet.hrRange)
    private static func hrRange(_ v: [Double], resting: Double?) -> ClosedRange<Double> {
        var lo = v.min() ?? 40, hi = v.max() ?? 120
        if let r = resting { lo = Swift.min(lo, r) }
        if hi <= lo { return (lo - 5)...(hi + 5) }
        let span = hi - lo
        return (lo - span * 0.12)...(hi + span * 0.12)
    }

    private static let hrClock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h a"; return f
    }()

    // MARK: - Time in zones · today (FER-253)

    /// Minutes in [rest, Z1, Z2, Z3, Z4, Z5] from a curve snapshot (index 0 = below Zone 1). nil when
    /// there's no max HR or too little curve to bucket. Pure — off-main-safe (FER-976, same seam as
    /// `SleepDetailScreen.buildSleepHeat`). `nonisolated` opts OUT of this View's inferred MainActor
    /// isolation (FER-978) so it's callable from inside `Task.detached`. Inlines the old `zoneSet` +
    /// `bucketMinutes` (both were single-use, only this function read them).
    private nonisolated static func computeZoneMinutesDetached(hrMax: Double,
                                                                intradayCurve: [TrendPoint]) -> [Double]? {
        guard hrMax > 0, intradayCurve.count > 1 else { return nil }
        let zs = HRZones.zones(maxHR: hrMax, source: "tanaka")
        let ts = intradayCurve.map { $0.date.timeIntervalSince1970 }.sorted()
        var per = 5.0
        if ts.count >= 2 {
            var gaps: [Double] = []
            for i in 1..<ts.count { let g = ts[i] - ts[i - 1]; if g > 0 { gaps.append(g) } }
            if !gaps.isEmpty {
                gaps.sort()
                per = Swift.max(gaps[gaps.count / 2] / 60.0, 0.5)
            }
        }
        var mins = [Double](repeating: 0, count: 6)
        for p in intradayCurve { mins[zs.zoneNumber(forBPM: p.value)] += per }
        return mins
    }

    /// Inner content of the HR zones block, framed by `narrativeIntradayFinal`'s SeccionBloque
    /// wrapper (which supplies its own title/divider).
    @ViewBuilder private func hrZonesBlockContent(_ mins: [Double]) -> some View {
        let elevated = Int((mins[3] + mins[4] + mins[5]).rounded())
        let total = Swift.max(mins.reduce(0, +), 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(elevated)").instrumentoHero(30).foregroundStyle(metricHue)
                Text("min elevated (zone 3+)")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { i in
                        Rectangle()
                            .fill(zoneFill(i))
                            .frame(width: geo.size.width * CGFloat(mins[i] / total))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 7) {
                ForEach((1...5).filter { mins[$0] >= 1 }, id: \.self) { i in
                    HStack(spacing: 8) {
                        Circle().fill(zoneFill(i)).frame(width: 8, height: 8)
                        Text(zoneLabel(i)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        Spacer()
                        Text("\(Int(mins[i].rounded())) min")
                            .font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
                    }
                }
            }
            Text("Zones as a percentage of your max heart rate (\(Int(hrMax.rounded())) bpm, Tanaka). The rest of the day you were resting or very light.")
                .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Trend (month over month)

    /// True when the latest series point is TODAY and this metric's day is still accumulating (steps) —
    /// then the trend figures exclude it so they read over completed days only. (FER-264)
    private var dropsIncompleteToday: Bool {
        spec.currentDayIncomplete && todayKey != nil && series.last?.day == todayKey
    }

    /// The window's rows used for the range/average, with the in-progress current day removed for a
    /// cumulative metric. (FER-264)
    private func trendStatRows(_ window: MetricWindow) -> [(day: String, value: Double)] {
        dropsIncompleteToday ? window.rows.filter { $0.day != todayKey } : window.rows
    }

    /// The full series the period comparison splits, with the in-progress current day removed for a
    /// cumulative metric (so "this period" and "the previous period" are both completed-day means). (FER-264)
    private var trendComparisonSeries: [(day: String, value: Double)] {
        // Single-source fold so the period Δ% compares band-to-band (or Apple-to-Apple), never mixed. (FER-635)
        dropsIncompleteToday ? statSeries.filter { $0.day != todayKey } : statSeries
    }


    // MARK: - Night vitals

    private var nightVitalsLine: LocalizedStringKey {
        let resp = nightVitals.respiration.map { String(format: "%.1f", $0) } ?? "—"
        let rhr = nightVitals.restingHR.map { "\(Int($0.rounded()))" } ?? "—"
        return "Respiration \(resp) · Resting HR \(rhr)"
    }

    // MARK: - What moves it (FER-209)

    // MARK: - Method disclosure (ported from MetricInfoSheet)

    // MARK: - VO₂max (Apple Health, measured · FER-257)

    /// The population median VO₂max for the user's age & sex (the reference the hero reads against).
    private var vo2maxExpected: Double? {
        spec.vo2maxProfile.map { VO2maxReference.expected(age: $0.age, sex: $0.sex) }
    }

    /// Where the latest measured value sits versus the age/sex median — the hero's headline reading. A
    /// small ±1.5 deadband keeps a value right at the median reading "in line", not flip-flopping.
    private var vo2maxComparison: LocalizedStringKey {
        guard let v = heroValue, let exp = vo2maxExpected else { return " " }
        if v > exp + 1.5 { return "Above what's expected for your age." }
        if v < exp - 1.5 { return "Below what's expected for your age." }
        return "In line with what's expected for your age."
    }


    /// Zero-reading state for VO₂max: an explanatory card (no chart), plus a quiet "Connect Apple Health"
    /// line when nothing's connected. (FER-257)
    private var sparseEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No VO₂max yet")
                .font(InstrumentoType.groteskHeadline(17))
                .foregroundStyle(theme.ink)
            Text("Your Apple Watch estimates VO₂max during outdoor walks and runs with a good GPS signal.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if appleConnectHint {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    StrandIcon.heart.image.font(StrandFont.glyph(.chevron)).foregroundStyle(theme.dataHeart)
                    Text("Connect Apple Health to see your VO₂max.")
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
    }

    // MARK: - Calibration (not enough history)

    private var calibrationBlock: some View {
        let nights = series.count
        // Steps are an Apple-sourced daily count, not a calibrated night vital: its empty state speaks in
        // "days" and omits the "normal range" the vitals promise (steps carries none). (FER-254)
        let isSteps = spec.descriptor.key == "steps"
        return VStack(alignment: .leading, spacing: 12) {
            Text("Not enough history yet")
                .font(InstrumentoType.groteskHeadline(17))
                .foregroundStyle(theme.ink)
            HStack(alignment: .firstTextBaseline) {
                Text(isSteps ? "Gathering" : "Calibrating").groteskOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text(isSteps ? "\(nights) / 7 days" : "\(nights) / 7 nights")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline).frame(height: 6)
                    Capsule().fill(metricHue)
                        .frame(width: max(6, geo.size.width * CGFloat(min(nights, 7)) / 7), height: 6)
                }
            }
            .frame(height: 6)
            Text(isSteps
                 ? "Connect Apple Salud and walk a few days to see your daily average and your trend."
                 : "We need a few more nights to show your 7-day average, your normal range and the trend.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
    }

    // MARK: - Detalle de Vital · narrative redesign (Hoy → Tu historia → (Tu patrón) → Método)
    //
    // The five vitals lead with TODAY's reading, draw the personal/clinical range inline AND behind the
    // chart line, and fold the old per-block ⓘ accordions into a tappable stat strip + per-datum disclosures
    // that reuse the SAME `explanation` copy. Steps / VO₂max have their own Final skeletons
    // (`stepsBodyFinal` / `vo2maxBodyFinal`).

    // MARK: Hoy (hero)

    /// The serif in-screen title — the metric's SHORT name (matching the Cuerpo tile labels), not the
    /// "{metric} · today" overline it replaces. (FER-581)
    private var narrativeHeroTitle: LocalizedStringKey {
        switch spec.descriptor.key {
        case "hrv":        return "HRV"
        case "rhr":        return "Resting HR"
        case "resp_rate":  return "Respiratory"
        case "spo2":       return "Blood Oxygen"
        case "heart_rate": return "Heart Rate"
        default:           return "Today"
        }
    }

    /// The hero numeral: today's reading for the vitals, today's average bpm for Heart Rate.
    private var heroTodayValue: Double? { isIntraday ? intradayAverage : todayValue }

    /// Today's plain-language verdict word: in-range «Normal for you» (green) vs «Unusual for you» (amber)
    /// for the personal vitals; the clinical Healthy / Low for SpO₂. nil until there's a reading.
    private var heroVerdict: (word: LocalizedStringKey, color: Color)? {
        guard let today = todayValue else { return nil }
        if spec.descriptor.key == "spo2" {
            let v = Self.spo2HeroVerdict(today)
            return (LocalizedStringKey(v.word), v.healthy ? theme.verdict : theme.warning)
        }
        guard let band = normalRange else { return nil }
        return band.contains(today) ? ("Normal for you", theme.verdict) : ("Unusual for you", theme.warning)
    }

    /// SpO₂'s hero word rides the engine's TWO-band ladder (`MetricLevels.bloodOxygen`: low < 95 /
    /// normal ≥ 95) — the hand-built three-way switch (≥ 95 / ≥ 90 / < 90) was the «Borderline
    /// fantasma» `DisplayBandsTests.testBloodOxygenIsTwoBandsNotThree` declared dead: a 94% read
    /// «Borderline» in the hero and «low» everywhere else. Static so the guard can pin that only two
    /// readings exist (patrón `StrainDetailScreen.fraseCarril`, TND-19). The word is the catalog key
    /// («Healthy» / «Low», es «Sano» / «Bajo»); the caller maps healthy → verdict, not → warning.
    static func spo2HeroVerdict(_ value: Double) -> (word: String, healthy: Bool) {
        // TND20-F1: la palabra es LA MISMA de la escalera (`MetricLevels.name` → «Normal»/«Low»)
        // — «Healthy» era un segundo vocabulario a un tap del carril que dice «Normal».
        let level = MetricLevels.levels(for: .bloodOxygen)[MetricLevels.index(of: value, for: .bloodOxygen)]
        return (MetricLevels.name(for: level.key), level.key == "normal")
    }

    /// "7-day level · 58 ms" — the trailing-average context that used to be the hero. nil until calibrated.
    private var sevenDayLevelText: LocalizedStringKey? {
        guard let avg = SeriesShape.latestMovingAverage(allValues, window: 7) else { return nil }
        return unit.isEmpty ? "7-day level · \(fmt(avg))" : "7-day level · \(fmt(avg)) \(unit)"
    }

    /// "min 51 · max 142 · resting 52 bpm" under the Heart Rate hero (the day's spread). nil < 2 readings.
    private var intradayHeroContextLine: LocalizedStringKey? {
        let v = intradayCurve.map(\.value)
        guard v.count > 1, let lo = v.min(), let hi = v.max() else { return nil }
        let minS = "\(Int(lo.rounded()))", maxS = "\(Int(hi.rounded()))"
        if let rest = restingHR {
            let restS = "\(Int(rest.rounded()))"
            return "min \(minS) · max \(maxS) · resting \(restS) bpm"
        }
        return "min \(minS) · max \(maxS) bpm"
    }

    // MARK: Inline range band (tappable, in the Hoy section)

    /// The geometry + copy of the inline «today vs your range» bar. Fractions are along the bar's axis (0…1).
    private struct InlineBand {
        var bandLoFrac: CGFloat
        var bandHiFrac: CGFloat
        var markFrac: CGFloat
        var markLabel: String      // today's value, rotulated above the thumb
        var markOutside: Bool      // today is beyond the band → tint the value `warning`
        var loLabel: String
        var hiLabel: String
        var loLabelFrac: CGFloat   // x of the lo label: the band's left edge (personal) or the axis end (SpO₂)
        var hiLabelFrac: CGFloat   // x of the hi label: the band's right edge (personal) or the axis end (SpO₂)
        var centerLabel: LocalizedStringKey
        var fillColor: Color
        var disclosureTitle: LocalizedStringKey
    }


    /// The band to draw inline under the hero: SpO₂'s fixed clinical zone (≥95% across the 88…100 domain),
    /// or the personal ±SD «normal range» for HRV / Resting HR / Respiration. nil when there's no reading
    /// or no baseline yet (then the bar is omitted, like the old normal-range block). (Detalle de Vital)
    private var inlineBandData: InlineBand? {
        guard let today = todayValue else { return nil }
        if spec.descriptor.key == "spo2" {
            guard let domain = spec.chartDomain, let floor = spec.lowThreshold else { return nil }
            let lo = domain.lowerBound, hi = domain.upperBound, span = hi - lo
            guard span > 0 else { return nil }
            return InlineBand(
                bandLoFrac: CGFloat((floor - lo) / span), bandHiFrac: 1,
                markFrac: clampFrac((today - lo) / span),
                markLabel: fmt(today), markOutside: today < floor,
                loLabel: fmt(lo), hiLabel: fmt(hi),
                loLabelFrac: 0, hiLabelFrac: 1,   // SpO₂ labels are the domain ends (the bar's edges)
                centerLabel: "healthy zone ≥ 95%",
                fillColor: theme.verdict.opacity(0.26), // token-exempt: relleno de banda (área de dato, fuera de escala)
                disclosureTitle: "Healthy zone")
        }
        guard let s = baselineState, s.nValid >= 1 else { return nil }
        let band = Baselines.normalRange(s)
        let lo = band.lowerBound, hi = band.upperBound, spanB = hi - lo
        guard spanB > 0 else { return nil }
        let axisLo = lo - spanB * 0.45, axisHi = hi + spanB * 0.45, span = axisHi - axisLo
        let bandLoFrac = CGFloat((lo - axisLo) / span), bandHiFrac = CGFloat((hi - axisLo) / span)
        return InlineBand(
            bandLoFrac: bandLoFrac, bandHiFrac: bandHiFrac,
            markFrac: clampFrac((today - axisLo) / span),
            markLabel: fmt(today), markOutside: today < lo || today > hi,
            loLabel: fmt(lo), hiLabel: fmt(hi),
            loLabelFrac: bandLoFrac, hiLabelFrac: bandHiFrac,   // labels sit under the band's actual edges
            centerLabel: "your normal range · \(s.nValid) nights",
            fillColor: metricHue.opacity(0.26), // token-exempt: relleno de banda (área de dato, fuera de escala)
            disclosureTitle: "Your normal range")
    }

    /// The handoff's position slider: a 64%-wide normal-range track centered on the rail, with a circular
    /// thumb marking where today sits inside your normal range, and lo · «tu normal» · hi labels beneath.
    private func positionSlider(_ b: InlineBand) -> some View {
        // Today's position WITHIN the normal band, clamped to [0,1] → mapped onto the 18%…82% track.
        let span = max(b.bandHiFrac - b.bandLoFrac, 0.0001)
        let t = min(max((b.markFrac - b.bandLoFrac) / span, 0), 1)
        return GeometryReader { geo in
            let w = geo.size.width
            let clampX: (CGFloat) -> CGFloat = { min(max($0, 14), w - 14) }
            ZStack(alignment: .topLeading) {
                // Normal-range track (64% wide, centered) + the position thumb.
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.trackWarm)
                        .frame(width: w * 0.64, height: 10)
                        .offset(x: w * 0.18)
                    Circle().fill(b.fillColor)
                        .frame(width: 12, height: 12)
                        .offset(x: w * (0.18 + t * 0.64) - 6)
                }
                .frame(width: w, height: 12)
                .position(x: w / 2, y: 8)
                // lo · «tu normal» · hi under the track's edges/center.
                Text(b.loLabel).font(StrandFont.footnote).monospacedDigit().foregroundStyle(theme.inkTertiary)
                    .fixedSize().position(x: clampX(w * 0.18), y: 30)
                Text(b.centerLabel).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize().position(x: w * 0.5, y: 30)
                Text(b.hiLabel).font(StrandFont.footnote).monospacedDigit().foregroundStyle(theme.inkTertiary)
                    .fixedSize().position(x: clampX(w * 0.82), y: 30)
            }
        }
        .frame(height: 40)
    }

    // MARK: Narrative body

    /// Whether the «Tu patrón» section has anything to show (HRV / Resting HR have «what moves it»; HRV /
    /// Respiration have last night's companion signals). SpO₂ and Heart Rate have no pattern section.
    private var hasPatron: Bool {
        let qm = visibleBlocks.contains(.whatMovesIt) && !series.isEmpty
        let nv = visibleBlocks.contains(.nightVitals)
            && (nightVitals.respiration != nil || nightVitals.restingHR != nil)
        return qm || nv
    }

    // MARK: Tu historia (selector + chart + stat strip)

    // MARK: - Ranges-mode fixed table (FER-469)

    /// One datum of the stat strip (display-only, per `tileStripFinal` below). `value` is the formatted
    /// figure. The consistency cell carries `slot == "consistencia"`.
    private struct StatCell: Identifiable {
        var id: String { slot }
        let slot: String
        let label: LocalizedStringKey
        let value: String
        var unitSuffix: String? = nil
        var note: LocalizedStringKey? = nil
        let color: Color
    }

    private func statCells(_ window: MetricWindow) -> [StatCell] {
        switch spec.descriptor.key {
        case "spo2":
            return spo2StatCells(window)
        case "hrv":
            var cells = [averageCell(window)]
            if let t = trendCell(window) { cells.append(t) }
            if let c = consistencyCell() { cells.append(c) }
            return cells
        case "rhr":
            var cells = [averageCell(window)]
            if let t = trendCell(window) { cells.append(t) }
            cells.append(rangeCell(window))
            return cells
        case "resp_rate":
            return [averageCell(window), rangeCell(window)]
        default:
            return []
        }
    }

    private func averageCell(_ window: MetricWindow) -> StatCell {
        let s = ComparisonEngine.stat(trendStatRows(window).map(\.value))
        return StatCell(slot: "promedio", label: "Average", value: fmt(s.mean),
                        unitSuffix: unit.isEmpty ? nil : unit, color: theme.ink)
    }

    private func rangeCell(_ window: MetricWindow) -> StatCell {
        let s = ComparisonEngine.stat(trendStatRows(window).map(\.value))
        return StatCell(slot: "rango", label: "Range", value: "\(fmt(s.min))–\(fmt(s.max))",
                        unitSuffix: unit.isEmpty ? nil : unit, color: theme.ink)
    }

    private func trendCell(_ window: MetricWindow) -> StatCell? {
        guard let pct = window.range.periodComparison(of: trendComparisonSeries)?.pctChange else { return nil }
        let rounded = Int(abs(pct).rounded())
        let arrow = rounded == 0 ? "" : (pct >= 0 ? "▲ " : "▼ ")
        return StatCell(slot: "tendencia", label: "Trend", value: "\(arrow)\(rounded)%",
                        color: trendDeltaColor(pct))
    }

    /// Colour for a period-over-period % change, by this metric's polarity: the good direction → verdict,
    /// against → warning, flat (rounds to 0%) or a neutral metric → quiet ink. Shared by the trend stat
    /// cell and the dynamic-average caption so the two never disagree. (FER-563)
    private func trendDeltaColor(_ pct: Double) -> Color {
        if Int(abs(pct).rounded()) == 0 { return theme.inkSecondary }
        switch trendPolarity {
        case .higherIsBetter: return pct > 0 ? theme.verdict : theme.warning
        case .lowerIsBetter:  return pct < 0 ? theme.verdict : theme.warning
        case .neutral:        return theme.inkSecondary
        }
    }

    private func consistencyCell() -> StatCell? {
        guard let cv = SeriesShape.coefficientOfVariation(allValues, window: 7) else { return nil }
        let steady = Int((cv * 100).rounded()) <= 10
        return StatCell(slot: "consistencia", label: "Consistency",
                        value: String(localized: steady ? "Steady" : "Variable"),
                        color: theme.ink)
    }

    private func spo2StatCells(_ window: MetricWindow) -> [StatCell] {
        let s = ComparisonEngine.stat(window.values)
        let avg = StatCell(slot: "promedio", label: "Average", value: fmt(s.mean),
                           unitSuffix: unit, color: theme.ink)
        guard let threshold = spec.lowThreshold else { return [avg] }
        let recent = MetricWindowMath.slice(parsedSeries, for: .month)
        let low = recent.reduce(0) { $0 + ($1.value < threshold ? 1 : 0) }
        let nights = StatCell(slot: "lownights", label: "Nights < 95%", value: "\(low)",
                              note: "of \(recent.count)",
                              color: low > 0 ? theme.warning : theme.verdict)
        return [avg, nights]
    }

    // MARK: Disclosure panels (reuse the same explanation copy the old ⓘ accordions showed)

    // MARK: Tu patrón (what moves it + last night's companion signals)


    private var nightSignalsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Other signals from last night").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Spacer(minLength: 8)
                Text(narrativeNightLine).font(StrandFont.captionNumber).foregroundStyle(theme.ink)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .instrumentoCard(.inset, theme: theme)
            if let reading = readingCopy(for: .nightVitals) {
                Text(reading).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// «Otras señales de anoche»: respiration is dropped for the Respiratory-rate detail (it's the hero), so
    /// only the companion Resting HR shows; the other vitals show both. (Detalle de Vital)
    private var narrativeNightLine: LocalizedStringKey {
        if spec.descriptor.key == "resp_rate" {
            let rhr = nightVitals.restingHR.map { "\(Int($0.rounded()))" } ?? "—"
            return "Resting HR \(rhr)"
        }
        return nightVitalsLine
    }

    // MARK: Tu HRV por frecuencia (frequency-domain breakdown, FER-702)

    private func spectralBandRow(title: LocalizedStringKey, tag: String, subtitle: LocalizedStringKey,
                                 band: SpectralHRV.Band, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Text(title).font(StrandFont.subhead).foregroundStyle(theme.ink)
                    Text("· \(tag)").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                spectralValue(band.value, accent: accent)
            }
            Text(subtitle).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let phrase = Self.spectralLabelPhrase(band.label) {
                Text(phrase).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
        }
    }

    private func spectralValue(_ v: Double, accent: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(Self.groupedInt.string(from: NSNumber(value: Int(v.rounded()))) ?? "\(Int(v.rounded()))")
                .font(StrandFont.number(15)).foregroundStyle(accent)
            Text("ms²").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
    }

    private func spectralNote(_ text: LocalizedStringKey) -> some View {
        Text(text).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// «vs tu normal» phrase per band; nil while calibrating (no trusted baseline yet).
    private static func spectralLabelPhrase(_ label: HRVSpectralBaseline.Label?) -> LocalizedStringKey? {
        switch label {
        case .higher: return "higher than your normal"
        case .normal: return "within your normal"
        case .lower:  return "lower than your normal"
        case nil:     return nil
        }
    }

    // MARK: Tu día (Heart Rate intraday)

    private func hrStatCell(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).textCase(.uppercase).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Text(value).font(StrandFont.number(14)).foregroundStyle(theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .instrumentoCard(.inset, theme: theme)
    }

    // MARK: - Cuerpo narrativo en vidrio Liquid (FER-103 · TND-20)
    //
    // Migración PURAMENTE VISUAL del camino narrativo (HRV / FC en reposo / Respiración / SpO₂ — un
    // solo árbol para los cuatro) del papel «Instrumento» a los legos Liquid, calcando el patrón de
    // `SleepDetailScreen` (la vara) y de `StrainDetailScreen` / `StressDetailScreen` /
    // `SkinTempDetailScreen` (los bloques hermanos ya firmados): campo teñido a sangre
    // (`LiquidCampoMetrica`) → costuras de sección (`LiquidFranjaSeccion`) → lectura de nivel
    // (`LiquidReadingLine`; los rangos viven en la escalera tocable del historial, A-UX-08) →
    // patrón (`LiquidTendenciaCard`, posición de las gemelas: entre Niveles e Historial) →
    // historial (`LiquidRangeSelector` + `LiquidGraficaNiveles` + `LiquidResumenVentana` +
    // `LiquidLevelsList`) → espectral VFC (`LiquidCajitaGrid`, calco «Estabilidad térmica») →
    // método + sello (patrón `pieMetodo` de Sueño).
    //
    // La plomería de datos NO CAMBIA (A14): spec + closures + `.task` con parseo off-main quedan tal
    // cual; cero matemática nueva. La ESCALERA ÚNICA (TND-19) es la fuente de toda palabra/color:
    // `spec.info.bands` (con `key` de motor) para FCr/Resp/SpO₂, la banda personal ±σ para VFC, y
    // `spo2HeroVerdict` para el héroe de SpO₂. El CAMPO se tiñe SIEMPRE por identidad (cian/rosa/
    // azul, calco `LiquidMetricSheetView.tono` :225-248), nunca por juicio.
    //
    // Los helpers de papel del camino narrativo (narrativeBodyFinal, hoyVsRangoContent,
    // graficaRangosBlock, tileStripFinal, …) quedan INTACTOS: el cuerpo intradía sigue en papel
    // hasta su propio bloque, y los árboles viejos (Pasos, VO₂max incluidos) son el rollback.

    /// La identidad Liquid de la métrica — calco del mapa id→hue de la hoja de Hoy
    /// (`LiquidMetricSheetView.tono` :225-248): hrv → cian · rhr → rosa · resp_rate/spo2 → azul
    /// (familia respiratoria) · steps → teal (TND-21) · vo2max → verdePrimario (TND-22, el
    /// mismo default que la hoja de Hoy le da a vo2max en :247). Nunca un color de juicio: el
    /// veredicto lo dicen las palabras. OJO declarado (A11): verde también es el color del
    /// veredicto en el sistema — aquí viste IDENTIDAD por precedente de la hoja; si el campo a
    /// sangre lee como juicio, el tono nuevo es decisión del dueño, no de este bloque.
    private var liquidTono: Color {
        switch spec.descriptor.key {
        case "hrv":               return LiquidColor.cian
        case "rhr", "heart_rate": return LiquidColor.rosa   // TND-23: mismo par que la hoja (:231)
        case "steps":             return LiquidColor.teal
        case "vo2max":            return LiquidColor.verdePrimario
        default:                  return LiquidColor.azul   // resp_rate, spo2
        }
    }

    /// El glifo del campo — calco `LiquidMetricSheetView.glifo` :255-269. spo2 → `.resp`:
    /// «el set Liquid no tiene gota»; el oxígeno comparte la familia respiratoria, igual que su hue.
    private var liquidGlifo: LiquidIcon.Glyph {
        switch spec.descriptor.key {
        case "hrv":               return .onda
        case "rhr", "heart_rate": return .corazon
        case "steps":             return .pasos
        default:                  return .resp   // resp_rate, spo2
        }
    }

    /// Voz nocturna («anoche»/«noches») para SpO₂ y Respiración; diurna para VFC y FC en reposo —
    /// el MISMO reparto que `BandSummaryCopy.isNightly` fija para toda la app.
    private var liquidNocturno: Bool { BandSummaryCopy.isNightly(metricID: spec.descriptor.key) }

    /// Una sección: la costura a sangre + su contenido con el margen del sistema (calco gemelas).
    @ViewBuilder
    private func seccionLiquid<Content: View>(_ titulo: String, @ViewBuilder content: () -> Content) -> some View {
        LiquidFranjaSeccion(titulo, tono: liquidTono)
        content().liquidSeccion()
    }

    /// El esqueleto Liquid del camino narrativo (ver el MARK de arriba para el mapa de bloques).
    /// La lectura del ancla SOLO si es fresca — su llave de día es HOY (TND20-F2, la clase
    /// ancla-de-ayer de las gemelas): una noche vieja no se viste de «hoy/anoche». Sin
    /// `todayKey` del caller se resuelve aquí (body = MainActor, mismo reloj que el resto).
    /// VIT-03: en el PRIMER frame (antes de que el `.task` siembre `series`) el campo abre
    /// con el valor que el spec YA trae — el mismo del tile que se tocó — vía
    /// `liquidSemillaSpec`; el `.task` solo enriquece. La honestidad de ancla queda intacta:
    /// el caller pasa al spec el valor de HOY o nil, así que la semilla nunca es una noche vieja.
    private var liquidValorFresco: Double? {
        guard loaded else { return liquidSemillaSpec }
        guard let last = series.last else { return nil }
        let tk = todayKey ?? Repository.localDayKey(Date())
        return last.day == tk ? last.value : nil
    }

    /// VIT-03 · El valor que el spec trae de fábrica (el del tile de hoy): `levelsTodayValue`
    /// donde el catálogo lo declara (los 4 narrativos, pasos), y el `displayValue` numérico
    /// plano donde no (FC intradía, VO₂max — sus display son enteros sin formato). Si el spec
    /// no trae valor, `nil`: el campo abre apagado, como siempre.
    private var liquidSemillaSpec: Double? {
        spec.info.levelsTodayValue ?? Double(spec.info.displayValue)
    }

    @ViewBuilder private func narrativeBodyLiquid(_ window: MetricWindow) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let v = liquidValorFresco {
                liquidCampoConDato(v)
            } else {
                liquidCampoSinDato
            }
            if infoOpen { liquidQueMedimosCard }
            if !loaded {
                LiquidSheetSkeleton(a11yCargando: String(localized: "Reading your history…"))
                    .liquidSeccion()
            } else if !enoughHistory {
                // Calibrando: la cláusula/sello del campo ya lo dice; con ≥1 lectura el pie de
                // método se conserva (paridad con el papel: `calibrationBlock` + pie).
                if !series.isEmpty { liquidPieMetodo }
            } else {
                // Niveles = solo la lectura del ancla (A-UX-08: los rangos viven en la escalera
                // tocable del historial); sin lectura de hoy, la sección se oculta.
                if liquidIndiceAncla != nil {
                    seccionLiquid(String(localized: "Levels")) { liquidLevelsContent }
                }
                // VIT-09: la franja habla como la familia — «Qué la mueve» (concuerda con la
                // VFC/la FC/la respiración), entre Niveles e Historial (A-UX-09).
                if hasPatron {
                    seccionLiquid(String(localized: "What moves it")) { liquidPatronContent }
                }
                // La sección monta hasta que el parseo terminó (A-UX-04, calco del gate
                // `parsed.count >= 2` de Sueño/Esfuerzo): sin esto, el primer frame pinta la
                // gráfica vacía y brinca al llegar `parsedSeries`.
                if parsedSeries.count >= 2 {
                    seccionLiquid(String(localized: "History")) { liquidHistoryContent(window) }
                }
                if spec.descriptor.key == "hrv", let s = spectral {
                    seccionLiquid(String(localized: "Your HRV by frequency")) { liquidSpectralContent(s) }
                }
                liquidPieMetodo
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: TND-20 · 1. El campo (héroe) — identidad por métrica, veredicto en palabras

    /// El campo teñido a sangre con dato: numeral + unidad con el rótulo temporal («hoy»/«anoche»),
    /// el veredicto de la escalera única, y en la ranura libre las cápsulas que el héroe de papel
    /// llevaba pegadas al numeral («nivel 7 días · …», «Apple») como `LiquidCampoSello`.
    private func liquidCampoConDato(_ v: Double) -> some View {
        LiquidCampoMetrica(
            tono: liquidTono,
            titulo: String(localized: spec.info.name),
            glifo: liquidGlifo,
            datos: [.init(valor: fmt(v), unidad: unit,
                          // El rótulo temporal SOLO con frescura confirmada: la semilla del spec
                          // puede venir de Cuerpo con la lectura de AYER (VIT-03 P2 residual) —
                          // el numeral se ve desde el primer frame, la palabra «hoy/anoche»
                          // espera al `.task`.
                          rotulo: !loaded ? ""
                                : liquidNocturno ? String(localized: "last night")
                                                 : String(localized: "today"))],
            veredicto: liquidVeredicto,
            infoAbierto: infoOpen,
            infoEtiqueta: String(localized: "What we measure"),
            onInfo: { withAnimation(LiquidMotion.lift) { infoOpen.toggle() } }
        ) {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                if let s = liquidSello7d {
                    LiquidCampoSello(s)
                }
                // FER-487: el dato de hoy vino de Apple Salud — la cápsula «Apple» del papel.
                if todayFromApple {
                    LiquidCampoSello(String(localized: "Apple"))
                }
                // Con 1 lectura el campo tiene dato pero la base aún calibra: el aviso vive
                // como sello, no como una segunda escalera de cortes.
                if loaded, !enoughHistory {
                    // TND20-F4: la voz sigue a la métrica (BandSummaryCopy.isNightly) — VFC y
                    // FC en reposo cuentan DÍAS, no noches.
                    LiquidCampoSello(liquidNocturno
                        ? String(localized: "Calibrating · \(series.count) of 7 nights")
                        : String(localized: "Calibrating · \(series.count) of 7 days"))
                }
            }
        }
    }

    /// El campo APAGADO: sin lectura el numeral es un guion, nunca un cero (patrón
    /// `SleepDetailScreen.campoApagado` / `StrainDetailScreen.campoSinDato`).
    private var liquidCampoSinDato: some View {
        LiquidCampoMetrica(
            tono: liquidTono,
            titulo: String(localized: spec.info.name),
            glifo: liquidGlifo,
            datos: [.init(valor: LiquidCajita.sinDato,
                          rotulo: liquidNocturno ? String(localized: "last night")
                                                 : String(localized: "today"),
                          a11y: String(localized: "no data"), ausente: true)],
            clausula: liquidClausulaSinDato
        ) {
            if sinPermiso {
                LiquidVerMas(title: String(localized: "Manage Apple Health permissions"),
                             tone: LiquidColor.papelAlto) { Self.abrirAjustesSalud() }
            }
        }
    }

    /// Cuatro vacíos distintos, no uno: cargando · sin permiso · con historia y sin lectura
    /// fresca · calibrando N de 7 noches. Mismo árbol que `SkinTempDetailScreen.clausulaSinDato`.
    private var liquidClausulaSinDato: String {
        guard loaded else { return String(localized: "Reading your history…") }
        if sinPermiso {
            // Neutro a propósito («lecturas»): la misma cláusula sirve a métricas diurnas y
            // nocturnas (TND20-F4).
            return String(localized: "Cénit can't read this vital: Apple Health hasn't granted permission. Turn it on and your readings will show up here.")
        }
        if enoughHistory {
            return liquidNocturno
                ? String(localized: "No reading from last night yet: your recent history is below.")
                : String(localized: "No reading from today yet: your recent history is below.")
        }
        // VIT-14: primera persona del sistema («Necesito…»), la voz de la familia — claves de
        // esta rama, renombradas. El CTA «Manage Apple Health permissions» QUEDA como está
        // (decisión del orquestador contra la rec de UX: consistencia de familia > brevedad).
        return liquidNocturno
            ? String(localized: "Calibrating your base · \(series.count) of 7 nights. I need a few more nights to show your 7-day average, your normal range and the trend.")
            : String(localized: "Calibrating your base · \(series.count) of 7 days. I need a few more days to show your 7-day average, your normal range and the trend.")
    }

    /// Abre Ajustes de iOS en la ficha de la app — mismo atajo que Sueño/Esfuerzo (FER-102).
    private static func abrirAjustesSalud() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// El veredicto en palabras bajo el numeral — la COSTURA hoja→detalle: las MISMAS frases
    /// que la hoja de Hoy (`MetricLevelPhrase` → `reading.*`, claves ya traducidas), nunca un
    /// segundo vocabulario. SpO₂ = `spo2HeroVerdict` (la escalera de DOS tramos del motor,
    /// TND-19). El campo NUNCA se tiñe por juicio (las gemelas tampoco): la palabra basta.
    private var liquidVeredicto: String? {
        // Sin frescura confirmada, sin frase: la semilla del spec puede ser de ayer (VIT-03
        // residual) — la frase «hoy/anoche» espera al `.task`, como el rótulo.
        guard loaded, let today = liquidValorFresco else { return nil }
        switch spec.descriptor.key {
        case "spo2":
            let v = Self.spo2HeroVerdict(today)
            return String(localized: String.LocalizationValue(v.word))
        case "hrv":
            // VIT-01: las TRES frases de la hoja (`reading.vsBase.hrv.*`) con la MISMA
            // selección half-open que su host de niveles (`MetricLevelsHostModel.compute`:
            // below < lo ≤ inBase < hi ≤ above), sobre la banda que ESTE detalle ya dibuja.
            // Muere el colapso «Normal/Unusual for you».
            guard let band = normalRange else { return nil }
            let key = today < band.lowerBound ? "below"
                : (today >= band.upperBound ? "above" : "inBase")
            return liquidFraseHoja(levelKey: key)
        case "rhr", "resp_rate":
            // VIT-02: la frase POBLACIONAL de la hoja (`reading.vsPopulation.*`), keyeada por
            // el carril del motor donde cae el ancla — la misma gramática que su escalera.
            guard let i = liquidIndiceAncla, let levelKey = liquidBandas[i].key else { return nil }
            return liquidFraseHoja(levelKey: levelKey)
        default:
            guard let band = normalRange else { return nil }
            return band.contains(today)
                ? String(localized: "Normal for you")
                : String(localized: "Unusual for you")
        }
    }

    /// La frase de lectura de la hoja de Hoy para un carril de ESTA métrica — mismo lookup que
    /// `LiquidMetricSheetView.vitalReadingText` (`MetricLevelPhrase.key` → catálogo). `nil`
    /// cuando el par no está en el contrato (sin línea, nunca un default mudo).
    private func liquidFraseHoja(levelKey: String) -> String? {
        guard let phraseKey = MetricLevelPhrase.key(metricID: spec.descriptor.key,
                                                    levelKey: levelKey) else { return nil }
        return String(localized: String.LocalizationValue(phraseKey))
    }

    /// «promedio de 7 días · 58 ms» — la cápsula de contexto que era la cláusula del héroe de
    /// papel. M3: UNA palabra en los dos cuerpos («average», como el sello de Pasos; la clave
    /// vieja «7-day level · %@ %@» sigue viva para el papel rollback). VIT-11: con menos de 7
    /// puntos el sello no miente «7 días» — dice sobre cuántos corre de verdad (armonizado con
    /// M3: «average», no «level»; misma decisión de vocabulario único).
    private var liquidSello7d: String? {
        guard let avg = SeriesShape.latestMovingAverage(allValues, window: 7) else { return nil }
        if allValues.count < 7 {
            return String(localized: "average over \(allValues.count) days · \(fmt(avg)) \(unit)")
        }
        return String(localized: "7-day average · \(fmt(avg)) \(unit)")
    }

    /// La tarjeta del ⓘ bajo el campo — VIT-10: el MISMO copy que la hoja de Hoy enseña en su
    /// ⓘ (`spec.info.headline`, con es para los 7 — verificado), no el `readingCopy(.header)`
    /// del papel: una explicación, dos superficies. Patrón `SleepDetailScreen.queMedimosCard`.
    @ViewBuilder private var liquidQueMedimosCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(String(localized: "What we measure"))
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: spec.info.headline))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidTarjetaSeccion()
        .liquidSeccion(top: LiquidSpace.s400, bottom: LiquidSpace.s200)
    }

    // MARK: TND-20 · La escalera única, vestida Liquid

    /// Un carril de la escalera Liquid. Para FCr/Resp/SpO₂ sale de `spec.info.bands` (la escalera
    /// del motor, con `key` — TND-19); para VFC de la banda personal ±σ (`graficaRangosBands`
    /// conservada como DATO). Nunca una segunda copia de cortes.
    struct BandaVitalLiquid {
        let key: String?
        let label: String
        let lo: Double?
        let hi: Double?
        let color: Color
        let range: String
    }

    /// Los carriles de esta métrica, en el orden ascendente del motor (paridad gemelas). VFC sin
    /// base → `[]` (modo sin carriles, estado honesto).
    private var liquidBandas: [BandaVitalLiquid] {
        if spec.descriptor.key == "hrv" {
            guard let nr = normalRange else { return [] }
            let lo = nr.lowerBound, hi = nr.upperBound
            // Carriles half-open que cubren la banda personal CERRADA [lo, hi] — el MISMO reparto
            // que `graficaRangosBands()` usa en el papel (below / within / above).
            return [
                BandaVitalLiquid(key: "below", label: String(localized: "Unusual for you"),
                                 lo: nil, hi: lo,
                                 color: Self.liquidColorNivel(metric: "hrv", key: "below", tono: liquidTono),
                                 range: "< \(fmt(lo))"),
                BandaVitalLiquid(key: "within", label: String(localized: "Normal for you"),
                                 lo: lo, hi: hi.nextUp,
                                 color: Self.liquidColorNivel(metric: "hrv", key: "within", tono: liquidTono),
                                 range: "\(fmt(lo))–\(fmt(hi))"),
                BandaVitalLiquid(key: "above", label: String(localized: "Unusual for you"),
                                 lo: hi.nextUp, hi: nil,
                                 color: Self.liquidColorNivel(metric: "hrv", key: "above", tono: liquidTono),
                                 range: "≥ \(fmt(hi))")
            ]
        }
        return spec.info.bands
            .filter { $0.lower != nil || $0.upper != nil }
            .map { b in
                BandaVitalLiquid(key: b.key,
                                 label: plainLocalizedLabel(b.label),
                                 lo: b.lower, hi: b.upper,
                                 color: Self.liquidColorNivel(metric: spec.descriptor.key,
                                                              key: b.key, tono: liquidTono),
                                 range: b.range)
            }
    }

    /// El tono de cada carril: UNA rampa del hue de identidad graduada por CLAVE — la tinta sube
    /// con el valor de la métrica, literal (calco `StrainDetailScreen.colorNivel` /
    /// `SkinTempDetailScreen.colorNivel`). Nunca un semáforo ni `theme.*` en el camino Liquid:
    /// `laneColor` (TND-19) queda para el papel restante. Estática para poder fijarla en tests.
    static func liquidColorNivel(metric: String, key: String?, tono: Color) -> Color {
        switch (metric, key) {
        case ("hrv", "below"):        return tono.opacity(0.32)  // token-exempt: rampa graduada de identidad (geometría de dato)
        case ("hrv", "within"):       return tono.opacity(0.62)  // token-exempt: rampa graduada de identidad (geometría de dato)
        case ("hrv", "above"):        return tono
        case ("rhr", "rhrAthlete"):   return tono.opacity(0.28)  // token-exempt: rampa graduada de identidad (geometría de dato)
        case ("rhr", "rhrLow"):       return tono.opacity(0.48)  // token-exempt: rampa graduada de identidad (geometría de dato)
        case ("rhr", "rhrTypical"):   return tono.opacity(0.70)  // token-exempt: rampa graduada de identidad (geometría de dato)
        case ("rhr", "rhrHigher"):    return tono
        case ("resp_rate", "normal"): return tono.opacity(0.55)  // token-exempt: rampa graduada de identidad (geometría de dato)
        case ("resp_rate", "elevated"): return tono
        case ("spo2", "low"):         return tono.opacity(0.50)  // token-exempt: rampa graduada de identidad (geometría de dato)
        case ("spo2", "normal"):      return tono
        // Steps (TND-21): la tinta sube con el valor — misma rampa de 3 carriles que la de VFC.
        case ("steps", "sedentary"):  return tono.opacity(0.32)  // token-exempt: rampa graduada de identidad (geometría de dato)
        case ("steps", "active"):     return tono.opacity(0.62)  // token-exempt: rampa graduada de identidad (geometría de dato)
        case ("steps", "veryActive"): return tono
        default:                      return tono
        }
    }

    /// El carril en que cae la lectura de hoy, o `nil` sin lectura/sin base. Único predicado del
    /// camino Liquid: lo leen el campo, Niveles, el historial y la escalera tocable.
    private var liquidIndiceAncla: Int? {
        guard let v = liquidValorFresco else { return nil }
        return liquidBandas.firstIndex { b in
            (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!)
        }
    }

    /// El carril resaltado en la gráfica y en la escalera: el que el dedo explora, o el del ancla.
    private var liquidDestacado: Int? { bandaExplorada ?? liquidIndiceAncla }

    // MARK: TND-20 · 2. Niveles — la lectura del ancla contra la escalera única

    /// «Hoy/Anoche cae en X · …» — la banda inline del papel MUERE (A-UX-08, degradación
    /// decidida): los rangos viven en la escalera tocable del historial. El `positionSlider`
    /// del papel no era tocable (solo a11y), así que no se pierde interacción.
    @ViewBuilder private var liquidLevelsContent: some View {
        if let i = liquidIndiceAncla {
            let b = liquidBandas[i]
            if spec.descriptor.key == "hrv", let s = baselineState {
                // TND20-F4: VFC habla en DÍAS (BandSummaryCopy.isNightly la declara diurna).
                LiquidReadingLine(
                    String(localized: "Today falls in \(b.label) · your normal range from \(s.nValid) days"),
                    highlight: b.label, highlightTone: liquidTono)
            } else if spec.descriptor.key == "spo2" {
                // VIT-13: el hedge de SpO₂ nombra el piso clínico real (95%), no el genérico
                // «referencia poblacional» — la clave vieja sigue viva para rhr/resp/pasos.
                LiquidReadingLine(
                    String(localized: "Last night falls in \(b.label) · healthy adults usually sit at 95% or above"),
                    highlight: b.label, highlightTone: liquidTono)
            } else if liquidNocturno {
                LiquidReadingLine(
                    String(localized: "Last night falls in \(b.label) · population reference, not your verdict"),
                    highlight: b.label, highlightTone: liquidTono)
            } else {
                LiquidReadingLine(
                    String(localized: "Today falls in \(b.label) · population reference, not your verdict"),
                    highlight: b.label, highlightTone: liquidTono)
            }
        }
    }

    // MARK: TND-20 · 3. Tu patrón — hallazgos direccionales + señales de anoche

    /// `LiquidTendenciaCard` (la pieza de las gemelas, A-UX-09) con las MISMAS frases de
    /// `WhatMovesItFinding.phrase`, más las señales de anoche como notas. Las flechas ↑/↓ del papel
    /// no cruzan: la dirección la dicen las palabras, como en Esfuerzo/Estrés.
    @ViewBuilder private var liquidPatronContent: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            if visibleBlocks.contains(.whatMovesIt), !series.isEmpty {
                if whatMovesItFindings.isEmpty {
                    // VIT-14: la FC en reposo no exige el Watch (Apple Salud también la trae)
                    // — su vacío pide «sigue registrando tus días». La clave del Watch es
                    // COMPARTIDA con el papel (quemueveFinalView) y queda intacta para VFC/Resp.
                    LiquidNotaLine(spec.descriptor.key == "rhr"
                        ? String(localized: "Not enough data yet: keep logging your days and check back in a few weeks.")
                        : String(localized: "Not enough data yet: keep wearing your Apple Watch and check back in a few weeks."),
                                   tono: LiquidColor.tinta700)
                } else {
                    LiquidTendenciaCard(
                        overline: String(localized: "What we see in your history"),
                        chip: String(localized: "trend, not cause"),
                        lineas: whatMovesItFindings.map { plainLocalizedLabel($0.phrase) })
                }
            }
            if visibleBlocks.contains(.nightVitals),
               nightVitals.respiration != nil || nightVitals.restingHR != nil {
                VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                    LiquidNotaLine(liquidSenalesNoche, tono: LiquidColor.tinta700)
                    if let reading = readingCopy(for: .nightVitals) {
                        LiquidNotaLine(plainLocalizedLabel(reading))
                    }
                }
            }
        }
    }

    /// «Otras señales de anoche · Respiración 14.6 · FC reposo 52» — mismas claves que el papel
    /// (`narrativeNightLine`): la respiración se omite en el detalle de Respiración (es el héroe).
    private var liquidSenalesNoche: String {
        let label = String(localized: "Other signals from last night")
        let rhr = nightVitals.restingHR.map { "\(Int($0.rounded()))" } ?? "—"
        if spec.descriptor.key == "resp_rate" {
            return "\(label) · " + String(localized: "Resting HR \(rhr)")
        }
        let resp = nightVitals.respiration.map { String(format: "%.1f", $0) } ?? "—"
        return "\(label) · " + String(localized: "Respiration \(resp) · Resting HR \(rhr)")
    }

    // MARK: TND-20 · 4. Historial — selector + gráfica + resumen + escalera tocable

    private func liquidHistoryContent(_ window: MetricWindow) -> some View {
        // SpO₂ (clínica) grafica noches CRUDAS; los vitales personales suavizan la serie nocturna
        // ruidosa a 7 días — el MISMO reparto que `graficaRangosBlock` hace en el papel.
        let plot: [Double] = spec.clinicalBands
            ? window.values
            : SeriesShape.movingAverage(window.values, window: 7)
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            if visibleBlocks.contains(.periodSelector) {
                LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                    seleccion: liquidRangeSeleccion, tono: liquidTono)
            }
            if window.values.count > 1 {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    // TND20-F3: la frase y la escalera cuentan LO QUE LA GRÁFICA TRAZA (`plot`,
                    // la media móvil donde se suaviza) — el papel (`GraficaRangos`) contaba los
                    // puntos graficados; contar la serie cruda hacía que tocar «12 noches» no
                    // encendiera 12 puntos.
                    liquidFraseNivelHistorial(window, plot: plot)
                    liquidNotaDelta(window)
                    liquidGraficaHistorial(window, plot: plot)
                    LiquidNotaLine(liquidNotaGrafica)
                    LiquidResumenVentana(celdas: liquidResumenCeldas(window))
                }
                .liquidTarjetaSeccion()
                if !liquidBandas.isEmpty {
                    LiquidLevelsList(filas: liquidCarriles(window, plot: plot), tono: liquidTono)
                    LiquidNotaLine(liquidNocturno
                        ? String(localized: "How many nights of the period fell in each band. Tap one to see its nights on the chart.")
                        : String(localized: "How many days of the period fell in each band. Tap one to see its days on the chart."))
                }
            } else {
                // Una sola lectura o ninguna en el rango → el pozo vacío honesto (calco gemelas).
                LiquidGraficaNiveles(puntos: [], bandas: [],
                                     dominio: liquidDominio(plot: []), ticksY: [],
                                     tono: liquidTono,
                                     estadoVacio: liquidEstadoVacio,
                                     a11yLabel: liquidA11yGrafica)
            }
        }
    }

    /// El índice del selector ⇄ `ExploreRange`; cambiar de rango suelta el carril explorado.
    private var liquidRangeSeleccion: Binding<Int> {
        Binding(
            get: { ExploreRange.allCases.firstIndex(of: range) ?? 0 },
            set: { idx in
                range = ExploreRange.allCases[idx]
                bandaExplorada = nil
            })
    }

    /// El carril del ancla y cuántos días/noches del periodo cayeron con él — mismo contrato que
    /// `fraseNivelHistorial` de las gemelas.
    /// `anclaEnLinea`: false cuando el ancla fresca NO es un punto trazado (Pasos: la línea
    /// solo lleva días completos y el parcial de hoy queda fuera, TND21-1) — la frase no nombra
    /// el carril del parcial como si fuera el de la serie.
    @ViewBuilder private func liquidFraseNivelHistorial(_ window: MetricWindow,
                                                        plot: [Double],
                                                        anclaEnLinea: Bool = true) -> some View {
        if anclaEnLinea, let i = liquidIndiceAncla {
            let b = liquidBandas[i]
            // TND20-F3: se cuenta la serie TRAZADA (paridad `GraficaRangos`: contaba `points`).
            let n = plot.filter { v in
                (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!)
            }.count
            LiquidFraseNivel(nivel: b.label,
                             conteo: liquidNocturno
                                ? String(localized: "\(n) of your last \(plot.count) nights")
                                : String(localized: "\(n) of your last \(plot.count) days"),
                             tono: liquidTono)
        } else {
            // `sinLectura` solo cuando de verdad NO hay lectura FRESCA: VFC sin base tiene
            // lectura pero cero carriles — decir «Hoy sin lectura» ahí mentiría (estado honesto).
            // B3: la frase cuenta LO TRAZADO (`plot`), SIEMPRE — `window.values` incluye el
            // parcial de hoy que en Pasos no está en la línea de días completos.
            LiquidFraseNivel(nivel: nil,
                             conteo: liquidNocturno
                                ? String(localized: "\(plot.count) nights with data in this range")
                                : String(localized: "\(plot.count) days with data in this range"),
                             tono: liquidTono,
                             sinLectura: liquidValorFresco != nil ? nil
                                : (liquidNocturno
                                    ? String(localized: "No reading last night")
                                    : String(localized: "No reading today")))
        }
    }

    /// M1 · El Δ% del periodo vs el anterior como nota coloreada CON signo entre la frase y la
    /// gráfica — el formato de las hermanas (calco `StrainDetailScreen` :270-273), coloreado
    /// por la polaridad de la métrica (la MISMA lógica que tenía la celda «Trend» del resumen,
    /// que muere con esto). Plano (0%) o métrica neutral → tinta quieta.
    @ViewBuilder private func liquidNotaDelta(_ window: MetricWindow) -> some View {
        if let pct = window.range.periodComparison(of: trendComparisonSeries)?.pctChange {
            let rounded = Int(pct.rounded())
            let texto = pct >= 0 ? "+\(rounded)%" : "\(rounded)%"
            if let tono = liquidTonoDelta(pct) {
                LiquidNotaLine(texto, tono: tono)
            } else {
                LiquidNotaLine(texto)
            }
        }
    }

    /// El tono del Δ% por polaridad (VFC↑ bueno, FCr/Resp↓ bueno…): la dirección buena →
    /// positivo, la contraria → atención; plano o neutral → nil (tinta por defecto).
    private func liquidTonoDelta(_ pct: Double) -> Color? {
        guard Int(abs(pct).rounded()) != 0 else { return nil }
        switch trendPolarity {
        case .higherIsBetter: return pct > 0 ? LiquidColor.positivo : LiquidColor.atencionTexto
        case .lowerIsBetter:  return pct < 0 ? LiquidColor.positivo : LiquidColor.atencionTexto
        case .neutral:        return nil
        }
    }

    /// La gráfica del historial con los carriles de la escalera única detrás y los ticks
    /// afirmando los CORTES reales del motor (paridad TND10-3).
    private func liquidGraficaHistorial(_ window: MetricWindow, plot: [Double]) -> some View {
        let puntos = MetricWindowMath
            .decimatedPoints(rows: window.rows, values: plot, maxPoints: 80)
            .map { (fecha: $0.date, valor: $0.value) }
        return LiquidGraficaNiveles(
            puntos: puntos,
            bandas: liquidBandas.enumerated().map { i, b in
                LiquidChartBanda(lo: b.lo, hi: b.hi, color: b.color, activa: i == liquidDestacado)
            },
            dominio: liquidDominio(plot: plot),
            ticksY: liquidTicksY,
            tono: liquidTono,
            // TND20-F6: la joya de «hoy» solo con lectura FRESCA — el último punto puede ser
            // de anteayer.
            puntoHoy: liquidValorFresco != nil ? puntos.last : nil,
            hoyAnillo: bandaExplorada != nil && bandaExplorada != liquidIndiceAncla,
            formatoScrub: { v, f in "\(fmt(v)) · \(Self.ejeFechaLiquid.string(from: f))" },
            formatoValorScrub: { fmt($0) },
            formatoFechaScrub: { Self.ejeFechaLiquid.string(from: $0) },
            formatoFechaEje: { Self.ejeFechaLiquid.string(from: $0) },
            atenuarFuera: bandaExplorada != nil,
            estadoVacio: liquidEstadoVacio,
            a11yLabel: liquidA11yGrafica)
            .id(range)
    }

    /// El dominio Y: SpO₂ su dominio clínico fijo (88–100); VFC la banda personal con aire (la
    /// MISMA aritmética que `graficaDomain` del papel); FCr/Resp abren TODOS los cortes del motor
    /// con el dato incluido — así el carril se lee como carril y no como borde recortado (paridad
    /// `SkinTempDetailScreen.dominioTemp`). Presentación pura, cero matemática de datos.
    private func liquidDominio(plot: [Double]) -> ClosedRange<Double> {
        if let domain = spec.chartDomain { return domain }
        if spec.descriptor.key == "hrv", let band = normalRange {
            let span = band.upperBound - band.lowerBound
            let pad = Swift.max(span * 0.6, 1)
            let lo = Swift.min(band.lowerBound - pad, plot.min() ?? band.lowerBound)
            let hi = Swift.max(band.upperBound + pad, plot.max() ?? band.upperBound)
            return lo...hi
        }
        let cortes = liquidBandas.flatMap { [$0.lo, $0.hi].compactMap { $0 } }
        let lo = Swift.min(plot.min() ?? (cortes.min() ?? 0), cortes.min() ?? (plot.min() ?? 0))
        let hi = Swift.max(plot.max() ?? (cortes.max() ?? 1), cortes.max() ?? (plot.max() ?? 1))
        guard hi > lo else { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.1
        return (lo - pad)...(hi + pad)
    }

    /// Los ticks del eje: los cortes reales de la escalera (SpO₂ añade los extremos de su dominio
    /// clínico, paridad `clinicalYAxisValues`; VFC los bordes de su banda personal).
    private var liquidTicksY: [(valor: Double, etiqueta: String)] {
        if spec.descriptor.key == "spo2", let domain = spec.chartDomain {
            let cortes = Set(liquidBandas.flatMap { [$0.lo, $0.hi].compactMap { $0 } })
            return ([domain.lowerBound, domain.upperBound] + cortes)
                .sorted(by: >)
                .map { ($0, fmt($0)) }
        }
        if spec.descriptor.key == "hrv" {
            guard let band = normalRange else { return [] }
            return [(band.upperBound, fmt(band.upperBound)), (band.lowerBound, fmt(band.lowerBound))]
        }
        let cortes = Set(liquidBandas.flatMap { [$0.lo, $0.hi].compactMap { $0 } })
        return cortes.sorted(by: >).map { ($0, fmt($0)) }
    }

    /// La nota bajo la gráfica: qué línea es (suavizada vs cruda) — el conmutador Media ⇄ Rangos
    /// del papel MUERE (A9); la información sobrevive en la gráfica + la escalera con conteos.
    private var liquidNotaGrafica: String {
        if spec.clinicalBands {
            return String(localized: "Nightly values · the healthy zone is 95% or above.")
        }
        // TND20-F7: la voz sigue a la métrica — VFC y FC en reposo hablan en días.
        return liquidNocturno
            ? String(localized: "7-day moving average: night-to-night values are noisy.")
            : String(localized: "7-day moving average: day-to-day values are noisy.")
    }

    private var liquidEstadoVacio: String {
        liquidNocturno
            ? String(localized: "Not enough nights in this range to draw a trend.")
            : String(localized: "Not enough days in this range to draw a trend.")
    }

    private var liquidA11yGrafica: String {
        switch spec.descriptor.key {
        case "hrv":    return String(localized: "HRV history")
        case "rhr":    return String(localized: "Resting heart rate history")
        case "spo2":   return String(localized: "Blood oxygen history")
        case "steps":  return String(localized: "Steps history")
        case "vo2max": return String(localized: "VO₂max history")
        default:       return String(localized: "Breathing history")
        }
    }

    /// El resumen por métrica, calcando `statCells` del papel (M4: promedio/rango CRUDOS de la
    /// ventana del selector): VFC Promedio/Consistencia · FCr Promedio/Rango · Resp Promedio/
    /// Rango · SpO₂ Promedio/«Noches < 95%». M1: la celda «Tendencia» MURIÓ — el Δ% vive como
    /// nota con signo sobre la gráfica. M2: TODAS las celdas siguen a la VENTANA del selector
    /// (noches < 95% y la consistencia también), no a un mes fijo ni a la serie completa.
    /// M3: la celda-ancla «Hoy» de las hermanas NO se añade — aquí el CAMPO es el ancla
    /// (decisión del orquestador); el sello de 7 días ya dice «average», una palabra en los
    /// dos cuerpos.
    private func liquidResumenCeldas(_ window: MetricWindow) -> [LiquidResumenVentana.Celda] {
        let stat = ComparisonEngine.stat(window.values)
        let promedio = LiquidResumenVentana.Celda(
            rotulo: String(localized: "Average"),
            valor: unit.isEmpty ? fmt(stat.mean) : "\(fmt(stat.mean)) \(unit)")
        let rango = LiquidResumenVentana.Celda(
            rotulo: String(localized: "Range"),
            valor: "\(fmt(stat.min))–\(fmt(stat.max))")
        switch spec.descriptor.key {
        case "hrv":
            var celdas = [promedio]
            // M2: CV sobre la ventana (mismo trato que Temp UX-11), no sobre toda la historia.
            if let cv = SeriesShape.coefficientOfVariation(window.values, window: 7) {
                let steady = Int((cv * 100).rounded()) <= 10
                celdas.append(.init(rotulo: String(localized: "Consistency"),
                                    valor: String(localized: steady ? "Steady" : "Variable")))
            }
            return celdas
        case "rhr":
            return [promedio, rango]
        case "spo2":
            guard let threshold = spec.lowThreshold else { return [promedio] }
            // M2: noches < 95% de la VENTANA del selector (el papel contaba el último mes fijo).
            let low = window.values.reduce(0) { $0 + ($1 < threshold ? 1 : 0) }
            return [promedio,
                    .init(rotulo: String(localized: "Nights < 95%"),
                          valor: String(localized: "\(low) of \(window.values.count)"),
                          tono: low > 0 ? LiquidColor.atencionTexto : nil)]
        default:   // resp_rate
            return [promedio, rango]
        }
    }

    /// Los carriles tocables bajo la gráfica: tocar uno resalta sus días/noches; re-tocarlo limpia.
    /// Mismo contrato que `carrilesHistorial` de las gemelas.
    private func liquidCarriles(_ window: MetricWindow, plot: [Double],
                                anclaEnLinea: Bool = true) -> [LiquidLevelsList.Fila] {
        let hint = String(localized: "Highlights this level on the chart")
        let hoyRotulo = liquidNocturno ? String(localized: "· last night") : String(localized: "· today")
        // TND21-1: sin ancla en la línea (Pasos), ninguna fila viste «· today» de un punto
        // que no está trazado.
        let iAncla = anclaEnLinea ? liquidIndiceAncla : nil
        let bandas = liquidBandas
        return bandas.indices.map { i in
            let b = bandas[i]
            // TND20-F3: la serie TRAZADA, para que «N noches» encienda N puntos.
            let n = plot.filter { v in
                (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!)
            }.count
            let conteo: String = liquidNocturno
                ? (n == 1 ? String(localized: "\(n) night") : String(localized: "\(n) nights"))
                : (n == 1 ? String(localized: "\(n) day") : String(localized: "\(n) days"))
            return LiquidLevelsList.Fila(
                etiqueta: b.label, rango: b.range,
                conteo: conteo,
                esHoy: i == iAncla, activa: i == (bandaExplorada ?? iAncla),
                hoyEtiqueta: hoyRotulo, a11yHint: hint,
                onTap: {
                    withAnimation(LiquidMotion.lift) {
                        bandaExplorada = (bandaExplorada == i) ? nil : i
                    }
                })
        }
    }

    private static let ejeFechaLiquid: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("dMMM"); return f
    }()

    // MARK: TND-20 · 5. Espectral VFC — calco EXACTO del patrón «Estabilidad térmica»
    // (`SkinTempDetailScreen.thermalBlock` :513-525): cajitas + notas de hedge. Cero pérdida
    // de copy — las claves (subtítulos, frases «vs tu normal», Lomb-Scargle) se conservan.

    @ViewBuilder private func liquidSpectralContent(_ s: SpectralHRV) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCajitaGrid {
                LiquidCajita(rotulo: "\(String(localized: "Respiratory")) · HF",
                             valor: liquidSpectralValor(s.hf.value),
                             unidad: "ms²",
                             pie: liquidSpectralPie(
                                subtitulo: String(localized: "your calm signal, tied to your breathing"),
                                label: s.hf.label),
                             tono: liquidTono,
                             compacto: true)
                if let lf = s.lf {
                    LiquidCajita(rotulo: "\(String(localized: "Slow")) · LF",
                                 valor: liquidSpectralValor(lf.value),
                                 unidad: "ms²",
                                 pie: liquidSpectralPie(
                                    subtitulo: String(localized: "slow waves; a mix of signals"),
                                    label: lf.label),
                                 compacto: true)
                }
                LiquidCajita(rotulo: String(localized: "Total variation"),
                             valor: liquidSpectralValor(s.total),
                             unidad: "ms²",
                             pie: String(localized: "everything together, the “volume” of your HRV"),
                             compacto: true)
            }
            if s.lf == nil {
                LiquidNotaLine(String(localized: "Last night's reading was short, so it only covers the respiratory part: not the slow waves."),
                               tono: LiquidColor.tinta700)
            } else if s.hf.label == nil {
                LiquidNotaLine(String(localized: "Still learning your normal range. Once there are enough nights, I'll tell you whether a value is high or low for you."),
                               tono: LiquidColor.tinta700)
            }
            LiquidNotaLine(String(localized: "Computed from last night's heartbeats (Lomb-Scargle). These are descriptive band powers to compare against yourself: not a diagnosis or a “stress balance.”"))
        }
    }

    private func liquidSpectralValor(_ v: Double) -> String {
        Self.groupedInt.string(from: NSNumber(value: Int(v.rounded()))) ?? "\(Int(v.rounded()))"
    }

    /// El pie de una cajita espectral: subtítulo + «vs tu normal» (mismas claves que el papel).
    private func liquidSpectralPie(subtitulo: String, label: HRVSpectralBaseline.Label?) -> String {
        guard let frase = liquidFraseEspectral(label) else { return subtitulo }
        return "\(subtitulo) · \(frase)"
    }

    /// «vs tu normal» por banda; nil mientras calibra — mismas claves que `spectralLabelPhrase`.
    private func liquidFraseEspectral(_ label: HRVSpectralBaseline.Label?) -> String? {
        switch label {
        case .higher: return String(localized: "higher than your normal")
        case .normal: return String(localized: "within your normal")
        case .lower:  return String(localized: "lower than your normal")
        case nil:     return nil
        }
    }

    // MARK: TND-20 · 6. Método + sello — patrón `pieMetodo` de Sueño (capilar sin franja propia)

    private var liquidPieMetodo: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            if visibleBlocks.contains(.method), let method = spec.info.method {
                LiquidMetodo(title: String(localized: "How it's calculated"),
                             mostrar: String(localized: "Show explanation"),
                             ocultar: String(localized: "Hide explanation")) {
                    LiquidNotaLine(String(localized: method.prose), tono: LiquidColor.tinta700)
                    if let citation = method.citation {
                        LiquidNotaLine(String(localized: citation))
                    }
                }
            }
            // VIT-10: el chip de origen es la marca de PROCEDENCIA de la hoja de Hoy
            // (`origenChipVista` :1611-1626) para los 7 — gota `.corazon` sobre rosa +
            // «Apple Health» (Watch para resp_rate), NUNCA el glifo/hue de la métrica: el
            // chip nombra la fuente, no la señal. El sufijo temporal fresco se CONSERVA
            // (decisión del orquestador: nuestra M2 —«hoy/anoche» solo con lectura fresca—
            // es más honesta que el «on your device» fijo de la hoja). M2: nunca
            // procedencia sobre un guion — el chip solo con historia.
            if !series.isEmpty {
                LiquidOrigenChip(glyph: .corazon, badgeTono: LiquidColor.rosa,
                                 etiqueta: spec.descriptor.key == "resp_rate"
                                     ? String(localized: "Apple Watch")
                                     : String(localized: "Apple Health"),
                                 // TND20-F6: el sufijo temporal solo con lectura FRESCA
                                 // (para VO₂max, casi nunca — su ancla es vieja por diseño).
                                 sufijo: liquidValorFresco != nil
                                     ? (liquidNocturno ? String(localized: "last night")
                                                       : String(localized: "today"))
                                     : nil)
            }
        }
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

    // MARK: - Cuerpo de Pasos en vidrio Liquid (FER-103 · TND-21)
    //
    // Migración PURAMENTE VISUAL del camino de Pasos (`stepsBodyFinal`, que queda como rollback)
    // sobre los mismos legos que el cuerpo narrativo de arriba. Las decisiones ya cobradas:
    //
    // · ANCLA FRESCA (TND20-F2): el campo con dato SOLO cuando `liquidValorFresco` dice que la
    //   última fila ES hoy — un teléfono sin uso no viste un conteo viejo de «hoy». El conteo de
    //   hoy además está SIEMPRE acumulándose (`spec.currentDayIncomplete`, FER-264): el campo lo
    //   sella «en curso» (calco StrainDetailScreen) y la serie trazada / los promedios de ventana
    //   leen SOLO días completos (`trendStatRows`), exactamente el reparto del papel.
    // · ESCALERA ÚNICA (TND-19): los 3 carriles del motor via `spec.info.bands` (sedentary /
    //   active / veryActive — la guarda `MetricInfoEscaleraUnicaTests` los fija); palabra, color
    //   (rampa teal en `liquidColorNivel`) y conteos salen SOLO de ahí.
    // · CONTEOS = LO TRAZADO (TND20-F3): frase y escalera cuentan `plot` (la media móvil de 7
    //   días sobre días completos, el mismo reparto que `graficaRangosBlock` hacía en papel).
    // · VOZ diurna (TND20-F4): pasos habla en DÍAS (`BandSummaryCopy.isNightly("steps")` = false).
    // · Sello de origen (M1/M2): «Apple Health» — el vocabulario de la hoja de Hoy
    //   (`LiquidMetricSheetView.origen`: steps → appleSalud); `liquidPieMetodo` ya lo resuelve.

    /// El esqueleto Liquid de Pasos: campo → (ⓘ) → patrón → historial → método. «Tu patrón» va
    /// ANTES del historial — la posición de familia (A-UX-09), no el orden del papel.
    @ViewBuilder private func stepsBodyLiquid(_ window: MetricWindow) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let v = liquidValorFresco {
                liquidStepsCampoConDato(v)
            } else {
                liquidStepsCampoSinDato
            }
            if infoOpen { liquidQueMedimosCard }
            if !loaded {
                LiquidSheetSkeleton(a11yCargando: String(localized: "Reading your history…"))
                    .liquidSeccion()
            } else if !enoughHistory {
                // Reuniendo: la cláusula/sello del campo ya lo dice; con ≥1 lectura el pie de
                // método se conserva (paridad papel: `calibrationBlock` + pie).
                if !series.isEmpty { liquidPieMetodo }
            } else {
                // VIT-05: la sección «Niveles» vuelve para Pasos — la lectura del ancla contra
                // la escalera del motor (clave existente con su hedge poblacional), gateada a
                // lectura FRESCA; el «hasta ahora» del veredicto ya cubre el día parcial.
                if liquidIndiceAncla != nil {
                    seccionLiquid(String(localized: "Levels")) { liquidLevelsContent }
                }
                if stepsMovers != nil {
                    // VIT-09: la franja conserva la voz propia de Pasos («Qué mueve tus pasos»).
                    seccionLiquid(String(localized: "What moves your steps")) { liquidStepsPatronContent }
                }
                if parsedSeries.count >= 2 {
                    seccionLiquid(String(localized: "History")) { liquidStepsHistoryContent(window) }
                }
                liquidPieMetodo
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: TND-21 · 1. El campo — conteo de hoy en curso, la frase de la hoja como veredicto

    /// El campo teñido con dato: numeral = el conteo de HOY (sin unidad, como el héroe de papel),
    /// veredicto = la frase POBLACIONAL de la hoja de Hoy (VIT-05: `reading.vsPopulation.steps.*`,
    /// ya con hedge de día parcial — «hasta ahora»), y en la ranura libre «en curso»
    /// (`currentDayIncomplete`), la media de 7 días como SELLO (bajó del veredicto), la cápsula
    /// «Apple» del papel y el aviso de calibración en voz de pasos.
    private func liquidStepsCampoConDato(_ v: Double) -> some View {
        LiquidCampoMetrica(
            tono: liquidTono,
            titulo: String(localized: spec.info.name),
            glifo: liquidGlifo,
            // Rótulo temporal solo con frescura confirmada (VIT-03 residual, como el narrativo).
            datos: [.init(valor: fmt(v), rotulo: !loaded ? "" : String(localized: "today"))],
            veredicto: liquidStepsVeredicto,
            infoAbierto: infoOpen,
            infoEtiqueta: String(localized: "What we measure"),
            onInfo: { withAnimation(LiquidMotion.lift) { infoOpen.toggle() } }
        ) {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                // El conteo de hoy SIEMPRE está acumulándose (FER-264) — el mismo aviso que
                // Esfuerzo y la FC intradía llevan pegado al numeral. (calco StrainDetailScreen)
                LiquidCampoSello(String(localized: "in progress"))
                // VIT-05: la media de 7 días como sello del campo (era el veredicto). La media
                // corre sobre la serie completa, hoy parcial incluido — calco del papel.
                if let s = liquidStepsSello7d {
                    LiquidCampoSello(s)
                }
                if todayFromApple {
                    LiquidCampoSello(String(localized: "Apple"))
                }
                // FER-254: pasos «reúne» (no «calibra») y NUNCA promete un «rango normal» —
                // no tiene banda personal. Por eso no cruza el sello genérico de calibración.
                if loaded, !enoughHistory {
                    LiquidCampoSello(String(localized: "Gathering · \(series.count) of 7 days"))
                }
            }
        }
    }

    /// VIT-05: el veredicto del campo es la MISMA frase poblacional de la hoja de Hoy, keyeada
    /// por el carril del motor donde cae el conteo fresco («Activo, un buen día» / «Tranquilo
    /// hasta ahora» / «Muy activo hoy»).
    private var liquidStepsVeredicto: String? {
        // Sin frescura confirmada, sin frase (VIT-03 residual — misma regla que el narrativo).
        guard loaded, let i = liquidIndiceAncla, let levelKey = liquidBandas[i].key else { return nil }
        return liquidFraseHoja(levelKey: levelKey)
    }

    /// «promedio de 7 días · N pasos» — el sello con la llave del héroe de papel (es en
    /// minúscula, T5). VIT-11: con menos de 7 días dice sobre cuántos corre de verdad.
    private var liquidStepsSello7d: String? {
        guard let avg = SeriesShape.latestMovingAverage(allValues, window: 7) else { return nil }
        if allValues.count < 7 {
            return String(localized: "average over \(allValues.count) days · \(fmt(avg)) steps")
        }
        return String(localized: "7-day average · \(fmt(avg)) steps")
    }

    /// El campo APAGADO: sin conteo de hoy el numeral es un guion, nunca un cero. Separado del
    /// genérico porque aquella cláusula habla de «vital» y promete «rango normal» — pasos no es
    /// lo uno ni tiene lo otro (FER-254).
    private var liquidStepsCampoSinDato: some View {
        LiquidCampoMetrica(
            tono: liquidTono,
            titulo: String(localized: spec.info.name),
            glifo: liquidGlifo,
            datos: [.init(valor: LiquidCajita.sinDato,
                          rotulo: String(localized: "today"),
                          a11y: String(localized: "no data"), ausente: true)],
            clausula: liquidStepsClausulaSinDato
        ) {
            if sinPermiso {
                LiquidVerMas(title: String(localized: "Manage Apple Health permissions"),
                             tone: LiquidColor.papelAlto) { Self.abrirAjustesSalud() }
            }
        }
    }

    /// Cuatro vacíos distintos, no uno: cargando · sin permiso · con historia y sin conteo de
    /// hoy · reuniendo N de 7 días. Mismo árbol que `liquidClausulaSinDato`, en voz de pasos.
    private var liquidStepsClausulaSinDato: String {
        guard loaded else { return String(localized: "Reading your history…") }
        if sinPermiso {
            return String(localized: "Cénit can't read your steps: Apple Health hasn't granted permission. Turn it on and your daily count will show up here.")
        }
        if enoughHistory {
            return String(localized: "No reading from today yet: your recent history is below.")
        }
        return String(localized: "Gathering your days · \(series.count) of 7. Walk a few more days and your daily average and trend will show up here.")
    }

    // MARK: TND-21 · 2. Tu patrón — fin de semana vs entre semana

    /// `LiquidTendenciaCard` (posición y pieza de la familia, A-UX-09) con las MISMAS frases y el
    /// MISMO gate (`stepsMovers != nil`) que `stepsPatronFinalContent` tenía en papel.
    /// T7: el overline es el de la FAMILIA («Lo que vemos en tu historial») — el título-franja
    /// («Qué mueve tus pasos») ya vive en la costura de sección y no se repite aquí.
    @ViewBuilder private var liquidStepsPatronContent: some View {
        if let m = stepsMovers {
            let pctStr = "\(m.pct)%"
            LiquidTendenciaCard(
                overline: String(localized: "What we see in your history"),
                chip: String(localized: "trend, not cause"),
                lineas: [m.weekendHigher
                    ? String(localized: "Your weekends average about \(fmt(m.weekendAvg)) steps: roughly \(pctStr) more than your weekdays.")
                    : String(localized: "Your weekends average about \(fmt(m.weekendAvg)) steps: roughly \(pctStr) fewer than your weekdays.")])
        }
    }

    // MARK: TND-21 · 3. Historial — días completos, escalera del motor, sin joya de «hoy»

    /// Selector + gráfica + resumen + escalera tocable. Paridad `graficaRangosBlock` + FER-264:
    /// la serie trazada lee SOLO días completos (`trendStatRows` tira el parcial de hoy — el borde
    /// derecho no se hunde con la mañana) y se suaviza a 7 días. Hoy vive en el campo, «en curso».
    private func liquidStepsHistoryContent(_ window: MetricWindow) -> some View {
        let rows = trendStatRows(window)
        let plot = SeriesShape.movingAverage(rows.map(\.value), window: 7)
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            if visibleBlocks.contains(.periodSelector) {
                LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                    seleccion: liquidRangeSeleccion, tono: liquidTono)
            }
            if rows.count > 1 {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    // TND20-F3: frase y escalera cuentan LO QUE LA GRÁFICA TRAZA (`plot`).
                    // TND21-1: el ancla (parcial de hoy) NO está en la línea de días completos —
                    // sin «· today» ni carril del parcial; el campo ya carga el parcial arriba.
                    liquidFraseNivelHistorial(window, plot: plot, anclaEnLinea: false)
                    liquidNotaDelta(window)
                    liquidStepsGrafica(rows: rows, plot: plot)
                    LiquidNotaLine(String(localized: "7-day moving average of completed days: today, still adding up, stays out of the line."))
                    LiquidResumenVentana(celdas: liquidStepsResumenCeldas(window))
                }
                .liquidTarjetaSeccion()
                if !liquidBandas.isEmpty {
                    LiquidLevelsList(filas: liquidCarriles(window, plot: plot, anclaEnLinea: false),
                                     tono: liquidTono)
                    LiquidNotaLine(String(localized: "How many days of the period fell in each band. Tap one to see its days on the chart."))
                }
            } else {
                // Un solo día completo o ninguno en el rango → el pozo vacío honesto (calco).
                LiquidGraficaNiveles(puntos: [], bandas: [],
                                     dominio: liquidDominio(plot: []), ticksY: [],
                                     tono: liquidTono,
                                     estadoVacio: liquidEstadoVacio,
                                     a11yLabel: liquidA11yGrafica)
            }
        }
    }

    /// La gráfica del historial de pasos: carriles del motor detrás, ticks en los cortes reales
    /// (5,000 / 10,000) y SIN joya de «hoy» — el último punto trazado es AYER (el parcial de hoy
    /// queda fuera de la línea): vestirlo de «hoy» sería la clase ancla-vieja (TND20-F6).
    private func liquidStepsGrafica(rows: [(day: String, value: Double)],
                                    plot: [Double]) -> some View {
        let puntos = MetricWindowMath
            .decimatedPoints(rows: rows, values: plot, maxPoints: 80)
            .map { (fecha: $0.date, valor: $0.value) }
        return LiquidGraficaNiveles(
            puntos: puntos,
            bandas: liquidBandas.enumerated().map { i, b in
                // TND21-1: el wash sigue SOLO al dedo — el ancla parcial no está en la línea.
                LiquidChartBanda(lo: b.lo, hi: b.hi, color: b.color, activa: i == bandaExplorada)
            },
            dominio: liquidDominio(plot: plot),
            ticksY: liquidTicksY,
            tono: liquidTono,
            puntoHoy: nil,
            formatoScrub: { v, f in "\(fmt(v)) · \(Self.ejeFechaLiquid.string(from: f))" },
            formatoValorScrub: { fmt($0) },
            formatoFechaScrub: { Self.ejeFechaLiquid.string(from: $0) },
            formatoFechaEje: { Self.ejeFechaLiquid.string(from: $0) },
            atenuarFuera: bandaExplorada != nil,
            estadoVacio: liquidEstadoVacio,
            a11yLabel: liquidA11yGrafica)
            .id(range)
    }

    /// El resumen de Pasos: Promedio (crudo, días completos — paridad `averageCell`) · Racha
    /// (días seguidos ≥ tu media de 7 días — el dato del papel que no vive en ningún otro
    /// lado). M1: la celda «Tendencia» MURIÓ — el Δ% vive como nota con signo sobre la
    /// gráfica. HOY y MEDIA 7D no se repiten aquí: ya viven en el campo como numeral y sello.
    private func liquidStepsResumenCeldas(_ window: MetricWindow) -> [LiquidResumenVentana.Celda] {
        let stat = ComparisonEngine.stat(trendStatRows(window).map(\.value))
        var celdas = [LiquidResumenVentana.Celda(rotulo: String(localized: "Average"),
                                                 valor: fmt(stat.mean))]
        if let racha = stepsStreak {
            celdas.append(.init(rotulo: String(localized: "Streak"),
                                valor: racha == 1 ? String(localized: "\(racha) day")
                                                  : String(localized: "\(racha) days")))
        }
        return celdas
    }

    // MARK: - Cuerpo de VO₂max en vidrio Liquid (FER-103 · TND-22)
    //
    // Migración PURAMENTE VISUAL del camino de VO₂max (`vo2maxBodyFinal`, que queda como rollback)
    // sobre los mismos legos que los cuerpos de arriba. Los rasgos PROPIOS de la métrica:
    //
    // · SPARSE MEASURED: Apple lo mide de vez en cuando, no a diario. La gráfica traza los puntos
    //   medidos CRUDOS (paridad `chartBlock`: `chartPlotsRaw` → sin media móvil; el modo rangos
    //   del papel era código muerto inalcanzable y NO se resucita). `info.bands` está VACÍO: sin
    //   escalera, sin `LiquidReadingLine`, sin `LiquidLevelsList`.
    // · ANCLA = LA ÚLTIMA MEDICIÓN, casi nunca de hoy. Honestidad temporal ESTRUCTURAL (la clase
    //   ancla-vieja, TND20-F6): el rótulo del numeral dice «latest measurement», NUNCA «today»;
    //   el sello dice «Measured N days ago» (claves del papel); la joya de la gráfica y el sufijo
    //   del chip solo cuando la medición ES de hoy (`liquidValorFresco`).
    // · NO CALIBRA: sin base personal no hay «N de 7» — con 1 medición ya hay campo y secciones;
    //   el pozo del historial es el único gate (>1 punto para trazar).
    // · VOZ de MEDICIONES: los conteos y vacíos del historial hablan de mediciones, ni días ni
    //   noches — la serie no es un diario.
    // · VOCABULARIO ÚNICO: la categoría (Low/Average/Good/Excellent) sale SOLO de
    //   `VO2maxReference.category` + `vo2maxCategoryWord` — héroe, cajita y frases, una fuente.
    // · Identidad verdePrimario SIN glifo (paridad hoja de Hoy :247/:267); chip de procedencia
    //   calcado de `origenChipVista` (A11, ver `liquidPieMetodo`).

    /// El esqueleto Liquid de VO₂max: campo (ancla) → (ⓘ) → historial → dónde caes → método.
    @ViewBuilder private func vo2maxBodyLiquid(_ window: MetricWindow) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            // El campo enseña la última medición SIEMPRE que exista (hero `.latest`, paridad
            // papel) — la honestidad vive en el rótulo/sello, no en esconder el dato.
            // VIT-03: el primer frame abre con el valor del spec (el del tile), vía el ancla.
            if let v = liquidVo2Ancla {
                liquidVo2CampoConDato(v)
            } else {
                liquidVo2CampoSinDato
            }
            if infoOpen { liquidQueMedimosCard }
            if !loaded {
                LiquidSheetSkeleton(a11yCargando: String(localized: "Reading your history…"))
                    .liquidSeccion()
            } else if !series.isEmpty {
                // (En el vacío total no entra nada aquí: el campo apagado ya lo dice todo —
                // cláusula + sello + CTA — y el pie con chip solo viaja con historia, paridad
                // familia.)
                seccionLiquid(String(localized: "History")) { liquidVo2HistoryContent(window) }
                seccionLiquid(String(localized: "Where you fall")) { liquidVo2DondeCaesContent }
                liquidPieMetodo
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: TND-22 · 1. El campo — la última medición como ancla, sin «hoy» jamás

    /// El campo teñido con dato: numeral = la ÚLTIMA MEDICIÓN («latest measurement», nunca
    /// «today»), veredicto = dónde cae vs lo esperado para tu edad (mismas claves y deadband
    /// que `vo2maxComparison` del papel), y en la ranura libre el sello de honestidad temporal
    /// «Measured N days ago» + la cápsula «Apple» del papel.
    private func liquidVo2CampoConDato(_ v: Double) -> some View {
        LiquidCampoMetrica(
            tono: liquidTono,
            titulo: String(localized: spec.info.name),
            // Sin glifo: el set Liquid no tiene uno para vo2max y la hoja de Hoy lo deja
            // igual (`LiquidMetricSheetView.glifo` :267 — «recovery y vo2max quedan sin
            // glifo»). `LiquidCampoMetrica` ya contempla el campo sin gota (glifo opcional).
            datos: [.init(valor: fmt(v), unidad: unit,
                          rotulo: String(localized: "latest measurement"))],
            veredicto: liquidVo2Veredicto,
            infoAbierto: infoOpen,
            infoEtiqueta: String(localized: "What we measure"),
            onInfo: { withAnimation(LiquidMotion.lift) { infoOpen.toggle() } }
        ) {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                if let s = liquidVo2SelloMedido {
                    LiquidCampoSello(s)
                }
                // FER-487: el dato de HOY vino de Apple — con ancla vieja no se enseña.
                if todayFromApple {
                    LiquidCampoSello(String(localized: "Apple"))
                }
                // VO₂max NO calibra: sin base personal, sin sello «N de 7».
            }
        }
    }

    /// VIT-03 · El ancla del campo de VO₂max: la última medición de la serie, o —solo en el
    /// primer frame, antes de que el `.task` siembre— el valor que el spec ya trae del tile.
    private var liquidVo2Ancla: Double? {
        heroValue ?? (loaded ? nil : liquidSemillaSpec)
    }

    /// El campo APAGADO: sin medición el numeral es un guion. La cláusula conserva el copy del
    /// vacío del papel (`sparseEmptyState`), el título de aquel card vive como sello, y el hint
    /// de conectar Apple Salud (cableado solo para vo2max desde CuerpoView) es el CTA a Ajustes.
    /// VIT-07: SIN PERMISO manda la cláusula de permiso + el CTA de la familia («Manage Apple
    /// Health permissions») ANTES que la cláusula del Watch — la causa real primero.
    private var liquidVo2CampoSinDato: some View {
        LiquidCampoMetrica(
            tono: liquidTono,
            titulo: String(localized: spec.info.name),
            datos: [.init(valor: LiquidCajita.sinDato,
                          rotulo: String(localized: "latest measurement"),
                          a11y: String(localized: "no data"), ausente: true)],
            clausula: liquidVo2ClausulaSinDato
        ) {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                if loaded, !sinPermiso {
                    LiquidCampoSello(String(localized: "No VO₂max yet"))
                }
                if sinPermiso {
                    LiquidVerMas(title: String(localized: "Manage Apple Health permissions"),
                                 tone: LiquidColor.papelAlto) { Self.abrirAjustesSalud() }
                } else if appleConnectHint {
                    // T8: el CTA sin punto final (los CTA de la familia no puntúan).
                    LiquidVerMas(title: String(localized: "Connect Apple Health to see your VO₂max"),
                                 tone: LiquidColor.papelAlto) { Self.abrirAjustesSalud() }
                }
            }
        }
    }

    /// Tres vacíos: cargando · sin permiso (VIT-07, la cláusula de la familia) · sin mediciones
    /// (VO₂max no calibra ni promete rango normal; la explicación del Watch cierra la fila).
    private var liquidVo2ClausulaSinDato: String {
        guard loaded else { return String(localized: "Reading your history…") }
        if sinPermiso {
            return String(localized: "Cénit can't read this vital: Apple Health hasn't granted permission. Turn it on and your readings will show up here.")
        }
        return String(localized: "Your Apple Watch estimates VO₂max during outdoor walks and runs with a good GPS signal.")
    }

    /// Dónde cae la última medición vs la mediana de tu edad/sexo — las MISMAS claves y el mismo
    /// deadband ±1.5 que `vo2maxComparison` (:1711, el papel es el rollback; esta es la voz en
    /// `String` que el campo necesita).
    private var liquidVo2Veredicto: String? {
        guard let v = liquidVo2Ancla, let exp = vo2maxExpected else { return nil }
        if v > exp + 1.5 { return String(localized: "Above what's expected for your age.") }
        if v < exp - 1.5 { return String(localized: "Below what's expected for your age.") }
        return String(localized: "In line with what's expected for your age.")
    }

    /// «Measured today / yesterday / N days ago» — el ancla temporal, con las claves del papel
    /// (:848-862, que queda como rollback).
    ///
    /// TND22-1: el delta sale de las MISMAS llaves de día que compara `liquidValorFresco`
    /// (ambas parseadas en UTC, diferencia en calendario UTC). Mezclar `parseDayKey` (UTC
    /// medianoche) con `Calendar.current.startOfDay` local corría el sello +1 al oeste de
    /// UTC: una medición de HOY decía «Measured yesterday» junto a una joya encendida
    /// (la clase fila-fantasma UTC↔local que `MetricTrendChart` ya documenta).
    private var liquidVo2SelloMedido: String? {
        guard let day = series.last?.day, let date = Repository.parseDayKey(day),
              let hoy = Repository.parseDayKey(todayKey ?? Repository.localDayKey(Date()))
        else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.dateComponents([.day], from: date, to: hoy).day, d >= 0 else { return nil }
        switch d {
        case 0:  return String(localized: "Measured today")
        case 1:  return String(localized: "Measured yesterday")
        default: return String(localized: "Measured \(d) days ago")
        }
    }

    // MARK: TND-22 · 2. Historial — puntos medidos crudos, sin escalera, con las dos anclas

    /// Selector + gráfica cruda + las dos anclas del papel como `LiquidNotaLine` (paridad
    /// gemelas: BarraAncla → NotaLine). Sin `LiquidResumenVentana`: el papel no tenía celdas
    /// de resumen para vo2max y no se inventan.
    private func liquidVo2HistoryContent(_ window: MetricWindow) -> some View {
        // sparseMeasured: se traza la serie CRUDA de la ventana (paridad `chartBlock`).
        let plot = window.values
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            if visibleBlocks.contains(.periodSelector) {
                LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                    seleccion: liquidRangeSeleccion, tono: liquidTono)
            }
            if plot.count > 1 {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    // Voz de MEDICIONES; con fallback la frase mentiría («N en este rango»
                    // cuando el rango elegido está vacío), así que la nota honesta la releva.
                    if window.fellBack {
                        LiquidNotaLine(String(localized: "No measurements in this range: showing your most recent \(window.rows.count)."),
                                       tono: LiquidColor.atencionTexto)
                    } else {
                        LiquidFraseNivel(nivel: nil,
                                         conteo: String(localized: "\(plot.count) measurements in this range"),
                                         tono: liquidTono)
                    }
                    liquidVo2Grafica(window, plot: plot)
                    // La leyenda del papel para sparse (`chartCaption` :1511): puntos crudos.
                    LiquidNotaLine(String(localized: "Measured values."))
                }
                .liquidTarjetaSeccion()
            } else {
                // 1 medición o el rango elegido vacío sin dónde ensanchar → pozo honesto.
                LiquidGraficaNiveles(puntos: [], bandas: [],
                                     dominio: liquidDominio(plot: []), ticksY: [],
                                     tono: liquidTono,
                                     estadoVacio: String(localized: "Not enough measurements in this range to draw a trend."),
                                     a11yLabel: liquidA11yGrafica)
            }
            liquidVo2Anclas
        }
    }

    /// La BarraAncla de referencia del papel dicha en NotaLine, bajo la tarjeta (la posición
    /// de las notas post-tarjeta de la familia). B5: la nota «Measured N days ago» MURIÓ aquí
    /// — el sello del campo ya la carga; decirla dos veces era la duplicación.
    @ViewBuilder private var liquidVo2Anclas: some View {
        if let exp = vo2maxExpected {
            LiquidNotaLine(String(localized: "Expected for your age: ~\(Int(exp.rounded()))"))
        }
    }

    /// La gráfica del historial: puntos medidos crudos, SIN carriles (info.bands vacío), y la
    /// joya de «hoy» SOLO si la última medición es literalmente de hoy (TND20-F6).
    private func liquidVo2Grafica(_ window: MetricWindow, plot: [Double]) -> some View {
        let puntos = MetricWindowMath
            .decimatedPoints(rows: window.rows, values: plot, maxPoints: 80)
            .map { (fecha: $0.date, valor: $0.value) }
        return LiquidGraficaNiveles(
            puntos: puntos,
            bandas: [],
            dominio: liquidDominio(plot: plot),
            ticksY: liquidVo2TicksY(plot: plot),
            tono: liquidTono,
            puntoHoy: liquidValorFresco != nil ? puntos.last : nil,
            formatoScrub: { v, f in "\(fmt(v)) · \(Self.ejeFechaLiquid.string(from: f))" },
            formatoValorScrub: { fmt($0) },
            formatoFechaScrub: { Self.ejeFechaLiquid.string(from: $0) },
            formatoFechaEje: { Self.ejeFechaLiquid.string(from: $0) },
            estadoVacio: String(localized: "Not enough measurements in this range to draw a trend."),
            a11yLabel: liquidA11yGrafica)
            .id(range)
    }

    /// Los ticks del eje: sin cortes de motor (info.bands vacío), afirman los EXTREMOS medidos
    /// reales de la ventana (el mismo papel que los bordes del dominio clínico juegan en SpO₂,
    /// `liquidTicksY`) — presentación, cero matemática nueva.
    private func liquidVo2TicksY(plot: [Double]) -> [(valor: Double, etiqueta: String)] {
        guard let lo = plot.min(), let hi = plot.max(), hi > lo else { return [] }
        return [(hi, fmt(hi)), (lo, fmt(lo))]
    }

    // MARK: TND-22 · 3. Dónde caes — categoría + edad equivalente, calco «Estabilidad térmica»

    /// `LiquidCajitaGrid` (calco `SkinTempDetailScreen.thermalBlock` :513-525) + el copy de
    /// longevidad y sus citas INTACTOS como notas del bloque (la posición de las notas de hedge
    /// del patrón espectral/térmico) — visibles sin desplegar, como en el papel; el método del
    /// pie carga además su propia versión con FRIEND/Kaminsky (catálogo, sin cambios).
    @ViewBuilder private var liquidVo2DondeCaesContent: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            if let v = heroValue, let profile = spec.vo2maxProfile {
                // VOCABULARIO ÚNICO: la categoría sale SOLO de `VO2maxReference` +
                // `vo2maxCategoryWord` — la misma fuente que usaba el papel.
                let active = VO2maxReference.category(value: v, age: profile.age, sex: profile.sex)
                let eq = VO2maxReference.equivalentAge(value: v, sex: profile.sex)
                LiquidCajitaGrid {
                    // La PALABRA de juicio en tinta neutra (calco SkinTemp: «el verde/ámbar de
                    // juicio del papel no cruza al vidrio»); el número lleva el tono.
                    // B2: rótulos en sentence case (las claves CAPS quedan solo en el rollback).
                    LiquidCajita(rotulo: String(localized: "Fitness category"),
                                 valor: vo2maxCategoryWord(active),
                                 compacto: true)
                    LiquidCajita(rotulo: String(localized: "Equivalent age"),
                                 valor: "~\(eq)",
                                 tono: liquidTono,
                                 compacto: true)
                }
            }
            LiquidNotaLine(String(localized: "A higher VO₂max is associated with a lower risk of all-cause mortality. It's one of the best-evidenced predictors of long-term health."),
                           tono: LiquidColor.tinta700)
            LiquidNotaLine(String(localized: "Mandsager 2018 (JAMA) · Kodama 2009"))
        }
    }

    // MARK: - Cuerpo intradía de FC en vidrio Liquid (FER-103 · TND-23)
    //
    // Migración PURAMENTE VISUAL del camino intradía (`narrativeIntradayFinal`, que queda como
    // rollback) — el ÚLTIMO cuerpo de papel del archivo. Los rasgos PROPIOS de la métrica:
    //
    // · INTRADÍA ES HOY por definición: no hay ancla vieja que vestir ni serie diaria (el
    //   caller inyecta `seriesLoader: { [] }`), así que aquí no aplican `liquidValorFresco`
    //   ni el pie genérico (`liquidPieMetodo` gatea en `series`) — el intradía tiene el suyo.
    //   Pero SIN lecturas hoy el campo va apagado («No readings yet today.», clave de la
    //   familia) y NADA dice «en curso» sobre un guion.
    // · Sin selector de rango, sin escalera, sin calendario: el papel tampoco los tenía.
    // · Identidad rosa/.corazon — el MISMO par que la hoja de Hoy (`LiquidMetricSheetView.tono`
    //   :231 / `.glifo` :264); el vidrio de la curva es LA MISMA pieza (`LiquidCurvaFC`) con
    //   el MISMO vocabulario («Beats per minute», «5-minute average · since midnight»,
    //   Min/Avg/Max), extendida en TND-23 con la referencia (FC en reposo) y el pico marcado
    //   que el papel dibujaba (`TrendChart` referenceLine/markedPoint) — cero pérdida.
    // · HORAS CIVILES del reloj local (`Self.hrClock`, paridad papel): la curva vive en el
    //   día del teléfono, sin llaves UTC.
    // · Zonas: `LiquidTiempoZonas` (FER-99, su PRIMER cliente) sobre `cachedZoneMinutes`
    //   (el cálculo en `Task.detached` queda INTACTO, A14). La pieza arregla el pecado del
    //   papel (`mins[i] >= 1` borraba una zona en cero), así que el gate del papel («algún
    //   mins[1...] > 0») MUERE: un día todo-reposo enseña la barra llena de reposo y los
    //   cinco rieles vacíos — el estado honesto que la pieza existe para dibujar (su preview
    //   «Zonas · día en reposo» es exactamente esto, firmado en el DS).
    // · Sello de origen: «Apple Health» (el vocabulario de la hoja: `origen` cae a
    //   `.appleSalud` para heart_rate), sufijo «today, in progress» (clave del papel) SOLO
    //   con lecturas hoy — M2: nunca procedencia sobre un guion.

    /// El esqueleto Liquid del intradía: campo → (ⓘ) → Tu día → zonas → método.
    @ViewBuilder private var intradayBodyLiquid: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            // VIT-03: el primer frame abre con la media que el spec ya trae del tile.
            if let v = liquidIntraAncla {
                liquidIntraCampoConDato(v)
            } else {
                liquidIntraCampoSinDato
            }
            if infoOpen { liquidQueMedimosCard }
            if !loaded {
                LiquidSheetSkeleton(a11yCargando: String(localized: "Reading your history…"))
                    .liquidSeccion()
            } else {
                if intradayCurve.count > 1 {
                    seccionLiquid(String(localized: "Your day")) { liquidIntraCurvaContent }
                    if let mins = cachedZoneMinutes {
                        seccionLiquid(String(localized: "Time in zones · today")) {
                            liquidIntraZonasContent(mins)
                        }
                    }
                }
                // Sin lecturas el campo apagado ya lo dice todo (paridad familia: vo2max /
                // narrativo tampoco montan el pie sin datos). Con lecturas, método + sello.
                if !intradayCurve.isEmpty {
                    liquidIntraPieMetodo
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: TND-23 · 1. El campo — la media de hoy, siempre «en curso»

    /// VIT-03 · El ancla del campo intradía: la media de la curva, o —solo en el primer
    /// frame, antes de que el `.task` siembre— la media que el spec ya trae del tile.
    private var liquidIntraAncla: Double? {
        intradayAverage ?? (loaded ? nil : liquidSemillaSpec)
    }

    /// El campo teñido con dato: numeral = la MEDIA de hoy (el mismo `heroTodayValue` →
    /// `intradayAverage` del papel) y en la ranura libre «en curso» — el día corre SIEMPRE
    /// en intradía (paridad héroe de papel :914) — más la cápsula «Apple» si el caller la
    /// declarara (hoy nunca para heart_rate; el `if` es paridad de familia, no promesa).
    /// VIT-08: el veredicto «min · max · resting» MURIÓ — el caption y las stats de la
    /// curva ya cargan esas tres cifras; decirlas dos veces era la duplicación.
    private func liquidIntraCampoConDato(_ v: Double) -> some View {
        LiquidCampoMetrica(
            tono: liquidTono,
            titulo: String(localized: spec.info.name),
            glifo: liquidGlifo,
            datos: [.init(valor: fmt(v), unidad: unit,
                          rotulo: String(localized: "today"))],
            infoAbierto: infoOpen,
            infoEtiqueta: String(localized: "What we measure"),
            onInfo: { withAnimation(LiquidMotion.lift) { infoOpen.toggle() } }
        ) {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                LiquidCampoSello(String(localized: "in progress"))
                if todayFromApple {
                    LiquidCampoSello(String(localized: "Apple"))
                }
            }
        }
    }

    /// El campo APAGADO: sin lecturas hoy el numeral es un guion, nunca un cero, y nada
    /// dice «en curso». Tres vacíos, no uno: cargando · sin permiso · sin lecturas hoy
    /// (el intradía no calibra ni tiene «historia abajo» — la curva ES el dato).
    private var liquidIntraCampoSinDato: some View {
        LiquidCampoMetrica(
            tono: liquidTono,
            titulo: String(localized: spec.info.name),
            glifo: liquidGlifo,
            datos: [.init(valor: LiquidCajita.sinDato,
                          rotulo: String(localized: "today"),
                          a11y: String(localized: "no data"), ausente: true)],
            clausula: liquidIntraClausulaSinDato
        ) {
            if sinPermiso {
                LiquidVerMas(title: String(localized: "Manage Apple Health permissions"),
                             tone: LiquidColor.papelAlto) { Self.abrirAjustesSalud() }
            }
        }
    }

    private var liquidIntraClausulaSinDato: String {
        guard loaded else { return String(localized: "Reading your history…") }
        if sinPermiso {
            return String(localized: "Cénit can't read this vital: Apple Health hasn't granted permission. Turn it on and your readings will show up here.")
        }
        return String(localized: "No readings yet today.")
    }

    // MARK: TND-23 · 2. Tu día — la curva de la hoja + referencia y pico del papel

    /// `LiquidCurvaFC` con el MISMO cableado que la hoja de Hoy (`heartRateBlock` :991) más
    /// los dos contextos del papel: la FC en reposo como punteada (`referencia`) y el pico
    /// como joya (`puntoMarcado`). El caption pico/reposo del papel va debajo, mismas claves.
    @ViewBuilder private var liquidIntraCurvaContent: some View {
        let values: [Double] = intradayCurve.map(\.value)
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCurvaFC(
                titulo: String(localized: "Beats per minute"),
                subtitulo: String(localized: "5-minute average · since midnight"),
                ultimo: values.last.map { String(localized: "\(Int($0.rounded())) bpm") },
                puntos: intradayCurve.map { (fecha: $0.date, valor: $0.value) },
                // El dominio del papel: aire del 12 % y ensanchado hasta la FC en reposo,
                // para que la punteada de referencia siempre caiga dentro.
                dominio: Self.hrRange(values, resting: restingHR),
                referencia: restingHR,
                puntoMarcado: peakPoint.map { (fecha: $0.date, valor: $0.value) },
                stats: liquidIntraStats(values),
                statsEtiquetas: (min: String(localized: "Min"),
                                 prom: String(localized: "Avg"),
                                 max: String(localized: "Max")),
                ticksY: liquidIntraTicksY(values),
                formatoScrub: { (v: Double, f: Date) in
                    "\(String(localized: "\(Int(v.rounded())) bpm")) · \(Self.hrScrubHora.string(from: f))"
                },
                formatoValorScrub: { (v: Double) in String(localized: "\(Int(v.rounded())) bpm") },
                formatoFechaScrub: { (d: Date) in Self.hrScrubHora.string(from: d) },
                formatoFechaEje: { (d: Date) in Self.hrEjeHora.string(from: d) },
                estado: .datos,
                a11yLabel: String(localized: "Today's heart rate, 5-minute averages"))
            liquidIntraCaption
        }
        .liquidTarjetaSeccion()
    }

    /// B1 · Los DOS formateadores por PLANTILLA de la hoja de Hoy (:866-873) — el eje solo la
    /// hora («7 a. m.», template "ha"), el scrub hora y minuto en el ciclo del locale
    /// (template "jmm": recupera los minutos que el reloj duro «h a» perdía). `hrClock`
    /// (dateFormat duro) queda para el papel rollback.
    private static let hrEjeHora: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("ha"); return f
    }()
    private static let hrScrubHora: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("jmm"); return f
    }()

    /// «Pico 142 lpm · 6 p. m. · Reposo 52» — el caption del papel (`peakRestingCaption`),
    /// mismas claves, dicho como nota de la familia (hora del pico en el reloj del locale, B1).
    @ViewBuilder private var liquidIntraCaption: some View {
        if let peak = peakPoint {
            let pico = String(localized: "Peak \(Int(peak.value.rounded())) bpm · \(Self.hrEjeHora.string(from: peak.date))")
            if let rest = restingHR {
                LiquidNotaLine("\(pico) · \(String(localized: "Resting \(Int(rest.rounded()))"))")
            } else {
                LiquidNotaLine(pico)
            }
        }
    }

    /// Min / prom / max YA formateados (calco `hrStats` de la hoja / `intradayCurveStatsRow`
    /// del papel — mismas cifras, cero matemática nueva).
    private func liquidIntraStats(_ v: [Double]) -> (min: String, prom: String, max: String)? {
        guard !v.isEmpty else { return nil }
        let lo: Double = v.min() ?? 0
        let hi: Double = v.max() ?? 0
        let avg: Double = v.reduce(0, +) / Double(Swift.max(v.count, 1))
        return (min: "\(Int(lo.rounded()))",
                prom: "\(Int(avg.rounded()))",
                max: "\(Int(hi.rounded()))")
    }

    /// Tres marcas sobre los DATOS (mín · medio · máx en latidos enteros, calco del
    /// `ticksY(_:cuanto:1)` de la hoja): los bordes del dominio son puro respiro y
    /// etiquetarlos imprimiría valores que nunca ocurrieron.
    private func liquidIntraTicksY(_ v: [Double]) -> [(valor: Double, etiqueta: String)] {
        guard let lo = v.min(), let hi = v.max(), hi > lo else { return [] }
        let qLo = lo.rounded(), qHi = hi.rounded(), qMedio = ((lo + hi) / 2).rounded()
        var valores: [Double] = [qLo]
        if qMedio > qLo && qMedio < qHi { valores.append(qMedio) }
        if qHi > qLo { valores.append(qHi) }
        return valores.map { (v: Double) -> (valor: Double, etiqueta: String) in
            (valor: v, etiqueta: "\(Int(v))")
        }
    }

    // MARK: TND-23 · 3. Tiempo en zonas — LiquidTiempoZonas sobre los minutos cacheados

    /// Titular «138 min elevated (zone 3+)» (mismas claves y misma suma que el papel) +
    /// la pieza de zonas + la nota Tanaka. Sin tarjeta: la pieza no trae marco propio y la
    /// sección la enmarca (contrato de `LiquidTiempoZonas`; mismo trato que el espectral).
    @ViewBuilder private func liquidIntraZonasContent(_ mins: [Double]) -> some View {
        let elevated = Int((mins[3] + mins[4] + mins[5]).rounded())
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
                Text(verbatim: "\(elevated)")
                    .font(LiquidType.valorTileL)
                    .tracking(LiquidType.valorTileTracking)
                    .foregroundStyle(liquidTono)
                Text(String(localized: "min elevated (zone 3+)"))
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta700)
            }
            LiquidTiempoZonas(
                zonas: liquidIntraZonas(mins),
                a11yLabel: String(localized: "Time in zones · today"),
                // Vacío a propósito: la pieza deriva el reparto por ciento de las MISMAS
                // partes que dibuja — una sola fuente, cero copy nuevo.
                a11yValue: "")
            LiquidNotaLine(String(localized: "Zones as a percentage of your max heart rate (\(Int(hrMax.rounded())) bpm, Tanaka). The rest of the day you were resting or very light."))
        }
    }

    /// Las 6 zonas SIEMPRE (contrato de la pieza): minutos medidos (jamás `nil` aquí — la
    /// curva existe si llegamos), etiqueta con las claves del papel + el reposo, y el
    /// detalle «N min» que la leyenda de papel ponía a la derecha.
    private func liquidIntraZonas(_ mins: [Double]) -> [LiquidTiempoZonas.Zona] {
        (0..<6).map { i in
            let m: Double = i < mins.count ? mins[i] : 0
            return LiquidTiempoZonas.Zona(
                id: i,
                etiqueta: liquidIntraZonaEtiqueta(i),
                minutos: m,
                color: Self.liquidZonaRampa(i, tono: liquidTono),
                detalle: String(localized: "\(Int(m.rounded())) min"))
        }
    }

    /// Las MISMAS claves que `zoneLabel` (papel) para Z1…Z5; el reposo — que el papel
    /// nunca rotulaba porque su leyenda lo filtraba — estrena la suya con el patrón de
    /// la familia («Reposo · bajo zona 1»).
    private func liquidIntraZonaEtiqueta(_ i: Int) -> String {
        switch i {
        case 0:  return String(localized: "Rest · below zone 1")
        case 1:  return String(localized: "Zone 1 · very light")
        case 2:  return String(localized: "Zone 2 · light")
        case 3:  return String(localized: "Zone 3 · moderate")
        case 4:  return String(localized: "Zone 4 · hard")
        default: return String(localized: "Zone 5 · max")
        }
    }

    /// La rampa de zona en el hue de identidad: reposo en tinta quieta y las cinco zonas
    /// graduando el rosa, más oscuro = más duro — calco del `zoneFill` de papel (misma
    /// geometría de opacidades) dicho en tokens Liquid, y el MISMO reparto que la preview
    /// de `LiquidTiempoZonas` documenta (el DS no conoce zonas de pulso: la rampa es del
    /// caller). Estática para poder fijarla en un test sin montar la pantalla.
    static func liquidZonaRampa(_ i: Int, tono: Color) -> Color {
        switch i {
        case 0:  return LiquidColor.tinta10
        case 1:  return tono.opacity(0.35) // token-exempt: rampa de intensidad de zona (geometría de dato)
        case 2:  return tono.opacity(0.5)  // token-exempt: rampa de intensidad de zona (geometría de dato)
        case 3:  return tono.opacity(0.65) // token-exempt: rampa de intensidad de zona (geometría de dato)
        case 4:  return tono.opacity(0.82) // token-exempt: rampa de intensidad de zona (geometría de dato)
        default: return tono
        }
    }

    // MARK: TND-23 · 4. Método + sello — rama intradía del pie

    /// El pie del intradía: método del catálogo (Tanaka) + el chip de procedencia en el
    /// vocabulario de la hoja («Apple Health» — `LiquidMetricSheetView.origen` cae a
    /// `.appleSalud` para heart_rate) con el sufijo del papel «today, in progress» SOLO
    /// cuando hay lecturas hoy (paridad `pieMetodoIntradayFinal`: el sello gateaba en
    /// `intradayCurve.count > 1`; M2: nunca procedencia sobre un guion).
    private var liquidIntraPieMetodo: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            if visibleBlocks.contains(.method), let method = spec.info.method {
                LiquidMetodo(title: String(localized: "How it's calculated"),
                             mostrar: String(localized: "Show explanation"),
                             ocultar: String(localized: "Hide explanation")) {
                    LiquidNotaLine(String(localized: method.prose), tono: LiquidColor.tinta700)
                    if let citation = method.citation {
                        LiquidNotaLine(String(localized: citation))
                    }
                }
            }
            if intradayCurve.count > 1 {
                // VIT-10: la marca de PROCEDENCIA de la hoja (corazón/rosa), no el glifo/hue
                // de la métrica; el sufijo temporal del papel se conserva (M2 > «on your device»).
                LiquidOrigenChip(glyph: .corazon, badgeTono: LiquidColor.rosa,
                                 etiqueta: String(localized: "Apple Health"),
                                 sufijo: String(localized: "today, in progress"))
            }
        }
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

}


// MARK: - Preview

#if DEBUG
private func sampleVitalSeries(base: Double, swing: Double, days: Int = 40) -> [(day: String, value: Double)] {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let f = MetricDetailScreen.dayParser
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = base + swing * sin(Double(i) / 4.0) + Double((i * 13) % 5) - 2
        return (f.string(from: date), max(1, v))
    }
}

#Preview("MetricDetailScreen: HRV (full)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .hrv(64),
            depth: .full,
            seriesLoader: { sampleVitalSeries(base: 58, swing: 12) },
            nightVitalsLoader: { .init(respiration: 14.6, restingHR: 52) }
        )
    }
}

#Preview("MetricDetailScreen: HRV (focus)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .hrv(64),
            depth: .focus,
            seriesLoader: { sampleVitalSeries(base: 58, swing: 12) },
            nightVitalsLoader: { .init(respiration: 14.6, restingHR: 52) }
        )
    }
}

#Preview("MetricDetailScreen: Resting HR (full)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .restingHR(54),
            depth: .full,
            seriesLoader: { sampleVitalSeries(base: 54, swing: 4) }
        )
    }
}

#Preview("MetricDetailScreen: Respiratory (full)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .respiratory(14.8),
            depth: .full,
            seriesLoader: { sampleVitalSeries(base: 14.5, swing: 1.2) },
            nightVitalsLoader: { .init(respiration: 14.8, restingHR: 54) }
        )
    }
}

#Preview("MetricDetailScreen: Steps (full)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .steps(4_820),
            depth: .full,
            todayFromApple: true,
            seriesLoader: { sampleVitalSeries(base: 8_200, swing: 2_600) },
            todayKey: MetricDetailScreen.dayParser.string(from: Date())
        )
    }
}

private func sampleHRCurve() -> [TrendPoint] {
    let cal = Calendar(identifier: .gregorian)
    let midnight = cal.startOfDay(for: Date())
    return (0..<200).map { i in
        let t = midnight.addingTimeInterval(Double(i) * 300)
        let base = 60.0 + 26.0 * sin(Double(i) / 18.0) + Double((i * 7) % 9)
        let spike = (i > 150 && i < 162) ? 60.0 : 0
        return TrendPoint(date: t, value: max(48, base + spike))
    }
}

#Preview("MetricDetailScreen: Heart Rate (full)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .heartRate(68),
            depth: .full,
            seriesLoader: { [] },
            intradayCurveLoader: { sampleHRCurve() },
            hrMax: 188,
            restingHR: 52
        )
    }
}

#Preview("MetricDetailScreen: Heart Rate (no readings)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .heartRate(nil),
            depth: .full,
            seriesLoader: { [] },
            intradayCurveLoader: { [] },
            hrMax: 188
        )
    }
}

#Preview("MetricDetailScreen: HRV (calibrating)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .hrv(nil),
            depth: .full,
            seriesLoader: { Array(sampleVitalSeries(base: 58, swing: 12).suffix(1)) }
        )
    }
}

#Preview("MetricDetailScreen: SpO₂ (full)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .spo2(97),
            depth: .full,
            todayFromApple: true,
            seriesLoader: { sampleVitalSeries(base: 96.5, swing: 1.2).map { ($0.day, min($0.value, 100)) } }
        )
    }
}

/// VO₂max se mide RALO (cada tantos días), no a diario — la muestra respeta esa cadencia.
private func sampleVO2maxSeries() -> [(day: String, value: Double)] {
    sampleVitalSeries(base: 41, swing: 2, days: 120).enumerated()
        .filter { $0.offset % 9 == 0 }
        .map { $0.element }
}

#Preview("MetricDetailScreen: VO₂max (full)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .vo2max(value: 41, age: 34, sex: "male"),
            depth: .full,
            seriesLoader: { sampleVO2maxSeries() }
        )
    }
}

#Preview("MetricDetailScreen: Resting HR (sin permiso)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricDetailScreen(
            spec: .restingHR(nil),
            depth: .full,
            seriesLoader: { [] },
            sinPermiso: true
        )
    }
}
#endif
#endif
