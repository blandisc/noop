import XCTest
import SwiftUI
@testable import CenitDesign

/// FER-141 — the «Edad física» (Fitness Age) numeral is tinted by DIRECTION: verde `verdict` /
/// `dataRecovery` when the user reads younger, ámbar `warning` when older, over the «Instrumento»
/// paper. At hero size (~64pt) the applicable WCAG floor is AA-large, 3:1.
///
/// FER-398 retired the by-the-hour engine, so there is a single `.base` paper. This suite pins the
/// Fitness Age use-case EXPLICITLY — so a future retint of the theme can't silently dip the directional
/// hero below 3:1 without a red test pointing back at this screen.
final class FitnessAgeContrastTests: XCTestCase {

    private func luminance(_ c: Color) -> Double {
        let k = c.rgbaComponents
        return 0.2126 * OKLab.srgbToLinear(k.r) + 0.7152 * OKLab.srgbToLinear(k.g) + 0.0722 * OKLab.srgbToLinear(k.b)
    }
    private func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Both directional hues clear AA-large (3:1) on the base paper.
    func testPhysicalAgeNumeralHuesClearAALargeOnPaper() {
        let anchors: [(String, InstrumentoTheme)] = [
            ("base", .base),
        ]
        for (name, t) in anchors {
            XCTAssertGreaterThanOrEqual(contrast(t.verdict, t.paper), 3.0,
                "younger (verdict) numeral below AA-large on \(name) paper")
            XCTAssertGreaterThanOrEqual(contrast(t.dataRecovery, t.paper), 3.0,
                "younger (dataRecovery) numeral below AA-large on \(name) paper")
            XCTAssertGreaterThanOrEqual(contrast(t.warning, t.paper), 3.0,
                "older (warning) numeral below AA-large on \(name) paper")
        }
    }

    /// Pin the documented `.base` ratios so the numbers cited in the spec/CHANGELOG stay honest.
    func testBaseRatiosMatchDocumentedValues() {
        XCTAssertEqual(contrast(InstrumentoTheme.base.verdict, InstrumentoTheme.base.paper),
                       3.63, accuracy: 0.1)   // verde — younger
        XCTAssertEqual(contrast(InstrumentoTheme.base.warning, InstrumentoTheme.base.paper),
                       4.62, accuracy: 0.1)   // ámbar — older
    }
}
