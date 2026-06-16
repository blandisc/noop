#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-132 — renders the by-the-hour theme at 06/12/19/23 to a PNG so the warm
/// day→night drift (and the dimmed-parchment night, NOT an inverted dark mode) can
/// be eyeballed. Developer render harness, not a CI assertion.
/// Run: swift test --filter InstrumentoThemeSnapshotTests
final class InstrumentoThemeSnapshotTests: XCTestCase {

    @MainActor
    func test_renderThemeByHour() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func theme(_ h: Int) -> InstrumentoTheme {
            InstrumentoThemeEngine.theme(at: cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: h))!, calendar: cal)
        }

        func panel(_ t: InstrumentoTheme, _ label: String, _ verdict: String) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(InstrumentoType.overline).tracking(InstrumentoType.overlineTracking)
                    .textCase(.uppercase).foregroundStyle(t.inkTertiary)
                Text("RECUPERACIÓN").font(InstrumentoType.overline).tracking(InstrumentoType.overlineTracking)
                    .textCase(.uppercase).foregroundStyle(t.inkTertiary)
                Text("82").instrumentoHero(64).foregroundStyle(t.dataRecovery)
                Text(verdict).font(StrandFont.subhead).foregroundStyle(t.inkSecondary)
                Divider().overlay(t.hairline).padding(.vertical, 4)
                HStack(spacing: 8) {
                    ForEach([("ESFUERZO", t.dataStrain, "11.4"), ("ALERTA", t.warning, "—")], id: \.0) { lbl, c, v in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lbl).font(InstrumentoType.overline).foregroundStyle(t.inkTertiary)
                            Text(v).font(StrandFont.bodyNumber).foregroundStyle(c)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
            .frame(width: 210, height: 230, alignment: .topLeading)
            .background(t.paper)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(t.hairline, lineWidth: 1))
        }

        let grid = VStack(spacing: 16) {
            HStack(spacing: 16) {
                panel(theme(6),  "06:00 · amanecer", "Listo para un día fuerte")
                panel(theme(12), "12:00 · día",      "Bien recuperado")
            }
            HStack(spacing: 16) {
                panel(theme(19), "19:00 · atardecer", "Afloja el ritmo")
                panel(theme(23), "23:00 · noche",     "Hora de descansar")
            }
        }
        .padding(28)
        .background(Color(hex: "#E8E2D6"))

        let renderer = ImageRenderer(content: grid)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-fer132/theme_by_hour.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
}
#endif
