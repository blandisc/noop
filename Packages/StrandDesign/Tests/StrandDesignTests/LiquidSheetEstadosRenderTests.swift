import XCTest
import SwiftUI
@testable import StrandDesign

/// Arnés de renders de la hoja de resumen Liquid (épico hoja Liquid, gate C5 del contrato
/// docs/design-system/LIQUID-SHEET-CONTRACT.md §6): compone cada variante/estado de la
/// matriz §1 con los componentes REALES del DS y escribe un PNG por estado a
/// /tmp/noop-liquid/ para verificación visual del dueño.
/// Determinista: fechas fijas (sin Date()/Date.now), series sinusoidales fijas.
/// Run: swift test --filter LiquidSheetEstadosRenderTests
///
/// # Lo que este arnés SÍ y NO prueba
///
/// El target de tests del DS no puede importar `LiquidMetricSheetView` (vive en la capa
/// app), así que estos PNG no son la hoja: son sus componentes compuestos a mano en el
/// mismo orden. Eso los vuelve útiles solo mientras el cableado sea el MISMO que el de la
/// hoja, y una revisión encontró que se había separado en tres puntos (banda con color
/// propio, tabla de bandas donde la hoja pone filas tocables, filas sin su superficie).
/// Reglas para que no vuelva a pasar — si cambias la hoja, cambia esto:
///
/// 1. **Un solo color de banda.** `LiquidMetricSheetView` pinta TODA banda con `color:
///    tono` (:1261-1263 y :841); un semáforo de tres colores muestra discos que la app no
///    puede dibujar.
/// 2. **Las variantes con niveles usan `LiquidLevelsList`**, no `LiquidBandsTable`: esa es
///    la lista TOCABLE, con «· hoy», anillo hueco y `.isSelected`. La tabla de bandas es
///    de la variante clásica (trend de 14 días).
/// 3. **Las marcas del eje Y llevan unidad SOLO en la de arriba** (contrato D3, hoja
///    :1328-1340): el resto va en crudo.
/// 4. **Nada de valores literales que la serie no contiene** (el punto de hoy sale de
///    `puntos.last`, los conteos se DERIVAN con los mismos cortes de las bandas).
///
/// **Dynamic Type:** los fixtures `_ax` corren bajo `#if os(macOS)` con `ImageRenderer`,
/// donde las fuentes relativas a text style NO escalan. Lo único que demuestran es la rama
/// de LAYOUT que lee `dynamicTypeSize` directo (el apilado de `LiquidBandsTable`, el
/// `limiteNumeral` de la cabecera, el envoltorio 2×2 de la leyenda). El tamaño real de la
/// letra a AX solo se verifica en device o en un test de iOS.
final class LiquidSheetEstadosRenderTests: XCTestCase {

    #if os(macOS)
    @MainActor
    func test_renderEstadosHoja() throws {
        for (nombre, view) in Self.estados() {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                XCTFail("ImageRenderer no produjo imagen para \(nombre)")
                continue
            }
            XCTAssertGreaterThan(png.count, 50_000, "\(nombre): PNG sospechosamente vacío")
            let url = URL(fileURLWithPath: "/tmp/noop-liquid/hoja_\(nombre).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? png.write(to: url)
            print("WROTE \(url.path)")
        }
    }

    // MARK: - Fixtures deterministas (fechas FIJAS, jamás Date()/Date.now)

    /// Ancla fija: todas las series terminan aquí. (≈ mediados de 2025; el valor exacto
    /// no importa — importa que NUNCA cambie entre corridas.)
    private static let ancla = Date(timeIntervalSinceReferenceDate: 774_500_000)

    /// Serie diaria sinusoidal determinista que termina en `ancla`.
    private static func serieDiaria(dias: Int, base: Double, onda: Double)
        -> [(fecha: Date, valor: Double)] {
        (0..<dias).map { i in
            let fecha = ancla.addingTimeInterval(Double(i - (dias - 1)) * 86_400)
            let seno = onda * sin(Double(i) / 2.4)
            let ruido = Double((i * 11) % 7) - 3.0
            return (fecha: fecha, valor: base + seno + ruido)
        }
    }

    /// Curva FC intradía determinista: ~200 puntos cada 5 min desde la MEDIANOCHE del día
    /// del ancla (en el huso fijo). Arranca en medianoche de verdad porque el subtítulo del
    /// fixture lo afirma y el eje de reloj ahora lo enseña: antes la serie empezaba a las
    /// 8 p.m. y nadie podía verlo.
    private static func curvaFCDia() -> [(fecha: Date, valor: Double)] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = husoFijo
        let medianoche = cal.startOfDay(for: ancla)
        return (0..<200).map { i in
            let t = Double(i) / 200.0
            let base = 62.0 + 26.0 * sin(t * .pi * 3.1) * sin(t * .pi)
            let ruido = Double((i * 13) % 9) - 4.0
            return (fecha: medianoche.addingTimeInterval(Double(i) * 300.0), valor: base + ruido)
        }
    }

    // MARK: Formateadores del eje y del popup (contrato D3 — los pone el CALLER)

    /// Locale y huso FIJOS. El DS no conoce locales, así que el eje X y el popup se arman
    /// con closures del arnés; si esos closures leyeran el locale del Mac, el mismo commit
    /// escribiría PNG distintos en dos máquinas y el arnés dejaría de ser comparable.
    private static let localeFijo = Locale(identifier: "es_MX")
    private static let husoFijo = TimeZone(identifier: "America/Mexico_City")
        ?? TimeZone(secondsFromGMT: 0)!

    /// Un `DateFormatter` por PLANTILLA (jamás `dateFormat` duro), como la hoja real (L3.1).
    private static func fmt(_ plantilla: String) -> (Date) -> String {
        let f = DateFormatter()
        f.locale = localeFijo
        f.timeZone = husoFijo
        f.setLocalizedDateFormatFromTemplate(plantilla)
        return { (d: Date) -> String in f.string(from: d) }
    }

    /// Los cuatro formatos que cablea la hoja: eje diario, eje de reloj (curva FC), y las
    /// dos fechas de popup. CACHEADOS como en la hoja real (armar un `DateFormatter` por
    /// punto es caro) y aislados al main actor: los fixtures ya viven ahí, y así el
    /// harness no arrastra estado global mutable.
    @MainActor private static let ejeDia: (Date) -> String = fmt("dMMM")
    @MainActor private static let ejeHora: (Date) -> String = fmt("ha")
    @MainActor private static let popupDia: (Date) -> String = fmt("EEEdMMM")
    @MainActor private static let popupHora: (Date) -> String = fmt("jmm")

    /// Las tres bandas de VFC, TODAS en el tono de la métrica.
    ///
    /// Antes iban en tres colores (positivo/cian/atención) y por eso los renders enseñaban
    /// discos verdes y naranjas: la hoja pinta cada banda con `color: tono` y el color del
    /// disco sale de SU banda (`LiquidChartCore:633`), así que un semáforo de tres colores
    /// era un dibujo que la app no puede producir.
    private static func bandasVFC(activa: Int?) -> [LiquidChartBanda] {
        bandas([(63, nil), (48, 63), (nil, 48)], tono: LiquidColor.cian, activa: activa)
    }

    /// Bandas de un solo tono a partir de sus cortes (lo, hi), como las arma la hoja.
    private static func bandas(_ cortes: [(lo: Double?, hi: Double?)],
                               tono: Color, activa: Int?) -> [LiquidChartBanda] {
        cortes.indices.map { (i: Int) -> LiquidChartBanda in
            LiquidChartBanda(lo: cortes[i].lo, hi: cortes[i].hi,
                             color: tono, activa: activa == i)
        }
    }

    /// Cuenta las lecturas de una serie dentro de un corte semiabierto [lo, hi).
    /// Los conteos de las filas SIEMPRE se derivan: escritos a mano, la fila afirma «4
    /// noches» sobre un wash sin un solo disco dentro y el render deja de ser evidencia.
    private static func cuenta(_ puntos: [(fecha: Date, valor: Double)],
                               _ lo: Double?, _ hi: Double?) -> Int {
        puntos.reduce(0) { (n: Int, p: (fecha: Date, valor: Double)) -> Int in
            let dentro = (lo == nil || p.valor >= lo!) && (hi == nil || p.valor < hi!)
            return n + (dentro ? 1 : 0)
        }
    }

    /// El plural lo resuelve el caller (en la app, `BandSummaryCopy.countLabel` con la
    /// variación del catálogo): «1 noches» delataría un fixture que no pasó por ahí.
    private static func noches(_ n: Int) -> String { "\(n) " + (n == 1 ? "noche" : "noches") }
    private static func dias(_ n: Int) -> String { "\(n) " + (n == 1 ? "día" : "días") }

    /// Columna de hoja: mismo lienzo para todas las variantes (ancho iPhone 402,
    /// fondo `LiquidSheetFondo` con el suspiro del tono, motion congelado).
    private static func columna<Content: View>(tone: Color,
                                               @ViewBuilder _ content: () -> Content) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: LiquidSpace.s400, content: content)
                .padding(LiquidSpace.s550)
                .frame(width: 402, alignment: .topLeading)
                .background(LiquidSheetFondo(tone: tone))
                .environment(\.liquidMotionDisabled, true)
        )
    }

    // MARK: - Matriz de estados (contrato §1)

    @MainActor
    private static func estados() -> [(String, AnyView)] {
        [
            ("vital_dato", vitalConDato()),
            ("vital_sindato", vitalSinDato()),
            ("recovery", recovery()),
            ("sleep_rica", sleepRica()),
            ("sleep_rica_ax", sleepRica(tamano: .accessibility3)),
            ("sleep_skeleton", sleepSkeleton()),
            ("sleep_sinnoche", sleepSinNoche()),
            ("sleep_sindato", sleepSinDato()),
            ("recovery_calibrando", recoveryCalibrando()),
            ("vital_spo2", vitalSpO2()),
            ("sleep_sin_ventana", sleepSinVentana()),
            ("niveles_reposo_filas", nivelesReposoConFilas()),
            ("niveles_explorando", nivelesExplorando()),
            ("niveles_ventana_vacia", nivelesVentanaVacia()),
            ("niveles_cargando", nivelesCargando()),
            ("charts_cargando_vacio", chartsCargandoVacio()),
            ("sleep_performance", sleepPerformance()),
            ("strain", strain()),
            ("heart_rate", heartRate()),
            ("clasica", clasica()),
            ("hrv_sinbase", hrvSinBase()),
            // Densidad de los discos por dato (carril A2): la ventana «M» los recupera y la
            // serie apiñada los cede. Es la evidencia visual que el test de motor
            // (`LiquidChartMotorTests`) sólo puede afirmar en números.
            ("niveles_densidad", nivelesDensidad()),
            // Una sola lectura (carril E2): la pantalla cae al pozo vacío — y ahora la voz
            // dice lo mismo (`LiquidCarrilEA11yTests`).
            ("niveles_una_lectura", nivelesUnaLectura()),
            // Acta del veredicto («Cómo llegué a esto»): los estados de su tabla.
            ("acta_verde", acta(LiquidActaFixtures.verde)),
            ("acta_ambar", acta(LiquidActaFixtures.ambar)),
            ("acta_rojo", acta(LiquidActaFixtures.rojo)),
            // Histéresis activa: el acta de HOY (1 fuera) NO cuadra con el veredicto
            // MOSTRADO (verde, porque el crudo nuevo todavía no se repite 2 días). Sin el
            // aviso, la hoja se contradice sola — por eso el estado tiene su propio PNG.
            ("acta_histeresis", acta(LiquidActaFixtures.histeresis)),
            // Empujón de tendencia: MISMA forma (1 fuera, veredicto que no cuadra), OTRA
            // causa. Los dos avisos tienen precedencia: nunca se pintan juntos.
            ("acta_tendencia", acta(LiquidActaFixtures.tendencia)),
            ("acta_lectura_dia", acta(LiquidActaFixtures.lecturaDeDia)),
            ("acta_sin_veredicto", acta(LiquidActaFixtures.sinVeredicto)),
            // Gate «cero color sin veredicto» con un eje FUERA (Grok r1): joya fuera de
            // banda en tinta, sin wash — la clase de defecto que los fixtures «quietos»
            // no podían atrapar.
            ("acta_lectura_dia_fuera", acta(LiquidActaFixtures.lecturaDeDiaFuera)),
            ("acta_sin_permiso", acta(LiquidActaFixtures.sinPermiso)),
            // AX5: las filas del acta se apilan en dos renglones en vez de aplastar cuatro
            // columnas de texto.
            ("acta_ambar_ax5", acta(LiquidActaFixtures.ambar, tamano: .accessibility5)),
        ]
    }

    /// El acta se renderiza SUELTA (ya trae su propio ritmo de bloques s550): solo ancho de
    /// hoja, margen y fondo del tono — exactamente lo que le pone `LiquidMetricSheet`.
    @MainActor
    private static func acta(_ model: LiquidActa,
                             tamano: DynamicTypeSize = .large) -> AnyView {
        AnyView(
            LiquidActaVeredicto(model, onVerMas: {})
                .padding(LiquidSpace.s550)
                .frame(width: 402, alignment: .topLeading)
                .background(LiquidSheetFondo(tone: model.tono))
                .environment(\.dynamicTypeSize, tamano)
                .environment(\.liquidMotionDisabled, true)
        )
    }

    /// §1.2 · Vital-template con dato: VFC 56 ms, selector + explorador de niveles con la
    /// banda media activa, filas de nivel, patrón, método y «Ver más» ancho completo.
    /// Es el fixture COMPLETO del bloque de niveles: mismo orden que `levelsBlock` de la
    /// hoja real (selector → frase → gráfica), con eje X de fechas, puntos por dato y el
    /// popup de DOS líneas del scrub.
    @MainActor
    private static func vitalConDato() -> AnyView {
        let puntos = serieDiaria(dias: 28, base: 58, onda: 13)
        // Los cortes de las bandas y los de las filas son LOS MISMOS objetos de verdad
        // (≥ 71 · 49–71 · < 49) y los conteos salen de la serie.
        let cortes: [(lo: Double?, hi: Double?)] = [(71, nil), (49, 71), (nil, 49)]
        var grafica = LiquidGraficaNiveles(
            puntos: puntos,
            bandas: bandas(cortes, tono: LiquidColor.cian, activa: 1),
            dominio: 30...95,
            // D3 · la unidad va SOLO en la marca de arriba (la hoja: `scrubValor` en el
            // último tick, `levelsValueFormat` en el resto).
            ticksY: [(71, "71 ms"), (49, "49")], tono: LiquidColor.cian,
            puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
            hoyAnillo: false,
            // La frase COMPUESTA es lo que lee VoiceOver (el DS no acuña el « · »).
            formatoScrub: { (v: Double, f: Date) in "\(Int(v)) ms · \(popupDia(f))" },
            formatoValorScrub: { (v: Double) in "\(Int(v)) ms" },
            formatoFechaScrub: popupDia,
            formatoFechaEje: ejeDia,
            estadoVacio: "Sin lecturas en este rango.",
            a11yLabel: "VFC, últimos 28 días")
        grafica.scrubFijo = 9
        return columna(tone: LiquidColor.cian) {
            LiquidSheetHeader(
                icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                numeral: "56", unidad: "ms",
                origenEtiqueta: "Apple Salud · anoche",
                explicacion: "La variación entre latidos mientras duermes — tu señal más temprana de recuperación.",
                infoMostrar: "Mostrar explicación",
                infoOcultar: "Ocultar explicación")
            LiquidReadingLine("Tu VFC amaneció en tu rango.",
                              highlight: "en tu rango",
                              highlightTone: LiquidColor.verdeProfundo)
            LiquidRangeSelector(opciones: ["S", "M", "3M", "6M", "1A", "TODO"],
                                seleccion: .constant(1))
            // La frase display del nivel destacado (L2), en su sitio canónico: entre el
            // selector y la gráfica.
            LiquidFraseNivel(
                nivel: "En tu base",
                conteo: "\(cuenta(puntos, 49, 71)) de tus últimos \(puntos.count) días",
                tono: LiquidColor.cian)
            grafica
            // La variante VITAL lista sus carriles con las filas TOCABLES dentro de su
            // superficie (`LiquidLevelsList`, lo que dibuja `nivelesLista` en la hoja), no
            // con la tabla de bandas de la variante clásica: aquí viven el rótulo «· hoy»,
            // el punto de anillo y el trait `.isSelected`.
            LiquidLevelsList(
                filas: [
                    .init(etiqueta: "Alto", rango: "≥ 71",
                          conteo: dias(cuenta(puntos, 71, nil)),
                          a11yHint: "Resalta este nivel en la gráfica"),
                    .init(etiqueta: "En tu base", rango: "49–71",
                          conteo: dias(cuenta(puntos, 49, 71)),
                          esHoy: true, activa: true, hoyEtiqueta: "· hoy",
                          a11yHint: "Resalta este nivel en la gráfica"),
                    .init(etiqueta: "Bajo", rango: "< 49",
                          conteo: dias(cuenta(puntos, nil, 49)),
                          a11yHint: "Resalta este nivel en la gráfica"),
                ],
                tono: LiquidColor.cian)
            LiquidPatternBlock(
                overline: "Tu patrón",
                lineas: [
                    "Tus noches con alcohol bajan tu VFC al día siguiente.",
                    "Dormir 7 h o más sube tu base a la mañana.",
                ],
                tono: LiquidColor.cian)
            // B6 · el plegable trae SUS propias etiquetas de VoiceOver: con las del ⓘ
            // («Mostrar explicación») la hoja anunciaría dos botones idénticos.
            LiquidMetodo(title: "Cómo se calcula",
                         mostrar: "Ver cómo se calcula",
                         ocultar: "Ocultar cómo se calcula") {
                LiquidNotaLine("SDNN sobre los latidos nocturnos, comparado contra tu base de 21 noches (Task Force, 1996).")
            }
            LiquidVerMas(title: "Ver más en Tendencias", hint: "Abre el detalle completo",
                         tone: LiquidColor.cian, anchoCompleto: true, action: {})
        }
    }

    /// §1.2 · Vital sin dato: FC en reposo «—», nota honesta, SIN gráfica.
    @MainActor
    private static func vitalSinDato() -> AnyView {
        columna(tone: LiquidColor.rosa) {
            LiquidSheetHeader(
                icono: .corazon, titulo: "FC EN REPOSO", tono: LiquidColor.rosa,
                numeral: "—",
                explicacion: "Tu pulso más bajo mientras duermes — baja cuando tu base aeróbica mejora.")
            LiquidNotaLine("Sin lectura anoche. Duerme con tu Apple Watch para ver tu pulso en reposo aquí.")
            LiquidMetodo(title: "Cómo se calcula") {
                LiquidNotaLine("El promedio de tus pulsaciones en el sueño profundo de la noche.")
            }
            LiquidVerMas(title: "Ver más", hint: "Abre el detalle completo",
                         tone: LiquidColor.rosa, action: {})
        }
    }

    /// §1.1 · Recovery con dato: header sin glifo, 78/100 calculado, medidor de zonas
    /// con el tick al 62 %.
    @MainActor
    private static func recovery() -> AnyView {
        columna(tone: LiquidColor.verdePrimario) {
            LiquidSheetHeader(
                icono: nil, titulo: "RECUPERACIÓN", tono: LiquidColor.verdePrimario,
                numeral: "78", sufijo: "/ 100",
                numeralTono: LiquidColor.verdeProfundo, origen: .calculadoEnTelefono,
                origenEtiqueta: "Calculado",
                explicacion: "Qué tan listo amaneció tu cuerpo para el esfuerzo de hoy.")
            LiquidReadingLine("Tu cuerpo amaneció listo para empujar.",
                              highlight: "listo",
                              highlightTone: LiquidColor.verdeProfundo)
            // Las 5 zonas CANÓNICAS de recovery (25/25/20/18/12, matriz §1.1 — QA D3);
            // 78/100 cae en ALTO (25+25+20=70 … 88).
            LiquidZoneMeter(segmentos: [
                .init(peso: 25, color: LiquidColor.negativo, activa: false, etiqueta: "AGOTADO"),
                .init(peso: 25, color: LiquidColor.atencion, activa: false, etiqueta: "BAJO"),
                .init(peso: 20, color: LiquidColor.ambar, activa: false, etiqueta: "MODERADO"),
                .init(peso: 18, color: LiquidColor.positivo, activa: true, etiqueta: "ALTO"),
                .init(peso: 12, color: LiquidColor.verdeProfundo, activa: false, etiqueta: "PLENO"),
            ], fraccion: 0.78)
            LiquidMetodo(title: "Cómo se calcula") {
                LiquidNotaLine("VFC, pulso en reposo y sueño de anoche, comparados contra tu propia base.")
            }
            LiquidVerMas(title: "Ver más en Tendencias", hint: "Abre el detalle completo",
                         tone: LiquidColor.verdePrimario, anchoCompleto: true, action: {})
        }
    }

    /// §1.3 · Sueño rica: doble dato 7:12 | 84 con el ⓘ de regularidad (L5.2), etapas de la
    /// noche. La pastilla `LiquidLaneLabel` está RETIRADA (L3.3): la
    /// frase display de los niveles ya dice el carril en grande.
    ///
    /// Las etapas CUADRAN con el numeral: 91 + 104 + 237 = 432 min dormido = 7:12, + 47
    /// despierto = 479 en cama = 23:38 → 7:37. Un fixture que se contradice a sí mismo no
    /// sirve para verificar nada.
    @MainActor
    private static func sleepRica(tamano: DynamicTypeSize = .large) -> AnyView {
        AnyView(columna(tone: LiquidColor.indigo) {
            LiquidSheetHeader(
                icono: .luna, titulo: "SUEÑO", tono: LiquidColor.indigo,
                numeral: nil,
                // B1 · la variante rica pasa `numeral: nil`, y con la procedencia atrapada
                // dentro de la fila del dato la hoja NO decía de dónde salía la noche
                // mientras VoiceOver sí lo anunciaba. El fixture la pasa porque la hoja
                // real la pasa (`origenApple`), o el render no podría desmentir nada.
                origenEtiqueta: "Apple Salud",
                explicacion: "Cuánto y qué tan parejo dormiste anoche.",
                infoMostrar: "Mostrar explicación",
                infoOcultar: "Ocultar explicación")
            LiquidDobleDato(
                principal: (valor: "7:12", etiqueta: "horas dormidas"),
                secundario: (valor: "84", etiqueta: "regularidad"),
                tono: LiquidColor.indigo,
                secundarioInfo: "Qué tan parejo es tu horario de sueño: tomamos el centro de cada noche (entre dormirte y despertar) y medimos cuánto brinca de noche a noche. Menos brincos, más cerca de 100.",
                infoMostrar: "Mostrar explicación",
                infoOcultar: "Ocultar explicación")
            LiquidReadingLine("Dormiste dentro de tu rango óptimo.",
                              highlight: "rango óptimo",
                              highlightTone: LiquidColor.indigo)
            LiquidStageBar(
                etapas: [
                    .init(minutos: 91, color: LiquidColor.indigo,
                          etiqueta: "Profundo", duracion: "1:31"),
                    .init(minutos: 104, color: LiquidColor.indigo.opacity(0.78), // token-exempt: rampa graduada de etapas
                          etiqueta: "REM", duracion: "1:44"),
                    .init(minutos: 237, color: LiquidColor.indigo.opacity(0.52), // token-exempt: rampa graduada de etapas
                          etiqueta: "Ligero", duracion: "3:57"),
                    .init(minutos: 47, color: LiquidColor.oro,   // igual que el app
                          etiqueta: "Despierto", duracion: "0:47"),
                ],
                overline: "Anoche",
                ventana: "23:38 → 7:37")
            // «Para esta noche» retirado por el dueño (/inject): el arnés debe reflejar
            // la hoja REAL, no la anterior.
        }
        .environment(\.dynamicTypeSize, tamano))
    }

    /// §1.3 · Sueño con la noche del FALLBACK DIARIO de Apple (B7/D10): `startTs == endTs`
    /// ⇒ sin ventana que afirmar, y `awake == 0` por construcción ⇒ sin etapa «Despierto».
    /// Ni «6:00 → 6:00» ni «DESPIERTO 0:00»: los tres segmentos medidos reparten la barra
    /// completa (y se comen el gap fantasma del segmento de ancho 0).
    @MainActor
    private static func sleepSinVentana() -> AnyView {
        columna(tone: LiquidColor.indigo) {
            LiquidSheetHeader(
                icono: .luna, titulo: "SUEÑO", tono: LiquidColor.indigo,
                numeral: nil, origenEtiqueta: "Apple Salud",
                explicacion: "Cuánto y qué tan parejo dormiste anoche.",
                infoMostrar: "Mostrar explicación",
                infoOcultar: "Ocultar explicación")
            LiquidDobleDato(
                principal: (valor: "6:45", etiqueta: "horas dormidas"),
                secundario: (valor: "71", etiqueta: "regularidad"),
                tono: LiquidColor.indigo)
            LiquidStageBar(
                etapas: [
                    .init(minutos: 84, color: LiquidColor.indigo,
                          etiqueta: "Profundo", duracion: "1:24"),
                    .init(minutos: 96, color: LiquidColor.indigo.opacity(0.78), // token-exempt: rampa graduada de etapas
                          etiqueta: "REM", duracion: "1:36"),
                    .init(minutos: 225, color: LiquidColor.indigo.opacity(0.52), // token-exempt: rampa graduada de etapas
                          etiqueta: "Ligero", duracion: "3:45"),
                    .init(minutos: 0, color: LiquidColor.oro,
                          etiqueta: "Despierto", duracion: "0:00"),
                ],
                overline: "Anoche")
        }
    }

    /// §1.3 · Sueño cargando async: el skeleton NUEVO de F5 bajo el header de sueño.
    @MainActor
    private static func sleepSkeleton() -> AnyView {
        columna(tone: LiquidColor.indigo) {
            LiquidSheetHeader(
                icono: .luna, titulo: "SUEÑO", tono: LiquidColor.indigo,
                numeral: nil)
            LiquidSheetSkeleton(a11yCargando: "Cargando tu noche")
        }
    }

    /// §1.4 · Strain con dato: 10.0 / 21 calculado + explorador de niveles con la banda
    /// moderada activa.
    @MainActor
    private static func strain() -> AnyView {
        let puntos = serieDiaria(dias: 28, base: 10.5, onda: 4).map {
            (fecha: $0.fecha, valor: min(max($0.valor, 1), 20))
        }
        var grafica = LiquidGraficaNiveles(
            puntos: puntos,
            bandas: bandas([(14, nil), (8, 14), (nil, 8)],
                           tono: LiquidColor.ambar, activa: 1),
            dominio: 0...21,
            ticksY: [(14, "14"), (8, "8")], tono: LiquidColor.ambar,
            puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
            hoyAnillo: false,
            formatoScrub: { (v: Double, f: Date) in
                String(format: "%.1f", v) + " · " + popupDia(f)
            },
            formatoValorScrub: { (v: Double) in String(format: "%.1f", v) },
            formatoFechaScrub: popupDia,
            formatoFechaEje: ejeDia,
            estadoVacio: "Sin días en este rango.",
            a11yLabel: "Esfuerzo, últimos 28 días")
        grafica.scrubFijo = 14
        return columna(tone: LiquidColor.ambar) {
            LiquidSheetHeader(
                icono: .llama, titulo: "ESFUERZO", tono: LiquidColor.ambar,
                numeral: "10.0", sufijo: "/ 21", origen: .calculadoEnTelefono,
                // El punto de origen y su palabra viajan SIEMPRE juntos (la hoja los
                // empareja en :447-449). Sin la etiqueta salía un bullet huérfano colgando
                // detrás de «/ 21» — hoy el componente ya no lo dibuja, y el fixture
                // tampoco lo pide.
                origenEtiqueta: "Calculado",
                explicacion: "Cuánta carga cardiovascular llevas acumulada hoy.")
            LiquidReadingLine("Esfuerzo moderado hasta ahora — hay espacio para más.",
                              highlight: "moderado",
                              highlightTone: LiquidColor.atencionTexto)
            grafica
            LiquidMetodo(title: "Cómo se calcula") {
                LiquidNotaLine("Zonas de pulso ponderadas sobre el día (Edwards/Banister).")
            }
            LiquidVerMas(title: "Ver más en Tendencias", hint: "Abre el detalle completo",
                         tone: LiquidColor.ambar, anchoCompleto: true, action: {})
        }
    }

    /// §1.6 · heart_rate: curva 24h con ~200 puntos deterministas + stats min/prom/max,
    /// ahora con eje de RELOJ y ticks Y (L3.4). El eje se reparte por TIEMPO real, no por
    /// índice: los buckets de 5 min sin muestras no existen en la serie.
    @MainActor
    private static func heartRate() -> AnyView {
        var curva = LiquidCurvaFC(
            titulo: "Pulsaciones por minuto",
            subtitulo: "Promedio de 5 min · desde medianoche",
            // Numeral, stats y ticks salen de la serie de verdad (mín 32 · prom 62 · máx 82,
            // último 62): con los valores decorativos de antes el dominio 40…105 recortaba
            // el valle y el popup del scrub cantaba «33 lpm» bajo un «MÍN 48».
            ultimo: "62 lpm",
            puntos: curvaFCDia(),
            dominio: 26...88,
            stats: (min: "32", prom: "62", max: "82"),
            statsEtiquetas: (min: "Mín", prom: "Prom", max: "Máx"),
            // Tres marcas sobre los DATOS (mín · prom · máx), como las cablea la hoja: los
            // bordes del dominio son puro respiro y etiquetarlos imprimiría valores que
            // nunca ocurrieron — además el de abajo caería sobre la fila de fechas.
            ticksY: [(82, "82"), (62, "62"), (32, "32")],
            formatoScrub: { (v: Double, f: Date) in "\(Int(v)) lpm · \(popupHora(f))" },
            formatoValorScrub: { (v: Double) in "\(Int(v)) lpm" },
            formatoFechaScrub: popupHora,
            formatoFechaEje: ejeHora,
            estado: .datos,
            a11yLabel: "Frecuencia cardiaca de hoy")
        curva.scrubFijo = 90
        return columna(tone: LiquidColor.rosa) {
            LiquidSheetHeader(
                icono: .corazon, titulo: "FRECUENCIA CARDIACA", tono: LiquidColor.rosa,
                numeral: nil,
                explicacion: "Tu pulso a lo largo del día, en promedios de 5 minutos.")
            curva
        }
    }

    /// §1.5 · Clásica PURA (VO₂máx: sin niveles, sin calibración — la calibración es de
    /// recovery, QA F5-D1): headline + trend 14d con readout + tabla de bandas.
    @MainActor
    private static func clasica() -> AnyView {
        let puntos = serieDiaria(dias: 14, base: 7.1, onda: 0.9).map {
            (fecha: $0.fecha, valor: min(max($0.valor / 1.0, 5.2), 9.6))
        }
        var trend = LiquidTrendChart(
            titulo: "Últimos 14 días",
            // El readout nombra la banda ACTIVA (Óptimo), la misma de la fila activa:
            // el código real deriva ambos del mismo índice, el fixture debe respetarlo.
            readout: (etiqueta: "Óptimo", tono: LiquidColor.indigo,
                      frase: "9 de las últimas 14 noches en este rango"),
            puntos: puntos,
            bandas: bandas([(7, 9), (6, 7), (nil, 6)],
                           tono: LiquidColor.indigo, activa: 0),
            dominio: 5...10,
            // El eje habla como el popup («9.6 h»): la unidad, en la marca de arriba.
            ticksY: [(9, "9 h"), (7, "7"), (6, "6")],
            tono: LiquidColor.indigo,
            formatoScrub: { (v: Double, f: Date) in
                String(format: "%.1f h", v) + " · " + popupDia(f)
            },
            formatoValorScrub: { (v: Double) in String(format: "%.1f h", v) },
            formatoFechaScrub: popupDia,
            formatoFechaEje: ejeDia,
            estado: .datos,
            a11yLabel: "Sueño, últimos 14 días")
        trend.scrubFijo = 5
        return columna(tone: LiquidColor.indigo) {
            LiquidSheetHeader(
                icono: .luna, titulo: "HORAS DE SUEÑO", tono: LiquidColor.indigo,
                numeral: "7:12", origenEtiqueta: "Apple Salud · anoche",
                explicacion: "Cuánto dormiste anoche, contra tu rango de referencia.",
                infoMostrar: "Mostrar explicación",
                infoOcultar: "Ocultar explicación")
            // Auto-widen (L6): la nota AVISA que la ventana no es la que pediste, así que
            // va en `atencionTexto`, no en la tinta quieta del resto de las notas.
            LiquidNotaLine("Mostrando los últimos 14 días", tono: LiquidColor.atencionTexto)
            trend
            LiquidBandsTable(
                filas: [
                    .init(etiqueta: "Óptimo", rango: "7–9 h", conteo: "9 noches", activa: true),
                    .init(etiqueta: "Adecuado", rango: "6–7 h", conteo: "3 noches"),
                    .init(etiqueta: "Corto", rango: "5–6 h", conteo: "2 noches"),
                    .init(etiqueta: "Muy corto", rango: "< 5 h", conteo: "0 noches"),
                ],
                tono: LiquidColor.indigo)
        }
    }

    /// §1.1 · Recovery CALIBRANDO: numeral «—» + tarjeta de calibración (el único lugar
    /// donde la calibración existe — QA F5-D1).
    @MainActor
    private static func recoveryCalibrando() -> AnyView {
        columna(tone: LiquidColor.verdePrimario) {
            LiquidSheetHeader(
                icono: nil, titulo: "RECUPERACIÓN", tono: LiquidColor.verdePrimario,
                numeral: "—", origen: .calculadoEnTelefono, origenEtiqueta: "Calculado",
                explicacion: "Qué tan listo amaneció tu cuerpo.")
            LiquidCalibracionCard(titulo: "Calibrando tu base",
                                  leyenda: "2 de 4 noches",
                                  hechas: 2, necesarias: 4,
                                  tono: LiquidColor.verdePrimario)
            // L6 · con CERO noches el riel sigue mostrando el nub mínimo de 6 pt (paridad
            // de la tarjeta vieja): la barra vacía del todo se leía como componente roto.
            LiquidCalibracionCard(titulo: "Calibrando tu base",
                                  leyenda: "0 de 7 noches",
                                  hechas: 0, necesarias: 7,
                                  tono: LiquidColor.verdePrimario)
        }
    }

    /// §1.3 · Sueño SIN NOCHE (fallback clásico): numeral único + gráfica de niveles,
    /// SIN doble dato ni etapas (QA F5-D1).
    @MainActor
    private static func sleepSinNoche() -> AnyView {
        let puntos = serieDiaria(dias: 21, base: 430, onda: 40)
        var grafica = LiquidGraficaNiveles(
            puntos: puntos.map { (fecha: $0.fecha, valor: $0.valor) },
            bandas: bandas([(420, 540), (360, 420), (nil, 360)],
                           tono: LiquidColor.indigo, activa: 0),
            dominio: 320...560,
            // Sueño se dice en RELOJ, como el numeral de la hoja («7:12»), no en «7 h 12
            // min»: `levelsValueFormat` del caller real formatea `%d:%02d`.
            ticksY: [(540, "9:00"), (420, "7:00"), (360, "6:00")],
            tono: LiquidColor.indigo,
            puntoHoy: nil, hoyAnillo: false,
            formatoScrub: { (v: Double, f: Date) in
                let m = Int(v.rounded())
                return String(format: "%d:%02d", m / 60, m % 60) + " · " + popupDia(f)
            },
            formatoValorScrub: { (v: Double) in
                let m = Int(v.rounded()); return String(format: "%d:%02d", m / 60, m % 60)
            },
            formatoFechaScrub: popupDia,
            formatoFechaEje: ejeDia,
            estadoVacio: "Sin lecturas en este rango",
            a11yLabel: "Sueño por noche")
        grafica.scrubFijo = nil
        return columna(tone: LiquidColor.indigo) {
            LiquidSheetHeader(
                icono: .luna, titulo: "SUEÑO", tono: LiquidColor.indigo,
                numeral: "7:12", origenEtiqueta: "Apple Salud",
                explicacion: "Cuánto dormiste, contra tu rango de referencia.")
            LiquidNotaLine("Sin noche con etapas anoche: el resumen muestra tus horas contra tu rango.")
            grafica
        }
    }

    /// §1.3 · Sueño SIN DATO: «—» neutro, nota honesta (QA F5-D1).
    @MainActor
    private static func sleepSinDato() -> AnyView {
        columna(tone: LiquidColor.indigo) {
            LiquidSheetHeader(
                icono: .luna, titulo: "SUEÑO", tono: LiquidColor.indigo,
                numeral: "—",
                explicacion: "Cuánto y qué tan parejo dormiste anoche.")
            LiquidNotaLine("Duerme con tu Apple Watch para ver tu noche aquí.")
        }
    }

    /// §1.7 · SpO₂ (vital + niveles .bloodOxygen — QA F4-D2/C5): sin entry point vivo,
    /// verificable solo por arnés (decisión D2 del revote).
    @MainActor
    private static func vitalSpO2() -> AnyView {
        let puntos = serieDiaria(dias: 28, base: 97.2, onda: 0.9).map {
            (fecha: $0.fecha, valor: min(max($0.valor, 94.5), 99.4))
        }
        var grafica = LiquidGraficaNiveles(
            puntos: puntos,
            bandas: bandas([(95, nil), (90, 95), (nil, 90)],
                           tono: LiquidColor.azul, activa: 0),
            dominio: 88...100,
            ticksY: [(98, "98 %"), (95, "95"), (90, "90")],
            tono: LiquidColor.azul,
            // El punto de hoy sale de la SERIE. Con el 97.0 literal de antes, el anillo de
            // «hoy» flotaba ~6 pt encima del disco real del último dato: dos marcadores
            // encimados en la misma x.
            puntoHoy: puntos[puntos.count - 1],
            hoyAnillo: false,
            formatoScrub: { (v: Double, f: Date) in
                String(format: "%.0f %% · ", v) + popupDia(f)
            },
            formatoValorScrub: { (v: Double) in String(format: "%.0f %%", v) },
            formatoFechaScrub: popupDia,
            formatoFechaEje: ejeDia,
            estadoVacio: "Sin lecturas en este rango",
            a11yLabel: "Oxígeno en sangre")
        grafica.scrubFijo = 20
        return columna(tone: LiquidColor.azul) {
            LiquidSheetHeader(
                icono: .resp, titulo: "SPO₂", tono: LiquidColor.azul,
                numeral: "97", unidad: "%",
                origenEtiqueta: "Apple Salud · anoche",
                explicacion: "Cuánto oxígeno lleva tu sangre mientras duermes.")
            LiquidReadingLine("Tu oxígeno se mantuvo en rango normal.",
                              highlight: "rango normal",
                              highlightTone: LiquidColor.azul)
            grafica
        }
    }

    /// §6-F3b · Niveles SIN lectura hoy (todas las bandas al reposo 8 %) + las filas
    /// tocables (`LiquidLevelsList`, QA F3b-D1: el arnés no las renderizaba).
    @MainActor
    private static func nivelesReposoConFilas() -> AnyView {
        // Amplitud suficiente para que los tres carriles TENGAN lecturas: con la anterior
        // (55 ± 6) la banda iluminada «< 48» quedaba sin un solo disco dentro de su wash
        // mientras su fila afirmaba «4 noches».
        let puntos = serieDiaria(dias: 28, base: 53, onda: 11)
        let grafica = LiquidGraficaNiveles(
            puntos: puntos,
            // I1: la banda iluminada es la de la fila ACTIVA de abajo — «Debajo de tu
            // base» (índice 2), que es el nivel que el usuario está explorando. Si no
            // coinciden, el render desmiente al invariante.
            bandas: bandasVFC(activa: 2),
            dominio: 34...72,
            ticksY: [(63, "63 ms"), (48, "48")],
            tono: LiquidColor.cian,
            puntoHoy: nil, hoyAnillo: false,
            formatoScrub: { (v: Double, f: Date) in "\(Int(v.rounded())) ms · \(popupDia(f))" },
            formatoValorScrub: { (v: Double) in "\(Int(v.rounded())) ms" },
            formatoFechaScrub: popupDia,
            formatoFechaEje: ejeDia,
            estadoVacio: "Sin lecturas en este rango",
            a11yLabel: "VFC por noche")
        return columna(tone: LiquidColor.cian) {
            LiquidSheetHeader(
                icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                numeral: "—",
                explicacion: "La variación entre latidos mientras duermes.")
            // Rama SIN lectura de `LiquidFraseNivel`: el texto honesto del caller en
            // tinta/500 (el DS jamás lo acuña), con el conteo debajo.
            LiquidFraseNivel(nivel: nil,
                             conteo: "\(puntos.count) noches con datos en este rango",
                             tono: LiquidColor.cian,
                             sinLectura: "Hoy sin lectura")
            grafica
            // NINGUNA fila lleva «· hoy»: el titular dice «Hoy sin lectura» y en la hoja
            // `esHoy` es `i == d.activeIndex`, que sin lectura de hoy es falso en todas.
            // La pantalla se contradecía a sí misma («Hoy sin lectura» arriba, «En tu base
            // · hoy» con anillo una fila abajo).
            LiquidLevelsList(
                filas: [
                    .init(etiqueta: "Arriba de tu base", rango: "> 63",
                          conteo: noches(cuenta(puntos, 63, nil)),
                          a11yHint: "Resalta este nivel en la gráfica"),
                    .init(etiqueta: "En tu base", rango: "48–63",
                          conteo: noches(cuenta(puntos, 48, 63)),
                          a11yHint: "Resalta este nivel en la gráfica"),
                    .init(etiqueta: "Debajo de tu base", rango: "< 48",
                          conteo: noches(cuenta(puntos, nil, 48)),
                          activa: true,
                          a11yHint: "Resalta este nivel en la gráfica"),
                ],
                tono: LiquidColor.cian)
        }
    }

    /// §6-F3b (A4 · D12) · EXPLORANDO un carril: el usuario tocó la fila «Arriba de tu
    /// base», que no es la de hoy. Es el único estado donde los puntos se apagan fuera de
    /// la banda iluminada (`atenuarFuera`) — en reposo van todos a tono pleno y la banda
    /// activa se dice sola con su wash — y donde «hoy» conserva su anillo HUECO para no
    /// perderse mientras se mira otro nivel.
    @MainActor
    private static func nivelesExplorando() -> AnyView {
        let puntos = serieDiaria(dias: 21, base: 58, onda: 13)
        // Los conteos se DERIVAN de la serie (mismos cortes que `bandasVFC`: > 63 · 48–63 ·
        // < 48). Escritos a mano, la fila afirmaría «5 noches» mientras el ojo cuenta ocho
        // bolitas encendidas dentro del wash — el render dejaría de ser evidencia.
        let nArriba = cuenta(puntos, 63, nil)
        let nBase = cuenta(puntos, 48, 63)
        let nAbajo = cuenta(puntos, nil, 48)
        let grafica = LiquidGraficaNiveles(
            puntos: puntos,
            bandas: bandasVFC(activa: 0),
            dominio: 30...95,
            ticksY: [(63, "63 ms"), (48, "48")],
            tono: LiquidColor.cian,
            puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
            hoyAnillo: true,
            formatoScrub: { (v: Double, f: Date) in "\(Int(v.rounded())) ms · \(popupDia(f))" },
            formatoValorScrub: { (v: Double) in "\(Int(v.rounded())) ms" },
            formatoFechaScrub: popupDia,
            formatoFechaEje: ejeDia,
            atenuarFuera: true,
            estadoVacio: "Sin lecturas en este rango",
            a11yLabel: "VFC por noche")
        return columna(tone: LiquidColor.cian) {
            LiquidSheetHeader(
                icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                numeral: "56", unidad: "ms",
                origenEtiqueta: "Apple Salud · anoche")
            // La frase re-lee el nivel EXPLORADO, no el de hoy (paridad NIV-03).
            LiquidFraseNivel(nivel: "Arriba de tu base",
                             conteo: "\(nArriba) de tus últimas \(puntos.count) noches",
                             tono: LiquidColor.cian)
            grafica
            LiquidLevelsList(
                filas: [
                    .init(etiqueta: "Arriba de tu base", rango: "> 63",
                          conteo: noches(nArriba), activa: true,
                          a11yHint: "Resalta este nivel en la gráfica"),
                    // Hoy cayó aquí mientras exploras otro nivel: anillo hueco + «· hoy».
                    .init(etiqueta: "En tu base", rango: "48–63", conteo: noches(nBase),
                          esHoy: true, hoyEtiqueta: "· hoy",
                          a11yHint: "Resalta este nivel en la gráfica"),
                    .init(etiqueta: "Debajo de tu base", rango: "< 48",
                          conteo: noches(nAbajo),
                          a11yHint: "Resalta este nivel en la gráfica"),
                ],
                tono: LiquidColor.cian)
        }
    }

    /// §6-F3b (D7) · El explorador CARGANDO: mientras la serie viaja, el esqueleto del
    /// mismo alto — no el pozo de vacío con la palabra «Cargando» dentro, y sobre todo no
    /// las filas en «0 de tus últimos 0 días», que era una mentira momentánea de la hoja
    /// vieja. La hoja no brinca cuando llegan los datos porque los tres estados miden igual.
    @MainActor
    private static func nivelesCargando() -> AnyView {
        columna(tone: LiquidColor.cian) {
            LiquidSheetHeader(
                icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                numeral: "56", unidad: "ms",
                origenEtiqueta: "Apple Salud · anoche")
            LiquidGraficaNiveles(
                puntos: [], bandas: [], dominio: 0.0...1.0, ticksY: [],
                tono: LiquidColor.cian,
                estado: .cargando,
                estadoVacio: "",
                a11yLabel: "VFC por noche")
            LiquidGraficaNiveles(
                puntos: [], bandas: [], dominio: 0.0...1.0, ticksY: [],
                tono: LiquidColor.cian,
                estado: .vacio("Sin lecturas en este rango"),
                estadoVacio: "Sin lecturas en este rango",
                a11yLabel: "VFC por noche")
        }
    }

    /// §6-F3b · Ventana VACÍA (fellBack): la gráfica muestra su estado vacío.
    @MainActor
    private static func nivelesVentanaVacia() -> AnyView {
        let grafica = LiquidGraficaNiveles(
            puntos: [],
            bandas: bandasVFC(activa: nil),
            dominio: 40...72,
            ticksY: [(66, "66 ms"), (55, "55"), (46, "46")],
            tono: LiquidColor.cian,
            puntoHoy: nil, hoyAnillo: false,
            formatoScrub: { v, _ in "\(Int(v.rounded())) ms" },
            estadoVacio: "Sin lecturas en este rango",
            a11yLabel: "VFC por noche")
        return columna(tone: LiquidColor.cian) {
            LiquidSheetHeader(
                icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                numeral: "56", unidad: "ms",
                origenEtiqueta: "Apple Salud · anoche")
            grafica
        }
    }

    /// Serie con offsets de día EXPLÍCITOS respecto del ancla. Las tres gráficas de la
    /// familia reparten por TIEMPO real, así que el hueco entre lecturas es parte del dato
    /// (y de la geometría que decide si caben los discos).
    private static func serieOffsets(_ offsets: [Int], base: Double, onda: Double)
        -> [(fecha: Date, valor: Double)] {
        offsets.enumerated().map { (k: Int, d: Int) in
            (fecha: ancla.addingTimeInterval(Double(d) * 86_400),
             valor: base + onda * sin(Double(k) / 1.7) + Double((k * 5) % 6) - 2.5)
        }
    }

    /// §A2 · Los DOS lados del gate de densidad, en la misma hoja.
    ///
    /// Arriba, 30 lecturas diarias — la ventana «M». El gate viejo medía `paso >= radio × 4`,
    /// así que cuando el dueño subió el radio de 2.2 a 3.0 el corte se movió solo de n≈34 a
    /// n≈26 y «M» perdió sus discos sin que nadie lo pidiera. Con la separación mínima entre
    /// CENTROS (9 pt = dos radios + hueco) vuelven: uno por día, contables.
    ///
    /// Abajo, 12 lecturas en 90 días con DOS en días seguidos. El promedio dice ~27 pt de
    /// aire, pero ese par cae a ~3.6 pt: dibujarlo encimado haría contar 11 donde la fila de
    /// nivel afirma 12, así que la serie entera cede sus discos y se queda con la polilínea.
    /// Es un cambio de comportamiento —no sólo una restauración— y por eso tiene render.
    @MainActor
    private static func nivelesDensidad() -> AnyView {
        let densa = serieDiaria(dias: 30, base: 58, onda: 13)
        // 54 y 55 días atrás: el par pegado que muerde.
        let racimo = serieOffsets([-90, -81, -72, -63, -55, -54, -45, -36, -27, -18, -9, 0],
                                  base: 58, onda: 12)
        func grafica(_ puntos: [(fecha: Date, valor: Double)],
                     dias: Int) -> LiquidGraficaNiveles {
            LiquidGraficaNiveles(
                puntos: puntos, bandas: bandasVFC(activa: 1), dominio: 30...95,
                ticksY: [(63, "63 ms"), (48, "48")], tono: LiquidColor.cian,
                puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
                hoyAnillo: false,
                formatoScrub: { (v: Double, f: Date) in "\(Int(v.rounded())) ms · \(popupDia(f))" },
                formatoValorScrub: { (v: Double) in "\(Int(v.rounded())) ms" },
                formatoFechaScrub: popupDia,
                formatoFechaEje: ejeDia,
                estadoVacio: "Sin lecturas en este rango",
                a11yLabel: "VFC, últimos \(dias) días")
        }
        return columna(tone: LiquidColor.cian) {
            LiquidSheetHeader(
                icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                numeral: "56", unidad: "ms",
                origenEtiqueta: "Apple Salud · anoche")
            LiquidNotaLine("30 lecturas diarias: un disco por día, contable.")
            grafica(densa, dias: 30)
            LiquidNotaLine("12 lecturas en 90 días, dos en días seguidos: sin discos, porque contarlos mentiría.")
            grafica(racimo, dias: 90)
        }
    }

    /// §E2 · UNA sola lectura en la ventana. La gráfica cae al pozo (`puntos.count > 1`) y
    /// ahora VoiceOver dice lo MISMO: antes anunciaba «56 ms» sobre una pantalla que
    /// declaraba no tener nada que dibujar — el caso del usuario nuevo, justo quien más
    /// depende de la voz.
    ///
    /// El pozo lleva el mensaje HONESTO de la hoja real («solo una lectura», no «sin
    /// lecturas»): con la lectura de anoche viva en el numeral, negar que existe sería la
    /// mentira contraria. La hoja lo manda como estado explícito
    /// (`LiquidMetricSheetView:857`) y lo pasa TAMBIÉN como `estadoVacio`, que es la red de
    /// seguridad de E2 si algún caller olvidara el estado.
    @MainActor
    private static func nivelesUnaLectura() -> AnyView {
        let unica = serieDiaria(dias: 1, base: 56, onda: 0)
        let honesto = "Solo una lectura en este rango, aún no alcanza para trazar una línea."
        return columna(tone: LiquidColor.cian) {
            LiquidSheetHeader(
                icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                numeral: "56", unidad: "ms",
                origenEtiqueta: "Apple Salud · anoche")
            LiquidFraseNivel(nivel: nil,
                             conteo: "1 noche con datos en este rango",
                             tono: LiquidColor.cian,
                             sinLectura: "Aún no hay línea que dibujar")
            LiquidGraficaNiveles(
                puntos: unica, bandas: bandasVFC(activa: nil), dominio: 30...95,
                ticksY: [(63, "63 ms"), (48, "48")], tono: LiquidColor.cian,
                puntoHoy: nil, hoyAnillo: false,
                formatoScrub: { (v: Double, f: Date) in "\(Int(v.rounded())) ms · \(popupDia(f))" },
                formatoFechaEje: ejeDia,
                estadoVacio: honesto,
                a11yLabel: "VFC por noche")
        }
    }

    /// §6-F4 (QA D5) · Estados cargando y vacío de los charts clásicos, en columna.
    @MainActor
    private static func chartsCargandoVacio() -> AnyView {
        columna(tone: LiquidColor.rosa) {
            LiquidSheetHeader(
                icono: .corazon, titulo: "FC EN REPOSO", tono: LiquidColor.rosa,
                numeral: "52", unidad: "lpm")
            LiquidTrendChart(
                titulo: "Últimos 14 días", readout: nil, puntos: [], bandas: [],
                dominio: 40...80, ticksY: [], tono: LiquidColor.rosa,
                formatoScrub: { v, _ in "\(Int(v.rounded()))" },
                estado: .cargando,
                a11yLabel: "Tendencia FC en reposo")
            LiquidTrendChart(
                titulo: "Últimos 14 días", readout: nil, puntos: [], bandas: [],
                dominio: 40...80, ticksY: [], tono: LiquidColor.rosa,
                formatoScrub: { v, _ in "\(Int(v.rounded()))" },
                estado: .vacio("Sin datos de los últimos 14 días"),
                a11yLabel: "Tendencia FC en reposo")
        }
    }

    /// §1.5 (C1 · D13) · Rendimiento de sueño: la rama CLÁSICA que solo se alcanza desde el
    /// Detalle de Sueño, y el único sitio donde se ve el arreglo de las cotas del catálogo.
    /// Sus tres bandas venían SIN cotas: una banda sin cotas contiene cualquier valor, así
    /// que la hoja decía «14 de las últimas 14 noches en este rango» y la tabla «14 / 0 / 0»
    /// pasara lo que pasara. Aquí los conteos y el readout se DERIVAN de la serie (< 70 ·
    /// 70–85 · ≥ 85, semiabiertas), así que el fixture no puede contradecirse a sí mismo, y
    /// los mismos cortes entran como washes al trend (antes iba `bandas: []`: una polilínea
    /// desnuda bajo una tabla que sí clasificaba).
    @MainActor
    private static func sleepPerformance() -> AnyView {
        let puntos = serieDiaria(dias: 14, base: 84, onda: 11).map {
            (fecha: $0.fecha, valor: min(max($0.valor, 58), 100))
        }
        let cortes: [(lo: Double?, hi: Double?, etiqueta: String, rango: String)] = [
            (85, nil, "Óptimo", "85 – 100%"),
            (70, 85, "Adecuado", "70 – 85%"),
            (nil, 70, "Bajo", "< 70%"),
        ]
        func cuenta(_ lo: Double?, _ hi: Double?) -> Int {
            puntos.reduce(0) { n, p in
                let dentro = (lo == nil || p.valor >= lo!) && (hi == nil || p.valor < hi!)
                return n + (dentro ? 1 : 0)
            }
        }
        // La banda ACTIVA es la de la última noche — la misma que nombra el readout y la
        // que se ilumina en la gráfica (un solo índice manda sobre los tres sitios).
        let ultima = puntos[puntos.count - 1].valor
        let iActiva = cortes.firstIndex { c in
            (c.lo == nil || ultima >= c.lo!) && (c.hi == nil || ultima < c.hi!)
        } ?? 0
        let trend = LiquidTrendChart(
            titulo: "Últimos 14 días",
            readout: (etiqueta: cortes[iActiva].etiqueta, tono: LiquidColor.indigo,
                      frase: "\(cuenta(cortes[iActiva].lo, cortes[iActiva].hi)) de las últimas \(puntos.count) noches en este rango"),
            puntos: puntos,
            bandas: cortes.enumerated().map { (i, c) in
                .init(lo: c.lo, hi: c.hi, color: LiquidColor.indigo, activa: i == iActiva)
            },
            dominio: 55...105,
            ticksY: [(85, "85%"), (70, "70%")],
            tono: LiquidColor.indigo,
            formatoScrub: { (v: Double, f: Date) in "\(Int(v.rounded())) % · \(popupDia(f))" },
            formatoValorScrub: { (v: Double) in "\(Int(v.rounded())) %" },
            formatoFechaScrub: popupDia,
            formatoFechaEje: ejeDia,
            estado: .datos,
            a11yLabel: "Rendimiento de sueño, últimos 14 días")
        return columna(tone: LiquidColor.indigo) {
            LiquidSheetHeader(
                icono: .luna, titulo: "RENDIMIENTO", tono: LiquidColor.indigo,
                numeral: "\(Int(ultima.rounded()))%",
                origenEtiqueta: "Apple Salud · anoche",
                explicacion: "Cuánto dormiste contra lo que tu cuerpo necesita. Al 100 % cubriste la necesidad de anoche.",
                infoMostrar: "Mostrar explicación",
                infoOcultar: "Ocultar explicación")
            trend
            LiquidBandsTable(
                filas: cortes.enumerated().map { (i, c) in
                    .init(etiqueta: c.etiqueta, rango: c.rango,
                          conteo: "\(cuenta(c.lo, c.hi)) noches", activa: i == iActiva)
                },
                tono: LiquidColor.indigo)
            LiquidNotaLine("Tu necesidad es tu propio promedio de las últimas noches, nunca menos de 7.5 h.")
        }
    }

    /// §1.2 · VFC sin base (niveles relativos, <1 noche válida): dato de anoche pero la
    /// nota honesta reemplaza a la gráfica.
    @MainActor
    private static func hrvSinBase() -> AnyView {
        columna(tone: LiquidColor.cian) {
            LiquidSheetHeader(
                icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                numeral: "44", unidad: "ms",
                origenEtiqueta: "Apple Salud · anoche",
                explicacion: "La variación entre latidos mientras duermes — tu señal más temprana de recuperación.")
            LiquidNotaLine("Tus niveles salen de tu propia base. Aún no hay noches suficientes para dibujarla — duerme unas noches más con tu Apple Watch.")
            LiquidMetodo(title: "Cómo se calcula") {
                LiquidNotaLine("SDNN sobre los latidos nocturnos, comparado contra tu base de 21 noches (Task Force, 1996).")
            }
            LiquidVerMas(title: "Ver más", hint: "Abre el detalle completo",
                         tone: LiquidColor.cian, action: {})
        }
    }
    #endif
}
