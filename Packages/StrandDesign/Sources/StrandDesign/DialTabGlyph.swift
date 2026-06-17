import SwiftUI

// MARK: - «Instrumento diurno» — 24-hour dial glyph for the tab bar (FER-163)
//
// A compact 24-hour dial for the «Hoy» tab: a quiet ring with four cardinal ticks
// and a single now-dot. It echoes the `DiurnalDial` hero and the Cénit «dial
// diurno» app mark, so the most-used tab points back at the home screen's
// instrument.
//
// It speaks the language (see Instrumento.swift): the glyph carries NO data hue —
// it is drawn in one ink color. The green now-dot the language reserves for the
// datum lives in the tab bar UNDER the label (the selection mark), not inside the
// icon. Pure and size-driven: every measure scales from `size`, so it renders
// crisply at tab size and in the #Preview, and never reads `Date()`.

/// A 24-hour dial glyph drawn in a single `color`. Use as the «Hoy» tab icon.
public struct DialTabGlyph: View {

    /// Edge length of the (square) glyph; every measure scales from it.
    public var size: CGFloat
    /// The single ink color the whole glyph is drawn in (ring, ticks, now-dot).
    public var color: Color
    /// Stroke width override; defaults to a size-proportional hairline.
    public var lineWidth: CGFloat?

    public init(size: CGFloat = 23, color: Color, lineWidth: CGFloat? = nil) {
        self.size = size
        self.color = color
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let r = sz.width * 0.346
            let lw = lineWidth ?? max(1.2, sz.width * 0.063)

            // The 24h bezel.
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(color), lineWidth: lw)

            // Four short cardinal ticks just inside the ring, to orient the face.
            let tick = sz.width * 0.072
            for deg in stride(from: 0.0, to: 360.0, by: 90.0) {
                let a = deg * .pi / 180
                let outer = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                let inner = CGPoint(x: c.x + cos(a) * (r - tick), y: c.y + sin(a) * (r - tick))
                var p = Path(); p.move(to: inner); p.addLine(to: outer)
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }

            // The now-dot — upper-right, seated on the ring (≈ -45°). Echoes the
            // DiurnalDial's now marker; here it's part of the glyph's identity.
            let da = -45.0 * .pi / 180
            let dr = r * 0.8
            let dp = CGPoint(x: c.x + cos(da) * dr, y: c.y + sin(da) * dr)
            let dotR = sz.width * 0.066
            ctx.fill(Path(ellipseIn: CGRect(x: dp.x - dotR, y: dp.y - dotR, width: dotR * 2, height: dotR * 2)),
                     with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("DialTabGlyph") {
    let day = InstrumentoTheme.base
    return VStack(spacing: 28) {
        // On paper (Hoy), active vs idle ink.
        HStack(spacing: 28) {
            VStack(spacing: 6) {
                DialTabGlyph(size: 23, color: day.ink)
                Text("Hoy").font(.caption2).fontWeight(.medium).foregroundStyle(day.ink)
                Circle().fill(day.dataRecovery).frame(width: 5, height: 5)
            }
            VStack(spacing: 6) {
                DialTabGlyph(size: 23, color: day.inkTertiary)
                Text("Hoy").font(.caption2).foregroundStyle(day.inkTertiary)
                Circle().fill(.clear).frame(width: 5, height: 5)
            }
        }
        .padding(20)
        .background(day.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        // On the dark instrument panel.
        HStack(spacing: 28) {
            DialTabGlyph(size: 23, color: StrandPalette.textPrimary)
            DialTabGlyph(size: 23, color: StrandPalette.textSecondary)
            DialTabGlyph(size: 40, color: StrandPalette.textPrimary)
        }
        .padding(20)
        .background(StrandPalette.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .padding(24)
}
#endif
