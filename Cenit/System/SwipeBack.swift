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

/// Le da a una pantalla MODAL el gesto de salir desde el borde izquierdo (FER-998).
///
/// Un `fullScreenCover` y un `.sheet` no tienen gesto de borde: no están empujados sobre nada, así
/// que no hay pila de la cual hacer pop y `keepsSwipeBack` no aplica. Pero el dedo del usuario no
/// sabe eso — arrastra desde el borde esperando salir. Esto se lo da.
///
/// Va sobre un `UIScreenEdgePanGestureRecognizer` y no sobre un `DragGesture` de SwiftUI a
/// propósito: el reconocedor de UIKit solo despierta en el borde real de la pantalla y convive con
/// los scrolls y arrastres que ya viven dentro (reordenar ejercicios en la sesión), en vez de
/// robarles el toque con una franja invisible encima.
/// Es un `UIViewControllerRepresentable` (igual que `SwipeBackEnabler`) y no un
/// `UIViewRepresentable`: UIKit nos entrega el controlador que nos contiene en vez de tener que
/// adivinarlo caminando la cadena de responders, que puede no estar completa todavía cuando la
/// vista entra en la ventana y dejaría el gesto mudo sin decirlo.
struct EdgeSwipeToExit: UIViewControllerRepresentable {
    /// La MISMA salida que corre el botón — nunca un `dismiss` crudo, o el gesto se saltaría la
    /// confirmación de descartar y el trabajo se perdería.
    let exit: () -> Void

    /// Cuánto hay que arrastrar para que cuente. Un roce en el borde no debe sacarte de una sesión.
    private static let threshold: CGFloat = 70
    /// Un lanzallamas horizontal cuenta aunque recorra poco — así se siente el pop nativo.
    private static let flickVelocity: CGFloat = 800

    func makeCoordinator() -> Coordinator { Coordinator(exit: exit) }

    func makeUIViewController(context: Context) -> UIViewController {
        Probe(coordinator: context.coordinator)
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.exit = exit
    }

    /// Sin esto el reconocedor sobrevive a la pantalla: se cuelga de una vista que no es nuestra y
    /// que SwiftUI puede reutilizar entre presentaciones, dejando un gesto huérfano que dispara la
    /// salida de una presentación anterior.
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var exit: () -> Void
        private weak var host: UIView?
        private var pan: UIScreenEdgePanGestureRecognizer?

        init(exit: @escaping () -> Void) { self.exit = exit }

        func install(on host: UIView) {
            guard pan == nil else { return }
            let recognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handle(_:)))
            recognizer.edges = .left
            recognizer.delegate = self
            host.addGestureRecognizer(recognizer)
            self.host = host
            self.pan = recognizer
        }

        func uninstall() {
            guard let pan else { return }
            host?.removeGestureRecognizer(pan)
            self.pan = nil
            self.host = nil
        }

        @objc private func handle(_ pan: UIScreenEdgePanGestureRecognizer) {
            guard pan.state == .ended else { return }
            let translation = pan.translation(in: pan.view)
            let velocity = pan.velocity(in: pan.view)
            // Exigir que el gesto sea DOMINANTEMENTE horizontal: en la sesión conviven arrastres
            // verticales (reordenar ejercicios, el asa «≡») y un flick diagonal que arranque cerca
            // del margen alcanzaría el umbral de velocidad, minimizando la sesión a media
            // reordenación.
            guard abs(translation.x) > abs(translation.y) else { return }
            guard translation.x > EdgeSwipeToExit.threshold
                    || velocity.x > EdgeSwipeToExit.flickVelocity else { return }
            exit()
        }

        /// Convivir, no competir: el reconocedor de borde solo despierta en el margen, así que
        /// dejarlo correr junto a los scrolls internos evita que se cancelen entre sí. Quien decide
        /// si la intención era horizontal es `handle`, no esta bandera.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    /// Un controlador vacío: su único trabajo es darnos la vista de la pantalla a la que colgarle el
    /// reconocedor — la de ESTA modal, nunca la raíz de la app (ahí el gesto viviría en toda ella).
    private final class Probe: UIViewController {
        private let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if let host = parent?.view { coordinator.install(on: host) }
        }

        /// Segundo intento: si al montarnos el padre todavía no existía, aquí ya existe. Sin este
        /// reintento el modo de falla es «el gesto simplemente no está», sin error ni aviso.
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if let host = parent?.view { coordinator.install(on: host) }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            coordinator.uninstall()
        }
    }
}

extension View {
    /// Le da a una pantalla modal el gesto de salir desde el borde izquierdo.
    ///
    /// - Parameter exit: la misma salida que corre el botón (minimizar, cerrar, confirmar descarte).
    func edgeSwipeToExit(_ exit: @escaping () -> Void) -> some View {
        background(EdgeSwipeToExit(exit: exit).frame(width: 0, height: 0).accessibilityHidden(true))
    }

    /// Mantiene vivo el gesto de volver aunque la pantalla oculte la barra de navegación.
    ///
    /// - Parameter shouldPop: se consulta al empezar el gesto. Devuelve `false` para vetarlo cuando
    ///   deslizar perdería trabajo — y corre ahí la misma salida que corre tu botón de atrás.
    func keepsSwipeBack(shouldPop: @escaping () -> Bool = { true }) -> some View {
        background(SwipeBackEnabler(shouldPop: shouldPop).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}
