#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - «Plantilla aplicada» — el aviso de éxito que confirma la escritura silenciosa
//
// FER-137: aplicar una plantilla en `CrearPlanScreen` crea rutinas y arma la semana sin pedir
// confirmación — un éxito silencioso necesita su propio eco, o el usuario no sabe si pasó algo. La
// misma disciplina que `SaveErrorToast` (auto-descarte, sin toque), pero abajo y en tinta —
// el prototipo lo dibuja como una píldora oscura flotando sobre el dock, no un banner arriba.
struct PlanAppliedToast: ViewModifier {
    @Environment(\.instrumentoTheme) private var theme
    @Binding var isPresented: Bool
    var seconds: Double = 3

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    Text("Template applied · your week is set, edit it whenever")
                        .font(StrandFont.caption).fontWeight(.medium)
                        .foregroundStyle(theme.paper)
                        .padding(.horizontal, LiquidSpace.s300).padding(.vertical, LiquidSpace.s200)
                        .background(theme.ink, in: Capsule())
                        .padding(.bottom, CenitMetrics.sectionGap)
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
