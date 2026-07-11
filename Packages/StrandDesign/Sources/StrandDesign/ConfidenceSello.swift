import SwiftUI

// MARK: - Confidence sello (FER-676)
//
// The quiet text+shape chip that grades how much to trust the number next to it — the
// shared stamp Esfuerzo / Sueño (and future scores) wear. Its style mirrors the inline
// chip ActivityRecoverySheet first introduced; folding that original into this component
// is a follow-up so every score shares literally ONE stamp.
//
// «Instrumento» discipline: confidence is not good/bad, so the sello NEVER takes an
// alarm colour — only ink emphasis varies (solid reads a step stronger than a thinner
// tier). Shape + text carry the meaning, not colour, so it survives monochrome and
// colour-blind reading. The label/a11y strings come from the CALLER (the app layer
// owns the String Catalog; this package stays copy-free).
public struct ConfidenceSello: View {

    private let label: Text
    private let a11yLabel: Text
    private let dimmed: Bool
    private let onField: Bool
    private let theme: InstrumentoTheme

    /// - Parameters:
    ///   - label: the visible tier text (already localized by the caller).
    ///   - a11yLabel: the VoiceOver phrase — spell out "confidence: …" so the tier is
    ///     never announced as a bare adjective.
    ///   - dimmed: true for a thinner tier (building/calibrating) — drops the ink one step.
    ///   - onField: true when the sello sits on a coloured data field (the Sleep/Strain hero),
    ///     not light paper. Ink tokens read dark-on-dark there, so switch to `paper` for text
    ///     and border. Shape+text still carry the meaning; only the tint flips to stay legible.
    public init(_ label: Text, a11yLabel: Text, dimmed: Bool, onField: Bool = false, theme: InstrumentoTheme) {
        self.label = label
        self.a11yLabel = a11yLabel
        self.dimmed = dimmed
        self.onField = onField
        self.theme = theme
    }

    public var body: some View {
        label
            .font(.system(size: 11, weight: .semibold))   // token-exempt: sello semibold+tracking (micro es 11/medium)
            .tracking(0.3)
            .textCase(.uppercase)
            .foregroundStyle(textTint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)   // token-exempt: geometría de dato (sello ≤6pt)
                .strokeBorder(borderTint, lineWidth: 1))
            .accessibilityLabel(a11yLabel)
    }

    private var textTint: Color {
        if onField { return dimmed ? theme.paper.opacity(OnFieldOpacity.secondary) : theme.paper }
        return dimmed ? theme.inkTertiary : theme.inkSecondary
    }

    private var borderTint: Color {
        onField ? theme.paper.opacity(OnFieldOpacity.secondary) : theme.hairlineStrong
    }
}

#Preview("ConfidenceSello") {
    let theme = InstrumentoTheme.base
    return VStack(alignment: .leading, spacing: 12) {
        ConfidenceSello(Text(verbatim: "Confianza alta"),
                        a11yLabel: Text(verbatim: "Confianza: alta"),
                        dimmed: false, theme: theme)
        ConfidenceSello(Text(verbatim: "Confianza media"),
                        a11yLabel: Text(verbatim: "Confianza: media"),
                        dimmed: true, theme: theme)
    }
    .padding(24)
    .background(theme.paper)
}
