import SwiftUI

// MARK: - Poincaré cloud (experimental rhythm visualization — FER-666)
//
// A scatter of successive beat-to-beat intervals (NNᵢ, NNᵢ₊₁): each point pairs one R-R interval
// with the next. A steady rhythm draws a tight, elongated comet hugging the identity diagonal; a
// more variable rhythm rounds out into a diffuse cloud. This is the DATUM of the «Ritmo» screen —
// the single place saturated color appears — so it's drawn in one calm cyan (`dataHrv`), never a
// traffic-light hue: the SHAPE carries the meaning, the color only makes the cloud legible.
//
// Deliberately NON-CLINICAL: this is a wellness plot, not an ECG or a diagnosis. It renders points
// and a reference diagonal — nothing here labels a rhythm, scores risk, or emits a verdict; the
// neutral word beside it comes from the caller. Cross-platform, tokens-only.
//
// Accessibility: the scatter is decorative to VoiceOver (a raw point cloud is meaningless spoken);
// the caller passes a plain-language `summary` that IS the accessible value ("Se vio estable · 1240
// latidos"), so assistive tech reads the read-out, not the dots.

public struct PoincareCloud: View {
    /// Successive interval pairs (x = NNᵢ, y = NNᵢ₊₁), in milliseconds. Empty → just the frame.
    public var points: [CGPoint]
    /// The datum hue. Defaults to the on-paper data cyan; callers should not pass a status color.
    public var color: Color
    /// Dims the cloud for a low-confidence ("calibrando") read, so a thin cloud looks tentative
    /// rather than as assertive as a solid one.
    public var faded: Bool
    /// Spoken value for VoiceOver — the words, not the points (e.g. the label + beat count).
    public var summary: String

    public init(points: [CGPoint],
                color: Color = InstrumentoTheme.base.dataHrv,
                faded: Bool = false,
                summary: String) {
        self.points = points
        self.color = color
        self.faded = faded
        self.summary = summary
    }

    /// Symmetric ms half-range around the cloud centre, so both axes share one scale (the identity
    /// line stays a true 45°). Poincaré axes are NOT zero-based — the plot is about spread around the
    /// mean interval, so a zero baseline would collapse the cloud to a dot. Framed to the data with a
    /// margin, floored so a tiny-spread steady night still reads as a comet, not a single blob.
    private var frame: (center: Double, half: Double) {
        guard !points.isEmpty else { return (1000, 300) }
        let xs = points.map { Double($0.x) }, ys = points.map { Double($0.y) }
        let lo = min(xs.min() ?? 700, ys.min() ?? 700)
        let hi = max(xs.max() ?? 1300, ys.max() ?? 1300)
        let center = (lo + hi) / 2
        let half = max((hi - lo) / 2 * 1.15, 120)   // 15% margin; floor 120 ms
        return (center, half)
    }

    public var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let ox = (size.width - side) / 2, oy = (size.height - side) / 2
            let inset: CGFloat = 12
            let plot = CGRect(x: ox + inset, y: oy + inset,
                              width: side - inset * 2, height: side - inset * 2)
            let f = frame

            // Map an (ms, ms) pair to plot coordinates (y inverted: larger interval = higher).
            func pt(_ xMs: Double, _ yMs: Double) -> CGPoint {
                let nx = (xMs - (f.center - f.half)) / (f.half * 2)
                let ny = (yMs - (f.center - f.half)) / (f.half * 2)
                return CGPoint(x: plot.minX + CGFloat(nx) * plot.width,
                               y: plot.maxY - CGFloat(ny) * plot.height)
            }

            // Faint frame.
            ctx.stroke(Path(plot), with: .color(InstrumentoTheme.base.hairline), lineWidth: 1)
            // Identity diagonal (NNᵢ = NNᵢ₊₁) — the reference a steady rhythm hugs.
            var diag = Path()
            diag.move(to: CGPoint(x: plot.minX, y: plot.maxY))
            diag.addLine(to: CGPoint(x: plot.maxX, y: plot.minY))
            ctx.stroke(diag, with: .color(InstrumentoTheme.base.hairlineStrong),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

            // The cloud. One calm cyan; slight transparency so density reads where points stack.
            let dotColor = color.opacity(faded ? 0.42 : 0.72)
            let r: CGFloat = faded ? 2.0 : 2.2
            for p in points {
                let c = pt(Double(p.x), Double(p.y))
                guard plot.contains(c) else { continue }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(dotColor))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(summary)
    }
}

#if DEBUG
import Foundation

/// Deterministic synthetic clouds for the preview (no trig-free requirement here — preview only).
private func demoCloud(n: Int, sd1: Double, sd2: Double, seed: UInt64) -> [CGPoint] {
    var s = seed
    func rnd() -> Double { s = s &* 1664525 &+ 1013904223; return Double(s % 100_000) / 100_000 }
    func gauss() -> Double { let u = max(rnd(), 1e-9), v = rnd(); return (-2 * log(u)).squareRoot() * cos(2 * .pi * v) }
    return (0..<n).map { _ in
        let along = gauss() * sd2, perp = gauss() * sd1
        let dx = (along + perp) / 2.0.squareRoot(), dy = (along - perp) / 2.0.squareRoot()
        return CGPoint(x: 1000 + dx, y: 1000 + dy)
    }
}

#Preview("PoincareCloud") {
    HStack(spacing: 20) {
        VStack(spacing: 8) {
            Text("ESTABLE").instrumentoOverline().foregroundStyle(InstrumentoTheme.base.inkTertiary)
            PoincareCloud(points: demoCloud(n: 150, sd1: 20, sd2: 55, seed: 3),
                          summary: "Se vio estable").frame(width: 150)
        }
        VStack(spacing: 8) {
            Text("VARIÓ").instrumentoOverline().foregroundStyle(InstrumentoTheme.base.inkTertiary)
            PoincareCloud(points: demoCloud(n: 150, sd1: 110, sd2: 120, seed: 7),
                          summary: "Varió más de lo usual").frame(width: 150)
        }
        VStack(spacing: 8) {
            Text("CALIBRANDO").instrumentoOverline().foregroundStyle(InstrumentoTheme.base.inkTertiary)
            PoincareCloud(points: demoCloud(n: 34, sd1: 24, sd2: 52, seed: 11), faded: true,
                          summary: "Aún calibrando").frame(width: 150)
        }
    }
    .padding(24)
    .frame(width: 560, height: 240)
    .background(InstrumentoTheme.base.paper)
    .preferredColorScheme(.light)
}
#endif
