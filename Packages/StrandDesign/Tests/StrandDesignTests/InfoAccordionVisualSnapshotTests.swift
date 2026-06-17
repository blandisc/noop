#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-220 — render harness for the per-block ⓘ accordion in the Detalle de Métrica. Renders the
/// InfoAccordion in its EXPANDED state (the Consistencia copy, «Instrumento» base theme, on warm
/// paper) so the disclosed technical panel — overline + ⓘ, datum + plain-language reading, then the
/// left-ruled margin note — can be eyeballed before the screen ships. Not a CI assertion; a developer
/// render harness. PNG lands in /tmp/fer220-accordion.png.
/// Run: swift test --filter InfoAccordionVisualSnapshotTests
final class InfoAccordionVisualSnapshotTests: XCTestCase {

    private let theme = InstrumentoTheme.base

    /// The accordion forced open (`isExpanded: .constant(true)`), with the Consistencia datum + reading
    /// as content and the CV technical copy disclosed below — exactly the look the user taps to reveal.
    @MainActor func test_expandedConsistency() throws {
        let theme = self.theme // capture locally so the @ViewBuilder content closure needn't say `self.`
        let view = InfoAccordion(
            title: "Consistency (CV)",
            explanation: "Coefficient of variation = standard deviation ÷ the mean of your last few weeks. It measures how spread out your values are around your average. Low = steady. In HRV, a rising CV can precede fatigue even while the value still looks high. (Plews 2013)",
            accessibilityLabel: "Information about consistency",
            theme: theme,
            isExpanded: .constant(true)
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text("±7% week to week · steady")
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(theme.ink)
                Text("How even it stays from one week to the next. Steadier usually means better rest; very uneven can be fatigue.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 700, height: 240)
        .background(theme.paper)
        try write(view, to: "/tmp/fer220-accordion.png")
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
}
#endif
