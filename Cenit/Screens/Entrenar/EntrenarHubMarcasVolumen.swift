#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Entrenar · MARCAS + VOLUMEN del hub v18 (FER-171 · Parte B)
//
// El par «Marcas · N en {mes}» (rosa, el último PR) + «Volumen · 8 sem» (ámbar, toneladas de la
// semana). Silencio independiente por tile (mock: sin PRs, MARCAS calla y VOLUMEN toma el ancho;
// <3 sesiones en 8 semanas, VOLUMEN calla). Si las dos callan, el par no se muestra.

struct EntrenarHubMarcasVolumen: View {
    struct Marca {
        let countThisMonth: Int
        let monthLabel: String        // «ago», ya en minúsculas — el `.uppercased()` lo pone la regla
        let valueText: String         // «102.5»
        let unitText: String?         // «kg» — nil para maxReps (el valor ya es un conteo sin unidad)
        let exerciseAndMetric: String // «Sentadilla · Peso máximo»
        let previousText: String?     // «antes 100.0 · hace 2 días» — nil sin PR anterior
    }
    struct Volumen {
        let tons: Double
        let deltaPercent: Int?
        /// 8 alturas 0…1 (la última = semana actual), ya recortadas.
        let bars: [Double]
    }

    let marca: Marca?
    let volumen: Volumen?

    private var hasMarca: Bool { marca != nil }
    private var hasVolumen: Bool { volumen != nil }

    var body: some View {
        if hasMarca || hasVolumen {
            HStack(alignment: .top, spacing: CenitMetrics.gap) {
                if let marca { marcaTile(marca) }
                if let volumen { volumenTile(volumen) }
            }
            .liquidEntrada(index: 5)
        }
    }

    // MARK: - Marcas (rosa)

    private func marcaTile(_ m: Marca) -> some View {
        EntrenarTile(tono: .rosa) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Marks · \(m.countThisMonth) in \(m.monthLabel)")
                    .liquidRegla().foregroundStyle(EntrenarTono.rosa.rotulo)
                HStack(alignment: .firstTextBaseline, spacing: EntrenarHubMetrics.numRowGap) {
                    Text(verbatim: m.valueText)
                        .font(LiquidType.valorTileM).tracking(LiquidType.valorTileTracking)
                        .foregroundStyle(LiquidColor.rosa)
                    if let unitText = m.unitText {
                        Text(verbatim: unitText).font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
                    }
                    Spacer(minLength: CenitMetrics.space1)
                    EntrenarMiniBarras(alturas: [0.625, 1.0], tono: .rosa)
                }
                .padding(.top, EntrenarHubMetrics.numRowTop)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: m.exerciseAndMetric).font(EntrenarHubMetrics.marcasUlt)
                        .foregroundStyle(LiquidColor.tinta700)
                    if let previousText = m.previousText {
                        Text(verbatim: previousText).font(EntrenarHubMetrics.marcasPrev)
                            .foregroundStyle(LiquidColor.tinta500)
                    }
                }
                .padding(.top, EntrenarHubMetrics.marcasUltTop)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Volumen (ámbar)

    private func volumenTile(_ v: Volumen) -> some View {
        EntrenarTile(tono: .ambar) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Volume · 8 weeks").liquidRegla().foregroundStyle(EntrenarTono.ambar.rotulo)
                HStack(alignment: .firstTextBaseline, spacing: EntrenarHubMetrics.numRowGap) {
                    Text(verbatim: Self.oneDecimal(v.tons))
                        .font(LiquidType.valorTileM).tracking(LiquidType.valorTileTracking)
                        .foregroundStyle(LiquidColor.ambar)
                    Text(verbatim: "t").font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
                    if let deltaPercent = v.deltaPercent {
                        Spacer(minLength: CenitMetrics.space1)
                        Text(verbatim: "↗ \(deltaPercent >= 0 ? "+" : "")\(deltaPercent) %")
                            .font(EntrenarHubMetrics.volumenDelta).foregroundStyle(LiquidColor.verdeProfundo)
                    }
                }
                .padding(.top, EntrenarHubMetrics.numRowTop)
                HStack(alignment: .bottom, spacing: EntrenarHubMetrics.vbarsGap) {
                    ForEach(Array(v.bars.enumerated()), id: \.offset) { i, h in
                        let esActual = i == v.bars.count - 1
                        RoundedRectangle(cornerRadius: EntrenarHubMetrics.vbarsRadius, style: .continuous)
                            .fill(esActual ? AnyShapeStyle(LiquidColor.ambar)
                                          : AnyShapeStyle(LiquidColor.tinta900.opacity(EntrenarHubMetrics.vbarsEmptyAlfa)))
                            .overlay {
                                if !esActual {
                                    RoundedRectangle(cornerRadius: EntrenarHubMetrics.vbarsRadius, style: .continuous)
                                        .strokeBorder(LiquidColor.tinta900.opacity(EntrenarHubMetrics.vbarsCantoAlfa), lineWidth: 0.5)
                                }
                            }
                            .frame(height: max(2, EntrenarHubMetrics.vbarsHeight * min(1, max(0, h))))
                    }
                }
                .frame(height: EntrenarHubMetrics.vbarsHeight, alignment: .bottom)
                .padding(.top, EntrenarHubMetrics.numRowTop)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }
}
#endif
