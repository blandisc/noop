import Foundation
import StrandTraining
import StrandAnalytics

/// La racha «días cumpliendo el plan» — UNA sola fuente para Entrenar y el bloque «Hoy en tu plan» del
/// Daily Brief (FER-613), para que nunca diverjan. Vive en la capa de app (no en `StrandAnalytics`) porque
/// depende del calendario LOCAL y de las `StrengthSession` persistidas; la matemática de adherencia/racha sí
/// es pura y vive en `WeeklySplit`.
///
/// Un día es de entreno si el split ACTUAL asigna su día de la semana, y «cumplido» si una sesión terminó
/// ese día. La ventana solo acota el bucle — la racha se corta en el día de entreno más reciente sin sesión.
enum TrainingStreak {

    /// Tope de la ventana de cálculo (solo acota el bucle; la racha real se corta antes si hubo un fallo).
    static let windowDays = 120

    /// Inicios de día locales con ≥1 sesión completada (la búsqueda que la racha lee).
    static func completedDayStarts(_ sessions: [StrengthSession], calendar: Calendar = .current) -> Set<Date> {
        var out = Set<Date>()
        for s in sessions where s.endTs != nil {
            out.insert(calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(s.startTs))))
        }
        return out
    }

    /// Estados de adherencia de la ventana, viejo→nuevo (el último = hoy). Insumo del gráfico de racha.
    static func adherenceStates(sessions: [StrengthSession], split: [Int: String],
                                now: Date = Date(), calendar: Calendar = .current) -> [WeeklySplit.DayAdherence] {
        let today = calendar.startOfDay(for: now)
        let done = completedDayStarts(sessions, calendar: calendar)
        var plans: [WeeklySplit.DayPlan] = []
        plans.reserveCapacity(windowDays)
        for offset in stride(from: windowDays - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let wd = calendar.component(.weekday, from: day)
            plans.append(.init(isTrainingDay: split[wd] != nil, trained: done.contains(day)))
        }
        return WeeklySplit.dailyAdherence(days: plans, includesToday: true)
    }

    /// La racha en días — el número que muestran tanto Entrenar como el bloque «Hoy en tu plan».
    ///
    /// Sin plan no hay racha. Sin este candado, un split vacío hace que TODOS los días de la ventana
    /// cuenten como `.metRest` (un día sin entreno asignado es «descanso cumplido»), así que la racha
    /// salía exactamente `windowDays`: a quien nunca configuró un plan la app le presumía «120 días
    /// cumpliendo el plan», que además es el tope de la ventana disfrazado de logro. Cumplir un plan
    /// que no existe no es una racha. (FER-973 · la prueba que lo cazaba nunca se había ejecutado.)
    ///
    /// `calendar` se puede inyectar como en `adherenceStates`/`completedDayStarts`: era la ÚNICA de
    /// las tres que no lo permitía, así que una prueba podía fijar las fechas en su zona horaria pero
    /// no el calendario con el que se bucketean, y el resultado dependía de la zona de la máquina.
    /// Pasaba en la Mac del dueño (CDMX) y fallaba en CI (UTC): una sesión de 19:30 en CDMX cae al día
    /// siguiente en UTC y parte la racha. Lo cazó la primera corrida de CI de esta suite (FER-50).
    static func streak(sessions: [StrengthSession], split: [Int: String],
                       now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard !split.isEmpty else { return 0 }
        return WeeklySplit.adherenceStreak(
            adherenceStates(sessions: sessions, split: split, now: now, calendar: calendar))
    }
}
