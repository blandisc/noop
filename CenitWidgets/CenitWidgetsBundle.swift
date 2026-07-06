// FER-721 · Entrenar v3 · F6 — the widget extension's entry point.
//
// The project's first app-extension target. Today it hosts only the rest Live Activity; future
// home-screen / lock-screen widgets would join this bundle.

#if canImport(ActivityKit)
import SwiftUI
import WidgetKit

@main
struct CenitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestLiveActivity()
    }
}
#endif
