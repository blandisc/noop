#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Fitness Age detail — «Edad física» en vidrio Liquid (FER-141 · FER-105 · TND-33)
//
// Migración PURAMENTE VISUAL del esqueleto «Tendencias Final» (papel «Instrumento») a los legos
// Liquid, calcando el patrón de `SkinTempDetailScreen.swift` (la vara) y de las hermanas ya
// firmadas: campo teñido a sangre (`LiquidCampoMetrica`) → costuras de sección
// (`LiquidFranjaSeccion`) → cajitas / notas → método + sello. La matemática y el copy se
// conservan; esto es un reskin.
//
// Presenta el número honestamente en los dos estados que el motor distingue:
//   • ready / estimate — campo verde longevidad con cápsula ESTIMATE permanente, delta + margen +
//     disclaimer no-clínico como veredicto, «What moves it» (2 cajitas RHR/actividad + ancla),
//     VO₂max medido (Apple, complementario) y método con el checklist de transparencia + Nes/HUNT.
//   • notReady — sin número inventado: campo apagado + el checklist de lo que aún falta.
//
// IDENTIDAD VERDE: `fitness_age` no está en el mapa canónico de tonos, así que toma
// `LiquidColor.verdePrimario` — coincide con el verde de longevidad de Hoy. El VO₂max de Apple
// (FER-215) se muestra como dato complementario etiquetado con su fuente; NO alimenta la Edad
// física de Nes (esa sigue siendo la comparación propia del modelo).
//
// Se presenta como CAPA desde Cuerpo (`detailOverlayContent`): sus `.presentation*` propios están
// inertes en producción (solo actúan en su #Preview). El fondo va por `background` (la capa) Y
// `presentationBackground` (la hoja del #Preview). El param `theme` se conserva como compat muerto
// — la hoja Liquid ya no lo referencia, pero los call sites de `CuerpoView` lo pasan (FER-100).

struct FitnessAgeDetailView: View {
    let snapshot: FitnessAgeSnapshot
    /// Chronological age + sex from the profile (the snapshot carries the derived values, not these).
    let chronoAge: Int
    let sex: String
    /// VO₂max measured by Apple Health (ml/kg/min), `nil` if none. Independent of the Nes Fitness Age —
    /// a complementary, source-labeled datum. (FER-215)
    var appleVO2max: Double? = nil
    /// When there's no Apple VO₂max AND Apple Health isn't connected → show a quiet connect nudge;
    /// when connected-but-no-reading, the block hides entirely. (FER-215)
    var appleConnectHint: Bool = false
    /// The fitness TRAJECTORY over weeks (rising / stable / falling) from `VO2maxTrend` (FER-679), plus
    /// the raw VO₂max series for the context sparkline. Kept on the API so call sites are unchanged; the
    /// Final «Edad física» layout does not surface the trend block (dead compat, as before).
    var vo2Trend: VO2maxTrend.Result? = nil
    /// The raw measured VO₂max series (values only, oldest→newest) behind the trend. Dead compat.
    var vo2Series: [Double] = []
    /// El tema vivo «Instrumento», retenido por compatibilidad con los call sites — la hoja Liquid ya
    /// no lo referencia (mismo trato que las hermanas ya migradas).
    var theme: InstrumentoTheme = .base

    /// El tono de la pantalla: el VERDE de longevidad, la identidad de la Edad física.
    private static let tono = LiquidColor.verdePrimario

    // MARK: - Body — el esqueleto del bloque, en vidrio

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let result = snapshot.result {
                    readyBody(result)
                } else {
                    notReadyBody
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
    private func seccion<Content: View>(_ titulo: String, pista: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        LiquidFranjaSeccion(titulo, pista: pista, tono: Self.tono)
        content().liquidSeccion()
    }

    // MARK: - Ready / estimate (Final skeleton)

    @ViewBuilder private func readyBody(_ result: FitnessAgeResult) -> some View {
        campoConDato(result)
        seccion(String(localized: "What moves it")) { leversContent }
        if showsVO2maxSection {
            seccion(String(localized: "VO₂max"), pista: String(localized: "Apple")) { vo2maxContent }
        }
        pieMetodo
    }

    // MARK: - 1. El campo (héroe) — edad física, identidad verde, cápsula ESTIMATE permanente

    /// El campo teñido con dato: la edad física como numeral, el delta vs tu edad como veredicto, el
    /// margen ±años + el disclaimer no-clínico en la cláusula, y la cápsula ESTIMATE permanente en la
    /// ranura del pie (el sello del campo).
    private func campoConDato(_ result: FitnessAgeResult) -> some View {
        let ageNum = Int(result.fitnessAge.rounded())
        let bandInt = Int(result.bandYears.rounded())
        return LiquidCampoMetrica(
            tono: Self.tono,
            titulo: String(localized: "Physical age"),
            glifo: .fitnessAge,
            // a11y omitido a propósito: el fallback del Dato dicta «valor + unidad» y la unidad
            // «years» ya está localizada, así que VoiceOver dice «36 years» sin una clave aparte.
            datos: [.init(valor: "\(ageNum)", unidad: String(localized: "years"), rotulo: "")],
            veredicto: deltaSubtitle(result),
            clausula: String(localized: "An estimate with a ±\(bandInt)-year margin.")
                + " " + String(localized: "It's a comparison of your fitness, not your biological age or a medical diagnosis.")) {
            LiquidCampoSello(String(localized: "Estimate"))
        }
    }

    // MARK: - 2. What moves it — 2 cajitas (RHR · actividad) + ancla Nes/HUNT
    //
    // Los valores van EN TINTA (no teñidos): dos cajitas de color bajo un campo ya verde sería
    // demasiado color (LiquidCajita §, DESIGN §8.4-2). El «trend, not cause» del papel se retira: RHR
    // y actividad son las ENTRADAS del modelo, no hallazgos de tendencia; el ancla dice de dónde sale.

    private var leversContent: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCajitaGrid(columnas: 2) {
                LiquidCajita(
                    rotulo: String(localized: "Resting heart rate"),
                    valor: snapshot.restingHR.map { "\(Int($0.rounded()))" } ?? LiquidCajita.sinDato,
                    unidad: snapshot.restingHR != nil ? String(localized: "bpm") : "",
                    pie: String(localized: "The lower it is, the younger."))
                LiquidCajita(
                    rotulo: String(localized: "Recent activity"),
                    valor: "\(snapshot.activeDays) / 7",
                    unidad: String(localized: "days"),
                    pie: String(localized: "More active days also bring it down."))
            }
            LiquidNotaLine(String(localized: "Nes/HUNT model (2011)"))
        }
    }

    // MARK: - 3. VO₂max (Apple Health, measured · FER-215)

    private var showsVO2maxSection: Bool { appleVO2max != nil || appleConnectHint }

    @ViewBuilder private var vo2maxContent: some View {
        if let vo2 = appleVO2max {
            let expected = Int(VO2maxReference.expected(age: chronoAge, sex: sex).rounded())
            VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
                    Text(verbatim: "\(Int(vo2.rounded()))")
                        .font(LiquidType.valorL)
                        .foregroundStyle(LiquidColor.azul)
                    Text(verbatim: "ml/kg/min")
                        .font(LiquidType.unidad)
                        .foregroundStyle(LiquidColor.tinta500)
                }
                .accessibilityElement(children: .combine)
                LiquidNotaLine(String(localized: "Measured by your Apple Watch during exercise."),
                               tono: LiquidColor.tinta700)
                LiquidNotaLine(String(localized: "The average for your age is around \(expected)."))
            }
        } else if appleConnectHint {
            // No Apple reading + not connected: a quiet, no-number invite. No button — connecting
            // lives in Today / Settings (parity with the paper original).
            LiquidNotaLine(String(localized: "Connect Apple Health to see your VO₂max."),
                           tono: LiquidColor.tinta700)
        }
    }

    // MARK: - 4. Not ready (no number — honest empty state)

    @ViewBuilder private var notReadyBody: some View {
        LiquidCampoMetrica(
            tono: Self.tono,
            titulo: String(localized: "Physical age"),
            glifo: .fitnessAge,
            datos: [.init(valor: LiquidCajita.sinDato, rotulo: "",
                          a11y: String(localized: "no data"), ausente: true)],
            veredicto: String(localized: "We can't calculate your physical age yet."))

        seccion(String(localized: "What we need")) {
            VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                VStack(alignment: .leading, spacing: 0) {
                    usingRow(profileStatus, label: String(localized: "Age and sex"),
                             motivo: String(localized: "Add your age and sex."))
                    usingRow(status("rhr"), label: String(localized: "Resting heart rate"),
                             motivo: String(localized: "\(snapshot.rhrNights) of 4 nights needed"))
                }
                .liquidTarjetaSeccion()
                LiquidNotaLine(String(localized: "Wear your Apple Watch to sleep and this fills in on its own."))
            }
        }

        if showsVO2maxSection {
            seccion(String(localized: "VO₂max"), pista: String(localized: "Apple")) { vo2maxContent }
        }

        pieMetodo
    }

    // MARK: - 5. Método + sello — patrón `pieMetodo` de Sueño (capilar sin franja propia)

    private var pieMetodo: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         mostrar: String(localized: "Show explanation"),
                         ocultar: String(localized: "Hide explanation")) {
                // Transparency checklist (was «usingSection») — preserved inside the method.
                Text(String(localized: "What we're using")).liquidLabel().foregroundStyle(LiquidColor.tinta500)
                VStack(alignment: .leading, spacing: 0) {
                    usingRow(profileStatus, label: String(localized: "Age and sex"),
                             motivo: String(localized: "Add your age and sex."))
                    usingRow(status("rhr"), label: String(localized: "Resting heart rate"),
                             motivo: String(localized: "\(snapshot.rhrNights) of 7 nights"))
                    usingRow(status("activity"), label: String(localized: "Recent activity"),
                             motivo: String(localized: "\(snapshot.activeDays) of 7 days"))
                }
                .liquidTarjetaSeccion()
                LiquidNotaLine(String(localized: "Based on the Nes/HUNT model (2011): it estimates your aerobic capacity from your resting heart rate and activity, and compares it with the average for your age."),
                               tono: LiquidColor.tinta700)
                LiquidNotaLine(String(localized: "It's a comparison of your fitness, not your biological age or a medical diagnosis."))
            }
            LiquidOrigenChip(glyph: .fitnessAge, badgeTono: Self.tono,
                             etiqueta: String(localized: "Calculated on your phone"),
                             sufijo: String(localized: "today"))
        }
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

    // MARK: - Checklist row (shared method / not-ready)
    //
    // `LiquidChecklistRow` muestra el motivo SOLO cuando el factor está ausente: un check honesto no
    // necesita excusa. El detalle de conteo del papel para las filas PRESENTES («5 de 7 noches») se
    // retira — el check ya dice «lo tenemos» (degradación declarada de la migración). `.partial` se
    // trata como ausente (no está del todo), y ahí el motivo sí aparece.

    private func usingRow(_ status: FitnessReadinessStatus, label: String, motivo: String) -> LiquidChecklistRow {
        LiquidChecklistRow(etiqueta: label, presente: status == .satisfied, motivo: motivo, tono: Self.tono)
    }

    // MARK: - Direction + copy

    private func deltaSubtitle(_ result: FitnessAgeResult) -> String {
        let yrs = Int(abs(result.deltaYears).rounded())
        switch result.direction {
        case .younger: return String(localized: "\(yrs) years younger than your age of \(chronoAge).")
        case .older:   return String(localized: "\(yrs) years above your age of \(chronoAge).")
        case .even:    return String(localized: "Right at your age of \(chronoAge).")
        }
    }

    // MARK: - Checklist status helpers

    private func status(_ key: String) -> FitnessReadinessStatus {
        snapshot.readiness.items.first { $0.key == key }?.status ?? .missing
    }

    /// Age + sex share one row: both come from the profile, so the row is satisfied unless one is unset.
    private var profileStatus: FitnessReadinessStatus {
        (status("age") == .satisfied && status("sex") == .satisfied) ? .satisfied : .missing
    }
}

// MARK: - Preview

#if DEBUG
private func previewSnapshot(rhr: Int, strainActiveDays: Int, age: Int, sex: String = "male")
    -> FitnessAgeSnapshot {
    let rhrArr: [Int?] = Array(repeating: rhr, count: 7)
    var strainArr: [Double?] = Array(repeating: nil, count: 7)
    for i in 0..<min(strainActiveDays, 7) { strainArr[i] = 12 }
    return FitnessAgeEngine.snapshot(rhrLast7: rhrArr, strainLast7: strainArr,
                                     age: age, sex: sex, hasHeightWeight: true)
}

#Preview("Fitness Age: younger (ready)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FitnessAgeDetailView(snapshot: previewSnapshot(rhr: 50, strainActiveDays: 7, age: 36),
                             chronoAge: 36, sex: "male")
    }
}

#Preview("Fitness Age: older (estimate) + VO₂max") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FitnessAgeDetailView(snapshot: previewSnapshot(rhr: 72, strainActiveDays: 4, age: 36),
                             chronoAge: 36, sex: "male", appleVO2max: 41)
    }
}

#Preview("Fitness Age: not ready") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FitnessAgeDetailView(
            snapshot: FitnessAgeEngine.snapshot(
                rhrLast7: [50, 52] + Array(repeating: nil, count: 5),
                strainLast7: Array(repeating: nil, count: 7),
                age: 36, sex: "male", hasHeightWeight: false),
            chronoAge: 36, sex: "male")
    }
}
#endif
#endif
