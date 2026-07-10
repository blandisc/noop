import SwiftUI
import StrandDesign

/// Root — the sidebar shell, with the first-run onboarding/pairing wizard overlaid until complete,
/// and a "What's New" changelog sheet shown automatically after an update.
struct ContentView: View {
    @AppStorage("noop.onboarded") private var onboarded = false
    @AppStorage("noop.lastSeenChangelogVersion") private var lastSeenChangelog = ""
    @AppStorage("noop.acceptedTermsVersion") private var acceptedTerms = ""
    @State private var showWhatsNew = false
    /// Whether Today is the active tab (RootTabView keeps this in sync). Drives the app's color scheme
    /// so the status bar is dark on Today's light paper and light on the dark instrument tabs.
    @State private var isTodayTab = true

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
            // Terms acknowledgment gate — over EVERYTHING (before onboarding/pairing/Bluetooth) until
            // the current terms version is accepted; re-appears if the terms materially change.
            if acceptedTerms != Terms.currentVersion {
                TermsGateView(onAccept: { acceptedTerms = Terms.currentVersion })
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: onboarded)
        .animation(.easeInOut(duration: 0.35), value: acceptedTerms)
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
            Text("It looks like there's no data on this device. If you've used Cénit before — on this phone or another — restore your strap history and settings from an iCloud Drive backup.")
        }
        // FER-837: the restore RESULT is an inline banner (the offer above stays a native alert — the
        // honest exception: it fires before the app visually exists).
        .overlay(alignment: .top) {
            if showRestoreResult {
                let theme = InstrumentoTheme.base
                Text(restoreMessage)
                    .font(.system(size: 13))
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
    }

    /// The Terms gate is light «Instrumento» paper (FER-416) and sits over everything until accepted →
    /// light scheme so its status bar renders in dark ink. The onboarding wizard is still dark. Once
    /// inside the app the scheme follows the active tab: Today is light paper (dark-ink status bar),
    /// every other tab is the dark instrument panel.
    private var resolvedColorScheme: ColorScheme {
        if acceptedTerms != Terms.currentVersion { return .light }   // Terms gate (paper) is on top
        guard onboarded else { return .dark }                        // onboarding wizard is still dark
        return isTodayTab ? .light : .dark
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
