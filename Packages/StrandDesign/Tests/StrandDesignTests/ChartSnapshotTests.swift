#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// Renders a ChartCard + TrendChart with HR-like sample data to a PNG so the FER-82
/// fix (no fill tint on the X-axis hour labels, last label not clipped) can be eyeballed.
/// Not a CI assertion — a developer render harness. Run: swift test --filter ChartSnapshotTests
final class ChartSnapshotTests: XCTestCase {

    @MainActor
    func test_renderTodayHeartRateCard() throws {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"

        // ~70 minutes of 5-minute HR buckets, ending near "now", so the X axis shows
        // times like "2:25 PM … 3:25 PM" and the last label lands near the right edge.
        let base = Date(timeIntervalSince1970: 1_718_000_000) // fixed (no Date.now in tests)
        let bpm: [Double] = [72, 78, 91, 110, 134, 128, 141, 119, 96, 88, 84, 101, 122, 137, 109]
        let points = bpm.enumerated().map { i, v in
            TrendPoint(date: base.addingTimeInterval(Double(i) * 300), value: v)
        }
        let lo = bpm.min()!, hi = bpm.max()!, span = hi - lo
        let range = (lo - span * 0.12)...(hi + span * 0.12)

        let card = ChartCard(
            title: "Beats per minute",
            subtitle: "5-minute average · since midnight",
            trailing: "\(Int(bpm.last!)) bpm"
        ) {
            TrendChart(
                points: points,
                gradient: Gradient(colors: [StrandPalette.metricRose.opacity(0.55), StrandPalette.metricRose]),
                valueRange: range,
                showsArea: true,
                height: NoopMetrics.chartHeight,
                showsHover: false,
                valueFormat: { "\(Int($0.rounded())) bpm" },
                dateFormat: { fmt.string(from: $0) }
            )
        } footer: {
            ChartFooter([("Min", "\(Int(lo))"), ("Avg", "92"), ("Max", "\(Int(hi))")])
        }

        let view = card
            .padding(NoopMetrics.screenPadding)
            .frame(width: 390)
            .background(StrandPalette.surfaceBase)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-fer82/today_hr.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }

    @MainActor
    func test_renderTrendsRecoveryCard() throws {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSince1970: 1_715_000_000)
        let vals: [Double] = [42, 51, 63, 58, 70, 66, 74, 81, 77, 69, 60, 55, 64, 72]
        let points = vals.enumerated().map { i, v in
            TrendPoint(date: base.addingTimeInterval(Double(i) * day), value: v)
        }

        let card = ChartCard(
            title: "Recovery",
            subtitle: "Last 14 days",
            trailing: "64"
        ) {
            TrendChart(
                points: points,
                gradient: StrandPalette.recoveryGradient,
                valueRange: 0...100,
                showsArea: true,
                height: NoopMetrics.chartHeight,
                showsHover: false,
                dateFormat: { fmt.string(from: $0) }
            )
        } footer: {
            ChartFooter([("Avg", "64"), ("Peak", "81"), ("Low", "42"), ("Days", "14")])
        }

        let view = card
            .padding(NoopMetrics.screenPadding)
            .frame(width: 390)
            .background(StrandPalette.surfaceBase)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-fer82/trends_recovery.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
}
#endif
