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
    /// El estilo del kicker. `.overline` es el de siempre (default); `.handoff` es el kicker de la
    /// landing de Entrenar (FER-130).
    public enum KickerStyle: Sendable { case overline, handoff }
    private let kickerStyle: KickerStyle

    private let kicker: LocalizedStringKey
    private let value: LocalizedStringKey?
    private let action: (() -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    public init(_ kicker: LocalizedStringKey, value: LocalizedStringKey? = nil,
                kickerStyle: KickerStyle = .overline, action: (() -> Void)? = nil) {
        self.kicker = kicker; self.kickerStyle = kickerStyle; self.value = value; self.action = action
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
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
            // FER-130: el hub de Entrenar pide el kicker del handoff (Grotesk 11.5/600 +1.5, uppercase); los
            // demás llamadores (la hoja «Ver toda la biblioteca» de la sesión) conservan el overline de
            // siempre. Default = lo de antes, para que un componente compartido no cambie pantallas que
            // nadie pidió tocar.
            if kickerStyle == .handoff {
                Text(kicker).entrenarCabeceraKicker().foregroundStyle(theme.inkTertiary)
            } else {
                Text(kicker).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: LiquidSpace.s200)
            if let value {
                Text(value)
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if action != nil {
                CenitIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)
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

        /// El tono del TEXTO del chip: los tres son texto chico, así que ninguno puede ir en el hue
        /// saturado. El rosa del pulso sobre papel se queda en 4.24:1; oscurecido llega a 4.5:1 sin
        /// dejar de ser rosa, que es lo que amarra el chip a su métrica.
        func tone(_ theme: InstrumentoTheme) -> Color {
            switch self {
            case .rest:        return OKLab.darkened(theme.dataHeart, toContrast: 4.5, against: theme.paper)
            case .progression: return theme.positiveText
            case .warmup:      return theme.inkSecondary
            }
        }
    }

    private let kind: Kind
    private let text: Text
    /// Icono que RESPALDA al de `kind` (FER-89) — hoy solo `.rest` lo necesita: distingue descanso
    /// por FC (♥) de descanso por reloj (⏱), algo que el símbolo fijo de `Kind` no admite por sí
    /// solo. `nil` (el default) conserva el símbolo de `kind` — los 3 call sites existentes
    /// (`EntrenarCatalog.swift`, el `#Preview` de abajo) no cambian.
    private let iconOverride: String?
    /// Tono que RESPALDA al de `kind`, mismo criterio que `iconOverride`.
    private let toneOverride: Color?
    /// El chevron «›» que marca «esto abre algo» (FER-89) — aditivo, default `false`: los 3 call
    /// sites existentes de `EntrenarChip` no lo mostraban y siguen sin mostrarlo.
    private let showsDisclosure: Bool
    private let action: (() -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    public init(_ kind: Kind, text: LocalizedStringKey, icon: String? = nil, tone: Color? = nil,
                showsDisclosure: Bool = false, action: (() -> Void)? = nil) {
        self.kind = kind; self.text = Text(text)
        self.iconOverride = icon; self.toneOverride = tone
        self.showsDisclosure = showsDisclosure; self.action = action
    }

    /// El texto ya resuelto en tiempo de ejecución («90 s», «HR · 45%») — no una clave de catálogo.
    /// `LocalizedStringKey` trataría un `String` dinámico como clave de búsqueda, que es incorrecto
    /// para un rótulo ya formateado (FER-89, `RestChip`/`ProgressionChip`).
    public init(_ kind: Kind, verbatim text: String, icon: String? = nil, tone: Color? = nil,
                showsDisclosure: Bool = false, action: (() -> Void)? = nil) {
        self.kind = kind; self.text = Text(verbatim: text)
        self.iconOverride = icon; self.toneOverride = tone
        self.showsDisclosure = showsDisclosure; self.action = action
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
        HStack(spacing: LiquidSpace.s100 + 2) {
            Image(systemName: iconOverride ?? kind.symbol)
                .font(StrandFont.glyph(.lead))
                .foregroundStyle(toneOverride ?? kind.tone(theme))
            text
                .font(StrandFont.caption)
                .foregroundStyle(toneOverride ?? kind.tone(theme))
                .fixedSize(horizontal: false, vertical: true)
            if showsDisclosure {
                CenitIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, LiquidSpace.s200 + 1)
        .frame(minHeight: EntrenarMetrics.badge)
        .background(theme.paper, in: RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous)
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
        // FER-89: RestChip distingue reloj/pulso con overrides de icono+tono + el chevron «›» que
        // RestChip ya tenía (mismo grammar de antes, ahora desde la pieza compartida).
        HStack(spacing: 8) {
            EntrenarChip(.rest, verbatim: "90 s", icon: "clock", tone: InstrumentoTheme.base.dataStrain,
                        showsDisclosure: true) {}
            EntrenarChip(.rest, verbatim: "HR · 45%", icon: "heart.fill", tone: InstrumentoTheme.base.dataRecovery,
                        showsDisclosure: true) {}
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
