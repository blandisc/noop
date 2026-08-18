import Foundation
import StrandAnalytics
import StrandTraining
import CenitStore

/// FER-96 — the Apple Watch's idle-face verdict, and a wrist-initiated «Empezar». Both need the SAME
/// resolution `EntrenarView` already does for «today» (its routine, and — for the start path — that
/// routine's guided-session slots): the one-oracle invariant is that the watch never resolves either
/// itself, it only asks; the iPhone remains the single source of truth.
///
/// `EntrenarView.swift` is out of THIS phase's scope (owned by E4/FER-85, and — while this phase is in
/// flight — locked by a parallel FER-96 sibling lane working `Cenit/Screens/Routine*`), so
/// `startToday()`/`startTodayNow()` there can't be extracted into a shared call site in this same
/// change. This resolves with the identical store/repo primitives `EntrenarView.load()` and
/// `startToday()` use (`WeeklySplit.todayRoutineId`, `repo.sessionSeed`, `repo.trainingAdvice`) — never
/// a shortcut straight into `startStrengthSession` with guessed/stale slots. A follow-up should point
/// `EntrenarView.startToday()` at this same method once `Cenit/Screens/**` is free to touch, so there is
/// exactly one implementation, not two that happen to agree today.
extension AppModel {

    // MARK: - Idle-face verdict push

    /// Push the resting-face context (today's routine name + the already-resolved daily verdict) to the
    /// watch. Best-effort and silent on every failure path (no store, no plan, no watch) — the watch
    /// simply keeps whatever it last knew, or its existing «sin lectura» look.
    func pushWatchIdleContext() async {
        let routine = await todayRoutineForWatch()
        let hilo = LiquidHoyBuilder.hiloEntrenar(
            prep: repo.todayPreparedness,
            nights: repo.todayPreparedness?.autonomicNights ?? 0,
            healthConnected: healthBridge?.auth == .authorized,
            verdictPending: repo.todayPreparedness == nil && !repo.fullyLoaded,
            hasPlan: routine != nil)
        mirroringBridge?.pushIdleContext(word: hilo?.palabra, toneRaw: hilo.map(Self.watchToneRaw(_:)),
                                         advice: hilo?.consejo, routineName: routine?.name)
    }

    /// The wire vocabulary `CenitWatch` decodes (`"clear"/"caution"/"ease"/"hollow"`) for
    /// `LiquidHoyBuilder.HiloEntrenar.Tono` — the SAME 4-case mapping `EntrenarView.hiloTono(_:)` uses to
    /// reach `EntrenarHilo.Tone`, just ending in a plain `String` instead of the `StrandDesign` enum
    /// (`CenitShared` stays free of that import — Alcance §4).
    private static func watchToneRaw(_ hilo: LiquidHoyBuilder.HiloEntrenar) -> String {
        switch hilo.tono {
        case .claro:    return "clear"
        case .atencion: return "caution"
        case .alerta:   return "ease"
        case .hueco:    return "hollow"
        }
    }

    // MARK: - Wrist-initiated start

    /// «Empezar» tapped on the wrist's idle face (`.startFromWrist`), outside any session. A no-op with a
    /// session already running, on a rest day, or with an empty routine — exactly what
    /// `EntrenarView.startTodayNow(_:)` already refuses («guard !todaySlots.isEmpty else { openRoutine…
    /// }» — the watch has no routine screen to fall back into, so it simply doesn't start).
    func startTodayFromWrist() async {
        guard strengthSession == nil else { return }
        guard let routine = await todayRoutineForWatch() else { return }
        let slots = await resolveTodaySlotsForWatch(routineId: routine.id)
        guard !slots.isEmpty else { return }
        startStrengthSession(routineId: routine.id, routineName: routine.name, slots: slots)
    }

    /// Today's scheduled routine, or nil on a rest day / with no plan — the same resolution
    /// `EntrenarView.todayRoutine` uses (`WeeklySplit.todayRoutineId` over the stored weekly split).
    private func todayRoutineForWatch() async -> Routine? {
        guard let store = await repo.storeHandle() else { return nil }
        let sched = (try? await store.routineSchedule()) ?? []
        let splitMap = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
        let weekday = Calendar.current.component(.weekday, from: Date())
        guard let tid = WeeklySplit.todayRoutineId(split: splitMap, todayWeekday: weekday) else { return nil }
        return (try? await store.routines())?.first { $0.id == tid }
    }

    /// Today's guided-session slots for `routineId` — the same per-exercise seed («la última vez» +
    /// progression) `EntrenarView.load()` prefetches, via the ONE `repo.sessionSeed` implementation the
    /// «Rutina» editor also calls (FER-E/G), so a wrist start seeds identically to an iPhone start.
    ///
    /// Unlike `EntrenarView.todaySlots` (a cached `@State` that can go stale between the prefetch and the
    /// tap, needing `startToday()`'s one-retry-against-the-live-verdict dance), this is built fresh on
    /// every call — `repo.trainingAdvice` is read once, right here, always the CURRENT verdict — so there
    /// is no cache to go stale and nothing to retry.
    private func resolveTodaySlotsForWatch(routineId: String) async -> [StrengthSessionModel.PlanSlot] {
        guard let store = await repo.storeHandle() else { return [] }
        let exs = (try? await store.routineExercises(routineId: routineId)) ?? []
        let custom = (try? await store.customExercises()) ?? []
        let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let overrides = (try? await store.exerciseTypeOverrides()) ?? [:]
        let inventory = plates.inventory
        let advice = repo.trainingAdvice
        var slots: [StrengthSessionModel.PlanSlot] = []
        for re in exs {
            let ex = (ExerciseCatalog.byID(re.exerciseId) ?? customByID[re.exerciseId])?.applying(overrides)
            let seed = await repo.sessionSeed(re: re, exercise: ex, inventory: inventory, advice: advice)
            slots.append(.init(re: re, exercise: ex, lastSets: seed.lastSets, raise: seed.evaluation?.raise))
        }
        return slots
    }
}
