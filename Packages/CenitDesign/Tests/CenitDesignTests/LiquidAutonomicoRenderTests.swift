import XCTest
import SwiftUI
@testable import CenitDesign

/// Arnés de renders de la hoja del eje AUTONÓMICO (FER-1045, sesión /inject): escribe un PNG por
/// estado a /tmp/noop-liquid/ para verificación visual. Run: swift test --filter LiquidAutonomicoRenderTests
final class LiquidAutonomicoRenderTests: XCTestCase {

    #if os(macOS)
    @MainActor
    func test_renderAutonomicoEstados() throws {
        for (nombre, model) in Self.estados {
            let view = LiquidAutonomicoScreen(model)
                .padding(LiquidSpace.s550)
                .frame(width: 402, alignment: .topLeading)
                .background(LiquidSheetFondo(tone: model.tono))
                .environment(\.liquidMotionDisabled, true)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                XCTFail("ImageRenderer no produjo imagen para \(nombre)")
                continue
            }
            XCTAssertGreaterThan(png.count, 20_000, "\(nombre): PNG sospechosamente vacío")
            let url = URL(fileURLWithPath: "/tmp/noop-liquid/autonomico_\(nombre).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? png.write(to: url)
            print("WROTE \(url.path)")
        }
    }
    #endif

    static let estados: [(String, LiquidAutonomico)] = [
        ("1_enRango", LiquidAutonomicoFixtures.enRango),
        ("2_fcFuera", LiquidAutonomicoFixtures.unaFuera),
        ("3_sinBase", LiquidAutonomicoFixtures.sinBase),
    ]
}
