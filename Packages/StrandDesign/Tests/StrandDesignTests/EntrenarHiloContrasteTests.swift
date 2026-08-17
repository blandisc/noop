import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-83/85 — la palabra del hilo del veredicto se lee sobre el RELLENO teñido de su pastilla, no
/// sobre el papel pelón. Medir el contraste contra el papel dejaba las tres palabras por debajo del
/// piso de AA justo donde el ojo las lee, y ese es el tipo de defecto que ningún ojo humano
/// dictamina con seguridad: se mide.
final class EntrenarHiloContrasteTests: XCTestCase {

    private let theme = InstrumentoTheme.base

    /// El fondo real bajo la palabra: papel con el tinte del veredicto al 12 %.
    private func fondo(_ tone: EntrenarHilo.Tone) -> Color {
        OKLab.blend(tone.dot(theme), over: theme.paper, alpha: EntrenarMetrics.pillFillAlpha)
    }

    func testLaPalabraCumpleAAsobreElRellenoDeSuPastilla() {
        for tone in [EntrenarHilo.Tone.clear, .caution, .ease] {
            let ratio = OKLab.contrastRatio(tone.word(theme), fondo(tone))
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(tone) da \(ratio):1 sobre su propio relleno")
        }
    }

    /// La variante hueca no lleva relleno: su piso se mide contra el papel.
    func testLaVarianteHuecaCumpleAAsobreElPapel() {
        let ratio = OKLab.contrastRatio(EntrenarHilo.Tone.hollow.word(theme), theme.paper)
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "hueca da \(ratio):1")
    }

    /// El velo del relleno oscurece: si el mezclado devolviera el papel tal cual, esta prueba no
    /// probaría nada. Se ancla el mezclado mismo.
    func testElMezcladoDeVerasOscureceElPapel() {
        for tone in [EntrenarHilo.Tone.clear, .caution, .ease] {
            let mezcla = fondo(tone)
            XCTAssertLessThan(OKLab.relativeLuminance(mezcla),
                              OKLab.relativeLuminance(theme.paper),
                              "\(tone): el relleno tiene que oscurecer el papel")
        }
    }
}
