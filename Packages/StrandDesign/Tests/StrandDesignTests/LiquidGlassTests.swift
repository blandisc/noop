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
            for d in spec.paths + spec.paths2 {
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
        XCTAssertEqual(LiquidSignalOrb.a11yLabel(label: "AUTONÓMICO", caption: "EN TU RANGO"),
                       "AUTONÓMICO: EN TU RANGO")
        XCTAssertEqual(LiquidCargaBar.a11yLabel(label: "CARGA", status: "EN EQUILIBRIO · 1.03"),
                       "CARGA: EN EQUILIBRIO · 1.03")
        XCTAssertEqual(
            LiquidHeroVeredicto.a11yLabel(title: "Dale\ncon todo",
                                          subtitle: "Tus 3 señales amanecieron dentro de tu rango.",
                                          confianza: "Confianza: 12 de 21 noches"),
            "Dale con todo. Tus 3 señales amanecieron dentro de tu rango. Confianza: 12 de 21 noches")
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
