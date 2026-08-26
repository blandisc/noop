#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - BodyAgeSheet — «Edad corporal» en vidrio Liquid (FER-145 · FER-105 · TND-33)
//
// Migración PURAMENTE VISUAL del esqueleto «Tendencias Final» (papel «Instrumento») a los legos
// Liquid, calcando el patrón de `SkinTempDetailScreen.swift` (la vara) y de las hermanas ya
// firmadas: campo teñido a sangre (`LiquidCampoMetrica`) → costuras de sección
// (`LiquidFranjaSeccion`) → banda / barras / notas → método + sello. La matemática y el copy se
// conservan; esto es un reskin.
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
// `presentationBackground` (la hoja del #Preview). El param `theme` se conserva como compat muerto
// — la hoja Liquid ya no lo referencia, pero los call sites de `CuerpoView` lo pasan (FER-100).

struct BodyAgeSheet: View {
    /// The computed Body Age + Vitality, or nil when fewer than `minFactors` signals are present.
    let result: VitalityEngine.Result?
    /// The inputs that fed the engine — drives the "what's built from" checklist in the empty state.
    let inputs: VitalityEngine.Inputs
    /// El tema vivo «Instrumento», retenido por compatibilidad con los call sites — la hoja Liquid ya
    /// no lo referencia (mismo trato que las hermanas ya migradas).
    var theme: InstrumentoTheme = .base

    /// El tono de la pantalla: el VERDE de longevidad, la identidad de la Edad corporal (el CAMPO). El
    /// color del VEREDICTO vive solo en la banda (`tintLiquid(forDelta:)`).
    private static let tono = LiquidColor.verdePrimario

    // MARK: - Body — el esqueleto del bloque, en vidrio

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
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
        seccion(String(localized: "Your band")) { bandContent(r) }
        seccion(String(localized: "What's moving it")) { movesContent(r) }
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
            clausula: r.isPartialEstimate ? Self.partialCaveat(r) : nil) {
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
                etiquetaCorporal: "\(Int(r.bodyAge.rounded()))",
                etiquetaReal: "\(Int(r.chronoAge.rounded()))",
                tono: Self.tintLiquid(forDelta: r.deltaYears),
                bandaAnos: r.bandYears,
                etiquetaBandaBaja: "\(lo)",
                etiquetaBandaAlta: "\(hi)",
                a11yLabel: String(localized: "Body age"),
                a11yValue: Self.bandAccessibility(r))
            LiquidNotaLine(String(localized: "The band, not the exact point, is the reading."))
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
                a11yLabel: String(localized: "What's moving it"),
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
            LiquidOrigenChip(glyph: .corazon, badgeTono: Self.tono,
                             etiqueta: String(localized: "Calculated on your phone"),
                             sufijo: String(localized: "today"))
        }
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

    // MARK: - 5. Empty (fewer than 3 signals) — checklist de qué está hecha, sin número inventado

    private var emptyState: some View {
        let present = presentFactors
        return VStack(alignment: .leading, spacing: 0) {
            LiquidCampoMetrica(
                tono: Self.tono,
                titulo: String(localized: "Body age"),
                glifo: .corazon,
                datos: [.init(valor: LiquidCajita.sinDato, rotulo: "",
                              a11y: String(localized: "no data"), ausente: true)],
                veredicto: String(localized: "I need at least 3 signals to work this out without guessing. You have \(present.count)."))

            seccion(String(localized: "What it's built from")) {
                VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                    // El checklist NUNCA oculta los que faltan: presente = check, ausente = motivo.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(Self.factorChecklist.enumerated()), id: \.offset) { _, f in
                            LiquidChecklistRow(etiqueta: f.label, presente: present.contains(f.key),
                                               motivo: f.reason, tono: Self.tono)
                        }
                    }
                    .liquidTarjetaSeccion()
                    LiquidNotaLine(String(localized: "As more nights sync, it appears on its own: we don't show a half-finished number."))
                }
            }

            pieMetodo
        }
    }

    // MARK: - Copy helpers

    private func deltaSentence(_ r: VitalityEngine.Result) -> String {
        let chrono = Int(r.chronoAge.rounded())
        let d = Int(r.deltaYears.rounded())
        if d > 0 { return String(localized: "\(d) years younger than your age (\(chrono))") }
        if d < 0 { return String(localized: "\(-d) years older than your age (\(chrono))") }
        return String(localized: "Right at your chronological age (\(chrono))")
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
    private static let factorChecklist: [Factor] = [
        .init(key: "rhr",         label: String(localized: "Nighttime resting HR"), reason: String(localized: "needs nights")),
        .init(key: "sleep",       label: String(localized: "Sleep"),                reason: String(localized: "needs nights")),
        .init(key: "consistency", label: String(localized: "Sleep regularity"),     reason: String(localized: "needs nights")),
        .init(key: "hrv",         label: String(localized: "HRV"),                  reason: String(localized: "needs valid nights")),
        .init(key: "steps",       label: String(localized: "Steps"),                reason: String(localized: "connect Apple Health")),
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
    /// fila de Cuerpo (vía `tint(forDelta:theme:)`) como la banda Liquid (vía `tintLiquid(forDelta:)`),
    /// así los umbrales viven en UN solo lugar. `deltaYears` es cronológica − corporal: positivo = más
    /// joven que tu edad (buena noticia).
    enum DeltaPaso { case rejuvenece, enTuEdad, mayor, muyMayor }

    static func paso(forDelta deltaYears: Double) -> DeltaPaso {
        if deltaYears > 0.5 { return .rejuvenece }
        if deltaYears >= -0.5 { return .enTuEdad }
        if deltaYears >= -8 { return .mayor }
        return .muyMayor
    }

    /// El tinte de la fila/marcador «Instrumento», por el SIGNO del delta. FIRMA CONGELADA: la usa la
    /// fila de Cuerpo (`CuerpoView.swift:1103`) — se conserva idéntica; solo delega los cortes a `paso`.
    static func tint(forDelta deltaYears: Double, theme: InstrumentoTheme) -> Color {
        switch paso(forDelta: deltaYears) {
        case .rejuvenece: return theme.dataRecovery   // más joven → verde
        case .enTuEdad:   return theme.ink             // en tu edad → tinta
        case .mayor:      return theme.warning         // mayor → ámbar
        case .muyMayor:   return theme.critical        // muy mayor → rojo
        }
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

    private static func signed(_ years: Double) -> String { String(format: "%+.1f", years) }

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
