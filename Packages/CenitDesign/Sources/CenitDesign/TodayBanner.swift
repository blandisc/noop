import SwiftUI

// MARK: - Banner de «Hoy» (handoff «Hoy · Estados» 2026-07 · FER-711)
//
// The single, reusable status card that rides UNDER the header, over the normal day (the mock's
// «banners sobre el día normal»): a status dot, a plain-language title + subtitle, and an optional
// CTA word. It is purely presentational — it owns the drawing, never the detection. The app decides
// WHICH banner (if any) is live from existing signals and hands the strings + colors in, so a new
// banner is a new driver, not a new view.
//
// Anatomy (from the handoff): an optional overline label (9/600, tracked, uppercased) sits above a
// surface card (radius 14, hairline border, soft lift shadow). Inside: a 7px status dot · a column
// of title (13/600 ink) + subtitle (11.5 inkTertiary) · an optional CTA word (11/600 grotesk) that
// makes the whole card a button.

public struct TodayBanner: View {

    /// The overline over the card (e.g. «SIESTA DETECTADA»). Uppercased + tracked by the view.
    public var label: LocalizedStringKey?
    /// The status dot color (the banner's identity: sync green, warning amber, critical red, …).
    public var dot: Color
    public var title: LocalizedStringKey
    public var subtitle: LocalizedStringKey
    /// Optional CTA word (e.g. «PERMISOS →»); when present with `action`, the whole card taps.
    public var cta: LocalizedStringKey?
    public var ctaColor: Color
    public var action: (() -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    public init(label: LocalizedStringKey? = nil,
                dot: Color,
                title: LocalizedStringKey,
                subtitle: LocalizedStringKey,
                cta: LocalizedStringKey? = nil,
                ctaColor: Color = .clear,
                action: (() -> Void)? = nil) {
        self.label = label
        self.dot = dot
        self.title = title
        self.subtitle = subtitle
        self.cta = cta
        self.ctaColor = ctaColor
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100 + 1) {
            if let label {
                Text(label)
                    .font(InstrumentoType.grotesk(9, weight: .semibold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.inkTertiary)
            }
            card
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var card: some View {
        let content = HStack(spacing: LiquidSpace.s200 + 2) {
            Circle().fill(dot).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let cta {
                Text(cta)
                    .font(InstrumentoType.grotesk(11, weight: .semibold))
                    .foregroundStyle(ctaColor)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, LiquidSpace.s400 - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
        .strandElevation(.floating, ink: theme.ink)

        if let action {
            Button(action: action) { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("Banners de Hoy") {
    let t = InstrumentoTheme.base
    return VStack(alignment: .leading, spacing: 14) {
        TodayBanner(label: "Sincronizando · transitorio, segundos", dot: t.verdict,
                    title: "Leyendo tu noche…",
                    subtitle: "la banda está entregando 7:12 de señal")
        TodayBanner(label: "Batería crítica", dot: t.critical,
                    title: "Banda al 8%",
                    subtitle: "cárgala antes de dormir o pierdes la noche")
        TodayBanner(label: "Banda desconectada de día", dot: t.inkMuted,
                    title: "Sin señal desde las 11:20",
                    subtitle: "el veredicto de hoy no cambia; la noche sí la necesita",
                    cta: "Conectar →", ctaColor: t.verdict, action: {})
        TodayBanner(label: "Apple Salud sin permisos suficientes", dot: t.originApple,
                    title: "Apple Salud está conectado a medias",
                    subtitle: "sin permiso de sueño y FC no hay preliminar",
                    cta: "Permisos →", ctaColor: t.verdict, action: {})
    }
    .padding(24)
    .frame(width: 393)
    .background(t.paper)
    .preferredColorScheme(.light)
}
#endif
