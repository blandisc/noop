#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import CenitDesign

/// FER-161 — render harness for the tappable affordance (trailing chevron) on «Métricas clave»
/// rows, in the «Instrumento diurno» theme. Reproduces how `TodayView.iosMetricsSection` builds
/// the rows so the chevron, the no-data row, and the pressed background can be eyeballed before the
/// app builds. Not a CI assertion — PNGs land in /tmp/noop-fer161/.
/// Run: swift test --filter MetricRowChevronSnapshotTests
final class MetricRowChevronSnapshotTests: XCTestCase {

    @MainActor func test_keyMetricsWithChevron() throws {
        try render(KeyMetricsDemo(), to: "key_metrics_chevron", width: 390)
    }

    @MainActor private func render<V: View>(_ content: V, to name: String, width: CGFloat) throws {
        let view = content.frame(width: width)
        let renderer = ImageRenderer(content: view.background(InstrumentoTheme.base.paper))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-fer161/\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
}

private struct KeyMetricsDemo: View {
    private let t = InstrumentoTheme.base
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Métricas clave").font(StrandFont.title1).foregroundStyle(t.ink)
                Spacer()
                Text("Tendencia 14 días").font(StrandFont.footnote).foregroundStyle(t.inkTertiary)
            }
            VStack(spacing: 0) {
                MetricRow(label: "Esfuerzo del día", value: "8.5",
                          valueColor: t.ink, labelColor: t.inkSecondary, unitColor: t.inkTertiary,
                          sparkline: [6, 9, 7, 11, 8, 10, 8.5], sparkColor: t.dataStrain,
                          showsChevron: true, chevronColor: t.inkTertiary)
                rule
                MetricRow(label: "HRV", value: "41", unit: "ms",
                          valueColor: t.ink, labelColor: t.inkSecondary, unitColor: t.inkTertiary,
                          sparkline: [58, 55, 52, 49, 46, 43, 41], sparkColor: t.dataHrv,
                          showsChevron: true, chevronColor: t.inkTertiary)
                rule
                // Pressed: the subtle fill the row shows mid-tap.
                MetricRow(label: "Frecuencia cardíaca", value: "62", unit: "bpm",
                          valueColor: t.ink, labelColor: t.inkSecondary, unitColor: t.inkTertiary,
                          sparkline: [60, 64, 61, 66, 63, 65, 62], sparkColor: t.dataHeart,
                          showsChevron: true, chevronColor: t.inkTertiary)
                    .background(t.ink.opacity(0.05))
                rule
                // No data: chevron still shows.
                MetricRow(label: "Oxígeno en sangre", value: "—", unit: "%",
                          valueColor: t.ink, labelColor: t.inkSecondary, unitColor: t.inkTertiary,
                          isPlaceholder: true, showsChevron: true, chevronColor: t.inkTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var rule: some View { Rectangle().fill(t.hairlineStrong).frame(height: 1) }
}
#endif
