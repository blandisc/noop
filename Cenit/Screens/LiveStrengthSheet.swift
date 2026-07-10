#if os(iOS)
import SwiftUI
import UIKit
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

// MARK: - Guided strength session (FER-347, full-screen since FER-716)
//
// The heart of the strength tracker: the guided, set-by-set execution as ONE continuous logging table
// («Flujo Entrenar v3 · 1j»). No modal «Foco» — the active row edits inline with the custom keypad, a
// time/distance row expands with a compact stopwatch, and the rest slots in as the inline 1k card.
// Finishing renders the 1l receipt in place.
//
// The session lives in `AppModel` (global) and is presented as a `fullScreenCover` at the RootTabView
// shell, so minimizing («‹») or switching tabs never loses it; the floating `SessionPill` re-opens it
// from any tab. No nested NavigationStack (FER-171). Runs fully offline and without HealthKit
// (logging strength is manual).

// MARK: - Session model (the durable, observable state owned by AppModel)

/// The post-session receipt (FER-409): everything `summaryPhase` renders, computed once at finish in
/// `AppModel`. A plain value type — no live recompute. `strain`/`costBand` stay nil until a session
/// carries strap HR (FER-399); the view omits those blocks rather than inventing a zero.
struct StrengthSummary: Equatable {
    var routineName: String
    /// When the session was saved (drives the receipt's «Sesión guardada · {fecha}» overline).
    var endTs: Int
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
    /// The previous completed session of the SAME routine (FER-716), for the «Contra tu última {rutina}»
    /// bars. `nil` when this routine has no earlier session (or the session was routine-less).
    var comparison: Comparison?
    /// One row per exercise with logged sets, in plan order — the receipt's «Por ejercicio» list.
    var exercises: [ExerciseLine]
    /// FER-742: the Apple Watch recorded the real FC/kcal and saved the workout to Health (the one-workout
    /// invariant then omitted the iPhone's estimate). Drives the receipt's watch-origin line; false = as today.
    var watchRecorded: Bool = false

    /// One new record set this session (already filtered to those that strictly beat a prior PR).
    /// `priorValueKg`/`priorReps` carry the beaten record, for the «100 → 102,5 kg» framing.
    struct PR: Equatable, Identifiable {
        var id: String { "\(exercise):\(metric.rawValue)" }
        let exercise: String
        let metric: PRMetric
        let valueKg: Double?
        let reps: Int?
        var priorValueKg: Double? = nil
        var priorReps: Int? = nil
    }

    /// The last same-routine session's aggregates the bars compare against.
    struct Comparison: Equatable {
        var prevVolumeKg: Double
        var prevSetCount: Int
        var prevDurationS: Int

        /// The volume change vs last time, as a rounded percent — single-sourced so the headline and
        /// the comparison bar never disagree. `nil` when there's no prior volume to compare against.
        func volumeDeltaPct(_ currentVolumeKg: Double) -> Int? {
            guard prevVolumeKg > 0 else { return nil }
            return Int((((currentVolumeKg - prevVolumeKg) / prevVolumeKg) * 100).rounded())
        }
    }

    /// One «Por ejercicio» row: logged sets, the session's top datum for its type, and the trend
    /// against «la última vez» (+1 up / 0 even / −1 down; nil = nothing to compare).
    struct ExerciseLine: Equatable, Identifiable {
        var id: String { name }
        let name: String
        let setCount: Int
        let topWeightKg: Double?
        let topTimeS: Int?
        let topDistanceM: Double?
        let trend: Int?
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
        /// Warm-up vs work (FER-720). Defaults to `.work` so every existing construction site is unchanged;
        /// `insertWarmup` sets `.warmup`. Persisted through to `SetEntry.kind`, so warm-ups are excluded
        /// from volume/PRs (which already filter `kind == .work`) without any other change.
        var kind: SetKind = .work
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
        /// An earned weight raise seeded into this run's cells (FER-E · 2b). nil = no proposal today.
        /// Cleared by «Volver a X» (the per-session opt-out). Not carried by the crash snapshot — after
        /// a restore the seeded weights survive; only the «por qué» affordance is gone.
        var proposedRaise: ProgressionPlanner.Raise? = nil

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
    /// Whether the session is paused (FER-823). The session clock and any running rest/stopwatch freeze;
    /// paused time is excluded from the saved duration and HR captured while paused is dropped from scoring.
    @Published var paused = false
    /// Total seconds already spent paused across all prior pauses this session. `pausedSeconds(at:)` adds
    /// the current open pause on top.
    private(set) var pausedAccumulatedS = 0
    /// When the current pause began; nil when not paused. The open pause is folded into `pausedAccumulatedS`
    /// on resume.
    private(set) var pausedAt: Date?

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

    /// Pending (not-done) sets left in the focused exercise, including the current one (FER-789). 0 when
    /// focus is parked on a done/skipped run. Drives the rest card's phase: 1 here means the upcoming set
    /// is this exercise's last, so completing it moves to a different exercise.
    var pendingInCurrentRun: Int { current.map { $0.sets.filter { !$0.done }.count } ?? 0 }

    /// The name of the next non-skipped exercise (after the current one) that still has a pending set —
    /// the rest card's «Sigue: …» line when the upcoming set is the current exercise's last (FER-789).
    var nextPendingExerciseName: String? {
        guard runs.indices.contains(currentIndex) else { return nil }
        for offset in 1...max(1, runs.count) {
            let idx = (currentIndex + offset) % max(1, runs.count)
            guard idx != currentIndex, runs.indices.contains(idx), !runs[idx].skipped else { continue }
            if runs[idx].sets.contains(where: { !$0.done }) { return runs[idx].name }
        }
        return nil
    }

    // MARK: Editing the current set

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

    // MARK: Pause / resume (FER-823)

    /// Total seconds this session has spent paused up to `now` — the accumulated closed pauses plus the
    /// current open one (if paused). Subtracted from the wall-clock span to get the active duration.
    func pausedSeconds(at now: Date = Date()) -> Int {
        pausedAccumulatedS + (pausedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0)
    }

    /// The active elapsed seconds of the session (wall-clock span minus paused time). Drives the header
    /// clock and the saved duration, so both exclude time on pause.
    func elapsedSeconds(now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince1970) - startTs - pausedSeconds(at: now))
    }

    /// Pause the session: freeze the clock, the rest countdown and any running stopwatch. Idempotent, and a
    /// no-op once the receipt is up. FC keeps streaming for display but is dropped from scoring while paused.
    func pause(now: Date = Date()) {
        guard !paused, summary == nil else { return }
        pausedAt = now
        paused = true
    }

    /// Resume: fold the open pause into the accumulator and shift every absolute-time anchor forward by the
    /// paused delta, so the remaining rest, the stopwatch, and the rest floor all resume exactly where they
    /// were. Idempotent.
    func resume(now: Date = Date()) {
        guard paused, let start = pausedAt else { paused = false; pausedAt = nil; return }
        let delta = max(0, now.timeIntervalSince(start))
        pausedAccumulatedS += Int(delta)
        if let r = restEndsAt { restEndsAt = r.addingTimeInterval(delta) }
        if let r = restStartedAt { restStartedAt = r.addingTimeInterval(delta) }
        if let t = timerStart { timerStart = t.addingTimeInterval(delta) }
        pausedAt = nil
        paused = false
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

    /// The rest default for exercises added on the fly in an ad-hoc session (FER-762): a plain 2-minute
    /// fixed countdown — no HR baseline to anchor a heart-rate target to, and the mock's copy promises
    /// «2 min» explicitly. Editable per set via the existing rest editor, same as any routine exercise.
    static let adHocRestSeconds = 120

    /// Append an exercise mid-session (FER-762): used by the «Rápido de fuerza» empty state (no routine)
    /// when the user adds a suggested or searched exercise. Seeds one working set from the exercise's last
    /// recorded weight/reps when there is history, else a starter default — same convention as `make(slots:)`.
    func addExercise(_ exercise: Exercise, lastWeightKg: Double? = nil, lastReps: Int? = nil) {
        let usesReps = exercise.type == .weightReps || exercise.type == .bodyweight
        let weight = lastWeightKg ?? 0
        let reps = usesReps ? (lastReps ?? 8) : 0
        let set = WorkingSet(id: UUID().uuidString, weightKg: weight, reps: reps, done: false)
        let run = ExerciseRun(id: UUID().uuidString, exerciseId: exercise.id,
                              name: StrengthDisplay.name(exercise), type: exercise.type,
                              restSeconds: Self.adHocRestSeconds, restMode: .fixed,
                              hrRestReference: .restingMargin, hrRestValue: 0,
                              lastWeightKg: lastWeightKg, lastReps: lastReps,
                              lastTimeS: nil, lastDistanceM: nil,
                              sets: [set], currentSet: 0, skipped: false)
        runs.append(run)
        currentIndex = runs.count - 1
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
    /// Insert warm-up sets at the FRONT of an exercise (FER-720 · 3a) — warm-ups precede the work sets.
    /// Marked `.warmup` so they're excluded from volume/PRs but still logged. Keeps the current set
    /// focused by shifting its index past the inserted rows.
    func insertWarmup(exercise ei: Int, sets warmups: [(weightKg: Double, reps: Int)]) {
        guard runs.indices.contains(ei), !warmups.isEmpty else { return }
        let rows = warmups.map {
            WorkingSet(id: UUID().uuidString, weightKg: $0.weightKg, reps: $0.reps, done: false, kind: .warmup)
        }
        runs[ei].sets.insert(contentsOf: rows, at: 0)
        runs[ei].currentSet += rows.count
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

    /// Build the `StrengthSession` + its done `SetEntry` rows for saving, each carrying its own `kind`
    /// (`.work`/`.warmup`, FER-720). Each set persists only the fields its exercise type measures, so a
    /// time/distance set never carries the model's placeholder reps and the weight×reps path stays as it was.
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
                                        position: position, kind: set.kind,
                                        weightKg: f.weightKg, reps: f.reps, timeS: f.timeS, distanceM: f.distanceM,
                                        done: true, ts: set.doneTs ?? endTs))
                position += 1
            }
        }
        return (session, entries)
    }

    // MARK: Crash-recovery snapshot (FER-798)

    /// Capture the session's durable state so it survives a crash/kill. Symmetric to `restore(from:)`.
    /// Omits `hrSamples` (memory-only by design) and the receipt; `phase` is re-derived on restore.
    func snapshot(now: Int = Int(Date().timeIntervalSince1970)) -> StrengthSessionSnapshot {
        StrengthSessionSnapshot(
            id: id, routineId: routineId, routineName: routineName, startTs: startTs,
            runs: runs.map { run in
                StrengthSessionSnapshot.RunSnapshot(
                    id: run.id, exerciseId: run.exerciseId, name: run.name, type: run.type,
                    restSeconds: run.restSeconds, restMode: run.restMode,
                    hrRestReference: run.hrRestReference, hrRestValue: run.hrRestValue,
                    lastWeightKg: run.lastWeightKg, lastReps: run.lastReps,
                    lastTimeS: run.lastTimeS, lastDistanceM: run.lastDistanceM,
                    sets: run.sets.map { s in
                        StrengthSessionSnapshot.SetSnapshot(
                            id: s.id, weightKg: s.weightKg, reps: s.reps, timeS: s.timeS,
                            distanceM: s.distanceM, done: s.done, doneTs: s.doneTs,
                            rest: s.rest, kind: s.kind)
                    },
                    currentSet: run.currentSet, skipped: run.skipped)
            },
            currentIndex: currentIndex, restEndsAt: restEndsAt, restStartedAt: restStartedAt,
            currentRestTarget: currentRestTarget, currentRestMode: currentRestMode,
            timerStart: timerStart,
            paused: paused, pausedAccumulatedS: pausedAccumulatedS, pausedAt: pausedAt,
            updatedTs: now)
    }

    /// Rebuild a live session from a persisted snapshot (FER-798). Re-derives `phase` from the rest state;
    /// the id is preserved so `WorkoutMirrorKey.externalUUID(for:)` re-pairs with the watch's `.end`.
    static func restore(from snap: StrengthSessionSnapshot) -> StrengthSessionModel {
        let runs: [ExerciseRun] = snap.runs.map { r in
            ExerciseRun(id: r.id, exerciseId: r.exerciseId, name: r.name, type: r.type,
                        restSeconds: r.restSeconds, restMode: r.restMode,
                        hrRestReference: r.hrRestReference, hrRestValue: r.hrRestValue,
                        lastWeightKg: r.lastWeightKg, lastReps: r.lastReps,
                        lastTimeS: r.lastTimeS, lastDistanceM: r.lastDistanceM,
                        sets: r.sets.map { s in
                            WorkingSet(id: s.id, weightKg: s.weightKg, reps: s.reps, timeS: s.timeS,
                                       distanceM: s.distanceM, done: s.done, doneTs: s.doneTs,
                                       rest: s.rest, kind: s.kind)
                        },
                        currentSet: r.currentSet, skipped: r.skipped)
        }
        let model = StrengthSessionModel(id: snap.id, routineId: snap.routineId,
                                         routineName: snap.routineName, startTs: snap.startTs, runs: runs)
        model.currentIndex = snap.currentIndex
        model.restEndsAt = snap.restEndsAt
        model.restStartedAt = snap.restStartedAt
        model.currentRestTarget = snap.currentRestTarget
        model.currentRestMode = snap.currentRestMode
        model.timerStart = snap.timerStart
        model.phase = snap.restEndsAt != nil ? .resting : .capturing
        model.paused = snap.paused
        model.pausedAccumulatedS = snap.pausedAccumulatedS
        model.pausedAt = snap.pausedAt
        return model
    }

    // MARK: Building from a routine plan

    /// One resolved plan slot handed in from «Rutina de hoy»: the routine exercise, its resolved exercise,
    /// and its recent work sets (newest first) for the «la última vez» prefill.
    struct PlanSlot {
        let re: RoutineExercise
        let exercise: Exercise?
        let lastSets: [SetEntry]
        /// An earned raise from `ProgressionPlanner` (FER-E): the Kg cells seed with `toKg` instead of
        /// the plan/last weight. Default nil so plan-less paths (templates, repeats) are untouched.
        var raise: ProgressionPlanner.Raise? = nil
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
                // FER-E: an earned raise changes the SEED, not the table — every work cell arrives at
                // the proposed weight (double progression trains all work sets at one load).
                let weight = slot.raise?.toKg ?? p.weightKg ?? lastWeight ?? 0
                let reps = usesReps ? (p.reps ?? lastReps ?? 8) : 0
                // FER-715: keep the planned `RoutineSet` id (so a per-set rest edit can persist back to the
                // routine) and carry the set's own rest override (nil = inherit the exercise at rest time).
                return WorkingSet(id: p.id, weightKg: weight, reps: reps, done: false, rest: p.rest)
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
                               sets: sets, currentSet: 0, skipped: false,
                               proposedRaise: type == .weightReps ? slot.raise : nil)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    /// Which runs have their «por qué» raise card expanded (FER-E), by run id.
    @State private var whyRaiseOpen: Set<String> = []
    /// The cell the custom keypad is editing (FER-716) — one at a time, so a single working buffer is
    /// enough. `nil` = no cell active (keypad hidden). Replaces the native keyboard + `@FocusState`.
    @State private var activeCell: CellRef?
    /// The working string of the active cell. Shown while editing; parsed into the model on every change,
    /// so the value persists without an explicit commit. Empty / unparseable keeps the previous value.
    @State private var buffer: String = ""
    /// Whether the user has typed since activating this cell — enables «replace on first keystroke»
    /// (tap a cell showing 60, type 6 → 6, not 606), the expected Hevy-style behavior.
    @State private var bufferTyped: Bool = false
    /// The exercise whose detail sheet is open — set by tapping an exercise's name (FER-538). nil = closed.
    /// Resolving the full `Exercise` (catalog + custom) is deferred to the tap so the session model stays lean.
    @State private var detailExercise: Exercise?
    /// The exercise whose rest editor is open — set by tapping its rest chip (FER-540). nil = closed.
    @State private var restEdit: RestEdit?
    /// Whether the receipt numerals show their final values (FER-716). Starts false so the first
    /// appearance rolls 0 → value; `playReceiptCountUp` flips it (animated only the first time).
    @State private var receiptCountUp = false
    /// The plate calculator (FER-720 · 3a), opened from the keypad's «⛓ discos» for a weight cell. nil = closed.
    @State private var platesTarget: PlatesTarget?
    /// The share-receipt screen (FER-720 · 3c), opened from the 1l receipt. nil = closed.
    @State private var shareReceipt: ShareRef?

    /// The empty «Rápido de fuerza» state (FER-762): no routine, no exercises added yet. Its search field
    /// opens `ExerciseLibraryScreen` in ADD mode; the freshness suggestions load once when this state
    /// appears. `nil` = not loaded yet (the `.task` hasn't resolved); `[]` = loaded, honestly no fresh
    /// muscle to suggest — one optional instead of a separate "have I tried yet" flag.
    @State private var showLibraryPicker = false
    @State private var freshSuggestions: [QuickSuggestion]?
    @State private var loadedMuscle: String?

    /// One «Sugeridos · músculos frescos hoy» row: an exercise for a fresh muscle, with its last logged set.
    struct QuickSuggestion: Identifiable {
        let exercise: Exercise
        let muscle: String
        let lastWeightKg: Double?
        let lastReps: Int?
        var id: String { exercise.id }
    }

    /// Identifies which exercise's rest is being edited (FER-716); `setIndex` non-nil = a per-set edit
    /// (from the rest card), nil = exercise-scope (from the rest chip). The editor seeds from `runs[id]`.
    struct RestEdit: Identifiable { let id: Int; var setIndex: Int? = nil }

    /// The exercise + work weight (kg) the plate calculator was opened for (FER-720 · 3a).
    struct PlatesTarget: Identifiable { let id = UUID(); let ei: Int; let weightKg: Double }
    /// A marker to present the share screen (FER-720 · 3c); the summary comes from `session.summary`.
    struct ShareRef: Identifiable { let id = UUID() }

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

    /// The «Rápido de fuerza» empty state (FER-762): an ad-hoc session (no routine) with nothing logged
    /// yet — the search + freshness-suggestions state, before the first exercise turns this into a normal
    /// guided session.
    private var isEmptyAdHoc: Bool { session.routineId == nil && session.runs.isEmpty }

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
            } else if isEmptyAdHoc {
                emptyAdHocSession
            } else {
                inlineSession
            }
        }
        .background(theme.paper.ignoresSafeArea())
        .instrumentoTheme(theme)
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
                let si = edit.setIndex
                let current: RestConfig = (si.flatMap { run.sets.indices.contains($0) ? run.sets[$0].rest : nil }) ?? run.restConfig
                RestEditorScreen(
                    theme: theme, exerciseName: run.name,
                    setNumber: si.map { $0 + 1 },
                    current: current,
                    persistsToRoutine: session.routineId != nil,
                    restingHR: restingBaseline, maxHR: profileMaxHR,
                    defaultApplyToAll: si == nil,
                    closeAsDismiss: true,   // FER-831: presented as a .sheet here → close with ✕, not a back chevron
                    onCancel: { restEdit = nil },
                    onApply: { config, applyToAll, saveToRoutine in
                        applyRestEdit(ei: edit.id, si: si, config: config, applyToAll: applyToAll, saveToRoutine: saveToRoutine)
                        restEdit = nil
                    }
                )
                .preferredColorScheme(.light)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(theme.paper)
            }
        }
        .sheet(item: $platesTarget) { target in
            PlatesScreen(
                theme: theme,
                targetKg: target.weightKg,
                exerciseName: session.runs.indices.contains(target.ei) ? session.runs[target.ei].name : "",
                store: model.plates,
                onInsertWarmup: { sets in
                    session.insertWarmup(exercise: target.ei, sets: sets)
                    platesTarget = nil
                },
                onClose: { platesTarget = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(theme.paper)
        }
        .sheet(item: $shareReceipt) { _ in
            if let summary = session.summary {
                ShareReceiptScreen(theme: theme, summary: summary, onClose: { shareReceipt = nil })
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(theme.paper)
            }
        }
        // S-2 (FER-830): one destructive-confirmation pattern across the flow — confirmationDialog, not a
        // mix of .alert and .confirmationDialog. The cancel verb is «Keep going» / «Seguir» everywhere.
        .confirmationDialog("Finish workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Save workout") { model.endStrengthSession(save: true) }
            Button("Discard workout", role: .destructive) { model.endStrengthSession(save: false) }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text(session.doneCount == 0
                 ? "You haven't logged any sets yet."
                 : (session.pendingCount > 0
                    ? "\(session.pendingCount) sets aren't logged yet. Save keeps them; discard deletes everything."
                    : "Save keeps this workout. Discard deletes everything you logged."))
        }
        .confirmationDialog("Discard workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { model.endStrengthSession(save: false) }
            Button("Keep going", role: .cancel) {}
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
                    // The rest card (1k) slots between this exercise's rows and the next, while resting here.
                    if session.phase == .resting, ei == session.currentIndex, session.summary == nil {
                        restInlineCard
                            // A fixed rest that runs out dismisses itself — focus lands on the next active
                            // set with no tap in between (HR rests keep the card up until the buzz/skip).
                            .task(id: session.restEndsAt) {
                                guard session.currentRestMode == .fixed, let end = session.restEndsAt else { return }
                                let delay = end.timeIntervalSinceNow
                                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                                guard !Task.isCancelled, session.phase == .resting, !session.paused else { return }
                                withAnimation(StrandMotion.gentle) { session.skipRest() }
                            }
                            .plainRow(top: 4)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let cell = activeCell { keypad(for: cell) }
        }
        .onChange(of: activeCell) { _, newValue in
            // Seed the buffer from the newly-active cell's current value (replace-on-first-keystroke), and
            // make its row the «active» one so the header/rest logic tracks it.
            if let f = newValue {
                let (ei, si) = Self.indices(f)
                session.select(exerciseIndex: ei, setIndex: si)
                buffer = currentCellString(f); bufferTyped = false
            } else {
                buffer = ""; bufferTyped = false
            }
        }
    }

    /// The custom keypad bound to the active cell (FER-716).
    @ViewBuilder private func keypad(for cell: CellRef) -> some View {
        let (ei, si) = Self.indices(cell)
        let run = session.runs.indices.contains(ei) ? session.runs[ei] : nil
        SessionKeypad(
            theme: theme,
            stepLabel: isWeightCell(cell) ? (imperial ? "±5" : "±2,5") : "±1",
            canCopyPrevious: run.map { previousText($0) != nil } ?? false,
            platesEnabled: isWeightCell(cell),
            onDigit: { keypadInput(String($0)) },
            onComma: { keypadComma() },
            onBackspace: { keypadBackspace() },
            onNext: { focusNextCell() },
            onCopyPrevious: { if let run { prefillTapped(ei: ei, si: si, run: run); syncBufferFromModel(cell) } },
            onStep: { keypadStep(cell) },
            onPlates: { openPlates(ei: ei, si: si) }
        )
        .transition(.move(edge: .bottom))
    }

    /// Open the plate calculator (FER-720 · 3a) for a weight cell, seeded with that set's current load.
    private func openPlates(ei: Int, si: Int) {
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return }
        platesTarget = PlatesTarget(ei: ei, weightKg: session.runs[ei].sets[si].weightKg)
    }

    /// The first non-skipped exercise's index — its header skips the inter-exercise top gap.
    private var firstActiveIndex: Int { session.runs.firstIndex { !$0.skipped } ?? 0 }

    private static func indices(_ ref: CellRef) -> (Int, Int) {
        switch ref { case let .weight(e, s): return (e, s); case let .reps(e, s): return (e, s) }
    }

    // MARK: Session header (title + Finish + live counters)

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            // Row 1: minimize «‹» (session stays alive, the pill re-opens it) · routine name · «Terminar».
            HStack(spacing: 10) {
                Button { model.strengthSheetPresented = false } label: {
                    Image(systemName: "chevron.left")
                        .font(StrandFont.glyph(.lead, weight: .semibold)).foregroundStyle(theme.ink)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Minimize session"))
                Text(session.routineName).font(StrandFont.title2).foregroundStyle(theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                // FER-823: paused → «Resume» is the primary action (finish after resuming); running with
                // sets → a pause toggle sits left of Finish; the empty ad-hoc session only offers Discard.
                if session.paused {
                    Button { model.resumeStrengthSessionFromPause() } label: {
                        Label("Resume", systemImage: "play.fill").labelStyle(.titleAndIcon)
                            .font(StrandFont.subhead).foregroundStyle(theme.ink)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Resume session"))
                } else if !isEmptyAdHoc {
                    Button { model.pauseStrengthSession() } label: {
                        Image(systemName: "pause.fill")
                            .font(StrandFont.glyph(.inline, weight: .semibold)).foregroundStyle(theme.ink)
                            .frame(width: 38, height: 38)
                            .background(theme.surface, in: Circle())
                            .overlay(Circle().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Pause session"))
                    // Ending the session is the one destructive-ish act in the header — it carries the
                    // reserved alert hue (label + border, never a fill: primary-by-border, DNA §).
                    Button { finishTapped() } label: {
                        Text("Finish").font(StrandFont.subhead).foregroundStyle(theme.critical)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(theme.critical.opacity(StrandOpacity.dim), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Finish workout"))
                } else {
                    Button { discardEmptySession() } label: {
                        Text("Discard").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Discard workout"))
                }
            }
            .padding(.leading, -10)   // pull the 44pt chevron target back to the 24pt margin edge

            // Row 2: per-exercise progress, filled by how done each exercise is.
            SessionProgressBar(segments: progressSegments,
                               hue: session.paused ? theme.inkDim : theme.dataStrain,   // FER-823: no hue while paused
                               track: theme.hairline)
                .accessibilityLabel(Text("Session progress"))
                .accessibilityValue(Text("\(session.doneCount) of \(sessionSetsTotal) sets"))

            // Row 3: the big running clock (the session's dominant datum in the header). FER-823: it counts
            // ACTIVE time (excludes pauses), so it naturally freezes while paused and dims to `inkDim`.
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                let elapsed = session.elapsedSeconds(now: ctx.date)
                Text(Self.clock(elapsed))
                    .font(InstrumentoType.groteskSessionClock)
                    .tracking(InstrumentoType.groteskSessionClockTracking)
                    .foregroundStyle(session.paused ? theme.inkDim : theme.ink)
                    .accessibilityLabel(Text(session.paused ? "Paused at \(Self.clock(elapsed))"
                                                             : "Elapsed \(Self.clock(elapsed))"))
            }
            if session.paused {
                Text("Paused").font(StrandFont.caption).textCase(.uppercase).tracking(0.8)
                    .foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)   // the clock already announces the paused state
            }

            // Row 4: quiet counters — volume · sets · (kcal only when the strap is streaming, no dashes).
            Text(counterLine).font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkSecondary)
                .accessibilityElement(children: .combine)

            // Row 5: live BPM with the one always-on pulse of the app — hidden (not dashed) with no strap.
            // PulseReader: only this row re-evaluates per heartbeat, including its presence (FER-755).
            PulseReader(model.live.pulse) { p in
                if let bpm = p.smoothedBpm {
                    HStack(spacing: 6) {
                        BpmPulseDot(color: theme.dataHeart, animated: !reduceMotion)
                        Text("\(bpm)").font(StrandFont.caption.monospacedDigit()).foregroundStyle(theme.dataHeart)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Heart rate \(bpm)"))
                } else if let rec = recovery {
                    // No strap: keep the «push / hold / ease» autoregulation line (F6), discreet, in place of BPM.
                    Text(recoveryLine(rec)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Row 6: the Apple Watch mirror status (FER-742) — one tertiary line, silent unless the watch
            // is recording or failed to answer. Never competes with the session; never blocks it.
            watchStatusLine
        }
        .padding(.horizontal, NoopMetrics.screenPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(theme.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    /// One progress segment per non-skipped exercise: width ∝ its set count, fill = fraction of its sets done.
    private var progressSegments: [SessionProgressBar.Segment] {
        session.runs.filter { !$0.skipped }.map { run in
            let total = max(run.sets.count, 1)
            let done = run.sets.filter(\.done).count
            return .init(sets: total, done: Double(done) / Double(total))
        }
    }

    /// Total planned sets across non-skipped exercises (the progress denominator).
    private var sessionSetsTotal: Int {
        session.runs.filter { !$0.skipped }.reduce(0) { $0 + $1.sets.count }
    }

    /// «2.480 kg · 8/17 series · ~312 kcal» — the kcal clause is dropped entirely when there's no strap
    /// HR (no dashes, no zero): the receipt is where the estimate lands.
    private var counterLine: String {
        var parts = ["\(massText(sessionVolumeKg))",
                     "\(session.doneCount)/\(sessionSetsTotal) " + String(localized: "series")]
        if let kcal = liveKcal { parts.append("~\(kcal) kcal") }
        return parts.joined(separator: " · ")
    }

    /// Live energy estimate (kcal) from the strap samples captured so far — nil (so the clause is hidden)
    /// until the strap has streamed HR. Same Keytel entry point as the receipt/persist path (FER-715).
    private var liveKcal: Int? {
        let samples = session.hrSamples
        guard samples.count >= Calories.strengthEnergyMinSamples else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let profile = UserProfile(weightKg: model.profile.weightKg, heightCm: model.profile.heightCm,
                                  age: Double(model.profile.age), sex: model.profile.sex)
        let kcal = Calories.estimateStrengthEnergy(
            hrSamples: samples, durationSeconds: Double(max(0, now - session.startTs)),
            profile: profile, hrMax: Double(model.profile.hrMax))
        return Int(kcal.rounded())
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

    /// The Apple Watch mirror line (FER-742): «Reloj grabando» when the watch confirms; «El reloj no
    /// respondió» + «Reintentar» on a first miss; «Sin reloj esta sesión» once the retry is spent. Nothing
    /// while the mirror is off, absent, or still connecting — the tertiary ink keeps it out of the way.
    @ViewBuilder
    private var watchStatusLine: some View {
        switch model.watchSessionStatus {
        case .recording:
            watchLine("applewatch", "Watch recording", retry: false)
        case .notResponding:
            watchLine("applewatch.slash", "The watch didn't respond", retry: true)
        case .unavailable:
            watchLine("applewatch.slash", "No watch this session", retry: false)
        case .inactive, .waiting:
            EmptyView()
        }
    }

    private func watchLine(_ icon: String, _ text: LocalizedStringKey, retry: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text(text).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            if retry {
                Button { model.retryWatchMirroring() } label: {
                    Text("Retry").font(StrandFont.caption).fontWeight(.medium).foregroundStyle(theme.ink)
                }
                .buttonStyle(.plain).padding(.leading, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Exercise header + inline rows

    /// One exercise's header: a type overline (for non-weight×reps), the name, and the column header.
    /// Grouped by whitespace + hairlines — a registration sheet, not a grid.
    private func exerciseHeader(_ run: StrengthSessionModel.ExerciseRun, ei: Int, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(spacing: 12) {
                SessionRunThumb(exerciseId: run.exerciseId)   // baked still fills the FER-751 slot
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
                            .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(run.name))
                .accessibilityHint(Text("View exercise detail"))
                }
            }
            // FER-E · 2b: the earned raise, named where you train. «↑ hoy 102,5 · por qué» toggles the
            // arithmetic card; green because the raise IS the datum.
            if let raise = run.proposedRaise {
                raiseLine(raise, ei: ei)
                if whyRaiseOpen.contains(run.id) { whyRaiseCard(raise, ei: ei) }
            }
            restChip(run, ei: ei)
            if !reflow { columnHeader(run.type) }
        }
        .padding(.top, first ? NoopMetrics.gap : NoopMetrics.sectionGap)
    }

    // MARK: Proposed raise (FER-E)

    private func raiseLine(_ raise: ProgressionPlanner.Raise, ei: Int) -> some View {
        Button {
            withAnimation(StrandMotion.interactive) {
                let id = session.runs[ei].id
                if whyRaiseOpen.contains(id) { whyRaiseOpen.remove(id) } else { whyRaiseOpen.insert(id) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up")
                    .font(StrandFont.glyph(.chevron, weight: .bold))
                Text("today \(massText(raise.toKg))")
                    .font(InstrumentoType.grotesk(12, weight: .bold)).monospacedDigit()
                Text("·").foregroundStyle(theme.inkTertiary)
                Text("why")
                    .font(InstrumentoType.grotesk(12, weight: .bold))
                    .underline(pattern: .dot, color: theme.dataRecovery.opacity(0.55))
            }
            .foregroundStyle(theme.dataRecovery)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Today you raise to \(massText(raise.toKg))"))
        .accessibilityHint(Text("Shows why, with your real dates"))
    }

    /// The «por qué» block (WhyRaiseCard, handoff 2b): connection surface, 2.5pt green bar, the arithmetic
    /// phrase, and the two text actions. «Volver a X» is the per-session opt-out: it reseeds the undone
    /// cells back to the old weight and drops the proposal — it never counts as a cycle failure.
    private func whyRaiseCard(_ raise: ProgressionPlanner.Raise, ei: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("WHY \(massText(raise.toKg))")
                .instrumentoOverline().foregroundStyle(theme.dataRecovery)
            Text(verbatim: raise.phrase)
                .font(StrandFont.caption).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Goal today: \(session.runs[ei].sets.count)×\(session.runs[ei].sets.first?.reps ?? 0) with the new weight. Losing a rep or two on a raise is normal; you win them back in 1 or 2 sessions.")
                .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Button { withAnimation(StrandMotion.interactive) { _ = whyRaiseOpen.remove(session.runs[ei].id) } } label: {
                    Text("Keep \(massText(raise.toKg))")
                        .font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.dataRecovery)
                }
                .buttonStyle(.plain)
                Button { revertRaise(ei: ei) } label: {
                    Text("Back to \(massText(raise.fromKg))")
                        .font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .overlay(alignment: .leading) { Rectangle().fill(theme.dataRecovery).frame(width: 2.5) }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 8, topTrailingRadius: 8))
    }

    /// The per-session opt-out («Volver a X»): undone cells go back to the old weight; done sets keep
    /// whatever was actually lifted. The cycle is untouched — hitting the goal at the old weight simply
    /// re-earns the raise for the next session.
    private func revertRaise(ei: Int) {
        guard session.runs.indices.contains(ei),
              let raise = session.runs[ei].proposedRaise else { return }
        withAnimation(StrandMotion.interactive) {
            for si in session.runs[ei].sets.indices where !session.runs[ei].sets[si].done {
                session.runs[ei].sets[si].weightKg = raise.fromKg
            }
            session.runs[ei].proposedRaise = nil
            whyRaiseOpen.remove(session.runs[ei].id)
        }
    }

    /// A quiet, tappable chip showing this exercise's rest — tap to edit it mid-session (FER-540).
    private func restChip(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        Button { openRestEditor(ei: ei) } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock").font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                Text(restChipLabel(run)).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                Image(systemName: "chevron.right").font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
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

    /// Open the rest editor (FER-540/716). `setIndex` non-nil → a per-set edit (from the rest card);
    /// nil → exercise-scope (from the rest chip).
    private func openRestEditor(ei: Int, setIndex: Int? = nil) {
        guard session.runs.indices.contains(ei) else { return }
        restEdit = RestEdit(id: ei, setIndex: setIndex)
    }

    /// Apply an edited rest from the 1e editor (FER-716): to the live session at the chosen scope, and —
    /// when «save to routine» is on and the session is backed by a saved routine — persist it (per-set via
    /// `updateRoutineSetRest`, or the whole exercise via the cascading `updateRoutineExerciseRest`).
    private func applyRestEdit(ei: Int, si: Int?, config: RestConfig, applyToAll: Bool, saveToRoutine: Bool) {
        guard session.runs.indices.contains(ei) else { return }
        if applyToAll || si == nil {
            session.updateRest(exercise: ei, mode: config.mode, seconds: config.seconds,
                               reference: config.hrReference, value: config.hrValue)
            if saveToRoutine, let routineId = session.routineId {
                let reId = session.runs[ei].id
                Task {
                    await model.repo.updateRoutineExerciseRest(
                        routineExerciseId: reId, routineId: routineId,
                        mode: config.mode, seconds: config.seconds,
                        reference: config.hrReference, value: config.hrValue)
                }
            }
        } else if let si {
            session.updateRest(exercise: ei, set: si, rest: config)
            if saveToRoutine, let routineId = session.routineId,
               session.runs[ei].sets.indices.contains(si) {
                let routineSetId = session.runs[ei].sets[si].id   // seeded from the planned RoutineSet id
                Task { await model.repo.updateRoutineSetRest(routineSetId: routineSetId, routineId: routineId, rest: config) }
            }
        }
    }

    /// The quiet column header (overline). Hidden at accessibility sizes — each reflowed cell self-labels.
    private func columnHeader(_ type: ExerciseType) -> some View {
        let titles = columnTitles(type)
        return HStack(spacing: 8) {
            Text("SET").instrumentoOverline().foregroundStyle(theme.inkTertiary).frame(width: 44, alignment: .center)
            Text("PREVIOUS · REST").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
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
        // A time / distance set, when it's the active row, expands inline with a compact stopwatch +
        // live HR zone (FER-716: this replaces the modal «Foco»). Other rows are the flat logging row.
        let cardio = run.type == .time || run.type == .distance
        Group {
            if active && cardio { cardioInlineRow(ei: ei, si: si, run: run, set: set) }
            else if reflow { reflowRow(ei: ei, si: si, run: run, set: set) }
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

    /// The active time / distance row, expanded inline (FER-716) — a compact stopwatch (the elapsed /
    /// captured time as the dominant datum), a Start/Stop capsule (Stop registers the set and starts the
    /// rest), a distance stepper for distance sets, and the strap's live HR zone on the right.
    @ViewBuilder private func cardioInlineRow(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                                              set: StrengthSessionModel.WorkingSet) -> some View {
        let running = session.timerStart != nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                badge(ei: ei, si: si, number: si + 1)
                // The clock — ticks live while running, else shows the captured time.
                Group {
                    if running {
                        TimelineView(.periodic(from: Date(), by: 1)) { ctx in cardioClock(session.timerElapsed(now: ctx.date)) }
                    } else {
                        cardioClock(set.timeS ?? 0)
                    }
                }
                Spacer(minLength: 8)
                PulseReader(model.live.pulse) { p in
                    if let hr = p.smoothedBpm { compactZone(hr) }
                }
                startStopButton(running: running)
                checkButton(ei: ei, si: si, set: set)
            }
            if run.type == .distance { distanceStepperRow(set.distanceM ?? 0) }
        }
        .frame(minHeight: run.type == .distance ? 96 : 64)
        .accessibilityElement(children: .contain)
    }

    private func cardioClock(_ elapsed: Int) -> some View {
        Text(Self.clock(elapsed))
            .font(InstrumentoType.groteskSessionClock).tracking(InstrumentoType.groteskSessionClockTracking)
            .foregroundStyle(elapsed > 0 ? theme.ink : theme.inkTertiary)
            .monospacedDigit()
    }

    private func startStopButton(running: Bool) -> some View {
        Button {
            withAnimation(.snappy) {
                running ? session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR)
                        : session.startSetTimer()
            }
        } label: {
            Text(running ? "Stop" : "Start").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .padding(.horizontal, 14).frame(height: 34)
                .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(running ? "Stop and register set" : "Start timer"))
    }

    /// Compact live HR zone (♥ bpm · Zn) in the zone hue — hidden when there's no strap (no dashes).
    private func compactZone(_ hr: Int) -> some View {
        let zone = hrZone(hr)
        let hue = theme.hrZoneRamp[max(0, min(theme.hrZoneRamp.count - 1, zone - 1))]
        return HStack(spacing: 5) {
            Image(systemName: "heart.fill").font(StrandFont.glyph(.chevron)).foregroundStyle(hue)
            Text("\(hr)").font(StrandFont.subhead.monospacedDigit()).foregroundStyle(hue)
            Text("Z\(zone)").font(StrandFont.caption).foregroundStyle(hue)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Heart rate \(hr), zone \(zone)"))
    }

    private func distanceStepperRow(_ meters: Double) -> some View {
        HStack(spacing: 14) {
            stepper(system: "minus", size: 26) { session.bumpDistance(byMeters: -distanceStepM) }
                .accessibilityLabel(Text("Decrease distance"))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(distanceNumber(meters)).font(StrandFont.number(18, weight: .regular)).monospacedDigit()
                    .foregroundStyle(theme.ink)
                Text(imperial ? "mi" : "km").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            stepper(system: "plus", size: 26) { session.bumpDistance(byMeters: distanceStepM) }
                .accessibilityLabel(Text("Increase distance"))
        }
        .padding(.leading, 44)
    }

    // MARK: - Inline rest card (1k, FER-716)

    /// The rest card — the ONE surface in the flow that lifts off the paper (`floatShadow`), because it's
    /// literally above the session's time. Slots between the marked set and the next; the table never
    /// disappears. By-HR: the live pulse drops toward the threshold; by-time: a countdown. No strap on an
    /// HR rest → it degrades to a capped timer with an honest notice (no dashes, no red).
    @ViewBuilder private var restInlineCard: some View {
        let hrMode = session.currentRestMode == .heartRate
        VStack(alignment: .leading, spacing: 12) {
            if hrMode, let started = session.restStartedAt {
                // PulseReader: the by-HR rest card follows the live pulse per beat (the TimelineView
                // alone would cap it at 1 s), and the haptic trigger keeps its per-beat evaluation (FER-755).
                PulseReader(model.live.pulse) { p in
                    TimelineView(.periodic(from: started, by: 1)) { ctx in
                        let elapsed = max(0, Int(ctx.date.timeIntervalSince(started)))
                        let v = RestReadinessRule.evaluate(
                            currentHR: p.smoothedBpm, worn: model.live.worn, restingHR: restingBaseline,
                            elapsedS: elapsed, targetHR: session.currentRestTarget)
                        if v.state == .noSignal {
                            restCardTimeBody(end: session.restEndsAt, now: ctx.date, noStrapFallback: true)
                        } else {
                            restCardHRBody(elapsed: elapsed, readiness: v)
                        }
                    }
                    .sensoryFeedback(.success, trigger: p.smoothedBpm != nil && session.currentRestTarget != nil)
                }
            } else if let end = session.restEndsAt, let started = session.restStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    restCardTimeBody(end: end, now: ctx.date, noStrapFallback: false)
                }
            }
            restCardPills
        }
        .padding(.horizontal, 17).padding(.vertical, 15)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairlineStrong, lineWidth: 1))
        .floatShadow(theme)
        .padding(.horizontal, -4).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    /// By-HR rest body: the live pulse dropping toward the threshold, with a gradient track + ink tick.
    private func restCardHRBody(elapsed: Int, readiness v: RestReadiness) -> some View {
        let bpm = model.bpm ?? 0
        let target = session.currentRestTarget
        let ready = v.ready
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Resting · by HR").font(StrandFont.caption).fontWeight(.semibold)
                    .tracking(0.8).textCase(.uppercase).foregroundStyle(theme.dataStrain)
                Spacer()
                Text("\(Self.clock(elapsed)) elapsed").font(StrandFont.caption).monospacedDigit()
                    .foregroundStyle(theme.inkTertiary)
            }
            Text(ready ? String(localized: "Ready") : "\(bpm)")
                .font(InstrumentoType.groteskRestPulse).tracking(InstrumentoType.groteskRestPulseTracking)
                .monospacedDigit()
                .foregroundStyle(theme.dataRecovery)
                .contentTransition(.numericText())
            restHRTrack(bpm: bpm, target: target)
            if let target, !ready {
                (Text(String(localized: "dropping toward "))
                 + Text("\(target) bpm").foregroundColor(theme.dataRecovery).bold()
                 + Text(" · " + String(localized: "the strap will buzz")))
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The FC track: a linear scale from a warm start toward the threshold; the ink tick is the threshold
    /// (position is the channel), the `dataHeart → dataRecovery` gradient reinforces hot → goal.
    private func restHRTrack(bpm: Int, target: Int?) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Progress toward ready: from a nominal peak (~target+40) down to the target.
            let hi = Double((target ?? bpm) + 40)
            let lo = Double(target ?? bpm)
            let frac = hi > lo ? max(0, min(1, (hi - Double(bpm)) / (hi - lo))) : 1
            ZStack(alignment: .leading) {
                Capsule().fill(theme.hairline)
                Capsule().fill(LinearGradient(colors: [theme.dataHeart, theme.dataRecovery],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * frac)
                Rectangle().fill(theme.ink).frame(width: 2, height: 14)
                    .offset(x: w - 1)   // threshold tick at the ready end
            }
        }
        .frame(height: 6)
    }

    /// By-time rest body (also the no-strap fallback for an HR rest, capped at 5 min with a notice).
    private func restCardTimeBody(end: Date?, now: Date, noStrapFallback: Bool) -> some View {
        let cappedEnd = noStrapFallback ? min(end ?? now, (session.restStartedAt ?? now).addingTimeInterval(300)) : end
        let remaining = cappedEnd.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(noStrapFallback ? "Resting · by time" : "Resting")
                    .font(StrandFont.caption).fontWeight(.semibold)
                    .tracking(0.8).textCase(.uppercase).foregroundStyle(theme.dataStrain)
                Spacer()
            }
            Text(Self.clock(remaining))
                .font(InstrumentoType.groteskRestPulse).tracking(InstrumentoType.groteskRestPulseTracking)
                .monospacedDigit()
                .foregroundStyle(remaining == 0 ? theme.dataRecovery : theme.ink)
                .contentTransition(.numericText())
            if noStrapFallback {
                Text("No strap signal: resting by time, 5 min cap")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var restCardPills: some View {
        HStack(spacing: 10) {
            Button { openRestEditor(ei: session.currentIndex,
                                    setIndex: session.runs.indices.contains(session.currentIndex) ? session.runs[session.currentIndex].currentSet : nil) } label: {
                Label("Change rest", systemImage: "pencil").font(StrandFont.caption).foregroundStyle(theme.ink)
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button { withAnimation(StrandMotion.gentle) { session.skipRest() } } label: {
                Text("Skip").font(StrandFont.caption).foregroundStyle(theme.ink)
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    /// The set-number badge — a non-interactive marker in the effort hue (FER-716: the Foco is gone; the
    /// row itself is the interactive surface). A ring with the set number.
    private func badge(ei: Int, si: Int, number: Int) -> some View {
        Text("\(number)").font(StrandFont.caption).monospacedDigit()
            .foregroundStyle(theme.dataStrain)
            .frame(width: 26, height: 26)
            .overlay(Circle().strokeBorder(theme.dataStrain, lineWidth: 1.5))
            .frame(width: reflow ? 26 : 44, height: reflow ? 26 : 44, alignment: .center)
            .accessibilityLabel(Text("Set \(number)"))
    }

    /// «ANTERIOR · DESCANSO» — last time's value + this set's own rest (FER-716, per-set since F0);
    /// tap to copy last time into this row. «—» (and inert) when there's neither.
    @ViewBuilder private func previousCell(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun) -> some View {
        let rest = shortRest(run.effectiveRest(forSet: si))
        if let text = previousText(run) {
            Button { prefillTapped(ei: ei, si: si, run: run) } label: {
                Text(reflow ? "Previous: \(text)" : "\(text) · \(rest)")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Previous, \(text)"))
            .accessibilityHint(Text("Copies it to this set"))
        } else {
            Text(verbatim: "— · \(rest)").font(StrandFont.caption).foregroundStyle(theme.inkDim)
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityLabel(Text("No previous record"))
        }
    }

    /// A set's rest, compressed for the ANTERIOR cell: «2 min» / «90 s» / «por FC».
    private func shortRest(_ config: RestConfig) -> String {
        guard config.mode != .heartRate else { return String(localized: "by HR") }
        if config.seconds >= 60, config.seconds % 60 == 0 { return "\(config.seconds / 60) min" }
        return "\(config.seconds) s"
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
    /// An editable numeric cell — a form field on paper filled «with the pen». Tapping it activates the
    /// custom keypad (FER-716, no native keyboard, no «Foco»); while active it shows the working buffer
    /// with a caret and a 2px ink underline, otherwise the formatted value with a hairline underline.
    private func numberCell(_ ref: CellRef, value: Double, isInt: Bool, done: Bool,
                            type: ExerciseType, width: CGFloat? = nil) -> some View {
        let active = activeCell == ref
        let shown = active ? buffer : formatCell(value, isInt: isInt)
        return Button { activeCell = ref } label: {
            HStack(spacing: 1) {
                Text(shown.isEmpty ? " " : shown)
                    .font(StrandFont.number(16, weight: .regular)).monospacedDigit()
                    .foregroundStyle(done ? theme.inkSecondary : theme.ink)
                if active {
                    Rectangle().fill(theme.ink).frame(width: 2, height: 18)   // caret
                        .opacity(0.9) // token-exempt: opacidad de caret >0.70
                }
            }
            .frame(width: width ?? (reflow ? 64 : cellWidth(type)), height: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(active ? theme.ink : theme.hairlineStrong)
                    .frame(height: active ? 2 : 1)
                    .padding(.bottom, 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(cellLabel(ref)))
        .accessibilityValue(Text(shown))
    }

    // MARK: Custom keypad input (FER-716)

    /// The active cell's current model value as a display string (seeds the buffer on activate).
    private func currentCellString(_ ref: CellRef) -> String {
        let (ei, si) = Self.indices(ref)
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return "" }
        let set = session.runs[ei].sets[si]
        switch ref {
        case .weight: return formatCell(displayWeight(set.weightKg), isInt: false)
        case .reps:   return formatCell(Double(set.reps), isInt: true)
        }
    }
    private func isWeightCell(_ ref: CellRef) -> Bool { if case .weight = ref { return true }; return false }

    /// Append a digit — replacing the seeded value on the first keystroke (Hevy-style).
    private func keypadInput(_ digit: String) {
        if !bufferTyped { buffer = ""; bufferTyped = true }
        buffer += digit
        commitBuffer()
    }
    private func keypadComma() {
        guard let cell = activeCell, isWeightCell(cell) else { return }   // reps are integers
        if !bufferTyped { buffer = "0"; bufferTyped = true }
        if !buffer.contains(",") && !buffer.contains(".") { buffer += "," }
        commitBuffer()
    }
    private func keypadBackspace() {
        if !bufferTyped { buffer = ""; bufferTyped = true }
        if !buffer.isEmpty { buffer.removeLast() }
        commitBuffer()
    }
    /// Quick add a plate / rep with the ± pill (adds the step; decrement via editing). Acts on the active
    /// cell's row, which `activeCell` has already made the current set.
    private func keypadStep(_ cell: CellRef) {
        switch cell {
        case .weight: session.bumpWeight(byKg: weightStepKg)
        case .reps:   session.bumpReps(1)
        }
        syncBufferFromModel(cell)
    }
    /// Push the buffer's parsed value into the model — empty / invalid keeps the previous value.
    private func commitBuffer() {
        guard let cell = activeCell, let v = Self.parseDouble(buffer) else { return }
        let (ei, si) = Self.indices(cell)
        switch cell {
        case .weight: session.setWeight(exercise: ei, set: si, kg: storedKg(fromDisplay: v))
        case .reps:   session.setReps(exercise: ei, set: si, reps: Int(v.rounded()))
        }
    }
    /// Re-seed the buffer from the model after a mutation that didn't come from typing (± / copy last).
    private func syncBufferFromModel(_ cell: CellRef) { buffer = currentCellString(cell); bufferTyped = false }

    /// A captured (non-typed) time / distance cell — tap to select the row, which expands it inline with the
    /// stopwatch (FER-716: the Foco is gone). Shows «—» until set.
    private func capturedCell(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun, text: String?) -> some View {
        Button { withAnimation(StrandMotion.gentle) { session.select(exerciseIndex: ei, setIndex: si) } } label: {
            Group {
                if let text {
                    Text(text).font(StrandFont.number(16, weight: .regular)).monospacedDigit().foregroundStyle(theme.ink)
                } else {
                    Image(systemName: "play.circle").font(StrandFont.glyph(.lead)).foregroundStyle(theme.inkTertiary)
                }
            }
            .frame(width: reflow ? nil : cellWidth(run.type))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(text ?? String(localized: "Not recorded")))
        .accessibilityHint(Text("Expands the timer"))
    }

    /// The done toggle (the datum's color — green when logged). 44pt touch target. Checking the ACTIVE
    /// pending set registers it and starts the rest (FER-716: the rest card appears inline); any other
    /// tap is a plain toggle (a correction that starts no rest).
    private func checkButton(ei: Int, si: Int, set: StrengthSessionModel.WorkingSet) -> some View {
        let curSet = session.runs.indices.contains(ei) ? session.runs[ei].currentSet : -1
        let isActivePending = ei == session.currentIndex && si == curSet && !set.done
        return Button {
            withAnimation(.snappy) {
                if isActivePending { activeCell = nil; session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR) }
                else { session.toggleDone(exercise: ei, set: si) }
            }
        } label: {
            Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                .font(StrandFont.glyph(.lead))
                .foregroundStyle(set.done ? theme.dataRecovery
                                 : isActivePending ? theme.dataStrain : theme.inkDim)
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

    // MARK: Empty ad-hoc state (mock 1p, FER-762)

    private var emptyAdHocSession: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                Text("No routine: add exercises as you go. Rest defaults to 2 min, change it set by set.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button { showLibraryPicker = true } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").font(StrandFont.glyph(.inline)).foregroundStyle(theme.inkTertiary)
                        Text("Search the library…").font(StrandFont.body).foregroundStyle(theme.inkTertiary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13).padding(.vertical, 11)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityLabel(Text("Search the exercise library"))

                // FER-762: a brand-new user has no muscle-load history yet — `loadFreshSuggestions` then
                // returns no picks. Falling back to the search-only flow (no orphaned "Suggested" header
                // over an empty list) rather than a section with nothing under it.
                if let suggestions = freshSuggestions, !suggestions.isEmpty {
                    Text("Suggested · muscles fresh today").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        .padding(.top, 10)
                    ForEach(suggestions) { s in suggestionRow(s) }

                    if let muscle = loadedMuscle {
                        (Text(MuscleAtlas.name(muscle)) + Text(verbatim: " ") + Text("still carries load · suggestions avoid it."))
                            .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 13).padding(.vertical, 11)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                                .strokeBorder(theme.hairline, lineWidth: 1))
                            .padding(.top, 3)
                    }
                }

                Divider().overlay(theme.hairline).padding(.top, 10)
                Text("You'll be able to save this as a routine when you finish · it doesn't touch your plan.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 16)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .safeAreaInset(edge: .top, spacing: 0) { sessionHeader }
        .task {
            guard freshSuggestions == nil else { return }
            await loadFreshSuggestions()
        }
        .sheet(isPresented: $showLibraryPicker) {
            ExerciseLibraryScreen { picks in
                showLibraryPicker = false
                Task { await addExercises(picks) }
            }
            .instrumentoTheme(theme).environmentObject(model.repo).preferredColorScheme(.light)
        }
    }

    private func suggestionRow(_ s: QuickSuggestion) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: NoopMetrics.insetRadius, style: .continuous)
                .fill(theme.surface).frame(width: 48, height: 48)
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.insetRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(StrengthDisplay.name(s.exercise)).font(StrandFont.body).foregroundStyle(theme.ink)
                (Text(MuscleAtlas.name(s.muscle)) + Text(verbatim: " · ") + Text("fresh")
                    + (lastTimeText(s).map { Text(verbatim: " · ") + Text("last time \($0)") } ?? Text(verbatim: "")))
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: 8)
            Button { Task { await addExercises([s.exercise]) } } label: {
                Text("Add").font(StrandFont.caption).foregroundStyle(theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add \(StrengthDisplay.name(s.exercise))"))
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(theme.hairline) }
    }

    /// «82,5 kg × 8» — the last logged weight/reps for a suggestion, plain data (not a localized phrase,
    /// same convention as `previousText`).
    private func lastTimeText(_ s: QuickSuggestion) -> String? {
        guard let w = s.lastWeightKg, let r = s.lastReps else { return nil }
        return "\(massText(w)) × \(r)"
    }

    /// Freshness suggestions (FER-762): the same fetch-and-expand `MuscleFatigueMap` recipe as the muscle
    /// map, over the trailing 84 days — the top 3 fresh muscles, one exercise each (preferring one the
    /// user has history for), plus a note naming the single most-loaded muscle the picks are avoiding.
    private func loadFreshSuggestions() async {
        let cal = Calendar.current
        guard let since = cal.date(byAdding: .day, value: -84, to: cal.startOfDay(for: Date())) else { return }
        let sinceTs = Int(since.timeIntervalSince1970)
        async let eventsTask = model.repo.muscleSetEvents(sinceTs: sinceTs)
        async let exercisesTask = model.repo.allExercises()
        async let historyTask = model.repo.recentWorkSets(sinceTs: sinceTs)
        let (events, exercises, history) = await (eventsTask, exercisesTask, historyTask)
        let loads = MuscleFatigueMap.loads(events: events)
        let historyIds = Set(history.map(\.exerciseId))

        // Same engine call `MuscleMapScreen` reads (`.readyMuscles`), not a hand-rolled filter/sort: it
        // already gates fresh muscles behind systemic recovery (a red-recovery day suggests nothing).
        let freshMuscles = MuscleFatigueMap.recommendation(loads: loads, recovery: recovery).readyMuscles
        var picked: [(exercise: Exercise, muscle: String)] = []
        var usedExerciseIds: Set<String> = []
        for muscle in freshMuscles {
            guard picked.count < 3 else { break }
            let candidates = exercises.filter { $0.primaryMuscles.contains(muscle) && !usedExerciseIds.contains($0.id) }
            guard let ex = candidates.first(where: { historyIds.contains($0.id) }) ?? candidates.first else { continue }
            usedExerciseIds.insert(ex.id)
            picked.append((exercise: ex, muscle: muscle))
        }
        // The per-exercise "last time" lookups are independent JOINs — run them concurrently, not one
        // await per loop iteration.
        freshSuggestions = await withTaskGroup(of: QuickSuggestion.self) { group in
            for (ex, muscle) in picked {
                group.addTask {
                    let last = await self.model.repo.exerciseHistory(exerciseId: ex.id).last
                    return QuickSuggestion(exercise: ex, muscle: muscle, lastWeightKg: last?.weightKg, lastReps: last?.reps)
                }
            }
            var results: [QuickSuggestion] = []
            for await s in group { results.append(s) }
            // Restore freshness order (most-fresh-first) — a TaskGroup completes in arbitrary order.
            let order = Dictionary(uniqueKeysWithValues: picked.enumerated().map { ($1.exercise.id, $0) })
            return results.sorted { (order[$0.exercise.id] ?? 0) < (order[$1.exercise.id] ?? 0) }
        }
        loadedMuscle = loads.filter { $0.state == .loaded }.max { $0.load < $1.load }?.muscle
    }

    /// Add one or more exercises to the ad-hoc session (from a suggestion or the library picker), seeding
    /// each from its last logged set when there's history. The empty state falls away on its own once
    /// `session.runs` isn't empty.
    private func addExercises(_ picks: [Exercise]) async {
        let lasts = await withTaskGroup(of: (String, Double?, Int?).self) { group in
            for ex in picks {
                group.addTask {
                    let last = await self.model.repo.exerciseHistory(exerciseId: ex.id).last
                    return (ex.id, last?.weightKg, last?.reps)
                }
            }
            var results: [String: (Double?, Int?)] = [:]
            for await (id, weight, reps) in group { results[id] = (weight, reps) }
            return results
        }
        for ex in picks {
            let last = lasts[ex.id]
            session.addExercise(ex, lastWeightKg: last?.0, lastReps: last?.1)
        }
    }

    /// Discard the empty ad-hoc session (its «Descartar» pill, FER-762) — nothing logged yet, so no
    /// confirmation is needed (unlike `discardFooter`, which guards a session with real data).
    private func discardEmptySession() {
        model.endStrengthSession(save: false)
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

    // MARK: Inline helpers (formatting / focus / actions)

    /// Tap-ANTERIOR: copy last time into this row (weight/reps/distance; a time set captures live).
    private func prefillTapped(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun) {
        session.prefillPrevious(exercise: ei, set: si)
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
        guard let cur = activeCell, let idx = cells.firstIndex(of: cur) else { activeCell = nil; return }
        activeCell = idx + 1 < cells.count ? cells[idx + 1] : nil
    }

    private func distanceText(_ meters: Double) -> String {
        let v = imperial ? meters / Self.metersPerMile : meters / 1000
        return String(format: "%.2f %@", v, imperial ? "mi" : "km")
    }

    private func typeWord(_ t: ExerciseType) -> LocalizedStringKey {
        switch t {
        case .weightReps: return "Weight"
        case .bodyweight: return "Bodyweight"
        case .time:       return "Time"
        case .distance:   return "Distance"
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
            Image(systemName: "checkmark.seal.fill").font(StrandFont.glyph(.empty))
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
            // Keep the way back: tapping an exercise re-focuses its rows to edit (or add sets).
            if !session.activeExercises.isEmpty {
                planNavigator.padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Summary phase (the post-session receipt · FER-409, redesigned per «Flujo Entrenar v3 · 1l»)

    @ViewBuilder
    private func summaryPhase(_ s: StrengthSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            receiptHeader(s)
            if s.watchRecorded { receiptWatchOrigin }
            receiptHeadline(s)
            receiptStats(s)
            if let kcal = s.energyKcal { receiptDietBlock(kcal: kcal, estimated: s.energySource == .estimated) }
            if let c = s.comparison { receiptComparison(s, c) }

            if !s.prs.isEmpty {
                receiptRecords(s.prs)
            } else if s.isFirstTime {
                Text("First time logging these. From here on you'll see your progress.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !s.exercises.isEmpty { receiptExercises(s.exercises) }

            // Conserved from FER-409 (not in the 1l mock, but it's the only path to the fatigue map).
            if !s.muscles.isEmpty { summaryMuscles(s.muscles) }

            if let band = s.costBand { receiptCost(band, tomorrowPct: s.costTomorrowPct) }

            Button { shareReceipt = ShareRef() } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
                    .font(StrandFont.subhead).fontWeight(.medium)
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: NoopMetrics.ctaRadius, style: .continuous)
                        .strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.top, 6)

            Button { model.closeStrengthSummary() } label: {
                Text("Done")
                    .font(InstrumentoType.grotesk(15, weight: .bold)).tracking(0.3)
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.ctaRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { playReceiptCountUp() }
    }

    /// The 0→value count-up (FER-716): the numerals roll up over 750 ms ONLY the first time the receipt
    /// appears (at save). `receiptCountUpPlayed` lives on the session, so re-opening (or re-scrolling)
    /// renders the final values immediately. Reduce Motion skips the roll entirely.
    private func playReceiptCountUp() {
        if session.receiptCountUpPlayed || reduceMotion {
            receiptCountUp = true
        } else {
            withAnimation(StrandMotion.countUp) { receiptCountUp = true }
        }
        session.receiptCountUpPlayed = true
    }

    /// «Sesión guardada · jue 2 jul» + the data-origin dot for the energy figure (strap Keytel vs MET).
    private func receiptHeader(_ s: StrengthSummary) -> some View {
        HStack(spacing: 8) {
            Text("\(String(localized: "Session saved")) · \(receiptDate(s.endTs))")
                .groteskOverline().foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 8)
            // FER-742: when the watch recorded, its origin line replaces the iPhone's energy-origin dot below.
            if let src = s.energySource, !s.watchRecorded { originRow(src) }
        }
    }

    /// FER-742: the receipt's origin line when the Apple Watch recorded the real FC/kcal and saved the
    /// workout to Health — shown instead of the iPhone's energy-origin dot.
    private var receiptWatchOrigin: some View {
        HStack(spacing: 5) {
            Image(systemName: "applewatch").font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text("Heart rate and calories from Apple Watch, saved to Health")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func receiptDate(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts))
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// The data-origin row on the receipt (FER-716): where this session's energy figure came from — the
    /// strap (Keytel) or an estimate (MET fallback).
    private func originRow(_ src: EnergySource) -> some View {
        HStack(spacing: 5) {
            Circle().fill(src == .bandCalculated ? theme.originBand : theme.originComputed)
                .frame(width: 6, height: 6)
            Text(src == .bandCalculated ? "Band + calculated" : "Estimated")
                .font(.system(size: 10)).foregroundStyle(theme.inkTertiary) // token-exempt: microtexto <11pt
        }
        .accessibilityElement(children: .combine)
    }

    /// The editorial headline: «{rutina}, hecha.» + the session's one honest achievement.
    private func receiptHeadline(_ s: StrengthSummary) -> some View {
        (Text("\(s.routineName), done.") + Text(verbatim: "\n") + Text(verbatim: achievementLine(s)))
            .font(InstrumentoType.groteskReceiptHeadline)
            .tracking(InstrumentoType.groteskReceiptHeadlineTracking)
            .foregroundStyle(theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// One achievement, best available first: new records → more volume than last time → first time →
    /// the plain set count. Never invents a comparison that isn't there.
    private func achievementLine(_ s: StrengthSummary) -> String {
        if s.prs.count == 1 { return String(localized: "A new personal record.") }
        if s.prs.count > 1 { return String(localized: "\(s.prs.count) new personal records.") }
        if let pct = s.comparison?.volumeDeltaPct(s.volumeKg), pct >= 1 {
            return String(localized: "+\(pct)% volume vs your last one.")
        }
        if s.isFirstTime { return String(localized: "First time with this routine.") }
        return String(localized: "\(s.setCount) sets logged.")
    }

    /// The four receipt metrics (duración · volumen · strain · kcal). Strain is the one colored datum;
    /// with no strain but captured HR, the avg-HR slot proves the strap was read (FER-498). No dashes:
    /// a metric without data simply isn't rendered.
    private func receiptStats(_ s: StrengthSummary) -> some View {
        let cells = Group {
            receiptStat("Duration", value: Self.clock(s.durationS), zero: "0:00")
            receiptStat("Volume", value: plateNumber(displayWeight(s.volumeKg)), zero: "0",
                        unit: UnitFormatter.massUnit(units))
            if let strain = s.strain {
                receiptStat("Strain", value: Self.strainText(strain), zero: Self.strainText(0),
                            color: theme.dataStrain)
            } else if let avgHr = s.avgHr {
                receiptStat("Avg HR", value: "\(avgHr)", zero: "0", unit: String(localized: "bpm"))
            }
            if let kcal = s.energyKcal {
                receiptStat(s.energySource == .estimated ? "Calories · estimated" : "Calories",
                            value: "\(Int(kcal.rounded()))", zero: "0", unit: "kcal")
            }
        }
        return Group {
            if reflow {
                VStack(alignment: .leading, spacing: 12) { cells }
            } else {
                HStack(alignment: .top, spacing: 20) { cells; Spacer(minLength: 0) }
            }
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    private func receiptStat(_ label: LocalizedStringKey, value: String, zero: String,
                             unit: String? = nil, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).groteskOverline(small: true).foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(receiptCountUp ? value : zero)
                    .font(InstrumentoType.groteskReceiptStat)
                    .tracking(InstrumentoType.groteskReceiptStatTracking)
                    .monospacedDigit().contentTransition(.numericText())
                    .foregroundStyle(color ?? theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let unit { Text(unit).font(StrandFont.caption).foregroundStyle(theme.inkTertiary) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The Diet block (decision: link ONLY, no target-% math): the session's kcal in prose + «Dieta →».
    /// Until the Diet section lands, the link parks the user on «Entrenar» (where it will live).
    private func receiptDietBlock(kcal: Double, estimated: Bool) -> some View {
        Button {
            tabRouter.select(.train)
            model.closeStrengthSummary()
        } label: {
            HStack(spacing: 10) {
                (Text(verbatim: "\(Int(kcal.rounded())) kcal ").fontWeight(.semibold).foregroundColor(theme.ink)
                    + Text(estimated ? "estimated from this session." : "logged from this session.")
                        .foregroundColor(theme.inkSecondary))
                    .font(StrandFont.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 3) {
                    Text("Diet").font(StrandFont.caption).fontWeight(.semibold)
                    Image(systemName: "arrow.right").font(StrandFont.glyph(.chevron, weight: .semibold))
                }
                .foregroundStyle(theme.dataRecovery)
                .fixedSize()
            }
            .padding(.leading, 12).padding(.trailing, 12).padding(.vertical, 9)
            .patternBlock(theme, bar: theme.dataStrain)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// «Contra tu última {rutina}» — three bars (volumen / series / duración) against the previous
    /// session of the SAME routine. The tick marks last time; the bar is this session.
    private func receiptComparison(_ s: StrengthSummary, _ c: StrengthSummary.Comparison) -> some View {
        let volDelta: String = {
            guard let pct = c.volumeDeltaPct(s.volumeKg) else { return "=" }
            return pct == 0 ? "=" : (pct > 0 ? "+\(pct)%" : "−\(-pct)%")
        }()
        let setsDelta = s.setCount == c.prevSetCount
            ? "\(s.setCount) = \(c.prevSetCount)"
            : (s.setCount > c.prevSetCount ? "+\(s.setCount - c.prevSetCount)" : "−\(c.prevSetCount - s.setCount)")
        let minDiff = Int((Double(s.durationS - c.prevDurationS) / 60).rounded())
        let durDelta = minDiff == 0 ? "=" : (minDiff > 0
            ? String(localized: "+\(minDiff) min") : String(localized: "−\(-minDiff) min"))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Against your last \(s.routineName)").groteskOverline().foregroundStyle(theme.inkTertiary)
            comparisonRow("Volume", current: s.volumeKg, prev: c.prevVolumeKg,
                          delta: volDelta, positive: s.volumeKg > c.prevVolumeKg)
            comparisonRow("Sets", current: Double(s.setCount), prev: Double(c.prevSetCount),
                          delta: setsDelta, positive: s.setCount > c.prevSetCount)
            comparisonRow("Duration", current: Double(s.durationS), prev: Double(c.prevDurationS),
                          delta: durDelta, positive: false, neutral: true)
        }
    }

    /// One comparison bar: label · track with this session's fill + an ink tick at last time · delta.
    /// Duration is `neutral` (longer isn't better) — gray fill, quiet delta.
    private func comparisonRow(_ label: LocalizedStringKey, current: Double, prev: Double,
                               delta: String, positive: Bool, neutral: Bool = false) -> some View {
        let maxV = max(current, prev, 1)
        return HStack(spacing: 10) {
            Text(label).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline)
                    Capsule().fill(neutral ? theme.hairlineStrong : theme.dataRecovery)
                        .opacity(neutral || positive ? 1 : 0.75)
                        .frame(width: max(4, w * (current / maxV)))
                    Rectangle().fill(theme.ink).frame(width: 2, height: 14)
                        .offset(x: min(w - 2, max(0, w * (prev / maxV) - 1)))
                }
            }
            .frame(height: 8)
            Text(delta).font(StrandFont.caption).monospacedDigit()
                .foregroundStyle(positive ? theme.positiveText : theme.inkSecondary)
                .frame(width: 56, alignment: .trailing)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(delta))
    }

    /// The records card — the one `surface` card of the receipt. Each row frames the beaten record:
    /// «100 → 102,5 kg».
    private func receiptRecords(_ prs: [StrengthSummary.PR]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "star").font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(theme.dataRecovery)
                Text(prs.count == 1 ? String(localized: "A personal record")
                     : String(localized: "\(prs.count) personal records"))
                    .font(StrandFont.subhead).fontWeight(.semibold).foregroundStyle(theme.ink)
            }
            .padding(.bottom, 4)
            ForEach(Array(prs.enumerated()), id: \.element.id) { i, pr in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    (Text(verbatim: pr.exercise) + Text(verbatim: " · ") + Text(Self.prMetricLabel(pr.metric)))
                        .font(StrandFont.caption).foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    (Text(verbatim: prPriorText(pr)).foregroundColor(theme.inkTertiary)
                        + Text(verbatim: " → ")
                        + Text(verbatim: prValue(pr)).fontWeight(.semibold).foregroundColor(theme.ink))
                        .font(StrandFont.caption).monospacedDigit()
                }
                .frame(minHeight: 38)
                .overlay(alignment: .bottom) {
                    if i < prs.count - 1 { Rectangle().fill(theme.hairline).frame(height: 1) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    /// «Por ejercicio»: one quiet row per exercise — sets · top datum · trend vs «la última vez».
    private func receiptExercises(_ lines: [StrengthSummary.ExerciseLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("By exercise").groteskOverline().foregroundStyle(theme.inkTertiary)
                .padding(.bottom, 2)
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                HStack(spacing: 12) {
                    Text(line.name).font(StrandFont.subhead).foregroundStyle(theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(exerciseLineDetail(line))
                        .font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkSecondary)
                    exerciseTrendGlyph(line.trend)
                }
                .frame(minHeight: 40)
                .overlay(alignment: .bottom) {
                    if i < lines.count - 1 { Rectangle().fill(theme.hairline).frame(height: 1) }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func exerciseLineDetail(_ line: StrengthSummary.ExerciseLine) -> String {
        let top: String? = {
            if let w = line.topWeightKg, w > 0 { return massText(w) }
            if let t = line.topTimeS, t > 0 { return Self.clock(t) }
            if let d = line.topDistanceM, d > 0 { return distanceText(d) }
            return nil
        }()
        guard let top else { return String(localized: "\(line.setCount) sets") }
        return String(localized: "\(line.setCount) sets · \(top)")
    }

    @ViewBuilder private func exerciseTrendGlyph(_ trend: Int?) -> some View {
        switch trend {
        case .some(1):
            Image(systemName: "arrow.up").font(StrandFont.glyph(.chevron, weight: .semibold))
                .foregroundStyle(theme.positiveText)
                .accessibilityLabel(Text("Up vs last time"))
        case .some(-1):
            Image(systemName: "arrow.down").font(StrandFont.glyph(.chevron, weight: .semibold))
                .foregroundStyle(theme.inkTertiary)
                .accessibilityLabel(Text("Down vs last time"))
        case .some:
            Text(verbatim: "=").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .accessibilityLabel(Text("Same as last time"))
        case nil:
            Color.clear.frame(width: 12, height: 1)
        }
    }

    /// Recovery cost + tomorrow's projection (conserves FER-409/442) as a «patrón» block whose left bar
    /// wears the band's color.
    private func receiptCost(_ band: SessionRecoveryCost.Band, tomorrowPct: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recovery cost").groteskOverline(small: true).foregroundStyle(theme.inkTertiary)
            Text(Self.bandLabel(band)).font(StrandFont.subhead).fontWeight(.semibold)
                .foregroundStyle(bandColor(band))
            Text(Self.bandDetail(band)).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Tomorrow's projection given today's cost (FER-442): the prose in ink, the datum in
            // recovery green. Hidden when there isn't ~2 weeks of base (the engine returns nil).
            if let pct = tomorrowPct {
                (Text("Tomorrow, if you rest well, you should be around ").foregroundColor(theme.inkSecondary)
                    + Text("~\(pct)%").foregroundColor(theme.positiveText).fontWeight(.semibold))
                    .font(StrandFont.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Estimate · you decide").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .patternBlock(theme, bar: bandColor(band))
        .accessibilityElement(children: .combine)
    }

    /// The beaten record, for the «prior → new» framing. Volume compares totals (kg), matching `prValue`.
    private func prPriorText(_ pr: StrengthSummary.PR) -> String {
        switch pr.metric {
        case .maxWeight: return plateNumber(displayWeight(pr.priorValueKg ?? 0))
        case .maxReps:   return "\(pr.priorReps ?? 0)"
        case .maxVolume: return plateNumber(displayWeight(pr.priorValueKg ?? 0))
        }
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
        // Volume frames TOTALS («2.070 → 2.160 kg»), matching `prPriorText`.
        case .maxVolume: return massText((pr.valueKg ?? 0) * Double(pr.reps ?? 0))
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

    // MARK: The «change exercise» bridge (hosted by the complete footer)

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
                        .font(StrandFont.glyph(.inline))
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
                            Image(systemName: "arrow.up").font(StrandFont.glyph(.inline, weight: .semibold))
                                .foregroundStyle(theme.inkSecondary)
                        }
                        .buttonStyle(.plain).accessibilityLabel(Text("Move \(run.name) earlier"))
                    }
                    Button { withAnimation(.snappy) { session.skipExercise(index) } } label: {
                        Image(systemName: "forward.end").font(StrandFont.glyph(.inline, weight: .semibold))
                            .foregroundStyle(theme.inkSecondary)
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Skip \(run.name)"))
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
    }

    // MARK: Small builders

    private func stepper(system: String, size: CGFloat = 42, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: size > 38 ? 22 : 18, weight: .regular)) // token-exempt: tamaño de glifo condicional
                .foregroundStyle(theme.inkSecondary)
                .frame(width: size, height: size)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func finishTapped() {
        confirmFinish = true
    }

    private func restChipText(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 { return String(localized: "Rest \(seconds / 60) min") }
        return String(localized: "Rest \(seconds)s")
    }

    // MARK: Units / formatting

    private func displayWeight(_ kg: Double) -> Double { imperial ? UnitFormatter.kgToPounds(kg) : kg }
    private func massText(_ kg: Double) -> String { massString(kg, units: units) }

    static func clock(_ seconds: Int) -> String { SessionClock.format(seconds) }
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

// MARK: - Live BPM dot (FER-716)

/// The one always-on pulse of the app: the session header's live-BPM dot, breathing at 1.1 s. Falls
/// back to a static dot under Reduce Motion (the preset does not self-disable).
private struct BpmPulseDot: View {
    let color: Color
    var animated: Bool = true
    @State private var pulsing = false
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .scaleEffect(animated && pulsing ? 1.35 : 1.0)
            .opacity(animated && pulsing ? 0.65 : 1.0)
            .onAppear { if animated { withAnimation(StrandMotion.livePulse) { pulsing = true } } }
            .accessibilityHidden(true)
    }
}
#endif
