#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import CenitStore
import BiometricStreams
import Foundation

// MARK: - SleepDetailScreen — el «Detalle de Sueño» en vidrio Liquid (FER-102)
//
// Migración PURAMENTE VISUAL del esqueleto «Tendencias Final» (papel «Instrumento») a los legos
// Liquid: campo teñido a sangre (`LiquidCampoMetrica`) → costuras de sección
// (`LiquidFranjaSeccion`) → mosaicos (`LiquidCajita`) → las gráficas de la familia. Los motores,
// el modelo y los loaders NO cambian: `SleepDetailModel`, `NightAutonomicShape` y `Baselines` se
// leen tal cual, y esta pantalla sigue siendo pura presentación (cero DB).
//
// Tres decisiones del dueño (2026-08-17) van dentro:
//   1. el héroe conserva LOS DOS datos (horas | regularidad) en UN solo campo;
//   2. «Forma de la noche» se abre a Apple (solo necesita la FC del reloj, que Apple sí entrega)
//      y «Reserva para bajar de marcha» (DC nocturna) se ELIMINA — con ella se van `loadNightRR`
//      y `loadDCBaseline`, que no tenían otro consumidor;
//   3. el orden es de tres actos: lo que dormiste → lo que hizo tu corazón → el tiempo.
//
// Se presenta como hoja (TodayView) o como capa (CuerpoView, `DetailChrome`), con el tema vivo
// explícito (FER-162 — hoy solo lo consume `SleepStagesInfoSheet`, que sigue en papel) y SIN
// `NavigationStack` anidado (FER-171).

/// Detalle de Sueño en vidrio Liquid. Se arma UNA vez desde un `SleepDetailModel` (el caller
/// inyecta el modelo para que la pantalla siga sin tocar la base de datos).
struct SleepDetailScreen: View {
    /// El tema vivo «Instrumento», pasado explícito (las hojas arrancan un environment nuevo).
    /// Solo lo usa la hoja de etapas, que no está en el alcance de esta migración. (FER-162)
    var theme: InstrumentoTheme = .base
    /// Todo lo que la pantalla dibuja, derivado UNA vez por el caller desde `repo`.
    let model: SleepDetailModel
    /// Carga la FC de la noche para una ventana `[from, to)` — inyectada por el caller (que es
    /// quien tiene `repo`). El bloque «Forma de la noche» (FER-832) necesita la FC cruda.
    var loadNightHR: (_ from: Int, _ to: Int) async -> [HRSample] = { _, _ in [] }

    /// FER-7 · Veredicto v4 Fase 4: los deltas persistidos (bpm) primer tercio − último tercio
    /// por noche, leídos de la partición que calcula Apple. Vacío ⇒ el módulo de tercios se oculta.
    var loadNightThirds: () async -> [(day: String, value: Double)] = { [] }

    /// La métrica cuya hoja de info está abierta (tocar una cajita de «Métricas de la noche»).
    @State private var metricInfo: MetricInfo?
    /// Si la tarjeta combinada «Etapas del sueño» está abierta (desde «Cómo se calcula»).
    @State private var showStages = false
    /// El ⓘ del campo abre la tarjeta «Qué medimos» bajo él.
    @State private var infoOpen = false
    /// La ventana del historial de duración. Por omisión, un mes.
    @State private var range: ExploreRange = .month
    /// Serie de duración con cada llave de día parseada UNA vez en el `.task`.
    @State private var durationParsed: [(day: String, date: Date?, value: Double)] = []
    /// La retícula de 90 noches, construida UNA vez en el `.task` (90 pasadas de `DateFormatter`)
    /// en vez de en cada evaluación del body — el recálculo daba jank al abrir. (FER-878+)
    @State private var sleepHeatCache: [RecoveryDay] = []
    /// La noche tocada en el calendario, por su llave de día. (FER-830)
    @State private var selectedNightID: String? = nil
    /// La forma de la caída nocturna de la FC — async; `nil` hasta cargar o si es ilegible. (FER-832)
    @State private var nightShape: NightAutonomicShape.Result? = nil
    /// Serie de FC decimada (ventana dormida) para la curva de la caída. (FER-832)
    @State private var nightShapeCurve: [Double] = []
    /// FER-7 · Fase 4: la lectura primer tercio vs último de anoche (nil ⇒ sección oculta).
    @State private var nightThirds: NightThirdsUI? = nil
    /// El carril del historial que el dedo explora; `nil` = ninguno (paridad `GraficaRangos`).
    @State private var bandaExplorada: Int? = nil

    /// El tono de la pantalla: el sueño es índigo en toda la app (paridad `LiquidMetricSheetView`).
    private static let tono = LiquidColor.indigo
    /// El tono de las lecturas del CORAZÓN dentro de esta pantalla (forma de la noche, tercios).
    private static let tonoCorazon = LiquidColor.rosa

    // MARK: - Body — tres actos (lo que dormiste → lo que hizo tu corazón → el tiempo)

    var body: some View {
        ScrollView {
            // FER-964: Lazy para que el swap del modelo (FER-953) solo arme las secciones visibles.
            LazyVStack(alignment: .leading, spacing: 0) {
                if let night = model.night {
                    campo(night)
                    if infoOpen { queMedimosCard }
                    seccion(String(localized: "Last night"), pista: ventanaNoche(night)) {
                        lastNightContent(night)
                    }
                    seccion(String(localized: "Last night vs your typical")) {
                        stagesVsTypicalContent(night)
                    }
                    seccion(String(localized: "Tonight's metrics")) {
                        nightMetricsContent(night)
                    }
                    if let shape = nightShape {
                        seccion(String(localized: "Night shape")) { nightShapeContent(shape, night) }
                    }
                    if let thirds = nightThirds {
                        seccion(String(localized: "First third vs last")) { nightThirdsContent(thirds) }
                    }
                    if let debt = model.weeklyDebtMinutes, debt >= 15, model.weeklyDebtNights.count >= 2 {
                        seccion(String(localized: "Weekly debt")) { weeklyDebtContent(debt) }
                    }
                    if durationParsed.count >= 2 {
                        seccion(String(localized: "History")) { trendContent }
                    }
                    if durationParsed.contains(where: { $0.value > 0 }) {
                        seccion(String(localized: "Calendar · 90 nights")) { calendarContent }
                    }
                    pieMetodo
                } else {
                    campoApagado
                    if !model.loaded {
                        LiquidSheetSkeleton(a11yCargando: String(localized: "Loading your sleep history…"))
                            .liquidSeccion()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // El fondo va en las DOS formas de presentación: `background` para la capa de Tendencias
        // (`DetailChrome`, que no es una hoja) y `presentationBackground` para la hoja de Hoy —
        // el mismo par que la pantalla de papel tenía con `theme.paper` + `.sheetPaper`.
        .background { LiquidSheetFondo(tone: Self.tono).ignoresSafeArea() }
        .presentationBackground { LiquidSheetFondo(tone: Self.tono) }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(LiquidRadius.hoja)
        // FER-953: corre cuando el modelo placeholder se cambia por el real; parseo + heat off-main.
        .task(id: model.loaded) {
            guard model.loaded else { return }   // pasada placeholder — nada que parsear (FER-953)
            range = .month
            let series = model.durationSeries
            let todayKey = Repository.localDayKey(Date())   // main-isolated: resolver antes del hop
            let (parsed, heat) = await Task.detached(priority: .userInitiated) {
                (series.map { ($0.day, Repository.parseDayKey($0.day), $0.value) },
                 Self.buildSleepHeat(durationSeries: series, todayKey: todayKey))
            }.value
            durationParsed = parsed
            sleepHeatCache = heat
        }
        .task(id: model.night?.startTs) {
            let (shape, curve) = await loadNightShape()
            nightShape = shape
            nightShapeCurve = curve
        }
        .task(id: model.night?.startTs) {
            nightThirds = await loadNightThirdsUI()
        }
        .sheet(item: $metricInfo) { info in
            // Cutover F6 (decisión D1 del revote): las submétricas de sueño abren la hoja Liquid.
            LiquidMetricSheetView(info: info, trendLoader: trendLoader(for: info.id))
        }
        .sheet(isPresented: $showStages) {
            SleepStagesInfoSheet(theme: theme)
        }
    }

    /// Una sección: la costura a sangre + su contenido con el margen del sistema.
    @ViewBuilder
    private func seccion<Content: View>(_ titulo: String, pista: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        LiquidFranjaSeccion(titulo, pista: pista, tono: Self.tono)
        content().liquidSeccion()
    }

    // MARK: - 1. El campo (héroe) — dos datos, un veredicto de dos niveles

    /// El campo teñido a sangre: par de numerales (horas | regularidad) + veredicto + cláusula,
    /// con el ⓘ en la cabecera y, al pie, el aviso de siestas y el sello de confianza.
    private func campo(_ night: SleepDetailModel.Night) -> some View {
        LiquidCampoMetrica(
            tono: Self.tono,
            titulo: String(localized: "Sleep"),
            glifo: .luna,
            datos: [
                .init(valor: hoursOnly(night.stages.asleep),
                      rotulo: String(localized: "hours"),
                      // «7:12» se dicta como hora del reloj («siete doce»); VoiceOver dice horas.
                      a11y: horasHabladas(night.stages.asleep)),
                // Sin base todavía, el numeral NO miente: «··» atenuado con su motivo, no un
                // número. El tipo `Dato` cuelga del genérico del campo, así que se nombra
                // SIEMPRE por `.init`/`.calibrando` — escribirlo completo rompe la inferencia.
                model.regularity.map {
                    .init(valor: "\($0.score)", unidad: "/100",
                          rotulo: String(localized: "regularity"))
                } ?? .calibrando(rotulo: String(localized: "regularity"),
                                 motivo: calibrandoMotivo),
            ],
            veredicto: heroVerdictTitle(night),
            clausula: heroVerdictClause(night),
            infoAbierto: infoOpen,
            infoEtiqueta: String(localized: "What we measure"),
            onInfo: { withAnimation(LiquidMotion.lift) { infoOpen.toggle() } }
        ) {
            pieCampo
        }
    }

    /// El pie del campo: el aviso de siestas (prosa) y el sello de confianza, que es justo lo
    /// que la ranura libre existe para cargar.
    @ViewBuilder private var pieCampo: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            if model.excludedNapCount > 0 {
                Text(napNotice)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.papelAlto.opacity(LiquidCampo.alfaRotulo))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let tier = model.confidence {
                Text(tier.confidenceLabelText)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.papelAlto.opacity(LiquidCampo.alfaRotulo))
                    .padding(.horizontal, LiquidSpace.s250)
                    .padding(.vertical, LiquidSpace.s075)
                    .overlay(
                        Capsule().strokeBorder(
                            LiquidColor.papelAlto.opacity(LiquidCampo.alfaSeparador),
                            lineWidth: 1)
                    )
                    .accessibilityLabel(Text(tier.confidenceA11y))
            }
        }
    }

    /// Por qué la regularidad todavía no tiene número (la MISMA frase que la cláusula del campo).
    private var calibrandoMotivo: String {
        let missing = max(0, SleepRegularity.minNights - model.regularityNights)
        return String(localized: "Still learning your schedule · \(missing) nights to go")
    }

    /// La tarjeta del ⓘ bajo el campo: qué mide el puntaje, en lenguaje llano.
    private var queMedimosCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text("What we measure")
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            Text(heroExplanation)
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
        .liquidGlass(.superficieSolida)
        .liquidSeccion(top: LiquidSpace.s400, bottom: LiquidSpace.s200)
    }

    /// El campo APAGADO: sin noche (vacío o cargando) el numeral es un guion, nunca un cero.
    private var campoApagado: some View {
        LiquidCampoMetrica(
            tono: Self.tono,
            titulo: String(localized: "Sleep"),
            glifo: .luna,
            datos: [.init(valor: LiquidCajita.sinDato,
                          rotulo: String(localized: "hours"),
                          a11y: String(localized: "no data"),
                          ausente: true)],
            clausula: model.loaded
                ? String(localized: "No nights yet. Connect Apple Health in Data Sources to see your sleep stages and trends.")
                : String(localized: "Loading your sleep history…"))
    }

    /// Copy del ⓘ: regularidad = movimiento del punto medio; las siestas no cuentan; «necesidad» = 7–9 h.
    private var heroExplanation: LocalizedStringKey {
        "Regularity is how much your mid-sleep point moves night to night (the midpoint between falling asleep and waking): it predicts your health better than total hours. Naps don't count. \"Need\" is the 7–9 h target, not a measurement of you."
    }

    /// Veredicto de dos niveles (suficiencia + horario), con las mismas palabras del modelo.
    private func heroVerdictTitle(_ night: SleepDetailModel.Night) -> String {
        let perf = model.performancePct.map { Int(min(100, $0).rounded()) }
        let suff = sufficiencyWord(perf)
        if let r = model.regularity {
            return String(localized: "\(suff) and \(scheduleWord(r.score))")
        }
        return suff
    }

    /// La segunda cláusula, quieta (necesidad % + palabra de regularidad, o la nota de calibración).
    private func heroVerdictClause(_ night: SleepDetailModel.Night) -> String {
        let perf = model.performancePct.map { Int(min(100, $0).rounded()) }
        if let r = model.regularity, let p = perf {
            return String(localized: "\(p)% of your need, \(regularityWordText(r.score)) rhythm")
        }
        if let r = model.regularity {
            return String(localized: "\(regularityWordText(r.score)) rhythm")
        }
        if let p = perf {
            return String(localized: "\(p)% of your need")
        }
        if model.regularity == nil {
            let missing = max(0, SleepRegularity.minNights - model.regularityNights)
            return String(localized: "Still learning your schedule · \(missing) nights to go")
        }
        return String(localized: "Last night, logged.")
    }

    private func sufficiencyWord(_ perf: Int?) -> String {
        guard let p = perf else { return String(localized: "Logged") }
        if p >= 90 { return String(localized: "Enough") }
        if p >= 75 { return String(localized: "Almost enough") }
        return String(localized: "Short on sleep")
    }

    private func scheduleWord(_ score: Int) -> String {
        switch score {
        case 80...:   return String(localized: "right on schedule")
        case 55..<80: return String(localized: "fairly on schedule")
        default:      return String(localized: "on a shifting schedule")
        }
    }

    private func regularityWordText(_ score: Int) -> String {
        switch score {
        case 80...:   return String(localized: "very regular")
        case 55..<80: return String(localized: "regular")
        default:      return String(localized: "variable")
        }
    }

    // MARK: - 2. Anoche — el hipnograma (firma de la pantalla) + su lectura

    /// La ventana de la noche («23:38 → 7:04»), solo cuando hay reloj de verdad: el fallback
    /// diario de Apple fabrica noches con `startTs == endTs` y ahí no se afirma horario. (FER-1026)
    private func ventanaNoche(_ night: SleepDetailModel.Night) -> String? {
        guard night.endTs > night.startTs else { return nil }
        let inicio = Self.clockFmt.string(from: night.onsetDate)
        let fin = Self.clockFmt.string(from: Date(timeIntervalSince1970: TimeInterval(night.endTs)))
        return "\(inicio) → \(fin)"
    }

    @ViewBuilder
    private func lastNightContent(_ night: SleepDetailModel.Night) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            if model.intervals.count >= 2 {
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
                    LiquidNotaLine(nightTitle, tono: LiquidColor.tinta700)
                    Spacer(minLength: 0)
                    LiquidNotaLine(awakeText(night))
                }
                hipnograma(night)
            } else {
                // Sin tarjeta: el dueño pidió que las secciones sean planas y llenen el ancho
                // («nada flotando»). Y sin `ventana:` — la franja de la sección ya lleva el
                // reloj como pista, y repetirlo dentro leía como dos encabezados.
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
                    LiquidNotaLine(nightTitle, tono: LiquidColor.tinta700)
                    Spacer(minLength: 0)
                    LiquidNotaLine(awakeText(night))
                }
                LiquidStageBar(etapas: sleepEtapas(night), overline: "", ventana: nil)
                if model.isAppleHealth {
                    LiquidOrigenChip(glyph: .luna, badgeTono: Self.tono,
                                     etiqueta: String(localized: "Apple Health"))
                }
            }
        }
    }

    /// «Anoche · N ciclos» (o solo «Anoche» sin conteo de REM).
    private var nightTitle: String {
        remBoutCount.flatMap { $0 > 0 ? $0 : nil }
            .map { String(localized: "Night · \($0) cycles") } ?? String(localized: "Night")
    }

    private func awakeText(_ night: SleepDetailModel.Night) -> String {
        String(localized: "\(pct(night.stages.awake, night.stages.total))% awake")
    }

    /// El hipnograma Liquid, con su scrub (etapa · rango horario · duración) y su eje de 5 horas.
    private func hipnograma(_ night: SleepDetailModel.Night) -> some View {
        let intervalos = model.intervals.map { iv in
            LiquidHipnograma.Intervalo(inicio: night.onsetDate.addingTimeInterval(iv.start),
                                       fin: night.onsetDate.addingTimeInterval(iv.end),
                                       etapa: Self.etapaLiquid(iv.stage))
        }
        return LiquidHipnograma(
            intervalos: intervalos,
            colores: Self.coloresEtapa,
            etiquetas: Self.etiquetasEtapa,
            ejeInicio: Self.clockFmt.string(from: night.onsetDate),
            ejeFin: Self.clockFmt.string(from: Date(timeIntervalSince1970: TimeInterval(night.endTs))),
            horasEje: Self.horasEje(intervalos),
            textoTramo: { tramo in
                (valor: Self.etiquetasEtapa[tramo.etapa] ?? "",
                 detalle: Self.rangoTramo(tramo))
            },
            a11yLabel: nightTitle,
            a11yValue: stagesA11y(night.stages))
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
        .liquidGlass(.superficieSolida)
    }

    /// Las CINCO horas del eje del hipnograma, repartidas por el span real de la noche.
    private static func horasEje(_ intervalos: [LiquidHipnograma.Intervalo]) -> [String]? {
        // El MISMO criterio que el componente usa por dentro (`visibles` + `ventana`), que es
        // interno al paquete: un tramo de 0 min no existe, y el span va del primer inicio al
        // último fin. Si las dos vistas discreparan, el eje rotularía horas que no son.
        let visibles = intervalos.filter { $0.duracion > 0 }.sorted { $0.inicio < $1.inicio }
        guard let primero = visibles.first else { return nil }
        let ultimo = visibles.map(\.fin).max() ?? primero.fin
        let span = Swift.max(1, ultimo.timeIntervalSince(primero.inicio))
        return (0..<5).map { i in
            clockFmt.string(from: primero.inicio.addingTimeInterval(span * Double(i) / 4))
        }
    }

    /// «23:42 – 0:04 · 22 min» — el detalle del tramo bajo el dedo (el papel lo decía igual).
    private static func rangoTramo(_ tramo: LiquidHipnograma.Intervalo) -> String {
        let minutos = Int((tramo.duracion / 60).rounded())
        return "\(clockFmt.string(from: tramo.inicio)) – \(clockFmt.string(from: tramo.fin)) · \(minutos) min"
    }

    /// Lo que VoiceOver dice de la noche: el reparto por etapa en porcentaje (clave existente).
    private func stagesA11y(_ s: SleepDetailModel.Stages) -> String {
        String(localized: "Sleep stages: deep \(pct(s.deep, s.total)) percent, light \(pct(s.light, s.total)) percent, REM \(pct(s.rem, s.total)) percent, awake \(pct(s.awake, s.total)) percent")
    }

    /// La rampa Liquid de etapas: índigo graduado por opacidad para lo dormido y ORO para
    /// despierto (decisión del dueño /inject). Copiada de `LiquidMetricSheetView.sleepEtapas`
    /// para que la hoja de Hoy y este detalle pinten la MISMA noche con los mismos tonos.
    private static let coloresEtapa: [LiquidHipnograma.Etapa: Color] = [
        .profundo: LiquidColor.indigo,
        .rem: LiquidColor.indigo.opacity(0.78),    // token-exempt: rampa graduada de etapas
        .ligero: LiquidColor.indigo.opacity(0.52), // token-exempt: rampa graduada de etapas
        .despierto: LiquidColor.oro,
    ]

    private static var etiquetasEtapa: [LiquidHipnograma.Etapa: String] {
        [.despierto: String(localized: "Awake"),
         .rem: String(localized: "REM"),
         .ligero: String(localized: "Light"),
         .profundo: String(localized: "Deep")]
    }

    private static func etapaLiquid(_ stage: SleepStage) -> LiquidHipnograma.Etapa {
        switch stage {
        case .deep:  return .profundo
        case .rem:   return .rem
        case .light: return .ligero
        case .awake: return .despierto
        }
    }

    /// Las cuatro etapas para la barra de fallback (sin línea de tiempo por época).
    private func sleepEtapas(_ night: SleepDetailModel.Night) -> [LiquidStageBar.Etapa] {
        let s = night.stages
        return [
            .init(minutos: s.deep, color: Self.coloresEtapa[.profundo] ?? Self.tono,
                  etiqueta: String(localized: "Deep"), duracion: hoursOnly(s.deep)),
            .init(minutos: s.rem, color: Self.coloresEtapa[.rem] ?? Self.tono,
                  etiqueta: String(localized: "REM"), duracion: hoursOnly(s.rem)),
            .init(minutos: s.light, color: Self.coloresEtapa[.ligero] ?? Self.tono,
                  etiqueta: String(localized: "Light"), duracion: hoursOnly(s.light)),
            .init(minutos: s.awake, color: Self.coloresEtapa[.despierto] ?? LiquidColor.oro,
                  etiqueta: String(localized: "Awake"), duracion: hoursOnly(s.awake)),
        ]
    }

    /// El reloj de pared de la noche. Plantilla «Hmm», la MISMA que usa la hoja de resumen
    /// (`LiquidMetricSheetView.clockFmt`): con `timeStyle = .short` el detalle imprimía
    /// «10:48 p.m. → 6:36 a.m.» mientras la hoja, un toque antes, decía «22:48 → 6:36». La
    /// misma noche en dos formatos a un tap de distancia se lee como dos apps.
    /// (Por plantilla, nunca con `dateFormat`: regla de la casa.)
    private static let clockFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("Hmm"); return f
    }()

    /// Cuenta los tramos REM contiguos a partir de los intervalos (solo presentación).
    private var remBoutCount: Int? {
        guard !model.intervals.isEmpty else { return nil }
        var n = 0
        var inRem = false
        for iv in model.intervals.sorted(by: { $0.start < $1.start }) {
            if iv.stage == .rem {
                if !inRem { n += 1; inRem = true }
            } else {
                inRem = false
            }
        }
        return n
    }

    // MARK: - 3. Anoche vs lo típico — barras con marca de promedio

    private func stagesVsTypicalContent(_ night: SleepDetailModel.Night) -> some View {
        let s = night.stages
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            vsTypicalVerdictText(s)
                .fixedSize(horizontal: false, vertical: true)
            stageVsTypicalRow(String(localized: "Deep"), lastMin: s.deep, total: s.total,
                              typicalPct: model.typicalDeepPct,
                              color: Self.coloresEtapa[.profundo] ?? Self.tono,
                              higherIsBetter: true, index: 0)
            stageVsTypicalRow(String(localized: "REM"), lastMin: s.rem, total: s.total,
                              typicalPct: model.typicalRemPct,
                              color: Self.coloresEtapa[.rem] ?? Self.tono,
                              higherIsBetter: true, index: 1)
            stageVsTypicalRow(String(localized: "Light"), lastMin: s.light, total: s.total,
                              typicalPct: model.typicalLightPct,
                              color: Self.coloresEtapa[.ligero] ?? Self.tono,
                              higherIsBetter: false, index: 2)
            LiquidNotaLine(String(localized: "The mark is your average."))
        }
    }

    /// El nombre de la etapa TEÑIDO dentro de la frase; el resto en tinta. Mismas cinco frases
    /// localizadas de siempre (sin claves nuevas).
    private func vsTypicalVerdictText(_ s: SleepDetailModel.Stages) -> Text {
        let font = LiquidType.titulo
        let deep = stageShareAbove(s.deep, s.total, model.typicalDeepPct)
        let rem = stageShareAbove(s.rem, s.total, model.typicalRemPct)
        let full: String
        let stageNames: [String]
        if deep && rem {
            full = String(localized: "Deep and REM above your typical")
            stageNames = [String(localized: "Deep"), String(localized: "REM")]
        } else if deep {
            full = String(localized: "Deep above your typical")
            stageNames = [String(localized: "Deep")]
        } else if rem {
            full = String(localized: "REM above your typical")
            stageNames = [String(localized: "REM")]
        } else if let light = model.typicalLightPct {
            let last = s.total > 0 ? s.light / s.total * 100 : 0
            if last > light + 1 {
                full = String(localized: "More light sleep than your typical")
                // La frase fuente en EN dice "light sleep"; es-MX dice «sueño ligero».
                let candidates = ["light sleep", "sueño ligero"]
                stageNames = candidates.filter { full.range(of: $0, options: .caseInsensitive) != nil }
            } else {
                full = String(localized: "Close to your typical stage mix")
                stageNames = []
            }
        } else {
            full = String(localized: "Close to your typical stage mix")
            stageNames = []
        }
        return coloredStageVerdict(full: full, stageNames: stageNames, font: font)
    }

    /// Recorre `full` y pinta cada aparición del nombre de una etapa en el tono de la pantalla.
    private func coloredStageVerdict(full: String, stageNames: [String], font: Font) -> Text {
        guard !stageNames.isEmpty else {
            return Text(verbatim: full)
                .font(font)
                .foregroundColor(LiquidColor.tinta900)
        }
        // Coincidencias sin traslape, de izquierda a derecha.
        var matches: [(range: Range<String.Index>, name: String)] = []
        for name in stageNames {
            var searchFrom = full.startIndex
            while searchFrom < full.endIndex,
                  let r = full.range(of: name, options: .caseInsensitive, range: searchFrom..<full.endIndex) {
                let overlaps = matches.contains { $0.range.overlaps(r) }
                if !overlaps { matches.append((r, name)) }
                searchFrom = r.upperBound
            }
        }
        matches.sort { $0.range.lowerBound < $1.range.lowerBound }
        guard !matches.isEmpty else {
            return Text(verbatim: full)
                .font(font)
                .foregroundColor(LiquidColor.tinta900)
        }
        var result: Text?
        var cursor = full.startIndex
        for m in matches {
            if cursor < m.range.lowerBound {
                let plain = String(full[cursor..<m.range.lowerBound])
                let t = Text(verbatim: plain).font(font).foregroundColor(LiquidColor.tinta900)
                result = result.map { $0 + t } ?? t
            }
            let stage = String(full[m.range])
            let t = Text(verbatim: stage).font(font).foregroundColor(Self.tono)
            result = result.map { $0 + t } ?? t
            cursor = m.range.upperBound
        }
        if cursor < full.endIndex {
            let plain = String(full[cursor...])
            let t = Text(verbatim: plain).font(font).foregroundColor(LiquidColor.tinta900)
            result = result.map { $0 + t } ?? t
        }
        return result ?? Text(verbatim: full).font(font).foregroundColor(LiquidColor.tinta900)
    }

    private func stageShareAbove(_ min: Double, _ total: Double, _ typical: Double?) -> Bool {
        guard let typical, total > 0 else { return false }
        return (min / total * 100) > typical + 0.5
    }

    /// Una fila del bloque, ya como pieza del sistema: el relleno mide anoche y el tick de tinta
    /// marca tu promedio. El delta (y su color) los calcula el componente.
    private func stageVsTypicalRow(_ label: String, lastMin: Double, total: Double,
                                   typicalPct: Double?, color: Color,
                                   higherIsBetter: Bool, index: Int) -> some View {
        let lastPct = total > 0 ? lastMin / total * 100 : 0
        // Las MISMAS dos claves del papel («…, 22% last night» + «, typical 18%»), unidas igual:
        // sin base, la voz NO menciona promedio (regla 2 de `LiquidBarraMarca`).
        let voz = String(localized: "\(label), \(Int(lastPct.rounded()))% last night")
            + (typicalPct.map { String(localized: ", typical \(Int($0.rounded()))%") } ?? "")
        return LiquidBarraMarca(
            etiqueta: label,
            fraccion: total > 0 ? lastPct / 100 : nil,
            marca: typicalPct.map { $0 / 100 },
            tono: color,
            valorTexto: "\(Int(lastPct.rounded()))%",
            masEsMejor: higherIsBetter,
            indice: index,
            a11yLabel: label,
            a11yValue: voz)
    }

    // MARK: - 4. Métricas de la noche — seis cajitas tocables

    private func nightMetricsContent(_ night: SleepDetailModel.Night) -> some View {
        LiquidCajitaGrid {
            cajitaMetrica(rotulo: String(localized: "Performance"),
                          valor: model.performancePct.map { "\(Int(min(100, $0).rounded()))" },
                          unidad: "%",
                          pie: performanceCaptionString,
                          info: .sleepPerformance(model.performancePct))
            cajitaMetrica(rotulo: String(localized: "Efficiency"),
                          valor: efficiencyPct(night).map { "\(Int($0.rounded()))" },
                          unidad: "%",
                          pie: String(localized: "vs time in bed"),
                          info: .sleepEfficiency(efficiencyPct(night)))
            cajitaMetrica(rotulo: String(localized: "Restorative"),
                          valor: restorativePct(night.stages).map { "\(Int($0.rounded()))" },
                          unidad: "%",
                          pie: String(localized: "Deep + REM"),
                          info: .sleepRestorative(restorativePct(night.stages)))
            // `latencyMin` es hoy SIEMPRE nil (el caché no trae latencia de conciliación): el pie
            // lo dice en vez de prometer un rango sano que nunca se va a poder contrastar.
            cajitaMetrica(rotulo: String(localized: "Latency"),
                          valor: model.latencyMin.map { "\(Int($0.rounded()))" },
                          unidad: String(localized: "min"),
                          pie: model.latencyMin == nil
                              ? String(localized: "No data in Apple Health")
                              : String(localized: "10–20 healthy"),
                          info: .sleepLatency(model.latencyMin))
            cajitaMetrica(rotulo: String(localized: "Respiration"),
                          valor: night.respRate.map { String(format: "%.1f", $0) },
                          pie: String(localized: "rpm"),
                          tono: LiquidColor.azul,
                          info: .respiratory(night.respRate))
            cajitaMetrica(rotulo: String(localized: "Awakenings"),
                          valor: model.awakenings.map { "\($0)" },
                          pie: String(localized: "times"),
                          info: .sleepAwakenings(model.awakenings))
        }
    }

    /// Una cajita que abre su hoja de info. `valor == nil` ⇒ «—» (y sin unidad: un guion no
    /// lleva unidades).
    private func cajitaMetrica(rotulo: String, valor: String?, unidad: String = "",
                               pie: String?, tono: Color? = nil,
                               info: MetricInfo) -> some View {
        LiquidCajita(rotulo: rotulo,
                     valor: valor ?? LiquidCajita.sinDato,
                     unidad: valor == nil ? "" : unidad,
                     pie: pie,
                     tono: valor == nil ? nil : tono,
                     action: { metricInfo = info })
            .accessibilityHint(Text("Shows what this means"))
    }

    private var performanceCaptionString: String? {
        guard let missing = model.shortfallMinutes, missing >= 5 else {
            return String(localized: "vs your need")
        }
        return String(localized: "−\(hoursMinutes(missing)) vs your need")
    }

    private func trendLoader(for id: String) -> (() async -> [TrendPoint])? {
        let pts: [TrendPoint]
        switch id {
        case "sleep_performance": pts = model.performanceTrend
        case "sleep_efficiency":  pts = model.efficiencyTrend
        case "sleep_restorative": pts = model.restorativeTrend
        case "resp_rate":         pts = model.respirationTrend
        case "sleep_awakenings":  pts = model.awakeningsTrend
        default:                  return nil
        }
        return { pts }
    }

    // MARK: - 5. Forma de la noche (FER-832) — ahora también para Apple

    @ViewBuilder
    private func nightShapeContent(_ shape: NightAutonomicShape.Result,
                                   _ night: SleepDetailModel.Night) -> some View {
        if shape.confidence == .unreadable {
            LiquidNotaLine(String(localized: "There isn't enough signal tonight to read how your heart eased off."))
        } else {
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                LiquidFraseNivel(nivel: "−\(Int(shape.dipPct.rounded()))%",
                                 conteo: String(localized: "your pulse dropped as you fell asleep"),
                                 tono: Self.tonoCorazon)
                if nightShapeCurve.count >= 2 { curvaNoche(night) }
                LiquidCajitaGrid {
                    LiquidCajita(rotulo: String(localized: "lowest point"),
                                 valor: clockLabel(shape.nadirHour))
                    if model.rhrBaseline != nil {
                        LiquidCajita(rotulo: String(localized: "below your resting"),
                                     valor: "\(Int((shape.fractionBelowRHR * 100).rounded()))",
                                     unidad: "%",
                                     pie: String(localized: "of the night"))
                    }
                }
                LiquidNotaLine(String(localized: String.LocalizationValue(dipCopyKey(shape.dipShape))))
            }
        }
    }

    /// La curva de la caída, en la gramática de las gráficas Liquid: línea sin relleno, con
    /// scrub. El eje X se calla a propósito — la serie está decimada por MUESTRAS, no por reloj,
    /// así que afirmar una hora bajo cada punto sería inventar precisión que el motor no dio.
    private func curvaNoche(_ night: SleepDetailModel.Night) -> some View {
        let n = nightShapeCurve.count
        let inicio = night.onsetDate
        let span = Swift.max(1, Double(night.endTs - night.startTs))
        let puntos: [(fecha: Date, valor: Double)] = nightShapeCurve.enumerated().map { i, v in
            (fecha: inicio.addingTimeInterval(span * (Double(i) + 0.5) / Double(n)), valor: v)
        }
        let lo = nightShapeCurve.min() ?? 0
        let hi = nightShapeCurve.max() ?? 1
        let aire = Swift.max(1, (hi - lo) * 0.12)
        let bpm: (Double) -> String = { "\(Int($0.rounded())) \(String(localized: "bpm"))" }
        return LiquidGraficaNiveles(
            puntos: puntos,
            bandas: [],
            dominio: (lo - aire)...(hi + aire),
            ticksY: [],
            tono: Self.tonoCorazon,
            formatoScrub: { v, _ in bpm(v) },
            formatoValorScrub: bpm,
            estadoVacio: String(localized: "There isn't enough signal tonight to read how your heart eased off."),
            a11yLabel: String(localized: "Night shape"))
    }

    private func dipCopyKey(_ shape: NightAutonomicShape.DipShape) -> String {
        switch shape {
        case .pronounced:
            return "A marked, early drop: a sign you settled into rest. It's a pattern, not a diagnosis."
        case .moderate:
            return "A moderate drop overnight. It's a pattern, not a diagnosis."
        case .blunted:
            return "A gentler drop than a deep-rest night usually shows. It's a pattern, not a diagnosis."
        }
    }

    // MARK: - 6. Primer tercio vs último (FER-7 · Fase 4) — descriptivo, jamás un voto

    /// Cómo se compara el ascenso primer tercio→último tercio de anoche contra tu propio normal.
    enum ThirdsTone: Equatable { case calibrating(Int), usual, higher, lower }
    struct NightThirdsUI: Equatable { let deltaBpm: Double; let tone: ThirdsTone }

    private func nightThirdsContent(_ r: NightThirdsUI) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidFraseNivel(nivel: signedBpm(r.deltaBpm),
                             conteo: String(localized: "from the first third of the night to the last"),
                             tono: Self.tonoCorazon)
            LiquidNotaLine(String(localized: String.LocalizationValue(thirdsCopyKey(r.tone))))
        }
    }

    /// «+12 bpm» / «−3 bpm» / «0 bpm» — con signo, menos U+2212, unidad localizada.
    private func signedBpm(_ d: Double) -> String {
        let n = Int(d.rounded())
        let sign = n > 0 ? "+" : (n < 0 ? "\u{2212}" : "")
        return "\(sign)\(abs(n)) \(String(localized: "bpm"))"
    }

    private func thirdsCopyKey(_ tone: ThirdsTone) -> String {
        switch tone {
        case .calibrating:
            return "Getting to know your nights: a few more and we'll compare this to your usual."
        case .higher:
            return "Higher than your usual overnight rise: last night's start may have run hot (a workout, a late meal, a drink). It's a pattern, not a diagnosis."
        case .usual:
            return "About your usual overnight rise. It's a pattern, not a diagnosis."
        case .lower:
            return "A gentler overnight rise than your usual. It's a pattern, not a diagnosis."
        }
    }

    /// Lee los deltas persistidos, toma el de ESTA noche y lo puntúa contra tu normal (solo
    /// noches PASADAS, para que anoche no se compare consigo misma). `nil` ⇒ oculta.
    private func loadNightThirdsUI() async -> NightThirdsUI? {
        guard let night = model.night else { return nil }
        let series = await loadNightThirds()
        guard !series.isEmpty else { return nil }
        let nightDay = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(night.endTs)))
        guard let tonight = series.first(where: { $0.day == nightDay })?.value else { return nil }
        let cfg = Baselines.metricCfg["night_thirds_delta"]!
        let past: [Double?] = series.filter { $0.day < nightDay }.sorted { $0.day < $1.day }.map { $0.value }
        let state = Baselines.rollingMeanSD(past, cfg: cfg, window: 30)
        let tone: ThirdsTone
        if !state.trusted {
            tone = .calibrating(max(0, Baselines.minNightsTrust - state.nValid))
        } else {
            let dev = Baselines.deviation(tonight, state: state)
            tone = dev.inNormalRange ? .usual : (dev.z > 0 ? .higher : .lower)
        }
        return NightThirdsUI(deltaBpm: tonight, tone: tone)
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private func clockLabel(_ hour: Double) -> String {
        var h = Int(hour) % 24
        var m = Int(((hour - Double(Int(hour))) * 60).rounded())
        if m == 60 { m = 0; h = (h + 1) % 24 }
        var comps = DateComponents(); comps.hour = h; comps.minute = m
        let cal = Calendar.current
        if let date = cal.date(from: comps) {
            return Self.clockFormatter.string(from: date)
        }
        return String(format: "%d:%02d", h, m)
    }

    // MARK: - 7. Deuda de la semana

    private func weeklyDebtContent(_ debt: Double) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidFraseNivel(nivel: hoursMinutes(debt),
                             conteo: String(localized: "behind this week"),
                             tono: LiquidColor.atencionTexto)
            weeklyDebtBars(debt)
            LiquidNotaLine(
                String(localized: "What you missed versus what your body needs. One good night won't clear it."))
        }
    }

    private func weeklyDebtBars(_ debt: Double) -> some View {
        let nights = model.weeklyDebtNights
        let ultima = nights.count - 1
        let dias: [LiquidBarrasDeuda.Dia] = nights.enumerated().map { i, n in
            .init(id: "\(Int(n.date.timeIntervalSince1970))",
                  etiqueta: Self.weekdayNarrow(n.date),
                  minutos: n.vsNeedMin,
                  esHoy: i == ultima,
                  detalle: String(localized: "slept \(hoursMinutes(n.sleptMin))"))
        }
        // El tope lo manda el caller para que la escala sea estable entre semanas: el mayor
        // desvío de ESTA semana, con un piso de una hora para que un desvío chico no se infle.
        let maximo = Swift.max(60, nights.map { abs($0.vsNeedMin) }.max() ?? 60)
        return LiquidBarrasDeuda(
            dias: dias,
            tono: LiquidColor.atencion,
            maximo: maximo,
            a11yLabel: String(localized: "Hours above or below your sleep need, each of the last 7 nights"),
            a11yValue: "\(hoursMinutes(debt)) \(String(localized: "behind this week"))",
            formatoValor: { m in m < 0 ? "−\(hoursMinutes(-m))" : "+\(hoursMinutes(m))" })
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()
    private static func weekdayNarrow(_ date: Date) -> String { weekdayFormatter.string(from: date) }

    // MARK: - 8. Historial — selector + gráfica de niveles + cajitas + carriles

    private var trendContent: some View {
        let window = MetricWindowMath.make(durationParsed, selected: range)
        let stat = ComparisonEngine.stat(window.values)
        let pctChange = range.periodComparison(of: model.durationSeries)?.pctChange
        let lastNightHrs = model.night.map { $0.stages.asleep / 60.0 }
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                seleccion: rangeSeleccion,
                                tono: Self.tono)
            if window.values.count >= 2 {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    LiquidFraseNivel(nivel: String(format: "%.1f h", stat.mean),
                                     conteo: String(localized: "average of the \(range.name)"),
                                     tono: Self.tono)
                    if let pctChange {
                        LiquidNotaLine(pctChange >= 0 ? "+\(Int(pctChange.rounded()))%"
                                                      : "\(Int(pctChange.rounded()))%",
                                       tono: pctChange >= 0 ? LiquidColor.positivo
                                                            : LiquidColor.atencionTexto)
                    }
                    graficaHistorial(window)
                }
                .padding(LiquidSpace.s400)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
                .liquidGlass(.superficieSolida)
                LiquidCajitaGrid(columnas: 3) {
                    LiquidCajita(rotulo: String(localized: "Average"),
                                 valor: String(format: "%.1f h", stat.mean), compacto: true)
                    LiquidCajita(rotulo: String(localized: "Range"),
                                 valor: String(format: "%.1f–%.1f", stat.min, stat.max),
                                 compacto: true)
                    LiquidCajita(rotulo: String(localized: "Last night"),
                                 valor: lastNightHrs.map { hoursOnly($0 * 60) } ?? LiquidCajita.sinDato,
                                 tono: lastNightHrs != nil ? Self.tono : nil,
                                 compacto: true,
                                 a11yValor: lastNightHrs.map { horasHabladas($0 * 60) })
                }
                LiquidLevelsList(filas: carrilesHistorial(window), tono: Self.tono)
                LiquidNotaLine(String(localized: "Hours asleep per night. The wash is the optimal 7–9 h band."))
                LiquidNotaLine(String(localized: "How many nights of the period fell in each band. Tap one to see its nights on the chart."))
            } else {
                LiquidGraficaNiveles(
                    puntos: [], bandas: [], dominio: Self.dominioSueno, ticksY: [],
                    tono: Self.tono,
                    estadoVacio: String(localized: "Not enough nights yet to draw a trend."),
                    a11yLabel: String(localized: "History"))
            }
        }
    }

    /// El índice del selector ⇄ `ExploreRange`; cambiar de rango suelta el carril explorado.
    private var rangeSeleccion: Binding<Int> {
        Binding(
            get: { ExploreRange.allCases.firstIndex(of: range) ?? 0 },
            set: { idx in
                range = ExploreRange.allCases[idx]
                bandaExplorada = nil
            })
    }

    private func graficaHistorial(_ window: MetricWindow) -> some View {
        let puntos = MetricWindowMath
            .decimatedPoints(rows: window.rows, values: window.values, maxPoints: 80)
            .map { (fecha: $0.date, valor: $0.value) }
        let horas: (Double) -> String = { String(format: "%.1f h", $0) }
        return LiquidGraficaNiveles(
            puntos: puntos,
            bandas: Self.bandasSueno.enumerated().map { i, b in
                LiquidChartBanda(lo: b.lo, hi: b.hi, color: b.color, activa: i == bandaExplorada)
            },
            dominio: Self.dominioSueno,
            ticksY: [(10, "10"), (9, "9"), (7, "7"), (5, "5")],
            tono: Self.tono,
            formatoScrub: { v, f in "\(horas(v)) · \(Self.ejeFechaFmt.string(from: f))" },
            formatoValorScrub: horas,
            formatoFechaScrub: { Self.ejeFechaFmt.string(from: $0) },
            formatoFechaEje: { Self.ejeFechaFmt.string(from: $0) },
            // Los puntos se apagan SOLO cuando el usuario explora un carril (paridad `GraficaRangos`).
            atenuarFuera: bandaExplorada != nil,
            estadoVacio: String(localized: "Not enough nights yet to draw a trend."),
            a11yLabel: String(localized: "History"))
    }

    /// Los tres carriles tocables bajo la gráfica: tocar uno resalta sus noches; re-tocarlo limpia.
    private func carrilesHistorial(_ window: MetricWindow) -> [LiquidLevelsList.Fila] {
        let hint = String(localized: "Highlights this level on the chart")
        return Self.bandasSueno.indices.map { i in
            let b = Self.bandasSueno[i]
            let n = window.values.filter { v in
                (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!)
            }.count
            return LiquidLevelsList.Fila(
                etiqueta: b.label,
                rango: b.range,
                conteo: n == 1 ? String(localized: "\(n) night") : String(localized: "\(n) nights"),
                activa: i == bandaExplorada,
                a11yHint: hint,
                onTap: {
                    withAnimation(LiquidMotion.lift) {
                        bandaExplorada = (bandaExplorada == i) ? nil : i
                    }
                })
        }
    }

    /// Un carril de duración: los MISMOS cortes de siempre (≥7 · 6.3–7 · <6.3).
    struct BandaSueno {
        let label: String
        let lo: Double?
        let hi: Double?
        let color: Color
        let range: String
    }

    /// Los tres carriles de duración. El corte bajo es 6.3 h, el mismo que usa el calendario
    /// desde esta migración (antes el calendario cortaba en 6 y las dos piezas discrepaban).
    static var bandasSueno: [BandaSueno] {
        [
            .init(label: String(localized: "Enough sleep"), lo: 7, hi: nil,
                  color: LiquidColor.indigo, range: "≥ 7"),
            .init(label: String(localized: "A bit short"), lo: 6.3, hi: 7,
                  color: LiquidColor.indigo.opacity(0.52),  // token-exempt: rampa graduada de sueño
                  range: "6.3–7"),
            .init(label: String(localized: "Short sleep"), lo: nil, hi: 6.3,
                  color: LiquidColor.atencion, range: "< 6.3"),
        ]
    }

    /// El dominio Y del historial: 5–10 h, como el papel.
    private static let dominioSueno: ClosedRange<Double> = 5...10

    private static let ejeFechaFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }()

    // MARK: - 9. Calendario · 90 noches

    private var calendarContent: some View {
        LiquidCalendario90(
            dias: calendarioDias,
            tono: Self.tono,
            leyenda: Self.leyendaCalendario,
            seleccion: $selectedNightID,
            a11yLabel: String(localized: "Calendar · 90 nights"),
            pistaVacia: String(localized: "Tap a night to see its sleep."),
            sinLectura: String(localized: "no data"),
            a11yConteo: { conDato, total in
                String(localized: "\(conDato) of your last \(total) nights")
            })
    }

    /// Las 90 noches, ya resueltas: la retícula Liquid no formatea ni una fecha.
    private var calendarioDias: [LiquidCalendario90.Dia] {
        var mesVisto: String? = nil
        return sleepHeatCache.map { dia -> LiquidCalendario90.Dia in
            let key = Self.calDayFmt.string(from: dia.date)
            let mes = Self.mesFmt.string(from: dia.date)
            let rotuloMes: String? = mes == mesVisto ? nil : mes
            mesVisto = mes
            let horas = dia.score.map { $0 / 60 }
            return LiquidCalendario90.Dia(
                id: key,
                fecha: dia.date,
                intensidad: horas.map(Self.intensidadSueno),
                etiqueta: Self.ejeFechaFmt.string(from: dia.date),
                valor: dia.score.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) },
                palabra: horas.map { Self.sleepWord($0) },
                mes: rotuloMes)
        }
    }

    /// La leyenda se construye con los MISMOS alfas de la retícula (`alfa(intensidad:)`) sobre el
    /// mismo tono. La de papel pintaba cuatro hues distintos y mentía sobre lo que decodificaba.
    private static var leyendaCalendario: [LiquidCalendario90.NivelLeyenda] {
        [
            .init(id: "enough", color: tono.opacity(LiquidCalendario90.alfa(intensidad: 1)),
                  etiqueta: String(localized: "Enough sleep")),
            .init(id: "ok", color: tono.opacity(LiquidCalendario90.alfa(intensidad: 0.5)),
                  etiqueta: String(localized: "A bit short")),
            .init(id: "short", color: tono.opacity(LiquidCalendario90.alfa(intensidad: 0)),
                  etiqueta: String(localized: "Short sleep")),
            .init(id: "nodata", color: LiquidColor.tinta7,
                  etiqueta: String(localized: "no data")),
        ]
    }

    /// Los tres peldaños de la retícula, con los cortes ALINEADOS al historial (7 · 6.3).
    private static func intensidadSueno(_ hours: Double) -> Double {
        if hours >= 7 { return 1 }
        if hours >= 6.3 { return 0.5 }
        return 0
    }

    /// La palabra de estado de la lectura. Son las MISMAS tres palabras de la escalera del
    /// historial («Suficiente · Algo corta · Corta»), no un vocabulario paralelo: la misma
    /// noche decía «ok» aquí y «Algo corta» un scroll más arriba.
    private static func sleepWord(_ hours: Double) -> String {
        if hours >= 7 { return String(localized: "Enough sleep") }
        if hours >= 6.3 { return String(localized: "A bit short") }
        return String(localized: "Short sleep")
    }

    private static let mesFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f
    }()

    /// El formateador canónico de llave de día en UTC — el lado de LECTURA del contrato (FER-754).
    nonisolated private static let calDayFmt = DayKey.utcFormatter

    /// Arma la retícula de 90 noches desde una foto de la serie de duración (FER-953: pura).
    private nonisolated static func buildSleepHeat(durationSeries: [(day: String, value: Double)],
                                                   todayKey: String) -> [RecoveryDay] {
        var mins: [String: Double] = [:]
        for r in durationSeries { mins[r.day] = r.value }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        // Ancla la ventana de 90 dias al dia LOCAL, igual que Recovery.buildHeat. Anclar al dia UTC
        // hace que en husos negativos, por la tarde, la ventana empiece en otro dia de la semana que
        // Recovery y el grid dibuje 13 vs 14 columnas, con celdas de otro tamano.
        guard let today = Repository.parseDayKey(todayKey) else { return [] }
        return stride(from: 89, through: 0, by: -1).compactMap { off -> RecoveryDay? in
            guard let date = cal.date(byAdding: .day, value: -off, to: today) else { return nil }
            let key = Self.calDayFmt.string(from: date)
            return RecoveryDay(date: date.addingTimeInterval(12 * 3600), score: mins[key])
        }
    }

    // MARK: - 10. Método + sello

    private var pieMetodo: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         mostrar: String(localized: "Show explanation"),
                         ocultar: String(localized: "Hide explanation")) {
                LiquidNotaLine(String(localized: "Regularity is the night-to-night variability of your mid-sleep point (the midpoint between falling asleep and waking): a steadier schedule predicts health more strongly than how long you sleep. Naps don't count: only your main night (at least 3 h) feeds regularity. Stages are estimated from movement, heart rate and HRV, so they're approximate; deep sleep repairs the body, REM consolidates memory and emotion. \"Need\" is a 7–9 h population target, not a measurement of you."),
                               tono: LiquidColor.tinta700)
                LiquidNotaLine(String(localized: "Windred et al., Sleep 2024 (regularity); Miller et al., J Sports Sci 2020 (wrist staging vs PSG); Hirshkowitz et al., 2015 (sleep need)."))
                LiquidVerMas(title: String(localized: "Sleep stages in detail"),
                             tone: Self.tono) { showStages = true }
            }
            LiquidOrigenChip(glyph: .luna,
                             badgeTono: Self.tono,
                             etiqueta: (model.isAppleHealth ? DataOrigin.apple : DataOrigin.band).label,
                             sufijo: String(localized: "last night"))
            if let agreement = model.sourceAgreement {
                // Pieza compartida con las otras pantallas de detalle: se conserva tal cual
                // (migrarla es trabajo del sistema de diseño, no de esta pantalla).
                FusionAgreementRow(point: agreement, theme: theme, format: Self.sleepTotalHM)
            }
        }
        .liquidSeccion(top: LiquidSpace.s550, bottom: LiquidSpace.s800)
    }

    private static func sleepTotalHM(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return "\(m / 60) h \(String(format: "%02d", m % 60)) m"
    }

    // MARK: - Async loaders (FER-832) — mismos motores, sin math nueva

    /// Decisión del dueño (2026-08-17): la forma de la noche SE ABRE a Apple. Solo necesita la FC
    /// del reloj y la línea de tiempo de etapas, y las dos las entrega Apple Salud (FER-486).
    private func loadNightShape() async -> (shape: NightAutonomicShape.Result?, curve: [Double]) {
        guard let night = model.night, !model.intervals.isEmpty else { return (nil, []) }

        let hr = await loadNightHR(night.startTs, night.endTs)
        guard hr.count >= 2 else { return (nil, []) }

        // FER-953: la carga de FC se queda en el camino del caller; la derivación pura sale de main.
        let intervals = model.intervals
        let rhrBaseline = model.rhrBaseline
        let onsetDate = night.onsetDate
        return await Task.detached(priority: .userInitiated) { () -> (NightAutonomicShape.Result?, [Double]) in
            let asleep = intervals
                .filter { $0.stage != .awake }
                .map { NightAutonomicShape.AsleepSpan(start: Int($0.start), end: Int($0.end)) }
            guard !asleep.isEmpty else { return (nil, []) }

            let awakeSpans = intervals.filter { $0.stage == .awake }
            let awakeHR = hr.filter { s in awakeSpans.contains { Int($0.start) <= s.ts && s.ts < Int($0.end) } }
            let wakingRef: Double? = {
                if awakeHR.count >= 30 {
                    return Double(awakeHR.reduce(0) { $0 + $1.bpm }) / Double(awakeHR.count)
                }
                let sorted = hr.map { Double($0.bpm) }.sorted()
                guard !sorted.isEmpty else { return nil }
                let idx = Int((0.90 * Double(sorted.count - 1)).rounded())
                return sorted[idx]
            }()

            let tz = TimeZone.current.secondsFromGMT(for: onsetDate)
            let shape = NightAutonomicShape.compute(hr: hr, asleep: asleep,
                                                    wakingReferenceHR: wakingRef,
                                                    rhrBaseline: rhrBaseline,
                                                    tzOffsetSeconds: tz)

            let asleepHR = hr.filter { s in asleep.contains { $0.start <= s.ts && s.ts < $0.end } }
                             .sorted { $0.ts < $1.ts }
            let curve = Self.downsampleBpm(asleepHR, maxPoints: 48)
            return (shape, curve)
        }.value
    }

    private nonisolated static func downsampleBpm(_ hr: [HRSample], maxPoints: Int) -> [Double] {
        guard hr.count > maxPoints else { return hr.map { Double($0.bpm) } }
        var out: [Double] = []
        out.reserveCapacity(maxPoints)
        for b in 0..<maxPoints {
            let lo = b * hr.count / maxPoints
            let hi = (b + 1) * hr.count / maxPoints
            guard hi > lo else { continue }
            let sum = hr[lo..<hi].reduce(0) { $0 + $1.bpm }
            out.append(Double(sum) / Double(hi - lo))
        }
        return out
    }

    // MARK: - Formateo

    private func pct(_ minutes: Double, _ total: Double) -> Int {
        total > 0 ? Int((minutes / total * 100).rounded()) : 0
    }

    private func hoursOnly(_ minutes: Double) -> String {
        let m = Swift.max(0, Int(minutes.rounded()))
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// Cómo VoiceOver dice una duración de sueño: «7 horas 12 minutos». «7:12» se dicta como
    /// hora del reloj («siete doce»), que no es lo que el numeral quiere decir.
    private func horasHabladas(_ minutes: Double) -> String {
        let m = Swift.max(0, Int(minutes.rounded()))
        return String(localized: "\(m / 60) hours \(m % 60) minutes")
    }

    private var napNotice: String {
        if let minutes = model.excludedNapMinutes {
            return String(localized: "We didn't count your \(napDurationText(minutes)) nap, regularity uses only your main night.")
        }
        return String(localized: "We didn't count your naps (under \(napDurationText(Int(SleepMainNight.minDurationMinutes)))), regularity uses only your main night.")
    }

    private func napDurationText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h) h \(m) min" }
        if h > 0 { return "\(h) h" }
        return "\(m) min"
    }

    private func hoursMinutes(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60) h \(m % 60) m" : "\(m) min"
    }

    private func restorativePct(_ s: SleepDetailModel.Stages) -> Double? {
        guard s.asleep > 0 else { return nil }
        return (s.deep + s.rem) / s.asleep * 100
    }

    private func efficiencyPct(_ night: SleepDetailModel.Night) -> Double? {
        if let stored = night.efficiency {
            return stored <= 1.0 ? stored * 100 : stored
        }
        let bed = night.stages.total
        guard bed > 0 else { return nil }
        return Swift.min(100, night.stages.asleep / bed * 100)
    }
}


// MARK: - SleepStagesInfoSheet — the combined "what the stages mean" card (FER-227)
//
// One bottom sheet explaining all four sleep stages + why they're approximate, opened from the ⓘ next
// to "Last night". It mirrors the `MetricInfoSheet` visual language (warm paper, title, lede, rows,
// footnote) but its content is a list of stages rather than a banded value — so it's its own small
// view, not a contorted `MetricInfo`. Theme passed EXPLICITLY (it doesn't propagate through `.sheet`,
// FER-162); no nested `NavigationStack` (FER-171). The stage hues are the fixed `StrandPalette` sleep
// colors, the same dots the legend uses (color only in the datum).

struct SleepStagesInfoSheet: View {
    var theme: InstrumentoTheme = .base

    private struct StageRow: Identifiable {
        let id = UUID()
        let stage: SleepStage
        let name: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    private let rows: [StageRow] = [
        StageRow(stage: .rem,   name: "REM",   detail: "Dreams and memory. It consolidates what you learned and processes emotion."),
        StageRow(stage: .deep,  name: "Deep",  detail: "Physical repair. Your body restores itself and releases growth hormone."),
        StageRow(stage: .light, name: "Light", detail: "Most of the night. A transition in which your body winds down."),
        StageRow(stage: .awake, name: "Awake", detail: "Brief awakenings. They're normal and don't mean a bad night."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sleep stages")
                    .font(InstrumentoType.groteskHeadline(22))
                    .foregroundStyle(theme.ink)
                Text("Your night moves through four phases. The watch estimates them from your movement and heart rate, so they're approximate: it gets about 2 of 3 right.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        stageRow(row)
                        if i < rows.count - 1 {
                            Divider().overlay(theme.hairline)
                        }
                    }
                }
                Text("Proportions, not minutes. A clinical measurement needs a sleep study.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
    }

    private func stageRow(_ row: StageRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous) // token-exempt: geometría de dato (swatch de leyenda)
                .fill(StrandPalette.sleepStageColor(row.stage))
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(StrandFont.headline).foregroundStyle(theme.ink)
                Text(row.detail)
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - SleepDetailModel — every derivation the screen draws, built ONCE from the repo
//
// The data layer of the old dark sleep screen, lifted out of the view and merged with the new
// `SleepRegularity` engine. `SleepDetailScreen` is pure presentation over this; the caller (Cuerpo)
// builds it with `SleepDetailModel.build(...)` so the screen stays DB-free. Stage minutes come from
// `stagesJSON` (imported = dict of minutes; on-device = segment array); the "typical" is the mean over
// `repo.days`; the regularity read is computed from `repo.sleeps`' onset/wake, excluding Apple-only
// nights (which have no real clock).

struct SleepDetailModel {

    struct Stages: Equatable {
        var awake: Double
        var light: Double
        var deep: Double
        var rem: Double
        /// All stages (includes awake) — total time-in-bed minutes.
        var total: Double { awake + light + deep + rem }
        /// Asleep time = total minus awake.
        var asleep: Double { light + deep + rem }
    }

    struct Night: Equatable {
        let startTs: Int
        let endTs: Int
        let efficiency: Double?
        let respRate: Double?
        let stages: Stages

        var onsetDate: Date { Date(timeIntervalSince1970: TimeInterval(startTs)) }
        var dateLabel: String { Self.dateFmt.string(from: Date(timeIntervalSince1970: TimeInterval(startTs))) }
        private static let dateFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
        }()
    }

    /// The latest night (strap session preferred, else Apple Health fallback). `nil` → empty state.
    let night: Night?
    /// Stage intervals for the hypnogram (empty for Apple-only → proportional bar).
    let intervals: [SleepInterval]
    /// The night came from Apple Health (no clock, no per-epoch timeline). Hides the onset–wake clock.
    let isAppleHealth: Bool
    /// FER-670: the fused sleep-total point for the displayed night's day — nil unless BOTH the band
    /// and Apple Health reported that night. Drives the "coinciden / en conflicto" line in the footer.
    let sourceAgreement: FusedMetricPoint?
    /// Whether the repo finished its first load (drives the empty-state copy: loading vs no-data).
    let loaded: Bool
    /// Last night's rest-confidence tier (FER-676), from the persisted `restConfidence` (duration +
    /// resolved stages, H9-guarded). nil when the shown night has no graded row (e.g. Apple-only) → no sello.
    var confidence: ScoreConfidence? = nil

    // Regularity (FER-218 engine)
    let regularity: SleepRegularity.Result?
    /// How many timing nights fed (or would feed) the regularity read — for the "N to go" calibration.
    let regularityNights: Int
    /// Strap naps (shorter than a main night) excluded from the regularity window, so the UI can
    /// disclose that they didn't count (FER-310). 0 when none.
    let excludedNapCount: Int
    /// Duration (minutes) of the single excluded nap when `excludedNapCount == 1`, for the "your 2 h
    /// nap" copy; `nil` otherwise (0 naps, or ≥2 → generic copy).
    let excludedNapMinutes: Int?

    // "Typical" stage shares (percent of asleep, mean over history) for the vs-typical block.
    let typicalDeepPct: Double?
    let typicalRemPct: Double?
    let typicalLightPct: Double?

    // Night metrics
    /// Sleep performance %: imported WHOOP figure when present, else asleep / personal need (capped 100).
    let performancePct: Double?
    /// Need − asleep for last night, in minutes (the "performance" shortfall), floored at 0.
    let shortfallMinutes: Double?
    /// Sleep latency (minutes) — currently nil (the cache carries no onset-latency); shown as "—".
    let latencyMin: Double?
    /// Awakenings count (disturbances) for the latest night.
    let awakenings: Int?
    /// Baseline resting HR (bpm) for the night-shape's "% of the night below your resting HR": median of
    /// recent nightly resting-HR (the sleep nadir the app treats as RHR). `nil` until enough nights. (FER-832)
    let rhrBaseline: Double?

    // Duration trend + debt
    /// The FULL nightly duration series (oldest → newest) as `(day "yyyy-MM-dd", hours)`, so the duration
    /// trend carries its own period selector (W/M/3M/6M/1Y) + «Media móvil ⇄ Rangos» toggle like the
    /// vitals — windowed in the view via `MetricWindowMath`. (FER-573)
    let durationSeries: [(day: String, value: Double)]
    /// Accumulated sleep debt over the trailing 7 days, in minutes (sum of per-night need − asleep,
    /// floored per night). `nil` when there's nothing to sum.
    let weeklyDebtMinutes: Double?
    /// Per-night sleep-vs-need for the trailing 7 days, feeding the debt bars. `vsNeedMin` is signed:
    /// negative = fell short of need (debt), positive = beat it (surplus). (FER-249 v2)
    let weeklyDebtNights: [DebtNight]

    /// One night's sleep relative to your personal need, in minutes (signed). Drives a single debt bar.
    /// `sleptMin` is the night's total sleep, for the scrub tooltip's "slept …" line. (FER-249 v3)
    struct DebtNight: Equatable {
        let date: Date
        let vsNeedMin: Double
        let sleptMin: Double
    }

    // Per-metric 14-day mini-trends for the metric info cards (FER-227). Derived from `repo.days`;
    // empty when there's no series, so the sheet shows its "no data" well rather than a fake line.
    let performanceTrend: [TrendPoint]
    let efficiencyTrend: [TrendPoint]
    let restorativeTrend: [TrendPoint]
    let respirationTrend: [TrendPoint]
    let awakeningsTrend: [TrendPoint]
    /// The full nightly respiratory-rate series (oldest → newest, `nil` = missing night) for the
    /// respiration-trend watch (FER-851). The engine derives its own baseline + deviation from it.
    let respNightly: [Double?]

    // MARK: - Build

    /// Personal sleep need (minutes): mean asleep, never below a 7.5 h floor. Single source of truth
    /// shared with the coach/InsightEngine via `SleepMath` (FER-339), so both show the same debt.
    private static func sleepNeedMin(_ days: [DailyMetric]) -> Double {
        SleepMath.needMinutes(days)
    }

    /// Build the whole model from the repo's in-memory dashboard. Pure (no DB); call from the caller's
    /// view, once per data change. `appleHealthDays` flags which day rows are Apple-sourced (no clock).
    static func build(days: [DailyMetric],
                      sleeps: [CachedSleepSession],
                      appleSleeps: [CachedSleepSession] = [],
                      importedSleep: [String: ImportedSleepFigures],
                      appleHealthDays: Set<String>,
                      loaded: Bool,
                      todayKey: String,
                      fusion: [String: [String: FusedMetricPoint]] = [:]) -> SleepDetailModel {
        // Ignore any future-dated row: a daily can be bucketed under "tomorrow" in UTC (FER-226),
        // and a `.last` read would surface that empty row as "last night". Anchor to the device's
        // local day, mirroring StressModel (FER-224) / ReadinessEngine.
        let days = days.filter { $0.day <= todayKey }
        // --- Latest night: strap session wins, else Apple Health stage minutes (FER-62). ---
        // Respiration for the strap night comes from the latest daily metric (the session doesn't
        // carry it), so the Respiration tile shows anoche's value instead of "—". (FER-234)
        let strap = latestStrapNight(sleeps, respRate: days.last?.respRateBpm)
        // FER-486: an Apple Health session with a real per-epoch stage timeline (watchOS 9+) draws the SAME
        // hypnogram as a strap night. `appleSleeps` only holds nights the band didn't cover (band wins
        // upstream), so pick the most recent night across both — Apple wins only when it's newer / strap is nil.
        let appleNight = latestAppleSessionNight(appleSleeps)
        let useAppleSession: Bool = {
            guard let a = appleNight else { return false }
            guard let s = strap else { return true }
            return a.startTs > s.startTs
        }()
        let night: Night? = useAppleSession ? appleNight
                          : (strap ?? appleHealthNight(days: days, appleHealthDays: appleHealthDays))
        let isApple = useAppleSession || (strap == nil && night != nil)
        let intervals: [SleepInterval] = {
            if useAppleSession, let a = appleSleeps.last {
                return decodeSegments(a.stagesJSON, sessionStart: a.startTs)?.intervals ?? []
            }
            guard !isApple, let s = sleeps.last else { return [] }
            return decodeSegments(s.stagesJSON, sessionStart: s.startTs)?.intervals ?? []
        }()

        // --- Regularity: onset/wake from real sessions, Apple + strap (FER-1026). `appleSleeps` carry
        // real startTs/endTs (FER-486) and never overlap strap nights (`appleSleepsNotCoveredByStrap`),
        // so the union is every real night; the engine drops naps itself via `SleepMainNight`. Without
        // this, Apple-only users had an empty `timing` → "calibrating" forever. `realSessions` (the union
        // minus the degenerate daily fallback, start == end) also feeds the nap disclosure below. ---
        let realSessions = (appleSleeps + sleeps).filter { $0.endTs > $0.startTs }
        let timing = realSessions.map { SleepRegularity.NightTiming(onset: $0.startTs, wake: $0.endTs) }
        let regularity = SleepRegularity.compute(timing)
        // The effective window size the engine scores — main nights only, capped at windowNights — so
        // "N nights to go" matches `compute` instead of over-counting raw sessions (naps included).
        let regularityNights = SleepRegularity.effectiveNightCount(timing)

        // --- Naps excluded from the regularity window, for the disclosure line (FER-310). ---
        // The engine keeps only "main nights" (≥ SleepMainNight threshold) and scores the most recent
        // `windowNights` of them. A nap counts as excluded only if it onset at/after the oldest night
        // in that window — older naps are off-window and irrelevant to the current read.
        let napThresholdSec = Int(SleepMainNight.minDurationMinutes * 60)
        let mainNightWindow = realSessions
            .filter { $0.endTs - $0.startTs >= napThresholdSec }
            .sorted { $0.startTs > $1.startTs }
            .prefix(SleepRegularity.windowNights)
        let windowStart = mainNightWindow.last?.startTs ?? 0
        let excludedNaps = mainNightWindow.isEmpty ? [] : realSessions.filter {
            $0.endTs - $0.startTs < napThresholdSec && $0.startTs >= windowStart
        }
        let excludedNapCount = excludedNaps.count
        let excludedNapMinutes = excludedNapCount == 1
            ? (excludedNaps[0].endTs - excludedNaps[0].startTs) / 60 : nil

        // --- Typical stage shares (percent of asleep), mean over days that carry all three stages. ---
        var deepPcts: [Double] = [], remPcts: [Double] = [], lightPcts: [Double] = []
        for d in days {
            guard let deep = d.deepMin, let rem = d.remMin, let light = d.lightMin else { continue }
            let asleep = deep + rem + light
            guard asleep > 0 else { continue }
            deepPcts.append(deep / asleep * 100)
            remPcts.append(rem / asleep * 100)
            lightPcts.append(light / asleep * 100)
        }

        // --- Night metrics for the latest night. ---
        let need = sleepNeedMin(days)
        let latestDay = days.last
        let imported = latestDay.flatMap { importedSleep[$0.day] }
        let asleepLast = night?.stages.asleep
        let performancePct: Double? = {
            if let p = imported?.performancePct { return p }
            guard let asleep = asleepLast, asleep > 0, need > 0 else { return nil }
            return Swift.min(100, asleep / need * 100)
        }()
        let shortfall: Double? = {
            guard let asleep = asleepLast, asleep > 0 else { return nil }
            return Swift.max(0, need - asleep)
        }()
        let awakenings = latestDay?.disturbances

        // RHR baseline for the night-shape (FER-832): median of recent nightly resting-HR (the sleep
        // nadir the app already treats as RHR). Uses the trailing ~28 nights; nil until any exist.
        let recentRHR = sleeps.suffix(28).compactMap { $0.restingHr }.map(Double.init).sorted()
        let rhrBaseline: Double? = {
            guard !recentRHR.isEmpty else { return nil }
            let m = recentRHR.count / 2
            return recentRHR.count % 2 == 1 ? recentRHR[m] : (recentRHR[m - 1] + recentRHR[m]) / 2
        }()

        // --- Duration trend (full nightly series, in hours) + 7-day accumulated debt. ---
        // The FULL nightly duration series (hours), windowed by period in the trend block (FER-573).
        let durationSeries: [(day: String, value: Double)] = days.compactMap { d in
            guard let mins = d.totalSleepMin, mins > 0 else { return nil }
            return (d.day, mins / 60.0)
        }
        let weeklyDebt: Double? = {
            let last7 = days.suffix(7)
            let debts = last7.compactMap { d -> Double? in
                if let debt = importedSleep[d.day]?.debtMin { return debt }
                guard let asleep = d.totalSleepMin, asleep > 0, need > 0 else { return nil }
                return Swift.max(0, need - asleep)
            }
            return debts.isEmpty ? nil : debts.reduce(0, +)
        }()
        // Per-night sleep-vs-need for the debt bars (signed: < 0 = short of need). Derived on-device from
        // total sleep so it carries surplus too; the headline total above still honours imported debt.
        let debtNights: [DebtNight] = days.suffix(7).compactMap { d in
            guard let asleep = d.totalSleepMin, asleep > 0, need > 0,
                  let date = Repository.parseDayKey(d.day) else { return nil }
            return DebtNight(date: date, vsNeedMin: asleep - need, sleptMin: asleep)
        }

        // --- Per-metric 14-day mini-trends for the info cards (FER-227). Same derivations as the tiles,
        // over history; each skips nights missing that value. ---
        let performanceTrend = metricTrend(days) { d in
            if let p = importedSleep[d.day]?.performancePct { return p }
            guard let asleep = d.totalSleepMin, asleep > 0, need > 0 else { return nil }
            return Swift.min(100, asleep / need * 100)
        }
        let efficiencyTrend = metricTrend(days) { d in
            d.efficiency.map { $0 <= 1.0 ? $0 * 100 : $0 }
        }
        let restorativeTrend = metricTrend(days) { d in
            guard let deep = d.deepMin, let rem = d.remMin, let light = d.lightMin else { return nil }
            let asleep = deep + rem + light
            return asleep > 0 ? (deep + rem) / asleep * 100 : nil
        }
        let respirationTrend = metricTrend(days) { $0.respRateBpm }
        let awakeningsTrend = metricTrend(days) { $0.disturbances.map(Double.init) }
        // Full nightly respiration series (oldest → newest) for the respiration-trend watch (FER-851).
        let respNightly: [Double?] = days.map { $0.respRateBpm }

        return SleepDetailModel(
            night: night,
            intervals: intervals,
            isAppleHealth: isApple,
            // FER-670: the source-agreement point for the displayed night's day (the same `latestDay`
            // the other night metrics read) — non-nil only when band AND Apple reported that night.
            sourceAgreement: latestDay.flatMap { fusion[$0.day]?["sleep_total_min"] },
            loaded: loaded,
            // FER-676: the persisted rest tier of the same `latestDay` row the other night metrics
            // read. Apple-only rows never carry it → nil → no sello (honest, nothing was graded).
            confidence: latestDay?.restConfidence.flatMap(ScoreConfidence.init(rawValue:)),
            regularity: regularity,
            regularityNights: regularityNights,
            excludedNapCount: excludedNapCount,
            excludedNapMinutes: excludedNapMinutes,
            typicalDeepPct: mean(deepPcts),
            typicalRemPct: mean(remPcts),
            typicalLightPct: mean(lightPcts),
            performancePct: performancePct,
            shortfallMinutes: shortfall,
            latencyMin: nil,
            awakenings: awakenings,
            rhrBaseline: rhrBaseline,
            durationSeries: durationSeries,
            weeklyDebtMinutes: weeklyDebt,
            weeklyDebtNights: debtNights,
            performanceTrend: performanceTrend,
            efficiencyTrend: efficiencyTrend,
            restorativeTrend: restorativeTrend,
            respirationTrend: respirationTrend,
            awakeningsTrend: awakeningsTrend,
            respNightly: respNightly)
    }

    /// Runs `build` off the MainActor (FER-953): snapshots the inputs from `repo` on the MainActor
    /// (value-type copies), then hops the whole derivation — pure StrandAnalytics engines — to a
    /// background executor; only the finished model returns to main. Single seam for every call-site.
    @MainActor
    static func buildDetached(repo: Repository) async -> SleepDetailModel {
        let days = repo.days, sleeps = repo.sleeps, appleSleeps = repo.appleSleeps
        let importedSleep = repo.importedSleep, appleHealthDays = repo.appleHealthDays
        let loaded = repo.loaded, fusion = repo.fusion
        let todayKey = Repository.localDayKey(Date())
        return await Task.detached(priority: .userInitiated) {
            build(days: days, sleeps: sleeps, appleSleeps: appleSleeps, importedSleep: importedSleep,
                  appleHealthDays: appleHealthDays, loaded: loaded, todayKey: todayKey, fusion: fusion)
        }.value
    }

    /// Placeholder while `buildDetached` runs: renders the screen's existing `!loaded` loading state.
    /// Pure + deterministic, so it's computed once per process.
    static let loading: SleepDetailModel = build(
        days: [], sleeps: [], appleSleeps: [], importedSleep: [:], appleHealthDays: [],
        loaded: false, todayKey: "", fusion: [:])

    /// Trailing 14 nights of a metric, in whatever unit `pick` returns, as `TrendPoint`s. Skips nights
    /// where the value is missing; empty when there's nothing to chart. (FER-227)
    private static func metricTrend(_ days: [DailyMetric], _ pick: (DailyMetric) -> Double?) -> [TrendPoint] {
        // Solo se dibujan los últimos 14 puntos. Recorre desde el final y parsea a lo más ~14 llaves de día
        // en vez de parsear TODO el historial 5 veces en el hilo del tap: `Repository.parseDayKey` usa un
        // `DateFormatter` (caro), y build() antes hacía 5·N parseos síncronos → jank al abrir Sueño. Mismo
        // resultado que `compactMap{…}.suffix(14)` (últimos 14 puntos no nulos, en orden). (perf FER-freeze)
        var pts: [TrendPoint] = []
        for d in days.reversed() {
            guard let v = pick(d), let date = Repository.parseDayKey(d.day) else { continue }
            pts.append(TrendPoint(date: date, value: v))
            if pts.count == 14 { break }
        }
        return pts.reversed()
    }

    // MARK: - Night resolution (ported from the old sleep screen)

    /// The most recent strap sleep, decoded into stage durations + (when on-device) its real timeline.
    /// `respRate` is the night's mean respiration, taken from the matching daily metric — the cached
    /// sleep session itself doesn't carry it, so without this the "Respiration" tile read "—" even
    /// though the 14-day trend (sourced from `repo.days`) had data. (FER-234)
    private static func latestStrapNight(_ sleeps: [CachedSleepSession], respRate: Double?) -> Night? {
        guard let s = sleeps.last, s.endTs > s.startTs else { return nil }
        if let stages = decodeStages(s.stagesJSON), stages.total > 0 {
            return Night(startTs: s.startTs, endTs: s.endTs, efficiency: s.efficiency,
                         respRate: respRate, stages: stages)
        }
        if let seg = decodeSegments(s.stagesJSON, sessionStart: s.startTs), seg.stages.total > 0 {
            return Night(startTs: s.startTs, endTs: s.endTs, efficiency: s.efficiency,
                         respRate: respRate, stages: seg.stages)
        }
        return nil
    }

    /// Fallback Night from the most recent Apple Health day carrying sleep-stage minutes (FER-62). No
    /// real clock (startTs == endTs at noon-UTC), so the screen draws a proportional bar.
    private static func appleHealthNight(days: [DailyMetric], appleHealthDays: Set<String>) -> Night? {
        guard let d = days.last(where: {
            appleHealthDays.contains($0.day) && ($0.totalSleepMin ?? 0) > 0
        }) else { return nil }
        let deep = d.deepMin ?? 0, rem = d.remMin ?? 0, light = d.lightMin ?? 0
        guard deep + rem + light > 0 else { return nil }
        let stages = Stages(awake: 0, light: light, deep: deep, rem: rem)
        let startTs = Int((Repository.parseDayKey(d.day) ?? Date()).timeIntervalSince1970) + 12 * 3600
        return Night(startTs: startTs, endTs: startTs, efficiency: d.efficiency,
                     respRate: d.respRateBpm, stages: stages)
    }

    /// The most recent Apple Health session carrying a REAL stage timeline (FER-486) — drawn as a full
    /// hypnogram, unlike `appleHealthNight` (daily totals → proportional bar). Apple's sleepAnalysis has
    /// no per-session respiration/efficiency, so those tiles fall back to the daily metric / "—".
    private static func latestAppleSessionNight(_ appleSleeps: [CachedSleepSession]) -> Night? {
        guard let s = appleSleeps.last, s.endTs > s.startTs,
              let seg = decodeSegments(s.stagesJSON, sessionStart: s.startTs), seg.stages.total > 0
        else { return nil }
        return Night(startTs: s.startTs, endTs: s.endTs, efficiency: s.efficiency,
                     respRate: nil, stages: seg.stages)
    }

    /// Trailing 14 nights of total sleep, in HOURS — the same window the Today sleep sheet charts, so
    /// both screens read identically (FER-249 v2). Falls back to all nights when the window is sparse.
    // MARK: - Stage decoding (ported from the old sleep screen)

    /// Decode the imported stagesJSON dict of MINUTES {"light","deep","rem","awake"}.
    private static func decodeStages(_ json: String?) -> Stages? {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return nil }
        func val(_ key: String) -> Double {
            if let n = dict[key] as? NSNumber { return n.doubleValue }
            if let d = dict[key] as? Double { return d }
            if let i = dict[key] as? Int { return Double(i) }
            return 0
        }
        let s = Stages(awake: val("awake"), light: val("light"), deep: val("deep"), rem: val("rem"))
        return s.total > 0 ? s : nil
    }

    /// Decode the COMPUTED stagesJSON segment array [{start,end,stage}] into stage totals + the real
    /// timeline (seconds relative to the session start). The on-device SleepStager calls awake "wake".
    private static func decodeSegments(_ json: String?, sessionStart: Int) -> (stages: Stages, intervals: [SleepInterval])? {
        guard let json, let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              !arr.isEmpty else { return nil }
        var stages = Stages(awake: 0, light: 0, deep: 0, rem: 0)
        var intervals: [SleepInterval] = []
        for seg in arr {
            guard let start = (seg["start"] as? NSNumber)?.intValue,
                  let end = (seg["end"] as? NSNumber)?.intValue, end > start,
                  let name = seg["stage"] as? String else { continue }
            let minutes = Double(end - start) / 60.0
            let stage: SleepStage
            switch name {
            case "wake", "awake": stage = .awake; stages.awake += minutes
            case "light": stage = .light; stages.light += minutes
            case "deep": stage = .deep; stages.deep += minutes
            case "rem": stage = .rem; stages.rem += minutes
            default: continue
            }
            intervals.append(SleepInterval(stage: stage,
                                           start: TimeInterval(start - sessionStart),
                                           end: TimeInterval(end - sessionStart)))
        }
        return stages.total > 0 ? (stages, intervals) : nil
    }

    private static func mean(_ vals: [Double]) -> Double? {
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }
}
#endif
