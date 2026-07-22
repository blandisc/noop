import SwiftUI
import StrandDesign

// MARK: - AutonomicTrendDetailSheet

/// Explainer presented by the caller via `.sheet`. Theme is an explicit parameter because
/// `.sheet` sits in a fresh environment that does not reliably inherit `.instrumentoTheme`.
struct AutonomicTrendDetailSheet: View {
    var theme: InstrumentoTheme = .base

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("Cómo estimo tu tendencia")
                    .font(StrandFont.title3)
                    .foregroundStyle(theme.ink)

                Text("Miro la variabilidad de los latidos que tu reloj registra mientras duermes y la comparo con tu propio promedio, no con el de otra persona ni con un número fijo de población.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Es una guía de dirección, no una medición médica ni una puntuación exacta.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Task Force 1996; Plews 2013")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CenitMetrics.cardPadding)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Detail sheet") {
    AutonomicTrendDetailSheet(theme: .base)
}
#endif
