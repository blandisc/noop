#if os(iOS)
import SwiftUI
import CenitDesign
import StrandAnalytics
import CenitStore
import BiometricStreams
import Foundation

// MARK: - SleepDetailScreen — el «Detalle de Sueño» en vidrio Liquid (FER-102)
//
// Detalle de Sueño en Liquid Glass · El Eje (FER-102 · FER-342): campo teñido a sangre
// (`LiquidCampoMetrica`) → costuras de sección (`LiquidFranjaSeccion`) → mosaicos
// (`LiquidCajita`) → las gráficas de la familia. Los motores, el modelo y los loaders NO
// cambian: `SleepDetailModel`, `NightAutonomicShape` y `Baselines` se leen tal cual, y esta
// pantalla sigue siendo pura presentación (cero DB).
//
// Tres decisiones del dueño (2026-08-17) van dentro:
//   1. el héroe conserva LOS DOS datos (horas | regularidad) en UN solo campo;
//   2. se ELIMINAN los tres bloques que no podían dibujarse: «Reserva para bajar de marcha»
//      (necesita latido a latido, que Apple no entrega) y «Forma de la noche» + «Primer tercio
//      vs último» (necesitan la FC MIENTRAS DUERMES, y la app solo importa la de los
//      entrenamientos). Con ellos se van sus loaders inyectados y el cómputo que quedó sin
//      lector. Traer la FC nocturna es un issue aparte; entonces los bloques vuelven;
//   3. entra una sección de Regularidad con la MISMA tarjeta de la hoja de resumen;
//   4. el orden es de tres actos: lo que dormiste → cómo se compara → el tiempo.
//
// Se presenta como hoja (TodayView) o como capa (CuerpoView, `DetailChrome`), con el tema vivo
// explícito (FER-162 — hoy solo lo consume `SleepStagesInfoSheet`, que sigue en papel) y SIN
// `NavigationStack` anidado (FER-171).

/// Detalle de Sueño en vidrio Liquid. Se arma UNA vez desde un `SleepDetailModel` (el caller
/// inyecta el modelo para que la pantalla siga sin tocar la base de datos).
struct SleepDetailScreen: View {
    /// Todo lo que la pantalla dibuja, derivado UNA vez por el caller desde `repo`.
    let model: SleepDetailModel
    /// `true` cuando Apple Salud NO está autorizado. Sin esto, quien nunca dio permiso leía
    /// «Aún no hay noches»: le decíamos que no tiene datos cuando el problema es que no
    /// podemos verlos. Mismo predicado que ya usan Hoy y el aterrizaje. (Dueño 2026-08-18)
    var sinPermiso: Bool = false


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
            LazyVStack(alignment: .leading, spacing: .zero) {
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
                    seccion(String(localized: "Regularity")) { regularidadContent }
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
        // (`DetailChrome`, que no es una hoja) y `presentationBackground` para la hoja de Hoy.
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
        .sheet(item: $metricInfo) { info in
            // Cutover F6 (decisión D1 del revote): las submétricas de sueño abren la hoja Liquid.
            LiquidMetricSheetView(info: info, trendLoader: trendLoader(for: info.id))
        }
        .sheet(isPresented: $showStages) {
            SleepStagesInfoSheet()
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
                // Opción 2 del dueño (2026-08-17): los DOS numerales quedan limpios y la
                // unidad/escala baja al rótulo. El «/100» pegado a la diagonal apretaba, y la
                // «h» a 20 competía con el numeral; el rótulo ya es una línea de texto chico
                // donde caben sin estorbar.
                .init(valor: hoursOnly(night.stages.asleep),
                      rotulo: String(localized: "Hours slept"),
                      // «7:12» se dicta como hora del reloj («siete doce»); VoiceOver dice horas.
                      a11y: horasHabladas(night.stages.asleep)),
                // Sin base todavía, el numeral NO miente: «··» atenuado con su motivo, no un
                // número. El tipo `Dato` cuelga del genérico del campo, así que se nombra
                // SIEMPRE por `.init`/`.calibrando` — escribirlo completo rompe la inferencia.
                model.regularity.map {
                    .init(valor: "\($0.score)",
                          rotulo: String(localized: "Regularity · of 100"))
                } ?? .calibrando(rotulo: String(localized: "Regularity · of 100"),
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
                LiquidCampoSello(tier.confidenceLabelText, a11y: tier.confidenceA11yText)
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
        .liquidTarjetaSeccion()
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
            clausula: clausulaVacia) {
            if sinPermiso {
                LiquidVerMas(title: String(localized: "Manage Apple Health permissions"),
                             tone: LiquidColor.papelAlto) { abrirAjustesSalud() }
            }
        }
    }

    /// Tres vacíos distintos, no uno: cargando · sin permiso · con permiso y sin noches.
    private var clausulaVacia: String {
        guard model.loaded else { return String(localized: "Loading your sleep history…") }
        return sinPermiso
            ? String(localized: "Cénit can't read your sleep: Apple Health hasn't granted permission. Turn it on and the nights you already have will appear here.")
            : String(localized: "No nights yet. Connect Apple Health in Data Sources to see your sleep stages and trends.")
    }

    /// Abre Ajustes de iOS en la ficha de la app, que es donde vive el permiso de Salud.
    private func abrirAjustesSalud() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
                // `overline` es también el label de VoiceOver del componente: con "" la barra
                // quedaba como un elemento anónimo que dictaba las duraciones sin decir de qué.
                // El título va arriba en la fila, así que aquí se pasa oculto a la vista.
                LiquidStageBar(etapas: sleepEtapas(night), overline: nightTitle, ventana: nil,
                               mostrarOverline: false)
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
            horasEje: LiquidHipnograma.horasDelEje(intervalos) { Self.clockFmt.string(from: $0) },
            textoTramo: { tramo in
                (valor: Self.etiquetasEtapa[tramo.etapa] ?? "",
                 detalle: Self.rangoTramo(tramo))
            },
            a11yLabel: nightTitle,
            a11yValue: stagesA11y(night.stages))
        // Sin tarjeta, como la barra de etapas: el dueño pidió secciones planas que llenen el
        // ancho («nada flotando»). La sección ya tiene su margen; envolverla otra vez metía un
        // segundo sistema visual dentro del mismo bloque.
        .frame(maxWidth: .infinity, alignment: .leading)
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
    static let coloresEtapa: [LiquidHipnograma.Etapa: Color] = [
        .profundo: LiquidColor.indigo,
        .rem: LiquidColor.indigo.opacity(0.78),  // token-exempt(dato): rampa graduada de etapas
        .ligero: LiquidColor.indigo.opacity(0.52),  // token-exempt(dato): rampa graduada de etapas
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

    // MARK: - Regularidad — la MISMA tarjeta de la hoja de resumen

    /// `LiquidRegularityCard`, sin variante: es la pieza que ya usa la hoja
    /// (`LiquidMetricSheetView`), con su mismo copy y su mismo ⓘ. El dueño pidió que el
    /// detalle reutilice los componentes del resumen en vez de acuñar gemelos.
    ///
    /// El héroe sigue mostrando el 88 (decisión del dueño: el campo lleva los dos datos);
    /// esta sección es la que lo EXPLICA — su palabra de nivel y qué mide.
    private var regularidadContent: some View {
        LiquidRegularityCard(
            // Sin título: la franja de la sección ya dice «Regularidad». Repetirlo dentro
            // dejaba dos encabezados a 8 pt de distancia.
            titulo: "",
            puntaje: model.regularity?.score,
            leyenda: regularidadLeyenda,
            tono: Self.tono,
            explicacion: String(localized: "How steady your sleep schedule is: we take each night's midpoint (between falling asleep and waking) and measure how much it shifts night to night. Less drift, closer to 100."),
            infoMostrar: String(localized: "Show explanation"),
            infoOcultar: String(localized: "Hide explanation"))
    }

    /// La palabra de nivel de la regularidad, o cuántas noches faltan para tener base.
    private var regularidadLeyenda: String {
        guard let r = model.regularity else {
            let faltan = max(0, SleepRegularity.minNights - model.regularityNights)
            return String(localized: "Still learning your schedule · \(faltan) nights to go")
        }
        return regularityWordText(r.score)
    }

    // MARK: - 3. Anoche vs lo típico — barras con marca de promedio

    private func stagesVsTypicalContent(_ night: SleepDetailModel.Night) -> some View {
        let s = night.stages
        // El bloque FLOTA en la tarjeta del resumen: el dueño pidió combinar los componentes
        // flotantes de la hoja con las secciones que cierran del detalle, y este es una
        // LECTURA con su propio marco (como las cajitas de métricas), no la gráfica de la
        // sección. El hipnograma y la barra de etapas siguen planos a propósito.
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            vsTypicalVerdict(s)
            stageVsTypicalRow(String(localized: "Deep"), lastMin: s.deep, dormido: dormidoAnoche(s),
                              typicalPct: model.typicalDeepPct,
                              color: Self.coloresEtapa[.profundo] ?? Self.tono,
                              higherIsBetter: true, index: 0)
            stageVsTypicalRow(String(localized: "REM"), lastMin: s.rem, dormido: dormidoAnoche(s),
                              typicalPct: model.typicalRemPct,
                              color: Self.coloresEtapa[.rem] ?? Self.tono,
                              higherIsBetter: true, index: 1)
            stageVsTypicalRow(String(localized: "Light"), lastMin: s.light, dormido: dormidoAnoche(s),
                              typicalPct: model.typicalLightPct,
                              color: Self.coloresEtapa[.ligero] ?? Self.tono,
                              higherIsBetter: false, index: 2)
            LiquidNotaLine(String(localized: "The mark is your average."))
        }
        .liquidTarjetaSeccion()
    }

    /// El tiempo DORMIDO de la noche: el total menos lo que estuviste despierto. Es el
    /// denominador de las tres barras, el mismo que usa `typicalDeepPct` y compañía.
    private func dormidoAnoche(_ s: SleepDetailModel.Stages) -> Double {
        Swift.max(0, s.total - s.awake)
    }

    /// El nombre de la etapa TEÑIDO dentro de la frase; el resto en tinta. Mismas cinco frases
    /// localizadas de siempre (sin claves nuevas).
    /// El veredicto de etapas: la MISMA frase de siempre, con el nombre de la etapa teñido.
    ///
    /// Antes esto eran 42 líneas que recorrían la frase a mano buscando rangos sin traslape y
    /// concatenando `Text` — exactamente lo que hace `LiquidReadingLine`, que la hoja de
    /// resumen ya usaba. Se extendió el componente para destacar VARIOS trozos (el caso
    /// «Profundo y REM») en vez de forkear la pantalla. De paso la frase vuelve a escalar con
    /// Dynamic Type: `LiquidType.titulo` no es relativo a ningún estilo y la congelaba.
    @ViewBuilder private func vsTypicalVerdict(_ s: SleepDetailModel.Stages) -> some View {
        let deep = stageShareAbove(s.deep, s.total, model.typicalDeepPct)
        let rem = stageShareAbove(s.rem, s.total, model.typicalRemPct)
        let (frase, etapas): (String, [String]) = {
            if deep && rem {
                return (String(localized: "Deep and REM above your typical"),
                        [String(localized: "Deep"), String(localized: "REM")])
            }
            if deep { return (String(localized: "Deep above your typical"),
                              [String(localized: "Deep")]) }
            if rem  { return (String(localized: "REM above your typical"),
                              [String(localized: "REM")]) }
            if let light = model.typicalLightPct {
                let ultima = s.total > 0 ? s.light / s.total * 100 : 0
                if ultima > light + 1 {
                    let f = String(localized: "More light sleep than your typical")
                    // La frase fuente en EN dice «light sleep»; es-MX dice «sueño ligero».
                    let cand = ["light sleep", "sueño ligero"]
                    return (f, cand.filter { f.range(of: $0, options: .caseInsensitive) != nil })
                }
            }
            return (String(localized: "Close to your typical stage mix"), [])
        }()
        LiquidReadingLine(frase, highlights: etapas, highlightTone: Self.tono)
    }

    private func stageShareAbove(_ min: Double, _ total: Double, _ typical: Double?) -> Bool {
        guard let typical, total > 0 else { return false }
        return (min / total * 100) > typical + 0.5
    }

    /// Una fila del bloque, ya como pieza del sistema: el relleno mide anoche y el tick de tinta
    /// marca tu promedio. El delta (y su color) los calcula el componente.
    private func stageVsTypicalRow(_ label: String, lastMin: Double, dormido: Double,
                                   typicalPct: Double?, color: Color,
                                   higherIsBetter: Bool, index: Int) -> some View {
        // DENOMINADOR: tiempo DORMIDO, no tiempo en cama. Los dos lados de la barra tienen
        // que medir lo mismo — el típico (`typicalDeepPct`) siempre se calculó sobre dormido,
        // y anoche se calculaba sobre el total con despierto incluido. El sesgo era
        // 1 − despierto/total: un profundo real de 18.0 % se mostraba 16.2 % y la fila decía
        // «−2» en ámbar cuando el cambio verdadero era CERO. (Decisión del dueño 2026-08-18;
        // mueve los deltas de la base instalada, y por eso se decidió arriba, no aquí.)
        let lastPct = dormido > 0 ? lastMin / dormido * 100 : 0
        // Las MISMAS dos claves del papel («…, 22% last night» + «, typical 18%»), unidas igual:
        // sin base, la voz NO menciona promedio (regla 2 de `LiquidBarraMarca`).
        let voz = String(localized: "\(label), \(Int(lastPct.rounded()))% last night")
            + (typicalPct.map { String(localized: ", typical \(Int($0.rounded()))%") } ?? "")
        return LiquidBarraMarca(
            etiqueta: label,
            fraccion: dormido > 0 ? lastPct / 100 : nil,
            marca: typicalPct.map { $0 / 100 },
            tono: color,
            valorTexto: "\(Int(lastPct.rounded()))%",
            masEsMejor: higherIsBetter,
            indice: index,
            a11yLabel: label,
            a11yValue: voz)
    }

    /// **Latencia**: cuánto tardaste en dormirte, derivada del hipnograma.
    ///
    /// Es el tramo DESPIERTO con el que abre la noche, antes de la primera etapa de sueño.
    /// Apple no entrega un dato de latencia y el modelo la traía fija en `nil` desde siempre
    /// (`latencyMin: nil`, comentado «the cache carries no onset-latency»), así que la cajita
    /// enseñaba un guion eterno al lado de «10–20 sano» — una norma clínica sin dato.
    ///
    /// Devuelve `nil` —y lo DICE— cuando la noche abre ya dormida: si la sesión empezó en el
    /// sueño y no en la cama, no hubo espera que medir, y fabricar un 0 sería inventar que te
    /// dormiste al instante. Honesto sobre un límite real de la fuente.
    static func latenciaMin(_ intervalos: [SleepInterval]) -> Double? {
        let orden = intervalos.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard let primero = orden.first, primero.stage == .awake else { return nil }

        // El primer tramo de SUEÑO es la condición: sin él no hubo latencia que medir, hubo
        // una noche en vela. Sin esta guarda, una sesión de 8 h enteramente despierta
        // devolvía 480 y la cajita imprimía «480 min» junto a «10–20 sano».
        guard let onset = orden.first(where: { $0.stage != .awake }) else { return nil }

        // El despierto de apertura puede venir partido en tramos contiguos, pero NUNCA puede
        // pasarse del onset: dos fuentes de sueño escribiendo a la vez producen tramos
        // solapados, y sin el tope un awake 0–30 que solapa un sueño que arrancó en el 10
        // reportaba 30 (el triple de lo real).
        var fin = primero.end
        for iv in orden.dropFirst() {
            guard iv.stage == .awake, iv.start <= fin + 1 else { break }
            fin = max(fin, iv.end)
        }
        let minutos = (min(fin, onset.start) - primero.start) / 60
        return minutos > 0 ? minutos : nil
    }

    /// La latencia de ESTA noche, o nil si la noche abre ya dormida.
    private var latenciaNoche: Double? { Self.latenciaMin(model.intervals) }

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
            // La latencia se DERIVA del hipnograma (ver `latenciaMin`): el modelo la traía fija
            // en nil desde siempre y la cajita mostraba un guion eterno junto a un rango sano
            // que nunca se podía contrastar.
            cajitaMetrica(rotulo: String(localized: "Latency"),
                          valor: latenciaNoche.map { "\(Int($0.rounded()))" },
                          unidad: String(localized: "min"),
                          pie: latenciaNoche == nil
                              ? String(localized: "your night starts already asleep")
                              : String(localized: "10–20 healthy · see method"),
                          info: .sleepLatency(latenciaNoche))
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
        // Flota porque trae su PROPIO titular («1 h 45 m · de retraso esta semana»): la
        // tarjeta existe para amarrar el titular a su evidencia. Los bloques cuyo título lo
        // pone la franja —hipnograma, calendario— van planos; envolverlos sería un marco
        // dentro de otro marco. Era el único bloque que rompía la regla.
        .liquidTarjetaSeccion()
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
                    // La MISMA frase que encabeza la gráfica en la hoja de resumen: el
                    // CARRIL en que cayó anoche y cuántas noches del periodo cayeron con
                    // ella. Antes aquí iba la media, que no se pierde — vive en su cajita
                    // «Promedio», dos filas abajo.
                    fraseNivelHistorial(window)
                    if let pctChange {
                        LiquidNotaLine(pctChange >= 0 ? "+\(Int(pctChange.rounded()))%"
                                                      : "\(Int(pctChange.rounded()))%",
                                       tono: pctChange >= 0 ? LiquidColor.positivo
                                                            : LiquidColor.atencionTexto)
                    }
                    graficaHistorial(window)
                    // La nota describe la GRÁFICA: va pegada a ella, dentro de la tarjeta.
                    // Suelta al final quedaba después de la escalera, describiendo algo que
                    // el ojo ya había dejado atrás.
                    LiquidNotaLine(String(localized: "Hours asleep per night, with your bands behind."))
                    // `LiquidResumenVentana`: la pieza del sistema para Promedio · Rango ·
                    // Anoche — columnas con capilares y SIN superficie propia, apilada DENTRO
                    // de la tarjeta de la gráfica, que es como la declara §11.3. Tres tiles
                    // flotantes eran cuatro superficies donde el sistema pide una.
                    LiquidResumenVentana(celdas: [
                        .init(rotulo: String(localized: "Average"),
                              valor: String(format: "%.1f h", stat.mean)),
                        .init(rotulo: String(localized: "Range"),
                              valor: String(format: "%.1f–%.1f", stat.min, stat.max)),
                        .init(rotulo: String(localized: "Last night"),
                              valor: lastNightHrs.map { hoursOnly($0 * 60) } ?? LiquidCajita.sinDato,
                              tono: lastNightHrs != nil ? Self.tono : nil),
                    ], a11yLabel: String(localized: "History"))
                }
                .liquidTarjetaSeccion()
                LiquidLevelsList(filas: carrilesHistorial(window), tono: Self.tono)
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
            // La joya de la última noche, igual que la hoja de resumen (:1334): sin ella la
            // misma gráfica marcaba «hoy» en el resumen y no lo marcaba en el detalle. Anillo
            // hueco mientras exploras un carril, para que la joya no compita con lo explorado.
            puntoHoy: puntos.last,
            hoyAnillo: bandaExplorada != nil,
            formatoScrub: { v, f in "\(horas(v)) · \(Self.ejeFechaFmt.string(from: f))" },
            formatoValorScrub: horas,
            formatoFechaScrub: { Self.ejeFechaFmt.string(from: $0) },
            formatoFechaEje: { Self.ejeFechaFmt.string(from: $0) },
            // Los puntos se apagan SOLO cuando el usuario explora un carril (paridad `GraficaRangos`).
            atenuarFuera: bandaExplorada != nil,
            estadoVacio: String(localized: "Not enough nights yet to draw a trend."),
            a11yLabel: String(localized: "History"))
    }

    /// El carril de ANOCHE y cuántas noches del periodo cayeron con ella — el mismo contrato
    /// que `LiquidMetricSheetView.nivelesFrase`, con `LiquidFraseNivel`, la misma pieza.
    ///
    /// Sin lectura de anoche calla el nivel y dice cuántas noches tiene el rango, igual que la
    /// hoja: el nombre del carril es una afirmación sobre TU noche, y sin noche no se afirma.
    @ViewBuilder private func fraseNivelHistorial(_ window: MetricWindow) -> some View {
        let horas = model.night.map { $0.stages.asleep / 60.0 }
        let i = horas.flatMap(Self.indiceCarril)
        if let i {
            let b = Self.bandasSueno[i]
            let n = window.values.filter { v in
                (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!)
            }.count
            LiquidFraseNivel(
                nivel: b.label,
                conteo: String(localized: "\(n) of your last \(window.values.count) nights"),
                tono: Self.tono)
        } else {
            LiquidFraseNivel(
                nivel: nil,
                conteo: String(localized: "\(window.values.count) nights with data in this range"),
                tono: Self.tono,
                sinLectura: String(localized: "No reading last night"))
        }
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
        /// La clave estable del motor («short» / «adequate» / «optimal» / «extended»). Nunca
        /// se muestra: mapea color e intensidad sin depender del orden ni del idioma.
        let key: String
        let label: String
        let lo: Double?
        let hi: Double?
        let color: Color
        let range: String
    }

    /// Los carriles de duración, **derivados de la escalera del motor** — no escritos aquí.
    ///
    /// `MetricLevels.levels(for: .sleep)` son 360 / 420 / 510 minutos (< 6:00 · 6:00–7:00 ·
    /// 7:00–8:30 · ≥ 8:30), citados a Hirshkowitz 2015, y `MetricInfoCatalog` declara por
    /// escrito que la app tiene **UNA sola** escalera de sueño. Esta pantalla venía usando una
    /// propia de tres peldaños con un corte de 6.3 h que no existía en ningún otro archivo:
    /// una noche de 8.7 h era «Extenso» en la hoja de resumen y «Suficiente» aquí, a un tap.
    /// (El calendario ya cortaba en 6.0, o sea coincidía con el motor, y esta migración lo
    /// había movido a 6.3 — alineándolo al lado equivocado.) Decisión del dueño 2026-08-18:
    /// todo a la escalera del motor.
    ///
    /// El color sigue siendo de la pantalla: el motor da los cortes y el nombre, no la paleta.
    static let bandasSueno: [BandaSueno] = MetricLevels.levels(for: .sleep).map { nivel in
        BandaSueno(
            key: nivel.key,
            label: String(localized: String.LocalizationValue(MetricLevels.name(for: nivel.key))),
            lo: nivel.lower.map { $0 / 60 },
            hi: nivel.upper.map { $0 / 60 },
            color: colorCarril(nivel.key),
            range: rangoReloj(lo: nivel.lower, hi: nivel.upper))
    }

    /// El tono de cada carril. «Corto» es el único que avisa; los otros tres son grados del
    /// mismo índigo, del más lleno (tu objetivo) al más tenue.
    private static func colorCarril(_ key: String) -> Color {
        switch key {
        case "short":    return LiquidColor.atencion
        case "adequate": return LiquidColor.indigo.opacity(0.52)  // token-exempt(dato): rampa de sueño
        case "optimal":  return LiquidColor.indigo
        default:         return LiquidColor.indigo.opacity(0.72)  // token-exempt(dato): rampa de sueño
        }
    }

    /// «< 6:00» · «6:00–7:00» · «≥ 8:30» — los cortes en reloj, desde los minutos del motor.
    private static func rangoReloj(lo: Double?, hi: Double?) -> String {
        func hm(_ min: Double) -> String { horasReloj(min / 60) }
        switch (lo, hi) {
        case let (nil, .some(h)):        return "< \(hm(h))"
        case let (.some(l), nil):        return "≥ \(hm(l))"
        case let (.some(l), .some(h)):   return "\(hm(l))–\(hm(h))"
        default:                          return ""
        }
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
            // `score` ya viene en HORAS (`durationSeries` está documentada «in hours» y es
            // quien llena el heat). Dividirlo entre 60 dejaba 7.5 h en 0.125: las 90 celdas
            // caían al peldaño más pálido y la lectura decía «0:07 · Sueño corto» sobre una
            // noche de siete horas y media. Se veía en pantalla y se leyó como «faltan datos».
            let horas = dia.score
            return LiquidCalendario90.Dia(
                id: key,
                fecha: dia.date,
                intensidad: horas.map(Self.intensidadSueno),
                etiqueta: Self.ejeFechaFmt.string(from: dia.date),
                valor: horas.map(Self.horasReloj),
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

    /// Horas decimales → reloj «7:30». Nombrada (y no un `String(format:)` suelto en el
    /// call site) para que la prueba pueda fijar la unidad: el defecto que la motiva confundía
    /// horas con minutos y nadie podía verlo sin correr la app.
    static func horasReloj(_ horas: Double) -> String {
        // Clampeo como su hermano `hoursOnly`: un valor negativo imprimía «0:-30» y un
        // ±infinito hacía TRAP al convertir a Int. Hoy no es alcanzable (la serie filtra > 0),
        // pero un formateador no debe depender de que su llamador lo proteja.
        guard horas.isFinite else { return "—" }
        let total = Int((Swift.max(0, horas) * 60).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// El peldaño de la retícula. Se mapea por CLAVE, no por índice: con la escalera del motor
    /// el último carril es «extenso» (≥ 8:30), y por índice habría quedado más oscuro que
    /// «óptimo» — o sea, la retícula diría que dormir de más es mejor que dormir bien.
    /// La celda más llena es tu objetivo; «extenso» baja un escalón, no dos.
    static func intensidadSueno(_ horas: Double) -> Double {
        guard let i = indiceCarril(horas) else { return 0 }
        switch bandasSueno[i].key {
        case "optimal":  return 1.0
        case "extended": return 0.8
        case "adequate": return 0.55
        default:         return 0        // «short» — el más tenue
        }
    }

    /// La palabra del carril — la MISMA que la escalera del historial y que la hoja de resumen.
    static func sleepWord(_ horas: Double) -> String {
        guard let i = indiceCarril(horas) else { return bandasSueno.first?.label ?? "" }
        return bandasSueno[i].label
    }

    /// El carril en que cae un valor. Único predicado de la pantalla: lo usan la frase del
    /// historial, los conteos, el calendario y su lectura.
    static func indiceCarril(_ horas: Double) -> Int? {
        bandasSueno.firstIndex { b in
            (b.lo == nil || horas >= b.lo!) && (b.hi == nil || horas < b.hi!)
        }
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
        // HORAS, no minutos: el nombre viejo («mins») fue la mitad del defecto.
        var horasPorDia: [String: Double] = [:]
        for r in durationSeries { horasPorDia[r.day] = r.value }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        // Ancla la ventana de 90 dias al dia LOCAL, igual que Recovery.buildHeat. Anclar al dia UTC
        // hace que en husos negativos, por la tarde, la ventana empiece en otro dia de la semana que
        // Recovery y el grid dibuje 13 vs 14 columnas, con celdas de otro tamano.
        guard let today = Repository.parseDayKey(todayKey) else { return [] }
        return stride(from: 89, through: 0, by: -1).compactMap { off -> RecoveryDay? in
            guard let date = cal.date(byAdding: .day, value: -off, to: today) else { return nil }
            let key = Self.calDayFmt.string(from: date)
            return RecoveryDay(date: date.addingTimeInterval(12 * 3600), score: horasPorDia[key])
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
            // SIEMPRE Apple Salud. El sello decía «Medido por tu banda» cuando
            // `isAppleHealth` era falso, y eso es una MENTIRA: la app es solo-Apple y ningún
            // usuario tuvo banda nunca (axioma «cero banda»). Ese flag no distingue la
            // FUENTE, distingue si la noche trae tramos por época o se derivó del resumen
            // diario — las dos vienen de Apple Salud. (FER-102)
            LiquidOrigenChip(glyph: .luna,
                             badgeTono: Self.tono,
                             etiqueta: DataOrigin.apple.label,
                             sufijo: String(localized: "last night"))
            if let agreement = model.sourceAgreement {
                // Pieza compartida con las otras pantallas de detalle (Liquid via LiquidNotaLine).
                FusionAgreementRow(point: agreement, format: Self.sleepTotalHM)
            }
        }
        // El pie NO lleva franja (es pie, no sección), así que su padding superior se sumaba
        // al inferior de la sección de arriba: 22 + 22 + el capilar = un hueco muerto de casi
        // 60 pt donde no había nada que separar. El capilar YA hace la separación; el aire
        // solo tiene que dejarlo respirar. (Reportado por el dueño en el simulador.)
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

    private static func sleepTotalHM(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return "\(m / 60) h \(String(format: "%02d", m % 60)) m"
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
// to "Last night". It mirrors the Liquid metric-sheet language (title, lede, rows, footnote) but its
// content is a list of stages rather than a banded value, so it's its own small view, not a
// contorted `MetricInfo`. No nested `NavigationStack` (FER-171). The stage hues are the indigo
// ramp in `SleepDetailScreen.coloresEtapa` (`LiquidColor.indigo` graduado + `oro` despierto), the
// same dots the legend uses (color only in the datum).

/// «Etapas de sueño en detalle» — la hoja que abre desde el pie del método.
///
/// EN VIDRIO. Era el último trozo de papel de la pantalla, y el único con dibujo a mano:
/// spacings sueltos, `Divider`, un swatch con radio literal y tipos de la escala vieja. Tocabas
/// un enlace dentro de una pantalla de vidrio y aterrizabas en el lenguaje anterior — la
/// costura que esta migración existe para cerrar.
struct SleepStagesInfoSheet: View {
    private struct Etapa: Identifiable {
        let id = UUID()
        let etapa: LiquidHipnograma.Etapa
        let nombre: String
        let detalle: String
    }

    private var etapas: [Etapa] {
        [
            Etapa(etapa: .rem, nombre: String(localized: "REM"),
                  detalle: String(localized: "Dreams and memory. It consolidates what you learned and processes emotion.")),
            Etapa(etapa: .profundo, nombre: String(localized: "Deep"),
                  detalle: String(localized: "Physical repair. Your body restores itself and releases growth hormone.")),
            Etapa(etapa: .ligero, nombre: String(localized: "Light"),
                  detalle: String(localized: "Most of the night. A transition in which your body winds down.")),
            Etapa(etapa: .despierto, nombre: String(localized: "Awake"),
                  detalle: String(localized: "Brief awakenings. They're normal and don't mean a bad night.")),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                Text(String(localized: "Sleep stages"))
                    .font(LiquidType.tituloHoja)
                    .foregroundStyle(LiquidColor.tinta900)
                LiquidNotaLine(String(localized: "Your night moves through four phases. The watch estimates them from your movement and heart rate, so they're approximate: it gets about 2 of 3 right."),
                               tono: LiquidColor.tinta700)
                VStack(spacing: .zero) {
                    ForEach(Array(etapas.enumerated()), id: \.element.id) { i, e in
                        fila(e)
                        if i < etapas.count - 1 { LiquidCapilar(eje: .horizontal) }
                    }
                }
                .liquidTarjetaSeccion()
                LiquidNotaLine(String(localized: "Proportions, not minutes. A clinical measurement needs a sleep study."))
            }
            .padding(LiquidSpace.s550)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LiquidSheetFondo(tone: LiquidColor.indigo))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func fila(_ e: Etapa) -> some View {
        HStack(alignment: .top, spacing: LiquidSpace.s300) {
            // El swatch usa la MISMA rampa que pinta el hipnograma: si la leyenda eligiera
            // sus colores a mano, volvería a mentir sobre lo que decodifica.
            RoundedRectangle(cornerRadius: LiquidRadius.hairline * 6, style: .continuous)
                .fill(SleepDetailScreen.coloresEtapa[e.etapa] ?? LiquidColor.indigo)
                .frame(width: LiquidSpace.s250, height: LiquidSpace.s250)
                .padding(.top, LiquidSpace.s100)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LiquidSpace.s075) {
                Text(e.nombre)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta900)
                LiquidNotaLine(e.detalle)
            }
        }
        .padding(.vertical, LiquidSpace.s300)
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
