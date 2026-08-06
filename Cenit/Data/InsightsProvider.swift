import Foundation
import StrandAnalytics
import CenitStore

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

    /// Pure ranking core (testable seam). Clears ONLY `avgHrv` before the engine folds anything
    /// (`SourceLens.clearBandHrv`, the same lens «Qué la mueve» already uses).
    ///
    /// FER-48: this used to be `clearBandColumns`, which also nils `restingHr` and `respRateBpm` — and
    /// those are exactly the columns `InsightEngine.nightAnomalyInsights` probes, so NO vital anomaly
    /// could ever surface in Patrones or the Daily Brief. Live code that could not produce anything.
    /// The wide mask was inherited from the band era, when its job was to keep two instruments out of
    /// one baseline; with every row Apple-sourced there is no mixing left to prevent for a metric
    /// compared against its OWN history. What survives is HRV, and not because of the source: Apple
    /// records SDNN while `Baselines.hrvCfg` is tuned for RMSSD — different constructs, no published
    /// conversion (Task Force 1996; Shaffer & Ginsberg 2017). The honest nocturnal HRV path is
    /// `SourceFusion.autonomicTrend` (real `apple_rmssd_night`), which never comes through here.
    ///
    /// The engine reads NO sleep stages and NO `skinTempDevC` (pinned by
    /// `InsightEngineColumnSurfaceTests`), so widening the lens does not expose them: that contract
    /// test is now the guardrail the broad mask used to be by accident.
    ///
    /// `appleDays` no longer selects anything (every row is Apple) and is kept only for call-site
    /// compatibility.
    nonisolated static func rank(days: [DailyMetric], appleDays: Set<String>,
                                 behaviors: [String: Set<String>],
                                 eligibleDaysByBehavior: [String: Set<String>],
                                 proven: Set<Lever>, today: String) -> [Insight] {
        let bandDays = SourceLens.clearBandHrv(days)
        let inputs = InsightEngine.Inputs(days: bandDays, behaviors: behaviors,
                                          eligibleDaysByBehavior: eligibleDaysByBehavior, referenceDay: today)
        return InsightEngine.promoteProven(InsightEngine.generate(inputs), provenLevers: proven)
    }
}
