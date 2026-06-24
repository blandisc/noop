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

        let inputs = InsightEngine.Inputs(days: days, behaviors: behaviors,
                                          eligibleDaysByBehavior: eligibleDaysByBehavior, referenceDay: today)
        let proven = await repo.provenLevers()
        return InsightEngine.promoteProven(InsightEngine.generate(inputs), provenLevers: proven)
    }
}
