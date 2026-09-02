import SwiftUI

/// Botón redondo/rectangular −/+ del design system (FER-898). Fuente única del stepper de Entrenar.
public struct StepperButton: View {
    public enum ButtonShape { case circle, roundedControl }

    private let system: String
    private let size: CGFloat
    private let shape: ButtonShape
    private let glyph: Font
    private let theme: InstrumentoTheme
    private let action: () -> Void

    public init(system: String, size: CGFloat, shape: ButtonShape,
                glyph: Font, theme: InstrumentoTheme, action: @escaping () -> Void) {
        self.system = system; self.size = size; self.shape = shape
        self.glyph = glyph; self.theme = theme; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // contentShape requires Shape (not some View); branch per shape.
            switch shape {
            case .circle:
                glyphLabel.contentShape(Circle())
            case .roundedControl:
                glyphLabel.contentShape(
                    RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous))
            }
        }
        .buttonStyle(.plain)
    }

    private var glyphLabel: some View {
        Image(systemName: system)
            .font(glyph)
            .foregroundStyle(theme.inkSecondary)
            .frame(width: size, height: size)
            .background(background)
            .overlay(border)
    }

    @ViewBuilder private var background: some View {
        switch shape {
        case .circle:
            Circle().fill(theme.surface)
        case .roundedControl:
            RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous).fill(theme.surface)
        }
    }
    @ViewBuilder private var border: some View {
        switch shape {
        case .circle:
            Circle().strokeBorder(theme.hairlineStrong, lineWidth: 1)
        case .roundedControl:
            RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
                .strokeBorder(theme.hairlineStrong, lineWidth: 1)
        }
    }
}

#if DEBUG
#Preview("StepperButton") {
    let t = InstrumentoTheme.base
    HStack(spacing: 16) {
        // PlatesScreen: circle 34, glyph .inline semibold
        StepperButton(system: "minus", size: 34, shape: .circle,
                      glyph: StrandFont.glyph(.inline, weight: .semibold), theme: t, action: {})
        StepperButton(system: "plus", size: 34, shape: .circle,
                      glyph: StrandFont.glyph(.inline, weight: .semibold), theme: t, action: {})
        // ProgressionSetupScreen: circle 32, caption
        StepperButton(system: "minus", size: 32, shape: .circle,
                      glyph: StrandFont.caption, theme: t, action: {})
        StepperButton(system: "plus", size: 32, shape: .circle,
                      glyph: StrandFont.caption, theme: t, action: {})
        // RestEditorScreen: roundedControl 44, glyph .lead
        StepperButton(system: "minus", size: 44, shape: .roundedControl,
                      glyph: StrandFont.glyph(.lead), theme: t, action: {})
        StepperButton(system: "plus", size: 44, shape: .roundedControl,
                      glyph: StrandFont.glyph(.lead), theme: t, action: {})
    }
    .padding(20)
    .background(t.paper)
}
#endif
