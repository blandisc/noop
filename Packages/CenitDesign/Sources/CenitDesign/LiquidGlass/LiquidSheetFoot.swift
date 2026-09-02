import SwiftUI

// MARK: - Liquid Glass · Pie de hoja de resumen (épico hoja Liquid, F1/F6)
//
// Los remates del pie, como componentes independientes (la hoja los compone en orden):
//   · `LiquidMetodo` — «Cómo se calcula» plegable (prosa + cita), transparencia matemática.
//   · `LiquidOrigenChip` — pastilla de procedencia DENTRO del plegable (FER-33 · F0.4a).
//   · `LiquidNotaLine` — nota corta / línea de conectar Apple Salud (y, en su otra voz,
//     la fila de acuerdo de fusión; vive en `LiquidNotaLine.swift`).
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
    /// caller — `CenitDesign` no tiene catálogo. Sin ellas el label es el propio título.
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
                        // #inject r4 · Sube de caption (10.5) a footnote/semibold: «Cómo se
                        // calcula» es un CONTROL tocable, no letra chica — a caption se
                        // perdía (dueño). Mock `.metodo{12px/600}`; tinta700 para que se
                        // lea como acción sin competir con los datos.
                        .font(LiquidType.filaRango)
                        .foregroundStyle(LiquidColor.tinta700)
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

/// FER-294 · Pastilla de procedencia en listas/detalle de entrenamiento (gemelo Liquid de
/// `SourceBadge`). Label YA localizado; `tono: nil` = neutro (`tinta7` + `tinta10` + `tinta700`).
/// Distinto de `LiquidOrigenChip` (pie de hoja con glifo): aquí es solo texto caps en cápsula.
public struct LiquidOrigenBadge: View {
    private let label: String
    private let tono: Color?

    public init(_ label: String, tono: Color?) {
        self.label = label
        self.tono = tono
    }

    public var body: some View {
        Text(verbatim: label)
            .textCase(.uppercase)
            .font(LiquidType.microEstado)
            .foregroundStyle(texto)
            .padding(.horizontal, LiquidSpace.chipHorizontal)
            .padding(.vertical, LiquidSpace.s075)
            .background(relleno, in: Capsule())
            .overlay(Capsule().strokeBorder(canto, lineWidth: 0.5))
            .accessibilityElement(children: .combine)
    }

    private var relleno: Color {
        if let tono { return tono.opacity(LiquidTono.intensidadDefault) }
        return LiquidColor.tinta7
    }

    private var canto: Color {
        if let tono { return tono.opacity(LiquidTonoMetrics.cantoAlfaTeñido) }
        return LiquidColor.tinta10
    }

    private var texto: Color {
        if let tono { return LiquidColor.tonoCampo(tono) }
        return LiquidColor.tinta700
    }
}

/// FER-29 · El chip de procedencia que vive DENTRO del bloque «Cómo se calcula» (mock
/// canónico `sheet-generica-final` / `sheet-sueno-final`): una pastilla de papel con una
/// gota-badge (el glifo de la fuente en blanco sobre un cuadro del tono) + la etiqueta de
/// procedencia y un sufijo tenue. El DS no nombra «Apple»: la etiqueta y el sufijo llegan
/// YA localizados del caller (mismo contrato cerrado que `LiquidOrigen`). Es cromo, no
/// dato: tamaño fijo. Se lee como UN elemento en VoiceOver (el badge es decorativo).
public struct LiquidOrigenChip: View {
    /// `nil` = la fuente no tiene glifo canónico (TND31-4): en vez de inventar uno (un `.rayo` teñido
    /// mentía «calculado» para las ~28 métricas del Explorador sin glifo), la identidad la lleva SOLO
    /// el punto de tono. Los demás call sites pasan un glifo concreto → badge, sin cambio de conducta.
    private let glyph: LiquidIcon.Glyph?
    private let badgeTono: Color
    private let etiqueta: String
    private let sufijo: String?

    /// Geometría interna del badge (contrato §5: candidato menor, no token del sistema).
    private static let badge: CGFloat = 16
    private static let badgeGlifo: CGFloat = 9
    /// El punto de tono que sustituye al badge cuando no hay glifo: menor que el badge, centrado en su
    /// mismo hueco de 16 pt para que la fila no salte entre una fuente con glifo y una sin él.
    private static let punto: CGFloat = 8

    public init(glyph: LiquidIcon.Glyph? = nil, badgeTono: Color,
                etiqueta: String, sufijo: String? = nil) {
        self.glyph = glyph
        self.badgeTono = badgeTono
        self.etiqueta = etiqueta
        self.sufijo = sufijo
    }

    /// TND31-4 · contrato verificable: el badge de glifo SOLO existe con un glifo canónico. Sin él se
    /// dibuja el punto de tono, nunca un glifo inventado. (Fijado por `LiquidGlassTests`.)
    var dibujaBadge: Bool { glyph != nil }

    public var body: some View {
        HStack(spacing: LiquidSpace.s150) {
            if let glyph {
                RoundedRectangle(cornerRadius: LiquidSpace.s100, style: .continuous)
                    .fill(badgeTono)
                    .frame(width: Self.badge, height: Self.badge)
                    .overlay(LiquidIcon(glyph, size: Self.badgeGlifo, color: .white))
                    .accessibilityHidden(true)
            } else {
                // Sin glifo canónico: identidad por el punto de tono, mismo hueco que el badge.
                Circle()
                    .fill(badgeTono)
                    .frame(width: Self.punto, height: Self.punto)
                    .frame(width: Self.badge, height: Self.badge)
                    .accessibilityHidden(true)
            }
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
        // TND31-4 · fuente sin glifo canónico: punto de tono en vez de un glifo inventado.
        LiquidOrigenChip(glyph: nil, badgeTono: LiquidColor.verdePrimario,
                         etiqueta: "En tu dispositivo")
        LiquidNotaLine("Conecta Apple Salud para ver tu VFC aquí.")
        LiquidNotaLine("Se muestran los últimos 47 días.", tono: LiquidColor.atencionTexto)
        HStack(spacing: LiquidSpace.s200) {
            LiquidOrigenBadge("Apple", tono: LiquidColor.azul)
            LiquidOrigenBadge("Manual", tono: nil)
            LiquidOrigenBadge("Medido en el dispositivo", tono: LiquidColor.verdePrimario)
        }
        LiquidVerMas(title: "Ver más en Tendencias", hint: "Abre el detalle completo",
                     tone: LiquidColor.cian, anchoCompleto: true, action: {})
        LiquidVerMas(title: "Ver más", hint: "Abre el detalle completo",
                     tone: LiquidColor.cian, action: {})
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}

#endif
