import Foundation
import StrandAnalytics
import StrandModels

// MARK: - FER-51 · Inputs de la cara Matriz
//
// `MatrizInputs` es el material crudo día-alineado que Hoy resuelve una vez y las ventanas §7
// del builder recortan.

extension LiquidHoyBuilder {
    /// Las lecturas crudas de HOY para el acta, desde la fila del día: lo que Hoy y Entrenar
    /// pasan a `acta(lecturasHoy:)` para que las dos hojas digan lo mismo (FER-128 r12).
    static func lecturasHoy(_ today: DailyMetric?) -> (rhr: Bool, sueno: Bool) {
        (rhr: today?.restingHr != nil, sueno: today?.totalSleepMin != nil)
    }


    /// Entradas día-alineadas de la Matriz. Las ventanas §7 se recortan en el builder; aquí
    /// solo viaja el material crudo ya resuelto por Hoy.
    struct MatrizInputs {
        var prep: Preparedness.Read?
        /// suffix(21) + hoy, ordenado por `day` (de `repo.displayDays`).
        var diasRecientes: [DailyMetric] = []
        /// 0–3 diarios (`StressModel.fullTrend`), más viejo → más nuevo.
        var stressTrend: [(day: String, value: Double)] = []
        var carga: TrainingLoadModel?
        var stepsEstimados: [(day: String, value: Double)] = []
        var locale: Locale = .current
        var calendar: Calendar = .current
        var now: Date = Date()
    }
}
