import SwiftUI
import HealthKit
import WatchKit
import os

/// watchOS entry point for Cénit's Apple Watch companion (FER-740, F1.1 «espejo mínimo»). The app is
/// woken by the iPhone (`HKHealthStore.startWatchApp`) when a guided strength session starts; the
/// delegate below picks up the workout configuration and hands it to `WatchWorkoutManager`, which runs
/// the real `HKWorkoutSession` and mirrors it back. No pull-to-start UI in F1.1 — the iPhone drives.
@main
struct CenitWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var manager = WatchWorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            RestMirrorView()
                .environmentObject(manager)
                .onAppear {
                    manager.requestAuthorization()
                    manager.recoverIfNeeded()   // re-adopt a session that outlived the app
                }
        }
    }
}

/// Receives the workout configuration when the iPhone wakes the app, and starts the mirrored session.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    private let log = Logger(subsystem: "com.noopapp.noop.watch", category: "WatchApp")

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            do { try await WatchWorkoutManager.shared.start(configuration: workoutConfiguration) }
            catch { log.error("Failed to start mirrored workout: \(error.localizedDescription, privacy: .public)") }
        }
    }
}
