import SwiftUI
import CenitDesign

/// The watch face for a mirrored strength session (FER-741). One dominant focus per state, color only in
/// the datum, hierarchy by space — Liquid sobre OLED (DECISIONS 2026-09-03, FER-309/312). It routes the
/// coarse `WatchWorkoutManager.Phase` to a screen; the live face derives rest vs. pulse and the degraded
/// overlays (no reading / no permission / no iPhone) from the finer published state.
///
/// El suelo es `LiquidOLED.fondo` (negro OLED). `.instrumentoTheme(.watch)` se conserva solo para
/// `EntrenarHilo`, que todavía leen `\.instrumentoTheme` en el paquete (deuda de CenitDesign,
/// fuera de este issue).
struct WatchSessionRootView: View {
    @EnvironmentObject var manager: WatchWorkoutManager

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LiquidOLED.fondo.ignoresSafeArea())
            .instrumentoTheme(.watch)
    }

    @ViewBuilder private var content: some View {
        switch manager.phase {
        case let .idle(couldNotConnect):
            WatchIdleView(couldNotConnect: couldNotConnect)
        case .connecting:
            WatchConnectingView()
        case .healthKitFailure:
            WatchHealthKitFailureView()
        case .running:
            if manager.restEndedBanner { WatchRestEndedView() }
            else { WatchLiveFaceView() }
        case .summary:
            if let summary = manager.summary { WatchSummaryView(summary: summary) }
            else { WatchIdleView(couldNotConnect: false) }
        }
    }
}

// MARK: - 1 · Waiting (and the «couldn't connect» variant)

/// State 1 (and state 2's failure fallback). No dead buttons, no fake data — just what to do next.
///
/// FER-96: also shows today's routine + the already-resolved daily verdict (`manager.idleContext`,
/// pushed by the iPhone over `updateApplicationContext`) instead of a bare «No session», plus an
/// «Empezar» affordance when a routine is known — `.startFromWrist`, the one-oracle invariant: the
/// wrist only asks, the iPhone resolves + starts.
struct WatchIdleView: View {
    let couldNotConnect: Bool
    @EnvironmentObject var manager: WatchWorkoutManager
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var routineTitle: String {
        manager.idleContext.routineName ?? String(localized: "No session")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LiquidSpace.s200) {
                // Grupo informativo (sin el CTA): un solo elemento VoiceOver con los textos visibles.
                // `Group` no altera el layout; el botón «Empezar» sigue siendo foco aparte.
                Group {
                    Text(routineTitle)
                        .font(LiquidType.tituloHoja)
                        .foregroundStyle(LiquidOLED.tinta)
                        .multilineTextAlignment(.center)
                    if let word = manager.idleContext.word {
                        EntrenarHilo(tone: manager.idleContext.tone, word: LocalizedStringKey(word),
                                    advice: manager.idleContext.advice.map { LocalizedStringKey($0) },
                                    radio: EntrenarMetrics.orbeSesion)
                            // FER-96: freezes with the screen dimmed (Always-On), same brake `OrbeVivo`
                            // already reads for Reduce Motion.
                            .environment(\.liquidAmbientPaused, isLuminanceReduced)
                    }
                    Text("Start a strength routine on your iPhone and the watch joins in.")
                        .font(LiquidType.filaConteo)
                        .foregroundStyle(LiquidOLED.tintaSecundaria)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(idleAccessibilityLabel)

                if let routine = manager.idleContext.routineName { startButton(routine) }
                if couldNotConnect {
                    Text("Couldn't connect to the session. Keep going on your iPhone.")
                        .font(LiquidType.pie)
                        .foregroundStyle(LiquidOLED.tintaTerciaria)
                        .multilineTextAlignment(.center)
                }
                if manager.authorizationRequestFailed {
                    Text("Couldn't ask for Health access. Open Cénit on your iPhone.")
                        .font(LiquidType.pie)
                        .foregroundStyle(LiquidOLED.negativo)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LiquidSpace.s300)
            .padding(.vertical, LiquidSpace.s200)
        }
    }

    /// VoiceOver: los mismos textos visibles del bloque informativo (sin inventar copy).
    private var idleAccessibilityLabel: Text {
        var label = Text(verbatim: routineTitle)
        if let word = manager.idleContext.word {
            label = label + Text(verbatim: ". ") + Text(LocalizedStringKey(word))
            if let advice = manager.idleContext.advice {
                label = label + Text(verbatim: ". ") + Text(LocalizedStringKey(advice))
            }
        }
        return label + Text(verbatim: ". ") + Text("Start a strength routine on your iPhone and the watch joins in.")
    }

    private func startButton(_ routine: String) -> some View {
        Button {
            WatchHaptic.actionTapped.play()
            manager.startTodayFromWrist()
        } label: {
            Text("Start \(routine)")
                .font(LiquidType.filaConteo)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: LiquidControl.hitTarget)
        }
        // token-exempt(sistema): control nativo watchOS
        .buttonStyle(.borderedProminent)
        .tint(LiquidOLED.tinta)
    }
}

// MARK: - 2 · Connecting

/// State 2. A brief transition while the woken app spins up the session; falls to `WatchIdleView`
/// (couldn't connect) after 15s, handled by the manager's watchdog.
struct WatchConnectingView: View {
    var body: some View {
        VStack(spacing: LiquidSpace.s200) {
            Text("Connecting")
                .font(LiquidType.tituloHoja)
                .foregroundStyle(LiquidOLED.tintaSecundaria)
            ProgressView()
                .tint(LiquidOLED.tintaTerciaria)
        }
        .padding(.horizontal, LiquidSpace.s300)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Connecting"))
    }
}

// MARK: - 7-new · HealthKit refused to start

/// FER-96: `HKWorkoutSession(healthStore:configuration:)` (or the collection/mirror start that follows
/// it) threw — immediate and distinguishable from the generic 15s «couldn't connect» (`WatchIdleView`'s
/// `couldNotConnect`, a dropped/silent wake with no known cause). This one says WHY: a Health problem.
struct WatchHealthKitFailureView: View {
    var body: some View {
        VStack(spacing: LiquidSpace.s200) {
            // iconSF(36) ≈ 28 pt (factor 0.78), el rol de title1 en el Watch
            Image(systemName: "heart.text.square")
                .font(LiquidType.iconSF(size: 36))
                .foregroundStyle(LiquidOLED.negativo)
            Text("Couldn't start the workout")
                .font(LiquidType.tituloHoja)
                .foregroundStyle(LiquidOLED.tinta)
                .multilineTextAlignment(.center)
            Text("There's a problem with Health on your watch. Keep going on your iPhone.")
                .font(LiquidType.filaConteo)
                .foregroundStyle(LiquidOLED.tintaSecundaria)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, LiquidSpace.s300)
        .accessibilityElement(children: .combine)
        .onAppear {
            AccessibilityNotification.Announcement(String(localized: "Couldn't start the workout")).post()
        }
    }
}

// MARK: - 5 · Rest over

/// State 5's visual transition (~3s), shown while the strong rest-end haptic plays. The haptic is the
/// primary signal; this confirms it at a glance and posts a VoiceOver announcement. Returns to the live
/// face on its own.
struct WatchRestEndedView: View {
    var body: some View {
        VStack(spacing: LiquidSpace.s200) {
            // iconSF(36) ≈ 28 pt (factor 0.78), el rol de title1 en el Watch
            Image(systemName: "checkmark")
                .font(LiquidType.iconSF(size: 36))
                .foregroundStyle(LiquidOLED.verde)
            // FER-225 — reuses the «Ready» key (→ «Listo») instead of the retired «Rest over», so the
            // watch stops contradicting itself: `WatchLiveFaceView` already says «Listo» for the same
            // recovered instant in HR-mode rest.
            Text("Ready")
                .font(LiquidType.tituloHoja)
                .foregroundStyle(LiquidOLED.tinta)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, LiquidSpace.s300)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Ready"))
        .onAppear { AccessibilityNotification.Announcement(String(localized: "Ready")).post() }
    }
}

#if DEBUG
/// A configured `WatchWorkoutManager` for previews — a plain function (not a `@ViewBuilder` closure),
/// so setting its `@Published` properties is an ordinary statement, not a View-producing expression.
@MainActor private func previewManager(idleContext: WatchIdleContext = WatchIdleContext(),
                            authorizationRequestFailed: Bool = false) -> WatchWorkoutManager {
    let manager = WatchWorkoutManager()
    manager.idleContext = idleContext
    manager.authorizationRequestFailed = authorizationRequestFailed
    return manager
}

/// FER-96 — the idle face with a known verdict (the orbe/`EntrenarHilo` in play) + today's routine.
#Preview("Idle · con veredicto") {
    WatchIdleView(couldNotConnect: false)
        .environmentObject(previewManager(idleContext: .init(
            word: "En rango", advice: "tu plan de hoy, tal cual", routineName: "Empuje", toneRaw: "clear")))
        .background(LiquidOLED.fondo)
}

/// Freeze check for the criterion «cualquier pieza animada nueva se congela con `isLuminanceReduced`» —
/// compare against the previous preview: the orbe stops rotating here.
#Preview("Idle · con veredicto, pantalla atenuada") {
    WatchIdleView(couldNotConnect: false)
        .environmentObject(previewManager(idleContext: .init(
            word: "En rango", advice: "tu plan de hoy, tal cual", routineName: "Empuje", toneRaw: "clear")))
        .environment(\.isLuminanceReduced, true)
        .background(LiquidOLED.fondo)
}

/// Sin lectura + fallo de autorización de HealthKit (Higiene, FER-96) a la vez — el estado más cargado.
#Preview("Idle · sin lectura + fallo de Health") {
    WatchIdleView(couldNotConnect: true)
        .environmentObject(previewManager(authorizationRequestFailed: true))
        .background(LiquidOLED.fondo)
}

#Preview("Idle · AX5") {
    WatchIdleView(couldNotConnect: false)
        .environmentObject(previewManager(idleContext: .init(
            word: "Recupera", advice: "suave hoy, o descansa", routineName: "Tirón", toneRaw: "ease")))
        .background(LiquidOLED.fondo)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Fallo de HealthKit al arrancar") {
    WatchHealthKitFailureView()
        .background(LiquidOLED.fondo)
}
#endif
