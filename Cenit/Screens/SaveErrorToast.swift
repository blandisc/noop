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
struct SaveErrorToast: ViewModifier {
    @Binding var isPresented: Bool
    /// Texto del banner. `nil` (el default, para los 10+ call sites que no lo pasan) muestra el
    /// genérico «Couldn't save. Try again.» — pásalo ya resuelto (`String(localized:)`) cuando la
    /// pantalla necesita nombrar qué falló específicamente (FER-199: `WorkoutEditSheet` conserva
    /// su copy original, «Couldn't save the workout. Try again.», al absorber su banner a mano en
    /// este componente).
    var message: String? = nil
    /// Segundos antes de irse solo. El fallo de guardado NO es terminal (el trabajo sigue en pantalla),
    /// así que el aviso no debe requerir un toque para desaparecer.
    var seconds: Double = 4

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    // titulo vacío: una sola línea de cuerpo (paridad con el banner plano previo);
                    // `lineas: []` dejaría EmptyView dentro de LiquidPatternBlock.
                    LiquidAviso(
                        titulo: "",
                        cuerpo: message ?? String(localized: "Couldn't save. Try again."),
                        tono: LiquidColor.negativo
                    )
                    .padding(.horizontal, LiquidSpace.s400)
                    .transition(LiquidMotion.fallingFadeTransition)
                    .task {
                        try? await Task.sleep(for: .seconds(seconds))
                        isPresented = false
                    }
                }
            }
            .animation(LiquidMotion.fundido, value: isPresented)
    }
}

extension View {
    /// Banner «No se pudo guardar» que se descarta solo. Ver `SaveErrorToast`.
    func saveErrorToast(isPresented: Binding<Bool>, message: String? = nil) -> some View {
        modifier(SaveErrorToast(isPresented: isPresented, message: message))
    }
}
#endif
