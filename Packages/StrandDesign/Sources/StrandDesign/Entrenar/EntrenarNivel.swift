import SwiftUI

// MARK: - EntrenarNivel + EntrenarChip (FER-83 · E2)
//
// Las dos piezas de chrome que se repiten en toda la sección: el encabezado de un nivel y el chip
// de papel. Antes cada pantalla dibujaba su propia versión, con su propio alto y su propio toque.

/// El encabezado de un nivel de la landing («TU SEMANA», «MÚSCULOS CARGADOS», «BITÁCORA»).
///
/// La regla del lenguaje: el rótulo pelón en mayúsculas a la izquierda, el valor a la derecha, y
/// «›» solo cuando el nivel es puerta. Cuando es puerta, TODO el encabezado es tocable a 44 pt —
/// no solo el chevron, que es un blanco de 11 pt disfrazado de botón.
public struct EntrenarNivel: View {
    private let kicker: LocalizedStringKey
    private let value: LocalizedStringKey?
    private let action: (() -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    public init(_ kicker: LocalizedStringKey, value: LocalizedStringKey? = nil,
                action: (() -> Void)? = nil) {
        self.kicker = kicker; self.value = value; self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(EntrenarPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
        } else {
            row.accessibilityElement(children: .combine)
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space2) {
            Text(kicker).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Spacer(minLength: CenitMetrics.space2)
            if let value {
                Text(value)
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if action != nil {
                StrandIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(minHeight: EntrenarMetrics.row)
        .contentShape(Rectangle())
    }
}

/// El chip troquelado de la sección: papel hundido con canto, y el ÚNICO color vive en el icono y
/// en el valor. Lo usan la sesión y «Rutina» para descanso, progresión y calentamiento.
public struct EntrenarChip: View {

    public enum Kind: Sendable, Hashable {
        /// Descanso entre series — el pulso es su identidad.
        case rest
        /// El ciclo de progresión de un ejercicio.
        case progression
        /// Serie de calentamiento.
        case warmup

        var symbol: String {
            switch self {
            case .rest:        return "timer"
            case .progression: return "arrow.up.right"
            case .warmup:      return "flame"
            }
        }

        func tone(_ theme: InstrumentoTheme) -> Color {
            switch self {
            case .rest:        return theme.dataHeart
            case .progression: return theme.positiveText
            case .warmup:      return theme.inkSecondary
            }
        }
    }

    private let kind: Kind
    private let text: LocalizedStringKey
    private let action: (() -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    public init(_ kind: Kind, text: LocalizedStringKey, action: (() -> Void)? = nil) {
        self.kind = kind; self.text = text; self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { chip }
                .buttonStyle(EntrenarPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
        } else {
            chip.accessibilityElement(children: .combine)
        }
    }

    private var chip: some View {
        HStack(spacing: CenitMetrics.space1 + 2) {
            Image(systemName: kind.symbol)
                .font(StrandFont.glyph(.lead))
                .foregroundStyle(kind.tone(theme))
            Text(text)
                .font(StrandFont.caption)
                .foregroundStyle(kind.tone(theme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CenitMetrics.space2 + 1)
        .frame(minHeight: EntrenarMetrics.badge)
        .background(theme.paper, in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
            .strokeBorder(theme.hairlineStrong, lineWidth: 1))
        // El dibujo es de 28; el toque nunca baja de 44 (HIG).
        .frame(minHeight: action != nil ? EntrenarMetrics.row : EntrenarMetrics.badge)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("EntrenarNivel · estados") {
    VStack(spacing: 0) {
        EntrenarNivel("Your week", value: "2 of 3") {}
        Divider().overlay(InstrumentoTheme.base.hairline)
        EntrenarNivel("Loaded muscles", value: "estimate")
        Divider().overlay(InstrumentoTheme.base.hairline)
        EntrenarNivel("Log")
        Divider().overlay(InstrumentoTheme.base.hairline)
        EntrenarNivel("History and progress", value: "11 sessions · 90 days") {}
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("EntrenarChip · tipos") {
    VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
            EntrenarChip(.rest, text: "2:30")
            EntrenarChip(.progression, text: "2 of 2")
            EntrenarChip(.warmup, text: "warm-up")
        }
        HStack(spacing: 8) {
            EntrenarChip(.rest, text: "by heart rate · cap 2:30") {}
            EntrenarChip(.progression, text: "cycle") {}
        }
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("Nivel y chip · xxxLarge") {
    VStack(alignment: .leading, spacing: 12) {
        EntrenarNivel("History and progress", value: "11 sessions · 90 days") {}
        EntrenarChip(.rest, text: "by heart rate · cap 2:30") {}
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
