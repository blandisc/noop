#if os(iOS)
import SwiftUI
import UIKit
import CenitDesign

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
        Task.detached { LiquidType.ensureFontsRegistered() }
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
        mirroring.onWatchAction = { [weak model] sid, action, requestedAt in
            model?.applyWatchWorkoutAction(action, sessionId: sid, requestedAt: requestedAt)
        }
        // FER-810: «Ver recibo en iPhone» from the wrist → open the saved workout's history detail.
        mirroring.onOpenReceipt = { [weak model] sid in
            Task { @MainActor in await model?.openWorkoutReceipt(sessionId: sid) }
        }
        // FER-96: «Empezar» from the wrist's idle face → resolve + start today's session through the
        // same path the iPhone's own «Empezar» button uses (the one-oracle invariant).
        mirroring.onStartFromWrist = { [weak model] in
            Task { @MainActor in await model?.startTodayFromWrist() }
        }
        // FER-742: surface the bridge's watch state on AppModel, which the Settings row + strength sheet observe.
        mirroring.onPairingChanged = { [weak model] paired, installed in
            model?.watchPaired = paired
            model?.watchAppInstalled = installed
            // FER-96: a watch newly paired + installed is the moment it's worth refreshing the idle-face
            // context — it may be seeing this iPhone (or a fresh install) for the first time.
            if paired, installed { Task { @MainActor in await model?.pushWatchIdleContext() } }
        }
        mirroring.onSessionStatusChanged = { [weak model] status in model?.watchSessionStatus = status }
        mirroring.onWatchPulseChanged = { [weak model] bpm in
            if let bpm { model?.ingestWatchPulse(bpm: bpm) } else { model?.watchBpm = nil }
        }
        model.mirroringBridge = mirroring
        _mirroring = StateObject(wrappedValue: mirroring)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // FER-394: cap Dynamic Type at xxxLarge — reading text scales with the user's
                // text-size setting, but we don't promise the 5 giant Accessibility sizes (they'd
                // break the dense glanceable layouts). Sheets inherit this clamp.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)  // token-exempt(unico): tope global de la app (FER-394); distinto del cap bendecido por pantalla (.accessibility5)
                .environment(model)
                .environmentObject(model.repo)
                .environmentObject(model.profile)
                .environmentObject(model.behavior)
                .environmentObject(model.goal)
                .environmentObject(health)
                .environmentObject(autoBackup)
                .environmentObject(tabRouter)
                .environmentObject(mediaCoordinator)
                // Reanudar la descarga de media al abrir la app (FER-800): si el toggle opt-in está
                // ON y quedó a medias (background/kill/red), la retoma sola. Guarda internamente en
                // `isEnabled` → con el toggle OFF (default) es un no-op sin tocar red ni disco.
                .task { await mediaCoordinator.bulkDownloadThumbsIfNeeded() }
                // FER-95 · E14 — «Empezar» tocado en el widget con la app CERRADA: `.onChange(of:
                // scenePhase)` abajo no ve una transición de fase en un arranque en frío (llega
                // directo en `.active`), así que ese drain solo cubre reanudar desde segundo plano.
                // Este `.task` cubre el arranque en frío; `drain()` es idempotente (limpia la bandera
                // al leerla), así que si el segundo camino también corre, el segundo no hace nada.
                .task { if StartRoutineBridge.drain() { tabRouter.startTodayTraining() } }
                // FER-96: push the watch's idle-face context once at launch (today's routine + the daily
                // verdict, once resolved) — best-effort, a no-op without a paired watch.
                .task { await model.pushWatchIdleContext() }
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
                model.drainPendingIntents()
                // FER-95 · E14 — «Empezar» tapped on the home-screen widget while the app was closed:
                // reuse the SAME cross-tab path the Daily Brief's own «Empezar» already uses
                // (`TabRouter.startTodayTraining()`), so the app lands directly in today's guided
                // session, no second tap. `tabRouter` lives here (not on `AppModel`), so the drain
                // happens at this call site rather than alongside `drainPendingIntents()`.
                if StartRoutineBridge.drain() { tabRouter.startTodayTraining() }
                Task {
                    // FER-1024: one refresh per foreground, never two concurrent. `resumeForegroundAnalysis`
                    // forces a rebuild ONLY when the day rolled over (so «Hoy» re-buckets past midnight even
                    // with no new Apple data), and is awaited BEFORE the sync so the two never overlap. It
                    // replaces the old `startAnalysisLoop()` here, which re-ran the whole launch refresh —
                    // concurrently with the sync below — and assembled the dashboard twice per activation.
                    await model.resumeForegroundAnalysis()
                    await health.sync(trigger: .foreground)   // FER-872: delta window + no-op refresh guard
                    // Snapshot the (possibly just-offloaded) strap history to iCloud Drive. Throttled
                    // to ~once a day and a no-op until the user picks a folder, so it's safe here.
                    await autoBackup.backupIfDue(checkpoint: { await model.repo.checkpointForBackup() })
                }
            case .background:
                // Stop the analysis sequence while NOOP is off screen, so the band-mode periodic recompute
                // doesn't compete with BLE keep-alive / backfill on the main actor (FER-177).
                model.stopAnalysis()
                model.scheduleInProgressPersist(immediate: true)
            case .inactive:
                // Nancy · ronda 1: el snapshot anti-crash de la sesión viva (FER-798) solo se escribía
                // con 1 s de debounce, así que matar la app desde el selector —o que iOS la mate en
                // segundo plano— perdía las últimas capturas. `.inactive` es la PRIMERA señal antes de
                // ese cierre, así que aquí se fuerza el vaciado; es un no-op sin sesión viva.
                model.scheduleInProgressPersist(immediate: true)
                break   // transient (app switcher, Control Center) — keep the loop alive
            @unknown default:
                break
            }
        }
    }
}
#endif
