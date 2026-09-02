import SwiftUI

// MARK: - EntrenarHilo — el hilo del veredicto (FER-83 · E2 · reescrito en FER-85 · FER-316)
//
// El ÚNICO portador del veredicto en toda la sección Entrenar, y la puerta al acta de Hoy.
//
// La pastilla teñida se retiró: el handoff v3 la revierte con todas sus letras («el veredicto entra
// como ORBE VIVO … SIN pastilla de fondo»), y el ADN la prohibía desde antes — el hue no llena
// fondos ni molduras. Lo que queda es el orbe, la palabra en su tono de lectura, el consejo en
// tinta y «›», sobre papel pelón.
//
// El orbe es `OrbeVivo` tal cual, no una re-derivación: el mismo material que gira en Hoy, con otro
// radio. Cuatro variantes: tres con veredicto (en rango · ve leve · recupera) y la hueca, que no
// inventa consejo ni color — un aro punteado de 22 y texto en tinta secundaria.
//
// Sin pastilla, la palabra cae sobre el PAPEL: su contraste se mide contra el papel, no contra un
// relleno que ya no existe. En Watch (`sobreOLED: true`) el suelo es negro: la palabra no se
// oscurece — se aclara o se deja el tono si ya pasa AA sobre `LiquidOLED.fondo` (FER-316).

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
        /// Sin lectura usable: aro punteado y nada de color.
        case hollow

        /// El hue de la señal: el que gira en el orbe. Nunca toca texto.
        ///
        /// `public` desde FER-95: `CenitWidgets/HomeWidgets` (otro módulo, la extensión de widgets)
        /// necesita pintar el mismo tono de lectura que la landing sin re-derivar el veredicto — el
        /// widget nunca calcula el suyo, solo reproduce el que `AppModel` ya resolvió (el snapshot del
        /// App Group trae el `Tone` crudo). Antes era `internal`; el único llamador fuera de este
        /// archivo era una prueba con `@testable import CenitDesign`.
        /// `theme` se ignora (FER-316): lee `LiquidColor` directo.
        public func hue(_ theme: InstrumentoTheme = .base) -> Color {
            _ = theme
            switch self {
            case .clear:   return LiquidColor.verdePrimario
            // ex-warning (#9C5E10) → atencionTexto (no ambar/atencion) — decisión director FER-316.
            case .caution: return LiquidColor.atencionTexto
            case .ease:    return LiquidColor.negativo
            case .hollow:  return .clear
            }
        }

        /// El tono de LECTURA de la palabra: el mismo hue oscurecido hasta AA sobre el papel.
        /// Es el par obligatorio de `hue` — hue de dato, tono de lectura — y sin la pastilla el
        /// fondo real bajo la palabra es el papel, sin velo de por medio.
        ///
        /// Sobre OLED (`sobreOLED: true`) la regla se invierte: no oscurecer contra papel; usar el
        /// tono tal cual si su contraste sobre negro ≥ 4.5, si no el par LiquidOLED del rol.
        ///
        /// `public` por la misma razón que `hue` arriba (FER-95).
        /// `theme` se ignora (FER-316): lee `LiquidColor` / `LiquidOLED` directo.
        public func word(_ theme: InstrumentoTheme = .base, sobreOLED: Bool = false) -> Color {
            _ = theme
            if sobreOLED {
                if self == .hollow { return LiquidOLED.tinta }
                let h = hue()
                if OKLab.contrastRatio(h, LiquidOLED.fondo) >= 4.5 { return h }
                switch self {
                case .clear:   return LiquidOLED.verde
                case .caution: return LiquidOLED.ambar
                case .ease:    return LiquidOLED.negativo
                case .hollow:  return LiquidOLED.tinta
                }
            }
            // AA sobre el lienzo de referencia (FER-316).
            return self == .hollow ? LiquidColor.tinta700
                            : OKLab.darkened(hue(), toContrast: 4.5, against: EntrenarMetrics.lienzoContraste)
        }
    }

    private let tone: Tone
    private let word: LocalizedStringKey
    private let advice: LocalizedStringKey?
    /// El radio del orbe. Landing 15.5 · sesión 11 · hoja 20 · cabecera de sesión iPhone 32 (handoff v3/v4).
    private let radio: CGFloat
    /// A dónde lleva, para VoiceOver: sin esto la puerta principal de la pantalla se anunciaba como
    /// «botón» a secas y nadie sabía qué iba a abrir.
    private let hint: LocalizedStringKey?
    private let action: (() -> Void)?
    /// Watch / Dynamic Island: pinta tintas OLED sobre negro en vez de tinta700/500 sobre papel.
    private let sobreOLED: Bool

    /// - Parameters:
    ///   - tone: el color del día, ya traducido por la app.
    ///   - word: la palabra del veredicto («En rango», «Recupera», «Conociéndote»…).
    ///   - advice: el consejo grueso que la acompaña. `nil` en las variantes que no aconsejan.
    ///   - radio: el radio del orbe; por omisión el de la landing.
    ///   - sobreOLED: `true` en Watch (suelo negro); default `false` (papel).
    ///   - action: qué abre. `nil` deja el hilo informativo (sin «›» y sin toque).
    public init(tone: Tone, word: LocalizedStringKey, advice: LocalizedStringKey? = nil,
                radio: CGFloat = EntrenarMetrics.orbeLanding,
                hint: LocalizedStringKey? = nil, sobreOLED: Bool = false,
                action: (() -> Void)? = nil) {
        self.tone = tone; self.word = word; self.advice = advice
        self.radio = radio; self.hint = hint; self.sobreOLED = sobreOLED
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { hilo }
                .buttonStyle(EntrenarPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(hint.map { Text($0) } ?? Text(""))
        } else {
            hilo.accessibilityElement(children: .combine)
        }
    }

    private var hilo: some View {
        HStack(spacing: 9) {
            cuerpo
            // Con Dynamic Type grande la palabra y el consejo no caben lado a lado: en vez de
            // aplastar el veredicto —que es el dato—, se apilan.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { palabra; consejo }
                VStack(alignment: .leading, spacing: 2) { palabra; consejo }
            }
            Spacer(minLength: 8)
            if action != nil {
                CenitIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(sobreOLED ? LiquidOLED.tintaTerciaria : LiquidColor.tinta500)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: EntrenarMetrics.row)
        .contentShape(Rectangle())
    }

    private var palabra: some View {
        Text(word)
            .font(StrandFont.subhead.weight(.semibold))
            .foregroundStyle(tone.word(sobreOLED: sobreOLED))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var consejo: some View {
        if let advice {
            Text(advice)
                .font(StrandFont.subhead)
                .foregroundStyle(sobreOLED ? LiquidOLED.tintaSecundaria : LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// El orbe cuando hay lectura; el aro punteado cuando no la hay.
    ///
    /// El aro ocupa el MISMO ancho que el orbe para que la palabra no baile de sitio entre un día
    /// con veredicto y uno sin él: el hilo es la misma fila, cambie o no lo que tiene que decir.
    @ViewBuilder private var cuerpo: some View {
        let lado = radio * 2.5
        if tone == .hollow {
            Circle()
                .strokeBorder(sobreOLED ? LiquidOLED.tintaTerciaria : LiquidColor.tinta500,
                              style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                .frame(width: EntrenarMetrics.aroHueco, height: EntrenarMetrics.aroHueco)
                .frame(width: lado, height: lado)
        } else {
            OrbeVivo(radio: radio, hue: tone.hue(), semillaID: "entrenar-hilo")
                .frame(width: lado, height: lado)
                .accessibilityHidden(true)
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
#Preview("EntrenarHilo · 4 variantes") {
    VStack(alignment: .leading, spacing: 6) {
        EntrenarHilo(tone: .clear, word: "In range", advice: "your plan for today, as it is") {}
        EntrenarHilo(tone: .caution, word: "Go light today", advice: "don't add weight") {}
        EntrenarHilo(tone: .ease, word: "Recover", advice: "easy today, or rest") {}
        EntrenarHilo(tone: .hollow, word: "Getting to know you", advice: "no advice yet")
        EntrenarHilo(tone: .hollow, word: "Connect Apple Health") {}
    }
    .padding(24)
    .background(LiquidColor.fondoAlto)
}

#Preview("EntrenarHilo · los tres radios") {
    VStack(alignment: .leading, spacing: 6) {
        EntrenarHilo(tone: .clear, word: "In range", advice: "landing · 15.5") {}
        EntrenarHilo(tone: .clear, word: "In range", advice: "session · 11",
                     radio: EntrenarMetrics.orbeSesion) {}
        EntrenarHilo(tone: .clear, word: "In range", advice: "sheet · 20",
                     radio: EntrenarMetrics.orbeHoja) {}
    }
    .padding(24)
    .background(LiquidColor.fondoAlto)
}

#Preview("EntrenarHilo · xxxLarge") {
    VStack(alignment: .leading, spacing: 6) {
        EntrenarHilo(tone: .clear, word: "In range", advice: "your plan for today, as it is") {}
        EntrenarHilo(tone: .ease, word: "Recover", advice: "easy today, or rest") {}
        EntrenarHilo(tone: .hollow, word: "Getting to know you", advice: "no advice yet")
    }
    .padding(24)
    .background(LiquidColor.fondoAlto)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("EntrenarHilo · OLED") {
    VStack(alignment: .leading, spacing: 6) {
        EntrenarHilo(tone: .clear, word: "In range", advice: "your plan for today, as it is",
                     sobreOLED: true) {}
        EntrenarHilo(tone: .caution, word: "Go light today", advice: "don't add weight",
                     sobreOLED: true) {}
        EntrenarHilo(tone: .ease, word: "Recover", advice: "easy today, or rest",
                     sobreOLED: true) {}
        EntrenarHilo(tone: .hollow, word: "Getting to know you", advice: "no advice yet",
                     sobreOLED: true)
    }
    .padding(24)
    .background(LiquidOLED.fondo)
}
#endif
