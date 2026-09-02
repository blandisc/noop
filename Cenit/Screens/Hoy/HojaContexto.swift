import SwiftUI
import CenitDesign

// MARK: - FER-61 · La hoja-manual «Tu contexto»
//
// Se abre tocando el rótulo de nivel «Context» en la Matriz. Es el hogar ÚNICO del
// «no deciden tu día»: resuelve la asimetría de honestidad (antes solo VFC se
// auto-etiquetaba «no vota»). A propósito es ESTÁTICA (sin números de hoy). El copy
// respeta la semántica real del motor (Preparedness): votan sueño + FC en reposo; carga,
// esfuerzo, VFC y estrés son CONTEXTO/referencia. La nota de VFC es la que firmó el /cso
// (FER-61): el SDNN de día del Apple Watch es demasiado ruidoso para votar — se muestra
// como referencia (línea de centro), nunca como banda ni como juicio.

struct HojaContexto: View {
    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(String(localized: "manual.contexto.titulo",
                        defaultValue: "Your context"))
                .font(LiquidType.tituloHoja)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "manual.contexto.intro",
                        defaultValue: "These don't decide your day: only your sleep and resting heart rate vote. They're here to give you context around that verdict, never to judge it."))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .padding(.top, LiquidSpace.s100)

            seccion(String(localized: "manual.contexto.sec.que", defaultValue: "What each one is"))
            // El manual identifica cada señal con SU glifo de sistema y SU hue, los mismos del
            // módulo que abre esta hoja (revisión UX FER-125): antes puntos de color, y Carga
            // vestía el verde del veredicto.
            fila(.carga, color: LiquidColor.verdeCarga,
                 titulo: String(localized: "manual.contexto.carga", defaultValue: "Load"),
                 detalle: String(localized: "manual.contexto.carga.sub",
                                 defaultValue: "How much training you've been piling up lately, against what's usual for you."))
            // FER-73 · HJ-21: Effort es ÁMBAR desde el cambio de identidad (el teal es Pasos).
            fila(.llama, color: LiquidColor.ambar,
                 titulo: String(localized: "manual.contexto.esfuerzo", defaultValue: "Effort"),
                 detalle: String(localized: "manual.contexto.esfuerzo.sub",
                                 defaultValue: "What you've built up so far today."))
            fila(.onda, color: LiquidColor.cian,
                 titulo: String(localized: "manual.contexto.vfc", defaultValue: "HRV"),
                 detalle: String(localized: "manual.contexto.vfc.sub",
                                 defaultValue: "Your heart-rate variability, estimated by your watch through the day. The dotted line is where you usually sit."))
            fila(.estres, color: LiquidColor.estresMedio,
                 titulo: String(localized: "manual.contexto.estres", defaultValue: "Stress"),
                 detalle: String(localized: "manual.contexto.estres.sub",
                                 defaultValue: "Your estimated stress level for the day, on a low-to-high scale."))
            // Pasos vive en Contexto desde FER-118 (ocupó el sitio de la Bitácora): el manual
            // que explica el estante tiene que nombrarlo.
            fila(.pasos, color: LiquidColor.teal,
                 titulo: String(localized: "manual.contexto.pasos", defaultValue: "Steps"),
                 detalle: String(localized: "manual.contexto.pasos.sub",
                                 defaultValue: "How much you've moved today, next to your last two weeks. A count, not a judgment."))

            seccion(String(localized: "manual.contexto.sec.porque", defaultValue: "Why they don't vote"))
            Text(String(localized: "manual.contexto.porque",
                        defaultValue: "On a wrist watch, HRV and stress aren't stable enough to decide with. Your watch's daytime HRV drifts about 29% from a chest-strap reference, so we show it as a quiet line where you usually sit, never as a range you crossed. Your resting heart rate and sleep carry the verdict; these ride along as context."))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)

            // Mismo hedge que «Deciden» — una sola fuente de verdad.
            Text(String(localized: "manual.deciden.hedge",
                        defaultValue: "A wrist-watch reading: an honest approximation, not a diagnosis. Cénit is not a medical device."))
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
                .padding(.top, LiquidSpace.s400)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Piezas

    private func seccion(_ titulo: String) -> some View {
        // La misma voz que la cabecera de estante que abre esta hoja (FER-125).
        LiquidOverline(titulo)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s200)
    }

    private func fila(_ glifo: LiquidIcon.Glyph, color: Color, titulo: String, detalle: String) -> some View {
        HStack(alignment: .top, spacing: LiquidSpace.s200) {
            LiquidIconDrop(glifo, tone: color)
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(titulo)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta900)
                Text(detalle)
                    .font(LiquidType.cuerpo)
                    .lineSpacing(LiquidType.cuerpoLineSpacing)
                    .foregroundStyle(LiquidColor.tinta700)
            }
        }
        .padding(.bottom, LiquidSpace.s300)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Hoja · Tu contexto") {
    ScrollView {
        HojaContexto()
            .padding(LiquidSpace.s400)
    }
    .background(LiquidColor.papelMatriz)
}
