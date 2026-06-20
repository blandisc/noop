#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import WhoopStore

// Plate weights read cleaner without a trailing «.0» (60, not 60.0) but keep a half-plate decimal (2.5).
private func plateNumber(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v.rounded())) : String(format: "%.1f", v)
}

/// A weight in kilograms formatted for display in the user's unit, e.g. "82.5 kg" / "180 lb".
private func massString(_ kg: Double, units: UnitSystem) -> String {
    let v = units == .imperial ? UnitFormatter.kgToPounds(kg) : kg
    return "\(plateNumber(v)) \(UnitFormatter.massUnit(units))"
}

// MARK: - Guided strength session (FER-347)
//
// The heart of the strength tracker: the guided, set-by-set execution. A «Foco» (the dominant weight in
// the effort hue, a «register set» button, the «la última vez» reference + a suggested bump) plus a
// «cajón» — the full editable set table behind a detented sheet (`presentationDetents`) — and a rest
// phase that doubles as the «change exercise» bridge (the plan navigator: skip / reorder).
//
// Following the `LiveWorkoutSheet` pattern (FER-197): the session lives in `AppModel` (global), so
// closing the sheet or switching tabs never loses it; the Train hub re-presents it. No nested
// NavigationStack — the drawer is a SHEET with detents, not a pushed screen (FER-171). The fixed
// countdown is shipped here; the smart, HR-driven rest is FER-348 (W3·descanso) — its slot is the
// rest chip. Runs fully offline and without HealthKit (logging strength is manual).

// MARK: - Session model (the durable, observable state owned by AppModel)

/// A guided strength session in progress. A reference type owned by `AppModel` and observed directly by
/// the sheet, so the many small edits (steppers, table edits, rest ticks) don't republish all of AppModel.
@MainActor
final class StrengthSessionModel: ObservableObject {
    /// One logged/planned set within an exercise. Weight is stored in kilograms (display converts).
    struct WorkingSet: Identifiable, Equatable {
        let id: String
        var weightKg: Double
        var reps: Int
        var done: Bool
        var doneTs: Int?
    }

    /// One exercise's run: its plan, the editable sets, which set the Foco is on, and whether it was skipped.
    struct ExerciseRun: Identifiable, Equatable {
        let id: String            // the RoutineExercise id (stable within the routine)
        let exerciseId: String
        let name: String
        let type: ExerciseType
        let restSeconds: Int
        /// Last time's top work set, for the «la última vez» reference + the suggested bump. nil = first time.
        let lastWeightKg: Double?
        let lastReps: Int?
        var sets: [WorkingSet]
        var currentSet: Int
        var skipped: Bool
    }

    enum Phase: Equatable { case capturing, resting }

    let id: String
    let routineId: String?
    let routineName: String
    let startTs: Int

    @Published var runs: [ExerciseRun]
    @Published var currentIndex: Int
    @Published var phase: Phase = .capturing
    /// When the fixed rest countdown ends; nil when not resting. Durable so the timer survives a tab switch.
    @Published var restEndsAt: Date?

    init(id: String = UUID().uuidString, routineId: String?, routineName: String,
         startTs: Int, runs: [ExerciseRun]) {
        self.id = id
        self.routineId = routineId
        self.routineName = routineName
        self.startTs = startTs
        self.runs = runs
        self.currentIndex = runs.firstIndex { !$0.skipped } ?? 0
    }

    // MARK: Derived

    /// The focused exercise — nil when focus has nowhere active to land (every exercise done-and-parked is
    /// fine, but a *skipped* run is never surfaced; the sheet shows its «complete» state instead).
    var current: ExerciseRun? {
        guard runs.indices.contains(currentIndex) else { return nil }
        let run = runs[currentIndex]
        return run.skipped ? nil : run
    }
    var currentSet: WorkingSet? {
        guard let run = current, run.sets.indices.contains(run.currentSet) else { return nil }
        return run.sets[run.currentSet]
    }
    /// Active (non-skipped) exercises, with their original index — drives the plan navigator.
    var activeExercises: [(index: Int, run: ExerciseRun)] {
        runs.enumerated().compactMap { $0.element.skipped ? nil : ($0.offset, $0.element) }
    }
    /// Sets registered vs total planned, across non-skipped exercises (for the «terminar» confirm + footer).
    var doneCount: Int { runs.filter { !$0.skipped }.reduce(0) { $0 + $1.sets.filter(\.done).count } }
    var pendingCount: Int { runs.filter { !$0.skipped }.reduce(0) { $0 + $1.sets.filter { !$0.done }.count } }

    // MARK: Editing the current set

    func setCurrentWeight(_ kg: Double) { mutateCurrentSet { $0.weightKg = max(0, kg) } }
    func setCurrentReps(_ reps: Int) { mutateCurrentSet { $0.reps = max(0, reps) } }
    func bumpWeight(byKg delta: Double) { mutateCurrentSet { $0.weightKg = max(0, $0.weightKg + delta) } }
    func bumpReps(_ delta: Int) { mutateCurrentSet { $0.reps = max(0, $0.reps + delta) } }

    private func mutateCurrentSet(_ change: (inout WorkingSet) -> Void) {
        guard runs.indices.contains(currentIndex) else { return }
        let i = runs[currentIndex].currentSet
        guard runs[currentIndex].sets.indices.contains(i) else { return }
        change(&runs[currentIndex].sets[i])
    }

    /// Make a table row the current one (so the Foco's steppers edit it). Brings its exercise into focus.
    func select(exerciseIndex: Int, setIndex: Int) {
        guard runs.indices.contains(exerciseIndex),
              runs[exerciseIndex].sets.indices.contains(setIndex) else { return }
        currentIndex = exerciseIndex
        runs[exerciseIndex].currentSet = setIndex
        phase = .capturing
    }

    // MARK: Set actions

    /// Register the current set (mark done) and start the fixed rest. Then advance to the next pending set.
    func registerCurrentSet(now: Date = Date()) {
        guard runs.indices.contains(currentIndex) else { return }
        let i = runs[currentIndex].currentSet
        guard runs[currentIndex].sets.indices.contains(i) else { return }
        runs[currentIndex].sets[i].done = true
        runs[currentIndex].sets[i].doneTs = Int(now.timeIntervalSince1970)
        startRest(seconds: runs[currentIndex].restSeconds, now: now)
        advanceToNextPending()
    }

    /// Append a fresh set to the current exercise (copying the last row's load), and focus it.
    func addSet() {
        guard runs.indices.contains(currentIndex) else { return }
        let template = runs[currentIndex].sets.last
        let set = WorkingSet(id: UUID().uuidString,
                             weightKg: template?.weightKg ?? 0, reps: template?.reps ?? 8, done: false)
        runs[currentIndex].sets.append(set)
        runs[currentIndex].currentSet = runs[currentIndex].sets.count - 1
        phase = .capturing
    }

    /// Skip the current (pending) set: drop it from the plan. A done set is left untouched.
    func skipCurrentSet() {
        guard runs.indices.contains(currentIndex) else { return }
        let i = runs[currentIndex].currentSet
        guard runs[currentIndex].sets.indices.contains(i), !runs[currentIndex].sets[i].done else { return }
        runs[currentIndex].sets.remove(at: i)
        runs[currentIndex].currentSet = min(i, max(0, runs[currentIndex].sets.count - 1))
        advanceToNextPending()
    }

    // MARK: Exercise navigator (the «change exercise» bridge)

    /// Jump straight to an exercise (skips the rest). Used by the plan navigator.
    func goToExercise(_ index: Int) {
        guard runs.indices.contains(index), !runs[index].skipped else { return }
        currentIndex = index
        runs[index].currentSet = runs[index].sets.firstIndex { !$0.done } ?? 0
        phase = .capturing
        restEndsAt = nil
    }

    /// Mark an exercise as skipped (it no longer counts / shows as current). Advances off it if it was current.
    func skipExercise(_ index: Int) {
        guard runs.indices.contains(index) else { return }
        runs[index].skipped = true
        if index == currentIndex { phase = .capturing; restEndsAt = nil; advanceToNextPending(fromStart: true) }
    }

    /// Move an exercise one slot earlier in the plan (reorder), keeping the current exercise focused.
    func moveExerciseEarlier(_ index: Int) {
        guard runs.indices.contains(index), index > 0 else { return }
        let focused = current?.id
        runs.swapAt(index, index - 1)
        if let focused { currentIndex = runs.firstIndex { $0.id == focused } ?? currentIndex }
    }

    // MARK: Rest (fixed — FER-348 adds the HR-driven variant)

    func startRest(seconds: Int, now: Date = Date()) {
        guard seconds > 0 else { phase = .capturing; restEndsAt = nil; return }
        restEndsAt = now.addingTimeInterval(TimeInterval(seconds))
        phase = .resting
    }
    func extendRest(byseconds delta: Int, now: Date = Date()) {
        guard let end = restEndsAt else { return }
        restEndsAt = max(now, end.addingTimeInterval(TimeInterval(delta)))
    }
    func skipRest() { phase = .capturing; restEndsAt = nil }

    /// Move focus to the next not-done set: rest of the current exercise, then later non-skipped exercises.
    private func advanceToNextPending(fromStart: Bool = false) {
        // Current exercise first (a set after the current one), unless we were told to scan from scratch.
        if !fromStart, runs.indices.contains(currentIndex), !runs[currentIndex].skipped {
            if let next = runs[currentIndex].sets.firstIndex(where: { !$0.done }) {
                runs[currentIndex].currentSet = next
                return
            }
        }
        // Then the earliest pending set in any later/earlier non-skipped exercise.
        for offset in 1...max(1, runs.count) {
            let idx = (currentIndex + offset) % max(1, runs.count)
            guard runs.indices.contains(idx), !runs[idx].skipped else { continue }
            if let next = runs[idx].sets.firstIndex(where: { !$0.done }) {
                currentIndex = idx
                runs[idx].currentSet = next
                return
            }
        }
        // Nothing pending anywhere. Never leave focus on a skipped run (the Foco would render a skipped
        // exercise) — park it on the first still-active exercise if one remains.
        if !runs.indices.contains(currentIndex) || runs[currentIndex].skipped {
            if let active = runs.firstIndex(where: { !$0.skipped }) { currentIndex = active }
        }
    }

    /// True when every set across all non-skipped exercises is done (or all exercises were skipped) — the
    /// Foco then shows a «complete» state instead of a finished exercise's last set.
    var isComplete: Bool { pendingCount == 0 }

    // MARK: Persistence

    /// Build the `StrengthSession` + its done `SetEntry` rows for saving (work sets only; warm-ups are FER-351).
    func buildForSave(deviceId: String?, endTs: Int) -> (StrengthSession, [SetEntry]) {
        let session = StrengthSession(id: id, routineId: routineId, startTs: startTs,
                                      endTs: endTs, deviceId: deviceId)
        var entries: [SetEntry] = []
        var position = 0
        for run in runs where !run.skipped {
            for set in run.sets where set.done {
                entries.append(SetEntry(id: set.id, sessionId: id, exerciseId: run.exerciseId,
                                        position: position, kind: .work,
                                        weightKg: set.weightKg > 0 ? set.weightKg : nil,
                                        reps: set.reps > 0 ? set.reps : nil,
                                        done: true, ts: set.doneTs ?? endTs))
                position += 1
            }
        }
        return (session, entries)
    }

    // MARK: Building from a routine plan

    /// One resolved plan slot handed in from «Rutina de hoy»: the routine exercise, its resolved exercise,
    /// and its recent work sets (newest first) for the «la última vez» prefill.
    struct PlanSlot {
        let re: RoutineExercise
        let exercise: Exercise?
        let lastSets: [SetEntry]
    }

    static func make(routineId: String?, routineName: String, slots: [PlanSlot],
                     startTs: Int) -> StrengthSessionModel {
        let runs: [ExerciseRun] = slots.map { slot in
            let last = slot.lastSets.first
            let lastWeight = last?.weightKg
            let lastReps = last?.reps
            let count = max(1, slot.re.targetSets)
            let weight = slot.re.targetWeightKg ?? lastWeight ?? 0
            let reps = slot.re.targetReps ?? lastReps ?? 8
            let sets = (0..<count).map { _ in
                WorkingSet(id: UUID().uuidString, weightKg: weight, reps: reps, done: false)
            }
            return ExerciseRun(id: slot.re.id, exerciseId: slot.re.exerciseId,
                               name: slot.exercise?.name ?? String(localized: "Exercise"),
                               type: slot.exercise?.type ?? .weightReps,
                               restSeconds: slot.re.restSeconds,
                               lastWeightKg: lastWeight, lastReps: lastReps,
                               sets: sets, currentSet: 0, skipped: false)
        }
        return StrengthSessionModel(routineId: routineId, routineName: routineName,
                                    startTs: startTs, runs: runs)
    }
}

// MARK: - The guided session sheet

/// The guided strength session, in the light «Instrumento diurno» language. The theme is passed in
/// explicitly (it doesn't cross the `.sheet` boundary — FER-190). The weight is the dominant datum in the
/// effort hue; the table is a detented `.sheet` drawer; rest is a fixed countdown that hosts the plan
/// navigator. The session itself lives in `AppModel`, so dismissing this sheet never ends it.
struct LiveStrengthSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: StrengthSessionModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    var theme: InstrumentoTheme = .base

    @State private var showTable = false
    @State private var confirmFinish = false

    private var units: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var imperial: Bool { units == .imperial }
    /// Plate step: 2.5 kg metric, 5 lb imperial — stored as kg.
    private var weightStepKg: Double { imperial ? 5 * Self.kgPerPound : 2.5 }
    static let kgPerPound = 0.45359237

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                topBar
                if session.current == nil {
                    completePhase
                } else if session.phase == .resting, session.restEndsAt != nil {
                    restPhase
                } else {
                    capturePhase
                }
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .instrumentoTheme(theme)
        .sheet(isPresented: $showTable) {
            SetTableDrawer(session: session, units: units, theme: theme)
                .environmentObject(model)
                .instrumentoTheme(theme)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
                .preferredColorScheme(.light)
        }
        .alert("Finish workout?", isPresented: $confirmFinish) {
            Button("Finish", role: .destructive) { model.endStrengthSession(save: true); dismiss() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text(session.doneCount == 0
                 ? "No sets logged yet — finishing will discard this workout."
                 : (session.pendingCount > 0
                    ? "\(session.pendingCount) sets aren't logged yet. Finish anyway and save the ones you did?"
                    : "Save this workout?"))
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exerciseCounter).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(session.routineName).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
            Spacer(minLength: 8)
            Button { finishTapped() } label: {
                Text("Finish").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Finish workout"))
        }
    }

    private var exerciseCounter: String {
        guard let run = session.current, let pos = session.activeExercises.firstIndex(where: { $0.run.id == run.id })
        else { return String(localized: "Workout") }
        return String(localized: "Exercise \(pos + 1) of \(session.activeExercises.count)")
    }

    // MARK: Capture phase (the «Foco»)

    @ViewBuilder private var capturePhase: some View {
        if let run = session.current {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(run.name).font(StrandFont.title1).foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(restChipText(run.restSeconds))
                            .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous)
                                .strokeBorder(theme.hairline, lineWidth: 1))
                            .accessibilityLabel(Text("Rest \(run.restSeconds) seconds"))
                    }
                    referenceLine(run)
                }

                weightFoco(run)
                repsRow
                registerButton
                tableHandle(run)
            }
        }
    }

    private func referenceLine(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        HStack(spacing: 8) {
            Text(setCounterText(run)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            Spacer(minLength: 8)
            if let lw = run.lastWeightKg, let lr = run.lastReps {
                Text("Last · \(massText(lw)) × \(lr)")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                if let suggested = suggestedWeight(run) {
                    Button { session.setCurrentWeight(suggested) } label: {
                        Text("+\(plateNumber(displayWeight(weightStepKg)))")
                            .font(StrandFont.caption).foregroundStyle(theme.dataRecovery)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Use suggested weight \(massText(suggested))"))
                }
            } else {
                Text("First time").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
        }
    }

    /// The dominant datum: the weight, in the effort hue, flanked by minus/plus steppers.
    private func weightFoco(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        HStack {
            stepper(system: "minus") { session.bumpWeight(byKg: -weightStepKg) }
                .accessibilityLabel(Text("Decrease weight"))
            Spacer(minLength: 8)
            VStack(spacing: 0) {
                Text(plateNumber(displayWeight(session.currentSet?.weightKg ?? 0)))
                    .instrumentoHero(76).foregroundStyle(theme.dataStrain)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                Text(UnitFormatter.massUnit(units)).font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: 8)
            stepper(system: "plus") { session.bumpWeight(byKg: weightStepKg) }
                .accessibilityLabel(Text("Increase weight"))
        }
        .accessibilityElement(children: .contain)
    }

    private var repsRow: some View {
        HStack {
            Text("Reps").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
            Spacer()
            HStack(spacing: 16) {
                stepper(system: "minus", size: 34) { session.bumpReps(-1) }
                    .accessibilityLabel(Text("Decrease reps"))
                Text("\(session.currentSet?.reps ?? 0)")
                    .font(StrandFont.title2).monospacedDigit().foregroundStyle(theme.ink)
                    .frame(minWidth: 34)
                stepper(system: "plus", size: 34) { session.bumpReps(1) }
                    .accessibilityLabel(Text("Increase reps"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var registerButton: some View {
        Button { withAnimation(.snappy) { session.registerCurrentSet() } } label: {
            Label("Register set", systemImage: "checkmark")
                .font(StrandFont.headline).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func tableHandle(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        Button { showTable = true } label: {
            HStack {
                Text("All sets · \(run.sets.filter(\.done).count) done")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                Spacer()
                HStack(spacing: 4) {
                    Text("Open table").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    Image(systemName: "chevron.up").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .padding(.top, 6).padding(.bottom, 2)
            .overlay(alignment: .top) { Divider().overlay(theme.hairline) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Open the set table"))
    }

    // MARK: Complete / empty phase (every exercise done or skipped)

    private var completePhase: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 40))
                .foregroundStyle(theme.dataRecovery).accessibilityHidden(true)
            Text(session.doneCount > 0 ? "All done" : "Nothing left")
                .font(StrandFont.title1).foregroundStyle(theme.ink)
            Text(session.doneCount > 0
                 ? "You logged \(session.doneCount) sets. Finish to save this workout."
                 : "Every exercise was skipped. Finish to close, or resume from the hub.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { model.endStrengthSession(save: true); dismiss() } label: {
                Label("Finish", systemImage: "checkmark")
                    .font(StrandFont.headline).foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Rest phase (fixed countdown + the «change exercise» bridge)

    private var restPhase: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            Text("Rest").instrumentoOverline().foregroundStyle(theme.inkTertiary)

            if let end = session.restEndsAt {
                TimelineView(.periodic(from: end, by: 1)) { ctx in
                    let remaining = max(0, Int(end.timeIntervalSince(ctx.date).rounded(.up)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.clock(remaining)).instrumentoHero(64)
                            .monospacedDigit().foregroundStyle(remaining == 0 ? theme.dataRecovery : theme.ink)
                        Text(nextUpText).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(remaining == 0 ? "Rest done. \(nextUpText)"
                                             : "Resting, \(remaining) seconds left. \(nextUpText)"))
                }
            }

            HStack(spacing: 10) {
                restAdjust("−15") { session.extendRest(byseconds: -15) }
                Button { withAnimation(.snappy) { session.skipRest() } } label: {
                    Label("Skip rest", systemImage: "forward.fill")
                        .font(StrandFont.headline).foregroundStyle(theme.paper)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                restAdjust("+15") { session.extendRest(byseconds: 15) }
            }

            planNavigator
        }
    }

    private var planNavigator: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Change exercise").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(spacing: 0) {
                ForEach(Array(session.activeExercises.enumerated()), id: \.element.run.id) { pair in
                    let item = pair.element
                    navigatorRow(index: item.index, run: item.run, isFirst: pair.offset == 0)
                    if pair.offset != session.activeExercises.count - 1 { Divider().overlay(theme.hairline) }
                }
            }
            .padding(.horizontal, 14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
        }
    }

    private func navigatorRow(index: Int, run: StrengthSessionModel.ExerciseRun, isFirst: Bool) -> some View {
        let isCurrent = index == session.currentIndex
        let complete = !run.sets.contains { !$0.done }
        return HStack(spacing: 10) {
            Button { withAnimation(.snappy) { session.goToExercise(index) } } label: {
                HStack(spacing: 10) {
                    Image(systemName: complete ? "checkmark.circle.fill" : (isCurrent ? "circle.fill" : "circle"))
                        .font(.system(size: 15))
                        .foregroundStyle(complete ? theme.dataRecovery : (isCurrent ? theme.dataStrain : theme.inkTertiary))
                    Text(run.name).font(StrandFont.body)
                        .foregroundStyle(isCurrent ? theme.ink : theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isCurrent {
                Text("now").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            } else {
                HStack(spacing: 14) {
                    if !isFirst {
                        Button { withAnimation(.snappy) { session.moveExerciseEarlier(index) } } label: {
                            Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.inkSecondary)
                        }
                        .buttonStyle(.plain).accessibilityLabel(Text("Move \(run.name) earlier"))
                    }
                    Button { withAnimation(.snappy) { session.skipExercise(index) } } label: {
                        Image(systemName: "forward.end").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.inkSecondary)
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Skip \(run.name)"))
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
    }

    private var nextUpText: String {
        guard let run = session.current, let set = session.currentSet else { return String(localized: "Workout complete") }
        let n = (run.sets.firstIndex { $0.id == set.id } ?? 0) + 1
        return String(localized: "Up next · Set \(n) · \(massText(set.weightKg)) × \(set.reps)")
    }

    // MARK: Small builders

    private func stepper(system: String, size: CGFloat = 42, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: size > 38 ? 22 : 18, weight: .regular))
                .foregroundStyle(theme.inkSecondary)
                .frame(width: size, height: size)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func restAdjust(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(StrandFont.headline).monospacedDigit().foregroundStyle(theme.inkSecondary)
                .frame(width: 56).padding(.vertical, 13)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label == "−15" ? "Subtract 15 seconds" : "Add 15 seconds"))
    }

    private func finishTapped() {
        confirmFinish = true
    }

    private func setCounterText(_ run: StrengthSessionModel.ExerciseRun) -> String {
        let n = run.currentSet + 1
        return String(localized: "Set \(n) of \(run.sets.count)")
    }

    private func restChipText(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 { return String(localized: "Rest \(seconds / 60) min") }
        return String(localized: "Rest \(seconds)s")
    }

    private func suggestedWeight(_ run: StrengthSessionModel.ExerciseRun) -> Double? {
        guard let lw = run.lastWeightKg, run.type == .weightReps || run.type == .bodyweight else { return nil }
        return lw + weightStepKg
    }

    // MARK: Units / formatting

    private func displayWeight(_ kg: Double) -> Double { imperial ? UnitFormatter.kgToPounds(kg) : kg }
    private func massText(_ kg: Double) -> String { massString(kg, units: units) }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - The set table drawer (the «cajón»)

/// The full, editable set table, presented as a detented `.sheet` (the «cajón»). Tap a row to focus it in
/// the Foco; «Add set» / «Skip set» mutate the plan with buttons (not only a swipe — accessible). At very
/// large Dynamic Type the rows reflow from a grid to stacked blocks so nothing clips (AX5).
private struct SetTableDrawer: View {
    @ObservedObject var session: StrengthSessionModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    var units: UnitSystem
    var theme: InstrumentoTheme = .base

    private var reflow: Bool { typeSize >= .accessibility3 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sets").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        Text(session.current?.name ?? "").font(StrandFont.headline).foregroundStyle(theme.ink)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        HStack(spacing: 4) {
                            Text("Close").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.inkTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Close the set table"))
                }

                if let run = session.current {
                    table(run)
                    HStack(spacing: 10) {
                        drawerButton("Add set", "plus") { session.addSet() }
                        drawerButton("Skip set", "forward.end") { session.skipCurrentSet() }
                    }
                    Text("Tap a set to edit its weight or reps in the Focus.")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, NoopMetrics.screenPadding)
        }
        .background(theme.paper.ignoresSafeArea())
    }

    private func table(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(run.sets.enumerated()), id: \.element.id) { idx, set in
                rowButton(run: run, index: idx, set: set)
                if idx != run.sets.count - 1 { Divider().overlay(theme.hairline) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func rowButton(run: StrengthSessionModel.ExerciseRun, index: Int,
                           set: StrengthSessionModel.WorkingSet) -> some View {
        let focused = index == run.currentSet
        return Button { session.select(exerciseIndex: session.currentIndex, setIndex: index) } label: {
            Group {
                if reflow {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { setBadge(index: index, set: set, focused: focused); Spacer(); statusIcon(set) }
                        Text("\(massText(set.weightKg)) · \(set.reps) reps")
                            .font(StrandFont.body).foregroundStyle(set.done ? theme.inkSecondary : theme.ink)
                    }
                } else {
                    HStack(spacing: 8) {
                        setBadge(index: index, set: set, focused: focused)
                        Text(massText(set.weightKg)).font(StrandFont.body).monospacedDigit()
                            .foregroundStyle(set.done ? theme.inkSecondary : theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(set.reps)").font(StrandFont.body).monospacedDigit()
                            .foregroundStyle(set.done ? theme.inkSecondary : theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        statusIcon(set)
                    }
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Set \(index + 1), \(massText(set.weightKg)) by \(set.reps) reps, \(set.done ? "done" : "pending")"))
        .accessibilityHint(Text("Tap to edit"))
        .accessibilityAddTraits(focused ? .isSelected : [])
    }

    private func setBadge(index: Int, set: StrengthSessionModel.WorkingSet, focused: Bool) -> some View {
        Text("\(index + 1)").font(StrandFont.caption).monospacedDigit()
            .foregroundStyle(focused && !set.done ? theme.paper : theme.inkSecondary)
            .frame(width: 24, height: 24)
            .background(focused && !set.done ? theme.dataStrain : theme.paper,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(focused && !set.done ? Color.clear : theme.hairline, lineWidth: 1))
    }

    @ViewBuilder private func statusIcon(_ set: StrengthSessionModel.WorkingSet) -> some View {
        Image(systemName: set.done ? "checkmark" : "circle")
            .font(.system(size: set.done ? 16 : 13, weight: .semibold))
            .foregroundStyle(set.done ? theme.dataRecovery : theme.inkTertiary)
    }

    private func drawerButton(_ title: LocalizedStringKey, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func massText(_ kg: Double) -> String { massString(kg, units: units) }
}
#endif
