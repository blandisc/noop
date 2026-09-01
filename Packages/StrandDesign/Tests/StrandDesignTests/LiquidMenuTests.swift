import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-281 — LiquidMenu espeja el contrato de PaperMenu (FER-836/951).
final class LiquidMenuTests: XCTestCase {

    // MARK: - LiquidMenuItem inits

    func test_actionInit_preservesFields_andEmptyChildren() {
        var fired = false
        let item = LiquidMenuItem(
            "Quitar",
            subtitle: "no se puede deshacer",
            systemImage: "trash",
            isDestructive: true,
            action: { fired = true })

        XCTAssertEqual(item.title, "Quitar")
        XCTAssertEqual(item.subtitle, "no se puede deshacer")
        XCTAssertEqual(item.systemImage, "trash")
        XCTAssertTrue(item.isDestructive)
        XCTAssertTrue(item.children.isEmpty)

        item.action()
        XCTAssertTrue(fired)
    }

    func test_childrenInit_preservesFields_andDisablesDestructiveAction() {
        let child = LiquidMenuItem("Empuje y jalón")
        let item = LiquidMenuItem(
            "Mover a carpeta",
            subtitle: "elige destino",
            systemImage: "folder",
            children: [child])

        XCTAssertEqual(item.title, "Mover a carpeta")
        XCTAssertEqual(item.subtitle, "elige destino")
        XCTAssertEqual(item.systemImage, "folder")
        XCTAssertFalse(item.isDestructive,
                       "submenu rows never carry isDestructive (PaperMenu contract)")
        XCTAssertEqual(item.children.count, 1)
        XCTAssertEqual(item.children[0].title, "Empuje y jalón")

        // Default no-op action — must not crash.
        item.action()
    }

    func test_actionInit_defaults() {
        let item = LiquidMenuItem("Solo título")
        XCTAssertNil(item.subtitle)
        XCTAssertNil(item.systemImage)
        XCTAssertFalse(item.isDestructive)
        XCTAssertTrue(item.children.isEmpty)
    }

    // MARK: - estimatedHeight (misma matemática que PaperMenuCard)

    func test_estimatedHeight_plainRows() {
        // 3 filas sin subtítulo: 3×49 + 12 = 159
        XCTAssertEqual(
            LiquidMenuMetrics.estimatedHeight(rowCount: 3, subtitleCount: 0, hasBackRow: false),
            3 * 49 + 12)
    }

    func test_estimatedHeight_withSubtitles() {
        // 4 filas, 1 subtítulo: 4×49 + 14 + 12 = 222
        XCTAssertEqual(
            LiquidMenuMetrics.estimatedHeight(rowCount: 4, subtitleCount: 1, hasBackRow: false),
            4 * 49 + 14 + 12)
    }

    func test_estimatedHeight_withBackRow() {
        // Submenú: fila de regreso + 3 hijos: 41 + 3×49 + 12 = 200
        XCTAssertEqual(
            LiquidMenuMetrics.estimatedHeight(rowCount: 3, subtitleCount: 0, hasBackRow: true),
            41 + 3 * 49 + 12)
    }

    func test_estimatedHeight_capsAt420() {
        // 14 filas con varios subtítulos explotan el tope.
        let raw = LiquidMenuMetrics.estimatedHeight(
            rowCount: 14, subtitleCount: 5, hasBackRow: false)
        XCTAssertEqual(raw, LiquidMenuMetrics.heightCap)
        XCTAssertEqual(LiquidMenuMetrics.heightCap, 420)
    }

    func test_estimatedHeight_matchesPaperMenuFormula() {
        // Reconstruye la fórmula inline de PaperMenuCard para documentar paridad:
        // base(back) + Σ(49 + 14si subtítulo) + 12, min(_, 420).
        func paperFormula(hasSubtitles: [Bool], hasBack: Bool) -> CGFloat {
            let base: CGFloat = hasBack ? 41 : 0
            let content = hasSubtitles.reduce(CGFloat(0)) { $0 + 49 + ($1 ? 14 : 0) }
            return min(base + content + 12, 420)
        }

        let cases: [(hasSubtitles: [Bool], hasBack: Bool)] = [
            ([false, false, false], false),
            ([false, true, false, false], false),
            ([false, false], true),
            (Array(repeating: true, count: 12), false)
        ]
        for c in cases {
            let subtitles = c.hasSubtitles.filter { $0 }.count
            XCTAssertEqual(
                LiquidMenuMetrics.estimatedHeight(
                    rowCount: c.hasSubtitles.count,
                    subtitleCount: subtitles,
                    hasBackRow: c.hasBack),
                paperFormula(hasSubtitles: c.hasSubtitles, hasBack: c.hasBack))
        }
    }

    func test_metrics_matchKnownTokens() {
        XCTAssertEqual(LiquidMenuMetrics.iconColumn, LiquidSpace.s600)
        XCTAssertEqual(LiquidMenuMetrics.dividerHeight, LiquidSpace.s025)
        XCTAssertEqual(LiquidMenuMetrics.subtitleExtra, LiquidSpace.handoff14)
        XCTAssertEqual(LiquidMenuMetrics.verticalBreathing, LiquidSpace.s300)
        XCTAssertEqual(LiquidSpace.s150, 6, "vertical padding of the card content")
    }

    @MainActor
    func test_card_existsAsPublicAPI() {
        #if !os(watchOS)
        if #available(iOS 16.4, macOS 13.3, *) {
            let _: any View = LiquidMenuCard(
                items: [.init("A"), .init("B", children: [.init("B1")])],
                isPresented: .constant(false))
        }
        #endif
    }
}
