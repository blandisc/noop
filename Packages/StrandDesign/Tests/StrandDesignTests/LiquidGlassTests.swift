import XCTest
import SwiftUI
@testable import StrandDesign

/// Sistema «Liquid Glass v1» — parser SVG, catálogo de glifos, contrato de motion y un
/// render de humo de la pantalla Hoy. Run: swift test --filter LiquidGlassTests
final class LiquidGlassTests: XCTestCase {

    // MARK: Parser SVG

    /// Regresión del bug /inject 2026-07-22: el path DEBE arrancar con un moveTo real —
    /// macOS perdona un addLine inicial (lo trata como move) pero iOS descarta el path
    /// en silencio, así que el bounding box por sí solo no bastaba como test.
    func test_parser_arrancaConMoveTo() {
        for d in ["M2 3l4 0v5h-4z", "M1 8h3l2-4 3 8 2-4h4",
                  "M62 56 L62 94 C52 122, 112 132, 130 148"] {
            var first: CGPathElementType?
            SVGPathData.path(d).cgPath.applyWithBlock { element in
                if first == nil { first = element.pointee.type }
            }
            XCTAssertEqual(first, .moveToPoint, "«\(d.prefix(12))…» debe abrir con moveTo")
        }
    }

    func test_parser_lineasYRelativos() {
        // M/l/h/v relativos y absolutos.
        let p = SVGPathData.path("M2 3l4 0v5h-4z")
        let b = p.boundingRect
        XCTAssertEqual(b.minX, 2, accuracy: 0.001)
        XCTAssertEqual(b.minY, 3, accuracy: 0.001)
        XCTAssertEqual(b.maxX, 6, accuracy: 0.001)
        XCTAssertEqual(b.maxY, 8, accuracy: 0.001)
    }

    func test_parser_numerosPegados() {
        // «.5-1.6.2» = 0.5, −1.6, 0.2 — el estilo compacto del handoff.
        let p = SVGPathData.path("M0 0l.5-1.6.2-3.6")
        let b = p.boundingRect
        XCTAssertEqual(b.maxX, 0.7, accuracy: 0.001)
        XCTAssertEqual(b.minY, -5.2, accuracy: 0.001)
    }

    func test_parser_arcoCircular() {
        // Círculo completo r8 alrededor de (11.5, 11.5) expresado como dos arcos.
        let p = SVGPathData.path("M19.5 11.5A8 8 0 1 0 3.5 11.5A8 8 0 1 0 19.5 11.5")
        let b = p.boundingRect
        XCTAssertEqual(b.minX, 3.5, accuracy: 0.05)
        XCTAssertEqual(b.maxX, 19.5, accuracy: 0.05)
        XCTAssertEqual(b.minY, 3.5, accuracy: 0.05)
        XCTAssertEqual(b.maxY, 19.5, accuracy: 0.05)
    }

    func test_parser_reflexionS() {
        // S refleja el último control cúbico; la curva debe quedar acotada y suave.
        let p = SVGPathData.path("M1.5 8 C3 4.6, 4.6 4.6, 6 8 S8.6 11.4, 10 8 S12.4 5.2, 14 6.6")
        let b = p.boundingRect
        XCTAssertFalse(p.isEmpty)
        XCTAssertGreaterThan(b.width, 12)
        XCTAssertTrue(b.minY > 2 && b.maxY < 13)
    }

    /// Cada glifo del catálogo parsea a un path no vacío, finito y dentro de su viewBox
    /// (con holgura de trazo).
    func test_catalogoDeGlifos_dentroDelViewBox() {
        for glyph in LiquidIcon.Glyph.allCases {
            let spec = glyph.spec
            var combined = Path()
            // `pathsFilled` es la tercera capa (geometría YA rellena: los nodos de
            // `.tendencias`). Sin ella el test dejaba sin cubrir arte que SÍ se pinta.
            for d in spec.paths + spec.paths2 + spec.pathsFilled {
                combined.addPath(SVGPathData.path(d))
            }
            XCTAssertFalse(combined.isEmpty, "\(glyph.rawValue): path vacío")
            let b = combined.boundingRect
            for v in [b.minX, b.minY, b.maxX, b.maxY] {
                XCTAssertTrue(v.isFinite, "\(glyph.rawValue): bounds no finitos")
            }
            let slop: CGFloat = 1.5
            XCTAssertGreaterThanOrEqual(b.minX, -slop, glyph.rawValue)
            XCTAssertGreaterThanOrEqual(b.minY, -slop, glyph.rawValue)
            XCTAssertLessThanOrEqual(b.maxX, spec.viewBox + slop, glyph.rawValue)
            XCTAssertLessThanOrEqual(b.maxY, spec.viewBox + slop, glyph.rawValue)
        }
    }

    // MARK: Contrato de gráfica (recuperación /inject — tokens `LiquidChart`)

    /// El invariante que hace HONESTOS los puntos por dato: un disco por muestra vuelve la
    /// ventana CONTABLE, así que el umbral tiene que quedar por debajo del tope de
    /// decimación del caller (80, `MetricWindowMath.decimatedPoints`). Si alguien sube este
    /// número sin subir aquel, el usuario contaría 7 discos donde la fila de nivel afirma
    /// «9 noches» y la hoja mentiría en silencio, sin fallar ninguna compilación.
    func test_puntoDatoUmbral_bajoElTopeDeDecimacion() {
        XCTAssertLessThan(LiquidChart.puntoDatoUmbral, 80,
                          "los discos por dato harían contable una serie ya decimada")
        XCTAssertGreaterThan(LiquidChart.puntoDatoUmbral, 0)
    }

    /// I1 se juega en 13 puntos de alfa (8 reposo / 16 activa / 3 apagada): el disco de un
    /// punto FUERA de la banda activa tiene que acompañar a su wash, nunca competir con él.
    func test_puntosDato_apagadosPorDebajoDelEncendido() {
        XCTAssertLessThan(LiquidChart.puntoApagadoAlfa, 1)
        XCTAssertLessThan(LiquidChart.puntoApagadoEscala, 1)
        // I1 intacto: los tres washes de banda siguen siendo 8 / 16 / 3.
        XCTAssertEqual(LiquidChart.bandaReposoAlfa, 0.08)
        XCTAssertEqual(LiquidChart.bandaActivaAlfa, 0.16)
        XCTAssertEqual(LiquidChart.bandaApagadaAlfa, 0.03)
    }

    /// La banda es un intervalo half-open `[lo, hi)` — el mismo resolver que pinta el color
    /// del anillo del scrub, del popup y de cada disco. Un solo punto en dos bandas dejaría
    /// el anillo y su popup discrepando del wash que ilumina.
    func test_banda_intervaloHalfOpen() {
        let media = LiquidChartBanda(lo: 49, hi: 71, color: .cyan, activa: true)
        XCTAssertTrue(media.contiene(49), "el borde bajo PERTENECE a la banda")
        XCTAssertTrue(media.contiene(70.9))
        XCTAssertFalse(media.contiene(71), "el borde alto es de la banda de arriba")
        XCTAssertFalse(media.contiene(48.9))
        let abierta = LiquidChartBanda(lo: 71, hi: nil, color: .green, activa: false)
        XCTAssertTrue(abierta.contiene(1_000))
        let porAbajo = LiquidChartBanda(lo: nil, hi: 49, color: .orange, activa: false)
        XCTAssertTrue(porAbajo.contiene(-1_000))
        XCTAssertFalse(porAbajo.contiene(49))
    }

    /// Qué punto nombra VoiceOver: el que está bajo el dedo mientras dura el scrub, y el
    /// ÚLTIMO en reposo (nunca el primero, que es el más viejo de la ventana).
    func test_a11y_indiceDelScrub() {
        XCTAssertEqual(LiquidChartA11y.indice(3, 14), 3)
        XCTAssertEqual(LiquidChartA11y.indice(nil, 14), 13, "en reposo lee el último punto")
        XCTAssertEqual(LiquidChartA11y.indice(99, 14), 13, "índice fuera de rango = último")
        XCTAssertEqual(LiquidChartA11y.indice(-1, 14), 13)
        XCTAssertEqual(LiquidChartA11y.indice(nil, 0), 0, "serie vacía no puede desbordar")
    }

    /// A5 · Orden defensivo del plot. La serie se DIBUJA ordenada por fecha (con
    /// `mapeoPorTiempo` una serie revuelta rompe `fraccionTiempo`, que toma `first`/`last`
    /// como extremos del span), pero el índice que se publica —`onScrub`, y el `scrubFijo`
    /// que se recibe— pertenece al arreglo del CALLER. Sin la traducción, VoiceOver
    /// nombraría un día y el anillo se pararía sobre otro.
    func test_plot_ordenDefensivo_traduceIndicesAlCaller() {
        let t0 = Date(timeIntervalSinceReferenceDate: 774_500_000)
        func dia(_ d: Int) -> Date { t0.addingTimeInterval(Double(d) * 86_400) }
        // Revuelta a propósito: el caller la pasa así, el plot la ordena.
        let revuelta: [(fecha: Date, valor: Double)] = [
            (dia(2), 52), (dia(0), 58), (dia(3), 61), (dia(1), 47),
        ]
        let plot = LiquidChartPlot(puntos: revuelta, bandas: [], dominio: 40...70,
                                   ticksY: [], tono: .cyan, puntoHoy: nil, hoyAnillo: false,
                                   alto: 168)
        XCTAssertEqual(plot.puntos.map(\.valor), [58, 47, 52, 61], "el plot dibuja ordenado")
        XCTAssertEqual(plot.ordenOriginal, [1, 3, 0, 2],
                       "cada punto dibujado recuerda su índice en el arreglo del caller")
        // Ida y vuelta: el punto que el plot dibuja en la posición k es el del caller en
        // `ordenOriginal[k]`, y su valor coincide.
        for (k, orig) in plot.ordenOriginal.enumerated() {
            XCTAssertEqual(plot.puntos[k].valor, revuelta[orig].valor)
            XCTAssertEqual(plot.puntos[k].fecha, revuelta[orig].fecha)
        }
        // Camino rápido: una serie YA ordenada no se toca (identidad, sin copias).
        let ordenada: [(fecha: Date, valor: Double)] = (0..<5).map { (dia($0), Double(50 + $0)) }
        let plot2 = LiquidChartPlot(puntos: ordenada, bandas: [], dominio: 40...70,
                                    ticksY: [], tono: .cyan, puntoHoy: nil, hoyAnillo: false,
                                    alto: 168)
        XCTAssertEqual(plot2.ordenOriginal, Array(0..<5))
    }

    /// B7 · Una etapa de 0 minutos NO existe para la barra de la noche: con el fallback
    /// diario de Apple `awake` llega en 0 por construcción y la leyenda imprimía
    /// «DESPIERTO 0:00», insinuando una medición que nunca ocurrió. Y la ventana solo entra
    /// a VoiceOver cuando el caller la pudo afirmar («6:00 → 6:00» no es un horario).
    func test_stageBar_etapasEnCeroNoExisten() {
        let etapas: [LiquidStageBar.Etapa] = [
            .init(minutos: 91, color: .indigo, etiqueta: "Profundo", duracion: "1:31"),
            .init(minutos: 104, color: .indigo, etiqueta: "REM", duracion: "1:44"),
            .init(minutos: 190, color: .indigo, etiqueta: "Ligero", duracion: "3:10"),
            .init(minutos: 0, color: .yellow, etiqueta: "Despierto", duracion: "0:00"),
        ]
        XCTAssertEqual(LiquidStageBar.visibles(etapas).map(\.etiqueta),
                       ["Profundo", "REM", "Ligero"])
        XCTAssertEqual(LiquidStageBar.a11yValue(etapas: etapas, ventana: nil),
                       "Profundo 1:31, REM 1:44, Ligero 3:10")
        XCTAssertEqual(LiquidStageBar.a11yValue(etapas: etapas, ventana: "23:38 → 7:04"),
                       "Profundo 1:31, REM 1:44, Ligero 3:10, 23:38 → 7:04")
        // Noche sin medir: el componente no inventa nada (es el CALLER quien no debe
        // pintar la barra — `sleepEtapasMedidas` en la hoja).
        let ninguna = etapas.map {
            LiquidStageBar.Etapa(minutos: 0, color: $0.color,
                                 etiqueta: $0.etiqueta, duracion: "0:00")
        }
        XCTAssertTrue(LiquidStageBar.visibles(ninguna).isEmpty)
        XCTAssertEqual(LiquidStageBar.a11yValue(etapas: ninguna, ventana: nil), "")
    }

    /// B4 · La unidad del numeral ESCALA con Dynamic Type. Era `Font.system(size: 13)`
    /// duro: junto a un numeral que sí crecía, en `.xxxLarge` la unidad se quedaba enana.
    /// El test fija el estilo relativo, que es lo que macOS sí puede verificar (el escalado
    /// real solo se ve en el canvas de iOS: `ImageRenderer` de AppKit no escala fuentes).
    /// Fidelidad 2026-08-03: `.footnote` (13) → `.title3` (~20) para acompañar el numeral de
    /// 52 (el mock pide unidad de 19); sigue siendo un estilo relativo que escala.
    func test_type_unidadDelNumeralEscala() {
        XCTAssertEqual(LiquidType.numeralHojaUnidad, Font.system(.title3))
    }

    // MARK: Contrato de motion

    func test_motion_duraciones() {
        XCTAssertEqual(LiquidMotion.instant, 0.12)
        XCTAssertEqual(LiquidMotion.quick, 0.24)
        XCTAssertEqual(LiquidMotion.gentle, 0.42)
        XCTAssertEqual(LiquidMotion.sheetDuration, 0.56)
        XCTAssertEqual(LiquidMotion.flowPeriod, 6)   // 9 → 6: ritmo escalonado del dueño
        XCTAssertEqual(LiquidMotion.driftPeriods, 16...26)
        XCTAssertEqual(LiquidMotion.entradaStagger, 0.06)
        XCTAssertEqual(LiquidMotion.pressScale, 0.97)
    }

    func test_motion_driftProgress() {
        // alternate: 0 en t=0, 1 en t=periodo, 0 en t=2·periodo; reverse invierte.
        XCTAssertEqual(LiquidMotion.driftProgress(time: 0, period: 16), 0, accuracy: 1e-9)
        XCTAssertEqual(LiquidMotion.driftProgress(time: 16, period: 16), 1, accuracy: 1e-9)
        XCTAssertEqual(LiquidMotion.driftProgress(time: 32, period: 16), 0, accuracy: 1e-9)
        XCTAssertEqual(LiquidMotion.driftProgress(time: 0, period: 16, reverse: true), 1,
                       accuracy: 1e-9)
    }

    func test_motion_flowPulse() {
        // Un recorrido por ciclo de 6 s, continuo, con wrap limpio y delay por cable.
        XCTAssertEqual(LiquidMotion.flowPulseProgress(time: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(LiquidMotion.flowPulseProgress(time: 3), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LiquidMotion.flowPulseProgress(time: 6), 0, accuracy: 1e-9)
        XCTAssertEqual(LiquidMotion.flowPulseProgress(time: 0, delay: 2),
                       1 - 2.0 / 6, accuracy: 1e-9)
        XCTAssertEqual(LiquidMotion.flowPulseProgress(time: 5, delay: 2), 0.5, accuracy: 1e-9)
    }

    // MARK: Contratos a11y (FER-1045) — las composiciones de label que lee VoiceOver

    func test_a11y_contratos() {
        XCTAssertEqual(
            LiquidMetricTile.a11yLabel(label: "HRV", value: "56", unit: "ms",
                                       delta: "+2 ms vs tu base"),
            "HRV, 56 ms, +2 ms vs tu base")
        XCTAssertEqual(
            LiquidMetricTile.a11yLabel(label: "SUEÑO", value: "7:20", unit: "", delta: "En tu base"),
            "SUEÑO, 7:20, En tu base")
        XCTAssertEqual(LiquidCargaEscala.a11yLabel(eje: "CARGA", rotulo: "EN EQUILIBRIO", razon: 1.03),
                       "CARGA: EN EQUILIBRIO, 1.03")
    }

    /// El contrato de VoiceOver del Ecosistema (FER-10): veredicto + valores + guardián,
    /// JAMÁS la física (nada de «orbe», «partículas», «se funden»). El label es idéntico
    /// fundido o separado — la separación es puramente visual.
    func test_a11y_ecosistema() {
        let eco = LiquidEcosistema(
            senales: LiquidHoyModel.ejemplo.senales,
            hero: LiquidHoyModel.ejemplo.hero,
            guardian: LiquidHoyModel.ejemplo.guardian,
            ambiente: .bien, calibracion: nil, rotulos: .base,
            heroPuerta: "Cómo llegué a esto")
        let label = eco.a11yCompuesta
        XCTAssertTrue(label.contains("En rango"))
        XCTAssertTrue(label.contains("REPOSO: 52 lpm · en tu rango"))
        XCTAssertTrue(label.contains("SUEÑO: 7:20 h · en tu rango"))
        XCTAssertTrue(label.contains("VIGILANDO"))
        for prohibida in ["orbe", "partícula", "funde", "esfera"] {
            XCTAssertFalse(label.lowercased().contains(prohibida),
                           "el label de VoiceOver no habla de la física: \(prohibida)")
        }
    }

    /// La proyección modelo → coreografía (FER-10): el eclipse es EXCLUSIVO de `.juntas`,
    /// y una sola señal del guardián fuera jamás cambia la coreografía.
    func test_ecosistema_coreografia() {
        typealias Sim = EcosistemaSimulacion
        let v = LiquidHoyModel.ejemplo.hero
        XCTAssertEqual(LiquidEcosistema.coreografia(
            hero: v, ambiente: .bien, guardianEstado: .tranquilo, lunaSueno: true,
            calibracion: nil), .enRango)
        // Una señal del guardián fuera NO cambia nada («mostrar no es votar»).
        XCTAssertEqual(LiquidEcosistema.coreografia(
            hero: v, ambiente: .bien, guardianEstado: .tempFuera, lunaSueno: true,
            calibracion: nil), .enRango)
        // Atención SIN guardián en pareja → sin eclipse.
        XCTAssertEqual(LiquidEcosistema.coreografia(
            hero: v, ambiente: .atencion, guardianEstado: .tempFuera, lunaSueno: true,
            calibracion: nil), .atencion(eclipse: false))
        // Atención CON `.juntas` → el eclipse.
        XCTAssertEqual(LiquidEcosistema.coreografia(
            hero: v, ambiente: .atencion, guardianEstado: .juntas, lunaSueno: true,
            calibracion: nil), .atencion(eclipse: true))
        XCTAssertEqual(LiquidEcosistema.coreografia(
            hero: v, ambiente: .alerta, guardianEstado: .juntas, lunaSueno: true,
            calibracion: nil), .desgaste)
        // Calibrando manda sobre todo y no es separable.
        let cal = LiquidEcosistema.coreografia(
            hero: v, ambiente: .neutro, guardianEstado: nil, lunaSueno: false,
            calibracion: .init(noche: 4, total: 7))
        XCTAssertEqual(cal, .calibrando(noche: 4, total: 7))
        XCTAssertFalse(cal.separable)
    }

    // MARK: Contratos a11y — hoja de resumen (QA F0-F2 D4)

    func test_a11y_sheetHeader() {
        XCTAssertEqual(LiquidSheetHeader.a11yLabel(titulo: "VFC", numeral: "56",
                                                   unidad: "ms", origen: "Apple Salud"),
                       "VFC, 56 ms, Apple Salud")
        XCTAssertEqual(LiquidSheetHeader.a11yLabel(titulo: "SUEÑO", numeral: nil,
                                                   unidad: nil, origen: nil),
                       "SUEÑO")
        XCTAssertEqual(LiquidSheetHeader.a11yLabel(titulo: "ESFUERZO", numeral: "10.0",
                                                   unidad: nil, origen: nil),
                       "ESFUERZO, 10.0")
    }

    /// TND31-4 · el chip de procedencia NO inventa un glifo: con `glyph == nil` (las ~28 métricas del
    /// Explorador sin glifo canónico) no dibuja el badge de glifo — la identidad la lleva el punto de
    /// tono. Con un glifo concreto (todos los demás call sites) el badge se conserva.
    func test_origenChip_sinGlifoNoDibujaBadge() {
        let sinGlifo = LiquidOrigenChip(glyph: nil, badgeTono: LiquidColor.verdePrimario,
                                        etiqueta: "En tu dispositivo")
        XCTAssertFalse(sinGlifo.dibujaBadge, "sin glifo canónico el chip no debe dibujar badge")
        let conGlifo = LiquidOrigenChip(glyph: .corazon, badgeTono: LiquidColor.rosa,
                                        etiqueta: "Apple Salud")
        XCTAssertTrue(conGlifo.dibujaBadge, "con un glifo concreto el badge se conserva")
    }

    func test_a11y_zoneMeter() {
        let segmentos: [LiquidZoneMeter.Segmento] = [
            .init(peso: 1, color: .red, activa: false, etiqueta: "AGOTADO"),
            .init(peso: 1, color: .green, activa: true, etiqueta: "LISTO"),
        ]
        XCTAssertEqual(LiquidZoneMeter.a11yLabel(segmentos: segmentos), "LISTO")
        let ninguna = segmentos.map {
            LiquidZoneMeter.Segmento(peso: $0.peso, color: $0.color,
                                     activa: false, etiqueta: $0.etiqueta)
        }
        XCTAssertEqual(LiquidZoneMeter.a11yLabel(segmentos: ninguna), "")
    }

    // MARK: Lectura de la hoja (negrita del veredicto)

    /// La negrita cae en el veredicto sin necesitar una clave por frase (pasada UX H5).
    func test_lectura_clausulaDelVeredicto() {
        // Con coma: solo la primera cláusula.
        XCTAssertEqual(LiquidReadingLine.clausulaVeredicto("Por encima de tu base, buena señal."),
                       "Por encima de tu base")
        XCTAssertEqual(LiquidReadingLine.clausulaVeredicto("Above your base, a good sign."),
                       "Above your base")
        // Sin coma: la frase completa, sin el punto final.
        XCTAssertEqual(LiquidReadingLine.clausulaVeredicto("En tu rango de siempre."),
                       "En tu rango de siempre")
        // Degenerados: nada que destacar.
        XCTAssertNil(LiquidReadingLine.clausulaVeredicto(""))
        XCTAssertNil(LiquidReadingLine.clausulaVeredicto(","))
        XCTAssertNil(LiquidReadingLine.clausulaVeredicto("."))
    }

    // MARK: Render de humo (macOS)

    #if os(macOS)
    /// La pantalla Hoy renderiza completa (motion congelado) sin crashear y produce PNG.
    @MainActor
    func test_renderHoyScreen() throws {
        let view = LiquidHoyScreen(scrolls: false)
            .environment(\.liquidMotionDisabled, true)
            .frame(width: 402, height: 874)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer no produjo imagen")
            return
        }
        XCTAssertGreaterThan(png.count, 50_000, "el PNG salió sospechosamente vacío")
        let url = URL(fileURLWithPath: "/tmp/noop-liquid/hoy_liquid.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
    #endif
}
