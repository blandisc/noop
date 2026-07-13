// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StrandDesign",
    // FER-740: .watchOS added so the Apple Watch companion (CenitWatch) can paint the mirrored
    // strength session with the same StrandDesign tokens. The package stays pure — UIKit/AppKit are
    // behind `#if canImport(...)` and the two haptic/scrub spots behind `#if os(iOS)`.
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "StrandDesign", targets: ["StrandDesign"])],
    dependencies: [],
    targets: [
        .target(
            name: "StrandDesign",
            // Space Grotesk (OFL) — bundled so the «Instrumento» type voice renders fully offline;
            // registered at runtime via CoreText (a package can't use Info.plist UIAppFonts).
            resources: [.process("Resources")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // Token-doc generator (FER-131 handoff · 01): emits docs/design-system/* from the canonical
        // Instrumento.swift values so the doc + JSON can never drift from code. Run with
        // `swift run StrandDesignTokens` from this package dir; CI re-runs it and fails on a diff.
        .executableTarget(
            name: "StrandDesignTokens",
            dependencies: ["StrandDesign"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "StrandDesignTests",
            dependencies: ["StrandDesign"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
