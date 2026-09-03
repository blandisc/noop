#if os(iOS)
import SwiftUI
import UIKit
import CenitDesign
import StrandTraining
import StrandAnalytics
import BiometricStreams
import CenitStore

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
    /// Where `strain` came from (ola 1 · E3). Drives the single «estimado» label on the receipt hero.
    var strainSource: StrainSource? = nil
    /// The session-effort answer currently stored (6–10). `nil` = sin calificar.
    var sessionRpe: Double? = nil
    /// Whether that answer was tapped (`.answered`) or accepted as the suggested prefill (`.prefill`).
    var sessionRpeSource: SessionRpeSource? = nil
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
    /// Los músculos trabajados hoy, con su papel: los PRINCIPALES (protagonistas del ejercicio) y
    /// los de APOYO (FER-124). Antes era una lista plana de solo principales — el catálogo ya sabía
    /// cuáles eran de apoyo (`Exercise.secondaryMuscles`), pero el acta nunca los mostraba. No es un
    /// dato nuevo que guardar: se le vuelve a preguntar al catálogo. `StrengthSummary` es transitorio
    /// (Equatable, no Codable), así que esto no toca la base.
    var muscles: [WorkedMuscle]
    var isFirstTime: Bool
    /// The previous completed session of the SAME routine (FER-716), for the «Contra tu última {rutina}»
    /// bars. `nil` when this routine has no earlier session (or the session was routine-less).
    var comparison: Comparison?
    /// One row per exercise with logged sets, in plan order — the receipt's «Por ejercicio» list.
    var exercises: [ExerciseLine]
    /// FER-742: the Apple Watch recorded the real FC/kcal and saved the workout to Health (the one-workout
    /// invariant then omitted the iPhone's estimate). Drives the receipt's watch-origin line; false = as today.
    var watchRecorded: Bool = false

    /// Un músculo trabajado hoy y su papel. `isPrimary` = protagonista de al menos un ejercicio de
    /// la sesión; si un músculo fue principal en un ejercicio y de apoyo en otro, gana principal.
    struct WorkedMuscle: Equatable, Identifiable {
        var name: String
        var isPrimary: Bool
        var id: String { name }
    }

        /// Arma la lista de músculos con su papel a partir de los principales y de apoyo de cada
        /// serie de trabajo, en orden. Regla: el principal gana — si un músculo es protagonista en un
        /// ejercicio y de apoyo en otro, se marca principal. Pura y estática para que el acta y su
        /// prueba llamen EL MISMO código, no dos copias de la regla (FER-124).
        static func worked(primaryPerSet: [[String]], secondaryPerSet: [[String]],
                           titleCase: (String) -> String) -> [WorkedMuscle] {
            var order: [String] = []
            var isPrimary: [String: Bool] = [:]
            func note(_ raw: String, primary: Bool) {
                let m = titleCase(raw)
                if isPrimary[m] == nil { order.append(m); isPrimary[m] = primary }
                else if primary { isPrimary[m] = true }
            }
            for ex in primaryPerSet { for m in ex { note(m, primary: true) } }
            for ex in secondaryPerSet { for m in ex { note(m, primary: false) } }
            return order.map { WorkedMuscle(name: $0, isPrimary: isPrimary[$0] ?? true) }
        }

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
        /// D7 (ola 1 · FER-327 · E7 · issue): las reps de cada serie de trabajo NUMERADA, en el
        /// mismo orden que se hicieron — «8 · 8 · 11 máx» en el recibo/detalle. Vacío para
        /// tiempo/distancia (ya tienen `topTimeS`/`topDistanceM`) y para sesiones reconstruidas sin
        /// este detalle (reimpresión, `ReceiptMapping.summary`). Paralelo a `amrapFlags`.
        var repsSequence: [Int?] = []
        /// `true` en la posición de una serie AMRAP («las que puedas») — agrega «máx» a su número.
        var amrapFlags: [Bool] = []
        /// Un escalón de «bajar y seguir» de este ejercicio.
        struct DropLine: Equatable { let weightKg: Double; let reps: Int? }
        /// Los escalones de este ejercicio, en orden — «↳ bajar y seguir 64 kg · 9» cada uno. Nunca
        /// se cuentan en `setCount`/`topWeightKg` (D2): un escalón no es una serie numerada.
        var dropLines: [DropLine] = []
        /// Cuántas series de este ejercicio llegaron a RPE 10 («al fallo») — agrega «· N al fallo».
        var failureCount: Int = 0
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
        /// Repeticiones capturadas. Ola 1 (FER-327): OPCIONAL — `nil` = **pendiente**, el estado en que
        /// nace un AMRAP («las que puedas»: el número no existe hasta que la serie termina). El ✓ está
        /// bloqueado mientras siga en nil (`canRegisterCurrentSet`) y al guardar nunca se escribe un 0
        /// en su lugar. Las series normales siguen naciendo con su número, así que nada cambia para ellas.
        var reps: Int?
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
        /// El usuario ya escribió en esta fila (modelo fantasma FER-952): false = las celdas muestran
        /// la semilla «la última vez» en tinta tenue, y el ✓ la registra tal cual.
        var touched: Bool = false
        /// Perceived effort (RPE), 6-10 with half-steps (FER-930). Optional: marking a set done never
        /// requires it. Set from the RPE sheet, independent of `done`.
        var rpe: Double? = nil
        /// Set-scoped note text (FER-932), written from the note sheet with «Guardar en: Solo la serie N».
        /// nil = no set-scope note; the exercise-scope note lives on `ExerciseRun.note` instead.
        var note: String? = nil
        /// The real rest (seconds, pauses excluded) that FOLLOWED this set (FER-167), written by
        /// `closeOpenRest`. nil = no rest was measured for this set (not yet closed, never started —
        /// «Sin descanso» — or an intra-round superset jump).
        var restTakenS: Int? = nil
        /// Cómo se hace la serie (ola 1 · FER-327): `.standard`, `.amrap` («las que puedas») o `.drop`
        /// (el escalón de «bajar y seguir», una serie propia que cuelga de la anterior por ORDEN, sin
        /// FK). Sigue siendo `kind == .work`: los filtros de «¿es serie de trabajo?» (volumen/sesión
        /// activa) no se tocan; solo las cuatro reglas (volumen/progresión/récords/1RM) leen el modo
        /// directamente. PERO cualquier conteo que se lea como «serie N» o «N series» a un humano —
        /// numerales, «Serie N de M», rondas de superserie, `targetSets` que se ofrece guardar en la
        /// rutina, «repetir del historial» — SÍ debe excluir un escalón (D2, QA FER-332 ronda 1: media
        /// docena de estos conteos lo colaban como si fuera trabajo prescrito). `isNumberedWorkSet`
        /// abajo es ese ÚNICO oráculo — no relees `kind == .work && mode != .drop` a mano.
        var mode: SetMode = .standard

        /// Ola 1 (FER-327 · E7 · D2): ¿esta serie cuenta como UNA serie de trabajo NUMERADA? Un
        /// escalón de «bajar y seguir» sigue siendo `kind == .work` (cuenta a volumen), pero no es una
        /// serie que un humano cuenta como tal — no avanza «Serie N de M», no es una ronda propia de
        /// superserie, y no se ofrece como serie prescrita al guardar/repetir la rutina.
        var isNumberedWorkSet: Bool { kind == .work && mode != .drop }
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
        /// Last time's top work set's perceived effort (FER-167 ronda 2 · R12), for the ANT playhead's
        /// «· Q2» suffix (`HojaSesionViva.antPlayhead`). `nil` when the last session never captured RPE
        /// there — the playhead just omits the Q, same honesty rule as everywhere else Q is optional.
        let lastRPE: Double?
        var sets: [WorkingSet]
        var currentSet: Int
        var skipped: Bool
        /// An earned weight raise for this run (FER-E · 2b). nil = no proposal today.
        /// Cleared by «Volver a X» (the per-session opt-out).
        ///
        /// Two readings (FER-82): APPLIED (`waiting == false`) means the cells already opened at the
        /// new weight — the crash snapshot doesn't carry it because the weights themselves survive,
        /// and only the «por qué» affordance is lost. HELD (`waiting == true`) means today's verdict
        /// kept the seed at last time's weight and the raise is offered here, one tap away — THAT one
        /// the snapshot does carry, because losing it would silently retract what the hero promised.
        var proposedRaise: ProgressionPlanner.Raise? = nil
        /// B7 (FER-169): today's deload read from `ProgressionPlanner.evaluate` — `.deloading`
        /// (propose dropping to a weight) or `.stalled` (only surfaced, never a `nil`-then-appear
        /// after the fact — the live pill and `deloadDisplay` below decide what's worth showing).
        /// `nil` = no stall to report (readyToAdvance/inCycle/deferred, or progression not enabled).
        /// Cleared locally by «Seguir en X» (this session only — no opt-out persisted, same as before
        /// F4 the live session never proposed a deload at all).
        var deloadState: ProgressionState? = nil
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
        /// The routine's fixed note (`RoutineExercise.note`, FER-166) exactly as it was seeded into
        /// `note` above by `make(...)`. `buildForSave` compares `note` against this to tell an
        /// untouched seed (never copied to the session's acta) from a note the user actually edited
        /// this session (copied, same as any other `ExerciseNote`). `var` with a default, not `let`: a
        /// `let` with an initial value falls out of the memberwise init. `addExercise`/
        /// `insertExerciseAfterCurrent`/`replaceExercise` all leave it nil — an ad-hoc or swapped
        /// exercise never inherits the old movement's note.
        var seededNote: String? = nil
        /// Whether this run (or any of its sets) carries a note (FER-932) — drives the chip's «con nota» state.
        var hasNote: Bool { (note?.isEmpty == false) || sets.contains { $0.note?.isEmpty == false } }

        /// B7 (FER-169): what the deload pill shows, if anything — the single place that decides
        /// `deloadState` is worth surfacing. `.propose` only past `ProgressionMath.deloadStallThreshold`
        /// sessions AND when the policy allows proposing (the engine itself already folds
        /// `deloadWarnOnly` into whether `.deloading` or `.stalled` comes back — see
        /// `ProgressionMath.classify`); a `.stalled` BELOW threshold (1-2 sessions, mid-stall, nothing
        /// actionable yet) stays silent — the same quiet the app already kept before F4.
        enum DeloadDisplay: Equatable {
            case propose(fromKg: Double, toKg: Double)
            case warnOnly(sessions: Int)
        }
        var deloadDisplay: DeloadDisplay? {
            switch deloadState {
            case .deloading(let fromKg, let toKg): return .propose(fromKg: fromKg, toKg: toKg)
            case .stalled(let sessions) where sessions >= ProgressionMath.deloadStallThreshold:
                return .warnOnly(sessions: sessions)
            default: return nil
            }
        }

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
    /// La última vez que cambió el contexto que un toque remoto pudo estar viendo: se re-arma en CADA
    /// cierre de serie (`registerCurrentSet`, por cualquiera de sus ramas — descanso, superserie, «Sin
    /// descanso», fin de rutina) y en `startRest`, y a diferencia de `restStartedAt` NO se limpia al
    /// salir del descanso (Nancy · rondas 6–8). Es el ancla de staleness de los canales durables (inbox
    /// de la Live Activity y cola del reloj): un toque anterior a esta fecha se descarta.
    private(set) var lastRestStartedAt: Date?
    /// The HR «ready» target (bpm) for this rest, computed once on entry (FER-495/506). nil = use FER-348's
    /// resting+margin default (when `currentRestMode == .heartRate`).
    @Published var currentRestTarget: Int?
    /// Which number dominates this rest: a fixed countdown, or the HR «N bpm to ready» HUD.
    @Published var currentRestMode: RestMode = .fixed
    /// The `WorkingSet.id` that opened the rest currently in flight (FER-167) — who `closeOpenRest`
    /// writes `restTakenS` onto when the rest closes. nil = no rest open (or one that never started,
    /// e.g. «Sin descanso»).
    var restOwnerSetId: String?
    /// When the current set's stopwatch started; nil when not running. For `time`/`distance` Foco. Durable
    /// (an absolute Date), so the running clock survives closing the sheet or switching tabs.
    @Published var timerStart: Date?
    /// Non-nil once «Finish» saved the session: the post-session receipt the sheet renders as its terminal
    /// `summaryPhase` (FER-409). Computed once at finish in `AppModel`; the session stays alive until the
    /// user taps «Listo» so the summary has somewhere to live.
    @Published var summary: StrengthSummary?
    /// FER-969 (X-01): the final save failed — the sheet shows an honest banner with retry; the
    /// in-progress snapshot (FER-798) stays on disk until a save actually lands.
    @Published var saveError = false
    /// Strap HR captured during the session (FER-399), in memory only — fed by `AppModel.ingestHR` on the
    /// main actor. Drives avgHr/strain + the Keytel calorie estimate at finish; never persisted as a series.
    var hrSamples: [HRSample] = []
    /// La semana del programa en la que se sirvió esta sesión, y si se sirvió LIGERA (ola 1 · E10,
    /// FER-329). `nil` = no había programa: la columna se queda NULL, no un 0/false inventado. Se fijan
    /// al arrancar, viajan en el snapshot de rescate y se guardan en `strengthSession` — desde ahí
    /// `deload` convierte la sesión en frontera para `ProgressionMath` y la saca de `lastWorkSets`.
    var programWeek: Int?
    var deload: Bool?
    /// «· la semana ligera llega en la N» (ola 1 · E11, P8) — el mismo `ProgramServing.Context` que ya
    /// sirvió los slots, resumido a un texto para el chip de estancamiento. Efímero a propósito: NO
    /// viaja en el snapshot ni se persiste (a diferencia de `programWeek`/`deload`) — es una pista de
    /// UI que se recalcula la próxima vez que se arranca, nunca un dato de la sesión guardada.
    var lightWeekHint: String?
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

    /// How many `.work` series the run at `index` carries — the "rounds" a superset member cycles
    /// through. Ola 1 (FER-327 · E7): EXCLUYE los escalones de «bajar y seguir» — un drop no es una
    /// ronda propia (rompería «una fila por miembro por ronda» entre los demás miembros del bloque);
    /// vive como sub-fila de su madre (`RoutineSheetLiveTarjeta.filaRonda`).
    func supersetRounds(at index: Int) -> Int {
        guard runs.indices.contains(index) else { return 0 }
        return runs[index].sets.filter(\.isNumberedWorkSet).count
    }

    /// FER-170 (F5, ronda 2 del gate · R7): cuántas rondas de este bloque de superserie están
    /// CERRADAS ahora mismo (todas las filas de esa ronda, en TODOS los miembros, `.done`) — mismo
    /// criterio que `HojaTarjetaSuperserieSesion.rondaCerrada` (Cenit/Screens/Hoja/
    /// RoutineSheetLiveTarjeta.swift), como conteo puro para comparar antes/después de registrar
    /// (`HojaSesionViva.registerFromFoco`, D3: HECHO en superserie solo al cerrar ronda). Se detiene
    /// en la primera ronda abierta — las rondas cierran en orden, nunca fuera de secuencia. Vive aquí
    /// (no en la vista) porque solo toca datos de sesión — pura, testable con `StrengthSessionModel`
    /// sola (`StrengthSessionModelTests`), sin montar ninguna vista.
    func closedSupersetRounds(members: [Int]) -> Int {
        let total = members.map { supersetRounds(at: $0) }.max() ?? 0
        guard total > 0 else { return 0 }
        var closed = 0
        for r in 1...total {
            var slots = 0, done = 0
            for ei in members where runs.indices.contains(ei) {
                // Ola 1 (FER-327 · E7 · D2): mismo oráculo que `supersetRounds` — un escalón no es una ronda.
                let work = runs[ei].sets.filter(\.isNumberedWorkSet)
                guard r <= work.count else { continue }
                slots += 1
                if work[r - 1].done { done += 1 }
            }
            guard slots > 0, slots == done else { break }
            closed += 1
        }
        return closed
    }

    // MARK: The held raise (FER-82)

    /// Whether the run at `index` is offering a raise that can still be taken: earned, held by today's
    /// verdict, and with at least one work set left to lift. A finished exercise offers nothing —
    /// taking it would move no weight while the app claimed today's load went up.
    func canTakeHeldRaise(at index: Int) -> Bool {
        guard runs.indices.contains(index), runs[index].proposedRaise?.waiting == true else { return false }
        return runs[index].sets.contains { !$0.done && $0.kind == .work }
    }

    /// Take the held raise: every UNDONE work set moves to the proposed weight (the same all-work-sets
    /// rule an applied raise seeds with) and the proposal stops waiting. Done sets keep what was
    /// actually lifted. Returns false when there was nothing to take, so the UI can stay quiet.
    ///
    /// Taking it MID-exercise makes the session mixed: some sets at the old load, the rest at the new
    /// one. The cycle reads a session by its TOP weight and the reps done at that weight, so a mixed
    /// session would look like «went up and missed the goal» — a failure the athlete never had. It is
    /// marked opted-out, the same contract «Volver a X» uses: neither hit nor miss, invisible to the
    /// cycle, and the earned raise is proposed again next session (FER-82 · FER-835).
    @discardableResult
    func takeHeldRaise(at index: Int) -> Bool {
        guard canTakeHeldRaise(at: index), let toKg = runs[index].proposedRaise?.toKg else { return false }
        let mixed = runs[index].sets.contains { $0.done && $0.kind == .work }
        for si in runs[index].sets.indices where !runs[index].sets[si].done && runs[index].sets[si].kind == .work {
            runs[index].sets[si].weightKg = toKg
        }
        runs[index].proposedRaise?.waiting = false
        if mixed { runs[index].raiseOptedOut = true }
        return true
    }

    // MARK: Editing the current set

    func bumpWeight(byKg delta: Double) { mutateCurrentSet { $0.weightKg = max(0, $0.weightKg + delta) } }
    /// Nancy · ronda 3: el ± de Foco tocaba fondo en 0, y una fila de peso×reps con 0 repeticiones
    /// no es un estado representable — dejaba la serie imposible de registrar y las puertas remotas
    /// (Live Activity, Apple Watch), que no tienen dónde escribir, mudas. Para no registrar nada se
    /// borra la fila, no se baja a cero. Los ejercicios de tiempo/distancia no se juzgan por reps.
    func bumpReps(_ delta: Int) {
        let piso = (current?.type == .weightReps || current?.type == .bodyweight) ? 1 : 0
        // FER-327: una serie PENDIENTE (AMRAP sin número todavía) arranca desde el piso al primer «+»;
        // un «−» sobre nada la deja pendiente — bajar desde nil fabricaría una rep que nadie hizo y
        // desbloquearía el ✓ (revisión adversarial E6, H3).
        mutateCurrentSet {
            guard let r = $0.reps else {
                if delta > 0 { $0.reps = max(piso, delta) }
                return
            }
            $0.reps = max(piso, r + delta)
        }
    }
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
        // Pausar congela la cuenta: un aviso programado al instante viejo sonaría en plena pausa.
        RestEndNotifier.cancel()
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
        if let r = lastRestStartedAt { lastRestStartedAt = r.addingTimeInterval(delta) }
        if let t = timerStart { timerStart = t.addingTimeInterval(delta) }
        pausedAt = nil
        paused = false
        // Al reanudar, el descanso tiene un final NUEVO (se corrió por el tiempo pausado).
        reprogramarAviso()
    }

    // MARK: Set actions

    /// Register the current set (mark done) and start the fixed rest. Then advance to the next pending set.
    /// A running stopwatch is captured first, so «register» on a time/distance set logs its elapsed time.
    /// `restingHR`/`maxHR` come from the sheet (the user's nightly baseline + profile HR-max) so the rest
    /// target can be resolved without the model importing CoreBluetooth/HealthKit (FER-506).
    /// `hasLivePulse` (FER-250): ¿hay pulso del Apple Watch transmitiendo AHORA? Default `true` para no
    /// alterar los call sites viejos (snapshot/restore, tests). Sin reloj vivo, un descanso por FC se
    /// degrada a temporizador fijo (ver `computeRestTarget`) — el reloj es mejora, no requisito.
    /// ¿La serie enfocada es registrable? `false` solo para peso×reps sin repeticiones (Nancy · ronda 2):
    /// una serie de volumen cero no es trabajo. La piel lo consulta para mandar a escribir las reps en
    /// vez de tragarse el tap en silencio; el motor lo aplica pase quien pase (Foco, Live Activity, reloj).
    var canRegisterCurrentSet: Bool {
        guard runs.indices.contains(currentIndex) else { return false }
        let run = runs[currentIndex]
        guard run.sets.indices.contains(run.currentSet) else { return false }
        let usaReps = run.type == .weightReps || run.type == .bodyweight
        // FER-327: `nil` = AMRAP pendiente — el ✓ está bloqueado hasta que haya un número, igual que
        // con un 0: una serie sin repeticiones no es trabajo registrable, y nunca se guarda un 0.
        return !(usaReps && (run.sets[run.currentSet].reps ?? 0) <= 0)
    }

    func registerCurrentSet(now: Date = Date(), restingHR: Double? = nil, maxHR: Double? = nil,
                            hasLivePulse: Bool = true) {
        guard runs.indices.contains(currentIndex) else { return }
        // Nancy · ronda 2 (BLOQUEANTE): el guard de «0 repeticiones» vivía SOLO en la fila de la tabla
        // (`confirmOrToggleSet`), así que el ✓ de Foco, el «Completar» de la Live Activity y el del
        // Apple Watch entraban por aquí y SÍ registraban una serie hecha de volumen cero. El candado
        // vive ahora en el motor —antes de cerrar el descanso o parar el cronómetro, para no dejar
        // efectos a medias— así que ninguna puerta puede palomearla. Las series de tiempo/distancia
        // no se juzgan por reps y pasan igual.
        if canRegisterCurrentSet == false { return }
        // FER-167: palomear la siguiente serie mientras el descanso anterior sigue corriendo lo cierra
        // aquí mismo — ANTES de cualquier otra cosa, incluido el salto de ronda de superserie de abajo.
        closeOpenRest(now: now)
        if timerStart != nil { stopSetTimer(now: now) }
        let i = runs[currentIndex].currentSet
        guard runs[currentIndex].sets.indices.contains(i) else { return }
        let justCompletedKind = runs[currentIndex].sets[i].kind
        let doneTs = Int(now.timeIntervalSince1970)
        runs[currentIndex].sets[i].done = true
        runs[currentIndex].sets[i].doneTs = doneTs
        // Nancy · ronda 8: el ancla de staleness se re-arma AQUÍ, en el único punto por el que pasa
        // TODO cierre de serie — no solo en `startRest`: el salto de superserie, «Sin descanso» y el
        // fin de rutina salen a `.capturing` sin descanso, y un toque encolado (reloj/Live Activity)
        // anterior a este instante ya vio un contexto que dejó de existir.
        lastRestStartedAt = now

        // FER-931: superset round-robin — A1 done moves straight to A2, no rest in between; the rest
        // lands when the ROUND closes (the last member with pending work). r18 (owner edge case):
        // the partner is found by its NEXT PENDING work set, not by the same round index — with
        // staggered counts (A on its 5th set, B on its 1st) index-pairing broke the superset and a
        // rest leaked between A and B. While any LATER member of the group still has pending work,
        // the jump is rest-free. Warm-ups don't participate; only `.work` cycles the group. A
        // standalone exercise (group of one) skips this entirely — pre-931 path below, untouched.
        // FER-327: «bajar y seguir» es literal — si la serie que se acaba de cerrar tiene un escalón de
        // drop pegado detrás, NO se abre descanso: se pasa directo al escalón, ANTES del salto de
        // superserie (el escalón pertenece a esta misma serie; el compañero espera al escalón, no al
        // revés — revisión adversarial E6, H6). Misma convención que el salto intra-superserie: sin
        // descanso iniciado no hay `restTakenS` que medir, así que se queda en nil en vez de un 0 que
        // fingiría una pausa de cero segundos.
        if hasDropAfter(exercise: currentIndex, set: i) {
            phase = .capturing
            clearRest()
            timerStart = nil
            runs[currentIndex].currentSet = i + 1
            return
        }

        let group = supersetMembers(at: currentIndex)
        if justCompletedKind == .work, group.count > 1,
           let posInGroup = group.firstIndex(of: currentIndex) {
            for nextMember in group.dropFirst(posInGroup + 1) where !runs[nextMember].skipped {
                if let si = runs[nextMember].sets.firstIndex(where: { !$0.done && $0.kind == .work }) {
                    phase = .capturing
                    clearRest()
                    timerStart = nil
                    currentIndex = nextMember
                    runs[nextMember].currentSet = si
                    return
                }
            }
        }

        // FER-715: rest is resolved per set — the active set's own override, else the exercise's default.
        let rest = runs[currentIndex].effectiveRest(forSet: i)
        // r9 (owner): «Sin descanso» — un descanso fijo de 0 s registra y sigue de largo.
        if rest.mode == .fixed, rest.seconds <= 0 {
            phase = .capturing
            clearRest()
            advanceToNextPending()
            return
        }
        computeRestTarget(rest: rest, doneTs: doneTs, restingHR: restingHR, maxHR: maxHR,
                          hasLivePulse: hasLivePulse)
        // FER-250: si el descanso quedó fijo por FALTA de pulso vivo (o de baseline honesto) y la rutina
        // no fija segundos, cae al respaldo — un descanso de reloj de verdad, no un cronómetro en 0.
        let restSecs = (currentRestMode == .fixed && rest.seconds <= 0) ? Self.noWatchRestFallbackSeconds
                                                                        : rest.seconds
        startRest(seconds: restSecs, now: now)
        restOwnerSetId = runs[currentIndex].sets[i].id   // FER-167: `i` captured before advancing
        advanceToNextPending()
        // r9 (owner): tras el ÚLTIMO set del ÚLTIMO ejercicio no hay nada que descansar.
        if isComplete {
            phase = .capturing
            clearRest()
        }
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
    private func computeRestTarget(rest: RestConfig, doneTs: Int, restingHR: Double?, maxHR: Double?,
                                   hasLivePulse: Bool = true) {
        guard rest.mode == .heartRate else { currentRestMode = .fixed; currentRestTarget = nil; return }
        // FER-250: descanso por FC pedido, pero sin pulso vivo AHORA (el caso más común, sin reloj) →
        // temporizador fijo. Así el auto-skip corre y no se regaña «sin reloj» en cada descanso.
        // FER-257 D5 (deliberado, no fix): si este descanso ya degradó a fijo y el Watch conecta
        // a mitad, NO se re-promueve a FC — el reloj es mejora, no requisito. Se re-evalúa al
        // siguiente registro (`registerCurrentSet` vuelve a pasar `hasLivePulse`).
        guard hasLivePulse else { currentRestMode = .fixed; currentRestTarget = nil; return }
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
        // La plantilla es la última serie NO escalón: clonar un drop nacería standard al peso rebajado
        // y esa serie ligera sí alimentaría progresión y «la última vez» (revisión adversarial E6, H5).
        let template = runs[currentIndex].sets.last(where: { $0.mode != .drop }) ?? runs[currentIndex].sets.last
        let usaReps = runs[currentIndex].type == .weightReps || runs[currentIndex].type == .bodyweight
        let reps = usaReps ? max(1, template?.reps ?? 8) : (template?.reps ?? 0)   // Nancy · ronda 5
        let set = WorkingSet(id: UUID().uuidString,
                             weightKg: template?.weightKg ?? 0, reps: reps, done: false)
        runs[currentIndex].sets.append(set)
        runs[currentIndex].currentSet = runs[currentIndex].sets.count - 1
        phase = .capturing
        timerStart = nil
    }

    /// The rest default for exercises added on the fly in an ad-hoc session (FER-762): a plain 2-minute
    /// fixed countdown — no HR baseline to anchor a heart-rate target to, and the mock's copy promises
    /// «2 min» explicitly. Editable per set via the existing rest editor, same as any routine exercise.
    static let adHocRestSeconds = 120
    /// FER-250: descanso de respaldo cuando la rutina pide descanso por FC pero no hay reloj vivo y la
    /// rutina no define segundos. Decisión del dueño (docs/DECISIONS.md): el objetivo de la rutina, o 90 s.
    static let noWatchRestFallbackSeconds = 90

    /// Append an exercise mid-session (FER-762): used by the «Rápido de fuerza» empty state (no routine)
    /// when the user adds a suggested or searched exercise. Seeds one working set from the exercise's last
    /// recorded weight/reps when there is history, else a starter default — same convention as `make(slots:)`.
    func addExercise(_ exercise: Exercise, lastWeightKg: Double? = nil, lastReps: Int? = nil) {
        let usesReps = exercise.type == .weightReps || exercise.type == .bodyweight
        let weight = lastWeightKg ?? 0
        let reps = usesReps ? max(1, lastReps ?? 8) : 0   // Nancy · ronda 4: historial con reps 0 no siembra en 0
        let set = WorkingSet(id: UUID().uuidString, weightKg: weight, reps: reps, done: false)
        let run = ExerciseRun(id: UUID().uuidString, exerciseId: exercise.id,
                              name: StrengthDisplay.name(exercise), type: exercise.type,
                              restSeconds: Self.adHocRestSeconds, restMode: .fixed,
                              hrRestReference: .restingMargin, hrRestValue: 0,
                              lastWeightKg: lastWeightKg, lastReps: lastReps,
                              lastTimeS: nil, lastDistanceM: nil, lastRPE: nil,
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
        guard runs.indices.contains(currentIndex) else { return }
        insertExercise(exercise, afterRunId: runs[currentIndex].id,
                       lastWeightKg: lastWeightKg, lastReps: lastReps)
    }

    /// Insert an exercise right after the run with `afterRunId`, WITHOUT touching the guided focus
    /// (Nancy · ronda 10): «＋ Agregar» desde el menú «···» de CUALQUIER fila insertaba reasignando
    /// `currentIndex` en crudo — robaba el foco al ejercicio de esa fila, dejaba el descanso en vuelo
    /// huérfano, y esquivaba el candado de staleness (un toque remoto encolado registraba la serie
    /// del ejercicio equivocado). Aquí la identidad enfocada se conserva: si el insert cae antes del
    /// foco, el índice se corre; el foco nunca cambia de run.
    func insertExercise(_ exercise: Exercise, afterRunId: String,
                        lastWeightKg: Double? = nil, lastReps: Int? = nil) {
        guard let after = runs.firstIndex(where: { $0.id == afterRunId }) else { return }
        let usesReps = exercise.type == .weightReps || exercise.type == .bodyweight
        let weight = lastWeightKg ?? 0
        let reps = usesReps ? max(1, lastReps ?? 8) : 0   // Nancy · ronda 4: historial con reps 0 no siembra en 0
        let set = WorkingSet(id: UUID().uuidString, weightKg: weight, reps: reps, done: false)
        let run = ExerciseRun(id: UUID().uuidString, exerciseId: exercise.id,
                              name: StrengthDisplay.name(exercise), type: exercise.type,
                              restSeconds: Self.adHocRestSeconds, restMode: .fixed,
                              hrRestReference: .restingMargin, hrRestValue: 0,
                              lastWeightKg: lastWeightKg, lastReps: lastReps,
                              lastTimeS: nil, lastDistanceM: nil, lastRPE: nil,
                              sets: [set], currentSet: 0, skipped: false)
        // Nancy · ronda 11: la pertenencia a superserie es ADYACENCIA por índice — insertar en
        // `after+1` cuando `after` es miembro no-terminal partía el bloque en silencio (en vivo y,
        // vía persistInsertedExercises, para siempre en la rutina). El insert cae tras el ÚLTIMO
        // miembro del bloque: la superserie queda intacta y «después de X» sigue siendo verdad.
        let insertionPoint = (supersetMembers(at: after).last ?? after) + 1
        runs.insert(run, at: min(insertionPoint, runs.count))
        if insertionPoint <= currentIndex { currentIndex += 1 }
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
        runs[ei].sets[si].touched = true
    }
    /// Set a row's reps directly from its cell.
    func setReps(exercise ei: Int, set si: Int, reps: Int) {
        guard runs.indices.contains(ei), runs[ei].sets.indices.contains(si) else { return }
        runs[ei].sets[si].reps = max(0, reps)
        runs[ei].sets[si].touched = true
    }
    /// Toggle a row's done flag from the inline ✓ — no rest is started (the rest belongs to the Foco /
    /// FER-348). Stamps `doneTs` when marking done, clears it when un-marking.
    func toggleDone(exercise ei: Int, set si: Int, now: Date = Date()) {
        guard runs.indices.contains(ei), runs[ei].sets.indices.contains(si) else { return }
        let nowDone = !runs[ei].sets[si].done
        runs[ei].sets[si].done = nowDone
        runs[ei].sets[si].doneTs = nowDone ? Int(now.timeIntervalSince1970) : nil
        // FER-167: palomear inline también es «volví a trabajar» — cierra el descanso abierto (si lo hay).
        if nowDone { closeOpenRest(now: now) }
    }
    /// Append a set to a specific exercise (copying its last row's load) — the inline «Agregar serie».
    func addSet(exercise ei: Int) {
        guard runs.indices.contains(ei) else { return }
        let template = runs[ei].sets.last(where: { $0.mode != .drop }) ?? runs[ei].sets.last   // H5, ver addSet()
        let usaReps = runs[ei].type == .weightReps || runs[ei].type == .bodyweight
        let reps = usaReps ? max(1, template?.reps ?? 8) : (template?.reps ?? 0)   // Nancy · ronda 3
        runs[ei].sets.append(WorkingSet(id: UUID().uuidString,
                                        weightKg: template?.weightKg ?? 0,
                                        reps: reps, done: false))
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
    ///
    /// FER-327: borrar una serie MADRE se lleva sus escalones de drop contiguos — un drop es «bajar y
    /// seguir» DESDE esa serie; sin ella, la bajada no significa nada y quedaría flotando en el acta a
    /// un peso que nadie levantó como trabajo. Borrar un drop suelto no toca a los demás.
    func removeSet(exercise ei: Int, set si: Int) {
        guard runs.indices.contains(ei), runs[ei].sets.indices.contains(si) else { return }
        var last = si
        if runs[ei].sets[si].mode != .drop {
            while last + 1 < runs[ei].sets.count && runs[ei].sets[last + 1].mode == .drop { last += 1 }
        }
        runs[ei].sets.removeSubrange(si...last)
        if runs[ei].currentSet >= runs[ei].sets.count {
            runs[ei].currentSet = max(0, runs[ei].sets.count - 1)
        }
    }

    // MARK: - «Bajar y seguir»: el drop como sub-serie (FER-327 · E6)

    /// Cuelga un escalón de drop de la serie `si` (o del último escalón que ya colgaba de ella): una
    /// `WorkingSet` PROPIA con `mode = .drop`, insertada justo detrás —la relación con su madre es el
    /// ORDEN, sin FK— al 80 % del peso de la serie de la que baja (`SetVariants.dropFraction`,
    /// redondeado a un peso construible con `PlateMath.snap`), con las mismas repeticiones de la madre
    /// y sin descanso propio.
    ///
    /// `implement` viene de la pantalla (el equipo del ejercicio, `PlateMath.Implement.from(equipment:)`)
    /// porque el modelo no resuelve el catálogo. Devuelve `false` cuando no había nada que colgar o
    /// cuando la cadena ya llegó al tope (`SetVariants.maxDropSteps`), para que la interfaz se calle en
    /// vez de fingir que insertó algo.
    /// ¿Colgar un escalón de `si` (o de su madre, si `si` ya es un escalón) SERÍA posible? Misma
    /// cadena de invariantes que `addDrop`, sin mutar nada — D9 (QA FER-332 ronda 2): el menú de la
    /// serie la usa para deshabilitar «Bajar y seguir» en vez de fingir que sirvió (barra sola en el
    /// equipo, o ya son 3 escalones). `addDrop` LLAMA a esta misma función, no repite la cuenta.
    func canAddDrop(exercise ei: Int, set si: Int, implement: PlateMath.Implement = .barbell,
                    inventory: [PlateMath.PlateStock] = PlateMath.defaultInventory,
                    barKg: Double = PlateMath.defaultBarKg,
                    fixedStepKg: Double = 2.5) -> Bool {
        guard runs.indices.contains(ei), runs[ei].sets.indices.contains(si) else { return false }
        guard runs[ei].sets[si].kind == .work else { return false }
        var motherIndex = si
        while motherIndex > 0 && runs[ei].sets[motherIndex].mode == .drop { motherIndex -= 1 }
        guard runs[ei].sets[motherIndex].mode != .drop else { return false }   // huérfano: no cuelga nada
        var tail = motherIndex
        var steps = 0
        while tail + 1 < runs[ei].sets.count && runs[ei].sets[tail + 1].mode == .drop {
            tail += 1; steps += 1
        }
        guard steps < SetVariants.maxDropSteps else { return false }
        let from = runs[ei].sets[tail]
        let target = SetVariants.dropTargetKg(fromKg: from.weightKg)
        let weight = PlateMath.snap(targetKg: target, implement: implement, barKg: barKg,
                                    inventory: inventory, fixedStepKg: fixedStepKg)
        // Si lo construible no queda por DEBAJO de donde venimos (madre en la barra sola, rack en su
        // mínimo), no hay bajada que hacer: no se inserta un escalón que miente (H8).
        return weight < from.weightKg
    }

    @discardableResult
    func addDrop(exercise ei: Int, set si: Int, implement: PlateMath.Implement = .barbell,
                 inventory: [PlateMath.PlateStock] = PlateMath.defaultInventory,
                 barKg: Double = PlateMath.defaultBarKg,
                 fixedStepKg: Double = 2.5) -> Bool {
        guard canAddDrop(exercise: ei, set: si, implement: implement, inventory: inventory,
                         barKg: barKg, fixedStepKg: fixedStepKg) else { return false }
        // La madre es la serie tocada, o —si se tocó un escalón— la no-drop de la que cuelga.
        var motherIndex = si
        while motherIndex > 0 && runs[ei].sets[motherIndex].mode == .drop { motherIndex -= 1 }
        var tail = motherIndex
        while tail + 1 < runs[ei].sets.count && runs[ei].sets[tail + 1].mode == .drop { tail += 1 }
        let from = runs[ei].sets[tail]
        let target = SetVariants.dropTargetKg(fromKg: from.weightKg)
        let weight = PlateMath.snap(targetKg: target, implement: implement, barKg: barKg,
                                    inventory: inventory, fixedStepKg: fixedStepKg)
        let drop = WorkingSet(id: UUID().uuidString, weightKg: weight,
                              reps: runs[ei].sets[motherIndex].reps, done: false,
                              rest: nil, mode: .drop)
        runs[ei].sets.insert(drop, at: tail + 1)
        if runs[ei].currentSet > tail { runs[ei].currentSet += 1 }
        return true
    }

    /// ¿La serie `si` de `ei` tiene un drop pegado detrás? «Bajar y seguir» significa exactamente eso:
    /// no hay descanso entre la serie y su escalón (misma convención que el salto intra-superserie,
    /// FER-167: sin descanso medido, `restTakenS` se queda en nil).
    func hasDropAfter(exercise ei: Int, set si: Int) -> Bool {
        guard runs.indices.contains(ei), runs[ei].sets.indices.contains(si + 1) else { return false }
        return runs[ei].sets[si + 1].mode == .drop
    }
    /// Copy «la última vez» into a row (the tap-ANTERIOR prefill). Weight×reps types fill weight+reps;
    /// distance fills the distance. Time's goal is a view concern, handled in the sheet.
    func prefillPrevious(exercise ei: Int, set si: Int) {
        guard runs.indices.contains(ei), runs[ei].sets.indices.contains(si) else { return }
        let run = runs[ei]
        if let w = run.lastWeightKg { runs[ei].sets[si].weightKg = w }
        if let r = run.lastReps { runs[ei].sets[si].reps = r }
        runs[ei].sets[si].touched = true
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
        if index == currentIndex {
            // Nancy · ronda 9: mover el foco también cierra el contexto que un toque remoto encolado
            // pudo estar viendo — el ancla de staleness se re-arma igual que en un cierre de serie.
            lastRestStartedAt = Date()
            phase = .capturing; clearRest(); timerStart = nil; advanceToNextPending(fromStart: true)
        }
    }

    /// Swap the exercise at `ei` for a different movement mid-session (FER-894 · «Cómo llego a Cambiar»).
    /// The run keeps its slot, its rest configuration and its id (so the table row, the focus and the
    /// routine mapping are undisturbed) and takes on the new exercise's identity (exerciseId / name /
    /// type). Any pending raise proposal is dropped — that plan belonged to the old movement.
    ///
    /// Nancy · ronda 1 (BLOQUEANTE): las series ya HECHAS antes de sustituir NO pueden viajar dentro
    /// del run sustituido. `buildForSave` etiqueta cada `SetEntry` con `run.exerciseId`, así que
    /// dejarlas ahí re-etiquetaba trabajo real (3 series de Banca) como el movimiento NUEVO (Inclinado)
    /// — acta mentirosa, PR envenenado y mapa muscular equivocado. Ahora ese trabajo se congela en un
    /// run PROPIO, insertado en el mismo sitio, que conserva la identidad VIEJA: sin series pendientes
    /// (nunca roba el foco), sin superserie (no deja un grupo de uno) y con un `id` nuevo, así que no
    /// mapea a ningún `RoutineExercise` y `persistRoutineChanges` lo ignora — la rutina sigue viendo
    /// una sola sustitución, la del run que sí conserva su id.
    func replaceExercise(at ei: Int, with exercise: Exercise, lastWeightKg: Double? = nil, lastReps: Int? = nil) {
        guard runs.indices.contains(ei) else { return }
        let old = runs[ei]
        let usesReps = exercise.type == .weightReps || exercise.type == .bodyweight
        let seedWeight = lastWeightKg ?? 0
        let seedReps = usesReps ? max(1, lastReps ?? 8) : 0   // Nancy · ronda 3: nunca una fila de 0 reps
        let wasCurrent = ei == currentIndex
        let doneSets = old.sets.filter { $0.done }
        let pendingCount = max(old.sets.count - doneSets.count, 1)
        let newSets = (0..<pendingCount).map { _ in
            WorkingSet(id: UUID().uuidString, weightKg: seedWeight, reps: seedReps, done: false)
        }
        runs[ei] = ExerciseRun(
            id: old.id, exerciseId: exercise.id,
            name: StrengthDisplay.name(exercise), type: exercise.type,
            restSeconds: old.restSeconds, restMode: old.restMode,
            hrRestReference: old.hrRestReference, hrRestValue: old.hrRestValue,
            lastWeightKg: lastWeightKg, lastReps: lastReps,
            lastTimeS: nil, lastDistanceM: nil, lastRPE: nil,
            sets: newSets, currentSet: 0,
            skipped: false)
        if !doneSets.isEmpty {
            let frozen = ExerciseRun(
                id: UUID().uuidString, exerciseId: old.exerciseId,
                name: old.name, type: old.type,
                restSeconds: old.restSeconds, restMode: old.restMode,
                hrRestReference: old.hrRestReference, hrRestValue: old.hrRestValue,
                lastWeightKg: old.lastWeightKg, lastReps: old.lastReps,
                lastTimeS: old.lastTimeS, lastDistanceM: old.lastDistanceM, lastRPE: old.lastRPE,
                sets: doneSets, currentSet: max(0, doneSets.count - 1),
                skipped: false,
                raiseOptedOut: old.raiseOptedOut,
                note: old.note, seededNote: old.seededNote)
            runs.insert(frozen, at: ei)
            if currentIndex >= ei { currentIndex += 1 }
        }
        if wasCurrent {
            currentIndex = doneSets.isEmpty ? ei : ei + 1
            lastRestStartedAt = Date()   // Nancy · ronda 9: sustituir el foco cierra su contexto
            phase = .capturing; clearRest(); timerStart = nil
        }
    }

    /// Remove an exercise from the session entirely (FER-894 menu «Remove from session»). Unlike
    /// `skipExercise` (which keeps it, greyed, in the plan), this drops the run. Never empties the session —
    /// the last remaining exercise can only be skipped, not removed. Re-focuses if the current one went.
    func removeExercise(at ei: Int) {
        guard runs.indices.contains(ei), runs.count > 1 else { return }
        let wasCurrent = ei == currentIndex
        // FER-188: capture the OTHER members of `ei`'s superset span BEFORE removing it, by their
        // stable id (never their index — the removal below shifts every later index down by one). If
        // that leaves fewer than 2 members, the group is dissolved on whoever's left — same criterion
        // `breakSupersetBlock` (RoutineSheetLiveLogic) uses to clear a whole block — so a member never
        // survives alone carrying a dead group-of-one `supersetGroup`.
        let otherGroupMemberIds = supersetMembers(at: ei).filter { $0 != ei }
            .compactMap { runs.indices.contains($0) ? runs[$0].id : nil }
        runs.remove(at: ei)
        if ei < currentIndex { currentIndex -= 1 }
        currentIndex = min(currentIndex, runs.count - 1)
        if otherGroupMemberIds.count < 2 {
            for id in otherGroupMemberIds {
                guard let idx = runs.firstIndex(where: { $0.id == id }) else { continue }
                runs[idx].supersetGroup = nil
            }
        }
        if wasCurrent {
            lastRestStartedAt = Date()   // Nancy · ronda 9: quitar el foco cierra su contexto
            phase = .capturing; clearRest(); timerStart = nil; advanceToNextPending(fromStart: true)
        }
    }

    /// B8 (FER-169) «Saltar ejercicio · vuelve al final»: sends this exercise to the END of the plan,
    /// remaining fully ACTIVE — unlike `skipExercise` (which excludes it and never re-offers it), this
    /// one is still capturable, just deferred. If it was the focused exercise, guided focus advances
    /// to whatever is now next; sets already done ride along untouched.
    func sendExerciseToEnd(_ index: Int) {
        guard runs.indices.contains(index), runs.count > 1 else { return }
        let wasCurrent = index == currentIndex
        let run = runs.remove(at: index)
        runs.append(run)
        if index < currentIndex { currentIndex -= 1 }
        if wasCurrent {
            lastRestStartedAt = Date()   // Nancy · ronda 9: diferir el foco cierra su contexto
            phase = .capturing; clearRest(); timerStart = nil; advanceToNextPending(fromStart: true)
        }
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
        // El ancla se re-arma aunque NO haya descanso («Sin descanso»): cerrar una serie también cierra
        // el contexto que un toque encolado (Live Activity / reloj) pudo estar viendo (Nancy · ronda 7).
        lastRestStartedAt = now
        guard seconds > 0 else { phase = .capturing; clearRest(); return }
        restEndsAt = now.addingTimeInterval(TimeInterval(seconds))
        restStartedAt = now
        phase = .resting
        reprogramarAviso()
    }

    /// FER-93: el ÚNICO punto que programa el aviso del descanso, para que no haya dos verdades.
    ///
    /// Se llama desde todos los sitios que MUEVEN `restEndsAt` (empezar, alargar, reanudar): antes
    /// solo lo hacía `startRest`, así que alargar el descanso dejaba el aviso sonando en el instante
    /// original mientras la cuenta seguía corriendo al lado.
    ///
    /// Solo el descanso por RELOJ programa: en el descanso por pulso `restEndsAt` es un techo que la
    /// app no usa para terminarlo (lo termina tu pulso), así que un aviso ahí anunciaría un final
    /// que puede no haber ocurrido.
    /// Re-arma el aviso desde el estado ACTUAL. Interno (no privado) porque la restauración tras
    /// matar la app también lo necesita: el descanso sí vuelve corriendo, y sin esto el aviso se
    /// cancelaba y nadie lo volvía a poner (FER-86).
    func reprogramarAviso() {
        guard debeAvisar else { RestEndNotifier.cancel(); return }
        guard let end = restEndsAt else { return }
        RestEndNotifier.schedule(endsAt: end)
    }

    /// Si este descanso, tal como está AHORA, merece un aviso programado. Separada del efecto para
    /// que la regla se pueda afirmar en una prueba sin falsear el sistema de notificaciones —
    /// falsearlo no se puede, y una prueba que finge hacerlo no prueba nada.
    var debeAvisar: Bool {
        phase == .resting && !paused && currentRestMode == .fixed && restEndsAt != nil
            && SessionComfort.isEnabled(SessionComfort.restNotifyKey)
    }
    func extendRest(byseconds delta: Int, now: Date = Date()) {
        guard let end = restEndsAt else { return }
        restEndsAt = max(now, end.addingTimeInterval(TimeInterval(delta)))   // moves the ceiling, not the floor
        reprogramarAviso()
    }
    /// Salta el descanso — tap manual, auto-cierre del countdown fijo al llegar a 0, tope 3:00 del modo
    /// FC, y los skips espejo del Watch (todos comparten este único punto). Cierra y registra primero
    /// (FER-167): el número que el usuario vio es el que se guarda.
    func skipRest(now: Date = Date()) {
        closeOpenRest(now: now)
        phase = .capturing
        clearRest()
    }

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
        // FER-167: toda salida de descanso que pasa por aquí SIN haber llamado `closeOpenRest` primero
        // (navegación, cierre de sesión) DESCARTA la medición — un descanso que ninguna serie consumió
        // o que se abandonó por un cambio de plan no es dato de la tile.
        restOwnerSetId = nil
        // FER-93: TODAS las salidas del descanso pasan por aquí (saltarlo, palomear la siguiente
        // serie, cerrar la sesión), así que este es el sitio donde el aviso no puede sobrevivir.
        // Un aviso que suena cuando ya volviste a entrenar es peor que no avisar.
        RestEndNotifier.cancel()
    }

    /// Cierra el descanso abierto registrando su duración real (segundos, pausas excluidas) en la
    /// serie dueña (FER-167). Sin descanso abierto = no-op. No toca `phase`/`restEndsAt` — quien llama
    /// decide qué hacer con la fase después (seguir descansando no tendría sentido, pero eso lo deciden
    /// `skipRest`/`registerCurrentSet`/`toggleDone`, no esta función).
    func closeOpenRest(now: Date = Date()) {
        guard let started = restStartedAt, let owner = restOwnerSetId else { return }
        // FER-167 ronda 2 (R15): si la pausa sigue ABIERTA (nunca se reanudó), el reloj que el
        // usuario VIO se congeló en `pausedAt` — medir contra el wall-clock real inflaría el
        // descanso con tiempo en pausa. `resume()` ya cubre la pausa CERRADA (desplaza
        // `restStartedAt` por el delta pausado, así que este cálculo la excluye solo); esto cubre
        // la que sigue abierta cuando `closeOpenRest` dispara (p. ej. saltar sin haber reanudado).
        let effectiveNow = pausedAt ?? now
        let elapsed = max(0, Int(effectiveNow.timeIntervalSince(started)))
        for ri in runs.indices {
            if let si = runs[ri].sets.firstIndex(where: { $0.id == owner }) {
                runs[ri].sets[si].restTakenS = elapsed
                break
            }
        }
        restOwnerSetId = nil
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
                                      endTs: endTs, deviceId: deviceId,
                                      programWeek: programWeek, deload: deload)
        var entries: [SetEntry] = []
        var optedOut: Set<String> = []
        var notes: [ExerciseNote] = []
        var position = 0
        for run in runs where !run.skipped {
            // FER-835: the exercise's «Volver a X» mark rides with the save — only if something was
            // actually logged (no saved sets → no session rows to mark).
            if run.raiseOptedOut, run.sets.contains(where: \.done) { optedOut.insert(run.exerciseId) }
            // FER-166: an untouched seed (the routine's fixed note, never edited this session) never
            // copies into the session's acta — only a note the user actually typed/changed does.
            if let text = run.note, !text.isEmpty, text != run.seededNote {
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
                                        done: true, ts: set.doneTs ?? endTs, rpe: set.rpe,
                                        restTakenS: set.restTakenS, mode: set.mode))
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
                    lastTimeS: run.lastTimeS, lastDistanceM: run.lastDistanceM, lastRPE: run.lastRPE,
                    sets: run.sets.map { s in
                        StrengthSessionSnapshot.SetSnapshot(
                            id: s.id, weightKg: s.weightKg, reps: s.reps, timeS: s.timeS,
                            distanceM: s.distanceM, done: s.done, doneTs: s.doneTs,
                            rest: s.rest, kind: s.kind, rpe: s.rpe, note: s.note,
                            touched: s.touched ? true : nil, restTakenS: s.restTakenS,
                            mode: s.mode == .standard ? nil : s.mode)
                    },
                    currentSet: run.currentSet, skipped: run.skipped,
                    raiseOptedOut: run.raiseOptedOut ? true : nil,
                    supersetGroup: run.supersetGroup, note: run.note,
                    // FER-82: only a HELD raise travels — an applied one is already in the weights.
                    heldRaise: run.proposedRaise.flatMap { r in
                        r.waiting ? .init(fromKg: r.fromKg, toKg: r.toKg, phrase: r.phrase) : nil
                    },
                    seededNote: run.seededNote,
                    // FER-189: the un-actioned deload proposal/stall travels too, same reasoning as
                    // `heldRaise` — an applied deload is already in the weights.
                    deloadState: run.deloadState.map { state in
                        switch state {
                        case .readyToAdvance(let newKg): return .readyToAdvance(newKg: newKg)
                        case .inCycle(let done, let of): return .inCycle(done: done, of: of)
                        case .stalled(let sessions): return .stalled(sessions: sessions)
                        case .deloading(let fromKg, let toKg): return .deloading(fromKg: fromKg, toKg: toKg)
                        case .deferred(let newKg): return .deferred(newKg: newKg)
                        }
                    })
            },
            currentIndex: currentIndex, restEndsAt: restEndsAt, restStartedAt: restStartedAt,
            currentRestTarget: currentRestTarget, currentRestMode: currentRestMode,
            timerStart: timerStart,
            paused: paused, pausedAccumulatedS: pausedAccumulatedS, pausedAt: pausedAt,
            updatedTs: now, restOwnerSetId: restOwnerSetId, lastRestStartedAt: lastRestStartedAt,
            programWeek: programWeek, deload: deload)
    }

    /// Rebuild a live session from a persisted snapshot (FER-798). Re-derives `phase` from the rest state;
    /// the id is preserved so `WorkoutMirrorKey.externalUUID(for:)` re-pairs with the watch's `.end`.
    static func restore(from snap: StrengthSessionSnapshot) -> StrengthSessionModel {
        let runs: [ExerciseRun] = snap.runs.map { r in
            ExerciseRun(id: r.id, exerciseId: r.exerciseId, name: r.name, type: r.type,
                        restSeconds: r.restSeconds, restMode: r.restMode,
                        hrRestReference: r.hrRestReference, hrRestValue: r.hrRestValue,
                        lastWeightKg: r.lastWeightKg, lastReps: r.lastReps,
                        lastTimeS: r.lastTimeS, lastDistanceM: r.lastDistanceM, lastRPE: r.lastRPE,
                        sets: r.sets.map { s in
                            WorkingSet(id: s.id, weightKg: s.weightKg, reps: s.reps, timeS: s.timeS,
                                       distanceM: s.distanceM, done: s.done, doneTs: s.doneTs,
                                       rest: s.rest, kind: s.kind, touched: s.touched ?? false,
                                       rpe: s.rpe, note: s.note, restTakenS: s.restTakenS,
                                       mode: s.mode ?? .standard)
                        },
                        currentSet: r.currentSet, skipped: r.skipped,
                        // The held offer is re-armed exactly as it was: the table already opened at
                        // last time's weight, so taking it stays one tap away after a restore (FER-82).
                        proposedRaise: r.heldRaise.map {
                            ProgressionPlanner.Raise(fromKg: $0.fromKg, toKg: $0.toKg,
                                                     phrase: $0.phrase, waiting: true)
                        },
                        // FER-189: re-arm the un-actioned deload proposal/stall exactly as it was.
                        deloadState: r.deloadState.map { state in
                            switch state {
                            case .readyToAdvance(let newKg): return .readyToAdvance(newKg: newKg)
                            case .inCycle(let done, let of): return .inCycle(done: done, of: of)
                            case .stalled(let sessions): return .stalled(sessions: sessions)
                            case .deloading(let fromKg, let toKg): return .deloading(fromKg: fromKg, toKg: toKg)
                            case .deferred(let newKg): return .deferred(newKg: newKg)
                            }
                        },
                        raiseOptedOut: r.raiseOptedOut ?? false,
                        supersetGroup: r.supersetGroup, note: r.note, seededNote: r.seededNote)
        }
        let model = StrengthSessionModel(id: snap.id, routineId: snap.routineId,
                                         routineName: snap.routineName, startTs: snap.startTs, runs: runs)
        model.currentIndex = snap.currentIndex
        model.restEndsAt = snap.restEndsAt
        model.restStartedAt = snap.restStartedAt
        // Nancy · ronda 9: el ancla viaja en el snapshot — derivarla de `restStartedAt` (que se limpia
        // fuera del descanso) dejaba el candado MUERTO tras relanzar sin descanso activo, y un toque
        // encolado pre-muerte registraba la serie equivocada. Snapshot viejo sin el campo → ancla = el
        // momento del rescate (conservador: un toque anterior al relanzamiento se descarta, nunca
        // se aplica a ciegas).
        model.lastRestStartedAt = snap.lastRestStartedAt ?? snap.restStartedAt ?? Date()
        model.currentRestTarget = snap.currentRestTarget
        model.currentRestMode = snap.currentRestMode
        model.restOwnerSetId = snap.restOwnerSetId
        model.timerStart = snap.timerStart
        model.phase = snap.restEndsAt != nil ? .resting : .capturing
        model.paused = snap.paused
        model.pausedAccumulatedS = snap.pausedAccumulatedS
        model.pausedAt = snap.pausedAt
        // Ola 1 · E10: la sesión rescatada sigue siendo la de la semana N y sigue siendo (o no) ligera
        // — se guardó así antes del crash y tiene que guardarse así después.
        model.programWeek = snap.programWeek
        model.deload = snap.deload
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
        /// B7 (FER-169): today's progression classification, for the live deload pill. Default nil so
        /// plan-less paths (templates, repeats) are untouched — same convention as `raise`.
        var progressionState: ProgressionState? = nil
        /// Ola 1 · E10 (FER-329): en semana ligera con «menos series y peso», la bajada va sobre el
        /// peso FINAL de la semilla (`earned ?? held ?? lastWeight`), porque «la última vez» gana al
        /// plan y taparía un recorte que solo viajara en `re` (arq-B §⑤; gate /qa D1). El plan servido
        /// (`re.sets`) ya viene rebajado, así que el cierre NO se aplica cuando la semilla cae a él.
        var lightLoad: ((Double) -> Double)? = nil
        /// Ola 1 · E5: por qué el ritmo «según reps en reserva» hizo lo que hizo — para la línea 2 del
        /// hub (`EntrenarView`). Default nil, misma convención que `raise`/`progressionState`.
        var raiseRhythmNote: ProgressionPlanner.RaiseRhythmNote? = nil
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
                // Regla fantasma (decisión Fer, FER-952): «si no lleno nada, que sea lo mismo que la
                // anterior» — la última vez gana al plan; la subida ganada (FER-E) sigue primero.
                // FER-82: a raise the day is HOLDING (`waiting`) does not seed — the table opens at
                // the weight the raise would climb FROM (the cycle's working load, i.e. last session's
                // top work set), and the raise is offered inside the session, one tap away. Using
                // `lastWeight` here would open at the last row logged, which may be a back-off set:
                // the hero would promise «la subida DESDE 82,5» over a table sitting at 70.
                let held = (type == .weightReps && slot.raise?.waiting == true) ? slot.raise?.fromKg : nil
                let earned = (type == .weightReps && slot.raise?.waiting == false) ? slot.raise?.toKg : nil
                let seeded = earned ?? held ?? lastWeight
                let weight = seeded.map { slot.lightLoad?($0) ?? $0 } ?? p.weightKg ?? 0
                // E13/FER-94: with a rep range (e.g. 8-12), the cell opens at the TOP — «la última
                // vez» still wins whenever it exists, exactly the fantasma rule above; the range top
                // only enters as the plan's fallback, same tier as the fixed `p.reps` it replaces.
                // Nancy · ronda 3: `max(1, …)` — una rutina con `targetReps` 0, o un historial viejo con
                // series de 0 reps, sembraba filas imposibles de registrar (ver `canRegisterCurrentSet`).
                let reps = usesReps ? max(1, lastReps ?? p.repsRangeTop ?? p.reps ?? 8) : 0
                // FER-327 (Q7): un AMRAP nace con la celda VACÍA — «las que puedas» no tiene número
                // hasta que la serie termina, y prellenarlo con «la última vez» convertiría un objetivo
                // abierto en una cuota. El ✓ queda bloqueado hasta que se escriba (`canRegisterCurrentSet`).
                let seededReps: Int? = (p.mode == .amrap && usesReps) ? nil : reps
                // FER-715: keep the planned `RoutineSet` id (so a per-set rest edit can persist back to the
                // routine) and carry the set's own rest override (nil = inherit the exercise at rest time).
                return WorkingSet(id: p.id, weightKg: weight, reps: seededReps, done: false, rest: p.rest,
                                  mode: p.mode)
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
                               lastRPE: last?.rpe,
                               sets: sets, currentSet: 0, skipped: false,
                               proposedRaise: type == .weightReps ? slot.raise : nil,
                               deloadState: type == .weightReps ? slot.progressionState : nil,
                               supersetGroup: slot.re.supersetGroup,
                               note: slot.re.note, seededNote: slot.re.note)
        }
        return StrengthSessionModel(routineId: routineId, routineName: routineName,
                                    startTs: startTs, runs: runs)
    }
}


#endif
