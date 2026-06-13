#if os(iOS)
import SwiftUI
import StrandDesign

/// iOS navigation shell. macOS uses a `NavigationSplitView` sidebar (`RootView`); on iPhone the
/// natural analogue is a `TabView` with the most-used screens as tabs and everything else under a
/// "More" list. Every screen is the same `StrandDesign`-built view the macOS app uses.
struct RootTabView: View {
    private enum Tab: Hashable { case today, trends, live, sleep, more }

    /// The visible tab. Starts on Today, the launch screen.
    @State private var selection: Tab = .today
    /// Tabs whose content has been shown at least once. Only Today is built at launch; the other
    /// heavy tabs (Trends/Live/Sleep — each runs its own `.task` data load on appear) are deferred
    /// until first selected, then kept in the set so switching back doesn't rebuild from scratch.
    /// Was eager: all five tab bodies + their launch `.task`s ran at startup, widening the launch
    /// gap. The "More" list is already lazy (its destinations build on `NavigationLink` tap). FER-31.
    @State private var visited: Set<Tab> = [.today]

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
        NavigationStack {
            List {
                Section("Insights") {
                    link("Intelligence", "brain.head.profile") { IntelligenceView() }
                    link("Coach", "sparkles") { CoachView() }
                    link("Insights", "lightbulb.fill") { InsightsView() }
                    link("Explore", "square.grid.2x2.fill") { MetricExplorerView() }
                    link("Compare", "rectangle.split.2x1.fill") { CompareView() }
                }
                Section("Body") {
                    link("Workouts", "figure.run") { WorkoutsView() }
                    link("Health", "heart.text.square.fill") { HealthView() }
                    link("Stress", "bolt.heart.fill") { StressView() }
                    link("Breathe", "wind") { BreathingView() }
                    link("Intervals", "timer") { IntervalTimerView() }
                }
                Section("Data") {
                    link("Apple Health", "heart.fill") { AppleHealthView() }
                    link("Data Sources", "externaldrive.fill") { DataSourcesView() }
                }
                Section("App") {
                    link("Automations", "wand.and.stars") { AutomationsView() }
                    link("Settings", "gearshape.fill") { SettingsView() }
                    link("Support", "hands.clap.fill") { SupportView() }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("More")
        }
        .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
    }

    private func link<V: View>(_ title: LocalizedStringKey, _ icon: String, @ViewBuilder _ dest: @escaping () -> V) -> some View {
        NavigationLink {
            dest()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(StrandPalette.surfaceBase, for: .navigationBar)
        } label: {
            Label(title, systemImage: icon)
        }
        .listRowBackground(StrandPalette.surfaceRaised)
    }
}
#endif
