import SwiftUI
import StrandDesign

/// Strain/illness early-warning banner. Observes AppModel in isolation so the ~1 Hz HR stream
/// re-renders only this small view, not the whole screen. Renders nothing when there's no alert.
struct HealthAlertBanner: View {
    @Environment(AppModel.self) var model
    var body: some View {
        if let alert = model.healthAlert {
            HStack(alignment: .top, spacing: 10) {
                StrandIcon.warning.image
                    .foregroundStyle(StrandPalette.statusWarning)
                    .accessibilityHidden(true)
                Text(alert)
                    .font(StrandFont.subhead)
                    .foregroundStyle(InstrumentoTheme.base.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .instrumentoCard(.control, theme: InstrumentoTheme.base,
                             fill: StrandPalette.statusWarning.opacity(StrandOpacity.tintFill),
                             stroke: StrandPalette.statusWarning.opacity(StrandOpacity.dim))
            .accessibilityElement(children: .combine)
        }
    }
}
