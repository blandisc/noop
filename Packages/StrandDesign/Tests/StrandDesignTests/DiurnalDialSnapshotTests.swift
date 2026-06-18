#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-134 — renders the Diurnal Dial at 12:30 / 19:00 / 23:30 and the polar case
/// (no solar window) to a PNG so the day arc, sleep band, sunrise/sunset marks and
/// the now-dot can be eyeballed against the by-the-hour theme. ImageRenderer does
/// not fire `onAppear`, so it captures the resting state — which is the final state:
/// the dot settled at the current hour, halo static. Developer render harness, not
/// a CI assertion. Run: swift test --filter DiurnalDialSnapshotTests
final class DiurnalDialSnapshotTests: XCTestCase {

    @MainActor
    func test_renderDialByHour() throws {
        func utc() -> Calendar {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "UTC")!
            return c
        }
        func at(_ h: Int, _ m: Int = 0) -> Date {
            utc().date(from: DateComponents(year: 2026, month: 6, day: 16, hour: h, minute: m))!
        }
        let sun = SolarWindow(sunrise: 6.2, sunset: 19.8)
        let bed = SleepWindow(bedtime: 23.5, wake: 7.25)

        func panel(_ label: String, _ date: Date, solar: SolarWindow?, syncing: Bool = false) -> some View {
            let theme = InstrumentoThemeEngine.theme(at: date, calendar: utc(), solar: solar)
            return VStack(spacing: 12) {
                DiurnalDial(now: date, calendar: utc(), solar: solar, sleep: bed, diameter: 170,
                            syncing: syncing, animated: false)
                Text(label).font(InstrumentoType.overline).tracking(InstrumentoType.overlineTracking)
                    .textCase(.uppercase).foregroundStyle(theme.inkTertiary)
            }
            .padding(18)
            .frame(width: 230)
            .background(theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .instrumentoTheme(theme)
        }

        let grid = VStack(spacing: 16) {
            HStack(spacing: 16) {
                panel("12:30 · día", at(12, 30), solar: sun)
                panel("19:00 · atardecer", at(19), solar: sun)
            }
            HStack(spacing: 16) {
                panel("23:30 · noche", at(23, 30), solar: sun)
                panel("14:00 · sin sol (polar)", at(14), solar: nil)
            }
            // FER-221: el modo «sincronizando» — el arco verde reposa estático (sin animación) para
            // que el render sea determinista; el reloj de abajo debe permanecer legible.
            HStack(spacing: 16) {
                panel("12:30 · sincronizando", at(12, 30), solar: sun, syncing: true)
                panel("23:30 · sincronizando", at(23, 30), solar: sun, syncing: true)
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
        let url = URL(fileURLWithPath: "/tmp/noop-fer134/dial_by_hour.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }

    /// FER-222 — renders the determinate «arming» arc (pull-to-refresh) at progress 0 / 0.5 / 1.0
    /// and the `syncing` handoff, so the arc growth + head-dot placement can be eyeballed against
    /// the spinning comet it cedes to. Resting capture (no animation), like the by-hour test.
    /// Run: swift test --filter DiurnalDialSnapshotTests/test_renderDialArming
    @MainActor
    func test_renderDialArming() throws {
        func utc() -> Calendar {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "UTC")!
            return c
        }
        let date = utc().date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 14))!
        let sun = SolarWindow(sunrise: 6.2, sunset: 19.8)
        let bed = SleepWindow(bedtime: 23.5, wake: 7.25)
        let theme = InstrumentoThemeEngine.theme(at: date, calendar: utc(), solar: sun)

        func panel(_ label: String, armProgress: Double = 0, syncing: Bool = false) -> some View {
            VStack(spacing: 12) {
                DiurnalDial(now: date, calendar: utc(), solar: sun, sleep: bed, diameter: 170,
                            syncing: syncing, armProgress: armProgress, animated: false)
                Text(label).font(InstrumentoType.overline).tracking(InstrumentoType.overlineTracking)
                    .textCase(.uppercase).foregroundStyle(theme.inkTertiary)
            }
            .padding(18)
            .frame(width: 230)
            .background(theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .instrumentoTheme(theme)
        }

        let grid = VStack(spacing: 16) {
            HStack(spacing: 16) {
                panel("reposo")
                panel("armando 50%", armProgress: 0.5)
            }
            HStack(spacing: 16) {
                panel("umbral · 100%", armProgress: 1.0)
                panel("sincronizando", syncing: true)
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
        let url = URL(fileURLWithPath: "/tmp/noop-fer222/dial_arming.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
}
#endif
