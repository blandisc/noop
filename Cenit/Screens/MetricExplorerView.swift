#if os(iOS)
import SwiftUI
import Foundation
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Explore (Metric Explorer + Detail) — «Instrumento diurno» (FER-272)
//
// The catalog-driven "Explore" surface, reskinned from the dark legacy system to the light
// «Instrumento diurno» language (warm paper, one dominant number, color only in the datum,
// hierarchy by space). The root is a grouped list — one section per MetricCatalog.category,
// rows directly on the paper separated by hairlines — pushing a MetricDetailView. The detail is
// a uniform analytic dossier: a light hero (latest value + "as of"), the reusable
// `MetricTrendChart` (selector + line), a `TrendStatSummary`, and a "What correlates" block.
//
// Token-only: every color is an `InstrumentoTheme` role; the per-metric category accent (the one
// place saturated hue lands) stays as «color only in the datum». No dark `StrandPalette` chrome.
//
// Sparse-metric rule (owner saw "no data" on metrics that HAVE data): a series may be sampled
// weekly (weight / body fat). The shared `MetricWindowMath` (FER-269) takes the window RELATIVE TO
// THE LATEST data point — not "now" — so a stale-but-present series still resolves, and auto-widens
// to the smallest larger range that holds ≥1 point. The hero always shows the latest available
// point + "as of <date>".

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

/// The category accent (colour communicates category only — never decoration), mapped to the
/// «Instrumento» data roles so the one saturated hue per row reads on warm paper.
private func metricAccent(_ m: MetricDescriptor, theme: InstrumentoTheme) -> Color {
    switch m.key {
    case "recovery", "sleep_performance", "hours_vs_needed_pct", "sleep_consistency",
         "restorative_pct", "restorative_min", "sleep_efficiency", "sleep_total_min",
         "sleep_deep_min", "sleep_rem_min":
        return theme.dataRecovery
    case "strain", "hr_zones45_min", "hr_zones_all_min", "strength_min", "hr_zones13_min":
        return theme.dataStrain
    case "hrv":
        return theme.dataHrv
    case "vo2max", "lean_mass":
        return theme.dataSleep
    case "rhr", "stress", "sleep_debt_min", "body_fat", "max_hr":
        return theme.dataHeart
    case "spo2", "steps":
        return theme.dataSpO2
    case "energy_kcal", "active_kcal":
        return theme.dataStrain
    default:
        return m.source == "apple-health" ? theme.dataSpO2 : theme.ink
    }
}

// MARK: - Range
//
// `ExploreRange` (the W/M/3M/6M/1Y/ALL window) lives in `Cenit/Data/ExploreRange.swift` and the
// window math in `Cenit/Screens/MetricTrendChart.swift` (`MetricWindowMath`, FER-269); the Explorer
// drives its SegmentedPillControl from the same enum.

// MARK: - On-device series resolver (FER-281)

/// The daily series for a catalog `key` read from the merged on-device dashboard (`repo.displayDays`),
/// or `nil` for keys the dashboard doesn't compute (import-only: weight / body fat / BMI / HR zones /
/// avg·max HR / derived sleep %). The Explore catalog historically read only `repo.series` (the imports
/// table), which is empty for a strap user without a WHOOP export — so every metric looked dataless. This
/// resolves the scores the strap computes on device, mirroring the key→field map the Cuerpo detail
/// screens use (FER-149). Callers fall back to `repo.series` when this returns `nil` or an empty series.
private func dashboardSeries(_ key: String, from days: [DailyMetric]) -> [(day: String, value: Double)]? {
    let pick: (DailyMetric) -> Double?
    switch key {
    case "recovery":         pick = { $0.recovery }
    case "hrv":              pick = { $0.avgHrv }
    case "rhr":              pick = { $0.restingHr.map(Double.init) }
    case "resp_rate":        pick = { $0.respRateBpm }
    case "spo2":             pick = { $0.spo2Pct }
    case "skin_temp":        pick = { $0.skinTempDevC }
    case "strain":           pick = { $0.strain }
    case "steps":            pick = { $0.steps.map(Double.init) }
    case "sleep_total_min":  pick = { $0.totalSleepMin }
    case "sleep_efficiency": pick = { $0.efficiency }
    case "sleep_deep_min":   pick = { $0.deepMin }
    case "sleep_rem_min":    pick = { $0.remMin }
    case "sleep_light_min":  pick = { $0.lightMin }
    case "active_kcal", "energy_kcal": pick = { $0.activeKcalEst }
    default:                 return nil
    }
    return days.compactMap { row in pick(row).map { (row.day, $0) } }.sorted { $0.day < $1.day }
}

// MARK: - Root: categorized list

/// The "Explore" picker — categories as sections, metrics as rows on the paper (hairline-separated),
/// each pushing a MetricDetailView. A faint trailing "•" marks metrics whose series is empty.
struct MetricExplorerView: View {
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    @EnvironmentObject var repo: Repository
    /// metric.id → whether its series is empty (loaded once, lazily).
    @State private var emptyByID: [String: Bool] = [:]

    // No NavigationStack here: Explore is pushed inside the sheet's own stack (CuerpoView). A nested
    // NavigationStack crossing this view's MetricDescriptor values crashed SwiftUI — FER-171. The
    // catalog list + its `.navigationDestination(for: MetricDescriptor.self)` hang off that stack.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Explore").font(InstrumentoType.groteskHeadline(28)).foregroundStyle(theme.ink)
                    Text("Every signal, one tap deep.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                ForEach(MetricCatalog.categories, id: \.self) { category in
                    let metrics = MetricCatalog.inCategory(category)
                    if !metrics.isEmpty {
                        categorySection(category, metrics: metrics)
                    }
                }
            }
            .padding(CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .navigationDestination(for: MetricDescriptor.self) { metric in
            MetricDetailView(metric: metric, theme: theme)
        }
        .task { await probeEmptiness() }
    }

    /// One category: a quiet overline + title + count, then its rows directly on the paper, divided by
    /// hairlines (no card-in-card — Instrumento rule 3).
    private func categorySection(_ category: String, metrics: [MetricDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Category").groteskOverline().foregroundStyle(theme.inkTertiary)
                    Text(MetricCatalog.localizedCategory(category))
                        .font(InstrumentoType.groteskHeadline(22)).foregroundStyle(theme.ink)
                }
                Spacer()
                Text("\(metrics.count)").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { idx, metric in
                    NavigationLink(value: metric) {
                        CatalogRow(metric: metric,
                                  isEmpty: emptyByID[metric.id] ?? false,
                                  theme: theme)
                    }
                    .buttonStyle(.plain)
                    if idx < metrics.count - 1 {
                        Rectangle().fill(theme.hairline).frame(height: 1)
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    /// One lightweight pass to learn which metrics have no series, so rows can flag them with the faint
    /// trailing dot. One index-only `DISTINCT key` query per source (FER-27).
    private func probeEmptiness() async {
        guard emptyByID.isEmpty else { return }
        // A metric has data if the on-device dashboard computes it (BLE users) OR it was imported. (FER-281)
        let dash = repo.displayDays
        let keysBySource = await repo.availableKeySets(sources: MetricCatalog.all.map(\.source))
        var map: [String: Bool] = [:]
        for metric in MetricCatalog.all {
            let onDevice = !(dashboardSeries(metric.key, from: dash) ?? []).isEmpty
            let imported = keysBySource[metric.source]?.contains(metric.key) ?? false
            map[metric.id] = !(onDevice || imported)
        }
        emptyByID = map
    }
}

// MARK: - One catalog row

private struct CatalogRow: View {
    let metric: MetricDescriptor
    let isEmpty: Bool
    let theme: InstrumentoTheme

    // Trailing unit chip follows the Imperial/Metric preference (kg→lb, °C→°F).
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    private var unitLabel: String {
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        let temp = UnitPrefs.resolveTemperature(system: system, override: temperatureRaw)
        return metric.displayUnit(system: system, temperature: temp)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                    .fill(theme.surface)
                Image(systemName: metric.icon)
                    .font(StrandFont.glyph(.inline, weight: .medium))
                    .foregroundStyle(metricAccent(metric, theme: theme))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.title)
                    .font(StrandFont.body)
                    .foregroundStyle(theme.ink)
                Text(metric.source == "apple-health" ? "Apple Health" : "Whoop")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            }

            Spacer(minLength: 8)

            if !unitLabel.isEmpty {
                Text(unitLabel)
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkSecondary)
            }
            // Faint trailing dot ONLY when this metric has no series at all.
            if isEmpty {
                Text("•")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary.opacity(StrandOpacity.dim))
                    .accessibilityLabel("No data")
            }
            StrandIcon.disclosure.image
                .font(StrandFont.glyph(.chevron, weight: .semibold))
                .foregroundStyle(theme.inkTertiary)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title), \(unitLabel.isEmpty ? metric.localizedCategory : unitLabel)\(isEmpty ? ", no data" : "")")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Detail / drill-down

/// The full analytic dossier for one metric in «Instrumento»: a light hero (latest value + "as of"),
/// the reusable `MetricTrendChart` selector + line (FER-269), a `TrendStatSummary`, and a "What
/// correlates" block. Built only from theme tokens; the per-metric accent is the one saturated hue.
struct MetricDetailView: View {
    let metric: MetricDescriptor
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    @EnvironmentObject var repo: Repository

    // Imperial/Metric display preference (D#103). Display-only: weight (kg) and skin temp (°C) re-label
    // here; everything else is unit-agnostic and renders unchanged.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw)
    }
    private func fmt(_ v: Double) -> String { metric.format(v, system: unitSystem, temperature: temperatureUnit) }

    @State private var range: ExploreRange = .month
    /// Full ascending series for this metric — ALL history.
    @State private var series: [(day: String, value: Double)] = []
    /// The series with each `day` string parsed to a `Date` exactly ONCE — the shared window math reads
    /// `date` straight from here (FER-269). Built in `load()`.
    @State private var parsed: MetricWindowMath.Parsed = []
    /// Every OTHER catalog series, loaded once for the correlation scan.
    @State private var others: [(metric: MetricDescriptor, series: [(day: String, value: Double)])] = []
    @State private var loaded = false

    /// Cached correlation scan, keyed by its inputs (selected range + the metric id), so the full
    /// cross-catalog Pearson sweep runs ONLY when those change — not on every body re-eval. Recomputed
    /// from `recomputeCorrelations(...)` after load and on range change.
    @State private var correlationCache: [CorrRow] = []
    /// The (metricID, range) the cache was built for; nil means "not yet computed".
    @State private var correlationKey: String? = nil

    // MARK: Derived

    private var latest: (day: String, value: Double)? { series.last }

    /// Padded value range so the line never sits flush against an axis — the old `valueRange` behavior:
    /// min..max ± 12% of the span. Receives the (already-smoothed/plotted) line values.
    private func valueRange(_ windowValues: [Double]) -> ClosedRange<Double> {
        guard let lo = windowValues.min(), let hi = windowValues.max() else { return 0...1 }
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let span = hi - lo
        return (lo - span * 0.12)...(hi + span * 0.12)
    }

    // MARK: Body

    var body: some View {
        // Compute the window ONCE per body eval and hand it to the blocks (the shared math, FER-269).
        let window = MetricWindowMath.make(parsed, selected: range)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero(window: window)
                if loaded && series.isEmpty {
                    // ONLY genuine empty state: no data in the entire history.
                    ChartWell(theme).empty(text: "Import your history first. A WHOOP export in Data Sources fills every metric you can explore here in about a minute.")
                } else if !loaded {
                    ChartWell(theme).loading(height: 160)
                } else {
                    blockDivider
                    trendBlock(window: window)
                    blockDivider
                    correlationBlock
                }
            }
            .padding(CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .navigationTitle(metric.title)
        .task(id: metric.id) { await load() }
        // Range changes the window, hence the correlation inputs — recompute the cached scan rather than
        // letting `correlationBlock` run it inside body.
        .onChange(of: range) { recomputeCorrelations() }
    }

    /// A subtle 1px rule between blocks (token-only). Mirrors the sibling «Instrumento» screens.
    private var blockDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    private func load() async {
        // Prefer the merged on-device dashboard (`displayDays`) over the imports-only `series()` table —
        // a strap user's computed scores live there, and `series()` is empty without a WHOOP export. Falls
        // back to imports for import-only metrics (weight, body fat, HR zones…). (FER-281)
        let dash = repo.displayDays

        let keysBySource = await repo.availableKeySets(sources: MetricCatalog.all.map(\.source))
        // Candidates for the correlation scan: every OTHER metric with data — on-device OR imported.
        let candidates = MetricCatalog.all.filter { other in
            guard other.id != metric.id else { return false }
            let onDevice = !(dashboardSeries(other.key, from: dash) ?? []).isEmpty
            let imported = keysBySource[other.source]?.contains(other.key) ?? false
            return onDevice || imported
        }

        let loadedOthers: [(metric: MetricDescriptor, series: [(day: String, value: Double)])] =
            await withTaskGroup(of: (MetricDescriptor, [(day: String, value: Double)]).self) { group in
                for other in candidates {
                    let onDevice = dashboardSeries(other.key, from: dash) ?? []
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
        let focalOnDevice = dashboardSeries(metric.key, from: dash) ?? []
        let focalSeries = focalOnDevice.isEmpty
            ? await repo.series(key: metric.key, source: metric.source)
            : focalOnDevice
        series = focalSeries
        parsed = focalSeries.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
        // TaskGroup completion order is nondeterministic — restore catalog order so the correlation list
        // is stable across loads (recomputeCorrelations re-sorts by |r| for display).
        let catalogIndex = Dictionary(uniqueKeysWithValues: MetricCatalog.all.enumerated().map { ($1.id, $0) })
        others = loadedOthers.sorted { (catalogIndex[$0.metric.id] ?? 0) < (catalogIndex[$1.metric.id] ?? 0) }
        loaded = true
        recomputeCorrelations()
    }

    // MARK: - 1. Hero — la última lectura + "as of", número en el accent de categoría

    private func hero(window: MetricWindow) -> some View {
        let asOf: String = {
            guard let day = latest?.day, let d = Repository.parseDayKey(day) else { return "—" }
            return String(localized: "as of \(longDate(d))")
        }()
        let heroValue = latest.map { fmt($0.value) } ?? "—"
        let accent = metricAccent(metric, theme: theme)
        return VStack(alignment: .leading, spacing: 6) {
            Text(metric.localizedCategory).groteskOverline().foregroundStyle(theme.inkTertiary)
            Text(heroValue)
                .instrumentoHero(44)
                .foregroundStyle(latest == nil ? theme.inkTertiary : accent)
            Text(asOf)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkTertiary)
            // FER-670: when a second source reported the shown day (steps / sleep total / active kcal),
            // say whether they agree — both values stay visible, a conflict is flagged, never averaged.
            // `fusionPoint` folds the calorie alias (`energy_kcal`→`active_kcal`) via the policy, so the
            // raw catalog key works here.
            if let day = latest?.day,
               let agreement = repo.fusionPoint(day: day, metric: metric.key) {
                FusionAgreementRow(point: agreement, theme: theme, format: fmt)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 2. Selector de periodo + Tendencia (línea cruda) + TrendStatSummary

    private func trendBlock(window: MetricWindow) -> some View {
        let stat = ComparisonEngine.stat(window.values)
        // Compare the selected window against the equally-long window before it. `.all` has no previous
        // period, so no chip. (FER-264)
        let comparison = window.range.periodComparison(of: series)
        let accent = metricAccent(metric, theme: theme)
        let polarity: TrendStatSummary.Polarity = {
            switch metric.higherIsBetter {
            case .some(true):  return .higherIsBetter
            case .some(false): return .lowerIsBetter
            case .none:        return .neutral
            }
        }()
        return VStack(alignment: .leading, spacing: 10) {
            // Raw line (no moving average — the dossier traced the windowed values directly).
            MetricTrendChart(
                range: $range,
                window: window,
                theme: theme,
                style: .init(
                    smoothing: nil,
                    gradient: ChartWell.fillGradient(accent),
                    valueRange: { valueRange($0) },
                    valueFormat: { fmt($0) },
                    accessibilityLabel: "\(metric.title) trend"
                )
            ) {
                ChartWell(theme).empty(text: "Not enough days in this range to draw a trend.")
            }
            if window.values.count > 1 {
                TrendStatSummary(
                    average: fmt(stat.mean),
                    pctChange: comparison?.pctChange,
                    polarity: polarity,
                    period: window.range.comparisonPeriod ?? .month,
                    rangeLow: fmt(stat.min),
                    rangeHigh: fmt(stat.max),
                    theme: theme)
            }
        }
    }

    // MARK: - 3. Correlaciones («What correlates»)

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

    /// Top |r| catalog metrics over a given window (|r| ≥ 0.30, n ≥ 10). Pure — Sendable in, Sendable
    /// out — runs inside `Task.detached` (FER-976). `nonisolated` opts OUT of this View's inferred
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

    /// Rebuild the cached correlation scan for the CURRENT effective window, only when its key (metric
    /// id + selected range) changed — re-evals that don't alter the inputs are no-ops. The (expensive)
    /// cross-catalog Pearson sweep runs off the MainActor via `Task.detached` (FER-976): a Sendable
    /// (day,value) snapshot in, a Sendable scan out; `correlationCache` is assigned back on MainActor by
    /// reattaching the catalog `MetricDescriptor` (it isn't Sendable-verified, so it never crosses the hop).
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

    private var correlationBlock: some View {
        let rows = correlationCache
        return VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What correlates").groteskOverline().foregroundStyle(theme.inkTertiary)
                Text("Pearson r over the visible window · |r| ≥ 0.30, n ≥ 10")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                // Association, not cause. (FER-299)
                Text("Association, not cause: these move together, neither drives the other.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if rows.isEmpty {
                Text("Nothing in the catalog moves clearly with \(metric.title.lowercased()) over this window. Widen the range to surface relationships.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        correlationRowView(row)
                        if idx < rows.count - 1 {
                            Rectangle().fill(theme.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func correlationRowView(_ row: CorrRow) -> some View {
        let color = correlationColor(row.r)
        HStack(spacing: 12) {
            Image(systemName: row.metric.icon)
                .font(StrandFont.glyph(.inline, weight: .medium))
                .foregroundStyle(theme.inkSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.metric.title)
                    .font(StrandFont.body)
                    .foregroundStyle(theme.ink)
                Text("\(row.metric.localizedCategory) · n = \(row.n)")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.hairline)
                        Capsule().fill(color)
                            .frame(width: max(4, geo.size.width * min(abs(row.r), 1.0)))
                    }
                }
                .frame(width: 64, height: 6)
                Text("\(row.r >= 0 ? "+" : "−")\(String(format: "%.2f", abs(row.r)))")
                    .font(StrandFont.number(15))
                    .foregroundStyle(color)
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.metric.title), correlation \(String(format: "%.2f", row.r)), \(row.n) days")
    }

    /// Positive correlations ride the verdict green, negative ones the contained brick red — the two
    /// «Instrumento» state roles, so the sign reads as direction (not decoration).
    private func correlationColor(_ r: Double) -> Color {
        r >= 0 ? theme.verdict : theme.critical
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
