#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// /ui pass for the Today "data sources" footnote redesign. Renders 3 distinct visual
/// variants (single clean line / contained card / quiet monochrome chips) to PNG so the
/// design can be eyeballed before the production view in TodayView is touched.
///
/// Not a CI assertion — a developer render harness. Tokens-only (no inline hex/font/spacing).
/// Run: swift test --filter SourcesSectionSnapshotTests   →  PNGs land in /tmp/noop-sources/.
///
/// Sample data (per the brief): WHOOP 2 días · 1 noche, Apple Health 32 días · 8 entrenamientos,
/// "Historial sincronizado hace 5 min".
final class SourcesSectionSnapshotTests: XCTestCase {

    // The width of the Today content column at the iPhone screen padding NoopMetrics.screenPadding.
    private let columnWidth: CGFloat = 390 - 2 * NoopMetrics.screenPadding

    @MainActor func test_renderVariantA_singleLine() throws {
        try render(SourcesVariantA(), to: "variant_a_single_line")
    }

    @MainActor func test_renderVariantB_card() throws {
        try render(SourcesVariantB(), to: "variant_b_card")
    }

    @MainActor func test_renderVariantC_quietChips() throws {
        try render(SourcesVariantC(), to: "variant_c_quiet_chips")
    }

    // MARK: production-faithful state renders (FER-119 — mirror TodayView.sourcesSection exactly)

    @MainActor func test_renderProdBothSources() throws {
        try render(ProdSourcesCard(whoop: true, apple: true, state: .synced), to: "prod_both_sources")
    }
    @MainActor func test_renderProdOnlyWhoop() throws {
        try render(ProdSourcesCard(whoop: true, apple: false, state: .synced), to: "prod_only_whoop")
    }
    @MainActor func test_renderProdOnlyApple() throws {
        try render(ProdSourcesCard(whoop: false, apple: true, state: .synced), to: "prod_only_apple")
    }
    @MainActor func test_renderProdError() throws {
        try render(ProdSourcesCard(whoop: true, apple: true, state: .error), to: "prod_error")
    }
    @MainActor func test_renderProdSyncOnly() throws {
        try render(ProdSourcesCard(whoop: false, apple: false, state: .synced), to: "prod_sync_only")
    }

    /// All states stacked for an at-a-glance check.
    @MainActor func test_renderProdStates() throws {
        let stack = VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            label("AMBAS FUENTES");      ProdSourcesCard(whoop: true,  apple: true,  state: .synced)
            label("SOLO WHOOP");         ProdSourcesCard(whoop: true,  apple: false, state: .synced)
            label("SOLO APPLE HEALTH");  ProdSourcesCard(whoop: false, apple: true,  state: .synced)
            label("ERROR DE SYNC");      ProdSourcesCard(whoop: true,  apple: true,  state: .error)
            label("SOLO SYNC (SIN DATOS)"); ProdSourcesCard(whoop: false, apple: false, state: .synced)
        }
        try render(stack, to: "prod_states")
    }

    /// All three stacked on one canvas for an at-a-glance comparison.
    @MainActor func test_renderComparison() throws {
        let stack = VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            label("A · UNA LÍNEA LIMPIA")
            SourcesVariantA()
            label("B · TARJETA CONTENEDORA")
            SourcesVariantB()
            label("C · CHIPS MONOCROMÁTICOS")
            SourcesVariantC()
        }
        try render(stack, to: "comparison")
    }

    private func label(_ s: String) -> some View {
        Text(s).font(StrandFont.overline).tracking(StrandFont.overlineTracking)
            .foregroundStyle(StrandPalette.accent)
    }

    // MARK: render harness (copied from ChartSnapshotTests / VerdictHeroSnapshotTests)

    @MainActor private func render<V: View>(_ content: V, to name: String, width: CGFloat = 390) throws {
        let view = content
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.vertical, NoopMetrics.screenPadding)
            .frame(width: width)
            .background(InstrumentoTheme.base.paper)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-sources/\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
}

// MARK: - Sample copy (es-MX, fixed — copy is owned by /ux, this just mirrors the brief)

private enum SourcesSample {
    static let whoopCount = "2 días · 1 noche"
    static let appleCount = "32 días · 8 entrenamientos"
    static let sync = "Historial sincronizado hace 5 min"
}

// MARK: - Production-faithful card (FER-119) — mirrors TodayView.sourcesSection token-for-token.

/// Replica exacta de la Variante B tal como quedó en producción, para verificar los estados que
/// el PNG aprobado (ambas fuentes) no cubría: una sola fuente, error de sync, y card sólo-sync.
struct ProdSourcesCard: View {
    enum SyncState { case synced, error }
    let whoop: Bool
    let apple: Bool
    let state: SyncState
    var hasData: Bool { whoop || apple }

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                Text("FUENTES").strandOverline()
                if hasData {
                    if whoop {
                        row(symbol: "bolt.heart.fill", name: "WHOOP",
                            count: SourcesSample.whoopCount, tint: StrandPalette.accent)
                    }
                    if apple {
                        row(symbol: "heart.fill", name: "Apple Health",
                            count: SourcesSample.appleCount, tint: StrandPalette.metricCyan)
                    }
                }
                if hasData { Divider().overlay(InstrumentoTheme.base.hairline) }
                switch state {
                case .error:
                    syncLine(text: "No se pudo sincronizar el historial", tone: .warning,
                             color: StrandPalette.statusWarning)
                case .synced:
                    syncLine(text: SourcesSample.sync, tone: .neutral, color: InstrumentoTheme.base.inkTertiary)
                }
            }
        }
    }

    private func row(symbol: String, name: LocalizedStringKey, count: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: NoopMetrics.sourceGlyph, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(name).font(StrandFont.subhead).foregroundStyle(InstrumentoTheme.base.ink)
            Spacer(minLength: 8)
            Text(count).font(StrandFont.captionNumber).foregroundStyle(InstrumentoTheme.base.inkSecondary)
        }
    }

    private func syncLine(text: String, tone: StrandTone, color: Color) -> some View {
        HStack(spacing: 6) {
            ConnectionDot(tone: tone, size: 6)
            Text(text).font(StrandFont.footnote).foregroundStyle(color)
        }
    }
}

// MARK: - Variant A — Una línea limpia (single inline row + trailing sync pill)
//
// One calm horizontal line. Each source = SF Symbol glyph in its tint + name + tabular count,
// the two separated by a vertical hairline. Sync moves to a trailing StatePill (chrome, not a
// gray sentence). Smallest footprint; reads L→R as a status strip.

struct SourcesVariantA: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(spacing: 14) {
                sourceItem(symbol: "bolt.heart.fill", name: "WHOOP",
                           count: SourcesSample.whoopCount, tint: StrandPalette.accent)
                Rectangle().fill(InstrumentoTheme.base.hairline)
                    .frame(width: 1, height: 22)
                sourceItem(symbol: "heart.fill", name: "APPLE HEALTH",
                           count: SourcesSample.appleCount, tint: StrandPalette.metricCyan)
                Spacer(minLength: 8)
            }
            StatePill(LocalizedStringKey(SourcesSample.sync), tone: .neutral, showsDot: true)
        }
    }

    private func sourceItem(symbol: String, name: String, count: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                    .foregroundStyle(InstrumentoTheme.base.inkSecondary)
                Text(count).font(StrandFont.captionNumber)
                    .foregroundStyle(InstrumentoTheme.base.inkTertiary)
            }
        }
    }
}

// MARK: - Variant B — Tarjeta contenedora (NoopCard + two rows + sync footer)
//
// Gives the section a real home: the one card surface, an overline title, two MetricRow-style
// rows (icon + source name on the left, tabular count on the right), and the sync line as a
// hairline-divided footer with a StatePill. Most structured / "designed", largest footprint.

struct SourcesVariantB: View {
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("FUENTES").strandOverline()
                sourceRow(symbol: "bolt.heart.fill", name: "WHOOP",
                          count: SourcesSample.whoopCount, tint: StrandPalette.accent)
                sourceRow(symbol: "heart.fill", name: "Apple Health",
                          count: SourcesSample.appleCount, tint: StrandPalette.metricCyan)
                Divider().overlay(InstrumentoTheme.base.hairline)
                HStack(spacing: 6) {
                    ConnectionDot(tone: .neutral, size: 6)
                    Text(SourcesSample.sync).font(StrandFont.footnote)
                        .foregroundStyle(InstrumentoTheme.base.inkTertiary)
                }
            }
        }
    }

    private func sourceRow(symbol: String, name: String, count: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(name).font(StrandFont.subhead).foregroundStyle(InstrumentoTheme.base.ink)
            Spacer(minLength: 8)
            Text(count).font(StrandFont.captionNumber)
                .foregroundStyle(InstrumentoTheme.base.inkSecondary)
        }
    }
}

// MARK: - Variant C — Chips monocromáticos (quiet, single-accent)
//
// Kills the two competing tints entirely: source identity is carried by the SF Symbol glyph only,
// everything else is neutral chrome (textSecondary / textTertiary). The lone accent in the whole
// block is the small sync dot. Quietest of the three — pure footnote that recedes.

struct SourcesVariantC: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                chip(symbol: "bolt.heart.fill", name: "WHOOP", count: SourcesSample.whoopCount)
                chip(symbol: "heart.fill", name: "APPLE HEALTH", count: SourcesSample.appleCount)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                ConnectionDot(tone: .accent, size: 6)
                Text(SourcesSample.sync).font(StrandFont.footnote)
                    .foregroundStyle(InstrumentoTheme.base.inkTertiary)
            }
        }
    }

    private func chip(symbol: String, name: String, count: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(InstrumentoTheme.base.inkSecondary)
            Text(name).font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(InstrumentoTheme.base.inkSecondary)
            Text(count).font(StrandFont.captionNumber)
                .foregroundStyle(InstrumentoTheme.base.inkTertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(InstrumentoTheme.base.hairline, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(InstrumentoTheme.base.hairline, lineWidth: 1))
    }
}
#endif
