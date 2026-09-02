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
// owns the String Catalog; this package stays copy-free). Paints with `LiquidColor` (FER-316).
public struct ConfidenceSello: View {

    private let label: Text
    private let a11yLabel: Text
    private let dimmed: Bool
    private let onField: Bool

    /// - Parameters:
    ///   - label: the visible tier text (already localized by the caller).
    ///   - a11yLabel: the VoiceOver phrase — spell out "confidence: …" so the tier is
    ///     never announced as a bare adjective.
    ///   - dimmed: true for a thinner tier (building/calibrating) — drops the ink one step.
    ///   - onField: true when the sello sits on a coloured data field (the Sleep/Strain hero),
    ///     not light paper. Ink tokens read dark-on-dark there, so switch to paper for text
    ///     and border. Shape+text still carry the meaning; only the tint flips to stay legible.
    ///   - theme: ignored for painting (LiquidColor). Kept for call-site compatibility (FER-316).
    public init(_ label: Text, a11yLabel: Text, dimmed: Bool, onField: Bool = false,
                theme: InstrumentoTheme = .base) {
        self.label = label
        self.a11yLabel = a11yLabel
        self.dimmed = dimmed
        self.onField = onField
        _ = theme
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
        if onField { return dimmed ? LiquidColor.papelTarjeta.opacity(OnFieldOpacity.secondary) : LiquidColor.papelTarjeta }
        return dimmed ? LiquidColor.tinta500 : LiquidColor.tinta700
    }

    private var borderTint: Color {
        onField ? LiquidColor.papelTarjeta.opacity(OnFieldOpacity.secondary) : LiquidColor.tinta10
    }
}

#Preview("ConfidenceSello") {
    VStack(alignment: .leading, spacing: 12) {
        ConfidenceSello(Text(verbatim: "Confianza alta"),
                        a11yLabel: Text(verbatim: "Confianza: alta"),
                        dimmed: false)
        ConfidenceSello(Text(verbatim: "Confianza media"),
                        a11yLabel: Text(verbatim: "Confianza: media"),
                        dimmed: true)
    }
    .padding(24)
    .background(LiquidColor.fondoAlto)
}
