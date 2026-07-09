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
            WatchPlanRotor()
        }
        .tabViewStyle(.page)
    }
}

// MARK: - Metrics page (states 3 / 4 / 7 / 8)

private struct WatchFaceMetrics: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    private let t = InstrumentoTheme.base
    /// FER-808: brief check shown on the «Registrar serie» CTA right after a wrist log.
    @State private var loggedCheck = false

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
            else if let cap = manager.capture { captureContext(cap) }
            else { Text(routineTitle).font(StrandFont.caption).foregroundStyle(t.inkSecondary).lineLimit(2) }
            registerCTA
        }
    }

    // FER-809 — «qué toca» between rests: which set is up (N/M) + a chrome progress bar + the exercise and
    // its «weight × reps». Chrome tint (this bar isn't a physiological datum). Omitted detail line when a
    // time/distance set carries no load.
    private func captureContext(_ cap: WorkoutCaptureSnapshot) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text("Set \(cap.setNumber) / \(cap.setTotal)")
                .font(StrandFont.caption).foregroundStyle(t.ink)
            ProgressView(value: Double(cap.setNumber), total: Double(max(cap.setTotal, 1)))
                .tint(t.inkSecondary)
                .accessibilityHidden(true)
            Text(captureDetail(cap))
                .font(StrandFont.footnote).foregroundStyle(t.inkSecondary).lineLimit(2)
        }
    }

    private func captureDetail(_ cap: WorkoutCaptureSnapshot) -> String {
        cap.returnDetail.isEmpty ? cap.exerciseName : "\(cap.exerciseName) · \(cap.returnDetail)"
    }

    // FER-808 — «Registrar serie» from the wrist: a solid CTA (chrome ink, never a data hue). A soft
    // `.click` + a 400 ms check confirm the log. Stays alive with no permission / no iPhone: the message
    // queues and applies on reconnect — no dead button. (A literal Digital Crown *press* is reserved by
    // watchOS and can't be intercepted; the big button is the affordance, per the product decision.)
    private var registerCTA: some View {
        Button(action: logSet) {
            Group {
                if loggedCheck { Image(systemName: "checkmark").accessibilityHidden(true) }
                else { Text("Log set") }
            }
            .font(StrandFont.caption)
            .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(.borderedProminent)
        .tint(t.ink)
        .accessibilityLabel(Text("Log set"))
    }

    private func logSet() {
        manager.completeSetFromWrist()
        WatchHaptic.actionTapped.play()
        withAnimation(.easeOut(duration: 0.15)) { loggedCheck = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(.easeIn(duration: 0.15)) { loggedCheck = false }
        }
    }

    // State 4 — the focus migrates to the countdown; heart rate drops to secondary; the return detail
    // (set + exercise) stays visible.
    private func resting(_ rest: RestActivitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text("Rest").instrumentoOverline().foregroundStyle(t.inkTertiary).accessibilityHidden(true)
            Text(timerInterval: rest.restStartedAt...rest.restEndsAt, countsDown: true)
                .instrumentoHero(44)
                .foregroundStyle(t.dataStrain)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel(Text("Rest, \(secondsLeft(rest)) seconds left"))
            // FER-808 — rest progress bar, coherent with the iPhone Live Activity. The datum's amber hue.
            ProgressView(timerInterval: rest.restStartedAt...rest.restEndsAt, countsDown: false) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
                .tint(t.dataStrain)
                .accessibilityHidden(true)
            restControls(rest)
            Spacer(minLength: NoopMetrics.space1)
            heartSecondary
            Text("Next: set \(rest.setNumber) · \(rest.returnDetail)")
                .font(StrandFont.footnote).foregroundStyle(t.inkSecondary).lineLimit(2)
            if manager.healthAccessDenied { permissionWarning }
        }
    }

    // FER-808 — the rest controls the iPhone Live Activity already has: ±30 s and Skip, now on the wrist.
    // «−30» is hidden once the rest has run out (nothing left to trim; `extendRest` also floors at «now»).
    private func restControls(_ rest: RestActivitySnapshot) -> some View {
        HStack(spacing: NoopMetrics.space1) {
            if secondsLeft(rest) > 0 { pill("−30") { manager.adjustRestFromWrist(by: -30) } }
            pill("+30 s") { manager.adjustRestFromWrist(by: 30) }
            pill("Skip") { manager.skipRestFromWrist() }
        }
    }

    private func pill(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            WatchHaptic.actionTapped.play()
            action()
        } label: {
            Text(title).font(StrandFont.footnote).frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .tint(t.inkSecondary)
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
            zoneTag
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pulseLabel)
    }

    // FER-811 — a discreet effort-zone tag (Z2/Z3…) beside the pulse, from the profile's mirrored max HR.
    // Muted ink with a hairline border — chrome, never a data hue, so it never competes with the number.
    // Omitted with no pulse reading or no reliable max HR (honest degradation, never «Z0»).
    private var effortZone: Int? {
        guard !pulseDashed, let hrMax = manager.hrMax, hrMax > 0, manager.heartRate > 0 else { return nil }
        switch Double(manager.heartRate) / Double(hrMax) {
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default:     return 5
        }
    }

    @ViewBuilder private var zoneTag: some View {
        if let z = effortZone {
            Text(verbatim: "Z\(z)")
                .font(StrandFont.footnote)
                .foregroundStyle(t.inkSecondary)
                .padding(.horizontal, NoopMetrics.space1)
                .padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(t.inkTertiary, lineWidth: 1))
                .accessibilityLabel(Text("Effort zone \(z)"))
        }
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

// MARK: - Control page (swipe) — the real session actions (FER-809)

// The primary action follows the phase so no control is ever a dead button (handoff rule 5): «Registrar
// serie» while working a set, «Saltar descanso» while resting. «Terminar» is always available, behind a
// one-step confirmation aligned with the iPhone / Live Activity copy.
private struct WatchControlPage: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    @State private var confirming = false
    private let t = InstrumentoTheme.base

    var body: some View {
        VStack(spacing: NoopMetrics.space2) {
            Spacer()
            Text("Session").instrumentoOverline().foregroundStyle(t.inkTertiary)
            if manager.rest != nil {
                Button { WatchHaptic.actionTapped.play(); manager.skipRestFromWrist() } label: {
                    Text("Skip rest").frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered).tint(t.inkSecondary)
            } else {
                Button { WatchHaptic.actionTapped.play(); manager.completeSetFromWrist() } label: {
                    Text("Log set").frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent).tint(t.ink)
            }
            Button(role: .destructive) { confirming = true } label: {
                Text("End").frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered).tint(t.critical)
            Spacer()
        }
        .padding(.horizontal, NoopMetrics.gap)
        .confirmationDialog("End the session?", isPresented: $confirming, titleVisibility: .visible) {
            Button("End", role: .destructive) { manager.endFromWrist() }
            Button("Keep going", role: .cancel) { }
        }
    }
}

// MARK: - Plan rotor (swipe) — read-only glance at the routine (FER-810)

// A third page: done ✓ / current • / pending ○ + «N/M» per exercise. The watch never edits the plan, so
// rows carry no tap target — it's a glance, not a control. Color lands only on the «done» check (verdict),
// as on the rest-over screen; the current marker is chrome ink.
private struct WatchPlanRotor: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    private let t = InstrumentoTheme.base

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text("Plan").instrumentoOverline().foregroundStyle(t.inkTertiary)
                if let plan = manager.plan, !plan.exercises.isEmpty {
                    ForEach(Array(plan.exercises.enumerated()), id: \.offset) { _, ex in planRow(ex) }
                } else {
                    Text("No plan yet").font(StrandFont.caption).foregroundStyle(t.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NoopMetrics.gap)
            .padding(.vertical, NoopMetrics.space2)
        }
    }

    private func planRow(_ ex: WorkoutPlanSnapshot.Exercise) -> some View {
        let done = ex.setsTotal > 0 && ex.setsDone >= ex.setsTotal
        return HStack(spacing: NoopMetrics.space1) {
            marker(done: done, current: ex.isCurrent)
            Text(ex.name)
                .font(StrandFont.caption)
                .foregroundStyle(done ? t.inkTertiary : t.ink)
                .lineLimit(1)
            Spacer(minLength: NoopMetrics.space1)
            Text("\(ex.setsDone)/\(ex.setsTotal)")
                .font(StrandFont.footnote)
                .foregroundStyle(t.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func marker(done: Bool, current: Bool) -> some View {
        if done { Image(systemName: "checkmark").font(StrandFont.footnote).foregroundStyle(t.verdict) }
        else if current { Image(systemName: "circle.fill").font(StrandFont.footnote).foregroundStyle(t.ink) }
        else { Image(systemName: "circle").font(StrandFont.footnote).foregroundStyle(t.inkTertiary) }
    }
}
