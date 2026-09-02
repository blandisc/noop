import XCTest
import SwiftUI
@testable import CenitDesign

/// FER-988/FER-998 — la salida compartida de la app y su pareja, la acción con nombre.
///
/// Estos dos componentes nacieron sin tests y se adoptaron en nueve pantallas de un jalón. Lo que se
/// fija aquí es lo que puede romperse **en silencio**: un rol que miente en VoiceOver, la variante
/// sobre acento perdiendo contraste, o el área táctil cayendo bajo el mínimo de HIG. Nada de eso
/// falla el build ni se nota en un preview.
final class BackButtonTests: XCTestCase {

    // MARK: - El rol no puede mentir

    /// Volver y descartar son gestos distintos. Si alguien intercambia símbolo o rótulo, VoiceOver
    /// anuncia «Atrás» donde en realidad se descarta una hoja — y el usuario ciego pierde su trabajo
    /// creyendo que retrocede.
    func testRoleMapsSymbolAndLabelConsistently() {
        XCTAssertEqual(BackButton.Role.back.symbol, "chevron.left")
        XCTAssertEqual(BackButton.Role.close.symbol, "xmark")
        XCTAssertEqual(BackButton.Role.back.label, "Back")
        XCTAssertEqual(BackButton.Role.close.label, "Close")
    }

    /// El chevron jamás debe anunciarse como «Cerrar» ni el aspa como «Atrás».
    func testRolesNeverShareSymbolOrLabel() {
        XCTAssertNotEqual(BackButton.Role.back.symbol, BackButton.Role.close.symbol)
        XCTAssertNotEqual(BackButton.Role.back.label, BackButton.Role.close.label)
    }

    // MARK: - Contraste

    private func luminance(_ c: Color) -> Double {
        let k = c.rgbaComponents
        return 0.2126 * OKLab.srgbToLinear(k.r) + 0.7152 * OKLab.srgbToLinear(k.g) + 0.0722 * OKLab.srgbToLinear(k.b)
    }
    private func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// El glifo sobre el disco de papel: es un icono pequeño, así que aplica el piso AA de 4.5:1.
    func testPaperGlyphClearsAAOnItsDisc() {
        let t = InstrumentoTheme.base
        XCTAssertGreaterThanOrEqual(contrast(t.ink, t.surface), 4.5,
            "el chevron sobre el disco de papel cae bajo AA")
    }

    /// La variante `.accent` existe porque el disco de papel DESAPARECE sobre color: el modo foco de
    /// la sesión vive sobre el verde del descanso. El glifo crema debe leerse ahí — este es el
    /// riesgo que el QA de FER-998 no pudo verificar sin dispositivo.
    ///
    /// El piso aquí es 3:1, no 4.5:1: un glifo de icono es un elemento NO textual y le aplica
    /// WCAG 2.2 §1.4.11 (Non-text Contrast), no §1.4.3. Queda en 3.63 — pasa, pero con menos aire
    /// del que uno creería, así que el valor se fija abajo.
    func testAccentGlyphClearsNonTextContrastOnRestGreen() {
        let t = InstrumentoTheme.base
        XCTAssertGreaterThanOrEqual(contrast(t.paper, t.verdict), 3.0,
            "el glifo crema sobre el verde del descanso cae bajo el piso no-textual de WCAG")
    }

    /// Fija el margen real. Si un retinte del verde lo empuja hacia 3.0, este test se pone rojo
    /// ANTES de que el glifo se vuelva ilegible en la sesión — que es el único momento en que
    /// alguien lo notaría de otro modo.
    func testAccentGlyphContrastMatchesDocumentedValue() {
        let t = InstrumentoTheme.base
        XCTAssertEqual(contrast(t.paper, t.verdict), 3.63, accuracy: 0.1)
    }

    // MARK: - Área táctil

    #if os(macOS)
    /// HIG §8.7-4: 44×44 mínimo. El disco dibuja 40 a propósito; el marco de 44 es el que se toca.
    /// Si alguien «limpia» ese marco de más, el botón sigue viéndose idéntico y se vuelve difícil de
    /// atinar — exactamente el tipo de regresión invisible.
    @MainActor func testBackButtonKeepsForty4PointHitTarget() throws {
        let size = try renderedSize(BackButton(role: .back, theme: .base, action: {}))
        XCTAssertGreaterThanOrEqual(size.width, 44, "área táctil bajo el mínimo de HIG")
        XCTAssertGreaterThanOrEqual(size.height, 44, "área táctil bajo el mínimo de HIG")
    }

    @MainActor func testHeaderActionButtonKeepsForty4PointHitTarget() throws {
        let size = try renderedSize(
            HeaderActionButton(Text(verbatim: "Guardar"), theme: .base, action: {}))
        XCTAssertGreaterThanOrEqual(size.height, 44, "área táctil bajo el mínimo de HIG")
    }

    @MainActor private func renderedSize<V: View>(_ view: V) throws -> CGSize {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.nsImage else {
            XCTFail("ImageRenderer no produjo imagen"); return .zero
        }
        return image.size
    }
    #endif
}
