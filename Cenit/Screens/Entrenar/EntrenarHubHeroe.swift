#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Entrenar · el héroe del hub v18 (FER-171 · Parte B)
//
// El héroe de «rutina del día» (① en rango / ② recupera) rehecho en el vidrio v18: kicker teñido
// por la familia de HOY, nombre Grotesk 40, meta de la sesión, nombres de ejercicios, la píldora de
// subida en vidrio verde y la fila CTA («Empezar» + «Otra forma ⌄»). El pliegue de las cuatro
// puertas es el EXISTENTE (`EntrenarLanding.otraFormaPliegue`) — este componente solo lo aloja, vía
// el parámetro `pliegue`, para no bifurcar su lógica.
struct EntrenarHubHeroe<Pliegue: View>: View {
    let tono: LiquidTono
    let routineName: String
    let meta: String
    let exerciseNames: String?
    /// «Hoy subes: sentadilla · 82,5 kg» ya armado (negritas incluidas) — reusa
    /// `EntrenarLanding.raiseText` tal cual, la Parte B no reinterpreta `raisesToday`.
    let raiseLine: Text?
    let onOpenRaise: () -> Void
    let onStart: () -> Void
    let otraFormaAbierta: Bool
    let onToggleOtraForma: () -> Void
    private let pliegue: Pliegue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Ronda 2 · D2: `heroNombres`/`subPillTexto` eran `Font.system(size:)` fijo — texto de LECTURA
    /// sin escalar. `@ScaledMetric` en la vista (el `enum` de tokens no tiene entorno); la base sigue
    /// en `EntrenarHubMetrics`. `subPillTextoSize` ancla a `.subheadline`, el MISMO `relativeTo` que
    /// las cifras en negritas de `raiseText` (`EntrenarView`) — el prefijo «Hoy subes:» y los pesos
    /// tienen que crecer JUNTOS, no cada quien a su ritmo.
    @ScaledMetric(relativeTo: .footnote) private var heroNombresSize = EntrenarHubMetrics.heroNombresBase
    @ScaledMetric(relativeTo: .subheadline) private var subPillTextoSize = EntrenarHubMetrics.subPillTextoBase

    /// Init explícito (mismo patrón que `EntrenarModulo`, Parte A): `pliegue` se invoca UNA vez, aquí
    /// — el `body` de este struct se reconstruye cada vez que su padre redibuja de todos modos, así
    /// que evaluarlo en el `init` es equivalente a guardar el closure sin invocar.
    init(tono: LiquidTono, routineName: String, meta: String, exerciseNames: String?, raiseLine: Text?,
        onOpenRaise: @escaping () -> Void, onStart: @escaping () -> Void,
        otraFormaAbierta: Bool, onToggleOtraForma: @escaping () -> Void,
        @ViewBuilder pliegue: () -> Pliegue) {
        self.tono = tono; self.routineName = routineName; self.meta = meta
        self.exerciseNames = exerciseNames; self.raiseLine = raiseLine
        self.onOpenRaise = onOpenRaise; self.onStart = onStart
        self.otraFormaAbierta = otraFormaAbierta; self.onToggleOtraForma = onToggleOtraForma
        self.pliegue = pliegue()
    }

    var body: some View {
        EntrenarModulo(tono: tono, intensidad: EntrenarHubMetrics.heroIntensidad,
                       insets: EntrenarHubMetrics.heroInsets) {
            VStack(alignment: .leading, spacing: 0) {
                // El bloque de LECTURA (kicker+título+meta+nombres) es UN elemento de accesibilidad
                // — pero NO el héroe entero: la píldora de subida, «Empezar», «Otra forma» y el
                // pliegue son botones propios, y combinarlos aquí les habría robado su acción a
                // VoiceOver (regla del spec «un elemento por módulo» es para lectura, no para un
                // módulo con varios controles vivos).
                VStack(alignment: .leading, spacing: 0) {
                    Text("Today · your session")
                        .liquidRegla()
                        .foregroundStyle(tono.rotulo)
                    Text(verbatim: routineName)
                        .font(LiquidType.displayM).tracking(LiquidType.displayMTracking)
                        .foregroundStyle(LiquidColor.tinta900)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .padding(.top, EntrenarHubMetrics.heroKickerToTituloTop)
                    Text(verbatim: meta)
                        .font(EntrenarHubMetrics.heroMeta)
                        .foregroundStyle(LiquidColor.tinta700)
                        .padding(.top, EntrenarHubMetrics.heroTituloToMetaTop)
                    if let exerciseNames, !exerciseNames.isEmpty {
                        Text(verbatim: exerciseNames)
                            .font(.system(size: heroNombresSize))
                            .foregroundStyle(LiquidColor.tinta700)
                            .lineSpacing(EntrenarHubMetrics.heroNombresLineSpacing)
                            .lineLimit(2)
                            .frame(maxWidth: EntrenarHubMetrics.heroNombresMaxWidth, alignment: .leading)
                            .padding(.top, EntrenarHubMetrics.heroMetaToNombresTop)
                    }
                }
                .accessibilityElement(children: .combine)
                if let raiseLine {
                    subPill(raiseLine).padding(.top, EntrenarHubMetrics.heroNombresToSubPillTop)
                }
                ctaRow.padding(.top, EntrenarHubMetrics.heroSubPillToCtaTop)
                pliegue
            }
        }
        .liquidEntrada(index: 0)
    }

    // MARK: - Píldora «Hoy subes»

    private func subPill(_ line: Text) -> some View {
        Button(action: onOpenRaise) {
            HStack(spacing: CenitMetrics.space2) {
                Circle()
                    .fill(LiquidColor.papelTarjeta)
                    .frame(width: EntrenarHubMetrics.subPillBadge, height: EntrenarHubMetrics.subPillBadge)
                    .overlay {
                        Text(verbatim: "↑")
                            .font(EntrenarHubMetrics.subPillGlifo)
                            .foregroundStyle(LiquidColor.verdeProfundo)
                    }
                    .accessibilityHidden(true)   // decorativo — la palabra «subes» ya lo dice
                line.font(.system(size: subPillTextoSize)).foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, EntrenarHubMetrics.subPillPaddingLeading)
            .padding(.trailing, EntrenarHubMetrics.subPillPaddingTrailing)
            .padding(.vertical, EntrenarHubMetrics.subPillPaddingV)
            .background {
                Capsule().fill(LiquidColor.verdePrimario.opacity(EntrenarHubMetrics.subPillFondoAlfa))
            }
            .overlay {
                Capsule().strokeBorder(LiquidColor.papelTarjeta.opacity(EntrenarHubMetrics.subPillHighlightAlfa), lineWidth: 1)
            }
            .overlay {
                Capsule().strokeBorder(LiquidColor.vidrioEspecular.opacity(EntrenarHubMetrics.subPillAroAlfa), lineWidth: 1)
                    .padding(1)
            }
            .overlay {
                Capsule().stroke(LiquidColor.verdePrimario.opacity(EntrenarHubMetrics.subPillCantoAlfa), lineWidth: 0.5)
            }
            .liquidShadow([.init(color: LiquidColor.verdePrimario.opacity(EntrenarHubMetrics.subPillShadowAlfa),
                                 radius: EntrenarHubMetrics.subPillShadowRadius, y: EntrenarHubMetrics.subPillShadowY)])
        }
        .buttonStyle(.liquidPress)
    }

    // MARK: - Fila CTA

    private var ctaRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: EntrenarHubMetrics.heroCtaGap) { empezarPill; otraFormaPill }
            VStack(alignment: .leading, spacing: CenitMetrics.space2) { empezarPill; otraFormaPill }
        }
    }

    private var empezarPill: some View {
        Button(action: onStart) {
            // La MISMA clave que `EntrenarLanding.empezarLabel` (catálogo «Empezar» → en «Start»):
            // reutiliza la traducción existente en vez de una clave nueva idéntica.
            Text("Empezar")
                .font(EntrenarHubMetrics.heroCTATexto)
                .foregroundStyle(LiquidColor.tintaSobreVerde)
                .frame(minWidth: EntrenarHubMetrics.heroCTAMinWidth, minHeight: EntrenarMetrics.row)
                .background(LiquidColor.verdePrimario, in: Capsule())
                .liquidShadow([.init(color: LiquidColor.verdePrimario.opacity(EntrenarHubMetrics.heroCTAShadowAlfa),
                                     radius: EntrenarHubMetrics.heroCTAShadowRadius, y: EntrenarHubMetrics.heroCTAShadowY)])
        }
        .buttonStyle(.liquidPress)
    }

    private var otraFormaPill: some View {
        Button {
            withAnimation(reduceMotion ? StrandMotion.fade : StrandMotion.gentle) { onToggleOtraForma() }
        } label: {
            HStack(spacing: CenitMetrics.space1) {
                Text("Other ways")
                    .font(EntrenarHubMetrics.heroOtraFormaTexto)
                    .foregroundStyle(LiquidColor.tinta700)
                StrandIcon.down.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(LiquidColor.tinta700)
                    .rotationEffect(.degrees(otraFormaAbierta ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, EntrenarHubMetrics.otraFormaPaddingH)
            .frame(minHeight: EntrenarMetrics.row)
            .background {
                Capsule().fill(LiquidColor.papelTarjeta.opacity(EntrenarHubMetrics.otraFormaFondoAlfa))
            }
            .overlay {
                Capsule().strokeBorder(LiquidColor.vidrioEspecular.opacity(EntrenarHubMetrics.otraFormaHighlightAlfa), lineWidth: 1)
            }
            .overlay {
                Capsule().stroke(LiquidColor.tinta900.opacity(EntrenarHubMetrics.otraFormaCantoAlfa), lineWidth: 0.5)
            }
            .liquidShadow([.init(color: LiquidColor.tinta900.opacity(EntrenarHubMetrics.otraFormaShadowAlfa),
                                 radius: EntrenarHubMetrics.otraFormaShadowRadius, y: EntrenarHubMetrics.otraFormaShadowY)])
        }
        .buttonStyle(.liquidPress)
        .accessibilityValue(Text(otraFormaAbierta ? "expanded" : "collapsed"))
    }
}
#endif
