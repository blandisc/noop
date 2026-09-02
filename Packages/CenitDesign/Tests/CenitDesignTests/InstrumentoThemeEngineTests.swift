import XCTest
import SwiftUI
@testable import CenitDesign

/// Survivors of the retired by-the-hour theme engine (FER-132, removed in FER-398): the OKLab
/// colour math and the `positiveText` AA repair, both still load-bearing for the single `.base`
/// theme (paper gradient, `DiurnalDial`, `ReferenceRange`). The by-the-hour anchors / 24h-sweep
/// AA tests went with the engine.
final class InstrumentoThemeEngineTests: XCTestCase {

    // MARK: helpers

    private func luminance(_ c: Color) -> Double {
        let k = c.rgbaComponents
        return 0.2126 * OKLab.srgbToLinear(k.r) + 0.7152 * OKLab.srgbToLinear(k.g) + 0.0722 * OKLab.srgbToLinear(k.b)
    }
    private func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
    private func lab(_ c: Color) -> OKLab.Lab {
        let k = c.rgbaComponents
        return OKLab.toLab((k.r, k.g, k.b))
    }

    // MARK: OKLab math

    func testOKLabRoundTripIsStable() {
        for hex in ["#F4F1E8", "#221D16", "#0C8F62", "#C4631F", "#CDBE9F", "#191309", "#BC3A34", "#000000", "#FFFFFF"] {
            let k = Color(hex: hex).rgbaComponents
            let rt = OKLab.toRGB(OKLab.toLab((k.r, k.g, k.b)))
            XCTAssertEqual(rt.r, k.r, accuracy: 0.002, "\(hex) R")
            XCTAssertEqual(rt.g, k.g, accuracy: 0.002, "\(hex) G")
            XCTAssertEqual(rt.b, k.b, accuracy: 0.002, "\(hex) B")
        }
    }

    // MARK: positiveText — AA-at-text-size positive green on the base paper

    /// The base `verdict` actually fails the 12pt floor (proving the fix is needed), while
    /// `positiveText` repairs it and keeps the hue green (not collapsed to ink/black).
    func testPositiveTextFixesVerdictAndStaysGreen() {
        let t = InstrumentoTheme.base
        XCTAssertLessThan(contrast(t.verdict, t.paper), 4.5, "verdict should miss the 12pt text floor")
        XCTAssertGreaterThanOrEqual(contrast(t.positiveText, t.paper), 4.5, "positiveText must clear it")
        // Still green: the green channel dominates, and it's darker (lower OKLab L) than verdict.
        let k = t.positiveText.rgbaComponents
        XCTAssertGreaterThan(k.g, k.r, "positiveText should still read green (G > R)")
        XCTAssertGreaterThan(k.g, k.b, "positiveText should still read green (G > B)")
        XCTAssertLessThan(lab(t.positiveText).L, lab(t.verdict).L, "positiveText must be darker than verdict")
    }
}
