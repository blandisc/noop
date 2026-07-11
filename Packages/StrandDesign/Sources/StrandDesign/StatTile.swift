import SwiftUI

// MARK: - StatTile
//
// Compact stat tile for «Instrumento diurno»: overline label, value (+ unit),
// optional sparkline, optional caption. Dumb component: strings arrive pre-localized.

/// A compact stat tile with an optional inline sparkline.
public struct StatTile: View {
    private let label: String
    private let value: String
    private let unit: String?
    private let labelColor: Color?
    private let valueColor: Color?
    private let spark: [Double]?
    private let sparkColor: Color?
    private let caption: String?
    private let theme: InstrumentoTheme

    public init(
        label: String,
        value: String,
        unit: String? = nil,
        labelColor: Color? = nil,
        valueColor: Color? = nil,
        spark: [Double]? = nil,
        sparkColor: Color? = nil,
        caption: String? = nil,
        theme: InstrumentoTheme
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.labelColor = labelColor
        self.valueColor = valueColor
        self.spark = spark
        self.sparkColor = sparkColor
        self.caption = caption
        self.theme = theme
    }

    public var body: some View {
        let resolvedLabel = labelColor ?? theme.inkTertiary
        let resolvedValue = valueColor ?? theme.ink
        let lineColor = sparkColor ?? resolvedValue

        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(InstrumentoType.grotesk(10, weight: .semibold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(resolvedLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(InstrumentoType.groteskNumber(21, weight: .bold))
                    .foregroundStyle(resolvedValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary)
                }
            }

            if let spark, !spark.isEmpty {
                Sparkline(
                    values: spark,
                    gradient: Gradient(colors: [lineColor, lineColor]),
                    lineWidth: 1.5,
                    showsArea: false,
                    showsHead: false,
                    showsScrub: false
                )
                .frame(height: 16)
            }

            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.inkTertiary)
                    .lineLimit(2)
            }
        }
        .frame(minWidth: 0, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
private let statTilePreviewSpark: [Double] = [48, 50, 49, 53, 52, 55, 51, 54, 56, 52, 53, 57, 55, 54, 56, 58]

#Preview("StatTile") {
    let t = InstrumentoTheme.base
    HStack(alignment: .top, spacing: 16) {
        StatTile(
            label: "VFC",
            value: "52",
            unit: "ms",
            valueColor: t.dataHrv,
            spark: statTilePreviewSpark,
            sparkColor: t.dataHrv,
            caption: "vs 48 ayer",
            theme: t
        )
        StatTile(
            label: "Repos",
            value: "8.4",
            unit: "h",
            theme: t
        )
        StatTile(
            label: "FC reposo",
            value: "54",
            unit: "bpm",
            valueColor: t.dataHeart,
            spark: statTilePreviewSpark,
            caption: "estable",
            theme: t
        )
    }
    .padding(20)
    .background(t.paper)
}
#endif
