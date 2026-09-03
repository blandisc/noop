#if os(iOS)
import SwiftUI
import CenitDesign
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

    /// Ronda 3 · D5: `dosisNumeralWidth` era un ancho FIJO de 18 — los valores con medio que G7
    /// rescató («12.5») se truncaban con elipsis, peor con Dynamic Type (la fuente escala vía
    /// `relativeTo`, el frame no). `@ScaledMetric` con el MISMO `relativeTo` que `subLsDelta`
    /// (`.caption`) — numeral y columna crecen juntos. Sigue siendo un ancho EXACTO (no `minWidth`):
    /// así todas las filas reservan la MISMA columna y el riel de cada una alinea su filo derecho.
    @ScaledMetric(relativeTo: .caption) private var dosisNumeralWidth = EntrenarHubMetrics.dosisNumeralWidthBase

    var body: some View {
        if !rows.isEmpty {
            EntrenarModulo(tono: .cian) {
                VStack(alignment: .leading, spacing: .zero) {
                    Text("Sets per muscle · 7 days").liquidRegla().foregroundStyle(LiquidTono.cian.rotulo)
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
            LiquidBarraProgreso(
                fraccion: min(1, fila.fraction),
                tono: fila.low
                    ? LiquidColor.cian.opacity(EntrenarHubMetrics.dosisFillBajoAlfa)
                    : LiquidColor.cian,
                pista: LiquidColor.papelTarjeta.opacity(EntrenarHubMetrics.dosisTrackFondoAlfa),
                altura: EntrenarHubMetrics.dosisTrackHeight,
                animada: false,
                // Los dos ticks MUDOS de referencia — 50 % y el tope, sin texto (mock `.band`/`::after`);
                // viven dentro de la pieza y se recortan con la cápsula (FER-358).
                marcasMudas: [0.5, 1.0],
                tonoMarcaMuda: LiquidColor.tinta900.opacity(EntrenarHubMetrics.dosisTickAlfa))
                .frame(maxWidth: .infinity)
            Text(verbatim: MuscleFatigueMap.formattedSets(fila.sets))
                .font(EntrenarHubMetrics.subLsDelta)   // grotesk 10.5/700 tabular — mismo peldaño que `.drow b`
                .foregroundStyle(LiquidColor.tinta700)
                .lineLimit(1)
                .frame(width: dosisNumeralWidth, alignment: .trailing)
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
