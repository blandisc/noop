#if os(iOS)
import SwiftUI
import CenitDesign
import StrandAnalytics
import CenitStore   // FER-202: `WorkoutRow` — destino de detalle de actividad en el trainStack (fusión de historiales)
import Inject   // recarga en caliente (dev-only, inerte en Release)

/// iOS navigation shell — the «IA de 3 capas» tab shell (FER-182). Four tabs over the «Barra de
/// instrumento» (FER-163): **Hoy · Tendencias · Entrenar · Ajustes**. Patrones (Coach) was archived
/// in FER-240; En vivo is no longer a tab (it opens from Today's "beat by beat" `fullScreenCover`).
///
/// Hub tabs reconnect screens which don't have a final home yet:
///   • **Entrenar** → Breathe · Intervals (+ strength hub).
///   • **Ajustes**  → Settings + a temporary «Más» section listing the still-orphan screens
///     (Explore · Compare · Workouts · Apple Health · Data Sources · Automations · Support). Sueño /
///     Health / Stress now live in «Tendencias» (Cuerpo). Nothing from the old shell becomes unreachable.
struct RootTabView: View {
    // FER-240: `.coach` (Patrones) removed with the screen.
    private enum Tab: Hashable { case today, body, train, settings }

    /// Every screen reachable by pushing onto a hub tab's stack. Raw values match the `noop.nav.<key>`
    /// debug-navigation keys (`ScreenshotNav.swift`) so screenshot automation still reaches each one.
    private enum SecondaryScreen: String, Hashable {
        case library                              // Entrenar hub — exercise library (FER-346)
        case workoutHistory = "workouthistory"    // Entrenar hub — «Mis entrenamientos» (FER-504)
        // FER-92 / FER-239: `dieta` retirada del enum y la pantalla huérfana archivada.
        case breathe, intervals                   // Entrenar hub
        case weeklyPlan = "weeklyplan"            // Entrenar hub — weekly plan editor (FER-533)
        case misRutinas = "misrutinas"           // Entrenar hub — routine + folder management (FER-534)
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
    /// tabs (Entrenar/Ajustes) are plain lists whose destinations build on `NavigationLink` tap,
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
    // Inject: hooks en el struct NO privado del archivo (regla PR#1036) para iterar el
    // dock Liquid en vivo durante las sesiones /inject.
    @ObserveInjection private var inject

    var body: some View {
        rootChrome(rootTabs)
            .enableInjection()
    }

    /// Five-tab shell. Extracted from `body` (FER-981) so TabView + tags type-check apart from chrome.
    @ViewBuilder
    private var rootTabs: some View {
        TabView(selection: $selection) {
            lazyTab(.today, "Today", "circle.hexagongrid.fill") { TodayView() }
            lazyTab(.body,  "Tendencias", "chart.xyaxis.line") { CuerpoView() }
            // FER-240: Patrones (former Coach tab) archived — screen deleted, not just off-dock.
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
                openHistory: { trainStack.append(SecondaryScreen.workoutHistory) },
                openWeeklyPlan: { trainStack.append(SecondaryScreen.weeklyPlan) },
                openRoutines: { trainStack.append(SecondaryScreen.weeklyPlan) },
                openWorkoutSession: { trainStack.append($0) },
                openMuscleMap: { trainStack.append(MuscleVolumeRoute()) }
            )
            .barReservation(barHeight)
            .navigationDestination(for: SecondaryScreen.self) { screen in
                trainChrome(secondaryDestination(screen))
            }
            .navigationDestination(for: RoutineEditorRoute.self) { route in
                // «La Hoja» (FER-166, F1): crear = editar, la misma hoja en frío para todo origen
                // (hoy / día del plan / Mis rutinas). Sustituye a `RoutineEditorScreen` (FER-839).
                // Draws its own back/cancel header + pinned CTA, so the native nav bar is hidden.
                trainChrome(RoutineSheet(origin: route, mode: .editing))
                    .toolbar(.hidden, for: .navigationBar)
            }
            .navigationDestination(for: WorkoutSessionRoute.self) { route in
                trainChrome(WorkoutSessionDetailScreen(
                    route: route,
                    openRoutine: { id in trainStack.append(RoutineEditorRoute.routine(routineId: id)) }))
            }
            // Decisión Fer (2026-07-16): «Ver mapa» abre «Tu cuerpo» real (las siluetas de
            // Tendencias), empujado — FER-91 · E10 fusionó el mapa y el volumen en una sola
            // pantalla, así que las dos rutas viejas convergen aquí.
            .navigationDestination(for: MuscleVolumeRoute.self) { _ in
                trainChrome(TrainingBodyScreen())
            }
            .navigationDestination(for: SavedTicketsRoute.self) { _ in
                trainChrome(SavedTicketsScreen())
            }
            // FER-202 (fusión «Historial unificado»): el detalle de una fila de ACTIVIDAD (cardio/manual,
            // `WorkoutRow`) — `WorkoutHistoryScreen.openCardio` lo empuja aquí. Antes lo registraba
            // `WorkoutsView` (retirada); ahora vive en el trainStack como una ruta más (path heterogéneo,
            // no un stack anidado: sin riesgo FER-171).
            .navigationDestination(for: WorkoutRow.self) { row in
                // `onChange` bumpea el coordinador para que la lista unificada se recargue al volver de
                // una edición/borrado (paridad con lo que hacía `WorkoutsView.reload`).
                trainChrome(WorkoutDetailScreen(row: row,
                                                onChange: { workoutHistory.bumpReload() }))
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
                        .pantallaFondo()
                        .barReservation(barHeight)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(LiquidColor.papelAlto, for: .navigationBar)
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
        .tint(LiquidColor.verdePrimario)
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
        // Color scheme itself is owned by ContentView via `isTodayActive` (FER-160); the
        // Liquid dock paints its own glass. FER-398 retired the by-the-hour tint.
        .overlay(alignment: .bottom) {
            // /inject 2026-07-22 (decisión del dueño): el dock global pasa al lente Liquid
            // Glass — vidrio flotante con los 4 glifos del sistema y el punto verde activo.
            // Los rótulos salen del catálogo del APP (FER-112): vivían hardcodeados en español
            // dentro de CenitDesign, que no tiene catálogo, así que la barra de TODAS las
            // pantallas se veía en español con el teléfono en inglés.
            LiquidTabBar(active: liquidTab(for: selection),
                         rotulos: .cenit) { selection = appTab(for: $0) }
                .padding(.horizontal, LiquidSpace.dockSide)
                .padding(.bottom, LiquidSpace.dockBottom)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: BarHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        // The active-session pill (FER-716): floats over the dock on the OTHER four tabs while a
        // session is running and the full-screen cover is minimized. Tapping it re-opens the session.
        //
        // FER-132 DEROGADA (FER-167 · F2, orden del épico): el héroe de sesión viva del hub se
        // retiró — Entrenar ahora es mosaico v18 + píldora, como los otros 4 tabs. La píldora vive
        // en TODOS los tabs, incluido Entrenar.
        .overlay(alignment: .bottom) {
            if appModel.strengthSession != nil && !appModel.strengthSheetPresented {
                ActiveSessionPillHost(model: appModel, confirmDiscard: $confirmDiscardSession)
                    .padding(.horizontal, LiquidSpace.s600)
                    .padding(.bottom, barHeight + LiquidSpace.s200)
                    .transition(LiquidMotion.risingFadeTransition)
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
        // Handoff V10 (FER-139): título + mensaje alineados al prototipo, con el conteo REAL de
        // series de hoy y su plural correcto. Los rótulos de acción se quedan en «Seguir
        // entrenando»/«Descartar sesión» — no «Cancelar»/«Descartar» a secas — porque `ConfirmCard`
        // (CenitDesign, FER-836) documenta como ley que esos dos genéricos no existen en este
        // sistema; cada acción nombra lo que hace.
        .liquidConfirm(
            isPresented: $confirmDiscardSession,
            title: String(localized: "Discard the workout?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            message: String(localized: "You'll lose \(appModel.strengthSession?.doneCount ?? 0) logged set(s) today. This can't be undone."),
            actions: [
                .init(String(localized: "Keep training"), role: .primary),
                .init(String(localized: "Discard session"), role: .destructive) {
                    appModel.endStrengthSession(save: false)
                }
            ]
        )
        .animation(LiquidMotion.suave, value: appModel.strengthSheetPresented)
        .animation(LiquidMotion.suave, value: appModel.strengthSession == nil)
        // The guided strength session (FER-347/716): a full-screen cover so it covers the dock with no
        // grabber, opened from any tab. The session lives in AppModel, so dismissing the cover only hides
        // it (the pill re-opens); the summary is ended by `closeStrengthSummary` on its «Listo».
        .fullScreenCover(isPresented: $appModel.strengthSheetPresented, onDismiss: {
            if appModel.strengthSession?.summary != nil { appModel.closeStrengthSummary() }
        }) {
            // FER-167 (F2): La Hoja viva sustituye a `LiveStrengthSheet` como superficie montada —
            // ese tipo sigue vivo (modo Foco + acta), compuesto desde `HojaSesionViva`.
            if appModel.strengthSession != nil {
                RoutineSheet(origin: .today(routineId: appModel.strengthSession?.routineId), mode: .live)
                    .environment(appModel)
                    .environmentObject(tabRouter)
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
        // Cross-tab navigation requests (FER-378). One-shot: apply + clear.
        .onReceive(tabRouter.$requested.compactMap { $0 }) { req in
            switch req {
            case .today:    selection = .today
            case .body:     selection = .body
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
        // FER-186: strength summary «Ver mapa» → Entrenar + push `MuscleVolumeRoute` (same stack as
        // the hub MAPA door). Mirrors `pendingReceiptRoute`: apply + clear on the train stack owner.
        .onChange(of: tabRouter.openMuscleMapInTrain, initial: true) { _, open in
            guard open else { return }
            selection = .train
            trainStack.append(MuscleVolumeRoute())
            tabRouter.openMuscleMapInTrain = false
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
            // FER-240: «coach» / Patrones archived — key ignored (falls through to nil via default).
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

    /// Tabs con esquema claro Liquid Glass · El Eje (barra de estado oscura vía `isTodayActive` /
    /// `isLight`): Hoy, Cuerpo, Entrenar y Ajustes. El resto del chrome legacy sigue oscuro.
    private func isLightTab(_ tab: Tab) -> Bool { tab == .today || tab == .body || tab == .train || tab == .settings }

    /// The hub tab that owns a given secondary screen (for debug navigation).
    ///
    /// Exhaustive on purpose — no `default`. A screen routed to the wrong hub lands on a stack that
    /// doesn't inject that hub's environment objects, and SwiftUI answers a missing `@EnvironmentObject`
    /// with a `fatalError`, not a fallback: `.workoutHistory` used to fall through `default` to Ajustes,
    /// whose destination lacks the `.environmentObject(workoutHistory)` the Entrenar stack applies, so
    /// screenshot-nav to it crashed the app. Listing every case makes that a compile error instead.
    private func hub(for screen: SecondaryScreen) -> Tab {
        switch screen {
        case .library, .workoutHistory, .breathe, .intervals, .weeklyPlan, .misRutinas,
             .routineToday:
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
        .pantallaFondo()
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
            .pantallaFondo()
            .barReservation(barHeight)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LiquidColor.papelAlto, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }

    // MARK: - Custom bar (FER-163)

    /// The dock tabs as drawn by `InstrumentTabBar`. Thin-stroke set: the 24h dial for Hoy (the bar's
    /// signature mark), line glyphs for the rest. (Hidden `tabItem` icons use the filled variants from
    /// the issue spec; only this custom bar is visible.) Four tabs (FER-992 / FER-240).
    private func liquidTab(for tab: Tab) -> LiquidTab {
        switch tab {
        case .today: return .hoy
        case .body: return .tendencias
        case .train: return .entrenar
        case .settings: return .ajustes
        }
    }

    private func appTab(for liquid: LiquidTab) -> Tab {
        switch liquid {
        case .hoy: return .today
        case .tendencias: return .body
        case .entrenar: return .train
        case .ajustes: return .settings
        }
    }

    private var barItems: [InstrumentTabBar<Tab>.Item] {
        [
            .init(.today,    "Today",   .dial),
            .init(.body,     "Tendencias", .curveNodes),
            // FER-240: Patrones archived — no dock row.
            .init(.train,    "Train",   .system("figure.strengthtraining.functional")),
            .init(.settings, "Ajustes", .system("gearshape")),
        ]
    }

    @ViewBuilder
    private func secondaryDestination(_ screen: SecondaryScreen) -> some View {
        switch screen {
        case .library:      ExerciseLibraryScreen()
        // FER-90: el toque de un día del calendario empuja SU sesión. El agente cableó esto en
        // `AppMap.swift` (el arnés de desarrollo) y no aquí, que es la navegación real: en la app
        // el día se habría podido tocar y no habría pasado nada. `WorkoutSessionRoute` ya tiene su
        // `navigationDestination` registrado arriba, así que basta empujarla a la pila.
        // FER-202: la puerta de Entrenar abre el «Historial unificado» filtrado a Fuerza (la bitácora
        // rica); una fila de actividad de la línea mixta empuja su detalle Apple (`openCardio`).
        case .workoutHistory: WorkoutHistoryScreen(
            initialFilter: .strength,
            openWorkoutSession: { trainStack.append($0) },
            openCardio: { trainStack.append($0) })
        case .breathe:      BreathingView()
        case .intervals:    IntervalTimerView()
        // FER-890: «Tu Plan» is one unified screen (week + routines). Both routes resolve to it — the old
        // `.misRutinas` key stays so DEBUG screenshot-nav still reaches the routines home (now unified).
        case .weeklyPlan, .misRutinas:
            WeeklyPlanEditorView(
                openRoutine: { id in trainStack.append(RoutineEditorRoute.routine(routineId: id)) },
                openLibrary: { trainStack.append(SecondaryScreen.library) },
                openDay: { wd in trainStack.append(RoutineEditorRoute.planDay(weekday: wd)) })
        case .routineToday: RoutineSheet(origin: .today(routineId: nil), mode: .editing)
        case .explore:      MetricExplorerView()
        case .compare:      CompareView()
        // FER-202: `WorkoutsView` se retiró (fusionada en `WorkoutHistoryScreen`). Esta clave solo la
        // alcanza la navegación de screenshots DEBUG (`ScreenshotNav`, rawValue «workouts»), así que
        // apunta al historial unificado en «Todo» con su propio coordinador (no cuelga de un stack que
        // lo inyecte). Sin clausuras: no necesita navegar en ese camino de captura.
        case .workouts:     WorkoutHistoryScreen(initialFilter: .all)
                                .environmentObject(WorkoutHistoryCoordinator())
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
        safeAreaInset(edge: .bottom, spacing: .zero) {
            Color.clear.frame(height: height)
        }
    }
}

/// Hosts the `SessionPill` with a live-ticking clock (FER-716): a `TimelineView` recomputes the
/// elapsed time each second, and the BPM is the Apple Watch live mirror (`model.watchBpm` — the same
/// source as the session header; nil = no watch reading, so the pill drops its ♥ segment instead
/// of freezing a stale sample). Tapping re-opens the session. The routine hue is the indigo
/// (`dataSleep`) — the prototype's 6px pill dot (handoff V10 · FER-139), not the effort ember.
private struct ActiveSessionPillHost: View {
    @Bindable var model: AppModel
    /// Decisión Fer (2026-07-16): el ✕ del pill DESCARTA — destructivo, así que siempre confirma.
    /// El ConfirmCard vive en el RootTabView (pantalla completa); aquí solo se dispara.
    @Binding var confirmDiscard: Bool
    var body: some View {
        if let session = model.strengthSession {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                // FER-952: pause-aware clock (the raw now−start kept ticking while paused).
                let elapsed = SessionClock.format(session.elapsedSeconds(now: context.date))
                let total = session.runs.filter { !$0.skipped }.reduce(0) { $0 + $1.sets.count }
                // FER-167 ronda 2 (R20, Grok 14 + QA O2): «Serie N de M» — la MISMA palabra y el
                // MISMO «N de N · completa» que la cabecera de la Hoja viva (`HojaCabeceraSesion`),
                // nunca dos fuentes que puedan divergir en la unidad de avance.
                let isComplete = total > 0 && session.pendingCount == 0
                let detail: String? = total == 0 ? nil : (isComplete
                    ? String(localized: "\(total) of \(total) · complete")
                    : String(localized: "Set \(min(session.doneCount + 1, total)) of \(total)"))
                SessionPill(
                    routineName: session.routineName,
                    elapsed: elapsed,
                    bpm: model.watchBpm,
                    detail: detail,
                    paused: session.paused,
                    hue: LiquidColor.indigo,
                    accessibilityLabel: pillLabel(session.routineName, elapsed, model.watchBpm),
                    accessibilityHint: Text("Returns to the session"),
                    action: { model.resumeStrengthSession() },
                    onDiscard: { confirmDiscard = true },
                    discardAccessibilityLabel: Text("Discard session")
                )
            }
        }
    }

    /// VoiceOver label for the pill — localized here because the CenitDesign package has no catalog.
    private func pillLabel(_ name: String, _ elapsed: String, _ bpm: Int?) -> Text {
        if let bpm { return Text("Active session: \(name), \(elapsed), heart rate \(bpm)") }
        return Text("Active session: \(name), \(elapsed)")
    }
}
#endif
