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
    @State private var model: AppModel
    @StateObject private var health: HealthKitBridge
    @StateObject private var mirroring: WorkoutMirroringBridge   // FER-740: Apple Watch session mirroring
    @StateObject private var autoBackup = AutoBackup()
    /// App-level cross-tab navigation (FER-378 «Explóralo en el Coach»).
    @StateObject private var tabRouter = TabRouter()
    /// Opt-in exercise media (thumbs/loop) downloader + disk cache (FER-722). Shared across Ajustes
    /// (the toggle + "borrar" button) and every exercise detail screen (the on-demand loop fetch).
    @StateObject private var mediaCoordinator = MediaDownloadCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Canary: reports a missing App Group entitlement before any silent no-op (e.g. Shortcuts'
        // PendingIntents) can mask it. Logs a fault on device, asserts in the Simulator.
        AppGroup.warnIfGroupUnprovisioned()
        configureInstrumentoControlAppearance()   // FER-408: warm the native segmented control once at launch
        // Inject/InjectionNext: carga el puente de recarga en caliente SOLO en Debug (inerte en Release).
        // Con InjectionNext.app abierta (y Xcode lanzado DESDE ella) corriendo en el Simulador, intercambia
        // el código de las pantallas al guardar, sin recompilar. InjectionNext es el sucesor de InjectionIII,
        // hecho para Xcode 16.3+/26.x (el clásico ya no logra el redibujo en toolchains nuevos).
        #if DEBUG
        Bundle(path: "/Applications/InjectionNext.app/Contents/Resources/iOSInjection.bundle")?.load()
        #endif
        // Warm the bundled Space Grotesk registration OFF the main thread (perf): otherwise the first
        // Grotesk token during TodayView's first render pays the one-time CoreText registration on the
        // launch path. `ensureFontsRegistered()` is idempotent + thread-safe (a `static let`), so this
        // detached warm just moves the cost off the critical first-frame path.
        Task.detached { StrandFont.ensureFontsRegistered() }
        let model = AppModel()
        _model = State(wrappedValue: model)
        let healthBridge = HealthKitBridge(
            repo: model.repo,
            appleDeviceId: model.appleDeviceId,
            noopDeviceId: model.deviceId
        )
        model.healthBridge = healthBridge   // FER-226: AppModel reaches the bridge for the one-time re-bucket
        _health = StateObject(wrappedValue: healthBridge)

        // FER-740: the Apple Watch workout-mirroring bridge. Wakes the watch to record the real
        // HKWorkoutSession when a strength session starts; its callbacks close the one-workout invariant.
        let mirroring = WorkoutMirroringBridge()
        mirroring.onWatchDidSaveWorkout = { [weak model] sid in model?.noteWatchSavedWorkout(sid) }
        mirroring.onWatchWillNotSave = { [weak model] sid in model?.noteWatchWillNotSave(sid) }
        mirroring.onWatchEndedSession = { [weak model] sid, save in
            model?.endStrengthSessionFromWatch(sessionId: sid, save: save)
        }
        // FER-808: wrist-initiated set log / rest skip / ±30 → the same live-session path as the lock screen.
        mirroring.onWatchAction = { [weak model] sid, action in
            model?.applyWatchWorkoutAction(action, sessionId: sid)
        }
        // FER-810: «Ver recibo en iPhone» from the wrist → open the saved workout's history detail.
        mirroring.onOpenReceipt = { [weak model] sid in
            Task { @MainActor in await model?.openWorkoutReceipt(sessionId: sid) }
        }
        // FER-742: surface the bridge's watch state on AppModel, which the Settings row + strength sheet observe.
        mirroring.onPairingChanged = { [weak model] paired, installed in
            model?.watchPaired = paired
            model?.watchAppInstalled = installed
        }
        mirroring.onSessionStatusChanged = { [weak model] status in model?.watchSessionStatus = status }
        model.mirroringBridge = mirroring
        _mirroring = StateObject(wrappedValue: mirroring)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // FER-394: cap Dynamic Type at xxxLarge — reading text scales with the user's
                // text-size setting, but we don't promise the 5 giant Accessibility sizes (they'd
                // break the dense glanceable layouts). Sheets inherit this clamp.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .environment(model)
                .environment(model.live)
                .environmentObject(model.repo)
                .environmentObject(model.profile)
                .environmentObject(model.behavior)
                .environmentObject(model.inactivity)
                .environmentObject(model.goal)
                .environmentObject(model.intelligence)
                .environmentObject(health)
                .environmentObject(autoBackup)
                .environmentObject(tabRouter)
                .environmentObject(mediaCoordinator)
                // Reanudar la descarga de media al abrir la app (FER-800): si el toggle opt-in está
                // ON y quedó a medias (background/kill/red), la retoma sola. Guarda internamente en
                // `isEnabled` → con el toggle OFF (default) es un no-op sin tocar red ni disco.
                .task { await mediaCoordinator.bulkDownloadThumbsIfNeeded() }
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
                    await health.sync(trigger: .foreground)   // FER-872: delta window + no-op refresh guard
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
