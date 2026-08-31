#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import CenitStore
import Foundation

// MARK: - Cuerpo (the «between-days / history» landing) — FER-186 · FER-100 (Liquid Glass)
//
// The «Cuerpo» tab of the 3-layer IA redesign (FER-182 placed it; this screen replaces its interim
// `TrendsView`). FER-100 repaints the landing from the light «Instrumento diurno» paper to Liquid
// Glass: a tinted-lens hero (the Preparación verdict word + its clause, teñido by the verdict's own
// tone — apagado to paper/ink with no verdict, never green) over a column of `LiquidModulo` glass
// modules — Rest & load / Training load / Vitals / Activity / Longevity — each with an
// aurora edge in the hue of ITS OWN data (only the top two animate; the rest draw a still aurora, a
// scrolling list is too many clocks). Domain color is ALWAYS `MetricIdentity.identity(forKey:)`, never
// a raw theme token. Grouped stats (label in quiet ink · value in its data hue · optional legend) tap
// straight into their detail, separated by `LiquidCapilar` hairlines; the «How you wake after each
// sport» insight nests under one inside Activity → connect nudge → global actions (Compare · See all
// metrics) at the foot. Each stat is its own tap target (the direct shortcut the old rows had); the
// module header is a quiet regla label (no chevron — «See all metrics» at the foot is the one catalog
// door, no duplicate). This is a VISUAL migration only: the data path, engines and navigation below
// are untouched (see `loadAll` / `detailOverlayContent` / `DetailChrome`).
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
// on-device computed scores live in daily-metrics under `strap-noop`, so `series("strap")` is
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

/// Full-screen detail chrome (handoff v2 Chrome, FER-828): a «‹ Tendencias · {date}» top bar over a
/// pushed-looking detail. Presented via `fullScreenCover`, so it reads as a full screen with a back
/// chevron WITHOUT any `NavigationStack` — deliberately avoiding the nested-stack crash (FER-171).

/// Edge-swipe-back (FER-837): a drag that STARTS in the left `edgeZone` and runs horizontally pulls the
/// panel right, revealing Tendencias behind it, and past `dismissThreshold` (or a flick) pops — so you
/// don't have to hit the «‹» chevron exactly. Gated to the left edge + horizontal dominance so it never
/// competes with vertical scrolling. `.simultaneousGesture` keeps the ScrollView and the back button
/// working. `enabled: false` stands the gesture down where the system owns the edge (Entrenamientos with
/// a session pushed: its `NavigationStack` runs its own interactive pop from the same edge).
private struct EdgeSwipeBack: ViewModifier {
    let enabled: Bool
    let onClose: () -> Void
    @State private var dragX: CGFloat = 0

    /// The left-edge zone that arms the back-swipe (pt). Narrow so it never steals a normal touch.
    private static var edgeZone: CGFloat { 24 }
    /// Past this drag distance (or a flick predicted past `flickThreshold`) the screen dismisses.
    private static var dismissThreshold: CGFloat { 90 }
    private static var flickThreshold: CGFloat { 200 }

    func body(content: Content) -> some View {
        content
            .offset(x: dragX)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        guard enabled,
                              v.startLocation.x < Self.edgeZone,
                              v.translation.width > 0,
                              v.translation.width > abs(v.translation.height) else { return }
                        dragX = v.translation.width
                    }
                    .onEnded { v in
                        guard enabled, v.startLocation.x < Self.edgeZone, dragX > 0 else { return }
                        if v.translation.width > Self.dismissThreshold
                            || v.predictedEndTranslation.width > Self.flickThreshold {
                            // Pop from the current dragged position: the parent removes the layer with a
                            // trailing slide-out, continuing the motion under the finger (never a snap back).
                            onClose()
                        } else {
                            withAnimation(StrandMotion.interactive) { dragX = 0 }
                        }
                    }
            )
            // A pushed session owns the edge again: leave no stale drag behind when the gesture stands down.
            .onChange(of: enabled) { _, on in if !on { dragX = 0 } }
    }
}

private struct DetailChrome<Content: View>: View {
    let theme: InstrumentoTheme
    /// Pops the detail — clears the presenting state so the parent removes this layer (with a trailing
    /// slide-out transition). Replaces `@Environment(\.dismiss)`: the detail is now an in-hierarchy layer
    /// over the Tendencias landing, NOT a `fullScreenCover` (which hid the landing behind a blank platter).
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: LiquidSpace.s150) {
                Button { onClose() } label: {
                    HStack(spacing: LiquidSpace.s100) {
                        // No LiquidIcon back glyph — `.chevron` is the forward list-row arrow.
                        Image(systemName: "chevron.left")
                            .font(LiquidType.iconSF(size: 12))
                        Text("Trends")
                            .font(LiquidType.boton)
                            .tracking(LiquidType.botonTracking)
                    }
                    .foregroundStyle(LiquidColor.tinta700)
                    .padding(.horizontal, LiquidSpace.s400)
                    .padding(.vertical, LiquidSpace.s200)
                    .contentShape(Capsule())
                }
                .buttonStyle(.liquidPress)
                .liquidGlass(.pastillaSolida)
                Spacer(minLength: LiquidSpace.s200)
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s400)
            .padding(.bottom, LiquidSpace.s300)
            content
        }
        // One unified panel stacked OVER the Tendencias landing (same view hierarchy), so as it
        // slides right it reveals the real Tendencias underneath — no blank platter, no shadow, no
        // separate layers. At rest it covers the landing completely. Liquid sheet paper replaces
        // the old Instrumento `pantallaFondo` chrome (content inside was already Liquid).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { LiquidSheetFondo().ignoresSafeArea() }
        // No `NavigationStack` → no FER-171 risk. The edge owns the back-swipe outright.
        .modifier(EdgeSwipeBack(enabled: true, onClose: onClose))
    }
}

/// Identifiable wrapper so the light «Instrumento» Detalle de Sueño can ride `.sheet(item:)`
/// (the model itself isn't Identifiable). One per presentation. (FER-212)
private struct SleepDetailItem: Identifiable {
    let id: UUID
    let model: SleepDetailModel
    /// FER-953: an explicit `id` lets the built model swap in under the SAME presentation identity.
    init(id: UUID = UUID(), model: SleepDetailModel) { self.id = id; self.model = model }
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

/// Off-main engines payload for `CuerpoLanding.loadAll` — pure value types crossed via
/// `Task.detached` (FER-955).
private struct CuerpoLandingEngines: Sendable {
    let recoveryCalibration: Int?
    let stressModel: StressModel?
    let trainingLoad: TrainingLoadModel?
    let fitnessAge: FitnessAgeSnapshot
    let vitalityInputs: VitalityEngine.Inputs
    let vitalityResult: VitalityEngine.Result?
}

private struct CuerpoLanding: View {
    @EnvironmentObject var repo: Repository
    @Environment(AppModel.self) var model
    @EnvironmentObject var health: HealthKitBridge
    @Environment(\.instrumentoTheme) private var theme

    /// Light metric sheet (the same one Today opens), for metrics that have a `MetricInfo` factory.
    /// Unified Detalle de Métrica (FER-185): the three vitals (HRV / FC reposo / Respiración) open this
    /// at `.full` depth instead of the legacy `MetricInfoSheet` / dark `MetricDetailView` bridge.
    @State private var metricSpec: MetricDetailSpec? = nil
    /// Light «Instrumento» Detalle de Recuperación (FER-225): the recovery hero now opens this rich detail
    /// (superset of the old `MetricInfoSheet`), built fresh on tap from the in-memory dashboard, theme
    /// passed explicitly.
    @State private var recoveryDetail: PreparacionDetalleItem? = nil
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
    /// Light «Instrumento» Entrenamientos (FER-260) — the «Workouts» row opens the reskinned list as a
    /// detail LAYER, like every other Tendencias detail (it used to be the odd one out, a card sliding up
    /// from the bottom). It keeps its own NavigationStack so a session row still pushes the detail.
    @State private var showWorkouts = false
    /// The Entrenamientos stack's path, held here (not implicit inside `NavigationStack`) so the layer can
    /// tell root from pushed: the edge-swipe-back only arms at the root, where the system's own pop isn't
    /// already listening to that edge. FER-202: `NavigationPath` (no `[WorkoutRow]`) — la línea mixta
    /// empuja DOS tipos de detalle (`WorkoutSessionRoute` de fuerza + `WorkoutRow` de actividad).
    @State private var workoutsPath = NavigationPath()
    /// FER-202: el coordinador de la puerta de Cuerpo — instancia PROPIA y estable (`@StateObject`), no la
    /// del trainStack (las dos puertas nunca son visibles a la vez). Sin él, abrir el detalle rico de una
    /// sesión CRASHEA (`WorkoutSessionDetailScreen` lo exige como `@EnvironmentObject`).
    @StateObject private var workoutsCoordinator = WorkoutHistoryCoordinator()
    /// Light «Instrumento» Detalle de Sueño (FER-212) — the «Sueño» row now opens this superset of the
    /// old dark sleep screen (built fresh on tap from the in-memory dashboard), theme passed explicitly.
    @State private var sleepDetail: SleepDetailItem? = nil
    /// Light «Instrumento» Detalle de Esfuerzo (FER-238) — the «Day Strain» row now opens this rich detail
    /// (héroe + zonas + tendencia + método) instead of the legacy `MetricInfoSheet`. Hoy unchanged.
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
    /// Carga de entrenamiento (FER-705): today's ACWR + the replayed per-day series, computed once per
    /// refresh in `loadAll` from the band-masked dashboard (the same slice the recovery detail feeds
    /// `ReadinessEngine`). nil until the first load; `acwr == nil` inside → calibrating.
    @State private var trainingLoad: TrainingLoadModel? = nil
    /// Presents the light «Carga de entrenamiento» explainer sheet (FER-705).
    @State private var trainingLoadItem: TrainingLoadItem? = nil
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
    /// Sessions in the trailing 7 days — the «Entrenamientos» row's protagonist (recent training, not
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

    private static let recoverySeed = Baselines.minNightsSeed

    var body: some View {
        ZStack {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.cardGap) {
                titleBlock
                periodSelector
                // §8.7 landing micro-legend: today's values vs last month's trends (period selector above).
                Text("Today's values \u{00B7} last month's trends")
                    .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                recoveryHero
                restLoadCard
                trainingLoadCard
                vitalsCard
                activityCard
                longevityCard
                connectNudge
                footerActions
            }
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.top, LiquidSpace.s400)   // shared titled-tab top inset
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LiquidSheetFondo(tone: heroTono))
            // Detalle «Instrumento» como CAPA sobre el landing (handoff v2 Chrome, FER-828 / FER-837): una
            // sola pantalla de papel opaco encima de Tendencias EN LA MISMA jerarquía, no un `fullScreenCover`
            // (que ocultaba el landing detrás de una plancha en blanco). Así el back-swipe descubre la
            // pantalla real de Tendencias que está debajo. Cero `NavigationStack` → cero riesgo FER-171.
            if showWorkouts {
                // Entrenamientos is the one detail that NAVIGATES (list → session), so it brings its own
                // `NavigationStack` and wears its nav bar as the chrome instead of `DetailChrome`'s —
                // otherwise the two bars stack and the two chevrons mean different things. The stack is
                // safe here: the Tendencias tab has none of its own (`RootTabView.lazyTab(.body)`), so
                // nothing nests (FER-171). The back-swipe stands down once a session is pushed — from
                // there the stack runs the system's own interactive pop off the same edge.
                workoutsLayer
                    .transition(.move(edge: .trailing))
                    .recEntranceGate()
                    .zIndex(1)
            } else if detailPresented {
                DetailChrome(theme: theme, onClose: dismissDetail) { detailOverlayContent }
                    .transition(.move(edge: .trailing))
                    // The entrance keyframes wait for the slide to land: a detail that already has its
                    // datum (Estrés / Temp. de piel / Carga) built its hero on the first frame, so its
                    // rise played under the panel's own motion and never read as an animation.
                    .recEntranceGate()
                    .zIndex(1)
            }
        }
        .animation(StrandMotion.interactive, value: detailPresented)
        .task(id: repo.refreshSeq) { await loadAll() }
        .sheet(item: $darkSheet) { sheet in darkSheetContent(sheet) }
        .sheet(isPresented: $showCompare) {
            // Light «Instrumento» Comparar — the theme is injected at the root (it doesn't cross the
            // `.sheet` boundary, FER-162) and the env objects are re-supplied (a sheet starts a fresh
            // environment branch). No nested NavigationStack (FER-171); you drag to dismiss. (FER-268)
            CompareView()
                .instrumentoTheme(theme)
                .environmentObject(repo)
                .environment(model)
                .environmentObject(health)
        }
        .sheet(isPresented: $showExplore) {
            // Light «Instrumento» Explore (FER-272) — its OWN NavigationStack lives inside the sheet so a
            // metric row pushes its detail (NOT a stack nested across the tab path, FER-171). The theme is
            // passed explicitly to the screen AND injected at the root (it doesn't cross the `.sheet`
            // boundary, FER-162); the env objects are re-supplied (a sheet starts a fresh environment).
            // A light sheet from a light tab keeps the status bar honest (no dark pin needed).
            NavigationStack {
                MetricExplorerView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showExplore = false }.foregroundStyle(theme.ink)
                        }
                    }
            }
            .instrumentoTheme(theme)
            .environmentObject(repo)
            .environment(model)
            .environmentObject(health)
        }
    }

    // MARK: - Detail layer (FER-837 follow-up)

    /// Whether ANY «Instrumento» detail is showing over the landing. Drives the `detailOverlayContent`
    /// layer + its slide-in/out animation. Only one is ever set at a time (each tap sets exactly one).
    private var detailPresented: Bool {
        metricSpec != nil || recoveryDetail != nil || strainDetail != nil || sleepDetail != nil
            || stressDetail != nil || trainingLoadItem != nil || skinTempDetail != nil
            || showActivityCost || showFitnessAge || showBodyAge || showWorkouts
    }

    /// Pops the detail layer — clears every detail-presenting state (only one is set). The `.animation`
    /// on `detailPresented` slides the layer out to the trailing edge.
    private func dismissDetail() {
        metricSpec = nil; recoveryDetail = nil; strainDetail = nil; sleepDetail = nil
        stressDetail = nil; trainingLoadItem = nil; skinTempDetail = nil
        showActivityCost = false; showFitnessAge = false; showBodyAge = false
        // The path outlives the layer (it's state here, not inside the stack), so closing from a pushed
        // session and reopening would land back on that session instead of the list.
        showWorkouts = false; workoutsPath = NavigationPath()
    }

    /// Historial (fusión FER-202) como pantalla-capa: su propio `NavigationStack`, abierto en «Todo» (toda
    /// la actividad). Una fila de fuerza empuja `WorkoutSessionDetailScreen`; una de actividad,
    /// `WorkoutDetailScreen` — ambos destinos registrados aquí. `WorkoutHistoryScreen` viste la «‹
    /// Tendencias» vía `onClose` (la capa no tiene `dismiss()`). El coordinador PROPIO se inyecta (sin él,
    /// abrir el detalle rico crashea). Theme al raíz (FER-162); env objects re-suministrados.
    private var workoutsLayer: some View {
        NavigationStack(path: $workoutsPath) {
            WorkoutHistoryScreen(
                initialFilter: .all,
                openWorkoutSession: { workoutsPath.append($0) },
                openCardio: { workoutsPath.append($0) },
                onClose: dismissDetail)
            .navigationDestination(for: WorkoutSessionRoute.self) { route in
                WorkoutSessionDetailScreen(route: route)
            }
            .navigationDestination(for: WorkoutRow.self) { row in
                WorkoutDetailScreen(theme: theme, row: row,
                                    onChange: { workoutsCoordinator.bumpReload() })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pantallaFondo()
        .instrumentoTheme(theme)
        .environmentObject(repo)
        .environment(model)
        .environmentObject(health)
        .environmentObject(workoutsCoordinator)
        .modifier(EdgeSwipeBack(enabled: workoutsPath.isEmpty, onClose: dismissDetail))
    }

    /// The detail body for whichever state is set — built exactly as the old `fullScreenCover`s did (the
    /// tap sites are unchanged; they still build each model fresh from the in-memory dashboard).
    @ViewBuilder private var detailOverlayContent: some View {
        if let spec = metricSpec {
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
                todayKey: Repository.localDayKey(Date()),
                // TND20-F8: mismo predicado que la línea de `appleConnectHint` arriba y que
                // TodayView — el detalle Liquid enseña la cláusula de permiso + CTA a Ajustes.
                // (FER-100: una línea añadida aquí; el resto de CuerpoView sigue siendo tuyo.)
                sinPermiso: health.auth != .authorized && health.auth != .unavailable
            )
        } else if let item = recoveryDetail {
            PreparacionDetailScreen(modelo: item.modelo)
        } else if let item = strainDetail {
            StrainDetailScreen(theme: theme, model: item.model, estimated: item.estimated)
        } else if let item = sleepDetail {
            SleepDetailScreen(theme: theme, model: item.model,
                              sinPermiso: health.auth != .authorized && health.auth != .unavailable)
        } else if let item = stressDetail {
            // FER-1027: el mapa intradía de estrés es de banda; en Apple-only no se muestra.
            StressDetailScreen(theme: theme, model: item.model,
                               dayMap: nil,
                               patternsLoader: { await StressDayMapPresenter.timeOfDayPatterns(
                                   repo: repo, maxHR: model.profile.hrMax, restingHR: stressRestingHR) },
                               eventPatternsLoader: { await StressDayMapPresenter.eventPatterns(
                                   repo: repo, map: stressDayMap) })
        } else if let item = trainingLoadItem {
            TrainingLoadSheet(model: item.model)
        } else if let item = skinTempDetail {
            SkinTempDetailScreen(theme: theme, model: item.model,
                                 loadWarmingMagnitudes: { await repo.nocturnalWarmingMagnitudes() })
        } else if showActivityCost {
            activityRecoverySheet
        } else if showFitnessAge {
            FitnessAgeDetailView(snapshot: fitnessAge ?? computeFitnessAge(),
                                 chronoAge: model.profile.age, sex: model.profile.sex,
                                 appleVO2max: latestAppleVO2max,
                                 appleConnectHint: health.auth != .authorized && health.auth != .unavailable
                                     && latestAppleVO2max == nil,
                                 vo2Trend: vo2maxTrend,
                                 vo2Series: vitalSeries(for: "vo2max").map(\.value),
                                 theme: theme)
        } else if showBodyAge {
            BodyAgeSheet(
                result: vitalityResult,
                inputs: vitalityInputs ?? VitalityEngine.Inputs(chronoAge: Double(model.profile.age)),
                theme: theme)
        }
    }

    // MARK: - Title + date

    /// «Body» + today's date — the landing's temporal frame. Wordmark header (matching «Patrones»):
    /// the curve-with-nodes glyph + «Tendencias» on the left, today's date in mono on the right.
    /// Liquid re-skin of `InstrumentoTabHeader` (FER-100): same glyph, same date, tinta tokens.
    private var titleBlock: some View {
        HStack(alignment: .center, spacing: LiquidSpace.s200) {
            HStack(spacing: LiquidSpace.s150) {
                TendenciasGlyph(color: LiquidColor.tinta900).frame(width: 20, height: 20)
                Text("Tendencias")
                    .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                    .foregroundStyle(LiquidColor.tinta900)
            }
            Spacer(minLength: LiquidSpace.s200)
            Text(Self.dateLabel)
                .font(LiquidType.kicker).tracking(LiquidType.kickerTracking).textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.bottom, LiquidSpace.s150)
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
    /// Liquid re-skin (FER-100): the rectangular `LiquidRangeSelector` replaces `SegmentedPillControl`.
    private var periodSelector: some View {
        LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                            seleccion: periodIndex, tono: LiquidColor.tinta700)
            .accessibilityLabel(String(localized: "Time range"))
    }

    /// A `Binding<Int>` bridging `LiquidRangeSelector`'s index to `selectedPeriod`
    /// (`ExploreRange.allCases` order = W…ALL). Mirrors `CompareView.rangeIndex`.
    private var periodIndex: Binding<Int> {
        Binding(
            get: { ExploreRange.allCases.firstIndex(of: selectedPeriod) ?? 0 },
            set: { selectedPeriod = ExploreRange.allCases[$0] })
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


    /// The stress sparkline over the selected period. Reads the model's DERIVED daily trend (`fullTrend`) —
    /// the same source the Stress value uses (stored "stress" series where present, else derived from
    /// resting-HR / HRV), so the spark isn't blank for users with no persisted WHOOP stress rows (e.g.
    /// Apple-Health-only) even though the value shows. Falls back to the raw series only if the model isn't
    /// built yet. `.all` uses the whole trend; otherwise the trailing window. (FER · sparkline de estrés)
    private var stressSpark: [Double] {
        let trend = stressModel?.fullTrend ?? []
        guard !trend.isEmpty else { return stressSeries.map(\.value) }
        guard let n = selectedPeriod.days else { return trend.map(\.value) }
        let cutoff = Calendar.current.date(byAdding: .day, value: -(n - 1), to: Date()) ?? Date()
        // Compare `Date` against the start of the cutoff day — the SAME day-granularity window as the old
        // `localDayKey` string compare, but without a `DateFormatter` round-trip per trend point (this runs
        // over the full ~300-400pt trend on every render of the body).
        let cutoffDay = Calendar.current.startOfDay(for: cutoff)
        return trend.filter { $0.date >= cutoffDay }.map(\.value)
    }

    // MARK: - Domain module scaffolding (Liquid Glass — FER-100)

    /// Wraps a domain module's content in `LiquidModulo`: the aurora edge in the hue of ITS OWN data
    /// (a 1:1 `MetricIdentity` reflection, never a raw theme token). Only `animated` modules keep a
    /// live-spinning aurora — in a scrolling list, more clocks wash the piece out — the rest render a
    /// STILL edge via `liquidAmbientPaused`, which freezes ONLY the aurora: unlike `liquidMotionDisabled`,
    /// it does NOT gate `LiquidModulo`'s glass, so the 4 still modules keep the iOS 26 native lens.
    @ViewBuilder
    private func liquidModulo<Content: View>(index: Int, tones: [Color], period: Double,
                                             reverse: Bool = false, animated: Bool,
                                             @ViewBuilder content: () -> Content) -> some View {
        if animated {
            LiquidModulo(index: index, auroraTones: tones, auroraPeriod: period,
                        auroraReverse: reverse, content: content)
        } else {
            LiquidModulo(index: index, auroraTones: tones, auroraPeriod: period,
                        auroraReverse: reverse, content: content)
                .environment(\.liquidAmbientPaused, true)
        }
    }

    /// A module's quiet regla-kicker header («REST & LOAD»). Same voice on every module.
    private func moduleTitle(_ title: LocalizedStringKey) -> some View {
        Text(title).liquidRegla().foregroundStyle(LiquidColor.tinta500)
    }

    /// A tappable stat column inside a module: a quiet neutral label, the value in its data hue (ink
    /// «—» when absent — never a hue), an optional inline unit and a footnote legend. `value == nil`
    /// is an honest empty state. SAME 9-prop signature the paper version had (FER-826 follow-up):
    /// `estimate`/`fromApple` stay accepted but undrawn — provenance lives only on the detail's
    /// OriginStamp seal, this landing never lit those badges even before the migration.
    private func statColumn(_ label: LocalizedStringKey, value: String?, unit: String? = nil,
                            color: Color, legend: LocalizedStringKey? = nil, estimate: Bool = false,
                            fromApple: Bool = false, spark: [Double] = [], tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            // Columns left-aligned; the metric name is quiet ink (`LiquidColumna`'s own convention) —
            // only the VALUE carries the data hue.
            VStack(alignment: .leading, spacing: 3) {
                Text(label).liquidDato().foregroundStyle(LiquidColor.tinta500)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.9)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value ?? "—")
                        .font(LiquidType.valorL)
                        .foregroundStyle(value == nil ? LiquidColor.tinta500 : color)
                        .opacity(value == nil ? 0.55 : 1)
                    if let unit, value != nil {
                        Text(unit).font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
                    }
                }
                // Mini-trend over the selected period — re-windows with the header selector (FER-566). A stat
                // with <2 points in the window draws nothing (honest empty state, never a fake spark). Color
                // ONLY on the datum: the line carries the stat's own data hue, area very faint.
                if value != nil, spark.count > 1 {
                    Sparkline(values: spark,
                              gradient: ChartWell.fillGradient(color),
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
                    Text(legend).font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .combine)
    }

    /// Hairline between stat columns — `LiquidCapilar`, the Liquid capilar divider.
    private var vsep: some View { LiquidCapilar() }

    // MARK: - Domain modules

    /// Rest & load — Sleep · Day Strain · Stress, each column into its detail. Animated aurora (top module).
    private var restLoadCard: some View {
        liquidModulo(index: 0, tones: [LiquidColor.indigo, LiquidColor.ambar, LiquidColor.estresMedio],
                    period: 44, animated: true) {
            VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                moduleTitle("Rest & load")
                HStack(spacing: LiquidSpace.s300) {
                    sleepStat
                    vsep
                    strainStat
                    vsep
                    stressStat
                }
            }
        }
    }

    /// Carga de entrenamiento (FER-705) — the band in a plain word is the datum (colored by its band),
    /// with the glossed ratio underneath and the replayed-ratio mini-trend as the right accessory.
    /// Calibrating (< ~2 weeks of strain) shows an honest «—» + the wait copy, never a fake number.
    /// The whole card taps into the explainer sheet. Animated aurora (second module).
    private var trainingLoadCard: some View {
        let load = trainingLoad
        let band = load?.band
        return Button {
            trainingLoadItem = TrainingLoadItem(model: load ?? TrainingLoadModel(acwr: nil, series: []))
        } label: {
            liquidModulo(index: 1, tones: [LiquidColor.ambar, LiquidColor.ambarClaro],
                        period: 52, reverse: true, animated: true) {
                VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                    moduleTitle("Training load")
                    HStack(spacing: LiquidSpace.s400) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(band?.shortLabel ?? "—")
                                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                                .foregroundStyle(band.map(loadBandColor) ?? LiquidColor.tinta500)
                            if let acwr = load?.acwr {
                                Text("\(String(format: "%.2f", acwr)) · recent vs. your usual")
                                    .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta700)
                            } else {
                                Text("I need about two weeks of recorded strain to read your load.")
                                    .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta700)
                            }
                        }
                        Spacer(minLength: LiquidSpace.s200)
                        if let load, load.series.count > 1, let band {
                            let color = loadBandColor(band)
                            ZStack(alignment: .center) {
                                Capsule().fill(LiquidColor.tinta10)
                                    .frame(width: 104, height: 3)
                                Sparkline(values: load.series.map(\.value),
                                          gradient: ChartWell.fillGradient(color),
                                          lineWidth: 2.0, showsArea: false, showsHead: true, showsScrub: false)
                                    .frame(width: 104, height: 40)
                            }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
                        // Sin chevron (FER-837): el renglón «Toca cualquier dato para ver su detalle» ya comunica
                        // que la tarjeta es tocable; el chevron se reserva a las que abren una pantalla/herramienta
                        // distinta («tras cada deporte», Comparar, Ver todas las métricas).
                    }
                }
            }
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the training-load explainer.")
    }

    /// The band's Liquid color, the SAME mapping `TrainingLoadSheet.hillColor` uses (FER-105/TND-32),
    /// re-derived here since that helper is file-private — keeps the module and its explainer sheet
    /// agreeing on the band's color, never `ReadinessEngine.Flag.color(theme:)` (the paper mapping).
    private func loadBandColor(_ band: ReadinessEngine.LoadBand) -> Color {
        switch band {
        case .rampingDown, .sweetSpot: return LiquidColor.verdePrimario
        case .buildingFast:            return LiquidColor.atencion
        case .spiking:                 return LiquidColor.negativo
        }
    }

    /// Vitals — a 3×2 grid of scalar vitals, each into its `MetricDetailScreen`. Two explicit rows (not
    /// a `LazyVGrid`) so a `LiquidCapilar` can seam the two, same 6 stats/order/taps. Still aurora.
    private var vitalsCard: some View {
        liquidModulo(index: 3, tones: [LiquidColor.cian, LiquidColor.rosa, LiquidColor.azul],
                    period: 38, animated: false) {
            VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                moduleTitle("Vitals")
                VStack(spacing: LiquidSpace.s300) {
                    HStack(spacing: LiquidSpace.s300) { hrvStat; vsep; rhrStat; vsep; spo2Stat }
                    LiquidCapilar(eje: .horizontal)
                    HStack(spacing: LiquidSpace.s300) { heartStat; vsep; respStat; vsep; skinTempStat }
                }
            }
        }
    }

    /// Activity — Steps · Workouts·7d, with «How you wake after each sport» nested under a hairline.
    /// Still aurora.
    private var activityCard: some View {
        liquidModulo(index: 4, tones: [LiquidColor.teal, LiquidColor.ambar], period: 58, animated: false) {
            VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                moduleTitle("Activity")
                HStack(spacing: LiquidSpace.s300) {
                    stepsStat
                    vsep
                    workoutsStat
                }
                LiquidCapilar(eje: .horizontal)
                activityInsight
            }
        }
    }

    /// Longevity — Physical age · Body age · VO₂ Max, each with a micro-legend, into its sheet. Still aurora.
    private var longevityCard: some View {
        liquidModulo(index: 5, tones: [LiquidColor.verdePrimario, LiquidColor.ambar, LiquidColor.tinta500],
                    period: 44, animated: false) {
            VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                moduleTitle("Longevity")
                HStack(alignment: .top, spacing: LiquidSpace.s300) {
                    physicalAgeStat
                    vsep
                    bodyAgeStat
                    vsep
                    vo2maxStat
                }
            }
        }
    }

    // MARK: - Recovery hero (the single dominant element — Instrumento rule 1)

    /// El héroe del aterrizaje. **Ya no lee `recovery`**, que es `nil` en producción desde que
    /// la app dejó de tener banda (`AppleHealthImport.swift:70` y `HealthKitBridge.swift:452` lo
    /// escriben nil, y `RecoveryScorer.recovery(...)` no tiene un solo consumidor). El número
    /// nunca llegaba: la pantalla llevaba meses mostrando un guion o una calibración eterna.
    ///
    /// Ahora muestra lo que la app SÍ calcula: el veredicto de Preparación de hoy. Es
    /// categórico a propósito — el puntaje 0–100 se retiró y no vuelve por la puerta de atrás.
    /// Salud «conectada» EFECTIVA, con la misma regla que Hoy (`TodayView.saludConectada`): en
    /// modo fixture el permiso real nunca está concedido, y sin este escape la pantalla de
    /// Preparación se vería siempre en su estado «sin permiso» en las capturas.
    private var saludConectada: Bool {
        #if DEBUG
        if ScreenshotFixtures.activeState() != nil { return true }
        #endif
        return health.auth == .authorized
    }

    /// The hero's tone: `LiquidHoyBuilder.actaTono` (the SAME tone the acta uses) when there's a real
    /// verdict, `nil` otherwise — `nil` is the signal that apaga the lens to paper/ink, never green.
    /// Gate is `isNightAnchored`, the SAME one `preparacionHeroe` branches on: no night recorded, no
    /// verdict to tint. Also feeds the screen's ambient background (`LiquidSheetFondo`, `body`).
    private var heroTono: Color? {
        guard let prep = repo.todayPreparedness, prep.verdict != .lowSignal, prep.isNightAnchored
        else { return nil }
        return LiquidHoyBuilder.actaTono(prep)
    }

    /// The tinted-lens hero — FER-100's bespoke Liquid piece (`liquidLenteTenida`, below): a
    /// diagonal-gradient card in the verdict's own tone with a calado numeral, or paper/ink with NO
    /// gradient when there's nothing to tint. Content = the verdict WORD (or the calibration count, or
    /// «—»), never a number — the 0–100 score is retired and doesn't come back through this door.
    private var recoveryHero: some View {
        let prep = repo.todayPreparedness
        let cal = recoveryCalibration
        let tono = heroTono
        let calado = tono != nil
        return Button {
            // FER-954: present the loading state IMMEDIATELY; the model builds off-main and swaps
            // in under the same id (same pattern as `sleepStat`, FER-953).
            let item = PreparacionDetalleItem(modelo: .cargando)
            recoveryDetail = item
            Task {
                let m = await PreparacionDetalleModelo.buildDetached(repo: repo, healthConnected: saludConectada)
                if recoveryDetail?.id == item.id {
                    recoveryDetail = PreparacionDetalleItem(id: item.id, modelo: m)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                Text("Preparation")
                    .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                    .foregroundStyle(calado ? LiquidColor.papelAlto.opacity(LiquidCampo.alfaRotulo) : LiquidColor.tinta500)
                preparacionHeroe(prep, calibrando: cal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .liquidLenteTenida(tono: tono)
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .combine)
    }

    /// El héroe de Preparación: la PALABRA del veredicto, no un número.
    ///
    /// Las palabras son las de Hoy (`hero.title.*`, FER-10, aprobadas por el dueño en 6
    /// iteraciones y pasadas por `/cso`) — no las del comentario del motor, que quedaron
    /// obsoletas cuando estas las sustituyeron.
    @ViewBuilder
    private func preparacionHeroe(_ prep: Preparedness.Read?, calibrando: Int?) -> some View {
        // `isNightAnchored` es OBLIGATORIO, el MISMO gate que Hoy pone antes de titular
        // (`LiquidHoyBuilder.actaTono`, `:1185`): sin noche grabada no hay veredicto que
        // decir, y titularlo teñido contradiría al texto de la propia pantalla.
        if let prep, prep.verdict != .lowSignal, prep.isNightAnchored {
            Text(LiquidHoyBuilder.palabraVeredicto(prep.verdict))
                .font(LiquidType.displayL).tracking(LiquidType.displayLTracking)
                .foregroundStyle(LiquidColor.papelAlto)
            Text(LiquidHoyBuilder.clausulaVeredicto(prep))
                .font(LiquidType.clausulaCampo)
                .foregroundStyle(LiquidColor.papelAlto.opacity(LiquidCampo.alfaRotulo))
                .fixedSize(horizontal: false, vertical: true)
        } else if let calibrando {
            Text("\(calibrando)")
                .font(LiquidType.displayL).tracking(LiquidType.displayLTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(recoverySubtitle(calibrating: calibrando))
                .font(LiquidType.clausulaCampo).foregroundStyle(LiquidColor.tinta700)
            recoveryHeroAccessory(calibrating: calibrando)
        } else {
            Text("—")
                .font(LiquidType.displayL).tracking(LiquidType.displayLTracking)
                .foregroundStyle(LiquidColor.tinta500)
            Text(recoverySubtitle(calibrating: nil))
                .font(LiquidType.clausulaCampo).foregroundStyle(LiquidColor.tinta700)
        }
    }

    /// El acompañante del héroe: la barra de calibración mientras la base madura. SOLO la barra —
    /// sin sparkline, sin «vs media» (FER-100 spec). Track/relleno en tinta, nunca verde: calibrando
    /// vive en la rama SIN veredicto del héroe (apagada a papel/tinta).
    ///
    /// FER-119 le quitó la sparkline: su serie era `windowedSpark(\.recovery)` y los dos
    /// escritores de filas guardan `recovery: nil` (AppleHealthImport:70, HealthKitBridge:452),
    /// así que la serie salía vacía y la rama nunca se dibujaba. Preparación es categórica: su
    /// historia se lee como veredictos por noche en la pantalla de detalle, no como una curva.
    @ViewBuilder
    private func recoveryHeroAccessory(calibrating: Int?) -> some View {
        if let calibrating {
            Capsule().fill(LiquidColor.tinta10)
                .frame(width: 132, height: 6)
                .overlay(alignment: .leading) {
                    Capsule().fill(LiquidColor.tinta500)
                        .frame(width: 132 * CGFloat(calibrating) / CGFloat(Self.recoverySeed), height: 6)
                }
                .padding(.top, LiquidSpace.s200)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Stat columns (one per metric — same value resolution + tap target as the old rows)

    private var sleepStat: some View {
        let r = resolveMeasured { $0.totalSleepMin }
        let fromApple = r?.fromApple == true
        return statColumn("Sleep", value: r.map { sleepText($0.value) },
                          color: MetricIdentity.identity(forKey: "sleep_total_min").hue,
                          fromApple: fromApple, spark: windowedSpark { $0.totalSleepMin }) {
            // FER-953: present the loading state IMMEDIATELY; the model builds off-main and swaps
            // in under the same id (so the layer updates in place — no re-presentation).
            let item = SleepDetailItem(model: .loading)
            sleepDetail = item
            Task {
                let m = await SleepDetailModel.buildDetached(repo: repo)
                if sleepDetail?.id == item.id {   // still the same presentation — user didn't close it
                    sleepDetail = SleepDetailItem(id: item.id, model: m)
                }
            }
        }
    }

    private var strainStat: some View {
        // El score asentado del día (`displayedDayStrain`) — el mismo número que muestra el héroe del
        // Detalle de Esfuerzo (la curva intradía «hora a hora» se retiró en FER-1025). FER-883: on a
        // band-less Apple day the label flips to «Day load» + originApple; band days stay
        // byte-identical ("Day Strain" / originComputed).
        let v = model.displayedDayStrain
        let estimated = repo.isStrainEstimated(repo.today?.day ?? Repository.localDayKey(Date()))
        return statColumn(estimated ? "Day load" : "Day Strain", value: v.map { String(format: "%.1f", $0) },
                          color: MetricIdentity.identity(forKey: "strain").hue,
                          spark: windowedSpark { $0.strain }) {
            // Opens the rich Detalle de Esfuerzo (FER-238) — built fresh from the in-memory dashboard.
            // (Hoy still uses `MetricInfo.strain`/`MetricInfoSheet`.) FER-954: present the loading state IMMEDIATELY;
            // the model builds off-main and swaps in under the same id (same pattern as `sleepStat`).
            let estimatedNow = repo.isStrainEstimated(repo.today?.day ?? Repository.localDayKey(Date()))
            let item = StrainDetailItem(model: .loading, estimated: estimatedNow)
            strainDetail = item
            Task {
                let m = await StrainDetailModel.buildDetached(repo: repo)
                if strainDetail?.id == item.id {
                    strainDetail = StrainDetailItem(id: item.id, model: m, estimated: estimatedNow)
                }
            }
        }
    }

    private var stressStat: some View {
        let s = stressModel?.score
        // Stress accompanies, it doesn't vote (HJ-09): a STATIC identity chip, not a band ramp —
        // `MetricIdentity`'s representative mid-ocre for "stress", same color with or without a
        // reading today (the empty-state grey in `statColumn` already handles `value == nil`).
        return statColumn("Stress", value: s.map { String(format: "%.1f", $0) },
                          unit: s == nil ? nil : "/ 3",
                          color: MetricIdentity.identity(forKey: "stress").hue,
                          spark: stressSpark) {
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
        let fromApple = r?.fromApple == true
        return statColumn("HRV", value: r.map { "\(Int($0.value.rounded()))" }, unit: String(localized: "ms"),
                          color: MetricIdentity.identity(forKey: "hrv").hue,
                          fromApple: fromApple,
                          spark: windowedSpark { $0.avgHrv }) {
            metricSpec = .hrv(r?.value)
        }
    }

    private var rhrStat: some View {
        let r = resolveMeasured { $0.restingHr.map(Double.init) }
        let fromApple = r?.fromApple == true
        return statColumn("Resting HR", value: r.map { "\(Int($0.value.rounded()))" }, unit: String(localized: "bpm"),
                          color: MetricIdentity.identity(forKey: "rhr").hue,
                          fromApple: fromApple,
                          spark: windowedSpark { $0.restingHr.map(Double.init) }) {
            metricSpec = .restingHR(r.map { Int($0.value.rounded()) })
        }
    }

    private var spo2Stat: some View {
        let r = resolveMeasured { $0.spo2Pct }
        let fromApple = r?.fromApple == true
        return statColumn("Blood Oxygen", value: r.map { String(format: "%.0f", $0.value) }, unit: "%",
                          color: MetricIdentity.identity(forKey: "spo2").hue,
                          fromApple: fromApple,
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
                          color: MetricIdentity.identity(forKey: "heart_rate").hue,
                          legend: "intraday, no daily series") {
            metricSpec = .heartRate(avg)
        }
    }

    private var respStat: some View {
        let r = resolveMeasured { $0.respRateBpm }
        let fromApple = r?.fromApple == true
        return statColumn("Respiratory", value: r.map { String(format: "%.1f", $0.value) }, unit: String(localized: "rpm"),
                          color: MetricIdentity.identity(forKey: "resp_rate").hue,
                          fromApple: fromApple,
                          spark: windowedSpark { $0.respRateBpm }) {
            metricSpec = .respiratory(r?.value)
        }
    }

    private var skinTempStat: some View {
        let r = resolveMeasured { $0.skinTempDevC }
        let fromApple = r?.fromApple == true
        return statColumn("Skin temp", value: r.map { String(format: "%+.1f", $0.value) }, unit: "°C",
                          color: MetricIdentity.identity(forKey: "skin_temp").hue,
                          fromApple: fromApple,
                          spark: windowedSpark { $0.skinTempDevC }) {
            // Opens the rich light Detalle de Temperatura de la piel (FER-256) — built fresh from the
            // in-memory dashboard (última lectura resuelta + serie completa de `displayDays`).
            skinTempDetail = SkinTempDetailItem(model: SkinTempDetailModel.build(
                latest: r?.value, series: vitalSeries(for: "skin_temp"), loaded: repo.loaded))
        }
    }

    private var stepsStat: some View {
        let steps = freshSteps
        let fromApple = steps != nil
        return statColumn("Steps", value: steps.map { intString(Double($0)) },
                          color: MetricIdentity.identity(forKey: "steps").hue,
                          fromApple: fromApple,
                          spark: windowedSpark { $0.steps.map(Double.init) }) {
            metricSpec = .steps(steps)
        }
    }

    /// «Entrenamientos» — the recent-session count tinted in the effort hue. Not a `MetricCatalog` key
    /// (no `MetricIdentity` entry to route through), so it takes the strain family's hue directly —
    /// the same `LiquidColor.ambar` `MetricIdentity.identity(forKey: "strain")` resolves to. No recent
    /// sessions → honest "—"; VoiceOver says it plainly, not "dash". (FER-259)
    @ViewBuilder private var workoutsStat: some View {
        let n = recentWorkoutCount
        // Trailing 7 days from today — the SAME window and anchor the Entrenamientos screen opens on, so
        // the tile you tap and the screen you land on always show the same count (the «this week» legend
        // was a third, different window that read as a contradiction). (FER — unify to 7d trailing)
        let col = statColumn("Workouts · 7d", value: n > 0 ? "\(n)" : nil,
                             color: LiquidColor.ambar) {
            showWorkouts = true
        }
        if n > 0 { col } else { col.accessibilityLabel(Text("no workouts yet")) }
    }

    // MARK: - Longevity stats (Fitness Age FER-141 · Body Age FER-145 · VO₂max FER-257)

    /// Physical age — the value tinted by DIRECTION (younger green / older amber / even ink, faint «—»
    /// when there's no reading), with a compact legend and the «Estimate» chip on low confidence.
    private var physicalAgeStat: some View {
        let snap = fitnessAge
        let estimate = snap?.readiness.confidence == .estimate
        let color = snap?.result.map(physicalAgeColor) ?? LiquidColor.tinta500
        return statColumn("Physical age",
                          value: snap?.result.map { "\(Int($0.fitnessAge.rounded()))" },
                          color: color,
                          legend: physicalAgeLegend(snap), estimate: estimate) {
            showFitnessAge = true
        }
    }

    /// Direction hue: younger → recovery green, older → warning amber, even → ink. The ±0.5-yr
    /// deadband lives on `FitnessAgeResult.direction` (StrandAnalytics) so the row and the sheet agree.
    /// Physical age is NOT metric identity (FER-100 spec) — it keeps its DIRECTIONAL color by delta.
    private func physicalAgeColor(_ result: FitnessAgeResult) -> Color {
        switch result.direction {
        case .younger: return LiquidColor.verdePrimario
        case .older:   return LiquidColor.atencion
        case .even:    return LiquidColor.tinta900
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
    /// primary path is the off-main hop in `loadAll` (FER-955); kept as the sheet's on-demand fallback.
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
        // NOT metric identity (FER-100 spec) — DIRECTIONAL by delta, via the sheet's OWN Liquid ladder
        // (`BodyAgeSheet.tintLiquid`) so the tile and the detail it opens never disagree on a color.
        let color = r.map { BodyAgeSheet.tintLiquid(forDelta: $0.deltaYears) } ?? LiquidColor.tinta500
        // «Estimate» chip when a heaviest factor (HRV/RHR) is missing — same mechanism as Physical age
        // (FER-643), so the two longevity stats read consistently.
        return statColumn("Body age", value: r.map { "\(Int($0.bodyAge.rounded()))" },
                          color: color,
                          legend: r == nil ? nil : "vs your \(model.profile.age)",
                          estimate: r?.isPartialEstimate == true) {
            showBodyAge = true
        }
    }

    /// VO₂max (Apple Health, measured · FER-257): the most recent reading (no freshness gate), the unit
    /// carried by the «ml/kg·min» legend so the numeral stays clean. «—» + no chip when unread.
    private var vo2maxStat: some View {
        let v = latestAppleVO2max
        // Neutral ink on purpose (MetricIdentity D1, FER-108) — no family assigned yet, so it borrows
        // no other metric's color. Fixes the paper's `theme.dataSpO2` (blue) reuse bug.
        return statColumn("VO₂ Max", value: v.map { String(format: "%.0f", $0) },
                          color: MetricIdentity.identity(forKey: "vo2max").hue,
                          legend: "ml/kg·min", fromApple: v != nil) {
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
                HStack(spacing: LiquidSpace.s200) {
                    LiquidIcon(.corazon, size: 17, color: LiquidColor.azul)
                    Text("Connect Apple Health to fill steps and more.")
                        .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
                    Spacer(minLength: LiquidSpace.s150)
                    LiquidIcon(.chevron, size: 12, color: LiquidColor.tinta500)
                }
                .padding(.horizontal, LiquidSpace.s400)
                .padding(.vertical, LiquidSpace.s300)
                .background(LiquidColor.azul.opacity(0.07), // token-exempt: nudge tint, preview-approved
                           in: RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous)
                    .strokeBorder(LiquidColor.azul.opacity(0.14), lineWidth: 1))  // token-exempt: nudge border, preview-approved
                .contentShape(Rectangle())
            }
            .buttonStyle(.liquidPress)
        }
    }

    private var footerActions: some View {
        VStack(spacing: 0) {
            actionRow("Compare", icon: "arrow.left.arrow.right") { showCompare = true }
            LiquidCapilar(eje: .horizontal).padding(.leading, 46)
            actionRow("See all metrics", icon: "square.grid.2x2") { showExplore = true }
        }
        .liquidGlass(.superficieSolida)
    }

    private func actionRow(_ label: LocalizedStringKey, icon: String, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: LiquidSpace.s300) {
                Image(systemName: icon).font(LiquidType.iconSF(size: 17))
                    .foregroundStyle(LiquidColor.tinta700).frame(width: 22)
                Text(label).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                Spacer(minLength: LiquidSpace.s200)
                LiquidIcon(.chevron, size: 12, color: LiquidColor.tinta500)
            }
            .padding(.horizontal, LiquidSpace.s400).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
    }

    // MARK: - Activity insight (FER-139) — nested under Activity, NOT a card-in-card (Instrumento rule 3)

    /// «How you wake after each sport» — up to three top sports from the engine's ranking, each as
    /// `sport · N pts lower/higher` (colour only on the datum). A `delta < 3` sport reads «no clear
    /// link». When the engine returns nothing the block stays, showing «Gathering data» — it never
    /// hides. Lives under a hairline inside the Activity card; its own chevron jumps to the detail.
    private var activityInsight: some View {
        Button { showActivityCost = true } label: {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                HStack(spacing: LiquidSpace.s200) {
                    Text("How you wake after each sport")
                        .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                    // Provisional placement (likely Entrenar / Patrones later). (FER-566)
                    Spacer(minLength: LiquidSpace.s200)
                    if activityCosts.isEmpty {
                        Text("Gathering data").font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                    }
                    LiquidIcon(.chevron, size: 12, color: LiquidColor.tinta500)
                }
                if !activityCosts.isEmpty {
                    VStack(spacing: LiquidSpace.s150) {
                        ForEach(Array(activityCosts.prefix(3).enumerated()), id: \.offset) { _, c in
                            activityCostRow(c)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the per-sport detail.")
    }

    /// One summary row inside the block: sport name (ink) · its direction/points. Colour on the datum:
    /// the gap takes the strain family's hue (`LiquidColor.ambar`, not routed through `MetricIdentity` —
    /// this delta isn't a catalog metric) when there's a real link, quiet ink when it's under the
    /// engine's noise floor (then it reads «no clear link»). Same single-tone rule the paper had — NOT
    /// re-colored by the sign of the delta: `ActivityCost.delta`'s good/bad direction depends on which
    /// underlying signal moved, and guessing it here risked telling the wrong story (FER-100 — kept
    /// conservative rather than invent a new positive/negative semantic). Localized; "pts" stays plural
    /// (a reported gap is ≥ 3).
    private func activityCostRow(_ c: ActivityCost) -> some View {
        let meaningful = abs(c.delta) >= ActivityCostEngine.barelyMovesPoints
        let pts = Int(abs(c.delta).rounded())
        let summary: LocalizedStringKey = !meaningful ? "no clear link"
            : (c.delta >= 0 ? "\(pts) pts lower" : "\(pts) pts higher")
        return HStack(spacing: LiquidSpace.s200) {
            Text(verbatim: c.sport).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
            Spacer(minLength: LiquidSpace.s200)
            Text(summary)
                .font(LiquidType.captionLectura)
                .foregroundStyle(meaningful ? LiquidColor.ambar : LiquidColor.tinta500)
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
        .environment(model)
        .environmentObject(health)
        .preferredColorScheme(.light)
    }

    // MARK: - Loading (memoize once per refresh)

    /// Loads query-backed `@State` on MainActor, then runs the pure StrandAnalytics engines off-main
    /// (FER-955 — same snapshot → `Task.detached` seam as `SleepDetailModel.buildDetached`).
    private func loadAll() async {
        // Stale-refresh guard: `.task(id: repo.refreshSeq)` re-runs this when the seq bumps, but the
        // detached engines task is not auto-cancelled — discard results if a newer refresh won (FER-955).
        let seq = repo.refreshSeq

        // The sparklines (hero + every stat) are computed properties windowed by `selectedPeriod` straight
        // off `repo.displayDays`, so they re-window on selector change without a reload (FER-566). Only the
        // stored stress series needs loading here (stress isn't a `DailyMetric` field).

        // Today's HR is bucketed; the rest of the daily/Apple rows feed values, not sparklines.
        async let adRows     = repo.appleDailyRows()
        async let amRows     = repo.appleDailyMetricRows()
        async let wkRows     = repo.workoutRows()
        // Stored daily "stress" series (0–3) — the model prefers it, else derives from RHR/HRV.
        async let stressRows = repo.series(key: "stress", source: "strap")
        let startOfToday = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let nowTs = Int(Date().timeIntervalSince1970)
        async let hrRows = repo.hrBuckets(from: startOfToday, to: nowTs, bucketSeconds: 300)

        appleDays = await adRows
        appleMetricDays = (await amRows).sorted { $0.day < $1.day }
        let workouts = await wkRows
        workoutCount = workouts.count
        // Sessions in the trailing 7 calendar days for the «Entrenamientos» row — start-of-day 6 days ago
        // through now. SAME window + anchor as `WorkoutsView.cutoff(for: .week)`, so the tile and the
        // screen it opens never disagree (they used to: 14d tile vs 7d screen). (FER — unify to 7d trailing)
        let recentCutoff = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        let recentCutoffTs = Int(recentCutoff.timeIntervalSince1970)
        recentWorkoutCount = workouts.filter { $0.startTs >= recentCutoffTs }.count
        activityCosts = repo.activityCosts(from: workouts)   // reuses the rows above — no second query
        hrPoints = await hrRows.map {
            TrendPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: $0.bpm)
        }
        // Ola 2: live day-strain fold retired with the band; settled daily strain via repo.today is enough.
        // displayDays = Apple-health fallback (FER-149); local todayKey ignores a UTC "tomorrow" row (FER-226).
        let stored = await stressRows
        stressSeries = stored   // for the Stress stat's sparkline (FER-566)

        // Value-type snapshots for the off-main engines hop (FER-955).
        let days: [DailyMetric] = repo.days
        let displayDays: [DailyMetric] = repo.displayDays
        let appleHealthDays: Set<String> = repo.appleHealthDays
        // FER-119: esto apaga el contador de calibración (`guard !hasRecovery`, RecoveryScorer:140).
        // Colgaba de `recovery`, que los dos escritores de filas dejan en `nil`
        // (AppleHealthImport:70, HealthKitBridge:452) — así que era SIEMPRE falso y el aterrizaje
        // se quedaba «calibrando» para siempre, aun con el veredicto ya en firme. Ahora cuelga del
        // veredicto real: `lowSignal` es «no hubo lectura», no una lectura, y sigue calibrando.
        let prepNights: Int? = repo.todayPreparedness?.autonomicNights
        let hasRecovery: Bool = {
            guard let p = repo.todayPreparedness else { return false }
            return p.verdict != .lowSignal && p.isNightAnchored
        }()
        let sleeps = repo.sleeps
        let appleSleeps = repo.appleSleeps   // FER-1026: real Apple sleep sessions feed regularity too (no strap)
        let age: Int = model.profile.age
        let sex = model.profile.sex
        let todayKey: String = Repository.localDayKey(Date())
        let regularityCutoff: Int = Int(Date().timeIntervalSince1970) - 35 * 86_400

        // Pure StrandAnalytics engines off MainActor (FER-955). Same expressions as before; only the
        // executor moves. Assignments return to main below, gated by `seq`.
        let engines: CuerpoLandingEngines = await Task.detached(priority: .userInitiated) { () -> CuerpoLandingEngines in
            // FER-119: el contador cuenta AHORA lo mismo que madura el veredicto. Antes salía
            // de `RecoveryScorer.calibrationNights(nightlyHrv:)`, que cuenta noches con VFC
            // (SDNN) — pero la madurez del veredicto sale de la base de FC EN REPOSO
            // (`Preparedness.autonomicNights`, y `wHRV = 0`: la VFC de Apple ni siquiera vota).
            // Son dos constructos distintos que divergen: quien acumule noches de VFC más
            // rápido veía la barra llenarse hasta «4 de 4», desaparecer, y caer a «—» sin
            // veredicto — el mismo síntoma que este cambio venía a quitar, por otra puerta.
            let recoveryCalibration: Int? = {
                guard !hasRecovery, let n = prepNights, (1..<Baselines.minNightsSeed).contains(n)
                else { return nil }
                return n
            }()

            let stressModel: StressModel? = StressModel(days: displayDays, stored: stored,
                                                        todayKey: todayKey, appleDays: appleHealthDays)

            // Carga de entrenamiento (FER-705): today's ACWR + the replayed series, from the BAND-masked
            // dashboard — the same slice the recovery detail feeds `ReadinessEngine` (FER-632), so the card,
            // the «Your patterns» line and the verdict signal can never disagree on the band.
            let bandMasked: [DailyMetric] = SourceLens.clearBandColumns(days)
            let readiness = ReadinessEngine.evaluate(days: bandMasked, today: todayKey)
            let acwrSeries: [(day: String, value: Double)] = ReadinessEngine.acwrSeries(days: bandMasked)
                .map { (p: (day: String, ratio: Double)) -> (day: String, value: Double) in
                    (day: p.day, value: p.ratio)
                }
            let trainingLoad: TrainingLoadModel = TrainingLoadModel(
                acwr: readiness.acwr,
                series: acwrSeries,
                days: bandMasked)

            // Trailing-N of `displayDays` — same cutoff+filter as `trailingDisplay`, inlined so we never
            // call MainActor-isolated helpers from this detached task. `DayKey.localFormatter` is the
            // same object `Repository.localDayKey` uses (nonisolated; FER-955).
            func trailing(_ n: Int) -> [DailyMetric] {
                let cutoffDate: Date = Calendar.current.date(byAdding: .day, value: -(n - 1), to: Date()) ?? Date()
                let cutoff: String = DayKey.localFormatter.string(from: cutoffDate)
                return displayDays.filter { (d: DailyMetric) -> Bool in d.day >= cutoff }
            }

            let last7: [DailyMetric] = trailing(7)
            let fitnessAge = FitnessAgeEngine.snapshot(
                rhrLast7: last7.map { (d: DailyMetric) in d.restingHr },
                strainLast7: last7.map { (d: DailyMetric) in d.strain },
                age: age, sex: sex,
                hasHeightWeight: true)

            // Longevity (FER-145 + FER-214): Body Age + Vitality from a 28-night window. Regularity uses the
            // real Sleep Regularity Index when there's coverage (FER-214), else the documented duration proxy;
            // VO₂max needs a waist the profile doesn't collect, so the cardio signal flows through resting HR.
            // Clear cross-source columns before the engine folds them (FER-640): `nightlyRMSSD`
            // takes the MEDIAN of `avgHrv` and `VitalityEngine` scores it against an RMSSD-by-age norm, but
            // `displayDays` back-fills Apple **SDNN** on band-less nights (FER-149) — a different construct with
            // no published conversion (Task Force 1996; Shaffer & Ginsberg 2017), so a few Apple nights bias
            // Body Age by source, not physiology. The same `SourceLens.clearBandColumns` (FER-631)
            // also nils Apple's resting HR (band −12.7 bpm offset), which likewise scores against a band-domain
            // norm — so both nocturnal inputs stay single-source. Single-source columns (steps) and cross-source-
            // comparable ones (sleep duration) are untouched. If the user is Apple-only, band RMSSD is empty →
            // `VitalityInputsBuilder`'s coverage gate drops the HRV factor rather than comparing SDNN to the
            // band norm. A strap-only user is the identity — `recentBand == recent`.
            let recent: [DailyMetric] = trailing(28)
            let recentBand: [DailyMetric] = SourceLens.clearBandColumns(recent)
            // Sleep Regularity Index (FER-214) over a trailing ~35d of sessions, as 0–1 for the engine (SRI/100).
            // nil → the builder's duration proxy. Was `computeSleepRegularity()`; inlined for the hop (FER-955).
            // FER-1026: feed from Apple + strap sessions (union, no overlap) so Apple-only users keep the SRI
            // instead of silently dropping to the duration proxy.
            let recentSleeps = (appleSleeps + sleeps).filter { (s: CachedSleepSession) -> Bool in s.startTs >= regularityCutoff }
            let sleepRegularity: Double? = SleepRegularityIndex.fromSessions(recentSleeps).map { (sri: Double) -> Double in sri / 100.0 }
            let nightlyRestingHR: [Double] = recentBand.compactMap { (d: DailyMetric) -> Double? in d.restingHr.map(Double.init) }
            let nightlyRMSSD: [Double] = recentBand.compactMap { (d: DailyMetric) -> Double? in d.avgHrv }
            let nightlySleepHours: [Double] = recent.compactMap { (d: DailyMetric) -> Double? in
                d.totalSleepMin.map { (m: Double) -> Double in m / 60.0 }
            }
            let dailySteps: [Double] = recent.compactMap { (d: DailyMetric) -> Double? in d.steps.map(Double.init) }
            let vInputs = VitalityInputsBuilder.build(.init(
                chronoAge: Double(age),
                nightlyRestingHR: nightlyRestingHR,
                nightlyRMSSD: nightlyRMSSD,
                nightlySleepHours: nightlySleepHours,
                dailySteps: dailySteps,
                sleepRegularity: sleepRegularity))
            let vResult = VitalityEngine.compute(vInputs)

            return CuerpoLandingEngines(
                recoveryCalibration: recoveryCalibration,
                stressModel: stressModel,
                trainingLoad: trainingLoad,
                fitnessAge: fitnessAge,
                vitalityInputs: vInputs,
                vitalityResult: vResult)
        }.value

        guard repo.refreshSeq == seq else { return }

        recoveryCalibration = engines.recoveryCalibration
        stressModel = engines.stressModel
        trainingLoad = engines.trainingLoad
        fitnessAge = engines.fitnessAge
        vitalityInputs = engines.vitalityInputs
        vitalityResult = engines.vitalityResult
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

    /// The fitness trajectory (rising / stable / falling) from the measured Apple VO₂max series (FER-833).
    /// `nil` below the data minimum (< 6 readings or < 21 days) → the trend block hides. Uses days-since-
    /// epoch as the time index the robust (Theil–Sen) slope needs. Every Apple reading is a real
    /// measurement, so the raw series feeds the trend directly.
    private var vo2maxTrend: VO2maxTrend.Result? {
        let points: [VO2maxTrend.Point] = vitalSeries(for: "vo2max").compactMap { row in
            guard let date = Repository.parseDayKey(row.day) else { return nil }
            return VO2maxTrend.Point(day: Int(date.timeIntervalSince1970 / 86_400), value: row.value)
        }
        return VO2maxTrend.assess(points)
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

    /// The 14-day trend loader the `MetricInfoSheet` runs lazily. Strain returns nil (it shows its
    /// verdict + levels instrument, not a 14-day chart); resp/skin_temp aren't routed here (they open the catalog).
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

    /// La línea bajo el héroe cuando todavía no hay veredicto que decir. FER-119 le quitó
    /// el parámetro `score`: el puntaje 0-100 murió con la banda, y su rama era inalcanzable.
    private func recoverySubtitle(calibrating: Int?) -> LocalizedStringKey {
        calibrating != nil ? "Calibrating your baseline" : "No reading yet"
    }

    private func sleepText(_ mins: Double) -> String { "\(Int(mins) / 60)h \(Int(mins) % 60)m" }

    private func intString(_ v: Double) -> String { StrandFormat.groupedInt(v) }

    private static func descriptor(_ key: String) -> MetricDescriptor? {
        MetricCatalog.all.first { $0.key == key }
    }

}

// MARK: - Liquid lente teñida (FER-100 — the Preparación hero's bespoke card)
//
// A tinted-lens card, purpose-built for this landing (not a general DS piece — a single call site).
// Radius `LiquidRadius.hoja` (the biggest of the five canonical radii — this is the one dominant
// element on the screen, Instrumento rule 1 carried into Liquid). Fill is a diagonal gradient of the
// verdict's own tone darkened via `LiquidColor.tonoCampo` (the SAME AA-safe darkening the detail
// screens' tinted field uses), OR `LiquidColor.papelGradient` when `tono` is nil — the apagado state
// (never a tinta gradient, never green without a verdict). One specular hairline dares it to read as
// glass, not flat color; the shadow glows the tone (`LiquidElevation.e2`) or sits quiet (`e1`) apagado.
private extension View {
    func liquidLenteTenida(tono: Color?) -> some View {
        modifier(LiquidLenteTenidaModifier(tono: tono))
    }
}

private struct LiquidLenteTenidaModifier: ViewModifier {
    let tono: Color?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiquidRadius.hoja, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.vertical, LiquidSpace.s400)
            .background(fondo)
            .overlay { especularSuperior }
            .overlay { shape.strokeBorder(LiquidColor.vidrioRealcePastilla, lineWidth: 1) }
            .clipShape(shape)
            .liquidShadow(sombra, silhouette: shape)
    }

    @ViewBuilder private var fondo: some View {
        if let tono {
            LinearGradient(colors: [tono, LiquidColor.tonoCampo(tono)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            LiquidColor.papelGradient
        }
    }

    /// El especular del canto superior: dice dónde empieza el material sin brillar (misma alfa de
    /// referencia que `LiquidCampoMetrica`, `LiquidCampo.alfaEspecularSuperior`).
    private var especularSuperior: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.white.opacity(LiquidCampo.alfaEspecularSuperior), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 40)
            Spacer(minLength: 0)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    private var sombra: [LiquidShadowLayer] {
        if let tono { return LiquidElevation.e2(tone: tono) }
        return LiquidElevation.e1
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

    // FER-985 — CASO CERRADO: el hotspot de type-check de este preview (~198 ms) es `AppModel.preview`
    // de abajo, y la causa es la expansión del macro @Observable sobre AppModel (~20 propiedades
    // rastreadas + ~14 sub-objetos): para resolver el miembro estático, el type-checker procesa el tipo
    // entero. NO lo vuelvas a investigar y NO hay arreglo barato — se midió con bisección (3 builds):
    //
    //   base (`let appModel = AppModel.preview`) ......... 5 avisos, máx 198 ms
    //   con tipo explícito (`let appModel: AppModel = …`) . 8 avisos, máx 291 ms  ← PEOR
    //   sin la referencia a AppModel ..................... 0 avisos              ← confirma la causa
    //
    // Quitarlo no es opción: CuerpoView declara `@Environment(AppModel.self) var model` sin opcional
    // (línea ~185), así que el preview compilaría pero reventaría al renderizar. El único arreglo real
    // sería adelgazar AppModel, y 17 vistas dependen de él — no se paga por ~198 ms de build en Debug.
    //
    // CUATRO hipótesis refutadas con evidencia, no las repitas: (1) la cadena de modificadores —izarlos
    // a `let` no movió el número—; (2) construir `AppModel()` vs la estática `AppModel.preview` —igual—;
    // (3) el bucle de datos de muestra de arriba —refutada: otros previews sin bucle costaban lo mismo—;
    // (4) anotar el tipo explícitamente —lo empeoró, ver tabla—.
    //
    // Nota: los otros tres previews que FER-985 listaba como caros (TodayView, OnboardingWizard,
    // IntervalTimerView) ya NO aparecen sobre el umbral de 100 ms; bajaron solos con FER-981/984.
    let appModel = AppModel.preview
    let health = HealthKitBridge(repo: repo, appleDeviceId: "preview-apple", noopDeviceId: "preview")
    return CuerpoView()
        .environmentObject(repo)
        .environment(appModel)
        .environmentObject(health)
        .frame(width: 390, height: 900)
}
#endif
#endif
