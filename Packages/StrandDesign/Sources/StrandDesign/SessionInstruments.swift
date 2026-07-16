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

// MARK: - Pattern block

public extension View {
    /// The «patrón/conexión» block idiom (FER-708): a `patternBlock` fill with the top/bottom-right
    /// corners rounded (0/0/8/8) and a 2.5 pt colored bar down the leading edge. Single source so the
    /// Today brief and the strength receipt share one geometry (FER-716).
    func patternBlock(_ theme: InstrumentoTheme, bar: Color, cornerRadius: CGFloat = 8) -> some View {
        background(theme.patternBlock,
                   in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                              bottomTrailingRadius: cornerRadius,
                                              topTrailingRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .leading) { Rectangle().fill(bar).frame(width: 2.5) }
    }
}

// MARK: - Duration formatting

/// The one duration formatter for the Entrenar flow (FER-716): «M:SS» under an hour, «H:MM:SS»
/// past it. A single source so the session clock, rest countdown, cardio stopwatch, receipt
/// duration and the pill never drift (nor silently show «74:00» on a long session).
public enum SessionClock {
    public static func format(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
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
        /// r7 (owner): cada segmento puede llevar el hue de SU ejercicio (familia push/pull/legs);
        /// nil cae al `hue` global de la barra.
        public var tint: Color?
        public init(sets: Int, done: Double, tint: Color? = nil) {
            self.sets = sets; self.done = max(0, done); self.tint = tint
        }
    }
    let segments: [Segment]
    let hue: Color
    var track: Color
    var height: CGFloat
    public init(segments: [Segment], hue: Color, track: Color, height: CGFloat = 5) {
        self.segments = segments; self.hue = hue; self.track = track; self.height = height
    }
    /// Overall completion 0…100, weighted by each segment's set count (FER-915, VoiceOver value).
    private var completionPercent: Int {
        let total = max(segments.reduce(0) { $0 + $1.sets }, 1)
        let done = segments.reduce(0.0) { $0 + Double($1.sets) * min($1.done, 1) }
        return Int((done / Double(total)) * 100)
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
                        Capsule().fill(seg.tint ?? hue)
                            .frame(width: w * CGFloat(min(seg.done, 1)))
                    }
                    .frame(width: w)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(Text("Session progress"))
        .accessibilityValue(Text("\(completionPercent)% complete"))
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
    /// Extra quiet segment, e.g. «serie 4/10» (FER-952). nil hides it.
    let detail: String?
    /// Paused state (FER-952): dims the clock and flips the trailing button to ▶.
    let paused: Bool
    let hue: Color
    let theme: InstrumentoTheme
    /// VoiceOver label + hint, provided by the CALLER — the package has no string catalog, so the
    /// app layer localizes them (FER-716).
    let accessibilityLabel: Text
    let accessibilityHint: Text
    let action: () -> Void
    /// Optional trailing ⏸/▶ (FER-952) — pauses/resumes WITHOUT opening the session. nil hides it.
    let onPlayPause: (() -> Void)?

    public init(routineName: String, elapsed: String, bpm: Int?,
                detail: String? = nil, paused: Bool = false, hue: Color,
                theme: InstrumentoTheme, accessibilityLabel: Text, accessibilityHint: Text,
                action: @escaping () -> Void, onPlayPause: (() -> Void)? = nil) {
        self.routineName = routineName; self.elapsed = elapsed; self.bpm = bpm
        self.detail = detail; self.paused = paused
        self.hue = hue; self.theme = theme
        self.accessibilityLabel = accessibilityLabel; self.accessibilityHint = accessibilityHint
        self.action = action; self.onPlayPause = onPlayPause
    }

    public var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Circle().fill(hue).frame(width: 6, height: 6)
                    Text(routineName)
                        .font(StrandFont.subhead).fontWeight(.semibold)
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    dot
                    Text(elapsed)
                        .font(InstrumentoType.groteskNumber(14))
                        .foregroundStyle(paused ? theme.inkDim : theme.ink)
                    if let bpm {
                        dot
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(theme.dataHeart)
                            Text("\(bpm)").font(StrandFont.subhead.monospacedDigit()).foregroundStyle(theme.dataHeart)
                        }
                    }
                    if let detail {
                        dot
                        Text(detail)
                            .font(InstrumentoType.groteskNumber(12, weight: .medium))
                            .foregroundStyle(theme.inkSecondary)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, onPlayPause == nil ? 16 : 6)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(InstrumentoPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(.isButton)
            if let onPlayPause {
                Button(action: onPlayPause) {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(theme.patternBlock))
                        .contentShape(Circle())
                }
                .buttonStyle(InstrumentoPressStyle())
                .padding(.trailing, 6)
            }
        }
        .background(Capsule(style: .continuous).fill(theme.surface))
        .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
        .floatShadow(theme, radius: 9, y: 6, opacity: 0.12)
    }

    private var dot: some View {
        Text("·").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
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
                    theme: t, accessibilityLabel: Text(verbatim: "Sesión activa"),
                    accessibilityHint: Text(verbatim: "Vuelve a la sesión")) {}
        SessionPill(routineName: "Pierna", elapsed: "24:10", bpm: nil, hue: t.dataSleep,
                    theme: t, accessibilityLabel: Text(verbatim: "Sesión activa"),
                    accessibilityHint: Text(verbatim: "Vuelve a la sesión")) {}
    }
    .padding(32)
    .frame(maxWidth: .infinity)
    .background(t.paper)
    .preferredColorScheme(.light)
}
#endif
