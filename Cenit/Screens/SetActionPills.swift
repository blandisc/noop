#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - «＋ Serie» / «Calentamiento» — el par que cierra la tarjeta de un ejercicio
//
// Vivía duplicado y DIVERGIDO entre editar rutina y la sesión activa: rectángulos contra cápsulas, gemelos
// al 50 % contra pills al contenido, gris hundido contra naranja sólido, 34 pt contra 44. Dos pantallas
// que deberían sentirse la misma se sentían de apps distintas (decisión Fer 2026-07-18). Ahora es UN
// componente y las dos lo llaman.
//
// Decisiones que lo definen:
//
// · **Gemelos de ancho completo.** El par se reparte la fila. Cuando ya hay rampa de calentamiento el
//   control desaparece y «Serie» se queda con todo el ancho — el hueco no queda flotando.
//
// · **El primario es TINTA, no ember.** Un relleno `dataStrain` es cromo pintado con el color que el DNA
//   reserva para el esfuerzo medido: gastarlo en un botón le quita significado al siguiente número naranja
//   que aparezca. La tinta sobre papel pesa más por contraste y no toca la paleta de datos.
//
// · **El calentamiento conserva su caja.** Se muestra UNA vez por ejercicio y desaparece para siempre en
//   cuanto existe la rampa; sin contorno, un control tan efímero se vuelve indescubrible justo en el
//   contexto de menos atención — en plena sesión.
//
// · **44 pt de alto en ambas.** El editor traía 34, por debajo del mínimo de la HIG. Era un bug heredado,
//   no una decisión de densidad.
struct SetActionPills: View {
    let showWarmup: Bool
    let theme: InstrumentoTheme
    let addSet: () -> Void
    let addWarmup: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: CenitMetrics.space2) {
            Button(action: addSet) {
                HStack(spacing: 6) {
                    StrandIcon.add.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                    Text("Add set")
                }
                .font(InstrumentoType.grotesk(15, weight: .semibold)).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(theme.ink, in: shape)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add set"))

            if showWarmup {
                Button(action: addWarmup) {
                    HStack(spacing: 6) {
                        StrandIcon.flame.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                        Text("Add warm-up")
                    }
                    .font(InstrumentoType.grotesk(15, weight: .medium)).foregroundStyle(theme.dataStrain)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(shape.strokeBorder(theme.dataStrain.opacity(StrandOpacity.strokeSoft), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add warm-up"))
            }
        }
    }
}

#if DEBUG
#Preview("SetActionPills") {
    VStack(spacing: 20) {
        SetActionPills(showWarmup: true, theme: .base, addSet: {}, addWarmup: {})
        SetActionPills(showWarmup: false, theme: .base, addSet: {}, addWarmup: {})
    }
    .padding()
    .background(InstrumentoTheme.base.paper)
}
#endif
#endif
