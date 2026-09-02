import XCTest
@testable import CenitDesign

/// Contrato mínimo de `LiquidHaptica` (FER-269b): el catálogo existe y el mapeo
/// rol → estilo es exactamente el declarado por el inventario de call sites.
final class LiquidHapticaTests: XCTestCase {

    func testCatalogoTieneLosCuatroRolesDelInventario() {
        XCTAssertEqual(
            Set(LiquidHaptica.allCases.map(\.rawValue)),
            Set(["toque", "acento", "confirmacion", "advertencia"])
        )
    }

    func testMapeoRolAEstiloEsElDeclarado() {
        let esperado: [LiquidHaptica: String] = [
            .toque:        "impact.medium",
            .acento:       "impact.heavy",
            .confirmacion: "notification.success",
            .advertencia:  "notification.warning",
        ]
        for rol in LiquidHaptica.allCases {
            XCTAssertEqual(
                rol.estiloDeclarado,
                esperado[rol],
                "\(rol.rawValue) debe mapear al estilo del inventario, no a uno nuevo"
            )
            // La firma declarativa existe para cada rol (compila + no traga el switch).
            _ = rol.feedback
        }
    }

    func testDispararNoTragaFueraDeIOS() {
        // No-op seguro en macOS / Linux de los tests del paquete; en iOS dispara el generador.
        for rol in LiquidHaptica.allCases {
            LiquidHaptica.disparar(rol)
        }
    }
}
