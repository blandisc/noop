#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// Render harness for the thermal-receipt family (Entrenar «Recibo», jul-2026): the full ticket, the
/// saved-tickets grid, and the printer mouth + «GUARDADO» seal — so the torn edge, barcode, zone
/// colors and layout can be eyeballed against the approved design without a simulator. Developer
/// render harness, not a CI assertion. Run: swift test --filter ThermalTicketSnapshotTests
final class ThermalTicketSnapshotTests: XCTestCase {

    @MainActor
    private func write(_ view: some View, to path: String, scale: CGFloat = 2) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }

    @MainActor
    func test_renderThermalFamily() throws {
        // Full ticket
        try write(
            ThermalTicketView(receipt: .sample).padding(40).background(Color(hex: "#F4F1E8")),
            to: "/tmp/noop-recibo/ticket_full.png"
        )
        // Mini-ticket grid
        let cols = [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)]
        let grid = LazyVGrid(columns: cols, spacing: 11) {
            ForEach(MiniTicket.sampleGrid) { MiniTicketView(ticket: $0) }
        }
        .frame(width: 320)
        .padding(20)
        .background(Color(hex: "#F4F1E8"))
        try write(grid, to: "/tmp/noop-recibo/mini_grid.png")
        // Printer mouth + GUARDADO
        let saved = VStack(spacing: 0) {
            PrinterMouth(width: 200)
            Spacer().frame(height: 44)
            ReceiptSavedSeal()
            Spacer().frame(height: 30)
        }
        .padding(.top, 8)
        .frame(width: 300)
        .background(InstrumentoTheme.base.paper)
        .environment(\.instrumentoTheme, .base)
        try write(saved, to: "/tmp/noop-recibo/mouth_saved.png")
    }
}
#endif
