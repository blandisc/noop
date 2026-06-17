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
        case intelligence, insights, coach        // Coach hub
        case breathe, intervals                   // Entrenar hub
        case settings                             // Ajustes — primary
        case explore, compare, workouts, health, stress
        case applehealth, datasources, automations, support   // Ajustes — «Más»
    }

    /// Whether Today is the active tab — published up to ContentView, which owns the color scheme
    /// (and with it the status bar): Today is light paper → dark status bar, the rest are dark.
    @Binding var isTodayActive: Bool

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
    @State private var coachStack = NavigationPath()
    @State private var trainStack = NavigationPath()
    @State private var settingsStack = NavigationPath()
    /// Measured height of the «Barra de instrumento» (its button row, above the
    /// home-indicator bleed). Each tab reserves exactly this much at its bottom so
    /// the last component clears the bar — see `barReservation`. Starts 0 and is
    /// filled on first layout via `BarHeightKey`.
    @State private var barHeight: CGFloat = 0

    var body: some View {
        TabView(selection: $selection) {
            lazyTab(.today, "Today", "circle.hexagongrid.fill") { TodayView() }
            lazyTab(.body,  "Body",  "chart.xyaxis.line") { CuerpoView() }

            // Coach — interim hub: the three insight surfaces, seed of the unified Coach layer.
            hubTab(.coach, "Coach", "sparkles", path: $coachStack) {
                Section {
                    row(.intelligence, "Intelligence", "brain.head.profile")
                    row(.insights,     "Insights",     "lightbulb.fill")
                    row(.coach,        "Coach",        "sparkles")
                }
            }

            // Entrenar — interim hub: live workout (FER-197) + the active-session tools.
            hubTab(.train, "Train", "figure.strengthtraining.functional", path: $trainStack) {
                LiveWorkoutHubRow(solar: barSolar)
                Section {
                    row(.breathe,   "Breathe",   "wind")
                    row(.intervals, "Intervals", "timer")
                }
            }

            // Ajustes — Settings + a temporary «Más» section holding every still-orphan screen so
            // nothing from the old shell (incl. Sleep, which lost its tab) becomes unreachable.
            hubTab(.settings, "Ajustes", "gearshape.fill", path: $settingsStack) {
                Section {
                    row(.settings, "Settings", "gearshape.fill")
                }
                // Sleep · Health · Stress moved to «Cuerpo» as métricas (FER-186) — Sueño opens the
                // light «Instrumento» Detalle de Sueño from Cuerpo (FER-212), and Health's vitals +
                // Stress are rows there. The rest stay in this interim drawer until their sibling issues
                // give them a home.
                Section("More") {
                    row(.explore,     "Explore",      "square.grid.2x2.fill")
                    row(.compare,     "Compare",      "rectangle.split.2x1.fill")
                    row(.workouts,    "Workouts",     "figure.run")
                    row(.applehealth, "Apple Health", "heart.fill")
                    row(.datasources, "Data Sources", "externaldrive.fill")
                    row(.automations, "Automations",  "wand.and.stars")
                    row(.support,     "Support",      "hands.clap.fill")
                }
            }
        }
        // `.tint` no longer paints the tab bar (it's hidden below; the custom
        // `InstrumentTabBar` sets its own ink), but it still tints links/controls
        // inside the screens — kept for those.
        .tint(StrandPalette.accent)
        // The «Barra de instrumento» (FER-163): the native bar is hidden per page
        // (see `lazyTab`/`hubTab`) and this custom bar takes its place.
        //
        // It is mounted as an `overlay` (it floats, pinned to the bottom) rather
        // than via `safeAreaInset` on the `TabView`: a bottom safe-area inset placed
        // on a `TabView` whose native bar is hidden draws the bar but does NOT reach
        // the safe area of each page's `ScrollView`, so the last component scrolled
        // under the bar. Instead each tab reserves the bar's measured height at the
        // CONTENT level (`barReservation`), where the inset does propagate to scroll
        // views. The bar reports its height via `BarHeightKey`.
        //
        // `instrumentoThemeByHour` drives `\.instrumentoTheme` so that — under Hoy —
        // the bar warms with the clock exactly like TodayView; under the dark screens
        // it ignores the theme and uses `StrandPalette`. (Color scheme itself is owned
        // by ContentView via `isTodayActive` — FER-160; the bar uses explicit colors
        // either way.)
        .overlay(alignment: .bottom) {
            InstrumentTabBar(items: barItems, selection: $selection, isLight: isLightTab(selection))
                .instrumentoThemeByHour(solar: barSolar)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: BarHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .onPreferenceChange(BarHeightKey.self) { barHeight = $0 }
        // Color scheme lo decide ContentView (cercano a la raíz) según `isTodayActive`; aquí solo lo
        // mantenemos sincronizado con la pestaña visible. Solo Hoy es papel claro «Instrumento»; las
        // otras cuatro pestañas son el panel oscuro. (En vivo es ahora un cover sobre Hoy, no pestaña.)
        .onChange(of: selection) { _, newValue in
            visited.insert(newValue)
            isTodayActive = isLightTab(newValue)
        }
        .onAppear { isTodayActive = isLightTab(selection) }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .noopDebugNav)) { note in
            guard let screen = note.object as? String else { return }
            // Tab-level keys land on a clean hub root. "trends" → Cuerpo, "more"/"ajustes" → Ajustes.
            let tab: Tab? = switch screen {
            case "today":              .today
            // Sueño lost its own screen — it now lives as a row inside «Cuerpo» (FER-186/212), so the
            // screenshot key lands on the Body tab (the screen that owns it) instead of a standalone push.
            case "body", "trends", "sleep": .body
            case "coach":              .coach
            case "train", "entrenar":  .train
            case "settings", "ajustes", "more": .settings
            default:                   nil
            }
            if let tab {
                selection = tab
                coachStack = NavigationPath(); trainStack = NavigationPath(); settingsStack = NavigationPath()
                return
            }
            // Secondary screens: select the owning hub and push the screen onto its stack.
            if let sec = SecondaryScreen(rawValue: screen) {
                let owner = hub(for: sec)
                selection = owner
                var path = NavigationPath(); path.append(sec)
                switch owner {
                case .coach:    coachStack = path
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
    private func isLightTab(_ tab: Tab) -> Bool { tab == .today || tab == .body }

    /// The hub tab that owns a given secondary screen (for debug navigation).
    private func hub(for screen: SecondaryScreen) -> Tab {
        switch screen {
        case .intelligence, .insights, .coach: return .coach
        case .breathe, .intervals:             return .train
        default:                               return .settings
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
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
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

    /// An interim hub tab: a `NavigationStack` over a grouped list whose rows push `SecondaryScreen`s.
    /// Same chrome the old "More" tab used (hidden native bar, dark surface, reserved bar height).
    @ViewBuilder
    private func hubTab<Rows: View>(_ tag: Tab, _ title: LocalizedStringKey, _ icon: String,
                                    path: Binding<NavigationPath>,
                                    @ViewBuilder rows: () -> Rows) -> some View {
        NavigationStack(path: path) {
            List { rows() }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .barReservation(barHeight)
                .navigationTitle(title)
                .navigationDestination(for: SecondaryScreen.self) { screen in
                    secondaryDestination(screen)
                        .background(StrandPalette.surfaceBase.ignoresSafeArea())
                        .barReservation(barHeight)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(StrandPalette.surfaceBase, for: .navigationBar)
                }
        }
        .toolbar(.hidden, for: .tabBar)
        .tabItem { Label(title, systemImage: icon) }
        .tag(tag)
    }

    /// A grouped-list row that pushes a secondary screen onto its hub's stack.
    private func row(_ screen: SecondaryScreen, _ title: LocalizedStringKey, _ icon: String) -> some View {
        NavigationLink(value: screen) { Label(title, systemImage: icon) }
            .listRowBackground(StrandPalette.surfaceRaised)
    }

    // MARK: - Custom bar (FER-163)

    /// The five tabs as drawn by `InstrumentTabBar`. Thin-stroke set: the 24h dial for Hoy (the bar's
    /// signature mark), line glyphs for the rest. (Hidden `tabItem` icons use the filled variants from
    /// the issue spec; only this custom bar is visible.)
    private var barItems: [InstrumentTabBar<Tab>.Item] {
        [
            .init(.today,    "Today",   .dial),
            .init(.body,     "Body",    .system("chart.xyaxis.line")),
            .init(.coach,    "Coach",   .system("sparkles")),
            .init(.train,    "Train",   .system("figure.strengthtraining.functional")),
            .init(.settings, "Ajustes", .system("gearshape")),
        ]
    }

    /// Sunrise/sunset for today, GPS- and permission-free (same `SolarClock` source
    /// TodayView uses), so the bar's by-the-hour theme tracks the real sun in step
    /// with the screen above it. `nil` in polar cases falls back to fixed hours.
    private var barSolar: SolarWindow? {
        guard let w = SolarClock.sunWindow(on: Date(), in: .current) else { return nil }
        return SolarWindow(sunrise: w.sunrise, sunset: w.sunset)
    }

    @ViewBuilder
    private func secondaryDestination(_ screen: SecondaryScreen) -> some View {
        switch screen {
        case .intelligence: IntelligenceView()
        case .insights:     InsightsView()
        case .coach:        CoachView()
        case .breathe:      BreathingView()
        case .intervals:    IntervalTimerView()
        case .settings:     SettingsView()
        case .explore:      MetricExplorerView()
        case .compare:      CompareView()
        case .workouts:     WorkoutsView()
        case .health:       HealthView()
        case .stress:       StressView()
        case .applehealth:  AppleHealthView()
        case .datasources:  DataSourcesView()
        case .automations:  AutomationsView()
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
#endif
