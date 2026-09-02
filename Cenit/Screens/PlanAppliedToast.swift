#if os(iOS)
import SwiftUI
import CenitDesign

// MARK: - «Plantilla aplicada» — el aviso de éxito que confirma la escritura silenciosa
//
// FER-137: aplicar una plantilla en `CrearPlanScreen` crea rutinas y arma la semana sin pedir
// confirmación — un éxito silencioso necesita su propio eco, o el usuario no sabe si pasó algo.
// FER-301: la píldora a mano (tinta + Capsule) cede a `LiquidAviso` del catálogo; sin acción
// de deshacer (no es `UndoToast`). API pública del modifier intacta.

struct PlanAppliedToast: ViewModifier {
    @Binding var isPresented: Bool
    var seconds: Double = 3

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    LiquidAviso(
                        titulo: String(localized: "Template applied · your week is set, edit it whenever"),
                        lineas: [],
                        tono: LiquidColor.positivo
                    )
                    .padding(.horizontal, LiquidSpace.s600)
                    .padding(.bottom, LiquidSpace.s600)
                    .transition(LiquidMotion.risingFadeTransition)
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
    /// Píldora de éxito «Plantilla aplicada» que se descarta sola. Ver `PlanAppliedToast`.
    func planAppliedToast(isPresented: Binding<Bool>) -> some View {
        modifier(PlanAppliedToast(isPresented: isPresented))
    }
}
#endif
