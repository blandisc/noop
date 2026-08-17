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

    /// Classify one exercise and, when the raise is earned today, build the seed + phrase.
    /// Returns (state, raise): `raise` is non-nil only for `.readyToAdvance`.
    static func evaluate(re: RoutineExercise,
                         history: [(startTs: Int, weightKg: Double, reps: Int, optedOut: Bool)],
                         inventory: [PlateMath.PlateStock],
                         equipment: String?,
                         recovery: Double?, recoveryZ: Double? = nil,
                         verdict: Preparedness.Verdict? = nil, hasVerdictSource: Bool = false)
        -> (state: ProgressionState, raise: Raise?)? {
        guard re.progressionEnabled else { return nil }
        let targetReps = re.plannedSets.first { $0.kind == .work }?.reps ?? re.targetReps ?? 8
        let targetSets = max(1, re.plannedSets.filter { $0.kind == .work }.count)
        let increment = re.progressionIncrementKg
            ?? PlateMath.minimumIncrement(for: .from(equipment: equipment), inventory: inventory)
        let sessions = pastSessions(from: history)
        // FER-82 «un solo oráculo»: when the caller hands us Hoy's verdict, IT decides whether an
        // earned raise goes through — the same word the user is reading at the top of the screen.
        // The legacy score path stays for callers that have no verdict source (and for its tests).
        let honoursRecovery = !re.progressionIgnoreRecovery
        let deferByVerdict = honoursRecovery && hasVerdictSource
            && !TrainingRegulation.allowsRaise(verdict: verdict)
        let reason = (honoursRecovery && !hasVerdictSource)
            ? TrainingRegulation.suggest(recovery: recovery, recoveryZ: recoveryZ)?.reason : nil
        let input = ProgressionMath.ProgressionInput(
            history: sessions.map(\.session),
            targetReps: targetReps, targetSets: targetSets,
            sessionsToAdvance: re.progressionSessions, incrementKg: increment,
            deloadWarnOnly: re.progressionDeload == .warn,
            recoveryReason: reason, deferRaise: deferByVerdict)
        let state = ProgressionMath.classify(input)
        guard case .readyToAdvance(let newKg) = state else { return (state, nil) }
        guard let fromKg = sessions.last?.session.workingKg else { return (state, nil) }
        // The qualifying dates: the trailing run of met sessions at the current weight, oldest first.
        let met = sessions.reversed().prefix {
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
        return (state, Raise(fromKg: fromKg, toKg: newKg, phrase: phrase))
    }
}
