import SwiftUI

// MARK: - Entrenar v3 session instruments (FER-716)
//
// The two «elevated» pieces of the strength flow — the rest card (in the app layer) and the
// active-session pill — are the ONLY surfaces that lift off the warm paper, because on this
// language elevation is exceptional and therefore means something (they sit above the session's
// time). Both share `floatShadow`. The session progress bar is a flat instrument (segments by
// exercise, partial fill), color = routine identity, position = the channel — no shadow.

public extension View {
    /// The single «float» shadow of the Entrenar flow (FER-716): a soft ink drop used by the rest
    /// card (radius 12, y 8) and, lighter, the session pill (radius 9, y 6). Deliberately scarce —
    /// nothing else on the paper casts a shadow.
    func floatShadow(_ theme: InstrumentoTheme, radius: CGFloat = 12, y: CGFloat = 8,
                     opacity: Double = 0.13) -> some View {
        shadow(color: theme.ink.opacity(opacity), radius: radius, x: 0, y: y)
    }
}

// MARK: - Session progress bar

/// The strength session's progress: one segment per exercise, its width ∝ its set count, filled
/// `done` (0…1) in the routine hue with the remainder in `hairline`. A flat instrument — length with
/// a zero base is the channel, the hue is identity; no axes, no shadow. (FER-716)
public struct SessionProgressBar: View {
    /// One exercise: how many sets it holds (drives width) and how done it is (0…1, drives fill).
    public struct Segment: Equatable {
        public var sets: Int
        public var done: Double
        public init(sets: Int, done: Double) { self.sets = sets; self.done = max(0, done) }
    }
    let segments: [Segment]
    let hue: Color
    var track: Color
    public init(segments: [Segment], hue: Color, track: Color) {
        self.segments = segments; self.hue = hue; self.track = track
    }
    public var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 3
            let totalSets = max(segments.reduce(0) { $0 + $1.sets }, 1)
            let gaps = CGFloat(max(segments.count - 1, 0)) * gap
            let usable = max(geo.size.width - gaps, 0)
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    let w = usable * CGFloat(seg.sets) / CGFloat(totalSets)
                    ZStack(alignment: .leading) {
                        Capsule().fill(track)
                        Capsule().fill(hue)
                            .frame(width: w * CGFloat(min(seg.done, 1)))
                    }
                    .frame(width: w)
                }
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Active-session pill

/// The floating «a session is running» pill (FER-716): it hovers over the dock in all five tabs and
/// re-opens the live session on tap, replacing the old «Resume» row. Format «Pierna · 24:10 · ♥ 118»
/// (the ♥ segment is dropped when there's no strap HR — no dashes). One of the two elevated pieces;
/// its dot is STATIC — the only always-on pulse in the app is the session header's BPM dot.
public struct SessionPill: View {
    let routineName: String
    let elapsed: String        // preformatted "24:10"
    let bpm: Int?              // nil = no strap → the ♥ segment is hidden
    let hue: Color
    let theme: InstrumentoTheme
    let action: () -> Void

    public init(routineName: String, elapsed: String, bpm: Int?, hue: Color,
                theme: InstrumentoTheme, action: @escaping () -> Void) {
        self.routineName = routineName; self.elapsed = elapsed; self.bpm = bpm
        self.hue = hue; self.theme = theme; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(hue).frame(width: 6, height: 6)
                Text(routineName)
                    .font(StrandFont.subhead).fontWeight(.semibold)
                    .foregroundStyle(theme.ink)
                dot
                Text(elapsed)
                    .font(InstrumentoType.groteskNumber(14))
                    .foregroundStyle(theme.ink)
                if let bpm {
                    dot
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(theme.dataHeart)
                        Text("\(bpm)").font(StrandFont.subhead.monospacedDigit()).foregroundStyle(theme.dataHeart)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Capsule(style: .continuous).fill(theme.surface))
            .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
            .floatShadow(theme, radius: 9, y: 6, opacity: 0.12)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
        .accessibilityHint(Text("Toca para volver a la sesión"))
        .accessibilityAddTraits(.isButton)
    }

    private var dot: some View {
        Text("·").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
    }
    private var a11y: Text {
        if let bpm {
            return Text("Sesión activa: \(routineName), \(elapsed), pulso \(bpm)")
        }
        return Text("Sesión activa: \(routineName), \(elapsed)")
    }
}

#if DEBUG
#Preview("Session instruments") {
    let t = InstrumentoTheme.base
    return VStack(spacing: 28) {
        SessionProgressBar(segments: [.init(sets: 4, done: 1), .init(sets: 4, done: 0.5),
                                      .init(sets: 3, done: 0), .init(sets: 5, done: 0)],
                           hue: t.dataSleep, track: t.hairline)
            .padding(.horizontal, 24)
        SessionPill(routineName: "Pierna", elapsed: "24:10", bpm: 118, hue: t.dataSleep,
                    theme: t) {}
        SessionPill(routineName: "Pierna", elapsed: "24:10", bpm: nil, hue: t.dataSleep,
                    theme: t) {}
    }
    .padding(32)
    .frame(maxWidth: .infinity)
    .background(t.paper)
    .preferredColorScheme(.light)
}
#endif
