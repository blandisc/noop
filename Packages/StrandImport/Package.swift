// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StrandImport",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "StrandImport", type: .static, targets: ["StrandImport"])],
    dependencies: [
        .package(path: "../CenitStore"),
        .package(path: "../StrandTraining"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "StrandImport",
            dependencies: [
                "CenitStore", "StrandTraining",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "StrandImportTests",
            dependencies: ["StrandImport", "CenitStore"],
            resources: [
                .copy("Resources"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
