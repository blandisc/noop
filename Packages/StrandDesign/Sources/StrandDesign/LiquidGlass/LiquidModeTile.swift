import SwiftUI

// MARK: - Liquid Glass · ModeTile (handoff §5.6)
//
// Tile cuadrado de modo de entrenamiento: vidrio/superficie + columna centrada
// [gota 28 (tono al 12 %) + label]. Hover: lift con glow del tono; press: el del sistema.

public struct LiquidModeTile: View {
    private let label: String
    private let icon: LiquidIcon.Glyph
    private let tone: Color
    private let action: (() -> Void)?

    public init(label: String, icon: LiquidIcon.Glyph, tone: Color,
                action: (() -> Void)? = nil) {
        self.label = label
        self.icon = icon
        self.tone = tone
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.liquidPress)
                .liquidLift(tone: tone)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: LiquidSpace.s150) {
            LiquidIconDrop(icon, tone: tone, size: 28, iconSize: 15, fillAlpha: 0.12)
            Text(label)
                .font(LiquidType.label).tracking(0.6) // spec §5.6: 8.5/600 con +0.6, sin caja alta
                .foregroundStyle(LiquidColor.tinta900)
                .lineLimit(1)
        }
        .padding(.top, 10)
        .padding(.horizontal, LiquidSpace.s100)
        .padding(.bottom, LiquidSpace.s200)
        .frame(maxWidth: .infinity, minHeight: 64)
        .liquidGlass(.superficie) // token-exempt: tile de Hoy, no vive dentro de una hoja
    }
}

#if DEBUG
#Preview("Liquid · ModeTile") {
    HStack(spacing: LiquidSpace.s200) {
        LiquidModeTile(label: "Rápido", icon: .rayo, tone: LiquidColor.ambar, action: {})
        LiquidModeTile(label: "En vivo", icon: .envivo, tone: LiquidColor.rosa, action: {})
        LiquidModeTile(label: "Intervalo", icon: .intervalo, tone: LiquidColor.indigo, action: {})
        LiquidModeTile(label: "Movilidad", icon: .movilidad, tone: LiquidColor.cian, action: {})
        LiquidModeTile(label: "Respira", icon: .respira, tone: LiquidColor.verdePrimario, action: {})
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
