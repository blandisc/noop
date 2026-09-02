import SwiftUI

/// A note card with a 2.5pt accent bar on the leading edge (FER-898 C6). Two verified-identical
/// treatments from Entrenar: `.warning` (PlatesScreen shortfall notice — full rounded corners + border)
/// and `.info` (ExerciseDetailScreen cycle block / LiveStrengthSheet why-raise card — trailing-only
/// rounded corners, no border). Content is supplied by the call site via @ViewBuilder.
/// Paints with `LiquidColor` (FER-316).
public struct NoteStrip<Content: View>: View {
    public enum Style {
        case warning
        case info
    }

    private let style: Style
    private let content: Content

    /// - Parameter theme: ignored for painting (LiquidColor). Kept for call-site compatibility (FER-316).
    public init(style: Style, theme: InstrumentoTheme = .base, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
        _ = theme
    }

    public var body: some View {
        switch style {
        case .warning:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(
                    LiquidColor.atencion.opacity(CenitOpacity.tintFill),
                    in: RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
                        .strokeBorder(LiquidColor.atencion.opacity(CenitOpacity.strokeSoft), lineWidth: 1)
                )
                .overlay(alignment: .leading) { Rectangle().fill(LiquidColor.atencion).frame(width: 2.5) }
        case .info:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13).padding(.vertical, 11)
                .background(LiquidColor.papelTarjeta)
                .overlay(alignment: .leading) { Rectangle().fill(LiquidColor.verdePrimario).frame(width: 2.5) }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                                  bottomTrailingRadius: 8, topTrailingRadius: 8))
        }
    }
}

#if DEBUG
#Preview("NoteStrip") {
    VStack(alignment: .leading, spacing: 16) {
        NoteStrip(style: .warning) {
            Text("Your plates can't hit 100 kg exactly, closest is 97.5 kg")
                .font(StrandFont.caption).foregroundStyle(LiquidColor.tinta700)
        }
        NoteStrip(style: .info) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Current cycle").instrumentoOverline().foregroundStyle(LiquidColor.verdePrimario)
                Text("You're 1 of 2 sessions in with 100 kg.")
                    .font(StrandFont.caption).foregroundStyle(LiquidColor.tinta900)
            }
        }
    }
    .padding()
    .background(LiquidColor.fondoAlto)
}
#endif
