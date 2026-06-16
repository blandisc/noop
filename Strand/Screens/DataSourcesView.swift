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
            #if os(iOS)
            // FER-137 — the "Sources" summary card moved here off the iPhone Today (which now reads as
            // verdict + Key Metrics only). iOS-only: macOS still shows it on its Today footer.
            SourcesSummaryCard()
            #endif
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
            // FER-115: coverage grid — macOS only (iOS shows it inside the live-sync card)
            #if !os(iOS)
            if !repo.days.isEmpty || !repo.appleHealthDays.isEmpty {
                Divider().overlay(StrandPalette.hairline)
                coverageBodyView
            }
            #endif
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
             subtitle: "Sync the last few weeks two-way, on-device: Cénit reads your Apple Health HR, HRV, sleep, SpO₂ and steps, and writes its own strap-derived metrics back. Strictly opt-in — nothing leaves your iPhone. (For a one-time bulk history, use the export import above.)") {
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
            // FER-115: coverage grid — hide when Apple Health is denied/unavailable and there are no strap days
            let healthAccessible = health.auth != .denied && health.auth != .unavailable
            if !repo.days.isEmpty || (!repo.appleHealthDays.isEmpty && healthAccessible) {
                Divider().overlay(StrandPalette.hairline)
                coverageBodyView
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
            Text(verbatim: "Apple Health access was declined. Enable it in Settings › Privacy & Security › Health › Cénit.")
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

    // MARK: FER-115 — 30-day source coverage grid

    /// Overline + summary line + 6×5 grid + legend. Caller adds the leading Divider.
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
            Text("Data coverage").strandOverline()
                .foregroundStyle(StrandPalette.textTertiary)
            Text(coverageSummaryString(whoop: whoopCount, apple: appleCount))
                .font(StrandFont.subhead)
                .foregroundStyle(whoopCount + appleCount > 0 ? StrandPalette.textSecondary
                                                             : StrandPalette.textTertiary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(Array(days30.enumerated()), id: \.offset) { _, day in
                    let isWhoop = allDayKeys.contains(day) && !repo.appleHealthDays.contains(day)
                    let isApple = repo.appleHealthDays.contains(day)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isWhoop ? StrandPalette.accent
                              : isApple ? StrandPalette.metricCyan
                              : StrandPalette.textTertiary.opacity(0.3))
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
        coverageLegendItem(color: StrandPalette.accent, label: "WHOOP strap", active: hasWhoop)
        coverageLegendItem(color: StrandPalette.metricCyan, label: "Apple Health only", active: hasApple)
        coverageLegendItem(color: StrandPalette.textTertiary.opacity(0.5), label: "No data", active: true)
    }

    @ViewBuilder
    private func coverageLegendItem(color: Color, label: LocalizedStringKey, active: Bool) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
        }
        .opacity(active ? 1.0 : 0.3)
    }

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
            Divider().overlay(StrandPalette.hairline)
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
            Text("Sync diagnostic").strandOverline()
                .foregroundStyle(StrandPalette.textTertiary)

            if !live.connected {
                Text("Connect your strap to run the sync diagnostic.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
            } else if !live.encryptedBond {
                Text("Complete secure pairing first — the strap won’t offload its history until the encrypted bond is set.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
            } else {
                strapRangeRow
                syncNowButton
                if live.backfilling {
                    syncProgressRow
                } else if let err = live.lastSyncError {
                    Text(verbatim: err)
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
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
                .font(.system(size: 12)).foregroundStyle(StrandPalette.textTertiary)
            Text("On the band:").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            if let oldest = live.strapHistoryOldest, let newest = live.strapHistoryNewest {
                Text(verbatim: "\(Self.dayFormatter.string(from: Date(timeIntervalSince1970: oldest))) → \(Self.dayFormatter.string(from: Date(timeIntervalSince1970: newest)))")
                    .font(StrandFont.footnote).monospacedDigit()
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                Text(verbatim: "—").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private var syncNowButton: some View {
        Button {
            model.ble.syncNow()
        } label: {
            Label(live.backfilling ? "Syncing…" : "Sync now",
                  systemImage: "arrow.triangle.2.circlepath").padding(.horizontal, 6)
        }
        .buttonStyle(.borderedProminent).tint(StrandPalette.accent)
        .disabled(live.backfilling)
    }

    /// Live offload progress — a pulsing pill plus the running chunk count (the only honest progress
    /// signal; the protocol never reveals the total pending, so a count, never a percent).
    private var syncProgressRow: some View {
        HStack(spacing: 10) {
            StatePill("Syncing strap history…", tone: .accent, pulsing: true)
            Text("\(live.syncChunksThisSession) pieces")
                .font(StrandFont.footnote).monospacedDigit()
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    /// "Received this sync" — rows that decoded and landed, per sensor. The honest data receipt
    /// (counts from StreamStore.insert, accumulated over the offload session).
    @ViewBuilder
    private var syncReceiptList: some View {
        let r = live.syncReceipt
        VStack(alignment: .leading, spacing: 4) {
            Text("Received this sync").strandOverline()
                .foregroundStyle(StrandPalette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Self.syncSensorRows(r), id: \.key) { row in
                    HStack(spacing: 8) {
                        Image(systemName: row.count > 0 ? "checkmark.circle.fill" : "minus.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(row.count > 0 ? StrandPalette.statusPositive : StrandPalette.textTertiary)
                        Text(LocalizedStringKey(row.key)).font(StrandFont.subhead)
                            .foregroundStyle(row.count > 0 ? StrandPalette.textSecondary : StrandPalette.textTertiary)
                        Spacer()
                        Text(verbatim: row.count > 0 ? "\(row.count)" : "—")
                            .font(StrandFont.footnote).monospacedDigit()
                            .foregroundStyle(row.count > 0 ? StrandPalette.textSecondary : StrandPalette.textTertiary)
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
                return ("circle", "The band has nothing new.", StrandPalette.textSecondary)
            case .notStoringClock:
                return ("clock.badge.exclamationmark.fill", "The band isn’t storing data (clock). Run it through the WHOOP app to resume.", StrandPalette.statusWarning)
            case .arrivesButNoDecode:
                return ("exclamationmark.triangle.fill", "Data arrives but doesn’t decode — please report.", StrandPalette.statusWarning)
            case .receivingAndStoring:
                return ("checkmark.seal.fill", "Receiving and storing everything.", StrandPalette.statusPositive)
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
