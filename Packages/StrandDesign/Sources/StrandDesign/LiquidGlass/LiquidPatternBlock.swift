import SwiftUI

// MARK: - Liquid Glass · Bloque de patrón (épico hoja Liquid, F2)
//
// «Tu patrón» y «Para esta noche» en una sola pieza: overline en caja alta + una o varias
// frases honestas de lectura, con la barra lateral en el tono de la métrica como única marca
// de color (el gesto «patrón/conexión» del bloque Instrumento, `vitalPatternBlock` /
// `PaperSideBarBlock`).
//
// Decisión de fondo: SIN vidrio. El bloque Instrumento llevaba `theme.surface` porque el
// surface papel es un wash plano y quieto; el `.liquidGlass(.superficie)` equivalente trae
// blur + borde + especular + sombra — una tarjeta completa que competiría con el vidrio de
// gráficas y explorador y volvería ruidosa una anotación quieta. La barra lateral sola ya da
// la identidad del bloque sobre el fondo de la hoja (`LiquidSheetFondo`).
//
// Contrato D3: strings YA localizados (findings ya resueltos a texto); el DS no conoce
// locales. El caller oculta el bloque cuando no hay líneas (paridad con el guard de
// `vitalPatternBlock`).

public struct LiquidPatternBlock: View {
    private let overline: String
    private let lineas: [String]
    private let tono: Color

    /// Ancho de la barra lateral — es trazo, no espaciado (paridad con el bloque Instrumento).
    private static let barraAncho: CGFloat = 2.5

    public init(overline: String, lineas: [String], tono: Color) {
        self.overline = overline
        self.lineas = lineas
        self.tono = tono
    }

    public var body: some View {
        // Sin líneas no hay bloque: un overline con barra y sin contenido es ruido
        // (revote adversarial F2 — paridad del guard de vitalPatternBlock).
        if lineas.isEmpty { EmptyView() } else { contenido }
    }

    private var contenido: some View {
        HStack(spacing: LiquidSpace.s300) {
            Capsule()
                .fill(tono)
                .frame(width: Self.barraAncho)
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                Text(overline).liquidLabel().foregroundStyle(LiquidColor.tinta500)
                ForEach(lineas.indices, id: \.self) { i in
                    Text(verbatim: lineas[i])
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta700)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Liquid · PatternBlock") {
    VStack(alignment: .leading, spacing: LiquidSpace.s550) {
        // «Para esta noche»: una sola línea (sueño).
        LiquidPatternBlock(
            overline: "Para esta noche",
            lineas: ["Acostarte a una hora pareja esta noche ayuda a tu ritmo."],
            tono: LiquidColor.indigo)

        // «Tu patrón»: varios hallazgos (VFC).
        LiquidPatternBlock(
            overline: "Tu patrón",
            lineas: [
                "Tus noches con alcohol bajan tu VFC al día siguiente.",
                "Dormir 7 h o más sube tu base a la mañana.",
                "Entrenar fuerte hoy suele leerse mañana, no hoy.",
            ],
            tono: LiquidColor.cian)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}
#endif
