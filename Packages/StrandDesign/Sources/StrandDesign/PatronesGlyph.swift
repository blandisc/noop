import SwiftUI

// MARK: - PatronesGlyph — the «Patrones» brand mark
//
// Two linked circles with an elbow connector — the wordmark/tab glyph for the «Patrones» layer
// (the redesigned Coach tab). One pattern feeding another: a top-left node, a bottom-right node, and
// the path between them. Drawn as a stroked `Shape` so it scales crisply at any size (the header
// wordmark, the bottom bar) and inherits the ink color from its caller — color stays on the datum,
// never the chrome. Pure SwiftUI; no UIKit/AppKit.

/// The two-linked-circles brand mark, stroked in `color`. Geometry is authored in a 24×24 box and
/// scaled to fit, matching the design handoff's `circle(7,7,r3) + circle(17,17,r3) + elbow`.
public struct PatronesGlyph: View {
    private let color: Color
    private let lineWidth: CGFloat

    public init(color: Color, lineWidth: CGFloat = 1.9) {
        self.color = color
        self.lineWidth = lineWidth
    }

    public var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 24
            Path { p in
                // Top-left node (r3 @ 7,7) and bottom-right node (r3 @ 17,17).
                p.addEllipse(in: CGRect(x: 4 * s, y: 4 * s, width: 6 * s, height: 6 * s))
                p.addEllipse(in: CGRect(x: 14 * s, y: 14 * s, width: 6 * s, height: 6 * s))
                // Elbow: down from the top node, round the corner, right into the bottom node.
                p.move(to: CGPoint(x: 7 * s, y: 10 * s))
                p.addLine(to: CGPoint(x: 7 * s, y: 14 * s))
                p.addQuadCurve(to: CGPoint(x: 10 * s, y: 17 * s), control: CGPoint(x: 7 * s, y: 17 * s))
                p.addLine(to: CGPoint(x: 14 * s, y: 17 * s))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("PatronesGlyph") {
    HStack(spacing: 24) {
        PatronesGlyph(color: InstrumentoTheme.base.ink).frame(width: 22, height: 22)
        PatronesGlyph(color: InstrumentoTheme.base.dataRecovery).frame(width: 40, height: 40)
        PatronesGlyph(color: InstrumentoTheme.base.inkTertiary, lineWidth: 1.6).frame(width: 23, height: 23)
    }
    .padding(40)
    .background(InstrumentoTheme.base.paper)
}
#endif
