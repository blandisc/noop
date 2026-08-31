#if os(iOS)
import SwiftUI
import Foundation
import StrandDesign
import StrandAnalytics
import CenitStore

// MARK: - Explore (Metric Explorer + Detail) — en vidrio «Liquid Glass» (FER-104 · TND-31)
//
// The catalog-driven "Explore" surface, migrated from the light «Instrumento» paper to the Liquid
// Glass language, sibling to Compare (TND-30) and the vital detail (TND-19/20). The root is a
// categorized picker — one section per `MetricCatalog.category`, its rows `LiquidListRow`s on a
// solid card, each pushing a GENERIC detail. The detail is a uniform analytic dossier for ANY of
// the ~35 catalog metrics: a tinted Liquid hero (`LiquidCampoMetrica`), a raw-line history
// (`LiquidGraficaNiveles` + `LiquidResumenVentana`), the cross-catalog Pearson «What correlates»
// as protagonist #2, and a method+provenance foot.
//
// A17 (architecture, co-decided): the Explorer migrates its OWN `MetricDetailView` IN PLACE to a
// generic Liquid detail — it does NOT route to `MetricDetailScreen`. The 7 rich metrics keep
// opening `MetricDetailScreen` from Hoy/Cuerpo; from the Explorer, ALL 35 open this generic
// dossier. The NavigationStack push is conserved (the Explorer's contract, distinct from the
// sheet/overlay of the rich screens).
//
// THE MIGRATION IS SKIN, NOT THREAD (FER-104): the data path is conserved verbatim from the paper
// screen — the shared `MetricSeriesResolver` for every series (TND-29), the memoized window math
// (FER-269), and the OFF-MAIN cross-catalog Pearson scan with reattach-by-id (FER-976). What
// changed is every surface, plus the three invariants TND-29 exists to fix:
//   • COLOR IS IDENTITY, per metric — `MetricIdentity.hue(for:)`, never the rival `metricAccent`
//     map (deleted here). Each dot/field/chart/correlate wears its family's hue on every screen.
//   • NAME IS CANONICAL — `canonicalTitle` says «Effort», never «Day Strain» (HJ-13).
//   • A negative correlation is NOT an alarm (TND30-4): the sign rides the leading «−» and the
//     side of the zero axis, never a red/green colour. The r bar wears the correlate's IDENTITY
//     hue; the value stays neutral ink.
//
// CORRELATION ROW — the bar is composed IN-LINE, not coined as a DS piece (DS rule §7: a single
// call-site composition stays atoms in the screen, the same choice Compare made for its pairCard).
// Neither declared option fit: `LiquidBarrasContribucion` carries a Body-Age good/bad colour
// convention (green for negative, amber for positive) that directly contradicts TND30-4, and
// coining `LiquidFilaCorrelacion` for one call site violates DS §7. So the zero-axis r bar is a
// handful of shapes here, honest for r∈[−1,1] (magnitude = |r|, side = sign, hue = identity).

/// "9 Jun 2026" — long date for the hero "as of" line, in the user's language (days are UTC-keyed,
/// so the zone stays pinned).
private let longDateFmt: DateFormatter = {
    let f = DateFormatter()
    f.locale = .autoupdatingCurrent
    f.timeZone = TimeZone(identifier: "UTC")
    f.setLocalizedDateFormatFromTemplate("d MMM y")
    return f
}()
private func longDate(_ d: Date) -> String { longDateFmt.string(from: d) }

// `originVocabulary(_:)` + `metricIsCalculated(_:)` now live in CompareView.swift (unguarded, shared
// by both instruments): the origin label speaks the Hoy sheet's CLOSED vocabulary — «Apple Health» /
// «Apple Watch» / «Calculated on your phone» — instead of the raw catalog tag (C-16). Used here as
// the catalog row subtitle and the detail's provenance chip label; the chip keeps its identity
// glyph/hue and only the text changes.

// MARK: - On-device series resolver / range
//
// Explore shares `MetricSeriesResolver` (`Cenit/Data/MetricSeriesResolver.swift`) with Compare so a
// catalog key resolves to the SAME number on both screens (TND-29). The W/M/3M/6M/1Y/ALL window
// lives in `ExploreRange` + `MetricWindowMath` (FER-269), shared by every drill-down.

// MARK: - Root: categorized picker

/// The "Explore" picker in Liquid — categories as inset sections, metrics as `LiquidListRow`s on a
/// solid card, each pushing the generic `MetricDetailView`. A metric with no series at all is flagged
/// in the a11y hint only ("No data"), never as a visible trailing word (TND31-3).
struct MetricExplorerView: View {
    @EnvironmentObject var repo: Repository
    /// metric.id → whether its series is empty (loaded once, lazily).
    @State private var emptyByID: [String: Bool] = [:]

    // No NavigationStack here: Explore is pushed inside the sheet's own stack (CuerpoView). A nested
    // NavigationStack crossing this view's MetricDescriptor values crashed SwiftUI — FER-171. The
    // catalog list + its `.navigationDestination(for: MetricDescriptor.self)` hang off that stack.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s550) {
                header
                ForEach(MetricCatalog.categories, id: \.self) { category in
                    let metrics = MetricCatalog.inCategory(category)
                    if !metrics.isEmpty {
                        categorySection(category, metrics: metrics)
                    }
                }
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background { LiquidSheetFondo().ignoresSafeArea() }
        // The Explorer has no single subject to tint — a neutral warm-paper backdrop, like Compare's
        // neutral picker. Set on the sheet so its gutters match the scroll ground.
        .presentationBackground { LiquidSheetFondo() }
        .navigationDestination(for: MetricDescriptor.self) { metric in
            MetricDetailView(metric: metric)
        }
        .task { await probeEmptiness() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text(String(localized: "Explore"))
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "Every signal, one tap deep."))
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// One category: an inset overline + count (the picker carries its count like Compare's blocks,
    /// not an a-sangre franja — that voice belongs to the read-only detail), then its rows on ONE
    /// solid card, hairline-divided by `LiquidListRow`'s own divider.
    private func categorySection(_ category: String, metrics: [MetricDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .firstTextBaseline) {
                Text(MetricCatalog.localizedCategory(category))
                    .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: LiquidSpace.s200)
                Text(verbatim: "\(metrics.count)")
                    .font(LiquidType.filaConteo).foregroundStyle(LiquidColor.tinta500)
            }
            VStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { idx, metric in
                    NavigationLink(value: metric) {
                        LiquidListRow(
                            title: metric.canonicalTitle,
                            subtitle: originVocabulary(metric),
                            // «No data» is a11y-ONLY (TND31-3): the paper flagged an empty metric with a
                            // quiet dot, never the WORD. `LiquidListRow`'s only trailing slot is a String
                            // that VoiceOver speaks, and adding a visual-only dot slot is a DS redesign out
                            // of scope here — so the flag lives in the a11y hint, the trailing stays the
                            // bare chevron (spec's fallback). Only for a metric with no series (probeEmptiness).
                            tone: MetricIdentity.hue(for: metric),
                            a11yHint: (emptyByID[metric.id] ?? false) ? String(localized: "No data") : nil,
                            divider: idx < metrics.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .liquidTarjetaSeccion(padding: LiquidSpace.s300)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One lightweight pass to learn which metrics have no series, so rows can flag them. A metric
    /// has data if the on-device dashboard computes it (BLE users) OR it was imported (FER-281). One
    /// index-only `DISTINCT key` query per source (FER-27). Uses the SHARED resolver (TND-29).
    private func probeEmptiness() async {
        guard emptyByID.isEmpty else { return }
        let dash = repo.displayDays
        let keysBySource = await repo.availableKeySets(sources: MetricCatalog.all.map(\.source))
        var map: [String: Bool] = [:]
        for metric in MetricCatalog.all {
            let onDevice = !(MetricSeriesResolver.dashboardSeries(metric.key, from: dash) ?? []).isEmpty
            let imported = keysBySource[metric.source]?.contains(metric.key) ?? false
            map[metric.id] = !(onDevice || imported)
        }
        emptyByID = map
    }
}

// MARK: - Detail / drill-down (generic Liquid dossier)

/// The uniform analytic dossier for ANY catalog metric in Liquid: a tinted hero
/// (`LiquidCampoMetrica`, identity per metric), a raw-line history (`LiquidGraficaNiveles` +
/// `LiquidResumenVentana`), the cross-catalog Pearson «What correlates», and a method+provenance
/// foot. Serves the ~35 metrics: the ~7 with a canonical hue read from the identity bridge, the
/// rest fall to `verdePrimario` with no glyph (TND-29's documented fallback).
struct MetricDetailView: View {
    let metric: MetricDescriptor
    @EnvironmentObject var repo: Repository
    /// Drives the correlation row's AX-size stacking (TND31-1), the same lever CompareView.pairCard uses.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Imperial/Metric display preference (D#103). Display-only: weight (kg) and skin temp (°C)
    // re-label; everything else is unit-agnostic and renders unchanged.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw)
    }
    private func fmt(_ v: Double) -> String { metric.format(v, system: unitSystem, temperature: temperatureUnit) }

    /// The displayed number for `v` WITHOUT its unit (TND31-2). The generic detail's `fmt` folds
    /// number+unit into one string, so the range extremes had to be built from `fmt` and doubled the
    /// unit («68 %–76 %»). This mirrors the sibling `MetricDetailScreen`, which keeps a bare `fmt`
    /// number and a separate `unit` suffix — the extremes join as bare numbers and the unit prints
    /// ONCE. The two SI units with an imperial form convert here too (kg → kg/lb at one decimal, like
    /// `UnitFormatter.massFromKilograms`; °C → °C/°F at the metric's precision), so the range never
    /// double-labels in either system. Everything else falls to the plain decimals path (`format`).
    private func bareNumber(_ v: Double) -> String {
        switch metric.unit {
        case "kg":
            return String(format: "%.1f", unitSystem == .imperial ? UnitFormatter.kgToPounds(v) : v)
        case "°C":
            let t = temperatureUnit == .fahrenheit ? UnitFormatter.celsiusToFahrenheit(v) : v
            return metric.decimals == 0 ? String(Int(t.rounded())) : String(format: "%.\(metric.decimals)f", t)
        default:
            return metric.decimals == 0 ? String(Int(v.rounded())) : String(format: "%.\(metric.decimals)f", v)
        }
    }

    /// The active display-unit label ("%", "min", "kg"/"lb", "°C"/"°F", …); "" for a unitless metric.
    private var displayUnit: String { metric.displayUnit(system: unitSystem, temperature: temperatureUnit) }

    /// «68–76 %» — the window range as bare extremes with the unit exactly ONCE (TND31-2), never the
    /// doubled «68 %–76 %». En-dash between the extremes (no spaces), one leading space before the unit,
    /// matching `MetricDescriptor.format`'s «\(n) \(unit)». Unitless metrics drop the suffix.
    private func rangoValor(_ lo: Double, _ hi: Double) -> String {
        let cuerpo = "\(bareNumber(lo))–\(bareNumber(hi))"
        return displayUnit.isEmpty ? cuerpo : "\(cuerpo) \(displayUnit)"
    }

    @State private var range: ExploreRange = .month
    /// The field's ⓘ opens the uniform «What we measure» card beneath it (D3/C-17, calco
    /// StrainDetailScreen.infoOpen). ONE card for all 35 metrics — no per-metric essay.
    @State private var infoOpen = false
    /// Full ascending series for this metric — ALL history.
    @State private var series: [(day: String, value: Double)] = []
    /// The series with each `day` string parsed to a `Date` exactly ONCE — the shared window math
    /// reads `date` straight from here (FER-269). Built in `load()`.
    @State private var parsed: MetricWindowMath.Parsed = []
    /// Every OTHER catalog series, loaded once for the correlation scan.
    @State private var others: [(metric: MetricDescriptor, series: [(day: String, value: Double)])] = []
    @State private var loaded = false

    /// Cached correlation scan, keyed by its inputs (selected range + the metric id), so the full
    /// cross-catalog Pearson sweep runs ONLY when those change — not on every body re-eval.
    @State private var correlationCache: [CorrRow] = []
    /// The (metricID, range) the cache was built for; nil means "not yet computed".
    @State private var correlationKey: String? = nil

    /// «jun 6» axis/scrub label, UTC-anchored so the local-zone label never slips west of UTC.
    private static let ejeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }()

    // MARK: Identity (the puente — kills `metricAccent`)

    private var hue: Color { MetricIdentity.hue(for: metric) }
    private var glyph: LiquidIcon.Glyph? { MetricIdentity.glyph(for: metric) }

    // MARK: Derived

    private var latest: (day: String, value: Double)? { series.last }

    /// Padded value range so the line never sits flush against an axis: min..max ± 12% of the span.
    /// The domain is the WINDOW's, never a fixed MetricLevels band.
    private func valueRange(_ windowValues: [Double]) -> ClosedRange<Double> {
        guard let lo = windowValues.min(), let hi = windowValues.max() else { return 0...1 }
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let span = hi - lo
        return (lo - span * 0.12)...(hi + span * 0.12)
    }

    /// A Binding<Int> bridging `LiquidRangeSelector`'s index to `range` (allCases order = W…ALL).
    private var rangeIndex: Binding<Int> {
        Binding(
            get: { ExploreRange.allCases.firstIndex(of: range) ?? 0 },
            set: { range = ExploreRange.allCases[$0] })
    }

    // MARK: Body

    var body: some View {
        // Compute the window ONCE per body eval and hand it to the blocks (the shared math, FER-269).
        let window = MetricWindowMath.make(parsed, selected: range)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroField
                if infoOpen { whatWeMeasureCard }
                fusionRow
                if !loaded {
                    LiquidSheetSkeleton(a11yCargando: String(localized: "Reading your history…"))
                        .liquidSeccion()
                } else if series.isEmpty {
                    // ONLY genuine empty state: no data in the entire history.
                    LiquidFranjaSeccion(String(localized: "History"), tono: hue)
                    LiquidGraficaNiveles(
                        puntos: [], bandas: [], dominio: 0...1, ticksY: [], tono: hue,
                        estadoVacio: String(localized: "No history yet. Connect Apple Health in Data Sources and it fills every metric you can explore here."),
                        a11yLabel: String(localized: "\(metric.canonicalTitle) trend"))
                        .liquidSeccion()
                } else {
                    LiquidFranjaSeccion(String(localized: "History"), tono: hue)
                    trendContent(window: window).liquidSeccion()
                    LiquidFranjaSeccion(String(localized: "What correlates"), tono: hue)
                    correlationContent.liquidSeccion()
                    pieMetodo
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background { LiquidSheetFondo(tone: hue).ignoresSafeArea() }
        .navigationTitle(metric.canonicalTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: metric.id) { await load() }
        // Range changes the window, hence the correlation inputs — recompute the cached scan rather
        // than letting `correlationContent` run it inside body.
        .onChange(of: range) { recomputeCorrelations() }
    }

    // MARK: - 1. Hero (campo teñido) — identidad por métrica, «as of» como cláusula

    @ViewBuilder private var heroField: some View {
        if let last = latest {
            LiquidCampoMetrica(
                tono: hue,
                titulo: metric.canonicalTitle,
                glifo: glyph,
                datos: [heroDato(last.value)],
                clausula: asOfClause,
                // D3/C-17: the ⓘ opens the uniform «What we measure» card (no verdict, no level
                // phrase — A17). Same lever the sibling MetricDetailScreen uses.
                infoAbierto: infoOpen,
                infoEtiqueta: String(localized: "What we measure"),
                onInfo: { withAnimation(LiquidMotion.lift) { infoOpen.toggle() } })
        } else {
            LiquidCampoMetrica(
                tono: hue,
                titulo: metric.canonicalTitle,
                glifo: glyph,
                // C-01: no category rótulo — it only echoed the title / a redundant category under a
                // numeral whose identity the title already names; the «as of <date>» clause carries
                // the temporal context.
                datos: [.init(valor: LiquidCajita.sinDato, rotulo: "",
                              a11y: String(localized: "no data"), ausente: true)])
        }
    }

    /// The hero numeral, unit split from the number so the value reads big and the unit small (the
    /// sibling detail's typography). The two SI-stored units that carry an imperial form (kg / °C)
    /// stay WHOLE — `fmt` converts + relabels them as one string, and re-splitting it is fragile.
    /// The bare-number logic mirrors `MetricDescriptor.format` exactly.
    private func heroDato(_ v: Double) -> LiquidCampoDato {
        // C-01: no rótulo — the numeral carried a repeated category («Recovery» under a «Recovery»
        // title). The title names the metric; the «as of <date>» clause dates the number.
        switch metric.unit {
        case "kg", "°C":
            return .init(valor: fmt(v), rotulo: "")
        default:
            let n = metric.decimals == 0 ? String(Int(v.rounded()))
                                         : String(format: "%.\(metric.decimals)f", v)
            return .init(valor: n, unidad: metric.unit, rotulo: "")
        }
    }

    private var asOfClause: String? {
        // C-12: the family (Today's twins, the vital detail) never stamps a FRESH numeral with an
        // absolute date — it says «hoy» / «anoche». The Explorer, though, covers all 35 catalog
        // metrics and many go stale (a weight from three weeks ago, a VO₂max from months back).
        // Dating a reading that IS current would desentonar with the family; NOT dating a 21-day-old
        // weight would LIE that it's current — and copy that misdates the body is the class that
        // breaks the review. So the clause stays SILENT inside the family's freshness window
        // (today / yesterday, the same cut CuerpoView.freshSteps uses) and only dates a reading
        // older than that.
        guard let day = latest?.day, let d = Repository.parseDayKey(day) else { return nil }
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        guard day < cutoff else { return nil }
        return String(localized: "as of \(longDate(d))")
    }

    /// The ⓘ card under the field: ONE uniform «what we measure» line for ALL 35 catalog metrics —
    /// no per-metric essay, no verdict, no level phrase (D3/C-17, A17). Same shape as
    /// `StrainDetailScreen.whatWeMeasureCard`.
    private var whatWeMeasureCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(String(localized: "What we measure"))
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "The daily series of this metric, in its unit; the number above is the most recent day."))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidTarjetaSeccion()
        .liquidSeccion(top: LiquidSpace.s400, bottom: LiquidSpace.s200)
    }

    /// FER-670 / FER-254: when a second source reported the shown day (steps / sleep total /
    /// active kcal), say whether they agree — both values visible, a conflict flagged, never
    /// averaged. Liquid via `LiquidNotaLine`. `fusionPoint` folds the calorie alias, so the raw
    /// key works.
    @ViewBuilder private var fusionRow: some View {
        if let day = latest?.day, let agreement = repo.fusionPoint(day: day, metric: metric.key) {
            FusionAgreementRow(point: agreement, format: fmt)
                .padding(.horizontal, LiquidSpace.s550)
                .padding(.top, LiquidSpace.s300)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 2. Tu historia — selector + gráfica cruda + resumen de ventana

    private func trendContent(window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                seleccion: rangeIndex, tono: hue)
                .accessibilityLabel(String(localized: "Time range"))
            if window.values.count > 1 {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    trendChart(window: window)
                    LiquidResumenVentana(celdas: resumenCeldas(window))
                }
                .liquidTarjetaSeccion()
            } else {
                // One reading or none in the range → the honest empty well (no card, no summary).
                LiquidGraficaNiveles(
                    puntos: [], bandas: [], dominio: valueRange(window.values), ticksY: [], tono: hue,
                    estadoVacio: String(localized: "Not enough days in this range to draw a trend."),
                    a11yLabel: String(localized: "\(metric.canonicalTitle) trend"))
            }
        }
    }

    /// The raw line (no moving average — the dossier traces the windowed values directly), on the
    /// window's own domain, tinted by identity. No bands: the generic detail has no level ladder.
    private func trendChart(window: MetricWindow) -> some View {
        let puntos = MetricWindowMath
            .decimatedPoints(rows: window.rows, values: window.values, maxPoints: 80)
            .map { (fecha: $0.date, valor: $0.value) }
        return LiquidGraficaNiveles(
            puntos: puntos,
            bandas: [],
            dominio: valueRange(window.values),
            ticksY: [],
            tono: hue,
            formatoScrub: { v, f in "\(fmt(v)) · \(Self.ejeFmt.string(from: f))" },
            formatoValorScrub: { fmt($0) },
            formatoFechaScrub: { Self.ejeFmt.string(from: $0) },
            formatoFechaEje: { Self.ejeFmt.string(from: $0) },
            estadoVacio: String(localized: "Not enough days in this range to draw a trend."),
            a11yLabel: String(localized: "\(metric.canonicalTitle) trend"))
    }

    /// Promedio · Δ% (period over period, tinted by the metric's polarity) · Rango — the paper's
    /// `TrendStatSummary`, now the reusable window summary. Δ% drops out on `.all` (no prior period).
    private func resumenCeldas(_ window: MetricWindow) -> [LiquidResumenVentana.Celda] {
        let stat = ComparisonEngine.stat(window.values)
        let promedio = LiquidResumenVentana.Celda(
            rotulo: String(localized: "Average"), valor: fmt(stat.mean))
        let rango = LiquidResumenVentana.Celda(
            rotulo: String(localized: "Range"), valor: rangoValor(stat.min, stat.max))
        guard let pct = window.range.periodComparison(of: series)?.pctChange else {
            return [promedio, rango]
        }
        let rounded = Int(pct.rounded())
        let texto = rounded > 0 ? "+\(rounded)%" : (rounded < 0 ? "−\(abs(rounded))%" : "0%")
        let cambio = LiquidResumenVentana.Celda(
            rotulo: String(localized: "Change"), valor: texto, tono: deltaTono(pct))
        return [promedio, cambio, rango]
    }

    /// Δ% tint by the metric's polarity: the good direction → `positivo`, the other → `atencionTexto`;
    /// flat or a neutral metric → quiet ink. Mirrors the vital detail's `liquidTonoDelta`.
    private func deltaTono(_ pct: Double) -> Color? {
        guard Int(abs(pct).rounded()) != 0 else { return nil }
        switch metric.higherIsBetter {
        case .some(true):  return pct > 0 ? LiquidColor.positivo : LiquidColor.atencionTexto
        case .some(false): return pct < 0 ? LiquidColor.positivo : LiquidColor.atencionTexto
        case .none:        return nil
        }
    }

    // MARK: - 3. Qué correlaciona («What correlates»)

    private struct CorrRow: Identifiable {
        let id: String
        let metric: MetricDescriptor
        let r: Double
        let n: Int
    }

    /// A Sendable-only scan result — no `MetricDescriptor` — so it can cross the `Task.detached` hop
    /// (FER-976). `attachCorrelationRows` reattaches the catalog `MetricDescriptor` on MainActor.
    private struct CorrScan: Sendable {
        let id: String
        let r: Double
        let n: Int
    }

    private var correlationContent: some View {
        let rows = correlationCache
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidNotaLine(String(localized: "Pearson r over the visible window · |r| ≥ 0.30, n ≥ 10"))
            // Association, not cause. (FER-299) C-05: ONE disclaimer key across both instruments —
            // the same LiquidNotaLine Compare shows, so the piece never speaks two texts.
            LiquidNotaLine(String(localized: "Association, not cause: moving together isn't one driving the other."))
            if rows.isEmpty {
                Text(String(localized: "Nothing in the catalog moves clearly with \(metric.canonicalTitle.lowercased()) over this window. Widen the range to surface relationships."))
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.tinta500)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .liquidTarjetaSeccion()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        correlationRow(row)
                        if idx < rows.count - 1 {
                            LiquidCapilar(eje: .horizontal)
                        }
                    }
                }
                .liquidTarjetaSeccion()
            }
        }
    }

    /// One correlate: the OTHER metric's identity dot + canonical name + «category · n = N», its
    /// signed r as a zero-axis bar (magnitude |r|, side = sign, hue = identity), and the value in
    /// neutral ink with the sign carried by the leading «−» (TND30-4: a negative correlation is not
    /// an alarm). Composed in-line — DS rule §7 (see the file header). At AX text sizes the row
    /// STACKS — identity on top, bar + r value below — so «−0.99» never clips and the title never
    /// races the value on one line (TND31-1, the same fix CompareView.pairCard made for TND30-5).
    private func correlationRow(_ row: CorrRow) -> some View {
        let tono = MetricIdentity.hue(for: row.metric)
        let valor = (row.r >= 0 ? "+" : "−") + String(format: "%.2f", abs(row.r))
        // The correlate's identity mark — a plain tone dot, the same identity language the catalog
        // rows carry (LiquidListRow's leading dot), minus its glow (a DS-owned value).
        let punto = Circle().fill(tono).frame(width: 8, height: 8).accessibilityHidden(true)
        let identidad = VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            Text(row.metric.canonicalTitle)
                .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
            // C-09: a STABLE key with the house-style «n=%lld» (no spaces, §4.6), not the
            // interpolation-generated «%@ · n = %@» whose count printed as %@ and never grew an `es`.
            Text(String(format: String(localized: "explore.corr.footer",
                                       defaultValue: "%1$@ · n=%2$lld"),
                        row.metric.localizedCategory, row.n))
                .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
        }
        let valorTexto = Text(verbatim: valor)
            .font(LiquidType.valorM).monospacedDigit()
            .foregroundStyle(LiquidColor.tinta900)

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                    HStack(spacing: LiquidSpace.s300) { punto; identidad }
                    HStack(spacing: LiquidSpace.s250) {
                        rBar(row.r, tono: tono)
                        // No fixed width at AX sizes: the mono value grows past 52 pt and must not clip.
                        valorTexto.fixedSize()
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(spacing: LiquidSpace.s300) {
                    punto
                    identidad
                    Spacer(minLength: LiquidSpace.s200)
                    HStack(spacing: LiquidSpace.s250) {
                        rBar(row.r, tono: tono)
                        valorTexto.frame(width: 52, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.vertical, LiquidSpace.s250)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        // C-03: VoiceOver speaks the SAME signed string the screen shows — the leading «−» (U+2212)
        // and «+», not the ASCII hyphen `%.2f` emits — so the spoken value matches `valor`.
        .accessibilityLabel(Text(String(localized: "\(row.metric.canonicalTitle), correlation \(valor), \(row.n) days")))
    }

    /// The zero-axis r bar: a 1 pt tinta axis at centre, a capsule of width `(track/2)·|r|` growing
    /// from centre toward the side of the sign, tinted by the correlate's identity hue. Honest for
    /// r∈[−1,1]; the shared scale is fixed (|r| ≤ 1), so a bar means the same magnitude in every row.
    private func rBar(_ r: Double, tono: Color) -> some View {
        GeometryReader { geo in
            let medio = geo.size.width / 2
            let cy = geo.size.height / 2
            let ancho = medio * CGFloat(min(abs(r), 1.0))
            ZStack(alignment: .topLeading) {
                Rectangle().fill(LiquidColor.tinta10)
                    .frame(width: 1, height: 14)
                    .position(x: medio, y: cy)
                Capsule().fill(tono)
                    .frame(width: ancho, height: 6)
                    .position(x: r < 0 ? medio - ancho / 2 : medio + ancho / 2, y: cy)
            }
        }
        .frame(width: 72, height: 18)
        .accessibilityHidden(true)
    }

    // MARK: - 4. Método + sello de procedencia

    /// D3/C-17 (b): the method line, HONEST by origin. «Your latest daily reading, shown raw, with no
    /// smoothing» LIED for the on-device-computed metrics (recovery / strain / stress) — those are a
    /// calculation, not a raw reading. Two templates, not 35 methods: a measured value vs. a computed
    /// one, keyed to the SAME «calculated» bucket as the provenance chip (`metricIsCalculated`). No
    /// verdict, no level phrase (A17).
    private var metodoTexto: String {
        metricIsCalculated(metric)
            ? String(localized: "The number is the most recent calculated value; the chart traces the daily values across the range.")
            : String(localized: "The number is the most recent value in this series; the chart traces the daily values across the range.")
    }

    private var pieMetodo: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         mostrar: String(localized: "Show explanation"),
                         ocultar: String(localized: "Hide explanation")) {
                LiquidNotaLine(metodoTexto, tono: LiquidColor.tinta700)
            }
            // Provenance chip: the Hoy sheet's CLOSED vocabulary («Apple Health» / «Apple Watch» /
            // «Calculated on your phone», C-16) over the metric's own identity mark — a glyph badge for
            // the ~7 canonical families, a plain tone dot for the rest (glyph == nil, TND31-4: no
            // invented `.rayo`). Only the LABEL adopts the vocabulary; glyph + hue stay identity. With
            // history only.
            if !series.isEmpty {
                LiquidOrigenChip(glyph: glyph, badgeTono: hue,
                                 etiqueta: originVocabulary(metric))
            }
        }
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

    // MARK: - Load (data path conserved verbatim from the paper screen)

    private func load() async {
        // Prefer the merged on-device dashboard (`displayDays`) over the imports-only `series()`
        // table — a strap user's computed scores live there. Falls back to imports for import-only
        // metrics (weight, body fat, HR zones…). (FER-281) Both via the SHARED resolver (TND-29).
        let dash = repo.displayDays

        let keysBySource = await repo.availableKeySets(sources: MetricCatalog.all.map(\.source))
        // Candidates for the correlation scan: every OTHER metric with data — on-device OR imported.
        let candidates = MetricCatalog.all.filter { other in
            guard other.id != metric.id else { return false }
            let onDevice = !(MetricSeriesResolver.dashboardSeries(other.key, from: dash) ?? []).isEmpty
            let imported = keysBySource[other.source]?.contains(other.key) ?? false
            return onDevice || imported
        }

        let loadedOthers: [(metric: MetricDescriptor, series: [(day: String, value: Double)])] =
            await withTaskGroup(of: (MetricDescriptor, [(day: String, value: Double)]).self) { group in
                for other in candidates {
                    let onDevice = MetricSeriesResolver.dashboardSeries(other.key, from: dash) ?? []
                    if onDevice.isEmpty {
                        group.addTask { (other, await repo.series(key: other.key, source: other.source)) }
                    } else {
                        group.addTask { (other, onDevice) }
                    }
                }
                var out: [(metric: MetricDescriptor, series: [(day: String, value: Double)])] = []
                for await (m, s) in group where !s.isEmpty { out.append((m, s)) }
                return out
            }

        // Focal series: on-device if the dashboard computes this metric, else the imported series.
        let focalOnDevice = MetricSeriesResolver.dashboardSeries(metric.key, from: dash) ?? []
        let focalSeries = focalOnDevice.isEmpty
            ? await repo.series(key: metric.key, source: metric.source)
            : focalOnDevice
        series = focalSeries
        parsed = focalSeries.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
        // TaskGroup completion order is nondeterministic — restore catalog order so the correlation
        // list is stable across loads (recomputeCorrelations re-sorts by |r| for display).
        let catalogIndex = Dictionary(uniqueKeysWithValues: MetricCatalog.all.enumerated().map { ($1.id, $0) })
        others = loadedOthers.sorted { (catalogIndex[$0.metric.id] ?? 0) < (catalogIndex[$1.metric.id] ?? 0) }
        loaded = true
        recomputeCorrelations()
    }

    // MARK: - Correlation compute (OFF-MAIN, reattach-by-id — conserved verbatim, FER-976)

    /// Top |r| catalog metrics over a given window (|r| ≥ 0.30, n ≥ 10 — the Explorer's stricter
    /// DISPLAY policy over the `CorrelationStrength.minPairs` compute floor, TND-29). Pure — Sendable
    /// in, Sendable out — runs inside `Task.detached`. `nonisolated` opts OUT of the View's inferred
    /// MainActor isolation.
    private nonisolated static func computeCorrelationScans(
        windowed: [(day: String, value: Double)],
        others: [(id: String, series: [(day: String, value: Double)])]
    ) -> [CorrScan] {
        let myDays = Set(windowed.map(\.day))
        guard !myDays.isEmpty else { return [] }
        var rows: [CorrScan] = []
        for entry in others {
            let otherWindowed = entry.series.filter { myDays.contains($0.day) }
            let pairs = CorrelationEngine.alignByDay(windowed, otherWindowed)
            guard pairs.count >= 10, let c = CorrelationEngine.pearson(pairs) else { continue }
            if abs(c.r) >= 0.3 {
                rows.append(CorrScan(id: entry.id, r: c.r, n: c.n))
            }
        }
        rows.sort { abs($0.r) > abs($1.r) }
        return Array(rows.prefix(6))
    }

    /// Reattaches a Sendable `CorrScan` to the catalog `MetricDescriptor`, by id.
    private func attachCorrelationRows(_ scans: [CorrScan]) -> [CorrRow] {
        let byId = Dictionary(uniqueKeysWithValues: others.map { ($0.metric.id, $0.metric) })
        return scans.compactMap { s in byId[s.id].map { CorrRow(id: s.id, metric: $0, r: s.r, n: s.n) } }
    }

    /// Rebuild the cached correlation scan for the CURRENT effective window, only when its key
    /// (metric id + selected range) changed. The expensive cross-catalog Pearson sweep runs off the
    /// MainActor via `Task.detached` (FER-976): a Sendable (day,value) snapshot in, a Sendable scan
    /// out; `correlationCache` is assigned back on MainActor by reattaching the catalog descriptor.
    private func recomputeCorrelations() {
        let key = "\(metric.id)|\(range.rawValue)"
        guard correlationKey != key else { return }
        correlationKey = key
        let window = MetricWindowMath.make(parsed, selected: range)
        let windowed = MetricWindowMath.slice(parsed, for: window.range)
        let othersSnapshot = others.map { (id: $0.metric.id, series: $0.series) }
        Task {
            let scans = await Task.detached(priority: .userInitiated) {
                Self.computeCorrelationScans(windowed: windowed, others: othersSnapshot)
            }.value
            guard correlationKey == key else { return }   // a newer metric/range landed first
            correlationCache = attachCorrelationRows(scans)
        }
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func explorerPreviewRepo() -> Repository {
    let repo = Repository(deviceId: "preview")
    repo.setDashboard()
    return repo
}

#Preview("Explore") {
    // Wrapped in a NavigationStack: the view itself no longer provides one (FER-171), so the preview
    // supplies the stack its `.navigationDestination` hangs off.
    NavigationStack {
        MetricExplorerView()
    }
    .environmentObject(explorerPreviewRepo())
    .frame(width: 390, height: 820)
}

#Preview("Metric Detail") {
    NavigationStack {
        MetricDetailView(metric: MetricCatalog.all.first { $0.key == "recovery" }!)
    }
    .environmentObject(explorerPreviewRepo())
    .frame(width: 390, height: 820)
}
#endif
#endif
