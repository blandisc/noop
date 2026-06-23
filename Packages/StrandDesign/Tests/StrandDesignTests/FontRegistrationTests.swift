import XCTest
import CoreText
@testable import StrandDesign

/// The «Instrumento» serif headline face (§2) is a bundled OFL resource registered at runtime.
/// If the resource were missing or registration silently failed, `Font.custom("Instrument Serif")`
/// would fall back to a system serif and nobody would notice in a build. These tests fail loudly
/// instead: they assert the bundled face actually resolves under its own family name.
final class FontRegistrationTests: XCTestCase {

    func testInstrumentSerifRegistersFromBundle() {
        StrandFont.ensureFontsRegistered()
        // CTFontCreateWithName returns a *fallback* (not nil) when the name is unknown, so the
        // assertion has to be on the resolved family — equality proves it's our bundled face,
        // not the system serif standing in for it.
        let font = CTFontCreateWithName("Instrument Serif" as CFString, 24, nil)
        let family = CTFontCopyFamilyName(font) as String
        XCTAssertEqual(
            family, "Instrument Serif",
            "Instrument Serif must register from the StrandDesign bundle; got '\(family)' — likely a system fallback (registration failed or the .ttf is missing from Resources)."
        )
    }

    func testBundledFontResourceExists() {
        XCTAssertNotNil(
            Bundle.module.url(forResource: "InstrumentSerif-Regular", withExtension: "ttf"),
            "InstrumentSerif-Regular.ttf must be bundled via Package.swift resources(.process(\"Resources\"))."
        )
    }
}
