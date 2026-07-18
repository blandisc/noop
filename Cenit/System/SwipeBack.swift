import SwiftUI
import UIKit

/// Devuelve el gesto de «deslizar desde el borde para volver» a las pantallas que ocultan la barra
/// de navegación (FER-988).
///
/// Cuando una pantalla hace `.toolbar(.hidden, for: .navigationBar)`, UIKit desactiva el
/// `interactivePopGestureRecognizer` — el botón de atrás desaparece y el gesto se va con él. Es una
/// expectativa tan básica de iOS que su ausencia se siente como que la app está trabada.
///
/// El arreglo: adueñarse del delegate del gesto y decidir nosotros cuándo puede empezar.
/// `gestureRecognizerShouldBegin` consulta `shouldPop`, así que una pantalla con trabajo sin
/// guardar puede vetar el pop y correr en su lugar su propia salida — la misma que corre el botón.
/// Sin eso, deslizar sacaría la pantalla de la pila sin pasar por el autosave y el trabajo se
/// perdería en silencio.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    /// `true` = el gesto puede hacer pop normal. `false` = lo vetamos; devolver `false` desde aquí
    /// es responsabilidad de la pantalla, que debe ejecutar su propia salida.
    let shouldPop: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(shouldPop: shouldPop) }

    func makeUIViewController(context: Context) -> UIViewController {
        Probe(coordinator: context.coordinator)
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        // La pantalla puede volverse «sucia» después de aparecer; el coordinator siempre debe
        // consultar el closure más reciente, no el de la primera evaluación de `body`.
        context.coordinator.shouldPop = shouldPop
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var shouldPop: () -> Bool
        weak var navigationController: UINavigationController?
        private weak var previousDelegate: UIGestureRecognizerDelegate?
        private var installed = false

        init(shouldPop: @escaping () -> Bool) { self.shouldPop = shouldPop }

        func install(on nav: UINavigationController) {
            guard !installed, let gesture = nav.interactivePopGestureRecognizer else { return }
            navigationController = nav
            previousDelegate = gesture.delegate
            gesture.delegate = self
            gesture.isEnabled = true
            installed = true
        }

        /// Devolver el gesto como estaba: otras pantallas de la pila tienen sus propias reglas y no
        /// deben heredar las nuestras.
        func uninstall() {
            guard installed, let gesture = navigationController?.interactivePopGestureRecognizer else { return }
            gesture.delegate = previousDelegate
            installed = false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Sin nada debajo, dejar empezar el gesto deja la pila en un estado roto del que UIKit
            // no se recupera (la pantalla raíz se queda a medio arrastrar).
            guard let nav = navigationController, nav.viewControllers.count > 1 else { return false }
            return shouldPop()
        }
    }

    /// Un controlador vacío cuyo único trabajo es encontrar el `UINavigationController` que SwiftUI
    /// tiene arriba — no hay API pública para pedirlo desde una vista.
    private final class Probe: UIViewController {
        private let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if let nav = parent?.navigationController { coordinator.install(on: nav) }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if let nav = navigationController { coordinator.install(on: nav) }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            coordinator.uninstall()
        }
    }
}

extension View {
    /// Mantiene vivo el gesto de volver aunque la pantalla oculte la barra de navegación.
    ///
    /// - Parameter shouldPop: se consulta al empezar el gesto. Devuelve `false` para vetarlo cuando
    ///   deslizar perdería trabajo — y corre ahí la misma salida que corre tu botón de atrás.
    func keepsSwipeBack(shouldPop: @escaping () -> Bool = { true }) -> some View {
        background(SwipeBackEnabler(shouldPop: shouldPop).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}
