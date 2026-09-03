import Foundation
import StrandTraining
import StrandAnalytics

// ProgramServing.swift — cómo se SIRVE hoy la receta guardada (ola 1 · E10, FER-329).
//
// El puente de una sola pieza entre los tres motores puros que la semana ligera necesita y que viven
// en paquetes que no se conocen entre sí:
//   · `ProgramCalendar` (StrandTraining) dice en qué semana vamos,
//   · `ProgramDeload` (StrandTraining) dice qué le pasa a la receta,
//   · `ProgressionMath.deloadFraction` y `PlateMath.snap` (StrandAnalytics) ponen el 7,5 % y el
//     redondeo a un peso que de verdad se pueda armar.
// StrandTraining no puede importar StrandAnalytics (ver docs/ARCHITECTURE.md), así que la composición
// es de la capa app — pero de UN solo punto, este, no de cada pantalla.
//
// Invariante dura: esto transforma la semilla EN MEMORIA. Nunca escribe en `routineSet`: el plan que el
// usuario guardó sigue diciendo 4×8 con 100 kg aunque esta semana se sirva 2×8 con 92,5.
enum ProgramServing {

    /// El programa activo y dónde cae hoy dentro de él. `Sendable` porque lo devuelve una función
    /// `async` del `Repository` (@MainActor) y hay lectores que la esperan desde fuera del hilo
    /// principal — sus dos campos ya lo son, así que no cuesta nada y cierra el hueco antes de que sea
    /// un error en Swift 6.
    struct Context: Equatable, Sendable {
        let program: Program
        let position: ProgramCalendar.Position

        /// Sírvelo ligero: es la semana ligera y el programa no terminó.
        var isLight: Bool { position.isLight }
    }

    /// La receta de un ejercicio tal como toca hoy. Sin contexto (no hay programa) o en una semana
    /// normal devuelve el MISMO `RoutineExercise` que entró — byte por byte, no una copia reconstruida.
    static func serve(_ re: RoutineExercise, context: Context?,
                      equipment: String?, inventory: [PlateMath.PlateStock],
                      barKg: Double = PlateMath.defaultBarKg) -> RoutineExercise {
        guard let context, context.isLight else { return re }
        let implement = PlateMath.Implement.from(equipment: equipment)
        // La normalización de las dos formas del plan (receta explícita vs. `targetSets` abanicado) la
        // hace el motor, no este puente: aquí solo se inyecta lo que StrandTraining no puede importar.
        return ProgramDeload.apply(
            rule: context.program.deloadRule, to: re,
            // UNA familia de «bajar»: el mismo 7,5 % del deload reactivo, no una segunda copia.
            deloadFraction: ProgressionMath.deloadFraction,
            snap: { PlateMath.snap(targetKg: $0, implement: implement, barKg: barKg, inventory: inventory) })
    }
}
