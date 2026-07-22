import SwiftUI

// MARK: - Liquid Glass · ListRow (handoff §5.7)
//
// Fila de lista (plan semanal, listados). Vive DENTRO de una tarjeta vidrio/superficie
// (`LiquidListCard`): punto de tono con glow · título + subtítulo · trailing · chevron
// en el tono. El divisor es borde inferior 0.5 tinta/10 (false en la última fila).

public struct LiquidListRow: View {
    private let title: String
    private let subtitle: String
    private let trailing: String?
    private let tone: Color
    private let divider: Bool
    private let action: (() -> Void)?

    public init(title: String, subtitle: String, trailing: String? = nil, tone: Color,
                divider: Bool = true, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.tone = tone
        self.divider = divider
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { content }.buttonStyle(.liquidPress)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tone)
                .frame(width: 8, height: 8)
                .shadow(color: tone.opacity(0.35), radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                Text(subtitle).font(LiquidType.unidadCompacta).foregroundStyle(LiquidColor.tinta500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Text(trailing).font(LiquidType.unidadCompacta).foregroundStyle(LiquidColor.tinta500)
            }
            LiquidIcon(.chevron, size: 12).foregroundStyle(tone)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, LiquidSpace.s100)
        .overlay(alignment: .bottom) {
            if divider {
                Rectangle().fill(LiquidColor.tinta10).frame(height: 0.5)
            }
        }
        .contentShape(Rectangle())
    }
}

/// La tarjeta contenedora de filas: vidrio/superficie con el padding 2/14 del handoff.
public struct LiquidListCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) { content }
            .padding(.vertical, LiquidSpace.s050)
            .padding(.horizontal, 14)
            .liquidGlass(.superficie)
    }
}

#if DEBUG
#Preview("Liquid · ListRow") {
    LiquidListCard {
        LiquidListRow(title: "Empuje", subtitle: "L · Pecho · Hombros · Tríceps",
                      tone: LiquidColor.ambar, action: {})
        LiquidListRow(title: "Jalón", subtitle: "M · Dorsales · Espalda baja · Espalda media",
                      tone: LiquidColor.cian, action: {})
        LiquidListRow(title: "Pierna", subtitle: "X · Cuádriceps · Glúteo · Isquios",
                      tone: LiquidColor.indigo, divider: false, action: {})
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
