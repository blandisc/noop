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
// · **El primario es TINTA, no ember.** Un relleno de esfuerzo medido es cromo pintado con el color que el
//   DNA reserva para el dato: gastarlo en un botón le quita significado al siguiente número ámbar
//   que aparezca. La tinta sobre papel pesa más por contraste y no toca la paleta de datos.
//
// · **El calentamiento conserva su caja.** Se muestra UNA vez por ejercicio y desaparece para siempre en
//   cuanto existe la rampa; sin contorno, un control tan efímero se vuelve indescubrible justo en el
//   contexto de menos atención — en plena sesión.
//
// · **44 pt de alto en ambas.** El editor traía 34, por debajo del mínimo de la HIG. Era un bug heredado,
//   no una decisión de densidad. `.lg` dibuja a 36 y expande el toque a 44.
//
// · **El glifo conjuga: `+` en las DOS** (decisión Fer 2026-07-19). La derecha traía la llama, y ahí estaba
//   la raíz del bug de dos renglones: el glifo cargaba el DOMINIO (calor) en vez del verbo, así que la
//   palabra tuvo que cargar verbo y objeto — «Agregar calentamiento», 21 caracteres en una píldora de media
//   fila. Con `+` enfrente, el sustantivo se vuelve el objeto de un verbo ya dicho y basta «Calentamiento»
//   (13, el mismo presupuesto que su gemela). Probar «Calentamiento» CON la llama se rechazó primero, y con
//   razón: un sustantivo desnudo tras un glifo de dominio se lee como destino, no como acción.
//   `docs/design-system/ICONOGRAFIA.md` §3 ya reservaba `add` para «agregar» y §2 asignaba `flame` a
//   «esfuerzo/calorías» — la llama hacía un trabajo que la doctrina le prohíbe. El verbo sobrevive completo
//   en el `accessibilityLabel`: la vista suelta el verbo, VoiceOver lo conserva.
//   Ojo: `"Add warm-up"` sigue viva como llave del MENÚ en `LiveStrengthSheet` (:2470), que hace otra cosa
//   —abre la hoja de discos, no inserta— por eso estas píldoras estrenaron llaves propias en vez de
//   reescribir aquella.
struct SetActionPills: View {
    let showWarmup: Bool
    let addSet: () -> Void
    let addWarmup: () -> Void

    var body: some View {
        HStack(spacing: LiquidSpace.s200) {
            OutlineCapsule(
                theme: .base,
                size: .lg,
                estilo: .outline,
                filled: true,
                fill: LiquidColor.tinta900,
                action: addSet
            ) {
                HStack(spacing: LiquidSpace.s150) {
                    StrandIcon.add.image.font(LiquidType.infoGlifoCompacto.weight(.semibold))
                    Text("Set")
                }
                .font(LiquidType.tituloGemela)
                .foregroundStyle(LiquidColor.papelTarjeta)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text("Add set"))

            if showWarmup {
                OutlineCapsule(
                    theme: .base,
                    size: .lg,
                    estilo: .vidrio,
                    action: addWarmup
                ) {
                    HStack(spacing: LiquidSpace.s150) {
                        StrandIcon.add.image.font(LiquidType.infoGlifoCompacto.weight(.semibold))
                        Text("Warm-up")
                    }
                    .font(LiquidType.tituloGemela)
                    .foregroundStyle(LiquidColor.ambar)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("Add warm-up"))
            }
        }
    }
}

#if DEBUG
#Preview("SetActionPills") {
    VStack(spacing: LiquidSpace.s600) {
        SetActionPills(showWarmup: true, addSet: {}, addWarmup: {})
        SetActionPills(showWarmup: false, addSet: {}, addWarmup: {})
    }
    .padding()
    .background(LiquidColor.fondoAlto)
}
#endif
#endif
