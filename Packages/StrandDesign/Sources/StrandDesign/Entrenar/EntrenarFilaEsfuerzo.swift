import SwiftUI

// MARK: - EntrenarFilaEsfuerzo — selector de esfuerzo en fila de pills (FER-197 · Ola 1)
//
// El patrón de RPE de la hoja viva (`RPESheet.scale`, Hevy-style): una escala que cabe en una
// sola fila de celdas seleccionables por toque (`LazyVGrid` de 1 renglón). Genérico a propósito
// — aunque hoy solo alimenta RPE (6 · 7 · 8 · 9 · 9,5 · 10), el contrato no conoce la escala:
// recibe los rótulos YA formateados y devuelve el ÍNDICE tocado. Superficie OPACA (papel de
// tarjeta + hairline), nunca vidrio — es una fila DENTRO de la hoja de vidrio (ADN §11.1).

public struct EntrenarFilaEsfuerzo: View {
    private let opciones: [String]
    private let seleccion: Int?
    private let tono: EntrenarTono
    private let onSelect: (Int) -> Void

    /// - Parameters:
    ///   - opciones: rótulos ya formateados, en orden de dibujo («6», «7», «8», «9», «9,5», «10»).
    ///   - seleccion: el índice elegido; `nil` = ninguna celda marcada.
    ///   - tono: rellena la celda seleccionada (ámbar de esfuerzo por default).
    public init(opciones: [String], seleccion: Int?, tono: EntrenarTono = .ambar,
                onSelect: @escaping (Int) -> Void) {
        self.opciones = opciones
        self.seleccion = seleccion
        self.tono = tono
        self.onSelect = onSelect
    }

    public var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: LiquidSpace.s200),
                                  count: max(1, opciones.count)),
                  spacing: LiquidSpace.s200) {
            ForEach(Array(opciones.enumerated()), id: \.offset) { index, texto in
                celda(texto, seleccionada: index == seleccion) { onSelect(index) }
            }
        }
    }

    private func celda(_ texto: String, seleccionada: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(texto)
                .font(InstrumentoType.groteskNumber(17, weight: seleccionada ? .bold : .regular))
                .foregroundStyle(seleccionada ? LiquidColor.papelTarjeta : LiquidColor.tinta700)
                .frame(maxWidth: .infinity)
                .frame(minHeight: EntrenarFilaEsfuerzoMetrics.celda)
                .background(fondoCelda(seleccionada: seleccionada))
                .contentShape(Rectangle())
        }
        .buttonStyle(EntrenarPressStyle())
        .accessibilityAddTraits(seleccionada ? [.isSelected] : [])
    }

    @ViewBuilder
    private func fondoCelda(seleccionada: Bool) -> some View {
        let forma = RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
        if seleccionada {
            forma.fill(tono.base)
        } else {
            forma.fill(LiquidColor.papelTarjeta)
                .overlay(forma.strokeBorder(LiquidColor.tinta10, lineWidth: 1))
        }
    }
}

private enum EntrenarFilaEsfuerzoMetrics {
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
#endif
