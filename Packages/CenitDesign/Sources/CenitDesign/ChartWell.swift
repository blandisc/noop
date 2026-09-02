import SwiftUI

// MARK: - ChartWell — the shared loading / empty well under every «Instrumento» chart
//
// A quiet rounded surface that stands in for a chart while it loads (a spinner) or when there's
// nothing to draw (an icon + centered copy). Before FER-757 each detail screen re-implemented these
// as private `loadingWell` / `emptyWell` helpers; this is the single canonical version.
//
// It's a configured factory, not a View: build one with the screen's fixed traits (icon, corner
// radius, border), then ask it for `.loading(height:)` / `.empty(text:)` wells. `theme` is kept for
// call-site compatibility but ignored for painting — colors come from `LiquidColor` (FER-316).
// The traits are parameterized because the screens genuinely differ on purpose: most wells use a
// 12 pt radius and the chart glyph; Sleep uses its moon at the card radius; Compare adds a hairline
// border. Zero visual change from the private copies is the contract.

public struct ChartWell {
    let icon: String
    let cornerRadius: CGFloat
    let bordered: Bool

    /// - Parameters:
    ///   - theme: ignored for painting (LiquidColor). Kept for call-site compatibility (FER-316).
    ///   - icon: SF Symbol shown in the empty well. Default is the generic chart glyph.
    ///   - cornerRadius: the well's rounding. Most wells use 12; card-shaped ones use
    ///     `CenitMetrics.cardRadius`.
    ///   - bordered: true adds a hairline stroke + horizontal breathing room (CompareView's well).
    public init(_ theme: InstrumentoTheme = .base,
                icon: String = "chart.xyaxis.line",
                cornerRadius: CGFloat = 12,
                bordered: Bool = false) {
        _ = theme
        self.icon = icon
        self.cornerRadius = cornerRadius
        self.bordered = bordered
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// The loading well: a faint surface at the chart's height with a quiet spinner.
    public func loading(height: CGFloat) -> some View {
        shape
            .fill(LiquidColor.papelTarjeta)
            .frame(height: height)
            .overlay { ProgressView().tint(LiquidColor.tinta500) }
    }

    /// The empty well: the configured icon over centered copy, on a faint surface.
    public func empty(text: LocalizedStringKey) -> some View {
        empty(icon: icon, text: text)
    }

    /// The empty well with a per-call icon (MetricInfoSheet varies it per chart).
    public func empty(icon: String, text: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(LiquidColor.tinta500)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(LiquidColor.tinta700)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, bordered ? 16 : 0)
        .background(LiquidColor.papelTarjeta, in: shape)
        .overlay {
            if bordered {
                shape.strokeBorder(LiquidColor.tinta7, lineWidth: 1)
            }
        }
    }

    /// The note well: a single quiet line, leading-aligned, no icon (MetricLevelsExplorer's
    /// "no readings in this range").
    public func note(text: LocalizedStringKey) -> some View {
        Text(text)
            .font(StrandFont.footnote)
            .foregroundStyle(LiquidColor.tinta500)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(LiquidColor.papelTarjeta, in: shape)
    }

    // MARK: - Área bajo una línea de tendencia (auditoría jul-2026, H4)

    /// El relleno vertical bajo una línea de tendencia: del tono a media opacidad (`CenitOpacity.muted`)
    /// arriba hacia el tono pleno abajo. Fuente ÚNICA — antes cada pantalla escribía
    /// `Gradient(colors: [hue.opacity(0.5), hue])` con la opacidad variando por archivo (0.5/0.55).
    /// Estandariza en `muted` (0.60); el salto desde 0.5/0.55 es imperceptible en un relleno de área.
    public static func fillGradient(_ hue: Color) -> Gradient {
        Gradient(colors: [hue.opacity(CenitOpacity.muted), hue])
    }
}

// MARK: - Preview

#Preview("ChartWell") {
    ScrollView {
        VStack(spacing: 16) {
            ChartWell().loading(height: 160)
            ChartWell().empty(text: "Not enough days in this range to draw a trend.")
            ChartWell(icon: "moon.zzz", cornerRadius: CenitMetrics.cardRadius)
                .empty(text: "Not enough nights yet to draw a trend.")
            ChartWell(icon: "arrow.left.arrow.right",
                      cornerRadius: CenitMetrics.cardRadius, bordered: true)
                .empty(text: "Compare needs at least two metrics with history.")
            ChartWell().note(text: "No readings in this range.")
        }
        .padding(20)
    }
    .background(LiquidColor.fondoAlto)
}
