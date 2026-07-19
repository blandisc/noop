#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - «No se pudo guardar» — el aviso que se va solo
//
// FER-969 le puso un banner honesto al fallo de escritura en vez del éxito silencioso, y el patrón se
// copió VERBATIM en tres pantallas: editar rutina, la sesión activa y el hub Entrenar. Mismas 13 líneas,
// mismo token exento, mismo temporizador de 4 s. Ahora es un modificador y las tres lo llaman.
// (2026-07-19)
//
// Se queda en la capa de app y no en StrandDesign a propósito: el «bar: critical» sobre `patternBlock`
// ya es un componente del sistema (`patternBlock`), y lo único que agrega esto es la política de
// auto-descarte — que es comportamiento de producto, no vocabulario visual.
struct SaveErrorToast: ViewModifier {
    @Environment(\.instrumentoTheme) private var theme
    @Binding var isPresented: Bool
    /// Segundos antes de irse solo. El fallo de guardado NO es terminal (el trabajo sigue en pantalla),
    /// así que el aviso no debe requerir un toque para desaparecer.
    var seconds: Double = 4

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    Text("Couldn't save. Try again.")
                        .font(.system(size: 13))   // token-exempt: cuerpo de banner (13pt, igual que el mensaje de ConfirmCard)
                        .foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .patternBlock(theme, bar: theme.critical)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(seconds))
                            isPresented = false
                        }
                }
            }
            .animation(StrandMotion.fade, value: isPresented)
    }
}

extension View {
    /// Banner «No se pudo guardar» que se descarta solo. Ver `SaveErrorToast`.
    func saveErrorToast(isPresented: Binding<Bool>) -> some View {
        modifier(SaveErrorToast(isPresented: isPresented))
    }
}
#endif
