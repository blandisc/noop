// swift-tools-version: 5.9
import PackageDescription

// StrandTraining — pure domain types for the strength tracker (Exercise, muscles,
// routine/session/set value models) + the bundled, read-only exercise catalog.
// Foundation-only: no GRDB, no UIKit, no CoreBluetooth. WhoopStore depends on it for
// persistence (GRDB conformance lives there, by extension); StrandAnalytics depends on
// it for the muscle-load / 1RM math (FER-350/FER-349). (FER-345)
let package = Package(
    name: "StrandTraining",
    // FER-740: .watchOS added so the Apple Watch companion (CenitWatch) can name/summarize the
    // mirrored strength session. Trivially safe — the package is Foundation-only.
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v10)],
    products: [.library(name: "StrandTraining", targets: ["StrandTraining"])],
    targets: [
        .target(
            name: "StrandTraining",
            resources: [
                .copy("Resources/exercises.json.zlib"),        // zlib-compressed catalog (FER-875)
                .copy("Resources/exercises.es.json.zlib"),     // Spanish overlay, zlib (FER-501/FER-779/FER-875)
                .copy("Resources/exercise-stills"),            // baked row thumbnails, {id}.jpg (FER-800)
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "StrandTrainingTests",
            dependencies: ["StrandTraining"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
