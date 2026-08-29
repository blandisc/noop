import SwiftUI

// MARK: - EntrenarFilaDiscos — el diagrama de discos por lado (FER-197 · Ola 1)
//
// El diagrama a escala de `PlatesScreen.barDiagram` re-vestido: una barra central + los discos
// de un lado, del más pesado (junto a la barra) al más ligero. El caller ya entrega los discos
// en ESE orden — el componente los dibuja tal cual a un lado y en espejo al otro; no decide un
// orden propio, para que un lado no se descuadre por accidente. Cada disco escala con su masa
// (mismo rango 30…76 pt de alto que la pantalla viva) y lleva su peso YA formateado, rotado,
// encima. `token-exempt`: la geometría de un disco es DATO (su tamaño es la carga real), no
// un radio/opacidad de sistema — mismo criterio que documenta `PlatesScreen.plateBar`.

public struct EntrenarFilaDiscos: View {
    /// SIN `Identifiable`/`UUID` a propósito: el despiece de placas es POSICIONAL, no una lista
    /// que se reordena — el `ForEach` de abajo identifica cada disco por su ÍNDICE (`id: \.offset`,
    /// mismo patrón que `PlatesScreen.barDiagram`), para que un recálculo del despiece actualice
    /// las barras en su lugar en vez de recrearlas (un `UUID()` nuevo en cada `init` rompía esa
    /// identidad estable y producía parpadeo).
    public struct Disco {
        /// La masa real del disco — SOLO para escalar el dibujo (el componente no la formatea).
        public let masaKg: Double
        /// El peso YA formateado («20», «1,25»).
        public let etiqueta: String

        public init(masaKg: Double, etiqueta: String) {
            self.masaKg = masaKg
            self.etiqueta = etiqueta
        }
    }

    private let discos: [Disco]
    private let tono: EntrenarTono
    private let a11yLabel: String

    /// - Parameters:
    ///   - discos: los discos de UN lado, del más pesado (junto a la barra) al más ligero.
    ///   - tono: el color de dato de los discos (ámbar de carga por default).
    ///   - a11yLabel: la frase completa ya lista para VoiceOver («por lado: 20 + 15 + 1,25 · barra
    ///     20 kg») — el componente no compone frases, solo dibuja.
    public init(discos: [Disco], tono: EntrenarTono = .ambar, a11yLabel: String) {
        self.discos = discos
        self.tono = tono
        self.a11yLabel = a11yLabel
    }

    public var body: some View {
        HStack(alignment: .center, spacing: LiquidSpace.s050) {
            ForEach(Array(discos.reversed().enumerated()), id: \.offset) { _, disco in barra(disco) }
            RoundedRectangle(cornerRadius: LiquidRadius.hairline)
                .fill(LiquidColor.tinta10)
                .frame(width: EntrenarFilaDiscosMetrics.barraAncho,
                       height: EntrenarFilaDiscosMetrics.barraAlto)
            ForEach(Array(discos.enumerated()), id: \.offset) { _, disco in barra(disco) }
        }
        .frame(maxWidth: .infinity, minHeight: EntrenarFilaDiscosMetrics.altoMinimo)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: a11yLabel))
    }

    private func barra(_ disco: Disco) -> some View {
        let m = EntrenarFilaDiscosMetrics.self
        let alto = m.altoBase + min(m.altoTope, disco.masaKg * m.altoFactor)
        let ancho = max(m.anchoMinimo, min(m.anchoTope, m.anchoBase + disco.masaKg * m.anchoFactor))
        return RoundedRectangle(cornerRadius: m.discoRadio, style: .continuous)
            .fill(tono.base)
            .frame(width: ancho, height: alto)
            .overlay {
                Text(disco.etiqueta)
                    .font(.system(size: 9, weight: .medium))   // token-exempt: microtexto <10pt
                    .foregroundStyle(LiquidColor.papelTarjeta)
                    .numeroVivo(value: disco.etiqueta)
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
            }
    }
}

private enum EntrenarFilaDiscosMetrics {
    static let altoMinimo: CGFloat = 76
    static let altoBase: CGFloat = 30
    static let altoTope: CGFloat = 46
    static let altoFactor: CGFloat = 1.7
    static let anchoMinimo: CGFloat = 8
    static let anchoTope: CGFloat = 16
    static let anchoBase: CGFloat = 6
    static let anchoFactor: CGFloat = 0.45
    static let discoRadio: CGFloat = 3
    static let barraAncho: CGFloat = 54
    static let barraAlto: CGFloat = 6
}

#if DEBUG
#Preview("EntrenarFilaDiscos · 82,5 kg por lado") {
    EntrenarFilaDiscos(
        discos: [
            .init(masaKg: 20, etiqueta: "20"),
            .init(masaKg: 15, etiqueta: "15"),
            .init(masaKg: 1.25, etiqueta: "1,25"),
        ],
        tono: .ambar,
        a11yLabel: "por lado: 20 + 15 + 1,25 · barra 20 kg")
    .padding(LiquidSpace.s400)
    .liquidGlass(.superficieSolida)
    .padding(LiquidSpace.s550)
    .entrenarHojaFondo(tono: .ambar)
}

/// Sin discos — solo la barra, el estado de arranque antes de cargar peso.
#Preview("EntrenarFilaDiscos · barra sola") {
    EntrenarFilaDiscos(discos: [], tono: .ambar, a11yLabel: "barra 20 kg")
        .padding(LiquidSpace.s400)
        .liquidGlass(.superficieSolida)
        .padding(LiquidSpace.s550)
        .entrenarHojaFondo(tono: .ambar)
}
#endif
