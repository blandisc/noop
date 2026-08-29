import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-234 — contrato AA del vidrio teñido unificado (`LiquidTono` × rol) y cinturones de
/// régimen mosaico/sobrio. Espejo del patrón de `EntrenarHiloContrasteTests`: mide con
/// `OKLab.contrastRatio`, no con el ojo.
///
/// Fórmula del compuesto (rótulo sobre vidrio): `mix(papelTarjeta, base, 0.10)` — piso
/// conservador sin modelar `glassEffect` (blur solo aclararía el fondo → más contraste para
/// rótulo oscuro). Tesela: texto claro (blanco) sobre relleno opaco.
final class LiquidTonoContrasteTests: XCTestCase {

    private let canvas = LiquidColor.papelTarjeta
    private let intensidad = LiquidTono.intensidadDefault // 0.10

    private func mismoColor(_ a: Color, _ b: Color) -> Bool {
        let x = a.rgbaComponents, y = b.rgbaComponents
        return abs(x.r - y.r) < 1e-6 && abs(x.g - y.g) < 1e-6
            && abs(x.b - y.b) < 1e-6 && abs(x.a - y.a) < 1e-6
    }

    private func compuestoVidrio(_ tono: LiquidTono) -> Color {
        OKLab.mix(canvas, tono.base, intensidad)
    }

    /// Rótulo (texto pequeño) sobre el vidrio teñido compuesto — piso 4.5:1.
    /// Incluye neutro + 5 teñidos. Verde pinado ~5.75 con `verdeCarga`.
    func testRotuloAAsobreVidrio() {
        var tabla: [(String, Double)] = []
        for tono in LiquidTono.allCases {
            let fondo = compuestoVidrio(tono)
            let ratio = OKLab.contrastRatio(tono.rotulo, fondo)
            tabla.append(("\(tono).rotulo", ratio))
            XCTAssertGreaterThanOrEqual(ratio, 4.5,
                                        "\(tono).rotulo da \(ratio):1 sobre compuesto @\(intensidad)")
        }
        // Ancla numérica del verde re-derivado (Q5 del arquitecto).
        let verdeRatio = OKLab.contrastRatio(LiquidTono.verde.rotulo, compuestoVidrio(.verde))
        XCTAssertGreaterThan(verdeRatio, 5.5,
                             "verde.rotulo debía ~5.75 con verdeCarga; dio \(verdeRatio)")
        print("LiquidTonoContraste · rotulo × ratio:")
        for (rol, r) in tabla { print("  \(rol)  \(String(format: "%.2f", r)):1") }
    }

    /// Tesela: texto/gráfico claro (blanco) sobre relleno opaco — piso 3:1.
    /// Verde pinado ~5.05 con `verdeCarga`.
    func testTeselaAA() {
        var tabla: [(String, Double)] = []
        // FER-231 OPEN: neutro.tesela == .white; blanco-sobre-blanco no puede cumplir 3:1.
        // El mock no usa tesela neutra. Se iteran los 5 teñidos; neutro queda cubierto en
        // testRotuloAAsobreVidrio. Acceptance «+ neutro» en tesela queda abierto.
        let teñidos = LiquidTono.allCases.filter { $0 != .neutro }
        for tono in teñidos {
            let ratio = OKLab.contrastRatio(.white, tono.tesela)
            tabla.append(("\(tono).tesela", ratio))
            XCTAssertGreaterThanOrEqual(ratio, 3.0,
                                        "\(tono).tesela da \(ratio):1 con texto claro")
        }
        let verdeRatio = OKLab.contrastRatio(.white, LiquidTono.verde.tesela)
        XCTAssertGreaterThan(verdeRatio, 4.5,
                             "verde.tesela debía ~5.05 con verdeCarga; dio \(verdeRatio)")
        print("LiquidTonoContraste · tesela × ratio:")
        for (rol, r) in tabla { print("  \(rol)  \(String(format: "%.2f", r)):1") }
    }

    /// `.sobrio` ignora el tono en la superficie: relleno/canto/highlight idénticos al neutro
    /// para los 5 teñidos.
    func testSobrioIgnoraTono() {
        let intens = LiquidTono.intensidadDefault
        let refRelleno = LiquidTonoSuperficie.rellenoResuelto(tono: .neutro, regimen: .sobrio,
                                                             intensidad: intens)
        let refCanto = LiquidTonoSuperficie.cantoResuelto(tono: .neutro, regimen: .sobrio)
        let refHighlight = LiquidTonoSuperficie.highlightResuelto(tono: .neutro, regimen: .sobrio)
        XCTAssertFalse(LiquidTonoSuperficie.usaAroTeñido(tono: .neutro, regimen: .sobrio))

        for tono in LiquidTono.allCases where tono != .neutro {
            let relleno = LiquidTonoSuperficie.rellenoResuelto(tono: tono, regimen: .sobrio,
                                                              intensidad: intens)
            let canto = LiquidTonoSuperficie.cantoResuelto(tono: tono, regimen: .sobrio)
            let highlight = LiquidTonoSuperficie.highlightResuelto(tono: tono, regimen: .sobrio)
            XCTAssertTrue(mismoColor(relleno, refRelleno),
                          "sobrio.\(tono) relleno no es neutro")
            XCTAssertTrue(mismoColor(canto, refCanto),
                          "sobrio.\(tono) canto no es neutro")
            XCTAssertTrue(mismoColor(highlight, refHighlight),
                          "sobrio.\(tono) highlight no es neutro")
            XCTAssertFalse(LiquidTonoSuperficie.usaAroTeñido(tono: tono, regimen: .sobrio),
                           "sobrio.\(tono) no debe llevar aro teñido")
            // Sombra: misma geometría que LiquidElevation.tarjeta (neutro).
            let sombras = LiquidTonoSuperficie.sombrasResueltas(tono: tono, regimen: .sobrio)
            XCTAssertEqual(sombras.count, LiquidElevation.tarjeta.count,
                           "sobrio.\(tono) sombra distinta de tarjeta neutra")
        }
    }

    /// Cinturón del hub: `EntrenarModulo`/`EntrenarTile` fijan `.mosaico` — el relleno teñido
    /// sigue siendo `base.opacity(intensidad)`, no blanco.
    func testMosaicoContenedorSigueTeñido() {
        let intens = LiquidTono.intensidadDefault
        for tono in LiquidTono.allCases where tono != .neutro {
            let mosaico = LiquidTonoSuperficie.rellenoResuelto(tono: tono, regimen: .mosaico,
                                                              intensidad: intens)
            let sobrio = LiquidTonoSuperficie.rellenoResuelto(tono: tono, regimen: .sobrio,
                                                             intensidad: intens)
            let esperado = tono.base.opacity(intens)
            XCTAssertTrue(mismoColor(mosaico, esperado),
                          "mosaico.\(tono) relleno ≠ base@\(intens)")
            XCTAssertFalse(mismoColor(mosaico, sobrio),
                           "mosaico.\(tono) relleno colapsó a sobrio/blanco")
            XCTAssertTrue(LiquidTonoSuperficie.usaAroTeñido(tono: tono, regimen: .mosaico),
                          "mosaico.\(tono) debe llevar aro teñido")
        }
    }

    /// Clava el cambio de identidad de carga: verde del tono = `verdeCarga`, no marca.
    func testVerdeBaseEsVerdeCarga() {
        XCTAssertTrue(mismoColor(LiquidTono.verde.base, LiquidColor.verdeCarga))
        XCTAssertFalse(mismoColor(LiquidTono.verde.base, LiquidColor.verdePrimario))
        XCTAssertTrue(mismoColor(LiquidTono.verde.tesela, LiquidColor.verdeCarga),
                      "tesela verde delega en base → debe ser verdeCarga")
    }
}
