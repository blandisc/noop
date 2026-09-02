// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CenitDesign",
    // FER-740: .watchOS added so the Apple Watch companion (CenitWatch) can paint the mirrored
    // strength session with the same CenitDesign tokens. The package stays pure — UIKit/AppKit are
    // behind `#if canImport(...)` and the two haptic/scrub spots behind `#if os(iOS)`.
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "CenitDesign", type: .static, targets: ["CenitDesign"])],
    dependencies: [],
    targets: [
        .target(
            name: "CenitDesign",
            // Space Grotesk (OFL) — bundled so the «Instrumento» type voice renders fully offline;
            // registered at runtime via CoreText (a package can't use Info.plist UIAppFonts).
            // El shader del Ecosistema (FER-13) viaja como FUENTE y se compila en runtime:
            // SwiftPM (tools 5.9) no compila `.metal` de un target, y así el mismo camino
            // sirve igual desde `swift build` y desde Xcode. Ver `EcosistemaMetal`.
            resources: [.process("Resources")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // Token-doc generator (FER-131 handoff · 01): emits docs/design-system/* from the canonical
        // Instrumento.swift values so the doc + JSON can never drift from code. Run with
        // `swift run CenitDesignTokens` from this package dir; CI re-runs it and fails on a diff.
        .executableTarget(
            name: "CenitDesignTokens",
            dependencies: ["CenitDesign"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "CenitDesignTests",
            dependencies: ["CenitDesign"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
