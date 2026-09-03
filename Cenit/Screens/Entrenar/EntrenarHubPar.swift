#if os(iOS)
import SwiftUI
import CenitDesign

// MARK: - Entrenar · EL PAR DEL DÍA del hub v18 (FER-171 · Parte B)
//
// «Subidas listas» (verde) + «Descanso real» (neutro), lado a lado. Silencio del par (regla del
// diseño, mock §orden): si una tile calla, la otra toma el ancho completo; si ambas callan, el par
// no se muestra. Hoy «Descanso real» SIEMPRE calla — `restReal` no tiene fuente de datos todavía
// (F2 la trae) — así que el par hoy es, en la práctica, «Subidas listas a lo ancho o nada».

struct EntrenarHubPar: View {
    /// Ronda 2 · D1: `valueText` es el ESCALÓN (`toKg − fromKg`) cuando `isStep` — el mock (`.subLs`,
    /// «▲ 2.5 kg») pide el salto, no el peso nuevo. Sin escalón real (primera vez, o `toKg ≤ fromKg`)
    /// `isStep` es `false` y `valueText` es el peso nuevo, SIN «▲» (el arreglo lo pinta solo el caller).
    struct Subida: Identifiable {
        let id: String
        let name: String
        let valueText: String
        let isStep: Bool
    }

    let raises: [Subida]
    /// Cablea la tile a futuro (F2): hoy SIEMPRE `nil`, así que «Descanso real» calla siempre.
    let restReal: (real: Int, planS: Int)?
    let onOpenRaises: () -> Void

    /// Ronda 2 · D2: `subLsFila`/`restClausula` eran `Font.system(size:)` fijo — texto de LECTURA que
    /// no escalaba con Dynamic Type. `@ScaledMetric` vive en la vista (el `enum` de tokens no tiene
    /// entorno); la base sigue viniendo de `EntrenarHubMetrics`.
    @ScaledMetric(relativeTo: .caption2) private var subLsFilaSize = EntrenarHubMetrics.subLsFilaBase
    @ScaledMetric(relativeTo: .caption2) private var restClausulaSize = EntrenarHubMetrics.restClausulaBase

    private var hasRaises: Bool { !raises.isEmpty }
    private var hasRest: Bool { restReal != nil }

    var body: some View {
        if hasRaises || hasRest {
            Group {
                if hasRaises, hasRest {
                    HStack(alignment: .top, spacing: LiquidSpace.s300) { subidasTile; descansoTile }
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
        // Ronda 2 · G8: `.onTapGesture` + combine no trae el rasgo de botón para VoiceOver — un
        // `Button` de verdad, mismo patrón que la píldora del héroe (`EntrenarHubHeroe.subPill`).
        Button(action: onOpenRaises) {
            EntrenarTile(tono: .verde) {
                VStack(alignment: .leading, spacing: .zero) {
                    Text("Ready raises").liquidRegla().foregroundStyle(LiquidTono.verde.rotulo)
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
                                Text(verbatim: subida.name).font(.system(size: subLsFilaSize))
                                    .foregroundStyle(LiquidColor.tinta700)
                                Spacer(minLength: LiquidSpace.s200)
                                subidaValor(subida)
                            }
                        }
                    }
                    .padding(.top, EntrenarHubMetrics.subLsTop)
                }
            }
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens today's routine"))
    }

    @ViewBuilder
    private func subidaValor(_ subida: Subida) -> some View {
        if subida.isStep {
            (Text(verbatim: "▲").font(EntrenarHubMetrics.subLsGlifo)
             + Text(verbatim: " ") + Text(verbatim: subida.valueText))
                .font(EntrenarHubMetrics.subLsDelta)
                .foregroundStyle(LiquidColor.verdeProfundo)
        } else {
            Text(verbatim: subida.valueText)
                .font(EntrenarHubMetrics.subLsDelta)
                .foregroundStyle(LiquidColor.verdeProfundo)
        }
    }

    // MARK: - Descanso real (F2 — hoy siempre en silencio)

    private var descansoTile: some View {
        EntrenarTile(tono: .neutro) {
            VStack(alignment: .leading, spacing: .zero) {
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
                        .font(.system(size: restClausulaSize))
                        .lineSpacing(EntrenarHubMetrics.restClausulaLineSpacing)
                        .padding(.top, EntrenarHubMetrics.subLsTop)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func restTrack(real: Int, planS: Int) -> some View {
        LiquidBarraProgreso(
            fraccion: min(1, planS > 0 ? Double(real) / Double(planS) : 1),
            tono: LiquidColor.cian.opacity(EntrenarHubMetrics.restFillAlfa),
            pista: LiquidColor.tinta900.opacity(EntrenarHubMetrics.vbarsEmptyAlfa),
            altura: EntrenarHubMetrics.restTrackHeight,
            animada: false)
            .overlay {
                GeometryReader { geo in
                    Rectangle().fill(LiquidColor.tinta900.opacity(EntrenarHubMetrics.restPlanTickAlfa))
                        .frame(width: EntrenarHubMetrics.restPlanTickWidth)
                        .position(x: geo.size.width - EntrenarHubMetrics.restPlanTickWidth / 2,
                                  y: geo.size.height / 2)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(Capsule())
    }

    private static func mmss(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
#endif
