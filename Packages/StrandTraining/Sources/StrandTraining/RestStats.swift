import Foundation

/// Estadística del descanso real vs plan (FER-167), para la tile «DESCANSO REAL» del hub v18.
/// Puro y determinista — la UI solo formatea lo que este motor calcula. Media aritmética
/// documentada; sin cajas negras.
public enum RestStats {
    /// Un «descanso» mayor a esto se lee como interrupción (teléfono bloqueado, plática) y se
    /// excluye de la media. 900 s = 15 min, muy por encima de cualquier prescripción real.
    public static let interruptionCapS = 900

    /// Media redondeada de los descansos medidos (0…`interruptionCapS` incluidos, ambos límites
    /// dentro); `nil` sin datos que promediar. El insumo típico es
    /// `CenitStore.realRestSeconds(routineId:sessionLimit:)`.
    public static func averageRestS(_ restS: [Int],
                                    interruptionCapS: Int = RestStats.interruptionCapS) -> Int? {
        let kept = restS.filter { $0 >= 0 && $0 <= interruptionCapS }
        guard !kept.isEmpty else { return nil }
        let mean = Double(kept.reduce(0, +)) / Double(kept.count)
        return Int(mean.rounded())
    }

    /// Media redondeada del descanso prescrito sobre las series de TRABAJO planeadas de la
    /// rutina: para cada `RoutineSet` de trabajo, `RoutineExercise.effectiveRest(for:)` resuelve
    /// el override del set o, si no hay, el default del ejercicio. En modo FC (`RestMode
    /// .heartRate`) `seconds` es el TOPE del descanso, no un objetivo — así se compara contra el
    /// real. `nil` cuando ninguna serie de trabajo tiene descanso > 0 (p.ej. «sin descanso» en
    /// todos lados, o una rutina vacía).
    public static func plannedAverageRestS(_ exercises: [RoutineExercise]) -> Int? {
        let seconds = exercises.flatMap { ex in
            ex.plannedSets
                .filter { $0.kind == .work }
                .map { ex.effectiveRest(for: $0).seconds }
        }.filter { $0 > 0 }
        guard !seconds.isEmpty else { return nil }
        let mean = Double(seconds.reduce(0, +)) / Double(seconds.count)
        return Int(mean.rounded())
    }
}
