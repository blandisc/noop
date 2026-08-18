import Foundation
import StrandTraining
import StrandAnalytics

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
    static func pastSessions(from rows: [(startTs: Int, weightKg: Double, reps: Int, optedOut: Bool)])
        -> [(startTs: Int, session: ProgressionMath.PastSession)] {
        var grouped: [Int: [(weightKg: Double, reps: Int, optedOut: Bool)]] = [:]
        for r in rows { grouped[r.startTs, default: []].append((r.weightKg, r.reps, r.optedOut)) }
        return grouped.keys.sorted().map { ts in
            let sets = grouped[ts]!
            let top = sets.map(\.weightKg).max() ?? 0
            let repsAtTop = sets.filter { abs($0.weightKg - top) < 0.0001 }.map(\.reps)
            // FER-835: the «Volver a X» mark is per (session, exercise), so every row of the session
            // carries it — any true means the whole session is invisible to the cycle.
            return (ts, ProgressionMath.PastSession(workingKg: top, workSetReps: repsAtTop,
                                                    optedOut: sets.contains { $0.optedOut }))
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
                         history: [(startTs: Int, weightKg: Double, reps: Int, optedOut: Bool)],
                         inventory: [PlateMath.PlateStock],
                         equipment: String?,
                         advice: TrainingRegulation.Advice)
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
            deferRaise: honoursRecovery && !TrainingRegulation.allowsRaise(advice))
        let state = ProgressionMath.classify(input)
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
        let visible = sessions.filter { !$0.session.optedOut }
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
