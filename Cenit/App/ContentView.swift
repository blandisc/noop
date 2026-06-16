import SwiftUI

/// Root — the sidebar shell, with the first-run onboarding/pairing wizard overlaid until complete,
/// and a "What's New" changelog sheet shown automatically after an update.
struct ContentView: View {
    @AppStorage("noop.onboarded") private var onboarded = false
    @AppStorage("noop.lastSeenChangelogVersion") private var lastSeenChangelog = ""
    @AppStorage("noop.acceptedTermsVersion") private var acceptedTerms = ""
    @State private var showWhatsNew = false

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
    #endif

    var body: some View {
        ZStack {
            RootTabView()
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
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(onClose: {
                lastSeenChangelog = AppChangelog.currentVersion
                showWhatsNew = false
            })
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
        .alert("Restore", isPresented: $showRestoreResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(restoreMessage)
        }
        #endif
    }

    #if os(iOS)
    @MainActor private func maybeOfferRestore() async {
        guard onboarded, !didOfferRestore else { return }
        try? await Task.sleep(nanoseconds: 2_500_000_000)   // let the launch refresh populate first
        guard !didOfferRestore, repo.days.isEmpty else { return }   // re-check after the await
        didOfferRestore = true
        showRestoreOffer = true
    }

    @MainActor private func runRestore() async {
        switch await DataBackup.runImport() {
        case .imported:
            restoreMessage = String(localized: "Your data has been restored. Reopen Cénit for it to take effect.")
            showRestoreResult = true
        case .failure(let message):
            restoreMessage = message
            showRestoreResult = true
        case .cancelled, .exported:
            break
        }
    }
    #endif
}
