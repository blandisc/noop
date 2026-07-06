// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StrandImport",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "StrandImport", targets: ["StrandImport"])],
    dependencies: [
        .package(path: "../WhoopStore"),
        .package(path: "../StrandTraining"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
    ],
    targets: [
        .target(name: "StrandImport", dependencies: [
            "WhoopStore", "StrandTraining",
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
        ]),
        .testTarget(name: "StrandImportTests", dependencies: ["StrandImport", "WhoopStore"], resources: [
            .copy("Resources"),
        ]),
    ]
)
