import SwiftUI

// MARK: - EntrenarFilaCardio — fila de actividad Apple Health / manual (FER-202)
//
// Hermana simétrica de `EntrenarFilaFuerza` (mismo esqueleto: glifo 38 · título+meta · dato
// derecho) con asimetría deliberada: SF Symbol NEUTRO del deporte (`inkSecondary` — Cénit no
// tiñe lo que no mide) + chip de origen (`SourceBadge` Apple/Manual) + dato = FC media o
// duración (NUNCA esfuerzo/21: la escala de cardio puede no ser la misma). No reusa
// `TarjetaSesion` (queda huérfana al retirar WorkoutsView).

public struct EntrenarFilaCardio: View {
    /// Origen de la actividad — tiñe el `SourceBadge`.
    public enum Origen: Sendable, Hashable {
        case apple
        case manual
    }

    /// Dato derecho ya resuelto (FC media, duración, …).
    public struct Dato: Sendable {
        public let valor: String
        public let unidad: String
        public let tono: Color

        public init(valor: String, unidad: String, tono: Color) {
            self.valor = valor
            self.unidad = unidad
            self.tono = tono
        }
    }

    private let sfSymbol: String
    private let deporte: String
    private let origen: Origen
    private let meta: String
    private let dato: Dato
    private let onTap: () -> Void

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - sfSymbol: nombre SF Symbol del deporte (`figure.run`, `dumbbell.fill`, …).
    ///   - deporte: ya localizado («Correr», «Ciclismo»).
    ///   - origen: `.apple` → badge «Apple» en tinte origen; `.manual` → «Manual» en tinta.
    ///   - meta: ya formateada («mié 8 jul · 30 min · 5,2 km»).
    ///   - dato: valor + unidad + tono (rosa AA para FC, tinta para duración).
    ///   - onTap: navegación al detalle Apple/manual.
    public init(sfSymbol: String, deporte: String, origen: Origen,
                meta: String, dato: Dato, onTap: @escaping () -> Void) {
        self.sfSymbol = sfSymbol
        self.deporte = deporte
        self.origen = origen
        self.meta = meta
        self.dato = dato
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            Group {
                if typeSize.isAccessibilitySize {
                    filaAccesible
                } else {
                    filaCompacta
                }
            }
            .padding(.vertical, LiquidSpace.s225)
            .frame(maxWidth: .infinity, minHeight: EntrenarMetrics.row, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: Layouts

    private var filaCompacta: some View {
        HStack(spacing: CenitMetrics.gap) {
            glifo
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                HStack(spacing: CenitMetrics.space1) {
                    deporteText.lineLimit(1).minimumScaleFactor(0.8)
                    origenBadge
                }
                metaText.lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: CenitMetrics.space2)
            datoDerecho
        }
    }

    /// AX5: el dato baja bajo el título; la meta envuelve — la fila no se corta.
    private var filaAccesible: some View {
        HStack(alignment: .top, spacing: CenitMetrics.gap) {
            glifo
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                HStack(spacing: CenitMetrics.space1) {
                    deporteText.fixedSize(horizontal: false, vertical: true)
                    origenBadge
                }
                metaText.fixedSize(horizontal: false, vertical: true)
                datoDerecho
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Piezas

    private var glifo: some View {
        Image(systemName: sfSymbol)
            .font(.system(size: Metrics.symbolSize, weight: .regular))
            .foregroundStyle(theme.inkSecondary)
            .frame(width: Metrics.chip, height: Metrics.chip)
            .background(theme.patternBlock,
                        in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    private var deporteText: some View {
        Text(verbatim: deporte)
            .font(StrandFont.subhead).fontWeight(.semibold)
            .foregroundStyle(theme.ink)
    }

    private var metaText: some View {
        Text(verbatim: meta)
            .font(StrandFont.caption)
            .foregroundStyle(theme.inkTertiary)
    }

    private var origenBadge: some View {
        switch origen {
        case .apple:
            SourceBadge("Apple", tint: theme.originApple)
        case .manual:
            SourceBadge("Manual", tint: theme.inkTertiary)
        }
    }

    private var datoDerecho: some View {
        (Text(verbatim: dato.valor)
            .font(InstrumentoType.grotesk(13, weight: .bold))
            .foregroundStyle(dato.tono)
         + Text(verbatim: " \(dato.unidad)")
            .font(StrandFont.caption)
            .foregroundStyle(theme.inkTertiary))
    }

    private var a11yLabel: Text {
        let origenTxt: LocalizedStringKey = origen == .apple ? "Apple" : "Manual"
        return Text(verbatim: "\(deporte). ")
            + Text(origenTxt)
            + Text(verbatim: ". \(meta). \(dato.valor) \(dato.unidad)")
    }
}

private enum Metrics {
    static let chip: CGFloat = 38
    static let symbolSize: CGFloat = 18
}

#if DEBUG
private enum EntrenarFilaCardioPreviewData {
    static let rosaLectura = OKLab.darkened(InstrumentoTheme.base.dataHeart,
                                            toContrast: 4.5,
                                            against: InstrumentoTheme.base.paper)
}

#Preview("EntrenarFilaCardio · Apple + FC") {
    EntrenarFilaCardio(
        sfSymbol: "figure.run", deporte: "Correr", origen: .apple,
        meta: "mié 8 jul · 30 min · 5,2 km",
        dato: .init(valor: "148", unidad: "bpm", tono: EntrenarFilaCardioPreviewData.rosaLectura),
        onTap: {})
        .padding(.horizontal, LiquidSpace.s400)
        .background(LiquidColor.fondoGradient)
        .instrumentoTheme(.base)
}

#Preview("EntrenarFilaCardio · Manual + duración") {
    EntrenarFilaCardio(
        sfSymbol: "figure.outdoor.cycle", deporte: "Ciclismo", origen: .manual,
        meta: "mar 7 jul · 45 min",
        dato: .init(valor: "45", unidad: "min", tono: InstrumentoTheme.base.inkSecondary),
        onTap: {})
        .padding(.horizontal, LiquidSpace.s400)
        .background(LiquidColor.fondoGradient)
        .instrumentoTheme(.base)
}

#Preview("EntrenarFilaCardio · Apple fuerza-like (no rica)") {
    EntrenarFilaCardio(
        sfSymbol: "dumbbell.fill", deporte: "Fuerza", origen: .apple,
        meta: "jue 9 jul · 38 min",
        dato: .init(valor: "132", unidad: "bpm", tono: EntrenarFilaCardioPreviewData.rosaLectura),
        onTap: {})
        .padding(.horizontal, LiquidSpace.s400)
        .background(LiquidColor.fondoGradient)
        .instrumentoTheme(.base)
}

#Preview("EntrenarFilaCardio · AX5") {
    EntrenarFilaCardio(
        sfSymbol: "figure.run", deporte: "Correr", origen: .apple,
        meta: "mié 8 jul · 30 min · 5,2 km",
        dato: .init(valor: "148", unidad: "bpm", tono: EntrenarFilaCardioPreviewData.rosaLectura),
        onTap: {})
        .padding(.horizontal, LiquidSpace.s400)
        .background(LiquidColor.fondoGradient)
        .instrumentoTheme(.base)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
