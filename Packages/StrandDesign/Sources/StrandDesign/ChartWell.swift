import SwiftUI

// MARK: - ChartWell — the shared loading / empty well under every «Instrumento» chart
//
// A quiet rounded surface that stands in for a chart while it loads (a spinner) or when there's
// nothing to draw (an icon + centered copy). Before FER-757 each detail screen re-implemented these
// as private `loadingWell` / `emptyWell` helpers; this is the single canonical version.
//
// It's a configured factory, not a View: build one with the screen's theme (passed EXPLICITLY —
// `InstrumentoTheme` does not propagate through `.sheet`, FER-162) plus the screen's fixed traits
// (icon, corner radius, border), then ask it for `.loading(height:)` / `.empty(text:)` wells.
// The traits are parameterized because the screens genuinely differ on purpose: most wells use a
// 12 pt radius and the chart glyph; Sleep uses its moon at the card radius; Compare adds a hairline
// border. Zero visual change from the private copies is the contract.

public struct ChartWell {
    let theme: InstrumentoTheme
    let icon: String
    let cornerRadius: CGFloat
    let bordered: Bool

    /// - Parameters:
    ///   - theme: the screen's explicit theme (sheets don't inherit it from the presenter).
    ///   - icon: SF Symbol shown in the empty well. Default is the generic chart glyph.
    ///   - cornerRadius: the well's rounding. Most wells use 12; card-shaped ones use
    ///     `CenitMetrics.cardRadius`.
    ///   - bordered: true adds a hairline stroke + horizontal breathing room (CompareView's well).
    public init(_ theme: InstrumentoTheme,
                icon: String = "chart.xyaxis.line",
                cornerRadius: CGFloat = 12,
                bordered: Bool = false) {
        self.theme = theme
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
            .fill(theme.surface)
            .frame(height: height)
            .overlay { ProgressView().tint(theme.inkTertiary) }
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
                .foregroundStyle(theme.inkTertiary)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, bordered ? 16 : 0)
        .background(theme.surface, in: shape)
        .overlay {
            if bordered {
                shape.strokeBorder(theme.hairline, lineWidth: 1)
            }
        }
    }

    /// The note well: a single quiet line, leading-aligned, no icon (MetricLevelsExplorer's
    /// "no readings in this range").
    public func note(text: LocalizedStringKey) -> some View {
        Text(text)
            .font(StrandFont.footnote)
            .foregroundStyle(theme.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(theme.surface, in: shape)
    }

    // MARK: - Área bajo una línea de tendencia (auditoría jul-2026, H4)

    /// El relleno vertical bajo una línea de tendencia: del tono a media opacidad (`StrandOpacity.muted`)
    /// arriba hacia el tono pleno abajo. Fuente ÚNICA — antes cada pantalla escribía
    /// `Gradient(colors: [hue.opacity(0.5), hue])` con la opacidad variando por archivo (0.5/0.55).
    /// Estandariza en `muted` (0.60); el salto desde 0.5/0.55 es imperceptible en un relleno de área.
    public static func fillGradient(_ hue: Color) -> Gradient {
        Gradient(colors: [hue.opacity(StrandOpacity.muted), hue])
    }
}

// MARK: - Preview

#Preview("ChartWell") {
    let theme = InstrumentoTheme.base
    ScrollView {
        VStack(spacing: 16) {
            ChartWell(theme).loading(height: 160)
            ChartWell(theme).empty(text: "Not enough days in this range to draw a trend.")
            ChartWell(theme, icon: "moon.zzz", cornerRadius: CenitMetrics.cardRadius)
                .empty(text: "Not enough nights yet to draw a trend.")
            ChartWell(theme, icon: "arrow.left.arrow.right",
                      cornerRadius: CenitMetrics.cardRadius, bordered: true)
                .empty(text: "Compare needs at least two metrics with history.")
            ChartWell(theme).note(text: "No readings in this range.")
        }
        .padding(20)
    }
    .background(theme.paper)
}
