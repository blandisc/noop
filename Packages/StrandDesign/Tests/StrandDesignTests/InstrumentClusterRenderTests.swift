#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// FER-292 v2 — developer render harness for the Coach «instrument cluster» pieces (zone gauge,
/// dumbbell, finding glyphs) and the composed decision hero, so they can be eyeballed on paper before
/// wiring into BucleView. Not a CI assertion. Run: swift test --filter InstrumentClusterRenderTests
/// PNGs land in /tmp/noop-fer292/.
final class InstrumentClusterRenderTests: XCTestCase {

    private let t = InstrumentoTheme.base

    @MainActor func test_renderGauges() throws {
        try render(HStack(spacing: 22) {
            RecoveryZoneGauge(score: 82, label: "RECUPERACIÓN", theme: t)
            RecoveryZoneGauge(score: 48, label: "RECUPERACIÓN", theme: t)
            RecoveryZoneGauge(score: 18, label: "RECUPERACIÓN", theme: t)
        }, to: "gauges", width: 460)
    }

    @MainActor func test_renderDumbbells() throws {
        try render(VStack(spacing: 24) {
            BehaviorDumbbell(meanWith: 48, meanWithout: 56, withText: "48", withoutText: "56 lpm",
                             withIsBetter: true, hue: t.dataHeart, theme: t)
            BehaviorDumbbell(meanWith: 7.9, meanWithout: 6.8, withText: "7.9 h", withoutText: "6.8 h",
                             withIsBetter: true, hue: t.dataSleep, theme: t)
        }, to: "dumbbells", width: 300)
    }

    @MainActor func test_renderGlyphs() throws {
        try render(HStack(spacing: 22) {
            InsightGlyph(kind: .relation, primary: t.dataRecovery, secondary: t.dataHrv, theme: t)
            InsightGlyph(kind: .trend, values: [40, 42, 41, 44, 46, 45, 49, 52, 55, 58, 61, 64, 67, 70],
                         primary: t.dataRecovery, secondary: t.dataHrv, theme: t)
            InsightGlyph(kind: .anomaly, primary: t.dataHeart, secondary: t.dataHrv, theme: t)
        }, to: "glyphs", width: 240)
    }

    @MainActor func test_renderHeroCluster() throws {
        try render(HeroClusterPreview(theme: t), to: "hero_cluster", width: 333)
    }

    @MainActor func test_renderLowerSections() throws {
        try render(LowerSectionsPreview(theme: t), to: "lower_sections", width: 333)
    }

    // MARK: harness

    @MainActor private func render<V: View>(_ content: V, to name: String, width: CGFloat) throws {
        let view = content
            .padding(20)
            .frame(width: width, alignment: .leading)
            .background(t.paper)
            .instrumentoTheme(t)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-fer292/\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
}

private struct HeroClusterPreview: View {
    let theme: InstrumentoTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Decision: gauge + verdict
            VStack(alignment: .leading, spacing: 0) {
                Text("Decisión de hoy").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(spacing: 18) {
                    RecoveryZoneGauge(score: 82, label: "RECUPERACIÓN", theme: theme)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Ve con calma.").font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(theme.ink)
                        Text("Tienes margen, pero hoy no es de exprimirte.")
                            .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 14)
            }
            // Señales
            VStack(alignment: .leading, spacing: 13) {
                Text("Señales de hoy").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(spacing: 0) {
                    signal("HRV", theme.dataRecovery, "+1.4σ", "sobre tu base")
                    divider
                    signal("FC reposo", theme.warning, "+1.2σ", "algo alta")
                    divider
                    signal("Carga", theme.dataRecovery, "1.0", "en zona")
                }
            }
            .padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
            // Trajectory
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tu recuperación · 14 días").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text("↑ 9% vs media").font(StrandFont.captionNumber).foregroundStyle(theme.positiveText)
                }
                Sparkline(values: [62, 60, 66, 63, 68, 65, 71, 67, 74, 70, 78, 75, 82, 84],
                          gradient: Gradient(colors: [theme.dataRecovery, theme.dataRecovery]),
                          lineWidth: 2, showsArea: true, showsHead: true, showsScrub: false)
                    .frame(height: 54)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(theme.hairline).frame(width: 1).padding(.vertical, 2).padding(.horizontal, 14)
    }

    private func signal(_ label: String, _ flag: Color, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9.5, weight: .semibold)).tracking(0.7).textCase(.uppercase)
                .foregroundStyle(theme.inkTertiary)
            HStack(spacing: 5) {
                Circle().fill(flag).frame(width: 8, height: 8)
                Text(value).font(StrandFont.mono(13, weight: .semibold)).foregroundStyle(theme.ink)
            }
            Text(detail).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LowerSectionsPreview: View {
    let theme: InstrumentoTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            // Lo que funciona — levers with dumbbells
            VStack(alignment: .leading, spacing: 0) {
                Text("Lo que funciona en ti").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                leverRow("Alcohol", "FC en reposo · 62 noches", "↑ 8.3 lpm", true,
                         meanWith: 48, meanWithout: 56, hue: theme.dataHeart)
                leverRow("Cena tardía", "Sueño · 59 noches", "↓ 65 min", false,
                         meanWith: 7.9, meanWithout: 6.8, hue: theme.dataSleep)
            }
            // Hallazgos — findings with glyphs
            VStack(alignment: .leading, spacing: 0) {
                Text("Hallazgos").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                findingRow(InsightGlyph(kind: .relation, primary: theme.dataRecovery, secondary: theme.dataHrv, theme: theme),
                           "Relación entre métricas", "HRV y Recuperación van juntas")
                findingRow(InsightGlyph(kind: .trend, values: [40, 44, 46, 49, 52, 55, 58, 61, 64, 67, 70],
                                        primary: theme.dataRecovery, secondary: theme.dataHrv, theme: theme),
                           "Tendencia", "Tu recuperación viene subiendo")
                findingRow(InsightGlyph(kind: .anomaly, primary: theme.dataHeart, secondary: theme.dataHrv, theme: theme),
                           "Anomalía · anoche", "Tu FC en reposo amaneció alta")
            }
            // Anota — progress segments
            VStack(alignment: .leading, spacing: 10) {
                Text("Anota tu día").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(spacing: 13) {
                    Image(systemName: "square.and.pencil").font(.system(size: 20)).foregroundStyle(theme.inkSecondary)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("2 de 5 anotados hoy").font(StrandFont.headline).foregroundStyle(theme.ink)
                        HStack(spacing: 5) {
                            ForEach(0..<5, id: \.self) { i in
                                Capsule().fill(i < 2 ? theme.ink : theme.hairline).frame(width: 22, height: 5)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
                }
                .padding(16)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.hairlineStrong, lineWidth: 1))
            }
        }
    }

    private func leverRow(_ name: String, _ sub: String, _ badge: String, _ good: Bool,
                          meanWith: Double, meanWithout: Double, hue: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(StrandFont.headline).foregroundStyle(theme.ink)
                    Text(sub).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
                Spacer()
                Text(badge).font(StrandFont.number(16)).monospacedDigit()
                    .foregroundStyle(good ? theme.positiveText : theme.critical)
                Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary).padding(.leading, 10)
            }
            BehaviorDumbbell(meanWith: meanWith, meanWithout: meanWithout,
                             withText: meanWith == meanWith.rounded() ? "\(Int(meanWith))" : String(format: "%.1f", meanWith),
                             withoutText: meanWithout == meanWithout.rounded() ? "\(Int(meanWithout))" : String(format: "%.1f", meanWithout),
                             withIsBetter: good, hue: hue, theme: theme)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
    }

    private func findingRow<G: View>(_ glyph: G, _ kind: String, _ title: String) -> some View {
        HStack(spacing: 13) {
            glyph
            VStack(alignment: .leading, spacing: 3) {
                Text(kind).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(title).font(StrandFont.headline).foregroundStyle(theme.ink)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
    }
}
#endif
