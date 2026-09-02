#if os(iOS)
import SwiftUI
import CenitDesign

// MARK: - Entrenar · MARCAS + VOLUMEN del hub v18 (FER-171 · Parte B)
//
// El par «Marcas · N en {mes}» (rosa, el último PR) + «Volumen · 8 sem» (ámbar, toneladas de la
// semana). Silencio independiente por tile (mock: sin PRs, MARCAS calla y VOLUMEN toma el ancho;
// <3 sesiones en 8 semanas, VOLUMEN calla). Si las dos callan, el par no se muestra.

struct EntrenarHubMarcasVolumen: View {
    struct Marca {
        /// Ronda 2 · O2: `nil` cuando el conteo del mes es 0 — la regla dice solo «MARCAS» (el PR
        /// vigente puede ser de un mes anterior; «· 0 en {mes}» sería una mentira honesta pero rara).
        let countThisMonth: Int?
        let monthLabel: String        // «ago», ya en minúsculas — el `.uppercased()` lo pone la regla
        let valueText: String         // «102.5»
        let unitText: String?         // «kg» — nil para maxReps (el valor ya es un conteo sin unidad)
        let exerciseAndMetric: String // «Sentadilla · peso máx»
        let previousText: String?     // «antes 100.0 · hace 2 días» — nil sin PR anterior
    }
    struct Volumen {
        let tons: Double
        let deltaPercent: Int?
        /// 8 alturas 0…1, ya recortadas.
        let bars: [Double]
        /// Ronda 2 · G5: qué barra acentuar (ámbar) — la de la semana que describen `tons`/
        /// `deltaPercent`, no siempre la última (con 0 sesiones esta semana, la semana activa es la
        /// última CON sesiones).
        let accentIndex: Int
    }

    let marca: Marca?
    let volumen: Volumen?

    /// Ronda 2 · D2: `marcasUlt`/`marcasPrev` eran `Font.system(size:)` fijo — texto de LECTURA sin
    /// escalar. `@ScaledMetric` vive en la vista; la base sigue en `EntrenarHubMetrics`.
    @ScaledMetric(relativeTo: .caption2) private var marcasUltSize = EntrenarHubMetrics.marcasUltBase
    @ScaledMetric(relativeTo: .caption2) private var marcasPrevSize = EntrenarHubMetrics.marcasPrevBase

    private var hasMarca: Bool { marca != nil }
    private var hasVolumen: Bool { volumen != nil }

    var body: some View {
        if hasMarca || hasVolumen {
            HStack(alignment: .top, spacing: LiquidSpace.s300) {
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
                marcaRegla(m).liquidRegla().foregroundStyle(LiquidTono.rosa.rotulo)
                HStack(alignment: .firstTextBaseline, spacing: EntrenarHubMetrics.numRowGap) {
                    Text(verbatim: m.valueText)
                        .font(LiquidType.valorTileM).tracking(LiquidType.valorTileTracking)
                        .foregroundStyle(LiquidColor.rosa)
                    if let unitText = m.unitText {
                        Text(verbatim: unitText).font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
                    }
                    Spacer(minLength: LiquidSpace.s100)
                    EntrenarMiniBarras(alturas: [0.625, 1.0], tono: .rosa)
                }
                .padding(.top, EntrenarHubMetrics.numRowTop)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: m.exerciseAndMetric).font(.system(size: marcasUltSize))
                        .foregroundStyle(LiquidColor.tinta700)
                    if let previousText = m.previousText {
                        Text(verbatim: previousText).font(.system(size: marcasPrevSize))
                            .foregroundStyle(LiquidColor.tinta500)
                    }
                }
                .padding(.top, EntrenarHubMetrics.marcasUltTop)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// «MARCAS · N EN AGO», o solo «MARCAS» cuando `countThisMonth` es `nil` (Ronda 2 · O2).
    private func marcaRegla(_ m: Marca) -> Text {
        guard let count = m.countThisMonth else { return Text("Marks") }
        return Text("Marks · \(count) in \(m.monthLabel)")
    }

    // MARK: - Volumen (ámbar)

    private func volumenTile(_ v: Volumen) -> some View {
        EntrenarTile(tono: .ambar) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Volume · 8 weeks").liquidRegla().foregroundStyle(LiquidTono.ambar.rotulo)
                HStack(alignment: .firstTextBaseline, spacing: EntrenarHubMetrics.numRowGap) {
                    Text(verbatim: Self.oneDecimal(v.tons))
                        .font(LiquidType.valorTileM).tracking(LiquidType.valorTileTracking)
                        .foregroundStyle(LiquidColor.ambar)
                    Text(verbatim: "t").font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
                    if let deltaPercent = v.deltaPercent, deltaPercent != 0 {
                        Spacer(minLength: LiquidSpace.s100)
                        deltaText(deltaPercent)
                    }
                }
                .padding(.top, EntrenarHubMetrics.numRowTop)
                HStack(alignment: .bottom, spacing: EntrenarHubMetrics.vbarsGap) {
                    ForEach(Array(v.bars.enumerated()), id: \.offset) { i, h in
                        let esActual = i == v.accentIndex
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

    /// Ronda 2 · D4: positivo → «↗» verde (como hoy); negativo → «↘» tinta700 — NUNCA rojo, bajar
    /// volumen no es un error, es una semana más ligera. El cero ya se filtra en el caller (sin
    /// flecha, sin signo). Sin «+» duplicado: `deltaPercent` ya trae su propio signo si es negativo.
    private func deltaText(_ deltaPercent: Int) -> some View {
        let positivo = deltaPercent > 0
        let flecha = positivo ? "↗" : "↘"
        let numero = positivo ? "+\(deltaPercent)" : "\(deltaPercent)"
        return Text(verbatim: "\(flecha) \(numero) %")
            .font(EntrenarHubMetrics.volumenDelta)
            .foregroundStyle(positivo ? LiquidColor.verdeProfundo : LiquidColor.tinta700)
    }

    private static func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }
}
#endif
