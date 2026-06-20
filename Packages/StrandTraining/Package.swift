// swift-tools-version: 5.9
import PackageDescription

// StrandTraining — pure domain types for the strength tracker (Exercise, muscles,
// routine/session/set value models) + the bundled, read-only exercise catalog.
// Foundation-only: no GRDB, no UIKit, no CoreBluetooth. WhoopStore depends on it for
// persistence (GRDB conformance lives there, by extension); StrandAnalytics depends on
// it for the muscle-load / 1RM math (FER-350/FER-349). (FER-345)
let package = Package(
    name: "StrandTraining",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "StrandTraining", targets: ["StrandTraining"])],
    targets: [
        .target(
            name: "StrandTraining",
            resources: [.process("Resources/exercises.json")]
        ),
        .testTarget(
            name: "StrandTrainingTests",
            dependencies: ["StrandTraining"]
        ),
    ]
)
