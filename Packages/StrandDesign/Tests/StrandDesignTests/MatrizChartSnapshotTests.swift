#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-51 — arnés de renders de la familia MatrizChart (6 formas × estados) para
/// verificación visual del dueño. No es aserción de CI: PNGs en /tmp/noop-fer51/.
/// Run: swift test --filter MatrizChartSnapshotTests
///
/// Los datasets se izan a locales con tipo EXPLÍCITO: dentro del view-builder de `render`,
/// un `.map` con aritmética + ternario hace que el type-checker infiera a través de toda la
/// cadena y reviente su presupuesto en CI (Xcode 26.6). Tipar aquí lo corta.
final class MatrizChartSnapshotTests: XCTestCase {

    @MainActor func test_columnas() throws {
        let conDatos: [MatrizColumnas.Noche] = (0..<14).map { i in
            let alerta: MedidorLunar.Alerta = i == 13 ? .atencion : (i == 3 ? .alarma : .ninguna)
            return MatrizColumnas.Noche(valor: 5.5 + Double(i % 5) * 0.4, alerta: alerta)
        }
        let vacio = [MatrizColumnas.Noche](repeating: .init(valor: nil), count: 14)
        try render(VStack(spacing: 16) {
            MatrizColumnas(chartID: "sueno", noches: conDatos, referencia: 7, referenciaTag: "7 h",
                           dominio: 4...10, hue: LiquidColor.indigo)
                .frame(width: 320, height: 56)
            MatrizColumnas(chartID: "sueno-vacio", noches: vacio, referencia: 7, referenciaTag: "7 h",
                           dominio: 4...10, hue: LiquidColor.indigo)
                .frame(width: 320, height: 56)
        }, to: "matriz_columnas")
    }

    @MainActor func test_linea_rellena() throws {
        let fc: [Double?] = (0..<20).map { i in 58 + Double(i % 7) - 2 }
        let vfc: [Double?] = (0..<20).map { i in 35 + Double(i % 9) }
        let vacio = [Double?](repeating: nil, count: 20)
        try render(VStack(spacing: 16) {
            MatrizLineaRellena(chartID: "fc", puntos: fc, base: 60, dominio: 50...75,
                               hue: LiquidColor.rosa, alertaHoy: .atencion)
                .frame(width: 160, height: 56)
            MatrizLineaRellena(chartID: "vfc", puntos: vfc, base: 40, dominio: 20...80,
                               hue: LiquidColor.cian, alfa: 0.6)
                .frame(width: 160, height: 56)
            MatrizLineaRellena(chartID: "fc-vacio", puntos: vacio, base: 60, dominio: 50...75,
                               hue: LiquidColor.rosa)
                .frame(width: 160, height: 56)
        }, to: "matriz_linea_rellena")
    }

    @MainActor func test_linea_serena() throws {
        let temp: [Double?] = (0..<20).map { i in Double(i % 5) * 0.15 - 0.3 }
        try render(MatrizLineaSerena(chartID: "guardian-temp", puntos: temp, banda: -0.4...0.4,
                                     dominio: -1...1, hue: LiquidColor.doradoTemp, alertaHoy: .alarma)
                    .frame(width: 320, height: 56),
                   to: "matriz_linea_serena")
    }

    @MainActor func test_riel_zona() throws {
        let estela: [Double] = [0.95, 1.05, 1.2, 0.9, 1.0]
        try render(VStack(spacing: 12) {
            MatrizColina(chartID: "carga", p: 1.12, zona: 0.8...1.3, estela: estela,
                           hue: LiquidColor.verdePrimario)
                .frame(width: 200, height: 28)
            MatrizColina(chartID: "carga-vacia", p: nil, zona: 0.8...1.3, estela: [],
                           hue: LiquidColor.verdePrimario)
                .frame(width: 200, height: 28)
        }, to: "matriz_riel_zona")
    }

    @MainActor func test_barras_mini() throws {
        let valores: [Double?] = (0..<14).map { i in Double(20 + i * 3) }
        try render(MatrizBarrasMini(chartID: "esfuerzo", valores: valores, hue: LiquidColor.teal)
                    .frame(width: 160, height: 40),
                   to: "matriz_barras_mini")
    }

    @MainActor func test_escalerita() throws {
        let niveles: [Int?] = [0, 1, 1, 2, 1, 0, 2]
        let vacio = [Int?](repeating: nil, count: 7)
        try render(VStack(spacing: 12) {
            MatrizEscalerita(chartID: "estres", niveles: niveles, hue: LiquidColor.tinta900)
                .frame(width: 160, height: 36)
            MatrizEscalerita(chartID: "estres-vacio", niveles: vacio, hue: LiquidColor.tinta900)
                .frame(width: 160, height: 36)
        }, to: "matriz_escalerita")
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
