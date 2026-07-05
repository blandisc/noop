#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// Renders the `PoincareCloud` (FER-666) to a PNG so the steady comet vs. varied diffuse cloud vs.
/// faded calibrating state can be eyeballed against the approved «Instrumento» preview. Developer
/// render harness, not a CI assertion. Run: swift test --filter PoincareCloudSnapshotTests
final class PoincareCloudSnapshotTests: XCTestCase {

    private func demo(n: Int, sd1: Double, sd2: Double, seed: UInt64) -> [CGPoint] {
        var s = seed
        func rnd() -> Double { s = s &* 1664525 &+ 1013904223; return Double(s % 100_000) / 100_000 }
        func gauss() -> Double { let u = max(rnd(), 1e-9), v = rnd(); return (-2 * log(u)).squareRoot() * cos(2 * .pi * v) }
        return (0..<n).map { _ in
            let along = gauss() * sd2, perp = gauss() * sd1
            return CGPoint(x: 1000 + (along + perp) / 2.0.squareRoot(),
                           y: 1000 + (along - perp) / 2.0.squareRoot())
        }
    }

    @MainActor
    func test_renderPoincareStates() throws {
        let view = HStack(spacing: 20) {
            cell("ESTABLE", PoincareCloud(points: demo(n: 150, sd1: 20, sd2: 55, seed: 3), summary: "estable"))
            cell("VARIÓ", PoincareCloud(points: demo(n: 150, sd1: 110, sd2: 120, seed: 7), summary: "varió"))
            cell("CALIBRANDO", PoincareCloud(points: demo(n: 34, sd1: 24, sd2: 52, seed: 11), faded: true, summary: "calib"))
        }
        .padding(24)
        .frame(width: 560, height: 230)
        .background(InstrumentoTheme.base.paper)
        .environment(\.instrumentoTheme, .base)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-fer666/poincare_states.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }

    private func cell(_ title: String, _ cloud: PoincareCloud) -> some View {
        VStack(spacing: 8) {
            Text(title).instrumentoOverline().foregroundStyle(InstrumentoTheme.base.inkTertiary)
            cloud.frame(width: 150)
        }
    }
}
#endif
