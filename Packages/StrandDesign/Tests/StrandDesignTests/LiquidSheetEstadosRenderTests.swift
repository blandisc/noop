import XCTest
import SwiftUI
@testable import StrandDesign

/// Arnés de renders de la hoja de resumen Liquid (épico hoja Liquid, gate C5 del contrato
/// docs/design-system/LIQUID-SHEET-CONTRACT.md §6): compone cada variante/estado de la
/// matriz §1 con los componentes REALES del DS y escribe un PNG por estado a
/// /tmp/noop-liquid/ para verificación visual del dueño.
/// Determinista: fechas fijas (sin Date()/Date.now), series sinusoidales fijas.
/// Run: swift test --filter LiquidSheetEstadosRenderTests
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

    private static func bandasVFC(activa: Int?) -> [LiquidChartBanda] {
        [
            .init(lo: 71, hi: nil, color: LiquidColor.positivo, activa: activa == 0),
            .init(lo: 49, hi: 71, color: LiquidColor.cian, activa: activa == 1),
            .init(lo: nil, hi: 49, color: LiquidColor.atencion, activa: activa == 2),
        ]
    }

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
            ("niveles_reposo_filas", nivelesReposoConFilas()),
            ("niveles_ventana_vacia", nivelesVentanaVacia()),
            ("charts_cargando_vacio", chartsCargandoVacio()),
            ("strain", strain()),
            ("heart_rate", heartRate()),
            ("clasica", clasica()),
            ("hrv_sinbase", hrvSinBase()),
        ]
    }

    /// §1.2 · Vital-template con dato: VFC 56 ms, selector + explorador de niveles con la
    /// banda media activa, filas de nivel, patrón, método y «Ver más» ancho completo.
    /// Es el fixture COMPLETO del bloque de niveles: mismo orden que `levelsBlock` de la
    /// hoja real (selector → frase → gráfica), con eje X de fechas, puntos por dato y el
    /// popup de DOS líneas del scrub.
    @MainActor
    private static func vitalConDato() -> AnyView {
        let puntos = serieDiaria(dias: 28, base: 58, onda: 13)
        var grafica = LiquidGraficaNiveles(
            puntos: puntos, bandas: bandasVFC(activa: 1), dominio: 30...95,
            ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
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
            LiquidFraseNivel(nivel: "En tu base",
                             conteo: "12 de tus últimos 28 días",
                             tono: LiquidColor.cian)
            grafica
            LiquidBandsTable(
                filas: [
                    .init(etiqueta: "Alto", rango: "≥ 71", conteo: "4 días"),
                    .init(etiqueta: "En tu base", rango: "49–71", conteo: "8 días", activa: true),
                    .init(etiqueta: "Bajo", rango: "< 49", conteo: "2 días"),
                ],
                tono: LiquidColor.cian)
            LiquidPatternBlock(
                overline: "Tu patrón",
                lineas: [
                    "Tus noches con alcohol bajan tu VFC al día siguiente.",
                    "Dormir 7 h o más sube tu base a la mañana.",
                ],
                tono: LiquidColor.cian)
            LiquidMetodo(title: "Cómo se calcula") {
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
                numeralTono: LiquidColor.verdeProfundo, origen: .calculado,
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
    /// noche y «Para esta noche». La pastilla `LiquidLaneLabel` está RETIRADA (L3.3): la
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
                explicacion: "Cuánto y qué tan parejo dormiste anoche.",
                infoMostrar: "Mostrar explicación",
                infoOcultar: "Ocultar explicación")
            LiquidDobleDato(
                principal: (valor: "7:12", etiqueta: "horas dormido"),
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
                    .init(minutos: 47, color: LiquidColor.tinta10,
                          etiqueta: "Despierto", duracion: "0:47"),
                ],
                overline: "Anoche",
                ventana: "23:38 → 7:37")
            LiquidPatternBlock(
                overline: "Para esta noche",
                lineas: ["Acostarte a una hora pareja esta noche ayuda a tu ritmo."],
                tono: LiquidColor.indigo)
        }
        .environment(\.dynamicTypeSize, tamano))
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
            bandas: [
                .init(lo: 14, hi: nil, color: LiquidColor.negativo, activa: false),
                .init(lo: 8, hi: 14, color: LiquidColor.ambar, activa: true),
                .init(lo: nil, hi: 8, color: LiquidColor.positivo, activa: false),
            ],
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
                numeral: "10.0", sufijo: "/ 21", origen: .calculado,
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
            readout: (etiqueta: "Adecuado", tono: LiquidColor.indigo,
                      frase: "9 de las últimas 14 noches en este rango"),
            puntos: puntos,
            bandas: [
                .init(lo: 7, hi: 9, color: LiquidColor.indigo, activa: true),
                .init(lo: 6, hi: 7, color: LiquidColor.teal, activa: false),
                .init(lo: nil, hi: 6, color: LiquidColor.atencion, activa: false),
            ],
            dominio: 5...10,
            ticksY: [(9, "9"), (7, "7"), (6, "6")],
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
                numeral: "—", origen: .calculado,
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
            bandas: [
                .init(lo: 420, hi: 540, color: LiquidColor.indigo, activa: true),
                .init(lo: 360, hi: 420, color: LiquidColor.teal, activa: false),
                .init(lo: nil, hi: 360, color: LiquidColor.atencion, activa: false),
            ],
            dominio: 320...560,
            ticksY: [(540, "9 h"), (420, "7 h"), (360, "6 h")],
            tono: LiquidColor.indigo,
            puntoHoy: nil, hoyAnillo: false,
            formatoScrub: { v, _ in
                let m = Int(v.rounded()); return "\(m / 60) h \(m % 60) min"
            },
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
            bandas: [
                .init(lo: 95, hi: nil, color: LiquidColor.azul, activa: true),
                .init(lo: 90, hi: 95, color: LiquidColor.atencion, activa: false),
                .init(lo: nil, hi: 90, color: LiquidColor.negativo, activa: false),
            ],
            dominio: 88...100,
            ticksY: [(98, "98"), (95, "95"), (90, "90")],
            tono: LiquidColor.azul,
            puntoHoy: (fecha: puntos[puntos.count - 1].fecha, valor: 97.0),
            hoyAnillo: false,
            formatoScrub: { v, _ in String(format: "%.0f %%", v) },
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
    /// tocables `LiquidLevelRow` (QA F3b-D1: el arnés no las renderizaba).
    @MainActor
    private static func nivelesReposoConFilas() -> AnyView {
        let puntos = serieDiaria(dias: 28, base: 55, onda: 6)
        let grafica = LiquidGraficaNiveles(
            puntos: puntos,
            bandas: bandasVFC(activa: nil),
            dominio: 40...72,
            ticksY: [(66, "66"), (55, "55"), (46, "46")],
            tono: LiquidColor.cian,
            puntoHoy: nil, hoyAnillo: false,
            formatoScrub: { v, _ in "\(Int(v.rounded())) ms" },
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
                             conteo: "28 noches con datos en este rango",
                             tono: LiquidColor.cian,
                             sinLectura: "Hoy sin lectura")
            grafica
            LiquidLevelRow(etiqueta: "Arriba de tu base", rango: "> 63", conteo: "6 noches",
                           esHoy: false, activa: false, tono: LiquidColor.cian, onTap: {})
            // Hoy cayó aquí mientras exploras otro nivel: anillo hueco + rótulo «· hoy».
            LiquidLevelRow(etiqueta: "En tu base", rango: "48–63", conteo: "18 noches",
                           esHoy: true, activa: false, tono: LiquidColor.cian,
                           hoyEtiqueta: "· hoy", onTap: {})
            LiquidLevelRow(etiqueta: "Debajo de tu base", rango: "< 48", conteo: "4 noches",
                           esHoy: false, activa: true, tono: LiquidColor.cian, onTap: {})
        }
    }

    /// §6-F3b · Ventana VACÍA (fellBack): la gráfica muestra su estado vacío.
    @MainActor
    private static func nivelesVentanaVacia() -> AnyView {
        let grafica = LiquidGraficaNiveles(
            puntos: [],
            bandas: bandasVFC(activa: nil),
            dominio: 40...72,
            ticksY: [(66, "66"), (55, "55"), (46, "46")],
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
