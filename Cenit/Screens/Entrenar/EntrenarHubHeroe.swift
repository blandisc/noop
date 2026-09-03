#if os(iOS)
import SwiftUI
import CenitDesign

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
    /// Ola 1 · E5: tono de la píldora — `.verde` («Hoy subes») por default; `.ambar` cuando
    /// `raiseLine` es en realidad «Hoy mantienes» (un ejercicio cumplió al fallo, sin subir).
    var raiseTono: LiquidTono = .verde
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
        raiseTono: LiquidTono = .verde,
        onOpenRaise: @escaping () -> Void, onStart: @escaping () -> Void,
        otraFormaAbierta: Bool, onToggleOtraForma: @escaping () -> Void,
        @ViewBuilder pliegue: () -> Pliegue) {
        self.tono = tono; self.routineName = routineName; self.meta = meta
        self.exerciseNames = exerciseNames; self.raiseLine = raiseLine; self.raiseTono = raiseTono
        self.onOpenRaise = onOpenRaise; self.onStart = onStart
        self.otraFormaAbierta = otraFormaAbierta; self.onToggleOtraForma = onToggleOtraForma
        self.pliegue = pliegue()
    }

    var body: some View {
        EntrenarModulo(tono: tono, intensidad: EntrenarHubMetrics.heroIntensidad,
                       insets: EntrenarHubMetrics.heroInsets) {
            VStack(alignment: .leading, spacing: .zero) {
                // El bloque de LECTURA (kicker+título+meta+nombres) es UN elemento de accesibilidad
                // — pero NO el héroe entero: la píldora de subida, «Empezar», «Otra forma» y el
                // pliegue son botones propios, y combinarlos aquí les habría robado su acción a
                // VoiceOver (regla del spec «un elemento por módulo» es para lectura, no para un
                // módulo con varios controles vivos).
                VStack(alignment: .leading, spacing: .zero) {
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
                            .lineLimit(2).minimumScaleFactor(0.8)
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

    // MARK: - Píldora «Hoy subes» / «Hoy mantienes» (Ola 1 · E5: `raiseTono` la tiñe)

    private func subPill(_ line: Text) -> some View {
        // 2A: cromo vía `OutlineCapsule.Estilo.tenida(_:)` (alfas en `EntrenarHubMetrics.subPill*`).
        OutlineCapsule(size: .aMedida(insets: EntrenarHubMetrics.subPillInsets, minHeight: nil, touchInset: 0),
                       estilo: .tenida(raiseTono), action: onOpenRaise) {
            HStack(spacing: LiquidSpace.s200) {
                Circle()
                    .fill(LiquidColor.papelTarjeta)
                    .frame(width: EntrenarHubMetrics.subPillBadge, height: EntrenarHubMetrics.subPillBadge)
                    .overlay {
                        // «↑» sube, «=» mantiene — el mismo badge, glifo distinto por tono.
                        Text(verbatim: raiseTono == .verde ? "↑" : "=")
                            .font(EntrenarHubMetrics.subPillGlifo)
                            .foregroundStyle(raiseTono.rotulo)
                    }
                    .accessibilityHidden(true)   // decorativo — la palabra «subes»/«mantienes» ya lo dice
                line.font(.system(size: subPillTextoSize)).foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Fila CTA

    private var ctaRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: EntrenarHubMetrics.heroCtaGap) { empezarPill; otraFormaPill }
            VStack(alignment: .leading, spacing: LiquidSpace.s200) { empezarPill; otraFormaPill }
        }
    }

    private var empezarPill: some View {
        // La MISMA clave que `EntrenarLanding.empezarLabel` (catálogo «Empezar» → en «Start»):
        // reutiliza la traducción existente en vez de una clave nueva idéntica.
        LiquidGlassButton("Empezar", variant: .primary,
                          minWidth: EntrenarHubMetrics.heroCTAMinWidth, action: onStart)
    }

    private var otraFormaPill: some View {
        // 2A: cromo vía `OutlineCapsule.Estilo.vidrio` + talla `.lg` (alfas en `EntrenarHubMetrics.otraForma*`).
        OutlineCapsule(size: .aMedida(insets: EntrenarHubMetrics.otraFormaInsets, minHeight: EntrenarMetrics.row, touchInset: 0),
                       estilo: .vidrio, action: {
            withAnimation(reduceMotion ? LiquidMotion.fundido : LiquidMotion.suave) { onToggleOtraForma() }
        }) {
            HStack(spacing: LiquidSpace.s100) {
                Text("Other ways")
                    .font(EntrenarHubMetrics.heroOtraFormaTexto)
                    .foregroundStyle(LiquidColor.tinta700)
                CenitIcon.down.image
                    .font(LiquidType.iconSF(size: 12).weight(.semibold))
                    .foregroundStyle(LiquidColor.tinta700)
                    .rotationEffect(.degrees(otraFormaAbierta ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue(Text(otraFormaAbierta ? "expanded" : "collapsed"))
    }
}
#endif
