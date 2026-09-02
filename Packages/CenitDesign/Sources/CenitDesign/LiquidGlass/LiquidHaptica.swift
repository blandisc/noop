import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Liquid Glass · Háptica (FER-269b · Fase 3)
//
// Un solo punto de verdad para el feedback háptico de la app (fuera de Entrenar y del
// scrub de gráficas). Cada caso es un ROL derivado del inventario real de call sites —
// dispara EXACTAMENTE el generador/estilo que ese sitio ya usaba. No se inventan
// eventos que ningún sitio dispare hoy.
//
// Complementa (no reemplaza):
//   · `EntrenarHaptic` — catálogo de la sesión de fuerza
//   · `ChartHaptics` — tick de scrub en gráficas

/// Catálogo háptico de Cénit por rol. Los call sites leen el nombre del evento, no el
/// tipo crudo de UIKit/SwiftUI.
public enum LiquidHaptica: String, CaseIterable, Sendable {
    /// Toque de sincronización / cue corto — impacto medio.
    /// Sitios: pull-to-sync de Hoy; `AppModel.buzz` con loops < 3.
    case toque
    /// Cue fuerte (temporizador / transición a trabajo) — impacto pesado.
    /// Sitios: `AppModel.buzz` con loops ≥ 3.
    case acento
    /// Cierre exitoso de un cue largo — notificación de éxito.
    /// Sitios: `AppModel.buzz` con loops ≥ 5 (además del impacto).
    case confirmacion
    /// Aviso de que la acción se puede deshacer — warning.
    /// Sitios: undo pendiente en historial de entrenos y editor del plan semanal.
    case advertencia

    /// Contrato de auditoría rol → estilo (el mismo que consumen `feedback` y `disparar`).
    /// Los tests anclan aquí para que un cambio de mapeo sea un fallo explícito.
    public var estiloDeclarado: String {
        switch self {
        case .toque:         return "impact.medium"
        case .acento:        return "impact.heavy"
        case .confirmacion:  return "notification.success"
        case .advertencia:   return "notification.warning"
        }
    }

    /// Firma declarativa (`SwiftUI.SensoryFeedback`) — forma preferida cuando hay un
    /// valor `Equatable` que cambia justo cuando el evento ocurre.
    public var feedback: SensoryFeedback {
        switch self {
        case .toque:         return .impact(weight: .medium)
        case .acento:        return .impact(weight: .heavy)
        case .confirmacion:  return .success
        case .advertencia:   return .warning
        }
    }

    /// Reproduce la firma de inmediato. Para call sites sin un valor observable a mano
    /// (p. ej. `AppModel.buzz`). No-op fuera de iOS: el paquete compila también para
    /// macOS y watchOS. El guard es `canImport(UIKit) && os(iOS)` — mismo contrato que
    /// `ChartHaptics` / `EntrenarHaptic.play()`: watchOS importa UIKit pero no tiene
    /// `UI*FeedbackGenerator`.
    public static func disparar(_ rol: LiquidHaptica) {
        #if canImport(UIKit) && os(iOS)
        switch rol {
        case .toque:
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred(intensity: 1.0)
        case .acento:
            let gen = UIImpactFeedbackGenerator(style: .heavy)
            gen.prepare()
            gen.impactOccurred(intensity: 1.0)
        case .confirmacion:
            let note = UINotificationFeedbackGenerator()
            note.prepare()
            note.notificationOccurred(.success)
        case .advertencia:
            let note = UINotificationFeedbackGenerator()
            note.prepare()
            note.notificationOccurred(.warning)
        }
        #endif
    }
}

extension View {
    /// Dispara la firma de LiquidHaptica declarativamente cuando `trigger` cambia —
    /// envuelve `.sensoryFeedback` para que el call site lea el rol, no el tipo crudo.
    @ViewBuilder
    public func liquidHaptica<T: Equatable>(_ rol: LiquidHaptica, trigger: T) -> some View {
        self.sensoryFeedback(rol.feedback, trigger: trigger)
    }
}

#Preview("LiquidHaptica — compila en iOS y macOS") {
    VStack(spacing: 12) {
        Text("Toque").liquidHaptica(.toque, trigger: true)
        Text("Advertencia").liquidHaptica(.advertencia, trigger: false)
        Button("Confirmación (imperativo)") { LiquidHaptica.disparar(.confirmacion) }
    }
    .padding()
}
