#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - ShareCardView — la tarjeta compartible del recibo de fuerza
//
// Vivía dentro de ShareReceiptScreen.swift, que FER-990 retiró por inalcanzable. Esta vista NO lo era:
// ReceiptPrinterScreen (la pantalla viva del recibo térmico) la renderiza con ImageRenderer, así que
// sobrevive al borrado en archivo propio, sin un solo cambio de comportamiento.


/// The shareable card, faithful to «Instrumento»: warm paper, the Cénit wordmark, an editorial title,
/// the date, three metrics (plus heart rate / calories when opted in), and a records footer. This exact
/// view is both the on-screen preview and the `ImageRenderer` source.
struct ShareCardView: View {
    static let width: CGFloat = 340
    let theme: InstrumentoTheme
    let summary: StrengthSummary
    let includeHR: Bool
    let includeKcal: Bool
    let includeRecords: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cénit").font(InstrumentoType.grotesk(16, weight: .semibold)).tracking(0.4)
                .foregroundStyle(theme.ink)
            Text(title).font(InstrumentoType.grotesk(24, weight: .bold)).tracking(-0.2)
                .foregroundStyle(theme.ink).padding(.top, 14)
            Text(dateString).font(StrandFont.caption).foregroundStyle(theme.inkTertiary).padding(.top, 3)

            Rectangle().fill(theme.hairline).frame(height: 1).padding(.vertical, 16)

            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { _, m in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.label).groteskOverline(small: true).foregroundStyle(theme.inkTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(m.value).font(InstrumentoType.grotesk(19, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(m.accent ?? theme.ink)
                            if let u = m.unit {
                                Text(u).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                            }
                        }
                    }
                }
            }

            if includeRecords, let pr = summary.prs.first {
                Text("★ \(String(localized: "Record")): \(prText(pr))")
                    .font(StrandFont.subhead).fontWeight(.medium).foregroundStyle(theme.verdict)
                    .padding(.top, 14)
            }
        }
        .padding(LiquidSpace.tarjetaAmplia)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
    }

    private struct Metric { let label: LocalizedStringKey; let value: String; let unit: String?; let accent: Color? }

    private var metrics: [Metric] {
        var out: [Metric] = [
            Metric(label: "Duration", value: durationString, unit: "min", accent: nil),
            Metric(label: "Volume", value: grouped(summary.volumeKg), unit: "kg", accent: nil),
        ]
        if let s = summary.strain {
            out.append(Metric(label: "Effort", value: decimal1(s), unit: nil, accent: theme.dataStrain))
        } else {
            out.append(Metric(label: "Sets", value: "\(summary.setCount)", unit: nil, accent: nil))
        }
        if includeHR, let hr = summary.avgHr {
            out.append(Metric(label: "Avg HR", value: "\(hr)", unit: nil, accent: theme.dataHeart))
        }
        if includeKcal, let k = summary.energyKcal {
            out.append(Metric(label: "Calories", value: "\(Int(k.rounded()))", unit: nil, accent: nil))
        }
        return out
    }

    private var title: String {
        summary.routineName.isEmpty ? String(localized: "Workout") : summary.routineName
    }
    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy · HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(summary.endTs)))
    }
    private var durationString: String { "\(Int((Double(summary.durationS) / 60).rounded()))" }

    private func prText(_ pr: StrengthSummary.PR) -> String {
        if let kg = pr.valueKg { return "\(pr.exercise) \(grouped(kg)) kg" }
        if let r = pr.reps { return "\(pr.exercise) \(r) \(String(localized: "reps"))" }
        return pr.exercise
    }

    private func grouped(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v.rounded()))"
    }
    // COPY-3 (FER-816): one fraction digit in the user's locale (comma in es, dot in en) — not a manual
    // «.»→«,» swap that breaks outside Spanish.
    private func decimal1(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) }
}
#endif
