#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-113 — render harness for the redesigned verdict hero ("two truths" + footer link) and the
/// "¿Por qué?" sheet, so the design can be eyeballed before the production view is built in TodayView.
/// Not a CI assertion — a developer render harness. Run: swift test --filter VerdictHeroSnapshotTests
/// PNGs land in /tmp/noop-fer113/.
final class VerdictHeroSnapshotTests: XCTestCase {

    @MainActor func test_renderHeroDivergenceLoad() throws {
        try render(VerdictHeroPreview(
            levelColor: StrandPalette.statusWarning, verdict: "Exigido", culprit: "por la carga",
            recovery: 92, recState: "PEAK",
            bridge: "Amaneciste muy recuperado. Lo que pide cuidado: hoy es tu carga, no tu cuerpo.",
            whyLabel: "¿Por qué exigido?"), to: "hero_divergence_load")
    }

    @MainActor func test_renderHeroPrimed() throws {
        try render(VerdictHeroPreview(
            levelColor: StrandPalette.statusPrimed, verdict: "Listo", culprit: "",
            recovery: 95, recState: "PEAK",
            bridge: "Tus señales están alineadas y tu carga aguanta. Un día fuerte está bien respaldado.",
            whyLabel: "¿Por qué listo?"), to: "hero_primed")
    }

    @MainActor func test_renderHeroRundown() throws {
        try render(VerdictHeroPreview(
            levelColor: StrandPalette.metricRose, verdict: "Agotado", culprit: "por varias señales",
            recovery: 38, recState: "LOW",
            bridge: "Varias señales están abajo. Hoy toca recuperar.",
            whyLabel: "¿Por qué agotado?"), to: "hero_rundown")
    }

    @MainActor func test_renderWhySheet() throws {
        try render(WhyVerdictSheetPreview(), to: "why_sheet", width: 380)
    }

    // MARK: harness

    @MainActor private func render<V: View>(_ content: V, to name: String, width: CGFloat = 390) throws {
        let view = content
            .padding(width == 390 ? NoopMetrics.screenPadding : 0)
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
        let url = URL(fileURLWithPath: "/tmp/noop-fer113/\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
}

// MARK: - Hero (two truths + footer link)

private struct VerdictHeroPreview: View {
    let levelColor: Color
    let verdict: String
    let culprit: String
    let recovery: Int
    let recState: String
    let bridge: String
    let whyLabel: String

    private var recColor: Color { StrandPalette.recoveryColor(Double(recovery)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VEREDICTO DE HOY")
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(InstrumentoTheme.base.inkTertiary)
            HStack(spacing: 10) {
                box("Veredicto", tint: levelColor) {
                    Text(verdict).font(StrandFont.title2).foregroundStyle(levelColor)
                    if !culprit.isEmpty {
                        Text(culprit).font(StrandFont.caption).foregroundStyle(levelColor)
                    }
                }
                box("Recuperación", tint: recColor) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(recovery)").font(StrandFont.number(22)).foregroundStyle(recColor)
                        Text("/100").font(StrandFont.caption).foregroundStyle(recColor.opacity(0.8))
                    }
                    Text(recState).font(StrandFont.caption).foregroundStyle(recColor)
                }
            }
            Text(bridge)
                .font(StrandFont.subhead).foregroundStyle(InstrumentoTheme.base.ink)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(InstrumentoTheme.base.hairline)
            HStack(spacing: 7) {
                Image(systemName: "info.circle").font(.system(size: 13))
                Text(whyLabel).font(StrandFont.caption)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(InstrumentoTheme.base.inkTertiary)
            }
            .foregroundStyle(StrandPalette.metricCyan)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(levelColor.opacity(0.08), in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(levelColor.opacity(0.30), lineWidth: 1))
    }

    @ViewBuilder private func box<Content: View>(_ label: String, tint: Color,
                                                 @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(InstrumentoTheme.base.inkTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.30), lineWidth: 0.5))
    }
}

// MARK: - "¿Por qué?" sheet

private struct WhyVerdictSheetPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(InstrumentoTheme.base.hairlineStrong).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 9).padding(.bottom, 14)
            HStack {
                Text("¿Por qué exigido?").font(StrandFont.headline).foregroundStyle(InstrumentoTheme.base.ink)
                Spacer(minLength: 0)
                Image(systemName: "xmark").font(.system(size: 15)).foregroundStyle(InstrumentoTheme.base.inkTertiary)
            }.padding(.bottom, 12)

            HStack(spacing: 8) {
                Circle().fill(StrandPalette.statusWarning).frame(width: 11, height: 11)
                Text("Hoy tu día es ámbar — Exigido").font(StrandFont.subhead).foregroundStyle(InstrumentoTheme.base.ink)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StrandPalette.statusWarning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(StrandPalette.statusWarning.opacity(0.30), lineWidth: 0.5))
            .padding(.bottom, 11)

            Text("Tu recuperación salió alta (92), pero el veredicto pesa una señal: tu carga de entrenamiento viene elevada. Por eso ámbar y no verde.")
                .font(StrandFont.subhead).foregroundStyle(InstrumentoTheme.base.inkSecondary)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, 16)

            Text("TUS SEÑALES HOY").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(InstrumentoTheme.base.inkTertiary).padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 11) {
                signal(StrandPalette.accent, "HRV", "sobre tu base — bien recuperado")
                signal(InstrumentoTheme.base.inkTertiary, "FC en reposo", "en tu rango normal")
                signal(InstrumentoTheme.base.inkTertiary, "Respiración", "normal")
                signal(StrandPalette.statusWarning, "Carga de entrenamiento", "alta · 1.6 agudo:crónico — baja el ritmo si hay fatiga")
            }

            Divider().overlay(InstrumentoTheme.base.hairline).padding(.vertical, 14)

            Text("QUÉ SIGNIFICA CADA COLOR").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(InstrumentoTheme.base.inkTertiary).padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 4) {
                legend(StrandPalette.statusPrimed, "Listo", "señales alineadas y carga que aguanta", here: false)
                legend(StrandPalette.statusPositive, "Equilibrado", "nada está flaggeando", here: false)
                legend(StrandPalette.statusWarning, "Exigido", "una señal pide cuidado", here: true)
                legend(StrandPalette.metricRose, "Agotado", "varias señales abajo", here: false)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstrumentoTheme.base.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func signal(_ color: Color, _ label: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(StrandFont.caption).foregroundStyle(InstrumentoTheme.base.ink)
                Text(detail).font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func legend(_ color: Color, _ name: String, _ condition: String, here: Bool) -> some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(name).font(StrandFont.caption).foregroundStyle(InstrumentoTheme.base.ink).frame(width: 86, alignment: .leading)
            Text(condition).font(StrandFont.footnote).foregroundStyle(here ? color : InstrumentoTheme.base.inkTertiary)
            Spacer(minLength: 0)
            if here {
                Text("HOY").font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(here ? StrandPalette.statusWarning.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
#endif
