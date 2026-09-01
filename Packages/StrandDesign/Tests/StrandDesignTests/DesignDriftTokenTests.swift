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

    // MARK: - FER-273 (Fase 1a, CONTRATO.md checklist Fase 1) — igualdad exacta de las 5 piezas
    // token minteadas del censo (docs/design-system/CENSO.md §clusters). Ninguna se aplica a un
    // call-site en este PR — estos tests solo anclan la CIFRA para que un cambio accidental
    // rompa CI, igual que el resto de este archivo.

    // (2) respiro horizontal de chip — CENSO «horizontal/chip handoff» (10 sitios, moda 9).
    func test_chipHorizontalMatchesCensusMode() {
        XCTAssertEqual(LiquidSpace.chipHorizontal, 9)
    }

    // (3) borde-de-tarjeta / respiro-de-fila — CENSO «edge ≠ rowVPad»: misma cifra (10) que
    // `CenitMetrics.rowVPad`, dos roles nuevos y distintos entre sí, ninguno el legacy.
    func test_seccionCantoAndFilaRespiroMatchCensusValueButNotRowVPadRole() {
        XCTAssertEqual(LiquidSpace.seccionCanto, 10)
        XCTAssertEqual(LiquidSpace.filaRespiro, 10)
        XCTAssertEqual(LiquidSpace.seccionCanto, CenitMetrics.rowVPad,
                        "misma CIFRA por diseño — el rol es lo que los distingue, no el número")
    }

    // (4) tipográfico cuerpo-de-banner 13pt — CENSO «cuerpo de banner (13pt, igual que el
    // mensaje de ConfirmCard)»: comparte CIFRA con `LiquidType.clausulaCampo` (13), no familia.
    func test_cuerpoBannerMatchesConfirmCardMessageSize() {
        XCTAssertEqual(LiquidType.cuerpoBannerTamano, 13)
    }

    // (5) handoff 14 y handoff 44 (== mínimo táctil HIG, nombre propio) — CENSO «14 del
    // handoff» / «44 del handoff».
    func test_handoffSpacingTokens() {
        XCTAssertEqual(LiquidSpace.handoff14, 14)
        XCTAssertEqual(LiquidSpace.handoff44, 44)
        XCTAssertEqual(LiquidSpace.handoff44, LiquidControl.hitTarget,
                        "misma CIFRA que el mínimo táctil por diseño — el rol (gap de layout, no toque) es lo que los distingue")
    }

    // (6) chip compacto 11/5 — CENSO «chip 11/5 del handoff» (3 sitios, 2 exactos).
    func test_chipCompactoMatchesCensusValue() {
        XCTAssertEqual(LiquidChip.compactoHorizontal, 11)
        XCTAssertEqual(LiquidChip.compactoVertical, 5)
    }

    // MARK: - FER-275 (Lote Uno, aprobación del dueño 2026-09-01) — igualdad exacta de las
    // piezas minteadas en este lote.

    func test_topeScrollMatchesCensusValue() {
        XCTAssertEqual(LiquidSpace.topeScroll, 20)
    }

    func test_ctaVerticalMatchesCensusValue() {
        XCTAssertEqual(LiquidSpace.ctaVertical, 15)
    }

    func test_liquidRadiusChipMatchesOwnerApprovedPixel() {
        XCTAssertEqual(LiquidRadius.chip, 8)
    }

    func test_estadoVacioAireAndBloqueAjusteMatchCensusValueButAreDistinctRoles() {
        XCTAssertEqual(LiquidSpace.estadoVacioAire, 14)
        XCTAssertEqual(LiquidSpace.bloqueAjuste, 14)
        XCTAssertEqual(LiquidSpace.estadoVacioAire, LiquidSpace.handoff14,
                        "misma CIFRA por diseño — el rol (spacing de VStack, no padding de tarjeta) es lo que los distingue")
    }

    // MARK: - FER-269a (Fase 3, primera ola) — dimensión movimiento: 12 literal-curve-duration +
    // 37 literal-transition del censo. Igualdad exacta de valor Y de curva/transición (por
    // descripción — `Animation`/`AnyTransition` no son `Equatable`, pero dos valores construidos
    // igual describen igual en este toolchain).

    // Duraciones nuevas: cifras REALES más frecuentes del censo de movimiento (no inventadas).
    func test_movimientoDuracionesMatchCensusValues() {
        XCTAssertEqual(LiquidMotion.brief, 0.15)     // Watch check-toggle (2 sitios)
        XCTAssertEqual(LiquidMotion.soft, 0.2)       // fase de respiración + reveal del héroe (3 sitios)
        XCTAssertEqual(LiquidMotion.measured, 0.35)  // gates de arranque (2 sitios)
    }

    // Curvas nuevas: `settle` (easeOut) y `dismiss` (easeIn) deben producir EXACTAMENTE la misma
    // animación que el literal crudo que envuelven — probado por descripción.
    func test_movimientoCurvasMatchRawEquivalents() {
        XCTAssertEqual(String(describing: LiquidMotion.settle(LiquidMotion.brief)),
                       String(describing: Animation.easeOut(duration: 0.15)))
        XCTAssertEqual(String(describing: LiquidMotion.dismiss(LiquidMotion.brief)),
                       String(describing: Animation.easeIn(duration: 0.15)))
        XCTAssertEqual(String(describing: LiquidMotion.settle(LiquidMotion.soft)),
                       String(describing: Animation.easeOut(duration: 0.2)))
        XCTAssertEqual(String(describing: LiquidMotion.ambient(LiquidMotion.soft)),
                       String(describing: Animation.easeInOut(duration: 0.2)))
        XCTAssertEqual(String(describing: LiquidMotion.ambient(LiquidMotion.measured)),
                       String(describing: Animation.easeInOut(duration: 0.35)))
    }

    // Transiciones nuevas: cada receta debe describir EXACTAMENTE igual que el `AnyTransition`
    // crudo que envuelve.
    func test_movimientoTransicionesMatchRawEquivalents() {
        XCTAssertEqual(String(describing: LiquidMotion.fadeTransition),
                       String(describing: AnyTransition.opacity))
        XCTAssertEqual(String(describing: LiquidMotion.risingFadeTransition),
                       String(describing: AnyTransition.move(edge: .bottom).combined(with: .opacity)))
        XCTAssertEqual(String(describing: LiquidMotion.fallingFadeTransition),
                       String(describing: AnyTransition.move(edge: .top).combined(with: .opacity)))
        XCTAssertEqual(String(describing: LiquidMotion.trailingTransition),
                       String(describing: AnyTransition.move(edge: .trailing)))
        XCTAssertEqual(String(describing: LiquidMotion.fadeOrIdentity(reduceMotion: false)),
                       String(describing: AnyTransition.opacity))
        XCTAssertEqual(String(describing: LiquidMotion.fadeOrIdentity(reduceMotion: true)),
                       String(describing: AnyTransition.identity))
    }
}

/// (1) `LiquidSectionHeader` — el componente Liquid que reemplaza `InstrumentoSectionBand`
/// (sin banda de papel). Test barato de existencia/forma: el kicker reusa `LiquidType.kicker`
/// y el `Trailing == EmptyView` sigue disponible cuando no hay acción — no renderiza, solo
/// prueba que el API se construye con el mismo patrón que `InstrumentoSectionBand`.
final class LiquidSectionHeaderTests: XCTestCase {
    @MainActor func test_initWithAndWithoutTrailingCompiles() {
        _ = LiquidSectionHeader("Título")
        _ = LiquidSectionHeader("Título") { Text("acción") }
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
