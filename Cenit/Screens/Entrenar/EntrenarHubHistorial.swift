#if os(iOS)
import SwiftUI
import CenitDesign

// MARK: - Entrenar · HISTORIAL del hub v18 (FER-171 · Parte B)
//
// «Historial ›» + hasta 2 filas de sesión (bead de familia · título · «jue 13 · 41 min · 3,640 kg») +
// la línea de hueco cuando hay días sin registrar entre las dos, cerrando con «Promedio · 7 días»
// (silencio con menos de 3 sesiones en la ventana).

struct EntrenarHubHistorial: View {
    struct Fila: Identifiable {
        let id: String
        let family: EntrenarFamily?
        let title: String
        let subtitle: String
        let action: () -> Void
    }

    let filas: [Fila]
    /// Días sin registrar ENTRE las dos filas (0 = sin hueco, no se muestra la línea).
    let gapDays: Int
    let promedio: (minutes: Int, kcal: Int?, tons: Double)?
    let onOpenHistory: () -> Void

    /// Ronda 2 · D2: `historialTitulo`/`historialSubtitulo` eran `Font.system(size:)` fijo — texto de
    /// LECTURA sin escalar.
    @ScaledMetric(relativeTo: .subheadline) private var historialTituloSize = EntrenarHubMetrics.historialTituloBase
    @ScaledMetric(relativeTo: .caption2) private var historialSubtituloSize = EntrenarHubMetrics.historialSubtituloBase

    var body: some View {
        EntrenarModulo(tono: .neutro) {
            VStack(alignment: .leading, spacing: .zero) {
                Button(action: onOpenHistory) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("History").liquidRegla().foregroundStyle(LiquidColor.tinta500)
                        Spacer(minLength: LiquidSpace.s200)
                        CenitIcon.disclosure.image
                            .font(LiquidType.iconSF(size: 15).weight(.semibold))
                            .foregroundStyle(LiquidColor.tinta500)
                    }
                    .frame(minHeight: EntrenarMetrics.row)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.liquidPress)
                ForEach(Array(filas.enumerated()), id: \.element.id) { i, fila in
                    filaRow(fila)
                    if i == 0, gapDays > 0 {
                        // Ronda 2 · O1: prefijo «· · » — mock línea 349. Piezas separadas para no
                        // tocar las claves YA traducidas («1 day not logged» / «%lld days not logged»).
                        (Text(verbatim: "· · ")
                         + Text(gapDays == 1 ? "1 day not logged" : "\(gapDays) days not logged"))
                            .entrenarHub9Label().foregroundStyle(LiquidColor.tinta500)
                            .padding(.leading, EntrenarHubMetrics.historialHuecoIndent)
                    }
                }
                if let promedio {
                    piePromedio(promedio)
                }
            }
        }
        .liquidEntrada(index: 7)
    }

    private func filaRow(_ fila: Fila) -> some View {
        Button(action: fila.action) {
            HStack(spacing: EntrenarHubMetrics.historialFilaGap) {
                Circle()
                    .fill(fila.family?.tono.base ?? LiquidColor.tinta500)
                    .frame(width: EntrenarMetrics.familyDot, height: EntrenarMetrics.familyDot)
                VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                    Text(verbatim: fila.title).font(.system(size: historialTituloSize, weight: .semibold))
                        .foregroundStyle(LiquidColor.tinta900)
                    Text(verbatim: fila.subtitle).font(.system(size: historialSubtituloSize))
                        .foregroundStyle(LiquidColor.tinta500)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, EntrenarHubMetrics.historialFilaPaddingV)
            .frame(minHeight: EntrenarMetrics.row, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .combine)
    }

    private func piePromedio(_ p: (minutes: Int, kcal: Int?, tons: Double)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: EntrenarHubMetrics.historialPromGap) {
            Text("Average · 7 days").entrenarHub9Label().foregroundStyle(LiquidColor.tinta500)
            promValor("\(p.minutes)", unit: "min")
            if let kcal = p.kcal { promValor("\(kcal)", unit: "kcal") }
            promValor(String(format: "%.1f", p.tons), unit: "t")
        }
        .padding(.top, EntrenarHubMetrics.historialPromPaddingTop)
        .padding(.bottom, EntrenarHubMetrics.historialPromPaddingBottom)
        .overlay(alignment: .top) {
            Rectangle().fill(LiquidColor.tinta7).frame(height: 1)
        }
        .padding(.top, EntrenarHubMetrics.historialPromTop)
        .accessibilityElement(children: .combine)
    }

    private func promValor(_ value: String, unit: String) -> some View {
        (Text(verbatim: value).font(EntrenarHubMetrics.promedioNumeral)
         + Text(verbatim: " ")
         + Text(verbatim: unit).font(EntrenarHubMetrics.historialPromUnidad))
            .foregroundStyle(LiquidColor.tinta700)
    }
}
#endif
