import SwiftUI

// MARK: - Liquid Glass · Capilar (FER-28 «El Tablero»)
//
// Separador vertical finísimo entre columnas de un módulo de vidrio: 1 pt de tinta/900 al
// 8 %, con las puntas desvanecidas para que la línea no toque los cantos del módulo (el
// vidrio ya tiene su propio borde; un hairline de canto a canto se leía como costura).
// Decorativo: no recibe taps (las columnas vecinas sí).

/// Separador capilar entre datos vecinos: una línea de 1 pt de tinta/900 al 8 %, con las
/// puntas desvanecidas (transparent → 8 % → 8 % → transparent) para que no toque los cantos.
/// Nació vertical entre columnas de «El Tablero» (FER-28); el eje `.horizontal` lo lleva a la
/// pantalla de detalle, donde separa filas a sangre (FER-102) y donde un hairline recto de
/// canto a canto se leía como el filo gris del papel, no como la firma del sistema.
public struct LiquidCapilar: View {
    /// Cómo corre la línea. `.vertical` separa columnas; `.horizontal` separa filas.
    public enum Eje: Sendable { case vertical, horizontal }

    private let eje: Eje

    public init(eje: Eje = .vertical) { self.eje = eje }

    public var body: some View {
        // 4 paradas: transparent en los extremos, 8 % en el tramo central (0.18…0.82).
        // cornerRadius 0.5 redondea lo mínimo el 1 pt para que no se vea un pixel cuadrado.
        RoundedRectangle(cornerRadius: LiquidRadius.hairline)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: LiquidColor.tinta900.opacity(0), location: 0.0),
                        .init(color: LiquidColor.tinta900.opacity(0.08), location: 0.18),
                        .init(color: LiquidColor.tinta900.opacity(0.08), location: 0.82),
                        .init(color: LiquidColor.tinta900.opacity(0), location: 1.0),
                    ],
                    startPoint: eje == .vertical ? .top : .leading,
                    endPoint: eje == .vertical ? .bottom : .trailing
                )
            )
            .frame(width: eje == .vertical ? 1 : nil,
                   height: eje == .horizontal ? 1 : nil)
            .frame(maxWidth: eje == .horizontal ? .infinity : nil,
                   maxHeight: eje == .vertical ? .infinity : nil)
            .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Liquid · Capilar") {
    HStack(spacing: LiquidSpace.s400) {
        Text("42")
            .font(LiquidType.valorL)
            .foregroundStyle(LiquidColor.indigo)
            .frame(maxWidth: .infinity)
        LiquidCapilar()
        Text("7.2")
            .font(LiquidType.valorL)
            .foregroundStyle(LiquidColor.cian)
            .frame(maxWidth: .infinity)
    }
    .frame(height: 48)
    .padding(LiquidSpace.s550)
    .background(LiquidColor.fondoGradient)
}
#endif
