// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhoopProtocol",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "WhoopProtocol", type: .static, targets: ["WhoopProtocol"]),
        .executable(name: "whoop-decode", targets: ["whoop-decode"]),
    ],
    dependencies: [
        // One-way: the wire protocol speaks the neutral vocabulary; BiometricStreams
        // never depends back on WhoopProtocol (FER-993 · D2).
        .package(path: "../BiometricStreams"),
    ],
    targets: [
        .target(
            name: "WhoopProtocol",
            dependencies: ["BiometricStreams"],
            resources: [.process("Resources/whoop_protocol.json")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .executableTarget(
            name: "whoop-decode",
            dependencies: ["WhoopProtocol", "BiometricStreams"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "WhoopProtocolTests",
            dependencies: ["WhoopProtocol", "BiometricStreams"],
            resources: [.process("Resources")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
