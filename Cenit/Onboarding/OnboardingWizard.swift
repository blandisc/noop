import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import WhoopStore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - OnboardingWizard  ·  «Instrumento diurno» (light)
//
// First-run setup, rebuilt light (FER-358, which absorbed the F2 re-skin). Apple
// Health is the BASE everyone connects; the WHOOP strap is an OPTIONAL layer on top.
// No dead ends: skipping Health and having no strap still lands you in the app.
//
// Flow (additive, ~6 screens):
//   welcome        — Cénit + "tus datos, nada en la nube" (one honest line)
//   appleHealth    — connect the base (with "Not now"); 5 states
//   whoopQuestion  — ¿tienes un WHOOP?  Sí → pairing · No → straight to profile
//   prepare/scan/bonded — pairing (only on the "Sí" branch)
//   profile        — age / sex / weight / height
//   importData     — optional history import
//   done           — "Enter Cénit" → onFinished()
//
// Surface is `InstrumentoTheme.base.paper`; color appears ONLY on a real measured
// state (verdict-green for "connected", critical-red for "denied"). CTAs are the
// shared InkButton / OutlineButton (hierarchy by ink fill, not color).

public struct OnboardingWizard: View {

    /// Called when the user finishes (or skips to the end of) onboarding.
    public var onFinished: () -> Void

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    private enum Step: Int, CaseIterable {
        case welcome, appleHealth, whoopQuestion, prepare, scan, bonded, profile, importData, done
        var isFirst: Bool { self == .welcome }
        var isLast: Bool { self == .done }
        /// Pairing steps live only on the "I have a WHOOP" branch.
        var isPairing: Bool { self == .prepare || self == .scan || self == .bonded }
    }

    @State private var step: Step = .welcome
    /// Set by the whoopQuestion branch; drives whether pairing steps are visited.
    @State private var hasWhoop = true

    public var body: some View {
        ZStack {
            InstrumentoTheme.base.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 28)
                    .padding(.top, 18)

                ZStack {
                    switch step {
                    case .welcome:       WelcomeStep(onContinue: advance)
                    case .appleHealth:   AppleHealthStep(onContinue: advance)
                    case .whoopQuestion: WhoopQuestionStep(onChoose: choose)
                    case .prepare:       PrepareStep(onContinue: advance)
                    case .scan:          ScanStep(onContinue: advance)
                    case .bonded:        BondedStep(onContinue: advance)
                    case .profile:       ProfileStep(onContinue: advance)
                    case .importData:    ImportStep(onContinue: advance)
                    case .done:          DoneStep(onFinish: onFinished)
                    }
                }
                .frame(maxWidth: 560, maxHeight: .infinity)
                .transition(stepTransition)
                .id(step)
                .padding(.horizontal, NoopMetrics.screenPadding)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .instrumentoTheme(.base)
        .preferredColorScheme(.light)
        // Isolated live observation — slides Scan → celebration on bond without
        // subscribing the whole wizard to per-tick updates.
        .background(BondWatcher(onBonded: handleBond))
    }

    private func handleBond() {
        if step == .scan { withAnimation(StrandMotion.hero) { step = .bonded } }
    }

    // MARK: Top bar (just a quiet Back affordance)

    @ViewBuilder
    private var topBar: some View {
        HStack {
            if step.isFirst {
                Color.clear.frame(width: 44, height: 28)
            } else {
                Button(action: back) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(StrandFont.subhead)
                    .foregroundStyle(InstrumentoTheme.base.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            Spacer()
        }
    }

    // MARK: Navigation (skips pairing when there's no WHOOP)

    private func advance() {
        var next = Step(rawValue: step.rawValue + 1)
        if !hasWhoop {
            while let n = next, n.isPairing { next = Step(rawValue: n.rawValue + 1) }
        }
        guard let n = next else { onFinished(); return }
        withAnimation(StrandMotion.gentle) { step = n }
    }

    private func back() {
        var prev = Step(rawValue: step.rawValue - 1)
        if !hasWhoop {
            while let p = prev, p.isPairing { prev = Step(rawValue: p.rawValue - 1) }
        }
        guard let p = prev else { return }
        withAnimation(StrandMotion.gentle) { step = p }
    }

    private func choose(_ value: Bool) {
        hasWhoop = value
        advance()
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

/// Hidden, isolated observer — fires `onBonded` when the strap bonds, keeping the
/// main wizard body out of the per-tick re-render path.
private struct BondWatcher: View {
    @EnvironmentObject private var live: LiveState
    let onBonded: () -> Void
    var body: some View {
        Color.clear.onChange(of: live.bonded) { _, newValue in if newValue { onBonded() } }
    }
}

// MARK: - Shared shell

/// One light page: a scrollable column on paper. Title/overline/body are the
/// caller's; this just gives the consistent margins and scroll behaviour so every
/// step survives Dynamic Type with its CTA reachable.
private struct StepShell<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        // minHeight = viewport so inner Spacers push the CTA to the foot, while
        // Dynamic Type overflow still scrolls (CTA stays reachable at AX5).
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                .padding(.vertical, NoopMetrics.space2)
            }
        }
    }
}

private struct Overline: View {
    let text: LocalizedStringKey
    @Environment(\.instrumentoTheme) private var theme
    var body: some View {
        Text(text).instrumentoOverline().foregroundStyle(theme.inkTertiary)
    }
}

// MARK: - Step · Welcome

private struct WelcomeStep: View {
    let onContinue: () -> Void
    @Environment(\.instrumentoTheme) private var theme
    var body: some View {
        StepShell {
            Spacer(minLength: NoopMetrics.sectionGap)
            Text("Cénit")
                .instrumentoHero(56)
                .foregroundStyle(theme.ink)
            Text("Your data, none of the cloud.")
                .font(StrandFont.title2)
                .foregroundStyle(theme.inkSecondary)
                .padding(.top, NoopMetrics.space1)
            Text("Cénit reads your recovery, sleep and strain and keeps them only on your iPhone. No account, no servers. Give it a few days of data and you'll start to see your patterns.")
                .font(StrandFont.body)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, NoopMetrics.sectionGap)
            Spacer(minLength: NoopMetrics.sectionGap)
            InkButton("Get started", action: onContinue)
        }
    }
}

// MARK: - Step · Apple Health (the base)

private struct AppleHealthStep: View {
    let onContinue: () -> Void
    @EnvironmentObject private var health: HealthKitBridge
    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var requesting = false

    var body: some View {
        Group {
            switch health.auth {
            case .unknown:     priming
            case .authorized:  granted
            case .denied:      denied
            case .unavailable: unavailable
            }
        }
        // If Health isn't available, don't strand the user on a dead screen.
        .onAppear { if health.auth == .unavailable { onContinue() } }
    }

    // Initial priming + the request, in flight ("Connecting…").
    private var priming: some View {
        StepShell {
            Overline(text: "Step 1 · The base")
            Text("Conecta Apple Health")
                .font(StrandFont.title1)
                .foregroundStyle(theme.ink)
                .padding(.top, NoopMetrics.space2)
            Text("It's the base of your data in Cénit.")
                .font(StrandFont.body)
                .foregroundStyle(theme.inkSecondary)
                .padding(.top, NoopMetrics.space2)
            Text("Cénit reads your sleep, steps, workouts, weight and heart rate from Apple Health to give you an honest read of your body.")
                .font(StrandFont.body)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, NoopMetrics.sectionGap)

            Rectangle().fill(theme.hairline).frame(height: 1)
                .padding(.top, NoopMetrics.sectionGap)
            HStack(alignment: .top, spacing: NoopMetrics.space2) {
                Image(systemName: "lock.fill")
                    .font(StrandFont.glyph(.chevron))
                    .foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)
                Text("Everything stays on your iPhone. Cénit doesn't upload anything to any server.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, NoopMetrics.gap)

            Spacer(minLength: NoopMetrics.sectionGap)
            InkButton(requesting ? "Connecting…" : "Conectar Apple Health") {
                guard !requesting else { return }
                requesting = true
                Task {
                    await health.requestAuthorization()
                    requesting = false
                    if health.auth == .authorized { await health.sync() }
                }
            }
            .disabled(requesting)
            OutlineButton("Not now", action: onContinue)
                .opacity(requesting ? 0.45 : 1)
                .disabled(requesting)
        }
    }

    private var granted: some View {
        CenteredState(
            glyph: "checkmark.circle.fill",
            glyphColor: theme.verdict,
            title: "Apple Health connected.",
            titleColor: theme.verdict,
            message: "You've got the base. Let's keep going."
        ) {
            InkButton("Continue", action: onContinue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Apple Health connected")
    }

    private var denied: some View {
        CenteredState(
            glyph: "exclamationmark.circle",
            glyphColor: theme.critical,
            title: "Access turned off",
            titleColor: theme.ink,
            message: "You left Apple Health access turned off. You can turn it on anytime in Settings. Cénit works without it, with less detail."
        ) {
            OutlineButton("Open Settings") {
                #if canImport(UIKit)
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                #endif
            }
            OutlineButton("Continue anyway", action: onContinue)
        }
    }

    private var unavailable: some View {
        CenteredState(
            glyph: "heart.slash",
            glyphColor: theme.inkTertiary,
            title: "Apple Health isn't available on this iPhone.",
            titleColor: theme.ink,
            message: nil
        ) {
            InkButton("Continue", action: onContinue)
        }
    }
}

/// A centered single-focus state (granted / denied / unavailable / done): a glyph,
/// a title, an optional message, and the caller's button stack pinned at the foot.
private struct CenteredState<Buttons: View>: View {
    let glyph: String
    let glyphColor: Color
    let title: LocalizedStringKey
    let titleColor: Color
    let message: LocalizedStringKey?
    @ViewBuilder var buttons: () -> Buttons
    @Environment(\.instrumentoTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: NoopMetrics.sectionGap)
            VStack(spacing: NoopMetrics.gap) {
                Image(systemName: glyph)
                    .font(.system(size: 48, weight: .regular)) // token-exempt: glifo hero 48pt fuera de banda
                    .foregroundStyle(glyphColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(StrandFont.title2)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(StrandFont.body)
                        .foregroundStyle(theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: NoopMetrics.sectionGap)
            VStack(spacing: NoopMetrics.gap) { buttons() }
        }
    }
}

// MARK: - Step · ¿Tienes un WHOOP?

private struct WhoopQuestionStep: View {
    let onChoose: (Bool) -> Void
    @Environment(\.instrumentoTheme) private var theme
    var body: some View {
        StepShell {
            Overline(text: "Step 2 · Sharpen the signal")
            Text("Do you have a WHOOP strap?")
                .font(StrandFont.title1)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, NoopMetrics.space2)
            Text("It sits on top of Apple Health and sharpens the signal: continuous HRV and strap-grade recovery.")
                .font(StrandFont.body)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, NoopMetrics.gap)
            Spacer(minLength: NoopMetrics.sectionGap)
            InkButton("Yes, I have a WHOOP") { onChoose(true) }
            OutlineButton("I don't have one") { onChoose(false) }
        }
    }
}

// MARK: - Step · Prepare (wear + charge + Bluetooth priming)

private struct PrepareStep: View {
    let onContinue: () -> Void
    @Environment(\.instrumentoTheme) private var theme
    var body: some View {
        StepShell {
            Overline(text: "Step 3 · Your strap")
            Text("Get your strap ready")
                .font(StrandFont.title1)
                .foregroundStyle(theme.ink)
                .padding(.top, NoopMetrics.space2)
            Text("A moment before connecting.")
                .font(StrandFont.body)
                .foregroundStyle(theme.inkSecondary)
                .padding(.top, NoopMetrics.space2)

            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                Checkline("Wear it snug: the sensor needs skin contact.")
                Checkline("Make sure it has charge.")
                Checkline("Keep your iPhone's Bluetooth on.")
            }
            .padding(.top, NoopMetrics.sectionGap)

            Rectangle().fill(theme.hairline).frame(height: 1)
                .padding(.top, NoopMetrics.sectionGap)
            HStack(alignment: .top, spacing: NoopMetrics.space2) {
                Image(systemName: "wave.3.right")
                    .font(StrandFont.glyph(.chevron))
                    .foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)
                Text("In a moment your iPhone will ask for Bluetooth permission. Choose Allow so Cénit can find your strap. The connection is direct: nothing goes through the cloud.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, NoopMetrics.gap)

            Spacer(minLength: NoopMetrics.sectionGap)
            InkButton("Find my strap", action: onContinue)
        }
    }
}

// MARK: - Step · Scan (sober, no radar)

private struct ScanStep: View {
    let onContinue: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @Environment(\.instrumentoTheme) private var theme

    @State private var scanning = false
    @State private var showHelp = false
    @State private var autoScanStarted = false

    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue
    private var selectedModel: WhoopModel { WhoopModel(rawValue: selectedModelRaw) ?? .whoop4 }

    var body: some View {
        StepShell {
            Overline(text: "Step 3 · Connect")
            Text("Looking for your strap…")
                .font(StrandFont.title1)
                .foregroundStyle(theme.ink)
                .padding(.top, NoopMetrics.space2)
            statusLine
                .padding(.top, NoopMetrics.gap)

            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text("Which strap?").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                Picker("Which strap?", selection: Binding(
                    get: { selectedModel },
                    set: { restartScan(for: $0) }
                )) {
                    ForEach(WhoopModel.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.top, NoopMetrics.sectionGap)

            if showHelp { reassurance.padding(.top, NoopMetrics.gap) }

            Spacer(minLength: NoopMetrics.sectionGap)
            OutlineButton(scanning ? "Searching…" : "Search again") { startScan() }
                .disabled(scanning)
            OutlineButton("Continue without pairing", action: onContinue)
        }
        .onAppear(perform: startAutoScanIfNeeded)
        .onDisappear { scanning = false }
    }

    @ViewBuilder
    private var statusLine: some View {
        if live.bonded {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(StrandFont.subhead).foregroundStyle(theme.verdict)
        } else if live.connected {
            Label("Connecting…", systemImage: "dot.radiowaves.left.and.right")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
        } else if scanning {
            Label("Searching…", systemImage: "dot.radiowaves.left.and.right")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
        } else {
            Label("Ready to search", systemImage: "magnifyingglass")
                .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
        }
    }

    private var reassurance: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            Text("Not showing up? That's normal.")
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
            Text("WHOOP straps don't show up in your iPhone's Settings › Bluetooth: they use a custom profile only apps like Cénit can see. There's nothing to pair there.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Checkline("It's charged and worn: the sensor wakes with skin contact.")
            Checkline("The WHOOP app isn't holding it. Only one host at a time: close it or turn off its Bluetooth.")
            Checkline("It's within a metre of your iPhone.")
        }
        .padding(NoopMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func startScan(model scanModel: WhoopModel? = nil) {
        let modelToScan = scanModel ?? selectedModel
        scanning = true
        showHelp = false
        model.scan(model: modelToScan)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if !live.bonded {
                scanning = false
                withAnimation(StrandMotion.gentle) { showHelp = true }
            }
        }
    }

    private func restartScan(for newModel: WhoopModel) {
        selectedModelRaw = newModel.rawValue
        guard !live.bonded else { return }
        model.disconnect()
        startScan(model: newModel)
    }

    private func startAutoScanIfNeeded() {
        guard !autoScanStarted, !live.bonded, !live.connected else { return }
        autoScanStarted = true
        startScan()
    }
}

// MARK: - Step · Bonded (sober celebration)

private struct BondedStep: View {
    let onContinue: () -> Void
    @EnvironmentObject private var live: LiveState
    @Environment(\.instrumentoTheme) private var theme
    var body: some View {
        CenteredState(
            glyph: "checkmark.circle.fill",
            glyphColor: theme.verdict,
            title: "Done. You're connected.",
            titleColor: theme.ink,
            message: batteryLine
        ) {
            InkButton("Continue", action: onContinue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connected")
    }
    private var batteryLine: LocalizedStringKey {
        if let pct = live.batteryPct {
            return "Your strap is connected · \(Int(pct))% battery."
        }
        return "Your strap is connected and ready."
    }
}

// MARK: - Step · Profile

private struct ProfileStep: View {
    let onContinue: () -> Void
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var health: HealthKitBridge
    @Environment(\.instrumentoTheme) private var theme
    @State private var fromHealth: Set<String> = []
    @State private var didAutoFill = false

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    private let sexes: [(String, String)] = [
        ("male", "Hombre"), ("female", "Mujer"), ("nonbinary", "Otro")
    ]

    var body: some View {
        StepShell {
            Overline(text: "About you")
            Text("About you")
                .font(StrandFont.title1)
                .foregroundStyle(theme.ink)
                .padding(.top, NoopMetrics.space2)
            Text("To compute your heart-rate zones and your baselines.")
                .font(StrandFont.body)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, NoopMetrics.space2)

            VStack(spacing: NoopMetrics.gap) {
                Stepper(value: $profile.age, in: 13...100) {
                    FieldRow(label: "Age", value: "\(profile.age)")
                }
                .tint(theme.inkSecondary)
                Divider().overlay(theme.hairline)
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Overline(text: "Sex")
                    Picker("Sex", selection: $profile.sex) {
                        ForEach(sexes, id: \.0) { key, label in Text(label).tag(key) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Divider().overlay(theme.hairline)
                Stepper(value: $profile.weightKg, in: 30...250, step: 0.5) {
                    FieldRow(label: "Weight", value: UnitFormatter.massFromKilograms(profile.weightKg, system: unitSystem))
                }
                .tint(theme.inkSecondary)
                Divider().overlay(theme.hairline)
                Stepper(value: $profile.heightCm, in: 120...230, step: 1) {
                    FieldRow(label: "Height", value: UnitFormatter.heightFromCentimeters(profile.heightCm, system: unitSystem))
                }
                .tint(theme.inkSecondary)
            }
            .padding(NoopMetrics.cardPadding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            .padding(.top, NoopMetrics.sectionGap)

            if !fromHealth.isEmpty {
                HStack(spacing: NoopMetrics.space2) {
                    Image(systemName: "heart.fill").font(StrandFont.glyph(.chevron)).foregroundStyle(theme.dataSpO2)
                    Text("From Apple Health · editable")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                .padding(.top, NoopMetrics.space2)
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: NoopMetrics.space2) {
                Image(systemName: "bolt.heart").foregroundStyle(theme.inkTertiary)
                Text("Estimated max heart rate · \(profile.hrMax) bpm")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(.top, NoopMetrics.gap)

            Spacer(minLength: NoopMetrics.sectionGap)
            InkButton("Continue", action: onContinue)
        }
        .task { await autoFill() }
    }

    /// Prellena el Perfil desde Apple Health una sola vez al aparecer (FER-361): aplica solo los campos
    /// que Health tiene (parcial, campo por campo) y marca su procedencia. Las ediciones del usuario son
    /// posteriores, así que ganan.
    private func autoFill() async {
        guard !didAutoFill, health.auth == .authorized else { return }
        didAutoFill = true
        let c = await health.readProfileCharacteristics()
        var marked: Set<String> = []
        if let s = c.sex { profile.sex = s; marked.insert("sex") }
        if let a = c.age, (13...100).contains(a) { profile.age = a; marked.insert("age") }
        if let w = c.weightKg, (30...250).contains(w) { profile.weightKg = w; marked.insert("weight") }
        if let h = c.heightCm, (120...230).contains(h) { profile.heightCm = h; marked.insert("height") }
        fromHealth = marked
    }
}

// MARK: - Step · Import (optional)

private struct ImportStep: View {
    let onContinue: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.instrumentoTheme) private var theme
    @State private var showingImporter = false
    @State private var importTarget: ImportTarget = .whoop

    var body: some View {
        StepShell {
            Overline(text: "Your history")
            Text("Bring your history")
                .font(StrandFont.title1)
                .foregroundStyle(theme.ink)
                .padding(.top, NoopMetrics.space2)
            Text("Optional. Fill your dashboard from day one.")
                .font(StrandFont.body)
                .foregroundStyle(theme.inkSecondary)
                .padding(.top, NoopMetrics.space2)
            Text("A WHOOP export backfills recovery, strain, sleep and workouts. An Apple Health export adds HR, HRV, sleep, blood oxygen, steps and weight.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, NoopMetrics.gap)

            VStack(spacing: NoopMetrics.gap) {
                ImportRow(title: model.isImporting(.whoop) ? "Importing…" : "Import WHOOP export",
                          systemImage: "tray.and.arrow.down",
                          disabled: model.hasActiveImport) { presentImporter(.whoop) }
                ImportRow(title: model.isImporting(.appleHealth) ? "Importing…" : "Import Apple Health export",
                          systemImage: "heart.fill",
                          disabled: model.hasActiveImport) { presentImporter(.appleHealth) }
            }
            .padding(.top, NoopMetrics.sectionGap)

            if model.hasActiveImport {
                HStack(spacing: NoopMetrics.space2) {
                    ProgressView().controlSize(.small).tint(theme.inkSecondary)
                    if let n = model.appleHealthImportProgress {
                        Text("\(n) registros")
                            .font(StrandFont.footnote)
                            .foregroundStyle(theme.inkTertiary)
                            .monospacedDigit()
                    }
                }
                .padding(.top, NoopMetrics.gap)
            }

            if let summary = lastSummary {
                Text(summary)
                    .font(StrandFont.subhead)
                    .foregroundStyle(model.importFailed(importKind) ? theme.critical : theme.verdict)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, NoopMetrics.gap)
            }

            Spacer(minLength: NoopMetrics.sectionGap)
            OutlineButton("Not now", action: onContinue)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importTarget.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result, for: importTarget)
        }
    }

    private var importKind: DataSourceImportKind {
        switch importTarget {
        case .whoop: return .whoop
        case .appleHealth: return .appleHealth
        }
    }
    private var lastSummary: String? {
        switch importTarget {
        case .whoop: return model.whoopImportSummary
        case .appleHealth: return model.appleHealthImportSummary
        }
    }
    private func presentImporter(_ target: ImportTarget) {
        importTarget = target
        showingImporter = true
    }
    private func handleImportResult(_ result: Result<[URL], Error>, for target: ImportTarget) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        switch target {
        case .whoop: model.importWhoop(url: url)
        case .appleHealth: model.importAppleHealth(url: url)
        }
    }
    private enum ImportTarget {
        case whoop, appleHealth
        var allowedContentTypes: [UTType] {
            switch self {
            case .whoop: return [.zip, .folder]
            case .appleHealth: return [.zip, .xml, .folder]
            }
        }
    }
}

// MARK: - Step · Done

private struct DoneStep: View {
    let onFinish: () -> Void
    @Environment(\.instrumentoTheme) private var theme
    var body: some View {
        CenteredState(
            glyph: "checkmark.seal",
            glyphColor: theme.verdict,
            title: "All set.",
            titleColor: theme.ink,
            message: "Every night and every day will weave into a single read of you. Welcome to Cénit."
        ) {
            InkButton("Enter Cénit", action: onFinish)
        }
    }
}

// MARK: - Reusable pieces

private struct Checkline: View {
    let text: LocalizedStringKey
    @Environment(\.instrumentoTheme) private var theme
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: NoopMetrics.space2) {
            Image(systemName: "checkmark")
                .font(StrandFont.glyph(.chevron, weight: .semibold))
                .foregroundStyle(theme.inkTertiary)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct FieldRow: View {
    let label: LocalizedStringKey
    let value: String
    @Environment(\.instrumentoTheme) private var theme
    var body: some View {
        HStack {
            Text(label).font(StrandFont.body).foregroundStyle(theme.ink)
            Spacer()
            Text(value).font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
        }
    }
}

private struct ImportRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    var disabled = false
    let action: () -> Void
    @Environment(\.instrumentoTheme) private var theme
    var body: some View {
        Button(action: action) {
            HStack(spacing: NoopMetrics.gap) {
                Image(systemName: systemImage)
                    .font(StrandFont.glyph(.inline, weight: .semibold))
                    .frame(width: 18)
                Text(title).font(StrandFont.subhead.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(StrandFont.glyph(.chevron, weight: .bold))
                    .foregroundStyle(theme.inkTertiary)
            }
            .foregroundStyle(theme.ink)
            .padding(.vertical, 12)
            .padding(.horizontal, NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }
}

// MARK: - Preview

#if DEBUG
private struct OnboardingPreview: View {
    @StateObject private var model = AppModel()
    var body: some View {
        OnboardingWizard(onFinished: {})
            .environmentObject(model)
            .environmentObject(model.live)
            .environmentObject(model.profile)
            .frame(width: 390, height: 780)
    }
}

#Preview("Onboarding") { OnboardingPreview() }
#endif
