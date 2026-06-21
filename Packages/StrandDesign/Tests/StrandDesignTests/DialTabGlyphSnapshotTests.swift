#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-163 — renders the «Hoy» dial glyph and a faithful static mock of the
/// «Barra de instrumento» (the real bar lives in the app target, so the row is
/// reproduced here with the same tokens + SF Symbols) so the icon set, the
/// ink/now-dot states, and the light day theme vs. the dark theme can be
/// eyeballed without a simulator. Developer render harness, not a CI assertion.
/// Run: swift test --filter DialTabGlyphSnapshotTests
final class DialTabGlyphSnapshotTests: XCTestCase {

    private struct TabMock: View {
        let theme: InstrumentoTheme?      // nil → dark StrandPalette
        let icon: (Color) -> AnyView
        let label: String
        let active: Bool

        private var ink: Color {
            if let t = theme { return active ? t.ink : t.inkTertiary }
            return active ? StrandPalette.textPrimary : StrandPalette.textSecondary
        }
        private var dot: Color { theme?.dataRecovery ?? StrandPalette.accent }

        var body: some View {
            VStack(spacing: 5) {
                icon(ink).frame(height: 23)
                Text(label).font(StrandFont.footnote).fontWeight(active ? .medium : .regular).foregroundStyle(ink)
                Circle().fill(active ? dot : .clear).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func bar(theme: InstrumentoTheme?, activeIndex: Int) -> some View {
        let items: [((Color) -> AnyView, String)] = [
            ({ c in AnyView(DialTabGlyph(size: 23, color: c)) }, "Hoy"),
            ({ c in AnyView(Image(systemName: "chart.xyaxis.line").font(.system(size: 21, weight: .regular)).foregroundStyle(c)) }, "Tendencias"),
            ({ c in AnyView(Image(systemName: "waveform.path.ecg").font(.system(size: 21, weight: .regular)).foregroundStyle(c)) }, "En vivo"),
            ({ c in AnyView(Image(systemName: "moon").font(.system(size: 21, weight: .regular)).foregroundStyle(c)) }, "Sueño"),
            ({ c in AnyView(Image(systemName: "ellipsis").font(.system(size: 21, weight: .regular)).foregroundStyle(c)) }, "Más"),
        ]
        let surface = theme?.paper ?? StrandPalette.surfaceBase
        let rule = theme?.hairline ?? StrandPalette.hairline
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, it in
                TabMock(theme: theme, icon: it.0, label: it.1, active: idx == activeIndex)
            }
        }
        .padding(.top, 10).padding(.bottom, 12)
        .frame(width: 390)
        .background(surface)
        .overlay(alignment: .top) { Rectangle().fill(rule).frame(height: 0.5) }
        .environment(\.instrumentoTheme, theme ?? .base)
    }

    @MainActor
    func test_renderBarAndGlyph() throws {
        func caption(_ s: String, _ t: InstrumentoTheme?) -> some View {
            Text(s).font(.system(size: 11, weight: .medium))
                .foregroundStyle((t?.inkTertiary) ?? StrandPalette.textSecondary)
        }

        let content = VStack(spacing: 14) {
            caption("Bajo Hoy — papel de día «Instrumento» (.base)", .base)
            bar(theme: .base, activeIndex: 0)
            caption("Bajo Tendencias / En vivo / Sueño / Más — oscuro", nil)
            bar(theme: nil, activeIndex: 1)
        }
        .padding(24)
        .background(Color(hex: "#E8E2D6"))

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-fer163/instrument_bar.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
}
#endif
