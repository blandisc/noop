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

    /// Curva FC intradía determinista: ~200 puntos cada 5 min desde la medianoche fija.
    private static func curvaFCDia() -> [(fecha: Date, valor: Double)] {
        (0..<200).map { i in
            let t = Double(i) / 200.0
            let base = 62.0 + 26.0 * sin(t * .pi * 3.1) * sin(t * .pi)
            let ruido = Double((i * 13) % 9) - 4.0
            return (fecha: ancla.addingTimeInterval(Double(i) * 300.0), valor: base + ruido)
        }
    }

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
            ("sleep_skeleton", sleepSkeleton()),
            ("strain", strain()),
            ("heart_rate", heartRate()),
            ("clasica", clasica()),
            ("hrv_sinbase", hrvSinBase()),
        ]
    }

    /// §1.2 · Vital-template con dato: VFC 56 ms, selector + explorador de niveles con la
    /// banda media activa, filas de nivel, patrón, método y «Ver más» ancho completo.
    @MainActor
    private static func vitalConDato() -> AnyView {
        let puntos = serieDiaria(dias: 28, base: 58, onda: 13)
        var grafica = LiquidGraficaNiveles(
            puntos: puntos, bandas: bandasVFC(activa: 1), dominio: 30...95,
            ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
            puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
            hoyAnillo: false,
            formatoScrub: { v, _ in "\(Int(v)) ms" },
            estadoVacio: "Sin lecturas en este rango.",
            a11yLabel: "VFC, últimos 28 días")
        grafica.scrubFijo = 9
        return columna(tone: LiquidColor.cian) {
            LiquidSheetHeader(
                icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                numeral: "56", unidad: "ms",
                origenEtiqueta: "Apple Salud · anoche",
                explicacion: "La variación entre latidos mientras duermes — tu señal más temprana de recuperación.")
            LiquidReadingLine("Tu VFC amaneció en tu rango.",
                              highlight: "en tu rango",
                              highlightTone: LiquidColor.verdeProfundo)
            LiquidRangeSelector(opciones: ["S", "M", "3M", "6M", "1A", "TODO"],
                                seleccion: .constant(1))
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
            // Coherencia numeral↔tick: 78/100 cae en la zona alta (LISTO activa).
            LiquidZoneMeter(segmentos: [
                .init(peso: 34, color: LiquidColor.negativo, activa: false, etiqueta: "AGOTADO"),
                .init(peso: 33, color: LiquidColor.atencion, activa: false, etiqueta: "MODERADO"),
                .init(peso: 33, color: LiquidColor.positivo, activa: true, etiqueta: "LISTO"),
            ], fraccion: 0.78)
            LiquidMetodo(title: "Cómo se calcula") {
                LiquidNotaLine("VFC, pulso en reposo y sueño de anoche, comparados contra tu propia base.")
            }
            LiquidVerMas(title: "Ver más en Tendencias", hint: "Abre el detalle completo",
                         tone: LiquidColor.verdePrimario, anchoCompleto: true, action: {})
        }
    }

    /// §1.3 · Sueño rica: doble dato 7:12 | 84, etapas de la noche, lane activa y
    /// «Para esta noche».
    @MainActor
    private static func sleepRica() -> AnyView {
        columna(tone: LiquidColor.indigo) {
            LiquidSheetHeader(
                icono: .luna, titulo: "SUEÑO", tono: LiquidColor.indigo,
                numeral: nil,
                explicacion: "Cuánto y qué tan parejo dormiste anoche.")
            LiquidDobleDato(principal: (valor: "7:12", etiqueta: "horas dormido"),
                            secundario: (valor: "84", etiqueta: "regularidad"),
                            tono: LiquidColor.indigo)
            LiquidReadingLine("Dormiste dentro de tu rango óptimo.",
                              highlight: "rango óptimo",
                              highlightTone: LiquidColor.indigo)
            LiquidStageBar(
                etapas: [
                    .init(minutos: 91, color: LiquidColor.indigo,
                          etiqueta: "Profundo", duracion: "1:31"),
                    .init(minutos: 104, color: LiquidColor.indigo.opacity(0.78), // token-exempt: rampa graduada de etapas
                          etiqueta: "REM", duracion: "1:44"),
                    .init(minutos: 190, color: LiquidColor.indigo.opacity(0.52), // token-exempt: rampa graduada de etapas
                          etiqueta: "Ligero", duracion: "3:10"),
                    .init(minutos: 47, color: LiquidColor.tinta10,
                          etiqueta: "Despierto", duracion: "0:47"),
                ],
                overline: "Anoche",
                ventana: "23:38 → 7:04")
            LiquidLaneLabel(texto: "ÓPTIMO · ANOCHE", tono: LiquidColor.indigo)
            LiquidPatternBlock(
                overline: "Para esta noche",
                lineas: ["Acostarte a una hora pareja esta noche ayuda a tu ritmo."],
                tono: LiquidColor.indigo)
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
            bandas: [
                .init(lo: 14, hi: nil, color: LiquidColor.negativo, activa: false),
                .init(lo: 8, hi: 14, color: LiquidColor.ambar, activa: true),
                .init(lo: nil, hi: 8, color: LiquidColor.positivo, activa: false),
            ],
            dominio: 0...21,
            ticksY: [(14, "14"), (8, "8")], tono: LiquidColor.ambar,
            puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
            hoyAnillo: false,
            formatoScrub: { v, _ in String(format: "%.1f", v) },
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

    /// §1.6 · heart_rate: curva 24h con ~200 puntos deterministas + stats min/prom/max.
    @MainActor
    private static func heartRate() -> AnyView {
        var curva = LiquidCurvaFC(
            titulo: "Pulsaciones por minuto",
            subtitulo: "Promedio de 5 min · desde medianoche",
            ultimo: "72 lpm",
            puntos: curvaFCDia(),
            dominio: 40...105,
            stats: (min: "48", prom: "64", max: "98"),
            statsEtiquetas: (min: "Mín", prom: "Prom", max: "Máx"),
            formatoScrub: { v, _ in "\(Int(v)) lpm · 2 pm" },
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

    /// §1.5 · Clásica: headline + trend 14d con readout + tabla de 4 bandas con conteos
    /// + tarjeta de calibración 2/4.
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
            formatoScrub: { v, _ in String(format: "%.1f h", v) },
            estado: .datos,
            a11yLabel: "Sueño, últimos 14 días")
        trend.scrubFijo = 5
        return columna(tone: LiquidColor.indigo) {
            LiquidSheetHeader(
                icono: .luna, titulo: "HORAS DE SUEÑO", tono: LiquidColor.indigo,
                numeral: "7:12", origenEtiqueta: "Apple Salud · anoche",
                explicacion: "Cuánto dormiste anoche, contra tu rango de referencia.")
            trend
            LiquidBandsTable(
                filas: [
                    .init(etiqueta: "Óptimo", rango: "7–9 h", conteo: "9 noches", activa: true),
                    .init(etiqueta: "Adecuado", rango: "6–7 h", conteo: "3 noches"),
                    .init(etiqueta: "Corto", rango: "5–6 h", conteo: "2 noches"),
                    .init(etiqueta: "Muy corto", rango: "< 5 h", conteo: "0 noches"),
                ],
                tono: LiquidColor.indigo)
            LiquidCalibracionCard(titulo: "Calibrando tu base",
                                  leyenda: "2 de 4 noches",
                                  hechas: 2, necesarias: 4,
                                  tono: LiquidColor.indigo)
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
