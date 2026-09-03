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
        /// ¿La semana de calendario INMEDIATA ANTERIOR a hoy pasó sin ninguna sesión? Ola 1 · E11
        /// (P7): cuando es así, el contador no avanzó por eso — no es un bug, es D-Q2 funcionando
        /// («una semana en blanco no adelanta la ligera»). `false` en la primera semana del programa
        /// (no hay «semana pasada» todavía) y una vez que el programa terminó.
        let lastWeekBlank: Bool

        init(program: Program, position: ProgramCalendar.Position, lastWeekBlank: Bool = false) {
            self.program = program
            self.position = position
            self.lastWeekBlank = lastWeekBlank
        }

        /// Sírvelo ligero: es la semana ligera y el programa no terminó.
        var isLight: Bool { position.isLight }
        /// La semana que se estampa en la sesión: nil cuando el programa ya terminó («un solo ciclo»),
        /// porque una fila con `programWeek` afirma «había programa» (gate /qa D3).
        var stampWeek: Int? { position.ended ? nil : position.week }
        /// Y su pareja: nil cuando el programa terminó, si no «¿se sirvió ligera?».
        var stampDeload: Bool? { position.ended ? nil : position.isLight }
        /// Acabas de entrar a un ciclo nuevo (repetir el ciclo, D-Q4/D-Q7) y todavía no entrenas nada
        /// en él — P7 «Ciclo nuevo». `cycle` es base 0 (0 = la primera pasada), así que `cycle > 0`
        /// es «ya dimos al menos una vuelta completa».
        var isFreshCycle: Bool { !position.ended && position.cycle > 0 && position.week == 1 }
    }

    /// El cierre que `StrengthSessionModel.make` aplica al peso FINAL de la semilla en semana ligera
    /// con «menos series y peso»; nil en cualquier otro caso. Misma `deloadFraction` y mismo `snap`
    /// que `serve`, para que la semilla y el plan servido bajen a la misma cifra.
    static func lightLoad(context: Context?, equipment: String?, inventory: [PlateMath.PlateStock],
                          barKg: Double = PlateMath.defaultBarKg) -> ((Double) -> Double)? {
        guard let context, context.isLight, context.program.deloadRule == .volumeAndLoad else { return nil }
        let implement = PlateMath.Implement.from(equipment: equipment)
        return { kg in
            PlateMath.snap(targetKg: kg * (1 - ProgressionMath.deloadFraction), implement: implement,
                           barKg: barKg, inventory: inventory)
        }
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

    /// ¿La semana de calendario inmediatamente anterior a `now` pasó sin ninguna sesión? Pura — `now`
    /// y `calendar` entran por parámetro, mismo contrato que `ProgramCalendar` — para que un test fije
    /// el día sin tocar el reloj del sistema. Reusa `ProgramCalendar.weekStart` (el único cálculo de
    /// «qué lunes es este»); no reimplementa el redondeo a semana aquí.
    static func lastWeekWasBlank(startTs: Int, trainedWeekStarts: Set<Int>, now: Date,
                                 calendar: Calendar) -> Bool {
        let startWeek = ProgramCalendar.weekStart(of: startTs, calendar: calendar)
        let currentWeek = ProgramCalendar.weekStart(of: Int(now.timeIntervalSince1970), calendar: calendar)
        let previousWeek = ProgramCalendar.weekStart(of: currentWeek - 7 * 24 * 3_600, calendar: calendar)
        guard previousWeek >= startWeek, previousWeek < currentWeek else { return false }
        return !trainedWeekStarts.contains(previousWeek)
    }

    /// «· la semana ligera llega en la N» (ola 1 · E11, P8) — el sufijo del chip de estancamiento
    /// cuando hay programa con semana ligera y todavía falta para ella. `nil` sin programa, sin
    /// ligera (`deloadRule == .none`), con el programa ya terminado, o YA en la semana ligera (el
    /// chip de esa semana no necesita avisar que ya llegó). Quien arranca la sesión (`EntrenarView`,
    /// `RoutineSheetLogic`) lo calcula UNA vez con el `serving` que ya tiene — nunca una segunda
    /// consulta al store desde dentro de la sesión viva.
    static func stalledHint(context: Context?) -> String? {
        guard let context, !context.position.ended, context.program.deloadRule != .none,
              context.position.week < context.program.weeks else { return nil }
        return String(localized: "· light week arrives in \(context.position.weeksUntilLight)")
    }
}
