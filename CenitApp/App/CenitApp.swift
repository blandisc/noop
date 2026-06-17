#if os(iOS)
import SwiftUI

/// iOS entry point. A single `WindowGroup`; the glanceable role is filled by the Home/Lock-Screen
/// widget.
@main
struct CenitApp: App {
    @StateObject private var model: AppModel
    @StateObject private var health: HealthKitBridge
    @StateObject private var autoBackup = AutoBackup()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Debug-only canary: trips if the App Group entitlement is missing on this target before any
        // silent no-op (PendingIntents, WidgetSnapshot.publish, Live Activity) can mask the issue as
        // "the widget doesn't show anything yet." No-op in Release.
        WidgetSnapshot.assertGroupProvisioned()
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        _health = StateObject(wrappedValue: HealthKitBridge(
            repo: model.repo,
            appleDeviceId: model.appleDeviceId,
            noopDeviceId: model.deviceId
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.live)
                .environmentObject(model.repo)
                .environmentObject(model.profile)
                .environmentObject(model.behavior)
                .environmentObject(model.intelligence)
                .environmentObject(model.coach)
                .environmentObject(health)
                .environmentObject(autoBackup)
                // El color scheme ya NO se fuerza global aquí: lo decide ContentView según la pestaña
                // activa (Hoy = papel claro → barra de estado en tinta oscura; resto = oscuro), con el
                // gate de onboarding/terms en oscuro. Ponerlo aquí (lo más cercano a la raíz) ganaba
                // siempre y dejaba la barra de estado clara sobre el papel de Hoy.
                #if DEBUG
                .modifier(DebugURLHandler())
                .onAppear { DebugNavWatcher.shared.start() }
                #endif
        }
        // HealthKit authorization is intentionally NOT requested on launch. The system permission
        // dialog without prior in-app rationale violates Apple HIG / App Review guidance — the user
        // sees the prompt before any context. Authorization should be triggered from an explicit
        // user action: an "Enable Apple Health" row in Settings, or a dedicated step in
        // OnboardingWizard. HealthKitBridge.sync below guards on `auth == .authorized`, so the
        // scenePhase trigger is a safe no-op until the user opts in.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.drainPendingIntents()
                Task {
                    await health.sync()
                    // Snapshot the (possibly just-offloaded) strap history to iCloud Drive. Throttled
                    // to ~once a day and a no-op until the user picks a folder, so it's safe here.
                    await autoBackup.backupIfDue(checkpoint: { await model.repo.checkpointForBackup() })
                    WidgetSnapshot.publish(from: model)
                }
            }
        }
    }
}
#endif
