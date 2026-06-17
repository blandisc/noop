#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-145 — render harness for the two longevity components (`BodyAgeBand`,
/// `ContributionBars`) so they can be eyeballed against the approved HTML preview
/// before the detail sheet is built on top. Not a CI assertion — a dev render harness.
/// PNGs land in /tmp/noop-fer145/. Run: swift test --filter BodyAgeComponentsSnapshotTests
final class BodyAgeComponentsSnapshotTests: XCTestCase {

    @MainActor func test_bodyAgeBand_bySign() throws { try render(BandDemo(), to: "body_age_band", width: 360, height: 380) }
    @MainActor func test_contributionBars()  throws { try render(BarsDemo(), to: "contribution_bars", width: 360, height: 280) }

    @MainActor private func render<V: View>(_ content: V, to name: String, width: CGFloat, height: CGFloat) throws {
        let view = content.instrumentoTheme(.base).frame(width: width, height: height)
        let renderer = ImageRenderer(content: view.background(InstrumentoTheme.base.paper))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-fer145/\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
}

private struct BandDemo: View {
    private let t = InstrumentoTheme.base
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            cell("Rejuvenece", bodyAge: 31, color: t.dataRecovery)
            cell("En tu edad (neutro)", bodyAge: 34, color: t.ink)
            cell("Envejece", bodyAge: 38, color: t.warning)
            cell("Tope — la edad sale de la banda", bodyAge: 44, color: t.critical)
        }
        .padding(20)
    }
    private func cell(_ title: String, bodyAge: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(StrandFont.caption).foregroundStyle(t.inkSecondary)
            BodyAgeBand(bodyAge: bodyAge, chronoAge: 34, color: color, youLabel: "you",
                        accessibilityLabelText: "Body age",
                        accessibilityValueText: "\(Int(bodyAge)) years", animated: false)
        }
    }
}

private struct BarsDemo: View {
    var body: some View {
        ContributionBars(items: [
            .init(label: "VO₂max", years: -1.8, accessibilityValue: ""),
            .init(label: "FC reposo", years: -1.4, accessibilityValue: ""),
            .init(label: "VFC", years: -0.6, accessibilityValue: ""),
            .init(label: "Sueño", years: -0.1, accessibilityValue: ""),
            .init(label: "Pasos", years: 0.3, accessibilityValue: ""),
            .init(label: "Regularidad", years: 0.9, accessibilityValue: ""),
        ], leftPole: "← te rejuvenece", rightPole: "te envejece →", animated: false)
        .padding(20)
    }
}
#endif
