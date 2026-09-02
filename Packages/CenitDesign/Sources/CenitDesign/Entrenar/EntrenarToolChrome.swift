import SwiftUI

// MARK: - EntrenarToolChrome (FER-120 · E8b)
//
// Las dos piezas de chrome que se repetían palabra por palabra entre `BreathingView` e
// `IntervalTimerView`: una píldora de estado quieta y una tarjeta contenida. Mismo patrón que
// `EntrenarNivel`/`EntrenarChip` («las dos piezas de chrome que se repiten») — un solo dueño por
// pieza en vez de una copia por pantalla.

/// La píldora de estado quieta: cápsula de papel con canto, rótulo en tinta, y un punto de color
/// OPCIONAL — el único lugar donde un hue toca esta pieza, y solo como un punto, nunca como relleno
/// (regla del ADN: el hue no llena fondos ni molduras).
public struct EntrenarStatusPill: View {
    private let text: LocalizedStringKey
    private let dotColor: Color?

    public init(_ text: LocalizedStringKey, dotColor: Color? = nil) {
        self.text = text
        self.dotColor = dotColor
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let dotColor {
                Circle().fill(dotColor).frame(width: 6, height: 6)
            }
            Text(text)
                .font(StrandFont.caption)
                .foregroundStyle(LiquidColor.tinta900)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlass(.pastillaSolida)
    }
}

/// La tarjeta contenida: papel de superficie con filo de tinta. El orbe de respiración, el anillo
/// de intervalos y sus lecturas necesitan una superficie sostenida donde asentarse — se usa poco
/// (el ADN prefiere jerarquía por espacio), pero cuando se usa, es siempre esta misma pieza.
struct EntrenarToolCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(.superficieSolida)
    }
}

#if DEBUG
#Preview("EntrenarStatusPill · con y sin punto") {
    VStack(alignment: .leading, spacing: 12) {
        EntrenarStatusPill("Ready")
        EntrenarStatusPill("Session live", dotColor: LiquidColor.verdePrimario)
        EntrenarStatusPill("Paused")
    }
    .padding(24)
    .background(LiquidColor.fondoAlto)
}

#Preview("EntrenarToolCard · distinto padding") {
    VStack(alignment: .leading, spacing: 16) {
        EntrenarToolCard {
            Text("Padding 16 (default)")
                .font(StrandFont.subhead).foregroundStyle(LiquidColor.tinta900)
        }
        EntrenarToolCard(padding: 24) {
            Text("Padding 24")
                .font(StrandFont.subhead).foregroundStyle(LiquidColor.tinta900)
        }
    }
    .padding(24)
    .background(LiquidColor.fondoAlto)
}
#endif
