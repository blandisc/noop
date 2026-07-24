import SwiftUI

// MARK: - Liquid Glass · Selector de rango (épico hoja de resumen, F3b — invariante I3)
//
// El selector de periodo del explorador («S M 3M 6M 1A TODO»). I3 del dueño: RECTANGULAR
// con esquinas suaves (`LiquidChart.selectorRadio` = r/control 12), JAMÁS cápsula. El
// thumb de tinta/900 persigue la opción activa con `matchedGeometryEffect` y la receta
// `LiquidMotion.selector`; bajo Reduce Motion o motion congelado salta sin animación.
//
// Las opciones llegan YA localizadas (contrato D3); el app mapea el índice a su
// `ExploreRange`. a11y: botones con trait `isSelected` (rúbrica «adjustable o botones»).

public struct LiquidRangeSelector: View {
    private let opciones: [String]
    @Binding private var seleccion: Int

    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    public init(opciones: [String], seleccion: Binding<Int>) {
        self.opciones = opciones
        self._seleccion = seleccion
    }

    public var body: some View {
        HStack(spacing: LiquidSpace.s050) {
            ForEach(opciones.indices, id: \.self) { i in
                segmento(i)
            }
        }
    }

    private func segmento(_ i: Int) -> some View {
        let activo = i == seleccion
        return Button {
            guard seleccion != i else { return }
            if reduceMotion || motionDisabled {
                seleccion = i
            } else {
                withAnimation(LiquidMotion.selector) { seleccion = i }
            }
        } label: {
            Text(verbatim: opciones[i])
                .font(LiquidType.microEstado)
                .foregroundStyle(activo ? LiquidColor.papelAlto : LiquidColor.tinta700)
                .frame(maxWidth: .infinity)
                .frame(height: LiquidChart.selectorAlto)
                .background {
                    if activo {
                        // NUNCA Capsule: rectangular r/control (I3).
                        RoundedRectangle(cornerRadius: LiquidChart.selectorRadio, style: .continuous)
                            .fill(LiquidColor.tinta900)
                            .matchedGeometryEffect(id: "thumb", in: ns)
                    }
                }
                // E4 · Blanco táctil HIG (44 pt) SIN tocar el alto visual: el track y su
                // thumb se siguen dibujando a `selectorAlto` (28) y quedan centrados en la
                // banda de 44. El 44 va crudo, igual que en `LiquidVerMas`: es el mínimo
                // de Apple, no un valor de nuestro sistema.
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: opciones[i]))
        .accessibilityAddTraits(activo ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
#Preview("Liquid · RangeSelector") {
    struct Demo: View {
        @State private var a = 0
        @State private var b = 4
        var body: some View {
            VStack(spacing: LiquidSpace.s400) {
                LiquidRangeSelector(opciones: ["S", "M", "3M", "6M", "1A", "TODO"], seleccion: $a)
                LiquidRangeSelector(opciones: ["S", "M", "3M", "6M", "1A", "TODO"], seleccion: $b)
                    .environment(\.liquidMotionDisabled, true)
            }
            .padding(LiquidSpace.s550)
            .background(LiquidSheetFondo())
        }
    }
    return Demo()
}
#endif
