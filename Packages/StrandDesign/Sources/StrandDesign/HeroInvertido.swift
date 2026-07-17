import SwiftUI

#if !os(watchOS)
/// Campo invertido del héroe: fondo saturado del `hue` con texto `theme.paper`. Centraliza el chrome
/// (glyph + rótulo uppercase + botón ⓘ) y el contenedor; numeral, veredicto y extras (sello /
/// estimación / chip de fecha) son slots porque varían por pantalla.
public struct HeroInvertido<Numeral: View, Verdict: View, Trailing: View>: View {
    private let glyph: MetricGlyph
    private let title: LocalizedStringKey
    private let hue: Color
    private let onInfo: (() -> Void)?
    private let theme: InstrumentoTheme
    private let numeral: Numeral
    private let verdict: Verdict
    private let trailing: Trailing

    public init(glyph: MetricGlyph, title: LocalizedStringKey, hue: Color, theme: InstrumentoTheme,
                onInfo: (() -> Void)? = nil,
                @ViewBuilder numeral: () -> Numeral,
                @ViewBuilder verdict: () -> Verdict,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.glyph = glyph; self.title = title; self.hue = hue; self.theme = theme
        self.onInfo = onInfo
        self.numeral = numeral(); self.verdict = verdict(); self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: glyph.sfSymbol)
                    .font(StrandFont.glyph(.chevron))
                    .foregroundStyle(theme.paper)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text(title)
                    .font(InstrumentoType.grotesk(12, weight: .bold))
                    .tracking(2.4).textCase(.uppercase)
                    .foregroundStyle(theme.paper)
                Spacer()
                if let onInfo {
                    Button { onInfo() } label: {
                        Image(systemName: "info.circle")
                            // `.lead` (18pt) — was `.chevron` (12pt); a clearer, easier-to-hit affordance.
                            .font(StrandFont.glyph(.lead, weight: .regular))
                            .foregroundStyle(theme.paper.opacity(OnFieldOpacity.dimChrome))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("What we measure")
                }
            }
            numeral
            verdict
            trailing
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 22, trailing: 20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hue)
        .accessibilityElement(children: .combine)
    }
}

/// Numeral estándar del héroe: valor grande (default 60pt, 44 para Sueño) + sufijo opcional + un slot
/// `trailing` para la cápsula. Aplica `.recRise()` al valor.
public struct HeroNumeral<Trailing: View>: View {
    private let value: String
    private let suffix: String?
    private let size: CGFloat
    private let theme: InstrumentoTheme
    private let trailing: Trailing
    public init(_ value: String, suffix: String? = nil, size: CGFloat = 60, theme: InstrumentoTheme,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.value = value; self.suffix = suffix; self.size = size; self.theme = theme
        self.trailing = trailing()
    }
    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(value)
                .font(InstrumentoType.groteskNumber(size, weight: .bold))
                .tracking(-2)
                .foregroundStyle(theme.paper)
                .recRise()
            if let suffix {
                Text(verbatim: suffix)
                    .font(InstrumentoType.grotesk(13))
                    .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
            }
            trailing
        }
    }
}

/// Veredicto bicolor del héroe: palabra (semibold, papel) · cláusula (papel al 0.75). Para el veredicto
/// de una sola frase, el caller pasa un `Text(...)` plano en el slot `verdict` en vez de esto.
public struct HeroVeredictoBicolor: View {
    private let word: LocalizedStringKey
    private let clause: LocalizedStringKey
    private let theme: InstrumentoTheme
    public init(word: LocalizedStringKey, clause: LocalizedStringKey, theme: InstrumentoTheme) {
        self.word = word; self.clause = clause; self.theme = theme
    }
    public var body: some View {
        (Text(word)
            .font(InstrumentoType.grotesk(15, weight: .semibold))
            .foregroundColor(theme.paper)
         + Text(verbatim: " · ")
            .font(InstrumentoType.grotesk(14))
            .foregroundColor(theme.paper.opacity(OnFieldOpacity.secondary))
         + Text(clause)
            .font(InstrumentoType.grotesk(14))
            .foregroundColor(theme.paper.opacity(OnFieldOpacity.secondary)))
            .fixedSize(horizontal: false, vertical: true)
    }
}

public extension View {
    /// La cápsula secundaria del héroe (fondo papel 0.16, radio cápsula, padding 10x4). El contenido
    /// (p. ej. «+6 vs your base» o «in progress») lo compone el caller.
    func heroCapsule(theme: InstrumentoTheme) -> some View {
        self.padding(.horizontal, 10).padding(.vertical, 4)
            .background(theme.paper.opacity(OnFieldOpacity.capsule), in: Capsule())
    }
}

#if DEBUG
#Preview("HeroInvertido · bicolor + frase única") {
    let theme = InstrumentoTheme.base
    return ScrollView {
        VStack(spacing: 16) {
            HeroInvertido(
                glyph: .recovery,
                title: "Recovery",
                hue: theme.verdict,
                theme: theme,
                onInfo: {},
                numeral: {
                    HeroNumeral("78", suffix: "/100", theme: theme) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: "+6")
                                .font(InstrumentoType.groteskNumber(13, weight: .semibold))
                                .foregroundStyle(theme.paper)
                            Text("vs your base")
                                .font(InstrumentoType.grotesk(11))
                                .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                        }
                        .heroCapsule(theme: theme)
                    }
                },
                verdict: {
                    HeroVeredictoBicolor(word: "Ready to train",
                                         clause: "above your baseline",
                                         theme: theme)
                }
            )
            HeroInvertido(
                glyph: .strain,
                title: "Day Strain",
                hue: theme.dataStrain,
                theme: theme,
                onInfo: {},
                numeral: {
                    HeroNumeral("8.4", suffix: "/ 21", theme: theme) {
                        Text("in progress")
                            .font(InstrumentoType.grotesk(13, weight: .semibold))
                            .foregroundStyle(theme.paper)
                            .heroCapsule(theme: theme)
                    }
                },
                verdict: {
                    Text("Moderate effort today.")
                        .font(InstrumentoType.grotesk(15, weight: .semibold))
                        .foregroundStyle(theme.paper)
                        .fixedSize(horizontal: false, vertical: true)
                }
            )
        }
    }
    .background(theme.paper)
}
#endif
#endif
