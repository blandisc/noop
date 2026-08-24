import XCTest
import SwiftUI
@testable import StrandDesign

/// Renders a PNG de los tres estados visuales de FER-129 que ninguna prueba de contrato puede
/// ver y que el simulador compartido no dejó capturar: la leyenda en flujo a ancho de iPhone
/// (¿envuelve el peldaño entero o parte el texto?), el campo con la palabra a displayL, y el
/// campo con el guion. Patrón `ChartSnapshotTests`: ImageRenderer → /tmp, para mirarlos.
#if canImport(AppKit)
@MainActor
final class PreparacionRenderTests: XCTestCase {

    private func escribe<V: View>(_ v: V, _ nombre: String, ancho: CGFloat = 402) throws {
        let renderer = ImageRenderer(content: v.frame(width: ancho).padding(LiquidSpace.s550)
                                                   .background(LiquidColor.fondoGradient))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-fer129/\(nombre).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }

    func testLeyendaEnFlujoAAnchoDeiPhone() throws {
        let cuatro: [LiquidCalendario90.NivelLeyenda] = [
            .init(id: "full", color: LiquidColor.verdePrimario, etiqueta: "Todo en rango"),
            .init(id: "caution", color: LiquidColor.atencion, etiqueta: "Una señal fuera"),
            .init(id: "easy", color: LiquidColor.negativo, etiqueta: "Dos o más fuera"),
            .init(id: "none", color: LiquidColor.celdaVaciaPip, etiqueta: "Sin lectura"),
        ]
        // 402 − 2×22 de margen = 358 pt útiles, el ancho real de la sección en iPhone.
        try escribe(LiquidLeyendaNiveles(cuatro), "leyenda_flujo", ancho: 358)
    }

    func testCampoConPalabraYConGuion() throws {
        try escribe(LiquidCampoMetrica(tono: LiquidColor.atencion, titulo: "Preparación", datos: [],
                                       palabra: "Hoy ve leve",
                                       clausula: "Tu FC en reposo amaneció arriba de tu base.") {
            LiquidCampoSello("39 noches de tu base")
        }, "campo_palabra")
        try escribe(LiquidCampoMetrica(tono: LiquidColor.tinta500, titulo: "Preparación", datos: [],
                                       palabra: "—", clausula: "Sin veredicto esta mañana."),
                    "campo_guion")
    }
}
#endif
