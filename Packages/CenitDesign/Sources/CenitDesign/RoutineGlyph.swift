import SwiftUI

// MARK: - RoutineRegionGlyph — the routine-family marks for «Mis rutinas» (FER-940)
//
// The «Tu Plan» handoff gives each routine row a small line-art mark of its movement family:
// bench (push), row (pull), squat (legs), dumbbell (full body). Authored in the shared 24×24
// space (`AuthoredGlyph`, FER-903), stroked in the routine's region tint, decorative only —
// the routine name beside it carries the meaning. The KIND enum is design-side on purpose:
// CenitDesign doesn't import StrandTraining, so the app maps `RoutineRegion` → kind.

public enum RoutineGlyphKind: Sendable {
    case push, pull, legs, fullBody
}

public struct RoutineRegionGlyph: View {
    private let kind: RoutineGlyphKind
    private let tint: Color

    public init(_ kind: RoutineGlyphKind, tint: Color) {
        self.kind = kind
        self.tint = tint
    }

    public var body: some View {
        AuthoredGlyph { s in
            path(scale: s)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.7 * s, lineCap: .round, lineJoin: .round))
        }
    }

    /// The authored 24×24 drawing, scaled by `s`.
    private func path(scale s: CGFloat) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var p = Path()
        switch kind {
        case .push:
            // Bench press seen side-on: the bar with a plate each side, over the bench line.
            p.move(to: pt(2.5, 8)); p.addLine(to: pt(21.5, 8))          // bar
            p.move(to: pt(6, 5));   p.addLine(to: pt(6, 11))            // left plate
            p.move(to: pt(18, 5));  p.addLine(to: pt(18, 11))           // right plate
            p.move(to: pt(5, 16));  p.addLine(to: pt(19, 16))           // bench
            p.move(to: pt(8, 16));  p.addLine(to: pt(8, 20))            // legs
            p.move(to: pt(16, 16)); p.addLine(to: pt(16, 20))
        case .pull:
            // Lat pulldown: the high bar, the cable, and the V of the pull.
            p.move(to: pt(4, 5));   p.addLine(to: pt(20, 5))            // high bar
            p.move(to: pt(12, 5));  p.addLine(to: pt(12, 11))           // cable
            p.move(to: pt(7.5, 16)); p.addLine(to: pt(12, 11)); p.addLine(to: pt(16.5, 16))  // pull V
            p.move(to: pt(7, 20));  p.addLine(to: pt(17, 20))           // seat
        case .legs:
            // Squat: the bar across the shoulders, and the two bent legs.
            p.move(to: pt(4, 6));   p.addLine(to: pt(20, 6))            // bar
            p.move(to: pt(6.5, 3.5)); p.addLine(to: pt(6.5, 8.5))       // left plate
            p.move(to: pt(17.5, 3.5)); p.addLine(to: pt(17.5, 8.5))     // right plate
            p.move(to: pt(9.5, 10)); p.addLine(to: pt(7.5, 15)); p.addLine(to: pt(9.5, 20))  // left leg
            p.move(to: pt(14.5, 10)); p.addLine(to: pt(16.5, 15)); p.addLine(to: pt(14.5, 20)) // right leg
        case .fullBody:
            // A dumbbell on the diagonal — the whole-body catch-all.
            p.move(to: pt(8, 16));  p.addLine(to: pt(16, 8))            // handle
            p.move(to: pt(4.5, 12.5)); p.addLine(to: pt(11.5, 19.5))    // left head
            p.move(to: pt(12.5, 4.5)); p.addLine(to: pt(19.5, 11.5))    // right head
        }
        return p
    }
}

private struct RoutineGlyphPreview: View {
    private let theme = InstrumentoTheme.base
    var body: some View {
        HStack(spacing: 18) {
            chip(.push, theme.dataStrain)
            chip(.pull, theme.dataHrv)
            chip(.legs, theme.dataSleep)
            chip(.fullBody, theme.ink)
        }
        .padding(30)
        .background(theme.paper)
    }
    private func chip(_ kind: RoutineGlyphKind, _ tint: Color) -> some View {
        RoutineRegionGlyph(kind, tint: tint)
            .frame(width: 22, height: 22)
            .frame(width: 38, height: 38)
            .background(theme.patternBlock, in: RoundedRectangle(cornerRadius: LiquidRadius.insetTarjeta, style: .continuous))
    }
}

#Preview("Routine glyphs") {
    RoutineGlyphPreview()
}
