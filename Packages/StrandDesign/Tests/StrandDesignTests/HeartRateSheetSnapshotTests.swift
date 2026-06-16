#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import StrandDesign

/// Dev render harness (NOT a CI assertion) for the "Frecuencia cardíaca" detail sheet that the new
/// Key-Metrics row will open. Renders the THREE candidate variants side by side so the owner can
/// pick: (1) chart + one context line, (2) chart only, (3) chart + HR zones. The chart is the real
/// 24h HR curve, rendered a bit taller than the standard 220 ("un poquito más grande").
/// Run: GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
///      swift test --filter HeartRateSheetSnapshotTests
final class HeartRateSheetSnapshotTests: XCTestCase {

    // A realistic full-day HR curve (00:00 → 19:00) at 5-minute buckets: ~52 asleep, a morning rise,
    // a daytime band, an evening workout spike to ~150, then cooldown. Deterministic (no random).
    private func sampleHRPoints() -> [TrendPoint] {
        let control: [(Double, Double)] = [
            (0, 52), (3, 50), (6, 53), (6.6, 59), (8, 72), (10, 78), (12, 83),
            (13, 75), (15, 80), (17, 77), (17.6, 100), (18.1, 148), (18.4, 150), (18.8, 126), (19, 92),
        ]
        func bpm(atHour h: Double) -> Double {
            if h <= control.first!.0 { return control.first!.1 }
            if h >= control.last!.0 { return control.last!.1 }
            for k in 1..<control.count {
                let (h0, v0) = control[k - 1], (h1, v1) = control[k]
                if h <= h1 { let t = (h - h0) / (h1 - h0); return v0 + (v1 - v0) * t }
            }
            return control.last!.1
        }
        let midnight = Date(timeIntervalSince1970: 1_718_000_000) // fixed (no Date.now in tests)
        let buckets = 19 * 12
        return (0...buckets).map { i in
            let h = Double(i) / 12.0
            let wobble = sin(Double(i) * 0.7) * 2.0 + sin(Double(i) * 0.23) * 1.3
            return TrendPoint(date: midnight.addingTimeInterval(h * 3600),
                              value: (bpm(atHour: h) + wobble).rounded())
        }
    }

    @MainActor
    func test_renderHeartRateSheetVariants() throws {
        let pts = sampleHRPoints()
        let v = pts.map(\.value)
        let lo = v.min()!, hi = v.max()!, span = hi - lo
        let avg = Int((v.reduce(0, +) / Double(v.count)).rounded())
        let last = Int(v.last!.rounded())
        let range = (lo - span * 0.12)...(hi + span * 0.12)

        let timeFmt = DateFormatter(); timeFmt.dateFormat = "ha"

        // The shared, slightly-taller HR chart card (260 vs the default 220).
        func chartCard() -> some View {
            ChartCard(
                title: "Pulsaciones por minuto",
                subtitle: "Promedio de 5 min · desde medianoche",
                trailing: "\(last) bpm",
                height: 260
            ) {
                TrendChart(
                    points: pts,
                    gradient: Gradient(colors: [StrandPalette.metricRose.opacity(0.55), StrandPalette.metricRose]),
                    valueRange: range,
                    showsArea: true,
                    height: 260,
                    showsHover: false,
                    valueFormat: { "\(Int($0.rounded())) bpm" },
                    dateFormat: { timeFmt.string(from: $0).lowercased() }
                )
            } footer: {
                ChartFooter([("Mín", "\(Int(lo))"), ("Prom", "\(avg)"), ("Máx", "\(Int(hi))")])
            }
        }

        // The sheet header: name on the left, big value + unit on the right (mirrors MetricInfoSheet).
        let header = HStack(alignment: .firstTextBaseline) {
            Text("Frecuencia cardíaca").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(avg)").font(StrandFont.number(28)).foregroundStyle(StrandPalette.metricRose)
                Text("bpm").font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
            }
        }

        // HR reference zones (variant 3 only).
        let zones: [(String, String, Color, Bool)] = [
            ("Reposo", "< 60", StrandPalette.accent, false),
            ("Ligera", "60 – 100", StrandPalette.metricCyan, true),
            ("Moderada", "100 – 140", StrandPalette.statusWarning, false),
            ("Alta", "> 140", StrandPalette.metricRose, false),
        ]
        let zonesTable = VStack(spacing: 0) {
            ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                HStack(spacing: 10) {
                    Circle().fill(z.3 ? z.2 : z.2.opacity(0.35)).frame(width: 8, height: 8).padding(.leading, 14)
                    Text(z.0).font(StrandFont.subhead)
                        .foregroundStyle(z.3 ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                    Spacer()
                    Text(z.1).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textTertiary).padding(.trailing, 14)
                }
                .padding(.vertical, 11)
                if i < zones.count - 1 { Divider().overlay(StrandPalette.hairline).padding(.leading, 36) }
            }
        }
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        // --- The three variants, each as a faithful sheet column ---
        func column<C: View>(@ViewBuilder _ content: () -> C) -> some View {
            VStack(alignment: .leading, spacing: 22, content: content)
                .padding(20)
                .frame(width: 380, alignment: .leading)
                .background(StrandPalette.surfaceBase)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }

        let variant1 = column {
            header
            Text("Tu frecuencia cardíaca a lo largo del día, promediada en intervalos de 5 minutos.")
                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            chartCard()
        }
        let variant2 = column {
            header
            chartCard()
        }
        let variant3 = column {
            header
            chartCard()
            zonesTable
        }

        func labeled<C: View>(_ title: String, @ViewBuilder _ col: () -> C) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                col()
            }
        }

        let board = HStack(alignment: .top, spacing: 24) {
            labeled("1 · Con 1 línea de contexto") { variant1 }
            labeled("2 · Solo la gráfica") { variant2 }
            labeled("3 · Con zonas de FC") { variant3 }
        }
        .padding(32)
        .background(Color.black)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: board)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-hr-sheet/variants.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }

    /// The "Métricas clave" list WITH the new "Frecuencia cardíaca" row inserted next to "Frecuencia
    /// en reposo" — the only visually-new on-screen element (the sheet is already approved). Renders
    /// both the with-data state (avg bpm + day-curve sparkline) and the no-data placeholder ("—").
    @MainActor
    func test_renderKeyMetricsWithHeartRateRow() throws {
        // The new row's sparkline IS today's HR curve, subsampled to the 50pt slot.
        let day = sampleHRPoints().map(\.value)
        let step = max(1, day.count / 32)
        let hrSpark = Swift.stride(from: 0, to: day.count, by: step).map { day[$0] }

        func row(_ label: String, _ value: String, unit: String? = nil, color: Color,
                 spark: [Double], sparkColor: Color, placeholder: Bool = false) -> some View {
            MetricRow(label: LocalizedStringKey(label), value: value, unit: unit, valueColor: color,
                      sparkline: placeholder ? nil : spark, sparkColor: sparkColor, isPlaceholder: placeholder)
        }
        func sep() -> some View { Divider().overlay(StrandPalette.hairline) }

        func section(noHR: Bool) -> some View {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                SectionHeader("Métricas clave", overline: "Hoy", trailing: "tendencia 14 días")
                VStack(spacing: 0) {
                    row("Esfuerzo del día", "8.5", color: StrandPalette.strainColor(8.5),
                        spark: [6,9,7,11,8,10,8.5,9,7,8,10,9,11,8.5], sparkColor: StrandPalette.strain066)
                    sep()
                    row("Sueño", "7h 20m", color: StrandPalette.textPrimary,
                        spark: [380,420,400,460,440,410,440,430,420,450,440,400,430,440], sparkColor: StrandPalette.metricPurple)
                    sep()
                    row("HRV", "62", unit: "ms", color: StrandPalette.metricPurple,
                        spark: [58,55,60,62,59,64,62,61,63,60,62,65,62,62], sparkColor: StrandPalette.metricPurple)
                    sep()
                    // NUEVO — Frecuencia cardíaca (curva del día), justo encima de Frecuencia en reposo.
                    if noHR {
                        row("Frecuencia cardíaca", "—", color: StrandPalette.metricRose,
                            spark: [], sparkColor: StrandPalette.metricRose, placeholder: true)
                    } else {
                        row("Frecuencia cardíaca", "68", unit: "bpm", color: StrandPalette.metricRose,
                            spark: hrSpark, sparkColor: StrandPalette.metricRose)
                    }
                    sep()
                    row("Frecuencia en reposo", "54", unit: "bpm", color: StrandPalette.metricRose,
                        spark: [56,55,54,55,53,54,54,55,54,53,54,55,54,54], sparkColor: StrandPalette.metricRose)
                    sep()
                    row("Oxígeno en sangre", "97", unit: "%", color: StrandPalette.metricCyan,
                        spark: [96,97,97,96,98,97,97,96,97,97,98,97,97,97], sparkColor: StrandPalette.metricCyan)
                    sep()
                    row("Pasos", "8,432", color: StrandPalette.textPrimary,
                        spark: [5000,7000,6500,9000,8000,7500,8432,6000,7000,8000,9000,7500,8200,8432], sparkColor: StrandPalette.metricCyan)
                }
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.vertical, 20)
            .frame(width: 390, alignment: .leading)
            .background(StrandPalette.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }

        func labeled<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                c()
            }
        }

        let board = HStack(alignment: .top, spacing: 28) {
            labeled("Con datos (renglón nuevo resaltado por el par de pulso)") { section(noHR: false) }
            labeled("Renglón sin lecturas del día") { section(noHR: true) }
        }
        .padding(32)
        .background(Color.black)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: board)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced no image"); return
        }
        let url = URL(fileURLWithPath: "/tmp/noop-hr-sheet/key-metrics.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("WROTE \(url.path) — \(image.size)")
    }
}
#endif
