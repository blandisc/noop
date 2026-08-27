#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Entrenar · EL PAR DEL DÍA del hub v18 (FER-171 · Parte B)
//
// «Subidas listas» (verde) + «Descanso real» (neutro), lado a lado. Silencio del par (regla del
// diseño, mock §orden): si una tile calla, la otra toma el ancho completo; si ambas callan, el par
// no se muestra. Hoy «Descanso real» SIEMPRE calla — `restReal` no tiene fuente de datos todavía
// (F2 la trae) — así que el par hoy es, en la práctica, «Subidas listas a lo ancho o nada».

struct EntrenarHubPar: View {
    struct Subida: Identifiable { let id: String; let name: String; let deltaText: String }

    let raises: [Subida]
    /// Cablea la tile a futuro (F2): hoy SIEMPRE `nil`, así que «Descanso real» calla siempre.
    let restReal: (real: Int, planS: Int)?
    let onOpenRaises: () -> Void

    private var hasRaises: Bool { !raises.isEmpty }
    private var hasRest: Bool { restReal != nil }

    var body: some View {
        if hasRaises || hasRest {
            Group {
                if hasRaises, hasRest {
                    HStack(alignment: .top, spacing: CenitMetrics.gap) { subidasTile; descansoTile }
                } else if hasRaises {
                    subidasTile
                } else {
                    descansoTile
                }
            }
            .liquidEntrada(index: 3)
        }
    }

    // MARK: - Subidas listas

    private var subidasTile: some View {
        EntrenarTile(tono: .verde) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ready raises").liquidRegla().foregroundStyle(EntrenarTono.verde.rotulo)
                HStack(alignment: .firstTextBaseline, spacing: EntrenarHubMetrics.numRowGap) {
                    Text(verbatim: "\(raises.count)")
                        .font(LiquidType.valorTileM).tracking(LiquidType.valorTileTracking)
                        .foregroundStyle(LiquidColor.verdeProfundo)
                    EntrenarMiniBarras(alturas: [0.5, 0.75, 1.0], tono: .verde)
                }
                .padding(.top, EntrenarHubMetrics.numRowTop)
                VStack(alignment: .leading, spacing: EntrenarHubMetrics.subLsGap) {
                    ForEach(raises.prefix(3)) { subida in
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: subida.name).font(EntrenarHubMetrics.subLsFila)
                                .foregroundStyle(LiquidColor.tinta700)
                            Spacer(minLength: CenitMetrics.space2)
                            (Text(verbatim: "▲").font(EntrenarHubMetrics.subLsGlifo)
                             + Text(verbatim: " ") + Text(verbatim: subida.deltaText))
                                .font(EntrenarHubMetrics.subLsDelta)
                                .foregroundStyle(LiquidColor.verdeProfundo)
                        }
                    }
                }
                .padding(.top, EntrenarHubMetrics.subLsTop)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenRaises)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens today's routine"))
    }

    // MARK: - Descanso real (F2 — hoy siempre en silencio)

    private var descansoTile: some View {
        EntrenarTile(tono: .neutro) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Real rest").liquidRegla().foregroundStyle(LiquidColor.tinta500)
                if let restReal {
                    Text(verbatim: Self.mmss(restReal.real))
                        .font(LiquidType.valorTileM).tracking(LiquidType.valorTileTracking)
                        .foregroundStyle(LiquidColor.tinta900)
                        .padding(.top, EntrenarHubMetrics.numRowTop)
                    restTrack(real: restReal.real, planS: restReal.planS)
                        .padding(.top, EntrenarHubMetrics.restTrackTop)
                    (Text("your average").foregroundStyle(LiquidColor.tinta700)
                     + Text(verbatim: " · ").foregroundStyle(LiquidColor.tinta700)
                     + Text("the plan calls for").foregroundStyle(LiquidColor.tinta700)
                     + Text(verbatim: " ")
                     + Text(verbatim: Self.mmss(restReal.planS)).fontWeight(.semibold).foregroundStyle(LiquidColor.tinta900))
                        .font(EntrenarHubMetrics.restClausula)
                        .lineSpacing(EntrenarHubMetrics.restClausulaLineSpacing)
                        .padding(.top, EntrenarHubMetrics.subLsTop)
                }
            }
        }
    }

    private func restTrack(real: Int, planS: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LiquidColor.tinta900.opacity(EntrenarHubMetrics.vbarsEmptyAlfa))
                Capsule().fill(LiquidColor.cian.opacity(EntrenarHubMetrics.restFillAlfa))
                    .frame(width: geo.size.width * min(1, planS > 0 ? Double(real) / Double(planS) : 1))
                Rectangle().fill(LiquidColor.tinta900.opacity(EntrenarHubMetrics.restPlanTickAlfa))
                    .frame(width: EntrenarHubMetrics.restPlanTickWidth)
                    .position(x: geo.size.width - EntrenarHubMetrics.restPlanTickWidth / 2, y: geo.size.height / 2)
            }
        }
        .frame(height: EntrenarHubMetrics.restTrackHeight)
        .clipShape(Capsule())
    }

    private static func mmss(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
#endif
