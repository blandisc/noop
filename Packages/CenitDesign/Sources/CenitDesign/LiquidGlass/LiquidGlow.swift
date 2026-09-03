import SwiftUI

// MARK: - LiquidGlow (FER-340)
//
// Halo/glow geométrico del sistema. El brillo vive DENTRO de la pieza — las pantallas
// no pintan `.blur` + fill ad-hoc para un respiro o un orbe. Dos formas:
//   · `contorno` — stroke desenfocado (+ fill opcional): aviso que late, punto con aura.
//   · `disco` — radial suave desenfocado: halo de orbe de respiración.

/// Glow geométrico Liquid. Pantallas pasan color/fase; el blur queda encapsulado aquí.
public struct LiquidGlow<S: InsettableShape>: View {
    private let shape: S
    private let stroke: Color
    private let fill: Color?
    private let lineWidth: CGFloat
    private let blur: CGFloat

    /// Contorno que brilla (halo de aviso / filo). `fill` nil = solo el stroke.
    public init(contorno shape: S,
                stroke: Color,
                blur: CGFloat,
                lineWidth: CGFloat = 3,
                fill: Color? = nil) {
        self.shape = shape
        self.stroke = stroke
        self.fill = fill
        self.lineWidth = lineWidth
        self.blur = blur
    }

    public var body: some View {
        ZStack {
            shape
                .strokeBorder(stroke, lineWidth: lineWidth)
                .blur(radius: blur)
            if let fill {
                shape.fill(fill)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Disco radial suave — halo de un orbe (respiración, señal).
public struct LiquidGlowDisco: View {
    private let color: Color
    private let diametro: CGFloat
    private let blur: CGFloat
    private let opacidadCentro: Double

    public init(color: Color,
                diametro: CGFloat,
                blur: CGFloat,
                opacidadCentro: Double = 0.18) {
        self.color = color
        self.diametro = diametro
        self.blur = blur
        self.opacidadCentro = opacidadCentro
    }

    public var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacidadCentro), color.opacity(0)],
                    center: .center,
                    startRadius: diametro * 0.15,
                    endRadius: diametro * 0.52
                )
            )
            .frame(width: diametro, height: diametro)
            .blur(radius: blur)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("LiquidGlow · contorno") {
    ZStack {
        LiquidColor.fondoGradient
        RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
            .fill(LiquidColor.papelTarjeta)
            .frame(width: 280, height: 64)
            .overlay {
                LiquidGlow(
                    contorno: RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous),
                    stroke: LiquidColor.rojoClaro.opacity(0.45),
                    blur: LiquidSpace.s200,
                    fill: LiquidColor.rojoClaro.opacity(0.08))
            }
    }
}

#Preview("LiquidGlow · disco") {
    ZStack {
        LiquidColor.fondoGradient
        LiquidGlowDisco(color: LiquidColor.azul, diametro: 220, blur: LiquidSpace.s550)
        Circle()
            .fill(LiquidColor.azul.opacity(0.28))
            .frame(width: 120, height: 120)
    }
}
#endif
