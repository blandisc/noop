#if os(iOS)
import SwiftUI
import CenitDesign

// MARK: - «No se pudo guardar» — el aviso que se va solo
//
// FER-969 le puso un banner honesto al fallo de escritura en vez del éxito silencioso, y el patrón se
// copió VERBATIM en tres pantallas: editar rutina, la sesión activa y el hub Entrenar. Mismas 13 líneas,
// mismo token exento, mismo temporizador de 4 s. Ahora es un modificador y las tres lo llaman.
// (2026-07-19)
//
// FER-305: la piel pasa a `LiquidAviso` (misma API pública del toast). Se queda en la capa de app a
// propósito: lo único que agrega esto es la política de auto-descarte — comportamiento de producto,
// no vocabulario visual.
//
// FER-339: el fallo FINAL de sesión (antes banner local con Retry) también pasa por aquí: `onRetry`
// no nil → sin auto-descarte, CTA en `LiquidAviso`.
struct SaveErrorToast: ViewModifier {
    @Binding var isPresented: Bool
    /// Texto del banner. `nil` (el default, para los 10+ call sites que no lo pasan) muestra el
    /// genérico «Couldn't save. Try again.» — pásalo ya resuelto (`String(localized:)`) cuando la
    /// pantalla necesita nombrar qué falló específicamente (FER-199: `WorkoutEditSheet` conserva
    /// su copy original, «Couldn't save the workout. Try again.», al absorber su banner a mano en
    /// este componente).
    var message: String? = nil
    /// Segunda línea opcional (p. ej. «Your sets are safe on this phone.»).
    var detail: String? = nil
    /// Rótulo del CTA de reintento; requiere `onRetry`.
    var retryTitle: String? = nil
    /// Si no es nil, el aviso es persistente (sin auto-descarte) y la tarjeta lleva CTA.
    var onRetry: (() -> Void)? = nil
    /// Segundos antes de irse solo (solo cuando no hay `onRetry`). El fallo de guardado NO es
    /// terminal (el trabajo sigue en pantalla), así que el aviso no debe requerir un toque para
    /// desaparecer.
    var seconds: Double = 4

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    aviso
                        .padding(.horizontal, LiquidSpace.s400)
                        .transition(LiquidMotion.fallingFadeTransition)
                        .task(id: isPresented) {
                            guard onRetry == nil else { return }
                            try? await Task.sleep(for: .seconds(seconds))
                            isPresented = false
                        }
                }
            }
            .animation(LiquidMotion.fundido, value: isPresented)
    }

    @ViewBuilder
    private var aviso: some View {
        let cuerpo = message ?? String(localized: "Couldn't save. Try again.")
        let lineas: [String] = {
            var out = [cuerpo]
            if let detail, !detail.isEmpty { out.append(detail) }
            return out
        }()
        if let onRetry {
            LiquidAviso(
                titulo: "",
                lineas: lineas,
                tono: LiquidColor.negativo,
                cta: retryTitle ?? String(localized: "Retry"),
                accion: onRetry
            )
        } else {
            LiquidAviso(
                titulo: "",
                lineas: lineas,
                tono: LiquidColor.negativo
            )
        }
    }
}

extension View {
    /// Banner «No se pudo guardar». Con `onRetry` es persistente; sin él, se descarta solo.
    func saveErrorToast(isPresented: Binding<Bool>,
                        message: String? = nil,
                        detail: String? = nil,
                        retryTitle: String? = nil,
                        onRetry: (() -> Void)? = nil) -> some View {
        modifier(SaveErrorToast(isPresented: isPresented,
                                message: message,
                                detail: detail,
                                retryTitle: retryTitle,
                                onRetry: onRetry))
    }
}
#endif
