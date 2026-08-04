import SwiftUI

// MARK: - Liquid Glass · Pie de hoja de resumen (épico hoja Liquid, F1/F6)
//
// Los remates del pie, como componentes independientes (la hoja los compone en orden):
//   · `LiquidMetodo` — «Cómo se calcula» plegable (prosa + cita), transparencia matemática.
//   · `LiquidOrigenChip` — pastilla de procedencia DENTRO del plegable (FER-33 · F0.4a).
//   · `LiquidNotaLine` — nota corta / línea de conectar Apple Salud.
//   · `LiquidVerMas` — el enlace al detalle rico; ancho completo con el glifo de Tendencias
//     cuando la métrica vive en niveles, compacto a la derecha si no.
// Strings YA localizados; el DS no conoce locales.

public struct LiquidMetodo<Content: View>: View {
    private let title: String
    private let mostrar: String?
    private let ocultar: String?
    private let content: Content
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// B6 · a11y del plegable (mismo contrato L5 que el ⓘ de la cabecera):
    /// `mostrar`/`ocultar` son la etiqueta de VoiceOver del botón, YA localizadas por el
    /// caller — `StrandDesign` no tiene catálogo. Sin ellas el label es el propio título.
    /// El `accessibilityValue` «1»/«0» se retiró en ambos caminos: VoiceOver leía
    /// «Cómo se calcula, uno», que no significa nada.
    public init(title: String, mostrar: String? = nil, ocultar: String? = nil,
                @ViewBuilder content: () -> Content) {
        self.title = title
        self.mostrar = mostrar
        self.ocultar = ocultar
        self.content = content()
    }

    private var etiquetaVO: String {
        (open ? (ocultar ?? mostrar) : (mostrar ?? ocultar)) ?? title
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Button {
                if reduceMotion {
                    open.toggle()
                } else {
                    withAnimation(LiquidMotion.lift) { open.toggle() }
                }
            } label: {
                HStack(spacing: LiquidSpace.s150) {
                    LiquidIcon(.chevron, size: 9, color: LiquidColor.tinta500)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(title)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.liquidPress)
            .accessibilityLabel(Text(verbatim: etiquetaVO))
            if open {
                content
                    .padding(.leading, LiquidSpace.s400)
            }
        }
    }
}

/// FER-29 · El chip de procedencia que vive DENTRO del bloque «Cómo se calcula» (mock
/// canónico `sheet-generica-final` / `sheet-sueno-final`): una pastilla de papel con una
/// gota-badge (el glifo de la fuente en blanco sobre un cuadro del tono) + la etiqueta de
/// procedencia y un sufijo tenue. El DS no nombra «Apple»: la etiqueta y el sufijo llegan
/// YA localizados del caller (mismo contrato cerrado que `LiquidOrigen`). Es cromo, no
/// dato: tamaño fijo. Se lee como UN elemento en VoiceOver (el badge es decorativo).
public struct LiquidOrigenChip: View {
    private let glyph: LiquidIcon.Glyph
    private let badgeTono: Color
    private let etiqueta: String
    private let sufijo: String?

    /// Geometría interna del badge (contrato §5: candidato menor, no token del sistema).
    private static let badge: CGFloat = 16
    private static let badgeGlifo: CGFloat = 9

    public init(glyph: LiquidIcon.Glyph, badgeTono: Color,
                etiqueta: String, sufijo: String? = nil) {
        self.glyph = glyph
        self.badgeTono = badgeTono
        self.etiqueta = etiqueta
        self.sufijo = sufijo
    }

    public var body: some View {
        HStack(spacing: LiquidSpace.s150) {
            RoundedRectangle(cornerRadius: LiquidSpace.s100, style: .continuous)
                .fill(badgeTono)
                .frame(width: Self.badge, height: Self.badge)
                .overlay(LiquidIcon(glyph, size: Self.badgeGlifo, color: .white))
                .accessibilityHidden(true)
            HStack(spacing: LiquidSpace.s100) {
                Text(verbatim: etiqueta)
                    .foregroundStyle(LiquidColor.tinta700)
                if let sufijo {
                    Text(verbatim: "·").foregroundStyle(LiquidColor.tinta500)
                    Text(verbatim: sufijo).foregroundStyle(LiquidColor.tinta500)
                }
            }
            .font(LiquidType.captionLectura)
        }
        .padding(.leading, LiquidSpace.s150)
        .padding(.trailing, LiquidSpace.s300)
        .padding(.vertical, LiquidSpace.s125)
        .background(LiquidColor.papelAlto.opacity(0.65), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(LiquidColor.tinta10, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Nota corta del pie (nota de método, o la línea de conectar Apple Salud).
///
/// El `tono` es tinta quieta por defecto — la nota acompaña, no llama. El caller solo lo
/// sube (a `LiquidColor.atencionTexto`) cuando la nota AVISA algo que cambia la lectura de
/// lo que está viendo: p. ej. «se muestran los últimos N días» cuando la ventana se
/// ensanchó sola. Recolorear el componente entero teñiría todas las notas de todas las
/// hojas, que es justo lo que no queremos.
public struct LiquidNotaLine: View {
    private let text: String
    private let tono: Color

    public init(_ text: String, tono: Color = LiquidColor.tinta500) {
        self.text = text
        self.tono = tono
    }

    public var body: some View {
        Text(verbatim: text)
            .font(LiquidType.captionLectura)
            .foregroundStyle(tono)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// El enlace «Ver más» al detalle rico.
public struct LiquidVerMas: View {
    private let title: String
    private let hint: String?
    private let tone: Color
    private let anchoCompleto: Bool
    private let action: () -> Void

    public init(title: String, hint: String? = nil, tone: Color,
                anchoCompleto: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.hint = hint
        self.tone = tone
        self.anchoCompleto = anchoCompleto
        self.action = action
    }

    public var body: some View {
        if anchoCompleto {
            Button(action: action) {
                // El glifo de Tendencias a la IZQUIERDA del rótulo (la variante de ancho
                // completo es siempre «Ver más en Tendencias»): el pie dibuja la pantalla a
                // la que lleva, con el mismo arte de la pestaña del dock. En tinta/900 —
                // acompaña al rótulo, no compite con el dato. Tamaño fijo: es cromo.
                HStack(spacing: LiquidSpace.s200) {
                    LiquidIcon(.tendencias, size: 18, color: LiquidColor.tinta900)
                        .accessibilityHidden(true)
                    Text(verbatim: title)
                        .font(LiquidType.boton).tracking(LiquidType.botonTracking)
                        .foregroundStyle(LiquidColor.tinta900)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, LiquidSpace.s300)
            }
            .buttonStyle(.liquidPress)
            .liquidGlass(.pastillaSolida)
            .accessibilityHint(Text(verbatim: hint ?? ""))
        } else {
            HStack {
                Spacer(minLength: 0)
                Button(action: action) {
                    HStack(spacing: LiquidSpace.s100) {
                        Text(verbatim: title)
                            .font(LiquidType.boton).tracking(LiquidType.botonTracking)
                        LiquidIcon(.chevron, size: 9, color: tone)
                    }
                    .foregroundStyle(tone)
                    .padding(.horizontal, LiquidSpace.s400)
                    .padding(.vertical, LiquidSpace.s200)
                    .background(tone.opacity(0.10), in: Capsule(style: .continuous))
                }
                .buttonStyle(.liquidPress)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityHint(Text(verbatim: hint ?? ""))
            }
        }
    }
}

#if DEBUG
#Preview("Liquid · SheetFoot") {
    VStack(alignment: .leading, spacing: LiquidSpace.s550) {
        // B6 · con etiquetas de VoiceOver propias (nunca las del ⓘ: son dos controles
        // distintos en la misma hoja y con el mismo rótulo se vuelven indistinguibles).
        LiquidMetodo(title: "Cómo se calcula",
                     mostrar: "Ver cómo se calcula",
                     ocultar: "Ocultar cómo se calcula") {
            LiquidNotaLine("SDNN sobre los latidos nocturnos, comparado contra tu base de 21 noches (Task Force, 1996).")
            LiquidOrigenChip(glyph: .corazon, badgeTono: LiquidColor.rosa,
                             etiqueta: "Apple Salud", sufijo: "en tu dispositivo")
        }
        // El chip calculado (esfuerzo/estrés): badge tenue, sin sufijo.
        LiquidOrigenChip(glyph: .rayo, badgeTono: LiquidColor.tinta500,
                         etiqueta: "Calculado en el teléfono")
        LiquidNotaLine("Conecta Apple Salud para ver tu VFC aquí.")
        LiquidNotaLine("Se muestran los últimos 47 días.", tono: LiquidColor.atencionTexto)
        LiquidVerMas(title: "Ver más en Tendencias", hint: "Abre el detalle completo",
                     tone: LiquidColor.cian, anchoCompleto: true, action: {})
        LiquidVerMas(title: "Ver más", hint: "Abre el detalle completo",
                     tone: LiquidColor.cian, action: {})
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}

#endif
