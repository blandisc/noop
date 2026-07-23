import SwiftUI

// MARK: - Liquid Glass · Pie de hoja de resumen (épico hoja Liquid, F1/F6)
//
// Los tres remates del pie, como componentes independientes (la hoja los compone en orden):
//   · `LiquidMetodo` — «Cómo se calcula» plegable (prosa + cita), transparencia matemática.
//   · `LiquidNotaLine` — nota corta / línea de conectar Apple Salud.
//   · `LiquidVerMas` — el enlace al detalle rico; ancho completo con el glifo de Tendencias
//     cuando la métrica vive en niveles, compacto a la derecha si no.
// Strings YA localizados; el DS no conoce locales.

public struct LiquidMetodo<Content: View>: View {
    private let title: String
    private let content: Content
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
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
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityValue(Text(verbatim: open ? "1" : "0"))
            if open {
                content
                    .padding(.leading, LiquidSpace.s400)
            }
        }
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
            .liquidGlass(.pastilla)
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
        LiquidMetodo(title: "Cómo se calcula") {
            LiquidNotaLine("SDNN sobre los latidos nocturnos, comparado contra tu base de 21 noches (Task Force, 1996).")
        }
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
