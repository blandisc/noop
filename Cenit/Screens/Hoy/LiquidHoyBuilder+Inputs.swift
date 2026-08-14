import Foundation
import StrandAnalytics
import StrandModels

// MARK: - FER-51 · Inputs compartidos de la cara Matriz
//
// `MatrizInputs` es el material crudo día-alineado que Hoy resuelve una vez y las ventanas §7
// del builder recortan. (`CosmosExtraInputs` sobrevive del modo Cosmos, ya retirado.)

extension LiquidHoyBuilder {

    /// Entradas día-alineadas de la Matriz (y base del Cosmos). Las ventanas §7 se recortan
    /// en el builder de cada cara; aquí solo viaja el material crudo ya resuelto por Hoy.
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

    /// Lecturas de HOY ya resueltas por los tiles (mismas resoluciones que `LiquidHoyBuilder.Inputs`).
    /// `temp` es el delta de temp de piel mostrado; el medidor usa `prep.thermalAdjustedDevC`
    /// cuando existe (descuento lúteo ya aplicado).
    struct CosmosExtraInputs {
        var sleep: Lectura?
        var rhr: Lectura?
        var hrv: Lectura?
        var temp: Lectura?
        var resp: Lectura?
        var stress: Double?
        var strain: Double?
        var steps: Double?
    }
}
