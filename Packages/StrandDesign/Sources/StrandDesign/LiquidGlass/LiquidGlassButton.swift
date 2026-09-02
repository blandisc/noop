import SwiftUI

// MARK: - Liquid Glass · GlassButton (handoff §5.4)
//
// Botón pill, min-height 44 (hit target), padding H 22, texto botón (SG 600 14). Cinco
// variantes: primary (gradiente verde), glass (vidrio/pastilla), solida (papel opaco),
// quiet (transparente) y destructive (cápsula crítica con borde, sin relleno — FER-280 ·
// 1c, clase 5). Press: la receta del sistema (scale 0.97 · dur/instant · glass-out).
//
// **Cuándo sí:** cualquier botón pill de pantalla, incluida la ÚNICA acción destructiva de una
// pantalla (`.destructive`: apagar respaldo, borrar, etc. — la anatomía real de
// `DataSourcesView.turnOffAutoBackupButton`). **Cuándo no:** un control inline chico (usa
// `LiquidGlassRecipe.pastilla` directo).

public struct LiquidGlassButton: View {
    public enum Variant: Sendable {
        case primary, glass, quiet
        /// Cápsula crítica: texto `negativo` + borde `negativo` a 0.35, sin relleno — la MISMA
        /// receta que `DataSourcesView.swift:820-834` construía a mano por falta de esta
        /// variante (FER-280 · 1c, clase 5: «APIs del catálogo incompletas que obligan al fork»).
        case destructive
        /// Pastilla OPACA (papel) — hermana de `.glass` con receta `.pastillaSolida` en vez
        /// de `.pastilla` (FER-289: «Crear ejercicio» sobre hoja El Eje, sin vidrio-sobre-vidrio).
        case solida
    }

    private let label: String
    private let variant: Variant
    private let expands: Bool
    private let minWidth: CGFloat?
    private let systemImage: String?
    private let action: () -> Void

    /// - Parameter expands: `true` estira el botón al ancho disponible (CTA de pantalla);
    ///   `false` lo deja abrazar su contenido (acciones inline, quiet).
    /// - Parameter minWidth: ancho mínimo opcional del label (p. ej. CTA del héroe); `nil` no fija.
    /// - Parameter systemImage: SF Symbol opcional antes del label (`LiquidType.iconSF(15)`,
    ///   gap `s150`) — p. ej. «Imprimir recibo» con `"printer"`.
    public init(_ label: String, variant: Variant = .primary, expands: Bool = false,
                minWidth: CGFloat? = nil, systemImage: String? = nil,
                action: @escaping () -> Void) {
        self.label = label
        self.variant = variant
        self.expands = expands
        self.minWidth = minWidth
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            core
        }
        .buttonStyle(.liquidPress)
    }

    @ViewBuilder
    private var labelContent: some View {
        HStack(spacing: LiquidSpace.s150) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(LiquidType.iconSF(size: 15))
            }
            Text(label)
                .font(LiquidType.boton).tracking(LiquidType.botonTracking)
                .lineLimit(1)
        }
        .padding(.horizontal, LiquidSpace.s550)
        .frame(minWidth: minWidth, maxWidth: expands ? .infinity : nil, minHeight: 44)
    }

    @ViewBuilder
    private var core: some View {
        switch variant {
        case .primary:
            labelContent
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
            labelContent
                .foregroundStyle(LiquidColor.tinta900)
                .liquidGlass(.pastilla) // token-exempt: boton de pantalla, no de hoja
        case .solida:
            labelContent
                .foregroundStyle(LiquidColor.tinta900)
                .liquidGlass(.pastillaSolida)
        case .quiet:
            labelContent
                .foregroundStyle(LiquidColor.verdeProfundo)
        case .destructive:
            labelContent
                .foregroundStyle(LiquidColor.negativo)
                .overlay {
                    Capsule().strokeBorder(LiquidColor.negativo.opacity(0.35), lineWidth: 1)
                }
        }
    }
}

#if DEBUG
#Preview("Liquid · GlassButton") {
    VStack(spacing: LiquidSpace.s400) {
        LiquidGlassButton("Empezar", variant: .primary, expands: true) {}
        LiquidGlassButton("Empezar", variant: .primary, minWidth: 168) {}
        LiquidGlassButton("Ver detalle", variant: .glass) {}
        LiquidGlassButton("Crear ejercicio", variant: .solida) {}
        LiquidGlassButton("Imprimir recibo", variant: .solida, expands: true, systemImage: "printer") {}
        LiquidGlassButton("Editar semana", variant: .quiet) {}
        LiquidGlassButton("Turn off automatic backup", variant: .destructive, expands: true) {}
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
