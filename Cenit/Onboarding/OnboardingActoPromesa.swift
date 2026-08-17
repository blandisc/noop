import SwiftUI
import StrandDesign

// MARK: - Actos 1 y 2 (+ la salida)  ·  FER-109
//
// El acto 1 promete y el 2 pide. Entre los dos no hay pantalla de relleno: el 2 ES el diagrama de
// pesos, así que quien concede el permiso ya sabe qué firma y con qué peso entra cada señal.
//
// El campo de partículas se comporta distinto en cada uno, y eso también es contenido:
//   · acto 1 `.disperso` — la materia se junta sola mientras lees. Todavía no hay evidencia
//     ninguna; lo que se ve es el campo presentándose, y por eso topa a la mitad y no cuaja.
//   · acto 2 `.quieto` — CONGELADO. Nada avanza hasta que la persona decide el permiso, que es
//     exactamente la verdad del momento: sin su sí, la app no puede dar un paso más.

// MARK: - Acto 1 · La promesa

struct OnbActoPromesa: View {
    @Binding var densidad: Double
    let onEmpezar: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrancada = false

    var body: some View {
        OnbShell {
            Spacer(minLength: LiquidSpace.s800)

            // La marca no se traduce ni entra al catálogo: es un nombre propio.
            OnbOverline("Cénit")
            OnbTitular(OnbCopy.promesaTitular)
                .padding(.top, LiquidSpace.s250)
            OnbCuerpo(OnbCopy.promesaCuerpo)
                .padding(.top, LiquidSpace.s400)

            Spacer(minLength: LiquidSpace.s800)

            // La privacidad es UNA LÍNEA, no una tarjeta: convertirla en tarjeta la vuelve un
            // aviso legal, y aquí es una invitación a comprobarlo (modo avión) en el momento.
            OnbCuerpo(OnbCopy.promesaPrivacidad, tono: LiquidColor.tinta500)
                .padding(.bottom, LiquidSpace.s400)

            LiquidGlassButton(OnbCopy.empezar, variant: .primary, expands: true, action: onEmpezar)
        }
        .task {
            guard !arrancada else { return }
            arrancada = true
            // Reduce Motion: el mismo destino, sin rampa larga. Un fundido no es movimiento
            // (la propia simulación hace crossfade de densidad ahí), así que el beat no se pierde.
            let anim = reduceMotion
                ? LiquidEcosistemaMotion.reduceCrossfadeAnim
                : LiquidMotion.ambient(OnbGuion.acumulacionPromesa)
            withAnimation(anim) { densidad = OnbGuion.densidadPromesa }
        }
    }
}

// MARK: - Acto 2 · El permiso, que es el diagrama de pesos

struct OnbActoPermiso: View {
    let onAtras: () -> Void
    let onConectar: @MainActor () async -> Void
    let onAhoraNo: () -> Void

    @State private var pidiendo = false

    var body: some View {
        // Los `Group` son puramente estructurales: SwiftUI tope los hijos de un builder en 10 y
        // este diagrama tiene 17. `Group` es transparente para el layout, así que cada renglón
        // sigue siendo hermano directo del `VStack` del shell (y los `Spacer` siguen empujando).
        OnbShell {
            Group {
                OnbAtras(accion: onAtras)

                OnbTitular(OnbCopy.permisoTitular)
                    .padding(.top, LiquidSpace.s250)
                OnbCuerpo(OnbCopy.permisoCuerpo)
                    .padding(.top, LiquidSpace.s300)
            }

            // La que sostiene todo.
            Group {
                OnbOverline(OnbCopy.permisoGrupoSostiene)
                    .padding(.top, LiquidSpace.s800)
                OnbFila(nombre: OnbCopy.permisoRhr, tono: LiquidColor.rosa,
                        glosa: OnbCopy.permisoRhrGlosa)
            }

            // Las que votan contigo.
            Group {
                OnbOverline(OnbCopy.permisoGrupoVotan)
                    .padding(.top, LiquidSpace.s600)
                OnbFila(nombre: OnbCopy.permisoSueno, tono: LiquidColor.indigo,
                        glosa: OnbCopy.permisoSuenoGlosa)
                OnbFila(nombre: OnbCopy.permisoTemp, tono: LiquidColor.doradoTemp,
                        glosa: OnbCopy.permisoTempGlosa)
                OnbFila(nombre: OnbCopy.permisoVfcNoche, tono: LiquidColor.cian,
                        glosa: OnbCopy.permisoVfcNocheGlosa)
            }

            // El capilar separa a las que DECIDEN de las que solo miran: es la frontera del
            // diagrama, y sin él las seis señales se leen como una sola lista con jerarquía
            // tipográfica. Sin hue las de abajo: no votan, así que no llevan identidad de
            // color, y esa ausencia ES el dato.
            Group {
                OnbHairline()
                    .padding(.top, LiquidSpace.s600)
                OnbOverline(OnbCopy.permisoGrupoVigilan)
                    .padding(.top, LiquidSpace.s600)
                OnbFila(nombre: OnbCopy.permisoResp, tono: nil, glosa: OnbCopy.permisoRespGlosa)
                OnbFila(nombre: OnbCopy.permisoVfcDia, tono: nil, glosa: OnbCopy.permisoVfcDiaGlosa)
            }

            // La nota que evita el error caro: Apple abre el permiso APAGADO y una concesión
            // parcial es indistinguible de una negada (HealthKit nunca revela el permiso de
            // lectura), así que el app no puede decir cuál falta.
            Group {
                VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                    OnbCuerpo(OnbCopy.permisoNotaFuerte, fuerte: true)
                    OnbCuerpo(OnbCopy.permisoNotaCuerpo, tono: LiquidColor.tinta500)
                }
                .padding(.top, LiquidSpace.s600)
                .accessibilityElement(children: .combine)

                Spacer(minLength: LiquidSpace.s600)

                LiquidGlassButton(OnbCopy.conectar, variant: .primary, expands: true) {
                    guard !pidiendo else { return }
                    pidiendo = true
                    Task { @MainActor in
                        await onConectar()
                        pidiendo = false
                    }
                }
                .disabled(pidiendo)
                OnbSalidaTexto(titulo: OnbCopy.ahoraNo, accion: onAhoraNo)
                    .disabled(pidiendo)
            }
        }
    }
}

// MARK: - Salida · «Ahora no»

/// No es un callejón: dice qué se pierde, qué sigue funcionando, y deja las dos puertas abiertas.
/// «No te voy a insistir» es literal — esta pantalla no vuelve a aparecer sola.
struct OnbActoSalida: View {
    let onReconsiderar: () -> Void
    let onEntrar: () -> Void

    var body: some View {
        OnbShell {
            Spacer(minLength: LiquidSpace.s600)

            OnbOverline(OnbCopy.salidaOverline)
            OnbTitular(OnbCopy.salidaTitular)
                .padding(.top, LiquidSpace.s250)
            OnbCuerpo(OnbCopy.salidaCuerpo)
                .padding(.top, LiquidSpace.s400)

            VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                OnbCuerpo(OnbCopy.salidaSi)
                OnbCuerpo(OnbCopy.salidaNo, tono: LiquidColor.tinta500)
            }
            .padding(.top, LiquidSpace.s600)

            OnbCuerpo(OnbCopy.salidaPie, tono: LiquidColor.tinta500)
                .padding(.top, LiquidSpace.s600)

            Spacer(minLength: LiquidSpace.s600)

            LiquidGlassButton(OnbCopy.salidaCta, variant: .primary, expands: true,
                              action: onReconsiderar)
            OnbSalidaTexto(titulo: OnbCopy.salidaCtaSecundaria, accion: onEntrar)
        }
    }
}
