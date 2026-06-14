import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import WhoopStore
#if os(iOS)
import HealthKit   // HKAuthorizationStatus, for the write-back permission tally
import UIKit       // UIApplication.openSettingsURLString
#endif

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
    /// iOS-only: connect + drive the live two-way Apple Health sync, and surface what it did. Beyond
    /// the connect/sync control it now shows live per-stage progress, a coverage summary (days +
    /// span), a per-metric "what landed" list, and a Settings deep-link — so the import stops being a
    /// silent background task the user can't reason about. (FER-70)
    @ViewBuilder
    private var appleHealthLiveCard: some View {
        card(title: "Apple Health — Live Sync", icon: "heart.text.square.fill",
             subtitle: "Sync the last few weeks two-way, on-device: NOOP reads your Apple Health HR, HRV, sleep, SpO₂ and steps, and writes its own strap-derived metrics back. Strictly opt-in — nothing leaves your iPhone. (For a one-time bulk history, use the export import above.)") {
            switch health.auth {
            case .unavailable:
                Text(verbatim: "Apple Health isn’t available on this device.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
            case .authorized:
                appleHealthAuthorizedBody
            case .unknown, .denied:
                appleHealthConnectBody
            }
            if let err = health.lastError {
                Text(verbatim: err)
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
            }
        }
        // Load coverage + write permissions on appear so opening the screen shows "X days imported"
        // and the per-metric list without forcing a re-import first.
        .task { await health.refreshStatus() }
    }

    /// Authorized: the sync/reimport control, then either live progress (mid-sync) or the coverage
    /// summary + per-metric status of what has been imported.
    @ViewBuilder
    private var appleHealthAuthorizedBody: some View {
        Button {
            Task { await health.sync() }
        } label: {
            Label(health.syncing ? "Syncing…" : "Sync now",
                  systemImage: "arrow.triangle.2.circlepath").padding(.horizontal, 6)
        }
        .buttonStyle(.borderedProminent).tint(StrandPalette.accent)
        .disabled(health.syncing)

        if health.syncing {
            appleHealthSyncProgress
        } else {
            appleHealthCoverageSection
            appleHealthMetricList
            if let at = health.lastSync {
                Text(verbatim: "Last synced \(at.formatted(.relative(presentation: .named)))")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        appleHealthPermissionsFooter
    }

    /// Not connected yet (or declined): the connect button, plus a Settings path when declined.
    @ViewBuilder
    private var appleHealthConnectBody: some View {
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
            settingsButton
        }
    }

    /// Live, per-stage progress while `sync` runs: a pulsing pill plus "Importing HRV… · 4/12", so a
    /// long pull reads as in-progress rather than frozen.
    @ViewBuilder
    private var appleHealthSyncProgress: some View {
        HStack(spacing: 10) {
            StatePill("Importing Apple Health…", tone: .accent, pulsing: true)
            if let p = health.syncProgress {
                Text(verbatim: "\(Self.stageLabel(p.stageKey)) · \(p.done)/\(p.total)")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    /// "Imported history" coverage summary (days + date span), or a nudge when nothing has landed.
    @ViewBuilder
    private var appleHealthCoverageSection: some View {
        if let cov = health.coverage, cov.totalDays > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Imported history").strandOverline()
                    .foregroundStyle(StrandPalette.textTertiary)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13)).foregroundStyle(StrandPalette.statusPositive)
                    Text(verbatim: Self.coverageSummaryText(cov))
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        } else {
            Text("No Apple Health data imported yet — tap Sync now to pull your recent history.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
    }

    /// Per-metric "what landed" list: ✓ + day count for metrics that imported, a dimmed — for those
    /// that didn't (no data, or a read scope the user didn't grant — HealthKit hides which, so we show
    /// the honest observable: whether days arrived).
    @ViewBuilder
    private var appleHealthMetricList: some View {
        let cov = health.coverage
        VStack(spacing: 0) {
            ForEach(Self.metricRows, id: \.key) { row in
                let days = cov?.daysByMetric[row.key]
                let has = days != nil
                HStack(spacing: 8) {
                    Image(systemName: has ? "checkmark.circle.fill" : "minus.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(has ? StrandPalette.statusPositive : StrandPalette.textTertiary)
                    Text(row.label)
                        .font(StrandFont.subhead)
                        .foregroundStyle(has ? StrandPalette.textSecondary : StrandPalette.textTertiary)
                    Spacer()
                    Text(verbatim: has ? "\(days!) d" : "—")
                        .font(StrandFont.footnote).monospacedDigit()
                        .foregroundStyle(has ? StrandPalette.textSecondary : StrandPalette.textTertiary)
                }
                .padding(.vertical, 5)
            }
        }
    }

    /// Permissions affordance: a one-line write-back tally (the status HealthKit *does* expose
    /// reliably) plus a deep link to Settings to grant any missing scope, then Sync again.
    @ViewBuilder
    private var appleHealthPermissionsFooter: some View {
        let writes = health.writePermissions
        VStack(alignment: .leading, spacing: 6) {
            if !writes.isEmpty {
                let granted = writes.filter { $0.status == .sharingAuthorized }.count
                Text("Write-back to Apple Health: \(granted)/\(writes.count) enabled")
            }
            settingsButton
        }
        .font(StrandFont.footnote)
        .foregroundStyle(StrandPalette.textTertiary)
    }

    private var settingsButton: some View {
        Button { openSystemSettings() } label: {
            Label("Manage Apple Health permissions", systemImage: "gearshape")
                .font(StrandFont.footnote)
        }
        .buttonStyle(.plain)
        .foregroundStyle(StrandPalette.accent)
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Stage key → localized label for the live progress line. Keys come from `HealthKitBridge`.
    private static func stageLabel(_ key: String) -> String {
        switch key {
        case "resting_hr":                return String(localized: "Resting heart rate")
        case "avg_hr", "max_hr":          return String(localized: "Heart rate")
        case "hrv":                       return String(localized: "HRV")
        case "spo2":                      return String(localized: "Blood oxygen")
        case "resp_rate":                 return String(localized: "Respiration")
        case "steps":                     return String(localized: "Steps")
        case "active_kcal", "basal_kcal": return String(localized: "Energy")
        case "vo2max":                    return String(localized: "VO₂ max")
        case "sleep":                     return String(localized: "Sleep")
        case "workouts":                  return String(localized: "Workouts")
        case "saving":                    return String(localized: "Saving…")
        default:                          return String(localized: "Apple Health")
        }
    }

    /// Metrics shown in the per-metric status list, in display order. Keys match
    /// `AppleHealthCoverage.daysByMetric`.
    private static let metricRows: [(key: String, label: LocalizedStringKey)] = [
        ("hrv", "HRV"),
        ("asleep_min", "Sleep"),
        ("resting_hr", "Resting HR"),
        ("spo2", "Blood Oxygen"),
        ("resp_rate", "Respiration"),
        ("steps", "Steps"),
        ("active_kcal", "Active Energy"),
        ("vo2max", "VO₂ Max"),
    ]

    // Coverage span is stored as "yyyy-MM-dd" (UTC); parse with a fixed parser, display in the user's
    // locale ("12 May" / "12 may").
    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let shortDate: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("dMMM"); return f
    }()
    private static func coverageSummaryText(_ cov: AppleHealthCoverage) -> String {
        guard let fs = cov.firstDay, let ls = cov.lastDay,
              let f = dayParser.date(from: fs), let l = dayParser.date(from: ls) else {
            return "\(cov.totalDays) d"
        }
        return "\(shortDate.string(from: f)) → \(shortDate.string(from: l)) · \(cov.totalDays) d"
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
