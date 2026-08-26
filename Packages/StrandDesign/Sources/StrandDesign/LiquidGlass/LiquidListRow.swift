import SwiftUI

// MARK: - Liquid Glass · ListRow (handoff §5.7)
//
// Fila de lista (plan semanal, listados). Vive DENTRO de una tarjeta vidrio/superficie
// (`LiquidListCard`): punto de tono con glow · título + subtítulo · trailing · chevron
// en el tono. El divisor es borde inferior 0.5 tinta/10 (false en la última fila).
//
// MODO SELECCIÓN (FER-104 · TND-30): con `seleccionado` no-nil la fila deja de ser una fila de
// navegación y se vuelve un TOGGLE — el chevron se cambia por un ✓ en el tono cuando está
// elegida (hueco reservado cuando no, para que el layout no salte), y anuncia `.isSelected`.
// `deshabilitado` la apaga y la vuelve inerte (el tope de 4 en el picker de Comparar): sin
// glow, en tinta terciaria, sin acción. El `subtitle` es opcional — vacío no dibuja renglón.

public struct LiquidListRow: View {
    private let title: String
    private let subtitle: String
    private let trailing: String?
    private let tone: Color
    /// nil = fila de navegación (chevron). No-nil = toggle: ✓ cuando `true`.
    private let seleccionado: Bool?
    /// Fila apagada e inerte (tope de selección alcanzado).
    private let deshabilitado: Bool
    private let divider: Bool
    private let action: (() -> Void)?

    public init(title: String, subtitle: String = "", trailing: String? = nil, tone: Color,
                seleccionado: Bool? = nil, deshabilitado: Bool = false,
                divider: Bool = true, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.tone = tone
        self.seleccionado = seleccionado
        self.deshabilitado = deshabilitado
        self.divider = divider
        self.action = action
    }

    public var body: some View {
        // Una fila apagada no es un botón: no responde y no debe leerse como accionable.
        if let action, !deshabilitado {
            Button(action: action) { content }
                .buttonStyle(.liquidPress)
                .accessibilityAddTraits(traits)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(traits)
        }
    }

    private var traits: AccessibilityTraits {
        seleccionado == true ? .isSelected : []
    }

    private var tintaTitulo: Color {
        deshabilitado ? LiquidColor.tinta500 : LiquidColor.tinta900
    }

    private var tonoPunto: Color {
        deshabilitado ? LiquidColor.tinta500 : tone
    }

    private var content: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tonoPunto)
                .frame(width: 8, height: 8)
                // Glow del punto como geometría (regla del sistema: nada de .shadow a mano).
                // Apagada: sin glow, para que la fila inerte no compita con las elegibles.
                .liquidShadow(deshabilitado
                              ? []
                              : [.init(color: tone.opacity(0.35), radius: 4, y: 0)],
                              silhouette: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LiquidType.tituloFila).foregroundStyle(tintaTitulo)
                if !subtitle.isEmpty {
                    Text(subtitle).font(LiquidType.unidadCompacta)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Text(trailing).font(LiquidType.unidadCompacta).foregroundStyle(LiquidColor.tinta500)
            }
            afordanciaTrailing
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

    @ViewBuilder private var afordanciaTrailing: some View {
        if let seleccionado {
            // Modo toggle: ✓ en el tono cuando está elegida. El hueco se reserva SIEMPRE
            // (opacidad 0 cuando no) para que activar/desactivar no mueva el layout.
            Image(systemName: "checkmark")
                .font(LiquidType.iconSF(size: 12))
                .foregroundStyle(tone)
                .opacity(seleccionado ? 1 : 0)
                .frame(width: 14, alignment: .trailing)
                .accessibilityHidden(true)
        } else {
            LiquidIcon(.chevron, size: 12, color: tone)
        }
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
            .liquidGlass(.superficie) // token-exempt: fila de lista de pantalla, no de hoja
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

/// Modo selección (picker de Comparar): ✓ en el tono cuando está elegida, apagada al tope.
#Preview("Liquid · ListRow selección") {
    VStack(spacing: 0) {
        LiquidListRow(title: "VFC", tone: LiquidColor.cian, seleccionado: true, action: {})
        LiquidListRow(title: "Esfuerzo", tone: LiquidColor.ambar, seleccionado: true, action: {})
        LiquidListRow(title: "Sueño", tone: LiquidColor.indigo, seleccionado: false, action: {})
        LiquidListRow(title: "FC en reposo", tone: LiquidColor.rosa,
                      seleccionado: false, deshabilitado: true, divider: false, action: {})
    }
    .liquidTarjetaSeccion()
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}
#endif
