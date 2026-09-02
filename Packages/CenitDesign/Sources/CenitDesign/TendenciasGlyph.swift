import SwiftUI

// MARK: - TendenciasGlyph — the «Tendencias» brand mark
//
// A curve threading four reading nodes — the rhythm of measuring something every day, with today's
// point (top-right) drawn larger. It's the wordmark/tab glyph for the «Tendencias» layer (the
// redesigned Body tab). No SF Symbol matches it exactly, so it's an authored glyph: a stroked
// polyline plus filled node dots, scaled from a 24×24 box so it stays crisp at any size (the header
// wordmark, the bottom bar) and inherits the ink color from its caller — color stays on the datum,
// never the chrome. Pure SwiftUI; no UIKit/AppKit.

/// The curve-with-nodes brand mark, drawn in `color`. Geometry matches the design handoff's
/// `polyline 3,16 9,12 14,13.5 21,5` with node dots (r1.6, today's @ 21,5 is r2.1).
public struct TendenciasGlyph: View {
    private let color: Color
    private let lineWidth: CGFloat

    public init(color: Color, lineWidth: CGFloat = 1.8) {
        self.color = color
        self.lineWidth = lineWidth
    }

    // Authored in a 24×24 box: the reading line and its four nodes (today's, top-right, is bigger).
    private static let points: [CGPoint] = [
        CGPoint(x: 3, y: 16), CGPoint(x: 9, y: 12), CGPoint(x: 14, y: 13.5), CGPoint(x: 21, y: 5),
    ]
    private static let nodeRadii: [CGFloat] = [1.6, 1.6, 1.6, 2.1]

    public var body: some View {
        // Shares the 24×24 scaled, decorative scaffold with `PatronesGlyph` via `AuthoredGlyph` (FER-903);
        // the two-pass stroke+fill drawing below is this glyph's own.
        AuthoredGlyph { s in
            ZStack {
                // The reading line connecting the nodes.
                Path { p in
                    let pts = Self.points.map { CGPoint(x: $0.x * s, y: $0.y * s) }
                    p.addLines(pts)
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                // The node dots — today's (last) is larger.
                Path { p in
                    for (pt, r) in zip(Self.points, Self.nodeRadii) {
                        let c = CGPoint(x: pt.x * s, y: pt.y * s)
                        p.addEllipse(in: CGRect(x: c.x - r * s, y: c.y - r * s, width: 2 * r * s, height: 2 * r * s))
                    }
                }
                .fill(color)
            }
        }
    }
}

#if DEBUG
#Preview("TendenciasGlyph") {
    HStack(spacing: 24) {
        TendenciasGlyph(color: InstrumentoTheme.base.ink).frame(width: 22, height: 22)
        TendenciasGlyph(color: InstrumentoTheme.base.dataRecovery).frame(width: 40, height: 40)
        TendenciasGlyph(color: InstrumentoTheme.base.inkTertiary, lineWidth: 1.6).frame(width: 23, height: 23)
    }
    .padding(40)
    .background(InstrumentoTheme.base.paper)
}
#endif
