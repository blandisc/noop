#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-51 — arnés de renders del sello-ícono (8 glifos) para verificación visual.
/// PNGs en /tmp/noop-fer51/. Run: swift test --filter SelloIconoSnapshotTests
final class SelloIconoSnapshotTests: XCTestCase {

    @MainActor func test_ocho_glifos() throws {
        let items: [(SelloIcono.Glifo, Color, (Color, Color)?)] = [
            (.luna, LiquidColor.indigo, nil),
            (.corazon, LiquidColor.rosa, nil),
            (.onda, LiquidColor.cian, nil),
            (.escudo, LiquidColor.doradoTemp, (LiquidColor.doradoTemp, LiquidColor.azul)),
            (.montana, LiquidColor.verdePrimario, nil),
            (.flama, LiquidColor.teal, nil),
            (.rayo, LiquidColor.tinta900, nil),
            (.huellas, LiquidColor.tinta500, nil),
        ]
        try render(HStack(spacing: 14) {
            ForEach(0..<items.count, id: \.self) { i in
                SelloIcono(glifo: items[i].0, hue: items[i].1, huesPar: items[i].2)
            }
        }, to: "sello_ocho_glifos")
    }

    @MainActor func test_tamanos() throws {
        try render(HStack(spacing: 20) {
            SelloIcono(glifo: .luna, hue: LiquidColor.indigo, radio: 9)
            SelloIcono(glifo: .corazon, hue: LiquidColor.rosa, radio: 12)
            SelloIcono(glifo: .escudo, hue: LiquidColor.doradoTemp,
                       huesPar: (LiquidColor.doradoTemp, LiquidColor.azul), radio: 14)
        }, to: "sello_tamanos")
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
