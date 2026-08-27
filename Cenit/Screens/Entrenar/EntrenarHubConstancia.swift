#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Entrenar · CONSTANCIA del hub v18 (FER-171 · Parte B)
//
// «Constancia · 12 sem» + «N este mes» — la rejilla honesta de 13 columnas (semanas, vieja→actual) ×
// 3 huecos de sesión. Sesión = color de su familia; hueco vacío = «con cuerpo» (tinta 8 % + canto);
// HOY = borde de tinta sin fondo. Sin animación de tejido (constancia no teje, spec §3).

struct EntrenarHubConstancia: View {
    /// Una columna (una semana), vieja→actual — 13 elementos, cada uno hasta 3 huecos.
    struct Semana {
        /// `nil` = hueco vacío ese slot; `.some(nil)` no existe: cada hueco es familia conocida o vacío.
        let huecos: [EntrenarFamily?]
        let isCurrent: Bool
    }

    let semanas: [Semana]
    let sessionsThisMonth: Int
    /// Etiquetas de mes bajo la rejilla, columna → texto («jun»/«jul»/«ago»).
    let monthLabels: [Int: String]
    /// Índice (semana, hueco) de la celda de HOY, si hoy ya tiene una sesión en esa columna reservada
    /// visualmente — `nil` cuando hoy cae en un hueco vacío de la última columna (el caso normal: hoy
    /// no ha entrenado todavía) y no hay una celda «hoy» dedicada que resaltar más allá del vacío.
    let todaySlot: (week: Int, slot: Int)?

    var body: some View {
        EntrenarModulo(tono: .neutro) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Consistency · 12 weeks").liquidRegla().foregroundStyle(LiquidColor.tinta500)
                    Spacer(minLength: CenitMetrics.space2)
                    (Text(verbatim: "\(sessionsThisMonth)")
                        .font(EntrenarHubMetrics.semValNumeral).tracking(EntrenarHubMetrics.semValTracking)
                     + Text(verbatim: " ")
                     + Text("this month")
                        .font(EntrenarHubMetrics.semValCalificativo).tracking(EntrenarHubMetrics.semValCalificativoTracking)
                        .textCase(.uppercase))
                        .foregroundStyle(LiquidColor.tinta900)
                }
                VStack(spacing: EntrenarHubMetrics.ghgridGap) {
                    ForEach(0..<3, id: \.self) { slot in
                        HStack(spacing: EntrenarHubMetrics.ghgridGap) {
                            ForEach(Array(semanas.enumerated()), id: \.offset) { week, semana in
                                celda(family: semana.huecos[safe: slot] ?? nil,
                                     esHoy: todaySlot?.week == week && todaySlot?.slot == slot)
                            }
                        }
                    }
                }
                .padding(.top, CenitMetrics.space2)
                // Repartidos a lo ancho, no clavados bajo su columna real (mock `.ghlabs{display:flex;
                // justify-content:space-between}` — la misma distribución que `WorkoutHistoryScreen`
                // ya usa para sus rótulos de mes).
                let sortedLabels = monthLabels.sorted { $0.key < $1.key }
                HStack {
                    ForEach(Array(sortedLabels.enumerated()), id: \.offset) { i, entry in
                        Text(verbatim: entry.value).entrenarHub9Label().foregroundStyle(LiquidColor.tinta500)
                        if i < sortedLabels.count - 1 { Spacer(minLength: 0) }
                    }
                }
                .padding(.top, CenitMetrics.space1 + 2)
            }
        }
        .liquidEntrada(index: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Consistency · 12 weeks"))
        .accessibilityValue(Text(verbatim: "\(sessionsThisMonth)"))
    }

    private func celda(family: EntrenarFamily?, esHoy: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: EntrenarHubMetrics.ghgridRadius, style: .continuous)
        return ZStack {
            if esHoy {
                shape.strokeBorder(LiquidColor.tinta900, lineWidth: EntrenarHubMetrics.ghgridHoyStroke)
            } else if let family {
                shape.fill(family.tono.base)
            } else {
                shape.fill(LiquidColor.tinta900.opacity(EntrenarHubMetrics.ghgridEmptyAlfa))
                    .overlay { shape.strokeBorder(LiquidColor.tinta900.opacity(EntrenarHubMetrics.ghgridCantoAlfa), lineWidth: 0.5) }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
