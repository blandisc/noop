import Foundation
import CoreText

// MARK: - Instrument Serif registration (§2 «Instrumento»)
//
// The serif headline / verdict face (`Instrument Serif`, OFL) ships as a bundled resource
// (`Resources/InstrumentSerif-Regular.ttf`) so it renders fully offline — no network, ever.
// A Swift package can't declare `UIAppFonts` in an app Info.plist (it has none), so the font
// is registered with CoreText at runtime, exactly once, the first time a serif token is asked
// for. CoreText is platform-neutral (no AppKit/UIKit), so this stays inside the package's
// cross-platform contract.

extension StrandFont {

    /// Registers Instrument Serif with the process font manager. The `static let` makes this run
    /// at most once (lazily, thread-safe) regardless of how many times `ensureFontsRegistered()`
    /// is called.
    private static let registerInstrumentSerif: Void = {
        guard let url = Bundle.module.url(forResource: "InstrumentSerif-Regular", withExtension: "ttf") else {
            assertionFailure("Instrument Serif resource missing from the StrandDesign bundle")
            return
        }
        // `.process` scope: visible to this process only — no global side effects on the OS.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    /// Make sure the bundled serif face is registered before a `Font.custom("Instrument Serif", …)`
    /// resolves (otherwise it would silently fall back to a system serif). Cheap to call repeatedly;
    /// the real work happens once. The app may also call this at launch to warm registration.
    public static func ensureFontsRegistered() {
        _ = registerInstrumentSerif
    }
}
