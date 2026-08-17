import SwiftUI

// MARK: - EntrenarHilo — el hilo del veredicto (FER-83 · E2)
//
// El ÚNICO portador del veredicto en toda la sección Entrenar: la misma pastilla que es la puerta
// de Hoy. Fondo al 12 % y borde al 38 % del tono, bolita con el hue saturado, palabra en el TONO DE
// LECTURA (nunca el hue saturado en texto chico), consejo al lado en tinta, fila de 44 pt y «›».
//
// Seis variantes: tres con veredicto (en rango · ve leve · recupera) y tres huecas (conociéndote ·
// sin lectura · sin permiso). Las huecas no inventan consejo: bolita hueca, texto en tinta500, borde
// tenue, sin fondo. Nunca hay dos portadores del veredicto en una pantalla.

public struct EntrenarHilo: View {

    /// El tono del hilo. Es el veredicto traducido a color, no el veredicto: el paquete no conoce
    /// `Preparedness` (la app hace el mapeo) y así el mismo componente sirve en la landing, la
    /// sesión, el acta y «Tu cuerpo».
    public enum Tone: Sendable, Hashable {
        /// «En rango» — verde.
        case clear
        /// «Hoy ve leve» — ámbar.
        case caution
        /// «Recupera» — rojo.
        case ease
        /// Sin lectura usable: bolita hueca y nada de color.
        case hollow

        func dot(_ theme: InstrumentoTheme) -> Color {
            switch self {
            case .clear:   return theme.verdict
            case .caution: return theme.warning
            case .ease:    return theme.critical
            case .hollow:  return .clear
            }
        }

        /// El tono de lectura de la palabra: AA a tamaño de texto, siempre.
        func word(_ theme: InstrumentoTheme) -> Color {
            switch self {
            case .clear:   return theme.positiveText
            case .caution: return OKLab.darkened(theme.warning, toContrast: 4.5, against: theme.paper)
            case .ease:    return theme.negativeText
            case .hollow:  return theme.inkSecondary
            }
        }

        func background(_ theme: InstrumentoTheme) -> Color {
            self == .hollow ? .clear : dot(theme).opacity(EntrenarMetrics.pillFillAlpha)
        }

        func border(_ theme: InstrumentoTheme) -> Color {
            self == .hollow ? theme.hairlineStrong : dot(theme).opacity(EntrenarMetrics.pillBorderAlpha)
        }
    }

    private let tone: Tone
    private let word: LocalizedStringKey
    private let advice: LocalizedStringKey?
    private let action: (() -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    /// - Parameters:
    ///   - tone: el color del día, ya traducido por la app.
    ///   - word: la palabra del veredicto («En rango», «Recupera», «Conociéndote»…).
    ///   - advice: el consejo grueso que la acompaña. `nil` en las variantes que no aconsejan.
    ///   - action: qué abre. `nil` deja la pastilla informativa (sin «›» y sin toque).
    public init(tone: Tone, word: LocalizedStringKey, advice: LocalizedStringKey? = nil,
                action: (() -> Void)? = nil) {
        self.tone = tone; self.word = word; self.advice = advice; self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { pill }
                .buttonStyle(EntrenarPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
        } else {
            pill.accessibilityElement(children: .combine)
        }
    }

    private var pill: some View {
        HStack(spacing: 9) {
            dot
            Text(word)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(tone.word(theme))
            if let advice {
                Text(advice)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if action != nil {
                StrandIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: EntrenarMetrics.row)
        .background(tone.background(theme), in: Capsule())
        .overlay(Capsule().strokeBorder(tone.border(theme), lineWidth: 1))
        .contentShape(Capsule())
    }

    @ViewBuilder private var dot: some View {
        if tone == .hollow {
            Circle().strokeBorder(theme.inkTertiary, lineWidth: 1.5).frame(width: 9, height: 9)
        } else {
            Circle().fill(tone.dot(theme)).frame(width: 9, height: 9)
        }
    }
}

/// El press de la sección: 0.97 con Reduce Motion cayendo a un bajón de opacidad. Un solo estilo
/// para todos los componentes de Entrenar, en vez de repetir el gesto en cada uno.
public struct EntrenarPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .opacity(reduceMotion && configuration.isPressed ? 0.7 : 1)
            .animation(StrandMotion.interactive, value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("EntrenarHilo · 6 variantes") {
    VStack(spacing: 10) {
        EntrenarHilo(tone: .clear, word: "In range", advice: "your plan for today, as it is") {}
        EntrenarHilo(tone: .caution, word: "Go light today", advice: "don't add weight") {}
        EntrenarHilo(tone: .ease, word: "Recover", advice: "easy today, or rest") {}
        EntrenarHilo(tone: .hollow, word: "Getting to know you", advice: "no advice yet")
        EntrenarHilo(tone: .hollow, word: "No reading today", advice: "sync in Today") {}
        EntrenarHilo(tone: .hollow, word: "Connect Apple Health") {}
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("EntrenarHilo · xxxLarge") {
    VStack(spacing: 10) {
        EntrenarHilo(tone: .clear, word: "In range", advice: "your plan for today, as it is") {}
        EntrenarHilo(tone: .ease, word: "Recover", advice: "easy today, or rest") {}
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
