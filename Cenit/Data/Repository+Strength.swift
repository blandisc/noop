import Foundation
import StrandAnalytics
import StrandTraining
import CenitStore

// Repository+Strength.swift — read/write pass-throughs to the strength tracker (FER-346).
//
// Thin async wrappers over the `CenitStore` strength API (FER-345), mirroring `Repository+Goal`:
// no logic here, just `storeHandle()` + a clean call. The strength screens (builder / library /
// detail) talk to the store only through these, so they never hold a `CenitStore` of their own.
// All return empty/no-op when the store can't be opened (same contract as the rest of Repository).

extension Repository {

    // MARK: - The single oracle (FER-82)

    /// What Entrenar advises today — the SAME verdict Hoy is painting, translated once.
    ///
    /// This is a property of the repository, not a parameter anyone passes around, and that is the
    /// whole point: the first cut of FER-82 threaded the verdict through call sites with a default,
    /// and three surfaces (the routine editor, the history, the exercise detail) silently kept
    /// deciding by the old 0–100 score. Read it here and no caller can fall back by omission.
    ///
    /// `pending` mirrors Hoy's own gate (`todayPreparedness == nil && !fullyLoaded`): on a cold start
    /// the verdict only exists after the full refresh, and until then Entrenar says nothing and holds
    /// any raise rather than announcing one the verdict is about to withhold.
    ///
    /// READ IT ONCE PER PASS, before the loop that builds a table. Every exercise of one session must
    /// share one verdict: reading it per exercise leaves a window (each `await` on the store yields to
    /// the main actor, where a refresh publishes) for a table where some rows took the raise and others
    /// held it — one screen, two verdicts, which is the whole thing this epic removes.
    /// `isNightAnchored` es la MISMA puerta que Hoy exige para pronunciar la palabra (FER-85): sin
    /// noche anclada, Hoy degrada el día a «lectura de día» y NO dice el veredicto. Si Entrenar
    /// actuara igual sobre ese veredicto, retendría una subida por una palabra que la otra pantalla
    /// se está negando a decir — un oráculo con dos puertas es dos oráculos.
    var trainingAdvice: TrainingRegulation.Advice {
        let read = todayPreparedness
        let usable = read?.isNightAnchored == true ? read?.verdict : nil
        return TrainingRegulation.advice(verdict: usable,
                                         isPending: read == nil && !fullyLoaded)
    }

    // MARK: - Routines

    func routines() async -> [Routine] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.routines()) ?? []
    }

    func routineExercises(routineId: String) async -> [RoutineExercise] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.routineExercises(routineId: routineId)) ?? []
    }

    /// La ÚNICA siembra de los slots de la sesión de hoy. El héroe del teléfono y el arranque desde
    /// la muñeca construyen slots IDÉNTICOS para la misma rutina porque llaman AQUÍ — no dos bucles
    /// que hoy coinciden y mañana podrían no hacerlo (FER-124). La garantía no es un test: es que hay
    /// un solo bucle.
    ///
    /// `inventory` lo pasa quien llama (el teléfono lo lee de `PlatesStore`, el reloj de `plates`):
    /// es la única entrada que legítimamente difiere por superficie, y no cambia qué rutina ni qué
    /// progresión se siembra. `advice` es el veredicto ya resuelto, leído UNA vez por el llamador.
    /// Qué rutina toca hoy, o nil en día de descanso / sin plan. El teléfono y el reloj preguntan
    /// AQUÍ (FER-124): antes cada uno tenía su copia byte-idéntica del mismo `routineSchedule()` +
    /// `WeeklySplit.todayRoutineId`, el mismo riesgo de divergencia que la siembra, un nivel arriba.
    func todayRoutineId(weekday: Int = Calendar.current.component(.weekday, from: Date())) async -> String? {
        guard let store = await storeHandle() else { return nil }
        let sched = (try? await store.routineSchedule()) ?? []
        let split = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
        return WeeklySplit.todayRoutineId(split: split, todayWeekday: weekday)
    }

    /// `serving` (ola 1 · E10) lo pasa quien YA leyó la semana en este pase, por la misma razón que
    /// `advice` no tiene default (FER-82): leerla otra vez aquí serían DOS lecturas de la base por
    /// pase y, si una sesión se guardara entre ambas, la tabla quedaría recortada con una semana y la
    /// sesión marcada con otra. `nil` = «no hay programa activo».
    func seedTodaySlots(routineId: String, advice: TrainingRegulation.Advice,
                        inventory: [PlateMath.PlateStock],
                        serving: ProgramServing.Context?) async -> [StrengthSessionModel.PlanSlot] {
        guard let store = await storeHandle() else { return [] }
        let exs = (try? await store.routineExercises(routineId: routineId)) ?? []
        let memo = await StrengthExerciseMemo.load(for: self, store: store)
        var slots: [StrengthSessionModel.PlanSlot] = []
        for re in exs {
            let ex = (ExerciseCatalog.byID(re.exerciseId) ?? memo.customById[re.exerciseId])?.applying(memo.overrides)
            // La progresión se evalúa contra el plan GUARDADO (la receta real); el recorte de la
            // semana ligera solo viaja hacia la sesión, en el slot.
            let seed = await sessionSeed(re: re, exercise: ex, inventory: inventory, advice: advice,
                                         isLightWeek: serving?.isLight == true)
            let served = ProgramServing.serve(re, context: serving, equipment: ex?.equipment,
                                              inventory: inventory)
            slots.append(.init(re: served, exercise: ex, lastSets: seed.lastSets,
                               raise: seed.evaluation?.raise,
                               progressionState: seed.evaluation?.state,
                               lightLoad: ProgramServing.lightLoad(context: serving, equipment: ex?.equipment,
                                                                   inventory: inventory),
                               raiseRhythmNote: seed.evaluation?.rhythmNote))
        }
        return slots
    }

    // MARK: - Programa de varias semanas (ola 1 · E10, FER-329)

    /// El programa activo y la semana en la que va HOY — el ÚNICO punto de la capa app que responde
    /// «¿en qué semana voy?» y «¿toca ligera?». Toda pantalla que lo necesite llama aquí; ninguna
    /// vuelve a contar semanas. `nil` = no hay programa (la app entera se comporta como antes de E10).
    ///
    /// La semana se DERIVA (`ProgramCalendar`) de `startTs` + las semanas con ≥ 1 sesión terminada
    /// (D-Q2), así que no hay estado que refrescar ni que pueda quedar viejo.
    func programServing(now: Date = Date(),
                        calendar: Calendar = .current) async -> ProgramServing.Context? {
        guard let store = await storeHandle(),
              let program = (try? await store.program()) ?? nil else { return nil }
        let starts = (try? await store.sessionStartTimes(sinceTs: program.startTs)) ?? []
        let trained = ProgramCalendar.trainedWeekStarts(sessionStartTs: starts, calendar: calendar)
        let position = ProgramCalendar.position(of: program, trainedWeekStarts: trained,
                                                now: now, calendar: calendar)
        // Ola 1 · E11 (P7): «la semana pasada quedó en blanco» — mismo insumo (`trained`) que ya
        // calculó `position`, ninguna segunda consulta al store.
        let lastWeekBlank = ProgramServing.lastWeekWasBlank(startTs: program.startTs,
                                                            trainedWeekStarts: trained,
                                                            now: now, calendar: calendar)
        return ProgramServing.Context(program: program, position: position, lastWeekBlank: lastWeekBlank)
    }

    /// Alta/actualización y baja del programa activo. «Terminar programa» borra solo la fila: las
    /// rutinas y el calendario semanal quedan intactos.
    func setProgram(_ program: Program) async throws {
        guard let store = await storeHandle() else { return }
        try await store.setProgram(program)
    }

    /// Instala un motor materializado (rutinas + calendario + `program`) en UNA transacción — la
    /// puerta de «Empezar programa» (ola 1 · E11). Nunca N awaits desde la pantalla: si el teléfono se
    /// cierra a la mitad, o queda el programa completo o no queda nada nuevo.
    func installProgram(_ materialized: ProgramTemplate.Materialized) async throws {
        guard let store = await storeHandle() else { return }
        try await store.installProgram(materialized)
    }

    func endProgram() async throws {
        guard let store = await storeHandle() else { return }
        try await store.deleteProgram()
    }

    func saveRoutine(_ routine: Routine, exercises: [RoutineExercise]) async throws {
        guard let store = await storeHandle() else { return }
        try await store.saveRoutine(routine, exercises: exercises)
    }

    /// Pinpoint-update one routine exercise's rest config (FER-540) — for editing rest mid-session
    /// without rewriting the whole routine. No-op when the store can't be opened; throws on write failure.
    func updateRoutineExerciseRest(routineExerciseId reId: String, routineId: String,
                                   mode: RestMode, seconds: Int,
                                   reference: HRRestReference, value: Double) async throws {
        guard let store = await storeHandle() else { return }
        try await store.updateRoutineExerciseRest(
            routineExerciseId: reId, routineId: routineId, mode: mode, seconds: seconds,
            reference: reference, value: value, updatedTs: Int(Date().timeIntervalSince1970))
    }

    /// Pinpoint-update one planned set's rest override (FER-715, per-set scope) — `rest == nil` clears it
    /// back to inheriting the exercise. No-op when the store can't be opened; throws on write failure.
    func updateRoutineSetRest(routineSetId: String, routineId: String, rest: RestConfig?) async throws {
        guard let store = await storeHandle() else { return }
        try await store.updateRoutineSetRest(
            routineSetId: routineSetId, routineId: routineId, rest: rest,
            updatedTs: Int(Date().timeIntervalSince1970))
    }

    func deleteRoutine(id: String) async throws {
        guard let store = await storeHandle() else { return }
        try await store.deleteRoutine(id: id)
    }

    // MARK: - Reorder (FER-526)

    func reorderFolders(_ idsInOrder: [String]) async throws {
        guard let store = await storeHandle() else { return }
        try await store.reorderFolders(idsInOrder)
    }

    func reorderRoutines(_ idsInOrder: [String]) async throws {
        guard let store = await storeHandle() else { return }
        try await store.reorderRoutines(idsInOrder)
    }

    // MARK: - Exercises (bundled catalog + user-created)

    /// The full exercise list a library screen browses: the bundled seed catalog merged with the user's
    /// own exercises, sorted by name — each one re-typed by the user's measurement-type override (FER-541)
    /// so a catalog or custom override is respected everywhere this list feeds. Catalog stays read-only;
    /// the override is applied on read, not baked into the bundled data.
    ///
    /// Custom exercises + overrides are decoded once (via `StrengthExerciseMemo`) and reused by
    /// `resolvedExercise` in the same session until a custom/override write invalidates the memo.
    func allExercises() async -> [Exercise] {
        guard let store = await storeHandle() else { return ExerciseCatalog.all }
        let memo = await StrengthExerciseMemo.load(for: self, store: store)
        // Decode custom once; apply overrides from the same memo (no per-exercise store round-trip).
        return (ExerciseCatalog.all + memo.custom).map { $0.applying(memo.overrides) }.sorted { $0.name < $1.name }
    }

    /// One slot's guided-session seed: «la última vez» prefill + the progression evaluation (FER-E).
    /// The SINGLE implementation behind the Entrenar landing prefetch, the «Rutina» editor and the
    /// history, so the raise the hero names is exactly the raise the editor seeds (FER-838 /simplify).
    /// The evaluation is nil when the slot didn't opt in or has no load to progress.
    ///
    /// `advice` is required and has no default (FER-82): the first cut of this change defaulted it,
    /// and three screens silently kept deciding by the old 0–100 score. Pass `repo.trainingAdvice`,
    /// read ONCE before the loop, so every exercise of the table shares one verdict.
    /// `isLightWeek` (ola 1 · E10) apaga la SUBIDA de esa sesión: en la semana ligera se entrena menos,
    /// así que ofrecer más kilos ahí sería incoherente con lo que la pantalla acaba de servir. Default
    /// `false`, así que todo camino que no sabe de programas se comporta exactamente como antes.
    func sessionSeed(re: RoutineExercise, exercise: Exercise?,
                     inventory: [PlateMath.PlateStock],
                     advice: TrainingRegulation.Advice,
                     isLightWeek: Bool = false) async
        -> (lastSets: [SetEntry],
            evaluation: (state: ProgressionState, raise: ProgressionPlanner.Raise?,
                        rhythmNote: ProgressionPlanner.RaiseRhythmNote?)?) {
        guard let store = await storeHandle() else { return ([], nil) }
        let last = (try? await store.lastWorkSets(exerciseId: re.exerciseId, limit: 4)) ?? []
        guard re.progressionEnabled, exercise?.type == .weightReps else { return (last, nil) }
        let history = (try? await store.workSetHistory(exerciseId: re.exerciseId)) ?? []
        let eval = ProgressionPlanner.evaluate(re: re, history: history, inventory: inventory,
                                               equipment: exercise?.equipment, advice: advice,
                                               isLightWeek: isLightWeek)
        return (last, eval)
    }

    /// Resolve one exercise by id (catalog or custom) with its user type override applied — the single
    /// point every guided-session / builder / detail path uses, so no reader sees a non-overridden type.
    /// Precedence: override > custom > catalog (FER-541). nil if the id is unknown.
    ///
    /// Uses the session memo so a loop of `resolvedExercise` calls does not re-fetch/decode every
    /// custom exercise's JSON blobs on each id (N+1).
    func resolvedExercise(_ id: String) async -> Exercise? {
        let catalog = ExerciseCatalog.byID(id)
        var custom: Exercise?
        var override: ExerciseType?
        if let store = await storeHandle() {
            let memo = await StrengthExerciseMemo.load(for: self, store: store)
            custom = memo.customById[id]
            override = memo.overrides[id]
        }
        return Self.resolveExercise(id: id, catalog: catalog, custom: custom, override: override)
    }

    /// Pure resolution (override > custom > catalog). Shared by `resolvedExercise` and tests so the
    /// memo only owns fetch/decode, not the precedence rules.
    static func resolveExercise(id: String, catalog: Exercise?, custom: Exercise?,
                                override: ExerciseType?) -> Exercise? {
        guard let base = custom ?? catalog else { return nil }
        let eff = ExerciseTypeResolver.effectiveType(override: override, custom: custom?.type,
                                                     catalog: catalog?.type)
        return (eff != nil && eff != base.type) ? base.retyped(to: eff!) : base
    }

    /// The ids of the user-created exercises — so the library can tell which rows are its own (and so
    /// which of them are still missing a primary muscle, FER-995). Ids only: `allExercises()` has
    /// already decoded the rows themselves, so re-fetching them here would be a wasted second pass.
    func customExerciseIds() async -> Set<String> {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.customExerciseIds()) ?? []
    }

    func saveCustomExercise(_ e: Exercise) async throws {
        guard let store = await storeHandle() else { return }
        try await store.saveCustomExercise(e)
        StrengthExerciseMemo.invalidate(for: self)
    }

    // MARK: - Exercise type overrides (FER-541)

    /// The user's current type override for an exercise (nil = none) — so the detail screen can offer
    /// «revert to default» only when there is one.
    func exerciseTypeOverride(_ exerciseId: String) async -> ExerciseType? {
        guard let store = await storeHandle() else { return nil }
        let memo = await StrengthExerciseMemo.load(for: self, store: store)
        return memo.overrides[exerciseId]
    }

    /// Override an exercise's measurement type (catalog or custom).
    /// No-op when the store can't be opened; throws on write failure.
    func setExerciseTypeOverride(_ exerciseId: String, type: ExerciseType) async throws {
        guard let store = await storeHandle() else { return }
        try await store.setExerciseTypeOverride(exerciseId, type: type, ts: Int(Date().timeIntervalSince1970))
        StrengthExerciseMemo.invalidate(for: self)
    }

    /// Drop an exercise's type override → it reverts to its catalog/custom default.
    /// No-op when the store can't be opened; throws on write failure.
    func clearExerciseTypeOverride(_ exerciseId: String) async throws {
        guard let store = await storeHandle() else { return }
        try await store.clearExerciseTypeOverride(exerciseId)
        StrengthExerciseMemo.invalidate(for: self)
    }

    // MARK: - Learned exercise aliases (import matching memory — FER-523)

    /// The user's learned import aliases (normalized name → exerciseId), for the import reconciler.
    func learnedExerciseAliases() async -> [String: String] {
        guard let store = await storeHandle() else { return [:] }
        return (try? await store.learnedExerciseAliases()) ?? [:]
    }

    /// Remember an import mapping so the same name resolves on its own next time.
    /// No-op when the store can't be opened; throws on write failure.
    func saveLearnedExerciseAlias(name: String, exerciseId: String) async throws {
        guard let store = await storeHandle() else { return }
        try await store.saveLearnedExerciseAlias(name: name, exerciseId: exerciseId,
                                                 ts: Int(Date().timeIntervalSince1970))
    }

    // MARK: - Sessions (the completed-workout history)

    /// Completed strength sessions, newest first — the «Mis entrenamientos» list (FER-504). Read-only.
    func recentSessions(limit: Int = 200) async -> [StrengthSession] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.recentSessions(limit: limit)) ?? []
    }

    /// One full session row by id — for the edit sheet to seed every field (FER-556). nil if unknown.
    func session(id: String) async -> StrengthSession? {
        guard let store = await storeHandle() else { return nil }
        return (try? await store.session(id: id)) ?? nil
    }

    /// The logged sets of one session, in position order — the per-session breakdown (FER-504).
    func sessionSets(sessionId: String) async -> [SetEntry] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.setEntries(sessionId: sessionId)) ?? []
    }

    /// Per-session work volume + completed-set count, keyed by session id — the numbers the history
    /// list shows per row (FER-504). One aggregate read in the store.
    func sessionVolumes() async -> [String: (volumeKg: Double, setCount: Int)] {
        guard let store = await storeHandle() else { return [:] }
        return (try? await store.sessionVolumes()) ?? [:]
    }

    /// Delete a completed session (+ its sets) and recompute the affected PRs (FER-527).
    func deleteSession(id: String) async throws {
        guard let store = await storeHandle() else { return }
        try await store.deleteSession(id: id)
    }

    /// Restore a session deleted by «Undo» — re-saving re-derives its PRs (FER-527).
    func saveSession(_ session: StrengthSession, sets: [SetEntry]) async throws {
        guard let store = await storeHandle() else { return }
        try await store.saveSession(session, sets: sets)
    }

    /// Batch upsert for CSV import (FER-333 · E9) — one store transaction for the whole lote.
    func saveSessions(_ batch: [(session: StrengthSession, sets: [SetEntry])]) async throws {
        guard let store = await storeHandle() else { return }
        try await store.saveSessions(batch)
    }

    /// Which of `ids` already exist — «Ya estaban» for re-import (FER-333 · E9).
    func existingSessionIds(_ ids: [String]) async -> Set<String> {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.existingSessionIds(ids)) ?? []
    }

    /// Compact provenance for «Posibles duplicados» ±30 min (FER-333 · E9).
    func sessionSummariesForImportOverlap() async -> [(id: String, source: String?, title: String?, startTs: Int)] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.sessionSummariesForImportOverlap()) ?? []
    }

    /// Edit a saved session (sets / exercise / date / notes / routine) and recompute the affected PRs
    /// exactly — for the exercises in the old sets ∪ the new sets (FER-556). Never touches strain/avgHr.
    func updateSession(_ session: StrengthSession, sets: [SetEntry]) async throws {
        guard let store = await storeHandle() else { return }
        try await store.updateSession(session, sets: sets)
    }

    /// Ola 1 · E3: write the session-effort answer (and the load it implies) without touching sets.
    func updateSessionEffort(sessionId: String,
                             sessionRpe: Double?,
                             sessionRpeSource: SessionRpeSource?,
                             strain: Double?,
                             strainSource: StrainSource?,
                             trimpPerAU: Double?) async throws {
        guard let store = await storeHandle() else { return }
        try await store.updateSessionEffort(sessionId: sessionId,
                                            sessionRpe: sessionRpe,
                                            sessionRpeSource: sessionRpeSource,
                                            strain: strain,
                                            strainSource: strainSource,
                                            trimpPerAU: trimpPerAU)
    }

    /// Ola 1 · E3: how many finished strength sessions in the last `daysBack` days are estimated
    /// (`strainSource == .rpe`) vs trained-without-a-load (`strain == nil`). Feeds the Carga pie;
    /// `strengthEstimatedDays` remains the day-key set the overlay published.
    func strengthEffortProvenance(daysBack: Int = 28) async -> (estimated: Int, unrated: Int) {
        let sessions = await recentSessions(limit: 400)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
        let cutoff = Int(cutoffDate.timeIntervalSince1970)
        let window = sessions.filter { $0.endTs != nil && $0.startTs >= cutoff }
        let estimated = window.filter { $0.strainSource == .rpe }.count
        let unrated = window.filter { $0.strain == nil }.count
        return (estimated, unrated)
    }

    // MARK: - History (per exercise)

    /// Completed work sets for one exercise with their session start time, oldest→newest — the raw
    /// material the detail screen buckets by day into the estimated-1RM trend. One JOIN in the store.
    func exerciseHistory(exerciseId: String) async -> [WorkSetHistoryRow] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.workSetHistory(exerciseId: exerciseId)) ?? []
    }

    /// Stored best-per-metric records for one exercise (maxWeight / maxReps / maxVolume) — the «Records
    /// personales» list (FER-505). Derived on save; read-only here.
    func personalRecords(exerciseId: String) async -> [PersonalRecord] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.personalRecords(exerciseId: exerciseId)) ?? []
    }

    /// Every personal record, across every exercise — «Tus marcas» (FER-360) groups these by
    /// `exerciseId` to build its list. Empty when the store can't be opened, same contract as the
    /// rest of this file.
    func allPersonalRecords() async -> [PersonalRecord] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.allPersonalRecords()) ?? []
    }

    /// Every completed work set since `sinceTs` (epoch seconds) with its exercise id and session start
    /// time — the raw material the muscle-fatigue map (FER-350) expands over `Exercise.muscleInvolvement`.
    func recentWorkSets(sinceTs: Int) async -> [(exerciseId: String, startTs: Int)] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.workSetsSince(sinceTs)) ?? []
    }

    /// Work sets since `sinceTs`, already expanded to per-muscle `MuscleSetEvent`s (one per muscle each
    /// set hits, weighted by involvement, aged in whole local-calendar days from today). The shared
    /// fetch-and-expand «Volume per muscle» (FER-719) feeds on with `resetTs` left at its default (0,
    /// no filter) — that reading intentionally ignores the manual recovery reset. `resetTs` is the
    /// «mark all recovered» filter (FER-525, `MuscleFatigueMap`'s own doc): work sets before it never
    /// become events. FER-131's «Músculos cargados» line passes it so the landing can't contradict
    /// «Tu cuerpo» — the same reset the athlete just tapped there. Unknown exercise ids are skipped.
    func muscleSetEvents(sinceTs: Int, resetTs: Int = 0) async -> [MuscleFatigueMap.MuscleSetEvent] {
        let rawSets = await recentWorkSets(sinceTs: sinceTs)
        let byId = Dictionary(await allExercises().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        var events: [MuscleFatigueMap.MuscleSetEvent] = []
        for set in rawSets where set.startTs >= resetTs {
            guard let ex = byId[set.exerciseId] else { continue }
            let setDay = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(set.startTs)))
            let daysAgo = cal.dateComponents([.day], from: setDay, to: startToday).day ?? 0
            for inv in ex.muscleInvolvement {
                events.append(.init(muscle: inv.muscle, involvement: inv.weight, daysAgo: daysAgo))
            }
        }
        return events
    }

    /// Prior notes for one exercise, across other sessions (FER-932) — the «NOTAS ANTERIORES» history
    /// in the note sheet. Empty when the store can't be opened, same contract as the rest of this file.
    func exerciseNotes(exerciseId: String, excludingSession: String) async -> [ExerciseNote] {
        guard let store = await storeHandle() else { return [] }
        return (try? await store.exerciseNotes(exerciseId: exerciseId, excludingSession: excludingSession)) ?? []
    }

    // MARK: - Marcas del hub v18 (FER-171 · Parte B)

    /// El PR más reciente de todo el historial — «Marcas · N en {mes}» del hub. `nil` sin PRs.
    func latestPersonalRecord() async -> PersonalRecord? {
        guard let store = await storeHandle() else { return nil }
        return try? await store.latestPersonalRecord()
    }

    /// Cuántos PRs cayeron desde `sinceTs` — el rótulo «Marcas · N en {mes}».
    func personalRecordCount(sinceTs: Double) async -> Int {
        guard let store = await storeHandle() else { return 0 }
        return (try? await store.personalRecordCount(sinceTs: sinceTs)) ?? 0
    }

    /// «Tus marcas» (FER-360): `total` = exercises with ≥1 PR ever; `thisMonth` = exercises whose
    /// MOST RECENT PR falls within `[monthStart, monthEnd)`. DISTINCT exercises, never
    /// `personalRecordCount`'s row count — the hub tile's badge and the «Tus marcas» screen's header
    /// both read this same function, so neither can disagree with the other about "how many marks".
    func personalRecordExerciseStats(monthStart: Double, monthEnd: Double) async -> (total: Int, thisMonth: Int) {
        guard let store = await storeHandle() else { return (0, 0) }
        return (try? await store.personalRecordExerciseStats(monthStart: monthStart, monthEnd: monthEnd)) ?? (0, 0)
    }

    /// El PR anterior del mismo ejercicio+métrica — «antes X · hace N días».
    func previousPersonalRecord(exerciseId: String, metric: PRMetric, beforeTs: Double) async -> PersonalRecord? {
        guard let store = await storeHandle() else { return nil }
        return try? await store.previousPersonalRecord(exerciseId: exerciseId, metric: metric, beforeTs: beforeTs)
    }
}

extension Exercise {
    /// Rebuild this exercise with a different measurement type, preserving every other field (FER-541).
    /// The id is kept, so PRs / history / matching stay linked; `Exercise` is an immutable value type.
    func retyped(to t: ExerciseType) -> Exercise {
        Exercise(id: id, name: name, nameES: nameES, type: t, equipment: equipment,
                 bodyParts: bodyParts, primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles,
                 instructions: instructions, instructionsES: instructionsES, gifUrl: gifUrl)
    }

    /// Apply a user type-override map (FER-541): re-type if this exercise's id is overridden, else
    /// unchanged. The single fold every list-resolution path uses, so they can't diverge.
    func applying(_ overrides: [String: ExerciseType]) -> Exercise {
        overrides[id].map { retyped(to: $0) } ?? self
    }
}

// MARK: - Custom-exercise read memo (L3-F1)
//
// `resolvedExercise` used to call `store.customExercises()` on every id, which re-reads and
// JSON-decodes the entire custom table (N+1 when resolving a loop of ids). Memoize the decoded
// list + overrides per Repository until a write path invalidates. Stored off the Repository type
// so this file owns the cache without touching Repository.swift (another lane).

@MainActor
enum StrengthExerciseMemo {
    struct Entry {
        let custom: [Exercise]
        let customById: [String: Exercise]
        let overrides: [String: ExerciseType]
    }

    private static var entries: [ObjectIdentifier: Entry] = [:]

    /// Load (or return cached) decoded custom exercises + type overrides for this repository.
    static func load(for repo: Repository, store: CenitStore) async -> Entry {
        let key = ObjectIdentifier(repo)
        if let hit = entries[key] { return hit }
        let custom = (try? await store.customExercises()) ?? []
        let overrides = (try? await store.exerciseTypeOverrides()) ?? [:]
        let entry = Entry(
            custom: custom,
            customById: Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
            overrides: overrides
        )
        entries[key] = entry
        return entry
    }

    static func invalidate(for repo: Repository) {
        entries[ObjectIdentifier(repo)] = nil
    }

    /// Test-only: how many times `load` has populated a fresh entry for `repo` (cache misses).
    static func cachedEntry(for repo: Repository) -> Entry? {
        entries[ObjectIdentifier(repo)]
    }
}
