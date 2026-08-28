import SwiftUI
import StrandDesign
import StrandAnalytics
import CenitStore
import Foundation

// MARK: - Apple Health (per-source page) — Liquid Glass (FER-108)
//
// Migration of the per-source Apple Health viewer from the light «Instrumento diurno» paper to
// Liquid Glass, sibling to Compare/Explore (TND-30/31) and Data Sources (FER-108): the neutral
// `LiquidSheetFondo`, inset section overlines (Compare's pattern, never a franja a sangre), the
// range control as `LiquidRangeSelector`, uniform composed metric tiles (this screen has no
// delta — the hero value + a sparkline replace it), and chart cards built from the shared Liquid
// chart core with an avg/min/max/points footer.
//
// THE MIGRATION IS SKIN, NOT THREAD: the data plumbing is UNCHANGED — everything still reads
// from the "apple-health" source, all history loads once, the range control windows it
// client-side relative to the latest point, and sparse series auto-widen exactly as before.
//
// CIMIENTOS (FER-108): every hue and canonical name comes from the shared bridge —
// `MetricIdentity.identity(forIngestKey:)` for color/glyph, `MetricCatalog.descriptor(forIngestKey:)?.canonicalTitle`
// for the name — never a locally invented label or an ad hoc paper-era accent. Several Apple
// Health metrics (VO₂ max, weight, body fat, lean mass, BMI, active energy) have no canonical
// family yet and fall to the catalog's documented default (verdePrimario, no glyph) — that
// collapse is an accepted, documented gap in the identity bridge itself, not something this
// screen invents.

struct AppleHealthView: View {
    @EnvironmentObject var repo: Repository

    // Imperial/Metric display preference (D#103). Weight and lean mass (stored kg) re-label to lb here;
    // every other Apple Health metric is unit-agnostic. Display-only.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    /// kg value → the active mass unit, full string with label (e.g. "74.5 kg" / "164.2 lb").
    private func massLabel(_ kg: Double) -> String { UnitFormatter.massFromKilograms(kg, system: unitSystem) }

    /// Optional pre-seeded data for previews; when set, the async store load is
    /// skipped (store-backed reads can't be seeded in a preview). Production leaves
    /// this nil and loads from the repository in `.task`.
    private let previewData: PreviewData?

    init() { self.previewData = nil }
    fileprivate init(previewData: PreviewData) { self.previewData = previewData }

    // Loaded state.
    @State private var loaded = false
    @State private var appleRows: [AppleDaily] = []
    @State private var workoutCount = 0

    // Raw series (day, value) keyed by metric — ALL history, ascending by day.
    @State private var series: [String: [(day: String, value: Double)]] = [:]

    // The active range window. The data goes back years — never hard-cap.
    @State private var range: RangeWindow = .quarter

    /// Memoized per-metric resolved window. Resolving a key (effective range +
    /// trimmed rows) re-slices the full multi-year series and, on auto-widen, slices
    /// it once per candidate range. The view body asks for the same key many times
    /// per render (every tile, every chart, plus rangeNote/rangeSummary), and
    /// SwiftUI re-evaluates the body on hover / animation / 1Hz HR ticks. The inputs
    /// (`series`, `range`) only change on load or pill tap, so we compute once and
    /// cache, recomputing via .onChange(of:) when an input actually changes.
    @State private var windowCache: [String: ResolvedSeries] = [:]

    /// Memoized per-day rows trimmed to the active window. Read by both
    /// `rangeSummaryCaption` and `spanSubtitle` every render; depends only on
    /// `appleRows` + `range`, so it's cached alongside `windowCache`.
    @State private var windowedRowsCache: [AppleDaily] = []

    /// A key's resolved (possibly auto-widened) window: the effective range plus the
    /// rows trimmed to it.
    private struct ResolvedSeries {
        var effective: RangeWindow
        var rows: [(day: String, value: Double)]
    }

    // The series keys this page pulls from the apple-health source.
    private static let seriesKeys = [
        "steps", "active_kcal", "vo2max",
        "resting_hr", "hrv", "spo2", "resp_rate", "asleep_min",
        "weight", "body_fat", "lean_mass", "bmi"
    ]

    // Ronda 2 #7: clavados a `en_US_POSIX` salían en inglés bajo es-MX («28 Aug 2026»). Mismo
    // patrón que CuerpoView (`dateHeader`, locale del app) y DataSourcesView (`shortDate`,
    // `setLocalizedDateFormatFromTemplate`) — se usan los dos juntos aquí.
    private static let spanFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        return f
    }()

    private static let asOfFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }()

    /// Chart card height — must match the Liquid chart core's internal `LiquidChartAlto.explorador`
    /// (144, package-internal) so the single-point/empty wells this screen composes by hand line up
    /// with the real chart. Same duplication precedent as `LiquidSheetSkeleton.Alto.grafica`.
    private static let chartHeight: CGFloat = 144

    /// Uniform tile height so every tile in the grid reads as one row regardless of whether it
    /// carries a sparkline/caption — the same "uniform-height tile" contract the paper had.
    private static let tileMinHeight: CGFloat = 100

    // yyyy-MM-dd → Date via the shared UTC / en_US_POSIX parser (FER-325).
    private func date(_ day: String) -> Date? { Repository.parseDayKey(day) }

    /// The canonical short name for an Apple Health ingest key — the ONE bridge (FER-108
    /// cimientos): never a locally invented label, and reconciled so a tile and its chart card
    /// call the same metric by the same name.
    private func metricLabel(_ key: String) -> String {
        MetricCatalog.descriptor(forIngestKey: key)?.canonicalTitle ?? key
    }

    // MARK: - Range control (W / M / 3M / 6M / 1Y / ALL) — the ONE pill control.

    enum RangeWindow: String, CaseIterable, Identifiable {
        case week, month, quarter, half, year, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .week:    return String(localized: "W")
            case .month:   return String(localized: "M")
            case .quarter: return String(localized: "3M")
            case .half:    return String(localized: "6M")
            case .year:    return String(localized: "1Y")
            case .all:     return String(localized: "ALL")
            }
        }
        /// Number of trailing days; nil = everything.
        var days: Int? {
            switch self {
            case .week:    return 7
            case .month:   return 30
            case .quarter: return 90
            case .half:    return 180
            case .year:    return 365
            case .all:     return nil
            }
        }
        var caption: String {
            switch self {
            case .week:    return String(localized: "7 DAYS")
            case .month:   return String(localized: "30 DAYS")
            case .quarter: return String(localized: "90 DAYS")
            case .half:    return String(localized: "180 DAYS")
            case .year:    return String(localized: "365 DAYS")
            case .all:     return String(localized: "ALL TIME")
            }
        }
        var name: String {
            switch self {
            case .week:    return String(localized: "week")
            case .month:   return String(localized: "month")
            case .quarter: return String(localized: "3 months")
            case .half:    return String(localized: "6 months")
            case .year:    return String(localized: "year")
            case .all:     return String(localized: "all history")
            }
        }
        /// This range plus every LARGER range, ascending — the auto-expand search
        /// order when the selected window holds zero points.
        var widening: [RangeWindow] {
            let order: [RangeWindow] = [.week, .month, .quarter, .half, .year, .all]
            guard let i = order.firstIndex(of: self) else { return [.all] }
            return Array(order[i...])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s550) {
                header
                if loaded && !hasAnyData {
                    emptyState
                } else if !loaded {
                    loadingState
                } else {
                    rangeControl
                    tileGrid
                    heartSection
                    activitySection
                    bodySection
                    sleepSection
                }
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background { LiquidSheetFondo().ignoresSafeArea() }
        .task { await load() }
        .onChange(of: range) { rebuildWindowCache() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Ronda 2 #20: el overline decía «Apple Health» igual que el título justo debajo — un
            // overline es de ROL (Cuerpo: glifo + Tendencias + fecha), no el mismo nombre repetido.
            LiquidOverline(String(localized: "Source"))
            Text(String(localized: "Apple Health"))
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            if let s = spanSubtitle {
                Text(verbatim: s)
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The honest empty state: no imported history at all yet. Composed from atoms (no 1:1 Liquid
    /// piece for this) inside the same solid-card recipe every other block on this screen uses.
    /// Ronda 2 #5: used to open straight on the 7-year zip export — the SLOW path — contradicting
    /// Data Sources' own empty state two taps back («tap Sync now»), and named a macOS step («On an
    /// iPhone:») nobody on this screen can be running. The fast path (Sync now / Connect, back in
    /// Data Sources) leads; the zip is the long-history fallback, named as one.
    /// Ronda 3 #4: cita el rótulo REAL del botón desconectado («Connect Apple Health»,
    /// `DataSourcesView.swift:385`), no «Connect» a secas.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(String(localized: "Nothing imported yet"))
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "Go back to Data Sources and tap Sync now (or Connect Apple Health, if it isn't linked yet)."))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "For years of history at once: Health app → your photo → Export All Health Data, then import that .zip in Data Sources."))
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidTarjetaSeccion()
    }

    /// The loading state: it NAMES what it is doing, visibly — not only in VoiceOver — in the same
    /// card the empty state uses. NOT `LiquidSheetSkeleton`, whose stage / hypnogram / double-data
    /// geometry belongs to the sleep detail, not to an Apple-Health list (FER-108 · Grok).
    private var loadingState: some View {
        HStack(spacing: LiquidSpace.s250) {
            ProgressView().tint(LiquidColor.tinta500)
            Text(String(localized: "Reading your Apple Health history…"))
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidTarjetaSeccion()
    }

    /// Rebuild the per-metric resolved-window cache from scratch. Called once after
    /// load and again whenever `range` changes — never inside the render path.
    private func rebuildWindowCache() {
        var cache: [String: ResolvedSeries] = [:]
        cache.reserveCapacity(Self.seriesKeys.count)
        for key in Self.seriesKeys {
            let eff = computeEffectiveRange(key)
            cache[key] = ResolvedSeries(effective: eff, rows: slice(key, eff))
        }
        windowCache = cache
        windowedRowsCache = computeWindowedRows()
    }

    /// True if ANY series or per-day row holds data (drives the empty state).
    private var hasAnyData: Bool {
        if !appleRows.isEmpty { return true }
        return series.values.contains { !$0.isEmpty }
    }

    // MARK: - Load

    private func load() async {
        // Previews inject data directly (store-backed reads can't be seeded).
        if let pd = previewData {
            appleRows = pd.rows.sorted { $0.day < $1.day }
            workoutCount = pd.workoutCount
            series = pd.series
            rebuildWindowCache()
            loaded = true
            return
        }

        async let rows = repo.appleDailyRows(respectingMode: false)      // FER-485: diagnostic — show what's stored
        async let workouts = repo.workoutRows(respectingMode: false)

        // Load the per-key series concurrently (was a sequential await loop = N+1 round-trips).
        // Same pattern as CompareView/InsightsView/MetricExplorerView (FER-318).
        let fetched = await withTaskGroup(of: (String, [(day: String, value: Double)]).self) { group in
            for key in Self.seriesKeys {
                group.addTask { (key, await repo.series(key: key, source: "apple-health")) }
            }
            var out: [String: [(day: String, value: Double)]] = [:]
            for await (key, s) in group { out[key] = s }
            return out
        }

        let loadedRows = await rows
        let appleWorkouts = await workouts.filter { $0.source == "apple_health" || $0.source == "apple-health" }

        await MainActor.run {
            appleRows = loadedRows.sorted { $0.day < $1.day }
            workoutCount = appleWorkouts.count
            series = fetched
            rebuildWindowCache()
            loaded = true
        }
    }

    // MARK: - Range control + header span

    private var rangeControl: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            LiquidRangeSelector(opciones: RangeWindow.allCases.map(\.label),
                                seleccion: rangeIndex, tono: LiquidColor.tinta700)
                .accessibilityLabel(String(localized: "Time range"))
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: rangeSummaryCaption)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(anyWidened ? LiquidColor.atencionTexto : LiquidColor.tinta500)
                    .accessibilityLabel(rangeSummaryCaption)
                Spacer(minLength: LiquidSpace.s200)
                Text(verbatim: range.caption)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
            }
        }
    }

    /// A Binding<Int> bridging `LiquidRangeSelector`'s index to `range` (allCases order = W…ALL) —
    /// the same bridge pattern Compare/Explore use for `ExploreRange`.
    private var rangeIndex: Binding<Int> {
        Binding(
            get: { RangeWindow.allCases.firstIndex(of: range) ?? 0 },
            set: { range = RangeWindow.allCases[$0] })
    }

    /// True if any tracked series had to auto-widen past the selected range.
    private var anyWidened: Bool {
        Self.seriesKeys.contains { !raw($0).isEmpty && effectiveRange($0) != range }
    }

    /// Window-level caption near the control: how many days the per-day rows span in
    /// the selected range, plus a flag if any tracked series had to auto-widen.
    private var rangeSummaryCaption: String {
        let n = windowedRows.count
        let unit = n == 1 ? String(localized: "day") : String(localized: "days")
        return anyWidened
            ? String(localized: "\(n) \(unit) · \(range.name) · some sparse series widened")
            : String(localized: "\(n) \(unit) · \(range.name)")
    }

    /// Header subtitle reflects the windowed (visible) per-day span.
    private var spanSubtitle: String? {
        let rows = loaded ? windowedRows : appleRows
        guard let first = rows.first?.day, let last = rows.last?.day,
              let lo = date(first), let hi = date(last) else {
            return String(localized: "Steps, heart, sleep, body composition and VO₂ max: read locally on this iPhone.")
        }
        let loS = Self.spanFormatter.string(from: lo)
        let hiS = Self.spanFormatter.string(from: hi)
        let span = loS == hiS ? loS : "\(loS) → \(hiS)"
        return String(localized: "\(rows.count) days · \(span)")
    }

    /// AppleDaily rows trimmed to the active window (for the span readout), taken
    /// RELATIVE TO THE LATEST recorded day rather than "now". Served from the
    /// per-render cache; recomputed only when `appleRows`/`range` change.
    private var windowedRows: [AppleDaily] {
        loaded ? windowedRowsCache : computeWindowedRows()
    }

    /// The actual windowing of the per-day rows. Called only from
    /// rebuildWindowCache and the not-yet-loaded fallback — never per render.
    private func computeWindowedRows() -> [AppleDaily] {
        guard let n = range.days else { return appleRows }
        guard let lastDay = appleRows.last?.day, let last = date(lastDay) else { return [] }
        let cutoff = last.addingTimeInterval(-Double(n - 1) * 86_400)
        return appleRows.filter { row in
            guard let d = date(row.day) else { return false }
            return d >= cutoff
        }
    }

    // MARK: - Metric tiles (uniform-height Liquid tiles in an adaptive grid)

    private var tileGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168), spacing: LiquidSpace.s200)],
            alignment: .leading,
            spacing: LiquidSpace.s200
        ) {
            liquidStatTile(key: "steps", fmt: { intString($0) })
            liquidStatTile(key: "resting_hr", unit: String(localized: "bpm"),
                           fmt: { "\(Int($0.rounded()))" })
            liquidStatTile(key: "hrv", unit: String(localized: "ms"),
                           fmt: { "\(Int($0.rounded()))" })
            liquidStatTile(key: "vo2max", unit: String(localized: "ml/kg"),
                           fmt: { String(format: "%.1f", $0) })
            liquidStatTile(key: "weight", fmt: { massLabel($0) })
            liquidStatTile(key: "body_fat", unit: "%", fmt: { String(format: "%.1f", $0) })
            liquidStatTile(key: "lean_mass", fmt: { massLabel($0) })
            liquidStatTile(key: "asleep_min", aggregate: .mean, fmt: { durationString($0) })
            workoutsTile
        }
    }

    /// How a tile's hero value is derived from its window.
    private enum Aggregate { case latest, mean }

    /// A Liquid metric tile composed from atoms (no delta here — `LiquidMetricTile` requires one
    /// and this screen has none, only a sparkline): a quiet label + icon drop, the value in its
    /// identity hue (ink when empty), an optional sparkline, and a caption. Sparse-safe: the
    /// window auto-falls-back to ALL, the hero is the LATEST point ("as of <date>") unless a mean
    /// is requested, and the sparkline + caption track the same resolved window.
    private func liquidStatTile(key: String, unit: String = "",
                                aggregate: Aggregate = .latest,
                                fmt: @escaping (Double) -> String) -> some View {
        let rows = resolvedWindow(key)
        let values = rows.map(\.value)
        let identity = MetricIdentity.identity(forIngestKey: key)
        let value: String
        let caption: String?
        if values.isEmpty {
            value = "—"
            caption = nil
        } else {
            switch aggregate {
            case .latest:
                let v = values.last ?? 0
                value = unit.isEmpty ? fmt(v) : "\(fmt(v)) \(unit)"
                caption = rows.last.flatMap { date($0.day) }.map { String(localized: "as of \(Self.asOfFormatter.string(from: $0))") }
            case .mean:
                let m = mean(values) ?? 0
                value = unit.isEmpty ? fmt(m) : "\(fmt(m)) \(unit)"
                caption = String(localized: "avg · \(values.count)d")
            }
        }
        return liquidTile(label: metricLabel(key), value: value, caption: caption,
                          tone: values.isEmpty ? LiquidColor.tinta500 : identity.hue,
                          glyph: identity.glyph,
                          sparkline: values.count > 1 ? sparkValues(values) : nil)
    }

    /// Workouts is a count, not a series — its own tile, still on the same recipe.
    private var workoutsTile: some View {
        liquidTile(label: String(localized: "Workouts"),
                  value: "\(workoutCount)",
                  caption: workoutCount > 0 ? String(localized: "Apple-logged") : nil,
                  tone: workoutCount > 0 ? LiquidColor.ambar : LiquidColor.tinta500,
                  glyph: .carga,
                  sparkline: nil)
    }

    /// One composed Liquid tile, uniform height: icon drop + label, value in tone, optional
    /// sparkline, optional caption — on the solid-card recipe (`liquidTarjetaSeccion`).
    private func liquidTile(label: String, value: String, caption: String?,
                            tone: Color, glyph: LiquidIcon.Glyph?,
                            sparkline: [Double]?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: LiquidSpace.s150) {
                if let glyph {
                    LiquidIconDrop(glyph, tone: tone)
                }
                Text(verbatim: label).liquidLabel().foregroundStyle(LiquidColor.tinta500)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            Text(verbatim: value).font(LiquidType.valorL).foregroundStyle(tone)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let sparkline, sparkline.count > 1 {
                Sparkline(values: sparkline,
                          gradient: ChartWell.fillGradient(tone),
                          showsArea: false, showsHead: false, showsScrub: false)
                    .frame(height: 22).padding(.top, 4)
            }
            if let caption {
                Text(verbatim: caption).font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                    .lineLimit(1).padding(.top, 2)
            }
        }
        .frame(minHeight: Self.tileMinHeight, alignment: .topLeading)
        .liquidTarjetaSeccion(padding: LiquidSpace.s300)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Chart sections (Liquid chart cards, uniform per page)

    private var heartSection: some View {
        chartSection(String(localized: "Heart & Vitals")) {
            chartCard(key: "resting_hr", fallback: 40...80,
                      fmt: { "\(Int($0.rounded())) \(String(localized: "bpm"))" })
            chartCard(key: "hrv", fallback: 20...120,
                      fmt: { "\(Int($0.rounded())) ms" })
            chartCard(key: "spo2", fallback: 90...100,
                      fmt: { String(format: "%.1f%%", $0) })
            chartCard(key: "resp_rate", fallback: 10...22,
                      fmt: { String(format: "%.1f rpm", $0) })
        }
    }

    private var activitySection: some View {
        chartSection(String(localized: "Activity & Energy")) {
            chartCard(key: "steps", fallback: 0...12000,
                      fmt: { intString($0) })
            chartCard(key: "active_kcal", fallback: 0...1000,
                      fmt: { "\(intString($0)) kcal" })
        }
    }

    private var bodySection: some View {
        chartSection(String(localized: "Body Composition")) {
            chartCard(key: "weight", fallback: 50...100, fmt: { massLabel($0) })
            chartCard(key: "body_fat", fallback: 8...35, fmt: { String(format: "%.1f%%", $0) })
            chartCard(key: "lean_mass", fallback: 40...80, fmt: { massLabel($0) })
            chartCard(key: "bmi", fallback: 16...35, fmt: { String(format: "%.1f", $0) })
        }
    }

    private var sleepSection: some View {
        chartSection(String(localized: "Sleep")) {
            chartCard(key: "asleep_min", fallback: 240...600, fmt: { durationString($0) })
        }
    }

    /// A Liquid chart section: an inset overline (Compare's pattern — never a franja a sangre) +
    /// the range caption, then its cards.
    @ViewBuilder
    private func chartSection<Cards: View>(_ title: String, @ViewBuilder cards: () -> Cards) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: LiquidSpace.s200)
                Text(verbatim: range.caption)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
            }
            cards()
        }
    }

    /// One Liquid chart card for a metric series: header (canonical name + "N readings · range" +
    /// avg in tone) + the raw-line history (`LiquidGraficaNiveles`, no bands — this dossier has no
    /// level ladder) with an avg/min/max/points footer (`LiquidResumenVentana`), on the solid-card
    /// recipe. Sparse-safe via `resolvedWindow`; a lone reading and a truly-empty series get their
    /// own honest wells (the shared chart engine folds both into one "not enough points" state, so
    /// this screen keeps its own — the contract calls out the single-point state by name).
    @ViewBuilder
    private func chartCard(key: String, fallback: ClosedRange<Double>,
                           fmt: @escaping (Double) -> String) -> some View {
        let rows = resolvedWindow(key)
        let pts = trendPoints(rows)
        let vals = rows.map(\.value)
        let title = metricLabel(key)
        let hue = MetricIdentity.identity(forIngestKey: key).hue
        let avg = mean(vals)
        let footerCeldas: [LiquidResumenVentana.Celda] = {
            guard let avg, let lo = vals.min(), let hi = vals.max() else {
                return [
                    .init(rotulo: String(localized: "Avg"), valor: "—"),
                    .init(rotulo: String(localized: "Min"), valor: "—"),
                    .init(rotulo: String(localized: "Max"), valor: "—"),
                    .init(rotulo: String(localized: "Points"), valor: "0"),
                ]
            }
            return [
                .init(rotulo: String(localized: "Avg"), valor: fmt(avg), tono: hue),
                .init(rotulo: String(localized: "Min"), valor: fmt(lo)),
                .init(rotulo: String(localized: "Max"), valor: fmt(hi)),
                .init(rotulo: String(localized: "Points"), valor: "\(vals.count)"),
            ]
        }()

        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                    Text(verbatim: rangeNote(forKey: key)).font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                }
                Spacer(minLength: LiquidSpace.s200)
                if let avg {
                    Text(verbatim: fmt(avg)).font(LiquidType.valorM).foregroundStyle(hue)
                }
            }
            Group {
                if pts.count >= 2 {
                    LiquidGraficaNiveles(
                        puntos: pts,
                        bandas: [],
                        dominio: valueRange(vals, fallback: fallback),
                        ticksY: [],
                        tono: hue,
                        formatoValorScrub: fmt,
                        formatoFechaScrub: { Self.asOfFormatter.string(from: $0) },
                        formatoFechaEje: { Self.asOfFormatter.string(from: $0) },
                        estadoVacio: String(localized: "No readings recorded."),
                        a11yLabel: String(localized: "\(title) trend"))
                } else if let only = vals.last {
                    // A single point is not a line — present the lone reading, never an "empty"
                    // state when the series has data.
                    singlePoint(only, fmt: fmt, accent: hue)
                } else {
                    emptyChart
                }
            }
            .frame(height: Self.chartHeight)
            .clipped()
            LiquidResumenVentana(celdas: footerCeldas)
        }
        .liquidTarjetaSeccion()
    }

    /// Lone-reading body for series with exactly one point in range.
    private func singlePoint(_ value: Double, fmt: (Double) -> String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(String(localized: "Latest reading")).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            Text(verbatim: fmt(value)).font(LiquidType.valorTileL).tracking(LiquidType.valorTileTracking)
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var emptyChart: some View {
        Text(String(localized: "No readings recorded."))
            .font(LiquidType.cuerpo)
            .foregroundStyle(LiquidColor.tinta500)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(LiquidColor.tinta7,
                        in: RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous))
    }

    // MARK: - Series helpers (sparse-data fallback to ALL)

    /// All-history rows for a key (ascending by day).
    private func raw(_ key: String) -> [(day: String, value: Double)] { series[key] ?? [] }

    /// The latest recorded day for a key (anchors its windows).
    private func latestDate(_ key: String) -> Date? {
        guard let d = raw(key).last?.day else { return nil }
        return date(d)
    }

    /// Rows for a key over a given range, taken RELATIVE TO THE LATEST data point
    /// (not "now"); `.all` returns everything.
    private func slice(_ key: String, _ r: RangeWindow) -> [(day: String, value: Double)] {
        let all = raw(key)
        guard let n = r.days else { return all }
        guard let last = latestDate(key) else { return [] }
        let cutoff = last.addingTimeInterval(-Double(n - 1) * 86_400)
        return all.filter { row in
            guard let d = date(row.day) else { return false }
            return d >= cutoff
        }
    }

    /// The range actually shown for a key: the SELECTED range whenever its window
    /// holds ≥1 point, otherwise the smallest LARGER range that does — so switching
    /// ranges stays visibly distinct and only sparse windows widen. Served from the
    /// per-render cache; falls back to a fresh compute on a cache miss.
    private func effectiveRange(_ key: String) -> RangeWindow {
        windowCache[key]?.effective ?? computeEffectiveRange(key)
    }

    /// The actual effective-range computation (re-slices the series, once per widening
    /// candidate). Called only from rebuildWindowCache and the cache-miss fallback —
    /// never repeatedly within a single render.
    private func computeEffectiveRange(_ key: String) -> RangeWindow {
        guard !raw(key).isEmpty else { return range }
        for r in range.widening where !slice(key, r).isEmpty { return r }
        return .all
    }

    /// Rows for a key trimmed to its resolved (possibly widened) window. Served from
    /// the per-render cache; falls back to a fresh compute on a cache miss.
    private func resolvedWindow(_ key: String) -> [(day: String, value: Double)] {
        if let cached = windowCache[key]?.rows { return cached }
        return slice(key, computeEffectiveRange(key))
    }

    /// Card subtitle: "N readings · <range>", flagging an auto-widen when it happened.
    private func rangeNote(forKey key: String) -> String {
        let rows = resolvedWindow(key)
        let eff = effectiveRange(key)
        let n = rows.count
        let unit = n == 1 ? String(localized: "reading") : String(localized: "readings")
        if eff != range {
            return String(localized: "\(n) \(unit) · sparse: widened to \(eff.name)")
        }
        return String(localized: "\(n) \(unit) · \(range.name)")
    }

    private func trendPoints(_ rows: [(day: String, value: Double)]) -> [(fecha: Date, valor: Double)] {
        rows.compactMap { row in
            guard let dt = date(row.day) else { return nil }
            return (fecha: dt, valor: row.value)
        }
    }

    /// Sparklines need a non-degenerate series; cap to the last ~40 samples.
    private func sparkValues(_ values: [Double]) -> [Double] {
        guard values.count > 1 else { return [values.first ?? 0, values.first ?? 0] }
        return Array(values.suffix(40))
    }

    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func valueRange(_ values: [Double], fallback: ClosedRange<Double>, pad: Double = 0.12) -> ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return fallback }
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let span = hi - lo
        return (lo - span * pad)...(hi + span * pad)
    }

    private func intString(_ v: Double) -> String { StrandFormat.groupedInt(v) }

    private func durationString(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60, m = total % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Preview seam

extension AppleHealthView {
    /// In-memory bundle that bypasses the store-backed async load for previews.
    fileprivate struct PreviewData {
        var rows: [AppleDaily]
        var workoutCount: Int
        var series: [String: [(day: String, value: Double)]]
    }
}

#if DEBUG
@MainActor
private func appleHealthPreviewData() -> AppleHealthView.PreviewData {
    let cal = Calendar(identifier: .gregorian)
    let fmt = DayKey.utcFormatter
    let today = Date()

    var rows: [AppleDaily] = []
    var series: [String: [(day: String, value: Double)]] = [
        "steps": [], "active_kcal": [], "vo2max": [],
        "resting_hr": [], "hrv": [], "spo2": [], "resp_rate": [], "asleep_min": [],
        "weight": [], "body_fat": [], "lean_mass": [], "bmi": []
    ]

    // Seed ~2 years so the range control has real depth to window into.
    for i in stride(from: 729, through: 0, by: -1) {
        guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
        let day = fmt.string(from: d)
        let phase = Double(729 - i)
        let steps  = 8000 + 3200 * sin(phase / 6.0) + Double((Int(phase) * 53) % 1800)
        let active = 420 + 180 * sin(phase / 5.0 + 0.6) + Double((Int(phase) * 17) % 90)
        let rhr    = 53 + 4 * sin(phase / 8.0) + Double((Int(phase) * 7) % 4) - 2
        let hrv    = 58 + 16 * sin(phase / 9.0) + Double((Int(phase) * 13) % 11) - 5
        let spo2   = 96 + 1.4 * sin(phase / 4.0) + Double((Int(phase) * 3) % 2)
        let resp   = 14.5 + 1.2 * sin(phase / 7.0)
        let vo2    = 47 + 2.2 * sin(phase / 21.0)
        let asleep = 410 + 55 * sin(phase / 5.0 + 1.1) + Double((Int(phase) * 11) % 30) - 15
        // Slow body-composition drift over the two years (measured WEEKLY → sparse).
        let weight = 78.0 - 5.0 * sin(phase / 220.0) + 0.6 * sin(phase / 13.0)
        let bodyFat = 18.0 - 3.0 * sin(phase / 240.0) + 0.4 * sin(phase / 11.0)
        let lean   = weight * (1.0 - bodyFat / 100.0)
        let bmi    = weight / (1.78 * 1.78)

        rows.append(AppleDaily(
            day: day,
            steps: Int(steps.rounded()),
            activeKcal: max(120, active),
            basalKcal: 1600,
            vo2max: vo2,
            avgHr: 72,
            maxHr: 148,
            walkingHr: 96,
            weightKg: weight))

        series["steps"]?.append((day, max(0, steps)))
        series["active_kcal"]?.append((day, max(80, active)))
        series["vo2max"]?.append((day, vo2))
        series["resting_hr"]?.append((day, max(40, rhr)))
        series["hrv"]?.append((day, max(15, hrv)))
        series["spo2"]?.append((day, min(100, spo2)))
        series["resp_rate"]?.append((day, resp))
        series["asleep_min"]?.append((day, max(180, asleep)))
        // Body composition is logged once a week → deliberately sparse, to exercise
        // the trailing-window → ALL fallback (a W/M view would otherwise be empty).
        if Int(phase) % 7 == 0 {
            series["weight"]?.append((day, weight))
            series["body_fat"]?.append((day, bodyFat))
            series["lean_mass"]?.append((day, lean))
            series["bmi"]?.append((day, bmi))
        }
    }

    return .init(rows: rows, workoutCount: 124, series: series)
}

#Preview("Apple Health: seeded") {
    AppleHealthView(previewData: appleHealthPreviewData())
        .environmentObject(Repository(deviceId: "preview"))
        .frame(width: 920, height: 980)
}

#Preview("Apple Health: empty") {
    AppleHealthView(previewData: .init(rows: [], workoutCount: 0, series: [:]))
        .environmentObject(Repository(deviceId: "preview"))
        .frame(width: 920, height: 600)
}
#endif
