import SwiftUI
import StrandDesign
import Inject   // recarga en caliente (dev-only, inerte en Release)

/// Marca de proceso de la entrada (FER-41): la coreografía de arranque corre UNA sola vez por
/// lanzamiento.
///
/// El `@State` de `ContentView` ya sobrevive a volver del segundo plano —SwiftUI no reconstruye
/// la raíz del `WindowGroup`—, pero no sobrevive a una reconexión de escena, donde la raíz sí se
/// re-crea y la entrada se repetiría sin que nadie la haya pedido. Esta marca lo deja dicho en
/// una línea y cierra ese caso.
@MainActor
enum EntradaDeArranque {
    private(set) static var yaCorrio = false
    static func marcarCorrida() { yaCorrio = true }
}

/// Root — the sidebar shell, with the first-run onboarding/pairing wizard overlaid until complete,
/// and a "What's New" changelog sheet shown automatically after an update.
struct ContentView: View {
    @AppStorage("noop.onboarded") private var onboarded = false
    @AppStorage("noop.lastSeenChangelogVersion") private var lastSeenChangelog = ""
    @AppStorage("noop.acceptedTermsVersion") private var acceptedTerms = ""
    @State private var showWhatsNew = false
    /// FER-41: la entrada sigue puesta hasta que su coreografía termina (o el usuario la toca).
    @State private var entradaLista = false
    /// El frame REAL del orbe del héroe en pantalla (para que la entrada aterrice sin costura).
    /// Se mide del tamaño de pantalla + área segura; `nil` hasta medir → la entrada cae al
    /// cénit fijo de siempre (sin regresión). Ver `heroDestinoRect`.
    @State private var heroDestino: CGRect? = nil
    /// Whether Today is the active tab (RootTabView keeps this in sync). Drives the app's color scheme
    /// so the status bar is dark on Today's light paper and light on the dark instrument tabs.
    @State private var isTodayTab = true
    /// Inject: al observar la recarga en caliente, la vista se redibuja cuando InjectionNext intercambia
    /// el código. No-op en Release. Puesta en la raíz → toda la app reacciona; para una pantalla puntual,
    /// copia estas dos líneas (la propiedad + `.enableInjection()` al final del `body`) en ese struct —
    /// pero SOLO si ese struct NO es `private`. Los miembros de un tipo privado compilan como símbolos
    /// locales y `-interposable` únicamente alcanza los globales, así que ahí los hooks quedan inertes en
    /// silencio: la inyección reporta éxito y la pantalla no cambia. Cuélgalos de la vista no privada más
    /// externa del archivo; al re-ligar su `body` construye la copia nueva, con todo el código privado
    /// adentro (ver `EntrenarView` y la sección de hot reload en docs/BUILD.md).
    @ObserveInjection private var inject

    #if os(iOS)
    // One-time restore nudge: if NOOP launches with no data (a fresh install or a reinstall after a
    // delete), point the user at the iCloud Drive backup so the strap history comes back in a tap.
    // Reuses the manual import path. The flag lives in UserDefaults (wiped on delete), so it re-arms
    // for exactly the reinstall case it's meant to catch. See [AutoBackup].
    @EnvironmentObject private var repo: Repository
    @AppStorage("noop.didOfferRestore") private var didOfferRestore = false
    @State private var showRestoreOffer = false
    @State private var restoreMessage = ""
    @State private var showRestoreResult = false
    @State private var restoreSucceeded = true
    #endif

    var body: some View {
        ZStack {
            RootTabView(isTodayActive: $isTodayTab)
            if !onboarded {
                OnboardingWizard(onFinished: {
                    onboarded = true
                    // A brand-new user just saw the expectations in onboarding — don't also pop the
                    // changelog at them; mark them current.
                    lastSeenChangelog = AppChangelog.currentVersion
                })
                .transition(.opacity)
                .zIndex(1)
            }
            #if os(iOS)
            // FER-969 (X-03): the store didn't open (wedged migration / corrupt file) — an honest
            // paper state with ways out, never an eternally empty dashboard. Only for onboarded users
            // (a fresh install has its own restore-offer path); the Terms gate stays on top.
            if onboarded && repo.storeOpenFailed {
                StoreFailureView(onRetry: { Task { await repo.retryStoreOpen() } },
                                 onRestore: { Task { await runRestore() } })
                    .transition(.opacity)
                    .zIndex(1)
            }
            #endif
            // Terms acknowledgment gate — over EVERYTHING (before onboarding/pairing/Bluetooth) until
            // the current terms version is accepted; re-appears if the terms materially change.
            if acceptedTerms != Terms.currentVersion {
                TermsGateView(onAccept: { acceptedTerms = Terms.currentVersion })
                    .transition(.opacity)
                    .zIndex(2)
            }
            // La entrada (FER-41) va HASTA ARRIBA, incluso sobre el gate de Términos: es lo
            // primero que existe al abrir. Y va como capa APARTE, no envolviendo a la app: el
            // árbol de abajo se construye y carga mientras la coreografía corre, así que la
            // entrada tapa el arranque pero nunca lo retrasa.
            if mostrandoEntrada {
                // El clima va como CIERRE: la entrada lo lee cuando el teñido arranca, no al
                // montarse — a los 0 ms el veredicto todavía se está calculando.
                // `destino` es el frame REAL del orbe del héroe (responsivo al notch y al
                // ancho): el ascenso aterriza AHÍ, no en un punto fijo, así que el fundido de
                // salida no deja costura. Se lee tarde (durante el ascenso), cuando ya se midió.
                LiquidOrbeEntrada(clima: { climaEntrada }, destino: { heroDestino }) {
                    EntradaDeArranque.marcarCorrida()
                    entradaLista = true
                }
                // Cinturón y tirantes: la entrada ya se apaga sola antes de avisar, así que al
                // quitarla debería ser invisible. Si algún día ese cálculo se desfasa, esto
                // convierte un corte seco en un fundido en vez de en un parpadeo.
                .transition(.opacity)
                .zIndex(3)
            }
        }
        // El héroe (LiquidEcosistema) publica el frame real de su orbe; la entrada lo lee para
        // aterrizar sin costura sobre él. Antes de que llegue (o si el árbol no lo propaga), la
        // entrada cae a su cénit fijo — sin regresión.
        .onPreferenceChange(HeroOrbeFrameKey.self) { heroDestino = $0 }
        .animation(.easeInOut(duration: 0.35), value: onboarded)
        .animation(.easeInOut(duration: 0.35), value: acceptedTerms)
        .animation(.easeOut(duration: 0.2), value: entradaLista)
        // El color scheme se decide AQUÍ (lo más cercano a la raíz del WindowGroup, que es donde el
        // controlador raíz lee `preferredColorScheme` para la barra de estado): el gate de Términos es
        // papel claro (FER-416) → barra en tinta oscura; el onboarding sigue oscuro; ya dentro, Hoy es
        // papel claro y el resto de pestañas oscuras.
        .preferredColorScheme(resolvedColorScheme)
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(onClose: {
                lastSeenChangelog = AppChangelog.currentVersion
                showWhatsNew = false
            })
            // La hoja es papel «Instrumento» (FER-415); la fijamos en claro para que la barra de estado
            // quede en tinta oscura aunque se abra desde una pestaña oscura (p. ej. Support en Ajustes).
            .preferredColorScheme(.light)
        }
        .onAppear {
            // Existing users who updated: their last-seen version is behind the current one.
            if onboarded && lastSeenChangelog != AppChangelog.currentVersion {
                showWhatsNew = true
            }
        }
        #if os(iOS)
        // Check at launch (covers updated users) and again the moment onboarding completes (covers a
        // fresh install / reinstall, where `onboarded` flips false→true after this view appears).
        .task { await maybeOfferRestore() }
        .onChange(of: onboarded) { _, done in if done { Task { await maybeOfferRestore() } } }
        .alert("Restore your data?", isPresented: $showRestoreOffer) {
            Button("Restore from backup…") { Task { await runRestore() } }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("It looks like there's no data on this device. If you've used Cénit before, on this phone or another, restore your history and settings from an iCloud Drive backup.")
        }
        // FER-837: the restore RESULT is an inline banner (the offer above stays a native alert — the
        // honest exception: it fires before the app visually exists).
        .overlay(alignment: .top) {
            if showRestoreResult {
                let theme = InstrumentoTheme.base
                Text(restoreMessage)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .patternBlock(theme, bar: restoreSucceeded ? theme.verdict : theme.critical)
                    .padding(.horizontal, 16)
                    .onTapGesture { showRestoreResult = false }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(8))
                        showRestoreResult = false
                    }
            }
        }
        .animation(StrandMotion.fade, value: showRestoreResult)
        #endif
        .enableInjection()   // Inject: activa la recarga en caliente para esta vista (no-op en Release)
    }

    /// The Terms gate is light «Instrumento» paper (FER-416) and sits over everything until accepted →
    /// light scheme so its status bar renders in dark ink. The onboarding wizard is still dark. Once
    /// inside the app the scheme follows the active tab: Today is light paper (dark-ink status bar),
    /// every other tab is the dark instrument panel.
    private var resolvedColorScheme: ColorScheme {
        if mostrandoEntrada { return .light }                        // la entrada es blanca (FER-41)
        if acceptedTerms != Terms.currentVersion { return .light }   // Terms gate (paper) is on top
        guard onboarded else { return .dark }                        // onboarding wizard is still dark
        return isTodayTab ? .light : .dark
    }

    /// La entrada se pinta mientras no haya terminado Y no haya corrido ya en este proceso.
    private var mostrandoEntrada: Bool { !entradaLista && !EntradaDeArranque.yaCorrio }

    /// El clima al que la entrada tiñe el orbe: el MISMO mapeo veredicto → ambiente que usa la
    /// superficie de Hoy, para que el color con el que el orbe asienta sea exactamente el que la
    /// pantalla de abajo va a mostrar. Al arrancar el veredicto casi nunca está calculado
    /// todavía y `ambiente` devuelve `.neutro`: el orbe se queda gris en vez de apostar un color
    /// y tener que corregirlo a la vista del usuario.
    private var climaEntrada: LiquidAmbiente {
        #if os(iOS)
        return LiquidHoyBuilder.ambiente(prep: repo.todayPreparedness)
        #else
        return .neutro
        #endif
    }

    #if os(iOS)
    @MainActor private func maybeOfferRestore() async {
        guard onboarded, !didOfferRestore else { return }
        try? await Task.sleep(nanoseconds: 2_500_000_000)   // let the launch refresh populate first
        // `fullyLoaded` too (two-pass launch): a user whose stored data is all older than the
        // first-paint window would look empty after pass ① — and `didOfferRestore` is sticky.
        guard !didOfferRestore, repo.fullyLoaded, repo.days.isEmpty else { return }   // re-check after the await
        didOfferRestore = true
        showRestoreOffer = true
    }

    @MainActor private func runRestore() async {
        switch await DataBackup.runImport() {
        case .imported:
            restoreMessage = String(localized: "Your data has been restored. Reopen Cénit for it to take effect.")
            restoreSucceeded = true
            showRestoreResult = true
        case .failure(let message):
            restoreMessage = message
            restoreSucceeded = false
            showRestoreResult = true
        case .cancelled, .exported:
            break
        }
    }
    #endif
}

#if os(iOS)
/// FER-969 (X-03): full-screen honest state when the SQLite store can't open (wedged migration or a
/// corrupt file). Paper, one message, two ways out — retry in place, or restore an iCloud backup.
private struct StoreFailureView: View {
    let onRetry: () -> Void
    let onRestore: () -> Void

    var body: some View {
        let theme = InstrumentoTheme.base
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("Cénit couldn't open your database.")
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
            Text("Your data is still on this phone: retry, or restore from an iCloud Drive backup.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onRetry) {
                Text("Retry")
                    .font(StrandFont.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.ink)
            .padding(.top, 10)
            Button(action: onRestore) {
                Text("Restore from backup…")
                    .font(StrandFont.subhead)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.ink)
            .padding(.vertical, 6)
            Spacer()
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.paper.ignoresSafeArea())
    }
}
#endif
