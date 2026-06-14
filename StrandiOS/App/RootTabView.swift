#if os(iOS)
import SwiftUI
import StrandDesign

/// iOS navigation shell. macOS uses a `NavigationSplitView` sidebar (`RootView`); on iPhone the
/// natural analogue is a `TabView` with the most-used screens as tabs and everything else under a
/// "More" list. Every screen is the same `StrandDesign`-built view the macOS app uses.
struct RootTabView: View {
    private enum Tab: Hashable { case today, trends, live, sleep, more }
    private enum MoreScreen: String, Hashable {
        case intelligence, coach, insights, explore, compare
        case workouts, health, stress, breathe, intervals
        case applehealth, datasources, automations, settings, support
    }

    /// The visible tab. Starts on Today, the launch screen.
    @State private var selection: Tab = .today
    /// Tabs whose content has been shown at least once. Only Today is built at launch; the other
    /// heavy tabs (Trends/Live/Sleep — each runs its own `.task` data load on appear) are deferred
    /// until first selected, then kept in the set so switching back doesn't rebuild from scratch.
    /// Was eager: all five tab bodies + their launch `.task`s ran at startup, widening the launch
    /// gap. The "More" list is already lazy (its destinations build on `NavigationLink` tap). FER-31.
    @State private var visited: Set<Tab> = [.today]
    @State private var moreStack: [MoreScreen] = []

    var body: some View {
        TabView(selection: $selection) {
            lazyTab(.today, "Today", "circle.hexagongrid.fill") { TodayView() }
            lazyTab(.trends, "Trends", "chart.xyaxis.line") { TrendsView() }
            lazyTab(.live, "Live", "waveform.path.ecg") { LiveView() }
            lazyTab(.sleep, "Sleep", "bed.double.fill") { SleepView() }
            moreTab.tag(Tab.more)
        }
        .tint(StrandPalette.accent)
        .preferredColorScheme(.dark)
        .onChange(of: selection) { _, newValue in visited.insert(newValue) }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .noopDebugNav)) { note in
            guard let screen = note.object as? String else { return }
            let tab: Tab? = switch screen {
            case "today":   .today
            case "trends":  .trends
            case "live":    .live
            case "sleep":   .sleep
            case "more":    .more
            default:        nil
            }
            if let tab {
                selection = tab
                visited.insert(tab)
                moreStack = []
                return
            }
            if let ms = MoreScreen(rawValue: screen) {
                selection = .more
                visited.insert(.more)
                moreStack = [ms]
            }
        }
        #endif
        // NOTE: the launch refresh is owned by AppModel.init (one source of truth). A second
        // `.task { repo.refresh() }` here ran a full-history load concurrently with that one at
        // launch — double DB work + an extra refreshSeq bump that re-fired TodayView.loadAll.
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
        .tabItem { Label(title, systemImage: icon) }
        .tag(tag)
    }

    private var moreTab: some View {
        NavigationStack(path: $moreStack) {
            List {
                Section("Insights") {
                    NavigationLink(value: MoreScreen.intelligence) { Label("Intelligence", systemImage: "brain.head.profile") }.listRowBackground(StrandPalette.surfaceRaised)
                    NavigationLink(value: MoreScreen.coach)        { Label("Coach",         systemImage: "sparkles") }.listRowBackground(StrandPalette.surfaceRaised)
                    NavigationLink(value: MoreScreen.insights)     { Label("Insights",      systemImage: "lightbulb.fill") }.listRowBackground(StrandPalette.surfaceRaised)
                    NavigationLink(value: MoreScreen.explore)      { Label("Explore",       systemImage: "square.grid.2x2.fill") }.listRowBackground(StrandPalette.surfaceRaised)
                    NavigationLink(value: MoreScreen.compare)      { Label("Compare",       systemImage: "rectangle.split.2x1.fill") }.listRowBackground(StrandPalette.surfaceRaised)
                }
                Section("Body") {
                    NavigationLink(value: MoreScreen.workouts)     { Label("Workouts", systemImage: "figure.run") }.listRowBackground(StrandPalette.surfaceRaised)
                    NavigationLink(value: MoreScreen.health)       { Label("Health",   systemImage: "heart.text.square.fill") }.listRowBackground(StrandPalette.surfaceRaised)
                    NavigationLink(value: MoreScreen.stress)       { Label("Stress",   systemImage: "bolt.heart.fill") }.listRowBackground(StrandPalette.surfaceRaised)
                    NavigationLink(value: MoreScreen.breathe)      { Label("Breathe",  systemImage: "wind") }.listRowBackground(StrandPalette.surfaceRaised)
                    NavigationLink(value: MoreScreen.intervals)    { Label("Intervals",systemImage: "timer") }.listRowBackground(StrandPalette.surfaceRaised)
                }
                Section("Data") {
                    NavigationLink(value: MoreScreen.applehealth)  { Label("Apple Health",  systemImage: "heart.fill") }.listRowBackground(StrandPalette.surfaceRaised)
                    NavigationLink(value: MoreScreen.datasources)  { Label("Data Sources",  systemImage: "externaldrive.fill") }.listRowBackground(StrandPalette.surfaceRaised)
                }
                Section("App") {
                    NavigationLink(value: MoreScreen.automations)  { Label("Automations", systemImage: "wand.and.stars") }.listRowBackground(StrandPalette.surfaceRaised)
                    NavigationLink(value: MoreScreen.settings)     { Label("Settings",    systemImage: "gearshape.fill") }.listRowBackground(StrandPalette.surfaceRaised)
                    NavigationLink(value: MoreScreen.support)      { Label("Support",     systemImage: "hands.clap.fill") }.listRowBackground(StrandPalette.surfaceRaised)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("More")
            .navigationDestination(for: MoreScreen.self) { screen in
                moreDestination(screen)
                    .background(StrandPalette.surfaceBase.ignoresSafeArea())
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(StrandPalette.surfaceBase, for: .navigationBar)
            }
        }
        .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
    }

    @ViewBuilder
    private func moreDestination(_ screen: MoreScreen) -> some View {
        switch screen {
        case .intelligence: IntelligenceView()
        case .coach:        CoachView()
        case .insights:     InsightsView()
        case .explore:      MetricExplorerView()
        case .compare:      CompareView()
        case .workouts:     WorkoutsView()
        case .health:       HealthView()
        case .stress:       StressView()
        case .breathe:      BreathingView()
        case .intervals:    IntervalTimerView()
        case .applehealth:  AppleHealthView()
        case .datasources:  DataSourcesView()
        case .automations:  AutomationsView()
        case .settings:     SettingsView()
        case .support:      SupportView()
        }
    }
}
#endif
