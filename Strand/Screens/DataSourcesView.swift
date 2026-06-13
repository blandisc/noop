import SwiftUI
import UniformTypeIdentifiers
import StrandDesign

struct DataSourcesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState
    @State private var showingImporter = false
    @State private var importTarget: ImportTarget = .whoop
    #if os(iOS)
    // Live two-way Apple Health (iOS only — macOS has no HealthKit). Injected by StrandiOSApp.
    @EnvironmentObject private var health: HealthKitBridge
    @State private var hkBusy = false
    #endif

    var body: some View {
        ScreenScaffold(title: "Data Sources",
                       subtitle: "Everything stays on this Mac. Bring your history in once, then it's yours.") {
            whoopCard
            appleHealthCard
            #if os(iOS)
            appleHealthLiveCard
            #endif
            liveCard
        }
        // A single target-aware importer avoids SwiftUI collapsing competing importers on the same screen.
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: importTarget.allowedContentTypes,
                      allowsMultipleSelection: false) { result in
            handleImportResult(result, for: importTarget)
        }
    }

    private var whoopCard: some View {
        card(title: "WHOOP Export", icon: "square.and.arrow.down.fill",
             subtitle: "Import your full WHOOP history — recovery, strain, sleep, workouts — from a data export (.zip). Works for WHOOP 4.0, 5.0 and MG. Get one at app.whoop.com → Data Management.") {
            let importingWhoop = model.isImporting(.whoop)
            HStack(spacing: 12) {
                Button {
                    presentImporter(.whoop)
                } label: {
                    Label(importingWhoop ? "Importing…" : "Choose export…",
                          systemImage: "tray.and.arrow.down")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .disabled(model.hasActiveImport)
                if importingWhoop { ProgressView().controlSize(.small) }
            }
            if let s = model.whoopImportSummary {
                Text(s).font(StrandFont.subhead)
                    .foregroundStyle(model.whoopImportFailed ? StrandPalette.statusWarning : StrandPalette.statusPositive)
            }
            Text("\(repo.days.count) days · \(repo.sleeps.count) sleeps stored")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private var appleHealthCard: some View {
        card(title: "Apple Health", icon: "heart.fill",
             subtitle: "Import an Apple Health export (Health app → profile → Export All Health Data → export.zip). 7 years of HR, HRV, sleep, SpO₂, steps and more — streamed locally. Large exports take a minute or two.") {
            let importingAppleHealth = model.isImporting(.appleHealth)
            HStack(spacing: 12) {
                Button { presentImporter(.appleHealth) } label: {
                    Label(importingAppleHealth ? "Working…" : "Choose export.zip…", systemImage: "tray.and.arrow.down")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent).tint(StrandPalette.accent)
                .disabled(model.hasActiveImport)
                if importingAppleHealth {
                    ProgressView().controlSize(.small)
                    if let n = model.appleHealthImportProgress {
                        Text("\(n) records").font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .monospacedDigit()
                    }
                }
            }
            if let s = model.appleHealthImportSummary {
                Text(s).font(StrandFont.subhead)
                    .foregroundStyle(model.appleHealthImportFailed ? StrandPalette.statusWarning : StrandPalette.statusPositive)
            }
        }
    }

    #if os(iOS)
    /// iOS-only: connect + drive the live two-way Apple Health sync. Authorization is requested HERE,
    /// from an explicit user tap with rationale shown first (HIG: never prompt cold at launch) — until
    /// this exists the `HealthKitBridge` was fully built but unreachable, so HealthKit sync was dead.
    @ViewBuilder
    private var appleHealthLiveCard: some View {
        card(title: "Apple Health — Live Sync", icon: "heart.text.square.fill",
             subtitle: "Sync the last few weeks two-way, on-device: NOOP reads your Apple Health HR, HRV, sleep, SpO₂ and steps, and writes its own strap-derived metrics back. Strictly opt-in — nothing leaves your iPhone. (For a one-time bulk history, use the export import above.)") {
            switch health.auth {
            case .unavailable:
                Text(verbatim: "Apple Health isn’t available on this device.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
            case .authorized:
                HStack(spacing: 12) {
                    Button {
                        Task { await health.sync() }
                    } label: {
                        Label(health.syncing ? "Syncing…" : "Sync now",
                              systemImage: "arrow.triangle.2.circlepath").padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(StrandPalette.accent)
                    .disabled(health.syncing)
                    if health.syncing { ProgressView().controlSize(.small) }
                }
                if let at = health.lastSync {
                    Text(verbatim: "Last synced \(at.formatted(.relative(presentation: .named)))")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                } else {
                    Text(verbatim: "Connected.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusPositive)
                }
            case .unknown, .denied:
                HStack(spacing: 12) {
                    Button {
                        Task {
                            hkBusy = true
                            await health.requestAuthorization()
                            if health.auth == .authorized { await health.sync() }
                            hkBusy = false
                        }
                    } label: {
                        Label(hkBusy ? "Connecting…" : "Connect Apple Health",
                              systemImage: "heart.fill").padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(StrandPalette.accent)
                    .disabled(hkBusy)
                    if hkBusy { ProgressView().controlSize(.small) }
                }
                if health.auth == .denied {
                    Text(verbatim: "Apple Health access was declined. Enable it in Settings › Privacy & Security › Health › NOOP.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
                }
            }
            if let err = health.lastError {
                Text(verbatim: err)
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
            }
        }
    }
    #endif

    private func presentImporter(_ target: ImportTarget) {
        importTarget = target
        showingImporter = true
    }

    private func handleImportResult(_ result: Result<[URL], Error>, for target: ImportTarget) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        switch target {
        case .whoop:
            model.importWhoop(url: url)
        case .appleHealth:
            model.importAppleHealth(url: url)
        }
    }

    private enum ImportTarget {
        case whoop
        case appleHealth

        var allowedContentTypes: [UTType] {
            switch self {
            case .whoop:
                return [.zip, .folder]
            case .appleHealth:
                return [.zip, .xml, .folder]
            }
        }
    }
    private var liveCard: some View {
        card(title: "WHOOP Strap (Live BLE)", icon: "antenna.radiowaves.left.and.right",
             subtitle: "Pairs directly with your strap over Bluetooth — no WHOOP app, no cloud.") {
            HStack(spacing: 8) {
                // Three-state, consistent with the Live screen's connection pill — a connected-but-
                // not-yet-streaming strap (e.g. an experimental WHOOP 5/MG link) no longer reads as
                // "Not connected" on one screen and "Connected" on another (issue #8).
                let (dot, label): (Color, String) =
                    live.bonded ? (StrandPalette.statusPositive, "Bonded — streaming.")
                    : live.connected ? (StrandPalette.statusWarning, "Connected.")
                    : (StrandPalette.statusCritical, "Not connected — open Live to pair.")
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func card<C: View>(title: String, icon: String, subtitle: String,
                              @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(StrandPalette.accent)
                Text(title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
            }
            Text(subtitle).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(StrandPalette.hairline))
    }
}
