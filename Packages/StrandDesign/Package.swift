// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StrandDesign",
    // FER-740: .watchOS added so the Apple Watch companion (CenitWatch) can paint the mirrored
    // strength session with the same StrandDesign tokens. The package stays pure — UIKit/AppKit are
    // behind `#if canImport(...)` and the two haptic/scrub spots behind `#if os(iOS)`.
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v10)],
    products: [.library(name: "StrandDesign", targets: ["StrandDesign"])],
    dependencies: [],
    targets: [
        .target(
            name: "StrandDesign",
            // Instrument Serif (OFL) — bundled so the «Instrumento» serif headlines render fully
            // offline; registered at runtime via CoreText (a package can't use Info.plist UIAppFonts).
            resources: [.process("Resources")]
        ),
        // Token-doc generator (FER-131 handoff · 01): emits docs/design-system/* from the canonical
        // Instrumento.swift values so the doc + JSON can never drift from code. Run with
        // `swift run StrandDesignTokens` from this package dir; CI re-runs it and fails on a diff.
        .executableTarget(name: "StrandDesignTokens", dependencies: ["StrandDesign"]),
        .testTarget(name: "StrandDesignTests", dependencies: ["StrandDesign"]),
    ]
)
