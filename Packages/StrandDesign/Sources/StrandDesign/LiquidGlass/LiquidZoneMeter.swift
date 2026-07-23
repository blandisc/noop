import SwiftUI

// MARK: - Liquid Glass · Medidor de zonas (épico hoja Liquid, F2)
//
// Rebuild ligero de la geometría de `ZoneMeter` (FER-707/710) en tokens Liquid — decisión C3
// del contrato (docs/design-system/LIQUID-SHEET-CONTRACT.md §4): la geometría son ~30 líneas
// triviales y parametrizar el tema ensuciaría el componente papel que Instrumento sigue usando.
// Una banda horizontal con un segmento por zona (ancho ∝ su peso en la escala), un tick de
// tinta en la posición de la lectura y los rótulos en caja alta debajo; la zona activa va
// iluminada (alfa llena) y con su rótulo en color, las demás quedan tenues — color solo en
// el datum.
//
// Contrato D3: los colores los pone el caller (LiquidColor.positivo/atencion/negativo) y los
// strings llegan YA localizados y en MAYÚSCULAS; el DS no conoce `MetricLevels` ni locales.

public struct LiquidZoneMeter: View {
    /// Una zona del medidor: su peso en la escala (cualquier unidad positiva — la fila
    /// normaliza por la suma), su color de banda, si la lectura de hoy cae ahí, y su rótulo
    /// corto (ya localizado y en MAYÚSCULAS).
    public struct Segmento: Sendable {
        public let peso: Double
        public let color: Color
        public let activa: Bool
        public let etiqueta: String

        public init(peso: Double, color: Color, activa: Bool, etiqueta: String) {
            self.peso = peso
            self.color = color
            self.activa = activa
            self.etiqueta = etiqueta
        }
    }

    private let segmentos: [Segmento]
    /// La posición de la lectura sobre toda la escala, 0 (izquierda) … 1 (derecha). El tick
    /// de tinta vive ahí; nil lo oculta (sin lectura).
    private let fraccion: Double?

    /// Ancho del trazo del tick — es trazo, no espaciado (paridad `ZoneMeter`).
    private static let tickAncho: CGFloat = 2.5
    /// Gap entre segmentos — paridad EXACTA con `ZoneMeter` (3, no un token de espacio:
    /// es geometría del instrumento; revote adversarial F2).
    private static let gap: CGFloat = 3
    /// Alfas de paridad `ZoneMeter` (0.9 activa / 0.28 tenue).
    private static let activaAlfa: Double = 0.9
    private static let tenueAlfa: Double = 0.28

    /// El alto de una línea de rótulo — escala con Dynamic Type junto a `microEstado`
    /// (relativo a .caption2), para que el frame del GeometryReader no recorte los rótulos.
    @ScaledMetric(relativeTo: .caption2) private var etiquetaAlto: CGFloat = 14

    public init(segmentos: [Segmento], fraccion: Double?) {
        self.segmentos = segmentos
        self.fraccion = fraccion
    }

    /// El ancho proporcional de cada segmento para un ancho disponible, después de reservar
    /// los gaps entre ellos — los anchos siguen los spans reales de las zonas
    /// (25/25/20/18/12), no un reparto parejo. (Paridad `ZoneMeter.widths`.)
    private func anchos(en total: CGFloat) -> [CGFloat] {
        let suma = segmentos.reduce(0) { $0 + $1.peso }
        guard suma > 0 else { return segmentos.map { _ in 0 } }
        let usable = max(0, total - Self.gap * CGFloat(segmentos.count - 1))
        return segmentos.map { CGFloat($0.peso / suma) * usable }
    }

    public var body: some View {
        GeometryReader { geo in
            let w = anchos(en: geo.size.width)
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                ZStack(alignment: .leading) {
                    HStack(spacing: Self.gap) {
                        ForEach(segmentos.indices, id: \.self) { i in
                            Capsule()
                                .fill(segmentos[i].color)
                                .opacity(segmentos[i].activa ? Self.activaAlfa : Self.tenueAlfa)
                                .frame(width: w[i], height: LiquidSpace.s150)
                        }
                    }
                    if let fraccion {
                        Capsule()
                            .fill(LiquidColor.tinta900)
                            .frame(width: Self.tickAncho, height: LiquidSpace.s300)
                            .offset(x: geo.size.width * CGFloat(min(max(fraccion, 0), 1))
                                        - Self.tickAncho / 2)
                    }
                }
                .frame(height: LiquidSpace.s300)
                HStack(spacing: Self.gap) {
                    ForEach(segmentos.indices, id: \.self) { i in
                        Text(verbatim: segmentos[i].etiqueta)
                            .font(LiquidType.microEstado)
                            .foregroundStyle(segmentos[i].activa ? segmentos[i].color
                                                                 : LiquidColor.tinta500)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: w[i], alignment: .leading)
                    }
                }
            }
        }
        .frame(height: LiquidSpace.s300 + LiquidSpace.s150 + etiquetaAlto)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.a11yLabel(segmentos: segmentos)))
    }

    /// La etiqueta de la zona activa (ya localizada por el caller) — contrato de VoiceOver
    /// testeable en frío; vacía cuando ninguna zona está activa (sin lectura).
    static func a11yLabel(segmentos: [Segmento]) -> String {
        segmentos.first(where: \.activa)?.etiqueta ?? ""
    }
}

#if DEBUG
#Preview("Liquid · ZoneMeter") {
    VStack(alignment: .leading, spacing: LiquidSpace.s800) {
        // Recovery con lectura: 3 zonas (34/33/33) y el tick al 62 % → zona media activa.
        LiquidZoneMeter(segmentos: [
            .init(peso: 34, color: LiquidColor.negativo, activa: false, etiqueta: "AGOTADO"),
            .init(peso: 33, color: LiquidColor.atencion, activa: true,  etiqueta: "MODERADO"),
            .init(peso: 33, color: LiquidColor.positivo, activa: false, etiqueta: "LISTO"),
        ], fraccion: 0.62)

        // Sin lectura: tick oculto, ninguna zona activa (todas tenues).
        LiquidZoneMeter(segmentos: [
            .init(peso: 34, color: LiquidColor.negativo, activa: false, etiqueta: "AGOTADO"),
            .init(peso: 33, color: LiquidColor.atencion, activa: false, etiqueta: "MODERADO"),
            .init(peso: 33, color: LiquidColor.positivo, activa: false, etiqueta: "LISTO"),
        ], fraccion: nil)

        // Otra zona activa: lectura alta (tick al 85 %).
        LiquidZoneMeter(segmentos: [
            .init(peso: 34, color: LiquidColor.negativo, activa: false, etiqueta: "AGOTADO"),
            .init(peso: 33, color: LiquidColor.atencion, activa: false, etiqueta: "MODERADO"),
            .init(peso: 33, color: LiquidColor.positivo, activa: true,  etiqueta: "LISTO"),
        ], fraccion: 0.85)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.verdePrimario))
}
#endif
