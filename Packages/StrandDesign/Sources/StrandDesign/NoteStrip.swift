import SwiftUI

/// A note card with a 2.5pt accent bar on the leading edge (FER-898 C6). Two verified-identical
/// treatments from Entrenar: `.warning` (PlatesScreen shortfall notice — full rounded corners + border)
/// and `.info` (ExerciseDetailScreen cycle block / LiveStrengthSheet why-raise card — trailing-only
/// rounded corners, no border). Content is supplied by the call site via @ViewBuilder.
public struct NoteStrip<Content: View>: View {
    public enum Style {
        case warning
        case info
    }

    private let style: Style
    private let theme: InstrumentoTheme
    private let content: Content

    public init(style: Style, theme: InstrumentoTheme, @ViewBuilder content: () -> Content) {
        self.style = style
        self.theme = theme
        self.content = content()
    }

    public var body: some View {
        switch style {
        case .warning:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(
                    theme.tint(theme.warning),
                    in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                        .strokeBorder(theme.softStroke(theme.warning), lineWidth: 1)
                )
                .overlay(alignment: .leading) { Rectangle().fill(theme.warning).frame(width: 2.5) }
        case .info:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13).padding(.vertical, 11)
                .background(theme.surface)
                .overlay(alignment: .leading) { Rectangle().fill(theme.dataRecovery).frame(width: 2.5) }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                                  bottomTrailingRadius: 8, topTrailingRadius: 8))
        }
    }
}

#if DEBUG
#Preview("NoteStrip") {
    let t = InstrumentoTheme.base
    return VStack(alignment: .leading, spacing: 16) {
        NoteStrip(style: .warning, theme: t) {
            Text("Your plates can't hit 100 kg exactly, closest is 97.5 kg")
                .font(StrandFont.caption).foregroundStyle(t.inkSecondary)
        }
        NoteStrip(style: .info, theme: t) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Current cycle").instrumentoOverline().foregroundStyle(t.dataRecovery)
                Text("You're 1 of 2 sessions in with 100 kg.")
                    .font(StrandFont.caption).foregroundStyle(t.ink)
            }
        }
    }
    .padding()
    .background(t.paper)
}
#endif
