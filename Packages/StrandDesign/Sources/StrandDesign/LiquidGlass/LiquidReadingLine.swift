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
    private let highlights: [String]?
    private let highlightTone: Color

    // 17 (#inject r3 — antes 16, antes 14; pedido del dueño: la frase-veredicto es lo
    /// segundo más importante de la hoja tras el numeral y seguía leyéndose chica).
    @ScaledMetric(relativeTo: .body) private var cuerpoSize: CGFloat = 17

    /// `highlight` debe aparecer dentro de `text` (se pinta su última ocurrencia).
    public init(_ text: String, highlight: String? = nil,
                highlightTone: Color = LiquidColor.verdePrimario) {
        self.text = text
        self.highlight = highlight
        self.highlights = nil
        self.highlightTone = highlightTone
    }

    /// Varios trozos destacados en la MISMA frase. Nace del veredicto de etapas de Sueño
    /// («Profundo y REM por encima de tu típico»), que destaca DOS nombres y por eso se
    /// dibujaba a mano con 42 líneas de recorrido de rangos dentro de la pantalla.
    ///
    /// Los trozos se ordenan y se recortan solos: si dos se solapan gana el primero, y los
    /// que no aparecen en `text` se ignoran — un traductor puede reescribir la frase sin
    /// romper el render.
    public init(_ text: String, highlights: [String],
                highlightTone: Color = LiquidColor.verdePrimario) {
        self.text = text
        self.highlight = nil
        self.highlights = highlights
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
        if let highlights { return compuestoMulti(highlights, base: base) }
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

    /// Recorre la frase UNA vez y va alternando tinta / tono. Los rangos se calculan primero,
    /// se ordenan por posición y se descartan los que se solapan con uno ya aceptado.
    private func compuestoMulti(_ trozos: [String], base: Font) -> Text {
        var rangos: [Range<String.Index>] = []
        for t in trozos where !t.isEmpty {
            guard let r = text.range(of: t) else { continue }
            if rangos.contains(where: { $0.overlaps(r) }) { continue }
            rangos.append(r)
        }
        guard !rangos.isEmpty else {
            return Text(verbatim: text).font(base).foregroundColor(LiquidColor.tinta700)
        }
        rangos.sort { $0.lowerBound < $1.lowerBound }

        var salida = Text(verbatim: "")
        var cursor = text.startIndex
        for r in rangos {
            if cursor < r.lowerBound {
                salida = salida + Text(verbatim: String(text[cursor..<r.lowerBound]))
                    .font(base).foregroundColor(LiquidColor.tinta700)
            }
            salida = salida + Text(verbatim: String(text[r]))
                .font(base).fontWeight(.bold).foregroundColor(highlightTone)
            cursor = r.upperBound
        }
        if cursor < text.endIndex {
            salida = salida + Text(verbatim: String(text[cursor...]))
                .font(base).foregroundColor(LiquidColor.tinta700)
        }
        return salida
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
        LiquidReadingLine("Profundo y REM por encima de tu típico",
                          highlights: ["Profundo", "REM"], highlightTone: LiquidColor.indigo)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo())
}
#endif
