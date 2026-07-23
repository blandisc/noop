import SwiftUI

// MARK: - Liquid Glass · Lectura/veredicto de hoja (épico hoja Liquid, F2)
//
// La línea de lectura bajo el numeral: una frase corta ya localizada («Tu VFC amaneció en
// tu rango.») con la FRASE CLAVE opcional destacada en el tono de la métrica — el mismo
// lenguaje del héroe de Hoy (color solo en el datum). Texto de LECTURA: escala con
// Dynamic Type.

public struct LiquidReadingLine: View {
    private let text: String
    private let highlight: String?
    private let highlightTone: Color

    // 16 (pedido del dueño /inject: a 14 la frase clave se leía chica para lo
    /// importante que es).
    @ScaledMetric(relativeTo: .body) private var cuerpoSize: CGFloat = 16

    /// `highlight` debe aparecer dentro de `text` (se pinta su última ocurrencia).
    public init(_ text: String, highlight: String? = nil,
                highlightTone: Color = LiquidColor.verdePrimario) {
        self.text = text
        self.highlight = highlight
        self.highlightTone = highlightTone
    }

    public var body: some View {
        composed
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text(verbatim: text))
    }

    /// El trozo a destacar. Si el caller no lo dice, se usa la PRIMERA CLÁUSULA —el
    /// veredicto— hasta la primera coma (pasada UX H5: sin esto la negrita solo llegaba a
    /// sueño y la misma frase salía plana en las otras 11 hojas). Derivarlo del texto en
    /// vez de acuñar una clave por frase evita el contrato frágil de subcadenas: si un
    /// traductor reescribe, la negrita sigue cayendo donde debe.
    static func clausulaVeredicto(_ t: String) -> String? {
        if let coma = t.firstIndex(of: ",") {
            let trozo = String(t[t.startIndex..<coma])
            return trozo.isEmpty ? nil : trozo
        }
        let limpio = t.hasSuffix(".") ? String(t.dropLast()) : t
        return limpio.isEmpty ? nil : limpio
    }

    private var composed: Text {
        let base = Font.system(size: cuerpoSize)
        let trozo: String? = highlight ?? Self.clausulaVeredicto(text)
        guard let highlight = trozo,
              let range = text.range(of: highlight, options: .backwards) else {
            return Text(verbatim: text).font(base).foregroundColor(LiquidColor.tinta700)
        }
        return Text(verbatim: String(text[..<range.lowerBound])).font(base)
            .foregroundColor(LiquidColor.tinta700)
            + Text(verbatim: String(text[range])).font(base).fontWeight(.bold)
            .foregroundColor(highlightTone)
            + Text(verbatim: String(text[range.upperBound...])).font(base)
            .foregroundColor(LiquidColor.tinta700)
    }
}

#if DEBUG
#Preview("Liquid · ReadingLine") {
    VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        LiquidReadingLine("Tu VFC amaneció en tu rango.",
                          highlight: "en tu rango", highlightTone: LiquidColor.verdeProfundo)
        LiquidReadingLine("Debajo de tu base — tu cuerpo sigue procesando el esfuerzo de ayer.",
                          highlight: "Debajo de tu base", highlightTone: LiquidColor.atencionTexto)
        LiquidReadingLine("Sin lectura esta noche.")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo())
}
#endif
