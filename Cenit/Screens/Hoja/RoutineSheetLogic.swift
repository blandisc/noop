#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// MARK: - RoutineSheet — carga, guardado, deshacer y mutaciones (FER-166)
//
// Ported 1:1 de `RoutineEditorScreen` (misma disciplina de autosave/deshacer/huérfanas) — solo la
// vista cambió de piel, este archivo es el motor. Ver el archivo retirado en git history para el
// diff exacto si algo aquí necesita compararse línea a línea.

extension RoutineSheet {

    // MARK: - Load + save

    /// El último paso de «la línea de la subida»: pasa la evaluación de `ProgressionPlanner` a
    /// `EditorItem.raise` sin re-filtrarla. Estática y pura para que un test la truene si alguien
    /// la envuelve en un gate de `advice`.
    static func raiseForEditorItem(
        _ evaluation: (state: ProgressionState, raise: ProgressionPlanner.Raise?)?
    ) -> ProgressionPlanner.Raise? {
        evaluation?.raise
    }

    func load() async {
        guard let store = await repo.storeHandle() else {
            routine = nil; items = []; itemsSnapshot = []; dirty = false; return
        }
        allRoutines = (try? await store.routines()) ?? []
        let target: Routine?
        switch origin {
        case .today(let id):
            let sched = (try? await store.routineSchedule()) ?? []
            let split = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
            let rid = id ?? WeeklySplit.todayRoutineId(
                split: split, todayWeekday: Calendar.current.component(.weekday, from: Date()))
            target = rid.flatMap { r in allRoutines.first { $0.id == r } }
        case .planDay(let wd):
            let sched = (try? await store.routineSchedule()) ?? []
            let rid = sched.first { $0.weekday == wd }?.routineId
            target = rid.flatMap { r in allRoutines.first { $0.id == r } }
        case .routine(let id):
            target = allRoutines.first { $0.id == id }
        }
        guard let r = target else {
            routine = nil; items = []; itemsSnapshot = []; dirty = false; return
        }
        routine = r
        let res = await repo.routineExercises(routineId: r.id)
        let all = await repo.allExercises()
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let inventory = plates.inventory
        let advice = repo.trainingAdvice
        let willStart = !isPlanDay && !res.isEmpty
        var built: [EditorItem] = []
        for re in res {
            guard let ex = byId[re.exerciseId] else { continue }
            if willStart {
                let seed = await repo.sessionSeed(re: re, exercise: ex, inventory: inventory, advice: advice)
                built.append(EditorItem(re: re, exercise: ex, lastSets: seed.lastSets,
                                        raise: Self.raiseForEditorItem(seed.evaluation)))
            } else {
                built.append(EditorItem(re: re, exercise: ex))
            }
        }
        // R4 (limpieza de datos legados): normaliza CUALQUIER rango piso/techo que haya quedado
        // invertido antes de que esta invariante existiera — nunca desde disco a un estado
        // imposible, ni por el tiempo que tarda la primera edición en tocarlo.
        for i in built.indices {
            for si in built[i].re.sets.indices {
                built[i].re.sets[si].repsRangeTop = RoutineSet.normalizedRepsRangeTop(
                    reps: built[i].re.sets[si].reps, top: built[i].re.sets[si].repsRangeTop)
            }
        }
        items = built
        refreshTint()
        dirty = false
        itemsSnapshot = items
        activeCell = nil
        // R6 (Grok G8): abre el primer BLOQUE, superserie incluida — no «el primer ejercicio
        // no-superserie». Una superserie ya se muestra completa siempre (nunca pliega), así que
        // cuando el primer bloque ES una superserie, `openID` se queda en nil a propósito: ningún
        // ejercicio SOLO debe robarse el acordeón porque el primero no calificaba.
        if let first = items.first, !RoutineSetEditing.inSuperset(items.map(\.re), 0) {
            openID = first.id
        } else {
            openID = nil
        }
    }

    func persist() {
        Task { await persistNow() }
    }

    @discardableResult
    func persistNow() async -> Bool {
        guard let r = routine else { return true }
        let now = Int(Date().timeIntervalSince1970)
        let updated = Routine(id: r.id, name: r.name, tag: r.tag, folderId: r.folderId,
                              createdTs: r.createdTs, updatedTs: now, sortOrder: r.sortOrder)
        let exercises = items.enumerated().map { idx, item -> RoutineExercise in
            var re = item.re; re.position = idx; re.routineId = r.id; return re
        }
        do {
            try await repo.saveRoutine(updated, exercises: exercises)
            return true
        } catch {
            saveError = true
            return false
        }
    }

    // MARK: - Navigation (Notes-style: autosave on leave when dirty)

    func back() {
        if isOrphan {
            Task { await discardOrphan(); dismiss() }
            return
        }
        guard dirty else { dismiss(); return }
        Task {
            if await persistNow() { dismiss() }
        }
    }

    /// C1: quedó vacía y con el nombre de fábrica — salir así dejaría una «Nueva rutina» fantasma.
    var isOrphan: Bool {
        guard let r = routine else { return false }
        return items.isEmpty && r.name == String(localized: "New routine")
    }

    func discardOrphan() async {
        guard let r = routine else { return }
        try? await repo.deleteRoutine(id: r.id)
    }

    func undo() {
        items = itemsSnapshot
        dirty = false
        refreshTint()
        persist()
    }

    // MARK: - Start the guided session

    func start() {
        // R1: el keypad no sigue escribiendo tras bloquear — bloquear es EXACTAMENTE lo que pasa
        // al arrancar/reanudar una sesión desde aquí.
        activeCell = nil
        if model.strengthSession != nil { model.resumeStrengthSession(); return }
        guard let r = routine else { return }
        if dirty { persist() }
        let slots = items.map {
            StrengthSessionModel.PlanSlot(re: $0.re, exercise: $0.exercise, lastSets: $0.lastSets,
                                          raise: $0.raise)
        }
        model.startStrengthSession(routineId: r.id, routineName: r.name, slots: slots)
    }

    // MARK: - Set + exercise mutations
    //
    // R1 (QA D1 = Grok G2): el candado vive en el MODELO — cada mutación corta con `guard !locked`,
    // no solo la vista que la dispara. La UI ya oculta/deshabilita los controles (paridad, doble
    // cinturón); esto es lo que de verdad impide escribir con una sesión viva corriendo esta rutina.

    func addSet(_ idx: Int) {
        guard !locked, items.indices.contains(idx) else { return }
        let work = items[idx].re.sets.last { $0.kind == .work }
        let reps = work?.reps ?? (showsReps(items[idx].exercise.type) ? 8 : nil)
        items[idx].re.sets.append(RoutineSet(position: items[idx].re.sets.count, kind: .work,
                                             reps: reps, weightKg: work?.weightKg,
                                             repsRangeTop: work?.repsRangeTop))
        dirty = true
    }

    /// R2 (QA D2 = Grok G6): por `setId` — la identidad FROZEN al armar la pastilla «Quitar serie»
    /// — nunca por un `si` de posición que el propio arrastre (o cualquier otra mutación) pudo
    /// haber corrido desde entonces.
    func deleteSet(idx: Int, setId: String) {
        guard !locked, items.indices.contains(idx),
              let si = items[idx].re.sets.firstIndex(where: { $0.id == setId }),
              items[idx].re.sets.count > 1 else { return }
        withAnimation(.snappy) { _ = items[idx].re.sets.remove(at: si) }
        renumber(idx)
        activeCell = nil   // R7: la celda dueña puede haber sido esta serie u otra que se corrió.
        dirty = true
    }

    func renumber(_ idx: Int) {
        for i in items[idx].re.sets.indices { items[idx].re.sets[i].position = i }
    }

    func hasWarmups(_ idx: Int) -> Bool { items[idx].re.sets.contains { $0.kind == .warmup } }

    /// «Añadir calentamiento» (A9, ahora en «···»): rampa 40·60·80 %.
    func addWarmupRamp(_ idx: Int) {
        guard !locked, items.indices.contains(idx) else { return }
        let ramp = RoutineSetEditing.warmupFactors
        items[idx].re.warmupPercents = ramp
        let top = items[idx].re.sets.first { $0.kind == .work }?.weightKg
        let usesReps = showsReps(items[idx].exercise.type)
        let rows = ramp.enumerated().map { i, pct in
            RoutineSet(position: i, kind: .warmup, reps: usesReps ? RoutineSetEditing.warmupReps : nil,
                       weightKg: top.map { $0 * pct })
        }
        withAnimation(.snappy) { items[idx].re.sets.insert(contentsOf: rows, at: 0) }
        renumber(idx)
        activeCell = nil   // R7: la rampa se inserta AL PRINCIPIO — corre el `si` de todo lo demás.
        dirty = true
    }

    func deleteExercise(_ idx: Int) {
        guard !locked, items.indices.contains(idx) else { return }
        let removedId = items[idx].id
        withAnimation(.snappy) { _ = items.remove(at: idx) }
        // R5: por id, no por índice — nada que reindexar.
        if openID == removedId { openID = nil }
        activeCell = nil
        refreshTint()
        dirty = true
    }

    func duplicate(_ idx: Int) {
        guard !locked, items.indices.contains(idx) else { return }
        let src = items[idx]
        var copy = src.re
        copy.id = UUID().uuidString
        copy.position = idx + 1
        copy.supersetGroup = nil
        copy.sets = src.re.sets.map { s in var n = s; n.id = UUID().uuidString; return n }
        withAnimation(.snappy) { items.insert(EditorItem(re: copy, exercise: src.exercise), at: idx + 1) }
        activeCell = nil
        refreshTint()
        dirty = true
    }

    /// Replace an exercise (keeping its sets) or append new ones, from the library.
    func addOrReplace(with picks: [Exercise]) {
        guard !locked, let first = picks.first, let r = routine else { return }
        if let i = replaceIndex, items.indices.contains(i) {
            items[i].exercise = first
            items[i].re.exerciseId = first.id
            activeCell = nil
        } else {
            var addedId: String? = nil
            for pick in picks {
                let usesReps = pick.type == .weightReps || pick.type == .bodyweight
                let reps: Int? = usesReps ? 8 : nil
                let sets = (0..<3).map { RoutineSet(position: $0, kind: .work, reps: reps, weightKg: nil) }
                let re = RoutineExercise(routineId: r.id, exerciseId: pick.id, position: items.count,
                                         targetSets: 3, targetReps: reps, targetWeightKg: nil, sets: sets)
                let item = EditorItem(re: re, exercise: pick)
                if addedId == nil { addedId = item.id }
                items.append(item)
            }
            // La tarjeta recién agregada se abre sola — no hay ceremonia entre agregar y prescribir.
            if let addedId { openID = addedId }
        }
        replaceIndex = nil
        refreshTint()
        dirty = true
    }

    // MARK: - «La receta que se pliega sola» + «Igualar todas» (ahora en «···», A3)

    func setsAreEqual(_ idx: Int) -> Bool {
        RoutineSetEditing.workSetsAreEqual(items[idx].re.sets)
    }

    /// R15 (QA D14): «3 × 10 · 145 kg» — el orden y la agrupación EXACTOS del mock
    /// (`hoja-pantallas.html` `.plegada .receta`: series × reps, luego el peso). Solo series de
    /// TRABAJO. Sin reps que emparejar (tiempo/distancia) cae al fallback legible «N sets».
    func recetaSummary(_ idx: Int) -> String {
        let work = items[idx].re.sets.filter { $0.kind == .work }
        let type = items[idx].exercise.type
        guard showsReps(type), let r = work.first?.reps else {
            return String(localized: "\(work.count) sets")
        }
        var head = "\(work.count) × \(r)"
        if showsWeight(type), let w = work.first?.weightKg, w > 0 {
            head += " · \(StrengthDisplay.weightNumber(w, system: system)) \(StrengthDisplay.weightUnit(system).lowercased())"
        }
        return head
    }

    /// A3 (pirámide sin castigo): cuántas recetas DISTINTAS hay entre las series de trabajo, cuando
    /// no son iguales — «2 recetas ›» en vez de fingir una sola línea.
    func recetaCount(_ idx: Int) -> Int {
        let work = items[idx].re.sets.filter { $0.kind == .work }
        var seen: [String] = []
        for s in work {
            let key = "\(s.weightKg ?? -1)-\(s.reps ?? -1)-\(s.repsRangeTop ?? -1)"
            if !seen.contains(key) { seen.append(key) }
        }
        return max(seen.count, 1)
    }

    /// «80 × 8 · Q 2» — la columna ANTERIOR. El peso/reps ya vivían en `RoutineEditorScreen`
    /// (`lastSetHistoryLabel`, sin Q); el «Q» es HONESTO, no inventado: reusa
    /// `LiveStrengthSheet.qLabel(fromRPE:)`, el mismo formateador que ya lee QUEDABAN desde
    /// `SetEntry.rpe` en el resto del app (RIR = 10 − RPE). Sin `rpe` capturado, no hay Q.
    func lastSetHistoryLabel(idx: Int, si: Int, type: ExerciseType) -> String? {
        guard items[idx].lastSets.indices.contains(si) else { return nil }
        let last = items[idx].lastSets[si]
        var parts: [String] = []
        if showsWeight(type), let w = last.weightKg { parts.append(StrengthDisplay.weightNumber(w, system: system)) }
        if showsReps(type), let r = last.reps { parts.append("\(r)") }
        guard !parts.isEmpty else { return nil }
        var label = parts.joined(separator: " × ")
        if let rpe = last.rpe { label += " · " + LiveStrengthSheet.qLabel(fromRPE: rpe) }
        return label
    }

    func equalizeAll(_ idx: Int) {
        guard !locked, items.indices.contains(idx),
              let first = items[idx].re.sets.first(where: { $0.kind == .work }) else { return }
        for si in items[idx].re.sets.indices where items[idx].re.sets[si].kind == .work {
            items[idx].re.sets[si].weightKg = first.weightKg
            items[idx].re.sets[si].reps = first.reps
            items[idx].re.sets[si].repsRangeTop = first.repsRangeTop
        }
        dirty = true
    }

    // MARK: - Arrastre ≡ (reordenar series dentro de un ejercicio, GAP cerrado del lane)
    //
    // Sin `List` por serie (las series viven dentro de UNA fila del `List` externo, la tarjeta
    // completa), así que no hay `.onMove` nativo aquí. Recorrido por umbral: cada vez que el dedo
    // cruza medio renglón, la serie arrastrada intercambia con su vecina — sin offset visual en
    // vuelo (decisión: simplicidad sobre pulir la animación de «Reordenar ejercicios», que sí
    // reutiliza `List.onMove`).
    //
    // R2 (QA D2 = Grok G6): llaveado por `dragID` = `RoutineSet.id`, FROZEN por el caller al
    // reconocer el gesto — nunca por un `si` de posición que un swap A MEDIO GESTO ya movió (la
    // cascada de swaps auto-guardados era corrupción real de la rutina: la vista podía seguir
    // entregando el `si` viejo mientras el arreglo ya había cambiado). La posición SIEMPRE se
    // resuelve de nuevo contra esa identidad en cada llamada; `rowHeight` es el alto REAL de la
    // fila (`HojaMetrics.hitMin`, 44 — el padding vertical ya está absorbido por ese `minHeight`,
    // sumarlo aparte medía 62 y desincronizaba el umbral del gesto contra la fila real).
    func dragSetChanged(idx: Int, setId: String, translation: CGFloat) {
        guard !locked, items.indices.contains(idx),
              let liveSi = items[idx].re.sets.firstIndex(where: { $0.id == setId }) else { return }
        let rowHeight = HojaMetrics.hitMin
        let state = (dragSet?.idx == idx && dragSet?.dragID == setId)
            ? dragSet! : DragSetState(idx: idx, dragID: setId, startSi: liveSi, currentSi: liveSi)
        let count = items[idx].re.sets.count
        let desired = min(max(state.startSi + Int((translation / rowHeight).rounded()), 0), count - 1)
        guard desired != state.currentSi else { dragSet = state; return }
        let toOffset = desired > state.currentSi ? desired + 1 : desired
        withAnimation(.snappy) {
            items[idx].re.sets.move(fromOffsets: IndexSet(integer: state.currentSi), toOffset: toOffset)
        }
        renumber(idx)
        dirty = true
        dragSet = DragSetState(idx: idx, dragID: setId, startSi: state.startSi, currentSi: desired)
    }

    func dragSetEnded() {
        dragSet = nil
    }

    /// Mismo criterio de identidad que `dragSetChanged`, para reordenar MIEMBROS de una superserie
    /// entre sí (el mock también dibuja «≡» en cada `.ssrow`). `dragID` = `RoutineExercise.id` del
    /// miembro arrastrado; `lo`/`hi` acotan el rango del grupo (fijo mientras dura el gesto — un
    /// reacomodo INTERNO no cambia cuántos miembros tiene ni dónde empieza/termina el bloque).
    func dragMemberChanged(members: [Int], dragID: String, translation: CGFloat) {
        guard !locked, let lo = members.min(), let hi = members.max(),
              items.indices.contains(lo), items.indices.contains(hi),
              let liveIdx = (lo...hi).first(where: { items[$0].re.id == dragID }) else { return }
        let rowHeight = HojaMetrics.hitMin
        let state = (dragSet?.idx == -1 && dragSet?.dragID == dragID)
            ? dragSet! : DragSetState(idx: -1, dragID: dragID, startSi: liveIdx, currentSi: liveIdx)
        let desired = min(max(state.startSi + Int((translation / rowHeight).rounded()), lo), hi)
        guard desired != state.currentSi else { dragSet = state; return }
        let toOffset = desired > state.currentSi ? desired + 1 : desired
        withAnimation(.snappy) {
            items.move(fromOffsets: IndexSet(integer: state.currentSi), toOffset: toOffset)
        }
        dirty = true
        dragSet = DragSetState(idx: -1, dragID: dragID, startSi: state.startSi, currentSi: desired)
    }

    // MARK: - Superset helpers (grouping lives in RoutineSetEditing)

    func firstOfGroup(_ i: Int) -> Bool { RoutineSetEditing.firstOfGroup(items.map(\.re), i) }

    func exerciseRest(_ idx: Int) -> RestConfig {
        let re = items[idx].re
        return RestConfig(mode: re.restMode, seconds: re.restSeconds,
                          hrReference: re.hrRestReference, hrValue: re.hrRestValue)
    }

    /// «＋ RONDA» (C2): agrega una ronda a TODOS los miembros del grupo a la vez, sembrada con la
    /// prescripción visible de cada uno (set 0 — el que la tarjeta muestra y edita).
    func addRound(members: [Int]) {
        guard !locked, members.allSatisfy({ items.indices.contains($0) }) else { return }
        for idx in members {
            let seed = items[idx].re.sets.first
            items[idx].re.sets.append(RoutineSet(position: items[idx].re.sets.count, kind: .work,
                                                 reps: seed?.reps, weightKg: seed?.weightKg,
                                                 repsRangeTop: seed?.repsRangeTop))
        }
        activeCell = nil
        dirty = true
    }

    /// Quita la ÚLTIMA ronda de todos los miembros a la vez (mantiene sus arreglos de series del
    /// mismo tamaño). No baja de 1 ronda.
    func removeLastRound(members: [Int]) {
        guard !locked, members.allSatisfy({ items.indices.contains($0) && items[$0].re.sets.count > 1 }) else { return }
        for idx in members {
            withAnimation(.snappy) { _ = items[idx].re.sets.removeLast() }
        }
        activeCell = nil
        dirty = true
    }

    func supersetWithNext(_ i: Int) {
        guard !locked, items.indices.contains(i) else { return }
        var res = items.map(\.re)
        RoutineSetEditing.supersetWithNext(&res, i)
        for (j, re) in res.enumerated() { items[j].re = re }
        activeCell = nil
        dirty = true
    }
    func breakSuperset(_ i: Int) {
        guard !locked, items.indices.contains(i) else { return }
        var res = items.map(\.re)
        RoutineSetEditing.breakSuperset(&res, i)
        for (j, re) in res.enumerated() { items[j].re = re }
        activeCell = nil
        dirty = true
    }

    /// One-step move (menu «Move up/down»). Cruzar el límite de una superserie solo la entra/sale
    /// visualmente; los grupos se conservan por id — `openID` (R5) no necesita reindexarse.
    func moveExercise(_ idx: Int, to dest: Int) {
        guard !locked, items.indices.contains(idx), items.indices.contains(dest) else { return }
        withAnimation(.snappy) { items.swapAt(idx, dest) }
        activeCell = nil
        dirty = true
    }

    // MARK: - Meta computations

    var totalSets: Int { items.reduce(0) { $0 + $1.re.sets.filter { $0.kind == .work }.count } }

    /// A transparent time estimate (display only): ~40 s of work per work set plus its resolved rest.
    var estimatedMinutes: Int {
        var seconds = 0
        for item in items {
            for si in item.re.sets.indices where item.re.sets[si].kind == .work {
                seconds += 40 + RoutineSetEditing.effectiveRest(item.re, si).seconds
            }
        }
        return max(1, Int((Double(seconds) / 60).rounded()))
    }

    /// R15 (QA D14): el tonelaje estimado de la meta («· ~4,300 kg») — suma peso × reps × series de
    /// TRABAJO de toda la prescripción. `nil` cuando ningún ejercicio tiene peso (bodyweight/tiempo
    /// puros): no hay tonelaje que fingir, así que la meta lo omite.
    var estimatedTonnageKg: Double? {
        var total = 0.0
        var sawWeight = false
        for item in items {
            for s in item.re.sets where s.kind == .work {
                guard let kg = s.weightKg, kg > 0, let reps = s.reps else { continue }
                sawWeight = true
                total += kg * Double(reps)
            }
        }
        return sawWeight ? total : nil
    }

    func refreshTint() {
        var tally: [MuscleGroup: Int] = [:]
        for item in items {
            for m in item.exercise.primaryMuscles { if let g = MuscleGroup.of(m) { tally[g, default: 0] += 1 } }
        }
        var best: MuscleGroup?
        var bestCount = 0
        for g in MuscleGroup.allCases where (tally[g] ?? 0) > bestCount {
            best = g; bestCount = tally[g] ?? 0
        }
        routineTint = best?.tint(theme) ?? theme.inkTertiary
        groupTitle = best?.title ?? String(localized: "Mixed")
    }

    func showsReps(_ t: ExerciseType) -> Bool { t == .weightReps || t == .bodyweight }
    func showsWeight(_ t: ExerciseType) -> Bool { t == .weightReps }

    // MARK: - Day assignment (.planDay «···»)

    func changeRoutine(to r: Routine) {
        guard !locked, let wd = planWeekday else { return }
        Task {
            guard let store = await repo.storeHandle() else { saveError = true; return }
            do {
                try await store.setRoutineSchedule(weekday: wd, routineId: r.id)
                await load()
            } catch {
                saveError = true
            }
        }
    }

    func markRest() {
        guard !locked, let wd = planWeekday else { return }
        Task {
            if dirty, !(await persistNow()) { return }
            guard let store = await repo.storeHandle() else { saveError = true; return }
            do {
                try await store.clearRoutineSchedule(weekday: wd)
            } catch {
                saveError = true
                return
            }
            dismiss()
        }
    }

    // MARK: - «···» del ejercicio (A9: solo bloque edición)

    func exerciseMenuItems(_ idx: Int) -> [PaperMenuItem] {
        let item = items[idx]
        var rows: [PaperMenuItem] = []
        if !hasWarmups(idx) {
            rows.append(.init(String(localized: "Add warm-up"), systemImage: "flame") {
                addWarmupRamp(idx)
            })
        }
        if !setsAreEqual(idx) {
            rows.append(.init(String(localized: "Equalize all sets"), systemImage: "equal.square") {
                equalizeTarget = idx
            })
        }
        let res = items.map(\.re)
        if idx > 0 {
            rows.append(.init(String(localized: "Move up"), systemImage: "arrow.up") { moveExercise(idx, to: idx - 1) })
        }
        if idx < items.count - 1 {
            rows.append(.init(String(localized: "Move down"), systemImage: "arrow.down") { moveExercise(idx, to: idx + 1) })
        }
        rows.append(.init(String(localized: "Reorder exercises"), systemImage: "line.3.horizontal") {
            activeCell = nil
            withAnimation(.snappy) { reordering = true }
        })
        if idx < items.count - 1 && !RoutineSetEditing.sameGroup(res, idx, idx + 1) {
            rows.append(.init(String(localized: "Superset with next"), systemImage: "link") { supersetWithNext(idx) })
        }
        if RoutineSetEditing.inSuperset(res, idx) {
            rows.append(.init(String(localized: "Undo superset"), systemImage: "link") { breakSuperset(idx) })
        }
        if item.exercise.type == .weightReps {
            rows.append(.init(String(localized: "Progression"),
                              subtitle: item.re.progressionEnabled
                                  ? ProgressionChip.summary(item.re, system: system,
                                                            derived: PlateMath.minimumIncrement(for: .from(equipment: item.exercise.equipment), inventory: plates.inventory))
                                  : nil,
                              systemImage: "chart.line.uptrend.xyaxis") {
                progressionTarget = ProgressionTarget(ei: idx)
            })
        }
        rows.append(.init(String(localized: "Change exercise"), systemImage: "arrow.triangle.2.circlepath") {
            replaceIndex = idx; showLibrary = true
        })
        rows.append(.init(String(localized: "Duplicate"), systemImage: "plus.square.on.square") { duplicate(idx) })
        rows.append(.init(String(localized: "Remove from routine"), systemImage: "trash", isDestructive: true) {
            deleteExercise(idx)
        })
        return rows
    }
}
#endif
