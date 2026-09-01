#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-131 — render harness for the «Instrumento diurno» foundations, so the new
/// visual language (warm paper, one dominant number, color only in the datum)
/// and its shared states can be eyeballed before any screen is built.
/// Not a CI assertion — a developer render harness. PNGs land in /tmp/noop-fer131/.
/// Run: swift test --filter InstrumentoSnapshotTests
final class InstrumentoSnapshotTests: XCTestCase {

    @MainActor func test_language()  throws { try render(LanguageDemo(),  to: "language", width: 390) }
    @MainActor func test_palette()   throws { try render(PaletteDemo(),   to: "palette",  width: 390) }
    // MARK: harness

    @MainActor private func render<V: View>(_ content: V, to name: String, width: CGFloat, height: CGFloat? = nil) throws {
        var view = AnyView(content.instrumentoTheme(.base).frame(width: width))
        if let height { view = AnyView(content.instrumentoTheme(.base).frame(width: width, height: height)) }
        let renderer = ImageRenderer(content: view.background(InstrumentoTheme.base.paper))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-fer131/\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
}

// MARK: - The language in action (the gate piece)

private struct LanguageDemo: View {
    private let t = InstrumentoTheme.base
    var body: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            // Header — quiet overline + one title.
            VStack(alignment: .leading, spacing: 4) {
                Text("MARTES 16 JUN").instrumentoOverline().foregroundStyle(t.inkTertiary)
                Text("Hoy").font(StrandFont.title1).foregroundStyle(t.ink)
            }

            // Rule 1 + 2: the ONE dominant number, colored because it's the datum.
            VStack(alignment: .leading, spacing: 2) {
                Text("RECUPERACIÓN").instrumentoOverline().foregroundStyle(t.inkTertiary)
                Text("82").instrumentoHero(96).foregroundStyle(t.dataRecovery)
                Text("Listo para un día fuerte").font(StrandFont.body).foregroundStyle(t.inkSecondary)
            }

            Divider().overlay(t.hairline)

            // A subordinate datum — smaller, still color-on-value, label in ink.
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                subordinate("ESFUERZO", "13.4", t.dataStrain)
                subordinate("SUEÑO", "7:42", t.ink)   // not a recovery/strain datum → ink
            }

            Divider().overlay(t.hairline)

            // Rule 3 + 4: signals grouped by space, labels quiet, no color on chrome.
            VStack(alignment: .leading, spacing: 10) {
                Text("SEÑALES DE HOY").instrumentoOverline().foregroundStyle(t.inkTertiary)
                signal("HRV", "62 ms · sobre tu base")
                signal("FC en reposo", "51 lpm · normal")
                signal("Respiración", "14.2 rpm · normal")
            }
        }
        .padding(CenitMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subordinate(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).instrumentoOverline().foregroundStyle(t.inkTertiary)
            Text(value).instrumentoHero(34).foregroundStyle(tint)
        }
    }

    private func signal(_ name: String, _ detail: String) -> some View {
        HStack(spacing: 8) {
            Text(name).font(StrandFont.subhead).foregroundStyle(t.ink).frame(width: 110, alignment: .leading)
            Text(detail).font(StrandFont.subhead).foregroundStyle(t.inkSecondary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Token swatches (color reference)

private struct PaletteDemo: View {
    private let t = InstrumentoTheme.base
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("INSTRUMENTO DIURNO · TOKENS").instrumentoOverline().foregroundStyle(t.inkTertiary)
            row("Papel", [("paper", t.paper), ("surface", t.surface), ("hairline", t.hairline), ("strong", t.hairlineStrong)])
            row("Tinta", [("ink 14.8:1", t.ink), ("secondary 6.5:1", t.inkSecondary), ("tertiary 4.9:1", t.inkTertiary)])
            row("Dato / estado", [("recovery", t.dataRecovery), ("strain", t.dataStrain), ("warning", t.warning), ("critical", t.critical)])
        }
        .padding(CenitMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func row(_ title: String, _ items: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).instrumentoOverline().foregroundStyle(t.inkTertiary)
            HStack(spacing: 10) {
                ForEach(items, id: \.0) { name, color in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8).fill(color).frame(width: 78, height: 46)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(t.hairlineStrong, lineWidth: 1))
                        Text(name).font(.system(size: 9)).foregroundStyle(t.inkSecondary)
                    }
                }
            }
        }
    }
}
#endif
