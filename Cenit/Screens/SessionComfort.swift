#if os(iOS)
import SwiftUI
import AudioToolbox

// MARK: - SessionComfort — las dos comodidades de la sesión (FER-93 · E12)
//
// Dos cosas que Hevy tiene y aquí se notaban por su ausencia, las dos con interruptor porque las dos
// pueden estorbar:
//
//   • La pantalla se apaga a media serie. Entre serie y serie pasan dos minutos sin tocar nada, así
//     que el iPhone se duerme justo cuando lo levantas para anotar. Mientras haya una sesión viva,
//     el auto-bloqueo se suspende — y se restaura SIEMPRE al terminar, incluso si la app se va a
//     segundo plano: dejar el auto-bloqueo apagado por accidente le come la batería a alguien que
//     ya salió del gimnasio.
//   • El descanso por tiempo terminaba EN SILENCIO ABSOLUTO: ni háptica ni sonido (la háptica que
//     el copy prometía no existía en ninguna parte). Ahora vibra siempre y, si lo pides, además
//     suena. Apagado por defecto, porque un gimnasio no es lugar para que un teléfono suene sin
//     que su dueño lo haya decidido.
//
// El alcance del sonido está acotado a lo que de verdad ocurre, y el copy lo dice: obedece al
// switch de silencio (la app nunca fija una categoría de audio, así que se queda en `soloAmbient`)
// y solo suena con la app en pantalla, porque el temporizador vive en la vista y el sistema
// suspende el proceso cuando el iPhone se bloquea. Prometer el bolsillo pedía notificación local
// o Live Activity: eso es otro requerimiento, no un parche aquí.
//
// Nada de esto toca la red ni guarda datos: son dos banderas locales y una llamada del sistema.

enum SessionComfort {
    /// Mantener la pantalla encendida mientras hay una sesión viva. Apagado por defecto: cambiar el
    /// comportamiento del iPhone de alguien sin avisarle es de mala educación.
    ///
    /// La bandera la manejan `AppModel.startStrengthSession` / `endStrengthSession` /
    /// `closeStrengthSummary`, no una vista: el modo foco y el recibo se presentan como
    /// `fullScreenCover` DESDE la hoja, y una presentación así desmonta a quien presenta, así que
    /// colgarla del ciclo de vida de la vista la apagaba justo donde más se quiere.
    static let keepAwakeKey = "noop.session.keepScreenAwake"
    /// Sonar al terminar el descanso, además de la háptica. Apagado por defecto.
    static let restSoundKey = "noop.session.restSound"
    /// Avisar por notificación cuando el descanso termina con el teléfono guardado o bloqueado.
    /// Apagado por defecto y con permiso pedido en el momento de encenderlo (FER-93).
    static let restNotifyKey = "noop.session.restNotify"

    /// El tono del sistema que suena al terminar el descanso. `1057` es el «Tink» de iOS: corto,
    /// discreto y ya instalado — no se empaqueta un archivo de audio para esto.
    private static let restSoundID: SystemSoundID = 1057

    static func isEnabled(_ key: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    /// Suspende o restaura el auto-bloqueo. Idempotente: se puede llamar de más sin efecto.
    ///
    /// `active` es «hay una sesión viva Y el usuario lo pidió»; cualquier otra combinación restaura
    /// el comportamiento normal del sistema. La decisión de restaurar SIEMPRE al salir es
    /// deliberada: una app que deja el auto-bloqueo apagado tras cerrarse es una app que quema
    /// batería a espaldas de su dueño.
    @MainActor
    static func applyKeepAwake(active: Bool, defaults: UserDefaults = .standard) {
        let wanted = active && isEnabled(keepAwakeKey, defaults: defaults)
        if UIApplication.shared.isIdleTimerDisabled != wanted {
            UIApplication.shared.isIdleTimerDisabled = wanted
        }
    }

    /// El aviso del fin de descanso. La háptica es aparte (FER-223): solo el descanso fijo que se
    /// acaba SOLO tiene una — `EntrenarHaptic.descansoTerminado.play()` en `RestAutoSkipModifier` —,
    /// porque ahí nadie está mirando el teléfono. El toque manual de «Saltar ›»/«Continuar ›»
    /// (`HojaSesionViva.skipRest()`) no lleva háptico a propósito: quien lo toca ya sabe lo que hizo.
    /// Esta función solo añade el sonido, y solo si el usuario lo encendió.
    static func playRestChime(defaults: UserDefaults = .standard) {
        guard isEnabled(restSoundKey, defaults: defaults) else { return }
        AudioServicesPlaySystemSound(restSoundID)
    }
}
#endif
