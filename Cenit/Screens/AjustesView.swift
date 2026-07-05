#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol
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
// Pulir pass (handoff «Pulir App Cenit»): profile steppers → wheels; HR-max auto/manual sheet;
// WHOOP 5/MG experimental moved off «Tu banda» into a new «Avanzado» sheet; the lower list grouped
// with overlines + subtitles; a privacy chip + gear icon in the header; Disconnect demoted to a text
// link behind a confirmation. Pure presentation — no store/state contracts change.
//
// Explore · Compare · Workouts are NOT here: they already open from Cuerpo's footer; the old «Más»
// duplicate is gone.

/// Theme wrapper: anchors `\.instrumentoTheme` to the single warm day paper (`.base`), then hands to
/// `AjustesLanding`, which reads the resolved theme from the environment. (FER-398 retired the
/// by-the-hour tint; Ajustes no longer changes colour with the clock.)
struct AjustesView: View {
    var body: some View {
        AjustesLanding()
            .instrumentoTheme(.base)
    }
}

// MARK: - Sheet routing

/// A still-dark sibling screen, presented as a self-contained sheet pinned to `.dark`. Each goes light
/// in its own issue (Datos y fuentes → FER-338, Automatizaciones → FER-69, Acerca de y soporte → FER-67).
private enum AjustesDarkScreen: String, Identifiable {
    case dataSources, automations, support
    var id: String { rawValue }
}

/// Which profile value the wheel sheet is editing (A1).
private enum ProfileWheel: String, Identifiable {
    case age, weight, height
    var id: String { rawValue }
}

// MARK: - Content-fitted sheet

/// Sizes a sheet to its content height (so a short form doesn't open as a giant half-empty card),
/// with `.large` as a fallback when the content is taller than the fitted height (e.g. big Dynamic
/// Type). Same measure-then-detent pattern as `MuscleDetailView`: the content must hug its height
/// (no `maxHeight: .infinity`, no trailing `Spacer`) for the measured size to reflect the content.
private struct FittedSheet: ViewModifier {
    @State private var height: CGFloat = 320
    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { height = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, h in height = h }
            })
            .presentationDetents([.height(height), .large])
            .presentationDragIndicator(.visible)
    }
}
private extension View {
    func fittedSheet() -> some View { modifier(FittedSheet()) }
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
    @EnvironmentObject private var inactivity: InactivityPrefs
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
    @State private var showAdvanced = false
    @State private var showMaxHR = false
    @State private var showStepsCal = false
    @State private var showStepTicks = false
    @State private var showCyclePhase = false
    @AppStorage(CyclePhaseExperiment.enabledKey) private var cyclePhaseOn = false
    @State private var showRitmo = false
    @State private var profileWheel: ProfileWheel? = nil
    @State private var darkScreen: AjustesDarkScreen? = nil
    @State private var confirmDisconnect = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header

                profileSection
                strapSection
                moreSection

                footer
            }
            .padding(.top, NoopMetrics.screenTop)   // shared titled-tab top inset
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
        .sheet(isPresented: $showAdvanced) {
            AdvancedSheet().instrumentoTheme(theme).environmentObject(live).environmentObject(model)
        }
        .sheet(isPresented: $showCyclePhase) {
            CyclePhaseSheet().instrumentoTheme(theme).environmentObject(repo)
        }
        .sheet(isPresented: $showMaxHR) {
            MaxHRSheet().instrumentoTheme(theme).environmentObject(profile)
        }
        .sheet(isPresented: $showStepsCal) {
            StepsCalibrationSheet().instrumentoTheme(theme).environmentObject(profile)
        }
        .sheet(isPresented: $showStepTicks) {
            StepTicksSheet().instrumentoTheme(theme).environmentObject(profile)
        }
        .sheet(isPresented: $showRitmo) {
            RitmoView().instrumentoTheme(theme).environmentObject(repo)
        }
        .sheet(item: $profileWheel) { wheel in
            ProfileWheelSheet(wheel: wheel).instrumentoTheme(theme).environmentObject(profile)
        }
        .sheet(item: $darkScreen) { screen in darkSheet(screen) }
        .confirmationDialog("Disconnect strap?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { model.disconnect() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will stop streaming until you re-scan. Your saved data isn't touched.")
        }
    }

    // MARK: - Header (A6: gear icon + title, privacy chip)

    private var header: some View {
        // The shared titled-tab wordmark (FER-605): same lockup, size and baseline as «Patrones» /
        // «Tendencias» / «Entrenar», so Ajustes lines up with them as you swipe between tabs. The privacy
        // chip rides below as a quiet subline (the lockup's trailing slot stays empty).
        VStack(alignment: .leading, spacing: 10) {
            InstrumentoTabHeader("Ajustes") {
                Image(systemName: "gearshape").font(.system(size: 20)).foregroundStyle(theme.ink)
            }
            privacyChip
        }
        .padding(.bottom, -8)
    }

    /// «En este iPhone · sin cuenta · sin nube» — the offline promise, made visible (A6).
    private var privacyChip: some View {
        Text("On this iPhone · no account · no cloud")
            .font(StrandFont.caption).foregroundStyle(theme.positiveText)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule(style: .continuous).fill(theme.dataRecovery.opacity(0.12))
            )
            .accessibilityLabel("Everything stays on this iPhone. No account, no cloud.")
    }

    // MARK: - Footer (A6: the offline promise, restated)

    private var footer: some View {
        Text("Cénit \(appVersion) · everything is computed on your iPhone · no account · no server")
            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    // MARK: - Profile (A1: steppers → wheels; A2: HR-max → sheet)

    private var profileSection: some View {
        section("Profile") {
            valueRow("Age", value: "\(profile.age)",
                     a11y: "Age, \(profile.age) years") { profileWheel = .age }
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
            valueRow("Weight", value: weightDisplay,
                     a11y: "Weight, \(weightDisplay)") { profileWheel = .weight }
            divider
            valueRow("Height", value: heightDisplay,
                     a11y: "Height, \(heightDisplay)") { profileWheel = .height }
            divider
            valueRow("Max heart rate", value: maxHRDisplay,
                     a11y: "Maximum heart rate, \(maxHRDisplay)") { showMaxHR = true }
            // Pasos por banda: la 4.0 ESTIMA pasos del movimiento (FER-663); el 5/MG lee un contador
            // NATIVO que sobre-cuenta y se calibra con un divisor (FER-665). Cada banda ve solo la suya.
            if WhoopModel.persisted.deviceFamily.estimatesSteps {
                divider
                valueRow("Steps estimate", value: stepsCalDisplay,
                         a11y: "Steps estimate, \(stepsCalDisplay)") { showStepsCal = true }
            } else {
                divider
                valueRow("Steps calibration", value: stepTicksDisplay,
                         a11y: "Steps calibration, \(stepTicksDisplay)") { showStepTicks = true }
            }
        }
    }

    private var weightDisplay: String {
        unitSystem == .imperial
            ? "\(Int(UnitFormatter.kgToPounds(profile.weightKg).rounded())) lb"
            : String(format: "%.1f kg", profile.weightKg)
    }
    private var heightDisplay: String {
        UnitFormatter.heightFromCentimeters(profile.heightCm, system: unitSystem)
    }
    private var maxHRDisplay: String {
        profile.hrMaxOverride > 0
            ? "\(profile.hrMaxOverride) bpm"
            : String(localized: "Auto · \(profile.hrMax) bpm")
    }
    /// One-line state for the «Steps estimate» row (FER-663): manual override, auto-fit, or not yet.
    private var stepsCalDisplay: String {
        if profile.stepsManualCoefficient > 0 { return String(localized: "Manual") }
        if profile.stepsCalibrationCoefficient > 0 { return String(localized: "Auto") }
        return String(localized: "Not calibrated")
    }
    /// One-line state for the 5/MG «Steps calibration» row (FER-665): the divisor, or «Off» at 1.0.
    private var stepTicksDisplay: String {
        profile.stepTicksPerStep > 1.0
            ? String(format: "÷ %.1f", profile.stepTicksPerStep)
            : String(localized: "Off")
    }

    // MARK: - Your strap (A4: status + action + log only; A7: disconnect demoted)

    private var strapSection: some View {
        section("Your strap") {
            HStack(spacing: 10) {
                Circle().fill(strapDotColor).frame(width: 8, height: 8)
                Text(strapStatusTitle).font(StrandFont.subhead).foregroundStyle(strapDotColor)
                Spacer(minLength: 8)
                if let pct = live.batteryPct {
                    Text(live.charging == true ? "\(Int(pct.rounded()))% · Charging" : "\(Int(pct.rounded()))%")
                        .font(StrandFont.bodyNumber).foregroundStyle(theme.batteryColor(forLevel: pct))
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)

            Text(strapStatusDetail).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                QuietButton("Re-scan") { model.scan() }
                Button { confirmDisconnect = true } label: {
                    Text("Disconnect").font(StrandFont.subhead)
                        .foregroundStyle((!live.connected && !live.bonded) ? theme.inkDim : theme.inkTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!live.connected && !live.bonded)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)

            divider
            navRow("Strap log") { showLog = true }
        }
    }

    // MARK: - More (A5: grouped drill rows with overlines + subtitles)

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            section("App") {
                navRow("Units & format", subtitle: unitsSubtitle) { showUnits = true }
                divider
                navRow("Automations", subtitle: Text("Zone alerts, reminders")) { darkScreen = .automations }
            }
            section("Data") {
                navRow("Data & sources", subtitle: Text("WHOOP · Apple Health · backup")) { darkScreen = .dataSources }
            }
            section("Experimental") {
                navRow("Ritmo", subtitle: Text("Regularidad de tu ritmo, latido a latido")) { showRitmo = true }
                divider
                navRow("Cycle phase",
                       subtitle: Text(cyclePhaseOn ? "Experiment · on" : "Experiment · off")) { showCyclePhase = true }
            }
            section("More") {
                navRow("Advanced", subtitle: Text("WHOOP 5/MG probes, frames")) { showAdvanced = true }
                divider
                navRow("About & support",
                       subtitle: Text("Version \(appVersion) · help · licenses")) { darkScreen = .support }
            }
        }
    }

    /// Live units summary, e.g. «Metric · °C» (A5).
    private var unitsSubtitle: Text {
        let sys = Text(unitSystem == .metric ? "Metric" : "Imperial")
        let temp: String
        switch temperatureRaw {
        case TemperatureUnit.celsius.rawValue:    temp = "°C"
        case TemperatureUnit.fahrenheit.rawValue: temp = "°F"
        default:                                  temp = "°C/°F"
        }
        return sys + Text(verbatim: " · \(temp)")
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

    /// A label-left / value + chevron row that opens a wheel sheet (A1/A2).
    private func valueRow(_ label: LocalizedStringKey, value: String, a11y: String,
                          open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Text(label).font(StrandFont.body).foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Text(value).font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
        .accessibilityHint("Opens a picker")
    }

    /// A quiet drill row: ink label (+ optional subtitle) + chevron, whole row tappable.
    private func navRow(_ label: LocalizedStringKey, subtitle: Text? = nil,
                        open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(StrandFont.body).foregroundStyle(theme.ink)
                    if let subtitle {
                        subtitle.font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
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
            .environmentObject(inactivity)
            .environmentObject(autoBackup)
            .preferredColorScheme(.light)
        }
    }
}

// MARK: - Profile wheel (A1: a focused wheel for Age / Weight / Height)

/// «Editar perfil» — a single value behind a `Picker(.wheel)`, honouring the imperial display
/// preference (the wheel itself shows lb / ft·in and writes the SI equivalent back). Replaces the
/// per-row steppers on the landing. Stored data is unchanged; only how it's entered.
private struct ProfileWheelSheet: View {
    let wheel: ProfileWheel
    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profile").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(title).font(StrandFont.title1).foregroundStyle(theme.ink)
            }

            wheelBody
                .frame(maxWidth: .infinity)
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paper.ignoresSafeArea())
        .fittedSheet()
    }

    private var title: LocalizedStringKey {
        switch wheel {
        case .age: return "Age"
        case .weight: return "Weight"
        case .height: return "Height"
        }
    }

    @ViewBuilder private var wheelBody: some View {
        switch wheel {
        case .age:
            Picker("Age", selection: $profile.age) {
                ForEach(13...100, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel).labelsHidden().tint(theme.ink)
        case .weight:
            if unitSystem == .imperial {
                let pounds = Binding<Double>(
                    get: { UnitFormatter.kgToPounds(profile.weightKg) },
                    set: { profile.weightKg = UnitFormatter.poundsToKg($0) })
                let opts = Array(stride(from: 66.0, through: 551.0, by: 1))
                let lb = snapped(pounds, options: opts)
                Picker("Weight in pounds", selection: lb) {
                    ForEach(opts, id: \.self) { Text("\(Int($0)) lb").tag($0) }
                }
                .pickerStyle(.wheel).labelsHidden().tint(theme.ink)
            } else {
                let opts = Array(stride(from: 30.0, through: 250.0, by: 0.5))
                let kg = snapped($profile.weightKg, options: opts)
                Picker("Weight in kilograms", selection: kg) {
                    ForEach(opts, id: \.self) { Text(String(format: "%.1f kg", $0)).tag($0) }
                }
                .pickerStyle(.wheel).labelsHidden().tint(theme.ink)
            }
        case .height:
            if unitSystem == .imperial {
                let inchesValue = Binding<Double>(
                    get: { UnitFormatter.cmToInches(profile.heightCm).rounded() },
                    set: { profile.heightCm = $0 * UnitFormatter.centimetersPerInch })
                let opts = Array(stride(from: 47.0, through: 91.0, by: 1))
                let inches = snapped(inchesValue, options: opts)
                Picker("Height in inches", selection: inches) {
                    ForEach(opts, id: \.self) { v -> Text in
                        let ft = Int(v) / 12, inch = Int(v) % 12
                        return Text("\(ft)′ \(inch)″")
                    }
                }
                .pickerStyle(.wheel).labelsHidden().tint(theme.ink)
            } else {
                let opts = Array(stride(from: 120.0, through: 230.0, by: 1))
                let cm = snapped($profile.heightCm, options: opts)
                Picker("Height in centimetres", selection: cm) {
                    ForEach(opts, id: \.self) { Text("\(Int($0)) cm").tag($0) }
                }
                .pickerStyle(.wheel).labelsHidden().tint(theme.ink)
            }
        }
    }

    /// A wheel-safe binding: the selection always lands on a tag in `options` (snaps the stored value
    /// to the nearest grid point), so the picker never shows an empty selection for an off-grid value.
    private func snapped(_ base: Binding<Double>, options: [Double]) -> Binding<Double> {
        Binding(
            get: { options.min(by: { abs($0 - base.wrappedValue) < abs($1 - base.wrappedValue) }) ?? base.wrappedValue },
            set: { base.wrappedValue = $0 })
    }
}

// MARK: - Max heart rate (A2: auto / manual)

/// «FC máxima» — a focused sheet over `profile.hrMaxOverride` (0 = auto). The segmented control is pure
/// UI sugar on that one value: Auto shows the Tanaka estimate large; Manual reveals a wheel writing the
/// override (and notes it's anulando the auto estimate).
private struct MaxHRSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var profile: ProfileStore
    /// Local mode toggle. Drives the override: Auto → 0; Manual → keep/seed a concrete bpm.
    @State private var manual = false

    /// The Tanaka auto estimate (208 − 0.7·age), shown in Auto and referenced in Manual.
    private var autoBpm: Int { Int((208 - 0.7 * Double(profile.age)).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profile").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Max heart rate").font(StrandFont.title1).foregroundStyle(theme.ink)
            }

            Picker("Mode", selection: $manual) {
                Text("Automatic").tag(false)
                Text("Manual").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: manual) { _, isManual in
                if isManual { if profile.hrMaxOverride == 0 { profile.hrMaxOverride = autoBpm } }
                else { profile.hrMaxOverride = 0 }
            }

            if manual {
                Picker("Maximum heart rate", selection: $profile.hrMaxOverride) {
                    ForEach(100...230, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.wheel).labelsHidden().tint(theme.ink)
                .frame(maxWidth: .infinity)
                Text("Overriding the automatic estimate (\(autoBpm)).")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
            } else {
                VStack(alignment: .center, spacing: 4) {
                    Text("\(autoBpm)")
                        .font(StrandFont.number(48)).foregroundStyle(theme.ink)
                    Text("bpm · Tanaka").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                Text("Estimated from your age (208 − 0.7 × age). Set it manually if you know your true max.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paper.ignoresSafeArea())
        .fittedSheet()
        .onAppear { manual = profile.hrMaxOverride > 0 }
    }
}

// MARK: - Steps estimate calibration (FER-663 — WHOOP 4.0 only)

/// «Estimación de pasos» — a focused sheet over the StepsEstimateEngine calibration. Auto shows the
/// current fit state (days used + confidence, or how many more overlapping days are needed); Manual
/// reveals a slider writing `profile.stepsManualCoefficient` (0 = auto), for users with no phone step
/// history to fit against. The copy always says ESTIMATE — the 4.0's motion data can't count strides.
private struct StepsCalibrationSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var profile: ProfileStore
    /// Local mode toggle. Drives the override: Auto → 0; Manual → keep/seed a concrete coefficient.
    @State private var manual = false

    /// Slider headroom: generous over whatever the auto-fit found so a manual nudge in either
    /// direction is reachable; floor keeps the slider usable before any fit exists.
    private var sliderMax: Double {
        max(profile.stepsCalibrationCoefficient, profile.stepsManualCoefficient, 50) * 2
    }
    /// Full fit line with a coarse confidence word (≥0.7 high, ≥0.4 medium, else low). Three whole
    /// sentences (not an interpolated word) so the es translation can agree in gender («confianza alta»).
    private var fitLine: Text {
        let n = profile.stepsCalibrationSampleDays
        let c = profile.stepsCalibrationConfidence
        if c >= 0.7 { return Text("Fit from \(n) days your iPhone also counted steps. Confidence: high.") }
        if c >= 0.4 { return Text("Fit from \(n) days your iPhone also counted steps. Confidence: medium.") }
        return Text("Fit from \(n) days your iPhone also counted steps. Confidence: low.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profile").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Steps estimate").font(StrandFont.title1).foregroundStyle(theme.ink)
            }

            Picker("Mode", selection: $manual) {
                Text("Automatic").tag(false)
                Text("Manual").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: manual) { _, isManual in
                if isManual {
                    if profile.stepsManualCoefficient == 0 {
                        profile.stepsManualCoefficient = profile.stepsCalibrationCoefficient > 0
                            ? profile.stepsCalibrationCoefficient : 50
                    }
                } else { profile.stepsManualCoefficient = 0 }
            }

            if manual {
                VStack(alignment: .center, spacing: 4) {
                    Text(String(format: "%.0f", profile.stepsManualCoefficient))
                        .font(StrandFont.number(48)).foregroundStyle(theme.ink)
                    Text("steps per unit of motion").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
                .frame(maxWidth: .infinity)
                Slider(value: $profile.stepsManualCoefficient, in: 1...sliderMax, step: 1)
                    .tint(theme.ink)
                    .accessibilityLabel(Text("Steps per unit of motion, \(Int(profile.stepsManualCoefficient))"))
                Text("Raise it if the estimate runs low against a day you know; lower it if it runs high.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Auto: either a fitted coefficient (big number + fit line) or not-yet-calibrated
                // («—» + how many more phone-counted days are needed). Same layout, only the values differ.
                let calibrated = profile.stepsCalibrationCoefficient > 0
                VStack(alignment: .center, spacing: 4) {
                    Text(calibrated ? String(format: "%.0f", profile.stepsCalibrationCoefficient) : "—")
                        .font(StrandFont.number(48)).foregroundStyle(calibrated ? theme.ink : theme.inkDim)
                    Text(calibrated ? "steps per unit of motion" : "not calibrated yet")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                Group {
                    if calibrated {
                        fitLine
                    } else {
                        Text("Needs \(max(0, StepsEstimateEngine.minCalibrationDays - profile.stepsCalibrationSampleDays)) more days where your iPhone also counted steps — or set the coefficient manually.")
                    }
                }
                .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text("A WHOOP 4.0 sends no step count, so Cénit estimates steps from wrist motion calibrated against your iPhone. It is always an estimate, never an exact count.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paper.ignoresSafeArea())
        .fittedSheet()
        .onAppear { manual = profile.stepsManualCoefficient > 0 }
    }
}

// MARK: - Steps calibration (FER-665 — WHOOP 5/MG native counter divisor)

/// «Calibración de pasos» — a focused sheet over `profile.stepTicksPerStep`, the divisor for the 5/MG
/// native step counter, which over-counts. 1.0 = off (raw pass-through); raise it if the strap reads
/// more steps than you took. Clamped 0.5–30 (observed overcount reaches ~24×). Distinct from the 4.0
/// «Steps estimate» sheet — this scales a REAL counter, it doesn't fit one from motion.
private struct StepTicksSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profile").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Steps calibration").font(StrandFont.title1).foregroundStyle(theme.ink)
            }

            VStack(alignment: .center, spacing: 4) {
                Text(profile.stepTicksPerStep > 1.0 ? String(format: "÷ %.1f", profile.stepTicksPerStep)
                                                    : String(localized: "Off"))
                    .font(StrandFont.number(48))
                    .foregroundStyle(profile.stepTicksPerStep > 1.0 ? theme.ink : theme.inkDim)
                Text("counter ticks per real step").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            .frame(maxWidth: .infinity)

            Slider(value: $profile.stepTicksPerStep, in: 1...30, step: 0.5)
                .tint(theme.ink)
                .accessibilityLabel(Text("Counter ticks per real step, \(String(format: "%.1f", profile.stepTicksPerStep))"))

            Text("Your WHOOP 5.0/MG counts steps from a wrist counter that tends to read high. If it shows more steps than you actually took, raise this until it matches a day you can check. Leave it at Off (1.0) to use the raw count.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paper.ignoresSafeArea())
        .fittedSheet()
    }
}

// MARK: - Advanced (A3: WHOOP 5/MG experimental, moved off «Tu banda»)

/// «Avanzado» — the opt-in WHOOP 5/MG protocol probes + raw-frame capture (off by default), moved out
/// of «Tu banda» where they only mattered to a 5/MG owner. The frame Export… button lives here now,
/// shown only when there are captured frames this session (HARD criterion: don't lose Export).
private struct AdvancedSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var model: AppModel
    @AppStorage(PuffinExperiment.defaultsKey) private var puffinExperiments = false
    @AppStorage(PuffinFrameRecorder.enabledKey) private var puffinCapture = false

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Advanced").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("WHOOP 5/MG probes").font(StrandFont.title1).foregroundStyle(theme.ink)
            }
            Text("Experimental tools for the newer WHOOP 5 and MG straps. They have no effect on a WHOOP 4.0.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $puffinExperiments) {
                    Text("WHOOP 5/MG protocol probes").font(StrandFont.body).foregroundStyle(theme.ink)
                }
                .toggleStyle(.instrumento)
                Text("On a 5/MG connection Cénit sends a probe after the handshake and logs what comes back. No effect on WHOOP 4.0.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(theme.hairline)

                Toggle(isOn: $puffinCapture) {
                    Text("Record 5/MG frames to a file").font(StrandFont.body).foregroundStyle(theme.ink)
                }
                .toggleStyle(.instrumento)
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
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paper.ignoresSafeArea())
        .fittedSheet()
    }

    private func exportPuffinCaptures() {
        model.ble.flushPuffinCaptures()
        guard let src = live.puffinCaptureURL else { return }
        FileExport.exportFile(at: src)
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
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paper.ignoresSafeArea())
        .fittedSheet()
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
