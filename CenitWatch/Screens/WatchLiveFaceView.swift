import SwiftUI
import CenitDesign

/// The live session face (states 3, 4, 7, 8, 9) plus the swipe-in control page. A single `TabView` page
/// carries the metrics; a second page carries «Terminar». Exactly one hero at a time — the heart rate,
/// or (during a rest) the countdown — never both.
///
/// Liquid sobre OLED (DECISIONS 2026-09-03, FER-309/312): tintas de `LiquidOLED`, tonos de dato de
/// `LiquidColor` (mismos que en el iPhone). Controles nativos watchOS (`.bordered` /
/// `.confirmationDialog`) se conservan: `LiquidGlassButton`/`liquidConfirm` compilan en el paquete
/// pero son chrome de hoja iPhone (44 pt / scrim), incompatibles con `WatchMetrics`.
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
    /// FER-808: brief check shown on the «Registrar serie» CTA right after a wrist log.
    @State private var loggedCheck = false

    private var elapsedStart: Date { manager.startDate ?? Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            if !manager.iPhoneReachable { disconnectedLine }
            if let rest = manager.rest { resting(rest) } else { active }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, LiquidSpace.s300)
        .padding(.vertical, LiquidSpace.s200)
    }

    // State 8 — a quiet line; heart rate and time keep running. Clears itself on reconnect.
    private var disconnectedLine: some View {
        Text("No connection to iPhone")
            .font(LiquidType.pie)
            .foregroundStyle(LiquidOLED.tintaTerciaria)
            .lineLimit(2)
    }

    // State 3 — heart rate is the hero; time and routine subordinate. State 7 swaps time+routine for the
    // Health-access warning while keeping the timer running.
    private var active: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text("Pulse").liquidKicker().foregroundStyle(LiquidOLED.tintaTerciaria).accessibilityHidden(true)
            pulseHero
            Spacer(minLength: LiquidSpace.s200)
            elapsed
            if manager.healthAccessDenied { permissionWarning }
            else if let cap = manager.capture { captureContext(cap) }
            else { Text(routineTitle).font(LiquidType.filaConteo).foregroundStyle(LiquidOLED.tintaSecundaria).lineLimit(2) }
            registerCTA
        }
    }

    // FER-809 — «qué toca» between rests: which set is up (N/M) + a chrome progress bar + the exercise and
    // its «weight × reps». Chrome tint (this bar isn't a physiological datum). Omitted detail line when a
    // time/distance set carries no load.
    private func captureContext(_ cap: WorkoutCaptureSnapshot) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text("Set \(cap.setNumber) / \(cap.setTotal)")
                .font(LiquidType.filaConteo).foregroundStyle(LiquidOLED.tinta)
            ProgressView(value: Double(cap.setNumber), total: Double(max(cap.setTotal, 1)))
                .tint(LiquidOLED.tintaSecundaria)
                .accessibilityHidden(true)
            Text(captureDetail(cap))
                .font(LiquidType.pie).foregroundStyle(LiquidOLED.tintaSecundaria).lineLimit(2)
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
                else { Text("Complete set") }
            }
            .font(LiquidType.filaConteo)
            .frame(maxWidth: .infinity, minHeight: WatchMetrics.ctaHeight)
        }
        // token-exempt(sistema): control nativo watchOS
        .buttonStyle(.borderedProminent)
        .tint(LiquidOLED.tinta)
        .accessibilityLabel(Text("Complete set"))
    }

    private func logSet() {
        manager.completeSetFromWrist()
        WatchHaptic.actionTapped.play()
        withAnimation(LiquidMotion.settle(LiquidMotion.brief)) { loggedCheck = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(LiquidMotion.dismiss(LiquidMotion.brief)) { loggedCheck = false }
        }
    }

    // State 4 — the focus migrates to the countdown (or, FER-96, the pulse-to-go when `isHRMode`); heart
    // rate drops to secondary; the return detail (set + exercise) stays visible.
    private func resting(_ rest: RestActivitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text("Rest").liquidKicker().foregroundStyle(LiquidOLED.tintaTerciaria).accessibilityHidden(true)
            if rest.isHRMode { hrRestHeadline(rest) }
            else {
                // token-exempt(sistema): geometría watchOS — countdown 44; sin token tabular Liquid a ese tamaño
                Text(timerInterval: rest.restStartedAt...rest.restEndsAt, countsDown: true)
                    .font(.system(size: WatchMetrics.heroRestCountdown, weight: .bold).monospacedDigit())
                    .foregroundStyle(LiquidOLED.ambar)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityLabel(Text("Rest, \(secondsLeft(rest)) seconds left"))
            }
            // FER-808 — rest progress bar, coherent with the iPhone Live Activity. The datum's amber hue.
            // Elapsed-time framing stays meaningful even in HR mode (the ceiling is still a clock).
            ProgressView(timerInterval: rest.restStartedAt...rest.restEndsAt, countsDown: false) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
                .tint(LiquidOLED.ambar)
                .accessibilityHidden(true)
            restControls(rest)
            Spacer(minLength: LiquidSpace.s100)
            heartSecondary
            Text("Back to: set \(rest.setNumber) · \(rest.returnDetail)")
                .font(LiquidType.pie).foregroundStyle(LiquidOLED.tintaSecundaria).lineLimit(2)
            // FER-96 — the exercise handoff, additive to the line above: same condition the widget's
            // card already uses (`RestLiveActivity.swift:297-309`, `phaseRaw == "lastSetOfExercise"` AND
            // a known `nextExerciseName`), never a second lexicon for the same datum.
            if rest.phaseRaw == "lastSetOfExercise", let next = rest.nextExerciseName {
                (Text("Next").font(LiquidType.pie).foregroundStyle(LiquidOLED.tintaTerciaria)
                 + Text(verbatim: ": ").font(LiquidType.pie).foregroundStyle(LiquidOLED.tintaTerciaria)
                 + Text(verbatim: next).font(LiquidType.pie).foregroundStyle(LiquidOLED.tinta))
                    .lineLimit(2)
            }
            if manager.healthAccessDenied { permissionWarning }
        }
    }

    /// FER-96 — HR-mode rest headline: «te faltan N lpm» computed from the watch's OWN live pulse
    /// (`manager.heartRate`, from its own `HKWorkoutSession`) against `rest.hrTarget` — no new data from
    /// the iPhone. Same 4-word vocabulary `RestBand` already defines for the iPhone (Ready / Almost /
    /// «you need N bpm» / waiting for your pulse), reused as WORDS — never re-derived from
    /// `RestReadinessRule` (`CenitWatch` carries zero `StrandAnalytics` imports, by design).
    @ViewBuilder
    private func hrRestHeadline(_ rest: RestActivitySnapshot) -> some View {
        if let target = rest.hrTarget, manager.heartRate > 0 {
            let gap = max(0, manager.heartRate - target)
            if gap == 0 {
                // displayM (40) es el grotesk más cercano a heroReadiness (36)
                Text("Ready")
                    .font(LiquidType.displayM)
                    .tracking(LiquidType.displayMTracking)
                    .foregroundStyle(LiquidOLED.verde)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            } else if gap <= Self.restHonestyBandBPM {
                // The engine's honesty band (`RestReadinessRule.defaultBandBPM` = 5): close enough that
                // beat-level precision would be fake.
                Text("Almost")
                    .font(LiquidType.displayM)
                    .tracking(LiquidType.displayMTracking)
                    .foregroundStyle(LiquidOLED.rosa)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            } else {
                (Text("you need").font(LiquidType.subtituloFila).foregroundStyle(LiquidOLED.tintaSecundaria)
                 + Text(verbatim: " ")
                 // displayM (40) es el grotesk más cercano a heroReadiness (36)
                 + Text(verbatim: "\(gap)").font(LiquidType.displayM).tracking(LiquidType.displayMTracking).foregroundStyle(LiquidOLED.rosa)
                 + Text(verbatim: " ")
                 + Text("bpm").font(LiquidType.subtituloFila).foregroundStyle(LiquidOLED.tintaSecundaria))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        } else {
            // No pulse reading yet — never a guessed/zero number.
            Text("Waiting for your pulse")
                .font(LiquidType.subtituloFila)
                .foregroundStyle(LiquidOLED.tintaSecundaria)
        }
    }

    /// Mirrors `RestReadinessRule.defaultBandBPM` (`Packages/StrandAnalytics`) as a plain constant — the
    /// watch never imports that package, so this is the number, not the rule.
    private static let restHonestyBandBPM = 5

    // FER-808 — the rest controls the iPhone Live Activity already has: ±30 s and Skip, now on the wrist.
    // «−30» is hidden once the rest has run out (nothing left to trim; `extendRest` also floors at «now»).
    private func restControls(_ rest: RestActivitySnapshot) -> some View {
        HStack(spacing: LiquidSpace.s100) {
            if secondsLeft(rest) > 0 { pill("−30 s") { manager.adjustRestFromWrist(by: -30) } }
            pill("+30 s") { manager.adjustRestFromWrist(by: 30) }
            pill("Skip rest") { manager.skipRestFromWrist() }
        }
    }

    private func pill(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            WatchHaptic.actionTapped.play()
            action()
        } label: {
            Text(title).font(LiquidType.pie).frame(maxWidth: .infinity, minHeight: WatchMetrics.pillHeight)
        }
        // token-exempt(sistema): control nativo watchOS
        .buttonStyle(.bordered)
        .tint(LiquidOLED.tintaSecundaria)
    }

    // «--» in muted ink (never a made-up number) when the sensor hasn't read or Health access is denied.
    private var pulseDashed: Bool { manager.heartRate == 0 || manager.healthAccessDenied }
    private var pulseValue: Text { pulseDashed ? Text(verbatim: "--") : Text(verbatim: "\(manager.heartRate)") }
    // One source for the VoiceOver phrase, shared by the hero and its demoted twin, so «Pulso, sin
    // lectura» / «Pulso, N latidos por minuto» can't drift between the two.
    private var pulseLabel: Text {
        pulseDashed ? Text("Pulse, no reading") : Text("Pulse, \(manager.heartRate) beats per minute")
    }

    // State 3 — the pulse hero. numeralHoja = 52 = WatchMetrics.heroPulse.
    private var pulseHero: some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
            pulseValue
                .font(LiquidType.numeralHoja)
                .foregroundStyle(pulseDashed ? LiquidOLED.tintaTerciaria : LiquidOLED.rosa) // inkDim → tintaTerciaria (rol más cercano)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("bpm").font(LiquidType.unidad).foregroundStyle(LiquidOLED.tintaSecundaria).accessibilityHidden(true)
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
                .font(LiquidType.pie)
                .foregroundStyle(LiquidOLED.tintaSecundaria)
                .padding(.horizontal, LiquidSpace.s100)
                .padding(.vertical, LiquidSpace.s025)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(LiquidOLED.tintaTerciaria, lineWidth: 1))  // token-exempt(sistema): geometría watchOS (fixed 4pt inset stroke)
                .accessibilityLabel(Text("Effort zone \(z)"))
        }
    }

    // State 4 — heart rate demoted during a rest: small, still the datum's hue (or «--»).
    private var heartSecondary: some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
            pulseValue
                .font(Font.system(.subheadline).monospacedDigit()) // bodyNumber → cuerpoLista tabular
                .foregroundStyle(pulseDashed ? LiquidOLED.tintaTerciaria : LiquidOLED.rosa) // inkDim → tintaTerciaria
            Text("bpm").font(LiquidType.unidad).foregroundStyle(LiquidOLED.tintaSecundaria).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pulseLabel)
    }

    private var elapsed: some View {
        Text(elapsedStart, style: .timer)
            .font(Font.system(.subheadline).monospacedDigit()) // bodyNumber → cuerpoLista tabular
            .foregroundStyle(LiquidOLED.tinta)
    }

    // State 7 — the session keeps serving (timer + rests + haptics); only pulse + saving degrade.
    private var permissionWarning: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text("No access to Health. Without it there's no pulse and nothing saved.")
                .font(LiquidType.filaConteo)
                .foregroundStyle(LiquidOLED.tintaSecundaria)
                .lineLimit(nil)
            Text("Turn it on in Settings, Health, on your iPhone.")
                .font(LiquidType.pie)
                .foregroundStyle(LiquidOLED.tintaTerciaria)
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

    var body: some View {
        VStack(spacing: LiquidSpace.s200) {
            Spacer()
            Text("Session").liquidKicker().foregroundStyle(LiquidOLED.tintaTerciaria)
            if manager.rest != nil {
                Button { WatchHaptic.actionTapped.play(); manager.skipRestFromWrist() } label: {
                    Text("Skip rest").frame(maxWidth: .infinity, minHeight: WatchMetrics.controlHeight)
                }
                // token-exempt(sistema): control nativo watchOS
                .buttonStyle(.bordered).tint(LiquidOLED.tintaSecundaria)
            } else {
                Button { WatchHaptic.actionTapped.play(); manager.completeSetFromWrist() } label: {
                    Text("Complete set").frame(maxWidth: .infinity, minHeight: WatchMetrics.controlHeight)
                }
                // token-exempt(sistema): control nativo watchOS
                .buttonStyle(.borderedProminent).tint(LiquidOLED.tinta)
            }
            Button(role: .destructive) { confirming = true } label: {
                Text("Finish").frame(maxWidth: .infinity, minHeight: WatchMetrics.controlHeight)
            }
            // token-exempt(sistema): control nativo watchOS
            .buttonStyle(.bordered).tint(LiquidOLED.negativo)
            Spacer()
        }
        .padding(.horizontal, LiquidSpace.s300)
        // token-exempt(sistema): control nativo watchOS — liquidConfirm es chrome de hoja iPhone
        .confirmationDialog("Finish workout?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Finish", role: .destructive) { manager.endFromWrist() }
            Button("Keep training", role: .cancel) { }
        }
    }
}

// MARK: - Plan rotor (swipe) — read-only glance at the routine (FER-810)

// A third page: done ✓ / current • / pending ○ + «N/M» per exercise. The watch never edits the plan, so
// rows carry no tap target — it's a glance, not a control. Color lands only on the «done» check (verdict),
// as on the rest-over screen; the current marker is chrome ink.
private struct WatchPlanRotor: View {
    @EnvironmentObject var manager: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                Text("Plan").liquidKicker().foregroundStyle(LiquidOLED.tintaTerciaria)
                if let plan = manager.plan, !plan.exercises.isEmpty {
                    ForEach(Array(plan.exercises.enumerated()), id: \.offset) { _, ex in planRow(ex) }
                } else {
                    Text("No plan yet").font(LiquidType.filaConteo).foregroundStyle(LiquidOLED.tintaSecundaria)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LiquidSpace.s300)
            .padding(.vertical, LiquidSpace.s200)
        }
    }

    private func planRow(_ ex: WorkoutPlanSnapshot.Exercise) -> some View {
        let done = ex.setsTotal > 0 && ex.setsDone >= ex.setsTotal
        return HStack(spacing: LiquidSpace.s100) {
            marker(done: done, current: ex.isCurrent)
            Text(ex.name)
                .font(LiquidType.filaConteo)
                .foregroundStyle(done ? LiquidOLED.tintaTerciaria : LiquidOLED.tinta)
                .lineLimit(1)
            Spacer(minLength: LiquidSpace.s100)
            Text("\(ex.setsDone)/\(ex.setsTotal)")
                .font(LiquidType.pie)
                .foregroundStyle(LiquidOLED.tintaSecundaria)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func marker(done: Bool, current: Bool) -> some View {
        if done { Image(systemName: "checkmark").font(LiquidType.pie).foregroundStyle(LiquidOLED.verde) }
        else if current { Image(systemName: "circle.fill").font(LiquidType.pie).foregroundStyle(LiquidOLED.tinta) }
        else { Image(systemName: "circle").font(LiquidType.pie).foregroundStyle(LiquidOLED.tintaTerciaria) }
    }
}

#if DEBUG
/// FER-96 — the four HR-mode rest states: waiting for a reading, «te faltan N lpm», the honesty band
/// («Almost»), and the recovered instant («Ready») — never a clock in HR mode, never a guessed number.
private func hrRestSnapshot(hrTarget: Int, nextExercise: (name: String, lastSet: Bool)? = nil) -> RestActivitySnapshot {
    RestActivitySnapshot(
        sessionId: "preview", routineName: "Empuje", setNumber: 2, setTotal: 4,
        exerciseName: "Press banca", returnDetail: "60 kg × 8",
        restStartedAt: Date(), restEndsAt: Date().addingTimeInterval(120),
        isHRMode: true, hrTarget: hrTarget, bpm: nil,
        phaseRaw: nextExercise?.lastSet == true ? "lastSetOfExercise" : nil,
        nextExerciseName: nextExercise?.name)
}

/// A configured `WatchWorkoutManager` for previews — a plain function (not a `@ViewBuilder` closure),
/// so setting its `@Published` properties is an ordinary statement, not a View-producing expression.
@MainActor private func previewRestingManager(hrTarget: Int, heartRate: Int = 0,
                                   nextExercise: (name: String, lastSet: Bool)? = nil) -> WatchWorkoutManager {
    let manager = WatchWorkoutManager()
    manager.rest = hrRestSnapshot(hrTarget: hrTarget, nextExercise: nextExercise)
    manager.heartRate = heartRate
    return manager
}

#Preview("Descanso por pulso · esperando lectura") {
    WatchFaceMetrics().environmentObject(previewRestingManager(hrTarget: 110))
        .background(LiquidOLED.fondo)
}

#Preview("Descanso por pulso · te faltan N lpm") {
    WatchFaceMetrics().environmentObject(previewRestingManager(hrTarget: 110, heartRate: 132))
        .background(LiquidOLED.fondo)
}

#Preview("Descanso por pulso · Almost") {
    // gap 3, dentro de la banda de honestidad (5)
    WatchFaceMetrics().environmentObject(previewRestingManager(hrTarget: 110, heartRate: 113))
        .background(LiquidOLED.fondo)
}

#Preview("Descanso por pulso · Ready") {
    WatchFaceMetrics().environmentObject(previewRestingManager(hrTarget: 110, heartRate: 108))
        .background(LiquidOLED.fondo)
}

/// «SIGUE: {next}» — última serie del ejercicio, próximo ejercicio conocido (Alcance §3).
#Preview("Descanso · SIGUE con el próximo ejercicio") {
    WatchFaceMetrics().environmentObject(previewRestingManager(
        hrTarget: 110, heartRate: 132, nextExercise: (name: "Fondos", lastSet: true)))
        .background(LiquidOLED.fondo)
}

#Preview("Descanso por pulso · AX5") {
    WatchFaceMetrics().environmentObject(previewRestingManager(hrTarget: 110, heartRate: 132))
        .background(LiquidOLED.fondo)
        .dynamicTypeSize(.accessibility5)
}
#endif
