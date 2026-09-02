import SwiftUI
import CenitDesign
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

/// Root — the sidebar shell, with the first-run onboarding/pairing wizard overlaid until complete.
struct ContentView: View {
    @AppStorage("noop.onboarded") private var onboarded = false
    @AppStorage("noop.acceptedTermsVersion") private var acceptedTerms = ""
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
    // One-time restore nudge: if Cénit launches with no data AND the user did connect Apple Health
    // (FER-116), point them at the backup FILE they exported themselves, so a reinstall gets its
    // history back in a tap. Reuses the manual import path. The flag lives in UserDefaults (wiped on
    // delete), so it re-arms for exactly the reinstall case it's meant to catch. See [AutoBackup].
    @EnvironmentObject private var repo: Repository
    /// FER-116: la conexión con Apple Salud es la señal que decide si la oferta de restaurar tiene
    /// sentido siquiera (ver `maybeOfferRestore`).
    @EnvironmentObject private var health: HealthKitBridge
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
                    // FER-109: la entrada de partículas se cuenta como YA CORRIDA al cerrar el
                    // onboarding. Sin esto, `mostrandoEntrada` se vuelve cierto en el instante en que
                    // `onboarded` pasa a true y el usuario recibe 2.8 s más de coreografía JUSTO
                    // después del reveal de su palabra — y si venía por la salida a Entrenar, el
                    // orbe aterrizaría sobre el frame del héroe de Hoy, que no es la pestaña activa.
                    // `yaCorrio` es estático por proceso, así que el próximo arranque la entrada
                    // vuelve sola, que es cuando por fin hay un veredicto que revelar.
                    EntradaDeArranque.marcarCorrida()
                    onboarded = true
                })
                .transition(LiquidMotion.fadeTransition)
                .zIndex(1)
            }
            #if os(iOS)
            // FER-969 (X-03): the store didn't open (wedged migration / corrupt file) — an honest
            // paper state with ways out, never an eternally empty dashboard. Only for onboarded users
            // (a fresh install has its own restore-offer path); the Terms gate stays on top.
            if onboarded && repo.storeOpenFailed {
                StoreFailureView(onRetry: { Task { await repo.retryStoreOpen() } },
                                 onRestore: { Task { await runRestore() } })
                    .transition(LiquidMotion.fadeTransition)
                    .zIndex(1)
            }
            #endif
            // Terms acknowledgment gate — over EVERYTHING (before onboarding/pairing/Bluetooth) until
            // the current terms version is accepted; re-appears if the terms materially change.
            if acceptedTerms != Terms.currentVersion {
                TermsGateView(onAccept: { acceptedTerms = Terms.currentVersion })
                    .transition(LiquidMotion.fadeTransition)
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
                .transition(LiquidMotion.fadeTransition)
                .zIndex(3)
            }
        }
        // El héroe (LiquidEcosistema) publica el frame real de su orbe; la entrada lo lee para
        // aterrizar sin costura sobre él. Antes de que llegue (o si el árbol no lo propaga), la
        // entrada cae a su cénit fijo — sin regresión.
        .onPreferenceChange(HeroOrbeFrameKey.self) { heroDestino = $0 }
        .animation(LiquidMotion.ambient(LiquidMotion.measured), value: onboarded)
        .animation(LiquidMotion.ambient(LiquidMotion.measured), value: acceptedTerms)
        .animation(LiquidMotion.settle(LiquidMotion.soft), value: entradaLista)
        // El color scheme se decide AQUÍ (lo más cercano a la raíz del WindowGroup, que es donde el
        // controlador raíz lee `preferredColorScheme` para la barra de estado): el gate de Términos es
        // papel claro (FER-416) → barra en tinta oscura; el onboarding sigue oscuro; ya dentro, Hoy es
        // papel claro y el resto de pestañas oscuras.
        .preferredColorScheme(resolvedColorScheme)
        #if os(iOS)
        // Check at launch (covers updated users) and again the moment onboarding completes (covers a
        // fresh install / reinstall, where `onboarded` flips false→true after this view appears).
        .task { await maybeOfferRestore() }
        .onChange(of: onboarded) { _, done in if done { Task { await maybeOfferRestore() } } }
        // Velo BAJO el alert de restore (dueño 2026-08-15): el alert nativo es
        // translúcido y el CTA verde «Connect Apple Health» del estado vacío quedaba justo
        // detrás — sangraba a través del material como una mancha verde sobre el mensaje
        // (parecía un subrayado roto). El velo opaca el fondo solo mientras el alert vive.
        .overlay {
            if showRestoreOffer {
                LiquidColor.fondoAlto.ignoresSafeArea()
            }
        }
        // FER-116: el copy nombra lo que el respaldo ES: un archivo que el usuario exportó y guardó
        // él mismo. Cénit no tiene nube, así que hablar de «restaurar de iCloud» sonaba a que sí.
        .alert("Restore from a backup file?", isPresented: $showRestoreOffer) {
            Button("Choose a backup file…") { Task { await runRestore() } }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("There's no data on this iPhone yet. Cénit has no cloud of its own: the only thing I can restore is a backup file that you exported from Cénit and saved yourself, in iCloud Drive or wherever you keep your files. If you don't have one, there's nothing to bring back.")
        }
        // FER-837: the restore RESULT is an inline banner (the offer above stays a native alert — the
        // honest exception: it fires before the app visually exists). FER-305: piel → LiquidAviso.
        .overlay(alignment: .top) {
            if showRestoreResult {
                LiquidAviso(
                    titulo: "",
                    cuerpo: restoreMessage,
                    tono: restoreSucceeded ? LiquidColor.verdePrimario : LiquidColor.negativo
                )
                .padding(.horizontal, LiquidSpace.s400)
                .onTapGesture { showRestoreResult = false }
                .transition(LiquidMotion.fallingFadeTransition)
                .task {
                    try? await Task.sleep(for: .seconds(8))
                    showRestoreResult = false
                }
            }
        }
        .animation(LiquidMotion.fundido, value: showRestoreResult)
        #endif
        .enableInjection()   // Inject: activa la recarga en caliente para esta vista (no-op en Release)
    }

    /// The Terms gate is light «Instrumento» paper (FER-416) and sits over everything until accepted →
    /// light scheme so its status bar renders in dark ink. FER-109: the onboarding is now light too
    /// (it lives on `LiquidColor.fondoGradient`, the SAME surface as Hoy, so the last frame of its
    /// reveal can transform into the hero without the background jumping colour). Once inside the app
    /// the scheme follows the active tab: Today is light paper (dark-ink status bar), every other tab
    /// is the dark instrument panel.
    private var resolvedColorScheme: ColorScheme {
        if mostrandoEntrada { return .light }                        // la entrada es blanca (FER-41)
        if acceptedTerms != Terms.currentVersion { return .light }   // Terms gate (paper) is on top
        guard onboarded else { return .light }                       // onboarding (FER-109) es papel claro
        return isTodayTab ? .light : .dark
    }

    /// La entrada se pinta mientras no haya terminado Y no haya corrido ya en este proceso.
    /// FER-109: la entrada NO corre en el primer arranque. El onboarding es dueño exclusivo de las
    /// partículas ese día, y por dos razones: (1) a los 0 ms del primer arranque no hay veredicto que
    /// revelar, así que la ley «el orbe entra neutro y el color llega como REVELACIÓN» se quemaría en
    /// la única corrida donde no hay nada que revelar; (2) el usuario vería la misma coreografía tres
    /// veces en medio minuto (entrada → Términos → acto 1), con dos significados distintos, y eso no
    /// se lee como poesía sino como que la app se repite. La entrada se GANA: vuelve en el segundo
    /// arranque, cuando ya hay una lectura suya que revelar.
    private var mostrandoEntrada: Bool { onboarded && !entradaLista && !EntradaDeArranque.yaCorrio }

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
        //
        // FER-116: y NUNCA a quien terminó el onboarding sin conectar Apple Salud. Esa persona acaba
        // de leer «sin cuenta, sin nube, ponlo en modo avión y compruébalo» y recibir, 2.5 s después,
        // una oferta de restaurar de iCloud contradice la promesa de marca en el peor momento posible.
        // `health.auth` es la señal honesta: solo llega a `.authorized` pasando por
        // `requestAuthorization()` (el acto «permiso» del onboarding), y sobrevive al relanzamiento en
        // `appleHealthConnected`. Se re-lee DESPUÉS del await, así que quien conecte durante esos
        // 2.5 s también la recibe. El caso que justifica la oferta (reinstalar teniendo un respaldo
        // propio, conectando Salud otra vez) queda intacto; para el resto, restaurar sigue a un tap en
        // Ajustes · Datos y fuentes.
        guard !didOfferRestore, health.auth == .authorized,
              repo.fullyLoaded, repo.days.isEmpty else { return }   // re-check after the await
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
/// FER-969 (X-03) / FER-256: full-screen honest state when the SQLite store can't open (wedged
/// migration or a corrupt file). Liquid sobrio — one message, two ways out: retry in place, or
/// restore from a backup file the user exported (no cloud).
private struct StoreFailureView: View {
    let onRetry: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text(String(localized: "store.failure.title",
                        defaultValue: "Cénit couldn't open your database."))
                .font(LiquidType.displayS)
                .tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "store.failure.body",
                        defaultValue: "Your data is still on this phone. Retry, or restore from the backup file you exported."))
                .font(.system(.subheadline)) // SF15 — cuerpo de pantalla (preview)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, LiquidSpace.s300)
            VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                LiquidGlassButton(
                    String(localized: "store.failure.retry", defaultValue: "Retry"),
                    variant: .primary, expands: true, action: onRetry)
                HStack {
                    Spacer(minLength: 0)
                    LiquidGlassButton(
                        String(localized: "store.failure.restore",
                               defaultValue: "Restore from your backup…"),
                        variant: .quiet, action: onRestore)
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, LiquidSpace.s800)
            Spacer()
        }
        .padding(.horizontal, LiquidSpace.s550)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(LiquidColor.fondoGradient.ignoresSafeArea())
    }
}
#endif
