import XCTest
import SwiftUI
@testable import StrandDesign

/// DESECHABLE (FER-28): renders de medición/comparación de «El Tablero». Se borra al cerrar Ola 3.
final class ZZTableroMedidaRenderTests: XCTestCase {
    #if os(macOS)
    @MainActor
    func test_render_tablero_iphone() throws {
        struct Caso {
            let nombre: String; let w: CGFloat; let h: CGFloat
            let fase: EcosistemaSimulacion.Fase?; let alto: CGFloat?
        }
        let casos: [Caso] = [
            .init(nombre: "sweep_200", w: 390, h: 844, fase: nil, alto: 200),
            .init(nombre: "sweep_216", w: 390, h: 844, fase: nil, alto: 216),
            .init(nombre: "sweep_232", w: 390, h: 844, fase: nil, alto: 232),
            .init(nombre: "final_393", w: 393, h: 852, fase: nil, alto: nil),
            .init(nombre: "final_390", w: 390, h: 844, fase: nil, alto: nil),
            .init(nombre: "separado", w: 393, h: 852, fase: .separada, alto: nil),
        ]
        for c in casos {
            LiquidTableroDebug.altoCompactoOverride = c.alto
            let view = ZStack {
                LiquidAmbientBackground.tablero(.bien)
                VStack(spacing: 0) {
                    LiquidHoyContent(model: .ejemplo, ecosistemaFase: c.fase)
                        .padding(.top, LiquidSpace.s550)
                    Spacer(minLength: 0)
                }
                .overlay(alignment: .bottom) {
                    LiquidTabBar(active: .hoy, onSelect: nil)
                        .padding(.horizontal, LiquidSpace.dockSide)
                        .padding(.bottom, LiquidSpace.dockBottom)
                }
            }
            .environment(\.liquidMotionDisabled, true)
            .frame(width: c.w, height: c.h)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                XCTFail("sin imagen \(c.nombre)"); continue
            }
            let url = URL(fileURLWithPath: "/tmp/noop-liquid/tab_\(c.nombre).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? png.write(to: url)
            print("WROTE \(url.path)")
        }
        LiquidTableroDebug.altoCompactoOverride = nil
    }
    #endif
}
