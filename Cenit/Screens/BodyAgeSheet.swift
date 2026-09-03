#if os(iOS)
import SwiftUI
import CenitDesign
import StrandAnalytics

// MARK: - BodyAgeSheet — «Edad corporal» en vidrio Liquid (FER-145 · FER-105 · TND-33)
//
// «Edad corporal» en Liquid Glass · El Eje (FER-145 · FER-342). Calcando el patrón de
// `SkinTempDetailScreen.swift` (la vara) y de las hermanas ya firmadas: campo teñido a sangre
// (`LiquidCampoMetrica`) → costuras de sección (`LiquidFranjaSeccion`) → banda / barras / notas
// → método + sello. La matemática y el copy se conservan.
//
// La Edad corporal es el héroe (campo verde longevidad, cápsula ESTIMATE permanente); el matiz de
// estimación parcial vive en la lectura del campo. La lectura es un RANGO (`LiquidBandaEdad`, ±5),
// no un punto — la banda, no el punto exacto, ES la lectura. Vitalidad 0–100 corre debajo como
// contexto quieto (la MISMA medida en otra escala, nunca un segundo héroe). El desglose son las
// `LiquidBarrasContribucion` con signo. Sin resultado aún (< 3 señales), un checklist honesto de
// «de qué está hecha» en vez de un número inventado.
//
// IDENTIDAD VERDE del CAMPO (no del veredicto): el campo se tiñe con `LiquidColor.verdePrimario`,
// la identidad de la Edad corporal. La BANDA sí lleva el color del VEREDICTO — una escalera bespoke
// de 4 ramas CON rojo (ver `paso(forDelta:)`), traducida a voces Liquid en el call site.
//
// Se presenta como CAPA desde Cuerpo (`detailOverlayContent`): sus `.presentation*` propios están
// inertes en producción (solo actúan en su #Preview). El fondo va por `background` (la capa) Y
// `presentationBackground` (la hoja del #Preview).

struct BodyAgeSheet: View {
    /// The computed Body Age + Vitality, or nil when fewer than `minFactors` signals are present.
    let result: VitalityEngine.Result?
    /// The inputs that fed the engine — drives the "what's built from" checklist in the empty state.
    let inputs: VitalityEngine.Inputs

    /// El ⓘ del campo abre la tarjeta «Qué medimos» bajo él — paridad con las gemelas
    /// (`StrainDetailScreen`/`SkinTempDetailScreen`). (FER-105 · M1)
    @State private var infoOpen = false

    /// El tono de la pantalla: el VERDE de longevidad, la identidad de la Edad corporal (el CAMPO). El
    /// color del VEREDICTO vive solo en la banda (`tintLiquid(forDelta:)`).
    private static let tono = LiquidColor.verdePrimario

    // MARK: - Body — el esqueleto del bloque, en vidrio

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: .zero) {
                if let r = result {
                    withData(r)
                } else {
                    emptyState
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

    // MARK: - With data (Final skeleton)

    @ViewBuilder private func withData(_ r: VitalityEngine.Result) -> some View {
        campoConDato(r)
        if infoOpen { whatWeMeasureCard }
        // B1: «Tu rango» — «banda» es el strap en el glosario y esta app RETIRÓ la banda.
        // T2: «What moves it», la MISMA clave que Edad física (no «What's moving it»).
        seccion(String(localized: "Your range")) { bandContent(r) }
        seccion(String(localized: "What moves it")) { movesContent(r) }
        pieMetodo
    }

    // MARK: - 1. El campo (héroe) — edad corporal, identidad verde, cápsula ESTIMATE permanente

    private func campoConDato(_ r: VitalityEngine.Result) -> some View {
        let bodyAge = Int(r.bodyAge.rounded())
        return LiquidCampoMetrica(
            tono: Self.tono,
            titulo: String(localized: "Body age"),
            glifo: .corazon,
            // a11y omitido a propósito: el fallback del Dato dicta «valor + unidad» y la unidad
            // «years» ya está localizada, así que VoiceOver dice «31 years» sin una clave aparte.
            datos: [.init(valor: "\(bodyAge)", unidad: String(localized: "years"), rotulo: "")],
            veredicto: deltaSentence(r),
            // Partial nuance lives in the hero reading (was a separate chip + caption).
            clausula: r.isPartialEstimate ? Self.partialCaveat(r) : nil,
            infoAbierto: infoOpen,
            infoEtiqueta: String(localized: "What we measure"),
            onInfo: { withAnimation(LiquidMotion.lift) { infoOpen.toggle() } }) {
            LiquidCampoSello(String(localized: "Estimate"))
        }
    }

    // MARK: - 2. Your band (LiquidBandaEdad + vitalidad de contexto)

    private func bandContent(_ r: VitalityEngine.Result) -> some View {
        let lo = Int((r.bodyAge - r.bandYears).rounded())
        let hi = Int((r.bodyAge + r.bandYears).rounded())
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidBandaEdad(
                edadCorporal: r.bodyAge,
                edadReal: r.chronoAge,
                dominio: Self.dominio(r),
                // T4: el contrato del DS pide «N años» en las etiquetas del dato y la referencia.
                // Los extremos de la banda van desnudos («26»/«36») por contrato del DS (comparten
                // el carril inferior con la edad real; tres «años» ahí se encimarían).
                etiquetaCorporal: String(localized: "\(Int(r.bodyAge.rounded())) years"),
                etiquetaReal: String(localized: "\(Int(r.chronoAge.rounded())) years"),
                tono: Self.tintLiquid(forDelta: r.deltaYears),
                bandaAnos: r.bandYears,
                etiquetaBandaBaja: "\(lo)",
                etiquetaBandaAlta: "\(hi)",
                a11yLabel: String(localized: "Body age"),
                a11yValue: Self.bandAccessibility(r))
            LiquidNotaLine(String(localized: "The range, not the exact point, is the reading."))
            // Vitality — the same measure on a 0–100 scale (quiet, in ink, never a second hero).
            LiquidCajita(rotulo: String(localized: "The same measure, 0–100"),
                         valor: "\(Int(r.vitality.rounded()))",
                         pie: String(localized: "50 = typical"))
        }
    }

    // MARK: - 3. What's moving it (LiquidBarrasContribucion con signo + diferenciador)

    private func movesContent(_ r: VitalityEngine.Result) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidBarrasContribucion(
                factores: Self.factores(r.contributions),
                maximo: Self.maximo(r.contributions),
                poloIzquierdo: String(localized: "← rejuvenates you"),
                poloDerecho: String(localized: "ages you →"),
                a11yLabel: String(localized: "What moves it"),
                a11yValue: Self.barsAccessibility(r.contributions))

            // Differentiator vs the cardio-only Physical Age (FER-141) — verbatim.
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                Text(String(localized: "This isn't your Physical age"))
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta900)
                LiquidNotaLine(String(localized: "Physical age measures only the cardiorespiratory side. This one also weighs sleep, regularity, HRV and steps: so the two can differ."),
                               tono: LiquidColor.tinta700)
            }
            .liquidTarjetaSeccion()
        }
    }

    // MARK: - 4. Método + sello — patrón `pieMetodo` de Sueño (capilar sin franja propia)

    private var pieMetodo: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         mostrar: String(localized: "Show explanation"),
                         ocultar: String(localized: "Hide explanation")) {
                LiquidNotaLine(String(localized: "A wellness comparison, not a biological age or a clinical diagnosis. HRV is estimated from nighttime PPG; the reference norm is conservative."),
                               tono: LiquidColor.tinta700)
            }
            // B5: sin sufijo temporal («hoy»): la edad corporal es un estimado, no la lectura de hoy.
            LiquidOrigenChip(glyph: .corazon, badgeTono: Self.tono,
                             etiqueta: String(localized: "Calculated on your phone"))
        }
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

    // MARK: - ⓘ «Qué medimos» — tarjeta bajo el campo (paridad gemelas, FER-105 · M1)

    /// La tarjeta del ⓘ: qué es la Edad corporal, en la prosa que la pantalla ya tiene (la nota
    /// del método). Mismo patrón que `StrainDetailScreen.whatWeMeasureCard`.
    private var whatWeMeasureCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(String(localized: "What we measure"))
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "A wellness comparison, not a biological age or a clinical diagnosis. HRV is estimated from nighttime PPG; the reference norm is conservative."))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidTarjetaSeccion()
        .liquidSeccion(top: LiquidSpace.s400, bottom: LiquidSpace.s200)
    }

    // MARK: - 5. Empty (fewer than 3 signals) — checklist de qué está hecha, sin número inventado

    private var emptyState: some View {
        let present = presentFactors
        return VStack(alignment: .leading, spacing: .zero) {
            LiquidCampoMetrica(
                tono: Self.tono,
                titulo: String(localized: "Body age"),
                glifo: .corazon,
                datos: [.init(valor: LiquidCajita.sinDato, rotulo: "",
                              a11y: String(localized: "no data"), ausente: true)],
                // B2/B3: el vacío vive en la CLÁUSULA (no en el veredicto) y en voz impersonal
                // de la familia (nunca «yo necesito»), como las gemelas.
                clausula: String(localized: "Cénit needs at least 3 signals to work this out without guessing. So far it has \(present.count)."))

            seccion(String(localized: "What it's built from")) {
                VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                    // El checklist NUNCA oculta los que faltan: presente = check, ausente = motivo.
                    VStack(alignment: .leading, spacing: .zero) {
                        ForEach(Array(Self.factorChecklist.enumerated()), id: \.offset) { _, f in
                            LiquidChecklistRow(etiqueta: f.label, presente: present.contains(f.key),
                                               motivo: f.reason, tono: Self.tono)
                        }
                    }
                    .liquidTarjetaSeccion()
                    LiquidNotaLine(String(localized: "As more nights sync, it appears on its own: we don't show a half-finished number."))
                }
            }
            // B4: sin dato, sin pie de método ni chip de origen sobre un guion (paridad gemelas /
            // ActivityRecovery). El método y su sello viven solo en el estado con dato.
        }
    }

    // MARK: - Copy helpers

    private func deltaSentence(_ r: VitalityEngine.Result) -> String {
        let chrono = Int(r.chronoAge.rounded())
        let d = Int(r.deltaYears.rounded())
        // T7: UN molde compartido con Edad física («… than your age of N.», con punto final).
        if d > 0 { return String(localized: "\(d) years younger than your age of \(chrono).") }
        if d < 0 { return String(localized: "\(-d) years older than your age of \(chrono).") }
        return String(localized: "Right at your age of \(chrono).")
    }

    /// Names which heaviest factor(s) the reading is missing (FER-643), so the caveat is specific: an
    /// Apple-Health-only user misses both HRV and resting HR; a band user with sparse HRV nights misses
    /// only HRV. Not shown when both are present (`isPartialEstimate == false`).
    private static func partialCaveat(_ r: VitalityEngine.Result) -> String {
        let keys = Set(r.contributions.map(\.key))
        let noHRV = !keys.contains("hrv"), noRHR = !keys.contains("rhr")
        if noHRV && noRHR {
            return String(localized: "Worked out without HRV or resting heart rate: the two heaviest signals. The number still holds, with less precision.")
        }
        if noHRV {
            return String(localized: "Worked out without HRV: one of the heaviest signals. The number still holds, with less precision.")
        }
        return String(localized: "Worked out without resting heart rate: one of the heaviest signals. The number still holds, with less precision.")
    }

    // MARK: - Empty-state coverage

    private struct Factor { let key: String; let label: String; let reason: String }
    // B6: los motivos de fila ausente son oraciones completas con punto (paridad
    // `LiquidChecklistRow` preview y las cláusulas de la familia), no fragmentos en minúscula.
    private static let factorChecklist: [Factor] = [
        .init(key: "rhr",         label: String(localized: "Nighttime resting HR"), reason: String(localized: "Needs a few more nights.")),
        .init(key: "sleep",       label: String(localized: "Sleep"),                reason: String(localized: "Needs a few more nights.")),
        .init(key: "consistency", label: String(localized: "Sleep regularity"),     reason: String(localized: "Needs a few more nights.")),
        .init(key: "hrv",         label: String(localized: "HRV"),                  reason: String(localized: "Needs a few more valid nights.")),
        .init(key: "steps",       label: String(localized: "Steps"),                reason: String(localized: "Connect Apple Health to include them.")),
    ]
    private var presentFactors: Set<String> {
        var s = Set<String>()
        if inputs.restingHR != nil { s.insert("rhr") }
        if inputs.sleepHours != nil { s.insert("sleep") }
        if inputs.sleepConsistency != nil { s.insert("consistency") }
        if inputs.rmssd != nil { s.insert("hrv") }
        if inputs.steps != nil { s.insert("steps") }
        return s
    }

    // MARK: - Banda: dominio + tinte de veredicto (escalera compartida con la fila de Cuerpo)

    /// La escala visible de la banda: abarca la banda ±N Y la edad cronológica, para que ni la marca
    /// del dato ni el tick de referencia se salgan del riel cuando el cuerpo deriva lejos. Presentación
    /// pura (el papel `BodyAgeBand` hacía lo mismo con su propio `scaleLo/scaleHi`).
    static func dominio(_ r: VitalityEngine.Result) -> ClosedRange<Double> {
        let lo = Swift.min(r.bodyAge - r.bandYears, r.chronoAge)
        let hi = Swift.max(r.bodyAge + r.bandYears, r.chronoAge)
        let pad = Swift.max((hi - lo) * 0.12, 2)
        return (lo - pad)...(hi + pad)
    }

    /// El PASO de la escalera bespoke de 4 ramas, por el SIGNO del delta. Es la ÚNICA fuente de los
    /// cortes (>0.5 rejuvenece · ≥−0.5 en tu edad · ≥−8 mayor · resto muy mayor) — la leen tanto la
    /// fila de Cuerpo como la banda (vía `tint(forDelta:)` / `tintLiquid(forDelta:)`), así los
    /// umbrales viven en UN solo lugar. `deltaYears` es cronológica − corporal: positivo = más
    /// joven que tu edad (buena noticia).
    enum DeltaPaso { case rejuvenece, enTuEdad, mayor, muyMayor }

    static func paso(forDelta deltaYears: Double) -> DeltaPaso {
        if deltaYears > 0.5 { return .rejuvenece }
        if deltaYears >= -0.5 { return .enTuEdad }
        if deltaYears >= -8 { return .mayor }
        return .muyMayor
    }

    /// El tinte de la fila/marcador, por el SIGNO del delta. Misma escalera que `tintLiquid`.
    static func tint(forDelta deltaYears: Double) -> Color {
        tintLiquid(forDelta: deltaYears)
    }

    /// El tinte de la BANDA Liquid, la MISMA escalera de 4 ramas traducida a voces Liquid CON rojo
    /// (decisión FER-105/B). `LiquidBarrasContribucion.tono` es 3-way SIN rojo a propósito; la banda
    /// SÍ lo lleva, y la traducción vive aquí en el call site — no dentro de la pieza.
    static func tintLiquid(forDelta deltaYears: Double) -> Color {
        switch paso(forDelta: deltaYears) {
        case .rejuvenece: return LiquidColor.verdePrimario
        case .enTuEdad:   return LiquidColor.tinta900
        case .mayor:      return LiquidColor.atencion
        case .muyMayor:   return LiquidColor.negativo
        }
    }

    // MARK: - Barras de contribución: mapeo + escala + a11y

    /// Map the engine contributions to Liquid diverging bars (years, ordered by |years| descending,
    /// localized short labels, bare signed number as the detail — matching the paper `ContributionBars`).
    static func factores(_ contribs: [VitalityEngine.Contribution]) -> [LiquidBarrasContribucion.Factor] {
        contribs
            .map { LiquidBarrasContribucion.Factor(id: $0.key, etiqueta: shortLabel(for: $0.key),
                                                   efecto: $0.years, detalle: signed($0.years)) }
            .sorted { abs($0.efecto) > abs($1.efecto) }
    }

    /// El tope |años| de la escala compartida (mismo cálculo que el papel: máximo local, piso 0.001 para
    /// no dividir entre cero). Lo pasa el caller para que el componente no normalice contra su máximo.
    static func maximo(_ contribs: [VitalityEngine.Contribution]) -> Double {
        Swift.max(contribs.map { abs($0.years) }.max() ?? 1, 0.001)
    }

    /// El valor hablado del bloque entero (`LiquidBarrasContribucion` colapsa a UN solo a11y): une la
    /// frase de cada factor en el orden mostrado.
    static func barsAccessibility(_ contribs: [VitalityEngine.Contribution]) -> String {
        contribs
            .sorted { abs($0.years) > abs($1.years) }
            .map { "\(shortLabel(for: $0.key)) \(barAccessibility($0.years))" }
            .joined(separator: "; ")
    }

    /// El número del factor CON unidad y con el menos real (U+2212), como pide el contrato del DS
    /// («−1.2 años») y como el numeral de ActivityRecovery ya arma su «−N». (FER-105 · T5)
    private static func signed(_ years: Double) -> String {
        let numero = (years < 0 ? "\u{2212}" : "+") + String(format: "%.1f", abs(years))
        return String(localized: "\(numero) years")
    }

    /// Localized spoken value for one contribution factor.
    private static func barAccessibility(_ years: Double) -> String {
        let mag = String(format: "%.1f", abs(years))
        if years < -0.05 { return String(localized: "rejuvenates you by \(mag) years") }
        if years > 0.05 { return String(localized: "ages you by \(mag) years") }
        return String(localized: "neutral")
    }

    /// Localized spoken value for the band (numbers only, three sign branches).
    private static func bandAccessibility(_ r: VitalityEngine.Result) -> String {
        let body = Int(r.bodyAge.rounded()), chrono = Int(r.chronoAge.rounded())
        let d = Int(r.deltaYears.rounded())
        let lo = Int((r.bodyAge - r.bandYears).rounded()), hi = Int((r.bodyAge + r.bandYears).rounded())
        // Announce reduced confidence first, so VoiceOver users hear it before the number (FER-643).
        let prefix = r.isPartialEstimate ? String(localized: "Partial estimate. ") : ""
        if d > 0 { return prefix + String(localized: "Body age \(body), \(d) years younger than your age \(chrono); estimated range \(lo) to \(hi)") }
        if d < 0 { return prefix + String(localized: "Body age \(body), \(-d) years older than your age \(chrono); estimated range \(lo) to \(hi)") }
        return prefix + String(localized: "Body age \(body), at your age \(chrono); estimated range \(lo) to \(hi)")
    }

    private static func shortLabel(for key: String) -> String {
        switch key {
        case "rhr":         return String(localized: "Resting HR")
        case "vo2max":      return String(localized: "VO₂max")
        case "sleep":       return String(localized: "Sleep")
        case "consistency": return String(localized: "Regularity")
        case "hrv":         return String(localized: "HRV")
        case "steps":       return String(localized: "Steps")
        default:            return key
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("BodyAgeSheet: con datos") {
    let inputs = VitalityInputsBuilder.build(.init(
        chronoAge: 34,
        nightlyRestingHR: Array(repeating: 54, count: 10),
        nightlyRMSSD: Array(repeating: 48, count: 10),
        nightlySleepHours: Array(repeating: 7.2, count: 10),
        dailySteps: Array(repeating: 8200, count: 10)))
    return Color.clear.sheet(isPresented: .constant(true)) {
        BodyAgeSheet(result: VitalityEngine.compute(inputs), inputs: inputs)
    }
}

#Preview("BodyAgeSheet: estimación parcial (solo Apple)") {
    // No band → no nocturnal RHR and HRV gated out; only sleep, regularity and steps remain → the
    // reading computes but flags «Partial estimate» (FER-643).
    let inputs = VitalityInputsBuilder.build(.init(
        chronoAge: 34,
        nightlySleepHours: Array(repeating: 7.2, count: 10),
        dailySteps: Array(repeating: 8200, count: 10)))
    return Color.clear.sheet(isPresented: .constant(true)) {
        BodyAgeSheet(result: VitalityEngine.compute(inputs), inputs: inputs)
    }
}

#Preview("BodyAgeSheet: sin señales") {
    let inputs = VitalityInputsBuilder.build(.init(chronoAge: 34, nightlyRestingHR: [55, 56]))
    return Color.clear.sheet(isPresented: .constant(true)) {
        BodyAgeSheet(result: VitalityEngine.compute(inputs), inputs: inputs)
    }
}
#endif
#endif
