import SwiftUI
import CenitDesign
import StrandAnalytics

// MARK: - ActivityRecoverySheet — «Cómo amaneces tras cada deporte» en vidrio Liquid (FER-139 · FER-105 · TND-33)
//
// Migración PURAMENTE VISUAL del esqueleto «Tendencias Final» (papel «Instrumento») a los legos
// Liquid, calcando el patrón de `SkinTempDetailScreen.swift` (la vara de esta migración) y de las
// hermanas ya firmadas: campo teñido a sangre (`LiquidCampoMetrica`) → costura de sección
// (`LiquidFranjaSeccion`) → tarjetas de deporte compuestas EN LÍNEA con átomos Liquid → método +
// sello (patrón `pieMetodo` de Sueño). La matemática y el orden del ranking NO CAMBIAN.
//
// IDENTIDAD ÁMBAR (decisión ya tomada, FER-105/A): el campo se tiñe con `LiquidColor.ambar`, la
// paridad con Esfuerzo (strain) — NO el verde de longevidad de las otras dos hojas de Tendencias.
// El default verde de las hojas de edad violaría la identidad: «tras el deporte» habla de carga,
// no de longevidad.
//
// LAS TARJETAS DE DEPORTE se componen EN LÍNEA (regla §7: `LiquidTarjetaSesion` sería de uso
// único): una `LiquidBarraConteo` sobre ESCALA COMPARTIDA de |delta| en puntos (así los deportes
// se comparan entre sí de un vistazo — «cuál me pega más»), + un chip de confianza + una
// `LiquidNotaLine` con la nota de sesión/vuelta a la base. La confianza `.building` atenúa la
// tarjeta (0.72), como el papel. El orden es EXACTAMENTE el del motor (|delta| desc · .solid ·
// name asc); nunca se re-ordena ni se filtra.
//
// Se presenta como CAPA desde Cuerpo (`detailOverlayContent`), no como `.sheet`: sus
// `.presentation*` propios están inertes en producción (solo actúan en su #Preview). El fondo va
// por `background` (la capa) Y `presentationBackground` (la hoja del #Preview). El param `theme`
// se conserva como compat muerto — la hoja Liquid ya no lo referencia, pero los call sites de
// `CuerpoView` lo pasan y no se tocan (FER-100).

struct ActivityRecoverySheet: View {
    /// One `ActivityCost` per sport, already ranked by the engine (|delta| desc · .solid · name asc).
    let costs: [ActivityCost]

    /// El tema vivo «Instrumento», retenido por compatibilidad con los call sites — la hoja Liquid
    /// ya no lo referencia (mismo trato que las hermanas ya migradas).
    var theme: InstrumentoTheme = .base

    /// When there are no sessions yet AND Apple Health isn't connected, the empty state offers a quiet
    /// "your workouts can come from Apple Health" line — without a button (the connect action lives in
    /// Today). Never set when there's already data.
    var appleConnectHint: Bool = false

    /// El ⓘ del campo abre la tarjeta «Qué medimos» bajo él — paridad con las gemelas
    /// (`StrainDetailScreen`/`SkinTempDetailScreen`). (FER-105 · M1)
    @State private var infoOpen = false

    /// El tono de la pantalla: el ÁMBAR de identidad (paridad con Esfuerzo), nunca el verde de las
    /// hojas de edad. Existe para no confundir «carga tras el deporte» con «longevidad».
    private static let tono = LiquidColor.ambar

    // MARK: - Body — el esqueleto del bloque, en vidrio

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: .zero) {
                if costs.isEmpty {
                    campoSinDato
                    if appleConnectHint {
                        LiquidNotaLine(String(localized: "Your workouts can come from Apple Health. Connect it from Today to add them here."))
                            .liquidSeccion()
                    }
                } else {
                    campoConDato
                    if infoOpen { whatWeMeasureCard }
                    seccion(String(localized: "Your sports")) { sportsContent }
                    LiquidNotaLine(String(localized: "It's an estimate from your own history, not a diagnosis."))
                        .liquidSeccion(top: LiquidSpace.s100, bottom: LiquidSpace.s200)
                    pieMetodo
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // El fondo va en las DOS formas de presentación: `background` para la capa de Cuerpo y
        // `presentationBackground` para la hoja del #Preview (mismo par que las hermanas, FER-102).
        .background { LiquidSheetFondo(tone: Self.tono).ignoresSafeArea() }
        .presentationBackground { LiquidSheetFondo(tone: Self.tono) }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(LiquidRadius.hoja)
    }

    /// Una sección: la costura a sangre + su contenido con el margen del sistema.
    @ViewBuilder
    private func seccion<Content: View>(_ titulo: String, @ViewBuilder content: () -> Content) -> some View {
        LiquidFranjaSeccion(titulo, tono: Self.tono)
        content().liquidSeccion()
    }

    // MARK: - 1. El campo (héroe) — delta del deporte tope, identidad ámbar, signo −/+

    /// El campo teñido con dato: el numeral es el delta del deporte TOPE del ranking del motor
    /// (`costs.first` ya es el efecto más grande), con el signo −/+ del papel. `barelyMoves` → guion
    /// y veredicto neutro (no se inventa un número sobre un efecto que apenas se mueve).
    private var campoConDato: some View {
        let top = costs.first
        let showsNumeral = top.map { abs($0.delta) >= ActivityCostEngine.barelyMovesPoints } ?? false
        return LiquidCampoMetrica(
            tono: Self.tono,
            titulo: String(localized: "After each sport"),
            glifo: .afterSport,
            datos: [numeralDato(top, showsNumeral: showsNumeral)],
            veredicto: heroVerdict,
            infoAbierto: infoOpen,
            infoEtiqueta: String(localized: "What we measure"),
            onInfo: { withAnimation(LiquidMotion.lift) { infoOpen.toggle() } })
    }

    /// El campo APAGADO (sin sesiones): numeral en guion, nunca un cero. B2: el vacío vive SOLO en
    /// la cláusula (sin veredicto), como `SkinTempDetailScreen.campoSinDato` / `StrainDetailScreen`.
    /// B3: voz impersonal de la familia («Cénit necesita…»).
    private var campoSinDato: some View {
        LiquidCampoMetrica(
            tono: Self.tono,
            titulo: String(localized: "After each sport"),
            glifo: .afterSport,
            datos: [.init(valor: LiquidCajita.sinDato, rotulo: "",
                          a11y: String(localized: "no data"), ausente: true)],
            clausula: String(localized: "Cénit needs about 6 sessions of the same sport before it can show how you wake afterward. Keep logging your workouts and this fills in on its own."))
    }

    /// El numeral del campo: el delta del deporte tope con su signo, o el guion cuando apenas se mueve.
    /// Misma convención de signo que la tarjeta: delta ≥ 0 → amaneces MÁS BAJO → «−N».
    private func numeralDato(_ top: ActivityCost?, showsNumeral: Bool) -> LiquidCampoDato {
        guard let cost = top, showsNumeral else {
            return .init(valor: LiquidCajita.sinDato, rotulo: "",
                         a11y: String(localized: "no data"), ausente: true)
        }
        let pts = Int(abs(cost.delta).rounded())
        let firmado = "\(cost.delta >= 0 ? "−" : "+")\(pts)"
        // a11y omitido a propósito: el fallback del Dato dicta «valor + unidad» y la unidad «points»
        // ya está localizada, así que VoiceOver dice «−8 points» sin una clave aparte.
        return .init(valor: firmado, unidad: String(localized: "points"), rotulo: "")
    }

    /// Association framing (not cause). Solo se llama CON dato (desde `campoConDato`); el campo
    /// vacío lleva su propia cláusula, así que la rama `costs.isEmpty` se retiró (B2). B7: la
    /// métrica del motor (0–100 tipo recuperación) es «Recovery»/«Recuperación», el término que
    /// el resto del app usa para ese número, no «Charge» (fuera del glosario) ni «Carga» (esfuerzo).
    private var heroVerdict: String {
        if let top = costs.first, abs(top.delta) < ActivityCostEngine.barelyMovesPoints {
            return String(localized: "Your next-day Recovery barely moves after the sports we can see so far.")
        }
        return String(localized: "How your Recovery tends to look the morning after each sport, vs your rest days. Observed in your history, not a cause.")
    }

    // MARK: - 2. Tus deportes — tarjetas compuestas en línea (barra de escala compartida + nota)

    /// La escala COMPARTIDA de todas las barras: el mayor |delta| en puntos de la lista (piso 1). Con
    /// ella, la barra de cada deporte se lee contra las demás («cuál me pega más») en vez de contra sí
    /// misma. Se deriva UNA vez de la lista que el motor ya ordenó.
    private var escalaPuntos: Int {
        max(1, costs.map { Int(abs($0.delta).rounded()) }.max() ?? 1)
    }

    private var sportsContent: some View {
        let escala = escalaPuntos
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            ForEach(Array(costs.enumerated()), id: \.offset) { idx, cost in
                sportCard(cost, escala: escala, indice: idx)
            }
        }
    }

    /// Un deporte, compuesto EN LÍNEA con átomos Liquid (no `LiquidTarjetaSesion`, uso único): la barra
    /// de conteo sobre la escala compartida (|delta| en puntos) + el chip de confianza + la nota de
    /// sesión. `.building` atenúa la tarjeta (0.72) para leerse como provisional sin ocultarla. La
    /// frase completa (asociación, nunca causa) va como etiqueta de VoiceOver; la barra muestra la nota.
    private func sportCard(_ cost: ActivityCost, escala: Int, indice: Int) -> some View {
        let dimmed = cost.confidence == .building
        let pts = Int(abs(cost.delta).rounded())
        // Misma convención de signo que el campo: delta ≥ 0 → amaneces MÁS BAJO → «−N pts».
        let valorTexto = "\(cost.delta >= 0 ? "−" : "+")\(pts) pts"
        return VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            LiquidBarraConteo(
                rotulo: cost.sport,
                conteo: pts,
                escala: escala,
                tono: Self.tono,
                valorTexto: valorTexto,
                indice: indice,
                a11yLabel: cost.sport,
                a11yValue: valorTexto)
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
                confidenceChip(cost.confidence)
                LiquidNotaLine(barNote(for: cost))
                Spacer(minLength: 0)
            }
        }
        .liquidTarjetaSeccion()
        .opacity(dimmed ? 0.72 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(sentence(for: cost)))
    }

    /// El chip de confianza: cápsula punteada en tinta neutra (mismos tokens que el chip-disclaimer de
    /// `LiquidTendenciaCard`), un rótulo de estado — nunca un dato. Reusa las claves «solid»/«building».
    private func confidenceChip(_ confidence: ScoreConfidence) -> some View {
        Text(confidence == .solid ? String(localized: "solid") : String(localized: "building"))
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.tinta700)
            .padding(.horizontal, LiquidSpace.s225)
            .padding(.vertical, LiquidSpace.s075)
            .overlay(Capsule()
                .stroke(LiquidColor.tinta10,
                                      style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])))
            .accessibilityHidden(true)
    }

    /// Session / climb-back note for the bar. Uses the same fields as `sentence(for:)` without changing
    /// that helper's math or catalog keys (kept for accessibility / future use).
    private func barNote(for cost: ActivityCost) -> String {
        let n = cost.n
        if abs(cost.delta) < ActivityCostEngine.barelyMovesPoints {
            return String(format: String(localized: "%d sessions"), n)
        }
        guard let days = cost.daysToBaseline else {
            // Climbing-back case without a day estimate: sessions only (sentence(for:) still owns the full line).
            return String(format: String(localized: "%d sessions"), n)
        }
        if days == 1 {
            return String(format: String(localized: "Back to your base in ~1 day · %d sessions"), n)
        }
        return String(format: String(localized: "Back to your base in ~%d days · %d sessions"), days, n)
    }

    // MARK: - Sentence (localized; association, never causal)
    // Preserved verbatim for the card's VoiceOver label; the visible bar uses barNote for its slot.

    /// The plain-language impact line, built from the engine's fields. English source strings mirror
    /// `ActivityCost.sentence()` so the catalog (es-MX / de) translates a wording the engine already
    /// owns. `|delta|` is always ≥ 3 in the typical branch (the engine's `barelyMovesPoints` floor), so
    /// "points" is always plural; only "day/days" varies, handled with separate keys. Direction:
    /// delta ≥ 0 → "lower" (you wake below baseline), < 0 → "higher".
    private func sentence(for cost: ActivityCost) -> LocalizedStringKey {
        let n = cost.n
        if abs(cost.delta) < ActivityCostEngine.barelyMovesPoints {
            return "Sessions like this are barely linked to any change in your next-day Recovery (n=\(n))."
        }
        let pts = Int(abs(cost.delta).rounded())
        let lower = cost.delta >= 0
        guard let days = cost.daysToBaseline else {
            return lower
                ? "Sessions like this are typically followed by a Recovery about \(pts) points lower the next morning (n=\(n))."
                : "Sessions like this are typically followed by a Recovery about \(pts) points higher the next morning (n=\(n))."
        }
        if days == 1 {
            return lower
                ? "Sessions like this are typically followed by a Recovery about \(pts) points lower the next morning, climbing back in about 1 day (n=\(n))."
                : "Sessions like this are typically followed by a Recovery about \(pts) points higher the next morning, climbing back in about 1 day (n=\(n))."
        }
        return lower
            ? "Sessions like this are typically followed by a Recovery about \(pts) points lower the next morning, climbing back in about \(days) days (n=\(n))."
            : "Sessions like this are typically followed by a Recovery about \(pts) points higher the next morning, climbing back in about \(days) days (n=\(n))."
    }

    // MARK: - 3. Método + sello — patrón `pieMetodo` de Sueño (capilar sin franja propia)

    /// Method prose moved verbatim into `LiquidMetodo`; computed origin chip (medians over your own
    /// history) closes it, with the SAME «Calculated on your phone» vocabulary the hoja de Hoy uses.
    private var pieMetodo: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         mostrar: String(localized: "Show explanation"),
                         ocultar: String(localized: "Hide explanation")) {
                LiquidNotaLine(String(localized: "We compare the median of your Recovery the morning after each sport against your “untouched” rest days (no workouts, and not the days right after a session). The difference is what you see here."),
                               tono: LiquidColor.tinta700)
                LiquidNotaLine(String(localized: "It's an association, not a cause. Things like training on the days you already wake up well (then drifting back down), resting when you're tired or sick, or which day of the week you train all play a part."),
                               tono: LiquidColor.tinta700)
                LiquidNotaLine(String(localized: "Medians over your own history (Plews et al., 2013; HRV via RMSSD, Task Force 1996)."))
            }
            // B5: sin sufijo temporal («hoy»): esto no es la lectura de hoy sino medianas sobre
            // tu historial (paridad «Carga calculada», que tampoco lo lleva).
            LiquidOrigenChip(glyph: .afterSport, badgeTono: Self.tono,
                             etiqueta: String(localized: "Calculated on your phone"))
        }
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

    // MARK: - ⓘ «Qué medimos» — tarjeta bajo el campo (paridad gemelas, FER-105 · M1)

    /// La tarjeta del ⓘ: qué medimos tras cada deporte, en la prosa que la pantalla ya tiene (la
    /// comparación del método). Mismo patrón que `StrainDetailScreen.whatWeMeasureCard`.
    private var whatWeMeasureCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(String(localized: "What we measure"))
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "We compare the median of your Recovery the morning after each sport against your “untouched” rest days (no workouts, and not the days right after a session). The difference is what you see here."))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidTarjetaSeccion()
        .liquidSeccion(top: LiquidSpace.s400, bottom: LiquidSpace.s200)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ActivityRecoverySheet: con datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ActivityRecoverySheet(costs: [
            ActivityCost(sport: "Weight Training", delta: 8.2, nextMorningCenter: 54, baselineCenter: 62,
                         daysToBaseline: 2, n: 12, confidence: .solid),
            ActivityCost(sport: "Running", delta: 5.1, nextMorningCenter: 57, baselineCenter: 62,
                         daysToBaseline: nil, n: 7, confidence: .building),
            ActivityCost(sport: "Yoga", delta: 1.4, nextMorningCenter: 61, baselineCenter: 62,
                         daysToBaseline: nil, n: 9, confidence: .solid),
        ])
    }
}

#Preview("ActivityRecoverySheet: juntando datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ActivityRecoverySheet(costs: [], appleConnectHint: true)
    }
}
#endif
