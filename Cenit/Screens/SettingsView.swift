import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import WhoopStore

/// Settings — profile (powers zones / calories / recovery), strap connection, and about.
/// Grouped cards on surface.raised with a two-column form feel.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var profile: ProfileStore
    #if os(iOS)
    @EnvironmentObject private var autoBackup: AutoBackup
    #endif

    /// Backup & restore UI state.
    @State private var backupBusy = false
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var showBackupAlert = false

    /// Opt-in WHOOP 5/MG protocol experiments (off by default). See [PuffinExperiment].
    @AppStorage(PuffinExperiment.defaultsKey) private var puffinExperiments = false

    /// Opt-in WHOOP 5/MG raw-frame capture to a file (off by default). See [PuffinFrameRecorder].
    @AppStorage(PuffinFrameRecorder.enabledKey) private var puffinCapture = false

    // Imperial/Metric display preference (D#103). Stored data is always SI; this only changes how
    // distances/weights/heights/temperatures are SHOWN — and lets the profile fields below take
    // imperial entry. Temperature has a separate override so °C/°F can be picked independently.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw)
    }

    /// "What's New" changelog sheet, reachable any time from About.
    @State private var showWhatsNew = false

    /// User-initiated GitHub release check behind the About "Check for updates" button.
    @StateObject private var updateChecker = UpdateChecker()
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScreenScaffold(title: "Settings",
                       subtitle: "Your numbers, your strap, and how Cénit works. All on this Mac.") {
            profileCard
            unitsCard
            strapCard
            experimentalCard
            backupCard
            #if os(iOS)
            autoBackupCard
            #endif
            aboutCard
        }
        .alert(backupAlertTitle, isPresented: $showBackupAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(backupAlertMessage)
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(onClose: { showWhatsNew = false })
        }
    }

    // MARK: - Profile

    private var profileCard: some View {
        SettingsSection(
            icon: "person.fill",
            title: "Profile",
            blurb: "These power your heart-rate zones, calorie estimates and recovery baselines. Keep them accurate."
        ) {
            VStack(spacing: 0) {
                FormRow(label: "Age") {
                    HStack(spacing: 12) {
                        Text("\(profile.age)")
                            .font(StrandFont.bodyNumber)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .frame(minWidth: 28, alignment: .trailing)
                        Stepper("Age", value: $profile.age, in: 13...100)
                            .labelsHidden()
                            .accessibilityLabel("Age, \(profile.age) years")
                    }
                }
                rowDivider
                FormRow(label: "Sex") {
                    Picker("Sex", selection: $profile.sex) {
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                        Text("Non-binary").tag("nonbinary")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityLabel("Sex")
                }
                rowDivider
                FormRow(label: "Weight") {
                    // Imperial mode steps in pounds and stores the kg equivalent; metric steps in kg.
                    if unitSystem == .imperial {
                        poundsField(weightKg: $profile.weightKg)
                    } else {
                        measureField(value: $profile.weightKg, unit: "kg",
                                     range: 30...250, step: 0.5, format: "%.1f",
                                     accessibility: "Weight in kilograms")
                    }
                }
                rowDivider
                FormRow(label: "Height") {
                    // Imperial mode steps in whole inches and stores the cm equivalent; metric steps in cm.
                    if unitSystem == .imperial {
                        feetInchesField(heightCm: $profile.heightCm)
                    } else {
                        measureField(value: $profile.heightCm, unit: "cm",
                                     range: 120...230, step: 1, format: "%.0f",
                                     accessibility: "Height in centimetres")
                    }
                }
                rowDivider
                FormRow(label: "Max heart rate") {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 8) {
                            hrMaxField
                            Text("bpm")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        Text(profile.hrMaxOverride > 0
                             ? "Manual override"
                             : "Auto · \(profile.hrMax) bpm (Tanaka)")
                            .font(StrandFont.footnote)
                            .foregroundStyle(profile.hrMaxOverride > 0
                                             ? StrandPalette.accent
                                             : StrandPalette.textTertiary)
                    }
                }
            }
        }
    }

    /// Numeric weight/height field: tabular value + small +/- stepper.
    private func measureField(value: Binding<Double>, unit: String,
                              range: ClosedRange<Double>, step: Double,
                              format: String, accessibility: String) -> some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: format, value.wrappedValue))
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(minWidth: 48, alignment: .trailing)
                Text(unit)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Stepper(accessibility, value: value, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel(accessibility)
        }
    }

    /// Imperial weight entry: shows pounds, steps in 1-lb increments, and writes the kg equivalent back
    /// to the SI-stored profile. Range mirrors the metric 30…250 kg (≈66…551 lb).
    private func poundsField(weightKg: Binding<Double>) -> some View {
        let lb = Binding<Double>(
            get: { UnitFormatter.kgToPounds(weightKg.wrappedValue) },
            set: { weightKg.wrappedValue = $0 / UnitFormatter.poundsPerKilogram }
        )
        return HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", lb.wrappedValue))
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(minWidth: 48, alignment: .trailing)
                Text("lb")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Stepper("Weight in pounds", value: lb, in: 66...551, step: 1)
                .labelsHidden()
                .accessibilityLabel("Weight, \(Int(lb.wrappedValue.rounded())) pounds")
        }
    }

    /// Imperial height entry: shows feet′ inches″, steps in whole inches, and writes the cm equivalent
    /// back to the SI-stored profile. Range mirrors the metric 120…230 cm (≈47…91 in).
    private func feetInchesField(heightCm: Binding<Double>) -> some View {
        let inches = Binding<Double>(
            get: { UnitFormatter.cmToInches(heightCm.wrappedValue).rounded() },
            set: { heightCm.wrappedValue = $0 * UnitFormatter.centimetersPerInch }
        )
        let parts = UnitFormatter.cmToFeetInches(heightCm.wrappedValue)
        return HStack(spacing: 10) {
            Text("\(parts.feet)′ \(parts.inches)″")
                .font(StrandFont.bodyNumber)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(minWidth: 56, alignment: .trailing)
            Stepper("Height in inches", value: inches, in: 47...91, step: 1)
                .labelsHidden()
                .accessibilityLabel("Height, \(parts.feet) feet \(parts.inches) inches")
        }
    }

    /// HR-max override: 0 = auto. Shown as a compact tabular value with a stepper.
    private var hrMaxField: some View {
        HStack(spacing: 10) {
            Text(profile.hrMaxOverride > 0 ? "\(profile.hrMaxOverride)" : "Auto")
                .font(StrandFont.bodyNumber)
                .foregroundStyle(profile.hrMaxOverride > 0
                                 ? StrandPalette.textPrimary
                                 : StrandPalette.textTertiary)
                .frame(minWidth: 44, alignment: .trailing)
            Stepper("Max heart rate override",
                    value: $profile.hrMaxOverride, in: 0...230, step: 1)
                .labelsHidden()
                .accessibilityLabel("Max heart rate override, \(profile.hrMaxOverride == 0 ? "automatic" : "\(profile.hrMaxOverride) bpm")")
        }
    }

    // MARK: - Units

    /// Imperial/Metric display toggle + a separate temperature override. Display-only — nothing stored
    /// changes, NOOP keeps everything in SI and converts at the point of display.
    private var unitsCard: some View {
        SettingsSection(
            icon: "ruler",
            title: "Units",
            blurb: "Choose how distances, weights, heights and temperatures are shown. Your data is always stored the same way — this only changes the display."
        ) {
            VStack(spacing: 0) {
                FormRow(label: "Measurement system") {
                    Picker("Measurement system", selection: $unitSystemRaw) {
                        Text("Metric").tag(UnitSystem.metric.rawValue)
                        Text("Imperial").tag(UnitSystem.imperial.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityLabel("Measurement system")
                }
                rowDivider
                FormRow(label: "Temperature") {
                    // Three-way: "Match" follows the system above; °C / °F pin it explicitly. Stored as
                    // an empty string ("match") or the TemperatureUnit raw value.
                    Picker("Temperature", selection: $temperatureRaw) {
                        Text("Match").tag("")
                        Text("°C").tag(TemperatureUnit.celsius.rawValue)
                        Text("°F").tag(TemperatureUnit.fahrenheit.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityLabel("Temperature unit")
                }
            }
        }
    }

    // MARK: - Strap

    private var strapCard: some View {
        SettingsSection(
            icon: "antenna.radiowaves.left.and.right",
            title: "Strap",
            blurb: "Cénit pairs directly with your WHOOP over Bluetooth — no WHOOP app, no cloud."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    StatePill("\(strapStatusTitle)", tone: strapTone, pulsing: live.connected)
                    if let pct = live.batteryPct {
                        StatePill(live.charging == true
                                  ? "Battery \(Int(pct.rounded()))% · Charging"
                                  : "Battery \(Int(pct.rounded()))%",
                                  tone: batteryTone(pct), showsDot: false)
                    }
                    Spacer(minLength: 0)
                }
                Text(strapStatusDetail)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                HStack(spacing: 12) {
                    Button {
                        model.scan()
                    } label: {
                        Label("Re-scan", systemImage: "arrow.clockwise")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StrandPalette.accent)

                    Button {
                        model.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(StrandPalette.statusCritical)
                    .disabled(!live.connected && !live.bonded)
                }
                strapLogSection
            }
        }
    }

    // MARK: - Strap log (restored in Settings after the «En vivo» redesign — FER-199)

    /// The raw BLE-session log (`live.log`), embedded under the strap controls. It used to live on the
    /// «En vivo» screen; the redesign to a pure monitor (FER-181/190) left it without a home. It's the
    /// diagnostic trail for connection/sync issues and the thing you attach to a bug report
    /// (Copy / Save…). Shown only when there are lines; otherwise a short honest placeholder.
    @ViewBuilder private var strapLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(StrandPalette.hairline)
            HStack(spacing: 12) {
                Text("STRAP LOG").strandOverline()
                Spacer()
                if !live.log.isEmpty {
                    Button("Copy") { copyStrapLog() }
                        .buttonStyle(.plain).font(StrandFont.mono)
                        .foregroundStyle(StrandPalette.accent)
                    Button("Save…") { saveStrapLog() }
                        .buttonStyle(.plain).font(StrandFont.mono)
                        .foregroundStyle(StrandPalette.accent)
                }
            }
            if live.log.isEmpty {
                Text("No activity yet. The log fills in as your strap connects.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(live.log.enumerated()), id: \.offset) { idx, line in
                                Text(line).font(StrandFont.mono)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                        }
                    }
                    .frame(height: 200)
                    .onChange(of: live.log.count) {
                        if let last = live.log.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
    }

    /// The shareable strap log as text (header + lines), for Copy / Save… — to attach to a bug report.
    private func strapLogText() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let osName = "iOS"
        let header = "Cénit strap log — \(osName)\nApp: \(v)\n\(osName): "
            + ProcessInfo.processInfo.operatingSystemVersionString + "\n"
            + String(repeating: "-", count: 40) + "\n"
        return header + live.log.joined(separator: "\n")
    }

    private func copyStrapLog() { PlatformPasteboard.copy(strapLogText()) }

    private func saveStrapLog() {
        FileExport.exportText(strapLogText(), suggestedName: "noop-strap-log.txt")
    }

    private var strapStatusTitle: String {
        if live.bonded && live.connected { return String(localized: "Bonded · streaming") }
        if live.connected { return String(localized: "Connected") }
        if live.bonded { return String(localized: "Bonded · idle") }
        return String(localized: "Disconnected")
    }

    private var strapTone: StrandTone {
        if live.connected { return .positive }
        if live.bonded { return .warning }
        return .critical
    }

    private var strapStatusDetail: String {
        if live.bonded && live.connected {
            return String(localized: "Your strap is paired and sending data. Open Live for a real-time heart rate.")
        }
        if live.connected, let hint = live.pairingHint { return hint }
        if live.connected { return String(localized: "Connected. Finishing the secure pairing handshake…") }
        if live.bonded { return String(localized: "Previously paired but not currently connected. Re-scan to reconnect.") }
        return String(localized: "No strap connected. Put your WHOOP nearby and tap Re-scan to pair.")
    }

    private func batteryTone(_ pct: Double) -> StrandTone {
        if pct <= 15 { return .critical }
        if pct <= 30 { return .warning }
        return .positive
    }

    // MARK: - Backup & restore

    // MARK: - Experimental (WHOOP 5 / MG)

    private var experimentalCard: some View {
        SettingsSection(
            icon: "flask.fill",
            title: "Experimental · WHOOP 5 / MG",
            blurb: "Live heart rate already works on a WHOOP 5/MG strap. These probes go further and try to coax more out of it. They are guesses, off by default, and only ever touch a 5/MG strap — WHOOP 4.0 is never affected."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $puffinExperiments) {
                    Text("Try WHOOP 5/MG protocol probes")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(StrandPalette.accent)
                Text("On a 5/MG connection Cénit will send a puffin realtime-stream request after the handshake, and log what comes back. If you have a 5/MG strap, turning this on and sharing your strap log helps map the protocol. No effect on WHOOP 4.0.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(StrandPalette.hairline)

                Toggle(isOn: $puffinCapture) {
                    Text("Record puffin frames to a file")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(StrandPalette.accent)
                Text("Saves every raw 5/MG frame (with a timestamp and the live heart rate) to a JSON file you can share to help map the biometric layout. This only records frames the strap already sent — it never writes to your strap — so it is safe to leave on. Export the file and attach it to a protocol-mapping issue.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if live.puffinCaptureCount > 0 {
                    Text("\(live.puffinCaptureCount) frame\(live.puffinCaptureCount == 1 ? "" : "s") captured this session.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    HStack(spacing: 12) {
                        Button {
                            exportPuffinCaptures()
                        } label: {
                            Label("Export frames…", systemImage: "square.and.arrow.up")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StrandPalette.accent)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// Flush the in-flight capture, then copy it to a user-chosen location (or share it on iOS).
    private func exportPuffinCaptures() {
        model.ble.flushPuffinCaptures()
        guard let src = live.puffinCaptureURL else { return }
        FileExport.exportFile(at: src)
    }

    private var backupCard: some View {
        SettingsSection(
            icon: "externaldrive.fill",
            title: "Backup & restore",
            blurb: "Move all your Cénit data to another machine. Export saves everything — history, sleeps, workouts, settings — to a single file you can copy across; import replaces this Mac's data with a backup."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        runExport()
                    } label: {
                        Label("Export…", systemImage: "square.and.arrow.up")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StrandPalette.accent)
                    .disabled(backupBusy)

                    Button {
                        runImport()
                    } label: {
                        Label("Import…", systemImage: "square.and.arrow.down")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(StrandPalette.accent)
                    .disabled(backupBusy)

                    Button {
                        runCsvExport()
                    } label: {
                        Label("Export CSV…", systemImage: "tablecells")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(StrandPalette.accent)
                    .disabled(backupBusy)

                    if backupBusy { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(StrandPalette.textTertiary)
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                    Text("Importing overwrites everything currently in Cénit. Your old data is kept in a side file just in case. Cénit needs a relaunch for an import to take effect. Export CSV writes a WHOOP-format zip of your days, sleeps, workouts and journal that re-imports into Cénit — on-device computed rows are marked APPROXIMATE in its Source column; the full backup stays the lossless restore path.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    #if os(iOS)
    /// iOS-only: automatic backup of the whole database to a folder in the user's iCloud Drive, so the
    /// strap history (which lives only inside the app) survives a reinstall or a new phone — even on a
    /// free Apple ID. Restore reuses the manual `runImport` below. See [AutoBackup].
    private var autoBackupCard: some View {
        SettingsSection(
            icon: "icloud.and.arrow.up.fill",
            title: "Automatic iCloud backup",
            blurb: "Pick a folder in iCloud Drive and Cénit keeps a fresh copy of all your data there. Your strap history lives only inside the app, so this is what protects it if you reinstall Cénit or switch phones. It uses your own iCloud Drive — a free Apple ID is enough."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let name = autoBackup.destinationName {
                    Label("Backing up to \(name)", systemImage: "checkmark.icloud.fill")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(lastBackupText)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)

                    HStack(spacing: 12) {
                        Button {
                            Task { await autoBackup.backupNow(checkpoint: { await model.repo.checkpointForBackup() }) }
                        } label: {
                            Label("Back up now", systemImage: "arrow.clockwise.icloud")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StrandPalette.accent)
                        .disabled(autoBackup.busy)

                        Button {
                            runImport()
                        } label: {
                            Label("Restore…", systemImage: "square.and.arrow.down")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(StrandPalette.accent)
                        .disabled(backupBusy)

                        if autoBackup.busy { ProgressView().controlSize(.small) }
                        Spacer(minLength: 0)
                    }

                    Button(role: .destructive) {
                        autoBackup.disable()
                    } label: {
                        Label("Turn off automatic backup", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            Task { await autoBackup.chooseFolder() }
                        } label: {
                            Label("Choose iCloud Drive folder…", systemImage: "folder.badge.plus")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StrandPalette.accent)

                        Button {
                            runImport()
                        } label: {
                            Label("Restore…", systemImage: "square.and.arrow.down")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(StrandPalette.accent)
                        .disabled(backupBusy)

                        Spacer(minLength: 0)
                    }
                }

                if let err = autoBackup.lastError {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 13))
                            .accessibilityHidden(true)
                        Text(err)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// "Last backup 2 hours ago" / "No backup yet." for the auto-backup status line.
    private var lastBackupText: String {
        guard let d = autoBackup.lastBackup else { return String(localized: "No backup yet.") }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .full
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
            case .cancelled:
                return
            case .exported(let url):
                backupAlertTitle = "CSV exported"
                backupAlertMessage = "Saved to \(url.lastPathComponent). The zip re-imports into Cénit (Data Sources → WHOOP Export)."
                showBackupAlert = true
            case .failure(let message):
                backupAlertTitle = "Export problem"
                backupAlertMessage = message
                showBackupAlert = true
            }
        }
    }

    @MainActor
    private func handleBackup(_ result: DataBackup.BackupResult) {
        backupBusy = false
        switch result {
        case .cancelled:
            return
        case .exported(let url):
            backupAlertTitle = "Backup exported"
            backupAlertMessage = "Saved to \(url.lastPathComponent). Copy this file to your other Mac and use Import there to restore everything."
            showBackupAlert = true
        case .imported:
            backupAlertTitle = "Backup imported"
            backupAlertMessage = "Your data has been restored. Quit and reopen Cénit for it to take effect."
            showBackupAlert = true
        case .failure(let message):
            backupAlertTitle = "Backup problem"
            backupAlertMessage = message
            showBackupAlert = true
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        SettingsSection(
            icon: "info.circle.fill",
            title: "About",
            blurb: "Cénit — all your data, none of the cloud."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text("Cénit")
                        .font(StrandFont.title2)
                        .foregroundStyle(StrandPalette.textPrimary)
                    StatePill("v\(AppChangelog.currentVersion)", tone: .neutral, showsDot: false)
                    Spacer()
                    Button {
                        showWhatsNew = true
                    } label: {
                        Label("What's new", systemImage: "sparkles").padding(.horizontal, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(StrandPalette.accent)
                }

                // Check for updates — a single, user-initiated read of GitHub's public releases API.
                // No background polling, no auto-update; sends nothing about you, just reads the version.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            updateChecker.check(currentVersion: AppChangelog.currentVersion)
                        } label: {
                            if updateChecker.state == .checking {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking…")
                                }
                            } else {
                                Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                                    .padding(.horizontal, 4)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(updateChecker.state == .checking)

                        if case .upToDate(let v) = updateChecker.state {
                            Text("You're on the latest (\(v)).")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                        } else if case .failed = updateChecker.state {
                            Text("Couldn't check. Try again.")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.statusWarning)
                        }
                        Spacer()
                    }

                    // Update available: show what's new, with a download straight to the release.
                    if case .available(let v, let url, let notes) = updateChecker.state {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Version \(v) is available")
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Spacer()
                                Button {
                                    openURL(url)
                                } label: {
                                    Label("Download", systemImage: "arrow.down.circle.fill")
                                        .padding(.horizontal, 4)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(StrandPalette.accent)
                            }
                            if !notes.isEmpty {
                                ScrollView {
                                    Text(notes)
                                        .font(StrandFont.footnote)
                                        .foregroundStyle(StrandPalette.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 150)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StrandPalette.surfaceInset,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(StrandPalette.accent.opacity(0.3), lineWidth: 1)
                        )
                    }

                    Text("Checks GitHub for the latest version when you tap — nothing else is sent.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }

                Text("A standalone companion for your WHOOP. Everything stays on this device — your history, your live stream, your numbers. Nothing is uploaded. Cénit is an independent, experimental project, not the WHOOP app.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Medical disclaimer
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(StrandPalette.statusWarning)
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                    Text("Cénit is not a medical device. It is for informational and personal-insight purposes only and is not intended to diagnose, treat, cure or prevent any condition. Talk to a clinician for medical advice.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StrandPalette.surfaceInset,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(StrandPalette.statusWarning.opacity(0.25), lineWidth: 1)
                )

                rowDivider

                VStack(alignment: .leading, spacing: 6) {
                    Text("Built on").strandOverline()
                    attribution(repo: "johnmiddleton12/my-whoop", note: "WHOOP 4.0 protocol")
                    attribution(repo: "b-nnett/goose", note: "WHOOP 5.0 protocol")
                }

                Text("Open-source BLE reverse-engineering work. Thank you.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func attribution(repo: String, note: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
                .accessibilityHidden(true)
            Text(repo)
                .font(StrandFont.mono(12))
                .foregroundStyle(StrandPalette.textPrimary)
            Text("· \(note)")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Shared bits

    private var rowDivider: some View {
        Rectangle()
            .fill(StrandPalette.hairline)
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

// MARK: - Section card

/// A grouped settings card: icon + title header, an explanatory blurb, then content.
private struct SettingsSection<Content: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let blurb: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                Text(blurb)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
        }
    }
}

// MARK: - Two-column form row

/// Label on the left, control on the right — the two-column form feel.
private struct FormRow<Control: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .frame(minHeight: 32)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Settings") {
    let model = AppModel()
    model.live.bonded = true
    model.live.connected = true
    model.live.batteryPct = 64
    return SettingsView()
        .environmentObject(model)
        .environmentObject(model.live)
        .environmentObject(model.profile)
        .frame(width: 720, height: 900)
        .background(StrandPalette.surfaceBase)
        .preferredColorScheme(.dark)
}
#endif
