import SwiftUI

// MARK: - Liquid Glass · Barra de etapas de sueño (épico hoja Liquid, F5)
//
// El «Anoche» de la hoja de sueño: una barra redondeada donde cada segmento mide ∝ los
// minutos de su etapa (profundo / REM / ligero / despierto), con overline a la izquierda,
// la ventana de la noche («23:38 → 7:04») a la derecha, y una leyenda por etapa
// (punto de color + etiqueta + duración) debajo. Port de la geometría de `SleepStageBar`
// (FER-707/710) con tokens Liquid puros; la variante absorbe el overline + la ventana que
// la hoja papel montaba fuera (contrato §4).
//
// El color vive SOLO en los segmentos y sus puntos de leyenda (rampa de opacidad del
// índigo que arma el CALLER); el texto es tinta quieta. Esquinas `LiquidRadius.control`.
//
// Contrato: strings y duraciones («1:31») YA resueltos por el caller.

public struct LiquidStageBar: View {
    /// Una etapa de la noche: minutos (para la proporción), su color, la etiqueta y la
    /// duración ya formateada.
    public struct Etapa: Identifiable {
        public let id = UUID()
        public let minutos: Double
        public let color: Color
        public let etiqueta: String
        public let duracion: String

        public init(minutos: Double, color: Color, etiqueta: String, duracion: String) {
            self.minutos = minutos
            self.color = color
            self.etiqueta = etiqueta
            self.duracion = duracion
        }
    }

    private let etapas: [Etapa]
    private let overline: String
    private let ventana: String

    /// La leyenda de 4 etapas no cabe en una fila cuando el texto crece: en tamaños de
    /// accesibilidad se acomoda en rejilla 2×2 (mismos items, dos columnas).
    @Environment(\.dynamicTypeSize) private var tamanoTexto

    /// Alto de la barra — geometría interna del componente (paridad `SleepStageBar`).
    private let altoBarra: CGFloat = 24

    public init(etapas: [Etapa], overline: String, ventana: String) {
        self.etapas = etapas
        self.overline = overline
        self.ventana = ventana
    }

    /// Anchos ∝ minutos sobre el total, descontando los gaps (paridad `SleepStageBar.widths`).
    private func anchos(en total: CGFloat) -> [CGFloat] {
        let suma = etapas.reduce(0) { $0 + $1.minutos }
        guard suma > 0 else { return etapas.map { _ in 0 } }
        let usable = max(0, total - LiquidSpace.s050 * CGFloat(etapas.count - 1))
        return etapas.map { CGFloat($0.minutos / suma) * usable }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: overline)
                    .font(LiquidType.microEstado)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                Spacer(minLength: LiquidSpace.s200)
                Text(verbatim: ventana)
                    .font(LiquidType.microEstado)
                    .foregroundStyle(LiquidColor.tinta700)
            }
            GeometryReader { geo in
                let w = anchos(en: geo.size.width)
                HStack(spacing: LiquidSpace.s050) {
                    ForEach(Array(etapas.enumerated()), id: \.element.id) { i, etapa in
                        Rectangle().fill(etapa.color).frame(width: w[i])
                    }
                }
            }
            .frame(height: altoBarra)
            .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous))
            leyenda
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: overline))
        .accessibilityValue(Text(verbatim:
            (etapas.map { "\($0.etiqueta) \($0.duracion)" } + [ventana])
                .joined(separator: ", ")))
    }

    /// Fila de 4 items; en tamaños de accesibilidad, rejilla 2×2 (el cambio es SOLO visual:
    /// el bloque entero es un único elemento de a11y, ver `.accessibilityElement`).
    @ViewBuilder private var leyenda: some View {
        if tamanoTexto.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                GridItem(.flexible(), alignment: .topLeading)],
                      alignment: .leading, spacing: LiquidSpace.s200) {
                ForEach(etapas) { item($0) }
            }
        } else {
            HStack(spacing: LiquidSpace.s300) {
                ForEach(etapas) { item($0) }
            }
        }
    }

    private func item(_ etapa: Etapa) -> some View {
        HStack(spacing: LiquidSpace.s100) {
            Circle()
                .fill(etapa.color)
                .frame(width: 5, height: 5)
            Text(verbatim: etapa.etiqueta)
                .font(LiquidType.microEstado)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            Text(verbatim: etapa.duracion)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
        }
    }
}

#if DEBUG
#Preview("Liquid · StageBar") {
    // Deep → REM → Light: un índigo graduado por opacidad (rampa del caller, sin tokens
    // nuevos — paridad `MetricInfoSheet.sleepAnocheBlock`); despierto en tinta quieta.
    LiquidStageBar(
        etapas: [
            .init(minutos: 91, color: LiquidColor.indigo, etiqueta: "Profundo", duracion: "1:31"),
            .init(minutos: 104, color: LiquidColor.indigo.opacity(0.78), etiqueta: "REM", duracion: "1:44"), // token-exempt: rampa graduada de etapas
            .init(minutos: 190, color: LiquidColor.indigo.opacity(0.52), etiqueta: "Ligero", duracion: "3:10"), // token-exempt: rampa graduada de etapas
            .init(minutos: 47, color: LiquidColor.tinta10, etiqueta: "Despierto", duracion: "0:47"),
        ],
        overline: "Anoche",
        ventana: "23:38 → 7:04")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}

#Preview("Liquid · StageBar (AX)") {
    // Tamaño de accesibilidad: la leyenda deja de ser una fila y se acomoda 2×2.
    LiquidStageBar(
        etapas: [
            .init(minutos: 91, color: LiquidColor.indigo, etiqueta: "Profundo", duracion: "1:31"),
            .init(minutos: 104, color: LiquidColor.indigo.opacity(0.78), etiqueta: "REM", duracion: "1:44"), // token-exempt: rampa graduada de etapas
            .init(minutos: 190, color: LiquidColor.indigo.opacity(0.52), etiqueta: "Ligero", duracion: "3:10"), // token-exempt: rampa graduada de etapas
            .init(minutos: 47, color: LiquidColor.tinta10, etiqueta: "Despierto", duracion: "0:47"),
        ],
        overline: "Anoche",
        ventana: "23:38 → 7:04")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
