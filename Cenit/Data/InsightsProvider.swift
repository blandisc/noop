import Foundation
import StrandAnalytics
import WhoopStore

/// La lista rankeada de `Insight` — UNA sola fuente para Patrones (BucleView) y «La conexión de hoy» del
/// Daily Brief (FER-614), para que la correlación que muestra el brief sea EXACTAMENTE la misma (misma
/// familia FDR, misma significancia) que la de Patrones. Vive en la capa de app porque arma los insumos
/// desde `Repository`; la matemática (correlación, FDR, ranking) vive en `InsightEngine`.
///
/// Reproduce el armado de insumos de `BucleView.load()` (comportamientos del diario + dieta), SIN sus efectos
/// secundarios (no cierra experimentos, no toca frescura): solo produce los hallazgos rankeados.
@MainActor
enum InsightsProvider {

    static func generate(repo: Repository, today: String) async -> [Insight] {
        let days = repo.days

        // Comportamientos del diario: día → {días con «sí»}.
        let entries = await repo.journalEntries()
        var behaviors: [String: Set<String>] = [:]
        for e in entries where e.answeredYes { behaviors[e.question, default: []].insert(e.day) }

        // Adherencia a la dieta como comportamiento (FER-385), acotada a los días realmente registrados.
        var eligibleDaysByBehavior: [String: Set<String>] = [:]
        if let from = days.map(\.day).min() {
            let dietByDay = await repo.dietAdherenceByDay(from: from, to: today)
            let dietKey = JournalCatalogStore.dietBehaviorKey
            if !dietByDay.isEmpty, behaviors[dietKey] == nil {
                behaviors[dietKey] = DietAdherence.adherentDays(percentByDay: dietByDay)
                eligibleDaysByBehavior[dietKey] = Set(dietByDay.keys)
            }
        }

        let proven = await repo.provenLevers()
        // FER-872: the ranking core (correlations + FDR over the whole journal history) is pure and can be
        // heavy; hop it off the main actor so the launch cascade's `loadAll` doesn't block a frame on it.
        // Inputs are snapshotted on the main actor above (all value types), so nothing races.
        let appleDays = repo.appleHealthDays
        return await Task.detached(priority: .userInitiated) {
            rank(days: days, appleDays: appleDays, behaviors: behaviors,
                 eligibleDaysByBehavior: eligibleDaysByBehavior, proven: proven, today: today)
        }.value
    }

    /// Pure ranking core (testable seam). Masks every cross-source column to the BAND source (FER-639)
    /// BEFORE the engine folds any HRV/RHR/resp baseline, anomaly or correlation — the same
    /// `SourceLens.maskForBaseline(keep:.band)` the Recovery detail and «Hoy» use (FER-631/632). Without
    /// it, `InsightEngine`'s HRV baseline (`avgHrv`) mixes band RMSSD with Apple SDNN (no published
    /// conversion — Task Force 1996; Shaffer & Ginsberg 2017), so «anoche tu HRV corrió bajo tu base» and
    /// the HRV↔behavior correlations shift by SCALE, not physiology. `strain`/ACWR (trainingLoadInsight)
    /// aren't cross-source columns, so that path is untouched. `appleDays == []` (strap-only) is the
    /// identity — an existing strap user's insights are bit-for-bit unchanged.
    nonisolated static func rank(days: [DailyMetric], appleDays: Set<String>,
                                 behaviors: [String: Set<String>],
                                 eligibleDaysByBehavior: [String: Set<String>],
                                 proven: Set<Lever>, today: String) -> [Insight] {
        let bandDays = SourceLens.maskForBaseline(days, keep: .band, appleDays: appleDays)
        let inputs = InsightEngine.Inputs(days: bandDays, behaviors: behaviors,
                                          eligibleDaysByBehavior: eligibleDaysByBehavior, referenceDay: today)
        return InsightEngine.promoteProven(InsightEngine.generate(inputs), provenLevers: proven)
    }
}
