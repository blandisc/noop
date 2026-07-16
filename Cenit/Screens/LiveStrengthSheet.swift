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
        /// Perceived effort (RPE), 6-10 with half-steps (FER-930). Optional: marking a set done never
        /// requires it. Set from the RPE sheet, independent of `done`.
        var rpe: Double? = nil
        /// Set-scoped note text (FER-932), written from the note sheet with «Guardar en: Solo la serie N».
        /// nil = no set-scope note; the exercise-scope note lives on `ExerciseRun.note` instead.
        var note: String? = nil
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
        /// «Volver a X» was tapped for this exercise (FER-835). Persisted with the session at save so
        /// the progression cycle treats it as neither hit nor miss; carried by the crash snapshot.
        var raiseOptedOut: Bool = false
        /// Superset grouping (FER-931), seeded from `RoutineExercise.supersetGroup`: the same `Int`
        /// within a session = one superset (round-robin, rest only after the last member). `nil` =
        /// standalone. `addExercise`/`replaceExercise` always seed `nil` — an ad-hoc/swapped exercise
        /// is never auto-grouped into a superset it wasn't authored into.
        var supersetGroup: Int? = nil
        /// Exercise-scoped note text (FER-932), written from the «✎ Nota» chip with «Guardar en: Este
        /// ejercicio». nil = no note. A set-scope note lives on the individual `WorkingSet.note` instead.
        var note: String? = nil
        /// Whether this run (or any of its sets) carries a note (FER-932) — drives the chip's «con nota» state.
        var hasNote: Bool { (note?.isEmpty == false) || sets.contains { $0.note?.isEmpty == false } }

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

    // MARK: Superset (FER-931 — the grouping was authored in the routine; here it only reads it)

    /// The consecutive span of run indices sharing `index`'s (non-nil) `supersetGroup` — the adjacency +
    /// equality rule mirrors `RoutineEditorScreen.reorderBlocks` (that one only scans forward from a block
    /// start; this one spans both directions since `index` can be any member). `[index]` when the run has
    /// no group or the span is a single exercise — so standalone exercises are always their own one-member
    /// "group" and every call site can treat `count <= 1` as "not a superset".
    func supersetMembers(at index: Int) -> [Int] {
        guard runs.indices.contains(index), let g = runs[index].supersetGroup else { return [index] }
        var lo = index
        while lo - 1 >= 0, runs[lo - 1].supersetGroup == g { lo -= 1 }
        var hi = index
        while hi + 1 < runs.count, runs[hi + 1].supersetGroup == g { hi += 1 }
        return Array(lo...hi)
    }

    /// Whether the run at `index` is part of a real (2+) superset span.
    func isInSuperset(_ index: Int) -> Bool { supersetMembers(at: index).count > 1 }

    /// «A», «B» … by order of appearance of the group among `runs` — the letter half of the A1/A2 badge.
    /// nil for a standalone exercise.
    func supersetLetter(for index: Int) -> String? {
        guard runs.indices.contains(index), let g = runs[index].supersetGroup else { return nil }
        var seen: [Int] = []
        for run in runs {
            if let rg = run.supersetGroup, !seen.contains(rg) { seen.append(rg) }
        }
        guard let ordinal = seen.firstIndex(of: g) else { return nil }
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let idx = letters.index(letters.startIndex, offsetBy: ordinal % letters.count)
        return String(letters[idx])
    }

    /// How many `.work` series the run at `index` carries — the "rounds" a superset member cycles through.
    func supersetRounds(at index: Int) -> Int {
        guard runs.indices.contains(index) else { return 0 }
        return runs[index].sets.filter { $0.kind == .work }.count
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
        let justCompletedKind = runs[currentIndex].sets[i].kind
        let doneTs = Int(now.timeIntervalSince1970)
        runs[currentIndex].sets[i].done = true
        runs[currentIndex].sets[i].doneTs = doneTs

        // FER-931: superset round-robin — A1 done moves straight to A2's same round, no rest in between.
        // Warm-ups don't participate; only `.work` cycles the group. A standalone exercise (group of one)
        // takes this branch's condition to false immediately, so its rest/advance is byte-for-byte the
        // pre-931 path below.
        let group = supersetMembers(at: currentIndex)
        if justCompletedKind == .work, group.count > 1,
           let posInGroup = group.firstIndex(of: currentIndex), posInGroup < group.count - 1 {
            let nextMember = group[posInGroup + 1]
            if !runs[nextMember].skipped, runs[nextMember].sets.indices.contains(i),
               !runs[nextMember].sets[i].done, runs[nextMember].sets[i].kind == .work {
                phase = .capturing
                clearRest()
                timerStart = nil
                currentIndex = nextMember
                runs[nextMember].currentSet = i
                return
            }
        }

        // FER-715: rest is resolved per set — the active set's own override, else the exercise's default.
        let rest = runs[currentIndex].effectiveRest(forSet: i)
        computeRestTarget(rest: rest, doneTs: doneTs, restingHR: restingHR, maxHR: maxHR)
        startRest(seconds: rest.seconds, now: now)
        advanceToNextPending()
    }

    /// Record (or clear, passing nil) the perceived-effort rating for one set (FER-930). Entirely
    /// independent of `registerCurrentSet`/`done` — the RPE sheet is opened from the table's RPE cell,
    /// never blocks marking a set, and can be set on a set that isn't done yet.
    func setRPE(exercise runId: String, set setId: String, rpe: Double?) {
        guard let runIdx = runs.firstIndex(where: { $0.id == runId }),
              let setIdx = runs[runIdx].sets.firstIndex(where: { $0.id == setId }) else { return }
        runs[runIdx].sets[setIdx].rpe = rpe
    }

    /// Write the exercise-scope note from the «✎ Nota» chip → `NoteSheet` (FER-932). Independent of
    /// `done`/rest — opening or saving the sheet never touches `restEndsAt`, so a running rest keeps
    /// counting behind it.
    func setExerciseNote(exercise runId: String, text: String?) {
        guard let runIdx = runs.firstIndex(where: { $0.id == runId }) else { return }
        runs[runIdx].note = text
    }

    /// Write the set-scope note («Guardar en: Solo la serie N») for one working set (FER-932).
    func setSetNote(exercise runId: String, set setId: String, text: String?) {
        guard let runIdx = runs.firstIndex(where: { $0.id == runId }),
              let setIdx = runs[runIdx].sets.firstIndex(where: { $0.id == setId }) else { return }
        runs[runIdx].sets[setIdx].note = text
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

    /// Insert an exercise right after the currently active one (FER-935): same seeding as `addExercise`,
    /// but the run lands at `currentIndex + 1` instead of the end, and the guided focus stays on the
    /// active exercise (no `currentIndex` reassignment — the insert always lands after it, so it never
    /// needs the reindex `removeExercise`/`moveExerciseEarlier` do). Calling this once per pick with the
    /// picks in reverse order keeps a multi-pick batch contiguous and in the user's chosen order, since
    /// each call lands its run at the same `currentIndex + 1` slot, pushing the previous insert one further.
    func insertExerciseAfterCurrent(_ exercise: Exercise, lastWeightKg: Double? = nil, lastReps: Int? = nil) {
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
        runs.insert(run, at: min(currentIndex + 1, runs.count))
    }

    /// Pair this exercise with the NEXT one as a superset (canvas pass 2026-07-15, menú «Superserie
    /// con el siguiente») — or unpair them if they already share a group. Runtime-only, same contract
    /// as the routine-seeded grouping (FER-931).
    func toggleSupersetWithNext(_ ei: Int) {
        guard runs.indices.contains(ei), runs.indices.contains(ei + 1) else { return }
        if let g = runs[ei].supersetGroup, runs[ei + 1].supersetGroup == g {
            runs[ei].supersetGroup = nil
            runs[ei + 1].supersetGroup = nil
        } else {
            let g = (runs.compactMap(\.supersetGroup).max() ?? 0) + 1
            runs[ei].supersetGroup = g
            runs[ei + 1].supersetGroup = g
        }
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

    /// Swap the exercise at `ei` for a different movement mid-session (FER-894 · «Cómo llego a Cambiar»),
    /// KEEPING the sets already marked `done` (they're real logged work) and re-seeding only the not-yet-done
    /// sets with the new exercise's prescription. The run keeps its slot, its rest configuration and its id
    /// (so the table row and focus are undisturbed); it takes on the new exercise's identity (exerciseId /
    /// name / type). Any pending raise proposal is dropped — that plan belonged to the old movement. Self-
    /// contained: it only rewrites this one run, leaving the rest of the session engine untouched.
    func replaceExercise(at ei: Int, with exercise: Exercise, lastWeightKg: Double? = nil, lastReps: Int? = nil) {
        guard runs.indices.contains(ei) else { return }
        let old = runs[ei]
        let usesReps = exercise.type == .weightReps || exercise.type == .bodyweight
        let seedWeight = lastWeightKg ?? 0
        let seedReps = usesReps ? (lastReps ?? 8) : 0
        // Keep the done sets verbatim; re-seed the pending ones (same count) with the new prescription.
        let doneSets = old.sets.filter { $0.done }
        let pendingCount = max(old.sets.count - doneSets.count, doneSets.isEmpty ? 1 : 0)
        let reseeded = (0..<pendingCount).map { _ in
            WorkingSet(id: UUID().uuidString, weightKg: seedWeight, reps: seedReps, done: false)
        }
        let newSets = doneSets + reseeded
        runs[ei] = ExerciseRun(
            id: old.id, exerciseId: exercise.id,
            name: StrengthDisplay.name(exercise), type: exercise.type,
            restSeconds: old.restSeconds, restMode: old.restMode,
            hrRestReference: old.hrRestReference, hrRestValue: old.hrRestValue,
            lastWeightKg: lastWeightKg, lastReps: lastReps,
            lastTimeS: nil, lastDistanceM: nil,
            sets: newSets, currentSet: min(doneSets.count, max(0, newSets.count - 1)),
            skipped: false)
        if ei == currentIndex { phase = .capturing; clearRest(); timerStart = nil }
    }

    /// Remove an exercise from the session entirely (FER-894 menu «Remove from session»). Unlike
    /// `skipExercise` (which keeps it, greyed, in the plan), this drops the run. Never empties the session —
    /// the last remaining exercise can only be skipped, not removed. Re-focuses if the current one went.
    func removeExercise(at ei: Int) {
        guard runs.indices.contains(ei), runs.count > 1 else { return }
        let wasCurrent = ei == currentIndex
        runs.remove(at: ei)
        if ei < currentIndex { currentIndex -= 1 }
        currentIndex = min(currentIndex, runs.count - 1)
        if wasCurrent { phase = .capturing; clearRest(); timerStart = nil; advanceToNextPending(fromStart: true) }
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
        // FER-931: a group's last member just rested — the next round belongs to the FIRST member, not a
        // continuation of the last one. Priority: the group's first member's earliest pending round, before
        // falling through to the plain "rest of this exercise" / "scan the plan" scan below. A standalone
        // exercise's `supersetMembers` is `[currentIndex]` (count 1), so this is a no-op for it.
        if !fromStart, runs.indices.contains(currentIndex), !runs[currentIndex].skipped {
            let group = supersetMembers(at: currentIndex)
            if group.count > 1, let first = group.first, runs.indices.contains(first),
               !runs[first].skipped, let next = runs[first].sets.firstIndex(where: { !$0.done }) {
                currentIndex = first
                runs[first].currentSet = next
                return
            }
        }
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
    func buildForSave(deviceId: String?, endTs: Int)
        -> (StrengthSession, [SetEntry], progressionOptOuts: Set<String>, notes: [ExerciseNote]) {
        let session = StrengthSession(id: id, routineId: routineId, startTs: startTs,
                                      endTs: endTs, deviceId: deviceId)
        var entries: [SetEntry] = []
        var optedOut: Set<String> = []
        var notes: [ExerciseNote] = []
        var position = 0
        for run in runs where !run.skipped {
            // FER-835: the exercise's «Volver a X» mark rides with the save — only if something was
            // actually logged (no saved sets → no session rows to mark).
            if run.raiseOptedOut, run.sets.contains(where: \.done) { optedOut.insert(run.exerciseId) }
            if let text = run.note, !text.isEmpty {
                notes.append(ExerciseNote(sessionId: id, exerciseId: run.exerciseId, text: text, ts: endTs))
            }
            for (setIndex, set) in run.sets.enumerated() {
                if let text = set.note, !text.isEmpty {
                    notes.append(ExerciseNote(sessionId: id, exerciseId: run.exerciseId,
                                              setPosition: setIndex, text: text, ts: endTs))
                }
                guard set.done else { continue }
                let f = SetCapture.fields(type: run.type, weightKg: set.weightKg, reps: set.reps,
                                          timeS: set.timeS, distanceM: set.distanceM)
                entries.append(SetEntry(id: set.id, sessionId: id, exerciseId: run.exerciseId,
                                        position: position, kind: set.kind,
                                        weightKg: f.weightKg, reps: f.reps, timeS: f.timeS, distanceM: f.distanceM,
                                        done: true, ts: set.doneTs ?? endTs, rpe: set.rpe))
                position += 1
            }
        }
        return (session, entries, optedOut, notes)
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
                            rest: s.rest, kind: s.kind, rpe: s.rpe, note: s.note)
                    },
                    currentSet: run.currentSet, skipped: run.skipped,
                    raiseOptedOut: run.raiseOptedOut ? true : nil,
                    supersetGroup: run.supersetGroup, note: run.note)
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
                                       rest: s.rest, kind: s.kind, rpe: s.rpe, note: s.note)
                        },
                        currentSet: r.currentSet, skipped: r.skipped,
                        raiseOptedOut: r.raiseOptedOut ?? false,
                        supersetGroup: r.supersetGroup, note: r.note)
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
                let weight = (type == .weightReps ? slot.raise?.toKg : nil) ?? p.weightKg ?? lastWeight ?? 0
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
                               proposedRaise: type == .weightReps ? slot.raise : nil,
                               supersetGroup: slot.re.supersetGroup)
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
    /// The set whose RPE sheet is open (FER-930), tapped from the table's RPE cell. nil = closed.
    @State private var rpeTarget: RPETarget?
    /// The exercise whose note sheet is open (FER-932), tapped from the «✎ Nota» chip. nil = closed.
    @State private var noteTarget: NoteTarget?
    /// This session's prior notes for `noteTarget.exerciseId` (across other sessions), loaded when the
    /// sheet opens — «NOTAS ANTERIORES». nil = still loading / not opened; [] = loaded, honestly empty.
    @State private var noteHistory: [ExerciseNote]?

    /// The empty «Rápido de fuerza» state (FER-762): no routine, no exercises added yet. Its search field
    /// opens `ExerciseLibraryScreen` in ADD mode; the freshness suggestions load once when this state
    /// appears. `nil` = not loaded yet (the `.task` hasn't resolved); `[]` = loaded, honestly no fresh
    /// muscle to suggest — one optional instead of a separate "have I tried yet" flag.
    @State private var showLibraryPicker = false
    /// FER-938: the id of a set just appended via «+ Serie», so its row shows the «COPIADA DE LA N» hint +
    /// dashed border until it's logged (the guard `!set.done` retires the hint the moment it's marked).
    @State private var copiedSetId: String?
    /// FER-936: which exercise's «≡» reorder handle is momentarily emphasised (ember) after picking
    /// «Reordenar» from its menu — a discoverability nudge toward the drag that already reorders.
    @State private var reorderHint: Int?
    /// «Modo mover» (FER-933): every exercise collapses to a compressed row and a `DragGesture` on each
    /// row shows the handoff's «SOLTAR AQUÍ · POSICIÓN N» drop zone. Entered by long-press on any rail row
    /// or the menu's «Reordenar» item; exits via «Listo». A view-layer toggle only — the model is untouched.
    @State private var reorderMode = false
    /// Canvas pass 2026-07-15 (menú «Progresión»): which exercise's progression mini-sheet is open.
    struct ProgressionEditTarget: Identifiable { let id: Int }
    @State private var progressionEdit: ProgressionEditTarget?
    /// The backing routine's exercises, keyed by `RoutineExercise.id` (== `ExerciseRun.id`) — the menu's
    /// progression subtitle and the mini-sheet read/write here; loaded once per routine.
    @State private var routineREs: [String: RoutineExercise] = [:]
    /// The exercise index currently being dragged in modo mover, and the slot its drop would land on.
    /// nil/nil when nothing is mid-drag.
    @State private var reorderDraggingIndex: Int?
    @State private var reorderTargetIndex: Int?

    /// FER-936: the breathing ember halo behind the active exercise's «···». A stroked ring (not a blurred
    /// shadow, per DNA) that pulses opacity + scale; a steady faint ring under Reduce Motion.
    private struct TapRing: View {
        let color: Color
        let animated: Bool
        @State private var on = false
        var body: some View {
            Circle()
                .strokeBorder(color, lineWidth: 2)
                .opacity(on ? 0.10 : 0.28)
                .scaleEffect(on ? 1.0 : 0.82)
                .frame(width: 30, height: 30)
                .onAppear { if animated { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { on = true } } }
        }
    }
    @State private var freshSuggestions: [QuickSuggestion]?
    @State private var loadedMuscle: String?
    /// Full-screen «Focus mode» cover — entry from the inline set list; dismiss returns to the table
    /// without ending the session (mock v21 handoff). Additive only; does not replace `inlineSession`.
    @State private var focusMode = false
    /// Manual Tiempo/FC toggle for the full-screen rest hero (FER-934). nil = follow `currentRestMode`
    /// (FC when a rest target exists and the strap has signal); the user can flip it either way.
    @State private var focusRestShowsHR: Bool?
    /// Which exercise's «···» paper menu is open (FER-894 · «Cómo llego a Cambiar»), by run index. nil = closed.
    @State private var menuExerciseIndex: Int?
    /// The exercise whose «Change {exercise}» sheet is open (FER-894). nil = closed.
    @State private var changeExercise: ChangeTarget?
    /// The terminal «Nothing to save» result card for discarding an empty session (FER-894 · Estados 2).
    @State private var nothingToSave = false

    /// Identifies which exercise the «Change» sheet is swapping (FER-894); carries the run for its header
    /// and same-muscle shortlist. `id` is the run id so `.sheet(item:)` re-presents cleanly per exercise.
    struct ChangeTarget: Identifiable {
        let ei: Int
        let run: StrengthSessionModel.ExerciseRun
        var id: String { run.id }
    }

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

    /// Identifies which set's RPE sheet is open (FER-930): the exercise's run id + the set id (stable
    /// across re-renders, unlike an index), plus the header context (set number, weight, reps).
    struct RPETarget: Identifiable {
        let id: String   // setId — unique across the session
        let runId: String
        let setNumber: Int
        let weightKg: Double
        let reps: Int
        let currentRPE: Double?
    }

    /// Identifies which exercise's note sheet is open (FER-932): the run id + exercise id (for the
    /// history lookup) + the active set's number (for the «Solo la serie N» scope option).
    struct NoteTarget: Identifiable {
        let id: String   // runId
        let exerciseId: String
        let exerciseName: String
        let setId: String
        let setNumber: Int
    }
    /// A marker to present the receipt printer (thermal ticket); carries the real session id for
    /// barcode/order stability and set/HR loads. The summary comes from `session.summary`.
    struct ShareRef: Identifiable {
        let id = UUID()
        let sessionId: String
    }

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
            if nothingToSave {
                nothingToSaveCard
            } else if let summary = session.summary {
                ScrollView {
                    VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                        summaryPhase(summary)
                    }
                    .padding(.horizontal, CenitMetrics.screenPadding)
                    .padding(.top, 18)
                    .padding(.bottom, CenitMetrics.screenPadding)
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
        // FER-935: hoisted from `emptyAdHocSession` to the shared root so the «＋» rail node also opens
        // the picker in a populated (routine-backed) session, not just the ad-hoc empty state.
        .sheet(isPresented: $showLibraryPicker) {
            // Canvas pass 2026-07-15: sin leyenda (owner call) — el ejercicio se inserta después del
            // actual y se queda PERMANENTE en la rutina (persistencia abajo en `addExercises`).
            ExerciseLibraryScreen { picks in
                showLibraryPicker = false
                Task { await addExercises(picks) }
            }
            .instrumentoTheme(theme).environmentObject(model.repo).preferredColorScheme(.light)
        }
        .onChange(of: session.phase) { _, phase in
            if phase != .resting { restAnchorEi = nil }
        }
        .sheet(item: $progressionEdit) { target in
            // r7: la pantalla de progresión COMPLETA (la misma del editor de rutina, con deload e
            // ignorar-recuperación) — el dueño la recordaba bien; la mini-hoja lean se retira.
            if session.runs.indices.contains(target.id) {
                let run = session.runs[target.id]
                if let re = routineREs[run.id] {
                    ProgressionSetupScreen(
                        theme: theme, exercise: re, exerciseName: run.name,
                        currentWeightKg: run.sets.first?.weightKg,
                        derivedIncrementKg: weightStepKg,
                        onBack: { progressionEdit = nil },
                        onSave: { enabled, targetReps, sessions, incrementKg, deload, ignoreRecovery in
                            persistProgressionFull(runId: run.id, enabled: enabled, targetReps: targetReps,
                                                   sessions: sessions, incrementKg: incrementKg,
                                                   deload: deload, ignoreRecovery: ignoreRecovery)
                            progressionEdit = nil
                        }
                    )
                    .padding(.top, CenitMetrics.gap)
                    .presentationDragIndicator(.visible)
                    .presentationBackground(theme.paper)
                    .preferredColorScheme(.light)
                } else {
                    // Sesión ad-hoc: sin rutina no hay plan que progresar.
                    VStack(spacing: 10) {
                        Text("Progression lives on saved routines.")
                            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        Button(String(localized: "Close")) { progressionEdit = nil }
                            .font(StrandFont.subhead).foregroundStyle(theme.ink)
                    }
                    .padding(CenitMetrics.screenPadding)
                    .presentationDetents([.height(160)])
                    .presentationBackground(theme.paper)
                }
            }
        }
        .task(id: session.routineId) { await loadRoutineREs() }
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
        .sheet(item: $changeExercise) { target in
            ChangeExerciseSheet(
                theme: theme, run: target.run, repo: model.repo,
                onUse: { ex in
                    changeExercise = nil
                    Task {
                        let last = await model.repo.exerciseHistory(exerciseId: ex.id).last
                        await MainActor.run {
                            withAnimation(.snappy) {
                                session.replaceExercise(at: target.ei, with: ex,
                                                        lastWeightKg: last?.weightKg, lastReps: last?.reps)
                            }
                        }
                    }
                },
                onClose: { changeExercise = nil }
            )
            .instrumentoTheme(theme).preferredColorScheme(.light)
            .presentationBackground(theme.paper)
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
            platesSheet(target)
        }
        .sheet(item: $rpeTarget) { target in
            RPESheet(theme: theme, target: target,
                     onPick: { rpe in
                         session.setRPE(exercise: target.runId, set: target.id, rpe: rpe)
                         rpeTarget = nil
                     },
                     onClose: { rpeTarget = nil })
                .presentationDetents([.height(560)])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
                .preferredColorScheme(.light)
        }
        .sheet(item: $noteTarget) { target in
            if let run = session.runs.first(where: { $0.id == target.id }) {
                NoteSheet(
                    theme: theme, target: target,
                    initialScope: .exercise,
                    exerciseText: run.note ?? "",
                    setText: run.sets.first(where: { $0.id == target.setId })?.note ?? "",
                    history: noteHistory,
                    onSave: { scope, text in
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let value: String? = trimmed.isEmpty ? nil : trimmed
                        switch scope {
                        case .exercise: session.setExerciseNote(exercise: target.id, text: value)
                        case .set: session.setSetNote(exercise: target.id, set: target.setId, text: value)
                        }
                        noteTarget = nil
                    },
                    onClose: { noteTarget = nil }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
                .preferredColorScheme(.light)
            }
        }
        .fullScreenCover(item: $shareReceipt) { ref in
            if let summary = session.summary {
                ReceiptPrinterScreen(
                    theme: theme,
                    summary: summary,
                    sessionId: ref.sessionId,
                    onClose: { shareReceipt = nil }
                )
                .environmentObject(model)
            }
        }
        .fullScreenCover(isPresented: $focusMode) {
            // Canvas pass 2026-07-15 (UI·discos): the plates sheet must ALSO hang inside the cover —
            // the outer `.sheet` presenter is covered while focus mode is up, so «⛓ discos» from the
            // focus KG card silently failed to present (the reported «rota»).
            focusModeView
                .sheet(item: $platesTarget) { target in
                    platesSheet(target)
                }
        }
        // S-2 (FER-830) → FER-837: one destructive-confirmation pattern across the flow, now the
        // «Instrumento» ConfirmCard. The stay-safe verb names its action («Keep training»), never a
        // generic cancel; destructive is always the red outline.
        .instrumentoConfirm(
            isPresented: $confirmFinish,
            title: String(localized: "Finish workout?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            message: session.doneCount == 0
                ? String(localized: "You haven't logged any sets yet.")
                : (session.pendingCount > 0
                   ? String(localized: "\(session.pendingCount) sets aren't logged yet. Save keeps them; discard deletes everything.")
                   : String(localized: "Save keeps this workout. Discard deletes everything you logged.")),
            actions: [
                .init(String(localized: "Save workout"), role: .primary) { model.endStrengthSession(save: true) },
                .init(String(localized: "Keep training"), role: .secondary),
                .init(String(localized: "Discard workout"), role: .destructive) { model.endStrengthSession(save: false) }
            ]
        )
        .instrumentoConfirm(
            isPresented: $confirmDiscard,
            title: String(localized: "Discard workout?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            message: String(localized: "Everything you logged in this session will be deleted. This can't be undone."),
            actions: [
                .init(String(localized: "Keep training"), role: .primary),
                .init(String(localized: "Discard workout"), role: .destructive) { model.endStrengthSession(save: false) }
            ]
        )
    }

    // MARK: Inline session (the default view — the Hevy-style logging table, FER-497)

    private var inlineSession: some View {
        // A flat List (not ScrollView) so each set row gets a real swipe-to-delete; styled down to the
        // warm-paper language — no native separators / background, our own hairlines. FER-497.
        // FER-929: rail + accordion — only the active exercise expands into its table; done/upcoming
        // exercises collapse to one line each, hung off a vertical rail (`railColumn`).
        // Canvas pass 2026-07-15 (sugerencia 3): the jump to the next exercise is NARRATED — when the
        // guided focus moves, the list scrolls the new active card into view instead of teleporting.
        ScrollViewReader { proxy in
        List {
            // FER-933: modo mover — every exercise compresses to a draggable row with a «SOLTAR AQUÍ ·
            // POSICIÓN N» drop zone; the accordion (`activeExerciseBlock`) stays closed for the duration.
            if reorderMode { reorderModeBar.plainRow(top: CenitMetrics.gap, bottom: 4).transition(.opacity) }
            ForEach(Array(session.runs.enumerated()), id: \.element.id) { ei, run in
                if !run.skipped {
                    if reorderMode {
                        // UX·anim #3: mode changes fade explicitly — the row TYPE swap (riel ↔ mover)
                        // had no declared transition and read as a flicker.
                        reorderRow(run, ei: ei).plainRow(top: 4, bottom: 4).transition(.opacity)
                    } else {
                        switch railState(ei: ei, run: run) {
                        case .active:
                            activeExerciseBlock(run, ei: ei)
                        case .done:
                            doneRow(run, ei: ei)
                                .plainRow()
                                .transition(.opacity)
                        case .upcoming:
                            comingRow(run, ei: ei)
                                .plainRow()
                                .transition(.opacity)
                        }
                    }
                }
            }
            if !reorderMode {
                // Canvas pass 2026-07-15: no top inset — an inset is a HOLE in the rail thread; the
                // node's breathing lives in its own taller cell so the line arrives unbroken.
                addExerciseNode.plainRow()
                if session.isComplete, session.doneCount > 0 { completeFooter.plainRow(top: CenitMetrics.sectionGap) }
                discardFooter.plainRow(top: CenitMetrics.gap, bottom: CenitMetrics.screenPadding)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.paper)
        .environment(\.defaultMinListRowHeight, 1)
        // UX·anim #2: one clock for the exercise jump — the row collapse shares the scroll's gentle
        // spring so both read as a single continuous gesture (before: snappy vs. gentle fighting).
        .animation(StrandMotion.gentle, value: session.currentIndex)
        .safeAreaInset(edge: .top, spacing: 0) { liveHead }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let cell = activeCell { keypad(for: cell) } else { statsBar }
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
        .onChange(of: accordionIndex) { _, newIndex in
            // Sugerencia 3 + r6: the narrated move happens when the ACCORDION moves — i.e. when the
            // rest ends — not when the model's index advances mid-rest.
            withAnimation(reduceMotion ? nil : StrandMotion.gentle) {
                proxy.scrollTo("session-exercise-\(newIndex)", anchor: .center)
            }
        }
        }
    }

    // MARK: Rail + accordion (FER-929)

    /// One exercise's position relative to the guided focus: active (accordion open), done (all its sets
    /// logged, or its index already passed), or upcoming. Derived purely from `StrengthSessionModel`'s
    /// existing `currentIndex`/`sets.done` — the model itself is untouched.
    private enum RailState { case active, done, upcoming }

    private func railState(ei: Int, run: StrengthSessionModel.ExerciseRun) -> RailState {
        if ei == accordionIndex { return .active }
        if ei < session.currentIndex || run.sets.allSatisfy(\.done) { return .done }
        return .upcoming
    }

    /// The vertical rail (canvas pass 2026-07-15): one CONTINUOUS thread in the routine's own family
    /// tint at low opacity («ember tenue» — structure, not datum), bridging the inter-row insets with
    /// negative vertical padding so it never breaks between rows. Each exercise hangs a fixed 9pt dot
    /// tinted by ITS movement family (push=ember · pull=teal · legs=indigo); the active dot keeps the
    /// existing soft halo. A superset span keeps its «A1»/«A2» teal badge (the LINE no longer flips
    /// teal — the badge/tag alone carry the superset, so rail-color and superset don't compete).
    /// Purely decorative — `accessibilityHidden`, the row's own label carries the state to VoiceOver.
    private func railColumn(_ state: RailState, superset: Bool, badgeText: String? = nil,
                            tint: Color, dotTopOffset: CGFloat? = nil, clipTop: Bool = false) -> some View {
        ZStack(alignment: dotTopOffset == nil ? .center : .top) {
            // The thread fills the WHOLE cell height (rows carry no outer vertical insets anymore —
            // their breathing lives inside the content), so adjacent cells butt up and the line reads
            // as one continuous hilo. `clipTop` (first exercise) starts the thread AT the dot — the
            // dot is its birthplace, nothing hangs above.
            if clipTop {
                VStack(spacing: 0) {
                    Color.clear
                    Rectangle().fill(railTint.opacity(0.35)).frame(width: 2)  // token-exempt: decorative rail-thread alpha (structure, not datum)
                }
            } else {
                Rectangle().fill(railTint.opacity(0.35)).frame(width: 2)  // token-exempt: decorative rail-thread alpha (structure, not datum)
            }
            Group {
                if let badgeText {
                    Circle()
                        .fill(theme.dataHrv)
                        .frame(width: 17, height: 17)
                        .overlay {
                            Text(badgeText).font(StrandFont.footnote).fontWeight(.semibold)
                                .foregroundStyle(theme.paper)
                        }
                } else {
                    ZStack {
                        Circle().fill(theme.paper).frame(width: 15, height: 15)
                        Circle().fill(tint).frame(width: 9, height: 9)
                    }
                }
            }
            .padding(.top, dotTopOffset.map { $0 - 4.5 } ?? 0)
        }
        .frame(width: 14)
        .accessibilityHidden(true)
    }

    /// The rail only exists with 2+ exercises — a thread through a single stop reads orphaned
    /// (canvas pass 2026-07-15, sugerencia 2).
    private var showRail: Bool { session.runs.filter { !$0.skipped }.count > 1 }

    /// The first visible (non-skipped) exercise — its dot is the thread's BIRTHPLACE: no line above it.
    private var firstRailIndex: Int? { session.runs.firstIndex { !$0.skipped } }

    /// The routine's own family tint — the color of the rail thread. Classified from what the session
    /// actually contains (same `RoutineClassifier` the hub/plan use), so an ad-hoc session earns a color
    /// too. Push routines read ember, pull teal, legs indigo; mixed/full-body falls back to ember.
    private var railTint: Color {
        let muscles = session.runs.compactMap { ExerciseCatalog.byID($0.exerciseId)?.primaryMuscles }
        switch RoutineClassifier.classify(primaryMusclesPerExercise: muscles) {
        case .pull: return theme.dataHrv
        case .legs: return theme.dataSleep
        default: return theme.dataStrain
        }
    }

    /// Movement-family tint for ONE exercise's rail dot (push=ember · pull=teal · legs=indigo) — the
    /// same mapping History (`muscleTint`) and Library use. Third screen using it: candidate to promote
    /// into StrandDesign at close (kept local during the live-canvas pass).
    private func categoryTint(_ run: StrengthSessionModel.ExerciseRun) -> Color {
        guard let ex = ExerciseCatalog.byID(run.exerciseId) else { return theme.dataStrain }
        let m = ex.primaryMuscles.joined(separator: " ").lowercased()
        if ["lats", "back", "biceps", "traps", "forearms"].contains(where: m.contains) { return theme.dataHrv }
        if ["quadriceps", "hamstrings", "glutes", "calves", "abductors", "adductors"].contains(where: m.contains) { return theme.dataSleep }
        return theme.dataStrain
    }

    /// The «A1»/«A2» badge text for the run at `ei`: its superset letter + (position in the span + 1).
    /// nil when the run isn't in a real superset (railColumn then falls back to the plain dot).
    private func supersetBadgeText(ei: Int) -> String? {
        guard session.isInSuperset(ei) else { return nil }
        let members = session.supersetMembers(at: ei)
        guard let letter = session.supersetLetter(for: ei),
              let position = members.firstIndex(of: ei) else { return nil }
        return "\(letter)\(position + 1)"
    }

    /// «SUPERSERIE» tag, teal, next to a run's name when it's part of a real superset span (FER-931).
    @ViewBuilder private func supersetTag(_ ei: Int) -> some View {
        if session.isInSuperset(ei) {
            Text("SUPERSET").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.dataHrv)
        }
    }

    /// A finished exercise, compressed to one line: dimmed name + «carga × reps·reps·reps» + a green
    /// check. Still tappable — re-opens the accordion on its first not-done set so a set can be corrected.
    private func doneRow(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        Button {
            restAnchorEi = nil   // switching by hand releases the rest-held accordion
            withAnimation(.snappy(duration: 0.22)) {
                session.select(exerciseIndex: ei, setIndex: run.sets.firstIndex { !$0.done } ?? 0)
            }
        } label: {
            HStack(spacing: 12) {
                railColumn(.done, superset: session.isInSuperset(ei), badgeText: supersetBadgeText(ei: ei),
                           tint: categoryTint(run), clipTop: ei == firstRailIndex)
                // Canvas pass: dim the CONTENT, not the whole row — the rail thread and its dot stay at
                // full strength so the hilo reads continuous while the finished exercise recedes. The
                // row's breathing lives HERE (vertical padding), not in list insets, so cells butt up.
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        supersetTag(ei)
                        Text(run.name).font(StrandFont.body).foregroundStyle(theme.inkTertiary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(doneDetailText(run)).font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
                        .lineLimit(1)
                    Image(systemName: "checkmark.circle.fill")
                        .font(StrandFont.glyph(.chevron)).foregroundStyle(theme.dataRecovery)
                }
                .opacity(StrandOpacity.dim)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // FER-933: long-press any rail row to enter modo mover (`simultaneousGesture`, not
        // `.onLongPressGesture`, so the row's own tap-to-reopen keeps working — same pattern as
        // RoutineEditorScreen's reorder entry).
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
            withAnimation(.snappy) { reorderMode = true }
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(supersetAccessibilityLabel(ei: ei, base: "\(run.name), done, \(doneDetailText(run))")))
        .accessibilityHint(Text("Double tap to reopen and correct a set"))
    }

    /// A not-yet-reached exercise, compressed to one line: name + its planned prescription. Tapping moves
    /// the guided focus here (the same `select` the plan navigator already used).
    private func comingRow(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        Button {
            restAnchorEi = nil   // switching by hand releases the rest-held accordion
            withAnimation(.snappy(duration: 0.22)) { session.select(exerciseIndex: ei, setIndex: 0) }
        } label: {
            HStack(spacing: 12) {
                railColumn(.upcoming, superset: session.isInSuperset(ei), badgeText: supersetBadgeText(ei: ei),
                           tint: categoryTint(run), clipTop: ei == firstRailIndex)
                // Canvas pass: upcoming rows now dim exactly like done rows (the row that «se escapaba»)
                // — content only, so the rail thread stays alive. Breathing inside the content.
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        supersetTag(ei)
                        Text(run.name).font(StrandFont.body).foregroundStyle(theme.ink).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(prescriptionText(run)).font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
                        .lineLimit(1)
                }
                .opacity(StrandOpacity.dim)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // FER-933: same long-press entry into modo mover as `doneRow`.
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
            withAnimation(.snappy) { reorderMode = true }
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(supersetAccessibilityLabel(ei: ei, base: "\(run.name), coming up, \(prescriptionText(run))")))
        .accessibilityHint(Text("Double tap to move focus here"))
    }

    /// Appends the superset role to a row's a11y label when the run is grouped (FER-931), e.g.
    /// «Press banca, superserie A1, coming up, 60 kg × 8» — a plain exercise's label is untouched.
    private func supersetAccessibilityLabel(ei: Int, base: String) -> String {
        guard let badge = supersetBadgeText(ei: ei) else { return base }
        let role = String(format: String(localized: "superset %@"), badge)
        // Insert right after the name (before the first comma) so the role reads naturally.
        guard let commaRange = base.range(of: ",") else { return "\(base), \(role)" }
        var result = base
        result.insert(contentsOf: ", \(role)", at: commaRange.lowerBound)
        return result
    }

    /// «82,5 kg × 8·8·6» for a finished weight/reps or bodyweight exercise; falls back to the plain
    /// «previous» phrasing for time/distance (there's no per-set rep list to join there).
    private func doneDetailText(_ run: StrengthSessionModel.ExerciseRun) -> String {
        guard run.type == .weightReps || run.type == .bodyweight else { return previousText(run) ?? "" }
        let w = run.sets.first?.weightKg ?? 0
        let reps = run.sets.map { "\($0.reps)" }.joined(separator: "·")
        return "\(massText(w)) × \(reps)"
    }

    /// «82,5 kg × 8» — the planned first-set prescription for an upcoming exercise.
    private func prescriptionText(_ run: StrengthSessionModel.ExerciseRun) -> String {
        guard run.type == .weightReps || run.type == .bodyweight else {
            return "\(run.sets.count) " + String(localized: "series")
        }
        let w = run.sets.first?.weightKg ?? 0
        let reps = run.sets.first?.reps ?? 0
        return "\(massText(w)) × \(reps)"
    }

    /// The active exercise: rail dot + full header, then its set table inside a `surface` card (spec §3),
    /// the inline rest card, and «Add set» — the exact content `inlineSession` rendered per exercise
    /// before FER-929, just no longer repeated for every exercise at once.
    @ViewBuilder private func activeExerciseBlock(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        // Canvas pass 2026-07-15: the whole block lives INSIDE one floating white card (the same hover
        // language as the rest card) — header, sets and «add set» are slices of it; the rail thread
        // runs BEHIND the card and the category dot centers on the 44pt thumbnail, both painted by the
        // row backgrounds so the hilo never breaks.
        exerciseHeader(run, ei: ei, first: true)
            .padding(.top, 12).padding(.horizontal, 14).padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
            .activeCardRow(top: true, bottom: false, theme: theme, railTint: railTint,
                           railVisible: showRail,
                           railTopInset: ei == firstRailIndex ? 12 + 22 : 0,
                           dotTint: categoryTint(run))
            .id("session-exercise-\(ei)")
        ForEach(Array(run.sets.enumerated()), id: \.element.id) { si, set in
            // The rest card slots BETWEEN the set just logged and the next one (owner call): an
            // opening of space inside the card, not an appendix under the table.
            if restSlotIndex(run, ei: ei) == si { restCardRow(run) }
            // FER-937: a «SERIES DE TRABAJO» rule separates the collapsible warm-up «C» rows from the
            // numbered work sets — drawn on the first work row that follows a warm-up.
            let afterWarmup = set.kind == .work && si > 0 && run.sets[si - 1].kind == .warmup
            VStack(spacing: 0) {
                if afterWarmup { workSetsDivider.padding(.top, 12).padding(.bottom, 6) }
                setRow(ei: ei, si: si, run: run, set: set, last: si == run.sets.count - 1)
                    .border(.blue)   // TEMP-DEBUG r7 (fila gorda): quitar al cerrar la cacería
            }
                .border(.red)   // TEMP-DEBUG r7 (fila gorda): quitar al cerrar la cacería
                // Owner bug #3: a freshly-added set inflated its row — the slice can never stretch
                // beyond its content's natural height.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .overlay(alignment: .bottom) {
                    if si < run.sets.count - 1 { Rectangle().fill(theme.hairline).frame(height: 1) }
                }
                .activeCardRow(top: false, bottom: false, theme: theme, railTint: railTint,
                               railVisible: showRail)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        withAnimation(.snappy) { session.removeSet(exercise: ei, set: si) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
        }
        // Rest after the exercise's LAST set (no pending set to anchor to) — before the card closes.
        if session.phase == .resting, ei == accordionIndex, session.summary == nil,
           restSlotIndex(run, ei: ei) == nil {
            restCardRow(run)
        }
        // «Add set» closes the card as its own row — the handoff's ember pill, inside (FER-935 kin).
        addSetButton(ei)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
            .activeCardRow(top: false, bottom: true, theme: theme, railTint: railTint,
                           railVisible: showRail)
    }

    /// The exercise the current rest belongs to (canvas pass 2026-07-15, owner bug #4): registering the
    /// LAST set advances `currentIndex` to the next exercise, but the rest card must stay GLUED under
    /// the exercise you just finished — so every register path stamps the anchor before advancing.
    @State private var restAnchorEi: Int?

    /// The exercise whose accordion is OPEN: while resting, the anchor (the exercise you just worked)
    /// holds the accordion open — the jump to `currentIndex` happens when the rest ends (owner r6).
    private var accordionIndex: Int {
        (session.phase == .resting ? restAnchorEi : nil) ?? session.currentIndex
    }

    /// Every «✓ registrar» in the view funnels here: stamp the rest's home exercise, THEN let the model
    /// advance. The anchor clears when the rest ends (`onChange` of `session.phase`).
    private func registerActiveSet() {
        restAnchorEi = session.currentIndex
        session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR)
    }

    /// The set index the inline rest card slots BEFORE (the next pending set of the resting exercise) —
    /// nil when the rest follows the exercise's last set (the card then lands after the table).
    private func restSlotIndex(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> Int? {
        guard session.phase == .resting, ei == accordionIndex, session.summary == nil else { return nil }
        let si = run.currentSet
        guard run.sets.indices.contains(si), !run.sets[si].done else { return nil }
        return si
    }

    /// The inline rest card as a slice of the active card's flow — keeps its own float/shadow (the
    /// «hover» the owner asked to preserve) and the auto-dismiss task for fixed rests; entering and
    /// leaving animates as an opening/closing of space between the sets.
    private func restCardRow(_ run: StrengthSessionModel.ExerciseRun, standalone: Bool = false) -> some View {
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
            .padding(.horizontal, 8)
            .padding(.vertical, standalone ? 6 : 0)
            .activeCardRow(top: standalone, bottom: standalone, theme: theme, railTint: railTint,
                           railVisible: showRail)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// FER-937: the «SERIES DE TRABAJO» rule between the warm-up «C» rows and the numbered work sets —
    /// two hairlines flanking a quiet overline. A label, not a datum, so it stays in tinted ink.
    private var workSetsDivider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(theme.hairline).frame(height: 1)
            Text("WORK SETS").instrumentoOverline().foregroundStyle(theme.inkDim)
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
        .accessibilityLabel(Text("Work sets"))
    }

    /// The riel's terminal node — a dotted circle affordance that opens the existing ad-hoc add-exercise
    /// flow (`showLibraryPicker` → `addExercises`). Positional insertion is a later child (FER-929 §1).
    private var addExerciseNode: some View {
        Button { showLibraryPicker = true } label: {
            HStack(spacing: 12) {
                // Canvas pass: the «＋» is the rail's TERMINAL stop — the thread drops from the cell
                // top and dies exactly at the ring's center; ring and thread share the same 14pt lane
                // center so they can't drift apart.
                ZStack {
                    VStack(spacing: 0) {
                        Rectangle().fill(railTint.opacity(0.35)).frame(width: 2)  // token-exempt: decorative rail-thread alpha (structure, not datum)
                            .opacity(showRail ? 1 : 0)
                        Color.clear
                    }
                    Circle().fill(theme.paper)
                        .overlay(Circle().strokeBorder(theme.dataStrain, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.dataStrain)  // token-exempt: tiny plus glyph sized to the 18pt dotted add-node
                        )
                }
                .frame(width: 14)
                Text("Add exercise").font(StrandFont.subhead).foregroundStyle(theme.ink)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44 + CenitMetrics.gap)   // the row's own breathing — not an inset hole
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add exercise"))
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
            onPlates: { openPlates(ei: ei, si: si) },
            onHide: { withAnimation(.snappy(duration: 0.22)) { activeCell = nil } }
        )
        .transition(.move(edge: .bottom))
    }

    /// The plate-calculator sheet content, shared by the two presenters (main body + inside the focus
    /// cover — a sheet can only present from the frontmost layer).
    private func platesSheet(_ target: PlatesTarget) -> some View {
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

    /// Open the plate calculator (FER-720 · 3a) for a weight cell, seeded with that set's current load.
    private func openPlates(ei: Int, si: Int) {
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return }
        platesTarget = PlatesTarget(ei: ei, weightKg: session.runs[ei].sets[si].weightKg)
    }

    private static func indices(_ ref: CellRef) -> (Int, Int) {
        switch ref { case let .weight(e, s): return (e, s); case let .reps(e, s): return (e, s) }
    }

    // MARK: _LiveHead (FER-929 — replaces the old `sessionHeader`: nav + title + live counters)

    private var liveHead: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            // Nav row: minimize «‹» (session stays alive, the pill re-opens it) · live/paused pulse.
            HStack(spacing: 10) {
                Button { model.strengthSheetPresented = false } label: {
                    StrandIcon.back.image
                        .font(StrandFont.glyph(.lead, weight: .semibold)).foregroundStyle(theme.ink)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Minimize session"))
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    // Canvas pass 2026-07-15: recording-red and STILL — a state lamp, not a heartbeat
                    // (the pulsing ember dot read as «loading»; owner call).
                    Circle().fill(session.paused ? theme.inkDim : theme.critical)
                        .frame(width: 8, height: 8)
                    Text(session.paused ? "Paused" : "In progress")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.leading, -10)   // pull the 44pt chevron target back to the 24pt margin edge

            // Overline: hidden in ad-hoc (no plan to name). No per-day schedule is exposed by
            // `StrengthSessionModel` today, so this counts exercises rather than inventing a day count.
            if !isEmptyAdHoc {
                Text("ROUTINE · \(session.activeExercises.count) EXERCISES")
                    .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)
            }

            // Title, underlined solid `ink` (not the dotted neutral rule reserved for table values).
            // Canvas pass 2026-07-15: sin subrayado — el peso de la tipografía basta (owner call).
            Text(isEmptyAdHoc ? String(localized: "Quick strength") : session.routineName)
                .font(StrandFont.title2.weight(.semibold)).foregroundStyle(theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)

            // Metrics: clock (dims + freezes while paused, FER-823) · BPM (strap-only, never «♥ --») ·
            // done/total · Spacer · Pausa/Reanuda + Terminar (or Discard for an empty ad-hoc session).
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                    let elapsed = session.elapsedSeconds(now: ctx.date)
                    Text(Self.clock(elapsed))
                        .font(InstrumentoType.groteskSessionClockInline)
                        .tracking(InstrumentoType.groteskSessionClockTracking)
                        .foregroundStyle(session.paused ? theme.inkDim : theme.ink)
                        .accessibilityLabel(Text(session.paused ? "Paused at \(Self.clock(elapsed))"
                                                                 : "Elapsed \(Self.clock(elapsed))"))
                }
                // BPM fused to the clock — the app's one always-on pulse. Hidden (not dashed) with no strap.
                PulseReader(model.live.pulse) { p in
                    if let bpm = p.smoothedBpm {
                        HStack(spacing: 6) {
                            BpmPulseDot(color: theme.dataHeart, animated: !reduceMotion)
                            Text("\(bpm)").font(StrandFont.caption.monospacedDigit()).foregroundStyle(theme.dataHeart)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text("Heart rate \(bpm)"))
                    }
                }
                Text("· \(session.doneCount)/\(sessionSetsTotal)")
                    .font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                headActionButtons
            }

            // Per-exercise progress, a 3px filete (FER-823: no hue while paused). No plan in ad-hoc.
            if !isEmptyAdHoc {
                SessionProgressBar(segments: progressSegments,
                                   hue: session.paused ? theme.inkDim : theme.dataStrain,
                                   track: theme.hairline, height: 3)
                    .accessibilityLabel(Text("Session progress"))
                    .accessibilityValue(Text("\(session.doneCount) of \(sessionSetsTotal) sets"))
            }

            // The Apple Watch mirror status (FER-742) — drawn ONLY when the watch fails.
            watchStatusLine
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(theme.paper)
        // Canvas pass 2026-07-15: the bottom hairline under the progress bar is gone — the whitespace
        // and the rail thread separate head from list on their own (owner call, punto 6).
    }

    /// The header's right-side action(s), FER-823: paused → «Resume» is the primary action (finish after
    /// resuming); running with sets → a pause toggle sits left of Finish; an empty ad-hoc session only
    /// offers Discard. Unchanged behavior from the pre-FER-929 `sessionHeader` — only its container moved.
    @ViewBuilder private var headActionButtons: some View {
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
            // Canvas pass 2026-07-15: Pausa dresses like Terminar's sibling — same capsule grammar,
            // neutral ink vs. Terminar's reserved alert hue, so the pair reads as one control family.
            Button { model.pauseStrengthSession() } label: {
                Label("Pause", systemImage: "pause.fill").labelStyle(.titleAndIcon)
                    .font(StrandFont.subhead).foregroundStyle(theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
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

    // MARK: _StatsBar (FER-929 — fixed bottom bar; the keypad takes this slot instead while a cell is active)

    private var statsBar: some View {
        VStack(spacing: 14) {   // canvas 2026-07-15: más aire entre «Modo foco» y los contadores
            // Canvas pass 2026-07-15: the handoff's «◐ Modo foco» — a quiet glyph+text, not a shouting
            // capsule; the bar's job is the counters, the entry just waits there.
            if !isEmptyAdHoc && session.summary == nil {
                Button { focusMode = true } label: {
                    Label("Focus mode", systemImage: "viewfinder")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .padding(.vertical, 2).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Focus mode"))
                .accessibilityHint(Text("Opens a full-screen set logger"))
            }
            // kg · series · (kcal only with a streaming strap, never dashes) — same sources as before,
            // now with the handoff's typographic contrast: Grotesk-bold values, light labels.
            counterLineStyled
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(counterLine))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(theme.paper)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    // MARK: - Focus mode (full-screen cover · additive entry from the inline list)

    /// Full-screen capture/rest surface. Closing returns to the inline table; session state is unchanged.
    /// FER-934: while resting, the whole surface flips to the `dataRecovery` green with crema ink
    /// (handoff `_RestFull`); the capture variant keeps the paper background untouched.
    private var focusModeView: some View {
        let resting = session.phase == .resting
        return VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            // Canvas pass 2026-07-15 (handoff `_FocusScreen`): capturing shows «× · MODO FOCO · SERIE
            // N DE M · reloj»; resting keeps FER-934's toggle-left/×-right green arrangement.
            HStack(spacing: 12) {
                if resting {
                    focusRestModeToggle
                    Spacer(minLength: 0)
                    focusCloseButton(onGreen: true)
                } else {
                    focusCloseButton(onGreen: false)
                    if let run = session.current {
                        Text("FOCUS MODE · SET \(min(run.currentSet + 1, run.sets.count)) OF \(run.sets.count)")
                            .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                        Text(Self.clock(session.elapsedSeconds(now: ctx.date)))
                            .font(InstrumentoType.groteskNumber(15)).monospacedDigit()
                            .foregroundStyle(theme.inkSecondary)
                    }
                    .accessibilityHidden(true)
                }
            }

            if resting {
                focusRestPhase
            } else {
                focusCapturePhase
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, CenitMetrics.sectionGap)
        .padding(.bottom, CenitMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background((resting ? theme.dataRecovery : theme.paper).ignoresSafeArea())
        .instrumentoTheme(theme)
        .preferredColorScheme(.light)
    }

    @ViewBuilder private var focusCapturePhase: some View {
        if let run = session.current {
            // Canvas pass 2026-07-15: rebuilt to the owner's handoff capture — centered thumb + name +
            // «la última vez», KG/REPS stepper cards, the big ink «✓ Registrar serie» pill, the quick
            // links row, and a prev/next exercise bar at the bottom.
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                Spacer(minLength: 0)
                // Canvas pass 2026-07-15: bigger hero (56pt thumb + 24pt Grotesk title), the row
                // left-aligned (long names get the room), the whole block vertically centered.
                HStack(spacing: 14) {
                    SessionRunThumb(exerciseId: run.exerciseId, side: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(run.name).font(InstrumentoType.grotesk(24, weight: .semibold))
                            .foregroundStyle(theme.ink)
                            .lineLimit(2).minimumScaleFactor(0.7)
                        if let prev = previousText(run) {
                            Text(String(localized: "last time ") + prev)
                                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                switch run.type {
                case .weightReps:
                    HStack(alignment: .top, spacing: 12) {
                        focusKgCard
                        focusRepsCard(run)
                    }
                    focusRegisterButton
                    focusQuickLinks(run)
                case .bodyweight:
                    focusRepsHero
                    focusAddedWeightRow
                    focusRegisterButton
                    focusQuickLinks(run)
                case .time:
                    focusTimeControls
                case .distance:
                    focusDistanceControls
                }
                Spacer(minLength: 0)
                focusPrevNextBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("All done").font(StrandFont.title1).foregroundStyle(theme.ink)
                Text("No pending set. Close focus mode to finish from the list.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var focusWeightHero: some View {
        HStack {
            stepper(system: "minus") { session.bumpWeight(byKg: -weightStepKg) }
                .accessibilityLabel(Text("Decrease weight"))
            Spacer(minLength: CenitMetrics.gap)
            VStack(spacing: 0) {
                Text(plateNumber(displayWeight(session.currentSet?.weightKg ?? 0)))
                    .instrumentoHero(76).foregroundStyle(theme.dataStrain)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                Text(UnitFormatter.massUnit(units)).font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: CenitMetrics.gap)
            stepper(system: "plus") { session.bumpWeight(byKg: weightStepKg) }
                .accessibilityLabel(Text("Increase weight"))
        }
        .accessibilityElement(children: .contain)
    }

    private var focusRepsHero: some View {
        HStack {
            stepper(system: "minus") { session.bumpReps(-1) }
                .accessibilityLabel(Text("Decrease reps"))
            Spacer(minLength: CenitMetrics.gap)
            VStack(spacing: 0) {
                Text("\(session.currentSet?.reps ?? 0)")
                    .instrumentoHero(76).foregroundStyle(theme.dataStrain)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                Text("reps").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: CenitMetrics.gap)
            stepper(system: "plus") { session.bumpReps(1) }
                .accessibilityLabel(Text("Increase reps"))
        }
        .accessibilityElement(children: .contain)
    }

    private var focusRepsRow: some View {
        HStack {
            Text("Reps").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
            Spacer()
            HStack(spacing: CenitMetrics.sectionGap) {
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

    private var focusAddedWeightRow: some View {
        let kg = session.currentSet?.weightKg ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Added weight").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                Text(kg > 0 ? "optional" : "optional · bodyweight only")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Spacer()
            HStack(spacing: CenitMetrics.sectionGap) {
                stepper(system: "minus", size: 34) { session.bumpWeight(byKg: -weightStepKg) }
                    .accessibilityLabel(Text("Decrease added weight"))
                Text("+\(plateNumber(displayWeight(kg))) \(UnitFormatter.massUnit(units))")
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .font(StrandFont.title2).monospacedDigit()
                    .foregroundStyle(kg > 0 ? theme.ink : theme.inkTertiary)
                stepper(system: "plus", size: 34) { session.bumpWeight(byKg: weightStepKg) }
                    .accessibilityLabel(Text("Increase added weight"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var focusRegisterButton: some View {
        Button {
            withAnimation(StrandMotion.gentle) {
                registerActiveSet()
            }
        } label: {
            // Canvas pass 2026-07-15: the handoff's big ink capsule.
            Label("Register set", systemImage: "checkmark")
                .font(StrandFont.headline).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(theme.ink, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// The focus close «×» — ink-on-paper while capturing, crema-on-green while resting (FER-934).
    private func focusCloseButton(onGreen: Bool) -> some View {
        Button { focusMode = false } label: {
            StrandIcon.close.image
                .font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(onGreen ? theme.paper : theme.ink)
                .frame(width: 38, height: 38)
                .background(onGreen ? theme.paper.opacity(0.14) : theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(onGreen ? theme.paper.opacity(0.3) : theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close focus mode"))
    }

    /// The KG stepper card (extracted so the capture switch stays cheap to type-check).
    private var focusKgCard: some View {
        focusStepperCard(UnitFormatter.massUnit(units).uppercased(),
                         value: plateNumber(displayWeight(session.currentSet?.weightKg ?? 0)),
                         valueTint: theme.dataRecovery,
                         minusLabel: "Decrease weight", plusLabel: "Increase weight",
                         minus: { session.bumpWeight(byKg: -weightStepKg) },
                         plus: { session.bumpWeight(byKg: weightStepKg) }) {
            Button {
                platesTarget = PlatesTarget(ei: session.currentIndex,
                                            weightKg: session.currentSet?.weightKg ?? 0)
            } label: {
                Text("±\(plateNumber(displayWeight(weightStepKg))) · ⛓ " + String(localized: "plates"))
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary).underline()
            }
            .buttonStyle(.plain)
        }
    }

    /// The REPS stepper card (see `focusKgCard`).
    private func focusRepsCard(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        focusStepperCard(String(localized: "Reps").uppercased(),
                         value: "\(session.currentSet?.reps ?? 0)",
                         valueTint: theme.ink,
                         minusLabel: "Decrease reps", plusLabel: "Increase reps",
                         minus: { session.bumpReps(-1) },
                         plus: { session.bumpReps(1) }) {
            if let lr = run.lastReps {
                Text(String(localized: "target \(lr)"))
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            } else {
                Color.clear.frame(height: 14)
            }
        }
    }

    /// One handoff stepper card: overline unit, −/+ round steps flanking the big Grotesk value, and a
    /// caption slot («±2,5 · discos» / «objetivo N»).
    private func focusStepperCard<Caption: View>(_ overline: String, value: String, valueTint: Color,
                                                 minusLabel: LocalizedStringKey, plusLabel: LocalizedStringKey,
                                                 minus: @escaping () -> Void, plus: @escaping () -> Void,
                                                 @ViewBuilder caption: () -> Caption) -> some View {
        VStack(spacing: 6) {
            Text(overline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(spacing: 8) {
                focusRoundStep("minus", label: minusLabel, action: minus)
                Text(value).font(InstrumentoType.groteskNumber(32)).monospacedDigit()
                    .foregroundStyle(valueTint).lineLimit(1).minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity)
                focusRoundStep("plus", label: plusLabel, action: plus)
            }
            caption()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 10)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func focusRoundStep(_ system: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 15, weight: .medium))  // token-exempt: glyph sized to the 32pt round step
                .foregroundStyle(theme.inkSecondary)
                .frame(width: 32, height: 32)
                .background(theme.paper, in: Circle())
                .overlay(Circle().strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    /// «♥ Descanso · RPE · ✎ Nota» — the handoff's quiet action row under the register pill; each link
    /// opens the sheet the inline table already uses (rest editor / RPE / note).
    private func focusQuickLinks(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Button { openRestEditor(ei: session.currentIndex, setIndex: run.currentSet) } label: {
                Label("Rest", systemImage: "heart.fill")
                    .font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.dataHrv)
            }
            .buttonStyle(.plain)
            Text(verbatim: "·").font(StrandFont.caption).foregroundStyle(theme.inkDim)
            Button {
                guard run.sets.indices.contains(run.currentSet) else { return }
                let set = run.sets[run.currentSet]
                rpeTarget = RPETarget(id: set.id, runId: run.id, setNumber: run.currentSet + 1,
                                      weightKg: displayWeight(set.weightKg), reps: set.reps, currentRPE: set.rpe)
            } label: {
                Text(verbatim: "RPE").font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.dataEffort)
            }
            .buttonStyle(.plain)
            Text(verbatim: "·").font(StrandFont.caption).foregroundStyle(theme.inkDim)
            Button { openNote(exercise: run, ei: session.currentIndex) } label: {
                Label("Note", systemImage: "pencil")
                    .font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.ink)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    /// «‹ anterior — siguiente ›» bottom bar (handoff): jumps the guided focus to the neighboring
    /// non-skipped exercise, landing on its first pending set.
    @ViewBuilder private var focusPrevNextBar: some View {
        let prev = focusNeighbor(-1)
        let next = focusNeighbor(1)
        if prev != nil || next != nil {
            HStack {
                if let p = prev {
                    Button { focusJump(to: p) } label: {
                        Text("‹ \(session.runs[p].name)").font(StrandFont.subhead)
                            .foregroundStyle(theme.inkSecondary).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 12)
                if let n = next {
                    Button { focusJump(to: n) } label: {
                        Text("\(session.runs[n].name) ›").font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(theme.ink).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
        }
    }

    /// The nearest non-skipped exercise `delta` steps away from the guided focus, if any.
    private func focusNeighbor(_ delta: Int) -> Int? {
        var i = session.currentIndex + delta
        while session.runs.indices.contains(i) {
            if !session.runs[i].skipped { return i }
            i += delta
        }
        return nil
    }

    private func focusJump(to ei: Int) {
        restAnchorEi = nil
        withAnimation(StrandMotion.gentle) {
            session.select(exerciseIndex: ei,
                           setIndex: session.runs[ei].sets.firstIndex { !$0.done } ?? 0)
        }
    }

    /// Time sets: running clock + Start / Stop-and-save. Goal store omitted (not present on the live
    /// sheet after the Foco removal) — plain timer is the simplification.
    @ViewBuilder private var focusTimeControls: some View {
        let running = session.timerStart != nil
        if running {
            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                focusTimeReadout(elapsed: session.timerElapsed(now: ctx.date))
            }
        } else {
            focusTimeReadout(elapsed: session.currentSet?.timeS ?? 0)
        }
        Button {
            withAnimation(StrandMotion.gentle) {
                if running {
                    registerActiveSet()
                } else {
                    session.startSetTimer()
                }
            }
        } label: {
            Label(running ? "Stop and save" : "Start",
                  systemImage: running ? "stop.fill" : "play.fill")
                .font(StrandFont.headline).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CenitMetrics.sectionGap)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func focusTimeReadout(elapsed: Int) -> some View {
        Text(Self.clock(elapsed))
            .instrumentoHero(76).monospacedDigit()
            .foregroundStyle(elapsed > 0 ? theme.dataStrain : theme.inkTertiary)
            .minimumScaleFactor(0.5).lineLimit(1)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text("Timing, \(elapsed) seconds"))
    }

    @ViewBuilder private var focusDistanceControls: some View {
        let dist = session.currentSet?.distanceM ?? 0
        let running = session.timerStart != nil
        VStack(spacing: CenitMetrics.gap) {
            HStack {
                stepper(system: "minus") { session.bumpDistance(byMeters: -distanceStepM) }
                    .accessibilityLabel(Text("Decrease distance"))
                Spacer(minLength: CenitMetrics.gap)
                VStack(spacing: 0) {
                    Text(distanceNumber(dist))
                        .instrumentoHero(76).foregroundStyle(theme.dataStrain)
                        .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    Text(imperial ? "mi" : "km").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: CenitMetrics.gap)
                stepper(system: "plus") { session.bumpDistance(byMeters: distanceStepM) }
                    .accessibilityLabel(Text("Increase distance"))
            }
            if running {
                TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                    Text(Self.clock(session.timerElapsed(now: ctx.date)))
                        .font(StrandFont.title2).monospacedDigit().foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity)
                }
            } else {
                Text(Self.clock(session.currentSet?.timeS ?? 0))
                    .font(StrandFont.title2).monospacedDigit()
                    .foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: CenitMetrics.gap) {
                Button {
                    withAnimation(StrandMotion.gentle) {
                        running ? session.stopSetTimer() : session.startSetTimer()
                    }
                } label: {
                    Text(running ? "Stop" : "Start")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CenitMetrics.gap)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                            .strokeBorder(theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(running ? "Stop the timer" : "Start the timer"))
            }
        }
        let captured = dist > 0 || (session.currentSet?.timeS ?? 0) > 0 || running
        Button {
            withAnimation(StrandMotion.gentle) {
                registerActiveSet()
            }
        } label: {
            Label("Register set", systemImage: "checkmark")
                .font(StrandFont.headline).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CenitMetrics.sectionGap)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!captured)
        .opacity(captured ? 1 : StrandOpacity.dim)
    }

    /// Rest phase scaled to full-screen, fully dressed in `dataRecovery` green + crema ink (FER-934,
    /// handoff `_RestFull`). Reuses the inline card's readiness/time evaluation patterns; only the
    /// vestment changes, the rest engine (`extendRest`/`skipRest`/`computeRestTarget`) is untouched.
    private var focusRestPhase: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            // Canvas pass 2026-07-15: the exercise's thumbnail anchors the caption — you know whose
            // rest this is at a glance, same as the list.
            HStack(spacing: 10) {
                if session.runs.indices.contains(session.currentIndex) {
                    SessionRunThumb(exerciseId: session.runs[session.currentIndex].exerciseId, side: 28)
                }
                Text(focusRestCaption).font(StrandFont.subhead).foregroundStyle(theme.paper.opacity(0.8))
            }

            if focusRestWantsHR, let started = session.restStartedAt {
                PulseReader(model.live.pulse) { p in
                    TimelineView(.periodic(from: started, by: 1)) { ctx in
                        let elapsed = max(0, Int(ctx.date.timeIntervalSince(started)))
                        let v = RestReadinessRule.evaluate(
                            currentHR: p.smoothedBpm, worn: model.live.worn, restingHR: restingBaseline,
                            elapsedS: elapsed, targetHR: session.currentRestTarget)
                        let noSignal = v.state == .noSignal
                        if !noSignal {
                            focusRestHRHero(elapsed: elapsed, readiness: v)
                        } else {
                            focusRestTimeHero(end: session.restEndsAt, now: ctx.date, noStrapFallback: noSignal)
                        }
                    }
                }
            } else if let end = session.restEndsAt, let started = session.restStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    focusRestTimeHero(end: end, now: ctx.date, noStrapFallback: false)
                }
            }

            HStack(spacing: CenitMetrics.gap) {
                focusRestAdjust("−15") { session.extendRest(byseconds: -15) }
                Button { withAnimation(StrandMotion.gentle) { session.skipRest() } } label: {
                    Text("Skip")
                        .font(StrandFont.headline).foregroundStyle(theme.dataRecovery)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CenitMetrics.sectionGap)
                        .background(theme.paper, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Skip rest"))
                focusRestAdjust("+15") { session.extendRest(byseconds: 15) }
            }

            Spacer(minLength: 0)   // r6: «SIGUE» baja hasta el fondo, con su margen del contenedor
            focusRestNextCard
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// «<ejercicio> · serie N ✓» — the just-completed set, for orientation while the screen is all green.
    private var focusRestCaption: String {
        guard session.runs.indices.contains(session.currentIndex) else { return String(localized: "Rest") }
        let run = session.runs[session.currentIndex]
        let doneIndex = run.currentSet - 1
        guard run.sets.indices.contains(doneIndex) else { return run.name }
        let n = run.sets.prefix(doneIndex + 1).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
        return "\(run.name) · " + String(localized: "set \(n)") + " ✓"
    }

    /// Tiempo/FC segmented toggle (FER-934 §3.2) — only shown when the active rest actually resolved a
    /// heart-rate target; a fixed-time rest has nothing to switch to. Defaults to FC (`nil` ≙ true).
    @ViewBuilder private var focusRestModeToggle: some View {
        // r7: el toggle vive SIEMPRE en el descanso (handoff) — en descansos por tiempo arranca en
        // «Tiempo»; la pestaña FC muestra el pulso en vivo (y cae a tiempo si no hay señal).
        Group {
            let showsHR = focusRestShowsHR ?? (session.currentRestMode == .heartRate)
            HStack(spacing: 2) {
                focusRestModeTab(String(localized: "Time"), systemImage: "timer", active: !showsHR) {
                    focusRestShowsHR = false
                }
                focusRestModeTab(String(localized: "HR"), systemImage: "heart.fill", active: showsHR) {
                    focusRestShowsHR = true
                }
            }
            .padding(3)
            // r6: rectangular como el handoff — misma gramática que el selector global.
            .background(theme.paper.opacity(StrandOpacity.tintFillStrong),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// El héroe del descanso respeta el toggle también en descansos POR TIEMPO (r7): si el usuario
    /// pide FC y hay pulso, lo enseña aunque el descanso sea fijo.
    private var focusRestWantsHR: Bool { focusRestShowsHR ?? (session.currentRestMode == .heartRate) }

    private func focusRestModeTab(_ label: String, systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(StrandFont.caption).fontWeight(.semibold)
                .foregroundStyle(active ? theme.dataRecovery : theme.paper)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? theme.paper : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func focusRestHRHero(elapsed: Int, readiness v: RestReadiness) -> some View {
        let bpm = model.bpm ?? 0
        let target = session.currentRestTarget
        let ready = v.ready
        return VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            if ready {
                Text("Ready")
                    .instrumentoHero(76).foregroundStyle(theme.paper)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.gap) {
                    Text("\(bpm)").instrumentoHero(100).monospacedDigit().foregroundStyle(theme.paper)
                    Text("bpm").font(StrandFont.headline).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
                }
            }
            if let target, !ready {
                (Text(String(localized: "dropping toward "))
                 + Text("\(target) bpm").bold()
                 + Text(" · " + String(localized: "the strap will buzz")))
                    .font(StrandFont.caption).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
            } else if let toReady = v.bpmToReady, !ready {
                Text("\(toReady) bpm to ready")
                    .font(StrandFont.subhead).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
            }
            focusRestHRTrack(bpm: bpm, target: target)
            Text("\(Self.clock(elapsed)) " + String(localized: "of rest · the strap buzzes on arrival"))
                .font(StrandFont.caption).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func focusRestTimeHero(end: Date?, now: Date, noStrapFallback: Bool) -> some View {
        let cappedEnd = noStrapFallback
            ? min(end ?? now, (session.restStartedAt ?? now).addingTimeInterval(300))
            : end
        let remaining = cappedEnd.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) } ?? 0
        let total = max(1, cappedEnd.map { Int($0.timeIntervalSince(session.restStartedAt ?? now)) } ?? remaining)
        return VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            ZStack {
                Circle().stroke(theme.paper.opacity(0.22), lineWidth: 10)  // token-exempt: pista sin llenar del anillo de progreso (geometría, FER-934)
                Circle()
                    .trim(from: 0, to: max(0, min(1, Double(remaining) / Double(total))))
                    .stroke(theme.paper, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(Self.clock(remaining))
                        .instrumentoHero(72).monospacedDigit().foregroundStyle(theme.paper)
                        .contentTransition(.numericText())
                    Text(String(localized: "of \(total) s"))
                        .font(StrandFont.caption).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
                }
            }
            .frame(width: 232, height: 232)
            .frame(maxWidth: .infinity)
            Text(noStrapFallback ? String(localized: "No strap signal: resting by time, 5 min cap")
                                  : String(localized: "Rings and buzzes when it ends."))
                .font(StrandFont.caption).foregroundStyle(theme.paper.opacity(StrandOpacity.muted))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(remaining == 0 ? "Rest done" : "Resting, \(remaining) seconds left"))
    }

    /// Focus-mode FC track (FER-934): crema-on-green variant of `restHRTrack`, kept separate so the
    /// shared inline-card track (dataHeart→dataRecovery gradient) is untouched.
    private func focusRestHRTrack(bpm: Int, target: Int?) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let hi = Double((target ?? bpm) + 40)
            let lo = Double(target ?? bpm)
            let frac = hi > lo ? max(0, min(1, (hi - Double(bpm)) / (hi - lo))) : 1
            ZStack(alignment: .leading) {
                Capsule().fill(theme.paper.opacity(0.22))  // token-exempt: pista sin llenar de la barra de FC (geometría, FER-934)
                Capsule().fill(theme.paper).frame(width: w * frac)
                Rectangle().fill(theme.paper).frame(width: 2, height: 14)
                    .offset(x: w - 1)
            }
        }
        .frame(height: 6)
    }

    private func focusRestAdjust(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(StrandFont.headline).monospacedDigit().foregroundStyle(theme.paper)
                .frame(width: 56)
                .padding(.vertical, CenitMetrics.sectionGap)
                .background(theme.paper.opacity(StrandOpacity.tintFillStrong), in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                    .strokeBorder(theme.paper.opacity(StrandOpacity.strokeSoft), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label == "−15" ? "Subtract 15 seconds" : "Add 15 seconds"))
    }

    /// «SIGUE» card (FER-934 §3.6): the next real step, derived the same way the inline UI derives it —
    /// `registerCurrentSet` already advanced `session.current`/`currentSet` before starting this rest, so
    /// it reflects either the next set of the active exercise or the next exercise once this one is done.
    @ViewBuilder private var focusRestNextCard: some View {
        if let run = session.current {
            let si = run.currentSet
            let n = run.sets.prefix(si + 1).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
            let load = run.sets.indices.contains(si) ? run.sets[si].weightKg : nil
            HStack(spacing: 12) {
                // Canvas pass 2026-07-15: the next exercise's thumbnail rides the SIGUE card.
                SessionRunThumb(exerciseId: run.exerciseId, side: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next").font(StrandFont.caption).fontWeight(.semibold)
                        .tracking(0.8).textCase(.uppercase).foregroundStyle(theme.paper.opacity(0.6))
                    if let load, load > 0 {
                        Text("\(run.name) · " + String(localized: "set \(n)") + " · \(massText(load))")
                            .font(StrandFont.subhead).foregroundStyle(theme.paper)
                    } else {
                        Text("\(run.name) · " + String(localized: "set \(n)"))
                            .font(StrandFont.subhead).foregroundStyle(theme.paper)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(theme.paper.opacity(StrandOpacity.tintFillStrong), in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        }
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

    /// The counter line with the handoff's typographic contrast (canvas pass 2026-07-15): values in
    /// Grotesk bold, labels/separators in light secondary ink. An HStack of small Texts (not one
    /// concatenated Text) so the type-checker stays fast. Same data as `counterLine` (the a11y read).
    private var counterLineStyled: some View {
        let done = "\(session.doneCount)/\(sessionSetsTotal)"
        let kcal = liveKcal
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            counterValue(massText(sessionVolumeKg))
            counterDot
            counterValue(done)
            counterLabel(String(localized: "series"))
            if let kcal {
                counterDot
                counterValue("~\(kcal)")
                counterLabel("kcal")
            }
        }
    }

    private func counterValue(_ s: String) -> some View {
        Text(s).font(InstrumentoType.groteskNumber(15)).monospacedDigit().foregroundStyle(theme.ink)
    }
    private func counterLabel(_ s: String) -> some View {
        Text(s).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
    }
    private var counterDot: some View {
        Text(verbatim: "·").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
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

    /// Today's recovery score (nil while calibrating) — feeds the muscle-fatigue readiness map.
    private var recovery: Double? { model.repo.today?.recovery }

    /// The Apple Watch mirror line (FER-742): «Reloj grabando» when the watch confirms; «El reloj no
    /// respondió» + «Reintentar» on a first miss; «Sin reloj esta sesión» once the retry is spent. Nothing
    /// while the mirror is off, absent, or still connecting — the tertiary ink keeps it out of the way.
    @ViewBuilder
    private var watchStatusLine: some View {
        switch model.watchSessionStatus {
        case .notResponding:
            watchLine("applewatch.slash", "The watch didn't respond", retry: true)
        case .unavailable:
            watchLine("applewatch.slash", "No watch this session", retry: false)
        case .recording, .inactive, .waiting:
            // v21: normal states (including a healthy «recording» mirror) cost no row — silent unless it fails.
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
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            HStack(spacing: 12) {
                SessionRunThumb(exerciseId: run.exerciseId)   // baked still fills the FER-751 slot
                    // Canvas pass 2026-07-15: the category dot is ANCHORED to the thumbnail itself —
                    // drawn as its overlay, vertically centered by construction (no offset math to
                    // drift), pushed left into the rail lane (thumb leading sits 31pt right of it).

                VStack(alignment: .leading, spacing: 2) {
                supersetTag(ei)
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
                        StrandIcon.disclosure.image
                            .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(run.name))
                .accessibilityHint(Text("View exercise detail"))
                }
                exerciseMenuButton(ei: ei, run: run)
                reorderHandle(ei: ei, run: run)
            }
            // FER-933: long-press the active exercise's header also enters modo mover — same entry as the
            // compressed rail rows (`doneRow`/`comingRow`).
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                withAnimation(.snappy) { reorderMode = true }
            })
            // FER-E · 2b: the earned raise, named where you train. «↑ hoy 102,5 · por qué» toggles the
            // arithmetic card; green because the raise IS the datum.
            if let raise = run.proposedRaise {
                raiseLine(raise, ei: ei)
                if whyRaiseOpen.contains(run.id) { whyRaiseCard(raise, ei: ei) }
            }
            HStack(spacing: 8) {
                restChip(run, ei: ei)
                noteChip(run, ei: ei)
            }
            supersetNoRestCaption(ei)
            if !reflow { columnHeader(run.type) }
        }
        .padding(.top, first ? CenitMetrics.gap : CenitMetrics.sectionGap)
    }

    /// «SIN DESCANSO ENTRE A1 Y A2» — shown only on the active block, only while it's a superset member
    /// that isn't the group's last (FER-931; the last member rests normally, so gets no caption).
    @ViewBuilder private func supersetNoRestCaption(_ ei: Int) -> some View {
        let members = session.supersetMembers(at: ei)
        if members.count > 1, members.last != ei,
           let currentBadge = supersetBadgeText(ei: ei),
           let nextIndex = members.first(where: { $0 > ei }), let nextBadge = supersetBadgeText(ei: nextIndex) {
            Text(String(format: String(localized: "NO REST BETWEEN %@ AND %@"), currentBadge, nextBadge))
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.dataHrv)
        }
    }

    /// The «···» exercise menu (FER-894 · «Cómo llego a Cambiar»): a themed paper menu (spec 4b) with
    /// View / Change / Skip / Remove. Reorder stays the drag handle (`reorderHandle`), never duplicated here.
    @ViewBuilder private func exerciseMenuButton(ei: Int, run: StrengthSessionModel.ExerciseRun) -> some View {
        Button { menuExerciseIndex = ei } label: {
            Image(systemName: "ellipsis")
                .font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(ei == session.currentIndex ? theme.dataStrain : theme.inkTertiary)
                .frame(width: 30, height: 44)
                .background {
                    // FER-936 tapRing: the active exercise's «···» wears a gently breathing ember ring,
                    // inviting a tap (menu holds Change / Reorder / Skip). Static under Reduce Motion.
                    if ei == session.currentIndex {
                        TapRing(color: theme.dataStrain, animated: !reduceMotion)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("More options for \(run.name)"))
        .paperMenu(
            isPresented: Binding(get: { menuExerciseIndex == ei },
                                 set: { if !$0 { menuExerciseIndex = nil } }),
            items: exerciseMenuItems(ei: ei, run: run)
        )
    }

    /// Canvas pass 2026-07-15: the handoff's `_ExMenu` set, in its order — Subir · Bajar · Añadir
    /// calentamiento · Superserie con el siguiente · Progresión (estado) · Cambiar · Quitar. «Ver
    /// ejercicio» dropped (tapping the name already opens it); «Saltar»/«Reordenar» dropped per the
    /// owner's explicit list (modo mover keeps its long-press entry).
    private func exerciseMenuItems(ei: Int, run: StrengthSessionModel.ExerciseRun) -> [PaperMenuItem] {
        var rows: [PaperMenuItem] = []
        if ei > 0 {
            rows.append(.init(String(localized: "Move up"), systemImage: "arrow.up") {
                withAnimation(.snappy) { reorderExercise(ei, by: -1) }
            })
        }
        if ei < session.runs.count - 1 {
            rows.append(.init(String(localized: "Move down"), systemImage: "arrow.down") {
                withAnimation(.snappy) { reorderExercise(ei, by: 1) }
            })
        }
        rows.append(.init(String(localized: "Add warm-up"), systemImage: "flame") {
            openPlates(ei: ei, si: min(run.currentSet, max(0, run.sets.count - 1)))
        })
        if ei < session.runs.count - 1 {
            let paired = run.supersetGroup != nil && run.supersetGroup == session.runs[ei + 1].supersetGroup
            rows.append(.init(String(localized: paired ? "Undo superset" : "Superset with next"),
                              systemImage: "link") {
                withAnimation(.snappy) { session.toggleSupersetWithNext(ei) }
            })
        }
        rows.append(.init(String(localized: "Progression"),
                          subtitle: progressionSubtitle(run),
                          systemImage: "chart.line.uptrend.xyaxis") {
            progressionEdit = ProgressionEditTarget(id: ei)
        })
        rows.append(.init(String(localized: "Change exercise"), systemImage: "arrow.triangle.2.circlepath") {
            changeExercise = ChangeTarget(ei: ei, run: run)
        })
        // Never leave the session empty — the last exercise can't be removed.
        if session.runs.count > 1 {
            rows.append(.init(String(localized: "Remove from session"), systemImage: "trash", isDestructive: true) {
                withAnimation(.snappy) { session.removeExercise(at: ei) }
            })
        }
        return rows
    }

    /// «activada · +2,5 kg cada 2 ✓» / «desactivada» — the progression state, read from the backing
    /// routine (cached at open; the session run doesn't carry progression config).
    private func progressionSubtitle(_ run: StrengthSessionModel.ExerciseRun) -> String {
        guard let re = routineREs[run.id] else { return String(localized: "off") }
        guard re.progressionEnabled else { return String(localized: "off") }
        let inc = re.progressionIncrementKg ?? 2.5
        return String(localized: "on") + " · +\(plateNumber(displayWeight(inc))) " +
               UnitFormatter.massUnit(units) + " " + String(localized: "every \(re.progressionSessions)") + " ✓"
    }

    /// The always-on, tenue reorder affordance (Sesión v21): a «≡» handle on each exercise header. Dragging
    /// it up/down reorders the exercise directly, riding the existing swap logic (`moveExerciseEarlier`,
    /// which keeps the focused exercise focused) — the same reorder the plan navigator exposes, now with a
    /// visible grab. VoiceOver gets explicit move-earlier / move-later actions since a drag isn't reachable.
    private func reorderHandle(ei: Int, run: StrengthSessionModel.ExerciseRun) -> some View {
        let hinted = reorderHint == ei
        return Image(systemName: "line.3.horizontal")
            .font(StrandFont.glyph(.chevron))
            .foregroundStyle(hinted ? theme.dataStrain : theme.inkTertiary)
            .scaleEffect(hinted ? 1.18 : 1)
            .animation(.snappy, value: hinted)
            .frame(width: 30, height: 44)
            .contentShape(Rectangle())
            // FER-936: the ember nudge from the menu fades on its own after a couple of seconds.
            .task(id: reorderHint) {
                guard reorderHint == ei else { return }
                try? await Task.sleep(for: .seconds(2.5))
                if reorderHint == ei { withAnimation(.snappy) { reorderHint = nil } }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 6)
                    .onEnded { value in
                        // Translate the vertical drag into whole-slot moves (~one exercise row per step).
                        let step: CGFloat = 56
                        let steps = Int((value.translation.height / step).rounded())
                        if steps != 0 { withAnimation(.snappy) { reorderExercise(ei, by: steps) } }
                    }
            )
            .accessibilityLabel(Text("Reorder \(run.name)"))
            .accessibilityHint(Text("Drag to change the order"))
            .accessibilityAction(named: Text("Move earlier")) {
                withAnimation(.snappy) { reorderExercise(ei, by: -1) }
            }
            .accessibilityAction(named: Text("Move later")) {
                withAnimation(.snappy) { reorderExercise(ei, by: 1) }
            }
    }

    /// Move the exercise at `ei` by `steps` slots (negative = earlier, positive = later), one swap at a time.
    /// Both directions ride the existing `moveExerciseEarlier` swap (moving a slot later == pulling the next
    /// one earlier), so the session engine and its focus tracking stay the single source of truth.
    private func reorderExercise(_ ei: Int, by steps: Int) {
        guard steps != 0 else { return }
        var idx = ei
        if steps < 0 {
            for _ in 0..<(-steps) where idx > 0 { session.moveExerciseEarlier(idx); idx -= 1 }
        } else {
            for _ in 0..<steps where idx < session.runs.count - 1 { session.moveExerciseEarlier(idx + 1); idx += 1 }
        }
    }

    // MARK: Modo mover (FER-933) — handoff `_ListScreen.dc.html` reorder state, adopted on the riel.

    /// The mode bar above the list: overline «MOVIENDO · ARRASTRA SOBRE EL RIEL» (ember) + «Listo» (verde).
    private var reorderModeBar: some View {
        HStack {
            Text("MOVING · DRAG ALONG THE RAIL")
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.dataStrain)
            Spacer()
            Button {
                withAnimation(.snappy) {
                    reorderMode = false
                    reorderDraggingIndex = nil
                    reorderTargetIndex = nil
                }
            } label: {
                Text("Done").font(StrandFont.caption.weight(.semibold)).foregroundStyle(theme.dataRecovery)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Done reordering"))
        }
    }

    /// Clamp `ei + steps` to a valid slot — the same bound `reorderExercise` enforces one swap at a time,
    /// computed up front here purely to label the drop zone while dragging.
    private func reorderClampedTarget(_ ei: Int, steps: Int) -> Int {
        max(0, min(session.runs.count - 1, ei + steps))
    }

    /// The dashed ember drop zone, «SOLTAR AQUÍ · POSICIÓN N» (1-based), shown at the slot a live drag
    /// would land on.
    private func reorderDropZone(position: Int) -> some View {
        Text(String(format: String(localized: "DROP HERE · POSITION %d"), position + 1))
            .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
            .foregroundStyle(theme.dataStrain)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(theme.dataStrain.opacity(0.06), in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))  // token-exempt: decorative drop-zone tint alpha
            .overlay {
                RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                    .strokeBorder(theme.dataStrain, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            .padding(.bottom, 6)
            .accessibilityHidden(true)
    }

    /// One exercise, compressed to a single draggable line in modo mover: dot handle + name + its current
    /// prescription/done detail. A vertical `DragGesture` rides the same slot-stepping `reorderExercise`
    /// the always-on «≡» handle uses; the row that's mid-drag lifts (scale + rotate + ember border +
    /// shadow), the rest dim, and `reorderDropZone` renders above the destination slot. Reduce Motion drops
    /// the scale/rotation, keeping only the border + soft shadow.
    private func reorderRow(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        let dragging = reorderDraggingIndex == ei
        let anyDragging = reorderDraggingIndex != nil
        return VStack(spacing: 0) {
            if let target = reorderTargetIndex, target == ei, !dragging {
                reorderDropZone(position: target)
            }
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                Text(run.name).font(StrandFont.body).foregroundStyle(theme.ink).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(run.sets.allSatisfy(\.done) ? doneDetailText(run) : prescriptionText(run))
                    .font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                    .strokeBorder(dragging ? theme.dataStrain : theme.hairlineStrong, lineWidth: dragging ? 2 : 1)
            }
            .shadow(color: dragging ? theme.dataStrain.opacity(0.25) : .clear,  // token-exempt: decorative lift-shadow alpha
                    radius: dragging ? 10 : 0, y: dragging ? 4 : 0)
            .scaleEffect(dragging && !reduceMotion ? 1.03 : 1)
            .rotationEffect(.degrees(dragging && !reduceMotion ? -1 : 0))
            .opacity(anyDragging && !dragging ? StrandOpacity.dim : 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        reorderDraggingIndex = ei
                        let step: CGFloat = 56
                        let steps = Int((value.translation.height / step).rounded())
                        reorderTargetIndex = reorderClampedTarget(ei, steps: steps)
                    }
                    .onEnded { value in
                        let step: CGFloat = 56
                        let steps = Int((value.translation.height / step).rounded())
                        if steps != 0 { withAnimation(.snappy) { reorderExercise(ei, by: steps) } }
                        reorderDraggingIndex = nil
                        reorderTargetIndex = nil
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(run.name))
            .accessibilityHint(Text("Drag to change the order"))
            .accessibilityAction(named: Text("Move earlier")) {
                withAnimation(.snappy) { reorderExercise(ei, by: -1) }
            }
            .accessibilityAction(named: Text("Move later")) {
                withAnimation(.snappy) { reorderExercise(ei, by: 1) }
            }
        }
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
                StrandIcon.up.image
                    .font(StrandFont.glyph(.chevron, weight: .bold))
                Text("today \(massText(raise.toKg))")
                    .font(InstrumentoType.grotesk(12, weight: .bold)).monospacedDigit()
                Text("·").foregroundStyle(theme.inkTertiary)
                Text("why")
                    .font(InstrumentoType.grotesk(12, weight: .bold))
                    .underline(pattern: .dot, color: theme.dataRecovery.opacity(0.55))   // token-exempt: subrayado punteado decorativo
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
        NoteStrip(style: .info, theme: theme) {
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
        }
    }

    /// The per-session opt-out («Volver a X»): undone cells go back to the old weight; done sets keep
    /// whatever was actually lifted. The session is persisted as opted-out (FER-835), so the cycle
    /// ignores it entirely — neither hit nor miss; the earned raise is proposed again next session.
    private func revertRaise(ei: Int) {
        guard session.runs.indices.contains(ei),
              let raise = session.runs[ei].proposedRaise else { return }
        withAnimation(StrandMotion.interactive) {
            for si in session.runs[ei].sets.indices where !session.runs[ei].sets[si].done {
                session.runs[ei].sets[si].weightKg = raise.fromKg
            }
            session.runs[ei].proposedRaise = nil
            session.runs[ei].raiseOptedOut = true
            whyRaiseOpen.remove(session.runs[ei].id)
        }
    }

    /// A quiet, tappable chip showing this exercise's rest — tap to edit it mid-session (FER-540).
    private func restChip(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        Button { openRestEditor(ei: ei) } label: {
            HStack(spacing: 6) {
                StrandIcon.clock.image.font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                Text(restChipLabel(run)).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
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

    /// The «✎ Nota» chip (FER-932), next to the rest chip on the active exercise's header. Opens
    /// `NoteSheet` without touching `restEndsAt` — a running rest keeps counting behind it. Fills when
    /// this run (or any of its sets) already carries a note.
    private func noteChip(_ run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        Button { openNote(exercise: run, ei: ei) } label: {
            HStack(spacing: 6) {
                Image(systemName: run.hasNote ? "square.and.pencil" : "square.and.pencil")
                    .font(StrandFont.glyph(.chevron)).foregroundStyle(run.hasNote ? theme.dataStrain : theme.inkTertiary)
                Text("Note").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                if run.hasNote {
                    Circle().fill(theme.dataStrain).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(run.hasNote ? "Edit note, has a note" : "Add note"))
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

    /// Open the note sheet (FER-932) for the active exercise, from the «✎ Nota» chip. Never touches
    /// `restEndsAt` — a running rest keeps counting behind the sheet. Loads the cross-session history
    /// (`exerciseNotes(excludingSession:)`) fresh each open so a note saved elsewhere shows up.
    private func openNote(exercise run: StrengthSessionModel.ExerciseRun, ei: Int) {
        let setNumber = min(run.currentSet + 1, max(run.sets.count, 1))
        let setId = run.sets.indices.contains(run.currentSet) ? run.sets[run.currentSet].id : (run.sets.first?.id ?? "")
        noteTarget = NoteTarget(id: run.id, exerciseId: run.exerciseId, exerciseName: run.name,
                                 setId: setId, setNumber: setNumber)
        noteHistory = nil
        Task {
            guard let store = await model.repo.storeHandle() else { return }
            let history = (try? await store.exerciseNotes(exerciseId: run.exerciseId,
                                                           excludingSession: session.id)) ?? []
            await MainActor.run { noteHistory = history }
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
            // Canvas pass 2026-07-15: «PREVIOUS · REST» truncated to an unreadable «PR…» at narrow
            // widths — the rest already lives on each row's own cell, so the column header only needs
            // to name the previous value.
            Text("PREVIOUS").instrumentoOverline().foregroundStyle(theme.inkTertiary)
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
        case .weightReps: return [massUnitTitle, "REPS", "RPE"]
        case .bodyweight: return ["+LOAD", "REPS", "RPE"]
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
        // r6: sin resaltado de fila (desbordaba el borde de la tarjeta) — la serie en curso se marca
        // solo con su numeral subrayado. El divisor vive a nivel rebanada (recibo, borde a borde).
        .overlay {
            // FER-938: a dashed ember outline marks a just-copied, not-yet-logged set.
            if set.id == copiedSetId, !set.done {
                RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.dataStrain, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            Button("Delete set") { withAnimation(.snappy) { session.removeSet(exercise: ei, set: si) } }
        }
    }

    private func gridRow(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                         set: StrengthSessionModel.WorkingSet) -> some View {
        HStack(spacing: 8) {
            badge(run: run, si: si)
            if set.id == copiedSetId, !set.done, si > 0 {
                // FER-938: the freshly-added set advertises where its values came from, in place of «anterior».
                let fromNumber = run.sets.prefix(si).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
                Text("COPIED FROM \(fromNumber)").instrumentoOverline().foregroundStyle(theme.dataStrain)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                previousCell(ei: ei, si: si, run: run)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            dataCells(ei: ei, si: si, run: run, set: set)
            checkButton(ei: ei, si: si, set: set)
        }
    }

    private func reflowRow(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                           set: StrengthSessionModel.WorkingSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                badge(run: run, si: si)
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
                badge(run: run, si: si)
                // The clock — ticks live while running, else shows the captured time.
                Group {
                    if running {
                        TimelineView(.periodic(from: Date(), by: 1)) { ctx in cardioClock(session.timerElapsed(now: ctx.date)) }
                    } else {
                        cardioClock(set.timeS ?? 0)
                    }
                }
                Spacer(minLength: 8)
                startStopButton(running: running)
                checkButton(ei: ei, si: si, set: set)
            }
            // The live intensity scale: the whole Z1–Z5 ramp with the current zone lit, «N% of your max»
            // beneath (FER-894 · Estados 2). Only appears with a strap reading — no dashes, no empty ramp.
            PulseReader(model.live.pulse) { p in
                if let hr = p.smoothedBpm { hrZoneRampRow(hr) }
            }
            if run.type == .distance { distanceStepperRow(set.distanceM ?? 0) }
        }
        .frame(minHeight: run.type == .distance ? 150 : 118)
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
                running ? registerActiveSet()
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

    /// The live HR intensity as a full Z1–Z5 ramp (FER-894 · Estados 2): five segments, the current zone lit
    /// in its `hrZoneRamp` hue, with «♥ bpm · N% of your max» beneath. Replaces the single-zone chip so the
    /// whole scale — and how far into it you are — is legible at a glance. Hidden when there's no strap.
    /// Paleta compartida: `InstrumentoTheme.hrZoneRamp`. 1 de 3 superficies de zonas HR distintas (aquí = intensidad ahora; WorkoutDetailScreen = %-tiempo; MetricDetailScreen = minutos) — NO se unifican, solo comparten la paleta (FER-908).
    private func hrZoneRampRow(_ hr: Int) -> some View {
        let zone = hrZone(hr)
        let maxHR = Double(model.profile.hrMax)
        let pct = maxHR > 0 ? Int((Double(hr) / maxHR * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { z in
                    let hue = theme.hrZoneRamp[z - 1]
                    let lit = z == zone
                    Text("Z\(z)")
                        .font(StrandFont.caption).monospacedDigit()
                        .foregroundStyle(lit ? theme.paper : theme.inkTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(lit ? hue : theme.surface,
                                    in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: lit ? 0 : 1))
                }
            }
            HStack(spacing: 5) {
                StrandIcon.heart.image.font(StrandFont.glyph(.chevron)).foregroundStyle(theme.hrZoneRamp[zone - 1])
                Text("\(hr)").font(StrandFont.subhead.monospacedDigit()).foregroundStyle(theme.ink)
                Text("·").foregroundStyle(theme.inkTertiary)
                Text("\(pct)% of your max").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Heart rate \(hr), zone \(zone), \(pct) percent of your maximum"))
    }

    private func distanceStepperRow(_ meters: Double) -> some View {
        HStack(spacing: 14) {
            stepper(system: "minus", size: 26) { session.bumpDistance(byMeters: -distanceStepM) }
                .accessibilityLabel(Text("Decrease distance"))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(distanceNumber(meters)).font(InstrumentoType.groteskNumber(18, weight: .medium)).monospacedDigit()
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
            // (El «SIGUE» vive solo en el descanso a pantalla completa — owner call 2026-07-15: dentro
            // del mismo ejercicio ya sabes qué sigue, la tarjeta en línea no lo repite.)
        }
        .padding(.horizontal, 17).padding(.vertical, 15)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
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
    /// The set's number badge. FER-937: a warm-up set shows a «C» (calentamiento) in a tenue ring and does
    /// not consume a work-set number; work sets are numbered 1..n counting only `.work` rows, so a warm-up
    /// never pushes «serie 1» to «serie 3».
    private func badge(run: StrengthSessionModel.ExerciseRun, si: Int) -> some View {
        let isWarmup = run.sets[si].kind == .warmup
        let workNumber = run.sets.prefix(si + 1).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
        let label = isWarmup ? String(localized: "C") : "\(workNumber)"
        // Canvas pass (propuesta C): the set being worked RIGHT NOW wears a 2pt ink underline beneath
        // its numeral — the same ink language as the block's rule, no color accent, survives
        // «Differentiate without color» by shape alone.
        let isCurrent = si == run.currentSet && !run.sets[si].done
        return Text(label).font(InstrumentoType.groteskNumber(12, weight: .medium)).monospacedDigit()
            .foregroundStyle(isWarmup ? theme.dataStrain.opacity(StrandOpacity.dim) : theme.dataStrain)  // token-exempt: warm-up badge tenue (handoff «C»)
            .frame(width: 26, height: 26)
            .overlay(Circle().strokeBorder(theme.dataStrain.opacity(isWarmup ? StrandOpacity.dim : 1), lineWidth: 1.5))  // token-exempt: warm-up ring tenue
            .overlay(alignment: .bottom) {
                if isCurrent, !isWarmup {
                    Rectangle().fill(theme.ink).frame(width: 16, height: 2).offset(y: 5)
                }
            }
            .frame(width: reflow ? 26 : 44, height: reflow ? 26 : 44, alignment: .center)
            .accessibilityLabel(Text(isWarmup ? "Warm-up set" : "Set \(workNumber)"))
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
            Text(verbatim: "— · \(rest)").font(StrandFont.caption).foregroundStyle(theme.inkDim) // token-exempt: glifo «sin registro previo» (—), no es copy conector
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
            rpeCell(ei: ei, si: si, run: run, set: set)
        case .bodyweight:
            HStack(spacing: 1) {
                Text("+").font(StrandFont.body).foregroundStyle(set.done ? theme.inkSecondary : theme.inkTertiary)
                numberCell(.weight(ei, si), value: displayWeight(set.weightKg), isInt: false, done: set.done, type: run.type, width: run.type == .bodyweight ? 48 : 56)
            }
            .frame(width: reflow ? nil : cellWidth(run.type), alignment: reflow ? .leading : .center)
            numberCell(.reps(ei, si), value: Double(set.reps), isInt: true, done: set.done, type: run.type)
            rpeCell(ei: ei, si: si, run: run, set: set)
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
        // Canvas pass 2026-07-15 (UX·anim #1): opening the keypad animates like closing it — the
        // `.move(edge: .bottom)` transition only runs inside withAnimation; bare assignment popped.
        return Button { withAnimation(.snappy(duration: 0.22)) { activeCell = ref } } label: {
            HStack(spacing: 1) {
                Text(shown.isEmpty ? " " : shown)
                    .font(InstrumentoType.groteskNumber(16, weight: .medium)).monospacedDigit()
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

    /// The RPE cell (FER-930): tap opens the RPE sheet for this set. Shows the captured value in
    /// `dataEffort` (the datum's own color) when set, else a tenue «RPE» placeholder — never a nag, never
    /// blocking the check button next to it. Entirely independent of `done`.
    private func rpeCell(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun,
                         set: StrengthSessionModel.WorkingSet) -> some View {
        Button {
            rpeTarget = RPETarget(id: set.id, runId: run.id, setNumber: si + 1,
                                  weightKg: displayWeight(set.weightKg), reps: set.reps, currentRPE: set.rpe)
        } label: {
            Group {
                if let rpe = set.rpe {
                    Text(Self.formatDecimalComma(rpe))
                        .font(InstrumentoType.groteskNumber(16, weight: .medium)).monospacedDigit()
                        .foregroundStyle(theme.dataEffort)
                } else {
                    Text("RPE").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                }
            }
            .frame(width: reflow ? nil : cellWidth(run.type), height: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.hairline).frame(height: 1).padding(.bottom, 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("RPE"))
        .accessibilityValue(Text(set.rpe.map(Self.formatDecimalComma) ?? String(localized: "Not recorded")))
    }

    /// es-MX decimal formatting: comma decimal, no trailing zero on whole numbers (8, not 8,0; 8,5).
    /// Shared by RPE values and, in `RPESheet`, the set's weight (FER-930).
    static func formatDecimalComma(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// A captured (non-typed) time / distance cell — tap to select the row, which expands it inline with the
    /// stopwatch (FER-716: the Foco is gone). Shows «—» until set.
    private func capturedCell(ei: Int, si: Int, run: StrengthSessionModel.ExerciseRun, text: String?) -> some View {
        Button { withAnimation(StrandMotion.gentle) { session.select(exerciseIndex: ei, setIndex: si) } } label: {
            Group {
                if let text {
                    Text(text).font(InstrumentoType.groteskNumber(16, weight: .medium)).monospacedDigit().foregroundStyle(theme.ink)
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
                if isActivePending { activeCell = nil; registerActiveSet() }
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
        Button {
            // Canvas pass 2026-07-15: a contained, gentle open — ONE row's worth of space, not a leap
            // (owner: «que se abra solamente con un nuevo renglón»).
            withAnimation(StrandMotion.gentle) { session.addSet(exercise: ei) }
            copiedSetId = session.runs.indices.contains(ei) ? session.runs[ei].sets.last?.id : nil  // FER-938
        } label: {
            // Canvas pass 2026-07-15: the handoff's ember «+ Serie» pill, living INSIDE the card as its
            // closing row (top hairline separates it from the last set).
            HStack {
                Label("Add set", systemImage: "plus")
                    .font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.paper)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(theme.dataStrain, in: Capsule())
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty ad-hoc state (mock 1p, FER-762)

    private var emptyAdHocSession: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("No routine: add exercises as you go. Rest defaults to 2 min, change it set by set.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button { showLibraryPicker = true } label: {
                    HStack(spacing: 9) {
                        StrandIcon.search.image.font(StrandFont.glyph(.inline)).foregroundStyle(theme.inkTertiary)
                        Text("Search the library…").font(StrandFont.body).foregroundStyle(theme.inkTertiary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13).padding(.vertical, 11)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
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
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
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
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, 16)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .safeAreaInset(edge: .top, spacing: 0) { liveHead }
        .task {
            guard freshSuggestions == nil else { return }
            await loadFreshSuggestions()
        }
    }

    private func suggestionRow(_ s: QuickSuggestion) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                .fill(theme.surface).frame(width: 48, height: 48)
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
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

    /// Add one or more exercises to the session (from a suggestion or the library picker), seeding each
    /// from its last logged set when there's history. The empty ad-hoc state falls away on its own once
    /// `session.runs` isn't empty. FER-935: when the session already has runs (routine-backed or an
    /// ad-hoc session past its first exercise), the picks land right after the active exercise instead of
    /// at the end — iterated in REVERSE so the batch stays contiguous and in the user's chosen order
    /// (each `insertExerciseAfterCurrent` call lands at the same `currentIndex + 1` slot, pushing the
    /// previous insert one further along — see its doc comment).
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
        if session.runs.isEmpty {
            for ex in picks {
                let last = lasts[ex.id]
                session.addExercise(ex, lastWeightKg: last?.0, lastReps: last?.1)
            }
        } else {
            for ex in picks.reversed() {
                let last = lasts[ex.id]
                session.insertExerciseAfterCurrent(ex, lastWeightKg: last?.0, lastReps: last?.1)
            }
            // Canvas pass 2026-07-15 (owner call): the added exercise is PERMANENT — it also lands in
            // the backing routine, right after the active exercise's slot.
            if session.routineId != nil { persistInsertedExercises(picks) }
        }
    }

    /// Persist mid-session additions into the backing routine (after the active exercise's position),
    /// renumbering positions — fire-and-forget; the live session already has its runs.
    private func persistInsertedExercises(_ picks: [Exercise]) {
        guard let rid = session.routineId else { return }
        let activeRunId = session.runs.indices.contains(session.currentIndex)
            ? session.runs[session.currentIndex].id : nil
        Task {
            guard let store = await model.repo.storeHandle(),
                  var res = try? await store.routineExercises(routineId: rid),
                  let routine = (try? await store.routines())?.first(where: { $0.id == rid }) else { return }
            var insertAt = activeRunId.flatMap { id in
                res.firstIndex(where: { $0.id == id }).map { $0 + 1 }
            } ?? res.count
            for ex in picks {
                let re = RoutineExercise(routineId: rid, exerciseId: ex.id, position: insertAt,
                                         targetSets: 1, targetReps: 8,
                                         restMode: .fixed, restSeconds: StrengthSessionModel.adHocRestSeconds)
                res.insert(re, at: min(insertAt, res.count))
                insertAt += 1
            }
            for i in res.indices { res[i].position = i }
            try? await store.saveRoutine(routine, exercises: res)
            await loadRoutineREs()
        }
    }

    /// Load the backing routine's exercises into the menu/progression cache.
    private func loadRoutineREs() async {
        guard let rid = session.routineId, let store = await model.repo.storeHandle() else { return }
        let res = (try? await store.routineExercises(routineId: rid)) ?? []
        routineREs = Dictionary(uniqueKeysWithValues: res.map { ($0.id, $0) })
    }

    /// Persist the FULL progression config (r7 — the real ProgressionSetupScreen fields) into the
    /// backing routine, including the rep goal onto the plan's work sets.
    private func persistProgressionFull(runId: String, enabled: Bool, targetReps: Int, sessions: Int,
                                        incrementKg: Double?, deload: DeloadPolicy, ignoreRecovery: Bool) {
        guard let rid = session.routineId else { return }
        Task {
            guard let store = await model.repo.storeHandle(),
                  var res = try? await store.routineExercises(routineId: rid),
                  let idx = res.firstIndex(where: { $0.id == runId }),
                  let routine = (try? await store.routines())?.first(where: { $0.id == rid }) else { return }
            res[idx].progressionEnabled = enabled
            res[idx].progressionSessions = sessions
            res[idx].progressionIncrementKg = incrementKg
            res[idx].progressionDeload = deload
            res[idx].progressionIgnoreRecovery = ignoreRecovery
            res[idx].targetReps = targetReps
            for i in res[idx].sets.indices where res[idx].sets[i].kind == .work {
                res[idx].sets[i].reps = targetReps
            }
            try? await store.saveRoutine(routine, exercises: res)
            routineREs[res[idx].id] = res[idx]
        }
    }

    /// Discard the empty ad-hoc session (its «Descartar» pill, FER-762). Nothing was logged, so instead of a
    /// destructive confirmation this shows a calm terminal result — «Nothing to save» (FER-894 · Estados 2) —
    /// and only ends the session when the user taps «Got it». A result state, not a warning.
    private func discardEmptySession() {
        withAnimation(.snappy) { nothingToSave = true }
    }

    /// The «Nothing to save · your history stays clean» result card (FER-894). Terminal state for an
    /// empty-session discard: no numbers to celebrate, just reassurance that nothing was recorded.
    private var nothingToSaveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal")
                .font(StrandFont.glyph(.empty)).foregroundStyle(theme.inkSecondary)
                .accessibilityHidden(true)
            Text("Nothing to save").font(StrandFont.title1).foregroundStyle(theme.ink)
            Text("Your history stays clean: no sets were logged this session.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { model.endStrengthSession(save: false) } label: {
                Text("Got it")
                    .font(StrandFont.headline).foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain).padding(.top, 4)
            .accessibilityLabel(Text("Got it, close the session"))
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: Complete + discard footers

    private var completeFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(theme.hairline).frame(height: 1)
            completePhase
        }
    }

    private var discardFooter: some View {
        // Canvas pass 2026-07-15: dressed as the destructive sibling of the header's «Terminar» —
        // same capsule grammar, red by border, never a fill (DNA: primary-by-border).
        Button(role: .destructive) { confirmDiscard = true } label: {
            Text("Discard workout").font(StrandFont.subhead.weight(.medium)).foregroundStyle(theme.critical)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.critical.opacity(StrandOpacity.dim), lineWidth: 1))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
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
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
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

            Button { shareReceipt = ShareRef(sessionId: session.id) } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
                    .font(StrandFont.subhead).fontWeight(.medium)
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous)
                        .strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.top, 6)

            Button { model.closeStrengthSummary() } label: {
                Text("Done")
                    .font(InstrumentoType.grotesk(15, weight: .bold)).tracking(0.3)
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous))
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
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
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
            StrandIcon.up.image.font(StrandFont.glyph(.chevron, weight: .semibold))
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
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
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
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
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
                            StrandIcon.up.image.font(StrandFont.glyph(.inline, weight: .semibold))
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
                .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
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

/// The «Change {exercise}» sheet (FER-894 · «Cómo llego a Cambiar»): a search field over the library plus a
/// shortlist of alternatives for the SAME primary muscle as the exercise being replaced. Picking «Use» swaps
/// it into the live run, keeping the sets already done. Self-contained so the session stays lean; it only
/// reads the catalog (`allExercises` / `resolvedExercise`) — the actual swap is the caller's `onUse`.
// MARK: - RPE sheet (FER-930)
//
// Estilo Hevy, aprobado en el preview v3 del handoff: número héroe grande + descriptor + una escala
// horizontal de pills (6…10, medios pasos) + «Ok ✓» verde. Tocar la celda RPE de una serie abre esto;
// el RPE es SIEMPRE opcional — no hay ningún estado que lo exija para marcar la serie.

struct RPESheet: View {
    let theme: InstrumentoTheme
    let target: LiveStrengthSheet.RPETarget
    let onPick: (Double?) -> Void
    let onClose: () -> Void

    /// The scale offered (canvas pass 2026-07-15, owner trim): 6 stops — 7,5/8,5 dropped, 9,5 kept —
    /// so the whole scale fits ONE row, no slide.
    private static let scale: [Double] = [6, 7, 8, 9, 9.5, 10]

    @State private var selected: Double

    init(theme: InstrumentoTheme, target: LiveStrengthSheet.RPETarget,
         onPick: @escaping (Double?) -> Void, onClose: @escaping () -> Void) {
        self.theme = theme; self.target = target; self.onPick = onPick; self.onClose = onClose
        _selected = State(initialValue: target.currentRPE ?? 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // Canvas pass 2026-07-15: sin ScrollView — con el grid 2×4 todo cabe; más aire arriba
            // (sectionGap) para que el héroe no se pegue a la colilla.
            VStack(spacing: 28) {
                hero
                scale
            }
            .padding(.top, CenitMetrics.sectionGap)
            Spacer(minLength: CenitMetrics.gap)
            okButton
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.bottom, CenitMetrics.screenPadding)
        .background(theme.paper.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                // Canvas pass 2026-07-15: it's a TITLE, not a label — Grotesk bold with real air above.
                Text("RPE").font(InstrumentoType.grotesk(22, weight: .bold)).foregroundStyle(theme.ink)
                Spacer()
                Button(action: onClose) {
                    StrandIcon.close.image.font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(theme.inkSecondary)
                }
                .accessibilityLabel(Text("Close"))
            }
            Text("Set \(target.setNumber) · \(LiveStrengthSheet.formatDecimalComma(target.weightKg)) kg × \(target.reps) reps")
                .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
        }
        .padding(.top, CenitMetrics.sectionGap)
        .padding(.bottom, 8)
    }

    private var hero: some View {
        VStack(spacing: 6) {
            // Canvas pass 2026-07-15 (UI·armonía #1): un solo tamaño de héroe entre hojas hermanas
            // (RPE 84 vs. discos 52 → 64 en ambas).
            Text(LiveStrengthSheet.formatDecimalComma(selected))
                .font(InstrumentoType.grotesk(64, weight: .semibold)).monospacedDigit()
                .foregroundStyle(theme.ink)
            Text(Self.descriptor(selected)).font(StrandFont.headline).foregroundStyle(theme.ink)
            Text(Self.subtitle(selected)).font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var scale: some View {
        // Canvas pass 2026-07-15: the whole scale visible at once — ONE row of six (7,5/8,5 dropped),
        // tiles ≥56pt (HIG), rounded-rect.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                  spacing: CenitMetrics.gap) {
            ForEach(Self.scale, id: \.self) { value in
                let sel = value == selected
                Button {
                    withAnimation(StrandMotion.interactive) { selected = value }
                } label: {
                    Text(LiveStrengthSheet.formatDecimalComma(value))
                        .font(StrandFont.number(17, weight: sel ? .bold : .regular)).monospacedDigit()
                        .foregroundStyle(sel ? theme.paper : theme.inkSecondary)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background {
                            let shape = RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                            if sel { shape.fill(theme.dataEffort) }
                            else { shape.strokeBorder(theme.hairlineStrong, lineWidth: 1) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(sel ? [.isSelected] : [])
            }
        }
    }

    private var okButton: some View {
        VStack(spacing: 8) {
            Button {
                onPick(selected)
            } label: {
                Text("Ok ✓")
                    .font(InstrumentoType.grotesk(17, weight: .semibold))
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(theme.verdictDeep, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("RPE is optional · tap the set's RPE cell")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .padding(.top, 12)
    }

    /// Descriptors (FER-930 spec §3, es-MX in the xcstrings catalog), no prescriptive coaching.
    private static func descriptor(_ v: Double) -> LocalizedStringKey {
        switch v {
        case 6:   return "Moderate effort"
        case 7:   return "Comfortable"
        case 8:   return "Hard effort"
        case 9:   return "Very hard"
        case 9.5: return "Near failure"
        case 10:  return "Maximum"
        default:  return ""   // 7.5 / 8.5: no descriptor of their own, just the subtitle
        }
    }
    private static func subtitle(_ v: Double) -> LocalizedStringKey {
        switch v {
        case 6:   return "You could've done 4+ more reps"
        case 7:   return "~3 more reps"
        case 7.5: return "~2-3 more reps"
        case 8:   return "You had ~2 reps left"
        case 8.5: return "~1-2 more reps"
        case 9:   return "~1 more rep"
        case 9.5: return "Near failure"
        case 10:  return "To failure"
        default:  return ""
        }
    }
}

// MARK: - Note sheet (FER-932)
//
// Preview v3 aprobado del handoff («Nota con color de vuelta»): editor con borde/caret ámbar
// (`dataStrain`), toggle «Guardar en:» exercise/set, «Guardar» verde, historial «NOTAS ANTERIORES»
// separado por hairline (sin tarjeta), omitido si está vacío. Abrir el sheet no toca `restEndsAt`.

/// Canvas pass 2026-07-15 — the exercise menu's «Progresión» mini-sheet: toggle + increment + cadence,
/// persisted to the backing routine. Paper voice; the state line is the dominant datum.
struct ProgressionMiniSheet: View {
    let theme: InstrumentoTheme
    let exerciseName: String
    let units: String
    let stepKg: Double
    let current: RoutineExercise?
    let canPersist: Bool
    let displayKg: (Double) -> Double
    let onApply: (Bool, Double, Int) -> Void
    let onClose: () -> Void

    @State private var enabled: Bool
    @State private var incrementKg: Double
    @State private var every: Int

    init(theme: InstrumentoTheme, exerciseName: String, units: String, stepKg: Double,
         current: RoutineExercise?, canPersist: Bool, displayKg: @escaping (Double) -> Double,
         onApply: @escaping (Bool, Double, Int) -> Void, onClose: @escaping () -> Void) {
        self.theme = theme; self.exerciseName = exerciseName; self.units = units; self.stepKg = stepKg
        self.current = current; self.canPersist = canPersist; self.displayKg = displayKg
        self.onApply = onApply; self.onClose = onClose
        _enabled = State(initialValue: current?.progressionEnabled ?? false)
        _incrementKg = State(initialValue: current?.progressionIncrementKg ?? 2.5)
        _every = State(initialValue: current?.progressionSessions ?? 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PROGRESSION").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text(exerciseName).font(InstrumentoType.grotesk(20, weight: .semibold))
                        .foregroundStyle(theme.ink).lineLimit(2)
                }
                Spacer()
                Button(action: onClose) {
                    StrandIcon.close.image
                        .font(StrandFont.glyph(.inline, weight: .semibold)).foregroundStyle(theme.ink)
                        .frame(width: 34, height: 34)
                        .background(theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
            Toggle(isOn: $enabled) {
                Text("Raise the load automatically").font(StrandFont.subhead).foregroundStyle(theme.ink)
            }
            .tint(theme.dataRecovery)
            HStack {
                Text("Increment").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                Spacer()
                Stepper(value: $incrementKg, in: stepKg...(stepKg * 8), step: stepKg) {
                    Text("+\(plateNumber(displayKg(incrementKg))) \(units)")
                        .font(InstrumentoType.groteskNumber(17)).foregroundStyle(theme.ink)
                }
                .fixedSize()
            }
            .opacity(enabled ? 1 : StrandOpacity.dim)
            HStack {
                Text("Every").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                Spacer()
                Stepper(value: $every, in: 1...5) {
                    Text(String(localized: "\(every) sessions"))
                        .font(InstrumentoType.groteskNumber(17)).foregroundStyle(theme.ink)
                }
                .fixedSize()
            }
            .opacity(enabled ? 1 : StrandOpacity.dim)
            if !canPersist {
                Text("Ad-hoc session: progression lives on saved routines.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: 0)
            Button {
                onApply(enabled, incrementKg, every)
            } label: {
                Text("Apply").font(StrandFont.headline).foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(canPersist ? theme.ink : theme.inkDim, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canPersist)
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, CenitMetrics.gap)
        .padding(.bottom, CenitMetrics.screenPadding)
        .background(theme.paper.ignoresSafeArea())
    }
}

struct NoteSheet: View {
    /// Where a note is saved: the whole exercise (default) or just the active set (FER-932 §4).
    enum Scope { case exercise, set }

    let theme: InstrumentoTheme
    let target: LiveStrengthSheet.NoteTarget
    let initialScope: Scope
    let exerciseText: String
    let setText: String
    /// Cross-session history for this exercise, loaded by the caller. nil = still loading.
    let history: [ExerciseNote]?
    let onSave: (Scope, String) -> Void
    let onClose: () -> Void

    @State private var scope: Scope
    @State private var text: String
    @FocusState private var focused: Bool

    init(theme: InstrumentoTheme, target: LiveStrengthSheet.NoteTarget, initialScope: Scope,
         exerciseText: String, setText: String, history: [ExerciseNote]?,
         onSave: @escaping (Scope, String) -> Void, onClose: @escaping () -> Void) {
        self.theme = theme; self.target = target; self.initialScope = initialScope
        self.exerciseText = exerciseText; self.setText = setText; self.history = history
        self.onSave = onSave; self.onClose = onClose
        _scope = State(initialValue: initialScope)
        _text = State(initialValue: initialScope == .exercise ? exerciseText : setText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            scopeToggle
            editor
            if let history, !history.isEmpty {
                historySection(history)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, 18)   // r6: el grabber se comía el título — aire real arriba (owner)
        .padding(.bottom, CenitMetrics.screenPadding)
        .background(theme.paper.ignoresSafeArea())
        .onChange(of: scope) { _, newScope in
            text = newScope == .exercise ? exerciseText : setText
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Note · \(target.exerciseName)").font(StrandFont.headline).foregroundStyle(theme.ink)
                Text(scope == .exercise
                     ? "Saved in this exercise's history"
                     : "Saved for this set only")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Spacer()
            Button { onSave(scope, text) } label: {
                Text("Save").font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.verdictDeep)
            }
            .buttonStyle(.plain)
        }
    }

    private var scopeToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Save to:").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            HStack(spacing: 3) {
                scopeOption(.exercise, label: String(localized: "This exercise"))
                scopeOption(.set, label: String(format: String(localized: "Only set %d"), target.setNumber))
            }
            .padding(3)
            .background(theme.trackWarm, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
        }
    }

    private func scopeOption(_ value: Scope, label: String) -> some View {
        let selected = scope == value
        return Button {
            withAnimation(StrandMotion.interactive) { scope = value }
        } label: {
            Text(label)
                .font(StrandFont.caption.weight(.bold))
                .foregroundStyle(selected ? theme.paper : theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if selected { RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous).fill(theme.ink) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Jot something for next time: how it felt, technique, a load tweak…")
                    .font(StrandFont.body).foregroundStyle(theme.inkTertiary)
                    .padding(.horizontal, 13).padding(.vertical, 13)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(StrandFont.body)
                .foregroundStyle(theme.ink)
                .scrollContentBackground(.hidden)
                .tint(theme.dataStrain)
                .focused($focused)
                .padding(9)
        }
        .frame(minHeight: 100)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.dataStrain, lineWidth: 1.5))
    }

    private func historySection(_ history: [ExerciseNote]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PREVIOUS NOTES").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(history.enumerated()), id: \.element.id) { index, note in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(Self.relativeDays(note.ts)).font(StrandFont.caption.weight(.semibold))
                                .foregroundStyle(theme.inkTertiary)
                            if note.setPosition != nil {
                                Text("Set \(note.setPosition! + 1)").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                            }
                        }
                        Text(verbatim: note.text).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if index < history.count - 1 {
                        Rectangle().fill(theme.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    /// «Hace N días» relative-day label for a note's `ts` (epoch seconds).
    private static func relativeDays(_ ts: Int) -> String {
        let days = max(0, Int((Date().timeIntervalSince1970 - Double(ts)) / 86400))
        if days == 0 { return String(localized: "Today") }
        if days == 1 { return String(localized: "Yesterday") }
        return String(format: String(localized: "%d days ago"), days)
    }
}

struct ChangeExerciseSheet: View {
    let theme: InstrumentoTheme
    let run: StrengthSessionModel.ExerciseRun
    let repo: Repository
    let onUse: (Exercise) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var all: [Exercise] = []
    @State private var primaryMuscle: String?
    @State private var loaded = false

    /// Same-muscle shortlist when the field is empty; a name search over the whole library otherwise. The
    /// current exercise is always excluded (you don't replace it with itself).
    private var filtered: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            guard let m = primaryMuscle else { return [] }
            return Array(all.filter { $0.id != run.exerciseId && $0.primaryMuscles.contains(m) }.prefix(12))
        }
        return Array(all.filter { $0.id != run.exerciseId && StrengthDisplay.name($0).lowercased().contains(q) }.prefix(20))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                    searchField
                    if !filtered.isEmpty {
                        if query.isEmpty, let m = primaryMuscle {
                            (Text("Suggested · ") + Text(MuscleAtlas.name(m)))
                                .instrumentoOverline().foregroundStyle(theme.inkTertiary).padding(.top, 4)
                        }
                        ForEach(filtered) { row($0) }
                    } else if loaded {
                        Text(query.isEmpty ? "No alternatives for this muscle: search the library."
                                           : "No matches.")
                            .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }
                }
                .padding(.horizontal, CenitMetrics.screenPadding)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.paper)
            .navigationTitle(Text("Change \(run.name)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }.foregroundStyle(theme.ink)
                }
            }
        }
        .task {
            guard !loaded else { return }
            async let exercisesTask = repo.allExercises()
            async let currentTask = repo.resolvedExercise(run.exerciseId)
            all = await exercisesTask
            primaryMuscle = await currentTask?.primaryMuscles.first
            loaded = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            StrandIcon.search.image.font(StrandFont.glyph(.inline)).foregroundStyle(theme.inkTertiary)
            TextField("Search the library…", text: $query)
                .font(StrandFont.body).foregroundStyle(theme.ink).tint(theme.ink)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func row(_ ex: Exercise) -> some View {
        HStack(spacing: 12) {
            SessionRunThumb(exerciseId: ex.id)
            VStack(alignment: .leading, spacing: 1) {
                Text(StrengthDisplay.name(ex)).font(StrandFont.body).foregroundStyle(theme.ink)
                if let m = ex.primaryMuscles.first {
                    Text(MuscleAtlas.name(m)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
            }
            Spacer(minLength: 8)
            Button { onUse(ex) } label: {
                Text("Use").font(StrandFont.caption).foregroundStyle(theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Use \(StrengthDisplay.name(ex))"))
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(theme.hairline) }
    }
}

/// Strips a `List` row down to the warm-paper language: one screen margin, no native background, no native
/// separator (the table draws its own hairlines). `top`/`bottom` tune the vertical rhythm per row. FER-497.
private extension View {
    func plainRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: CenitMetrics.screenPadding,
                                      bottom: bottom, trailing: CenitMetrics.screenPadding))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Canvas pass 2026-07-15 (vuelve la carta blanca, ahora FLOTANTE): the active exercise's rows are
    /// slices of one floating `surface` card — the same hover language as the rest card — while the
    /// row background also paints the rail thread BEHIND it and, on the header slice, the category dot
    /// centered to the 44pt thumbnail (`dotTint`/`dotTopOffset`). `railVisible: false` hides the
    /// thread/dot in single-exercise sessions where a rail would hang orphaned.
    func activeCardRow(top: Bool, bottom: Bool, theme: InstrumentoTheme, railTint: Color,
                       railVisible: Bool = true, railTopInset: CGFloat = 0,
                       dotTint: Color? = nil) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: top ? CenitMetrics.cardRadius : 0,
            bottomLeadingRadius: bottom ? CenitMetrics.cardRadius : 0,
            bottomTrailingRadius: bottom ? CenitMetrics.cardRadius : 0,
            topTrailingRadius: top ? CenitMetrics.cardRadius : 0)
        return self
            .listRowInsets(EdgeInsets(top: 0, leading: CenitMetrics.screenPadding + 26,
                                      bottom: 0, trailing: CenitMetrics.screenPadding))
            .listRowBackground(
                ZStack(alignment: .topLeading) {
                    if railVisible {
                        // `railTopInset` clips the thread's start on the FIRST exercise's header —
                        // the dot is the thread's birthplace, nothing hangs above it.
                        Rectangle().fill(railTint.opacity(0.35)).frame(width: 2)  // token-exempt: decorative rail-thread alpha (structure, not datum)
                            .padding(.top, railTopInset)
                            .padding(.leading, CenitMetrics.screenPadding + 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    if railVisible, let dotTint {
                        // r7: el punto se dibuja AQUÍ, en el mismo espacio que la línea — misma X por
                        // construcción (centrado exacto) y a la altura del centro del thumbnail (12 de
                        // padding + 22 = mitad de los 44pt). El respaldo de papel tapa la línea: el
                        // hilo muere/pasa DETRÁS del punto, nunca encima.
                        ZStack {
                            Circle().fill(theme.paper).frame(width: 17, height: 17)
                            Circle().fill(dotTint).frame(width: 11, height: 11)
                        }
                        .padding(.leading, CenitMetrics.screenPadding + 7 - 8.5)
                        .padding(.top, 12 + 22 - 8.5)
                    }
                    // Seamless slices (owner: sin sombra entre calentamiento y series): the hover
                    // shadow only paints on the card's OUTER edges — per-slice shadows banded at every
                    // internal boundary.
                    // «Recibo» (owner r6): superficie PLANA — borde hairline, cero sombra; las
                    // filas se separan con filetes, no con profundidad.
                    shape.fill(theme.surface)
                        .overlay(shape.strokeBorder(theme.hairline, lineWidth: 1))
                        .padding(.leading, CenitMetrics.screenPadding + 26)
                        .padding(.trailing, CenitMetrics.screenPadding)
                }
            )
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
