// FER-721 · Entrenar v3 · F6 — the widget extension's entry point.
//
// The project's first app-extension target. FER-95 (E14) adds the first two home-screen widgets
// alongside the rest Live Activity.

#if canImport(ActivityKit)
import SwiftUI
import WidgetKit

@main
struct CenitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestLiveActivity()
        TrainTodayWidget()
        WeekWidget()
    }
}
#endif
