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
            Text("How today added up").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
            TrendChart(
                points: points,
                gradient: StrandPalette.strainGradient,
                valueRange: range,
                showsArea: true,
                height: 170,
                showsHover: false,
                valueFormat: { String(format: "%.1f", $0) },
                dateFormat: { fmt.string(from: $0) }
            )
        }
        .padding(20)
        .frame(width: 360)
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
        let url = URL(fileURLWithPath: "/tmp/noop-fer110/strain_curve.png")
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
