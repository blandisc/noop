import SwiftUI

// MARK: - Sparkband de tile (handoff «Hoy» 2026-07 · FER-709)
//
// The 14-day trend inside a metric tile, read against the PERSONAL range: a soft band
// (`rangeBand`) spanning the series' p25–p75, a dotted personal-median line
// (`rangeMidline`), the trend line in the metric's hue over a fading area fill, and an
// end dot sitting in a paper moat. The band answers «¿esto es normal PARA MÍ?» at a
// glance — every reading is framed by the user's own recent range, never a generic ideal.
// Decorative for VoiceOver: the tile's delta line already narrates the trend in words.

public struct TileSparkband: View {
    /// Daily values, oldest → newest (the head is today). Fewer than 3 points draws nothing.
    public var series: [Double]
    public var color: Color
    public var height: CGFloat

    @Environment(\.instrumentoTheme) private var theme

    public init(series: [Double], color: Color, height: CGFloat = 20) {
        self.series = series; self.color = color; self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            if series.count >= 3 { content(size: geo.size) }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func content(size: CGSize) -> some View {
        let lo = series.min() ?? 0
        let hi = series.max() ?? 1
        let flat = (hi - lo) <= .ulpOfOne
        let span = Swift.max(hi - lo, .ulpOfOne)
        let inset: CGFloat = 3
        func y(_ v: Double) -> CGFloat {
            let frac = flat ? 0.5 : CGFloat((v - lo) / span)
            return (size.height - inset) - frac * (size.height - 2 * inset)
        }
        let pts = series.indices.map { i in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(series.count - 1), y: y(series[i]))
        }
        let sorted = series.sorted()
        let p25 = quantile(sorted, 0.25), p75 = quantile(sorted, 0.75)
        let median = quantile(sorted, 0.5)

        return ZStack(alignment: .topLeading) {
            // Personal range band p25–p75 (min 3 pt tall so a tight range still reads).
            let bandTop = y(p75), bandBottom = y(p25)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.rangeBand)
                .frame(height: Swift.max(bandBottom - bandTop, 3))
                .offset(y: bandTop)
            // Dotted personal median.
            Path { p in
                p.move(to: CGPoint(x: 0, y: y(median)))
                p.addLine(to: CGPoint(x: size.width, y: y(median)))
            }
            .stroke(theme.rangeMidline, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            // Area fade under the line.
            Path { p in
                guard let first = pts.first, let last = pts.last else { return }
                p.move(to: CGPoint(x: first.x, y: size.height))
                for c in pts { p.addLine(to: c) }
                p.addLine(to: CGPoint(x: last.x, y: size.height))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [color.opacity(0.14), color.opacity(0)],
                                 startPoint: .top, endPoint: .bottom))
            // The trend line.
            Path { p in
                for (i, c) in pts.enumerated() { i == 0 ? p.move(to: c) : p.addLine(to: c) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            // End dot in a paper moat.
            if let last = pts.last {
                Circle().fill(theme.surface).frame(width: 7, height: 7)
                    .position(last)
                Circle().fill(color).frame(width: 4.4, height: 4.4)
                    .position(last)
            }
        }
    }

    /// Linear-interpolated quantile over an already-sorted series.
    private func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard let first = sorted.first, let last = sorted.last else { return 0 }
        guard sorted.count > 1 else { return first }
        let pos = q * Double(sorted.count - 1)
        let i = Int(pos.rounded(.down))
        if i >= sorted.count - 1 { return last }
        let frac = pos - Double(i)
        return sorted[i] * (1 - frac) + sorted[i + 1] * frac
    }
}

#if DEBUG
#Preview("Sparkband") {
    let t = InstrumentoTheme.base
    return VStack(spacing: 20) {
        TileSparkband(series: [52, 55, 58, 54, 57, 61, 59, 56, 60, 63, 58, 57, 62, 66],
                      color: t.dataHrv)
        TileSparkband(series: [412, 430, 395, 445, 420, 460, 400, 415, 432, 447, 410, 438, 425, 432],
                      color: t.dataSleep)
        TileSparkband(series: [97, 97, 97, 97, 97, 97, 97, 97],
                      color: t.dataSpO2)
    }
    .frame(width: 150)
    .padding(40)
    .background(t.surface)
    .preferredColorScheme(.light)
}
#endif
