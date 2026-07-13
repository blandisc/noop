import Foundation
import CoreText

// MARK: - Bundled font registration (§2 «Instrumento»)
//
// The bundled faces (all OFL) ship as package resources so they render fully offline — no
// network, ever. A Swift package can't declare `UIAppFonts` in an app Info.plist (it has none),
// so the fonts are registered with CoreText at runtime, exactly once, the first time a token
// that needs them is asked for. CoreText is platform-neutral (no AppKit/UIKit), so this stays
// inside the package's cross-platform contract.
//
//   • Space Grotesk 400/500/600/700 — the evolved «Instrumento» voice (FER-707/708): numerals,
//     sheet titles, overlines, lane labels, tabs, buttons. Static instances (the SemiBold is
//     instanced from the official variable font), referenced by PostScript name.

extension StrandFont {

    /// Registers the bundled faces with the process font manager. The `static let` makes this run
    /// at most once (lazily, thread-safe) regardless of how many times `ensureFontsRegistered()`
    /// is called.
    private static let registerBundledFonts: Void = {
        let files = [
            "SpaceGrotesk-Regular", "SpaceGrotesk-Medium", "SpaceGrotesk-SemiBold", "SpaceGrotesk-Bold",
        ]
        for file in files {
            guard let url = Bundle.module.url(forResource: file, withExtension: "ttf") else {
                assertionFailure("\(file).ttf missing from the StrandDesign bundle")
                continue
            }
            // `.process` scope: visible to this process only — no global side effects on the OS.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Make sure the bundled faces are registered before a `Font.custom(…)` resolves (otherwise
    /// it would silently fall back to a system face). Cheap to call repeatedly; the real work
    /// happens once. The app may also call this at launch to warm registration.
    public static func ensureFontsRegistered() {
        _ = registerBundledFonts
    }
}
