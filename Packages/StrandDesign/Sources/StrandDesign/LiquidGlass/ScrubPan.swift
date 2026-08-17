import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Scrub horizontal que NO se roba el scroll (FER-73 · H-S)
//
// El scrub de la Matriz vive DENTRO del scroll de Hoy. Con un `DragGesture` de SwiftUI —aunque
// ignore los arrastres verticales en su `onChanged`— el reconocimiento ya ocurrió: en iOS 18+ el
// pan del ScrollView cede, y un scroll que ARRANCA sobre una gráfica no mueve la página. Cazado
// en el simulador con el mismo gesto sintético: desde el título de «Skin temp» scrollea, desde su
// gráfica no.
//
// La regla correcta no es «ignora lo vertical al procesar», es «no empieces si es vertical»: eso
// en UIKit es `gestureRecognizerShouldBegin`. `UIGestureRecognizerRepresentable` (iOS 18) permite
// decirlo sin envolver la vista en un `UIViewRepresentable`. En iOS 17 se conserva el
// `DragGesture` de antes (el comportamiento que ya se enviaba), y en macOS/watchOS también.

public extension View {
    /// Arrastre HORIZONTAL para leer una serie, con el scroll vertical intacto.
    ///
    /// - Parameters:
    ///   - enabled: apaga el gesto sin cambiar el árbol de vistas.
    ///   - onChange: posición del dedo en el espacio LOCAL de esta vista.
    ///   - onEnd: el dedo se levantó (o el gesto se canceló).
    @ViewBuilder
    func liquidScrubPan(enabled: Bool = true,
                        onChange: @escaping (CGPoint) -> Void,
                        onEnd: @escaping () -> Void) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            self.gesture(ScrubPanRepresentable(enabled: enabled, onChange: onChange, onEnd: onEnd))
        } else {
            self.simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .local)
                    .onChanged { g in
                        guard enabled,
                              abs(g.translation.width) >= abs(g.translation.height) else { return }
                        onChange(g.location)
                    }
                    .onEnded { _ in onEnd() }
            )
        }
        #else
        self.simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .local)
                .onChanged { g in
                    guard enabled,
                          abs(g.translation.width) >= abs(g.translation.height) else { return }
                    onChange(g.location)
                }
                .onEnded { _ in onEnd() }
        )
        #endif
    }
}

#if os(iOS)
@available(iOS 18.0, *)
private struct ScrubPanRepresentable: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let onChange: (CGPoint) -> Void
    let onEnd: () -> Void

    final class Coordinador: NSObject, UIGestureRecognizerDelegate {
        var habilitado: Bool = true

        /// El filtro que hace todo el trabajo: si el dedo va MÁS vertical que horizontal, este
        /// reconocedor no empieza y el pan del scroll se queda con el gesto.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard habilitado, let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }

        /// Convivir, no competir: el scroll conserva su reconocedor (no puede desplazarse en
        /// horizontal, así que un scrub no lo mueve).
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinador {
        let c = Coordinador()
        c.habilitado = enabled
        return c
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.habilitado = enabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(context.converter.localLocation)
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }
}
#endif
