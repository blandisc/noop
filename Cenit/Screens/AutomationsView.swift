#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - «Automatizaciones» — FER-69
//
// The strap's physical inputs (double-tap) and live biometrics turned into actions + haptic coaching,
// in the light «Instrumento diurno» language. Reskinned from the dark system and **saneado for iOS**:
// the Mac-only "lock the Mac when you take the strap off" control is gone, and the copy no longer talks
// about "this Mac" (the app is iOS-only). The iOS-valid automations stay: double-tap → a Shortcut / mark
// a moment, run a Shortcut on wrist off/on, haptic coaching, smart alarm, illness early-warning. Logic
// (BehaviorStore / alarm / haptics) is unchanged — only presentation + the Mac-only cleanup.

struct AutomationsView: View {
    var body: some View {
        AutomationsContent().instrumentoThemeByHour(solar: Self.solarWindow())
    }
    private static func solarWindow() -> SolarWindow? {
        guard let w = SolarClock.sunWindow(on: Date(), in: .current) else { return nil }
        return SolarWindow(sunrise: w.sunrise, sunset: w.sunset)
    }
}

private struct AutomationsContent: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var behavior: BehaviorStore
    @EnvironmentObject var live: LiveState
    @Environment(\.instrumentoTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automations").font(StrandFont.title1).foregroundStyle(theme.ink)
                    Text("Make the strap do things — tap to act, train by feel, wake to a buzz.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, -8)

                doubleTapSection
                divider
                wearSection
                divider
                coachingSection
                divider
                alarmSection
                divider
                illnessSection
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
    }

    private var divider: some View { Divider().overlay(theme.hairline) }

    @ViewBuilder
    private func section<C: View>(_ title: LocalizedStringKey, blurb: LocalizedStringKey,
                                 @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(blurb).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    // MARK: - Double tap

    private var doubleTapSection: some View {
        section("Double-tap", blurb: "Double-tap the strap to trigger an action. (The strap exposes a single double-tap gesture.)") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("When I double-tap").font(StrandFont.body).foregroundStyle(theme.ink)
                    Spacer()
                    Picker("", selection: $behavior.doubleTapAction) {
                        ForEach(StrapActionKind.available) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().fixedSize().tint(theme.ink)
                }
                if behavior.doubleTapAction == .runShortcut {
                    shortcutField("Shortcut name", text: $behavior.doubleTapShortcut)
                }
                HStack(spacing: 12) {
                    QuietButton("Test action") {
                        model.runStrapAction(behavior.doubleTapAction, shortcut: behavior.doubleTapShortcut)
                    }
                    .disabled(behavior.doubleTapAction == .none)
                    Spacer()
                    HStack(spacing: 7) {
                        Circle().fill(live.bonded ? theme.dataRecovery : theme.warning).frame(width: 8, height: 8)
                        Text(live.bonded ? "Strap bonded" : "Strap not connected")
                            .font(StrandFont.subhead)
                            .foregroundStyle(live.bonded ? theme.dataRecovery : theme.warning)
                    }
                }
                if !model.moments.isEmpty {
                    divider
                    momentsView
                }
            }
        }
    }

    private var momentsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent moments").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Button("Clear") {
                    model.moments.removeAll()
                    UserDefaults.standard.removeObject(forKey: "moments")
                }
                .buttonStyle(.plain).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
            ForEach(Array(model.moments.suffix(5).reversed().enumerated()), id: \.offset) { _, d in
                Text(Self.momentFormatter.string(from: d))
                    .font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
            }
        }
    }
    private static let momentFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM · HH:mm"; return f
    }()

    // MARK: - Wear & presence (Mac-only "lock" control removed — iOS-only, FER-69)

    private var wearSection: some View {
        section("Wear & presence", blurb: "Run a Shortcut when the strap comes off or goes back on — set a Focus, pause media, mark yourself away.") {
            VStack(spacing: 0) {
                shortcutFieldRow("Run a Shortcut when taken off",
                                 help: "Presence automation — set a Focus, pause media, set away…",
                                 text: $behavior.wristOffShortcut)
                divider
                shortcutFieldRow("Run a Shortcut when put back on",
                                 help: "Reverse the above when you return.",
                                 text: $behavior.wristOnShortcut)
            }
        }
    }

    // MARK: - Coaching

    private var coachingSection: some View {
        section("Haptic coaching", blurb: "Train by feel — the strap buzzes so you don't have to watch a screen.") {
            VStack(spacing: 0) {
                toggleRow("HR-zone coaching",
                          help: "Buzz when you hit your top zone (ease off) and again when you recover. Uses your max HR from Settings.",
                          isOn: $behavior.zoneCoaching)
                divider
                toggleRow("Resting stress nudge (experimental)",
                          help: "A gentle buzz when your HRV drops while your heart rate is calm — a cue to take a paced breath. Rate-limited to once every 15 minutes; off by default.",
                          isOn: $behavior.stressNudge)
            }
        }
    }

    // MARK: - Smart alarm

    private var alarmSection: some View {
        section("Smart alarm", blurb: "Wake to a wrist buzz. This arms the strap's own firmware alarm, so it still fires even if your iPhone is asleep or Cénit is closed.") {
            VStack(spacing: 0) {
                toggleRow("Enable smart alarm", help: "Arms the strap to buzz at your wake time.",
                          isOn: $behavior.smartAlarmEnabled)
                if behavior.smartAlarmEnabled {
                    divider
                    HStack {
                        Text("Wake at").font(StrandFont.body).foregroundStyle(theme.ink)
                        Spacer()
                        DatePicker("", selection: alarmTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.compact).tint(theme.dataRecovery)
                    }
                    .frame(minHeight: 42).padding(.vertical, 4)
                    Text("On WHOOP 5/MG this is experimental — arming is confirmed, but a strap-driven wake-up hasn't been verified yet, so don't rely on it as your only alarm there. WHOOP 4 is the proven path.")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
            }
            .onChange(of: behavior.smartAlarmEnabled) { model.applySmartAlarm() }
            .onChange(of: behavior.smartAlarmMinutes) { model.applySmartAlarm() }
        }
    }

    // MARK: - Illness early-warning

    private var illnessSection: some View {
        section("Illness early-warning", blurb: "Watches your resting HR, HRV, skin temperature and respiration against your own 28-day baseline. On-device and approximate — informational only, not a diagnosis.") {
            toggleRow("Watch for early-illness signs",
                      help: "Needs at least 14 days of history. When two or more signals drift together you get a notification — at most once a day.",
                      isOn: $behavior.illnessWatch)
                .onChange(of: behavior.illnessWatch) {
                    model.reevaluateIllness()
                    if behavior.illnessWatch { IllnessNotifier.requestAuthorization() }
                }
        }
    }

    // MARK: - Helpers

    private var alarmTimeBinding: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: behavior.smartAlarmMinutes) },
                set: { behavior.smartAlarmMinutes = Self.minutes(from: $0) })
    }
    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
    private static func minutes(from d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func shortcutField(_ placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .font(StrandFont.body)
            .frame(maxWidth: 320)
    }

    private func shortcutFieldRow(_ label: LocalizedStringKey, help: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(StrandFont.body).foregroundStyle(theme.ink)
                Text(help).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            shortcutField("Shortcut name", text: text)
        }
        .frame(minHeight: 42).padding(.vertical, 4)
    }

    private func toggleRow(_ label: LocalizedStringKey, help: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(StrandFont.body).foregroundStyle(theme.ink)
                Text(help).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).tint(theme.dataRecovery)
                .accessibilityLabel(label)
        }
        .frame(minHeight: 42).padding(.vertical, 4)
    }
}
#endif
