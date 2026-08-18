#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - «Series distintas» + «Igualar todas» (FER-88)
//
// `RoutineEditorScreen` pliega la receta de un ejercicio en una `RecetaLine` cuando todas sus series
// de trabajo coinciden (`RoutineSetEditing.workSetsAreEqual`) y la abre en renglones automáticos en
// cuanto una difiere. Esta es la pieza que corona esos renglones: el rótulo dice qué pasó, la
// píldora ofrece arreglarlo en un toque. Nace app-level, no en StrandDesign — mismo precedente que
// `SetActionPills`/`AddExerciseNode`: una pieza de una sola pantalla hoy: si otra fase la necesita
// después, se promueve entonces, no antes.

/// El aviso que corona la tabla cuando el detector dice que las series de trabajo YA NO coinciden.
/// El llamador decide cuándo montarla — si las series ya son iguales, simplemente no se dibuja (así
/// «Igualar todas» nunca aparece con nada que igualar).
struct EqualizeSetsPrompt: View {
    @Environment(\.instrumentoTheme) private var theme
    /// La identidad de familia del ejercicio — su texto SIEMPRE lee en el tono de lectura de esa
    /// familia (`EntrenarFamily.reading`), nunca en un gris genérico ni en el hue crudo.
    let family: EntrenarFamily
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: CenitMetrics.space2) {
            Text("Sets differ").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            Spacer(minLength: CenitMetrics.space2)
            Button(action: action) {
                Text("Equalize all")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(family.reading(theme))
                    .padding(.horizontal, CenitMetrics.gap)
                    .frame(height: EntrenarMetrics.secondaryButton)
                    .background(theme.paper, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    // dibujo 36, toque 44 (HIG) — mismo patrón que `RestBand`'s «Skip».
                    .frame(minHeight: EntrenarMetrics.row)
                    .contentShape(Rectangle())
            }
            .buttonStyle(EntrenarPressStyle())
            .disabled(disabled)
            .accessibilityLabel(Text("Equalize all sets to the first set's values"))
        }
    }
}

#if DEBUG
#Preview("EqualizeSetsPrompt · las cuatro familias") {
    let t = InstrumentoTheme.base
    return VStack(spacing: 20) {
        ForEach(EntrenarFamily.allCases, id: \.self) { f in
            EqualizeSetsPrompt(family: f) {}
        }
        EqualizeSetsPrompt(family: .push, disabled: true) {}
    }
    .padding(24)
    .background(t.paper)
    .instrumentoTheme(.base)
}

#Preview("EqualizeSetsPrompt · xxxLarge") {
    EqualizeSetsPrompt(family: .pull) {}
        .padding(24)
        .background(InstrumentoTheme.base.paper)
        .instrumentoTheme(.base)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
#endif
