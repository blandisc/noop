import SwiftUI
import CenitDesign
import StrandTraining

private typealias RunSnapshot = StrengthSessionSnapshot.RunSnapshot
private typealias SetSnapshot = StrengthSessionSnapshot.SetSnapshot

/// C1 (FER-361) · ola 2 · B2 — the STANDALONE session's live face: the watch itself is the logger, so
/// there is no iPhone mirroring `rest`/`capture`/`plan` to read (those stay nil the whole session). This
/// view reads `manager.sessionSnapshot` directly and derives «which set is up» itself — a document-order
/// walk to the first undone set — because `logStandaloneSet`/`addStandaloneDrop` never touch
/// `RunSnapshot.currentSet`/`currentIndex` (those are the PLAN's template cursor, frozen at the values
/// `asTemplate` seeded, B1's contract). Sibling of `WatchLiveFaceView` (the MIRRORED face): same page/
/// swipe grammar and Liquid-sobre-OLED vocabulary, but built fresh because the two faces read from
/// completely different published state.
///
/// D1 (decisión del dueño, ola 2): la META es el héroe — «peso × reps» + «SERIE N/M» — pulso y zona son
/// secundarios, la jerarquía inversa de la cara espejada (cuyo héroe es el pulso). La corona digital
/// mueve el número enfocado (peso por default, paso de 2.5 kg — el mismo `weightStepKg` métrico que usa
/// el teclado del iPhone; reps por 1); nada llega al manager hasta «Registrar».
struct WatchStandaloneLiveView: View {
    var body: some View {
        TabView {
            WatchStandaloneWorkingPage()
            WatchStandaloneFinishPage()
        }
        .tabViewStyle(.page)
    }
}

// MARK: - Cursor — the first undone set, in document order (no manager-maintained pointer exists)

/// Where standalone logging is right now. Recomputed on every `sessionSnapshot` change; `Equatable` so a
/// view can key a reseed off it without re-firing on every incidental mutation (e.g. `updatedTs`).
private struct StandaloneCursor: Equatable {
    var runIndex: Int
    var setIndex: Int

    /// The first non-skipped run's first undone set, walking runs and sets in plan order. nil once every
    /// run is either skipped or fully done.
    static func locate(in snapshot: StrengthSessionSnapshot?) -> StandaloneCursor? {
        guard let snapshot else { return nil }
        for (ri, run) in snapshot.runs.enumerated() where !run.skipped {
            if let si = run.sets.firstIndex(where: { !$0.done }) {
                return StandaloneCursor(runIndex: ri, setIndex: si)
            }
        }
        return nil
    }
}

// MARK: - Working page (states: working a set / resting / unsupported exercise / all done)

private struct WatchStandaloneWorkingPage: View {
    @EnvironmentObject var manager: WatchWorkoutManager

    private enum Focus: Equatable { case weight, reps }

    /// A rest window this view runs itself — no manager API exists for a standalone rest countdown
    /// (`RestActivitySnapshot`/`manager.rest` are populated only by iPhone `.rest` messages). Not
    /// persisted: a relaunch mid-rest drops back to the working state, losing only the countdown, never
    /// the logged sets (those already went through `WatchSessionStore` via `logStandaloneSet`).
    private struct LocalRest: Equatable {
        var startedAt: Date
        var endsAt: Date
    }

    @State private var draftWeightKg: Double = 0
    @State private var draftReps: Double = 1
    @State private var focus: Focus = .weight
    @State private var focusedValue: Double = 0
    /// AMRAP-pending only: becomes true once the person has moved focus to reps at least once, so the
    /// hero swaps the «Las que puedas» placeholder for the live crown number exactly when they start
    /// dialing it in, never before (D1 forbids ever showing a guessed rep count).
    @State private var repsEditingStarted = false
    @State private var loggedCheck = false
    @State private var localRest: LocalRest?
    @State private var restJustEnded = false
    @State private var crownAnnounceTask: Task<Void, Never>?
    @State private var restEndTask: Task<Void, Never>?

    private var cursor: StandaloneCursor? { StandaloneCursor.locate(in: manager.sessionSnapshot) }

    private var currentRun: RunSnapshot? {
        guard let cursor, let snap = manager.sessionSnapshot, cursor.runIndex < snap.runs.count else { return nil }
        return snap.runs[cursor.runIndex]
    }

    private var currentSet: SetSnapshot? {
        guard let cursor, let run = currentRun, cursor.setIndex < run.sets.count else { return nil }
        return run.sets[cursor.setIndex]
    }

    /// `logStandaloneSet` only ever writes `weightKg`/`reps` — it has no `timeS`/`distanceM` parameters,
    /// so a `.time`/`.distance` run genuinely can't be logged from here yet (a manager-API gap, not a UI
    /// choice not to build it; flagged in the B2 handoff).
    private var isSupportedType: Bool {
        guard let run = currentRun else { return true }
        return run.type == .weightReps || run.type == .bodyweight
    }

    private var isAmrapPending: Bool {
        guard let set = currentSet else { return false }
        return (set.mode ?? .standard) == .amrap && set.reps == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            if manager.isStandalone, !manager.iPhoneReachable { disconnectedLine }
            if restJustEnded {
                WatchRestEndedView()
            } else if let rest = localRest {
                restingView(rest)
            } else if let run = currentRun, let set = currentSet {
                if isSupportedType { workingView(run: run, set: set) }
                else { unsupportedView(run: run) }
            } else {
                allDoneView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, LiquidSpace.s300)
        .padding(.vertical, LiquidSpace.s200)
        .onChange(of: cursor, initial: true) { _, newCursor in
            guard let newCursor, let snap = manager.sessionSnapshot,
                  newCursor.runIndex < snap.runs.count else { return }
            let run = snap.runs[newCursor.runIndex]
            guard newCursor.setIndex < run.sets.count else { return }
            reseed(set: run.sets[newCursor.setIndex])
        }
        .onChange(of: focus) { _, newFocus in
            if newFocus == .reps { repsEditingStarted = true }
            focusedValue = newFocus == .weight ? draftWeightKg : draftReps
        }
        .onChange(of: focusedValue) { _, newValue in
            if focus == .weight { draftWeightKg = newValue } else { draftReps = newValue }
            scheduleCrownAnnouncement()
        }
    }

    private func reseed(set: SetSnapshot) {
        draftWeightKg = set.weightKg
        draftReps = Double(set.reps ?? 1)
        focus = .weight
        focusedValue = draftWeightKg
        repsEditingStarted = false
    }

    // MARK: Working — the hero + crown + Register

    private func workingView(run: RunSnapshot, set: SetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text("Set \(setNumber) / \(setTotal(run))")
                .font(LiquidType.filaConteo).foregroundStyle(LiquidOLED.tintaSecundaria)
            Text(verbatim: run.name)
                .font(LiquidType.tituloFila).foregroundStyle(LiquidOLED.tintaTerciaria).lineLimit(1)
            heroRow(set: set)
            Spacer(minLength: LiquidSpace.s100)
            pulseSecondaryLine
            if manager.healthAccessDenied { permissionNote }
            registerButtons(run: run, set: set)
        }
        .focusable()
        .digitalCrownRotation($focusedValue, from: crownFrom, through: crownThrough, by: crownStep,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
    }

    private var setNumber: Int { (cursor?.setIndex ?? 0) + 1 }
    private func setTotal(_ run: RunSnapshot) -> Int { run.sets.count }

    private var crownFrom: Double { focus == .weight ? 0 : 1 }
    private var crownThrough: Double { focus == .weight ? 400 : 99 }
    private var crownStep: Double { focus == .weight ? 2.5 : 1 }

    private func heroRow(set: SetSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
            numberChip(display: Self.weightNumberText(draftWeightKg), unit: "kg", isFocused: focus == .weight,
                       axLabel: Text("Weight, \(Self.weightNumberText(draftWeightKg)) kilograms")) {
                focus = .weight
            }
            Text(verbatim: "×").font(LiquidType.displayM).foregroundStyle(LiquidOLED.tintaTerciaria)
            if isAmrapPending, !repsEditingStarted {
                Text("However many you can")
                    .font(LiquidType.subtituloFila)
                    .foregroundStyle(LiquidOLED.tintaSecundaria)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(minHeight: LiquidControl.hitTarget, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { focus = .reps }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Reps, however many you can"))
                    .accessibilityAddTraits(.isButton)
            } else {
                numberChip(display: "\(Int(draftReps.rounded()))", unit: nil, isFocused: focus == .reps,
                           axLabel: Text("Reps, \(Int(draftReps.rounded()))")) {
                    focus = .reps
                }
            }
        }
        .animation(LiquidMotion.settle(LiquidMotion.quick), value: focus)
    }

    private func numberChip(display: String, unit: String?, isFocused: Bool, axLabel: Text,
                            onFocus: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s050) {
            Text(verbatim: display)
                .font(LiquidType.displayM).tracking(LiquidType.displayMTracking)
                .foregroundStyle(isFocused ? LiquidOLED.tinta : LiquidOLED.tintaSecundaria)
            if let unit {
                Text(verbatim: unit).font(LiquidType.unidad).foregroundStyle(LiquidOLED.tintaTerciaria)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .padding(.vertical, LiquidSpace.s050)
        .frame(minHeight: LiquidControl.hitTarget, alignment: .leading)
        .overlay(alignment: .bottom) {
            // token-exempt(sistema): geometría watchOS — subrayado de foco de 2 pt, sin token de borde a ese grosor
            if isFocused { Rectangle().fill(LiquidOLED.tinta).frame(height: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isFocused { WatchHaptic.actionTapped.play() }
            onFocus()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(axLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// «60» / «62.5» — trims the decimal when whole, same convention as the iPhone's `StrengthDisplay`
    /// (`CenitWatch` can't import that app-target file, so this is the watch's own copy of the rule).
    private static func weightNumberText(_ kg: Double) -> String {
        let rounded = kg.rounded()
        return abs(kg - rounded) < 0.01 ? "\(Int(rounded))" : String(format: "%.1f", kg)
    }

    private static func kgText(_ kg: Double) -> String { "\(weightNumberText(kg)) kg" }

    private func scheduleCrownAnnouncement() {
        crownAnnounceTask?.cancel()
        let isWeight = focus == .weight
        let weightNow = draftWeightKg
        let repsNow = Int(draftReps.rounded())
        crownAnnounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            let text = isWeight
                ? String(localized: "Weight, \(Self.weightNumberText(weightNow)) kilograms")
                : String(localized: "Reps, \(repsNow)")
            AccessibilityNotification.Announcement(text).post()
        }
    }

    // MARK: Register / Register-and-drop

    /// AMRAP-pending until the person has actually dialed a count (`repsEditingStarted`) — «pide el
    /// número con la corona» (handoff punto 2) means the button REQUIRES that, not silently registering
    /// the seeded placeholder draft (1 rep) if someone taps Register before ever touching reps.
    private var registrationBlockedByPendingAmrap: Bool { isAmrapPending && !repsEditingStarted }

    private func registerButtons(run: RunSnapshot, set: SetSnapshot) -> some View {
        VStack(spacing: LiquidSpace.s100) {
            Button(action: { registerCurrentSet(run: run, set: set) }) {
                Group {
                    if loggedCheck { Image(systemName: "checkmark").accessibilityHidden(true) }
                    else { Text("Complete set") }
                }
                .font(LiquidType.filaConteo)
                .frame(maxWidth: .infinity, minHeight: LiquidControl.hitTarget)
            }
            // token-exempt(sistema): control nativo watchOS
            .buttonStyle(.borderedProminent)
            .tint(LiquidOLED.tinta)
            .disabled(registrationBlockedByPendingAmrap)
            .accessibilityLabel(Text("Complete set"))

            if canDrop(run: run, set: set) {
                Button(action: { registerAndDrop(run: run, set: set) }) {
                    Text("Complete set and drop")
                        .font(LiquidType.pie)
                        .frame(maxWidth: .infinity, minHeight: LiquidControl.hitTarget)
                }
                // token-exempt(sistema): control nativo watchOS
                .buttonStyle(.bordered)
                .tint(LiquidOLED.tintaSecundaria)
                .disabled(registrationBlockedByPendingAmrap)
            }
        }
    }

    /// Read-only mirror of `WatchWorkoutManager.addStandaloneDrop`'s eligibility guard (mother lookup +
    /// `SetVariants.maxDropSteps` cap), so «Complete set and drop» is never shown when it would silently
    /// no-op. Duplicated on purpose — the manager exposes no `canAddDrop` query and this task's contract
    /// says not to add one to it; five read-only lines here are cheaper than a new manager API.
    private func canDrop(run: RunSnapshot, set: SetSnapshot) -> Bool {
        guard set.kind == .work, let si = run.sets.firstIndex(where: { $0.id == set.id }) else { return false }
        var motherIndex = si
        while motherIndex > 0 && run.sets[motherIndex].mode == .drop { motherIndex -= 1 }
        guard run.sets[motherIndex].mode != .drop else { return false }
        var tail = motherIndex
        var steps = 0
        while tail + 1 < run.sets.count && run.sets[tail + 1].mode == .drop { tail += 1; steps += 1 }
        return steps < SetVariants.maxDropSteps
    }

    private func registerCurrentSet(run: RunSnapshot, set: SetSnapshot) {
        let reps = max(1, Int(draftReps.rounded()))
        guard manager.logStandaloneSet(runId: run.id, setId: set.id, weightKg: draftWeightKg, reps: reps)
        else { return }
        showLoggedCheck()
        AccessibilityNotification.Announcement(String(localized: "Set \(setNumber) logged")).post()
        let seconds = set.rest?.seconds ?? run.restSeconds
        if seconds > 0 { startLocalRest(seconds: seconds) }
    }

    /// «Bajar y seguir sin descanso» is the method (`SetVariants` doc) — never opens a rest window.
    private func registerAndDrop(run: RunSnapshot, set: SetSnapshot) {
        let reps = max(1, Int(draftReps.rounded()))
        guard manager.logStandaloneSet(runId: run.id, setId: set.id, weightKg: draftWeightKg, reps: reps)
        else { return }
        _ = manager.addStandaloneDrop(runId: run.id, afterSetId: set.id)
        showLoggedCheck()
        AccessibilityNotification.Announcement(String(localized: "Set logged, drop added")).post()
    }

    private func showLoggedCheck() {
        withAnimation(LiquidMotion.settle(LiquidMotion.brief)) { loggedCheck = true }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(LiquidMotion.dismiss(LiquidMotion.brief)) { loggedCheck = false }
        }
    }

    // MARK: Pulse (secondary — D1: never the hero here)

    private var pulseDashed: Bool { manager.heartRate == 0 || manager.healthAccessDenied }

    private var pulseSecondaryLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
            (pulseDashed ? Text(verbatim: "--") : Text(verbatim: "\(manager.heartRate)"))
                .font(Font.system(.subheadline).monospacedDigit())
                .foregroundStyle(pulseDashed ? LiquidOLED.tintaTerciaria : LiquidOLED.rosa)
            Text("bpm").font(LiquidType.unidad).foregroundStyle(LiquidOLED.tintaSecundaria).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pulseDashed ? Text("Pulse, no reading") : Text("Pulse, \(manager.heartRate) beats per minute"))
    }

    /// State 7-equivalent for standalone (point 6 of the handoff): the session keeps serving — sets still
    /// log — only the pulse reading and the eventual Health save degrade. More precise than reusing the
    /// mirrored flow's generic warning, which says «nothing saved» (untrue here: the buffered sets still
    /// save; only the final `HKWorkout` needs the permission).
    private var permissionNote: some View {
        Text("No access to Health. Your sets still save. Saving to Health needs access.")
            .font(LiquidType.pie)
            .foregroundStyle(LiquidOLED.tintaSecundaria)
            .lineLimit(nil)
    }

    // MARK: Disconnected (point 4 of the handoff)

    private var disconnectedLine: some View {
        Text("No iPhone · saves when reconnected")
            .font(LiquidType.pie)
            .foregroundStyle(LiquidOLED.tintaTerciaria)
            .lineLimit(2)
    }

    // MARK: Unsupported exercise type (manager-API gap: no timeS/distanceM in logStandaloneSet)

    private func unsupportedView(run: RunSnapshot) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(verbatim: run.name).font(LiquidType.tituloHoja).foregroundStyle(LiquidOLED.tinta).lineLimit(2)
            Text("This exercise can't be logged from the watch yet. Log it on your iPhone.")
                .font(LiquidType.filaConteo)
                .foregroundStyle(LiquidOLED.tintaSecundaria)
                .lineLimit(nil)
        }
    }

    // MARK: All sets done

    private var allDoneView: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Image(systemName: "checkmark.circle")
                .font(LiquidType.iconSF(size: 36))
                .foregroundStyle(LiquidOLED.verde)
            Text("All sets logged").font(LiquidType.tituloHoja).foregroundStyle(LiquidOLED.tinta)
            Text("Swipe to finish your workout.")
                .font(LiquidType.filaConteo)
                .foregroundStyle(LiquidOLED.tintaSecundaria)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Resting — a LOCAL countdown (no manager rest API exists for standalone)

    private func restingView(_ rest: LocalRest) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text("Rest").liquidKicker().foregroundStyle(LiquidOLED.tintaTerciaria).accessibilityHidden(true)
            // token-exempt(sistema): geometría watchOS — countdown 44; sin token tabular Liquid a ese tamaño
            Text(timerInterval: rest.startedAt...rest.endsAt, countsDown: true)
                .font(.system(size: WatchMetrics.heroRestCountdown, weight: .bold).monospacedDigit())
                .foregroundStyle(LiquidOLED.ambar)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel(Text("Rest, \(secondsLeft(rest)) seconds left"))
            ProgressView(timerInterval: rest.startedAt...rest.endsAt, countsDown: false) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
                .tint(LiquidOLED.ambar)
                .accessibilityHidden(true)
            HStack(spacing: LiquidSpace.s100) {
                if secondsLeft(rest) > 0 { pill("−30 s") { adjustLocalRest(by: -30) } }
                pill("+30 s") { adjustLocalRest(by: 30) }
                pill("Skip rest") { skipLocalRest() }
            }
            Spacer(minLength: LiquidSpace.s100)
            if let run = currentRun, let set = currentSet {
                // `setNumber` goes through `String(_:)` so this extracts to the SAME "Next: set %@ · %@"
                // key `WatchLiveFaceView`'s sibling copy already reserved (es: «Sigue: serie %1$@ · %2$@»),
                // rather than minting a near-duplicate "Next: set %lld · %@" key.
                Text("Next: set \(String(setNumber)) · \(nextDetail(run: run, set: set))")
                    .font(LiquidType.pie)
                    .foregroundStyle(LiquidOLED.tintaSecundaria)
                    .lineLimit(2)
            }
        }
    }

    private func nextDetail(run: RunSnapshot, set: SetSnapshot) -> String {
        let weight = Self.kgText(set.weightKg)
        if let reps = set.reps { return "\(weight) × \(reps)" }
        if (set.mode ?? .standard) == .amrap { return "\(weight) × \(String(localized: "However many you can"))" }
        return weight
    }

    private func pill(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            WatchHaptic.actionTapped.play()
            action()
        } label: {
            Text(title).font(LiquidType.pie).frame(maxWidth: .infinity, minHeight: LiquidControl.hitTarget)
        }
        // token-exempt(sistema): control nativo watchOS
        .buttonStyle(.bordered)
        .tint(LiquidOLED.tintaSecundaria)
    }

    private func secondsLeft(_ rest: LocalRest) -> Int { max(0, Int(rest.endsAt.timeIntervalSinceNow.rounded())) }

    private func startLocalRest(seconds: Int) {
        let now = Date()
        let endsAt = now.addingTimeInterval(TimeInterval(seconds))
        localRest = LocalRest(startedAt: now, endsAt: endsAt)
        scheduleRestCompletion(endsAt: endsAt)
    }

    private func adjustLocalRest(by deltaS: Int) {
        guard var rest = localRest else { return }
        let newEnd = max(Date(), rest.endsAt.addingTimeInterval(TimeInterval(deltaS)))
        rest.endsAt = newEnd
        localRest = rest
        scheduleRestCompletion(endsAt: newEnd)
    }

    private func skipLocalRest() {
        restEndTask?.cancel()
        localRest = nil
    }

    /// Mirrors `WatchWorkoutManager.fireRestEnded()`'s shape (haptic + ~3s transition) since that method
    /// is `private` and gated on `manager.rest != nil` (never true standalone) — `WatchRestEndedView`'s
    /// own `.onAppear` already posts the «Ready» VoiceOver announcement, so this only plays the haptic.
    private func scheduleRestCompletion(endsAt: Date) {
        restEndTask?.cancel()
        restEndTask = Task {
            let delay = endsAt.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            localRest = nil
            restJustEnded = true
            WatchHaptic.restEnded.play()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            restJustEnded = false
        }
    }
}

// MARK: - Finish page (swipe) — «Terminar» is always reachable, one confirmation step

private struct WatchStandaloneFinishPage: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    @State private var confirming = false

    var body: some View {
        VStack(spacing: LiquidSpace.s200) {
            Spacer()
            Text("Session").liquidKicker().foregroundStyle(LiquidOLED.tintaTerciaria)
            Button(role: .destructive) { confirming = true } label: {
                Text("Finish").frame(maxWidth: .infinity, minHeight: LiquidControl.hitTarget)
            }
            // token-exempt(sistema): control nativo watchOS
            .buttonStyle(.bordered)
            .tint(LiquidOLED.negativo)
            Spacer()
        }
        .padding(.horizontal, LiquidSpace.s300)
        // token-exempt(sistema): control nativo watchOS — liquidConfirm es chrome de hoja iPhone
        .confirmationDialog("Finish workout?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Finish", role: .destructive) { manager.endStandaloneSession() }
            Button("Keep training", role: .cancel) { }
        }
    }
}
