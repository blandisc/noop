import SwiftUI

// MARK: - Liquid Glass · Campo de búsqueda (FER-289)
//
// Campo de texto con lupa + ✕ de limpiar, sobre papel opaco (`.superficieSolida`).
// Vive dentro de hojas El Eje (Biblioteca de ejercicios); el caller pasa el placeholder
// y el label a11y ya localizados — esta pieza es tonta.

public struct LiquidCampoBusqueda: View {
    private let placeholder: String
    @Binding private var text: String
    private let a11yLimpiar: String

    @ScaledMetric(relativeTo: .footnote) private var tamano: CGFloat = LiquidType.lecturaHojaBase

    public init(placeholder: String, text: Binding<String>, a11yLimpiar: String) {
        self.placeholder = placeholder
        self._text = text
        self.a11yLimpiar = a11yLimpiar
    }

    public var body: some View {
        HStack(spacing: LiquidSpace.s200) {
            StrandIcon.search.image
                .font(LiquidType.iconSF(size: 15))
                .foregroundStyle(LiquidColor.tinta500)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .font(.system(size: tamano))
                .foregroundStyle(LiquidColor.tinta900)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    StrandIcon.close.image
                        .font(LiquidType.iconSF(size: 15))
                        .foregroundStyle(LiquidColor.tinta500)
                        .frame(width: LiquidControl.hitTarget, height: LiquidControl.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(a11yLimpiar))
            }
        }
        .padding(.horizontal, LiquidSpace.s400)
        .padding(.vertical, LiquidSpace.s300)
        .liquidGlass(.superficieSolida)
    }
}

#if DEBUG
#Preview("LiquidCampoBusqueda · vacío") {
    LiquidCampoBusqueda(placeholder: "Buscar ejercicio", text: .constant(""),
                        a11yLimpiar: "Limpiar búsqueda")
        .padding(LiquidSpace.s550)
        .background(LiquidColor.fondoGradient)
}

#Preview("LiquidCampoBusqueda · con texto") {
    LiquidCampoBusqueda(placeholder: "Buscar ejercicio", text: .constant("press banca"),
                        a11yLimpiar: "Limpiar búsqueda")
        .padding(LiquidSpace.s550)
        .background(LiquidColor.fondoGradient)
}
#endif
