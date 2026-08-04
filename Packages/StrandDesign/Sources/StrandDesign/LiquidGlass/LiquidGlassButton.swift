import SwiftUI

// MARK: - Liquid Glass · GlassButton (handoff §5.4)
//
// Botón pill, min-height 44 (hit target), padding H 22, texto botón (SG 600 14). Tres
// variantes: primary (gradiente verde), glass (vidrio/pastilla) y quiet (transparente).
// Press: la receta del sistema (scale 0.97 · dur/instant · glass-out).

public struct LiquidGlassButton: View {
    public enum Variant: Sendable {
        case primary, glass, quiet
    }

    private let label: String
    private let variant: Variant
    private let expands: Bool
    private let action: () -> Void

    /// - Parameter expands: `true` estira el botón al ancho disponible (CTA de pantalla);
    ///   `false` lo deja abrazar su contenido (acciones inline, quiet).
    public init(_ label: String, variant: Variant = .primary, expands: Bool = false,
                action: @escaping () -> Void) {
        self.label = label
        self.variant = variant
        self.expands = expands
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            core
        }
        .buttonStyle(.liquidPress)
    }

    @ViewBuilder
    private var core: some View {
        let text = Text(label)
            .font(LiquidType.boton).tracking(LiquidType.botonTracking)
            .lineLimit(1)
            .padding(.horizontal, LiquidSpace.s550)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: 44)

        switch variant {
        case .primary:
            text
                .foregroundStyle(LiquidColor.tintaSobreVerde)
                .background {
                    Capsule().fill(LinearGradient(
                        colors: [LiquidColor.verdeBotonAlto, LiquidColor.verdePrimario],
                        startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    // inset 0 1px 1px blanco .35 — la luz entrando por el canto superior.
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.35), location: 0),
                                    .init(color: .white.opacity(0), location: 0.5),
                                ],
                                startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .clipShape(Capsule())
                .liquidShadow([.init(color: LiquidColor.verdePrimario.opacity(0.30), radius: 7, y: 5)])
        case .glass:
            text
                .foregroundStyle(LiquidColor.tinta900)
                .liquidGlass(.pastilla) // token-exempt: boton de pantalla, no de hoja
        case .quiet:
            text
                .foregroundStyle(LiquidColor.verdeProfundo)
        }
    }
}

#if DEBUG
#Preview("Liquid · GlassButton") {
    VStack(spacing: LiquidSpace.s400) {
        LiquidGlassButton("Empezar", variant: .primary, expands: true) {}
        LiquidGlassButton("Ver detalle", variant: .glass) {}
        LiquidGlassButton("Editar semana", variant: .quiet) {}
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
