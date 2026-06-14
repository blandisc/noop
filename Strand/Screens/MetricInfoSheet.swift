import SwiftUI
import StrandDesign

// MARK: - MetricInfo

/// Data model for the "tap a metric to learn more" bottom sheet.
/// Each metric defines its bands (fixed ranges + colors) and which band is active
/// for the user's current value.
struct MetricInfo: Identifiable {
    let id: String
    let name: LocalizedStringKey
    let headline: LocalizedStringKey
    let displayValue: String
    let unit: String?
    let currentColor: Color
    let bands: [Band]
    let note: LocalizedStringKey?

    struct Band {
        let label: LocalizedStringKey
        let range: String
        let color: Color
        var isActive: Bool
    }
}

// MARK: - Static factories

extension MetricInfo {

    static func strain(_ value: Double?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Rest / Light", range: "0 – 7",
                 color: StrandPalette.strain000,
                 isActive: value.map { $0 < 7 } ?? false),
            Band(label: "Moderate", range: "7 – 14",
                 color: StrandPalette.strain033,
                 isActive: value.map { $0 >= 7 && $0 < 14 } ?? false),
            Band(label: "Hard", range: "14 – 18",
                 color: StrandPalette.strain066,
                 isActive: value.map { $0 >= 14 && $0 < 18 } ?? false),
            Band(label: "Extreme", range: "18 – 21",
                 color: StrandPalette.strain100,
                 isActive: value.map { $0 >= 18 } ?? false),
        ]
        return MetricInfo(
            id: "strain",
            name: "Day Strain",
            headline: "Cardiovascular load scored 0–21. Each second of the day your heart rate is recorded, it's assigned to a zone (1–5). Higher zones carry more weight. The total is compressed logarithmically so 21 represents a theoretical maximum — a full day at peak intensity.",
            displayValue: value.map { String(format: "%.1f", $0) } ?? "—",
            unit: nil,
            currentColor: value.map { StrandPalette.strainColor($0) } ?? StrandPalette.textSecondary,
            bands: bands,
            note: nil
        )
    }

    static func sleep(_ totalMinutes: Int?) -> MetricInfo {
        let hours = totalMinutes.map { Double($0) / 60.0 }
        let bands: [Band] = [
            Band(label: "Short", range: "< 6 h",
                 color: StrandPalette.metricRose,
                 isActive: hours.map { $0 < 6 } ?? false),
            Band(label: "Adequate", range: "6 – 7 h",
                 color: StrandPalette.statusWarning,
                 isActive: hours.map { $0 >= 6 && $0 < 7 } ?? false),
            Band(label: "Optimal", range: "7 – 9 h",
                 color: StrandPalette.accent,
                 isActive: hours.map { $0 >= 7 && $0 <= 9 } ?? false),
            Band(label: "Extended", range: "> 9 h",
                 color: StrandPalette.textSecondary,
                 isActive: hours.map { $0 > 9 } ?? false),
        ]
        let display: String
        if let m = totalMinutes {
            let h = m / 60, min = m % 60
            display = min > 0 ? "\(h)h \(min)m" : "\(h)h"
        } else {
            display = "—"
        }
        return MetricInfo(
            id: "sleep",
            name: "Sleep",
            headline: "Total time asleep last night, estimated from movement and heart rate. Sleep contributes ~15% of your recovery score and feeds the strain-to-load balance (ACWR).",
            displayValue: display,
            unit: nil,
            currentColor: hours.map { h -> Color in
                switch h {
                case ..<6:   return StrandPalette.metricRose
                case ..<7:   return StrandPalette.statusWarning
                case ...9:   return StrandPalette.accent
                default:     return StrandPalette.textSecondary
                }
            } ?? StrandPalette.textSecondary,
            bands: bands,
            note: nil
        )
    }

    static func hrv(_ value: Double?) -> MetricInfo {
        MetricInfo(
            id: "hrv",
            name: "HRV",
            headline: "Heart Rate Variability — the millisecond fluctuation between heartbeats. Higher isn't always better: what matters is how your HRV compares to your own baseline. A dip from your norm signals stress, fatigue, or recovery debt. NOOP weights HRV at ~60% of your recovery score.",
            displayValue: value.map { "\(Int($0.rounded()))" } ?? "—",
            unit: "ms",
            currentColor: StrandPalette.metricPurple,
            bands: [],
            note: "HRV is personal. There are no universal good/bad thresholds — only your trend over time."
        )
    }

    static func restingHR(_ value: Int?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Athlete", range: "< 50 bpm",
                 color: StrandPalette.accent,
                 isActive: value.map { $0 < 50 } ?? false),
            Band(label: "Excellent", range: "50 – 60 bpm",
                 color: StrandPalette.accent,
                 isActive: value.map { $0 >= 50 && $0 < 60 } ?? false),
            Band(label: "Normal", range: "60 – 80 bpm",
                 color: StrandPalette.textSecondary,
                 isActive: value.map { $0 >= 60 && $0 < 80 } ?? false),
            Band(label: "Elevated", range: "> 80 bpm",
                 color: StrandPalette.statusWarning,
                 isActive: value.map { $0 >= 80 } ?? false),
        ]
        return MetricInfo(
            id: "rhr",
            name: "Resting HR",
            headline: "Your lowest heart rate during sleep — how hard your heart works at complete rest. Lower generally means a stronger, more efficient cardiovascular system. NOOP uses it as ~20% of your recovery score; a rise from your norm signals fatigue or illness.",
            displayValue: value.map { "\($0)" } ?? "—",
            unit: "bpm",
            currentColor: StrandPalette.metricRose,
            bands: bands,
            note: nil
        )
    }

    static func spo2(_ value: Double?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Normal", range: "95 – 100%",
                 color: StrandPalette.metricCyan,
                 isActive: value.map { $0 >= 95 } ?? false),
            Band(label: "Borderline", range: "90 – 94%",
                 color: StrandPalette.statusWarning,
                 isActive: value.map { $0 >= 90 && $0 < 95 } ?? false),
            Band(label: "Low", range: "< 90%",
                 color: StrandPalette.metricRose,
                 isActive: value.map { $0 < 90 } ?? false),
        ]
        return MetricInfo(
            id: "spo2",
            name: "Blood Oxygen",
            headline: "Percentage of haemoglobin carrying oxygen in your blood. Healthy adults typically stay above 95%. A drop can indicate altitude effects, sleep apnea, or respiratory illness.",
            displayValue: value.map { String(format: "%.0f", $0) } ?? "—",
            unit: "%",
            currentColor: StrandPalette.metricCyan,
            bands: bands,
            note: "Wrist-based sensors have lower accuracy than medical pulse oximeters — treat values as a trend, not a clinical reading."
        )
    }

    static func steps(_ value: Int?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Sedentary", range: "< 5 000",
                 color: StrandPalette.textSecondary,
                 isActive: value.map { $0 < 5_000 } ?? false),
            Band(label: "Light", range: "5 000 – 8 000",
                 color: StrandPalette.metricCyan.opacity(0.7),
                 isActive: value.map { $0 >= 5_000 && $0 < 8_000 } ?? false),
            Band(label: "Active", range: "8 000 – 10 000",
                 color: StrandPalette.metricCyan,
                 isActive: value.map { $0 >= 8_000 && $0 < 10_000 } ?? false),
            Band(label: "Very active", range: "> 10 000",
                 color: StrandPalette.accent,
                 isActive: value.map { $0 >= 10_000 } ?? false),
        ]
        return MetricInfo(
            id: "steps",
            name: "Steps",
            headline: "Daily step count. Consistent activity — even a 30-minute walk — supports cardiovascular health, mood, and recovery quality.",
            displayValue: value.map { v in
                let f = NumberFormatter(); f.numberStyle = .decimal
                return f.string(from: NSNumber(value: v)) ?? "\(v)"
            } ?? "—",
            unit: nil,
            currentColor: StrandPalette.metricCyan,
            bands: bands,
            note: "Steps come from Apple Health and are not recorded by the WHOOP strap."
        )
    }
}

// MARK: - MetricInfoSheet

struct MetricInfoSheet: View {
    let info: MetricInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                Text(info.headline)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !info.bands.isEmpty { bandsTable }
                if let note = info.note {
                    Text(note)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(StrandPalette.surfaceBase)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(StrandPalette.surfaceBase)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(info.name)
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(info.displayValue)
                    .font(StrandFont.number(28))
                    .foregroundStyle(info.currentColor)
                if let unit = info.unit {
                    Text(unit)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    private var bandsTable: some View {
        VStack(spacing: 0) {
            ForEach(Array(info.bands.enumerated()), id: \.offset) { i, band in
                bandRow(band)
                if i < info.bands.count - 1 {
                    Divider().overlay(StrandPalette.hairline).padding(.leading, 36)
                }
            }
        }
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func bandRow(_ band: MetricInfo.Band) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(band.isActive ? band.color : band.color.opacity(0.35))
                .frame(width: 8, height: 8)
                .padding(.leading, 14)
            Text(band.label)
                .font(StrandFont.subhead)
                .foregroundStyle(band.isActive ? StrandPalette.textPrimary : StrandPalette.textSecondary)
            Spacer()
            Text(band.range)
                .font(StrandFont.captionNumber)
                .foregroundStyle(band.isActive ? band.color : StrandPalette.textTertiary)
            if band.isActive {
                Image(systemName: "arrowshape.left.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(band.color)
                    .padding(.trailing, 14)
            } else {
                Spacer().frame(width: 22)
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(band.isActive ? band.color.opacity(0.07) : Color.clear)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("MetricInfoSheet — Strain") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .strain(11.5))
    }
    .preferredColorScheme(.dark)
}

#Preview("MetricInfoSheet — HRV") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .hrv(66))
    }
    .preferredColorScheme(.dark)
}

#Preview("MetricInfoSheet — SpO₂") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .spo2(97))
    }
    .preferredColorScheme(.dark)
}
#endif
