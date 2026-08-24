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
    /// Optional trailing ✕ (decisión Fer, 2026-07-16) — DESCARTA la sesión sin abrirla. El host
    /// SIEMPRE confirma (ConfirmCard) antes de ejecutar; el pill solo dispara la intención. nil lo oculta.
    let onDiscard: (() -> Void)?
    /// VoiceOver label del ✕ («Descartar sesión») — caller-localized (FER-716).
    let discardAccessibilityLabel: Text?

    public init(routineName: String, elapsed: String, bpm: Int?,
                detail: String? = nil, paused: Bool = false, hue: Color,
                theme: InstrumentoTheme, accessibilityLabel: Text, accessibilityHint: Text,
                action: @escaping () -> Void, onDiscard: (() -> Void)? = nil,
                discardAccessibilityLabel: Text? = nil) {
        self.routineName = routineName; self.elapsed = elapsed; self.bpm = bpm
        self.detail = detail; self.paused = paused
        self.hue = hue; self.theme = theme
        self.accessibilityLabel = accessibilityLabel; self.accessibilityHint = accessibilityHint
        self.action = action; self.onDiscard = onDiscard
        self.discardAccessibilityLabel = discardAccessibilityLabel
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
                        // inkTertiary, not inkDim: the frozen clock is still READ (§8.7 — inkDim
                        // never carries copy that must be legible).
                        .foregroundStyle(paused ? theme.inkTertiary : theme.ink)
                        .layoutPriority(1)
                    if let bpm {
                        dot
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill").font(StrandFont.glyph(.chevron)).foregroundStyle(theme.dataHeart)
                            // r26: measured datum speaks Grotesk tabular (same voice as the session header).
                            Text("\(bpm)").font(InstrumentoType.groteskNumber(12, weight: .medium)).foregroundStyle(theme.dataHeart)
                        }
                        .layoutPriority(1)
                    }
                    if let detail {
                        dot
                        Text(detail)
                            .font(InstrumentoType.groteskNumber(12, weight: .medium))
                            .foregroundStyle(theme.inkSecondary)
                            .layoutPriority(1)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, onDiscard == nil ? 16 : 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(InstrumentoPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(.isButton)
            if let onDiscard {
                Button(action: onDiscard) {
                    Image(systemName: "xmark")
                        .font(StrandFont.glyph(.inline, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(theme.patternBlock))
                        // 34 visual, 44 tocable — el mínimo HIG nunca se negocia (§8.7).
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(InstrumentoPressStyle())
                .accessibilityLabel(discardAccessibilityLabel ?? Text(verbatim: ""))
                .padding(.trailing, 2)
            }
        }
        .background(Capsule(style: .continuous).fill(theme.surface))
        .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
        .floatShadow(theme, radius: 9, y: 6, opacity: 0.12)
        // Instrumento compacto flotante: cap de Dynamic Type (la info completa viaja en el label a11y).
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var dot: some View {
        Text("·").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
    }
}

#if DEBUG
#Preview("Session instruments") {
    let t = InstrumentoTheme.base
    return VStack(spacing: 28) {
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
