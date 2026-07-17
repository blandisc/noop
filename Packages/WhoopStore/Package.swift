// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhoopStore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "WhoopStore", type: .static, targets: ["WhoopStore"])],
    dependencies: [
        .package(path: "../WhoopProtocol"),
        .package(path: "../StrandTraining"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "WhoopStore",
            dependencies: [
                "WhoopProtocol",
                "StrandTraining",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [
                // FER-923: id-remap maps driving the v33 exercise-catalog migration (zlib, raw DEFLATE).
                .copy("Resources/exercise-id-remap.json.zlib"),
                .copy("Resources/legacy-exercise-data.json.zlib"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "WhoopStoreTests",
            dependencies: ["WhoopStore"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
