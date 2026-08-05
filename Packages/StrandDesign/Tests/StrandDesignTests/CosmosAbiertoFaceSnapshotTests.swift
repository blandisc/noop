#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-51 · Lane C — arnés de renders de la cara Cosmos abierta (día bueno / malo / calibrando).
/// No es aserción de CI: PNGs en /tmp/noop-fer51/.
/// Run: swift test --filter CosmosAbiertoFaceSnapshotTests
final class CosmosAbiertoFaceSnapshotTests: XCTestCase {

    @MainActor func test_diaBueno() throws {
        try render(CosmosAbiertoFace(model: .previewDiaBueno)
            .frame(width: 390, height: 820),
                   to: "cosmos_abierto_dia_bueno")
    }

    @MainActor func test_diaMalo() throws {
        try render(CosmosAbiertoFace(model: .previewDiaMalo)
            .frame(width: 390, height: 820),
                   to: "cosmos_abierto_dia_malo")
    }

    @MainActor func test_calibrando() throws {
        try render(CosmosAbiertoFace(model: .previewCalibrando)
            .frame(width: 390, height: 820),
                   to: "cosmos_abierto_calibrando")
    }

    @MainActor private func render<V: View>(_ content: V, to name: String) throws {
        let renderer = ImageRenderer(content: content)
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
