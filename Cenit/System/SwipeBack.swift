#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Deslizar para volver, también con la barra de navegación oculta
//
// Varias pantallas del flujo Entrenar esconden la `navigationBar` para poner su propia cabecera de papel
// (`RoutineEditorScreen`, `RoutineBuilderScreen`). Al hacerlo, UIKit deja huérfano el
// `interactivePopGestureRecognizer` —su delegado por defecto es la barra— y el gesto de arrastrar desde
// el borde izquierdo deja de funcionar: solo se puede volver tocando el botón. En iOS eso se siente como
// que la app está trabada (bug Fer 2026-07-18).
//
// Este modificador vuelve a armar el gesto y le pone un delegado propio que solo lo permite cuando hay
// algo a lo que volver. Se cuelga de una vista vacía de cero puntos, así que no participa del layout.

/// Rearma «deslizar para volver» en la pantalla actual. Úsalo en TODA vista que oculte la barra de
/// navegación; en las que la conservan es inofensivo (el gesto ya funciona).
extension View {
    func keepsSwipeBack() -> some View { background(SwipeBackEnabler().frame(width: 0, height: 0)) }
}

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        // En `updateUIViewController` el controlador aún puede no estar en la jerarquía, y el
        // `navigationController` sería nil. Un salto al siguiente ciclo basta para que ya esté colgado.
        DispatchQueue.main.async {
            guard let nav = vc.navigationController,
                  let gesture = nav.interactivePopGestureRecognizer else { return }
            context.coordinator.nav = nav
            gesture.isEnabled = true
            gesture.delegate = context.coordinator   // el coordinator vive lo que vive la vista
        }
    }

    /// El delegado que hacía falta. Sin él habría que dejar `delegate = nil`, y entonces el gesto también
    /// dispararía en la pantalla RAÍZ de la pila: UIKit intenta desapilar lo que no existe y la navegación
    /// se queda congelada. Aquí solo se permite cuando de verdad hay una pantalla debajo.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var nav: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (nav?.viewControllers.count ?? 0) > 1
        }

        /// Convive con el scroll de la pantalla: sin esto, un `ScrollView` horizontal o un carrusel se
        /// tragarían el arrastre desde el borde y el gesto sería intermitente.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
