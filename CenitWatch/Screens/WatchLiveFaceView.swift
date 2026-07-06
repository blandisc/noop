import SwiftUI
import StrandDesign

/// The live session face (states 3, 4, 7, 8, 9) plus the swipe-in control page. A single `TabView` page
/// carries the metrics; a second page carries «Terminar». Exactly one hero at a time — the heart rate,
/// or (during a rest) the countdown — never both.
struct WatchLiveFaceView: View {
    var body: some View {
        TabView {
            WatchFaceMetrics()
            WatchControlPage()
        }
        .tabViewStyle(.page)
    }
}

// MARK: - Metrics page (states 3 / 4 / 7 / 8)

private struct WatchFaceMetrics: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    private let t = InstrumentoTheme.base

    private var elapsedStart: Date { manager.startDate ?? Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            if !manager.iPhoneReachable { disconnectedLine }
            if let rest = manager.rest { resting(rest) } else { active }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, NoopMetrics.gap)
        .padding(.vertical, NoopMetrics.space2)
    }

    // State 8 — a quiet line; heart rate and time keep running. Clears itself on reconnect.
    private var disconnectedLine: some View {
        Text("No connection to iPhone")
            .font(StrandFont.footnote)
            .foregroundStyle(t.inkTertiary)
            .lineLimit(2)
    }

    // State 3 — heart rate is the hero; time and routine subordinate. State 7 swaps time+routine for the
    // Health-access warning while keeping the timer running.
    private var active: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text("Pulse").instrumentoOverline().foregroundStyle(t.inkTertiary).accessibilityHidden(true)
            pulseHero
            Spacer(minLength: NoopMetrics.space2)
            elapsed
            if manager.healthAccessDenied { permissionWarning }
            else { Text(routineTitle).font(StrandFont.caption).foregroundStyle(t.inkSecondary).lineLimit(2) }
        }
    }

    // State 4 — the focus migrates to the countdown; heart rate drops to secondary; the return detail
    // (set + exercise) stays visible.
    private func resting(_ rest: RestActivitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text("Rest").instrumentoOverline().foregroundStyle(t.inkTertiary).accessibilityHidden(true)
            Text(timerInterval: rest.restStartedAt...rest.restEndsAt, countsDown: true)
                .instrumentoHero(50)
                .foregroundStyle(t.dataStrain)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel(Text("Rest, \(secondsLeft(rest)) seconds left"))
            Spacer(minLength: NoopMetrics.space2)
            heartSecondary
            Text(rest.returnDetail).font(StrandFont.caption).foregroundStyle(t.inkSecondary).lineLimit(2)
            if manager.healthAccessDenied { permissionWarning }
        }
    }

    // «--» in muted ink (never a made-up number) when the sensor hasn't read or Health access is denied.
    private var pulseDashed: Bool { manager.heartRate == 0 || manager.healthAccessDenied }
    private var pulseValue: Text { pulseDashed ? Text(verbatim: "--") : Text(verbatim: "\(manager.heartRate)") }
    // One source for the VoiceOver phrase, shared by the hero and its demoted twin, so «Pulso, sin
    // lectura» / «Pulso, N latidos por minuto» can't drift between the two.
    private var pulseLabel: Text {
        pulseDashed ? Text("Pulse, no reading") : Text("Pulse, \(manager.heartRate) beats per minute")
    }

    // State 3 — the pulse hero.
    private var pulseHero: some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
            pulseValue
                .instrumentoHero(52)
                .foregroundStyle(pulseDashed ? t.inkDim : t.dataHeart)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("bpm").font(StrandFont.unit).foregroundStyle(t.inkSecondary).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pulseLabel)
    }

    // State 4 — heart rate demoted during a rest: small, still the datum's hue (or «--»).
    private var heartSecondary: some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
            pulseValue
                .font(StrandFont.bodyNumber)
                .foregroundStyle(pulseDashed ? t.inkDim : t.dataHeart)
            Text("bpm").font(StrandFont.unit).foregroundStyle(t.inkSecondary).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pulseLabel)
    }

    private var elapsed: some View {
        Text(elapsedStart, style: .timer)
            .font(StrandFont.bodyNumber)
            .foregroundStyle(t.ink)
    }

    // State 7 — the session keeps serving (timer + rests + haptics); only pulse + saving degrade.
    private var permissionWarning: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text("No access to Health. Without it there's no pulse and nothing saved.")
                .font(StrandFont.caption)
                .foregroundStyle(t.inkSecondary)
                .lineLimit(nil)
            Text("Turn it on in Settings, Health, on your iPhone.")
                .font(StrandFont.footnote)
                .foregroundStyle(t.inkTertiary)
                .lineLimit(nil)
        }
    }

    private var routineTitle: String {
        manager.routineName.isEmpty ? String(localized: "Strength") : manager.routineName
    }

    private func secondsLeft(_ rest: RestActivitySnapshot) -> Int {
        max(0, Int(rest.restEndsAt.timeIntervalSinceNow.rounded()))
    }
}

// MARK: - Control page (swipe) — «Terminar» with a one-step confirmation

private struct WatchControlPage: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    @State private var confirming = false
    private let t = InstrumentoTheme.base

    var body: some View {
        VStack(spacing: NoopMetrics.space2) {
            Spacer()
            Text("Session").instrumentoOverline().foregroundStyle(t.inkTertiary)
            Button(role: .destructive) { confirming = true } label: {
                Text("End").frame(maxWidth: .infinity, minHeight: 44)
            }
            .tint(t.critical)
            Spacer()
        }
        .padding(.horizontal, NoopMetrics.gap)
        .confirmationDialog("End the session?", isPresented: $confirming, titleVisibility: .visible) {
            Button("End", role: .destructive) { manager.endFromWrist() }
            Button("Keep going", role: .cancel) { }
        }
    }
}
