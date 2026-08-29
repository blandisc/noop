import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// El catálogo háptico de Entrenar (FER-223): un único lugar para las señales de una sesión de
/// fuerza en el iPhone. Antes de esto, TODO Entrenar compartía un solo `.success` genérico
/// (`SetTable.swift`) — completar una serie, terminar el descanso y romper un récord se sentían
/// igual o, en varios call sites, no se sentían en absoluto. Cada caso tiene una firma DISTINTA y
/// justificada: romper un récord no puede sentirse igual que palomear una serie más.
///
/// Nomenclatura espejo de `WatchHaptic` (`CenitWatch/Health/WatchHaptics.swift`) para que iPhone y
/// Watch hablen el mismo idioma de eventos — no es el mismo tipo (el Watch habla `WKHapticType`,
/// aquí `SensoryFeedback`/`UIFeedbackGenerator`), pero un `restEnded`/`descansoTerminado` significa
/// lo mismo en las dos plataformas.
///
/// Este catálogo es SOLO para Entrenar. `ChartHaptics` (scrub de gráficas), `AppModel.buzz`
/// (temporizador/momentos sueltos, herencia de la banda retirada) y los `.sensoryFeedback` sueltos
/// de otras pantallas quedan intactos — no es un quinto sistema que los reemplace, es el catálogo de
/// esta superficie.
public enum EntrenarHaptic {
    /// Una serie más — el gesto más repetido de la sesión (decenas de veces por entrenamiento).
    /// `.selection`: el toque más ligero del catálogo, para que no canse al repetirse.
    case serieCompletada
    /// El descanso terminó y te reclama de vuelta — compite con que el teléfono está bocabajo en la
    /// banca, así que pide más presencia que una palomita: un impacto pesado, no una notificación
    /// (esa se reserva para el cierre de sesión/récord).
    case descansoTerminado
    /// Récord personal nuevo — el único evento que debe SENTIRSE especial. El patrón de éxito
    /// ascendente, reservado para esto y para el cierre de sesión: nunca para una serie más.
    case prNuevo
    /// Borrar una serie o un ejercicio — una advertencia corta, el mismo lenguaje que ya usa el undo
    /// del historial (`WorkoutHistoryScreen`), para que "esto se puede deshacer" se sienta igual en
    /// toda la app.
    case borrado
    /// La sesión arrancó — un toque suave de apertura, espejo de `WatchHaptic.sessionStart`. Sin
    /// call site propio todavía en el iPhone (el arranque no tenía ninguna háptica que reemplazar);
    /// se agrega para que el catálogo cubra el mismo vocabulario que el Watch desde el día uno.
    case sesionIniciada
    /// La sesión cerró y guardó — comparte patrón con `prNuevo` (las dos son un cierre exitoso) pero
    /// es infrecuente (una por sesión), así que compartir firma no genera confusión: nunca ocurren en
    /// el mismo segundo. Sin call site propio todavía, mismo motivo que `sesionIniciada`.
    case sesionTerminada

    /// La firma declarativa (`SwiftUI.SensoryFeedback`) — la forma preferida en este repo sobre
    /// `UIImpactFeedbackGenerator` imperativo, para vistas que ya tienen un valor `Equatable` que
    /// cambia justo cuando el evento ocurre (p. ej. `row.done`, `prFlash`).
    public var feedback: SensoryFeedback {
        switch self {
        case .serieCompletada:                    return .selection
        case .descansoTerminado:                  return .impact(weight: .heavy, intensity: 1.0)
        case .prNuevo, .sesionTerminada:           return .success
        case .borrado:                             return .warning
        case .sesionIniciada:                      return .impact(weight: .light)
        }
    }

    /// Reproduce la firma de inmediato. Para call sites sin un `Button`/valor observable a mano
    /// (closures de acción como "borrar", "✓ Serie" del keypad) — donde `.sensoryFeedback(trigger:)`
    /// no tiene de qué colgarse. No-op fuera de UIKit (macOS): el paquete compila también ahí y no
    /// puede importar UIKit sin guard.
    public func play() {
        #if canImport(UIKit)
        switch self {
        case .serieCompletada, .sesionIniciada:
            let gen = UISelectionFeedbackGenerator()
            gen.prepare()
            gen.selectionChanged()
        case .descansoTerminado:
            let gen = UIImpactFeedbackGenerator(style: .heavy)
            gen.prepare()
            gen.impactOccurred()
        case .prNuevo, .sesionTerminada:
            let gen = UINotificationFeedbackGenerator()
            gen.prepare()
            gen.notificationOccurred(.success)
        case .borrado:
            let gen = UINotificationFeedbackGenerator()
            gen.prepare()
            gen.notificationOccurred(.warning)
        }
        #endif
    }
}

extension View {
    /// Dispara la firma de Entrenar declarativamente cuando `trigger` cambia — envuelve
    /// `.sensoryFeedback` para que los call sites de Entrenar lean el nombre del evento, no el tipo
    /// crudo de SwiftUI.
    @ViewBuilder
    public func entrenarHaptic<T: Equatable>(_ haptic: EntrenarHaptic, trigger: T) -> some View {
        self.sensoryFeedback(haptic.feedback, trigger: trigger)
    }
}

#Preview("EntrenarHaptic — compila en iOS y macOS") {
    // No hay Taptic Engine en el preview; esto solo demuestra que el catálogo (declarativo +
    // imperativo, con su guard `canImport(UIKit)`) compila en las dos plataformas del paquete.
    VStack(spacing: 12) {
        Text("Serie completada").entrenarHaptic(.serieCompletada, trigger: true)
        Text("Descanso terminado").entrenarHaptic(.descansoTerminado, trigger: false)
        Button("PR nuevo (imperativo)") { EntrenarHaptic.prNuevo.play() }
    }
    .padding()
}
