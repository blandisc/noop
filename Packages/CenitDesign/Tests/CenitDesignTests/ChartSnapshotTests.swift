#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import CenitDesign

/// Renders the Day Strain accumulation curve (a `TrendChart`) to a PNG so the FER-110 auto-scaled
/// Y-axis fix can be eyeballed. Not a CI assertion — a developer render harness.
/// Run: swift test --filter ChartSnapshotTests
final class ChartSnapshotTests: XCTestCase {

    /// FER-110 — the Day Strain sheet's "How today added up" accumulated-strain curve. Renders a
    /// LOW day (ends at 3.9) so the auto-scaled Y axis (vs a fixed 0–21) is what keeps the buildup
    /// legible instead of a flat line on the floor. Run: swift test --filter ChartSnapshotTests
    @MainActor
    func test_renderStrainAccumulationCurve() throws {
        let fmt = DateFormatter()
        fmt.dateFormat = "h a"

        let score = 3.9
        let midnight = Date(timeIntervalSince1970: 1_718_000_000) // fixed (no Date.now in tests)
        // (hour-of-day, fraction of the day's score reached) — flat overnight, steeper around midday.
        let shape: [(h: Double, f: Double)] = [
            (0, 0), (6.5, 0.09), (8, 0.19), (10, 0.32), (12, 0.49),
            (12.75, 0.67), (13.25, 0.80), (14, 0.90), (15, 1.0),
        ]
        let points = shape.map { TrendPoint(date: midnight.addingTimeInterval($0.h * 3600), value: score * $0.f) }
        let peak = points.map(\.value).max() ?? 1
        let range = 0...max(peak * 1.15, 1)

        let view = VStack(alignment: .leading, spacing: 12) {
            Text("How today added up").font(StrandFont.headline).foregroundStyle(InstrumentoTheme.base.ink)
            TrendChart(
                points: points,
                gradient: StrandPalette.strainGradient,
                valueRange: range,
                showsArea: true,
                height: 132,
                showsScrub: false,
                valueFormat: { String(format: "%.1f", $0) },
                dateFormat: { fmt.string(from: $0) }
            )
        }
        .padding(20)
        .frame(width: 360)
        .background(InstrumentoTheme.base.paper)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-fer110/strain_curve.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
}
#endif
