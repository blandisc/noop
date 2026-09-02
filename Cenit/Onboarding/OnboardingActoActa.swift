import SwiftUI
import CenitDesign
import StrandAnalytics

// MARK: - Acto 5 · El acta (FER-109)
//
// De qué está hecha la palabra. El lienzo entra en `.descomposicion`: el orbe se desarma en tres
// pozos, uno por eje, DELANTE del usuario — es el mismo gesto que el acta explica en texto, y por
// eso la pantalla no necesita un diagrama aparte.
//
// Dos cosas que este acto NO hace, a propósito:
//   · **No inventa un puntaje.** No hay 0 a 100 en ninguna parte de la app, y el acto lo dice en
//     su primera línea en vez de dejar que el usuario lo suponga.
//   · **No re-escribe las cuatro palabras.** Salen de `LiquidHoyBuilder` (las mismas claves del
//     catálogo que dice el héroe). Aquí solo viven sus GLOSAS, que son de este acto.
//
// El titular es la palabra del veredicto, teñida, pero a talla de titular (22): la única talla de
// 30 en todo el flujo es el reveal del acto 4, y repetirla aquí le quitaría lo que la hace única.

struct OnbActoActa: View {

    let landing: OnboardingLanding?
    let onAtras: () -> Void
    let onContinuar: () -> Void

    var body: some View {
        // Los `Group` son puramente estructurales: SwiftUI tope los hijos de un builder en 10 y
        // el acta tiene 24. `Group` es transparente para el layout, así que cada renglón sigue
        // siendo hermano directo del `VStack` del shell.
        //
        // Acto largo por construcción (24 renglones): enseña su barra de scroll. Esconderla aquí
        // era esconder que la mitad del acta vive abajo del pliegue.
        OnbShell(indicadores: true) {
            Group {
                OnbAtras(accion: onAtras)

                OnbOverline(OnbCopy.actaOverline)
                    .padding(.top, LiquidSpace.s250)
                OnbTitular(palabra, tono: tono)
                    .padding(.top, LiquidSpace.s250)
                OnbCuerpo(OnbCopy.actaIntro)
                    .padding(.top, LiquidSpace.s300)
            }

            // Las cuatro palabras. Los títulos son los del catálogo; las glosas, de este acto.
            Group {
                OnbOverline(OnbCopy.actaOverlinePalabras)
                    .padding(.top, LiquidSpace.s800)
                OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.full),
                        tono: LiquidColor.verdePrimario, glosa: OnbCopy.actaGlosaFull)
                OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.caution),
                        tono: LiquidColor.atencionTexto, glosa: OnbCopy.actaGlosaCaution)
                OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.easy),
                        tono: LiquidColor.negativo, glosa: OnbCopy.actaGlosaEasy)
                OnbFila(nombre: LiquidHoyBuilder.palabraCalibrando,
                        tono: nil, glosa: OnbCopy.actaGlosaCalibrando)
            }

            // Los TRES votos que cuenta el motor: autonómico, sueño y el centinela. El centinela
            // ocupa dos renglones porque son dos señales, pero su etiqueta («en par») dice que
            // entre las dos cargan UN voto y que ninguna cuenta sola.
            Group {
                OnbOverline(OnbCopy.actaOverlineEjes)
                    .padding(.top, LiquidSpace.s800)
                OnbFila(nombre: OnbCopy.actaEjeAutonomico, tono: LiquidColor.rosa,
                        glosa: OnbCopy.actaEjeAutonomicoGlosa, etiqueta: OnbCopy.etiquetaManda)
                OnbFila(nombre: OnbCopy.actaEjeSueno, tono: LiquidColor.indigo,
                        glosa: OnbCopy.actaEjeSuenoGlosa, etiqueta: OnbCopy.etiquetaVota)
                OnbFila(nombre: OnbCopy.actaEjeTemp, tono: LiquidColor.doradoTemp,
                        glosa: OnbCopy.actaEjeTempGlosa, etiqueta: OnbCopy.etiquetaEnPar)
                OnbFila(nombre: OnbCopy.actaResp, tono: LiquidColor.azul,
                        glosa: OnbCopy.actaRespGlosa, etiqueta: OnbCopy.etiquetaEnPar)
            }

            // Dentro del eje que manda: aquí sí aparecen los PESOS, porque es el único lugar del
            // sistema donde una señal pesa distinto que su compañera.
            Group {
                OnbOverline(OnbCopy.actaOverlineDentro)
                    .padding(.top, LiquidSpace.s800)
                OnbFila(nombre: OnbCopy.actaRhr, tono: LiquidColor.rosa,
                        glosa: OnbCopy.actaRhrGlosa, peso: Self.pesoCompleto,
                        etiqueta: OnbCopy.etiquetaEspina)
                OnbFila(nombre: OnbCopy.actaVfcNoche, tono: LiquidColor.cian,
                        glosa: OnbCopy.actaVfcNocheGlosa, peso: Self.pesoMitad,
                        etiqueta: OnbCopy.etiquetaAcompana)
            }

            // Lo que no pesa, y por qué. Sin hue: la ausencia de identidad de color ES el dato.
            // La respiración salió de aquí: en par con la temperatura SÍ mueve el veredicto, así
            // que listarla como «aparte» era decir lo contrario de lo que hace el motor.
            Group {
                OnbOverline(OnbCopy.actaOverlineNoPesa)
                    .padding(.top, LiquidSpace.s800)
                OnbFila(nombre: OnbCopy.actaVfcDia, tono: nil, glosa: OnbCopy.actaVfcDiaGlosa,
                        etiqueta: OnbCopy.etiquetaFuera)
                OnbFila(nombre: OnbCopy.actaPasos, tono: nil, glosa: OnbCopy.actaPasosGlosa,
                        etiqueta: OnbCopy.etiquetaNunca)
            }

            // Contra qué te comparo: la tarjeta es la respuesta a «¿comparado con quién?», que es
            // la pregunta que el resto del acta deja abierta.
            Group {
                OnbTarjeta {
                    OnbOverline(OnbCopy.actaOverlineContra)
                    OnbCuerpo(OnbCopy.actaContra)
                }
                .padding(.top, LiquidSpace.s800)

                OnbCuerpo(OnbCopy.actaPie, tono: LiquidColor.tinta500)
                    .padding(.top, LiquidSpace.s600)

                Spacer(minLength: LiquidSpace.s600)

                LiquidGlassButton(OnbCopy.actaCta, variant: .primary, expands: true,
                                  action: onContinuar)
            }
        }
    }

    /// El peso de la FC en reposo dentro del eje autonómico (`wRHR`) y el de la VFC nocturna.
    /// Son etiquetas del DATO, no copy: no se traducen.
    private static let pesoCompleto = "1.0"
    private static let pesoMitad = "0.5"

    /// La palabra que se está descomponiendo. Sin veredicto, el acta habla igual (el usuario tiene
    /// derecho a saber cómo se decide antes de que le toque una palabra) y usa la de calibrando.
    private var palabra: String {
        guard case let .lectura(verdict, _, _) = landing else {
            return LiquidHoyBuilder.palabraCalibrando
        }
        return LiquidHoyBuilder.palabraVeredicto(verdict)
    }

    private var tono: Color {
        guard case let .lectura(verdict, _, _) = landing else { return LiquidColor.tinta700 }
        switch verdict {
        case .full:      return LiquidColor.verdePrimario
        // El ámbar de dato no alcanza AA en texto; su hermano de lectura sí.
        case .caution:   return LiquidColor.atencionTexto
        case .easy:      return LiquidColor.negativo
        case .lowSignal: return LiquidColor.tinta700
        }
    }
}
