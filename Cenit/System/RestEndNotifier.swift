import Foundation
import os
import UserNotifications

// MARK: - RestEndNotifier — el aviso del descanso cuando el teléfono está guardado (FER-93 · E12)
//
// El caso real: dejas el iPhone en el piso entre series. La app se congela cuando la pantalla se
// bloquea, así que la vibración y el tono que la sesión da NO salen — el aviso llegaba tarde, al
// reabrir la app. Este es el único camino que sigue vivo con el teléfono bloqueado: una notificación
// LOCAL programada al segundo en que termina tu descanso.
//
// Local de verdad: se programa y se entrega en tu iPhone, nada sale a ningún lado. La app sigue sin
// red, como siempre.
//
// Dos reglas que la hacen aceptable, y que son lo que se prueba:
//   1. Se cancela SIEMPRE al salir del descanso (saltarlo, terminar la serie, cerrar la sesión).
//      Un aviso que suena cuando ya volviste a entrenar es peor que no avisar.
//   2. Solo existe una a la vez: al programar una nueva se retira la anterior, así que un descanso
//      re-editado a media cuenta no deja dos avisos compitiendo.
enum RestEndNotifier {
    /// Un solo identificador: programar de nuevo REEMPLAZA, nunca acumula.
    private static let requestID = "cenit.rest.end"

    /// Permiso, pedido en el momento en que el usuario enciende el interruptor — no en un arranque
    /// cualquiera ni a media sesión. Si lo niega, todo lo demás es un no-op silencioso: la sesión
    /// sigue vibrando y sonando con la app en pantalla.
    /// Devuelve si el sistema lo concedió: quien enciende el interruptor tiene derecho a que la app
    /// no se quede prometiendo algo que iOS ya negó.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Si este descanso merece un aviso. Pura y probada aparte: un `endsAt` ya vencido (el caso de
    /// reabrir la app con un descanso viejo en el modelo) dispararía un aviso inmediato de algo que
    /// terminó hace rato.
    static func shouldSchedule(endsAt: Date, now: Date = Date()) -> Bool {
        endsAt.timeIntervalSince(now) > 0
    }

    /// La generación viva del descanso. El alta de la notificación ocurre DENTRO del callback de
    /// `getNotificationSettings`, así que una cancelación posterior podía ejecutarse ANTES del alta
    /// y dejar un aviso huérfano programado. El token deja fuera al rezagado: si la generación
    /// cambió mientras el sistema contestaba, ese alta ya no vale.
    private static let generacion = OSAllocatedUnfairLock(initialState: 0)

    /// Programa el aviso para el final de este descanso. `endsAt` en el pasado (o sin permiso) no
    /// programa nada.
    static func schedule(endsAt: Date, now: Date = Date(),
                         center: UNUserNotificationCenter = .current()) {
        cancel(center: center)
        guard shouldSchedule(endsAt: endsAt, now: now) else { return }
        let mia = generacion.withLock { $0 }
        let delay = endsAt.timeIntervalSince(now)
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized,
                  generacion.withLock({ $0 }) == mia else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Rest is up")
            content.body = String(localized: "Your next set is waiting.")
            content.sound = .default
            // `.interruptionLevel` por defecto: esto no es una alarma médica, es un temporizador.
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
        }
    }

    /// Retira el aviso pendiente (y el ya entregado, para no dejar basura en el centro de
    /// notificaciones). Se llama en cada salida del descanso, incluso cuando no había ninguno.
    static func cancel(center: UNUserNotificationCenter = .current()) {
        // Invalida cualquier alta en vuelo antes de retirar lo ya programado.
        generacion.withLock { $0 &+= 1 }
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        center.removeDeliveredNotifications(withIdentifiers: [requestID])
    }
}
