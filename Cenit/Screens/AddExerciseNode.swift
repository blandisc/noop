#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - «＋ Agregar ejercicio» — la parada terminal del riel
//
// Vivía duplicado entre editar rutina y la sesión activa, con la misma anatomía y ya divergido en la
// voz: `StrandFont.subhead` (SF) en el editor contra `InstrumentoType.grotesk(14)` en la sesión. Es el
// mismo mal que curó `SetActionPills` el 2026-07-18, al que a este control nadie le llegó. Ahora es UN
// componente y las dos pantallas lo llaman (decisión Fer 2026-07-19).
//
// Decisiones que lo definen:
//
// · **El troquel punteado, no un relleno.** Traía `theme.patternBlock` (#EFEAE0) sobre papel (#F4F1E8):
//   **1.06:1**. No es que se viera pálido — es que la forma prácticamente no existía, y por eso el
//   intento de julio de «hacerlo más prominente» ensanchándolo no sirvió: ensanchar una forma invisible
//   da una forma invisible más grande. Ahora el chip no tiene relleno y su contorno **hereda el guion
//   del anillo** que vive 12 pt a su izquierda. El ember queda haciendo trabajo ESTRUCTURAL —prolonga
//   el riel, que ya es ember punteado— en vez de pintar chrome.
//
// · **No es tinta, a propósito.** Se evaluó rellenarlo de `theme.ink` para emparejarlo con «＋ Serie»
//   (`SetActionPills`) y se descartó: aquella es tinta porque es el gesto de cada minuto DENTRO de una
//   tarjeta, mientras este pasa una o dos veces por sesión y vive a nivel de pantalla. Dos losas de
//   tinta en el mismo scroll dejan dos primarios compitiendo y hacen que la acción rara grite igual que
//   la frecuente. El parentesco entre ambos lo cargan el glifo `+` y la geometría compartida (44 pt,
//   mismo radio, mismo inset), no el relleno: parecerse no es pesar lo mismo.
//
// · **El `+` se queda dentro del chip** (decisión Fer). Sí, el anillo del riel ya trae uno y son dos
//   glifos iguales en la misma fila; el dueño lo prefiere así porque el chip es el blanco táctil real y
//   el anillo se lee como marca decorativa del hilo. Anotado por si una auditoría futura lo cuestiona:
//   es deliberado, no un descuido.
//
// · **Alineado a la izquierda.** El contenido iba centrado mientras los nombres de ejercicio de arriba
//   van a la izquierda; compartir el borde lo mete en la lista en vez de dejarlo en su propia cajita.
//
// · **Grotesk 15.** `DESIGN.md` §8.7 le da a Grotesk los botones y a SF el cuerpo de texto, así que la
//   voz del editor era la deriva; 15 porque sus dos vecinos de la sesión (`SetActionPills` y
//   «Terminar») ya son 15. El hilo unifica en `StrandOpacity.strokeSoft`, que el editor ya usaba.
struct AddExerciseNode: View {
    let theme: InstrumentoTheme
    /// Tinte del hilo que baja de la última tarjeta — el editor pasa el de la última rutina, la sesión
    /// el del riel vivo.
    let threadTint: Color
    /// La sesión oculta el hilo cuando hay un solo ejercicio (no hay línea que continuar).
    var showThread: Bool = true
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // El hilo cae desde el tope de la fila y muere en el centro del anillo; ambos comparten
                // el carril de 14 pt, así que no pueden separarse (medido: 0.15 pt de desviación).
                ZStack {
                    VStack(spacing: 0) {
                        Rectangle().fill(threadTint.opacity(StrandOpacity.strokeSoft)).frame(width: 2)
                            .opacity(showThread ? 1 : 0)
                        Color.clear
                    }
                    Circle().fill(theme.paper)
                        .overlay(Circle().strokeBorder(theme.dataStrain,
                                                       style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "plus").font(.system(size: 9, weight: .bold))  // token-exempt: glifo diminuto dimensionado al anillo de 18 pt
                                .foregroundStyle(theme.dataStrain)
                        )
                }
                .frame(width: 14)

                HStack(spacing: 8) {
                    StrandIcon.add.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                        .foregroundStyle(theme.dataStrain)
                    Text("Add exercise")
                        .font(InstrumentoType.grotesk(15, weight: .semibold))
                        .foregroundStyle(theme.inkSecondary)
                }
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .overlay(shape.strokeBorder(theme.dataStrain.opacity(StrandOpacity.strokeSoft),
                                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
            }
            .frame(minHeight: 44 + CenitMetrics.gap)   // el aire propio de la fila, no un hueco inset
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add exercise"))
    }
}

#if DEBUG
#Preview("AddExerciseNode") {
    VStack(spacing: 0) {
        AddExerciseNode(theme: .base, threadTint: InstrumentoTheme.base.dataHrv) {}
        AddExerciseNode(theme: .base, threadTint: InstrumentoTheme.base.dataStrain, showThread: false) {}
    }
    .padding(.horizontal, CenitMetrics.screenPadding)
    .background(InstrumentoTheme.base.paper)
}
#endif
#endif
