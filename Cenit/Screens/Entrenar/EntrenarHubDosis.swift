#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Entrenar · DOSIS del hub v18 (FER-171 · Parte B)
//
// «Series por músculo · 7 días»: hasta 4 filas (rótulo de 3 letras · riel · numeral de series), cian
// oscuro. Silencio si hay menos de 3 sesiones en 7 días (`EntrenarLanding` decide eso antes de
// construir `rows`; este componente solo pinta lo que recibe — vacío ⇒ `EmptyView`).
//
// Ronda 2 · G7: el numeral usa `MuscleFatigueMap.formattedSets` (Int(sets.rounded()) se tragaba el
// .5 de una serie secundaria — «7» en vez de «7.5»), el MISMO formateo que ya usa el mapa muscular.

struct EntrenarHubDosis: View {
    struct Fila: Identifiable {
        let id: String          // catalog muscle key
        let label3: String      // «PEC», «ESP»…
        let sets: Double
        /// Fracción 0…1 del riel, ya recortada a 100 % (`sets / MuscleFatigueMap.weeklyBandHigh`).
        let fraction: Double
        /// `true` cuando `band == .below` (mock `.fill.low`, cian atenuado).
        let low: Bool
    }

    let rows: [Fila]

    var body: some View {
        if !rows.isEmpty {
            EntrenarModulo(tono: .cian) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sets per muscle · 7 days").liquidRegla().foregroundStyle(EntrenarTono.cian.rotulo)
                    ForEach(rows) { fila in
                        drow(fila).padding(.top, EntrenarHubMetrics.dosisRowTop)
                    }
                }
            }
            .liquidEntrada(index: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private func drow(_ fila: EntrenarHubDosis.Fila) -> some View {
        HStack(spacing: EntrenarHubMetrics.dosisRowGap) {
            Text(verbatim: fila.label3)
                .font(EntrenarHubMetrics.microLabel9).tracking(EntrenarHubMetrics.microLabel9Tracking)
                .foregroundStyle(LiquidColor.tinta500)
                .frame(width: EntrenarHubMetrics.dosisLabelWidth, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(EntrenarHubMetrics.dosisTrackFondoAlfa))
                    Capsule()
                        .fill(fila.low ? LiquidColor.cian.opacity(EntrenarHubMetrics.dosisFillBajoAlfa) : LiquidColor.cian)
                        .frame(width: max(0, geo.size.width * min(1, fila.fraction)))
                    // Los dos ticks MUDOS de referencia — 50 % y el tope, sin texto (mock `.band`/`::after`).
                    Rectangle().fill(LiquidColor.tinta900.opacity(EntrenarHubMetrics.dosisTickAlfa))
                        .frame(width: EntrenarHubMetrics.dosisTickWidth)
                        .position(x: geo.size.width * 0.5, y: geo.size.height / 2)
                    Rectangle().fill(LiquidColor.tinta900.opacity(EntrenarHubMetrics.dosisTickAlfa))
                        .frame(width: EntrenarHubMetrics.dosisTickWidth)
                        .position(x: geo.size.width - EntrenarHubMetrics.dosisTickWidth / 2, y: geo.size.height / 2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: EntrenarHubMetrics.dosisTrackHeight)
            .clipShape(Capsule())
            Text(verbatim: MuscleFatigueMap.formattedSets(fila.sets))
                .font(EntrenarHubMetrics.subLsDelta)   // grotesk 10.5/700 tabular — mismo peldaño que `.drow b`
                .foregroundStyle(LiquidColor.tinta700)
                .frame(width: EntrenarHubMetrics.dosisNumeralWidth, alignment: .trailing)
        }
    }

    private var accessibilityLabel: Text {
        rows.enumerated().reduce(Text("Sets per muscle · 7 days")) { acc, pair in
            let (_, fila) = pair
            return acc + Text(verbatim: ". ") + Text(verbatim: fila.label3) + Text(verbatim: " ")
                + Text(verbatim: MuscleFatigueMap.formattedSets(fila.sets))
        }
    }
}
#endif
