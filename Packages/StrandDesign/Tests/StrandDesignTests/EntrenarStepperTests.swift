import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-293: contrato de tallas del stepper — el valor y los botones cambian de tamaño
/// según `.fila` / `.hoja`; el caller formatea el string.
final class EntrenarStepperTests: XCTestCase {
    func testTallasExisten() {
        // Compila el API público: ambas tallas + tono + extremos.
        _ = EntrenarStepper(valor: "+2,5 kg", tono: .verde, talla: .fila,
                            puedeBajar: true, puedeSubir: true, onBajar: {}, onSubir: {})
        _ = EntrenarStepper(valor: "1:30", tono: .neutro, talla: .hoja,
                            puedeBajar: false, puedeSubir: true, onBajar: {}, onSubir: {})
    }

    func testLiquidToggleStyleAPI() {
        _ = LiquidToggleStyle()
        let style: any ToggleStyle = .liquid
        _ = String(describing: style)
    }

    func testLiquidFlowTitleAPI() {
        _ = LiquidFlowTitle(kicker: "7 recibos · toca uno para reimprimir",
                            titulo: "Tickets guardados")
        _ = LiquidFlowTitle(titulo: "Tickets guardados")
    }

    func testLiquidPatternBlockOverlineOpcional() {
        _ = LiquidPatternBlock(overline: "Con este plan",
                               lineas: ["4×8 con 100 kg."],
                               tono: LiquidColor.verdeCarga)
        _ = LiquidPatternBlock(lineas: ["Sin overline."], tono: LiquidColor.tinta10)
        // Sin líneas → EmptyView (no crashea al construir).
        _ = LiquidPatternBlock(overline: "Huérfano", lineas: [], tono: LiquidColor.cian)
    }
}
