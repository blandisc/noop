import SwiftUI

// MARK: - NumeroVivo (FER-222)
//
// Todos los numerales vivos de Entrenar deben comportarse como el BPM del widget de Live Activity
// (`RestLiveActivity.swift`): transición suave al cambiar de valor, ancho estable cruzando dígitos
// (99 → 100), y respeto a Reduce Motion. Antes de este modificador cada superficie decidía su
// propio comportamiento por su cuenta (o no decidía nada, y el numeral saltaba). Este es el ÚNICO
// lugar donde se fija ese contrato — los call sites solo pasan el valor que cambia.
//
// Patrón copiado de `MatrizHoyFace.swift`/`RecoveryZoneGauge.swift`/`BreathingView.swift`:
// `.monospacedDigit()` + `.contentTransition(reduceMotion ? .identity : .numericText())` +
// `StrandMotion.countUp` (el mismo `easeOut(0.75)` que ya usa el recibo de la sesión). El gate de
// Reduce Motion vive AQUÍ, no en cada call site (`strandAnimation` ya lo hace para la animación; la
// transición de contenido se gatea igual, en el `body` de este modificador).

private struct NumeroVivoModifier<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .strandAnimation(StrandMotion.countUp, value: value)
    }
}

public extension View {
    /// Marca un `Text` (u otra vista con contenido numérico) como un numeral VIVO: cuenta entre
    /// valores en vez de saltar, con ancho estable (`monospacedDigit`) y gate de Reduce Motion.
    /// - Parameter value: el valor que cambia — dispara la transición/animación cuando cambia.
    func numeroVivo<V: Equatable>(value: V) -> some View {
        modifier(NumeroVivoModifier(value: value))
    }
}

#Preview("NumeroVivo") {
    struct Demo: View {
        @State private var n = 82
        var body: some View {
            VStack(spacing: 24) {
                Text("\(n)")
                    .font(InstrumentoType.groteskNumber(46, weight: .bold, relativeTo: .largeTitle))
                    .numeroVivo(value: n)
                Button("Cambiar") { n = n == 82 ? 100 : 82 }
            }
            .padding()
        }
    }
    return Demo()
}
