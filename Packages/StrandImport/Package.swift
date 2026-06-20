// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StrandImport",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "StrandImport", targets: ["StrandImport"])],
    dependencies: [
        .package(path: "../WhoopProtocol"),
        .package(path: "../WhoopStore"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
    ],
    targets: [
        .target(name: "StrandImport", dependencies: [
            "WhoopProtocol", "WhoopStore",
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
        ]),
        .testTarget(name: "StrandImportTests", dependencies: ["StrandImport", "WhoopStore"], resources: [
            .copy("Resources"),
        ]),
    ]
)
