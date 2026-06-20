// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StrandDesign",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "StrandDesign", targets: ["StrandDesign"])],
    dependencies: [],
    targets: [
        .target(name: "StrandDesign"),
        // Token-doc generator (FER-131 handoff · 01): emits docs/design-system/* from the canonical
        // Instrumento.swift values so the doc + JSON can never drift from code. Run with
        // `swift run StrandDesignTokens` from this package dir; CI re-runs it and fails on a diff.
        .executableTarget(name: "StrandDesignTokens", dependencies: ["StrandDesign"]),
        .testTarget(name: "StrandDesignTests", dependencies: ["StrandDesign"]),
    ]
)
