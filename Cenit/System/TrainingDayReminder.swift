import Foundation
import UserNotifications

/// FER-95 · E14 — «Hoy toca entrenar»: a local reminder on each of the next `horizonteDias` days that
/// the weekly split assigns a routine to, at the hour the owner picks in Ajustes. Nothing leaves the
/// iPhone: `UNCalendarNotificationTrigger`s, same as `MorningReadingScheduler`, whose shape this
/// mirrors — pure plan + a thin effects layer, opt-in, permission requested only when the switch turns
/// on, silence (never a cancel) when there's nothing to plan.
///
/// ## Why the text never names the verdict
///
/// Same honesty rule `MorningReadingScheduler` documents at length: Cénit only computes while the app
/// is open, so a notification's text — frozen the moment it's SCHEDULED — cannot know what a future
/// day's verdict will say. The routine's NAME is safe to freeze (the weekly split is a standing plan,
/// not a daily computation); the verdict is not. So the text is always the same generic shape: it
/// names the routine, never how the day will feel.
///
/// ## Why a routine name can go stale between scheduling and delivery
///
/// The split can change after this reminder is scheduled (edit the weekly plan, delete the routine).
/// A slightly stale routine name in an already-queued notification is an accepted, documented
/// trade-off — the same one `MorningReadingScheduler`'s `horizonteDias` already makes for the ENTIRE
/// notification, not just its text: a plan built ahead of time can only be as fresh as the moment it
/// was built. The reminder re-arms on every dashboard publish (`AppModel`) and every time Ajustes
/// appears, so a real edit is corrected within, at most, the next natural refresh — never instantly,
/// same bound as the morning notice.
enum TrainingDayReminder {

    // MARK: - Preferencia (UserDefaults; sobrevive al reinicio)

    static let enabledKey = "trainingDayReminder.enabled"
    static let hourKey = "trainingDayReminder.hour"
    static let minuteKey = "trainingDayReminder.minute"

    /// La hora por defecto del aviso: la noche antes no aplica (no hay «mañana» que prometer), así
    /// que por defecto suena temprano el propio día — igual que el aviso matutino.
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

    /// Cuántos días por delante se arman avisos de una vez — mismo horizonte y misma razón que
    /// `MorningReadingScheduler`: la app no despierta sola, así que el horario se arma de golpe y
    /// sobrevive al reinicio; más allá de una semana el plan que lo armó ya no es de fiar.
    static let horizonteDias = 7

    private static let prefix = "training-day-reminder-"

    // MARK: - La decisión (pura: se prueba sin `UNUserNotificationCenter`)

    /// Un aviso programado, con el nombre de la rutina YA congelado.
    struct Slot: Equatable {
        let id: String
        let fecha: Date
        let routineName: String
    }

    /// Los próximos `dias` DÍAS DE CALENDARIO (hoy incluido) que el split asigna una rutina, cada uno
    /// como el instante `hour:minute` de ese día — se salta hoy si esa hora ya pasó. Apagado o sin
    /// split (ningún weekday asignado) da plan vacío, silencio total.
    static func plan(split: [Int: String], routineNames: [String: String],
                     enabled: Bool, hour: Int, minute: Int, now: Date,
                     calendar: Calendar = .current, dias: Int = horizonteDias) -> [Slot] {
        guard enabled, !split.isEmpty, (0..<24).contains(hour), (0..<60).contains(minute) else { return [] }
        let hoy = calendar.startOfDay(for: now)
        var out: [Slot] = []
        for offset in 0..<dias {
            guard let dia = calendar.date(byAdding: .day, value: offset, to: hoy),
                  let fecha = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dia),
                  fecha > now else { continue }
            let wd = calendar.component(.weekday, from: dia)
            guard let routineId = split[wd], let name = routineNames[routineId] else { continue }
            out.append(Slot(id: "\(prefix)\(offset)", fecha: fecha, routineName: name))
        }
        return out
    }

    /// El texto del aviso: genérico + el nombre de la rutina, sin veredicto (ver el comentario de
    /// cabecera). `routineName` viaja verbatim — es un nombre propio, no copy a localizar.
    static func contenido(routineName: String) -> (titulo: String, cuerpo: String) {
        (String(localized: "Today's training"),
         String(localized: "\(routineName) is on today's plan."))
    }

    // MARK: - Los efectos (`UNUserNotificationCenter`)

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Reemplaza el horario entero por el plan de este momento. Apagado, o sin permiso, cancela lo
    /// pendiente; con plan lo reemplaza; plan vacío por «sin split» también cancela — a diferencia del
    /// aviso matutino, aquí no hay un «todavía no sé» que preservar: el split es un dato síncrono del
    /// store, no un veredicto en cómputo, así que un plan vacío siempre significa «nada que prometer
    /// hoy», nunca «espera, ya llega».
    static func reschedule(split: [Int: String], routineNames: [String: String], now: Date = Date(),
                           calendar: Calendar = .current) async {
        guard isEnabled else { await cancelAll(); return }
        let slots = plan(split: split, routineNames: routineNames, enabled: true,
                         hour: hour, minute: minute, now: now, calendar: calendar)
        guard await authorizationStatus() == .authorized else { return }
        await cancelAll()
        guard !slots.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        for slot in slots {
            let texto = contenido(routineName: slot.routineName)
            let content = UNMutableNotificationContent()
            content.title = texto.titulo
            content.body = texto.cuerpo
            content.sound = .default
            let cuando = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: slot.fecha)
            let trigger = UNCalendarNotificationTrigger(dateMatching: cuando, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: slot.id, content: content, trigger: trigger))
        }
    }

    /// Borra todo aviso pendiente de este recordatorio (solo los nuestros, por prefijo).
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
    }
}
