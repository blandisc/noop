import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import WhoopStore
#if os(iOS)
import HealthKit   // HKAuthorizationStatus, for the write-back permission tally
import UIKit       // UIApplication.openSettingsURLString
#endif

// MARK: - Datos y fuentes — light «Instrumento diurno» (FER-338)
//
// Reskin of the legacy dark Data Sources screen to the warm-paper language: hierarchy by space +
// hairlines (no card-in-card), quiet uppercase overlines in tertiary ink, color ONLY on a measured
// datum (a sync verdict, a coverage cell, an import-result line), chrome stays ink. Behavior is
// IDENTICAL to the dark version — same importers, same Apple Health live sync, same FER-83 band
// diagnostic, same backup/restore + iCloud auto-backup, same `#if os(iOS)` guards.
//
// The screen builds its own header (no `ScreenScaffold`: the app module's local dark `ScreenScaffold`
// wins name resolution, and `StrandDesign` can't be module-qualified — it's also a type), reads the
// resolved theme from the environment, and groups the existing cards into five sections by space:
// Importar · Apple Health · Sincronización de la banda · Cobertura · Respaldo. The per-source Apple
// Health viewer is reached via a `NavigationLink` (the screen is presented inside a NavigationStack).

struct DataSourcesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState
    @Environment(\.instrumentoTheme) private var theme
    @State private var showingImporter = false
    @State private var importTarget: ImportTarget = .whoop
    #if os(iOS)
    // Live two-way Apple Health. Injected by CenitApp.
    @EnvironmentObject private var health: HealthKitBridge
    @State private var hkBusy = false
    /// Opt-in mirror of finished strength sessions into Apple Health (FER-390). Off by default.
    @AppStorage(HealthKitBridge.saveStrengthWorkoutsKey) private var saveStrengthWorkouts = false
    #endif

    // Backup & restore + automatic iCloud backup — migrated here from SettingsView for FER-337 so no
    // content is orphaned when the old Settings screen goes away.
    @State private var backupBusy = false
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var showBackupAlert = false
    #if os(iOS)
    @EnvironmentObject private var autoBackup: AutoBackup
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sources").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text("Data Sources").font(StrandFont.title1).foregroundStyle(theme.ink)
                    Text("Everything stays on this iPhone. Bring your history in once, then it's yours.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                importSection
                appleHealthSection
                bandSyncSection
                #if os(iOS)
                coverageSection
                backupSection
                #endif
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        // A single target-aware importer avoids SwiftUI collapsing competing importers on the same screen.
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: importTarget.allowedContentTypes,
                      allowsMultipleSelection: false) { result in
            handleImportResult(result, for: importTarget)
        }
        .alert(backupAlertTitle, isPresented: $showBackupAlert) {
            Button("OK", role: .cancel) { }
        } message: { Text(backupAlertMessage) }
    }

    // MARK: - Section scaffolding (overline + content on paper, no card-in-card)

    @ViewBuilder
    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }

    /// A quiet inline block within a section: a title line + supporting copy, separated from siblings
    /// by space (and the caller's hairline). No surface, no border — the language groups by whitespace.
    @ViewBuilder
    private func block<Content: View>(_ title: LocalizedStringKey, subtitle: LocalizedStringKey,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(StrandFont.headline).foregroundStyle(theme.ink)
            Text(subtitle).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    private var divider: some View { Divider().overlay(theme.hairline) }

    // MARK: - Importar (WHOOP .zip + Apple Health .zip)

    private var importSection: some View {
        section("Import") {
            whoopBlock
            divider
            appleHealthImportBlock
        }
    }

    private var whoopBlock: some View {
        block("WHOOP Export",
              subtitle: "Import your full WHOOP history — recovery, strain, sleep, workouts — from a data export (.zip). Works for WHOOP 4.0, 5.0 and MG. Get one at app.whoop.com → Data Management.") {
            let importingWhoop = model.isImporting(.whoop)
            HStack(spacing: 12) {
                QuietButton(importingWhoop ? "Importing…" : "Choose export…") { presentImporter(.whoop) }
                    .disabled(model.hasActiveImport)
                if importingWhoop { ProgressView().controlSize(.small).tint(theme.inkSecondary) }
                Spacer(minLength: 0)
            }
            if let s = model.whoopImportSummary {
                Text(verbatim: s).font(StrandFont.subhead)
                    .foregroundStyle(model.whoopImportFailed ? theme.warning : theme.verdict)
            }
            Text("\(repo.days.count) days · \(repo.sleeps.count) sleeps stored")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
    }

    private var appleHealthImportBlock: some View {
        block("Apple Health Export",
              subtitle: "Import an Apple Health export (Health app → profile → Export All Health Data → export.zip). 7 years of HR, HRV, sleep, SpO₂, steps and more — streamed locally. Large exports take a minute or two.") {
            let importingAppleHealth = model.isImporting(.appleHealth)
            HStack(spacing: 12) {
                QuietButton(importingAppleHealth ? "Working…" : "Choose export.zip…") { presentImporter(.appleHealth) }
                    .disabled(model.hasActiveImport)
                if importingAppleHealth {
                    ProgressView().controlSize(.small).tint(theme.inkSecondary)
                    if let n = model.appleHealthImportProgress {
                        Text("\(n) records").font(StrandFont.footnote)
                            .foregroundStyle(theme.inkTertiary)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            if let s = model.appleHealthImportSummary {
                Text(verbatim: s).font(StrandFont.subhead)
                    .foregroundStyle(model.appleHealthImportFailed ? theme.warning : theme.verdict)
            }
            // FER-115: coverage grid — macOS only (iOS shows it in its own «Cobertura» section)
            #if !os(iOS)
            if !repo.days.isEmpty || !repo.appleHealthDays.isEmpty {
                divider
                coverageBodyView
            }
            #endif
        }
    }

    // MARK: - Apple Health (live sync + permissions + "View imported data")

    private var appleHealthSection: some View {
        #if os(iOS)
        section("Apple Health") { appleHealthLiveBody }
        #else
        EmptyView()
        #endif
    }

    #if os(iOS)
    /// iOS-only: connect + drive the live two-way Apple Health sync, and surface what it did. Beyond
    /// the connect/sync control it shows live per-stage progress, a coverage summary (days + span), a
    /// per-metric "what landed" list, a Settings deep-link, and the link to the per-source viewer. (FER-70)
    @ViewBuilder
    private var appleHealthLiveBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sync the last few weeks two-way, on-device: Cénit reads your Apple Health HR, HRV, sleep, SpO₂ and steps, and writes its own strap-derived metrics back. Strictly opt-in — nothing leaves your iPhone. (For a one-time bulk history, use the export import above.)")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            switch health.auth {
            case .unavailable:
                Text(verbatim: "Apple Health isn’t available on this device.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            case .authorized:
                appleHealthAuthorizedBody
            case .unknown, .denied:
                appleHealthConnectBody
            }
            if let err = health.lastError {
                Text(verbatim: err)
                    .font(StrandFont.footnote).foregroundStyle(theme.warning)
            }

            divider
            strengthWorkoutToggle

            // Reachability for the per-source Apple Health viewer. Pushed within this screen's
            // NavigationStack — «Ver datos importados ›».
            divider
            NavigationLink { AppleHealthView() } label: {
                HStack(spacing: 12) {
                    Text("View imported data").font(StrandFont.body).foregroundStyle(theme.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        // Load coverage + write permissions on appear so opening the screen shows "X days imported"
        // and the per-metric list without forcing a re-import first.
        .task { await health.refreshStatus() }
    }

    /// Opt-in: write finished strength sessions to Apple Health as workouts so they show in Health /
    /// Fitness and (via estimated active energy) count toward the iPhone's Move ring — no Apple Watch
    /// needed (FER-390). Off by default; flipping it on requests only the workout + active-energy
    /// share, independent of the main sync connection above.
    @ViewBuilder
    private var strengthWorkoutToggle: some View {
        Toggle(isOn: $saveStrengthWorkouts) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Save workouts to Apple Health")
                    .font(StrandFont.body).foregroundStyle(theme.ink)
                Text("Your strength sessions appear in Health and count toward your Move ring, with estimated calories.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.instrumento)
        .disabled(health.auth == .unavailable)
        .onChange(of: saveStrengthWorkouts) { _, on in
            if on { Task { await health.requestWorkoutShareAuthorization() } }
        }
    }

    /// Authorized: the sync/reimport control, then either live progress (mid-sync) or the coverage
    /// summary + per-metric status of what has been imported.
    @ViewBuilder
    private var appleHealthAuthorizedBody: some View {
        HStack(spacing: 12) {
            QuietButton(health.syncing ? "Syncing…" : "Sync now") { Task { await health.sync() } }
                .disabled(health.syncing)
            Spacer(minLength: 0)
        }

        if health.syncing {
            appleHealthSyncProgress
        } else {
            appleHealthCoverageSection
            appleHealthMetricList
            if let at = health.lastSync {
                Text(verbatim: "Last synced \(at.formatted(.relative(presentation: .named)))")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
        }
        appleHealthPermissionsFooter
    }

    /// Not connected yet (or declined): the connect button, plus a Settings path when declined.
    @ViewBuilder
    private var appleHealthConnectBody: some View {
        HStack(spacing: 12) {
            QuietButton(hkBusy ? "Connecting…" : "Connect Apple Health") {
                Task {
                    hkBusy = true
                    await health.requestAuthorization()
                    if health.auth == .authorized { await health.sync() }
                    hkBusy = false
                }
            }
            .disabled(hkBusy)
            if hkBusy { ProgressView().controlSize(.small).tint(theme.inkSecondary) }
            Spacer(minLength: 0)
        }
        if health.auth == .denied {
            Text(verbatim: "Apple Health access was declined. Enable it in Settings › Privacy & Security › Health › Cénit.")
                .font(StrandFont.footnote).foregroundStyle(theme.warning)
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
                    .foregroundStyle(theme.inkSecondary)
                    .monospacedDigit()
            }
        }
    }

    /// "Imported history" coverage summary (days + date span), or a nudge when nothing has landed.
    @ViewBuilder
    private var appleHealthCoverageSection: some View {
        if let cov = health.coverage, cov.totalDays > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Imported history").instrumentoOverline()
                    .foregroundStyle(theme.inkTertiary)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13)).foregroundStyle(theme.verdict)
                    Text(verbatim: Self.coverageSummaryText(cov))
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
            }
        } else {
            Text("No Apple Health data imported yet — tap Sync now to pull your recent history.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
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
                        .foregroundStyle(has ? theme.verdict : theme.inkTertiary)
                    Text(row.label)
                        .font(StrandFont.subhead)
                        .foregroundStyle(has ? theme.inkSecondary : theme.inkTertiary)
                    Spacer()
                    Text(verbatim: has ? "\(days!) d" : "—")
                        .font(StrandFont.footnote).monospacedDigit()
                        .foregroundStyle(has ? theme.inkSecondary : theme.inkTertiary)
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
        .foregroundStyle(theme.inkTertiary)
    }

    private var settingsButton: some View {
        Button { openSystemSettings() } label: {
            Label("Manage Apple Health permissions", systemImage: "gearshape")
                .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
        }
        .buttonStyle(.plain)
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

    // Coverage span is stored as "yyyy-MM-dd" (UTC); parse with the shared parser, display in the user's
    // locale ("12 May" / "12 may").
    private static let shortDate: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("dMMM"); return f
    }()
    private static func coverageSummaryText(_ cov: AppleHealthCoverage) -> String {
        guard let fs = cov.firstDay, let ls = cov.lastDay,
              let f = Repository.parseDayKey(fs), let l = Repository.parseDayKey(ls) else {
            return "\(cov.totalDays) d"
        }
        return "\(shortDate.string(from: f)) → \(shortDate.string(from: l)) · \(cov.totalDays) d"
    }
    #endif

    // MARK: - Sincronización de la banda (FER-83 diagnostic)

    private var bandSyncSection: some View {
        section("WHOOP Strap") {
            // Three-state, consistent with the Live screen's connection pill — a connected-but-not-yet-
            // streaming strap (e.g. an experimental WHOOP 5/MG link) no longer reads as "Not connected"
            // on one screen and "Connected" on another (issue #8). Color rides the status datum (the dot
            // + label); the supporting copy stays ink.
            let (dot, label): (Color, LocalizedStringKey) =
                live.bonded ? (theme.verdict, "Bonded — streaming.")
                : live.connected ? (theme.warning, "Connected.")
                : (theme.critical, "Not connected — open Live to pair.")
            HStack(spacing: 10) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(label).font(StrandFont.subhead).foregroundStyle(dot)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            Text("Pairs directly with your strap over Bluetooth — no WHOOP app, no cloud.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            divider
            strapSyncDiagnostic
        }
    }

    /// Sync diagnostic (FER-83): honest, read-only evidence that the band captured data and that NOOP
    /// is receiving, decoding and storing it. Informs only — the one action is "Sync now" (a single
    /// safe, reversible offload). State-driven: connect prompt / pairing prompt / live progress /
    /// result (band range + per-sensor receipt + verdict) / error.
    @ViewBuilder
    private var strapSyncDiagnostic: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sync diagnostic").instrumentoOverline()
                .foregroundStyle(theme.inkTertiary)

            if !live.connected {
                Text("Connect your strap to run the sync diagnostic.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            } else if !live.encryptedBond {
                Text("Complete secure pairing first — the strap won’t offload its history until the encrypted bond is set.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            } else {
                strapRangeRow
                syncNowButton
                if live.backfilling {
                    syncProgressRow
                } else if let err = live.lastSyncError {
                    Text(verbatim: err)
                        .font(StrandFont.footnote).foregroundStyle(theme.warning)
                } else if live.syncCompletedThisSession {
                    syncReceiptList
                    syncVerdictRow
                }
            }
        }
    }

    /// "On the band" — the strap's own retained-history window (proof the sensor captured + still holds
    /// it). "—" until a GET_DATA_RANGE response has been seen.
    @ViewBuilder
    private var strapRangeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
            Text("On the band:").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            if let oldest = live.strapHistoryOldest, let newest = live.strapHistoryNewest {
                Text(verbatim: "\(Self.dayFormatter.string(from: Date(timeIntervalSince1970: oldest))) → \(Self.dayFormatter.string(from: Date(timeIntervalSince1970: newest)))")
                    .font(StrandFont.footnote).monospacedDigit()
                    .foregroundStyle(theme.inkSecondary)
            } else {
                Text(verbatim: "—").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
        }
    }

    private var syncNowButton: some View {
        HStack(spacing: 12) {
            QuietButton(live.backfilling ? "Syncing…" : "Sync now") { model.ble.syncNow() }
                .disabled(live.backfilling)
            Spacer(minLength: 0)
        }
    }

    /// Live offload progress — a pulsing pill plus the running chunk count (the only honest progress
    /// signal; the protocol never reveals the total pending, so a count, never a percent).
    private var syncProgressRow: some View {
        HStack(spacing: 10) {
            StatePill("Syncing strap history…", tone: .accent, pulsing: true)
            Text("\(live.syncChunksThisSession) pieces")
                .font(StrandFont.footnote).monospacedDigit()
                .foregroundStyle(theme.inkSecondary)
        }
    }

    /// "Received this sync" — rows that decoded and landed, per sensor. The honest data receipt
    /// (counts from StreamStore.insert, accumulated over the offload session).
    @ViewBuilder
    private var syncReceiptList: some View {
        let r = live.syncReceipt
        VStack(alignment: .leading, spacing: 4) {
            Text("Received this sync").instrumentoOverline()
                .foregroundStyle(theme.inkTertiary)
            VStack(spacing: 0) {
                ForEach(Self.syncSensorRows(r), id: \.key) { row in
                    HStack(spacing: 8) {
                        Image(systemName: row.count > 0 ? "checkmark.circle.fill" : "minus.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(row.count > 0 ? theme.verdict : theme.inkTertiary)
                        Text(LocalizedStringKey(row.key)).font(StrandFont.subhead)
                            .foregroundStyle(row.count > 0 ? theme.inkSecondary : theme.inkTertiary)
                        Spacer()
                        Text(verbatim: row.count > 0 ? "\(row.count)" : "—")
                            .font(StrandFont.footnote).monospacedDigit()
                            .foregroundStyle(row.count > 0 ? theme.inkSecondary : theme.inkTertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    /// The honest verdict, derived purely from what the offload session observed plus whether the band
    /// reported a stored-history window. Branching lives in `LiveState.SyncVerdict.decide` (testable).
    @ViewBuilder
    private var syncVerdictRow: some View {
        // The "On the band" window shows only when both markers are present — same signal here: a
        // plausible GET_DATA_RANGE window means the band holds history, so a console-logs-only offload
        // is a decode failure, not a lost clock (FER-152).
        let reportsStoredHistory = live.strapHistoryOldest != nil && live.strapHistoryNewest != nil
        let verdict = LiveState.SyncVerdict.decide(live.syncReceipt, reportsStoredHistory: reportsStoredHistory)
        let (icon, text, tint): (String, LocalizedStringKey, Color) = {
            switch verdict {
            case .nothingNew:
                return ("circle", "The band has nothing new.", theme.inkSecondary)
            case .notStoringClock:
                return ("clock.badge.exclamationmark.fill", "The band lost its clock and isn’t saving. Cénit is re-setting it — keep it connected. If it doesn’t recover, run it through the WHOOP app.", theme.warning)
            case .arrivesButNoDecode:
                return ("exclamationmark.triangle.fill", "Data arrives but doesn’t decode — please report.", theme.warning)
            case .receivingAndStoring:
                return ("checkmark.seal.fill", "Receiving and storing everything.", theme.verdict)
            }
        }()
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
            Text(text).font(StrandFont.subhead).foregroundStyle(tint)
        }
    }

    /// The six sensor streams the receipt reports, paired with their (localizable) English label keys
    /// — `key` doubles as the stable ForEach id and the LocalizedStringKey lookup (FER-83).
    private static func syncSensorRows(_ r: LiveState.SyncReceipt) -> [(key: String, count: Int)] {
        [("Heart rate", r.hr), ("R-R", r.rr), ("Blood oxygen", r.spo2),
         ("Temperature", r.skinTemp), ("Respiration", r.resp), ("Movement", r.gravity)]
    }

    /// Medium-date formatter for the band's retained-history window (FER-83).
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    // MARK: - Cobertura (30-day grid + sources summary) — iOS

    #if os(iOS)
    @ViewBuilder
    private var coverageSection: some View {
        // Hide the whole section when there's nothing to show: no strap days, and Apple Health is
        // denied/unavailable or has imported nothing (mirrors the dark screen's guards).
        let healthAccessible = health.auth != .denied && health.auth != .unavailable
        let showsCoverage = !repo.days.isEmpty || (!repo.appleHealthDays.isEmpty && healthAccessible)
        if showsCoverage || sourcesHasContent {
            section("Coverage") {
                if showsCoverage {
                    coverageBodyView
                }
                if showsCoverage && sourcesHasContent { divider }
                if sourcesHasContent {
                    sourcesSummary
                }
            }
        }
    }
    #endif

    /// Overline + summary line + 6×5 grid + legend. (The leading section overline replaces the dark
    /// card's own overline, so this body opens straight on the summary line.)
    @ViewBuilder
    private var coverageBodyView: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days30: [String] = (0..<30).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { Repository.localDayKey($0) }
        }
        let allDayKeys = Set(repo.days.map(\.day))
        let whoopCount = days30.filter { allDayKeys.contains($0) && !repo.appleHealthDays.contains($0) }.count
        let appleCount = days30.filter { repo.appleHealthDays.contains($0) }.count
        let emptyCount  = 30 - whoopCount - appleCount
        VStack(alignment: .leading, spacing: 8) {
            Text(coverageSummaryString(whoop: whoopCount, apple: appleCount))
                .font(StrandFont.subhead)
                .foregroundStyle(whoopCount + appleCount > 0 ? theme.inkSecondary : theme.inkTertiary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(Array(days30.enumerated()), id: \.offset) { _, day in
                    let isWhoop = allDayKeys.contains(day) && !repo.appleHealthDays.contains(day)
                    let isApple = repo.appleHealthDays.contains(day)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isWhoop ? theme.dataRecovery
                              : isApple ? theme.dataSpO2
                              : theme.hairlineStrong)
                        .frame(height: 30)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(coverageA11yLabel(whoop: whoopCount, apple: appleCount, empty: emptyCount))
            coverageLegendView(hasWhoop: whoopCount > 0, hasApple: appleCount > 0)
        }
    }

    private func coverageSummaryString(whoop: Int, apple: Int) -> String {
        let total = whoop + apple
        if total == 0 { return String(localized: "No data in the last 30 days") }
        if apple == 0 { return String(localized: "\(total) of 30 days from your WHOOP strap") }
        if whoop == 0 { return String(localized: "\(total) of 30 days · Apple Health only") }
        return String(localized: "\(total) of 30 days · \(whoop) from the strap, \(apple) Apple Health only")
    }

    private func coverageA11yLabel(whoop: Int, apple: Int, empty: Int) -> String {
        let total = whoop + apple
        return String(localized: "Data coverage for the last 30 days: \(total) days with data. \(whoop) days from the WHOOP strap, \(apple) days Apple Health only, \(empty) days with no data.")
    }

    @ViewBuilder
    private func coverageLegendView(hasWhoop: Bool, hasApple: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { coverageLegendItems(hasWhoop: hasWhoop, hasApple: hasApple) }
            VStack(alignment: .leading, spacing: 4) { coverageLegendItems(hasWhoop: hasWhoop, hasApple: hasApple) }
        }
    }

    @ViewBuilder
    private func coverageLegendItems(hasWhoop: Bool, hasApple: Bool) -> some View {
        coverageLegendItem(color: theme.dataRecovery, label: "WHOOP strap", active: hasWhoop)
        coverageLegendItem(color: theme.dataSpO2, label: "Apple Health only", active: hasApple)
        coverageLegendItem(color: theme.hairlineStrong, label: "No data", active: true)
    }

    @ViewBuilder
    private func coverageLegendItem(color: Color, label: LocalizedStringKey, active: Bool) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
        }
        .opacity(active ? 1.0 : 0.3)
    }

    // MARK: - Sources summary (reskinned inline — was the dark `SourcesSummaryCard`)

    /// True when there's a per-source line or a sync line worth showing (mirrors `SourcesSummaryCard`).
    private var sourcesHasContent: Bool {
        let whoopDays = repo.days.count - repo.appleHealthDays.count
        let hasData = whoopDays > 0 || repo.appleHealthDays.count > 0
        let hasSync = live.lastSyncError != nil || live.lastSyncedAt != nil
        return hasData || (!live.backfilling && hasSync)
    }

    /// The compact "Sources" rollup — one row per data source (color rides the source-count datum) plus
    /// the last-sync footnote. Reskinned from `SourcesSummaryCard` into the light language inline (a dark
    /// `NoopCard` on warm paper would be card-in-card); same data, same conditions.
    @ViewBuilder
    private var sourcesSummary: some View {
        let whoopDays = repo.days.count - repo.appleHealthDays.count
        let ahDays    = repo.appleHealthDays.count
        let hasData   = whoopDays > 0 || ahDays > 0
        let hasSync   = live.lastSyncError != nil || live.lastSyncedAt != nil
        let showsSync = !live.backfilling && hasSync
        VStack(alignment: .leading, spacing: 8) {
            if hasData {
                if whoopDays > 0 {
                    sourceRow(name: "WHOOP",
                              count: String(localized: "\(whoopDays) days · \(repo.sleeps.count) sleeps"),
                              tint: theme.dataRecovery)
                }
                if ahDays > 0 {
                    sourceRow(name: "Apple Health",
                              count: String(localized: "\(ahDays) days · \(appleWorkouts) workouts"),
                              tint: theme.dataSpO2)
                }
            }
            if showsSync {
                if hasData { divider }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if let error = live.lastSyncError {
                        Text(verbatim: error).font(StrandFont.footnote).foregroundStyle(theme.warning)
                    } else if let at = live.lastSyncedAt {
                        Text("History synced \(relativeAgo(at, now: context.date.timeIntervalSince1970))")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                }
            }
        }
        .task {
            appleWorkouts = (await repo.workoutRows()).filter { $0.source == "apple-health" }.count
        }
    }

    /// One source rollup row: brand name (ink) · tabular count tinted in the source's data hue (the
    /// count is the measured datum). The dark card tinted a leading glyph; the language tints the datum.
    private func sourceRow(name: LocalizedStringKey, count: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(name).font(StrandFont.subhead).foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            Text(verbatim: count).font(StrandFont.captionNumber).foregroundStyle(tint)
        }
    }

    @State private var appleWorkouts = 0

    // MARK: - Import plumbing (unchanged)

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

    // MARK: - Respaldo (backup/restore + CSV + iCloud auto) — iOS

    #if os(iOS)
    private var backupSection: some View {
        section("Backup") {
            backupBlock
            divider
            autoBackupBlock
        }
    }

    private var backupBlock: some View {
        block("Backup & restore",
              subtitle: "Move all your Cénit data to another device. Export saves everything to one file you can copy across; import replaces this device's data with a backup.") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    QuietButton("Export…") { runExport() }.disabled(backupBusy)
                    QuietButton("Import…") { runImport() }.disabled(backupBusy)
                    QuietButton("Export CSV…") { runCsvExport() }.disabled(backupBusy)
                    if backupBusy { ProgressView().controlSize(.small).tint(theme.inkSecondary) }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(theme.inkTertiary)
                        .font(.system(size: 13)).accessibilityHidden(true)
                    Text("Importing overwrites everything currently in Cénit. Your old data is kept in a side file just in case, and Cénit needs a relaunch for an import to take effect. Export CSV writes a WHOOP-format zip of your days, sleeps, workouts and journal that re-imports into Cénit.")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var autoBackupBlock: some View {
        block("Automatic iCloud backup",
              subtitle: "Pick a folder in iCloud Drive and Cénit keeps a fresh copy of all your data there. Your strap history lives only inside the app, so this is what protects it if you reinstall Cénit or switch phones. A free Apple ID is enough.") {
            VStack(alignment: .leading, spacing: 14) {
                if let name = autoBackup.destinationName {
                    Label("Backing up to \(name)", systemImage: "checkmark.icloud.fill")
                        .font(StrandFont.subhead).foregroundStyle(theme.ink)
                    Text(verbatim: lastBackupText).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                    HStack(spacing: 12) {
                        QuietButton("Back up now") {
                            Task { await autoBackup.backupNow(checkpoint: { await model.repo.checkpointForBackup() }) }
                        }
                        .disabled(autoBackup.busy)
                        QuietButton("Restore…") { runImport() }.disabled(backupBusy)
                        if autoBackup.busy { ProgressView().controlSize(.small).tint(theme.inkSecondary) }
                        Spacer(minLength: 0)
                    }
                    Button { autoBackup.disable() } label: {
                        Text("Turn off automatic backup").font(StrandFont.headline)
                            .foregroundStyle(theme.critical)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 12) {
                        QuietButton("Choose iCloud Drive folder…") { Task { await autoBackup.chooseFolder() } }
                        QuietButton("Restore…") { runImport() }.disabled(backupBusy)
                        Spacer(minLength: 0)
                    }
                }
                if let err = autoBackup.lastError {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
                            .font(.system(size: 13)).accessibilityHidden(true)
                        Text(verbatim: err).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var lastBackupText: String {
        guard let d = autoBackup.lastBackup else { return String(localized: "No backup yet.") }
        let rel = RelativeDateTimeFormatter(); rel.unitsStyle = .full
        return String(localized: "Last backup \(rel.localizedString(for: d, relativeTo: Date()))")
    }
    #endif

    private func runExport() {
        backupBusy = true
        Task {
            let result = await DataBackup.runExport(checkpoint: { await model.repo.checkpointForBackup() })
            handleBackup(result)
        }
    }
    private func runImport() {
        backupBusy = true
        Task {
            let result = await DataBackup.runImport()
            handleBackup(result)
        }
    }
    private func runCsvExport() {
        backupBusy = true
        Task {
            let result = await CsvExport.run(repo: model.repo)
            backupBusy = false
            switch result {
            case .cancelled: return
            case .exported(let url):
                backupAlertTitle = "CSV exported"
                backupAlertMessage = "Saved to \(url.lastPathComponent). The zip re-imports into Cénit (Data Sources → WHOOP Export)."
                showBackupAlert = true
            case .failure(let message):
                backupAlertTitle = "Export problem"; backupAlertMessage = message; showBackupAlert = true
            }
        }
    }
    @MainActor
    private func handleBackup(_ result: DataBackup.BackupResult) {
        backupBusy = false
        switch result {
        case .cancelled: return
        case .exported(let url):
            backupAlertTitle = "Backup exported"
            backupAlertMessage = "Saved to \(url.lastPathComponent). Copy this file to your other device and use Import there to restore everything."
            showBackupAlert = true
        case .imported:
            backupAlertTitle = "Backup imported"
            backupAlertMessage = "Your data has been restored. Quit and reopen Cénit for it to take effect."
            showBackupAlert = true
        case .failure(let message):
            backupAlertTitle = "Backup problem"; backupAlertMessage = message; showBackupAlert = true
        }
    }
}
