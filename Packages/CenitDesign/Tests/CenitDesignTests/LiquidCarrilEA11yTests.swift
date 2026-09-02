import XCTest
import SwiftUI
@testable import CenitDesign

/// Carril E del plan de restauración de la hoja Liquid — accesibilidad menor del DS.
/// Cubre los dos defectos que ningún compilador atrapa: una voz que contradice a la
/// pantalla (E2) y un blanco táctil bajo el mínimo de Apple (E4).
/// Run: swift test --filter LiquidCarrilEA11yTests
final class LiquidCarrilEA11yTests: XCTestCase {

    // MARK: E2 · la voz y la pantalla deciden el pozo vacío con el MISMO umbral

    private static let ancla = Date(timeIntervalSinceReferenceDate: 774_500_000)

    private static func serie(_ n: Int) -> [(fecha: Date, valor: Double)] {
        (0..<n).map { i in
            (fecha: ancla.addingTimeInterval(Double(i - (n - 1)) * 86_400),
             valor: 56.0 + Double(i))
        }
    }

    private static func grafica(_ puntos: [(fecha: Date, valor: Double)],
                                estado: LiquidChartEstado = .datos) -> LiquidGraficaNiveles {
        LiquidGraficaNiveles(
            puntos: puntos,
            bandas: [.init(lo: 49, hi: 71, color: LiquidColor.cian, activa: true)],
            dominio: 30...95,
            ticksY: [(71, "71"), (49, "49")],
            tono: LiquidColor.cian,
            formatoScrub: { v, _ in "\(Int(v)) ms" },
            estado: estado,
            estadoVacio: "Sin lecturas en este rango.",
            a11yLabel: "VFC, últimos 30 días")
    }

    /// El defecto: `body` pinta el pozo vacío con `puntos.count <= 1`, pero la voz sólo
    /// callaba con `isEmpty` ⇒ con UNA lectura VoiceOver decía «56 ms» sobre una pantalla
    /// que decía «Sin lecturas en este rango».
    func test_e2_unSoloPunto_laVozDiceElPozoVacio() {
        XCTAssertEqual(Self.grafica(Self.serie(1)).valorA11y, "Sin lecturas en este rango.",
                       "con 1 punto la pantalla muestra el pozo: la voz debe decir lo mismo")
    }

    func test_e2_serieVacia_laVozDiceElPozoVacio() {
        XCTAssertEqual(Self.grafica([]).valorA11y, "Sin lecturas en este rango.")
    }

    /// No-regresión: con serie de verdad la voz sigue leyendo el último punto.
    func test_e2_conDatos_laVozSigueLeyendoElUltimoPunto() {
        XCTAssertEqual(Self.grafica(Self.serie(14)).valorA11y, "69 ms")
    }

    /// Los estados explícitos del caller mandan sobre el conteo (contrato de siempre).
    func test_e2_estadosDelCallerIntactos() {
        XCTAssertEqual(Self.grafica(Self.serie(14), estado: .cargando).valorA11y, "")
        XCTAssertEqual(Self.grafica(Self.serie(14), estado: .vacio("Otro mensaje.")).valorA11y,
                       "Otro mensaje.")
    }

    // MARK: E4 · blanco táctil del selector de periodo

    #if os(macOS)
    /// El segmento se dibuja a `selectorAlto` (28) pero se toca en 44: el mínimo HIG.
    /// Se mide el render real —no el token— porque el arreglo vive en el layout.
    @MainActor
    func test_e4_selectorSeTocaEn44AunqueSeVeaEn28() throws {
        struct Caja: View {
            @State var seleccion = 0
            var body: some View {
                LiquidRangeSelector(opciones: ["S", "M", "3M", "6M", "1A", "TODO"],
                                    seleccion: $seleccion)
                    .frame(width: 320)
            }
        }
        let renderer = ImageRenderer(content: Caja())
        let alto = try XCTUnwrap(renderer.nsImage?.size.height)
        XCTAssertGreaterThanOrEqual(alto, 44,
            "el selector debe ofrecer el blanco táctil de 44 pt (HIG)")
        XCTAssertLessThan(LiquidChart.selectorAlto, alto,
            "y el track visual sigue siendo el de 28: el alto extra es aire, no pastilla")
    }
    #endif
}
