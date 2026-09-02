import SwiftUI

// MARK: - Liquid Glass · Selector de rango (épico hoja de resumen, F1b)
//
// El selector de periodo del explorador («S M 3M 6M 1A TODO»). Gramática del nuevo Hoy:
// segmentos de texto (activo en tinta plena, sin caja negra) y bajo el activo un TICK de
// índice del tono que se DESLIZA con `matchedGeometryEffect` + `LiquidMotion.selector`
// (~0.18 s glass-spring). Bajo Reduce Motion o motion congelado el tick salta sin animación.
//
// Las opciones llegan YA localizadas (contrato D3); el app mapea el índice a su
// `ExploreRange`. a11y: botones con trait `isSelected` (rúbrica «adjustable o botones»).
// Track visual ~28 pt (`LiquidChart.selectorAlto`); blanco táctil ≥44 pt (HIG).

public struct LiquidRangeSelector: View {
    private let opciones: [String]
    @Binding private var seleccion: Int
    /// Tono de la métrica: rellena el tick de índice bajo el segmento activo.
    private let tono: Color

    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// Ancho del tick de índice (~16 pt).
    private static let tickAncho: CGFloat = 16
    /// Alto del tick de índice (~2.5 pt).
    private static let tickAlto: CGFloat = 2.5
    /// Radio del tick (2).
    private static let tickRadio: CGFloat = 2
    /// Id de `matchedGeometryEffect` del tick (un solo tick vive en el segmento activo).
    private static let tickID = "indice"

    public init(opciones: [String], seleccion: Binding<Int>,
                tono: Color = LiquidColor.rosa) {
        self.opciones = opciones
        self._seleccion = seleccion
        self.tono = tono
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(opciones.indices, id: \.self) { i in
                segmento(i)
            }
        }
    }

    // MARK: - Segmento

    private func segmento(_ i: Int) -> some View {
        let activo = i == seleccion
        return Button {
            seleccionar(i)
        } label: {
            labelSegmento(texto: opciones[i], activo: activo)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: opciones[i]))
        .accessibilityAddTraits(activo ? [.isButton, .isSelected] : .isButton)
    }

    private func seleccionar(_ i: Int) {
        guard seleccion != i else { return }
        if reduceMotion || motionDisabled {
            seleccion = i
        } else {
            withAnimation(LiquidMotion.selector) { seleccion = i }
        }
    }

    private func labelSegmento(texto: String, activo: Bool) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: texto)
                // 13/600 (mock `.rango {13px/600}`), no `microEstado` (10.5): el selector
                // se leía enano frente a la escalera (auditoría 2026-08-03).
                .font(LiquidType.filaRango)
                .foregroundStyle(activo ? LiquidColor.tinta900 : LiquidColor.tinta500)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            tickIndice(activo: activo)
        }
        .frame(maxWidth: .infinity)
        .frame(height: LiquidChart.selectorAlto)
        // E4 · Blanco táctil HIG (44 pt) SIN tocar el alto visual: el track se dibuja a
        // `selectorAlto` (28) y queda centrado en la banda de 44. El 44 va crudo, igual
        // que en `LiquidVerMas`: es el mínimo de Apple, no un valor de nuestro sistema.
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func tickIndice(activo: Bool) -> some View {
        // Reserva la canaleta del tick en todos los segmentos para que el layout no
        // salte al cambiar de activo; el relleno solo vive en el activo y se desliza.
        ZStack {
            Color.clear.frame(height: Self.tickAlto)
            if activo {
                RoundedRectangle(cornerRadius: Self.tickRadio, style: .continuous)
                    .fill(tono)
                    .frame(width: Self.tickAncho, height: Self.tickAlto)
                    .matchedGeometryEffect(id: Self.tickID, in: ns)
            }
        }
    }
}

#if DEBUG
#Preview("Liquid · RangeSelector") {
    struct Demo: View {
        @State private var a = 0
        @State private var b = 4
        var body: some View {
            VStack(spacing: LiquidSpace.s400) {
                LiquidRangeSelector(opciones: ["S", "M", "3M", "6M", "1A", "TODO"],
                                    seleccion: $a, tono: LiquidColor.rosa)
                LiquidRangeSelector(opciones: ["S", "M", "3M", "6M", "1A", "TODO"],
                                    seleccion: $b, tono: LiquidColor.cian)
                    .environment(\.liquidMotionDisabled, true)
            }
            .padding(LiquidSpace.s550)
            .background(LiquidSheetFondo())
        }
    }
    return Demo()
}
#endif
