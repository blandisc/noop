#if os(iOS)
import SwiftUI
import CenitDesign

// MARK: - Entrenar · CONSTANCIA del hub v18 (FER-171 · Parte B)
//
// «Constancia · 13 sem» + «N este mes» — la rejilla honesta de 13 columnas (semanas, vieja→actual) ×
// 3 huecos de sesión. Sesión = color de su familia; hueco vacío = «con cuerpo» (tinta 8 % + canto);
// HOY = borde de tinta sin fondo. Sin animación de tejido (constancia no teje, spec §3).

struct EntrenarHubConstancia: View {
    /// Una columna (una semana), vieja→actual — 13 elementos, cada uno con `constanciaSlotsPerWeek`
    /// huecos EXACTOS (el caller rellena a ese tope, nunca un arreglo más corto).
    struct Semana {
        /// Ronda 2 · G3: un hueco es o una SESIÓN (con o sin familia clasificable — «Rápido» no
        /// desaparece) o VACÍO (no hubo sesión ese lugar). Antes `EntrenarFamily?` colapsaba
        /// «sesión sin familia» y «sin sesión» en el mismo `nil` — la sesión sin familia se borraba
        /// de la rejilla.
        enum Hueco {
            case vacio
            case sesion(EntrenarFamily?)
        }
        let huecos: [Hueco]
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
                    Text("Consistency · 13 weeks").liquidRegla().foregroundStyle(LiquidColor.tinta500)
                    Spacer(minLength: LiquidSpace.s200)
                    // `Text.textCase(_:)` devuelve `some View`, no `Text` — rompe la concatenación `+`.
                    // Mayúsculas sobre el STRING ya resuelto (mismo patrón que `EntrenarHubSemana`).
                    (Text(verbatim: "\(sessionsThisMonth)")
                        .font(EntrenarHubMetrics.semValNumeral).tracking(EntrenarHubMetrics.semValTracking)
                     + Text(verbatim: " ")
                     + Text(verbatim: String(localized: "this month").uppercased())
                        .font(EntrenarHubMetrics.semValCalificativo).tracking(EntrenarHubMetrics.semValCalificativoTracking))
                        .foregroundStyle(LiquidColor.tinta900)
                }
                VStack(spacing: EntrenarHubMetrics.ghgridGap) {
                    ForEach(0..<3, id: \.self) { slot in
                        HStack(spacing: EntrenarHubMetrics.ghgridGap) {
                            ForEach(Array(semanas.enumerated()), id: \.offset) { week, semana in
                                celda(hueco: slot < semana.huecos.count ? semana.huecos[slot] : .vacio,
                                     esHoy: todaySlot?.week == week && todaySlot?.slot == slot)
                            }
                        }
                    }
                }
                .padding(.top, LiquidSpace.s200)
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
                .padding(.top, LiquidSpace.s100 + 2)
            }
        }
        .liquidEntrada(index: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Consistency · 13 weeks"))
        // Ronda 2 · G10: el value decía solo el número — VoiceOver perdía el calificativo «este mes»
        // que sí lee quien ve la pantalla.
        .accessibilityValue(Text("\(sessionsThisMonth) this month"))
    }

    private func celda(hueco: Semana.Hueco, esHoy: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: EntrenarHubMetrics.ghgridRadius, style: .continuous)
        return ZStack {
            if esHoy {
                shape.strokeBorder(LiquidColor.tinta900, lineWidth: EntrenarHubMetrics.ghgridHoyStroke)
            } else {
                switch hueco {
                case .sesion(let family?):
                    shape.fill(family.tono.base)
                case .sesion(nil):
                    // Ronda 2 · G3: sesión SIN familia clasificable — celda LLENA neutra (tinta500),
                    // nunca vacía (mismo respaldo que `EntrenarHubHistorial` con `family ?? tinta500`).
                    shape.fill(LiquidColor.tinta500)
                case .vacio:
                    shape.fill(LiquidColor.tinta900.opacity(EntrenarHubMetrics.ghgridEmptyAlfa))
                        .overlay { shape.strokeBorder(LiquidColor.tinta900.opacity(EntrenarHubMetrics.ghgridCantoAlfa), lineWidth: 0.5) }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
}
#endif
