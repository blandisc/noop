#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// Harness de render (no es aserción de CI): dibuja el héroe «El Ecosistema» a PNG en sus DOS
/// estados fundidos — con veredicto y sin lectura — para eyeballear A′ (FER-157: los rótulos de
/// las señales despegan del orbe). En macOS el orbe toma el camino Canvas (no Metal), así que
/// `ImageRenderer` sí lo pinta. `still` (motion disabled) asienta el cuadro para un render estable.
/// Run: swift test --filter EcosistemaRotuloAlFiloRenderTests
final class EcosistemaRotuloAlFiloRenderTests: XCTestCase {

    @MainActor
    private func render(_ view: some View, a nombre: String) throws {
        let host = ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()
            view.padding(.horizontal, LiquidSpace.s550)
        }
        .frame(width: 380, height: 360)
        .environment(\.liquidMotionDisabled, true)   // → still: cuadro asentado, sin animación
        let renderer = ImageRenderer(content: host)
        renderer.scale = 3
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer no produjo imagen"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-fer157/\(nombre).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }

    /// Estado CON veredicto (fundido, verde) — el look aprobado que A′ debe preservar salvo por
    /// los rótulos que pisaban el orbe.
    @MainActor
    func test_render_conVeredicto() throws {
        let m = LiquidHoyModel.ejemplo
        let v = LiquidEcosistema(
            senales: m.senales, hero: m.hero, guardian: m.guardian,
            ambiente: .bien, calibracion: nil, rotulos: .base,
            heroPuerta: "Cómo llegué a esto", faseForzada: .viva(desde: 0))
        try render(v, a: "con_veredicto")
    }

    /// Estado SIN lectura (demotado, neutra) — SIN kicker PREPARACIÓN (dueño 2026-08-26) y con el
    /// subtítulo corto (2 líneas). Donde el dueño reportó el traslape + el kicker de más.
    @MainActor
    func test_render_sinVeredicto() throws {
        let m = LiquidHoyModel.ejemplo
        let hero = LiquidHoyModel.Hero.demotado(
            kicker: nil,
            title: "Todavía no puedo leer tus mañanas",
            subtitle: "Se apoya en tu FC en reposo de la noche, que aún no llega. Dormir con tu Apple Watch la destraba.")
        let v = LiquidEcosistema(
            senales: m.senales, hero: hero, guardian: m.guardian,
            ambiente: .neutro, calibracion: nil, rotulos: .base,
            heroInfo: true, faseForzada: .viva(desde: 0))
        try render(v, a: "sin_veredicto")
    }
}
#endif
