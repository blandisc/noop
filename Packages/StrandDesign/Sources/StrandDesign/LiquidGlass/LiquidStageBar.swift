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
    private let ventana: String?

    /// La leyenda de 4 etapas no cabe en una fila cuando el texto crece: en tamaños de
    /// accesibilidad se acomoda en rejilla 2×2 (mismos items, dos columnas).
    @Environment(\.dynamicTypeSize) private var tamanoTexto

    /// Alto de la barra — geometría interna del componente (paridad `SleepStageBar`).
    private let altoBarra: CGFloat = 24

    /// B7 · `ventana` es OPCIONAL: el fallback diario de Apple fabrica noches con
    /// `startTs == endTs`, y el caller que no puede afirmar un horario real pasa `nil` en vez
    /// de imprimir «6:00 → 6:00». Sin ventana no se pinta el reloj ni entra a VoiceOver.
    public init(etapas: [Etapa], overline: String, ventana: String? = nil) {
        self.etapas = etapas
        self.overline = overline
        self.ventana = ventana
    }

    /// B7 · Las etapas de 0 minutos NO existen para esta barra: con el fallback diario de
    /// Apple `awake` llega en 0 por construcción y la leyenda imprimía «DESPIERTO 0:00»,
    /// insinuando una medición que nunca ocurrió. Se filtran UNA vez, arriba, para que
    /// segmentos, leyenda y VoiceOver cuenten exactamente lo mismo.
    ///
    /// Ojo (caller): con TODAS las etapas en 0 esto queda vacío y la barra se dibuja hueca.
    /// Esa noche no se midió: el caller no debe pintar el componente.
    private var etapasVisibles: [Etapa] { Self.visibles(etapas) }

    /// El filtro, como función pura para que segmentos, leyenda, VoiceOver **y el test**
    /// cuenten exactamente lo mismo.
    static func visibles(_ etapas: [Etapa]) -> [Etapa] {
        etapas.filter { $0.minutos > 0 }
    }

    /// Lo que dicta VoiceOver: las etapas MEDIDAS con su duración y, solo si el caller la
    /// pudo afirmar, la ventana de la noche (contrato testeable en frío, como
    /// `LiquidSheetHeader.a11yLabel`).
    static func a11yValue(etapas: [Etapa], ventana: String?) -> String {
        (visibles(etapas).map { "\($0.etiqueta) \($0.duracion)" }
            + [ventana].compactMap { $0 })
            .joined(separator: ", ")
    }

    /// Anchos ∝ minutos sobre el total, descontando los gaps (paridad `SleepStageBar.widths`).
    private func anchos(en total: CGFloat) -> [CGFloat] {
        let visibles = etapasVisibles
        let suma = visibles.reduce(0) { $0 + $1.minutos }
        guard suma > 0 else { return visibles.map { _ in 0 } }
        let usable = max(0, total - LiquidSpace.s050 * CGFloat(max(0, visibles.count - 1)))
        return visibles.map { CGFloat($0.minutos / suma) * usable }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: overline)
                    .font(LiquidType.microEstado)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                if let ventana {
                    Spacer(minLength: LiquidSpace.s200)
                    Text(verbatim: ventana)
                        .font(LiquidType.microEstado)
                        .foregroundStyle(LiquidColor.tinta700)
                }
            }
            GeometryReader { geo in
                let w = anchos(en: geo.size.width)
                HStack(spacing: LiquidSpace.s050) {
                    ForEach(Array(etapasVisibles.enumerated()), id: \.element.id) { i, etapa in
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
        .accessibilityValue(Text(verbatim: Self.a11yValue(etapas: etapas, ventana: ventana)))
    }

    /// Fila de 4 items; en tamaños de accesibilidad, rejilla 2×2 (el cambio es SOLO visual:
    /// el bloque entero es un único elemento de a11y, ver `.accessibilityElement`).
    @ViewBuilder private var leyenda: some View {
        if tamanoTexto.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                GridItem(.flexible(), alignment: .topLeading)],
                      alignment: .leading, spacing: LiquidSpace.s200) {
                ForEach(etapasVisibles) { item($0) }
            }
        } else {
            HStack(spacing: LiquidSpace.s300) {
                ForEach(etapasVisibles) { item($0) }
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

/// B7 · Noche sin horario afirmable (fallback diario de Apple: `startTs == endTs`) y sin
/// despertares MEDIDOS: ni reloj «6:00 → 6:00» ni «DESPIERTO 0:00». La barra pierde el gap
/// fantasma del segmento de ancho 0 (los tres segmentos reparten los 2 pt que sobran).
#Preview("Liquid · StageBar (sin ventana, etapa en 0)") {
    LiquidStageBar(
        etapas: [
            .init(minutos: 91, color: LiquidColor.indigo, etiqueta: "Profundo", duracion: "1:31"),
            .init(minutos: 104, color: LiquidColor.indigo.opacity(0.78), etiqueta: "REM", duracion: "1:44"), // token-exempt: rampa graduada de etapas
            .init(minutos: 190, color: LiquidColor.indigo.opacity(0.52), etiqueta: "Ligero", duracion: "3:10"), // token-exempt: rampa graduada de etapas
            .init(minutos: 0, color: LiquidColor.oro, etiqueta: "Despierto", duracion: "0:00"),
        ],
        overline: "Anoche")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}

/// B7 · Caso degenerado: NINGUNA etapa medida. El componente no inventa nada (barra hueca,
/// leyenda vacía) — es responsabilidad del CALLER no pintar «Anoche» cuando no hubo noche.
#Preview("Liquid · StageBar (noche sin medir)") {
    LiquidStageBar(
        etapas: [
            .init(minutos: 0, color: LiquidColor.indigo, etiqueta: "Profundo", duracion: "0:00"),
            .init(minutos: 0, color: LiquidColor.indigo.opacity(0.78), etiqueta: "REM", duracion: "0:00"), // token-exempt: rampa graduada de etapas
            .init(minutos: 0, color: LiquidColor.indigo.opacity(0.52), etiqueta: "Ligero", duracion: "0:00"), // token-exempt: rampa graduada de etapas
            .init(minutos: 0, color: LiquidColor.oro, etiqueta: "Despierto", duracion: "0:00"),
        ],
        overline: "Anoche")
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
