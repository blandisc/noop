#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - Cuerpo (the «between-days / history» landing) — FER-186
//
// The «Cuerpo» tab of the 3-layer IA redesign (FER-182 placed it; this screen replaces its interim
// `TrendsView`). A curated landing in the light «Instrumento diurno» language: warm paper, color ONLY
// on the datum, hierarchy by space. The body is a column of DOMAIN CARDS, not a flat list: a title +
// date frame → Recovery (the single hero numeral + 14-day trend) → Rest & load / Vitals / Activity /
// Longevity, each a `theme.surface` card whose grouped stats (label · value in its data hue · optional
// legend) tap straight into their detail, with the «How you wake after each sport» insight nested under
// a hairline inside Activity → connect nudge → global actions (Compare · See all metrics) at the foot.
// Each stat is its own tap target (the direct shortcut the old rows had); the card header is a quiet
// label (no chevron — «See all metrics» at the foot is the one catalog door, no duplicate).
//
// FER-566 (supersedes the FER-186 "number, not a chart" rule): every signal now carries a mini-trend
// sparkline — the hero plus each stat in Rest & load, Vitals and Steps — EXCEPT Longevity and
// Entrenamientos (numbers, not curves) and Heart Rate (intraday, no daily series). A period selector
// under the header (`selectedPeriod`) re-windows ALL of them at once, and the hero's «vs tu media»
// delta recomputes against the same window. Stress draws its spark from the stored daily stress series
// (it isn't a `DailyMetric` field); every other spark slices `displayDays` by the selected period.
//
// Detail bridge: every vital now opens a light «Instrumento» sheet — the scalar vitals (HRV / Resting HR /
// Respiración / SpO₂) through the unified `MetricDetailScreen` (FER-185), and the composite/own-shaped ones
// through their dedicated screens (Recovery / Sueño / Esfuerzo / Estrés, and Temp. de piel via
// `SkinTempDetailScreen`, FER-256). Entrenamientos, Comparar and «Ver todas» (Explore, FER-272) now also
// open light «Instrumento» sheets. Only Data Sources still opens the legacy dark screen as a `.sheet`
// pinned to `.dark` (a light tab pushing a dark screen would leave the status bar's dark ink on a
// near-black panel, so a self-contained dark sheet is the honest bridge, same pattern Today uses for
// Live / Data Sources).
//
// Values + sparklines read from `repo.displayDays` (the merged dashboard), NOT `series()`: the
// on-device computed scores live in daily-metrics under `my-whoop-noop`, so `series("my-whoop")` is
// empty for a BLE user — `displayDays` resolves for both import and strap users (FER-149).

/// Theme wrapper: anchors `\.instrumentoTheme` to the single warm day paper (`.base`), then hands off
/// to `CuerpoLanding`, which reads the resolved theme from the environment. (FER-398 retired the
/// by-the-hour tint; the app no longer changes colour with the clock.)
struct CuerpoView: View {
    var body: some View {
        CuerpoLanding()
            .instrumentoTheme(.base)
    }
}

// MARK: - Sheet routing

/// A dark, existing screen presented as a self-contained sheet (pinned to `.dark`).
private enum CuerpoScreen: Hashable { case dataSources }

/// Identifiable wrapper so the light «Instrumento» Detalle de Sueño can ride `.sheet(item:)`
/// (the model itself isn't Identifiable). One per presentation. (FER-212)
private struct SleepDetailItem: Identifiable {
    let id = UUID()
    let model: SleepDetailModel
}

/// The dark-sheet driver — the remaining legacy dark screen without a light sheet yet (Data Sources).
private enum CuerpoSheet: Identifiable {
    case screen(CuerpoScreen)
    var id: String {
        switch self {
        case .screen(let s): return "screen-\(s)"
        }
    }
}

// MARK: - Landing

private struct CuerpoLanding: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var health: HealthKitBridge
    @EnvironmentObject var tabRouter: TabRouter
    @Environment(\.instrumentoTheme) private var theme

    /// Light metric sheet (the same one Today opens), for metrics that have a `MetricInfo` factory.
    @State private var metricInfo: MetricInfo? = nil
    /// Unified Detalle de Métrica (FER-185): the three vitals (HRV / FC reposo / Respiración) open this
    /// at `.full` depth instead of the legacy `MetricInfoSheet` / dark `MetricDetailView` bridge.
    @State private var metricSpec: MetricDetailSpec? = nil
    /// Light «Instrumento» Detalle de Recuperación (FER-225): the recovery hero now opens this rich detail
    /// (superset of the old `MetricInfoSheet`), built fresh on tap from the in-memory dashboard, theme
    /// passed explicitly.
    @State private var recoveryDetail: RecoveryDetailItem? = nil
    /// Dark screen / catalog-detail sheet, for everything without a light sheet yet.
    @State private var darkSheet: CuerpoSheet? = nil
    /// Light «Instrumento» Comparar (FER-268) — the «Compare» row now opens the reskinned overlay screen
    /// as a light sheet (theme injected at the root; it doesn't cross the `.sheet` boundary, FER-162), NO
    /// nested NavigationStack (FER-171). Replaces the old dark `.screen(.compare)` bridge.
    @State private var showCompare = false
    /// Light «Instrumento» Explore (FER-272) — the «See all metrics» row now opens the reskinned metric
    /// catalog as a light sheet with its OWN NavigationStack (so a metric row pushes its detail), theme
    /// injected at the sheet root (it doesn't cross the `.sheet` boundary, FER-162). Replaces the old dark
    /// `.screen(.explore)` bridge.
    @State private var showExplore = false
    /// Light «Instrumento» Entrenamientos (FER-260) — the «Workouts» row now opens the reskinned list as a
    /// light sheet with its own NavigationStack (so a session row can push the detail), theme injected at
    /// the sheet root. Replaces the old dark `.screen(.workouts)` bridge.
    @State private var showWorkouts = false
    /// Light «Instrumento» Detalle de Sueño (FER-212) — the «Sueño» row now opens this superset of the
    /// old dark sleep screen (built fresh on tap from the in-memory dashboard), theme passed explicitly.
    @State private var sleepDetail: SleepDetailItem? = nil
    /// Light «Instrumento» Detalle de Esfuerzo (FER-238) — the «Day Strain» row now opens this rich detail
    /// (curva intradía + zonas + tendencia + método) instead of the legacy `MetricInfoSheet`. Hoy unchanged.
    @State private var strainDetail: StrainDetailItem? = nil
    /// Light «Instrumento» Detalle de Estrés (FER-241) — the «Stress» row now opens this dedicated screen
    /// (valor de hoy + bandas universales + qué lo mueve + ⓘ por concepto), theme passed explicitly. SOLO
    /// en Cuerpo: el tile de Estrés en Hoy NO cambia.
    @State private var stressDetail: StressDetailItem? = nil
    /// The «mapa del día» driver (EventKit + intraday stress), built fresh when the Stress row opens
    /// its detail and passed into the sheet. (FER-377)
    @State private var stressDayMap: CalendarDayMap? = nil
    /// Light «Instrumento» Detalle de Temperatura de la piel (FER-256) — the «Skin Temperature» row now
    /// opens this dedicated screen (última lectura + tendencia con banda ±típica + consistencia en SD °C +
    /// método) instead of the legacy dark catalog sheet; theme passed explicitly.
    @State private var skinTempDetail: SkinTempDetailItem? = nil
    /// «How you wake after each sport» — ranked ActivityCost per sport (FER-139); empty = "gathering data".
    @State private var activityCosts: [ActivityCost] = []
    /// Presents the light Activity-recovery detail sheet.
    @State private var showActivityCost = false
    /// Body Age + Vitality (FER-145): computed in `loadAll` from a window of nightly signals; nil until
    /// ≥3 factors are present. `vitalityInputs` drives the detail's "what's built from" checklist.
    @State private var vitalityResult: VitalityEngine.Result? = nil
    @State private var vitalityInputs: VitalityEngine.Inputs? = nil
    /// Presents the light Body-age detail sheet.
    @State private var showBodyAge = false

    /// The period the landing's sparklines (hero + every stat) window over. The header selector drives it;
    /// each spark re-slices `repo.displayDays` to this window on change, and the hero's «vs tu media» delta
    /// recomputes against the same window. (FER-566 — supersedes the fixed 14-day hero spark of FER-186.)
    @State private var selectedPeriod: ExploreRange = .month

    // Loaded once per refresh (memoized in `loadAll`) so the body never re-scans history per render.
    /// The stored daily stress series (0–3), kept so the «Stress» stat can draw a sparkline — stress isn't a
    /// `DailyMetric` field, so unlike the other stats its spark reads this series, not `displayDays`. (FER-566)
    @State private var stressSeries: [(day: String, value: Double)] = []
    @State private var hrPoints: [TrendPoint] = []
    @State private var appleDays: [AppleDaily] = []
    @State private var appleMetricDays: [DailyMetric] = []
    @State private var workoutCount: Int = 0
    /// Sessions in the trailing 14 days — the «Entrenamientos» row's protagonist (recent training, not
    /// the unbounded all-time total). `workoutCount` stays the lifetime count for the Apple-connect hint.
    @State private var recentWorkoutCount: Int = 0
    /// Today's stress model (0–3 autonomic proxy + markers + trend) — the same transparent model Hoy builds.
    /// Held whole (not just the score) so the «Stress» row can open the dedicated detail (FER-241).
    @State private var stressModel: StressModel? = nil
    /// Recovery cold-start: nights banked toward the seed gate while the baseline calibrates; nil once
    /// recovery is scored. Drives the hero's "N/4" + "Calibrating" copy instead of a fake number.
    @State private var recoveryCalibration: Int? = nil
    /// Fitness Age (FER-141): the 7-day orchestration snapshot, memoized once per refresh in `loadAll`.
    @State private var fitnessAge: FitnessAgeSnapshot? = nil
    /// Drives the Fitness Age detail sheet (the light «Instrumento» sheet for «Edad física»).
    @State private var showFitnessAge = false
    /// Light «Instrumento» Mapa muscular (FER-350) — front/back silhouettes tinted by per-muscle training
    /// load, crossed with systemic recovery. Theme passed explicitly (it doesn't cross the `.sheet`
    /// boundary, FER-162); the per-muscle detail rides a nested sheet, NO NavigationStack (FER-171).
    @State private var showMuscleMap = false

    private static let recoverySeed = Baselines.minNightsSeed

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                titleBlock
                periodSelector
                recoveryHero
                restLoadCard
                muscleMapCard
                vitalsCard
                activityCard
                longevityCard
                connectNudge
                footerActions
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, NoopMetrics.screenTop)   // shared titled-tab top inset
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PaperBackground())
        .task(id: repo.refreshSeq) { await loadAll() }
        .sheet(item: $metricInfo) { info in metricSheet(for: info) }
        .sheet(item: $metricSpec) { spec in
            MetricDetailScreen(
                spec: spec,
                depth: .full,
                theme: theme,
                // VO₂max is Apple-only: invite connecting Apple Health from its empty state when nothing's
                // connected and there's no reading (mirrors the Fitness Age VO₂max nudge). (FER-257)
                appleConnectHint: spec.descriptor.key == "vo2max"
                    && health.auth != .authorized && health.auth != .unavailable
                    && latestAppleVO2max == nil,
                // FER-487: seal today's datum «Apple» when it came from Apple Health, matching the tile.
                todayFromApple: todayVitalFromApple(spec.descriptor.key),
                // FER-635: which nights are Apple-sourced, so the detail folds the baseline/σ, CV and Δ%
                // on a single source (band-anchored) instead of mixing RMSSD↔SDNN and the band↔Apple offsets.
                appleDays: repo.appleHealthDays,
                seriesLoader: { vitalSeries(for: spec.descriptor.key) },
                nightVitalsLoader: spec.blocks.contains(.nightVitals) ? { await loadNightVitals() } : nil,
                whatMovesItLoader: spec.blocks.contains(.whatMovesIt)
                    ? { whatMovesItFindings(for: spec.descriptor.key) }
                    : nil,
                intradayCurveLoader: spec.blocks.contains(.intradayCurve) ? { hrPoints } : nil,
                // FER-702: the frequency-domain HRV breakdown lives only in the HRV detail.
                spectralLoader: spec.descriptor.key == "hrv" ? { await loadSpectralHRV() } : nil,
                hrMax: Double(model.profile.hrMax),
                restingHR: resolveMeasured { $0.restingHr.map(Double.init) }?.value,
                todayKey: Repository.localDayKey(Date())
            )
        }
        .sheet(item: $recoveryDetail) { item in
            // Light «Instrumento» Detalle de Recuperación — theme passed explicitly (it doesn't propagate
            // through `.sheet`), NO nested NavigationStack (FER-171). (FER-225)
            RecoveryDetailScreen(theme: theme, model: item.model)
        }
        .sheet(isPresented: $showMuscleMap) {
            // Light «Instrumento» Mapa muscular (FER-350) — theme injected at the root (it doesn't cross
            // the `.sheet` boundary, FER-162) and `repo` re-supplied (a sheet starts a fresh environment).
            // NO nested NavigationStack (FER-171); the per-muscle detail rides its own nested sheet.
            MuscleMapScreen(theme: theme)
                .instrumentoTheme(theme)
                .environmentObject(repo)
                .preferredColorScheme(.light)
        }
        // Handoff from the strength summary's muscle chips (FER-409): open the fatigue map on arrival.
        // `onAppear` covers a lazily-built tab; `onChange` covers the case where Cuerpo is already visible.
        .onAppear { if tabRouter.openMuscleMap { showMuscleMap = true; tabRouter.openMuscleMap = false } }
        .onChange(of: tabRouter.openMuscleMap) { _, open in
            if open { showMuscleMap = true; tabRouter.openMuscleMap = false }
        }
        .sheet(item: $darkSheet) { sheet in darkSheetContent(sheet) }
        .sheet(isPresented: $showCompare) {
            // Light «Instrumento» Comparar — the theme is injected at the root (it doesn't cross the
            // `.sheet` boundary, FER-162) and the env objects are re-supplied (a sheet starts a fresh
            // environment branch). No nested NavigationStack (FER-171); you drag to dismiss. (FER-268)
            CompareView()
                .instrumentoTheme(theme)
                .environmentObject(repo)
                .environmentObject(live)
                .environmentObject(model)
                .environmentObject(health)
        }
        .sheet(isPresented: $showWorkouts) {
            // Light «Instrumento» Entrenamientos — its OWN NavigationStack lives inside the sheet so each
            // session row pushes the detail (NOT a stack nested across the tab path, FER-171). The theme is
            // injected at the root (it doesn't cross the `.sheet` boundary, FER-162), and the screen's env
            // objects are re-supplied (a sheet starts a fresh environment branch). (FER-260)
            NavigationStack { WorkoutsView() }
                .instrumentoTheme(theme)
                .environmentObject(repo)
                .environmentObject(live)
                .environmentObject(model)
                .environmentObject(health)
        }
        .sheet(isPresented: $showExplore) {
            // Light «Instrumento» Explore (FER-272) — its OWN NavigationStack lives inside the sheet so a
            // metric row pushes its detail (NOT a stack nested across the tab path, FER-171). The theme is
            // passed explicitly to the screen AND injected at the root (it doesn't cross the `.sheet`
            // boundary, FER-162); the env objects are re-supplied (a sheet starts a fresh environment).
            // A light sheet from a light tab keeps the status bar honest (no dark pin needed).
            NavigationStack {
                MetricExplorerView(theme: theme)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showExplore = false }.foregroundStyle(theme.ink)
                        }
                    }
            }
            .instrumentoTheme(theme)
            .environmentObject(repo)
            .environmentObject(live)
            .environmentObject(model)
            .environmentObject(health)
        }
        .sheet(item: $strainDetail) { item in
            // Light «Instrumento» Detalle de Esfuerzo — theme passed explicitly (it doesn't propagate
            // through `.sheet`), NO nested NavigationStack (FER-171). The intraday curve is loaded the
            // same way the legacy sheet did (`loadStrainCurve`). (FER-238)
            StrainDetailScreen(theme: theme, model: item.model,
                               curveLoader: { await loadStrainCurve() })
        }
        .sheet(item: $sleepDetail) { item in
            // Light «Instrumento» sheet — pass the resolved theme explicitly (it doesn't propagate
            // through `.sheet`), NO nested NavigationStack (FER-171). (FER-212)
            SleepDetailScreen(theme: theme, model: item.model)
        }
        .sheet(item: $stressDetail) { item in
            // Light «Instrumento» Detalle de Estrés — theme passed explicitly (it doesn't propagate
            // through `.sheet`), NO nested NavigationStack (FER-171). (FER-241; unificado con Hoy en FER-452
            // vía el factory compartido `StressDayMapPresenter`.)
            // The «mapa del día» driver (EventKit + intraday curve) is built fresh on tap. (FER-377)
            // The cross-day pattern line (FER-378) is read-only — the Coach handoff was removed (Pase v2 #7).
            StressDetailScreen(theme: theme, model: item.model, dayMap: stressDayMap,
                               patternsLoader: { await StressDayMapPresenter.timeOfDayPatterns(
                                   repo: repo, maxHR: model.profile.hrMax, restingHR: stressRestingHR) },
                               eventPatternsLoader: { await StressDayMapPresenter.eventPatterns(
                                   repo: repo, map: stressDayMap) })
        }
        .sheet(item: $skinTempDetail) { item in
            // Light «Instrumento» Detalle de Temperatura de la piel — theme passed explicitly (it doesn't
            // propagate through `.sheet`), NO nested NavigationStack (FER-171). (FER-256)
            SkinTempDetailScreen(theme: theme, model: item.model)
        }
        .sheet(isPresented: $showActivityCost) { activityRecoverySheet }
        .sheet(isPresented: $showFitnessAge) {
            // Light «Instrumento» sheet — pass the resolved theme explicitly (it doesn't propagate
            // through `.sheet`), same as the metric sheet above.
            FitnessAgeDetailView(snapshot: fitnessAge ?? computeFitnessAge(),
                                 chronoAge: model.profile.age, sex: model.profile.sex,
                                 appleVO2max: latestAppleVO2max,
                                 appleConnectHint: health.auth != .authorized && health.auth != .unavailable
                                     && latestAppleVO2max == nil,
                                 theme: theme)
        }
        .sheet(isPresented: $showBodyAge) {
            BodyAgeSheet(
                result: vitalityResult,
                inputs: vitalityInputs ?? VitalityEngine.Inputs(chronoAge: Double(model.profile.age)),
                theme: theme)
        }
    }

    /// The canvas — read inside the themed subtree so it recolors by hour too.
    private struct PaperBackground: View {
        @Environment(\.instrumentoTheme) private var theme
        var body: some View { theme.paper.ignoresSafeArea() }
    }

    // MARK: - Title + date

    /// «Body» + today's date — the landing's temporal frame (the date is new to the card model).
    /// Wordmark header (matching «Patrones»): the curve-with-nodes glyph + «Tendencias» on the left,
    /// today's date in mono on the right. Replaces the old stacked «Body» + subhead-date block.
    private var titleBlock: some View {
        InstrumentoTabHeader("Tendencias") {
            TendenciasGlyph(color: theme.ink)
        } trailing: {
            Text(Self.dateLabel)
                .font(StrandFont.number(11, weight: .regular)).foregroundStyle(theme.inkTertiary)
                .textCase(.uppercase)
        }
        .padding(.bottom, 6)
    }

    /// Today as «THU 12 JUN» / «JUE 12 JUN» — follows the app language (`.current`), uppercased by the
    /// header. Same treatment as «Patrones» (FER-472): the date localizes with the rest of the screen.
    private static var dateLabel: String { dateHeader.string(from: Date()) }

    private static let dateHeader: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "EEE d MMM"; return f
    }()

    // MARK: - Period selector (FER-566) — re-windows every sparkline on the landing

    /// The W/M/3M/6M/1Y/ALL pills under the header (same `ExploreRange` the detail screens use). Changing it
    /// re-windows the hero trend + every stat sparkline + the hero's «vs tu media» delta.
    private var periodSelector: some View {
        SegmentedPillControl(ExploreRange.allCases, selection: $selectedPeriod, theme: theme) { $0.label }
    }

    // MARK: - Sparkline windowing (FER-566)

    /// The display dashboard sliced to the selected period (most recent calendar days ending today). `.all`
    /// returns the whole dashboard. Pure read of in-memory `displayDays` — cheap enough to recompute per
    /// render, which is what makes the sparks reactive to the selector.
    private var periodWindow: [DailyMetric] {
        guard let n = selectedPeriod.days else { return repo.displayDays }
        return trailingDisplay(n)
    }

    /// A stat's sparkline values over the selected period, from `displayDays` (the same layered source the
    /// values draw from). <2 points → the stat draws no spark.
    private func windowedSpark(_ pick: (DailyMetric) -> Double?) -> [Double] {
        periodWindow.compactMap(pick)
    }

    /// The Recovery hero trend over the selected period (was a fixed 14 days in FER-186). Computed, not
    /// memoized, so it re-windows when the selector changes.
    private var recoverySpark: [Double] { windowedSpark(\.recovery) }

    /// The stress sparkline over the selected period — from the stored daily stress series (stress isn't a
    /// `DailyMetric` field). `.all` uses the whole series; otherwise the trailing window.
    private var stressSpark: [Double] {
        guard let n = selectedPeriod.days else { return stressSeries.map(\.value) }
        let cutoffKey = Repository.localDayKey(
            Calendar.current.date(byAdding: .day, value: -(n - 1), to: Date()) ?? Date())
        return stressSeries.filter { $0.day >= cutoffKey }.map(\.value)
    }

    // MARK: - Domain card scaffolding (Instrumento rule 3: one surface, no card-in-card)

    /// A domain card: a quiet overline header (a label — it only orients, Instrumento rule 4) over its
    /// grouped stats, on a single `theme.surface` panel. The catalog door is the footer's «See all
    /// metrics»; the header carries no chevron so it doesn't duplicate that destination.
    private func domainCard<Content: View>(_ title: LocalizedStringKey,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Serif group header (FER-581 — the handoff titles the landing's domain groups in serif 27).
            Text(title).font(StrandFont.serif(27)).foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
        .padding(.vertical, 16).padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    /// A tappable stat column inside a domain card: a quiet label (optional Apple/Estimate chip), the
    /// value in its data hue (ink «—» when absent — never a hue), an optional inline unit and a footnote
    /// legend. `value == nil` is an honest empty state.
    private func statColumn(_ label: LocalizedStringKey, value: String?, unit: String? = nil,
                            color: Color, legend: LocalizedStringKey? = nil, estimate: Bool = false,
                            fromApple: Bool = false, spark: [Double] = [], tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(label).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    if fromApple { InlineFlagChip("Apple", color: theme.inkTertiary) }
                    if estimate { InlineFlagChip("Estimate", color: theme.warning) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value ?? "—")
                        .font(StrandFont.number(21))
                        .foregroundStyle(value == nil ? theme.inkTertiary : color)
                    if let unit, value != nil {
                        Text(unit).font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    }
                }
                // Mini-trend over the selected period — re-windows with the header selector (FER-566). A stat
                // with <2 points in the window draws nothing (honest empty state, never a fake spark). Color
                // ONLY on the datum (Instrumento): the line carries the stat's own data hue, area very faint.
                if value != nil, spark.count > 1 {
                    Sparkline(values: spark,
                              gradient: Gradient(colors: [color.opacity(0.5), color]),
                              lineWidth: 1.6, showsArea: true, showsHead: false, showsScrub: false)
                        .frame(height: 16)
                        .padding(.top, 2)
                        // Decorative only: `Sparkline` paints its own `contentShape`, which otherwise swallows
                        // taps on the chart (the biggest part of the tile) so the row didn't open. Disabling
                        // hit-testing hands EVERY tap in the tile to the Button below. (FER-566 follow-up)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if let legend {
                    Text(legend).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MetricRowButtonStyle(pressedFill: theme.ink.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    /// Vertical hairline between stat columns (no card-in-card — Instrumento rule 3).
    private var vsep: some View { Divider().overlay(theme.hairline) }

    // MARK: - Domain cards

    /// Rest & load — Sleep · Day Strain · Stress, each column into its detail.
    private var restLoadCard: some View {
        domainCard("Rest & load") {
            HStack(spacing: 13) {
                sleepStat
                vsep
                strainStat
                vsep
                stressStat
            }
        }
    }

    /// Muscle map (FER-350) — a navigational card into the front/back fatigue map. The whole card is the
    /// tap target (it opens a screen, not a metric detail), so it's a full button, not a `domainCard`.
    private var muscleMapCard: some View {
        Button { showMuscleMap = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Muscle map").font(StrandFont.serif(27)).foregroundStyle(theme.ink)   // serif group (FER-581)
                    // Provisional placement here, pending a product decision on its permanent home (likely
                    // Entrenar / Patrones) — flagged, not final. (FER-566 / handoff «DE MOMENTO»)
                    InlineFlagChip("For now", color: theme.warning)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
                Text("What to train today")
                    .font(StrandFont.headline).foregroundStyle(theme.ink)
                Text("Per-muscle load crossed with your recovery.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 16).padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(SurfacePressStyle(tint: theme.ink.opacity(0.05)))
        .accessibilityHint("Opens the muscle map.")
    }

    /// Vitals — a 3×2 grid of scalar vitals, each into its `MetricDetailScreen`.
    private var vitalsCard: some View {
        domainCard("Vitals") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: 3),
                      alignment: .leading, spacing: 18) {
                hrvStat; rhrStat; spo2Stat; heartStat; respStat; skinTempStat
            }
        }
    }

    /// Activity — Steps · Workouts·14d, with «How you wake after each sport» nested under a hairline.
    private var activityCard: some View {
        domainCard("Activity") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 13) {
                    stepsStat
                    vsep
                    workoutsStat
                }
                vsep
                activityInsight
            }
        }
    }

    /// Longevity — Physical age · Body age · VO₂ Max, each with a micro-legend, into its sheet.
    private var longevityCard: some View {
        domainCard("Longevity") {
            HStack(alignment: .top, spacing: 13) {
                physicalAgeStat
                vsep
                bodyAgeStat
                vsep
                vo2maxStat
            }
        }
    }

    // MARK: - Recovery hero (the single dominant element — Instrumento rule 1)

    private var recoveryHero: some View {
        let score = repo.today?.recovery.map { Int($0.rounded()) }
        let cal = recoveryCalibration
        let spark = recoverySpark
        let showSpark = spark.count > 1 && score != nil
        let color = score.map(recoveryColor) ?? theme.inkTertiary
        return Button {
            recoveryDetail = RecoveryDetailItem(model: RecoveryDetailModel.build(repo: repo))
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recovery").font(StrandFont.serif(27)).foregroundStyle(theme.ink)   // serif group (FER-581)
                    recoveryHeroNumeral(score: score, calibrating: cal, color: color)
                    Text(recoverySubtitle(score: score, calibrating: cal))
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                Spacer(minLength: 8)
                recoveryHeroAccessory(score: score, calibrating: cal,
                                      spark: showSpark ? spark : nil, color: color)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 18).padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        // Press feedback to match the stats: the hero draws its own `surface` background, so a fill
        // BEHIND the label (MetricRowButtonStyle) wouldn't show — `SurfacePressStyle` overlays the tint
        // on top, clipped to the same rounded shape. (FER-186 follow-up)
        .buttonStyle(SurfacePressStyle(tint: theme.ink.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    /// The hero numeral — the screen's one dominant figure (SF Mono). Scored → tinted by band + «/100»;
    /// calibrating → «N/seed» in ink; no reading → faint «—».
    @ViewBuilder
    private func recoveryHeroNumeral(score: Int?, calibrating: Int?, color: Color) -> some View {
        if let score {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(score)").instrumentoHero(56).foregroundStyle(color)
                Text("/100").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            }
        } else if let calibrating {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(calibrating)").instrumentoHero(48).foregroundStyle(theme.ink)
                Text("/\(Self.recoverySeed)").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            }
        } else {
            Text("—").instrumentoHero(56).foregroundStyle(theme.inkTertiary)
        }
    }

    /// The hero's right accessory: the 14-day trend (scored), a calibration progress bar (calibrating),
    /// or nothing — decorative, so it's hidden from VoiceOver (the numeral + subtitle carry meaning).
    @ViewBuilder
    private func recoveryHeroAccessory(score: Int?, calibrating: Int?, spark: [Double]?, color: Color) -> some View {
        if let spark, let score, spark.count > 1 {
            let mean = spark.reduce(0, +) / Double(spark.count)
            let delta = score - Int(mean.rounded())
            VStack(alignment: .trailing, spacing: 7) {
                Sparkline(values: spark,
                          gradient: Gradient(colors: [color.opacity(0.55), color]),
                          meanLine: mean, meanLineColor: theme.hairlineStrong,
                          lineWidth: 2.4, showsArea: true, showsHead: false, showsScrub: false)
                    .frame(width: 104, height: 46)
                // The trend's own baseline, read as a signed delta vs the 14-day mean (datum hue).
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                        .font(StrandFont.number(13, weight: .semibold)).foregroundStyle(color)
                    Text("vs tu media").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
            }
            .accessibilityHidden(true)
        } else if let calibrating {
            Capsule().fill(theme.hairline)
                .frame(width: 104, height: 6)
                .overlay(alignment: .leading) {
                    Capsule().fill(theme.dataRecovery)
                        .frame(width: 104 * CGFloat(calibrating) / CGFloat(Self.recoverySeed), height: 6)
                }
                .accessibilityHidden(true)
        }
    }

    // MARK: - Stat columns (one per metric — same value resolution + tap target as the old rows)

    private var sleepStat: some View {
        let r = resolveMeasured { $0.totalSleepMin }
        return statColumn("Sleep", value: r.map { sleepText($0.value) }, color: theme.dataSleep,
                          fromApple: r?.fromApple == true, spark: windowedSpark { $0.totalSleepMin }) {
            sleepDetail = SleepDetailItem(model: SleepDetailModel.build(
                days: repo.days,
                sleeps: repo.sleeps,
                appleSleeps: repo.appleSleeps,
                importedSleep: repo.importedSleep,
                appleHealthDays: repo.appleHealthDays,
                loaded: repo.loaded,
                todayKey: Repository.localDayKey(Date())))
        }
    }

    private var strainStat: some View {
        // Valor VIVO del día en curso (fin de la curva intradía), no el score asentado — una sola
        // derivación alimenta este número, el héroe del Detalle y la curva (FER-650). Cae al asentado
        // mientras el vivo aún no se computa.
        let v = model.displayedDayStrain
        return statColumn("Day Strain", value: v.map { String(format: "%.1f", $0) },
                          color: theme.dataStrain, spark: windowedSpark { $0.strain }) {
            // Opens the rich Detalle de Esfuerzo (FER-238) — built fresh from the in-memory dashboard;
            // the intraday curve loads async in the screen via `loadStrainCurve`. (Hoy still uses
            // `MetricInfo.strain`/`MetricInfoSheet`.)
            strainDetail = StrainDetailItem(model: StrainDetailModel.build(
                days: repo.days, today: repo.today, loaded: repo.loaded))
        }
    }

    private var stressStat: some View {
        let s = stressModel?.score
        return statColumn("Stress", value: s.map { String(format: "%.1f", $0) },
                          unit: s == nil ? nil : "/ 3",
                          color: s.map(stressDataColor) ?? theme.inkTertiary, spark: stressSpark) {
            stressDayMap = StressDayMapPresenter.make(
                repo: repo, maxHR: model.profile.hrMax, restingHR: stressRestingHR)
            stressDetail = StressDetailItem(model: stressModel)
        }
    }

    /// Today's resting HR for the «mapa del día» (resolved, with the engine's default as the floor) —
    /// the one input the shared `StressDayMapPresenter` can't derive itself.
    private var stressRestingHR: Double {
        resolveMeasured { $0.restingHr.map(Double.init) }?.value ?? StrainScorer.defaultRestingHR
    }

    private var hrvStat: some View {
        let r = resolveMeasured { $0.avgHrv }
        return statColumn("HRV", value: r.map { "\(Int($0.value.rounded()))" }, unit: String(localized: "ms"),
                          color: theme.dataHrv, fromApple: r?.fromApple == true,
                          spark: windowedSpark { $0.avgHrv }) {
            metricSpec = .hrv(r?.value)
        }
    }

    private var rhrStat: some View {
        let r = resolveMeasured { $0.restingHr.map(Double.init) }
        return statColumn("Resting HR", value: r.map { "\(Int($0.value.rounded()))" }, unit: String(localized: "bpm"),
                          color: theme.dataHeart, fromApple: r?.fromApple == true,
                          spark: windowedSpark { $0.restingHr.map(Double.init) }) {
            metricSpec = .restingHR(r.map { Int($0.value.rounded()) })
        }
    }

    private var spo2Stat: some View {
        let r = resolveMeasured { $0.spo2Pct }
        return statColumn("Blood Oxygen", value: r.map { String(format: "%.0f", $0.value) }, unit: "%",
                          color: theme.dataSpO2, fromApple: r?.fromApple == true,
                          spark: windowedSpark { $0.spo2Pct }) {
            metricSpec = .spo2(r?.value)
        }
    }

    private var heartStat: some View {
        let avg = hrTodayAvg
        // No sparkline: Heart Rate is an intraday metric (today's mean of the 5-min buckets), not a daily
        // dashboard series — its own detail has no period trend either (FER-253). A daily mean-HR series
        // doesn't exist in `displayDays`, so the honest landing read is the number alone. (FER-566)
        return statColumn("Heart Rate", value: avg.map { "\($0)" }, unit: String(localized: "bpm"),
                          color: theme.dataHeart) {
            metricSpec = .heartRate(avg)
        }
    }

    private var respStat: some View {
        let r = resolveMeasured { $0.respRateBpm }
        return statColumn("Respiratory", value: r.map { String(format: "%.1f", $0.value) }, unit: String(localized: "rpm"),
                          color: theme.dataSpO2, fromApple: r?.fromApple == true,
                          spark: windowedSpark { $0.respRateBpm }) {
            metricSpec = .respiratory(r?.value)
        }
    }

    private var skinTempStat: some View {
        let r = resolveMeasured { $0.skinTempDevC }
        return statColumn("Skin temp", value: r.map { String(format: "%+.1f", $0.value) }, unit: "°C",
                          color: theme.dataStrain, fromApple: r?.fromApple == true,
                          spark: windowedSpark { $0.skinTempDevC }) {
            // Opens the rich light Detalle de Temperatura de la piel (FER-256) — built fresh from the
            // in-memory dashboard (última lectura resuelta + serie completa de `displayDays`).
            skinTempDetail = SkinTempDetailItem(model: SkinTempDetailModel.build(
                latest: r?.value, series: vitalSeries(for: "skin_temp"), loaded: repo.loaded))
        }
    }

    private var stepsStat: some View {
        let steps = freshSteps
        return statColumn("Steps", value: steps.map { intString(Double($0)) },
                          color: theme.dataSteps, fromApple: steps != nil,
                          spark: windowedSpark { $0.steps.map(Double.init) }) {
            metricSpec = .steps(steps)
        }
    }

    /// «Entrenamientos» — the recent-session count tinted in the effort hue (`dataStrain`). No recent
    /// sessions → honest "—"; VoiceOver says it plainly, not "dash". (FER-259)
    @ViewBuilder private var workoutsStat: some View {
        let n = recentWorkoutCount
        let col = statColumn("Workouts · 14d", value: n > 0 ? "\(n)" : nil,
                             color: theme.dataStrain) {
            showWorkouts = true
        }
        if n > 0 { col } else { col.accessibilityLabel(Text("sin entrenamientos aún")) }
    }

    // MARK: - Longevity stats (Fitness Age FER-141 · Body Age FER-145 · VO₂max FER-257)

    /// Physical age — the value tinted by DIRECTION (younger green / older amber / even ink, faint «—»
    /// when there's no reading), with a compact legend and the «Estimate» chip on low confidence.
    private var physicalAgeStat: some View {
        let snap = fitnessAge
        let estimate = snap?.readiness.confidence == .estimate
        let color = snap?.result.map(physicalAgeColor) ?? theme.inkTertiary
        return statColumn("Physical age",
                          value: snap?.result.map { "\(Int($0.fitnessAge.rounded()))" },
                          color: color, legend: physicalAgeLegend(snap), estimate: estimate) {
            showFitnessAge = true
        }
    }

    /// Direction hue: younger → recovery green, older → warning amber, even → ink. The ±0.5-yr
    /// deadband lives on `FitnessAgeResult.direction` (StrandAnalytics) so the row and the sheet agree.
    private func physicalAgeColor(_ result: FitnessAgeResult) -> Color {
        switch result.direction {
        case .younger: return theme.dataRecovery
        case .older:   return theme.warning
        case .even:    return theme.ink
        }
    }

    /// The compact footnote under Physical age — direction when ready, else the honest RHR-coverage
    /// blocker; nil while still loading so the column doesn't jump.
    private func physicalAgeLegend(_ snap: FitnessAgeSnapshot?) -> LocalizedStringKey? {
        guard let snap else { return nil }
        if let result = snap.result {
            let yrs = Int(abs(result.deltaYears).rounded())
            let chrono = Int(result.chronoAge.rounded())
            switch result.direction {
            case .younger: return "\(yrs) yr younger"
            case .older:   return "\(yrs) yr older"
            case .even:    return "at your \(chrono)"
            }
        }
        // notReady — RHR coverage is the real blocker (age/sex come from the profile defaults).
        return "RHR \(snap.rhrNights)/4 nights"
    }

    /// Build the Fitness Age snapshot from the trailing 7-day display window + profile. Pure + cheap;
    /// memoized into `fitnessAge` by `loadAll`, recomputed on demand as the sheet's fallback.
    private func computeFitnessAge() -> FitnessAgeSnapshot {
        let last7 = trailingDisplay(7)
        return FitnessAgeEngine.snapshot(
            rhrLast7: last7.map { $0.restingHr },
            strainLast7: last7.map { $0.strain },
            age: model.profile.age, sex: model.profile.sex,
            hasHeightWeight: true)
    }

    /// «Body age» (Vitality/Body Age, FER-145): the years datum, tinted by the SIGN of the delta, with a
    /// «vs your N» legend; opens the longevity detail (the honest checklist even with no reading).
    private var bodyAgeStat: some View {
        let r = vitalityResult
        let color = r.map { BodyAgeSheet.tint(forDelta: $0.deltaYears, theme: theme) } ?? theme.inkTertiary
        // «Estimate» chip when a heaviest factor (HRV/RHR) is missing — same mechanism as Physical age
        // (FER-643), so the two longevity stats read consistently.
        return statColumn("Body age", value: r.map { "\(Int($0.bodyAge.rounded()))" },
                          color: color, legend: r == nil ? nil : "vs your \(model.profile.age)",
                          estimate: r?.isPartialEstimate == true) {
            showBodyAge = true
        }
    }

    /// VO₂max (Apple Health, measured · FER-257): the most recent reading (no freshness gate), the unit
    /// carried by the «ml/kg·min» legend so the numeral stays clean. «—» + no chip when unread.
    private var vo2maxStat: some View {
        let v = latestAppleVO2max
        return statColumn("VO₂ Max", value: v.map { String(format: "%.0f", $0) },
                          color: theme.dataSpO2, legend: "ml/kg·min", fromApple: v != nil) {
            metricSpec = .vo2max(value: v, age: model.profile.age, sex: model.profile.sex)
        }
    }

    // MARK: - Connect nudge + footer

    /// Apple-only metrics (Steps) invite connecting Apple Health when it isn't authorized and there's no
    /// stored value — without promising data that doesn't exist. Opens Data Sources.
    @ViewBuilder private var connectNudge: some View {
        let notConnected = health.auth != .authorized && health.auth != .unavailable
        if notConnected && freshSteps == nil {
            Button { darkSheet = .screen(.dataSources) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(theme.dataSpO2)
                    Text("Connect Apple Health to fill steps and more.")
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(theme.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ControlPressStyle())
        }
    }

    private var footerActions: some View {
        VStack(spacing: 0) {
            actionRow("Compare", icon: "arrow.left.arrow.right") { showCompare = true }
            Divider().overlay(theme.hairline).padding(.leading, 46)
            actionRow("See all metrics", icon: "square.grid.2x2") { showExplore = true }
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func actionRow(_ label: LocalizedStringKey, icon: String, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.inkSecondary).frame(width: 22)
                Text(label).font(StrandFont.body).foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(MetricRowButtonStyle(pressedFill: theme.ink.opacity(0.05)))
    }

    // MARK: - Activity insight (FER-139) — nested under Activity, NOT a card-in-card (Instrumento rule 3)

    /// «How you wake after each sport» — up to three top sports from the engine's ranking, each as
    /// `sport · N pts lower/higher` (colour only on the datum). A `delta < 3` sport reads «no clear
    /// link». When the engine returns nothing the block stays, showing «Gathering data» — it never
    /// hides. Lives under a hairline inside the Activity card; its own chevron jumps to the detail.
    private var activityInsight: some View {
        Button { showActivityCost = true } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Text("How you wake after each sport")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    // Provisional placement (likely Entrenar / Patrones later) — flagged, not final. (FER-566)
                    InlineFlagChip("For now", color: theme.warning)
                    Spacer(minLength: 8)
                    if activityCosts.isEmpty {
                        Text("Gathering data").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
                if !activityCosts.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(activityCosts.prefix(3).enumerated()), id: \.offset) { _, c in
                            activityCostRow(c)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(MetricRowButtonStyle(pressedFill: theme.ink.opacity(0.05)))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the per-sport detail.")
    }

    /// One summary row inside the block: sport name (ink) · its direction/points. Colour on the datum:
    /// the gap is `dataStrain` when there's a real link, quiet ink when it's under the engine's noise
    /// floor (then it reads «no clear link»). Localized; "pts" stays plural (a reported gap is ≥ 3).
    private func activityCostRow(_ c: ActivityCost) -> some View {
        let meaningful = abs(c.delta) >= ActivityCostEngine.barelyMovesPoints
        let pts = Int(abs(c.delta).rounded())
        let summary: LocalizedStringKey = !meaningful ? "no clear link"
            : (c.delta >= 0 ? "\(pts) pts lower" : "\(pts) pts higher")
        return HStack(spacing: 8) {
            Text(verbatim: c.sport).font(StrandFont.body).foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            Text(summary)
                .font(StrandFont.subhead)
                .foregroundStyle(meaningful ? theme.dataStrain : theme.inkTertiary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// The light Activity-recovery detail (FER-139), theme passed explicitly (it doesn't cross the
    /// `.sheet` boundary). The Apple-connect line appears only when nothing's connected and there are no
    /// sessions to draw from.
    private var activityRecoverySheet: some View {
        ActivityRecoverySheet(
            costs: activityCosts,
            theme: theme,
            appleConnectHint: health.auth != .authorized && health.auth != .unavailable && workoutCount == 0
        )
    }

    // MARK: - Detail sheets

    /// The light metric sheet (the same one Today opens), with the live theme passed explicitly (it
    /// does NOT propagate through `.sheet`'s fresh environment) and the matching trend / curve loaders.
    private func metricSheet(for info: MetricInfo) -> some View {
        let appleCapable = ["sleep", "hrv", "rhr", "spo2", "steps"].contains(info.id)
        let notConnected = health.auth != .authorized && health.auth != .unavailable
        return MetricInfoSheet(
            info: info,
            theme: theme,
            appleConnectHint: appleCapable && notConnected && info.displayValue == "—",
            strainCurveLoader: info.id == "strain" ? { await loadStrainCurve() } : nil,
            heartRateCurveLoader: info.id == "heart_rate" ? { hrPoints } : nil,
            trendLoader: trendLoader(for: info.id)
        )
    }

    /// Data Sources, now reskinned to the light «Instrumento» language (FER-338), presented
    /// self-contained: its own NavigationStack + Done button (so «Ver datos importados» pushes the
    /// Apple Health viewer), the theme injected at the root (it doesn't cross the `.sheet` boundary,
    /// FER-162), and the environment objects re-injected (a sheet starts a fresh environment branch).
    /// A light sheet from a light tab keeps the status bar honest (no dark pin needed).
    private func darkSheetContent(_ sheet: CuerpoSheet) -> some View {
        NavigationStack {
            Group {
                switch sheet {
                case .screen(.dataSources): DataSourcesView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { darkSheet = nil }.foregroundStyle(theme.ink)
                }
            }
        }
        .instrumentoTheme(theme)
        .environmentObject(repo)
        .environmentObject(live)
        .environmentObject(model)
        .environmentObject(health)
        .preferredColorScheme(.light)
    }

    // MARK: - Loading (memoize once per refresh)

    private func loadAll() async {
        recoveryCalibration = RecoveryScorer.calibrationNights(
            nightlyHrv: repo.days.map(\.avgHrv),
            hasRecovery: repo.today?.recovery != nil)

        // The sparklines (hero + every stat) are computed properties windowed by `selectedPeriod` straight
        // off `repo.displayDays`, so they re-window on selector change without a reload (FER-566). Only the
        // stored stress series needs loading here (stress isn't a `DailyMetric` field).

        // Today's HR is bucketed; the rest of the daily/Apple rows feed values, not sparklines.
        async let adRows     = repo.appleDailyRows()
        async let amRows     = repo.appleDailyMetricRows()
        async let wkRows     = repo.workoutRows()
        // Stored daily "stress" series (0–3) — the model prefers it, else derives from RHR/HRV.
        async let stressRows = repo.series(key: "stress", source: "my-whoop")
        let startOfToday = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let nowTs = Int(Date().timeIntervalSince1970)
        async let hrRows = repo.hrBuckets(from: startOfToday, to: nowTs, bucketSeconds: 300)

        appleDays = await adRows
        appleMetricDays = (await amRows).sorted { $0.day < $1.day }
        let workouts = await wkRows
        workoutCount = workouts.count
        // Sessions in the trailing 14 calendar days for the «Entrenamientos» row (FER-259) — start-of-day
        // 13 days ago through now, matching the app's standard trailing-14 window.
        let recentCutoff = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date())
        let recentCutoffTs = Int(recentCutoff.timeIntervalSince1970)
        recentWorkoutCount = workouts.filter { $0.startTs >= recentCutoffTs }.count
        activityCosts = repo.activityCosts(from: workouts)   // reuses the rows above — no second query
        hrPoints = await hrRows.map {
            TrendPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: $0.bpm)
        }
        // Esfuerzo del día en curso (FER-650): valor VIVO para el stat, en lockstep con la curva del Detalle.
        await model.refreshLiveDayStrain()
        // displayDays = Apple-health fallback (FER-149); local todayKey ignores a UTC "tomorrow" row (FER-226).
        let stored = await stressRows
        stressSeries = stored   // for the Stress stat's sparkline (FER-566)
        let stress = StressModel(days: repo.displayDays, stored: stored,
                                 todayKey: Repository.localDayKey(Date()), appleDays: repo.appleHealthDays)
        stressModel = stress

        fitnessAge = computeFitnessAge()

        // Longevity (FER-145 + FER-214): Body Age + Vitality from a 28-night window. Regularity uses the
        // real Sleep Regularity Index when there's coverage (FER-214), else the documented duration proxy;
        // VO₂max needs a waist the profile doesn't collect, so the cardio signal flows through resting HR.
        // Mask cross-source columns to the BAND before the engine folds them (FER-640): `nightlyRMSSD`
        // takes the MEDIAN of `avgHrv` and `VitalityEngine` scores it against an RMSSD-by-age norm, but
        // `displayDays` back-fills Apple **SDNN** on band-less nights (FER-149) — a different construct with
        // no published conversion (Task Force 1996; Shaffer & Ginsberg 2017), so a few Apple nights bias
        // Body Age by source, not physiology. The same `SourceLens.maskForBaseline(keep:.band)` (FER-631)
        // also nils Apple's resting HR (band −12.7 bpm offset), which likewise scores against a band-domain
        // norm — so both nocturnal inputs stay single-source. Single-source columns (steps) and cross-source-
        // comparable ones (sleep duration) are untouched. If the user is Apple-only, band RMSSD is empty →
        // `VitalityInputsBuilder`'s coverage gate drops the HRV factor rather than comparing SDNN to the
        // band norm. A strap-only user is the identity — `recentBand == recent`.
        let recent = trailingDisplay(28)
        let recentBand = SourceLens.maskForBaseline(recent, keep: .band, appleDays: repo.appleHealthDays)
        let vInputs = VitalityInputsBuilder.build(.init(
            chronoAge: Double(model.profile.age),
            nightlyRestingHR: recentBand.compactMap { $0.restingHr.map(Double.init) },
            nightlyRMSSD: recentBand.compactMap { $0.avgHrv },
            nightlySleepHours: recent.compactMap { $0.totalSleepMin.map { $0 / 60 } },
            dailySteps: recent.compactMap { $0.steps.map(Double.init) },
            sleepRegularity: computeSleepRegularity()))
        vitalityInputs = vInputs
        vitalityResult = VitalityEngine.compute(vInputs)
    }

    /// The real Sleep Regularity Index (FER-214) over a trailing window of persisted sleep sessions, as a
    /// 0–1 input for the engine (SRI/100). The session→timeline mapping is the pure
    /// `SleepRegularityIndex.fromSessions`; the view only supplies the window. nil → the builder's proxy.
    private func computeSleepRegularity() -> Double? {
        let cutoff = Int(Date().timeIntervalSince1970) - 35 * 86_400
        return SleepRegularityIndex.fromSessions(repo.sleeps.filter { $0.startTs >= cutoff }).map { $0 / 100 }
    }

    // MARK: - Trend / curve loaders for the light sheet (mirror Today)

    /// Trailing 14-day trend from `repo.displayDays` — the same layered source the rows draw from.
    private func loadTrend(pick: @escaping (DailyMetric) -> Double?, window: Int = 14) async -> [TrendPoint] {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -(window - 1), to: Date()) ?? Date())
        return repo.displayDays.compactMap { row -> TrendPoint? in
            guard row.day >= cutoff, let value = pick(row),
                  let date = Repository.parseDayKey(row.day) else { return nil }
            return TrendPoint(date: date.addingTimeInterval(12 * 3600), value: value)
        }
    }

    /// The FULL daily series (oldest → newest) for a vital, from `repo.displayDays` — the unified
    /// Detalle de Métrica (FER-185) carries its own range selector, so it needs all history. Same
    /// layered source the rows draw from (resolves for both import and BLE users; FER-149).
    private func vitalSeries(for key: String) -> [(day: String, value: Double)] {
        // VO₂max isn't a nightly dashboard metric — it lives in the Apple daily rows, measured sparsely
        // (FER-257). Every reading is a real measurement, so no freshness gate / no displayDays merge.
        if key == "vo2max" {
            return appleDays
                .compactMap { row in row.vo2max.map { (row.day, $0) } }
                .sorted { $0.day < $1.day }
        }
        let pick: (DailyMetric) -> Double?
        switch key {
        case "hrv":       pick = { $0.avgHrv }
        case "rhr":       pick = { $0.restingHr.map(Double.init) }
        case "resp_rate": pick = { $0.respRateBpm }
        case "spo2":      pick = { $0.spo2Pct }
        case "skin_temp": pick = { $0.skinTempDevC }
        case "steps":     pick = { $0.steps.map(Double.init) }
        default:          return []
        }
        // FER-635: the three cross-source vitals read `repo.days` (the un-backfilled merge), NOT
        // `displayDays` — `displayDays` fills a band night's missing HRV/RHR/resp from Apple, which would
        // slip an SDNN/offset value onto a band-classified day and defeat the detail's per-source fold. On
        // `days`, each reading truly belongs to its day's source (band or Apple), so the detail can segment
        // the baseline/σ, CV and Δ% cleanly (see `appleDays`). Single-source metrics keep the backfilled
        // `displayDays` for continuous coverage (FER-149).
        let source = ["hrv", "rhr", "resp_rate"].contains(key) ? repo.days : repo.displayDays
        return source
            .compactMap { row in pick(row).map { (row.day, $0) } }
            .sorted { $0.day < $1.day }
    }

    /// The gated, directional "Qué la mueve" findings (FER-209) for a vital, computed from the user's
    /// own history (`repo.displayDays`). Empty → the detail screen hides the block.
    private func whatMovesItFindings(for key: String) -> [WhatMovesItFinding] {
        WhatMovesItEngine.findings(forMetricKey: key, days: repo.displayDays, appleDays: repo.appleHealthDays)
    }

    /// Last night's companion vitals (respiration + resting HR) for the detail's "Vitales de la noche"
    /// block. Reuses `resolveMeasured` (today wins, else most recent within today/yesterday).
    private func loadNightVitals() async -> MetricDetailScreen.NightVitals {
        MetricDetailScreen.NightVitals(
            respiration: resolveMeasured { $0.respRateBpm }?.value,
            restingHR: resolveMeasured { $0.restingHr.map(Double.init) }?.value)
    }

    /// Last night's frequency-domain HRV breakdown (LF/HF/total, ms²) + a per-band «your normal» label,
    /// read from the `-noop` computed `metricSeries` the pipeline persisted (FER-702). Returns nil when
    /// there is no band-night spectrum, so the section stays hidden (an Apple-only night has none).
    private func loadSpectralHRV() async -> MetricDetailScreen.SpectralHRV? {
        let hf = (await repo.computedSeries(key: "hrv_hf")).sorted { $0.day < $1.day }
        guard let latest = hf.last else { return nil }
        let day = latest.day
        let lf = (await repo.computedSeries(key: "hrv_lf")).sorted { $0.day < $1.day }
        let total = (await repo.computedSeries(key: "hrv_totalpower")).sorted { $0.day < $1.day }
        func band(_ s: [(day: String, value: Double)]) -> MetricDetailScreen.SpectralHRV.Band? {
            guard let today = s.first(where: { $0.day == day }) else { return nil }
            let history = s.filter { $0.day < day }.map { Optional($0.value) }   // exclude tonight
            return .init(value: today.value,
                         label: HRVSpectralBaseline.label(value: today.value, history: history))
        }
        guard let hfBand = band(hf) else { return nil }
        let totalVal = total.first(where: { $0.day == day })?.value ?? hfBand.value
        return .init(hf: hfBand, lf: band(lf), total: totalVal)
    }

    /// The 14-day trend loader the `MetricInfoSheet` runs lazily. Strain returns nil (it has its own
    /// intraday "How today added up" curve); resp/skin_temp aren't routed here (they open the catalog).
    private func trendLoader(for id: String) -> (() async -> [TrendPoint])? {
        let pick: (DailyMetric) -> Double?
        switch id {
        case "recovery": pick = { $0.recovery }
        case "sleep":    pick = { $0.totalSleepMin }
        case "hrv":      pick = { $0.avgHrv }
        case "rhr":      pick = { $0.restingHr.map(Double.init) }
        case "spo2":     pick = { $0.spo2Pct }
        case "steps":    pick = { $0.steps.map(Double.init) }
        default:         return nil
        }
        return { await self.loadTrend(pick: pick) }
    }

    /// Today's accumulated-strain curve for the Day Strain sheet — the ONE canonical builder
    /// (`model.strainCurveTrendPoints`, FER-650) so its last point lands exactly on the header value and the
    /// Hoy tile. [] when there's no score / too little data.
    private func loadStrainCurve() async -> [TrendPoint] {
        await model.strainCurveTrendPoints()
    }

    // MARK: - Value resolution + helpers (mirror Today)

    /// Trailing-N-day window of the display dashboard (most recent calendar days ending today).
    private func trailingDisplay(_ days: Int) -> [DailyMetric] {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date())
        return repo.displayDays.filter { $0.day >= cutoff }
    }

    /// Resolve a measured signal: today's row wins; else the most recent value within today/yesterday
    /// (so a fresh sync/import still reads, but never older). `fromApple` badges Apple-sourced values.
    private func resolveMeasured(_ pick: (DailyMetric) -> Double?) -> (value: Double, fromApple: Bool)? {
        let todayKey = Repository.localDayKey(Date())
        if let d = repo.today, let v = pick(d) { return (v, repo.appleHealthDays.contains(todayKey)) }
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        for day in repo.days.reversed() {
            guard day.day >= cutoff else { break }
            if let v = pick(day) { return (v, repo.appleHealthDays.contains(day.day)) }
        }
        for day in appleMetricDays.reversed() {
            guard day.day >= cutoff else { break }
            if let v = pick(day) { return (v, true) }
        }
        return nil
    }

    /// FER-487: did TODAY's reading for a narrative vital come from Apple Health (not the band)? Mirrors
    /// the per-tile `fromApple` resolution so the detail's «Apple» seal matches the tile that opened it.
    /// Heart Rate (intraday, band-only), Steps and VO₂max are out of scope → never sealed here.
    private func todayVitalFromApple(_ key: String) -> Bool {
        switch key {
        case "hrv":       return resolveMeasured { $0.avgHrv }?.fromApple == true
        case "rhr":       return resolveMeasured { $0.restingHr.map(Double.init) }?.fromApple == true
        case "spo2":      return resolveMeasured { $0.spo2Pct }?.fromApple == true
        case "resp_rate": return resolveMeasured { $0.respRateBpm }?.fromApple == true
        default:          return false
        }
    }

    /// Today's step total from the Apple daily rows, within the freshness window (today/yesterday).
    private var freshSteps: Int? {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        return appleDays.last(where: { $0.day >= cutoff })?.steps
    }

    /// Most recent Apple Health VO₂max (ml/kg/min) — NOT a daily metric (Apple updates it occasionally
    /// after outdoor workouts), so the latest available reading wins, no today/yesterday freshness gate.
    private var latestAppleVO2max: Double? {
        appleDays.last(where: { $0.vo2max != nil })?.vo2max
    }

    /// Today's mean HR from the 5-minute buckets (nil when there are no readings).
    private var hrTodayAvg: Int? {
        guard hrPoints.count > 1 else { return nil }
        let v = hrPoints.map(\.value)
        return Int((v.reduce(0, +) / Double(v.count)).rounded())
    }

    private func recoveryColor(_ score: Int) -> Color {
        switch RecoveryScorer.band(Double(score)) {
        case "green":  return theme.dataRecovery
        case "yellow": return theme.warning
        default:       return theme.critical
        }
    }

    /// Stress value color by band 0–3 (low → verdict, medium → warning, high → critical). Reuses
    /// `StressBand` (StressView), matching Today's stress tile semantics.
    private func stressDataColor(_ score: Double) -> Color {
        StressBand(score: score).dataColor(theme)
    }

    private func recoverySubtitle(score: Int?, calibrating: Int?) -> LocalizedStringKey {
        if let score {
            switch RecoveryScorer.band(Double(score)) {
            case "green":  return "Ready to train"
            case "yellow": return "Recovering"
            default:       return "Prioritize rest"
            }
        }
        if calibrating != nil { return "Calibrating your baseline" }
        return "No reading yet"
    }

    private func sleepText(_ mins: Double) -> String { "\(Int(mins) / 60)h \(Int(mins) % 60)m" }

    private func intString(_ v: Double) -> String { StrandFormat.groupedInt(v) }

    private static func descriptor(_ key: String) -> MetricDescriptor? {
        MetricCatalog.all.first { $0.key == key }
    }

}

// MARK: - Preview

#if DEBUG
#Preview("Cuerpo") {
    let repo = Repository(deviceId: "preview")
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    var sample: [DailyMetric] = []
    for i in stride(from: 27, through: 0, by: -1) {
        let date = cal.date(byAdding: .day, value: -i, to: today)!
        let day = Repository.dayString(date)
        let phase = Double(i)
        sample.append(DailyMetric(
            day: day, totalSleepMin: 420 + 60 * sin(phase / 5), efficiency: 88,
            deepMin: 95, remMin: 110, lightMin: 200, disturbances: 4,
            restingHr: 52 + (i % 5), avgHrv: 46 + 12 * sin(phase / 4),
            recovery: min(max(60 + 30 * sin(phase / 6), 10), 99), strain: 9 + 5 * abs(sin(phase / 4)),
            exerciseCount: i % 2, spo2Pct: 96 + sin(phase / 3),
            skinTempDevC: 0.2 * sin(phase / 5), respRateBpm: 14 + sin(phase / 4)
        ))
    }
    repo.setDashboard(days: sample)

    return CuerpoView()
        .environmentObject(repo)
        .environmentObject(LiveState())
        .environmentObject(AppModel())
        .environmentObject(HealthKitBridge(repo: repo, appleDeviceId: "preview-apple", noopDeviceId: "preview"))
        .frame(width: 390, height: 900)
}
#endif
#endif
