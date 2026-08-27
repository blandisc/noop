import SwiftUI

// MARK: - Entrenar · mini-barras del hub v18 (FER-171 · Parte A)
//
// El chip de tendencia de dos tiles del hub: el «salto» de marcas (mock `.prJump`, tile Marcas —
// 2 barras, la vieja gris y la nueva teñida de rosa) y los «escalones» de subidas (mock `.steps`,
// tile Subidas listas — 3 barras, las dos primeras grises y la última verde). Un solo componente
// para las dos: ancho de barra 6, gap 3, alto máximo 16, radio superior 2 / inferior 1 (mock
// `border-radius:2px 2px 1px 1px`, vía `UnevenRoundedRectangle` — ya usada en el sistema, p.ej.
// `ConfirmCard`/`ThermalTicket`, no una forma nueva).

/// Constantes con nombre de la receta (mock v18, clases `.prJump`/`.steps`).
private enum EntrenarMiniBarrasMetrics {
    static let ancho: CGFloat = 6
    static let gap: CGFloat = 3
    static let altoMaximo: CGFloat = 16
    static let radioArriba: CGFloat = 2
    static let radioAbajo: CGFloat = 1
    /// Alfa de las barras «pasado» (todas salvo la última). El mock usa DOS alfas distintas para
    /// el mismo rol — `.prJump` (una sola barra gris junto al salto) va a tinta .50, `.steps` (dos
    /// barras grises antes del escalón final) va a tinta .30 — y el componente único de este
    /// archivo (sin un parámetro de alfa en su contrato, §3c) no puede reproducir ambas a la vez.
    /// .40 es el punto medio del rango que pide el spec («tinta al 30–50 %») — GAP documentado en
    /// el reporte del agente, no un valor inventado a ciegas.
    static let pasadoAlfa: Double = 0.40
}

/// Las mini-barras de tendencia: N barras relativas (0…1), la ÚLTIMA pintada del tono — las
/// anteriores en tinta neutra («pasado», sin protagonismo).
public struct EntrenarMiniBarras: View {
    private let alturas: [CGFloat]
    private let tono: EntrenarTono

    /// - Parameters:
    ///   - alturas: alturas relativas 0…1 (se clampan), izquierda→derecha en el mismo orden que
    ///     se dibujan. La ÚLTIMA es la barra "presente" y se pinta de `tono.base`.
    ///   - tono: el tono de la barra final.
    public init(alturas: [CGFloat], tono: EntrenarTono) {
        self.alturas = alturas
        self.tono = tono
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: EntrenarMiniBarrasMetrics.gap) {
            ForEach(Array(alturas.enumerated()), id: \.offset) { index, alturaRelativa in
                let esUltima = index == alturas.count - 1
                let alto = EntrenarMiniBarrasMetrics.altoMaximo * min(1, max(0, alturaRelativa))
                UnevenRoundedRectangle(topLeadingRadius: EntrenarMiniBarrasMetrics.radioArriba,
                                       bottomLeadingRadius: EntrenarMiniBarrasMetrics.radioAbajo,
                                       bottomTrailingRadius: EntrenarMiniBarrasMetrics.radioAbajo,
                                       topTrailingRadius: EntrenarMiniBarrasMetrics.radioArriba,
                                       style: .continuous)
                    .fill(esUltima ? AnyShapeStyle(tono.base)
                                   : AnyShapeStyle(LiquidColor.tinta900.opacity(EntrenarMiniBarrasMetrics.pasadoAlfa)))
                    .frame(width: EntrenarMiniBarrasMetrics.ancho, height: max(1, alto))
            }
        }
        // El numeral grande que siempre acompaña a estas barras (102.5 kg, 3 subidas…) ya dice el
        // dato; el chip es refuerzo visual puro — mismo criterio que `EntrenarFamilyDot`.
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("EntrenarMiniBarras · 2 y 3 barras") {
    VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "El salto de marcas (2 barras)").font(.system(size: 11))
            EntrenarMiniBarras(alturas: [0.625, 1.0], tono: .rosa)
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Los escalones de subidas (3 barras)").font(.system(size: 11))
            EntrenarMiniBarras(alturas: [0.5, 0.75, 1.0], tono: .verde)
        }
    }
    .padding(24)
    .background(LiquidColor.fondoGradient)
}
#endif
