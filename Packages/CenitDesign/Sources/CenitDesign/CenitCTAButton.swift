import SwiftUI

// MARK: - CenitCTAButton — the one full-width call-to-action (EST-1/2/3, FER-812)
//
// Before this, the flow's solid CTA drifted across screens: radius 12/13/14/16, padding 14/15, label
// `paper` vs `paperHi`, some SF and some grotesk. This is the single canonical bar. Hierarchy comes from
// the INK FILL, not color (DESIGN.md §8.4): `.solid` is ink with a `paperHi` label — the heaviest element
// on the screen without a pixel of color; `.outline` is the first-class quiet exit (readable border,
// never a ghost). One radius (`ctaRadius` = 14), one vertical padding (15), the session's grotesk voice.

/// Shared press feedback: a subtle sink, no glow or color change.
struct InstrumentoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(StrandMotion.interactive, value: configuration.isPressed)
    }
}

public struct CenitCTAButton: View {
    public enum Kind { case solid, outline }

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let kind: Kind
    /// Relleno alternativo del `.solid` (identidad de rutina, puerta ámbar del módulo Entrenar).
    /// nil = tinta, el default del sistema. Ignorado en `.outline`.
    private let tint: Color?
    private let action: () -> Void

    /// FER-86: el héroe de Entrenar lo quiere COMPACTO, como su handoff lo dibuja (pastilla de
    /// 46 con aire a los lados), no como una banda de ancho completo. Por omisión sigue llenando
    /// el ancho, así que ningún otro sitio cambia.
    private let fillsWidth: Bool

    public init(_ title: LocalizedStringKey, systemImage: String? = nil,
                kind: Kind = .solid, tint: Color? = nil, fillsWidth: Bool = true,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.tint = tint
        self.fillsWidth = fillsWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            label
                .font(InstrumentoType.grotesk(15, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(kind == .solid ? theme.paperHi : theme.ink)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .padding(.horizontal, fillsWidth ? 0 : CenitMetrics.sectionGapCompact + LiquidSpace.s300)
                .padding(.vertical, 15)
                .background {
                    let shape = RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous)
                    switch kind {
                    case .solid:
                        shape.fill(tint ?? theme.ink)
                    case .outline:
                        shape.fill(theme.surface)
                            .overlay(shape.strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    }
                }
                .contentShape(Rectangle())
                // Disabled: dim to the shared dim value; the Button already blocks the tap (FER-916).
                .opacity(isEnabled ? 1 : CenitOpacity.dim)
        }
        .buttonStyle(InstrumentoPressStyle())
    }

    @ViewBuilder private var label: some View {
        if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
    }
}

#if DEBUG
#Preview("Instrumento · CenitCTAButton") {
    VStack(spacing: LiquidSpace.s300) {
        CenitCTAButton("Empezar", action: {})
        CenitCTAButton("Descartar", kind: .outline, action: {})
        CenitCTAButton("Guardar", action: {}).disabled(true)
    }
    .padding(LiquidSpace.s600)
    .frame(width: 390)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}
#endif
