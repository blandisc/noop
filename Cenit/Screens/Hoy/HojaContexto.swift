import SwiftUI
import StrandDesign

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
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "manual.contexto.titulo",
                        defaultValue: "Your context"))
                .font(LiquidType.tituloHoja)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "manual.contexto.intro",
                        defaultValue: "These four don't decide your day: only your sleep and resting heart rate vote. They're here to give you context around that verdict, never to judge it."))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .padding(.top, LiquidSpace.s100)

            seccion(String(localized: "manual.contexto.sec.que", defaultValue: "What each one is"))
            fila(color: LiquidColor.verdePrimario,
                 titulo: String(localized: "manual.contexto.carga", defaultValue: "Load"),
                 detalle: String(localized: "manual.contexto.carga.sub",
                                 defaultValue: "How much training you've been piling up lately, against what's usual for you."))
            // FER-73 · HJ-21: Effort es ÁMBAR desde el cambio de identidad (el teal es Pasos).
            fila(color: LiquidColor.ambar,
                 titulo: String(localized: "manual.contexto.esfuerzo", defaultValue: "Effort"),
                 detalle: String(localized: "manual.contexto.esfuerzo.sub",
                                 defaultValue: "What you've built up so far today."))
            fila(color: LiquidColor.cian,
                 titulo: String(localized: "manual.contexto.vfc", defaultValue: "HRV"),
                 detalle: String(localized: "manual.contexto.vfc.sub",
                                 defaultValue: "Your heart-rate variability, estimated by your watch through the day. The dotted line is where you usually sit."))
            fila(color: LiquidColor.tinta500,
                 titulo: String(localized: "manual.contexto.estres", defaultValue: "Stress"),
                 detalle: String(localized: "manual.contexto.estres.sub",
                                 defaultValue: "Your estimated stress level for the day, on a low-to-high scale."))

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
        Text(titulo)
            .font(LiquidType.micro)
            .tracking(LiquidType.microTracking)
            .textCase(.uppercase)
            .foregroundStyle(LiquidColor.tinta500)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s200)
    }

    private func fila(color: Color, titulo: String, detalle: String) -> some View {
        HStack(alignment: .top, spacing: LiquidSpace.s200) {
            Circle().fill(color).frame(width: 12, height: 12).padding(.top, 2)
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
