#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-56 — arnés de renders del sello del guardián VIVO (Ola 3), los 6 estados.
/// PNGs en /tmp/noop-fer56/. Run: swift test --filter SelloGuardianVivoSnapshotTests
final class SelloGuardianVivoSnapshotTests: XCTestCase {

    @MainActor func test_seis_estados() throws {
        let estados: [(String, SelloGuardianVivo.Estado)] = [
            ("calma", .calma),
            ("vigila temp", .vigilaTemp),
            ("vigila resp", .vigilaResp),
            ("ambas · ambar", .ambasAmbar),
            ("ambas · roja", .ambasRoja),
            ("sin datos", .sinDatos),
        ]
        try render(HStack(alignment: .top, spacing: 26) {
            ForEach(0..<estados.count, id: \.self) { i in
                VStack(spacing: 12) {
                    SelloGuardianVivo(radio: 18,
                                      hueTemp: LiquidColor.doradoTemp,
                                      hueResp: LiquidColor.azul,
                                      estado: estados[i].1)
                    Text(estados[i].0)
                        .font(.system(size: 10))
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
        }, to: "sello_guardian_estados")
    }

    /// Los tres a tamaño de sello real (radio de la Matriz) junto a un rótulo, para juzgar
    /// legibilidad a la escala en que vive.
    @MainActor func test_tamano_real() throws {
        let reales: [(String, SelloGuardianVivo.Estado)] =
            [("calma", .calma), ("ambas · ambar", .ambasAmbar), ("ambas · roja", .ambasRoja)]
        try render(VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<reales.count, id: \.self) { i in
                HStack(spacing: 8) {
                    SelloGuardianVivo(radio: 10,
                                      hueTemp: LiquidColor.doradoTemp,
                                      hueResp: LiquidColor.azul,
                                      estado: reales[i].1)
                    Text("GUARDIÁN")
                        .font(LiquidType.tituloFila)
                        .foregroundStyle(LiquidColor.tinta700)
                        .textCase(.uppercase)
                    Text(reales[i].0).font(.system(size: 10)).foregroundStyle(LiquidColor.tinta500)
                }
            }
        }, to: "sello_guardian_tamano_real")
    }

    @MainActor private func render<V: View>(_ content: V, to name: String) throws {
        let renderer = ImageRenderer(content: content.padding(28).background(LiquidColor.papelMatriz))
        renderer.scale = 3
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("no se pudo renderizar \(name)")
        }
        let dir = URL(fileURLWithPath: "/tmp/noop-fer56", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
#endif
