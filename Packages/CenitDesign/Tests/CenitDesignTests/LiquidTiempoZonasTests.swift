import XCTest
import SwiftUI
@testable import CenitDesign

/// Contrato del reparto de `LiquidTiempoZonas`, en frío (sin simulador).
/// Run: `swift test --filter LiquidTiempoZonasTests`
///
/// Los tres invariantes que el bloque de papel (`MetricDetailScreen.hrZonesBlockContent`)
/// NO cumplía o cumplía por accidente:
///   (a) las 6 zonas se dibujan siempre, aunque estén en cero — el papel filtraba
///       `mins[i] >= 1` y la zona sin minutos desaparecía de la pantalla;
///   (b) las fracciones reparten el TOTAL del día (suman 1), no la zona más alta;
///   (c) un día con total 0 no divide entre cero.
final class LiquidTiempoZonasTests: XCTestCase {

    /// Las 6 zonas del día: `[reposo, Z1…Z5]`, tal como las entrega el cálculo de la app.
    private func zonas(_ minutos: [Double]) -> [LiquidTiempoZonas.Zona] {
        let etiquetas = ["Reposo", "Z1", "Z2", "Z3", "Z4", "Z5"]
        return (0..<minutos.count).map { i in
            LiquidTiempoZonas.Zona(id: i, etiqueta: etiquetas[i], minutos: minutos[i],
                                   color: .red, detalle: nil)
        }
    }

    // MARK: (a) · las 6 zonas siempre están, aunque haya ceros

    /// Un día entero en reposo: las cinco zonas de entrenamiento están en 0 y aun así las
    /// seis siguen en el reparto (riel vacío + etiqueta). Si alguien re-introduce el filtro
    /// del papel, este conteo cae de 6 y el test truena.
    func test_seisZonas_aunqueEstenEnCero() {
        let repartos = LiquidTiempoZonas.partes(zonas([1320, 0, 0, 0, 0, 0]))
        XCTAssertEqual(repartos.count, 6)
        XCTAssertEqual(repartos.map(\.zona.etiqueta),
                       ["Reposo", "Z1", "Z2", "Z3", "Z4", "Z5"])
        // Y las que están en cero se reparten cero: eso es el riel VACÍO en pantalla.
        XCTAssertEqual(repartos[0].fraccion, 1, accuracy: 1e-9)
        for i in 1...5 {
            XCTAssertEqual(repartos[i].fraccion, 0, accuracy: 1e-9)
        }
    }

    /// Ni siquiera un día SIN NADA medido borra zonas: seis entran, seis salen.
    func test_seisZonas_conTodoEnCero() {
        XCTAssertEqual(LiquidTiempoZonas.partes(zonas([0, 0, 0, 0, 0, 0])).count, 6)
    }

    // MARK: (b) · las fracciones reparten el total del día

    /// La proporción es sobre el TOTAL, no sobre la zona más alta: las seis fracciones
    /// suman 1, y ninguna llega a 1 solo por ser la mayor.
    func test_fraccionesSumanUno_sobreElTotal() {
        let repartos = LiquidTiempoZonas.partes(zonas([742, 260, 180, 96, 34, 8]))
        XCTAssertEqual(repartos.reduce(0.0) { $0 + $1.fraccion }, 1, accuracy: 1e-9)
        // Reposo = 742 / 1320.
        XCTAssertEqual(repartos[0].fraccion, 742.0 / 1320.0, accuracy: 1e-9)
        // Z5, la astilla del día, NO se normaliza contra la zona más alta (sería 8/742).
        XCTAssertEqual(repartos[5].fraccion, 8.0 / 1320.0, accuracy: 1e-9)
        XCTAssertLessThan(repartos[0].fraccion, 1)
    }

    // MARK: (c) · total 0 no divide entre cero

    /// Sin minutos que repartir, cada fracción es 0 (finita, no NaN ni ∞): la barra queda
    /// hueca en vez de reventar el layout con un ancho no numérico.
    func test_totalCero_noDivideEntreCero() {
        let repartos = LiquidTiempoZonas.partes(zonas([0, 0, 0, 0, 0, 0]))
        for parte in repartos {
            XCTAssertEqual(parte.fraccion, 0)
            XCTAssertTrue(parte.fraccion.isFinite)
        }
        // Y el mismo reparto alimenta la voz sin producir «nan%».
        XCTAssertEqual(
            LiquidTiempoZonas.a11yValue(zonas: zonas([0, 0, 0, 0, 0, 0]), explicito: "", sinMedicion: ""),
            "Reposo 0%, Z1 0%, Z2 0%, Z3 0%, Z4 0%, Z5 0%")
    }

    /// Lista vacía (el caller no pasó zonas): ni reparto ni división — nada que decir.
    func test_sinZonas_repartoVacio() {
        XCTAssertTrue(LiquidTiempoZonas.partes([]).isEmpty)
        XCTAssertEqual(LiquidTiempoZonas.a11yValue(zonas: [], explicito: "", sinMedicion: ""), "")
    }

    // MARK: VoiceOver · la frase del caller manda; si no la hay, se deriva del reparto

    /// El `a11yValue` del caller es donde vive el total del día en minutos (la palabra
    /// «minutos» es copy: el DS no la inventa). Si llega, gana.
    func test_a11yValue_explicitoGana() {
        XCTAssertEqual(
            LiquidTiempoZonas.a11yValue(zonas: zonas([742, 260, 180, 96, 34, 8]),
                                        explicito: "138 minutos en zona 3 o más alta", sinMedicion: ""),
            "138 minutos en zona 3 o más alta")
    }

    /// Sin frase del caller, la voz lee el MISMO reparto que pinta la barra, en por ciento.
    func test_a11yValue_derivadoDelReparto() {
        XCTAssertEqual(
            LiquidTiempoZonas.a11yValue(zonas: zonas([660, 660, 0, 0, 0, 0]), explicito: "", sinMedicion: ""),
            "Reposo 50%, Z1 50%, Z2 0%, Z3 0%, Z4 0%, Z5 0%")
    }
}
