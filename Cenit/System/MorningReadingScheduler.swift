import Foundation
import UserNotifications
import StrandAnalytics

/// FER-114 · «Te aviso cuando esté»: UN solo aviso local al día, a la hora que el dueño elija, con la
/// palabra de SU lectura. Nada sale del iPhone: son `UNCalendarNotificationTrigger`s, sin push, sin
/// servidor. Copia la forma de `DietReminderScheduler` (el permiso se pide al encender el switch, el
/// horario se reconstruye entero cada vez que algo cambia) y le añade lo que aquí es obligatorio: la
/// HONESTIDAD sobre lo que puede prometer.
///
/// ## Por qué el aviso tiene dos caras (decisión de producto, FER-114)
///
/// Cénit calcula SOLO mientras está abierta: no hay servidor, no hay despertar en segundo plano
/// (ni `UIBackgroundModes` ni `enableBackgroundDelivery` de HealthKit en este proyecto). El texto de
/// una notificación, en cambio, se congela cuando se PROGRAMA. De ahí sale la regla dura:
///
/// - **El aviso jamás lleva una palabra que pueda envejecer.** El veredicto de mañana se calcula con
///   la noche de mañana, así que programar hoy «En rango» para mañana a las 7:00 sería inventarlo. La
///   palabra solo viaja cuando el aviso cae en el MISMO día civil en que se armó y ya hay lectura:
///   entonces la palabra del aviso es, letra por letra, la que el héroe está mostrando
///   (`LiquidHoyBuilder.palabraVeredicto`, nunca un string propio).
/// - **Los días que no puede llevar palabra, el aviso no finge tenerla:** es una CITA («Hora de
///   leerte»), no un veredicto. No dice que tu lectura esté lista, porque a esa hora nadie lo sabe.
/// - **Y si Cénit no puede dar veredicto, no hay aviso de ningún tipo.** Con la base calibrando, sin
///   FC en reposo nocturna, con la base rancia o sin la noche de hoy, el plan sale VACÍO y todo lo
///   pendiente se cancela: preferimos callar a mandar un aviso vacío.
///
/// El plan se re-arma con cada publicación del dashboard (`AppModel`) y cada vez que la pantalla de
/// Ajustes aparece o cambia la hora; por eso se arma un horizonte de `horizonteDias` de una sola vez
/// (los pendientes sobreviven al reinicio y al apagado del teléfono) en lugar de un trigger repetido:
/// un trigger `repeats: true` no podría llevar nunca la palabra del día sin que se volviera vieja.
///
/// (Sin `#if os(iOS)` a diferencia de `DietReminderScheduler` — no hay nada de UIKit aquí, y sin la
/// valla la capa de decisión se puede ejercitar fuera del target de la app.)
enum MorningReadingScheduler {

    // MARK: - Preferencia (UserDefaults; sobrevive al reinicio)

    static let enabledKey = "morningReading.enabled"
    static let hourKey = "morningReading.hour"
    static let minuteKey = "morningReading.minute"

    /// La hora por defecto del aviso: 7:00. `object(forKey:)`, no `integer(forKey:)` — con el segundo,
    /// «nunca lo he elegido» y «lo puse a medianoche» serían el mismo 0.
    static let horaPorDefecto = 7

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    static var hour: Int {
        get { UserDefaults.standard.object(forKey: hourKey) as? Int ?? horaPorDefecto }
        set { UserDefaults.standard.set(newValue, forKey: hourKey) }
    }
    static var minute: Int {
        get { UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: minuteKey) }
    }

    /// Cuántos días por delante se arman avisos de una vez. También es un límite honesto: a los 7 días
    /// sin abrir la app, lo que sabíamos de tu motor ya no vale para prometer nada, y el aviso calla
    /// hasta que Cénit vuelva a leerte.
    static let horizonteDias = 7

    /// Prefijo de nuestros identificadores, para cancelar SOLO los nuestros.
    private static let prefix = "morning-reading-"

    // MARK: - La decisión (pura: se prueba sin `UNUserNotificationCenter`)

    /// Qué puede decir honestamente el aviso de una fecha concreta.
    enum Aviso: Equatable {
        /// Cae hoy y la lectura ya existe: lleva la palabra del héroe, tal cual.
        case lectura(palabra: String)
        /// Cae en un día futuro: la palabra de ese día todavía no existe, así que el aviso es una
        /// cita, no un veredicto.
        case cita
    }

    struct Slot: Equatable {
        let id: String
        let fecha: Date
        let aviso: Aviso
    }

    /// ¿Hay lectura que dar? Es EXACTAMENTE la puerta del héroe (`LiquidHoyBuilder.acta`:
    /// `prep != nil && verdict != .lowSignal && isNightAnchored`). Cualquier otro estado del motor
    /// (calibrando, base rancia, sin FC en reposo, lectura de día sin noche grabada) cae en
    /// `lowSignal` o pierde el anclaje nocturno, y ahí no hay palabra que mandar.
    static func hayLectura(_ prep: Preparedness.Read?) -> Bool {
        guard let prep else { return false }
        return prep.verdict != .lowSignal && prep.isNightAnchored
    }

    /// Las próximas `count` ocurrencias de `hour:minute` ESTRICTAMENTE después de `desde`.
    /// `Calendar.nextDate` resuelve los dos casos raros del reloj: la hora que no existe el día que
    /// el horario de verano salta (`.nextTime` da la siguiente real) y la que ocurre dos veces
    /// cuando vuelve (`.first`).
    static func proximasOcurrencias(hour: Int, minute: Int, desde now: Date,
                                    calendar: Calendar = .current, count: Int) -> [Date] {
        guard (0..<24).contains(hour), (0..<60).contains(minute), count > 0 else { return [] }
        var out: [Date] = []
        var cursor = now
        let objetivo = DateComponents(hour: hour, minute: minute)
        for _ in 0..<count {
            guard let next = calendar.nextDate(after: cursor, matching: objetivo,
                                               matchingPolicy: .nextTime,
                                               repeatedTimePolicy: .first,
                                               direction: .forward) else { break }
            out.append(next)
            cursor = next
        }
        return out
    }

    /// El plan completo. Vacío = silencio (y el efecto cancela lo que hubiera pendiente).
    static func plan(prep: Preparedness.Read?, enabled: Bool, hour: Int, minute: Int,
                     now: Date, calendar: Calendar = .current,
                     dias: Int = horizonteDias) -> [Slot] {
        guard enabled, let prep, hayLectura(prep) else { return [] }
        // La palabra sale del héroe, jamás de un string de aquí: si el aviso dijera una palabra
        // distinta a la que se ve al abrir, la app se contradiría a sí misma.
        let palabra = LiquidHoyBuilder.palabraVeredicto(prep.verdict)
        return proximasOcurrencias(hour: hour, minute: minute, desde: now,
                                   calendar: calendar, count: dias)
            .enumerated().map { i, fecha in
                // Solo el aviso que cae HOY puede llevar la palabra: es la única fecha en la que la
                // lectura que tenemos en la mano seguirá siendo la del día cuando suene.
                let mismoDia = calendar.isDate(fecha, inSameDayAs: now)
                return Slot(id: "\(prefix)\(i)", fecha: fecha,
                            aviso: mismoDia ? .lectura(palabra: palabra) : .cita)
            }
    }

    /// El texto del aviso. La cita NO nombra ningún veredicto (ni promete que la lectura esté lista):
    /// a esa hora nadie lo sabe todavía.
    static func contenido(_ aviso: Aviso) -> (titulo: String, cuerpo: String) {
        switch aviso {
        case .lectura(let palabra):
            return (palabra,
                    String(localized: "aviso.matutino.lectura.cuerpo",
                           defaultValue: "Your reading for today is ready."))
        case .cita:
            return (String(localized: "aviso.matutino.cita.titulo",
                           defaultValue: "Time to read you"),
                    String(localized: "aviso.matutino.cita.cuerpo",
                           defaultValue: "Open Cénit and I will tell you what I found in your night."))
        }
    }

    // MARK: - Los efectos (`UNUserNotificationCenter`)

    /// Se pide EN EL MOMENTO en que se enciende el switch, nunca antes (el onboarding no lo pide).
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// El estado REAL del permiso, para que Ajustes pueda decir la verdad cuando lo negaron fuera.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Reemplaza el horario entero por el plan de este momento. Cancela SIEMPRE antes de agregar (y
    /// espera la cancelación) para que un cambio de hora no deje conviviendo la vieja con la nueva.
    static func reschedule(prep: Preparedness.Read?, now: Date = Date(),
                           calendar: Calendar = .current) async {
        await cancelAll()
        let slots = plan(prep: prep, enabled: isEnabled, hour: hour, minute: minute,
                         now: now, calendar: calendar)
        guard !slots.isEmpty else { return }
        // El permiso se pide al encender el switch; aquí solo se consulta (jamás un segundo diálogo).
        guard await authorizationStatus() == .authorized else { return }
        let center = UNUserNotificationCenter.current()
        for slot in slots {
            let texto = contenido(slot.aviso)
            let content = UNMutableNotificationContent()
            content.title = texto.titulo
            content.body = texto.cuerpo
            content.sound = .default
            let cuando = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: slot.fecha)
            let trigger = UNCalendarNotificationTrigger(dateMatching: cuando, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: slot.id,
                                                        content: content, trigger: trigger))
        }
    }

    /// Borra todo aviso matutino pendiente (solo los nuestros, por prefijo).
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
    }
}
