#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// Re-skins the native `UISegmentedControl` to the «Instrumento» language (FER-408): a warm selected
/// pill in ink text instead of the system's pure-white pill. `.pickerStyle(.segmented)` ignores SwiftUI
/// `.tint`, so this UIKit appearance pass is the contained, app-wide way to theme every segmented
/// picker at once. Safe because the app anchors to the single light `.base` theme everywhere (FER-398),
/// so there is no dark segmented control to mis-theme. (Toggles use `InstrumentoToggleStyle`; steppers
/// keep `.tint`.)
@MainActor private func configureInstrumentoControlAppearance() {
    let t = InstrumentoTheme.base
    let seg = UISegmentedControl.appearance()
    seg.selectedSegmentTintColor = UIColor(t.surface)        // warm pill, never pure white
    seg.backgroundColor = UIColor(t.hairline)                // warm track behind the segments
    seg.setTitleTextAttributes([.foregroundColor: UIColor(t.inkSecondary)], for: .normal)
    seg.setTitleTextAttributes([.foregroundColor: UIColor(t.ink)], for: .selected)
}

/// iOS entry point. A single `WindowGroup`; the glanceable role is filled by the Home/Lock-Screen
/// widget.
@main
struct CenitApp: App {
    @StateObject private var model: AppModel
    @StateObject private var health: HealthKitBridge
    @StateObject private var autoBackup = AutoBackup()
    /// App-level cross-tab navigation (FER-378 «Explóralo en el Coach»).
    @StateObject private var tabRouter = TabRouter()
    /// Opt-in exercise media (thumbs/loop) downloader + disk cache (FER-722). Shared across Ajustes
    /// (the toggle + "borrar" button) and every exercise detail screen (the on-demand loop fetch).
    @StateObject private var mediaCoordinator = MediaDownloadCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Debug-only canary: trips if the App Group entitlement is missing on this target before any
        // silent no-op (e.g. Shortcuts' PendingIntents) can mask it. No-op in Release.
        AppGroup.assertGroupProvisioned()
        configureInstrumentoControlAppearance()   // FER-408: warm the native segmented control once at launch
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        let healthBridge = HealthKitBridge(
            repo: model.repo,
            appleDeviceId: model.appleDeviceId,
            noopDeviceId: model.deviceId
        )
        model.healthBridge = healthBridge   // FER-226: AppModel reaches the bridge for the one-time re-bucket
        _health = StateObject(wrappedValue: healthBridge)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // FER-394: cap Dynamic Type at xxxLarge — reading text scales with the user's
                // text-size setting, but we don't promise the 5 giant Accessibility sizes (they'd
                // break the dense glanceable layouts). Sheets inherit this clamp.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .environmentObject(model)
                .environmentObject(model.live)
                .environmentObject(model.repo)
                .environmentObject(model.profile)
                .environmentObject(model.behavior)
                .environmentObject(model.inactivity)
                .environmentObject(model.goal)
                .environmentObject(model.intelligence)
                .environmentObject(model.coach)
                .environmentObject(health)
                .environmentObject(autoBackup)
                .environmentObject(tabRouter)
                .environmentObject(mediaCoordinator)
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
            switch phase {
            case .active:
                // Resume the periodic on-device analysis loop (cancelled when we backgrounded). Idempotent,
                // so the initial launch — where AppModel.init already started it — is a no-op here.
                model.startAnalysisLoop()
                model.drainPendingIntents()
                Task {
                    await health.sync()
                    // Snapshot the (possibly just-offloaded) strap history to iCloud Drive. Throttled
                    // to ~once a day and a no-op until the user picks a folder, so it's safe here.
                    await autoBackup.backupIfDue(checkpoint: { await model.repo.checkpointForBackup() })
                }
            case .background:
                // Stop the heavy 15-min analysis while NOOP is off screen, so it doesn't compete with
                // BLE keep-alive / backfill on the main actor (FER-177).
                model.stopAnalysisLoop()
            case .inactive:
                break   // transient (app switcher, Control Center) — keep the loop alive
            @unknown default:
                break
            }
        }
    }
}
#endif
