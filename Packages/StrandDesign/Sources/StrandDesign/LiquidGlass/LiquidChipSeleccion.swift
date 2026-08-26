import SwiftUI

// MARK: - Liquid Glass · Chip de selección removible (Comparar, FER-104 · TND-30)
//
// El chip de una métrica ELEGIDA en «Comparar»: un punto del tono de IDENTIDAD de la señal +
// su nombre + una ✕. Reemplaza al `FlowChips` del papel. Se acomodan en flujo con
// `LiquidFlujoLeyenda` (el mismo Layout que envuelve la leyenda del calendario de 90).
//
// TODA LA CÁPSULA ES EL CONTROL DE QUITAR. La ✕ es la seña visual, no un botón anidado: el
// papel colgaba una `Button` dentro de un chip inerte, y un target del tamaño de una ✕ es
// hostil al dedo. Aquí el chip entero quita (un solo elemento de VoiceOver, «Quitar VFC», con
// blanco táctil holgado), que es como iOS retira un token de filtro.
//
// CÁPSULA SÓLIDA, no vidrio. El chip vive DENTRO de la hoja de vidrio de Comparar; una receta
// de vidrio aquí muestrearía el fondo y saltaría de gris a blanco al arrastrar la hoja (el
// defecto de las «tablas grises», FER-29/33). El papel opaco (`.pastillaSolida`) es imposible
// de ensuciar por construcción.
//
// Contrato: `nombre` y `a11yQuitar` llegan YA localizados; el `tono` es la identidad de la
// señal — nunca un color por índice — el MISMO hue que su línea en la gráfica y su gota en el
// tooltip (esa unidad de color es la razón de ser del puente de identidad de TND-29).

public struct LiquidChipSeleccion: View {
    private let nombre: String
    private let tono: Color
    private let a11yQuitar: String
    private let onQuitar: () -> Void

    /// En tallas de accesibilidad el nombre puede desbordar la fila de flujo (el layout mide el
    /// chip con su ancho ideal): ahí se le pone techo y se deja envolver a dos renglones en vez
    /// de correrse fuera del bisel (TND30-5).
    @Environment(\.dynamicTypeSize) private var tamano
    /// Techo del nombre en AX: cabe con holgura en el ancho de flujo del iPhone más chico
    /// (≈276 pt menos el punto, la ✕ y el padding de la cápsula).
    private let anchoNombreAX: CGFloat = 200

    public init(nombre: String, tono: Color, a11yQuitar: String,
                onQuitar: @escaping () -> Void) {
        self.nombre = nombre
        self.tono = tono
        self.a11yQuitar = a11yQuitar
        self.onQuitar = onQuitar
    }

    public var body: some View {
        Button(action: onQuitar) {
            HStack(spacing: LiquidSpace.s150) {
                // El punto de identidad: el mismo tono que la línea de esta señal en la
                // gráfica. Decorativo — el nombre de al lado ya lo dice.
                Circle()
                    .fill(tono)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(verbatim: nombre)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(tamano.isAccessibilitySize ? 2 : 1)
                    .truncationMode(.tail)
                    .frame(maxWidth: tamano.isAccessibilitySize ? anchoNombreAX : nil,
                           alignment: .leading)
                // La seña de quitar. Decorativa: la acción vive en el chip entero.
                Image(systemName: "xmark")
                    .font(LiquidType.iconSF(size: 9))
                    .foregroundStyle(LiquidColor.tinta500)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, LiquidSpace.s300)
            .padding(.vertical, LiquidSpace.s150)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.liquidPress)
        .liquidGlass(.pastillaSolida)
        // El `Button` YA aporta el trait `.isButton`; repetirlo hacía que VoiceOver dijera
        // «botón, botón» (TND30-6). El label reemplaza el texto por «Quitar <métrica>», una
        // sola parada.
        .accessibilityLabel(Text(verbatim: a11yQuitar))
    }
}

#if DEBUG
#Preview("Liquid · ChipSeleccion") {
    LiquidFlujoLeyenda(espacioH: LiquidSpace.s150, espacioV: LiquidSpace.s150) {
        LiquidChipSeleccion(nombre: "VFC", tono: LiquidColor.cian,
                            a11yQuitar: "Quitar VFC") {}
        LiquidChipSeleccion(nombre: "Esfuerzo", tono: LiquidColor.ambar,
                            a11yQuitar: "Quitar Esfuerzo") {}
        LiquidChipSeleccion(nombre: "Sueño", tono: LiquidColor.indigo,
                            a11yQuitar: "Quitar Sueño") {}
        LiquidChipSeleccion(nombre: "FC en reposo", tono: LiquidColor.rosa,
                            a11yQuitar: "Quitar FC en reposo") {}
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}
#endif
