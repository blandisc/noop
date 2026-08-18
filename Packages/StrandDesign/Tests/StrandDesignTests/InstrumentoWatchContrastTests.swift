import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-96 — the wrist's dark floor (`InstrumentoTheme.watch`) is a brand-new preset with its own 18
/// hand-picked hexes; a header comment claiming "recalculated for AA" doesn't verify anything — a
/// mis-picked hex here ships an unreadable watch face. Every text/data role is measured against
/// `theme.watch.paper` with the SAME authority `EntrenarHiloContrasteTests` already uses for the
/// iPhone (`OKLab.contrastRatio`), never eyeballed and never a render-only snapshot.
final class InstrumentoWatchContrastTests: XCTestCase {
    private let theme = InstrumentoTheme.watch

    private var inkRoles: [(String, Color)] {
        [("ink", theme.ink), ("inkSecondary", theme.inkSecondary), ("inkTertiary", theme.inkTertiary)]
    }

    private var dataAndVerdictRoles: [(String, Color)] {
        [("dataRecovery", theme.dataRecovery), ("dataStrain", theme.dataStrain),
         ("dataSleep", theme.dataSleep), ("dataHrv", theme.dataHrv),
         ("dataHeart", theme.dataHeart), ("dataSpO2", theme.dataSpO2),
         ("dataOxygen", theme.dataOxygen), ("dataSteps", theme.dataSteps),
         ("verdict", theme.verdict), ("warning", theme.warning), ("critical", theme.critical)]
    }

    func testLosRolesDeTintaCumplenAASobreElSueloOscuro() {
        for (name, color) in inkRoles {
            let ratio = OKLab.contrastRatio(color, theme.paper)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) da \(ratio):1 sobre el suelo oscuro")
        }
    }

    func testLosRolesDeDatoYVeredictoCumplenAASobreElSueloOscuro() {
        for (name, color) in dataAndVerdictRoles {
            let ratio = OKLab.contrastRatio(color, theme.paper)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) da \(ratio):1 sobre el suelo oscuro")
        }
    }

    /// El punto de esta fase (Alcance §2): el reloj pide negro real, no el papel del iPhone. Si alguien
    /// revierte `.watch.paper` al mismo hex que `.base.paper` (el bug que este épico corrige), esta
    /// prueba truena — nunca «casi negro», el hex exacto debe seguir siendo distinto y su luminancia baja.
    func testElSueloDelRelojEsNegroDeVerdadYPropio() {
        XCTAssertNotEqual(theme.paper, InstrumentoTheme.base.paper,
                          "el reloj no puede seguir pintando el papel claro del iPhone")
        XCTAssertLessThan(OKLab.relativeLuminance(theme.paper), 0.05,
                          "el suelo del reloj debe leer como negro, no como un gris claro")
    }

    /// «El reloj hereda la voz, no el suelo» (Alcance §2 del spec): el verdict sigue siendo el MISMO hue
    /// que `dataRecovery`, igual que en `.base` — el patrón de identidad no se rompe al cambiar de fondo.
    func testElVeredictoSigueSiendoElMismoHueQueRecoveryComoEnBase() {
        XCTAssertEqual(theme.verdict, theme.dataRecovery)
        XCTAssertEqual(InstrumentoTheme.base.verdict, InstrumentoTheme.base.dataRecovery)
    }
}
