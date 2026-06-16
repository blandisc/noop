import SwiftUI
import StrandDesign

/// Strain/illness early-warning banner. Observes AppModel in isolation so the ~1 Hz HR stream
/// re-renders only this small view, not the whole screen. Renders nothing when there's no alert.
struct HealthAlertBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let alert = model.healthAlert {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(StrandPalette.statusWarning)
                    .accessibilityHidden(true)
                Text(alert)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StrandPalette.statusWarning.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(StrandPalette.statusWarning.opacity(0.4), lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }
}
