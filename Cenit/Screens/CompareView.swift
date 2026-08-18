import SwiftUI
import Foundation
import Charts
import StrandDesign
import StrandAnalytics
import CenitStore

// MARK: - Compare — en lenguaje «Instrumento diurno» (FER-268)
//
// The "overlay metrics & draw conclusions" screen. Pick 2–4 metrics from the
// catalog, choose a time window, and read them on a single normalized overlay
// chart (each metric min–max scaled to 0–1 within the window so different units
// share an axis). Below, every pair of selected metrics gets a live Pearson-r
// correlation readout with a plain-English conclusion. Pure read-side: each
// metric loads from repo.series; everything else is derived in-view.
//
// Visual language: «Instrumento diurno» (FER-131) — warm paper, color ONLY in the
// datum (the overlay lines and the r value), hierarchy by space. Presented from
// Cuerpo as a light `.sheet` with the live theme injected at the root (it doesn't
// cross the `.sheet` boundary, FER-162) and NO nested NavigationStack (FER-171);
// you drag to dismiss. Was a dark legacy sheet before the reskin.

// yyyy-MM-dd → Date, fixed UTC / en_US_POSIX — the shared day-key parser (FER-325).
private func parseCompareDay(_ day: String) -> Date? { Repository.parseDayKey(day) }

// MARK: - Range control (shared spec — W / M / 3M / 6M / 1Y / ALL)

/// The canonical Strand range window. `days == nil` means ALL of history.
enum CompareRange: String, CaseIterable, Identifiable {
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

    /// The trailing window length in days; nil = everything.
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

    /// A human phrase for sentences ("over 1Y").
    var phrase: String {
        switch self {
        case .week:    return String(localized: "the last 7 days")
        case .month:   return String(localized: "30 days")
        case .quarter: return String(localized: "3 months")
        case .half:    return String(localized: "6 months")
        case .year:    return String(localized: "1 year")
        case .all:     return String(localized: "all history")
        }
    }

    /// This range plus every LARGER range, ascending — the auto-expand search order
    /// when a selected window holds zero points for a series.
    var widening: [CompareRange] {
        let order: [CompareRange] = [.week, .month, .quarter, .half, .year, .all]
        guard let i = order.firstIndex(of: self) else { return [.all] }
        return Array(order[i...])
    }
}

// MARK: - Per-series model

/// One selected metric, resolved over the active window: its descriptor, the
/// windowed (day,value) rows, a stable display color, and its real min/max.
private struct CompareSeries: Identifiable {
    let metric: MetricDescriptor
    let color: Color
    let rows: [(day: String, value: Double)]

    var id: String { metric.id }
    var values: [Double] { rows.map(\.value) }
    var realMin: Double { values.min() ?? 0 }
    var realMax: Double { values.max() ?? 0 }

    /// Min–max normalize a value into 0…1 within this series' window. Flat series
    /// (max == min) collapse to the mid-line so they still render.
    func normalized(_ v: Double) -> Double {
        let lo = realMin, hi = realMax
        guard hi > lo else { return 0.5 }
        return min(max((v - lo) / (hi - lo), 0), 1)
    }

    /// The value on a given day, if recorded.
    func value(on day: String) -> Double? {
        rows.first(where: { $0.day == day })?.value
    }
}

// MARK: - Root

struct CompareView: View {
    @EnvironmentObject var repo: Repository
    /// The live «Instrumento» theme, injected at the sheet root by Cuerpo (it doesn't propagate through
    /// `.sheet`, FER-162). Drives every surface, ink and datum color on the warm paper.
    @Environment(\.instrumentoTheme) private var theme

    /// Distinct, high-legibility series colors on warm paper: the «Instrumento» data hues (deep,
    /// saturated — NOT the bright dark-system ramps, which bleach on light paper). All four clear AA at
    /// numeral/line weight. Order is the legend + color mapping (verdict green → HRV cyan → sleep indigo
    /// → strain ember). (FER-268)
    private var seriesPalette: [Color] {
        [theme.verdict, theme.dataHrv, theme.dataSleep, theme.dataStrain]
    }

    /// Default starter selection (falls back gracefully if a key is missing). All three resolve from the
    /// merged dashboard (`displayDays`), so a strap user sees an overlay on first open — not an empty
    /// well — without importing a CSV. (FER-275)
    private static let defaultKeys = ["recovery", "strain", "hrv"]

    @State private var range: CompareRange = .year
    /// Ordered selection (max 4). Drives both the legend order and color mapping.
    @State private var selected: [MetricDescriptor] = []
    /// Presents the metric picker as a scroll-stable sheet. A SwiftUI `Menu` rebuilds (and resets its
    /// scroll to the top) every time the parent re-renders — and Compare re-renders on each `repo` tick
    /// while the strap syncs — so a long catalog menu was unusable: scrolling down snapped back up. A
    /// `.sheet` keeps its own scroll state across parent re-renders. (FER-279)
    @State private var showPicker = false
    /// Full-history series per selected metric id (ascending by day).
    @State private var fullSeries: [String: [(day: String, value: Double)]] = [:]
    @State private var loadedOnce = false

    /// Cache of the last pairwise-correlation scan + the inputs it was computed for.
    /// The scan (alignByDay + Pearson over full windows) is expensive and was re-run on
    /// every body evaluation — including hover/animation/HR ticks. We recompute it only
    /// when the windowed series content actually changes (see `correlationKey`).
    @State private var pairCache: [PairResult] = []
    @State private var pairCacheKey: String = ""

    /// `activeSeries` recomputed ONLY on selection/range/fetch change (FER-976) — the plain computed
    /// property below was re-derived on every access (≥4×/render: overlay, correlation, rangeCaption,
    /// task/onChange), each pass re-slicing `fullSeries` per selected metric.
    @State private var activeSeriesCache: [CompareSeries] = []

    private let maxSelection = 4
    private let minSelection = 2

    var body: some View {
        ScrollView {
            // Rhythm by space: sections breathe on `sectionGap`, no rule between them — hierarchy by
            // space, not boxes (DESIGN.md §8). Color lives only on the overlay lines and the r value.
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                header
                metricSection

                if selected.count < minSelection {
                    ChartWell(theme, icon: "arrow.left.arrow.right", cornerRadius: CenitMetrics.cardRadius, bordered: true).empty(text: "Compare needs at least two metrics with history. Connect Apple Health in Data Sources first.")
                } else {
                    let series = activeSeries
                    if series.allSatisfy({ $0.rows.isEmpty }) {
                        ChartWell(theme, icon: "arrow.left.arrow.right", cornerRadius: CenitMetrics.cardRadius, bordered: true).empty(text: loadedOnce
                            ? "No data for these metrics in \(range.phrase). Widen the range or pick metrics you've logged."
                            : "Reading your history…")
                    } else {
                        overlaySection(series)
                        correlationSection(series)
                    }
                }
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, 20)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
        .sheet(isPresented: $showPicker) {
            MetricPickerSheet(selected: $selected, maxSelection: maxSelection, theme: theme)
        }
        .task { await loadIfNeeded() }
        .task(id: selectionKey) {
            await loadSelected()
            recomputeActiveSeries()
            refreshPairCache(activeSeries)
        }
        // FER-976: range is the other input `activeSeries` depends on (selection is covered by
        // `.task(id: selectionKey)` above via `selectionKey`).
        .onChange(of: range) {
            recomputeActiveSeries()
        }
        // Recompute the pairwise scan only when the windowed series content changes,
        // never on hover/animation/HR-tick re-renders that don't touch these inputs.
        .onChange(of: correlationKey(activeSeries)) {
            refreshPairCache(activeSeries)
        }
    }

    // MARK: - Title

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Compare").font(InstrumentoType.groteskHeadline(28)).foregroundStyle(theme.ink)
            Text("Overlay signals, draw conclusions.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Selection key (re-loads when the set of metrics changes)

    private var selectionKey: String { selected.map(\.id).sorted().joined(separator: "|") }

    // MARK: - Active windowed series

    /// A full-history series' rows over a given range, taken RELATIVE TO THAT SERIES'
    /// LATEST data point (not "now"); `.all` returns everything.
    private func slice(_ full: [(day: String, value: Double)], _ r: CompareRange) -> [(day: String, value: Double)] {
        guard let n = r.days else { return full }
        guard let lastDay = full.last?.day, let last = parseCompareDay(lastDay) else { return [] }
        let cutoff = last.addingTimeInterval(-Double(n - 1) * 86_400)
        return full.filter { row in
            guard let d = parseCompareDay(row.day) else { return false }
            return d >= cutoff
        }
    }

    /// The range actually used for a series: the SELECTED range when its window holds
    /// ≥1 point, else the smallest LARGER range that does. So sparse metrics still
    /// overlay against dense ones, and switching ranges stays visibly distinct.
    private func effectiveRange(_ full: [(day: String, value: Double)]) -> CompareRange {
        guard !full.isEmpty else { return range }
        for r in range.widening where !slice(full, r).isEmpty { return r }
        return .all
    }

    /// Selected metrics resolved to windowed rows + stable colors, in pick order. Reads the memoized
    /// cache (FER-976) — see `recomputeActiveSeries()`, called from `.task(id: selectionKey)` and
    /// `.onChange(of: range)`, the only two inputs this depends on.
    private var activeSeries: [CompareSeries] { activeSeriesCache }

    private func recomputeActiveSeries() {
        activeSeriesCache = selected.enumerated().map { idx, metric in
            let full = fullSeries[metric.id] ?? []
            let rows = slice(full, effectiveRange(full))
            return CompareSeries(
                metric: metric,
                color: seriesPalette[idx % seriesPalette.count],
                rows: rows
            )
        }
    }

    /// True if any selected series had to auto-widen past the selected range.
    private var anyWidened: Bool {
        selected.contains { metric in
            let full = fullSeries[metric.id] ?? []
            return !full.isEmpty && effectiveRange(full) != range
        }
    }

    /// "N readings · <range>" caption near the control, flagging any auto-widen.
    private var rangeCaption: String {
        let series = activeSeries
        let total = series.reduce(0) { $0 + $1.rows.count }
        let unit = total == 1 ? "reading" : "readings"
        let base = "\(total) \(unit) across \(series.count) · \(range.phrase)"
        return anyWidened ? base + " · sparse widened" : base
    }

    // MARK: - Loading

    private func loadIfNeeded() async {
        guard selected.isEmpty else { return }
        // Seed the default selection from whichever default keys exist.
        var picks: [MetricDescriptor] = []
        for key in Self.defaultKeys {
            if let m = MetricCatalog.all.first(where: { $0.key == key }) { picks.append(m) }
        }
        if picks.isEmpty { picks = Array(MetricCatalog.all.prefix(2)) }
        selected = Array(picks.prefix(maxSelection))
    }

    /// Load (and cache) the full history for any selected metric not yet fetched.
    ///
    /// Two data paths (FER-275): metrics that are nightly dashboard fields read from `repo.displayDays`
    /// — the merged source Cuerpo/Today use, which resolves for **strap users** (their computed scores
    /// live under "<deviceId>-noop", which the import-only `repo.series()` never sees). Everything else
    /// (Apple-Health body metrics, HR-zone splits, derived sleep percentages) falls back to `series()`.
    /// Full history is kept on purpose: `slice`/`effectiveRange` auto-widen a sparse series past the
    /// selected range to ALL, so the cache must hold every row — the window is applied in-view (FER-27).
    private func loadSelected() async {
        let missing = selected.filter { fullSeries[$0.id] == nil }
        // Dashboard-resolvable metrics: extract synchronously from the in-memory merged dashboard.
        var resolved: [(id: String, series: [(day: String, value: Double)])] = []
        var needsSeries: [MetricDescriptor] = []
        for metric in missing {
            if let pick = Self.dailyPicker(for: metric.key) {
                resolved.append((metric.id, dailySeries(pick)))
            } else {
                needsSeries.append(metric)
            }
        }
        // The genuinely import-/Apple-only metrics still load (concurrently) from `series()`.
        let fetched = await withTaskGroup(of: (String, [(day: String, value: Double)]).self) { group in
            for metric in needsSeries {
                group.addTask { (metric.id, await repo.series(key: metric.key, source: metric.source)) }
            }
            var out: [(id: String, series: [(day: String, value: Double)])] = []
            for await (id, s) in group { out.append((id, s)) }
            return out
        }
        for (id, s) in resolved { fullSeries[id] = s }
        for (id, s) in fetched  { fullSeries[id] = s }
        loadedOnce = true
    }

    /// A metric's full daily history (ascending by day) from the merged dashboard — same contract as
    /// `repo.series()`, but resolving for strap users too. (FER-275)
    private func dailySeries(_ pick: (DailyMetric) -> Double?) -> [(day: String, value: Double)] {
        repo.displayDays
            .compactMap { row in pick(row).map { (row.day, $0) } }
            .sorted { $0.day < $1.day }
    }

    /// The nightly-dashboard field for a metric key, or `nil` for keys that aren't computed on-device
    /// (body composition, HR-zone splits, derived sleep percentages) — those keep the import-/Apple-only
    /// `series()` path. Mirrors the per-metric extraction Cuerpo's rows + `vitalSeries` already use. (FER-275)
    private static func dailyPicker(for key: String) -> ((DailyMetric) -> Double?)? {
        switch key {
        case "recovery":         return { $0.recovery }
        case "strain":           return { $0.strain }
        case "hrv":              return { $0.avgHrv }
        case "rhr":              return { $0.restingHr.map(Double.init) }
        case "resp_rate":        return { $0.respRateBpm }
        case "spo2":             return { $0.spo2Pct }
        case "skin_temp":        return { $0.skinTempDevC }
        case "steps":            return { $0.steps.map(Double.init) }
        case "sleep_total_min":  return { $0.totalSleepMin }
        case "sleep_deep_min":   return { $0.deepMin }
        case "sleep_rem_min":    return { $0.remMin }
        case "sleep_light_min":  return { $0.lightMin }
        case "sleep_efficiency": return { $0.efficiency.map { $0 <= 1.0 ? $0 * 100 : $0 } }
        // NOTE: `active_kcal` stays on the `series()` path on purpose — the catalog sources it from Apple
        // Health, and the dashboard's `activeKcalEst` is a *different* figure (an HR-only whole-day
        // estimate), so resolving it here would silently swap that metric's meaning. (FER-275)
        default:                 return nil
        }
    }

    // MARK: - Metric picker section (range control + chips, on a contained surface)

    // The controls live directly on the paper (no surface card): hierarchy by space, not boxes
    // (Instrumento rule 3), and the full screen width keeps the 6-segment range control from wrapping
    // — the earlier card padding squeezed "ALL"/«TODO» onto a second line. (FER-275)
    private var metricSection: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            Text("Metrics").groteskOverline().foregroundStyle(theme.inkTertiary)

            SegmentedPillControl(CompareRange.allCases, selection: $range, theme: theme) { $0.label }
                .accessibilityLabel("Time range")

            HStack(alignment: .firstTextBaseline) {
                if selected.count >= minSelection {
                    Text(rangeCaption)
                        .font(StrandFont.footnote)
                        .foregroundStyle(anyWidened ? theme.warning : theme.inkTertiary)
                        .accessibilityLabel(rangeCaption)
                }
                Spacer(minLength: 8)
                addButton
            }

            if selected.isEmpty {
                Text("Nothing selected yet.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkTertiary)
            } else {
                FlowChips(metrics: selected, colorFor: colorFor, theme: theme) { metric in
                    remove(metric)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Opens the metric picker sheet. (A button, not a `Menu`: a long `Menu` resets its scroll on every
    /// parent re-render — unusable while the strap syncs. See `showPicker`. FER-279.) Always tappable —
    /// the picker is where you both add and remove, so it stays reachable at the 4-metric cap.
    private var addButton: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text(selected.count >= maxSelection ? "Max 4" : "Add metric")
                    .font(StrandFont.subhead)
            }
            .foregroundStyle(selected.count >= maxSelection ? theme.inkTertiary : theme.verdict)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Add or remove metrics")
    }

    private func colorFor(_ metric: MetricDescriptor) -> Color {
        guard let idx = selected.firstIndex(of: metric) else { return theme.inkSecondary }
        return seriesPalette[idx % seriesPalette.count]
    }

    private func remove(_ metric: MetricDescriptor) {
        withAnimation(StrandMotion.gentle) { selected.removeAll { $0 == metric } }
    }

    // MARK: - Overlay chart section

    @ViewBuilder
    private func overlaySection(_ series: [CompareSeries]) -> some View {
        let nonEmpty = series.filter { !$0.rows.isEmpty }
        block(title: "Overlay", trailing: "\(nonEmpty.count) series") {
            VStack(alignment: .leading, spacing: 12) {
                Text(anyWidened
                    ? "Min–max normalized · sparse series widened past \(range.phrase) · hover for real values"
                    : "Each line min–max normalized within \(range.phrase) · hover for real values")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                OverlayChart(series: nonEmpty, theme: theme, height: CenitMetrics.chartHeight)
                legend(nonEmpty)
            }
        }
    }

    private func legend(_ series: [CompareSeries]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(series.enumerated()), id: \.element.id) { idx, s in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)   // token-exempt: geometría de dato (muestra de leyenda)
                        .fill(s.color)
                        .frame(width: 14, height: 3)
                    Text(s.metric.title)
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.ink)
                    Spacer()
                    Text("\(s.metric.format(s.realMin)) – \(s.metric.format(s.realMax))")
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(theme.inkSecondary)
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(s.metric.title), range \(s.metric.format(s.realMin)) to \(s.metric.format(s.realMax))")
                if idx < series.count - 1 {
                    Divider().overlay(theme.hairline)
                }
            }
        }
    }

    // MARK: - Pairwise correlations

    private struct PairResult: Identifiable {
        let id: String
        let a: CompareSeries
        let b: CompareSeries
        let r: Double
        let n: Int
    }

    /// A Sendable-only scan result — no `Color`/`CompareSeries` — so it can cross the `Task.detached`
    /// hop (FER-976). `attachPairResults` reattaches the display-only `CompareSeries` on MainActor.
    private struct PairScan: Sendable {
        let aId: String
        let bId: String
        let r: Double
        let n: Int
    }

    /// A stable fingerprint of the inputs the correlation scan depends on: the
    /// non-empty series (in order) and their windowed content. Row content only
    /// changes when `selected`, `range`, or fetched `fullSeries` change, so this
    /// covers every case that alters the scan result. Used to invalidate `pairCache`.
    private func correlationKey(_ series: [CompareSeries]) -> String {
        series
            .filter { !$0.rows.isEmpty }
            .map { s in "\(s.id):\(s.rows.count):\(s.rows.first?.day ?? "")>\(s.rows.last?.day ?? "")" }
            .joined(separator: "|")
    }

    /// Cached accessor used by the body. Returns the memoized scan when the inputs
    /// match `pairCacheKey`; otherwise computes once for THIS render (without mutating
    /// state — that would be illegal mid-body) so the visible result is never stale by
    /// a frame. The matching `.onChange`/`.task` then persists the same result into
    /// `@State`, so subsequent renders (hover/animation/HR ticks) hit the cache.
    private func pairResults(_ series: [CompareSeries]) -> [PairResult] {
        correlationKey(series) == pairCacheKey ? pairCache : computePairResults(series)
    }

    /// The actual (expensive) pairwise scan, pure — Sendable in, Sendable out — so it's usable both
    /// synchronously (below) AND inside `Task.detached` (FER-976). `nonisolated` opts OUT of this
    /// View's inferred MainActor isolation.
    private nonisolated static func computePairScans(
        _ series: [(id: String, rows: [(day: String, value: Double)])]
    ) -> [PairScan] {
        var out: [PairScan] = []
        guard series.count >= 2 else { return out }
        for i in 0..<(series.count - 1) {
            for j in (i + 1)..<series.count {
                let pairs = CorrelationEngine.alignByDay(series[i].rows, series[j].rows)
                guard pairs.count >= 3, let c = CorrelationEngine.pearson(pairs) else { continue }
                out.append(PairScan(aId: series[i].id, bId: series[j].id, r: c.r, n: c.n))
            }
        }
        // Strongest relationships first.
        out.sort { abs($0.r) > abs($1.r) }
        return out
    }

    /// Reattaches a Sendable `PairScan` to the display-only `CompareSeries` (color/metric), by id.
    private func attachPairResults(_ scans: [PairScan], series: [CompareSeries]) -> [PairResult] {
        let byId = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        return scans.compactMap { scan in
            guard let a = byId[scan.aId], let b = byId[scan.bId] else { return nil }
            return PairResult(id: "\(scan.aId)~\(scan.bId)", a: a, b: b, r: scan.r, n: scan.n)
        }
    }

    /// The actual (expensive) pairwise scan. Pure — no view state read/written. Synchronous — used ONLY
    /// as `pairResults(_:)`'s same-frame fallback (see its doc above); the scheduled/background refresh
    /// below (`refreshPairCache`) runs the SAME math off-main via `Task.detached`.
    private func computePairResults(_ series: [CompareSeries]) -> [PairResult] {
        let s = series.filter { !$0.rows.isEmpty }
        return attachPairResults(Self.computePairScans(s.map { (id: $0.id, rows: $0.rows) }), series: s)
    }

    /// Recompute the pair cache if (and only if) the correlation inputs changed. Dispatches the
    /// (expensive) scan to `Task.detached` off a Sendable (id, rows) snapshot — never a raw
    /// `CompareSeries` (it carries a `Color`) — then reattaches + assigns `pairCache` back on MainActor
    /// (FER-976), same seam as `PreparacionDetalleModelo.buildDetached`.
    private func refreshPairCache(_ series: [CompareSeries]) {
        let key = correlationKey(series)
        guard key != pairCacheKey else { return }
        pairCacheKey = key
        let s = series.filter { !$0.rows.isEmpty }
        let snapshot = s.map { (id: $0.id, rows: $0.rows) }
        Task {
            let scans = await Task.detached(priority: .userInitiated) {
                Self.computePairScans(snapshot)
            }.value
            guard pairCacheKey == key else { return }   // a newer selection/range landed first
            pairCache = attachPairResults(scans, series: s)
        }
    }

    @ViewBuilder
    private func correlationSection(_ series: [CompareSeries]) -> some View {
        let pairs = pairResults(series)
        block(title: "How They Move Together", trailing: pairs.isEmpty ? nil : "\(pairs.count) pairs") {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("Pearson r · \(range.phrase)")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)

                // Association, not cause: overlapping trends move together; that's not
                // one causing the other. (FER-299)
                Text("Association, not cause: moving together isn't one driving the other.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if pairs.isEmpty {
                    ChartWell(theme, icon: "arrow.left.arrow.right", cornerRadius: CenitMetrics.cardRadius, bordered: true).empty(text: "Not enough overlapping days between these metrics in \(range.phrase). Widen the range.")
                } else {
                    ForEach(pairs) { p in
                        pairCard(p)
                    }
                }
            }
        }
    }

    /// One pairwise correlation on its own surface card.
    private func pairCard(_ p: PairResult) -> some View {
        let tint = correlationColor(p.r)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Two color swatches for the pair.
                HStack(spacing: 3) {
                    Circle().fill(p.a.color).frame(width: 8, height: 8)
                    Circle().fill(p.b.color).frame(width: 8, height: 8)
                }
                Text("\(p.a.metric.title) ↔ \(p.b.metric.title)")
                    .font(StrandFont.headline)
                    .foregroundStyle(theme.ink)
                Spacer()
                Text("r = \(signedR(p.r))")
                    .font(InstrumentoType.groteskNumber(18))
                    .foregroundStyle(tint)
            }

            Text(insightSentence(p))
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(p.n) overlapping days · \(strengthWord(p.r)) \(directionWord(p.r)) correlation")
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
        }
        .padding(CenitMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.a.metric.title) versus \(p.b.metric.title), r equals \(String(format: "%.2f", p.r)), \(p.n) days")
    }

    // MARK: - Shared scaffold + wells (mirrors SleepDetailScreen / MetricDetailScreen)

    /// A titled block on the paper: a quiet overline (+ optional trailing count) and content — no
    /// card-in-card; `surface` is used sparingly inside (Instrumento rule 3).
    @ViewBuilder
    private func block<Content: View>(title: LocalizedStringKey, trailing: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).groteskOverline().foregroundStyle(theme.inkTertiary)
                if let trailing {
                    Spacer(minLength: 8)
                    Text(trailing).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Insight language

    /// "Weight ↔ Recovery: r = −0.34 (moderate negative) over 1Y" + a plain-English
    /// conclusion when |r| is notable.
    private func insightSentence(_ p: PairResult) -> String {
        let head = String(localized: "\(p.a.metric.title) ↔ \(p.b.metric.title): r = \(signedR(p.r)) (\(strengthWord(p.r)) \(directionWord(p.r))) over \(p.n) shared days.")
        guard abs(p.r) >= 0.3 else {
            return head + String(localized: " No clear relationship: they move largely independently.")
        }
        let lower = p.r < 0
        let aT = p.a.metric.title.lowercased()
        let bT = p.b.metric.title.lowercased()
        let verb = lower ? String(localized: "tends to fall") : String(localized: "tends to rise")
        return head + String(localized: " When \(aT) rises, \(bT) \(verb): a \(strengthWord(p.r)) \(directionWord(p.r)) link.")
    }

    private func signedR(_ r: Double) -> String {
        (r >= 0 ? "+" : "−") + String(format: "%.2f", abs(r))
    }

    private func strengthWord(_ r: Double) -> String {
        switch abs(r) {
        case ..<0.1:  return String(localized: "negligible")
        case ..<0.3:  return String(localized: "weak")
        case ..<0.5:  return String(localized: "moderate")
        case ..<0.7:  return String(localized: "strong")
        default:      return String(localized: "very strong")
        }
    }

    private func directionWord(_ r: Double) -> String {
        if abs(r) < 0.1 { return "" }
        return r >= 0 ? String(localized: "positive") : String(localized: "negative")
    }

    /// The r value is the datum, so it carries the only saturated hue in the card: verdict green for a
    /// positive link, the contained brick red for a negative one (red reserved for genuine signal).
    private func correlationColor(_ r: Double) -> Color {
        r >= 0 ? theme.verdict : theme.critical
    }
}

// MARK: - Selected-metric chips (wrapping flow layout)

/// Removable chips for the active selection, tinted to each series' color, on warm paper.
private struct FlowChips: View {
    let metrics: [MetricDescriptor]
    let colorFor: (MetricDescriptor) -> Color
    var theme: InstrumentoTheme
    let onRemove: (MetricDescriptor) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(metrics) { metric in
                let color = colorFor(metric)
                HStack(spacing: 7) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(metric.title)
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Button {
                        onRemove(metric)
                    } label: {
                        StrandIcon.close.image
                            .font(.system(size: 9, weight: .bold))   // token-exempt: microtexto <10pt
                            .foregroundStyle(theme.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(metric.title)")
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous).fill(theme.paper)
                )
                .overlay(
                    Capsule(style: .continuous).stroke(color.opacity(0.4), lineWidth: 1)   // token-exempt: 0.4 en frontera de banda (strokeSoft .30 aclararía el borde)
                )
            }
        }
    }
}

// MARK: - Metric picker sheet (scroll-stable replacement for the catalog Menu)

/// The "add / remove metrics" picker, as a light «Instrumento» sheet (FER-279). Replaces the old
/// catalog `Menu`, which reset its scroll to the top on every parent re-render — so on a syncing strap
/// you couldn't scroll it. A `.sheet` owns its scroll state across re-renders. Grouped by catalog
/// category; tap a row to toggle (a checkmark marks the picked ones); rows disable at the 4-metric cap,
/// but already-picked rows stay tappable so you can swap. Mutates the shared `selected` binding; you
/// drag down to dismiss.
private struct MetricPickerSheet: View {
    @Binding var selected: [MetricDescriptor]
    let maxSelection: Int
    var theme: InstrumentoTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("Metrics").font(InstrumentoType.groteskHeadline(22)).foregroundStyle(theme.ink)
                Text("Pick 2–4 to overlay.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .padding(.bottom, 4)

                ForEach(MetricCatalog.categories, id: \.self) { category in
                    let metrics = MetricCatalog.inCategory(category)
                    if !metrics.isEmpty {
                        Text(MetricCatalog.localizedCategory(category))
                            .groteskOverline().foregroundStyle(theme.inkTertiary)
                            .padding(.top, 10)
                        VStack(spacing: 0) {
                            ForEach(Array(metrics.enumerated()), id: \.element.id) { i, metric in
                                row(metric)
                                if i < metrics.count - 1 { Divider().overlay(theme.hairline) }
                            }
                        }
                    }
                }
            }
            .padding(CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .sheetPaper(theme)
    }

    private func row(_ metric: MetricDescriptor) -> some View {
        let isOn = selected.contains(metric)
        let atCap = !isOn && selected.count >= maxSelection
        return Button {
            withAnimation(StrandMotion.gentle) {
                if isOn { selected.removeAll { $0 == metric } }
                else if selected.count < maxSelection { selected.append(metric) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: metric.icon)
                    .font(StrandFont.glyph(.inline))
                    .foregroundStyle(atCap ? theme.inkTertiary : theme.inkSecondary)
                    .frame(width: 24)
                Text(metric.title)
                    .font(StrandFont.body)
                    .foregroundStyle(atCap ? theme.inkTertiary : theme.ink)
                Spacer(minLength: 8)
                if isOn {
                    StrandIcon.confirm.image
                        .font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(theme.verdict)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(atCap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Overlay chart (custom multi-line Swift Chart, normalized 0–1)

/// Draws each series as its own colored line on a shared 0…1 normalized y-axis.
/// Hovering reveals a crosshair plus a tooltip listing every series' REAL value on
/// the nearest day.
private struct OverlayChart: View {
    let series: [CompareSeries]
    var theme: InstrumentoTheme
    var height: CGFloat = 260

    @State private var hoverX: CGFloat? = nil
    /// Day currently under the finger (nil when not scrubbing) — drives VoiceOver value. (FER-977)
    @State private var a11yDay: String? = nil

    // A flat, plottable point: the series title (drives the categorical color
    // scale), the date, and the min–max normalized y.
    private struct Plot: Identifiable {
        // Stable identity (one value per metric per day) so Chart can diff across renders instead
        // of treating every point as new on each hover tick — was `UUID()`, which forced full rebuilds.
        var id: String { title + "@" + String(date.timeIntervalSince1970) }
        let title: String
        let date: Date
        let norm: Double
    }

    /// All series flattened into normalized plot points (dropping unparseable days), and the
    /// union of all days present (ascending) for hover snapping. Both are derived purely from
    /// `series`, so they're computed ONCE in init — not on every `body` pass. Swift Charts
    /// re-evaluates `body` on every hover tick; recomputing the flatten/parse/sort there meant
    /// rebuilding the whole dataset per cursor move. `init` only re-runs when the parent passes
    /// new `series`, never when the internal `hoverX` @State changes (FER-319).
    private let plots: [Plot]
    private let allDays: [String]
    /// Day strings paired with their already-parsed dates — built once in init so
    /// hover/scrub nearest-day lookup never re-parses strings per frame.
    private let allDates: [(day: String, date: Date)]

    init(series: [CompareSeries], theme: InstrumentoTheme, height: CGFloat = 260) {
        self.series = series
        self.theme = theme
        self.height = height
        self.plots = series.flatMap { s in
            s.rows.compactMap { row -> Plot? in
                guard let d = parseCompareDay(row.day) else { return nil }
                return Plot(title: s.metric.title, date: d, norm: s.normalized(row.value))
            }
        }
        var set = Set<String>()
        for s in series { for r in s.rows { set.insert(r.day) } }
        self.allDays = set.sorted()
        self.allDates = set.compactMap { day -> (day: String, date: Date)? in
            guard let date = parseCompareDay(day) else { return nil }
            return (day: day, date: date)
        }.sorted { $0.date < $1.date }
    }

    private static let a11yDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    /// VoiceOver value: scrub day if active, else the last day present across series. (FER-977)
    private var accessibilityValueText: String {
        let day = a11yDay ?? allDays.last
        guard let day else { return "No data" }
        let dateStr: String = {
            if let d = parseCompareDay(day) { return Self.a11yDateFmt.string(from: d) }
            return day
        }()
        let values = series.map { s -> String in
            let formatted = s.value(on: day).map { s.metric.format($0) } ?? "—"
            return "\(s.metric.title) \(formatted)"
        }
        return values.joined(separator: ", ") + ", on \(dateStr)"
    }

    private var accessibilityLabelText: String {
        let names = series.map(\.metric.title).joined(separator: ", ")
        return "Comparing \(names)"
    }

    var body: some View {
        Chart(plots) { p in
            LineMark(
                x: .value("Date", p.date),
                y: .value("Normalized", p.norm)
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .foregroundStyle(by: .value("Metric", p.title))

            PointMark(
                x: .value("Date", p.date),
                y: .value("Normalized", p.norm)
            )
            .symbolSize(10)
            .foregroundStyle(by: .value("Metric", p.title))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabelText))
        .accessibilityValue(Text(accessibilityValueText))
        .chartForegroundStyleScale(range: series.map(\.color))
        .chartYScale(domain: 0...1)
        .chartYAxis {
            // Normalized axis — label endpoints as low/high rather than raw numbers.
            AxisMarks(position: .leading, values: [0.0, 0.5, 1.0]) { value in
                AxisGridLine().foregroundStyle(theme.hairline)
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(d == 0 ? "low" : d == 1 ? "high" : "mid")
                            .font(StrandFont.footnote)
                            .foregroundStyle(theme.inkTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(theme.hairline)
                AxisValueLabel().foregroundStyle(theme.inkTertiary)
                    .font(StrandFont.footnote)
            }
        }
        .chartLegend(.hidden) // legend rendered separately with real min/max
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = geo[proxy.plotFrame!]
                // Day under the finger — drives crosshair/tooltip and VoiceOver value. (FER-977)
                let selectedDay: String? = hoverX.flatMap { nearestDay(toX: $0, proxy: proxy, plot: plot) }
                ZStack(alignment: .topLeading) {
                    // Full-bleed hit target so scrub works before any crosshair exists (same pattern as
                    // TrendChart — without it the ZStack is 0×0 until the first touch lands). (FER-977)
                    Color.clear
                        .onChange(of: selectedDay) { _, day in a11yDay = day }

                    if let day = selectedDay,
                       let d = parseCompareDay(day),
                       let px = proxy.position(forX: d) {
                        let cx = px + plot.minX
                        // Vertical crosshair at the hovered day.
                        Rectangle()
                            .fill(theme.hairlineStrong)
                            .frame(width: 1, height: geo.size.height)
                            .position(x: cx, y: geo.size.height / 2)

                        // Dot on each series at this day (where it has a value).
                        ForEach(series) { s in
                            if let v = s.value(on: day),
                               let py = proxy.position(forY: s.normalized(v)) {
                                Circle()
                                    .fill(s.color)
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(theme.paper, lineWidth: 2))
                                    .position(x: cx, y: py + plot.minY)
                            }
                        }

                        MultiTooltip(
                            day: day,
                            series: series,
                            theme: theme,
                            anchorX: cx,
                            container: geo.size
                        )
                    }
                }
                .animation(StrandMotion.fade, value: hoverX)
                .contentShape(Rectangle())
                // Shared toolkit: finger drag on iOS + pointer hover on macOS → same `hoverX`. (FER-977)
                .scrubGesture(enabled: true, hoverX: $hoverX)
            }
        }
        .frame(height: height)
    }

    /// Map a cursor x back to the nearest day-string present in the data.
    private func nearestDay(toX x: CGFloat, proxy: ChartProxy, plot: CGRect) -> String? {
        guard !allDates.isEmpty else { return nil }
        let relX = x - plot.minX
        guard let target: Date = proxy.value(atX: relX) else { return nil }
        return allDates.min(by: { a, b in
            abs(a.date.timeIntervalSince(target)) < abs(b.date.timeIntervalSince(target))
        })?.day
    }
}

// MARK: - Multi-series tooltip

/// A floating tooltip listing each series' REAL value on the hovered day, kept
/// inside the chart bounds.
private struct MultiTooltip: View {
    let day: String
    let series: [CompareSeries]
    var theme: InstrumentoTheme
    let anchorX: CGFloat
    let container: CGSize

    private static let dateLabelFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM yyyy"
        return f
    }()
    private var dateLabel: String {
        guard let d = parseCompareDay(day) else { return day }
        return Self.dateLabelFmt.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(dateLabel)
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
            ForEach(series) { s in
                HStack(spacing: 7) {
                    Circle().fill(s.color).frame(width: 7, height: 7)
                    Text(s.metric.title)
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                    Spacer(minLength: 12)
                    Text(s.value(on: day).map { s.metric.format($0) } ?? "—")
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(theme.ink)
                }
            }
        }
        .padding(10)
        .instrumentoCard(.inset, theme: theme)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)   // token-exempt: opacidad de sombra (fuera de banda)
        .frame(width: tooltipWidth, alignment: .leading)
        .position(x: clampedX, y: tooltipHeight / 2 + 8)
        .allowsHitTesting(false)
    }

    private var tooltipWidth: CGFloat { 220 }
    private var tooltipHeight: CGFloat { CGFloat(24 + series.count * 18) }

    /// Keep the tooltip on the side of the crosshair with more room, clamped.
    private var clampedX: CGFloat {
        let half = tooltipWidth / 2
        let preferRight = anchorX < container.width / 2
        let target = preferRight ? anchorX + half + 14 : anchorX - half - 14
        return min(max(target, half + 4), container.width - half - 4)
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func comparePreviewRepo() -> Repository {
    let repo = Repository(deviceId: "preview")
    repo.setDashboard()
    return repo
}

#Preview("Compare") {
    CompareView()
        .instrumentoTheme(.base)
        .environmentObject(comparePreviewRepo())
        .frame(width: 920, height: 860)
}
#endif
