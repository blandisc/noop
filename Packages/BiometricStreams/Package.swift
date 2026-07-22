// swift-tools-version: 5.9
import PackageDescription

// BiometricStreams — the neutral vocabulary of decoded biometric rows (HRSample, RRInterval,
// StreamEvent, BatterySample, the type-47 biometric samples, `Streams`) plus `ParsedValue`.
// Foundation-only and dependency-free BY DESIGN: it is the root of the package graph, so
// persistence (CenitStore) and math (StrandAnalytics) can speak this vocabulary from a
// single, dependency-free root (FER-993 · D2).
let package = Package(
    name: "BiometricStreams",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "BiometricStreams", type: .static, targets: ["BiometricStreams"])],
    targets: [
        .target(
            name: "BiometricStreams",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "BiometricStreamsTests",
            dependencies: ["BiometricStreams"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
