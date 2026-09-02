import SwiftUI

// MARK: - Metric row (dense list)
//
// The list-style metric row from the Today redesign: `label (+ optional flag) · inline sparkline ·
// right-aligned value + unit`. The Apple/Whoop "Key Metrics" pattern — denser than a `StatTile`
// grid, so six metrics read as one calm column instead of six boxes. Values are tabular and pinned
// to a fixed-width column so the decimal points line up. Reuses `Sparkline`. Tokens-only.

public struct MetricRow: View {
    let label: LocalizedStringKey
    var flag: LocalizedStringKey?
    var flagColor: Color
    let value: String
    var unit: String?
    var valueColor: Color
    /// Label / unit ink. Default to the legacy `StrandPalette` so existing callers are unchanged;
    /// «Instrumento diurno» screens pass `theme.inkSecondary` / `theme.inkTertiary`. (FER-135)
    var labelColor: Color
    var unitColor: Color
    var sparkline: [Double]?
    var sparkColor: Color
    /// Optional reference band (p25–p75 typical range) drawn faintly behind the sparkline; `nil` = none.
    var referenceBand: ClosedRange<Double>?
    var bandColor: Color
    /// When there's no data yet: shows a faint skeleton in the sparkline slot (honest empty state).
    var isPlaceholder: Bool
    /// When `true`, draws a faint trailing `chevron.right` so the row reads as tappable (opens a
    /// detail sheet). The whole row stays the tap target — the chevron is only the affordance. (FER-161)
    var showsChevron: Bool
    /// Chevron ink — pass the by-hour theme's faint ink (`theme.inkTertiary`) so it recolors with
    /// the rest of the row. Ignored unless `showsChevron`.
    var chevronColor: Color

    public init(label: LocalizedStringKey, value: String, unit: String? = nil,
                valueColor: Color = InstrumentoTheme.base.ink,
                labelColor: Color = InstrumentoTheme.base.inkSecondary,
                unitColor: Color = InstrumentoTheme.base.inkTertiary,
                flag: LocalizedStringKey? = nil, flagColor: Color = StrandPalette.statusWarning,
                sparkline: [Double]? = nil, sparkColor: Color = InstrumentoTheme.base.inkSecondary,
                referenceBand: ClosedRange<Double>? = nil,
                bandColor: Color = InstrumentoTheme.base.hairlineStrong,
                isPlaceholder: Bool = false,
                showsChevron: Bool = false,
                chevronColor: Color = InstrumentoTheme.base.inkTertiary) {
        self.label = label
        self.value = value
        self.unit = unit
        self.valueColor = valueColor
        self.labelColor = labelColor
        self.unitColor = unitColor
        self.flag = flag
        self.flagColor = flagColor
        self.sparkline = sparkline
        self.sparkColor = sparkColor
        self.referenceBand = referenceBand
        self.bandColor = bandColor
        self.isPlaceholder = isPlaceholder
        self.showsChevron = showsChevron
        self.chevronColor = chevronColor
    }

    public var body: some View {
        HStack(spacing: 12) {
            // La etiqueta nunca se recorta ni se encoge: cuando cabe va en una línea junto a su chip;
            // cuando una etiqueta larga lleva chip (p. ej. "Oxígeno en sangre · APPLE SALUD") el chip
            // baja a una segunda línea, todo a tamaño completo.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Text(label).font(StrandFont.body).foregroundStyle(labelColor).lineLimit(1)
                    if let flag { InlineFlagChip(flag, color: flagColor) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(StrandFont.body).foregroundStyle(labelColor)
                        .fixedSize(horizontal: false, vertical: true)
                    if let flag { InlineFlagChip(flag, color: flagColor) }
                }
            }
            Spacer(minLength: 8)
            ZStack {
                if let sparkline, sparkline.count > 1 {
                    Sparkline(values: sparkline,
                              gradient: Gradient(colors: [sparkColor.opacity(0.55), sparkColor]),
                              referenceBand: referenceBand, bandColor: bandColor,
                              lineWidth: 2.0, showsArea: false, showsHead: false, showsScrub: false)
                } else if isPlaceholder {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(InstrumentoTheme.base.ink.opacity(0.06))
                        .frame(height: 8)
                }
            }
            .frame(width: 60, height: 26)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(StrandFont.number(20)).foregroundStyle(valueColor)
                    // VoiceOver reads "—" as "guion" / "dash". When there's no reading yet, say it
                    // plainly instead — the detail still exists. (FER-161)
                    .accessibilityLabel(isPlaceholder ? Text("no reading today") : Text(value))
                if let unit {
                    Text(unit).font(StrandFont.unit).foregroundStyle(unitColor)
                        // Don't append a unit to "sin dato de hoy".
                        .accessibilityHidden(isPlaceholder)
                }
            }
            .lineLimit(1)
            .frame(width: 88, alignment: .trailing)
            if showsChevron {
                // Quiet tappable affordance: its own gap (the HStack's 12pt) keeps it off the number,
                // and `firstTextBaseline` alignment on the row sits it with the value. Decorative — the
                // whole row is the button, so it's hidden from VoiceOver.
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(chevronColor)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity)
        // Read each row as one element: "label, value" (or "label, sin dato de hoy"), keeping any flag.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Inline flag chip (file-private — only MetricRow consumes it)

/// A tiny outlined chip for inline caveats next to a label (e.g. "Low conf" on HRV after a short
/// night). Annotates; doesn't announce.
private struct InlineFlagChip: View {
    let text: LocalizedStringKey
    var color: Color
    init(_ text: LocalizedStringKey, color: Color = StrandPalette.statusWarning) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.system(size: 8.5, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.4), lineWidth: 1))
    }
}

#if DEBUG
#Preview("MetricRow") {
    VStack(spacing: 0) {
        MetricRow(label: "Day Strain", value: "8.5",
                  sparkline: [6, 9, 7, 11, 8, 10, 8.5], sparkColor: StrandPalette.strain066,
                  showsChevron: true)
        Divider().overlay(InstrumentoTheme.base.hairline)
        MetricRow(label: "HRV", value: "41", unit: "ms", valueColor: StrandPalette.metricPurple,
                  flag: "Low conf", sparkline: [58, 55, 52, 49, 46, 43, 41], sparkColor: StrandPalette.statusWarning,
                  showsChevron: true)
        Divider().overlay(InstrumentoTheme.base.hairline)
        // No data: chevron still shows — the detail exists even without a reading today.
        MetricRow(label: "Blood Oxygen", value: "—", isPlaceholder: true, showsChevron: true)
    }
    .padding(.horizontal, 18)
    .frame(width: 340, height: 220)
    .background(InstrumentoTheme.base.paper)
    .preferredColorScheme(.light)
}
#endif
