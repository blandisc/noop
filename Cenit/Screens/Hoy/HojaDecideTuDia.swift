import SwiftUI
import StrandDesign

// MARK: - FER-54 · La hoja-manual «¿Qué decide tu día?»
//
// Se abre tocando el rótulo de nivel «Decide your day» en la Matriz. Es el MANUAL del
// modelo — no el acta de hoy (esa vive en el héroe): enseña la promesa, quién vota,
// las combinaciones posibles del veredicto y cómo se calcula. A propósito es ESTÁTICA
// (sin números de hoy): así nunca contradice al héroe ni caduca. El copy respeta la
// semántica real del motor (Preparedness): votan sueño + FC en reposo; el guardián es
// centinela (temp + resp solo pesan juntas); VFC/carga/esfuerzo son referencia.

struct HojaDecideTuDia: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "manual.deciden.titulo",
                        defaultValue: "What decides your day?"))
                .font(LiquidType.tituloHoja)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "manual.deciden.promesa",
                        defaultValue: "Every morning I read your night and tell you one thing: whether you woke up inside your range. Your resting heart rate is compared against your own recent weeks; your sleep, against the recommended range for health."))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .padding(.top, LiquidSpace.s100)

            seccion(String(localized: "manual.deciden.sec.votan", defaultValue: "Who votes"))
            votante(orbe: .simple(LiquidColor.indigo),
                    titulo: String(localized: "manual.deciden.sueno", defaultValue: "Sleep"),
                    detalle: String(localized: "manual.deciden.sueno.sub",
                                    defaultValue: "How much and how well you slept last night, against the recommended range."),
                    sello: .vota)
            votante(orbe: .simple(LiquidColor.rosa),
                    titulo: String(localized: "manual.deciden.fc", defaultValue: "Resting heart rate"),
                    detalle: String(localized: "manual.deciden.fc.sub",
                                    defaultValue: "Your lowest pulse of the night, against your recent weeks."),
                    sello: .vota)
            votante(orbe: .guardian,
                    titulo: String(localized: "manual.deciden.guardian", defaultValue: "The guardian"),
                    detalle: String(localized: "manual.deciden.guardian.sub",
                                    defaultValue: "Temperature and breathing watch together. They only weigh in when both step out at once; one alone can be noise."),
                    sello: .centinela)
            votante(orbe: .simple(LiquidColor.cian),
                    titulo: String(localized: "manual.deciden.resto", defaultValue: "HRV, load, effort, stress, steps"),
                    detalle: String(localized: "manual.deciden.resto.sub",
                                    defaultValue: "They give you context, but don't vote: on a wrist watch they aren't stable enough to decide."),
                    sello: .referencia)

            seccion(String(localized: "manual.deciden.sec.combos", defaultValue: "The combinations"))
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                // FER-73 · HJ-03: el manual nombra las combinaciones con las MISMAS palabras
                // que el héroe («In range» / «Go light today» / «Recover» / «Getting to know
                // you»). Antes enseñaba nombres de veredicto ya retirados.
                combo(LiquidColor.verdePrimario,
                      String(localized: "hero.title.full", defaultValue: "In range"),
                      String(localized: "manual.deciden.c1.sub",
                             defaultValue: "No signal out. Your body woke up where it usually does."))
                combo(LiquidColor.ambar,
                      String(localized: "hero.title.caution", defaultValue: "Go light today"),
                      String(localized: "manual.deciden.c2.sub",
                             defaultValue: "One signal out, and I tell you which."))
                combo(LiquidColor.negativo,
                      String(localized: "hero.title.easy", defaultValue: "Recover"),
                      String(localized: "manual.deciden.c3.sub",
                             defaultValue: "Two or more votes out."))
                combo(LiquidColor.tinta500,
                      String(localized: "hero.title.calibrando", defaultValue: "Getting to know you"),
                      String(localized: "manual.deciden.c4.sub",
                             defaultValue: "Not enough reading last night. Without data I don't guess."))
            }
            .padding(LiquidSpace.s300)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LiquidRadius.control)
                    .stroke(LiquidColor.tinta10, lineWidth: 1))

            seccion(String(localized: "manual.deciden.sec.como", defaultValue: "How it's calculated"))
            Text(String(localized: "manual.deciden.como",
                        defaultValue: "From your recent weeks I learn your normal band for your resting heart rate and your breathing; your temperature is measured by how far it drifts from your own baseline, against a fixed cut that is the same for everyone, and your sleep against the recommended range for health. Each morning I compare the night: in or out. The verdict counts how many voting signals stepped out. It is never a 0-100 score, because your watch doesn't measure with that precision and I won't pretend it does."))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)

            Text(String(localized: "manual.deciden.hedge",
                        defaultValue: "A wrist-watch reading: an honest approximation, not a diagnosis. Cénit is not a medical device."))
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
                .padding(.top, LiquidSpace.s400)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Piezas

    private enum Orbe { case simple(Color), guardian }
    private enum Sello { case vota, centinela, referencia }

    private func seccion(_ titulo: String) -> some View {
        // La misma voz que la cabecera de estante que abre esta hoja (FER-125).
        LiquidOverline(titulo)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s200)
    }

    @ViewBuilder private func orbeView(_ orbe: Orbe) -> some View {
        switch orbe {
        case .simple(let color):
            Circle().fill(color).frame(width: 12, height: 12)
        case .guardian:
            // El par del centinela: dorado (temp) | azul (resp), corte al centro —
            // a 12 pt el degradado se enloda; el split duro lee «son dos».
            Circle()
                .fill(LinearGradient(
                    stops: [.init(color: LiquidColor.doradoTemp, location: 0.5),
                            .init(color: LiquidColor.azul, location: 0.5)],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: 12, height: 12)
        }
    }

    private func selloView(_ sello: Sello) -> some View {
        let (texto, color): (String, Color) = switch sello {
        case .vota:
            (String(localized: "manual.deciden.sello.vota", defaultValue: "votes"),
             LiquidColor.verdePrimario)
        case .centinela:
            (String(localized: "manual.deciden.sello.centinela", defaultValue: "sentinel"),
             LiquidColor.doradoTemp)
        case .referencia:
            (String(localized: "manual.deciden.sello.ref", defaultValue: "reference"),
             LiquidColor.tinta500)
        }
        return Text(texto)
            .font(LiquidType.micro)
            .tracking(LiquidType.microTracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, LiquidSpace.s150)
            .padding(.vertical, LiquidSpace.s025)
            .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1)) // token-exempt: mismo aro al 45 % del sello «vota» de la Matriz
    }

    private func votante(orbe: Orbe, titulo: String, detalle: String, sello: Sello) -> some View {
        HStack(alignment: .top, spacing: LiquidSpace.s200) {
            orbeView(orbe).padding(.top, 2)
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(titulo)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta900)
                Text(detalle)
                    .font(LiquidType.cuerpo)
                    .lineSpacing(LiquidType.cuerpoLineSpacing)
                    .foregroundStyle(LiquidColor.tinta700)
            }
            Spacer(minLength: LiquidSpace.s150)
            selloView(sello)
        }
        .padding(.bottom, LiquidSpace.s300)
        .accessibilityElement(children: .combine)
    }

    private func combo(_ color: Color, _ titulo: String, _ detalle: String) -> some View {
        HStack(alignment: .top, spacing: LiquidSpace.s200) {
            Circle().fill(color).frame(width: 10, height: 10).padding(.top, 3)
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
        .accessibilityElement(children: .combine)
    }
}

#Preview("Hoja · ¿Qué decide tu día?") {
    ScrollView {
        HojaDecideTuDia()
            .padding(LiquidSpace.s400)
    }
    .background(LiquidColor.papelMatriz)
}
