import SwiftUI

// MARK: - InstrumentoFlowTitle — the one flow-screen header (EST-5/EST-3, FER-813)
//
// The Entrenar flow's non-metric screens (Historial, Rutina de hoy, Detalle de sesión, Editor de
// descanso) titled themselves four ways: `title1` bare, overline + `title1`, and a raw `groteskScreenTitle`.
// This is the single header for them: an optional section overline above the session's `groteskScreenTitle`.
// (Metric screens keep `InstrumentoScreenTitle` with its `MetricGlyph`; this is the sibling for screens
// that carry no metric icon.) The overline uses the one canonical helper, `instrumentoOverline` (EST-3).
//
// Takes `Text` for both slots so callers pass a localized key (`Text("Rutina de hoy")`) or a runtime
// string (`Text(verbatim: routineName)`); the component owns the font, tracking and ink.
public struct InstrumentoFlowTitle: View {
    @Environment(\.instrumentoTheme) private var theme
    private let overline: Text?
    private let title: Text

    public init(overline: Text? = nil, _ title: Text) {
        self.overline = overline
        self.title = title
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let overline {
                overline.instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
            title
                .font(InstrumentoType.groteskScreenTitle)
                .tracking(InstrumentoType.groteskScreenTitleTracking)
                .foregroundStyle(theme.ink)
                // Un nombre largo envuelve a dos líneas; el interlineado por defecto del Grotesk 25 bold
                // las apretaba. 4pt de aire las separa sin abrir de más los títulos de un solo renglón
                // (lineSpacing solo actúa ENTRE líneas, así que los de una línea no se mueven).
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Instrumento · flow title") {
    VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
        InstrumentoFlowTitle(overline: Text(verbatim: "TODAY'S ROUTINE"), Text(verbatim: "Pierna"))
        InstrumentoFlowTitle(Text(verbatim: "My workouts"))
        // Nombre largo → dos líneas: el interlineado de 4pt las deja respirar.
        InstrumentoFlowTitle(overline: Text(verbatim: "VIE 10 JUL · 18:04"),
                             Text(verbatim: "Empuje pesado de pecho y hombros"))
    }
    .frame(width: 390, alignment: .leading)
    .padding(CenitMetrics.screenPadding)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}
#endif
