#if os(iOS)
import SwiftUI
import CenitDesign

// MARK: - El botón de «agregar algo a una lista» — una sola anatomía
//
// «＋ Nueva rutina» (hub Entrenar) y el botón flotante de la Biblioteca de ejercicios («Agregar 3
// ejercicios» / «Crear rutina con 3») hacían el mismo trabajo con dos anatomías distintas: uno de
// ancho completo con relleno `patternBlock` y Grotesk 14, el otro una cápsula CTA con `ctaRadius`,
// Grotesk 15 bold y relleno `surface`. Ahora es UN componente (decisión Fer 2026-07-19).
//
// Decisiones que lo definen:
//
// · **Superficie con borde, no `patternBlock`.** La anatomía ganadora es la del botón flotante, no la
//   del hub, y el motivo es medible: `patternBlock` sobre papel daba contraste casi nulo (la forma
//   prácticamente no existía). Con papel de tarjeta + borde de vidrio fuerte el control se lee, y un
//   botón que flota sobre una lista en scroll NECESITA leerse. El hub hereda la corrección de paso.
//
// · **`prominent` para la salida de un flujo.** En el flujo de CREACIÓN el botón no agrega a algo que
//   ya existe: es la SALIDA («Crear rutina con 3»). Ahí se llena de ámbar como cualquier CTA
//   terminal. En el modo agregar-a-lo-que-ya-existe se queda con borde: es una acción más, no el final
//   del camino.
//
// · **El glifo es `add`.** ICONOGRAFIA §3 lo reserva para «agregar» — mismo verbo glífico que las
//   píldoras de serie y el nodo del riel, de modo que toda la familia «agregar» se lea igual.
struct InstrumentoAddButton: View {
    /// El texto ya resuelto (los dos sitios lo arman con conteos y plurales del catálogo).
    let label: String
    /// Salida de un flujo (relleno sólido) contra una acción más de la lista (contorno).
    var prominent: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiquidRadius.insetTarjeta, style: .continuous)
    }

    private var foreground: Color {
        if disabled { return LiquidColor.tinta500 }
        return prominent ? LiquidColor.papelTarjeta : LiquidColor.tinta900
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: LiquidSpace.s200) {
                if !disabled {
                    CenitIcon.add.image.font(LiquidType.iconSF(size: 15))
                }
                Text(verbatim: label)
                    .font(LiquidType.boton)
                    .tracking(LiquidType.botonTracking)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(prominent && !disabled ? AnyShapeStyle(LiquidColor.ambar) : AnyShapeStyle(LiquidColor.papelTarjeta),
                        in: shape)
            .overlay(shape.strokeBorder(prominent && !disabled ? .clear : LiquidColor.vidrioBordeFuerte, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

#if DEBUG
#Preview("InstrumentoAddButton") {
    VStack(spacing: LiquidSpace.s300) {
        InstrumentoAddButton(label: "Nueva rutina") {}
        InstrumentoAddButton(label: "Agregar 3 ejercicios") {}
        InstrumentoAddButton(label: "Crear rutina con 3", prominent: true) {}
        InstrumentoAddButton(label: "Elige al menos un ejercicio", disabled: true) {}
    }
    .padding(LiquidSpace.s600)
    .background(LiquidColor.fondoAlto)
}
#endif
#endif
