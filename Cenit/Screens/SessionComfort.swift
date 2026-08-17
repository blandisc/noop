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
//   • El descanso termina y solo hay háptica. Con el teléfono en el suelo o en el bolsillo, la
//     háptica no llega; un sonido corto sí. Apagado por defecto: un gimnasio no es un lugar donde
//     todos quieran que su teléfono suene.
//
// Nada de esto toca la red ni guarda datos: son dos banderas locales y una llamada del sistema.

enum SessionComfort {
    /// Mantener la pantalla encendida mientras hay una sesión viva. Apagado por defecto: cambiar el
    /// comportamiento del iPhone de alguien sin avisarle es de mala educación.
    static let keepAwakeKey = "noop.session.keepScreenAwake"
    /// Sonar al terminar el descanso, además de la háptica. Apagado por defecto.
    static let restSoundKey = "noop.session.restSound"

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

    /// El aviso del fin de descanso. La háptica la sigue dando la vista (`sensoryFeedback`); esto
    /// solo añade el sonido, y solo si el usuario lo encendió.
    static func playRestChime(defaults: UserDefaults = .standard) {
        guard isEnabled(restSoundKey, defaults: defaults) else { return }
        AudioServicesPlaySystemSound(restSoundID)
    }
}
#endif
