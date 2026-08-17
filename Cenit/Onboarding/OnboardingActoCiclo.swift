import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Acto 7 · El ciclo y la mañana (FER-109)
//
// El último acto contesta la única pregunta que queda: «y con eso, qué». La lectura no es un dato
// para archivar; es lo que decide el día, y quien lo ejecuta es Entrenar.
//
// El lienzo entra en `.circulacion`, con DOS centros: las motas viajan de un orbe al otro sin
// parar. Es el ciclo hecho movimiento, y es la única vez en todo el flujo que el campo tiene dos
// casas — exactamente las dos que el dock de abajo enseña.
//
// Sin confeti y sin celebración: el veredicto de mañana puede ser «Recupera», y un onboarding que
// termina en fiesta le pone un tono a la app que la app no sostiene al día siguiente.

struct OnbActoCiclo: View {

    let landing: OnboardingLanding?
    let onAtras: () -> Void
    let onEntrar: () -> Void

    var body: some View {
        // Los `Group` son puramente estructurales (tope de 10 hijos por builder); son
        // transparentes para el layout, así que cada pieza sigue siendo hermana directa del
        // `VStack` del shell y los `Spacer` siguen empujando el CTA al pie.
        //
        // Acto largo (traducción + tarjeta + cierre + dock): enseña su barra de scroll.
        OnbShell(indicadores: true) {
            Group {
                OnbAtras(accion: onAtras)

                OnbOverline(OnbCopy.cicloOverline)
                    .padding(.top, LiquidSpace.s250)
                OnbTitular(OnbCopy.cicloTitular)
                    .padding(.top, LiquidSpace.s250)
                OnbCuerpo(OnbCopy.cicloCuerpo)
                    .padding(.top, LiquidSpace.s300)
            }

            // Cómo se traduce: los mismos títulos del catálogo del acta, ahora con lo que HACEN.
            Group {
                OnbOverline(OnbCopy.cicloOverlineTraduce)
                    .padding(.top, LiquidSpace.s800)
                OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.full),
                        tono: LiquidColor.verdePrimario, glosa: OnbCopy.cicloFull)
                OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.caution),
                        tono: LiquidColor.atencionTexto, glosa: OnbCopy.cicloCaution)
                OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.easy),
                        tono: LiquidColor.negativo, glosa: OnbCopy.cicloEasy)
            }

            Group {
                OnbTarjeta {
                    OnbCuerpo(OnbCopy.cicloTarjetaFuerte, fuerte: true)
                    OnbCuerpo(OnbCopy.cicloTarjetaCuerpo)
                }
                .padding(.top, LiquidSpace.s600)

                OnbCuerpo(OnbCopy.cicloPie, tono: LiquidColor.tinta500)
                    .padding(.top, LiquidSpace.s300)
            }

            // El cierre vive en el MISMO acto, abajo: el ritual de la noche es la consecuencia de
            // todo lo anterior, no una pantalla más que despedir.
            Group {
                OnbTitular(conReloj ? OnbCopy.cierreTitular : OnbCopy.cierreTitularSinReloj)
                    .padding(.top, LiquidSpace.s800)
                OnbCuerpo(conReloj ? OnbCopy.cierreCuerpo : OnbCopy.cierreCuerpoSinReloj)
                    .padding(.top, LiquidSpace.s300)
                // El aviso solo se ofrece donde puede existir: sin noches con reloj no hay lectura
                // que anunciar y `MorningReadingScheduler.plan` sale vacío (`hayLectura`), así que
                // aquí sería un recordatorio prometido que nunca va a sonar.
                if conReloj {
                    OnbCuerpo(OnbCopy.cierreAviso, tono: LiquidColor.tinta500)
                        .padding(.top, LiquidSpace.s250)
                }
            }

            // El dock REAL, no un dibujo: lo que se promete arriba es lo que se toca abajo.
            Group {
                VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                    Text(OnbCopy.cicloDock)
                        .groteskOverline()
                        .foregroundStyle(LiquidColor.tinta500)
                    LiquidTabBar(active: .hoy)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    OnbCuerpo(OnbCopy.cicloDockPie, tono: LiquidColor.tinta500)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, LiquidSpace.s600)

                Spacer(minLength: LiquidSpace.s600)

                LiquidGlassButton(OnbCopy.entrar, variant: .primary, expands: true, action: onEntrar)
            }
        }
    }

    /// ¿Hay noches con el reloj puesto? Es lo que decide qué cierre es honesto: prometerle «duerme
    /// con el reloj» a quien no tiene reloj es una instrucción imposible, y prometerle «si algún
    /// día usas un reloj» a quien ya duerme con uno lo trata de desconocido.
    private var conReloj: Bool {
        switch landing {
        case let .lectura(_, noches, _):     return noches > 0
        case let .calibrando(noches, _, _):  return noches > 0
        default:                              return false
        }
    }
}
