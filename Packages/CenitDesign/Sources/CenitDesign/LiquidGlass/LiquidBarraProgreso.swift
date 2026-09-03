import SwiftUI

// MARK: - Liquid Glass · Barra de progreso (pista + relleno) (FER-338)
//
// La cápsula de dato más simple: una pista y un relleno proporcional a `fraccion` (0…1).
// Mata la clase de `Capsule().fill` a mano que el gate `no-capsule-a-mano` caza en pantallas —
// dentro del paquete el `Capsule()` es legítimo.
//
// POR QUÉ NO ES `LiquidBarraMarca`: aquella es una FILA (rótulo · dato · delta + tick de
// promedio tipico). POR QUÉ NO ES `LiquidBarraConteo` / `LiquidStageBar`: aquellas cargan
// glifo, escala compartida o segmentos de sueño. Aquí solo hay fracción + tono.
//
// Parámetros opcionales documentados:
//   · `marca` — tick de tinta en 0…1 (comparar «esta sesión» vs «la pasada»).
//   · `contorno` — `strokeBorder` encima (indicadores de ronda vacíos).
//   · `anchoMinimoRelleno` — piso en pt cuando `fraccion > 0` (barras que no deben desaparecer).

public struct LiquidBarraProgreso: View {

    private let fraccion: Double
    private let tono: Color
    private let pista: Color
    private let altura: CGFloat
    private let animada: Bool
    private let marca: Double?
    private let contorno: Color?
    private let anchoMinimoRelleno: CGFloat

    /// Grosor del tick de marca (paridad con `LiquidBarraMarca`).
    private static let anchoMarca: CGFloat = 2
    /// Alto del tick: sobresale 3 pt arriba y abajo de la cápsula de 8 pt típica.
    private static let altoMarcaExtra: CGFloat = 6

    /// - Parameters:
    ///   - fraccion: 0…1; fuera de rango se clampea. NaN/infinito → 0.
    ///   - tono: color del relleno.
    ///   - pista: color del riel.
    ///   - altura: alto de la cápsula (`LiquidSpace.s150` = 6 pt por defecto).
    ///   - animada: si el relleno anima al cambiar la fracción (respeta Reduce Motion vía
    ///     `strandAnimation`).
    ///   - marca: posición 0…1 del tick de referencia; `nil` = sin tick.
    ///   - contorno: color de `strokeBorder` a 1 pt; `nil` = sin contorno.
    ///   - anchoMinimoRelleno: piso del relleno en pt cuando hay dato (`fraccion > 0`).
    public init(fraccion: Double,
                tono: Color = LiquidColor.verdePrimario,
                pista: Color = LiquidColor.tinta10,
                altura: CGFloat = LiquidSpace.s150,
                animada: Bool = true,
                marca: Double? = nil,
                contorno: Color? = nil,
                anchoMinimoRelleno: CGFloat = 0) {
        self.fraccion = fraccion
        self.tono = tono
        self.pista = pista
        self.altura = altura
        self.animada = animada
        self.marca = marca
        self.contorno = contorno
        self.anchoMinimoRelleno = anchoMinimoRelleno
    }

    /// Fracción en 0…1; mata NaN/infinito para no romper el layout.
    public static func enRango(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(1, max(0, v))
    }

    public var body: some View {
        let f = Self.enRango(fraccion)
        GeometryReader { geo in
            let w = geo.size.width
            let relleno: CGFloat = {
                guard f > 0 else { return 0 }
                let crudo = CGFloat(f) * w
                guard anchoMinimoRelleno > 0 else { return crudo }
                return min(w, max(anchoMinimoRelleno, crudo))
            }()
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(pista)
                Capsule(style: .continuous)
                    .fill(tono)
                    .frame(width: relleno)
                    .strandAnimation(animada ? .easeInOut(duration: 0.35) : nil, value: f)
                if let marca {
                    let pos = Self.enRango(marca)
                    if pos > 0 {
                        Rectangle()
                            .fill(LiquidColor.tinta900)
                            .frame(width: Self.anchoMarca,
                                   height: altura + Self.altoMarcaExtra)
                            .offset(x: min(w - Self.anchoMarca,
                                           max(0, w * CGFloat(pos) - Self.anchoMarca / 2)))
                    }
                }
                if let contorno {
                    Capsule(style: .continuous)
                        .strokeBorder(contorno, lineWidth: 1)
                }
            }
        }
        .frame(height: altura)
        .accessibilityValue(Text(verbatim: "\(Int((Self.enRango(fraccion) * 100).rounded()))%"))
    }
}

#if DEBUG
#Preview("LiquidBarraProgreso") {
    VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        LiquidBarraProgreso(fraccion: 0.25)
        LiquidBarraProgreso(fraccion: 0.60, tono: LiquidColor.cian)
        LiquidBarraProgreso(fraccion: 0.90, tono: LiquidColor.ambar, marca: 0.55)
    }
    .padding(LiquidSpace.s600)
    .frame(width: 280)
    .background(LiquidColor.papelAlto)
}
#endif
