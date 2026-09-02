import XCTest
import SwiftUI
@testable import CenitDesign

/// FER-120 · E8b — `EntrenarStatusPill`/`EntrenarToolCard` reemplazan los `pill()`/`card()` locales
/// duplicados palabra por palabra en `BreathingView` e `IntervalTimerView`. La única lógica que la
/// pieza porta (no es solo chrome inerte) es el color del rótulo sobre la cápsula: como toda
/// pantalla de Entrenar corre sobre `InstrumentoTheme`, el texto de la píldora tiene que cumplir
/// AA (≥ 4.5:1) sobre `theme.surface`, no solo sobre el papel — es donde de verdad se pinta.
final class EntrenarToolChromeTests: XCTestCase {

    private let theme = InstrumentoTheme.base

    /// El texto de la píldora («Ready», «Running», «Session live»…) siempre se pinta con
    /// `theme.ink` — el ADN exige ≥ 4.5:1 para cualquier texto bajo 24 pt, y aquí el fondo real es
    /// `theme.surface` (papel hundido), no `theme.paper`.
    func testElRotuloDeLaPildoraCumpleAASobreSuFondo() {
        let ratio = OKLab.contrastRatio(theme.ink, theme.surface)
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "theme.ink sobre theme.surface da \(ratio):1")
    }

    /// La tarjeta contenida usa el mismo par surface/hairline — el filo tiene que distinguirse del
    /// relleno o la tarjeta se lee como un bloque sin borde (viola «filos de 1 px» del ADN).
    func testElFiloDeLaTarjetaSeDistingueDeSuFondo() {
        XCTAssertNotEqual(theme.hairline, theme.surface,
                          "el filo de EntrenarToolCard tiene que ser un color distinto de su relleno")
    }
}

/// FER-120 — primer uso real de `StrandMotion.gated` para envolver un `withAnimation(_:)` explícito
/// (`IntervalTimerView.finishSession()`). La función existía desde antes sin una sola prueba: si
/// alguien invirtiera la condición (p.ej. `reduceMotion ? animation : nil`), toda la sección seguiría
/// compilando y las 3 pantallas que ya usan `.strandAnimation` (que sí ejercita esta misma función
/// por dentro) fallarían en silencio bajo Reduce Motion — exactamente el bug que este ticket corrige
/// en `finishSession()`.
final class StrandMotionGatedTests: XCTestCase {

    func testSinReduceMotionDevuelveLaAnimacion() {
        let animation = StrandMotion.gated(.snappy, false)
        XCTAssertNotNil(animation, "sin Reduce Motion, gated() no puede apagar la animación")
    }

    func testConReduceMotionApagaLaAnimacion() {
        let animation = StrandMotion.gated(.snappy, true)
        XCTAssertNil(animation, "con Reduce Motion activo, gated() tiene que devolver nil")
    }

    /// Un `Animation?` de entrada `nil` (p.ej. un caller que ya decidió no animar) se queda en
    /// `nil` sin Reduce Motion de por medio — `gated` no inventa una animación de la nada.
    func testAnimacionNilDeEntradaSeQuedaNil() {
        XCTAssertNil(StrandMotion.gated(nil, false))
        XCTAssertNil(StrandMotion.gated(nil, true))
    }
}
