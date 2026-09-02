#if os(iOS)
import SwiftUI
import StrandDesign

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
//   del hub, y el motivo es medible: `patternBlock` (#EFEAE0) sobre papel (#F4F1E8) da **1.06:1** — la
//   forma prácticamente no existe. Con `surface` + `hairlineStrong` (1.36:1 de borde) el control se
//   lee, y un botón que flota sobre una lista en scroll NECESITA leerse. El hub hereda la corrección
//   de paso.
//
// · **`prominent` para la salida de un flujo.** En el flujo de CREACIÓN el botón no agrega a algo que
//   ya existe: es la SALIDA («Crear rutina con 3»). Ahí se llena de `dataStrain` como cualquier CTA
//   terminal. En el modo agregar-a-lo-que-ya-existe se queda con borde: es una acción más, no el final
//   del camino.
//
// · **El glifo es `add`.** ICONOGRAFIA §3 lo reserva para «agregar» — mismo verbo glífico que las
//   píldoras de serie y el nodo del riel, de modo que toda la familia «agregar» se lea igual.
struct InstrumentoAddButton: View {
    let theme: InstrumentoTheme
    /// El texto ya resuelto (los dos sitios lo arman con conteos y plurales del catálogo).
    let label: String
    /// Salida de un flujo (relleno sólido) contra una acción más de la lista (contorno).
    var prominent: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
    }

    private var foreground: Color {
        if disabled { return theme.inkTertiary }
        return prominent ? theme.paper : theme.ink
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !disabled {
                    StrandIcon.add.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                }
                Text(verbatim: label).font(InstrumentoType.grotesk(15, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(prominent && !disabled ? AnyShapeStyle(theme.dataStrain) : AnyShapeStyle(theme.surface),
                        in: shape)
            .overlay(shape.strokeBorder(prominent && !disabled ? .clear : theme.hairlineStrong, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

#if DEBUG
#Preview("InstrumentoAddButton") {
    VStack(spacing: 12) {
        InstrumentoAddButton(theme: .base, label: "Nueva rutina") {}
        InstrumentoAddButton(theme: .base, label: "Agregar 3 ejercicios") {}
        InstrumentoAddButton(theme: .base, label: "Crear rutina con 3", prominent: true) {}
        InstrumentoAddButton(theme: .base, label: "Elige al menos un ejercicio", disabled: true) {}
    }
    .padding(LiquidSpace.s600)
    .background(InstrumentoTheme.base.paper)
}
#endif
#endif
