import XCTest
import CoreText
@testable import StrandDesign

/// The «Instrumento» type voice — Space Grotesk (§2, FER-707/708) — is a set of bundled OFL resources
/// registered at runtime. If a resource were missing or registration silently failed, `Font.custom(…)`
/// would fall back to a system face and nobody would notice in a build. These tests fail loudly instead:
/// they assert each bundled weight actually resolves under its own PostScript name.
/// (The serif face was retired in FER-901; these tests moved with the voice.)
final class FontRegistrationTests: XCTestCase {

    private static let bundledWeights = ["Regular", "Medium", "SemiBold", "Bold"]

    func testSpaceGroteskRegistersFromBundle() {
        StrandFont.ensureFontsRegistered()
        // The static Google builds ship weight-suffixed family names, so the PostScript name is the
        // stable identifier. CTFontCreateWithName returns a *fallback* (not nil) for an unknown name,
        // so the assertion is on the resolved PS name — equality proves it's our bundled face.
        for weight in Self.bundledWeights {
            let ps = "SpaceGrotesk-\(weight)"
            let font = CTFontCreateWithName(ps as CFString, 24, nil)
            let resolved = CTFontCopyPostScriptName(font) as String
            XCTAssertEqual(
                resolved, ps,
                "\(ps) must register from the StrandDesign bundle; got '\(resolved)' — likely a system fallback (registration failed or the .ttf is missing from Resources)."
            )
        }
    }

    func testBundledFontResourcesExist() {
        for weight in Self.bundledWeights {
            let name = "SpaceGrotesk-\(weight)"
            XCTAssertNotNil(
                Bundle.module.url(forResource: name, withExtension: "ttf"),
                "\(name).ttf must be bundled via Package.swift resources(.process(\"Resources\"))."
            )
        }
    }
}
