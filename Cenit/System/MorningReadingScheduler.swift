import Foundation
import UserNotifications
import StrandAnalytics

/// FER-114 · «Recuérdame leerme en la mañana»: UN solo recordatorio local al día, a la hora que el
/// dueño elija. Nada sale del iPhone: son `UNCalendarNotificationTrigger`s, sin push, sin servidor.
/// Copia la forma de `DietReminderScheduler` (el permiso se pide al encender el switch, el horario se
/// reconstruye entero cada vez que algo cambia) y le añade lo que aquí es obligatorio: la HONESTIDAD
/// sobre lo que puede prometer.
///
/// ## Por qué es un RECORDATORIO y no una entrega (decisión de producto, FER-111)
///
/// Cénit calcula SOLO mientras está abierta: no hay servidor, no hay despertar en segundo plano
/// (ni `UIBackgroundModes`, ni `enableBackgroundDelivery` de HealthKit, ni `BGTaskScheduler` en este
/// proyecto). El texto de una notificación, en cambio, se congela cuando se PROGRAMA. De ahí sale la
/// regla dura:
///
/// - **El aviso jamás lleva la palabra del veredicto: es SIEMPRE el mismo texto.** Un texto congelado
///   no puede decir la palabra de un día que todavía no se ha calculado. Y el único aviso que sí
///   podría llevarla —el que cae el mismo día civil en que se armó el plan, con la lectura ya en la
///   mano— viaja necesariamente DESPUÉS de que el dueño abrió la app y ya la leyó: ese camino se
///   cuidaba con esmero y en la práctica no le tocaba a nadie (quien elige las 7:00 recibía siempre
///   el texto genérico). Un recordatorio fijo, en cambio, se cumple al 100% y forma más hábito que
///   una entrega intermitente. El aviso es una CITA («Hora de leerte»), no un veredicto: no dice que
///   tu lectura esté lista, porque a esa hora nadie lo sabe.
/// - **Y si Cénit no puede dar veredicto, no hay aviso NUEVO.** Con la base calibrando, sin FC en
///   reposo nocturna, con la base rancia o sin la noche de hoy, el plan sale VACÍO: no se programa
///   nada. A quien no tiene reloj no se le recuerda leer una lectura que no va a existir. Lo que ya
///   estaba pendiente NO se borra por eso — ver `reschedule`: «sin plan» significa «todavía no sé»,
///   y cancelar ahí es lo que dejaba al dueño sin su aviso de las 7:00 cada vez que abría la app
///   antes de que el reloj publicara la noche.
///
/// El plan se re-arma con cada publicación del dashboard (`AppModel`) y cada vez que la pantalla de
/// Ajustes aparece o cambia la hora; por eso se arma un horizonte de `horizonteDias` de una sola vez
/// (los pendientes sobreviven al reinicio y al apagado del teléfono) en lugar de un trigger repetido:
/// un `repeats: true` seguiría recordando para siempre aunque el motor se hubiera quedado mudo hace
/// meses, y el horizonte es justo el límite de lo que sabemos.
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

    /// Un aviso programado. No lleva texto: TODOS dicen lo mismo (ver `contenido`), así que la única
    /// decisión que queda por fecha es cuándo suena y con qué identificador se cancela.
    struct Slot: Equatable {
        let id: String
        let fecha: Date
    }

    /// ¿Hay lectura que dar? Es EXACTAMENTE la puerta del héroe (`LiquidHoyBuilder.acta`:
    /// `prep != nil && verdict != .lowSignal && isNightAnchored`). Cualquier otro estado del motor
    /// (calibrando, base rancia, sin FC en reposo, lectura de día sin noche grabada) cae en
    /// `lowSignal` o pierde el anclaje nocturno, y ahí no hay lectura que ir a leer.
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
        // `hayLectura` sigue siendo la puerta para PROGRAMAR, aunque el texto ya no dependa de ella:
        // a quien el motor no le puede dar veredicto no se le recuerda ir a leer nada.
        guard enabled, hayLectura(prep) else { return [] }
        return proximasOcurrencias(hour: hour, minute: minute, desde: now,
                                   calendar: calendar, count: dias)
            .enumerated().map { i, fecha in Slot(id: "\(prefix)\(i)", fecha: fecha) }
    }

    /// Qué hacer con el horario cuando llega una publicación nueva. Es la parte que se equivocaba,
    /// así que vive aparte y PURA para poder fijarla en pruebas (ver `MorningReadingSchedulerTests`);
    /// los efectos (`cancelAll` / `add`) son la capa delgada de abajo.
    enum Reprogramacion: Equatable {
        /// Hay plan nuevo: se reemplaza el horario entero.
        case reemplazar([Slot])
        /// Callar de verdad: el dueño apagó el aviso, o cambió la hora y ya no hay plan que poner.
        case cancelar
        /// «Todavía no sé»: no hay lectura que anunciar. Lo pendiente se queda donde está.
        case dejarComoEsta
    }

    /// - Parameter cancelaSinPlan: solo lo pide quien REEMPLAZA un horario (cambiar la hora): ahí,
    ///   quedarse con lo pendiente haría sonar el aviso a la hora vieja.
    static func reprogramacion(prep: Preparedness.Read?, enabled: Bool, hour: Int, minute: Int,
                               now: Date, calendar: Calendar = .current,
                               cancelaSinPlan: Bool = false,
                               dias: Int = horizonteDias) -> Reprogramacion {
        guard enabled else { return .cancelar }
        let slots = plan(prep: prep, enabled: true, hour: hour, minute: minute,
                         now: now, calendar: calendar, dias: dias)
        if !slots.isEmpty { return .reemplazar(slots) }
        return cancelaSinPlan ? .cancelar : .dejarComoEsta
    }

    /// El texto del aviso: UNO solo, el mismo todos los días. NO nombra ningún veredicto ni promete
    /// que la lectura esté lista — a esa hora nadie lo sabe todavía, y el texto se congeló al
    /// programarse. Invita a abrir la app, que es donde Cénit calcula.
    static var contenido: (titulo: String, cuerpo: String) {
        (String(localized: "aviso.matutino.cita.titulo",
                defaultValue: "Time to read you"),
         String(localized: "aviso.matutino.cita.cuerpo",
                defaultValue: "Open Cénit and I will tell you what I found in your night."))
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

    /// Reemplaza el horario entero por el plan de este momento.
    ///
    /// **«Sin plan» no es «apagado».** El `cancelAll()` incondicional de antes era un bug con
    /// consecuencia diaria: `repo.$dashboard` es `@Published`, así que el `.sink` de `AppModel`
    /// dispara de inmediato con el valor de `init` (`preparedness == nil`) → plan vacío → se
    /// borraban los 7 pendientes y nada los reponía. Abrir la app a las 06:00, antes de que el
    /// reloj publique la noche, dejaba el aviso de las 07:00 cancelado para siempre. Así que solo
    /// se cancela lo pendiente cuando hay una razón REAL para callar:
    ///
    ///   · el dueño apagó el switch (`enabled == false`), o
    ///   · hay plan nuevo que poner (y entonces se reemplaza entero), o
    ///   · quien llama lo pide explícitamente (`cancelaSinPlan`: cambiar la hora, donde dejar lo
    ///     viejo pendiente sonaría a la hora anterior).
    ///
    /// «Todavía no hay lectura» NO cancela: lo pendiente se armó cuando sí la había y sigue siendo
    /// honesto, porque el texto no afirma nada del cuerpo — solo recuerda abrir la app.
    ///
    /// Todo esto corre EN COLA (`Cola.compartida`): dos publicaciones seguidas del dashboard
    /// lanzaban dos tasks sueltas, y el `cancelAll()` de la vieja podía resolverse DESPUÉS del
    /// `add` de la nueva — el horario quedaba vacío sin que nadie lo hubiera pedido.
    static func reschedule(prep: Preparedness.Read?, now: Date = Date(),
                           calendar: Calendar = .current,
                           cancelaSinPlan: Bool = false) async {
        await Cola.compartida.encolar {
            await aplicar(prep: prep, now: now, calendar: calendar, cancelaSinPlan: cancelaSinPlan)
        }.value
    }

    /// El trabajo de `reschedule`, ya serializado por la cola. Cancela SIEMPRE antes de agregar (y
    /// espera la cancelación) para que un cambio de hora no deje conviviendo la vieja con la nueva.
    private static func aplicar(prep: Preparedness.Read?, now: Date,
                                calendar: Calendar, cancelaSinPlan: Bool) async {
        let slots: [Slot]
        switch reprogramacion(prep: prep, enabled: isEnabled, hour: hour, minute: minute,
                              now: now, calendar: calendar, cancelaSinPlan: cancelaSinPlan) {
        case .cancelar:      await cancelAll(); return
        case .dejarComoEsta: return
        case let .reemplazar(nuevos): slots = nuevos
        }
        // El permiso se pide al encender el switch; aquí solo se consulta (jamás un segundo diálogo).
        guard await authorizationStatus() == .authorized else { return }
        await cancelAll()
        let center = UNUserNotificationCenter.current()
        let texto = contenido
        for slot in slots {
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

    /// La cola de reprogramaciones: una a la vez, en el orden en que llegaron. Cada trabajo espera
    /// al anterior, así que un `cancelAll()` jamás puede aterrizar encima de los `add` de la
    /// reprogramación siguiente.
    private actor Cola {
        static let compartida = Cola()
        private var ultima: Task<Void, Never>?

        func encolar(_ trabajo: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
            let anterior = ultima
            let nueva = Task {
                await anterior?.value
                await trabajo()
            }
            ultima = nueva
            return nueva
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
