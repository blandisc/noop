import SwiftUI

// MARK: - EntrenarFilaEsfuerzo — selector de esfuerzo en fila de pills (FER-197 · Ola 1 · E3)
//
// El patrón de RPE de la hoja viva (`RPESheet.scale`, Hevy-style): una escala que cabe en una
// sola fila de celdas seleccionables por toque (`LazyVGrid`). Genérico a propósito — aunque hoy
// solo alimenta RPE (6 · 7 · 8 · 9 · 9,5 · 10), el contrato no conoce la escala: recibe los
// rótulos YA formateados y devuelve el ÍNDICE tocado. Superficie OPACA (papel de tarjeta +
// hairline), nunca vidrio — es una fila DENTRO de la hoja de vidrio (ADN §11.1).
//
// E3 (FER-330): el prellenado de la pregunta de sesión («sugerido») no es una respuesta — la
// media por serie sesga hacia arriba (Sweet 2004). Se dibuja punteado y SIN el relleno de
// selección; tocar confirma (`.answered`) o cambia.

public struct EntrenarFilaEsfuerzo: View {
    private let opciones: [String]
    private let seleccion: Int?
    /// Índice marcado como sugerencia (borde punteado). Ignorado si coincide con `seleccion`.
    private let sugerida: Int?
    private let tono: LiquidTono
    private let onSelect: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - opciones: rótulos ya formateados, en orden de dibujo («6», «7», «8», «9», «9,5», «10»).
    ///   - seleccion: el índice elegido; `nil` = ninguna celda marcada como respuesta.
    ///   - sugerida: índice del valor sugerido (punteado); `nil` = sin sugerencia.
    ///   - tono: rellena la celda seleccionada (ámbar de esfuerzo por default).
    public init(opciones: [String], seleccion: Int?, sugerida: Int? = nil,
                tono: LiquidTono = .ambar,
                onSelect: @escaping (Int) -> Void) {
        self.opciones = opciones
        self.seleccion = seleccion
        self.sugerida = sugerida
        self.tono = tono
        self.onSelect = onSelect
    }

    public var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: LiquidSpace.s200),
                                  count: columnCount),
                  spacing: LiquidSpace.s200) {
            ForEach(Array(opciones.enumerated()), id: \.offset) { index, texto in
                celda(texto,
                      seleccionada: index == seleccion,
                      sugerida: index == sugerida && index != seleccion) {
                    onSelect(index)
                }
            }
        }
    }

    /// Desde AX1 la fila de 6 pasa a 2 renglones de 3 (A9 / a11y del recibo).
    private var columnCount: Int {
        if dynamicTypeSize >= .accessibility1 {
            return min(3, max(1, opciones.count))
        }
        return max(1, opciones.count)
    }

    private func celda(_ texto: String, seleccionada: Bool, sugerida: Bool,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(texto)
                .font(InstrumentoType.groteskNumber(17, weight: seleccionada ? .bold : .regular))
                .foregroundStyle(seleccionada ? LiquidColor.papelTarjeta : LiquidColor.tinta700)
                .frame(maxWidth: .infinity)
                .frame(minHeight: EntrenarFilaEsfuerzoMetrics.celda)
                .background(fondoCelda(seleccionada: seleccionada, sugerida: sugerida))
                .contentShape(Rectangle())
        }
        .buttonStyle(EntrenarPressStyle())
        .accessibilityAddTraits(seleccionada ? [.isSelected] : [])
    }

    @ViewBuilder
    private func fondoCelda(seleccionada: Bool, sugerida: Bool) -> some View {
        let forma = RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
        if seleccionada {
            forma.fill(tono.base)
        } else if sugerida {
            forma.fill(LiquidColor.papelTarjeta)
                .overlay(forma.strokeBorder(tono.base,
                                            style: StrokeStyle(lineWidth: HomeWidgetMetrics.ringRest,
                                                               dash: HomeWidgetMetrics.ringRestDash)))
        } else {
            forma.fill(LiquidColor.papelTarjeta)
                .overlay(forma.strokeBorder(LiquidColor.tinta10, lineWidth: 1))
        }
    }
}

private enum EntrenarFilaEsfuerzoMetrics {
    /// ≥ 44 pt (A9); 56 hereda el hit target cómodo de la hoja de RPE por serie.
    static let celda: CGFloat = 56
}

#if DEBUG
#Preview("EntrenarFilaEsfuerzo · RPE, 6 celdas") {
    EntrenarFilaEsfuerzo(opciones: ["6", "7", "8", "9", "9,5", "10"], seleccion: 2) { _ in }
        .padding(LiquidSpace.s400)
        .liquidGlass(.superficieSolida)
        .padding(LiquidSpace.s550)
        .entrenarHojaFondo(tono: .ambar)
}

/// Sin selección — la fila abre así antes de tocar una celda.
#Preview("EntrenarFilaEsfuerzo · sin selección") {
    EntrenarFilaEsfuerzo(opciones: ["6", "7", "8", "9", "9,5", "10"], seleccion: nil) { _ in }
        .padding(LiquidSpace.s400)
        .liquidGlass(.superficieSolida)
        .padding(LiquidSpace.s550)
        .entrenarHojaFondo(tono: .ambar)
}

/// Prefill de sesión: celda sugerida punteada, aún no confirmada (E3 · FER-330).
#Preview("EntrenarFilaEsfuerzo · sugerida") {
    EntrenarFilaEsfuerzo(opciones: ["6", "7", "8", "9", "9,5", "10"],
                         seleccion: nil, sugerida: 2) { _ in }
        .padding(LiquidSpace.s400)
        .liquidGlass(.superficieSolida)
        .padding(LiquidSpace.s550)
        .entrenarHojaFondo(tono: .ambar)
}
#endif
