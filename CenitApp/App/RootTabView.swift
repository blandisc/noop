#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// iOS navigation shell — the «IA de 3 capas» tab shell (FER-182). Five tabs over the «Barra de
/// instrumento» (FER-163): **Hoy · Cuerpo · Coach · Entrenar · Ajustes**. Trends and the old "More"
/// drawer are gone; En vivo is no longer a tab (it opens from Today's "beat by beat" `fullScreenCover`).
///
/// Three of the tabs are interim hub-lists that reconnect screens which don't have a final home yet —
/// each sibling issue (Cuerpo / Coach / Entrenar / Ajustes) replaces its interim with the real layer:
///   • **Coach**    → Intelligence · Insights · Coach (seed of the unified Coach layer).
///   • **Entrenar** → Breathe · Intervals.
///   • **Ajustes**  → Settings + a temporary «Más» section listing the still-orphan screens
///     (Explore · Compare · Workouts · Apple Health · Data Sources · Automations · Support). Sueño /
///     Health / Stress now live in «Cuerpo». Nothing from the old shell becomes unreachable.
struct RootTabView: View {
    private enum Tab: Hashable { case today, body, coach, train, settings }

    /// Every screen reachable by pushing onto a hub tab's stack. Raw values match the `noop.nav.<key>`
    /// debug-navigation keys (`ScreenshotNav.swift`) so screenshot automation still reaches each one.
    private enum SecondaryScreen: String, Hashable {
        case library                              // Entrenar hub — exercise library (FER-346)
        case workoutHistory = "workouthistory"    // Entrenar hub — «Mis entrenamientos» (FER-504)
        case breathe, intervals, dieta            // Entrenar hub
        case weeklyPlan = "weeklyplan"            // Entrenar hub — weekly plan editor (FER-533)
        case misRutinas = "misrutinas"           // Entrenar hub — routine + folder management (FER-534)
        case restDay = "restday"                  // Entrenar hub — «Hoy descansas» (v3 · 2B, now a push, FER-718)
        case otherWays = "otherways"              // Entrenar hub — «Otra forma de entrenar» (v3 · 3e, now a push, FER-718)
        case routineToday                         // Entrenar hub — «Rutina de hoy» (DEBUG screenshot-nav)
        // Reachable via DEBUG screenshot-nav (pushed onto the Ajustes stack). Explore/Compare/Workouts
        // also still open from Cuerpo's footer; the rest open as sheets from the Ajustes root (FER-337).
        case explore, compare, workouts
        case applehealth, datasources, support
    }

    /// Whether Today is the active tab — published up to ContentView, which owns the color scheme
    /// (and with it the status bar): Today is light paper → dark status bar, the rest are dark.
    @Binding var isTodayActive: Bool

    /// App-level cross-tab navigation (FER-378). A screen can ask to jump tabs; we apply + clear it.
    @EnvironmentObject private var tabRouter: TabRouter

    /// The strength session lives here (FER-716): it presents as a full-screen cover (over the dock, no
    /// grabber) from ANY tab, and its floating pill hovers over the bar on all five tabs. Owned by
    /// AppModel so navigation never kills it — dismissing the cover only minimizes it (the pill re-opens).
    @Environment(AppModel.self) private var appModel

    /// The visible tab. Starts on Today, the launch screen.
    @State private var selection: Tab = .today
    /// Tabs whose content has been shown at least once. Only Today is built at launch; the one heavy
    /// lazy tab — Cuerpo (`CuerpoView` runs its own `.task` data load on appear) — is deferred until
    /// first selected, then kept in the set so switching back doesn't rebuild from scratch. The hub
    /// tabs (Coach/Entrenar/Ajustes) are plain lists whose destinations build on `NavigationLink` tap,
    /// so they stay eager (cheap). Avoids widening the launch gap — FER-31.
    @State private var visited: Set<Tab> = [.today]
    /// One type-erased path per hub. `NavigationPath` (not a homogeneous `[SecondaryScreen]`) because
    /// the Ajustes stack carries Explore, which pushes `MetricDescriptor` values onto it — a typed
    /// path crossing a second value type crashed SwiftUI (FER-171).
    @State private var trainStack = NavigationPath()
    @State private var settingsStack = NavigationPath()
    /// Bridges the workout-history list and the session detail (siblings in `trainStack`) so a delete or
    /// edit in the detail surfaces «Undo» / a reload on the list (FER-556).
    @StateObject private var workoutHistory = WorkoutHistoryCoordinator()
    /// Measured height of the «Barra de instrumento» (its button row, above the
    /// home-indicator bleed). Each tab reserves exactly this much at its bottom so
    /// the last component clears the bar — see `barReservation`. Starts 0 and is
    /// filled on first layout via `BarHeightKey`.
    @State private var barHeight: CGFloat = 0
    /// El ✕ del pill pide confirmación aquí (pantalla completa), no en el frame del pill.
    @State private var confirmDiscardSession = false

    // FER-981: `body` kept thin so type-check stays under the long-function budget. Tab shell,
    // heavy tabs, and the modifier chain each type-check in their own scope.
    var body: some View {
        rootChrome(rootTabs)
    }

    /// Five-tab shell. Extracted from `body` (FER-981) so TabView + tags type-check apart from chrome.
    @ViewBuilder
    private var rootTabs: some View {
        TabView(selection: $selection) {
            lazyTab(.today, "Today", "circle.hexagongrid.fill") { TodayView() }
            lazyTab(.body,  "Tendencias", "chart.xyaxis.line") { CuerpoView() }

            // FER-992: Patrones off the dock (code + Tab.coach + BucleView stay; re-enable by restoring
            // the lazyTab below and the barItems row). Was: one «Instrumento diurno» screen fed by
            // InsightEngine (FER-290/292), light tab (warm paper).
            // lazyTab(.coach, "Patrones", "sparkles") { BucleView() }

            trainTab
            settingsTab
        }
    }

    // Entrenar — the redesigned light «Instrumento» hub (FER-343 + FER-346): the «Hoy» card +
    // recovery band, «Mis rutinas» (build / edit), the exercise library, and the Respira /
    // Intervalos / Dieta / En-vivo tools (FER-39 epic). Like Cuerpo/Ajustes the visible hub
    // navigates by pushing onto this tab's NavigationStack; that stack also lets DEBUG
    // screenshot-nav reach «Rutina de hoy» / Biblioteca / Respira / Intervalos / Dieta. Warm
    // paper throughout, so there's no light-tab → dark-screen status-bar bridge to manage.
    @ViewBuilder
    private var trainTab: some View {
        NavigationStack(path: $trainStack) {
            EntrenarView(
                openRoutine: { id in trainStack.append(RoutineEditorRoute.today(routineId: id)) },
                openBreathe: { trainStack.append(SecondaryScreen.breathe) },
                openIntervals: { trainStack.append(SecondaryScreen.intervals) },
                // FER-992: Dieta UI entry off — SecondaryScreen.dieta + DietCaptureView stay.
                // Re-enable: openDiet: { trainStack.append(SecondaryScreen.dieta) },
                openDiet: { },
                openHistory: { trainStack.append(SecondaryScreen.workoutHistory) },
                openWeeklyPlan: { trainStack.append(SecondaryScreen.weeklyPlan) },
                openRoutines: { trainStack.append(SecondaryScreen.weeklyPlan) },
                openRestDay: { trainStack.append(SecondaryScreen.restDay) },
                openOtherWays: { trainStack.append(SecondaryScreen.otherWays) },
                openWorkoutSession: { trainStack.append($0) }
            )
            .barReservation(barHeight)
            .navigationDestination(for: SecondaryScreen.self) { screen in
                trainChrome(secondaryDestination(screen))
            }
            .navigationDestination(for: RoutineEditorRoute.self) { route in
                // «Rutina» (FER-839): ONE prescription editor for every origin (today / plan day /
                // Mis rutinas). It draws its own back/cancel header + pinned CTA, so the native nav
                // bar is hidden (trainChrome still paints paper + reserves the bar).
                trainChrome(RoutineEditorScreen(origin: route))
                    .toolbar(.hidden, for: .navigationBar)
            }
            .navigationDestination(for: WorkoutSessionRoute.self) { route in
                trainChrome(WorkoutSessionDetailScreen(
                    route: route,
                    openRoutine: { id in trainStack.append(RoutineEditorRoute.routine(routineId: id)) }))
            }
            // Decisión Fer (2026-07-16): «Ver mapa» abre el MAPA muscular real (las siluetas de
            // Tendencias) — el mismo MuscleMapScreen, empujado; las barras vs banda viven como
            // pantalla hija enlazada desde el mapa.
            .navigationDestination(for: MuscleVolumeRoute.self) { _ in
                trainChrome(MuscleMapScreen(theme: .base, showsVolumeLink: true))
            }
            .navigationDestination(for: MuscleVolumeBarsRoute.self) { _ in
                trainChrome(MuscleVolumeScreen())
            }
            .navigationDestination(for: SavedTicketsRoute.self) { _ in
                trainChrome(SavedTicketsScreen())
            }
        }
        .environmentObject(workoutHistory)
        .toolbar(.hidden, for: .tabBar)
        .tabItem { Label("Train", systemImage: "figure.strengthtraining.functional") }
        .tag(Tab.train)
    }

    // Ajustes — the redesigned light «Instrumento» Settings root (FER-337). Replaces the old
    // list → SettingsView indirection AND the «Más» drawer: the tab now opens directly here.
    // The visible UI navigates by SHEET (AjustesView), like Cuerpo; the NavigationStack here
    // exists only so DEBUG screenshot-nav can still push a secondary screen — its path only
    // ever carries `SecondaryScreen` (one value type), so there's no FER-171 mixed-path crash.
    // Explore · Compare · Workouts are gone from Ajustes (they open from Cuerpo now).
    @ViewBuilder
    private var settingsTab: some View {
        NavigationStack(path: $settingsStack) {
            AjustesView()
                .barReservation(barHeight)
                .navigationDestination(for: SecondaryScreen.self) { screen in
                    secondaryDestination(screen)
                        .background(InstrumentoTheme.base.paper.ignoresSafeArea())
                        .barReservation(barHeight)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(InstrumentoTheme.base.paper, for: .navigationBar)
                }
        }
        .toolbar(.hidden, for: .tabBar)
        .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
        .tag(Tab.settings)
    }

    /// Overlays, covers, and lifecycle observers on the tab shell. Composed from three
    /// smaller modifier helpers so no single chain type-checks over the long-function budget (FER-981).
    private func rootChrome<Content: View>(_ content: Content) -> some View {
        rootChromeLifecycle(rootChromeCovers(rootChromeOverlays(content)))
    }

    /// Tint + floating instrument bar + active-session pill (FER-163 / FER-716).
    ///
    /// FER-985 — CASO CERRADO en ~201 ms de type-check, a propósito. Se intentó izar la condición del
    /// pill (`appModel.strengthSession != nil && !appModel.strengthSheetPresented`) a un `let Bool` con
    /// tipo explícito fuera del `@ViewBuilder`. Medido, el costo NO se fue: se MOVIÓ y quedó peor.
    ///
    ///   antes .... método 201 ms · condición (el `if` de abajo) 196 ms
    ///   después .. método 291 ms · `.tint` 274 ms · isLightTab 103 ms   ← peor, y dos hotspots nuevos
    ///
    /// Es el MISMO desenlace que el intento previo de FER-981 (mover la cadena a una sola función
    /// genérica: body 284 → rootChrome 309). Partir o izar piezas de esta cadena redistribuye el costo
    /// entre las expresiones vecinas en vez de bajarlo, porque el costo real no está en la forma de la
    /// cadena: son accesos al tipo expandido por el macro `@Observable` de `AppModel` — la misma causa
    /// confirmada por bisección en el `#Preview` de `CuerpoView`. El único arreglo de fondo sería
    /// adelgazar `AppModel` (17 vistas dependen de él), y no se paga por ~200 ms de build en Debug.
    ///
    /// NO lo vuelvas a intentar sin medir antes y después: dos intentos ya salieron peor.
    private func rootChromeOverlays<Content: View>(_ content: Content) -> some View {
        content
        // `.tint` no longer paints the tab bar (it's hidden below; the custom
        // `InstrumentTabBar` sets its own ink), but it still tints links/controls
        // inside the screens — kept for those.
        .tint(StrandPalette.accent)
        // The «Barra de instrumento» (FER-163): the native bar is hidden per page
        // (see `lazyTab` and the per-hub NavigationStacks) and this custom bar takes its place.
        //
        // It is mounted as an `overlay` (it floats, pinned to the bottom) rather
        // than via `safeAreaInset` on the `TabView`: a bottom safe-area inset placed
        // on a `TabView` whose native bar is hidden draws the bar but does NOT reach
        // the safe area of each page's `ScrollView`, so the last component scrolled
        // under the bar. Instead each tab reserves the bar's measured height at the
        // CONTENT level (`barReservation`), where the inset does propagate to scroll
        // views. The bar reports its height via `BarHeightKey`.
        //
        // `.instrumentoTheme(.base)` drives `\.instrumentoTheme` so that — under Hoy —
        // the bar reads the warm day paper exactly like TodayView; under the dark screens
        // it ignores the theme and uses `StrandPalette`. (Color scheme itself is owned
        // by ContentView via `isTodayActive` — FER-160; the bar uses explicit colors
        // either way. FER-398 retired the by-the-hour tint.)
        .overlay(alignment: .bottom) {
            InstrumentTabBar(items: barItems, selection: $selection, isLight: isLightTab(selection))
                .instrumentoTheme(.base)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: BarHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        // The active-session pill (FER-716): floats over the dock on ALL five tabs while a session is
        // running and the full-screen cover is minimized. Tapping it re-opens the session.
        .overlay(alignment: .bottom) {
            if appModel.strengthSession != nil && !appModel.strengthSheetPresented {
                ActiveSessionPillHost(model: appModel, confirmDiscard: $confirmDiscardSession)
                    .padding(.horizontal, CenitMetrics.screenPadding)
                    .padding(.bottom, barHeight + CenitMetrics.space2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Confirm discard, session animations, and the guided-strength fullScreenCover (FER-347/716).
    /// Own `@Bindable` for FER-984 (`$appModel.strengthSheetPresented`).
    private func rootChromeCovers<Content: View>(_ content: Content) -> some View {
        // FER-984: `appModel` es `@Environment` (sin `$` publishers); este `@Bindable` local habilita el
        // binding `$appModel.strengthSheetPresented` del fullScreenCover de la sesión de fuerza (abajo).
        @Bindable var appModel = appModel
        return content
        // El ConfirmCard del ✕ del pill vive AQUÍ (pantalla completa): colgado del host del pill se
        // anclaba a su frame angosto — velo recortado y esquinas rotas (bug Fer 2026-07-16).
        .instrumentoConfirm(
            isPresented: $confirmDiscardSession,
            title: String(localized: "Discard this session?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            message: String(localized: "Its logged sets won't be saved."),
            actions: [
                .init(String(localized: "Keep training"), role: .primary),
                .init(String(localized: "Discard session"), role: .destructive) {
                    appModel.endStrengthSession(save: false)
                }
            ]
        )
        .animation(StrandMotion.gentle, value: appModel.strengthSheetPresented)
        .animation(StrandMotion.gentle, value: appModel.strengthSession == nil)
        // The guided strength session (FER-347/716): a full-screen cover so it covers the dock with no
        // grabber, opened from any tab. The session lives in AppModel, so dismissing the cover only hides
        // it (the pill re-opens); the summary is ended by `closeStrengthSummary` on its «Listo».
        .fullScreenCover(isPresented: $appModel.strengthSheetPresented, onDismiss: {
            if appModel.strengthSession?.summary != nil { appModel.closeStrengthSummary() }
        }) {
            if let session = appModel.strengthSession {
                LiveStrengthSheet(session: session, theme: .base)
                    .environment(appModel)
                    .environmentObject(tabRouter)
                    .preferredColorScheme(.light)
            }
        }
    }

    /// Preference, tab selection, cross-tab routing, watch receipt, and DEBUG nav observers.
    private func rootChromeLifecycle<Content: View>(_ content: Content) -> some View {
        content
        .onPreferenceChange(BarHeightKey.self) { barHeight = $0 }
        // Color scheme lo decide ContentView (cercano a la raíz) según `isTodayActive`; aquí solo lo
        // mantenemos sincronizado con la pestaña visible. Solo Hoy es papel claro «Instrumento»; las
        // otras cuatro pestañas son el panel oscuro. (En vivo es ahora un cover sobre Hoy, no pestaña.)
        .onChange(of: selection) { _, newValue in
            visited.insert(newValue)
            isTodayActive = isLightTab(newValue)
        }
        .onAppear { isTodayActive = isLightTab(selection) }
        // Cross-tab navigation requests (FER-378 «Explóralo en el Coach»). One-shot: apply + clear.
        .onReceive(tabRouter.$requested.compactMap { $0 }) { req in
            switch req {
            case .today:    selection = .today
            case .body:     selection = .body
            // FER-999: «coach» ya no se monta como pestaña (FER-992) — sin `lazyTab` en el TabView, asignar
            // `selection = .coach` dejaría a SwiftUI en un estado sin tag (pestaña en blanco), igual que en la
            // ruta DEBUG de abajo. La petición se ignora. Re-enable con la pestaña: case .coach: selection = .coach
            case .coach:    break
            case .train:    selection = .train
            case .settings: selection = .settings
            }
            tabRouter.requested = nil
        }
        // FER-810: «Ver recibo en iPhone» from the Apple Watch → switch to Entrenar and push the saved
        // workout's history detail. One-shot: apply + clear.
        // FER-984: `@Observable` no expone `$` publishers; se reacciona al cambio de la propiedad con
        // `onChange` en vez del `onReceive` del publisher. `initial: true` reemplaza la emisión inmediata
        // del publisher de Combine al suscribirse — así una ruta YA presente al montar (cold-launch desde
        // el watch, FER-810) también se atiende. One-shot: aplica al primer valor no-nil y limpia.
        .onChange(of: appModel.pendingReceiptRoute, initial: true) { _, route in
            guard let route else { return }
            selection = .train
            trainStack.append(route)
            appModel.pendingReceiptRoute = nil
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .noopDebugNav)) { note in
            guard let screen = note.object as? String else { return }
            // Tab-level keys land on a clean hub root. "trends" → Cuerpo, "more"/"ajustes" → Ajustes.
            let tab: Tab? = switch screen {
            case "today":              .today
            // Sueño lost its own screen — it now lives as a row inside «Cuerpo» (FER-186/212), so the
            // screenshot key lands on the Body tab (the screen that owns it) instead of a standalone push.
            case "body", "trends", "sleep": .body
            // FER-992: «coach» sale del ruteo de screenshots — sin `lazyTab` en el TabView, asignar
            // `selection = .coach` dejaba a SwiftUI en un estado sin tag (pestaña en blanco). Apagado,
            // no roto. Re-enable con la pestaña: case "coach": .coach
            case "train", "entrenar":  .train
            case "settings", "ajustes", "more": .settings
            default:                   nil
            }
            if let tab {
                selection = tab
                trainStack = NavigationPath(); settingsStack = NavigationPath()
                return
            }
            // Secondary screens: select the owning hub and push the screen onto its stack.
            if let sec = SecondaryScreen(rawValue: screen) {
                let owner = hub(for: sec)
                selection = owner
                var path = NavigationPath(); path.append(sec)
                switch owner {
                case .train:    trainStack = path
                default:        settingsStack = path
                }
            }
        }
        #endif
        // NOTE: the launch refresh is owned by AppModel.init (one source of truth). A second
        // `.task { repo.refresh() }` here ran a full-history load concurrently with that one at
        // launch — double DB work + an extra refreshSeq bump that re-fired TodayView.loadAll.
    }

    /// Which tabs render in the light «Instrumento diurno» paper (drives the status-bar color scheme
    /// via `isTodayActive` and the instrument bar's `isLight`). Hoy and Cuerpo — the «historia» landing
    /// is warm paper too (FER-186), color only on the datum; every other tab is the dark instrument
    /// panel. (En vivo's light paper lives in a cover over Hoy, not a tab.)
    private func isLightTab(_ tab: Tab) -> Bool { tab == .today || tab == .body || tab == .coach || tab == .train || tab == .settings }

    /// The hub tab that owns a given secondary screen (for debug navigation).
    ///
    /// Exhaustive on purpose — no `default`. A screen routed to the wrong hub lands on a stack that
    /// doesn't inject that hub's environment objects, and SwiftUI answers a missing `@EnvironmentObject`
    /// with a `fatalError`, not a fallback: `.workoutHistory` used to fall through `default` to Ajustes,
    /// whose destination lacks the `.environmentObject(workoutHistory)` the Entrenar stack applies, so
    /// screenshot-nav to it crashed the app. Listing every case makes that a compile error instead.
    private func hub(for screen: SecondaryScreen) -> Tab {
        switch screen {
        case .library, .workoutHistory, .breathe, .intervals, .dieta, .weeklyPlan, .misRutinas,
             .restDay, .otherWays, .routineToday:
            return .train
        case .explore, .compare, .workouts, .applehealth, .datasources, .support:
            return .settings
        }
    }

    /// A tab whose real content is built only once its tag has been visited (kept alive afterward),
    /// so non-selected screens don't construct their body or fire their launch `.task` at startup.
    @ViewBuilder
    private func lazyTab<V: View>(_ tag: Tab, _ title: LocalizedStringKey, _ icon: String,
                                  @ViewBuilder _ content: @escaping () -> V) -> some View {
        Group {
            if visited.contains(tag) {
                content()
            } else {
                Color.clear   // placeholder until first selected; never visible (selecting builds it)
            }
        }
        .background(InstrumentoTheme.base.paper.ignoresSafeArea())
        // Reserve the floating bar's height at the content level so the page's
        // ScrollView stops above the bar (the inset reaches scroll views here; it
        // would not from the TabView — see `body`).
        .barReservation(barHeight)
        // Hide the native tab bar everywhere; the custom `InstrumentTabBar` (the
        // floating overlay on the TabView) is the visible bar. `tabItem` stays so
        // TabView keeps its tag/selection wiring — its label just never renders.
        .toolbar(.hidden, for: .tabBar)
        .tabItem { Label(title, systemImage: icon) }
        .tag(tag)
    }

    /// Chrome for a screen pushed onto the Entrenar stack: warm-paper background, reserved bar height,
    /// and a light navigation bar (the whole tab is «Instrumento» paper — FER-343).
    @ViewBuilder
    private func trainChrome<V: View>(_ screen: V) -> some View {
        screen
            .background(InstrumentoTheme.base.paper.ignoresSafeArea())
            .barReservation(barHeight)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(InstrumentoTheme.base.paper, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }

    // MARK: - Custom bar (FER-163)

    /// The dock tabs as drawn by `InstrumentTabBar`. Thin-stroke set: the 24h dial for Hoy (the bar's
    /// signature mark), line glyphs for the rest. (Hidden `tabItem` icons use the filled variants from
    /// the issue spec; only this custom bar is visible.) FER-992: Patrones removed — four tabs.
    private var barItems: [InstrumentTabBar<Tab>.Item] {
        [
            .init(.today,    "Today",   .dial),
            .init(.body,     "Tendencias", .curveNodes),
            // FER-992: Patrones off — re-enable: .init(.coach, "Patrones", .linkedCircles),
            .init(.train,    "Train",   .system("figure.strengthtraining.functional")),
            .init(.settings, "Ajustes", .system("gearshape")),
        ]
    }

    @ViewBuilder
    private func secondaryDestination(_ screen: SecondaryScreen) -> some View {
        switch screen {
        case .library:      ExerciseLibraryScreen()
        case .workoutHistory: WorkoutHistoryScreen()
        case .breathe:      BreathingView()
        case .intervals:    IntervalTimerView()
        // FER-890: «Tu Plan» is one unified screen (week + routines). Both routes resolve to it — the old
        // `.misRutinas` key stays so DEBUG screenshot-nav still reaches the routines home (now unified).
        case .weeklyPlan, .misRutinas:
            WeeklyPlanEditorView(
                openRoutine: { id in trainStack.append(RoutineEditorRoute.routine(routineId: id)) },
                openLibrary: { trainStack.append(SecondaryScreen.library) },
                openDay: { wd in trainStack.append(RoutineEditorRoute.planDay(weekday: wd)) })
        case .restDay:      RestDayScreen(
                                openIntervals: { trainStack.append(SecondaryScreen.intervals) },
                                openBreathe: { trainStack.append(SecondaryScreen.breathe) },
                                openRoutines: { trainStack.append(SecondaryScreen.misRutinas) })
        case .otherWays:    OtherWaysScreen(
                                openIntervals: { trainStack.append(SecondaryScreen.intervals) },
                                openBreathe: { trainStack.append(SecondaryScreen.breathe) })
        case .routineToday: RoutineEditorScreen(origin: .today(routineId: nil))
        case .dieta:        DietCaptureView()
        case .explore:      MetricExplorerView()
        case .compare:      CompareView()
        case .workouts:     WorkoutsView()
        case .applehealth:  AppleHealthView()
        case .datasources:  DataSourcesView()
        case .support:      SupportView()
        }
    }
}

/// The «Barra de instrumento»'s measured height, bubbled from the floating overlay
/// bar up to `RootTabView` so each tab can reserve exactly that much. `max` keeps
/// the real (non-zero) value if SwiftUI momentarily reports a 0-height pass.
private struct BarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    /// Reserve `height` points of clear space at the bottom safe area, so a page's
    /// scroll content clears the floating tab bar. Applied at the content level
    /// (where the inset reaches scroll views), never on the `TabView` — see
    /// `RootTabView.body`.
    func barReservation(_ height: CGFloat) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: height)
        }
    }
}

/// Hosts the `SessionPill` with a live-ticking clock (FER-716): a `TimelineView` recomputes the
/// elapsed time each second, and the BPM is the Apple Watch live mirror (`model.watchBpm` — the same
/// source as the session header; nil = no watch reading, so the pill drops its ♥ segment instead
/// of freezing a stale sample). Tapping re-opens the session. The routine hue is the effort ember
/// (`dataStrain`) — the same hue the session screen and the approved previews use.
private struct ActiveSessionPillHost: View {
    @Bindable var model: AppModel
    /// Decisión Fer (2026-07-16): el ✕ del pill DESCARTA — destructivo, así que siempre confirma.
    /// El ConfirmCard vive en el RootTabView (pantalla completa); aquí solo se dispara.
    @Binding var confirmDiscard: Bool
    var body: some View {
        if let session = model.strengthSession {
            let theme = InstrumentoTheme.base
            TimelineView(.periodic(from: .now, by: 1)) { context in
                // FER-952: pause-aware clock (the raw now−start kept ticking while paused).
                let elapsed = SessionClock.format(session.elapsedSeconds(now: context.date))
                let total = session.runs.filter { !$0.skipped }.reduce(0) { $0 + $1.sets.count }
                SessionPill(
                    routineName: session.routineName,
                    elapsed: elapsed,
                    bpm: model.watchBpm,
                    detail: total > 0 ? String(localized: "set \(min(session.doneCount + 1, total))/\(total)") : nil,
                    paused: session.paused,
                    hue: theme.dataStrain,
                    theme: theme,
                    accessibilityLabel: pillLabel(session.routineName, elapsed, model.watchBpm),
                    accessibilityHint: Text("Returns to the session"),
                    action: { model.resumeStrengthSession() },
                    onDiscard: { confirmDiscard = true },
                    discardAccessibilityLabel: Text("Discard session")
                )
            }
        }
    }

    /// VoiceOver label for the pill — localized here because the StrandDesign package has no catalog.
    private func pillLabel(_ name: String, _ elapsed: String, _ bpm: Int?) -> Text {
        if let bpm { return Text("Active session: \(name), \(elapsed), heart rate \(bpm)") }
        return Text("Active session: \(name), \(elapsed)")
    }
}
#endif
