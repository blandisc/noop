import SwiftUI

// MARK: - Insight glyphs — a drawn mark per finding type (FER-292 v2)
//
// A small (46×30) instrument mark that gives each «Hallazgo» a visual identity at a glance, drawn flat
// in tokens:
//   • relation — two intertwined curves (the two metrics that move together), in their data hues.
//   • trend    — a rising/falling line of the recent series with a head dot in the metric hue.
//   • anomaly  — a quiet dashed baseline with a recent flat run and a single spike marked in `critical`.
//
// Color lives only on the datum (the curves / line / spike); the chrome (baseline, dashes) is ink. The
// theme is injected; the trend reads its series + hue from the caller.

public struct InsightGlyph: View {

    public enum Kind: Equatable { case relation, trend, anomaly }

    public var kind: Kind
    /// The recent series for `.trend` (e.g. last 14 nights). Ignored by the other kinds.
    public var values: [Double]
    /// The metric hue (trend line / head dot, and the second relation curve).
    public var primary: Color
    /// The companion hue for `.relation`'s first curve (e.g. HRV).
    public var secondary: Color
    public var theme: InstrumentoTheme

    public init(kind: Kind, values: [Double] = [], primary: Color, secondary: Color, theme: InstrumentoTheme) {
        self.kind = kind
        self.values = values
        self.primary = primary
        self.secondary = secondary
        self.theme = theme
    }

    private static let size = CGSize(width: 46, height: 30)

    public var body: some View {
        content
            .frame(width: Self.size.width, height: Self.size.height)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .relation: relation
        case .trend:    trend
        case .anomaly:  anomaly
        }
    }

    // Two intertwined curves crossing twice — the "they move together" mark.
    private var relation: some View {
        ZStack {
            curve(y0: 22, yMid: 8).stroke(secondary, style: line)
            curve(y0: 15, yMid: 26).stroke(primary.opacity(0.85), style: line)
        }
    }

    private func curve(y0: CGFloat, yMid: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 2, y: y0))
            p.addCurve(to: CGPoint(x: 22, y: yMid),
                       control1: CGPoint(x: 10, y: y0), control2: CGPoint(x: 12, y: yMid))
            p.addCurve(to: CGPoint(x: 44, y: y0),
                       control1: CGPoint(x: 32, y: yMid), control2: CGPoint(x: 34, y: y0))
        }
    }

    // A normalized polyline of the recent series + a head dot. Falls back to a gentle rising line.
    private var trend: some View {
        let pts = trendPoints
        return ZStack {
            Path { p in
                guard let first = pts.first else { return }
                p.move(to: first)
                for q in pts.dropFirst() { p.addLine(to: q) }
            }
            .stroke(primary, style: line)
            if let head = pts.last {
                Circle().fill(primary).frame(width: 5, height: 5).position(head)
            }
        }
    }

    private var trendPoints: [CGPoint] {
        let series = values.suffix(14)
        guard series.count >= 2 else {
            return [CGPoint(x: 2, y: 22), CGPoint(x: 16, y: 18), CGPoint(x: 30, y: 11), CGPoint(x: 44, y: 5)]
        }
        let lo = series.min()!, hi = series.max()!
        let span = Swift.max(hi - lo, 0.0001)
        let n = series.count
        return series.enumerated().map { (i, v) -> CGPoint in
            let x: CGFloat = 2 + 42 * CGFloat(i) / CGFloat(n - 1)
            let y: CGFloat = 25 - 20 * CGFloat((v - lo) / span)
            return CGPoint(x: x, y: y)
        }
    }

    // A dashed baseline, a recent flat run, and a single spike marked in `critical`.
    private var anomaly: some View {
        ZStack {
            Path { p in p.move(to: CGPoint(x: 2, y: 20)); p.addLine(to: CGPoint(x: 44, y: 20)) }
                .stroke(theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            Path { p in
                p.move(to: CGPoint(x: 2, y: 21)); p.addLine(to: CGPoint(x: 12, y: 20))
                p.addLine(to: CGPoint(x: 22, y: 21)); p.addLine(to: CGPoint(x: 30, y: 20))
            }
            .stroke(theme.hairlineStrong, style: line)
            Path { p in p.move(to: CGPoint(x: 36, y: 20)); p.addLine(to: CGPoint(x: 36, y: 6)) }
                .stroke(theme.critical, style: line)
            Circle().fill(theme.critical).frame(width: 6, height: 6).position(x: 36, y: 6)
        }
    }

    private var line: StrokeStyle { StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round) }
}

#if DEBUG
#Preview("InsightGlyph") {
    let t = InstrumentoTheme.base
    return HStack(spacing: 24) {
        InsightGlyph(kind: .relation, primary: t.dataRecovery, secondary: t.dataHrv, theme: t)
        InsightGlyph(kind: .trend, values: [40, 42, 41, 44, 46, 45, 49, 52, 55, 58, 61, 64, 67, 70],
                     primary: t.dataRecovery, secondary: t.dataHrv, theme: t)
        InsightGlyph(kind: .anomaly, primary: t.dataHeart, secondary: t.dataHrv, theme: t)
    }
    .padding(40)
    .background(t.paper)
}
#endif
