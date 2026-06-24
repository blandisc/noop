#if os(iOS)
import SwiftUI

/// App-level cross-tab navigation. A screen deep inside one tab (e.g. a sheet presented from «Cuerpo»)
/// can ask the app to switch tabs by calling `select(_:)`; `RootTabView` observes `requested` and applies
/// it, then clears it. Deliberately ADDITIVE — it does not own the tab selection (that stays
/// `RootTabView`'s `@State`); it only relays a one-shot request, so the tab shell keeps its existing
/// wiring. (FER-378 — the «Explóralo en el Coach» handoff.)
@MainActor
final class TabRouter: ObservableObject {
    enum Tab: String, Sendable { case today, body, coach, train, settings }

    /// A one-shot tab-switch request. `RootTabView` consumes it (sets it back to nil) on receipt.
    @Published var requested: Tab?
    /// One-shot: after landing on «Cuerpo», open the muscle-fatigue map. Consumed (reset to false) by
    /// `CuerpoView`. Lets the strength summary's muscle chips reach the map without stacking a third
    /// sheet over the session (FER-409).
    @Published var openMuscleMap = false

    /// One-shot: after landing on «Entrenar», start today's guided session. Consumed (reset to false) by
    /// `EntrenarView`. Lets the Daily Brief's «Hoy en tu plan» block start the workout in one tap, reusing
    /// Entrenar's own prefetched slots instead of duplicating the load (FER-613).
    @Published var startTodaySession = false

    func select(_ tab: Tab) { requested = tab }

    /// Switch to «Cuerpo» and ask it to open the fatigue map (the strength summary's muscle chips).
    func openFatigueMap() { openMuscleMap = true; requested = .body }

    /// Switch to «Entrenar» and ask it to start today's session (the Daily Brief's «Empezar»).
    func startTodayTraining() { startTodaySession = true; requested = .train }
}
#endif
