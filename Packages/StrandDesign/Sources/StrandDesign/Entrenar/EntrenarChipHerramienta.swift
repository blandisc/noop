import SwiftUI

// MARK: - EntrenarChipHerramienta (FER-292)
//
// Puerta de herramienta del flujo Entrenar sobre papel sólido El Eje: mismo contrato que
// `InstrumentoToolChip` (systemImage + label `Text` + action), piel `.pastillaSolida` en vez
// del `patternBlock` hundido. Crear plan / Nueva sección / Plantillas.

public struct EntrenarChipHerramienta: View {
    let systemImage: String
    let label: Text
    let action: () -> Void

    public init(systemImage: String, label: Text, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: LiquidSpace.s150) {
                Image(systemName: systemImage)
                    .font(LiquidType.iconSF(size: 15))
                    .foregroundStyle(LiquidColor.tinta700)
                label
                    .font(LiquidType.boton)
                    .tracking(LiquidType.botonTracking)
                    .foregroundStyle(LiquidColor.tinta900)
            }
            .frame(maxWidth: .infinity, minHeight: LiquidControl.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        .liquidGlass(.pastillaSolida)
    }
}

#if DEBUG
#Preview("EntrenarChipHerramienta") {
    HStack(spacing: LiquidSpace.s200) {
        EntrenarChipHerramienta(systemImage: "rectangle.stack.badge.plus",
                                label: Text(verbatim: "Crear plan")) {}
        EntrenarChipHerramienta(systemImage: "folder.badge.plus",
                                label: Text(verbatim: "Nueva sección")) {}
    }
    .padding(LiquidSpace.s600)
    .background(LiquidColor.fondoGradient)
}
#endif
