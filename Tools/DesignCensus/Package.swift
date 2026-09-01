// swift-tools-version:5.9
import PackageDescription

// AISLADO a propósito (FER-266 / épico FER-261, principio 1): este paquete vive fuera de
// Packages/**, no aparece en project.yml ni en ningún workflow de .github, y no es dependencia
// de ningún paquete de la app. swift-syntax se baja de la red UNA vez al compilar el censo en
// dev — la regla "offline" del repo aplica al app en runtime, no a este tooling de reporte.
let package = Package(
    name: "DesignCensus",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0")
    ],
    targets: [
        .executableTarget(
            name: "design-census",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        )
    ]
)
