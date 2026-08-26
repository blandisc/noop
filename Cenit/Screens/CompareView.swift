import SwiftUI
import Foundation
import StrandDesign
import StrandAnalytics
import CenitStore

// MARK: - Compare — en vidrio «Liquid Glass» (FER-104 · TND-30)
//
// The "overlay metrics & draw conclusions" screen. Pick 2–4 metrics from the catalog, choose a
// time window, and read them on a single overlay chart where EACH line is min–max scaled within
// its own window (different units share the plot by shape, never by magnitude). Below, every pair
// of selected metrics gets a live Pearson-r correlation with a plain-English conclusion. Pure
// read-side: each metric loads from repo, everything else is derived in-view.
//
// Visual language: Liquid Glass. Presented from Cuerpo and Bucle as a `.sheet`; the sheet's own
// backdrop is `LiquidSheetFondo` (neutral — Compare has no single subject to tint) with the hoja
// corner radius. You drag to dismiss; no nested NavigationStack (FER-171).
//
// THE MIGRATION IS SKIN, NOT THREAD (FER-104): the data path, the windowing, the memoized
// `activeSeries`, and the OFF-MAIN Pearson scan with reattach-by-id (FER-976) are conserved
// verbatim from the paper screen. What changed is every surface, and two invariants the paper
// violated that TND-29 exists to fix:
//   • COLOR IS IDENTITY, per metric — `MetricIdentity.hue(for:)`, never a palette-by-index. Each
//     series/chip/swatch/tooltip dot wears the SAME hue as its family on every screen.
//   • NAME IS CANONICAL — `canonicalTitle` says «Effort», never «Day Strain» (HJ-13).

// yyyy-MM-dd → Date, fixed UTC / en_US_POSIX — the shared day-key parser (FER-325).
private func parseCompareDay(_ day: String) -> Date? { Repository.parseDayKey(day) }

// MARK: - Range control (shared spec — W / M / 3M / 6M / 1Y / ALL)
//
// Compare shares the canonical `ExploreRange` (`Cenit/Data/ExploreRange.swift`) with every
// drill-down, window math included (`MetricWindowMath`). `ExploreRange.phrase` carries the
// sentence phrase Compare used to own (FER-104 / TND-29).

// MARK: - Per-series model

/// One selected metric, resolved over the active window: its descriptor, the windowed (day,value)
/// rows, its IDENTITY color, and its real min/max.
private struct CompareSeries: Identifiable {
    let metric: MetricDescriptor
    /// The metric's IDENTITY hue (`MetricIdentity.hue`), not a color-by-index. This is the whole
    /// point of the identity bridge: the same signal is the same color everywhere.
    let color: Color
    let rows: [(day: String, value: Double)]

    var id: String { metric.id }
    var values: [Double] { rows.map(\.value) }
    var realMin: Double { values.min() ?? 0 }
    var realMax: Double { values.max() ?? 0 }

    /// The value on a given day, if recorded.
    func value(on day: String) -> Double? {
        rows.first(where: { $0.day == day })?.value
    }
}

// MARK: - Root

struct CompareView: View {
    @EnvironmentObject var repo: Repository
    /// Accessibility text size — the pair card stacks its header instead of racing the title
    /// against the r value at AX sizes (TND30-5).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Default starter selection (falls back gracefully if a key is missing). All three resolve
    /// from the merged dashboard (`displayDays`), so a user sees an overlay on first open. (FER-275)
    private static let defaultKeys = ["recovery", "strain", "hrv"]

    @State private var range: ExploreRange = .year
    /// Ordered selection (max 4). Drives the legend order.
    @State private var selected: [MetricDescriptor] = []
    /// Presents the metric picker as a scroll-stable sheet (a `Menu` resets its scroll on each
    /// parent re-render while the strap syncs — unusable, FER-279).
    @State private var showPicker = false
    /// Full-history series per selected metric id (ascending by day).
    @State private var fullSeries: [String: [(day: String, value: Double)]] = [:]
    @State private var loadedOnce = false

    /// Cache of the last pairwise-correlation scan + the inputs it was computed for (FER-976).
    @State private var pairCache: [PairResult] = []
    @State private var pairCacheKey: String = ""

    /// `activeSeries` recomputed ONLY on selection/range/fetch change (FER-976).
    @State private var activeSeriesCache: [CompareSeries] = []

    private let maxSelection = 4
    private let minSelection = 2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s550) {
                header
                metricSection

                if selected.count < minSelection {
                    // Fewer than two picked isn't a data problem — the picker is right there.
                    // Telling them to connect Apple Health would lie (TND30-2). The HealthKit
                    // copy is reserved below, for when nothing they picked has ANY history.
                    emptyWell(String(localized: "Pick 2–4 metrics to overlay."))
                } else {
                    let series = activeSeries
                    if series.allSatisfy({ $0.rows.isEmpty }) {
                        if loadedOnce {
                            // Two causes, two copies (TND30-2): nothing has ANY history (the
                            // real no-permission / no-data case → connect Apple Health) vs.
                            // there is history but none in THIS window (→ widen the range).
                            emptyWell(noHistoryAtAll
                                ? String(localized: "Compare needs at least two metrics with history. Connect Apple Health in Data Sources first.")
                                : sinDatosMensaje)
                        } else {
                            LiquidSheetSkeleton(a11yCargando: String(localized: "Reading your history…"))
                        }
                    } else {
                        overlaySection(series)
                        correlationSection(series)
                    }
                }
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .presentationBackground { LiquidSheetFondo() }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(LiquidRadius.hoja)
        .sheet(isPresented: $showPicker) {
            MetricPickerSheet(selected: $selected, maxSelection: maxSelection)
        }
        .task { await loadIfNeeded() }
        .task(id: selectionKey) {
            await loadSelected()
            recomputeActiveSeries()
            refreshPairCache(activeSeries)
        }
        // FER-976: range is the other input `activeSeries` depends on.
        .onChange(of: range) {
            recomputeActiveSeries()
        }
        // Recompute the pairwise scan only when the windowed series content changes.
        .onChange(of: correlationKey(activeSeries)) {
            refreshPairCache(activeSeries)
        }
    }

    // MARK: - Title

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text(String(localized: "Compare"))
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "Overlay signals, draw conclusions."))
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Selection key (re-loads when the set of metrics changes)

    private var selectionKey: String { selected.map(\.id).sorted().joined(separator: "|") }

    // MARK: - Active windowed series

    private func parsed(_ full: [(day: String, value: Double)]) -> MetricWindowMath.Parsed {
        full.map { (day: $0.day, date: parseCompareDay($0.day), value: $0.value) }
    }

    /// Selected metrics resolved to windowed rows + IDENTITY colors, in pick order. Reads the
    /// memoized cache (FER-976).
    private var activeSeries: [CompareSeries] { activeSeriesCache }

    private func recomputeActiveSeries() {
        activeSeriesCache = selected.map { metric in
            let full = fullSeries[metric.id] ?? []
            let window = MetricWindowMath.make(parsed(full), selected: range)
            return CompareSeries(
                metric: metric,
                // IDENTITY, per metric — the color-by-index of the paper is dead (FER-104 / TND-29).
                color: MetricIdentity.hue(for: metric),
                rows: window.rows
            )
        }
    }

    /// True if any selected series had to auto-widen past the selected range.
    private var anyWidened: Bool {
        selected.contains { metric in
            let full = fullSeries[metric.id] ?? []
            guard !full.isEmpty else { return false }
            return MetricWindowMath.effectiveRange(parsed(full), selected: range) != range
        }
    }

    /// "N readings · <range>" caption near the control, flagging any auto-widen. Built from
    /// localized format strings — the paper concatenated a hardcoded English "across" and the
    /// "· sparse widened" suffix, so neither ever translated (FER-104 / TND-30). The series count
    /// is dropped here: it lives in the Overlay block's «N series», and "en 3" named nothing in
    /// es-MX (TND30-3).
    private var rangeCaption: String {
        let series = activeSeries
        let total = series.reduce(0) { $0 + $1.rows.count }
        let unit = total == 1 ? String(localized: "reading") : String(localized: "readings")
        let base = String(format: String(localized: "compare.caption.readings",
                                         defaultValue: "%1$lld %2$@ · %3$@"),
                          total, unit, range.phrase)
        guard anyWidened else { return base }
        return String(format: String(localized: "compare.caption.widened",
                                     defaultValue: "%1$@ · sparse widened"), base)
    }

    private var sinDatosMensaje: String {
        String(localized: "No data for these metrics in \(range.phrase). Widen the range or pick metrics you've logged.")
    }

    /// True once loaded when NO selected metric has any history at all — the genuine no-data /
    /// no-HealthKit-permission case, distinct from "has history, none in this window". Reserves
    /// the "connect Apple Health" copy for the case where connecting is actually the fix (TND30-2).
    private var noHistoryAtAll: Bool {
        selected.allSatisfy { (fullSeries[$0.id] ?? []).isEmpty }
    }

    // MARK: - Loading

    private func loadIfNeeded() async {
        guard selected.isEmpty else { return }
        var picks: [MetricDescriptor] = []
        for key in Self.defaultKeys {
            if let m = MetricCatalog.all.first(where: { $0.key == key }) { picks.append(m) }
        }
        if picks.isEmpty { picks = Array(MetricCatalog.all.prefix(2)) }
        selected = Array(picks.prefix(maxSelection))
    }

    /// Load (and cache) the full history for any selected metric not yet fetched. Two data paths
    /// (FER-275): dashboard fields read from `repo.displayDays` via the shared
    /// `MetricSeriesResolver.dashboardSeries` (FER-104 / TND-29, foco 3 — the SAME resolver Explore
    /// uses, so a key reads the same number on both screens); everything else falls back to
    /// `series()`. Full history is kept so the in-view window can auto-widen a sparse series.
    private func loadSelected() async {
        let missing = selected.filter { fullSeries[$0.id] == nil }
        var resolved: [(id: String, series: [(day: String, value: Double)])] = []
        var needsSeries: [MetricDescriptor] = []
        for metric in missing {
            if let series = MetricSeriesResolver.dashboardSeries(metric.key, from: repo.displayDays) {
                resolved.append((metric.id, series))
            } else {
                needsSeries.append(metric)
            }
        }
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

    // MARK: - Metric picker section (range control + chips, on the paper)

    private var metricSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text(String(localized: "Metrics"))
                .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)

            LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                seleccion: rangeIndex, tono: LiquidColor.tinta700)
                .accessibilityLabel(String(localized: "Time range"))

            HStack(alignment: .firstTextBaseline) {
                if selected.count >= minSelection {
                    Text(verbatim: rangeCaption)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(anyWidened ? LiquidColor.atencionTexto : LiquidColor.tinta500)
                        .accessibilityLabel(rangeCaption)
                }
                Spacer(minLength: LiquidSpace.s200)
                addButton
            }

            if selected.isEmpty {
                Text(String(localized: "Nothing selected yet."))
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.tinta500)
            } else {
                LiquidFlujoLeyenda(espacioH: LiquidSpace.s150, espacioV: LiquidSpace.s150) {
                    ForEach(selected) { metric in
                        LiquidChipSeleccion(
                            nombre: metric.canonicalTitle,
                            tono: MetricIdentity.hue(for: metric),
                            a11yQuitar: String(localized: "Remove \(metric.canonicalTitle)")) {
                                remove(metric)
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A Binding<Int> bridging `LiquidRangeSelector`'s index to `range` (allCases order = W…ALL).
    private var rangeIndex: Binding<Int> {
        Binding(
            get: { ExploreRange.allCases.firstIndex(of: range) ?? 0 },
            set: { range = ExploreRange.allCases[$0] })
    }

    /// Opens the picker. Always tappable — the picker is where you add AND remove, so it stays
    /// reachable at the 4-metric cap.
    private var addButton: some View {
        let atMax = selected.count >= maxSelection
        return Button {
            showPicker = true
        } label: {
            HStack(spacing: LiquidSpace.s150) {
                Image(systemName: "plus.circle.fill")
                    .font(LiquidType.iconSF(size: 14))
                Text(atMax ? String(localized: "Max 4") : String(localized: "Add metric"))
                    .font(LiquidType.boton)
            }
            .foregroundStyle(atMax ? LiquidColor.tinta500 : LiquidColor.tinta900)
            .padding(.horizontal, LiquidSpace.s300)
            .padding(.vertical, LiquidSpace.s150)
        }
        .buttonStyle(.liquidPress)
        .liquidGlass(.pastillaSolida)
        .fixedSize()
        .accessibilityLabel(String(localized: "Add or remove metrics"))
    }

    private func remove(_ metric: MetricDescriptor) {
        withAnimation(LiquidMotion.selector) { selected.removeAll { $0 == metric } }
    }

    // MARK: - Overlay chart section

    /// The overlay + tooltip live in their OWN view so the scrub — which writes the day binding on
    /// every finger tick — re-renders JUST this block, never the correlation cards below, and so the
    /// per-series plot data is built ONCE per construction, not per tick (paridad `OverlayChart`,
    /// FER-319). `anyWidened`/`phrase` come from the parent (they change only with selection/range).
    private func overlaySection(_ series: [CompareSeries]) -> some View {
        let nonEmpty = series.filter { !$0.rows.isEmpty }
        // Pass ALL selected series (not just the non-empty) so the PIECE resolves the honest
        // state: with 2+ picked but < 2 carrying readings in the window, it lands on
        // `.sinLecturas` («No data in <range>»), never `.minimo` (the HealthKit copy). Pre-
        // filtering here collapsed a 1-of-2 window into a fake "pick more metrics" (TND30-1).
        // The trailing count stays the drawable count («N series»).
        return bloque(title: String(localized: "Overlay"),
                      trailing: String(format: String(localized: "compare.overlay.count",
                                                      defaultValue: "%lld series"), nonEmpty.count)) {
            CompareOverlay(series: series, anyWidened: anyWidened, phrase: range.phrase)
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

    /// A stable fingerprint of the correlation inputs, to invalidate `pairCache`.
    private func correlationKey(_ series: [CompareSeries]) -> String {
        series
            .filter { !$0.rows.isEmpty }
            .map { s in "\(s.id):\(s.rows.count):\(s.rows.first?.day ?? "")>\(s.rows.last?.day ?? "")" }
            .joined(separator: "|")
    }

    /// Cached accessor used by the body: memoized scan when inputs match, else a one-shot compute
    /// for THIS render (no state mutation mid-body).
    private func pairResults(_ series: [CompareSeries]) -> [PairResult] {
        correlationKey(series) == pairCacheKey ? pairCache : computePairResults(series)
    }

    /// The expensive pairwise scan, pure — Sendable in, Sendable out — usable synchronously AND in
    /// `Task.detached` (FER-976). The canonical compute floor (`CorrelationStrength.minPairs`) and
    /// the strength ladder are TND-29's single source of truth.
    private nonisolated static func computePairScans(
        _ series: [(id: String, rows: [(day: String, value: Double)])]
    ) -> [PairScan] {
        var out: [PairScan] = []
        guard series.count >= 2 else { return out }
        for i in 0..<(series.count - 1) {
            for j in (i + 1)..<series.count {
                let pairs = CorrelationEngine.alignByDay(series[i].rows, series[j].rows)
                guard pairs.count >= CorrelationStrength.minPairs,
                      let c = CorrelationEngine.pearson(pairs) else { continue }
                out.append(PairScan(aId: series[i].id, bId: series[j].id, r: c.r, n: c.n))
            }
        }
        out.sort { abs($0.r) > abs($1.r) }
        return out
    }

    /// Reattaches a Sendable `PairScan` to its display-only `CompareSeries` (color/metric), by id.
    private func attachPairResults(_ scans: [PairScan], series: [CompareSeries]) -> [PairResult] {
        let byId = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        return scans.compactMap { scan in
            guard let a = byId[scan.aId], let b = byId[scan.bId] else { return nil }
            return PairResult(id: "\(scan.aId)~\(scan.bId)", a: a, b: b, r: scan.r, n: scan.n)
        }
    }

    /// Pure synchronous scan, used ONLY as `pairResults`'s same-frame fallback.
    private func computePairResults(_ series: [CompareSeries]) -> [PairResult] {
        let s = series.filter { !$0.rows.isEmpty }
        return attachPairResults(Self.computePairScans(s.map { (id: $0.id, rows: $0.rows) }), series: s)
    }

    /// Recompute the pair cache off-main iff the correlation inputs changed. Dispatches the scan to
    /// `Task.detached` off a Sendable (id, rows) snapshot — never a raw `CompareSeries` (it carries a
    /// `Color`) — then reattaches + assigns back on MainActor (FER-976).
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
        bloque(title: String(localized: "How They Move Together"),
               trailing: pairs.isEmpty ? nil
                : String(format: String(localized: "compare.pairs.count",
                                        defaultValue: "%lld pairs"), pairs.count)) {
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                Text(String(localized: "Pearson r · \(range.phrase)"))
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)

                // Association, not cause: overlapping trends move together; that's not one causing
                // the other. `LiquidNotaLine` is the house of the sheet disclaimer. (FER-299)
                LiquidNotaLine(String(localized: "Association, not cause: moving together isn't one driving the other."))

                if pairs.isEmpty {
                    emptyWell(String(localized: "Not enough overlapping days between these metrics in \(range.phrase). Widen the range."))
                } else {
                    ForEach(pairs) { p in
                        pairCard(p)
                    }
                }
            }
        }
    }

    /// One pairwise correlation on its own opaque paper card (composed in-line: a single-use card
    /// stays atoms in the screen, not a coined DS piece — DS rule §7). Two identity swatches, the
    /// A↔B pair in canonical names, the r value in neutral ink (its sign carried by the leading
    /// «−», never by color — a negative correlation is not an alarm, TND30-4), the strength phrase
    /// and the overlap footer. At AX text sizes the header stacks instead of racing title against
    /// value on one line (TND30-5).
    private func pairCard(_ p: PairResult) -> some View {
        let swatches = HStack(spacing: LiquidSpace.s075) {
            Circle().fill(p.a.color).frame(width: 8, height: 8)
            Circle().fill(p.b.color).frame(width: 8, height: 8)
        }
        .accessibilityHidden(true)
        let titulo = Text(verbatim: "\(p.a.metric.canonicalTitle) ↔ \(p.b.metric.canonicalTitle)")
            .font(LiquidType.tituloFila)
            .foregroundStyle(LiquidColor.tinta900)
        // Neutral ink: the value is the datum by SIZE (valorM/mono), not by hue. Sign is the «−».
        let valorR = Text(verbatim: "r = \(signedR(p.r))")
            .font(LiquidType.valorM).monospacedDigit()
            .foregroundStyle(LiquidColor.tinta900)

        return VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                    HStack(spacing: LiquidSpace.s250) { swatches; titulo }
                    valorR
                }
            } else {
                HStack(spacing: LiquidSpace.s250) {
                    swatches
                    titulo
                    Spacer(minLength: LiquidSpace.s200)
                    valorR
                }
            }

            Text(verbatim: insightSentence(p))
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: pairFooter(p))
                .font(LiquidType.caption)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .liquidTarjetaSeccion()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: pairA11y(p)))
    }

    // MARK: - Shared scaffold + wells

    /// A titled block on the paper: a quiet overline (+ optional trailing count) and content. The
    /// overline speaks in the section-strip voice of the migrated family, inset (not full-bleed:
    /// Compare's sections carry interactive controls, unlike the read-only detail gemelas).
    @ViewBuilder
    private func bloque<Content: View>(title: String, trailing: String? = nil,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                    .accessibilityAddTraits(.isHeader)
                if let trailing {
                    Spacer(minLength: LiquidSpace.s200)
                    Text(verbatim: trailing)
                        .font(LiquidType.filaConteo)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// An honest empty state on opaque paper (inside a glass sheet, never glass-on-glass).
    private func emptyWell(_ text: String) -> some View {
        Text(verbatim: text)
            .font(LiquidType.cuerpo)
            .foregroundStyle(LiquidColor.tinta500)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .liquidTarjetaSeccion()
    }

    // MARK: - Insight language

    /// "Weight ↔ Recovery: r = −0.34 (moderate negative) over N shared days." + a plain-English
    /// conclusion when |r| is notable. Names are CANONICAL («Effort», not «Day Strain»).
    private func insightSentence(_ p: PairResult) -> String {
        let aT = p.a.metric.canonicalTitle
        let bT = p.b.metric.canonicalTitle
        let head = String(localized: "\(aT) ↔ \(bT): r = \(signedR(p.r)) (\(strengthDirection(p.r))) over \(p.n) shared days.")
        guard abs(p.r) >= 0.3 else {
            return head + String(localized: " No clear relationship: they move largely independently.")
        }
        let lower = p.r < 0
        let aLower = aT.lowercased()
        let bLower = bT.lowercased()
        let verb = lower ? String(localized: "tends to fall") : String(localized: "tends to rise")
        return head + String(localized: " When \(aLower) rises, \(bLower) \(verb): a \(strengthWord(p.r)) \(directionWord(p.r)) link.")
    }

    private func pairFooter(_ p: PairResult) -> String {
        String(format: String(localized: "compare.pair.footer",
                              defaultValue: "%1$lld overlapping days · %2$@ correlation"),
               p.n, strengthDirection(p.r))
    }

    private func pairA11y(_ p: PairResult) -> String {
        String(format: String(localized: "compare.pair.a11y",
                              defaultValue: "%1$@ versus %2$@, r equals %3$@, %4$lld days"),
               p.a.metric.canonicalTitle, p.b.metric.canonicalTitle,
               String(format: "%.2f", p.r), p.n)
    }

    private func signedR(_ r: Double) -> String {
        (r >= 0 ? "+" : "−") + String(format: "%.2f", abs(r))
    }

    /// The localized strength word for a coefficient. The CUTS are the canonical
    /// `CorrelationStrength` ladder (StrandAnalytics, TND-29); the WORD is localized here.
    private func strengthWord(_ r: Double) -> String {
        switch CorrelationStrength.classify(r: r) {
        case .negligible: return String(localized: "negligible")
        case .weak:       return String(localized: "weak")
        case .moderate:   return String(localized: "moderate")
        case .strong:     return String(localized: "strong")
        case .veryStrong: return String(localized: "very strong")
        }
    }

    private func directionWord(_ r: Double) -> String {
        if abs(r) < 0.1 { return "" }
        return r >= 0 ? String(localized: "positive") : String(localized: "negative")
    }

    /// Strength + direction as ONE phrase, with no dangling space when the direction is empty
    /// (|r| < 0.1 → «negligible», not «negligible ») — the double-space the footer and the insight
    /// head both inherited (paper duda c). Order matches the paper: strength then direction.
    private func strengthDirection(_ r: Double) -> String {
        let dir = directionWord(r)
        let str = strengthWord(r)
        return dir.isEmpty ? str : "\(str) \(dir)"
    }
}

// MARK: - Overlay chart + tooltip (isolated so scrub re-renders only here)

/// The normalized overlay chart with its live scrub readout. Owns the scrub day so a finger tick
/// re-renders only this block (the correlation cards stay put), and builds the per-series plot data
/// ONCE per construction — the same isolation the paper's `OverlayChart` had (FER-319). The chart
/// draws its own crosshair, per-series rings and legend (real min–max per series). Color is
/// IDENTITY, names are CANONICAL. The tooltip is a sibling piece (the chart doesn't format dates):
/// a fixed readout at the top of the plot, since the chart doesn't expose the cursor x.
private struct CompareOverlay: View {
    let series: [CompareSeries]        // ALL selected — the piece resolves .minimo/.sinLecturas (TND30-1)
    let anyWidened: Bool
    let phrase: String

    /// The drawable series (non-empty in the window) — the tooltip rows and the a11y label follow
    /// the legend, which the piece builds from the non-empty ones. `series` keeps the empties only
    /// so the piece can count what was PICKED and pick the honest empty-state message.
    private var visibles: [CompareSeries] { series.filter { !$0.rows.isEmpty } }

    /// Built once per construction (init), never per scrub tick.
    private let liquidSeries: [LiquidGraficaSuperpuesta.Serie]
    private let porId: [String: MetricDescriptor]
    private let rango: ClosedRange<Date>

    /// The day under the finger (nil at rest). Published by `LiquidGraficaSuperpuesta` via
    /// `liquidScrubPan` — NEVER a DragGesture of our own (FER-977).
    @State private var scrubDay: Date? = nil

    // The chart dates are UTC-anchored (`parseCompareDay` = UTC epoch day), so both format in UTC to
    // label the right calendar day (FER-630), with the current locale for month/weekday names.
    private static let ejeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }()
    private static let tooltipFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.setLocalizedDateFormatFromTemplate("EEEdMMMyyyy")
        return f
    }()

    init(series: [CompareSeries], anyWidened: Bool, phrase: String) {
        self.series = series
        self.anyWidened = anyWidened
        self.phrase = phrase
        self.liquidSeries = series.map { s in
            LiquidGraficaSuperpuesta.Serie(
                id: s.id,
                nombre: s.metric.canonicalTitle,
                color: s.color,
                puntos: s.rows.compactMap { row in
                    parseCompareDay(row.day).map { (fecha: $0, valor: row.value) }
                },
                // Min–max of the window per series (`CompareSeries` real min/max) — NEVER a fixed
                // MetricLevels band, which would spawn a fourth scale (FER-104 / TND-30).
                dominio: s.realMin...s.realMax)
        }
        self.porId = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0.metric) })
        let fechas = series.flatMap { $0.rows.compactMap { parseCompareDay($0.day) } }
        self.rango = (fechas.min() ?? Date())...(fechas.max() ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text(verbatim: caption)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .top) {
                LiquidGraficaSuperpuesta(
                    series: liquidSeries,
                    rango: rango,
                    seleccion: $scrubDay,
                    formatoValor: { serie, v in porId[serie.id]?.format(v) ?? "" },
                    a11yLabel: a11yLabel,
                    formatoFechaEje: { Self.ejeFmt.string(from: $0) },
                    rotulosRejilla: (bajo: String(localized: "low"),
                                     medio: String(localized: "mid"),
                                     alto: String(localized: "high")),
                    mensajeMinimo: String(localized: "Compare needs at least two metrics with history. Connect Apple Health in Data Sources first."),
                    mensajeSinLecturas: sinDatos)
                if let d = scrubDay {
                    LiquidTooltipMulti(fecha: Self.tooltipFmt.string(from: d), filas: filas(on: d))
                        .padding(.top, LiquidSpace.s200)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var caption: String {
        anyWidened
            ? String(format: String(localized: "compare.overlay.caption.widened",
                                    defaultValue: "Min–max normalized · sparse series widened past %1$@ · drag to read values"),
                     phrase)
            : String(format: String(localized: "compare.overlay.caption",
                                    defaultValue: "Each line min–max normalized within %1$@ · drag to read values"),
                     phrase)
    }

    private var sinDatos: String {
        String(localized: "No data for these metrics in \(phrase). Widen the range or pick metrics you've logged.")
    }

    private var a11yLabel: String {
        String(format: String(localized: "compare.chart.a11y", defaultValue: "Comparing %1$@"),
               visibles.map(\.metric.canonicalTitle).joined(separator: ", "))
    }

    /// One tooltip row per drawn series, in legend order — the scrubbed day's REAL value, or nil («—»).
    private func filas(on date: Date) -> [LiquidTooltipMulti.Fila] {
        let day = Repository.utcDayKey(date)
        return visibles.map { s in
            LiquidTooltipMulti.Fila(
                id: s.id, color: s.color, nombre: s.metric.canonicalTitle,
                valor: s.value(on: day).map { s.metric.format($0) })
        }
    }
}

// MARK: - Metric picker sheet (scroll-stable, Liquid)

/// The "add / remove metrics" picker, as a Liquid summary-sheet shell (`LiquidMetricSheet` +
/// `LiquidSheetHeader` + the sheet's own `LiquidSheetFondo`). Replaces the old catalog `Menu`,
/// which reset its scroll to the top on every parent re-render (FER-279). Grouped by catalog
/// category; each row is a `LiquidListRow` toggle (a ✓ marks the picked ones); rows disable at the
/// 4-metric cap, but already-picked rows stay tappable so you can swap. Drag down to dismiss.
private struct MetricPickerSheet: View {
    @Binding var selected: [MetricDescriptor]
    let maxSelection: Int

    /// Neutral: the picker has no single subject either, so its plasta is a quiet warm-gray breath.
    private let tono = LiquidColor.tinta500

    var body: some View {
        LiquidMetricSheet(tono: tono, detent: .porContenido) {
            LiquidSheetHeader(icono: nil,
                              titulo: String(localized: "Metrics"),
                              tono: tono, numeral: nil)
            LiquidNotaLine(String(localized: "Pick 2–4 to overlay."))
            ForEach(MetricCatalog.categories, id: \.self) { category in
                let metrics = MetricCatalog.inCategory(category)
                if !metrics.isEmpty {
                    seccion(category, metrics)
                }
            }
        }
    }

    private func seccion(_ category: String, _ metrics: [MetricDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Text(MetricCatalog.localizedCategory(category))
                .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            VStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { i, metric in
                    fila(metric, ultima: i == metrics.count - 1)
                }
            }
            .liquidTarjetaSeccion(padding: LiquidSpace.s300)
        }
    }

    private func fila(_ metric: MetricDescriptor, ultima: Bool) -> some View {
        let isOn = selected.contains(metric)
        let atCap = !isOn && selected.count >= maxSelection
        return LiquidListRow(
            title: metric.canonicalTitle,
            tone: MetricIdentity.hue(for: metric),
            seleccionado: isOn,
            deshabilitado: atCap,
            // Why the row is inert: VoiceOver otherwise reads a dimmed row with no reason (TND30-7).
            a11yHint: atCap ? String(localized: "At most 4 metrics.") : nil,
            divider: !ultima) {
                withAnimation(LiquidMotion.selector) {
                    if isOn { selected.removeAll { $0 == metric } }
                    else if selected.count < maxSelection { selected.append(metric) }
                }
            }
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
    Color.clear.sheet(isPresented: .constant(true)) {
        CompareView()
            .environmentObject(comparePreviewRepo())
    }
}
#endif
