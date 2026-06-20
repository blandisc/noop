#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Ajustes (the Settings tab root) — FER-337
//
// The redesigned «Ajustes» tab in the light «Instrumento diurno» language (warm paper, color only on
// the datum, hierarchy by space). It replaces TWO stacked surfaces from the old shell: the interim
// «Más» drawer (a junk list of orphan screens) AND the dark `SettingsView` it pointed at. The tab now
// opens DIRECTLY here — no list → "Settings" indirection.
//
// Structure (Opción B, approved preview FER-337): Perfil and «Tu strap» are surfaced inline on the
// root; everything else is a quiet row that opens a focused screen. Like Cuerpo, navigation is by
// SHEET, not a nested NavigationStack (FER-171): the light sub-screens (Unidades, Log de la banda)
// ride light sheets with the theme passed explicitly (it doesn't cross `.sheet` — FER-162); the three
// still-dark sibling screens (Datos y fuentes, Automatizaciones, Acerca de y soporte) ride a sheet
// pinned to `.dark` (a light tab can't host a dark screen without breaking the status bar — same
// bridge Cuerpo/Today use). Those go light in FER-338 / FER-69 / FER-67.
//
// Explore · Compare · Workouts are NOT here: they already open from Cuerpo's footer; the old «Más»
// duplicate is gone.

/// Theme wrapper: drives `\.instrumentoTheme` by the hour (like Today / Cuerpo) so Ajustes warms with
/// the real sun, then hands to `AjustesLanding`, which reads the resolved theme from the environment.
struct AjustesView: View {
    var body: some View {
        AjustesLanding()
            .instrumentoThemeByHour(solar: Self.solarWindow())
    }

    /// Sunrise/sunset for today, GPS- and permission-free (same `SolarClock` source Today/Cuerpo use).
    /// `nil` in polar cases falls back to fixed hours.
    private static func solarWindow() -> SolarWindow? {
        guard let w = SolarClock.sunWindow(on: Date(), in: .current) else { return nil }
        return SolarWindow(sunrise: w.sunrise, sunset: w.sunset)
    }
}

// MARK: - Sheet routing

/// A still-dark sibling screen, presented as a self-contained sheet pinned to `.dark`. Each goes light
/// in its own issue (Datos y fuentes → FER-338, Automatizaciones → FER-69, Acerca de y soporte → FER-67).
private enum AjustesDarkScreen: String, Identifiable {
    case dataSources, automations, support
    var id: String { rawValue }
}

// MARK: - Landing

private struct AjustesLanding: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var profile: ProfileStore
    // Read only to re-inject into the dark sibling sheets (a sheet starts a fresh environment branch).
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var behavior: BehaviorStore
    @EnvironmentObject private var autoBackup: AutoBackup
    @Environment(\.instrumentoTheme) private var theme

    /// Opt-in WHOOP 5/MG protocol experiments (off by default). See [PuffinExperiment].
    @AppStorage(PuffinExperiment.defaultsKey) private var puffinExperiments = false
    /// Opt-in WHOOP 5/MG raw-frame capture to a file (off by default). See [PuffinFrameRecorder].
    @AppStorage(PuffinFrameRecorder.enabledKey) private var puffinCapture = false

    // Imperial/Metric display preference (D#103). Stored data is always SI; this only changes how
    // distances/weights/heights/temperatures are SHOWN — and lets the profile fields take imperial entry.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    // Sheet drivers.
    @State private var showUnits = false
    @State private var showLog = false
    @State private var darkScreen: AjustesDarkScreen? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings").font(StrandFont.title1).foregroundStyle(theme.ink)
                    Text("Your numbers, your strap, and how Cénit works. All on this iPhone.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, -8)

                profileSection
                strapSection
                moreSection
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .sheet(isPresented: $showUnits) {
            UnidadesSheet().instrumentoTheme(theme)
        }
        .sheet(isPresented: $showLog) {
            StrapLogSheet().instrumentoTheme(theme).environmentObject(live)
        }
        .sheet(item: $darkScreen) { screen in darkSheet(screen) }
    }

    // MARK: - Profile

    private var profileSection: some View {
        section("Profile") {
            formRow("Age") {
                HStack(spacing: 12) {
                    Text("\(profile.age)")
                        .font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
                        .frame(minWidth: 28, alignment: .trailing)
                    Stepper("Age", value: $profile.age, in: 13...100)
                        .labelsHidden().tint(theme.dataRecovery)
                        .accessibilityLabel("Age, \(profile.age) years")
                }
            }
            divider
            formRow("Sex") {
                Picker("Sex", selection: $profile.sex) {
                    Text("Male").tag("male")
                    Text("Female").tag("female")
                    Text("Non-binary").tag("nonbinary")
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .accessibilityLabel("Sex")
            }
            divider
            formRow("Weight") {
                if unitSystem == .imperial { poundsField(weightKg: $profile.weightKg) }
                else { measureField(value: $profile.weightKg, unit: "kg", range: 30...250, step: 0.5,
                                    format: "%.1f", accessibility: "Weight in kilograms") }
            }
            divider
            formRow("Height") {
                if unitSystem == .imperial { feetInchesField(heightCm: $profile.heightCm) }
                else { measureField(value: $profile.heightCm, unit: "cm", range: 120...230, step: 1,
                                    format: "%.0f", accessibility: "Height in centimetres") }
            }
            divider
            formRow("Max heart rate") {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) { hrMaxField
                        Text("bpm").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                    Text(profile.hrMaxOverride > 0 ? "Manual override"
                         : "Auto · \(profile.hrMax) bpm (Tanaka)")
                        .font(StrandFont.footnote)
                        .foregroundStyle(profile.hrMaxOverride > 0 ? theme.dataRecovery : theme.inkTertiary)
                }
            }
        }
    }

    /// Numeric weight/height field: tabular value + small +/- stepper.
    private func measureField(value: Binding<Double>, unit: String, range: ClosedRange<Double>,
                              step: Double, format: String, accessibility: String) -> some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: format, value.wrappedValue))
                    .font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
                    .frame(minWidth: 48, alignment: .trailing)
                Text(unit).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Stepper(accessibility, value: value, in: range, step: step)
                .labelsHidden().tint(theme.dataRecovery).accessibilityLabel(accessibility)
        }
    }

    /// Imperial weight entry: shows pounds, steps in 1-lb increments, writes the kg equivalent back.
    private func poundsField(weightKg: Binding<Double>) -> some View {
        let lb = Binding<Double>(
            get: { UnitFormatter.kgToPounds(weightKg.wrappedValue) },
            set: { weightKg.wrappedValue = $0 / UnitFormatter.poundsPerKilogram })
        return HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", lb.wrappedValue))
                    .font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
                    .frame(minWidth: 48, alignment: .trailing)
                Text("lb").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Stepper("Weight in pounds", value: lb, in: 66...551, step: 1)
                .labelsHidden().tint(theme.dataRecovery)
                .accessibilityLabel("Weight, \(Int(lb.wrappedValue.rounded())) pounds")
        }
    }

    /// Imperial height entry: shows feet′ inches″, steps in whole inches, writes the cm equivalent back.
    private func feetInchesField(heightCm: Binding<Double>) -> some View {
        let inches = Binding<Double>(
            get: { UnitFormatter.cmToInches(heightCm.wrappedValue).rounded() },
            set: { heightCm.wrappedValue = $0 * UnitFormatter.centimetersPerInch })
        let parts = UnitFormatter.cmToFeetInches(heightCm.wrappedValue)
        return HStack(spacing: 10) {
            Text("\(parts.feet)′ \(parts.inches)″")
                .font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
                .frame(minWidth: 56, alignment: .trailing)
            Stepper("Height in inches", value: inches, in: 47...91, step: 1)
                .labelsHidden().tint(theme.dataRecovery)
                .accessibilityLabel("Height, \(parts.feet) feet \(parts.inches) inches")
        }
    }

    /// HR-max override: 0 = auto. Compact tabular value + stepper.
    private var hrMaxField: some View {
        HStack(spacing: 10) {
            Text(profile.hrMaxOverride > 0 ? "\(profile.hrMaxOverride)" : "Auto")
                .font(StrandFont.bodyNumber)
                .foregroundStyle(profile.hrMaxOverride > 0 ? theme.ink : theme.inkTertiary)
                .frame(minWidth: 44, alignment: .trailing)
            Stepper("Max heart rate override", value: $profile.hrMaxOverride, in: 0...230, step: 1)
                .labelsHidden().tint(theme.dataRecovery)
                .accessibilityLabel("Max heart rate override, \(profile.hrMaxOverride == 0 ? "automatic" : "\(profile.hrMaxOverride) \(String(localized: "bpm"))")")
        }
    }

    // MARK: - Your strap

    private var strapSection: some View {
        section("Your strap") {
            HStack(spacing: 10) {
                Circle().fill(strapDotColor).frame(width: 8, height: 8)
                Text(strapStatusTitle).font(StrandFont.subhead).foregroundStyle(strapDotColor)
                Spacer(minLength: 8)
                if let pct = live.batteryPct {
                    Text(live.charging == true ? "\(Int(pct.rounded()))% · Charging" : "\(Int(pct.rounded()))%")
                        .font(StrandFont.bodyNumber).foregroundStyle(batteryColor(pct))
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)

            Text(strapStatusDetail).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                QuietButton("Re-scan") { model.scan() }
                Button { model.disconnect() } label: {
                    Text("Disconnect").font(StrandFont.headline)
                        .foregroundStyle((!live.connected && !live.bonded) ? theme.inkTertiary : theme.critical)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!live.connected && !live.bonded)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)

            divider
            navRow("Strap log") { showLog = true }
            divider
            experimentalRows
        }
    }

    /// Opt-in WHOOP 5/MG probes — kept on the root (one toggle), per the approved preview; the
    /// frame-capture toggle + export sit just under it (they only matter to a 5/MG owner).
    @ViewBuilder private var experimentalRows: some View {
        Toggle(isOn: $puffinExperiments) {
            Text("WHOOP 5/MG protocol probes").font(StrandFont.body).foregroundStyle(theme.ink)
        }
        .toggleStyle(.switch).tint(theme.dataRecovery).padding(.vertical, 4)
        Text("On a 5/MG connection Cénit sends a probe after the handshake and logs what comes back. No effect on WHOOP 4.0.")
            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)

        Toggle(isOn: $puffinCapture) {
            Text("Record 5/MG frames to a file").font(StrandFont.body).foregroundStyle(theme.ink)
        }
        .toggleStyle(.switch).tint(theme.dataRecovery).padding(.vertical, 4)
        if live.puffinCaptureCount > 0 {
            HStack(spacing: 10) {
                Text("\(live.puffinCaptureCount) frame\(live.puffinCaptureCount == 1 ? "" : "s") captured this session.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Spacer(minLength: 0)
                QuietButton("Export…") { exportPuffinCaptures() }
            }
            .padding(.top, 2)
        }
    }

    private func exportPuffinCaptures() {
        model.ble.flushPuffinCaptures()
        guard let src = live.puffinCaptureURL else { return }
        FileExport.exportFile(at: src)
    }

    // MARK: - More (drill rows)

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            navRow("Units & format") { showUnits = true }
            divider
            navRow("Data & sources") { darkScreen = .dataSources }
            divider
            navRow("Automations") { darkScreen = .automations }
            divider
            navRow("About & support") { darkScreen = .support }
        }
    }

    // MARK: - Strap status helpers (mirror SettingsView)

    private var strapStatusTitle: String {
        if live.bonded && live.connected { return String(localized: "Bonded · streaming") }
        if live.connected { return String(localized: "Connected") }
        if live.bonded { return String(localized: "Bonded · idle") }
        return String(localized: "Disconnected")
    }
    private var strapDotColor: Color {
        if live.connected { return theme.dataRecovery }
        if live.bonded { return theme.warning }
        return theme.critical
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
    private func batteryColor(_ pct: Double) -> Color {
        if pct <= 15 { return theme.critical }
        if pct <= 30 { return theme.warning }
        return theme.inkSecondary
    }

    // MARK: - Section scaffolding (Instrumento: overline + rows on paper, no card-in-card)

    @ViewBuilder
    private func section<Rows: View>(_ title: LocalizedStringKey, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            rows()
        }
    }

    private var divider: some View { Divider().overlay(theme.hairline) }

    /// A label-left / control-right form row.
    private func formRow<Control: View>(_ label: LocalizedStringKey,
                                        @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label).font(StrandFont.body).foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .frame(minHeight: 36)
    }

    /// A quiet drill row: ink label + chevron, whole row tappable, opens a sheet.
    private func navRow(_ label: LocalizedStringKey, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Text(label).font(StrandFont.body).foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sibling sheet (DataSources is light · Automations / Support still dark, pinned to .dark)

    @ViewBuilder
    private func darkSheet(_ screen: AjustesDarkScreen) -> some View {
        switch screen {
        case .dataSources:
            // Reskinned to the light «Instrumento» language (FER-338): a light sheet with its own
            // NavigationStack (so «Ver datos importados» pushes the Apple Health viewer). The theme is
            // injected at the root (it doesn't cross the `.sheet` boundary, FER-162); a light sheet from
            // a light tab keeps the status bar honest (no dark pin needed).
            NavigationStack {
                DataSourcesView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { darkScreen = nil }.foregroundStyle(theme.ink)
                        }
                    }
            }
            .instrumentoTheme(theme)
            .environmentObject(model)
            .environmentObject(repo)
            .environmentObject(live)
            .environmentObject(health)
            .environmentObject(behavior)
            .environmentObject(autoBackup)
            .preferredColorScheme(.light)
        case .support:
            // Reskinned to light «Instrumento» (FER-67): a light sheet, theme injected at the root
            // (it doesn't cross the `.sheet` boundary, FER-162); no dark pin needed.
            NavigationStack {
                SupportView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { darkScreen = nil }.foregroundStyle(theme.ink)
                        }
                    }
            }
            .instrumentoTheme(theme)
            .environmentObject(model)
            .environmentObject(repo)
            .environmentObject(live)
            .environmentObject(health)
            .environmentObject(behavior)
            .environmentObject(autoBackup)
            .preferredColorScheme(.light)
        case .automations:
            // Light «Instrumento» now that AutomationsView is reskinned (FER-69); un-pinned from `.dark`
            // in FER-381 (it had stayed dark-pinned, so the light screen showed dark chrome). Theme
            // injected at the root (it doesn't cross the `.sheet` boundary, FER-162).
            NavigationStack {
                AutomationsView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { darkScreen = nil }.foregroundStyle(theme.ink)
                        }
                    }
            }
            .instrumentoTheme(theme)
            .environmentObject(model)
            .environmentObject(repo)
            .environmentObject(live)
            .environmentObject(health)
            .environmentObject(behavior)
            .environmentObject(autoBackup)
            .preferredColorScheme(.light)
        }
    }
}

// MARK: - Units & format (light sheet)

/// «Unidades y formato» — the display-only unit prefs, migrated from `SettingsView.unitsCard` into a
/// light «Instrumento» sheet. Nothing stored changes; this only changes how values are shown.
private struct UnidadesSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Display").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Units & format").font(StrandFont.title1).foregroundStyle(theme.ink)
            }
            Text("Your data is always stored the same way — this only changes how distances, weights, heights and temperatures are shown.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Text("Measurement system").font(StrandFont.body).foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Picker("Measurement system", selection: $unitSystemRaw) {
                        Text("Metric").tag(UnitSystem.metric.rawValue)
                        Text("Imperial").tag(UnitSystem.imperial.rawValue)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                Divider().overlay(theme.hairline)
                HStack(spacing: 16) {
                    Text("Temperature").font(StrandFont.body).foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Picker("Temperature", selection: $temperatureRaw) {
                        Text("Match").tag("")
                        Text("°C").tag(TemperatureUnit.celsius.rawValue)
                        Text("°F").tag(TemperatureUnit.fahrenheit.rawValue)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.paper.ignoresSafeArea())
    }
}

// MARK: - Strap log (light sheet)

/// «Log de la banda» — the raw BLE session log (`live.log`) with Copy / Save, migrated from
/// `SettingsView.strapLogSection`. The diagnostic trail you attach to a bug report. The HARD criterion
/// of FER-337: this stays reachable, here under «Tu strap».
private struct StrapLogSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject var live: LiveState

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your strap").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Strap log").font(StrandFont.title1).foregroundStyle(theme.ink)
            }
            Text("Your strap's connection trail. Attach it to a bug report if something looks off.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if live.log.isEmpty {
                Text("No activity yet. The log fills in as your strap connects.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 10) {
                    QuietButton("Copy") { copyStrapLog() }
                    QuietButton("Save…") { saveStrapLog() }
                    Spacer(minLength: 0)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(live.log.enumerated()), id: \.offset) { idx, line in
                                Text(line).font(StrandFont.mono)
                                    .foregroundStyle(theme.inkSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onChange(of: live.log.count) {
                        if let last = live.log.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.paper.ignoresSafeArea())
    }

    private func strapLogText() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let osName = "iOS"
        let header = "Cénit strap log — \(osName)\nApp: \(v)\n\(osName): "
            + ProcessInfo.processInfo.operatingSystemVersionString + "\n"
            + String(repeating: "-", count: 40) + "\n"
        return header + live.log.joined(separator: "\n")
    }
    private func copyStrapLog() { PlatformPasteboard.copy(strapLogText()) }
    private func saveStrapLog() { FileExport.exportText(strapLogText(), suggestedName: "noop-strap-log.txt") }
}
#endif
