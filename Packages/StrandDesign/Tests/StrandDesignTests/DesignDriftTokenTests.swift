import XCTest
import SwiftUI
@testable import StrandDesign

/// Auditoría jul-2026 (cierre de deriva del sistema de diseño). Ancla los tokens nuevos que absorben
/// la deriva de las pantallas para que un cambio accidental de valor rompa CI en vez de derivar en
/// silencio: los radios semánticos de tarjeta (H3), la escala de glifos (H1) y la escala de
/// opacidades (H4). No renderiza — son aserciones baratas y deterministas.
final class DesignDriftTokenTests: XCTestCase {

    // H3 — radios de tarjeta: cada rol mapea a su token de CenitMetrics, sin literales fantasma.
    func test_cardRadiusRolesMapToTokens() {
        XCTAssertEqual(InstrumentoCardRadius.card.value,    CenitMetrics.cardRadius)
        XCTAssertEqual(InstrumentoCardRadius.cta.value,     CenitMetrics.ctaRadius)
        XCTAssertEqual(InstrumentoCardRadius.control.value, CenitMetrics.controlRadius)
        XCTAssertEqual(InstrumentoCardRadius.inset.value,   CenitMetrics.insetRadius)
        // Los cuatro radios son distintos y ordenados inset < control < cta < card.
        XCTAssertLessThan(InstrumentoCardRadius.inset.value, InstrumentoCardRadius.control.value)
        XCTAssertLessThan(InstrumentoCardRadius.control.value, InstrumentoCardRadius.cta.value)
        XCTAssertLessThan(InstrumentoCardRadius.cta.value, InstrumentoCardRadius.card.value)
        XCTAssertEqual(CenitMetrics.insetRadius, 10)
    }

    // H1 — escala de glifos: cuatro escalones fijos, crecientes.
    func test_glyphScaleIsFixedAndOrdered() {
        XCTAssertEqual(StrandFont.GlyphSize.chevron.rawValue, 12)
        XCTAssertEqual(StrandFont.GlyphSize.inline.rawValue, 15)
        XCTAssertEqual(StrandFont.GlyphSize.lead.rawValue, 18)
        XCTAssertEqual(StrandFont.GlyphSize.empty.rawValue, 34)
        let sizes = [StrandFont.GlyphSize.chevron, .inline, .lead, .empty].map(\.rawValue)
        XCTAssertEqual(sizes, sizes.sorted())
    }

    // H4 — escala de opacidades: valores sancionados, y `dim` == el precedente `disabledOpacity`.
    func test_opacityScale() {
        XCTAssertEqual(StrandOpacity.tintFill, 0.10)
        XCTAssertEqual(StrandOpacity.tintFillStrong, 0.14)
        XCTAssertEqual(StrandOpacity.strokeSoft, 0.30)
        XCTAssertEqual(StrandOpacity.dim, 0.45)
        XCTAssertEqual(StrandOpacity.muted, 0.60)
        XCTAssertEqual(StrandOpacity.dim, StrandPalette.disabledOpacity,
                       "`dim` debe seguir al precedente `disabledOpacity`")
        let scale: [Double] = [StrandOpacity.tintFill, StrandOpacity.tintFillStrong,
                               StrandOpacity.strokeSoft, StrandOpacity.dim, StrandOpacity.muted]
        XCTAssertEqual(scale, scale.sorted())
    }
}

#if os(macOS)
import AppKit

/// Harness de render del modifier `.instrumentoCard()` en sus 4 radios — para eyeball antes de que
/// compile la app (no es aserción de CI; los PNG caen en /tmp/noop-audit/).
/// Run: swift test --filter InstrumentoCardRenderTests
final class InstrumentoCardRenderTests: XCTestCase {
    @MainActor func test_renderFourRadii() throws {
        let t = InstrumentoTheme.base
        let demo = VStack(spacing: 16) {
            card("card", .card, t)
            card("cta", .cta, t)
            card("control", .control, t)
            card("inset", .inset, t)
        }
        .padding(24)
        .frame(width: 320)
        .background(t.paper)
        .instrumentoTheme(t)

        let renderer = ImageRenderer(content: demo)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-audit/instrumento_card.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }

    @MainActor private func card(_ name: String, _ r: InstrumentoCardRadius, _ t: InstrumentoTheme) -> some View {
        Text(name)
            .font(StrandFont.caption)
            .foregroundStyle(t.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(CenitMetrics.cardPadding)
            .instrumentoCard(r)
    }
}
#endif
