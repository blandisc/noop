#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-211 — render harness for the two Detalle de Métrica visual fixes, so the «Instrumento»
/// (light/paper) variants can be eyeballed before the screen ships:
///   • the SegmentedPillControl in its themed variant (quiet track, subtle ink-tinted active
///     segment, NO bright green) on warm paper;
///   • a TrendChart with paper-legible axes + gradient area (the band-less replacement for the old
///     grey-rectangle Sparkline).
/// Not a CI assertion — a developer render harness. PNGs land in /tmp/fer211-*.png.
/// Run: swift test --filter MetricDetailVisualSnapshotTests
final class MetricDetailVisualSnapshotTests: XCTestCase {

    private let theme = InstrumentoTheme.base

    /// The themed SegmentedPillControl: 6 ranges, one active, on paper — confirms the active segment
    /// is an ink-tinted capsule (not the dark-palette bright accent).
    @MainActor func test_themedSelector() throws {
        let view = SelectorHarness(theme: theme)
            .padding(20)
            .frame(width: 700, height: 120)
            .background(theme.paper)
        try write(view, to: "/tmp/fer211-selector.png")
    }

    /// A TrendChart with ~30 days of HRV-like data in Instrumento colors on paper — confirms area +
    /// gradient + date/value axes (and NO grey reference rectangle).
    @MainActor func test_themedTrendChart() throws {
        let hue = theme.dataHrv
        let points = sampleTrend(days: 30, base: 58, swing: 12)
        let values = points.map(\.value)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = (hi - lo) * 0.15
        let view = VStack(alignment: .leading, spacing: 10) {
            TrendChart(
                points: points,
                gradient: Gradient(colors: [hue.opacity(0.5), hue]),
                valueRange: (lo - pad)...(hi + pad),
                showsArea: true,
                height: 200,
                showsHover: false,
                valueFormat: { "\(Int($0.rounded())) ms" },
                axisLabelColor: theme.inkTertiary,
                gridLineColor: theme.hairline
            )
            Text("7-day moving average · last month.")
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
        }
        .padding(20)
        .frame(width: 700, height: 460)
        .background(theme.paper)
        try write(view, to: "/tmp/fer211-chart.png")
    }

    // MARK: harness

    @MainActor private func write<V: View>(_ content: V, to path: String) throws {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        try png.write(to: URL(fileURLWithPath: path))
        print("WROTE \(path) — \(image.size)")
    }

    private func sampleTrend(days: Int, base: Double, swing: Double) -> [TrendPoint] {
        let cal = Calendar.current
        let today = Date(timeIntervalSince1970: 1_718_000_000) // fixed (no Date.now in tests)
        return (0..<days).map { i in
            let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
            let v = base + swing * sin(Double(i) / 4.0) + Double((i * 13) % 5) - 2
            return TrendPoint(date: date, value: max(1, v))
        }
    }
}

/// A tiny stateful wrapper so the themed control has a live `selection` binding to render.
private struct SelectorHarness: View {
    let theme: InstrumentoTheme
    @State private var selection = "M"
    private let ranges = ["S", "M", "3M", "6M", "1A", "TODO"]
    var body: some View {
        SegmentedPillControl(ranges, selection: $selection, theme: theme) { $0 }
    }
}
#endif
