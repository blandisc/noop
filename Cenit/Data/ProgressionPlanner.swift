import Foundation
import StrandTraining
import StrandAnalytics
import CenitStore

// ProgressionPlanner.swift — the app-layer bridge for load progression (FER-E).
//
// `ProgressionMath.classify` (StrandAnalytics) is pure and database-free; this is the ONE place that
// feeds it real app data: raw `workSetHistory` rows grouped into per-session facts, the plan's rep goal,
// the increment (manual override or derived from the plate inventory, FER-C), and today's recovery via
// `TrainingRegulation`. Output is the seed the session uses (`Raise`) plus the arithmetic phrase — every
// proposed kilo must be explainable in one sentence with real dates (transparency rule del handoff).

enum ProgressionPlanner {

    /// A proposed weight raise for one exercise, carried into the live session (FER-E · 2b).
    struct Raise: Equatable, Codable {
        let fromKg: Double
        let toKg: Double
        /// The one-sentence arithmetic justification («Hiciste 4×8 con 100 kg el jue 25 jun y el jue 2 jul»).
        let phrase: String
        /// FER-82: `true` when today's verdict held the raise. The cells seed at `fromKg` and the raise
        /// is offered, one tap away — held, never lost, and never a block on editing by hand.
        var waiting: Bool = false
    }

    /// Group raw work-set rows (oldest→newest) into per-session facts for the classifier. A session's
    /// working weight is its TOP work-set weight; the reps counted toward the goal are the reps done AT
    /// that weight (back-off sets at lighter loads don't gate the raise).
    static func pastSessions(from rows: [WorkSetHistoryRow])
        -> [(startTs: Int, session: ProgressionMath.PastSession)] {
        var grouped: [Int: [(weightKg: Double, reps: Int, optedOut: Bool, rpe: Double?, deload: Bool)]] = [:]
        for r in rows {
            grouped[r.startTs, default: []].append((r.weightKg, r.reps, r.optedOut, r.rpe, r.deload))
        }
        return grouped.keys.sorted().map { ts in
            let sets = grouped[ts]!
            let top = sets.map(\.weightKg).max() ?? 0
            let atTop = sets.filter { abs($0.weightKg - top) < 0.0001 }
            // Ola 1 · E4: the per-set effort rides ALONGSIDE the reps, same sets and same order, so a
            // missing rating reads as `.unknown` instead of shifting the rule onto the wrong set.
            return (ts, ProgressionMath.PastSession(workingKg: top, workSetReps: atTop.map(\.reps),
                                                    // FER-835: the «Volver a X» mark is per (session,
                                                    // exercise), so every row of the session carries it
                                                    // — any true makes the session invisible to the cycle.
                                                    optedOut: sets.contains { $0.optedOut },
                                                    workSetRPE: atTop.map(\.rpe),
                                                    // Ola 1 · E10: la marca de semana ligera es de la
                                                    // SESIÓN, así que viaja igual en todas sus filas.
                                                    deload: sets.contains { $0.deload }))
        }
    }

    /// Classify one exercise and, when a raise is earned, build the seed + phrase.
    ///
    /// FER-82 «un solo oráculo»: `advice` is the SAME verdict Hoy is painting, translated once in
    /// `TrainingRegulation`. It has no default — the day this parameter was optional, three screens
    /// kept deciding by the old 0–100 score and the app contradicted itself on the same day.
    ///
    /// Returns (state, raise). `raise` is non-nil for `.readyToAdvance` (applied to the seed) AND for
    /// `.deferred` (`waiting == true`: earned, held by today's verdict, offered one tap away).
    static func evaluate(re: RoutineExercise,
                         history: [WorkSetHistoryRow],
                         inventory: [PlateMath.PlateStock],
                         equipment: String?,
                         advice: TrainingRegulation.Advice,
                         isLightWeek: Bool = false)
        -> (state: ProgressionState, raise: Raise?)? {
        guard re.progressionEnabled else { return nil }
        // E13/FER-94: with a rep range (e.g. 8-12) the raise fires once every work set touches the
        // TOP, not the floor — `repsRangeTop` outranks the fixed `reps` it replaces. `nil` (no range,
        // today's behavior) falls through to `reps` exactly as before.
        let targetReps = re.plannedSets.first { $0.kind == .work }
            .flatMap { $0.repsRangeTop ?? $0.reps } ?? re.targetReps ?? 8
        let targetSets = max(1, re.plannedSets.filter { $0.kind == .work }.count)
        let increment = re.progressionIncrementKg
            ?? PlateMath.minimumIncrement(for: .from(equipment: equipment), inventory: inventory)
        let sessions = pastSessions(from: history)
        // Per-exercise opt-out: «ignora mi recuperación en este ejercicio» keeps the raise on the log alone.
        let honoursRecovery = !re.progressionIgnoreRecovery
        let input = ProgressionMath.ProgressionInput(
            history: sessions.map(\.session),
            targetReps: targetReps, targetSets: targetSets,
            sessionsToAdvance: re.progressionSessions, incrementKg: increment,
            deloadWarnOnly: re.progressionDeload == .warn,
            recoveryReason: nil,
            deferRaise: honoursRecovery && !TrainingRegulation.allowsRaise(advice),
            useRPE: re.progressionUseRPE)
        let state = ProgressionMath.classify(input)
        // Ola 1 · E10: en la semana ligera NO se propone subida. El estado se sigue calculando y se
        // sigue mostrando (el ciclo no se pierde: la subida ganada aparece la semana que sigue), pero
        // esta sesión se sirvió con menos volumen — ofrecer más kilos encima contradiría lo que la
        // tabla acaba de poner. La descarga reactiva NO se toca: `.deloading` no es una subida.
        guard !isLightWeek else {
            // La descarga REACTIVA sigue viva, pero proponer «bajar a X» en una sesión que ya se sirvió
            // ligera es una propuesta fantasma: aceptarla no cambia nada (con peso) o se desvanece al
            // ser frontera (solo series). Esta sesión avisa el estancamiento; la propuesta íntegra
            // reaparece en la semana 1 del ciclo siguiente (gate /biomecanico FER-329 #3).
            if case .deloading = state {
                return (.stalled(sessions: ProgressionMath.deloadStallThreshold), nil)
            }
            return (state, nil)
        }
        let newKg: Double
        let waiting: Bool
        switch state {
        case .readyToAdvance(let kg): newKg = kg; waiting = false
        case .deferred(let kg):       newKg = kg; waiting = true
        default: return (state, nil)
        }
        // FER-82: TODO lo que se muestra sale de las sesiones que el ciclo ve. Una sesión marcada
        // opt-out (se tomó la subida a media sesión, o se pulsó «Volver a X») tiene como peso tope el
        // NUEVO: leerla aquí devolvía fromKg = toKg —la siguiente sesión sembraba el peso subido
        // incluso en un día que retiene la subida— y cortaba la racha de fechas, dejando la frase
        // del «por qué» sin ninguna («Hiciste 3×8 con 82.5 kg el —»). El clasificador ya las ignora;
        // estas dos derivaciones también.
        // Ola 1 · E10: la semana ligera es FRONTERA también aquí — las sesiones servidas ligeras no
        // pueden ser «la última vez» del `fromKg` ni aparecer entre las fechas del «por qué»: se
        // hicieron con la mitad de las series (y quizá menos peso), así que nombrarlas como prueba de
        // la subida sería una frase que miente.
        let visible = sessions.filter { !$0.session.optedOut && !$0.session.deload }
        guard let fromKg = visible.last?.session.workingKg else { return (state, nil) }
        // The qualifying dates: the trailing run of met sessions at the current weight, oldest first.
        let met = visible.reversed().prefix {
            abs($0.session.workingKg - fromKg) < 0.0001 &&
            $0.session.workSetReps.count >= targetSets &&
            $0.session.workSetReps.allSatisfy { $0 >= targetReps }
        }.reversed().prefix(re.progressionSessions)
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.setLocalizedDateFormatFromTemplate("EEEdMMM")
        let dates = met.map { df.string(from: Date(timeIntervalSince1970: TimeInterval($0.startTs))) }
        let kgFmt = fromKg.formatted(.number.precision(.fractionLength(0...2)))
        let phrase: String
        if dates.count >= 2 {
            phrase = String(format: String(localized: "You did %lld×%lld with %@ kg on %@ and %@."),
                            targetSets, targetReps, kgFmt, dates[dates.count - 2], dates[dates.count - 1])
        } else {
            phrase = String(format: String(localized: "You did %lld×%lld with %@ kg on %@."),
                            targetSets, targetReps, kgFmt, dates.last ?? "—")
        }
        return (state, Raise(fromKg: fromKg, toKg: newKg, phrase: phrase, waiting: waiting))
    }
}
