import SwiftUI

// MARK: - TarjetaSesion
//
// Data-first session card for «Instrumento diurno». Two body variants share one
// container and header:
//
//   · Variant A (metrics non-empty): a horizontal metric grid (value + unit + label).
//   · Variant B (barValue non-nil): a big number with an optional progress bar under it.
//
// Copy arrives pre-localized. The package does not load a string catalog.

/// A data-first session card: metric-grid (A) or big-number-with-bar (B).
public struct TarjetaSesion: View {

    /// One column in the variant-A metric grid.
    public struct Metric {
        public var value: String
        public var unit: String?
        public var label: String
        public var color: Color?
        public var labelColor: Color?

        public init(
            value: String,
            unit: String? = nil,
            label: String,
            color: Color? = nil,
            labelColor: Color? = nil
        ) {
            self.value = value
            self.unit = unit
            self.label = label
            self.color = color
            self.labelColor = labelColor
        }
    }

    private let titulo: String
    private let meta: String?
    private let chip: LocalizedStringKey?
    private let metrics: [Metric]
    private let barValue: String?
    private let barValueTail: String?
    private let barColor: Color?
    private let barPct: Double
    private let barOpacity: Double
    private let barNota: String?
    private let theme: InstrumentoTheme

    /// Variant A: metric grid. Pass a non-empty `metrics` array.
    public init(
        titulo: String,
        meta: String? = nil,
        chip: LocalizedStringKey? = nil,
        metrics: [Metric],
        theme: InstrumentoTheme
    ) {
        self.titulo = titulo
        self.meta = meta
        self.chip = chip
        self.metrics = metrics
        self.barValue = nil
        self.barValueTail = nil
        self.barColor = nil
        self.barPct = 0
        self.barOpacity = 1
        self.barNota = nil
        self.theme = theme
    }

    /// Variant B: big number with optional filled progress bar.
    public init(
        titulo: String,
        meta: String? = nil,
        chip: LocalizedStringKey? = nil,
        barValue: String,
        barValueTail: String? = nil,
        barColor: Color,
        barPct: Double,
        barOpacity: Double = 1,
        barNota: String? = nil,
        theme: InstrumentoTheme
    ) {
        self.titulo = titulo
        self.meta = meta
        self.chip = chip
        self.metrics = []
        self.barValue = barValue
        self.barValueTail = barValueTail
        self.barColor = barColor
        self.barPct = barPct
        self.barOpacity = barOpacity
        self.barNota = barNota
        self.theme = theme
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            bodyContent
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(titulo)
                .font(InstrumentoType.grotesk(16, weight: .semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            if let meta {
                Text(meta)
                    .font(InstrumentoType.grotesk(11, weight: .regular))
                    .foregroundStyle(theme.inkTertiary)
                    .lineLimit(1)
            }
            if let chip {
                ChipTendencia(chip, theme: theme)
            }
        }
    }

    // MARK: Body

    @ViewBuilder
    private var bodyContent: some View {
        if !metrics.isEmpty {
            metricsBody
        } else if let barValue, let barColor {
            barBody(value: barValue, color: barColor)
        }
    }

    private var metricsBody: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(metric.value)
                            .font(InstrumentoType.groteskNumber(18, weight: .bold))
                            .foregroundStyle(metric.color ?? theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let unit = metric.unit {
                            Text(unit)
                                .font(StrandFont.scaled(11))
                                .foregroundStyle(theme.inkTertiary)
                        }
                    }
                    Text(metric.label)
                        .font(InstrumentoType.grotesk(9, weight: .semibold))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(metric.labelColor ?? theme.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func barBody(value: String, color: Color) -> some View {
        let pct = min(max(barPct, 0), 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(InstrumentoType.groteskNumber(34, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let barValueTail {
                    Text(barValueTail)
                        .font(StrandFont.scaled(12))
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(theme.rangeBand)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.opacity(barOpacity))
                        .frame(width: geo.size.width * pct)
                        .recGrow()
                }
            }
            .frame(height: 6)
            if let barNota {
                Text(barNota)
                    .font(StrandFont.scaled(11))
                    .foregroundStyle(theme.inkTertiary)
            }
        }
    }
}

#if DEBUG
#Preview("TarjetaSesion") {
    let t = InstrumentoTheme.base
    VStack(spacing: 14) {
        TarjetaSesion(
            titulo: "Fuerza · empujes",
            meta: "42 min",
            metrics: [
                .init(value: "12", unit: "sets", label: "Volumen"),
                .init(value: "8.4", unit: "t", label: "Carga", color: t.dataStrain),
                .init(value: "142", unit: "bpm", label: "FC max", color: t.dataHeart)
            ],
            theme: t
        )
        TarjetaSesion(
            titulo: "Recuperacion",
            chip: "tendencia",
            barValue: "78",
            barValueTail: "/100",
            barColor: t.dataRecovery,
            barPct: 0.78,
            barNota: "Dentro de tu base de 30 dias",
            theme: t
        )
        TarjetaSesion(
            titulo: "Esfuerzo",
            meta: "hoy",
            chip: "en vivo",
            barValue: "14.2",
            barColor: t.dataStrain,
            barPct: 0.71,
            barOpacity: 0.9,
            theme: t
        )
    }
    .padding(20)
    .background(t.paper)
}
#endif
