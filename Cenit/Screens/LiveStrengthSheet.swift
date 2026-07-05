#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics
import WhoopProtocol
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

/// The post-session receipt (FER-409): everything `summaryPhase` renders, computed once at finish in
/// `AppModel`. A plain value type — no live recompute. `strain`/`costBand` stay nil until a session
/// carries strap HR (FER-399); the view omits those blocks rather than inventing a zero.
struct StrengthSummary: Equatable {
    var routineName: String
    var durationS: Int
    var volumeKg: Double
    var setCount: Int
    var strain: Double?
    /// Average HR captured this session (≥2 samples), shown when the session was too short for an
    /// effort score (`strain == nil`) so the receipt proves HR was recorded instead of claiming none (FER-498).
    var avgHr: Int?
    var costBand: SessionRecoveryCost.Band?
    /// Tomorrow's projected recovery (0–100, rounded) given today's session cost — `nil` when there
    /// isn't ~2 weeks of recovery base (then the projection line is hidden). (FER-442)
    var costTomorrowPct: Int?
    /// Energy spent this session (kcal) and where it came from (FER-715): `.bandCalculated` (Keytel over
    /// strap HR) or `.estimated` (MET fallback). `nil` only for a legacy session with no persisted energy.
    var energyKcal: Double?
    var energySource: EnergySource?
    var prs: [PR]
    var muscles: [String]
    var isFirstTime: Bool

    /// One new record set this session (already filtered to those that strictly beat a prior PR).
    struct PR: Equatable, Identifiable {
        var id: String { "\(exercise):\(metric.rawValue)" }
        let exercise: String
        let metric: PRMetric
        let valueKg: Double?
        let reps: Int?
    }
}

/// A guided strength session in progress. A reference type owned by `AppModel` and observed directly by
/// the sheet, so the many small edits (steppers, table edits, rest ticks) don't republish all of AppModel.
@MainActor
final class StrengthSessionModel: ObservableObject {
    /// One logged/planned set within an exercise. Which fields matter depends on the exercise's
    /// `ExerciseType`: weight+reps / reps(+optional lastre) / time / distance(+time). Weight is stored
    /// in kilograms, time in seconds, distance in meters (display converts). Unused fields stay nil/0.
    struct WorkingSet: Identifiable, Equatable {
        let id: String
        var weightKg: Double
        var reps: Int
        /// Captured seconds for `time`/`distance` sets (nil until the stopwatch is stopped).
        var timeS: Int?
        /// Captured meters for `distance` sets.
        var distanceM: Double?
        var done: Bool
        var doneTs: Int?
        /// This set's own rest override (FER-715); `nil` = inherit the exercise's rest. Seeded from the
        /// planned `RoutineSet.rest`; `computeRestTarget`/`startRest` resolve it with an exercise fallback.
        var rest: RestConfig?
    }

    /// One exercise's run: its plan, the editable sets, which set the Foco is on, and whether it was skipped.
    struct ExerciseRun: Identifiable, Equatable {
        let id: String            // the RoutineExercise id (stable within the routine)
        let exerciseId: String
        let name: String
        let type: ExerciseType
        /// The rest fields are editable mid-session (FER-540): the chip → `RestEditor` writes them, and
        /// the next rest reads the new value. They start from the routine's `RoutineExercise`.
        var restSeconds: Int
        /// How the rest is timed (FER-348/495): fixed countdown, or by heart-rate recovery to a target.
        var restMode: RestMode
        var hrRestReference: HRRestReference
        var hrRestValue: Double
        /// Last time's top work set, for the «la última vez» reference + the suggested bump. nil = first time.
        let lastWeightKg: Double?
        let lastReps: Int?
        /// Last time's captured time / distance, for the «ANTERIOR» cell on time / distance exercises.
        let lastTimeS: Int?
        let lastDistanceM: Double?
        var sets: [WorkingSet]
        var currentSet: Int
        var skipped: Bool

        /// This exercise's rest as the shared `RestConfig` shape (FER-715), from its four flat fields.
        var restConfig: RestConfig {
            RestConfig(mode: restMode, seconds: restSeconds,
                       hrReference: hrRestReference, hrValue: hrRestValue)
        }
        /// The rest to apply for the set at `index`: its own override, else this exercise's default.
        func effectiveRest(forSet index: Int) -> RestConfig {
            (sets.indices.contains(index) ? sets[index].rest : nil) ?? restConfig
        }
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
    /// When the current rest started — the anchor for `elapsedS` in the HR readiness rule (FER-506). Set
    /// alongside `restEndsAt`; not moved by ±15 so the floor counts from the real start.
    @Published var restStartedAt: Date?
    /// The HR «ready» target (bpm) for this rest, computed once on entry (FER-495/506). nil = use FER-348's
    /// resting+margin default (when `currentRestMode == .heartRate`).
    @Published var currentRestTarget: Int?
    /// Which number dominates this rest: a fixed countdown, or the HR «N bpm to ready» HUD.
    @Published var currentRestMode: RestMode = .fixed
    /// When the current set's stopwatch started; nil when not running. For `time`/`distance` Foco. Durable
    /// (an absolute Date), so the running clock survives closing the sheet or switching tabs.
    @Published var timerStart: Date?
    /// Non-nil once «Finish» saved the session: the post-session receipt the sheet renders as its terminal
    /// `summaryPhase` (FER-409). Computed once at finish in `AppModel`; the session stays alive until the
    /// user taps «Listo» so the summary has somewhere to live.
    @Published var summary: StrengthSummary?
    /// Strap HR captured during the session (FER-399), in memory only — fed by `AppModel.ingestHR` on the
    /// main actor. Drives avgHr/strain + the Keytel calorie estimate at finish; never persisted as a series.
    var hrSamples: [HRSample] = []
    /// Whether the receipt's 0→value count-up already played (FER-715). A plain flag (not `@Published`, so
    /// setting it never re-renders): the receipt view sets it after animating, so the numerals count up only
    /// the first time the summary appears (at save), never when the session is re-opened. Dies with the session.
    var receiptCountUpPlayed = false

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
    func bumpDistance(byMeters delta: Double) { mutateCurrentSet { $0.distanceM = max(0, ($0.distanceM ?? 0) + delta) } }

    // MARK: Stopwatch (time / distance Foco)

    /// Live elapsed seconds of the running stopwatch (0 when stopped). Driven by a `TimelineView`.
    func timerElapsed(now: Date = Date()) -> Int {
        guard let start = timerStart else { return 0 }
        return max(0, Int(now.timeIntervalSince(start)))
    }
    /// Start the current set's stopwatch.
    func startSetTimer(now: Date = Date()) { phase = .capturing; timerStart = now }
    /// Stop the stopwatch and fold its elapsed seconds onto the current set's `timeS` (accumulates, so
    /// start/stop/start keeps the total). A no-op if it wasn't running.
    func stopSetTimer(now: Date = Date()) {
        guard let start = timerStart else { return }
        let elapsed = max(0, Int(now.timeIntervalSince(start)))
        mutateCurrentSet { $0.timeS = ($0.timeS ?? 0) + elapsed }
        timerStart = nil
    }

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
        timerStart = nil
    }

    // MARK: Set actions

    /// Register the current set (mark done) and start the fixed rest. Then advance to the next pending set.
    /// A running stopwatch is captured first, so «register» on a time/distance set logs its elapsed time.
    /// `restingHR`/`maxHR` come from the sheet (the user's nightly baseline + profile HR-max) so the rest
    /// target can be resolved without the model importing CoreBluetooth/HealthKit (FER-506).
    func registerCurrentSet(now: Date = Date(), restingHR: Double? = nil, maxHR: Double? = nil) {
        guard runs.indices.contains(currentIndex) else { return }
        if timerStart != nil { stopSetTimer(now: now) }
        let i = runs[currentIndex].currentSet
        guard runs[currentIndex].sets.indices.contains(i) else { return }
        let doneTs = Int(now.timeIntervalSince1970)
        runs[currentIndex].sets[i].done = true
        runs[currentIndex].sets[i].doneTs = doneTs
        // FER-715: rest is resolved per set — the active set's own override, else the exercise's default.
        let rest = runs[currentIndex].effectiveRest(forSet: i)
        computeRestTarget(rest: rest, doneTs: doneTs, restingHR: restingHR, maxHR: maxHR)
        startRest(seconds: rest.seconds, now: now)
        advanceToNextPending()
    }

    /// Resolve the HR rest target once on entry (FER-495/506), for a set's effective `RestConfig`. The set
    /// peak is the max strap sample in the ~90 s up to `doneTs` (the just-finished set's effort).
    /// `restingMargin`/no-target with a baseline → HR mode using FER-348's default; no honest target and no
    /// baseline → degrade to the fixed timer.
    private func computeRestTarget(rest: RestConfig, doneTs: Int, restingHR: Double?, maxHR: Double?) {
        guard rest.mode == .heartRate else { currentRestMode = .fixed; currentRestTarget = nil; return }
        let peak = hrSamples.filter { $0.ts >= doneTs - 90 && $0.ts <= doneTs }.map(\.bpm).max()
        let target = RestTarget.resolve(reference: rest.hrReference.restTargetReference,
                                        value: rest.hrValue, peakHR: peak,
                                        restingHR: restingHR, maxHR: maxHR)
        if target != nil {
            currentRestMode = .heartRate; currentRestTarget = target
        } else if restingHR != nil {
            currentRestMode = .heartRate; currentRestTarget = nil   // FER-348 resting+margin default
        } else {
            currentRestMode = .fixed; currentRestTarget = nil       // no honest HR target → fixed timer
        }
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
        timerStart = nil
    }

    /// Skip the current (pending) set: drop it from the plan. A done set is left untouched.
    func skipCurrentSet() {
        guard runs.indices.contains(currentIndex) else { return }
        let i = runs[currentIndex].currentSet
        guard runs[currentIndex].sets.indices.contains(i), !runs[currentIndex].sets[i].done else { return }
        runs[currentIndex].sets.remove(at: i)
        runs[currentIndex].currentSet = min(i, max(0, runs[currentIndex].sets.count - 1))
        timerStart = nil
        advanceToNextPending()
    }

    // MARK: Inline-table edits (any set in any exercise — the Hevy-style logging surface, FER-497)

    /// Set a row's weight (kg) directly from its cell. Used by the inline table; the Foco keeps its steppers.
    func setWeight(exercise ei: Int, set si: Int, kg: Double) {
        guard runs.indices.contains(ei), runs[ei].sets.indices.contains(si) else { return }
        runs[ei].sets[si].weightKg = max(0, kg)
    }
    /// Set a row's reps directly from its cell.
    func setReps(exercise ei: Int, set si: Int, reps: Int) {
        guard runs.indices.contains(ei), runs[ei].sets.indices.contains(si) else { return }
        runs[ei].sets[si].reps = max(0, reps)
    }
    /// Toggle a row's done flag from the inline ✓ — no rest is started (the rest belongs to the Foco /
    /// FER-348). Stamps `doneTs` when marking done, clears it when un-marking.
    func toggleDone(exercise ei: Int, set si: Int, now: Date = Date()) {
        guard runs.indices.contains(ei), runs[ei].sets.indices.contains(si) else { return }
        let nowDone = !runs[ei].sets[si].done
        runs[ei].sets[si].done = nowDone
        runs[ei].sets[si].doneTs = nowDone ? Int(now.timeIntervalSince1970) : nil
    }
    /// Append a set to a specific exercise (copying its last row's load) — the inline «Agregar serie».
    func addSet(exercise ei: Int) {
        guard runs.indices.contains(ei) else { return }
        let template = runs[ei].sets.last
        runs[ei].sets.append(WorkingSet(id: UUID().uuidString,
                                        weightKg: template?.weightKg ?? 0,
                                        reps: template?.reps ?? 8, done: false))
    }
    /// Remove a set from a specific exercise (the inline swipe / accessible delete action).
    func removeSet(exercise ei: Int, set si: Int) {
        guard runs.indices.contains(ei), runs[ei].sets.indices.contains(si) else { return }
        runs[ei].sets.remove(at: si)
        if runs[ei].currentSet >= runs[ei].sets.count {
            runs[ei].currentSet = max(0, runs[ei].sets.count - 1)
        }
    }
    /// Copy «la última vez» into a row (the tap-ANTERIOR prefill). Weight×reps types fill weight+reps;
    /// distance fills the distance. Time's goal is a view concern, handled in the sheet.
    func prefillPrevious(exercise ei: Int, set si: Int) {
        guard runs.indices.contains(ei), runs[ei].sets.indices.contains(si) else { return }
        let run = runs[ei]
        if let w = run.lastWeightKg { runs[ei].sets[si].weightKg = w }
        if let r = run.lastReps { runs[ei].sets[si].reps = r }
        if let d = run.lastDistanceM { runs[ei].sets[si].distanceM = d }
    }

    // MARK: Exercise navigator (the «change exercise» bridge)

    /// Jump straight to an exercise (skips the rest). Used by the plan navigator.
    func goToExercise(_ index: Int) {
        guard runs.indices.contains(index), !runs[index].skipped else { return }
        currentIndex = index
        runs[index].currentSet = runs[index].sets.firstIndex { !$0.done } ?? 0
        phase = .capturing
        clearRest()
        timerStart = nil
    }

    /// Mark an exercise as skipped (it no longer counts / shows as current). Advances off it if it was current.
    func skipExercise(_ index: Int) {
        guard runs.indices.contains(index) else { return }
        runs[index].skipped = true
        if index == currentIndex { phase = .capturing; clearRest(); timerStart = nil; advanceToNextPending(fromStart: true) }
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
        guard seconds > 0 else { phase = .capturing; clearRest(); return }
        restEndsAt = now.addingTimeInterval(TimeInterval(seconds))
        restStartedAt = now
        phase = .resting
    }
    func extendRest(byseconds delta: Int, now: Date = Date()) {
        guard let end = restEndsAt else { return }
        restEndsAt = max(now, end.addingTimeInterval(TimeInterval(delta)))   // moves the ceiling, not the floor
    }
    func skipRest() { phase = .capturing; clearRest() }

    /// Edit a run's rest configuration mid-session at EXERCISE scope (FER-540, generalized in FER-715).
    /// Applies to that exercise's *remaining* rests (the next `startRest` reads `restSeconds`;
    /// `computeRestTarget` reads the mode/reference). Clears every set's per-set override on that run so
    /// they all fall back to this new exercise default — otherwise a set materialized by the v26 migration
    /// would shadow the edit. Does not retime a rest already counting down. Persisting to the backing
    /// routine is the view's job (it owns the repo).
    func updateRest(exercise ei: Int, mode: RestMode, seconds: Int,
                    reference: HRRestReference, value: Double) {
        guard runs.indices.contains(ei) else { return }
        runs[ei].restMode = mode
        runs[ei].restSeconds = seconds
        runs[ei].hrRestReference = reference
        runs[ei].hrRestValue = value
        for si in runs[ei].sets.indices { runs[ei].sets[si].rest = nil }
    }

    /// Edit one set's rest override mid-session at SET scope (FER-715). `nil` clears the override so the
    /// set inherits the exercise. Only touches that set — siblings and the exercise default are untouched.
    func updateRest(exercise ei: Int, set si: Int, rest: RestConfig?) {
        guard runs.indices.contains(ei), runs[ei].sets.indices.contains(si) else { return }
        runs[ei].sets[si].rest = rest
    }

    /// Clear all rest state (the fixed countdown + the HR target), so a stale HR target never bleeds into
    /// the next rest or a non-resting phase.
    private func clearRest() {
        restEndsAt = nil; restStartedAt = nil; currentRestTarget = nil; currentRestMode = .fixed
    }

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

    /// Build the `StrengthSession` + its done `SetEntry` rows for saving (work sets only). Each set
    /// persists only the fields its exercise type measures, so a time/distance set never carries the
    /// model's placeholder reps and the weight×reps path stays exactly as it was.
    func buildForSave(deviceId: String?, endTs: Int) -> (StrengthSession, [SetEntry]) {
        let session = StrengthSession(id: id, routineId: routineId, startTs: startTs,
                                      endTs: endTs, deviceId: deviceId)
        var entries: [SetEntry] = []
        var position = 0
        for run in runs where !run.skipped {
            for set in run.sets where set.done {
                let f = SetCapture.fields(type: run.type, weightKg: set.weightKg, reps: set.reps,
                                          timeS: set.timeS, distanceM: set.distanceM)
                entries.append(SetEntry(id: set.id, sessionId: id, exerciseId: run.exerciseId,
                                        position: position, kind: .work,
                                        weightKg: f.weightKg, reps: f.reps, timeS: f.timeS, distanceM: f.distanceM,
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
            let type = slot.exercise?.type ?? .weightReps
            let usesReps = type == .weightReps || type == .bodyweight
            let last = slot.lastSets.first
            let lastWeight = last?.weightKg
            let lastReps = last?.reps
            // Seed one working set per planned set (FER-492): each carries its own reps/weight, with
            // «la última vez» as the fallback. `plannedSets` normalizes a legacy/template slot (no sets)
            // to the single target* fanned out, so both paths share one mapping. Reps only seed the
            // rep-based types; time/distance capture their datum live, so 0 there.
            let sets: [WorkingSet] = slot.re.plannedSets.filter { $0.kind == .work }.map { p in
                let weight = p.weightKg ?? lastWeight ?? 0
                let reps = usesReps ? (p.reps ?? lastReps ?? 8) : 0
                // FER-715: carry the set's own rest override (nil = inherit the exercise at rest time).
                return WorkingSet(id: UUID().uuidString, weightKg: weight, reps: reps, done: false, rest: p.rest)
            }
            return ExerciseRun(id: slot.re.id, exerciseId: slot.re.exerciseId,
                               name: slot.exercise.map(StrengthDisplay.name) ?? String(localized: "Exercise"),
                               type: type,
                               restSeconds: slot.re.restSeconds,
                               restMode: slot.re.restMode,
                               hrRestReference: slot.re.hrRestReference,
                               hrRestValue: slot.re.hrRestValue,
                               lastWeightKg: lastWeight, lastReps: lastReps,
                               lastTimeS: last?.timeS.map { Int($0) }, lastDistanceM: last?.distanceM,
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
    @EnvironmentObject private var tabRouter: TabRouter
    @ObservedObject var session: StrengthSessionModel
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    var theme: InstrumentoTheme = .base

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    /// Whether the optional «Foco» (big-button mode) sheet is up — opened by tapping a set's number badge,
    /// or a time/distance row (which captures with the stopwatch). FER-497.
    @State private var showFoco = false
    /// Per-exercise time goal (seconds) for the `time` Foco — a display target, default 30s.
    @State private var goals: [String: Int] = [:]
    /// The inline editing focus + a per-cell text buffer, so an empty / unparseable entry keeps the
    /// previous value instead of falling to zero (the buffer is dropped on blur, reformatting the datum).
    @FocusState private var focusedCell: CellRef?
    @State private var cellBuffers: [CellRef: String] = [:]
    /// The exercise whose detail sheet is open — set by tapping an exercise's name (FER-538). nil = closed.
    /// Resolving the full `Exercise` (catalog + custom) is deferred to the tap so the session model stays lean.
    @State private var detailExercise: Exercise?
    /// The exercise whose rest editor is open — set by tapping its rest chip (FER-540). nil = closed.
    @State private var restEdit: RestEdit?

    /// Identifies which exercise's rest is being edited; the editor sheet seeds itself from `runs[id]`.
    struct RestEdit: Identifiable { let id: Int }

    /// Identifies an editable inline cell: a weight or reps field at (exerciseIndex, setIndex).
    enum CellRef: Hashable { case weight(Int, Int), reps(Int, Int) }

    /// The user's resting-HR baseline for the HR rest target (FER-506): the most recent trustworthy nightly
    /// RHR. nil → the rest falls back to the fixed timer (peakDrop/fixedBpm still work via an explicit target).
    private var restingBaseline: Double? { model.repo.days.compactMap(\.restingHr).last.map(Double.init) }
    /// Profile HR-max (Tanaka if no override) — the Karvonen ceiling.
    private var profileMaxHR: Double { Double(model.profile.hrMax) }

    private var units: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var imperial: Bool { units == .imperial }
    /// Plate step: 2.5 kg metric, 5 lb imperial — stored as kg.
    private var weightStepKg: Double { imperial ? 5 * Self.kgPerPound : 2.5 }
    static let kgPerPound = 0.45359237
    static let metersPerMile = 1609.344
    /// Distance step: 0.1 km metric, 0.1 mi imperial — stored as meters.
    private var distanceStepM: Double { imperial ? Self.metersPerMile * 0.1 : 100 }
    /// At large accessibility sizes the cardio two-up reflows to a single column so nothing clips.
    private var reflow: Bool { typeSize >= .accessibility1 }

    var body: some View {
        Group {
            if let summary = session.summary {
                ScrollView {
                    VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                        summaryPhase(summary)
                    }
                    .padding(.horizontal, NoopMetrics.screenPadding)
                    .padding(.top, 18)
                    .padding(.bottom, NoopMetrics.screenPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                inlineSession
            }
        }
        .background(theme.paper.ignoresSafeArea())
        .instrumentoTheme(theme)
        .sheet(isPresented: $showFoco) {
            focoSheet
                .environmentObject(model)
                .instrumentoTheme(theme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
                .preferredColorScheme(.light)
        }
        .sheet(item: $detailExercise) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { detailExercise = nil }.foregroundStyle(theme.ink)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
            }
            .instrumentoTheme(theme).environmentObject(model.repo).preferredColorScheme(.light)
        }
        .sheet(item: $restEdit) { edit in
            if session.runs.indices.contains(edit.id) {
                let run = session.runs[edit.id]
                NavigationStack {
                    RestEditorSheet(mode: run.restMode, seconds: run.restSeconds,
                                    reference: run.hrRestReference, value: run.hrRestValue,
                                    persistsToRoutine: session.routineId != nil) { mode, seconds, ref, value in
                        commitRest(ei: edit.id, mode: mode, seconds: seconds, reference: ref, value: value)
                    }
                    .navigationTitle(Text(run.name))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { restEdit = nil }.foregroundStyle(theme.inkSecondary)
                    } }
                    .toolbarBackground(theme.paper, for: .navigationBar)
                }
                .instrumentoTheme(theme).preferredColorScheme(.light)
                .presentationDetents([.medium])
                .presentationBackground(theme.paper)
            }
        }
        .alert("Finish workout?", isPresented: $confirmFinish) {
            Button("Finish", role: .destructive) { model.endStrengthSession(save: true) }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text(session.doneCount == 0
                 ? "No sets logged yet — finishing will discard this workout."
                 : (session.pendingCount > 0
                    ? "\(session.pendingCount) sets aren't logged yet. Finish anyway and save the ones you did?"
                    : "Save this workout?"))
        }
        .alert("Discard workout?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { model.endStrengthSession(save: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything you logged in this session will be deleted. This can't be undone.")
        }
    }

    // MARK: Inline session (the default view — the Hevy-style logging table, FER-497)

    private var inlineSession: some View {
        // A flat List (not ScrollView) so each set row gets a real swipe-to-delete; styled down to the
        // warm-paper language — no native separators / background, our own hairlines. FER-497.
        List {
            ForEach(Array(session.runs.enumerated()), id: \.element.id) { ei, run in
                if !run.skipped {
                    exerciseHeader(run, ei: ei, first: ei == firstActiveIndex)
                        .plainRow()
                    ForEach(Array(run.sets.enumerated()), id: \.element.id) { si, set in
                        setRow(ei: ei, si: si, run: run, set: set, last: si == run.sets.count - 1)
                            .plainRow()
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation(.snappy) { session.removeSet(exercise: ei, set: si) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    addSetButton(ei).plainRow(top: 4)
                }
            }
            if session.isComplete, session.doneCount > 0 { completeFooter.plainRow(top: NoopMetrics.sectionGap) }
            discardFooter.plainRow(top: NoopMetrics.gap, bottom: NoopMetrics.screenPadding)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.paper)
        .environment(\.defaultMinListRowHeight, 1)
        .safeAreaInset(edge: .top, spacing: 0) { sessionHeader }
        .onChange(of: focusedCell) { _, newValue in
            // Drop every stale buffer on blur / focus move (each cell reformats from its datum) and make
            // the focused row the «active» one.
            cellBuffers = cellBuffers.filter { $0.key == newValue }
            if let f = newValue { let (ei, si) = Self.indices(f); session.select(exerciseIndex: ei, setIndex: si) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Next") { focusNextCell() }
                Spacer()
                Button("Done") { focusedCell = nil }
            }
        }
    }

    /// The first non-skipped exercise's index — its header skips the inter-exercise top gap.
    private var firstActiveIndex: Int { session.runs.firstIndex { !$0.skipped } ?? 0 }

    private static func indices(_ ref: CellRef) -> (Int, Int) {
        switch ref { case let .weight(e, s): return (e, s); case let .reps(e, s): return (e, s) }
    }

    // MARK: Session header (title + Finish + live counters)

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.routineName).font(StrandFont.title2).foregroundStyle(theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Button { finishTapped() } label: {
                    Text("Finish").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Finish workout"))
            }
            // The autoregulation line that «Rutina de hoy» used to carry (F6): now that the session starts
            // in one tap, the «push / hold / ease» implication of today's recovery rides here instead of a
            // duplicated band. Quiet, one line, hidden while calibrating. The cited rule is `TrainingRegulation`.
            if let rec = recovery {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle().fill(theme.dataRecovery).frame(width: 7, height: 7)
                    Text(recoveryLine(rec)).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            sessionCounters
        }
        .padding(.horizontal, NoopMetrics.screenPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(theme.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    /// Duración · Volumen · Series — plain counters in ink (no color: they're not verdicts). The session
    /// clock ticks live; volume is the sum of done weight×reps; series is the done count.
    private var sessionCounters: some View {
        let cells = Group {
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                counterCell("Duration", Self.clock(max(0, Int(ctx.date.timeIntervalSince1970) - session.startTs)))
            }
            counterCell("Volume", massText(sessionVolumeKg))
            counterCell("Sets", "\(session.doneCount)")
            // Live HR from the strap, shown for EVERY exercise (not just cardio) so you can see the
            // session is actually reading your pulse — "—" until a fresh sample lands (FER-498).
            counterCell("HR", model.bpm.map { "\($0)" } ?? "—")
        }
        return Group {
            if reflow {
                VStack(alignment: .leading, spacing: 8) { cells }
            } else {
                HStack(alignment: .top, spacing: 22) { cells; Spacer(minLength: 0) }
            }
        }
    }

    private func counterCell(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(value).font(StrandFont.number(19, weight: .regular)).monospacedDigit().foregroundStyle(theme.ink)
        }
        .accessibilityElement(children: .combine)
    }

    /// Done weight×reps volume across non-skipped exercises (bodyweight adds lastre×reps; time/distance 0).
    private var sessionVolumeKg: Double {
        session.runs.filter { !$0.skipped }.reduce(0.0) { acc, run in
            guard run.type == .weightReps || run.type == .bodyweight else { return acc }
            return acc + run.sets.filter(\.done).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
        }
    }

    /// Today's recovery score (nil while calibrating) — drives the header's autoregulation line (F2/F6).
    private var recovery: Double? { model.repo.today?.recovery }

    /// The compact «push / hold / ease» implication of today's recovery, same copy as the landing hero
    /// (cited rule: `TrainingRegulation`, StrandAnalytics). Reused strings — no new catalog keys.
    private func recoveryLine(_ rec: Double) -> String {
        switch TrainingRegulation.suggest(recovery: rec)?.reason {
        case .recoveryHigh: return String(localized: "Recovery high for you · you can take on your full plan.")
        case .recoveryLow:  return String(localized: "Recovery low for you · maybe ease the volume today.")
        default:            return String(localized: "Recovery in your range · train at your usual load.")
        }
    }

    // MARK: Exercise header + inline rows

    /// One exercise's header: a type overline (for non-weight×reps), the name, and the column header.
    /// Grouped by whitespace + hairlines — a registration sheet, not a grid.
    private func exerciseHeader(_ run: StrengthSessionModel.ExerciseRun, ei: Int, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            VStack(alignment: .leading, spacing: 2) {
                if run.type != .weightReps {
                    Text(typeWord(run.type)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        .accessibilityHidden(true)
                }
                // Tap the name → the exercise's Detail (how-to, trend, records) as a sheet (FER-538).
                Button { openDetail(run) } label: {
                    HStack(spacing: 8) {
                        Text(run.name).font(StrandFont.headline).foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(run.name))
                .accessibilityHint(Text("View exercise detail"))
            }
            restChip(run, ei: ei)
            if !reflow { columnHeader(run.type) }
        }
        .padding(.top, first ? NoopMetrics.gap : NoopMetrics.sectionGap)
    }

    /// A quiet, tappable chip showing this exercise's rest — tap to edit it mid-session (FER-540).
    private func restChip(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        Button { openRestEditor(ei: ei) } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
                Text(restChipLabel(run)).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Edit rest"))
        .accessibilityValue(Text(restChipLabel(run)))
    }

    /// Mode-aware chip text: the fixed duration, or «by HR» when the rest is heart-rate driven.
    private func restChipLabel(_ run: StrengthSessionModel.ExerciseRun) -> String {
        run.restMode == .heartRate ? String(localized: "Rest · by HR") : restChipText(run.restSeconds)
    }

    /// Resolve the full `Exercise` for a session run (override > custom > catalog, FER-541) and open its
    /// Detail sheet. Dismissing it leaves the session untouched — the session lives in `AppModel`.
    private func openDetail(_ run: StrengthSessionModel.ExerciseRun) {
        Task {
            if let ex = await model.repo.resolvedExercise(run.exerciseId) {
                await MainActor.run { detailExercise = ex }
            }
        }
    }

    /// Open the rest editor for an exercise (FER-540).
    private func openRestEditor(ei: Int) {
        guard session.runs.indices.contains(ei) else { return }
        restEdit = RestEdit(id: ei)
    }

    /// Apply an edited rest to the session (remaining rests of that exercise) and, when the session is
    /// backed by a saved routine, persist it so next time the routine remembers it (FER-540).
    private func commitRest(ei: Int, mode: RestMode, seconds: Int,
                            reference: HRRestReference, value: Double) {
        session.updateRest(exercise: ei, mode: mode, seconds: seconds, reference: reference, value: value)
        guard session.runs.indices.contains(ei) else { return }
        persistRestToRoutine(session.runs[ei])
    }

    /// Persist the run's edited rest to its backing `RoutineExercise` (matched by id) via a pinpoint
    /// repo update — leaves the routine's other exercises and per-set rows untouched. No-op for a
    /// freestyle session (no routine to write to).
    private func persistRestToRoutine(_ run: StrengthSessionModel.ExerciseRun) {
        guard let routineId = session.routineId else { return }
        Task {
            await model.repo.updateRoutineExerciseRest(
                routineExerciseId: run.id, routineId: routineId,
                mode: run.restMode, seconds: run.restSeconds,
                reference: run.hrRestReference, value: run.hrRestValue)
        }
    }

    /// The quiet column header (overline). Hidden at accessibility sizes — each reflowed cell self-labels.
    private func columnHeader(_ type: ExerciseType) -> some View {
        let titles = columnTitles(type)
        return HStack(spacing: 8) {
            Text("SET").instrumentoOverline().foregroundStyle(theme.inkTertiary).frame(width: 44, alignment: .center)
            Text("PREVIOUS").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(titles.indices, id: \.self) { i in
                Text(titles[i]).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .frame(width: cellWidth(type), alignment: .center)
            }
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    private func columnTitles(_ type: ExerciseType) -> [LocalizedStringKey] {
        switch type {
        case .weightReps: return [massUnitTitle, "REPS"]
        case .bodyweight: return ["+LOAD", "REPS"]
        case .time:       return ["TIME"]
        case .distance:   return [imperial ? "MI" : "KM", "TIME"]
        }
    }
    private var massUnitTitle: LocalizedStringKey { imperial ? "LB" : "KG" }
    private func cellWidth(_ type: ExerciseType) -> CGFloat {
        switch type {
        case .weightReps: return 56
        case .bodyweight: return 60
        case .time:       return 70
        case .distance:   return 56
        }
    }

    // MARK: A single set row

    @ViewBuilder private func setRow(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                                     set: StrengthSessionModel.WorkingSet, last: Bool) -> some View {
        let active = ei == session.currentIndex && si == run.currentSet && !set.done && session.summary == nil
        Group {
            if reflow { reflowRow(ei: ei, si: si, run: run, set: set) }
            else { gridRow(ei: ei, si: si, run: run, set: set) }
        }
        .padding(.vertical, reflow ? 8 : 2)
        .padding(.horizontal, active ? 6 : 0)
        .background(active ? theme.surface : .clear,
                    in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(theme.hairline).frame(height: 1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            Button("Delete set") { withAnimation(.snappy) { session.removeSet(exercise: ei, set: si) } }
        }
    }

    private func gridRow(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                         set: StrengthSessionModel.WorkingSet) -> some View {
        HStack(spacing: 8) {
            badge(ei: ei, si: si, number: si + 1)
            previousCell(ei: ei, si: si, run: run)
                .frame(maxWidth: .infinity, alignment: .leading)
            dataCells(ei: ei, si: si, run: run, set: set)
            checkButton(ei: ei, si: si, set: set)
        }
    }

    private func reflowRow(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                           set: StrengthSessionModel.WorkingSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                badge(ei: ei, si: si, number: si + 1)
                Spacer()
                checkButton(ei: ei, si: si, set: set)
            }
            previousCell(ei: ei, si: si, run: run)
            HStack(spacing: 16) { dataCells(ei: ei, si: si, run: run, set: set) }
        }
    }

    /// The set-number badge — tap to open the optional Foco focused on this row. Always in the effort hue
    /// inside a ring, as the approved render (FER-499).
    private func badge(ei: Int, si: Int, number: Int) -> some View {
        Button { openFoco(ei: ei, si: si) } label: {
            Text("\(number)").font(StrandFont.caption).monospacedDigit()
                .foregroundStyle(theme.dataStrain)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(theme.dataStrain, lineWidth: 1.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: reflow ? nil : 44, alignment: .center)
        .accessibilityLabel(Text("Set \(number)"))
        .accessibilityHint(Text("Opens the big-button mode"))
    }

    /// «ANTERIOR» — last time's value; tap to copy it into this row. «—» (and inert) when there's none.
    @ViewBuilder private func previousCell(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun) -> some View {
        if let text = previousText(run) {
            Button { prefillTapped(ei: ei, si: si, run: run) } label: {
                Text(reflow ? "Previous: \(text)" : text)
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Previous, \(text)"))
            .accessibilityHint(Text("Copies it to this set"))
        } else {
            Text("—").font(StrandFont.caption).foregroundStyle(theme.inkDim)
                .accessibilityLabel(Text("No previous record"))
        }
    }

    /// The editable / captured data columns, by exercise type.
    @ViewBuilder private func dataCells(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                                        set: StrengthSessionModel.WorkingSet) -> some View {
        switch run.type {
        case .weightReps:
            numberCell(.weight(ei, si), value: displayWeight(set.weightKg), isInt: false, done: set.done, type: run.type)
            numberCell(.reps(ei, si), value: Double(set.reps), isInt: true, done: set.done, type: run.type)
        case .bodyweight:
            HStack(spacing: 1) {
                Text("+").font(StrandFont.body).foregroundStyle(set.done ? theme.inkSecondary : theme.inkTertiary)
                numberCell(.weight(ei, si), value: displayWeight(set.weightKg), isInt: false, done: set.done, type: run.type, width: run.type == .bodyweight ? 48 : 56)
            }
            .frame(width: reflow ? nil : cellWidth(run.type), alignment: reflow ? .leading : .center)
            numberCell(.reps(ei, si), value: Double(set.reps), isInt: true, done: set.done, type: run.type)
        case .time:
            capturedCell(ei: ei, si: si, run: run,
                         text: (set.timeS ?? 0) > 0 ? Self.clock(set.timeS ?? 0) : nil)
        case .distance:
            capturedCell(ei: ei, si: si, run: run,
                         text: (set.distanceM ?? 0) > 0 ? distanceText(set.distanceM ?? 0) : nil)
            capturedCell(ei: ei, si: si, run: run,
                         text: (set.timeS ?? 0) > 0 ? Self.clock(set.timeS ?? 0) : nil)
        }
    }

    /// An editable numeric cell — a form field on paper (a faint underline you fill «with pen»). An empty or
    /// unparseable entry keeps the previous value (the buffer is dropped on blur). FER-497.
    private func numberCell(_ ref: CellRef, value: Double, isInt: Bool, done: Bool,
                            type: ExerciseType, width: CGFloat? = nil) -> some View {
        let text = Binding<String>(
            get: { cellBuffers[ref] ?? formatCell(value, isInt: isInt) },
            set: { raw in
                cellBuffers[ref] = raw
                guard let v = Self.parseDouble(raw) else { return }   // empty / invalid → keep previous
                switch ref {
                case let .weight(ei, si): session.setWeight(exercise: ei, set: si, kg: storedKg(fromDisplay: v))
                case let .reps(ei, si):   session.setReps(exercise: ei, set: si, reps: Int(v.rounded()))
                }
            })
        return TextField("", text: text)
            .keyboardType(isInt ? .numberPad : .decimalPad)
            .multilineTextAlignment(.center)
            .font(StrandFont.number(16, weight: .regular)).monospacedDigit()
            .foregroundStyle(done ? theme.inkSecondary : theme.ink)
            .focused($focusedCell, equals: ref)
            .frame(width: width ?? (reflow ? 64 : cellWidth(type)), height: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(focusedCell == ref ? theme.ink : theme.hairlineStrong)
                    .frame(height: focusedCell == ref ? 2 : 1)
                    .padding(.bottom, 6)
            }
            .accessibilityLabel(Text(cellLabel(ref)))
    }

    /// A captured (non-typed) time / distance cell — tap to open the stopwatch Foco. Shows «—» until set.
    private func capturedCell(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun, text: String?) -> some View {
        Button { openFoco(ei: ei, si: si) } label: {
            Group {
                if let text {
                    Text(text).font(StrandFont.number(16, weight: .regular)).monospacedDigit().foregroundStyle(theme.ink)
                } else {
                    Image(systemName: "play.circle").font(.system(size: 18)).foregroundStyle(theme.inkTertiary)
                }
            }
            .frame(width: reflow ? nil : cellWidth(run.type))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(text ?? String(localized: "Not recorded")))
        .accessibilityHint(Text("Opens the timer"))
    }

    /// The done toggle (the datum's color — green when logged). 44pt touch target.
    private func checkButton(ei: Int, si: Int, set: StrengthSessionModel.WorkingSet) -> some View {
        Button { withAnimation(.snappy) { session.toggleDone(exercise: ei, set: si) } } label: {
            Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(set.done ? theme.dataRecovery : theme.inkDim)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: reflow ? nil : 44)
        .accessibilityLabel(Text(set.done ? "Mark set \(si + 1) as not done" : "Mark set \(si + 1) as done"))
    }

    private func addSetButton(_ ei: Int) -> some View {
        Button { withAnimation(.snappy) { session.addSet(exercise: ei) } } label: {
            Label("Add set", systemImage: "plus")
                .font(StrandFont.subhead).foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(theme.paper, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    // MARK: Complete + discard footers

    private var completeFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(theme.hairline).frame(height: 1)
            completePhase
        }
    }

    private var discardFooter: some View {
        Button(role: .destructive) { confirmDiscard = true } label: {
            Text("Discard workout").font(StrandFont.subhead).foregroundStyle(theme.critical)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Discard workout"))
    }

    // MARK: The optional Foco sheet (big-button mode + the fixed rest)

    private var focoSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                HStack {
                    Text("Focus").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Button { showFoco = false } label: {
                        HStack(spacing: 4) {
                            Text("Close").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.inkTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Close"))
                }
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
    }

    // MARK: Inline helpers (formatting / focus / actions)

    private func openFoco(ei: Int, si: Int) {
        session.select(exerciseIndex: ei, setIndex: si)
        showFoco = true
    }

    /// Tap-ANTERIOR: copy last time into this row. Time exercises set the goal; the rest prefill the datum.
    private func prefillTapped(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun) {
        if run.type == .time, let last = run.lastTimeS { goals[run.id] = last }
        else { session.prefillPrevious(exercise: ei, set: si) }
    }

    private func previousText(_ run: StrengthSessionModel.ExerciseRun) -> String? {
        switch run.type {
        case .weightReps:
            guard let w = run.lastWeightKg, let r = run.lastReps else { return nil }
            return "\(massText(w)) × \(r)"
        case .bodyweight:
            guard let r = run.lastReps else { return nil }
            let w = run.lastWeightKg ?? 0
            return "+\(plateNumber(displayWeight(w))) × \(r)"
        case .time:
            guard let t = run.lastTimeS else { return nil }
            return Self.clock(t)
        case .distance:
            guard let d = run.lastDistanceM else { return nil }
            return "\(distanceText(d)) · \(Self.clock(run.lastTimeS ?? 0))"
        }
    }

    private func formatCell(_ value: Double, isInt: Bool) -> String {
        isInt ? "\(Int(value.rounded()))" : plateNumber(value)
    }
    private static func parseDouble(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Double(t)
    }
    private func storedKg(fromDisplay v: Double) -> Double { imperial ? v * Self.kgPerPound : v }

    private func cellLabel(_ ref: CellRef) -> LocalizedStringKey {
        switch ref {
        case let .weight(_, si): return "Weight, set \(si + 1)"
        case let .reps(_, si):   return "Reps, set \(si + 1)"
        }
    }

    /// The editable cells in row-major order, for the keyboard «Next» button.
    private var editableCells: [CellRef] {
        var out: [CellRef] = []
        for (ei, run) in session.runs.enumerated() where !run.skipped {
            guard run.type == .weightReps || run.type == .bodyweight else { continue }
            for si in run.sets.indices { out.append(.weight(ei, si)); out.append(.reps(ei, si)) }
        }
        return out
    }
    private func focusNextCell() {
        let cells = editableCells
        guard let cur = focusedCell, let idx = cells.firstIndex(of: cur) else { focusedCell = nil; return }
        focusedCell = idx + 1 < cells.count ? cells[idx + 1] : nil
    }

    private func distanceText(_ meters: Double) -> String {
        let v = imperial ? meters / Self.metersPerMile : meters / 1000
        return String(format: "%.2f %@", v, imperial ? "mi" : "km")
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
                        // The same tappable rest chip as the inline header — edit rest mid-session (FER-540).
                        restChip(run, ei: session.currentIndex)
                    }
                    if run.type == .weightReps { referenceLine(run) } else { setTypeLine(run) }
                }

                // The Foco adapts to the exercise type (FER-351): weight×reps, reps(+lastre), a
                // stopwatch with a goal, or distance/time with the strap's live HR.
                switch run.type {
                case .weightReps:
                    weightFoco(run)
                    repsRow
                    registerButton
                case .bodyweight:
                    repsFoco(run)
                    lastreRow(run)
                    registerButton
                case .time:
                    timeControls(run)
                case .distance:
                    distanceControls(run)
                }
            }
        }
    }

    /// Set counter + the measure word, for the non-weight×reps variants (which don't show «la última vez»).
    private func setTypeLine(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        HStack(spacing: 8) {
            Text(setCounterText(run)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            Spacer(minLength: 8)
            Text(typeWord(run.type)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
    }

    private func typeWord(_ t: ExerciseType) -> LocalizedStringKey {
        switch t {
        case .weightReps: return "Weight"
        case .bodyweight: return "Bodyweight"
        case .time:       return "Time"
        case .distance:   return "Distance"
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
        Button { withAnimation(.snappy) { session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR) } } label: {
            Label("Register set", systemImage: "checkmark")
                .font(StrandFont.headline).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Bodyweight Foco (reps lead; lastre optional)

    /// The dominant datum for a bodyweight exercise: the reps, in the effort hue, flanked by steppers.
    private func repsFoco(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        HStack {
            stepper(system: "minus") { session.bumpReps(-1) }
                .accessibilityLabel(Text("Decrease reps"))
            Spacer(minLength: 8)
            VStack(spacing: 0) {
                Text("\(session.currentSet?.reps ?? 0)")
                    .instrumentoHero(76).foregroundStyle(theme.dataStrain)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                Text("reps").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: 8)
            stepper(system: "plus") { session.bumpReps(1) }
                .accessibilityLabel(Text("Increase reps"))
        }
        .accessibilityElement(children: .contain)
    }

    /// Optional added load («lastre») for a bodyweight set — starts at zero (bodyweight only).
    private func lastreRow(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        let kg = session.currentSet?.weightKg ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Added weight").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                Text(kg > 0 ? "optional" : "optional · bodyweight only")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Spacer()
            HStack(spacing: 16) {
                stepper(system: "minus", size: 34) { session.bumpWeight(byKg: -weightStepKg) }
                    .accessibilityLabel(Text("Decrease added weight"))
                Text("+\(plateNumber(displayWeight(kg))) \(UnitFormatter.massUnit(units))")
                    .font(StrandFont.title2).monospacedDigit()
                    .foregroundStyle(kg > 0 ? theme.ink : theme.inkTertiary)
                stepper(system: "plus", size: 34) { session.bumpWeight(byKg: weightStepKg) }
                    .accessibilityLabel(Text("Increase added weight"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Time Foco (stopwatch with a goal; registers on stop)

    @ViewBuilder private func timeControls(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        let running = session.timerStart != nil
        if running {
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                timeReadout(elapsed: session.timerElapsed(now: ctx.date), run: run)
            }
        } else {
            timeReadout(elapsed: session.currentSet?.timeS ?? 0, run: run)
        }
        Button { withAnimation(.snappy) { running ? session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR) : session.startSetTimer() } } label: {
            Label(running ? "Stop and save" : "Start", systemImage: running ? "stop.fill" : "play.fill")
                .font(StrandFont.headline).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func timeReadout(elapsed: Int, run: StrengthSessionModel.ExerciseRun) -> some View {
        let goal = goalSeconds(run)
        let met = elapsed >= goal && elapsed > 0
        let isRunning = session.timerStart != nil
        return VStack(spacing: 8) {
            Text(Self.clock(elapsed))
                .instrumentoHero(72).monospacedDigit()
                .foregroundStyle(elapsed > 0 ? theme.dataStrain : theme.inkTertiary)
                .minimumScaleFactor(0.5).lineLimit(1)
            HStack(spacing: 14) {
                stepper(system: "minus", size: 30) { adjustGoal(run, -15) }
                    .accessibilityLabel(Text("Decrease goal"))
                Text(met ? "Goal \(Self.clock(goal)) · reached" : "Goal \(Self.clock(goal))")
                    .font(StrandFont.subhead).monospacedDigit()
                    .foregroundStyle(met ? theme.dataRecovery : theme.inkSecondary)
                stepper(system: "plus", size: 30) { adjustGoal(run, 15) }
                    .accessibilityLabel(Text("Increase goal"))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isRunning ? "Timing, \(elapsed) seconds. Goal \(goal) seconds."
                                 : "\(elapsed) seconds. Goal \(goal) seconds."))
    }

    private func goalSeconds(_ run: StrengthSessionModel.ExerciseRun) -> Int { goals[run.id] ?? 30 }
    private func adjustGoal(_ run: StrengthSessionModel.ExerciseRun, _ delta: Int) {
        goals[run.id] = max(5, goalSeconds(run) + delta)
    }

    // MARK: Distance / cardio Foco (distance + time in ink; strap HR + zone in color)

    @ViewBuilder private func distanceControls(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        let dist = session.currentSet?.distanceM ?? 0
        let running = session.timerStart != nil
        if reflow {
            VStack(spacing: 12) { distanceCard(dist); timeCard(running: running) }
        } else {
            HStack(spacing: 12) { distanceCard(dist); timeCard(running: running) }
        }
        hrZoneRow
        let captured = dist > 0 || (session.currentSet?.timeS ?? 0) > 0 || running
        Button { withAnimation(.snappy) { session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR) } } label: {
            Label("Register set", systemImage: "checkmark")
                .font(StrandFont.headline).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!captured)
        .opacity(captured ? 1 : 0.5)
    }

    private func distanceCard(_ meters: Double) -> some View {
        cardioCard {
            Text(distanceNumber(meters))
                .instrumentoHero(40).foregroundStyle(theme.ink)
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
            Text(imperial ? "mi" : "km").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            HStack(spacing: 18) {
                stepper(system: "minus", size: 34) { session.bumpDistance(byMeters: -distanceStepM) }
                    .accessibilityLabel(Text("Decrease distance"))
                stepper(system: "plus", size: 34) { session.bumpDistance(byMeters: distanceStepM) }
                    .accessibilityLabel(Text("Increase distance"))
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Distance \(distanceNumber(meters)) \(imperial ? String(localized: "miles") : String(localized: "kilometers"))"))
    }

    @ViewBuilder private func timeCard(running: Bool) -> some View {
        if running {
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                timeCardBody(elapsed: session.timerElapsed(now: ctx.date), running: true)
            }
        } else {
            timeCardBody(elapsed: session.currentSet?.timeS ?? 0, running: false)
        }
    }

    private func timeCardBody(elapsed: Int, running: Bool) -> some View {
        cardioCard {
            Text(Self.clock(elapsed))
                .instrumentoHero(40).foregroundStyle(theme.ink)
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
            Text("time").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            Button { withAnimation(.snappy) { running ? session.stopSetTimer() : session.startSetTimer() } } label: {
                Text(running ? "Stop" : "Start")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(theme.paper, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                        .strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel(Text(running ? "Stop the timer" : "Start the timer"))
        }
    }

    /// A surface card used by the cardio two-up (distance / time).
    private func cardioCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 6) { content() }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14).padding(.horizontal, 10)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
    }

    /// The strap's live HR + zone, in the zone hue. Absent (degraded) when no strap is streaming.
    @ViewBuilder private var hrZoneRow: some View {
        if let hr = model.bpm {
            let zone = hrZone(hr)
            let hue = theme.hrZoneRamp[max(0, min(theme.hrZoneRamp.count - 1, zone - 1))]
            HStack(spacing: 10) {
                Image(systemName: "heart.fill").font(.system(size: 17)).foregroundStyle(hue)
                Text("\(hr)").font(StrandFont.title2).monospacedDigit().foregroundStyle(hue)
                Text("bpm").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("Zone \(zone)").font(StrandFont.caption).foregroundStyle(hue)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(theme.paper, in: RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1))
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Heart rate \(hr) beats per minute, zone \(zone)"))
        }
    }

    /// Coarse 1–5 HR zone from %HRmax — the same thresholds as the live zone-coaching haptics.
    private func hrZone(_ hr: Int) -> Int {
        let maxHR = Double(model.profile.hrMax)
        guard maxHR > 0 else { return 1 }
        let pct = Double(hr) / maxHR
        return pct >= 0.9 ? 5 : pct >= 0.8 ? 4 : pct >= 0.7 ? 3 : pct >= 0.6 ? 2 : 1
    }

    /// Stored meters → the user's unit (km / mi), two decimals.
    private func distanceNumber(_ meters: Double) -> String {
        let v = imperial ? meters / Self.metersPerMile : meters / 1000
        return String(format: "%.2f", v)
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
            Button { finishTapped() } label: {
                Label("Finish", systemImage: "checkmark")
                    .font(StrandFont.headline).foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain).padding(.top, 4)
            // Keep the way back: tapping an exercise returns to its capture screen to edit (or add sets).
            if !session.activeExercises.isEmpty {
                planNavigator.padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Summary phase (the post-session receipt · FER-409)

    @ViewBuilder
    private func summaryPhase(_ s: StrengthSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Summary").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(s.routineName).font(StrandFont.title1).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Hero: effort (strain) when the session was long enough; else the average HR if we captured
            // any (a short session reads HR but can't score a meaningful effort, FER-498); else duration
            // when there genuinely was no HR.
            if let strain = s.strain {
                summaryHero(label: "Effort", value: Self.strainText(strain), unit: nil,
                            color: theme.dataStrain, caption: "What this session cost your body.")
            } else if let avgHr = s.avgHr {
                summaryHero(label: "Avg HR", value: "\(avgHr)", unit: "bpm",
                            color: theme.dataStrain, caption: "Heart rate recorded; too short for an effort score.")
            } else {
                summaryHero(label: "Duration", value: "\(s.durationS / 60)", unit: "min",
                            color: theme.ink, caption: "No heart rate this session.")
            }

            Divider().overlay(theme.hairline)
            summarySecondaries(s)

            if !s.prs.isEmpty {
                Divider().overlay(theme.hairline)
                summaryRecords(s.prs)
            } else if s.isFirstTime {
                Divider().overlay(theme.hairline)
                Text("First time logging these. From here on you'll see your progress.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let band = s.costBand {
                Divider().overlay(theme.hairline)
                summaryCost(band, tomorrowPct: s.costTomorrowPct)
            }

            if !s.muscles.isEmpty {
                Divider().overlay(theme.hairline)
                summaryMuscles(s.muscles)
            }

            Button { model.closeStrengthSummary() } label: {
                Text("Done")
                    .font(StrandFont.headline).foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryHero(label: LocalizedStringKey, value: String, unit: String?,
                             color: Color, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).instrumentoHero(64).foregroundStyle(color)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                if let unit { Text(unit).font(StrandFont.unit).foregroundStyle(theme.inkTertiary) }
            }
            Text(caption).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func summarySecondaries(_ s: StrengthSummary) -> some View {
        // Duration is the hero when there's no strain → don't repeat it as a secondary. At large type
        // sizes the row reflows to a column so the three numbers never clip.
        let cells = Group {
            summaryStat("Volume", massText(s.volumeKg))
            summaryStat("Sets", "\(s.setCount)")
            if s.strain != nil { summaryStat("Duration", "\(s.durationS / 60) min") }
        }
        if reflow {
            VStack(alignment: .leading, spacing: 12) { cells }
        } else {
            HStack(alignment: .top, spacing: 18) { cells; Spacer(minLength: 0) }
        }
    }

    private func summaryStat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(StrandFont.number(19, weight: .semibold)).foregroundStyle(theme.ink).monospacedDigit()
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
        }
        .frame(minWidth: reflow ? nil : 60, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func summaryRecords(_ prs: [StrengthSummary.PR]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New records").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            ForEach(prs) { pr in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Record").font(StrandFont.caption).foregroundStyle(theme.dataRecovery)
                    Text(pr.exercise).font(StrandFont.subhead).foregroundStyle(theme.ink)
                    Spacer(minLength: 8)
                    (Text(Self.prMetricLabel(pr.metric)) + Text(verbatim: " · \(prValue(pr))"))
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func summaryCost(_ band: SessionRecoveryCost.Band, tomorrowPct: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recovery cost").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(Self.bandLabel(band)).font(StrandFont.title2).foregroundStyle(bandColor(band))
            Text(Self.bandDetail(band)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Tomorrow's projection given today's cost (FER-442): the prose in ink, the datum in
            // recovery green. Hidden when there isn't ~2 weeks of base (the engine returns nil).
            if let pct = tomorrowPct {
                (Text("Tomorrow, if you rest well, you should be around ").foregroundColor(theme.inkSecondary)
                    + Text("~\(pct)%").foregroundColor(theme.dataRecovery).fontWeight(.semibold))
                    .font(StrandFont.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Estimate · you decide").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private func summaryMuscles(_ muscles: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Today's muscles").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("Tap a muscle to see when to train it again.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            ChipFlow(spacing: 7) {
                ForEach(muscles, id: \.self) { m in
                    Button { openFatigueMap() } label: {
                        Text(m).font(StrandFont.subhead).foregroundStyle(theme.ink)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous)
                                .strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens the fatigue map"))
                }
            }
        }
    }

    /// Close the summary and hand off to «Cuerpo» → fatigue map (no third sheet stacked on the session).
    private func openFatigueMap() {
        tabRouter.openFatigueMap()
        model.closeStrengthSummary()
    }

    // MARK: Summary formatting

    private static func strainText(_ v: Double) -> String { String(format: "%.1f", v) }

    private func prValue(_ pr: StrengthSummary.PR) -> String {
        switch pr.metric {
        case .maxWeight: return massText(pr.valueKg ?? 0)
        case .maxReps:   return "\(pr.reps ?? 0)"
        case .maxVolume: return "\(massText(pr.valueKg ?? 0)) × \(pr.reps ?? 0)"
        }
    }

    private static func prMetricLabel(_ m: PRMetric) -> LocalizedStringKey {
        switch m {
        case .maxWeight: return "Max weight"
        case .maxReps:   return "Most reps"
        case .maxVolume: return "Best set"
        }
    }

    private static func bandLabel(_ b: SessionRecoveryCost.Band) -> LocalizedStringKey {
        switch b { case .light: return "Light"; case .moderate: return "Moderate"; case .high: return "High" }
    }

    private static func bandDetail(_ b: SessionRecoveryCost.Band) -> LocalizedStringKey {
        switch b {
        case .light:    return "Low cardiovascular cost. Your body barely felt it."
        case .moderate: return "A session that counted. Give yourself some rest."
        case .high:     return "A demanding session. Make sleep a priority today."
        }
    }

    private func bandColor(_ b: SessionRecoveryCost.Band) -> Color {
        switch b { case .light: return theme.dataRecovery; case .moderate: return theme.dataStrain; case .high: return theme.dataHeart }
    }

    // MARK: Rest phase (fixed countdown + the «change exercise» bridge)

    private var restPhase: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            Text("Rest").instrumentoOverline().foregroundStyle(theme.inkTertiary)

            // By-HR rest (FER-348/495/506): the dominant number is «N bpm to ready → Ready», computed live
            // from the strap. Losing the signal mid-rest falls to the honest fixed clock — no invented HR.
            if session.currentRestMode == .heartRate, let started = session.restStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    let v = RestReadinessRule.evaluate(
                        currentHR: model.bpm, worn: model.live.worn, restingHR: restingBaseline,
                        elapsedS: max(0, Int(ctx.date.timeIntervalSince(started))),
                        targetHR: session.currentRestTarget)
                    Group {
                        if v.state == .noSignal { fixedRestHero(end: session.restEndsAt, now: ctx.date, hrFallback: true) }
                        else { hrRestHero(v) }
                    }
                    .sensoryFeedback(.success, trigger: v.ready && model.live.bonded)
                }
            } else if let end = session.restEndsAt {
                TimelineView(.periodic(from: end, by: 1)) { ctx in
                    fixedRestHero(end: end, now: ctx.date, hrFallback: false)
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

    /// The HR rest HUD (variant C2): «N bpm to ready» in the heart hue while resting, «Ready» in the
    /// recovery hue once your pulse settles. The bpm number is the only colored datum.
    private func hrRestHero(_ v: RestReadiness) -> some View {
        let hue = v.ready ? theme.dataRecovery : theme.dataHeart
        return VStack(alignment: .leading, spacing: 8) {
            if v.ready {
                Text("Ready").instrumentoHero(56).foregroundStyle(theme.dataRecovery)
                Text("\(String(localized: "Your pulse recovered")) · \(nextUpText)")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(v.bpmToReady ?? 0)").instrumentoHero(64).monospacedDigit().foregroundStyle(theme.dataHeart)
                    Text("bpm").font(StrandFont.headline).foregroundStyle(theme.inkSecondary)
                }
                Text("\(String(localized: "to ready")) · \(nextUpText)")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
            ECGWave(color: hue, animate: true, bpm: model.bpm).frame(height: 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(v.ready ? "Ready. \(nextUpText)"
                                 : "\(v.bpmToReady ?? 0) beats per minute to ready. \(nextUpText)"))
    }

    /// The fixed countdown hero — the normal `.fixed` rest, and the honest fallback when an HR rest loses
    /// the strap mid-set (`hrFallback`: appends the «connect your strap» hint, never invents a number).
    private func fixedRestHero(end: Date?, now: Date, hrFallback: Bool) -> some View {
        let remaining = end.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) } ?? 0
        let sub = hrFallback ? "\(nextUpText) · \(String(localized: "connect your strap for HR rest"))" : nextUpText
        return VStack(alignment: .leading, spacing: 4) {
            Text(Self.clock(remaining)).instrumentoHero(64)
                .monospacedDigit().foregroundStyle(remaining == 0 ? theme.dataRecovery : theme.ink)
            Text(sub).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(remaining == 0 ? "Rest done. \(nextUpText)"
                                 : "Resting, \(remaining) seconds left. \(nextUpText)"))
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
        return String(localized: "Up next · Set \(n) · \(upNextMeasure(run, set))")
    }

    /// The «up next» measure for the rest screen, by exercise type.
    private func upNextMeasure(_ run: StrengthSessionModel.ExerciseRun, _ set: StrengthSessionModel.WorkingSet) -> String {
        switch run.type {
        case .weightReps: return "\(massText(set.weightKg)) × \(set.reps)"
        case .bodyweight: return set.weightKg > 0 ? "\(set.reps) reps · +\(massText(set.weightKg))" : String(localized: "\(set.reps) reps")
        case .time:       return Self.clock(goalSeconds(run))
        case .distance:   return String(localized: "distance")
        }
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

/// Strips a `List` row down to the warm-paper language: one screen margin, no native background, no native
/// separator (the table draws its own hairlines). `top`/`bottom` tune the vertical rhythm per row. FER-497.
private extension View {
    func plainRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: NoopMetrics.screenPadding,
                                      bottom: bottom, trailing: NoopMetrics.screenPadding))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// Minimal flow layout: lays subviews left-to-right, wrapping to a new row when the next would overflow
/// the proposed width. Used for the summary's muscle chips (FER-409) so they wrap instead of truncating
/// at large Dynamic Type sizes.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW.isFinite ? maxW : x, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > bounds.width { x = 0; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - HR rest reference mapping (FER-506)

/// Maps the persisted domain enum (StrandTraining) onto the rest-math vocabulary (StrandAnalytics), so the
/// math package stays decoupled from the data model. 1-to-1.
extension HRRestReference {
    var restTargetReference: RestTarget.Reference {
        switch self {
        case .restingMargin:   return .restingMargin
        case .peakDrop:        return .peakDrop
        case .karvonenReserve: return .karvonenReserve
        case .fixedBpm:        return .fixedBpm
        }
    }
}
#endif
