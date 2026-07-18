// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StrandAnalytics",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "StrandAnalytics", type: .static, targets: ["StrandAnalytics"])],
    dependencies: [
        .package(path: "../WhoopProtocol"),
        .package(path: "../CenitStore"),
    ],
    targets: [
        .target(
            name: "StrandAnalytics",
            dependencies: ["WhoopProtocol", "CenitStore"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "StrandAnalyticsTests",
            dependencies: ["StrandAnalytics"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
