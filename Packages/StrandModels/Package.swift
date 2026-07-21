// swift-tools-version: 5.9
import PackageDescription

// StrandModels — the shared vocabulary of daily metric value types (DailyMetric,
// CachedSleepSession, DietMealStatus). Foundation-only and dependency-free BY DESIGN: it is a
// leaf of the package graph so persistence (CenitStore) and math (StrandAnalytics) can speak
// these shapes WITHOUT one package owning the types the other consumes. Moved from CenitStore
// (plan 2026-07-20 · L3-C1a).
let package = Package(
    name: "StrandModels",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "StrandModels", type: .static, targets: ["StrandModels"])],
    targets: [
        .target(
            name: "StrandModels",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "StrandModelsTests",
            dependencies: ["StrandModels"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
