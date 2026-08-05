#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-51 — arnés de renders del medidor lunar (sabores × estados) para verificación
/// visual del dueño. No es aserción de CI: PNGs en /tmp/noop-fer51/.
/// Run: swift test --filter MedidorLunarSnapshotTests
final class MedidorLunarSnapshotTests: XCTestCase {

    @MainActor func test_sabores() throws {
        try render(HStack(spacing: 24) {
            MedidorLunar(radioAnillo: 22, sabor: .progreso,
                         lunitas: [.init(p: 48, hue: LiquidColor.indigo)])
            MedidorLunar(radioAnillo: 22, sabor: .desviacion,
                         lunitas: [.init(p: 52, hue: LiquidColor.rosa)])
            MedidorLunar(radioAnillo: 21, sabor: .zona,
                         lunitas: [.init(p: 56, hue: LiquidColor.verdePrimario)])
        }, to: "medidor_sabores")
    }

    @MainActor func test_alertas() throws {
        try render(HStack(spacing: 24) {
            MedidorLunar(radioAnillo: 22, sabor: .progreso,
                         lunitas: [.init(p: 88, hue: LiquidColor.indigo, alerta: .atencion)])
            MedidorLunar(radioAnillo: 17, sabor: .desviacion,
                         lunitas: [.init(p: 93, hue: LiquidColor.doradoTemp, alerta: .alarma),
                                   .init(p: 84, hue: LiquidColor.azul, alerta: .alarma)])
        }, to: "medidor_alertas")
    }

    @MainActor func test_punteado_y_fantasma() throws {
        try render(HStack(spacing: 24) {
            MedidorLunar(radioAnillo: 17, sabor: .desviacion,
                         lunitas: [.init(p: 55, hue: LiquidColor.cian)], punteado: true)
            MedidorLunar(radioAnillo: 22, sabor: .desviacion, lunitas: [], fantasma: true)
        }, to: "medidor_punteado_fantasma")
    }

    @MainActor private func render<V: View>(_ content: V, to name: String) throws {
        let renderer = ImageRenderer(content: content.padding(24).background(LiquidColor.papelMatriz))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("no se pudo renderizar \(name)")
        }
        let dir = URL(fileURLWithPath: "/tmp/noop-fer51", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
#endif
