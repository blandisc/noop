import SwiftUI

// MARK: - «Instrumento diurno» — screen scaffold & shared states (FER-131)
//
// The reusable shell every redesigned screen sits in, plus the three states a
// screen can be in before it has data. All read the theme from the Environment
// (`\.instrumentoTheme`), so the hour engine (FER-132) recolors them for free.
// They obey the language: warm paper, ink labels, hierarchy by space, and color
// only where it carries meaning (the error mark).

// MARK: - ScreenScaffold

/// The base shell for an «Instrumento diurno» screen: warm-paper canvas, screen
/// padding, and an optional quiet header (moderate overline + one dominant
/// title). It does NOT scroll — a screen wraps its own content in a `ScrollView`
/// when it needs to, so static screens stay static.
public struct ScreenScaffold<Content: View>: View {
    @Environment(\.instrumentoTheme) private var theme

    private let title: LocalizedStringKey?
    private let overline: LocalizedStringKey?
    @ViewBuilder private let content: () -> Content

    public init(
        title: LocalizedStringKey? = nil,
        overline: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.overline = overline
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            if title != nil || overline != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let overline {
                        Text(overline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    }
                    if let title {
                        Text(title)
                            .font(StrandFont.title1)
                            .foregroundStyle(theme.ink)
                    }
                }
            }
            content()
        }
        .padding(CenitMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.paper.ignoresSafeArea())
    }
}

/// A sober action button — ink label on a hairline-bordered surface. No color:
/// chrome stays quiet so the datum can speak.
public struct QuietButton: View {
    @Environment(\.instrumentoTheme) private var theme
    private let title: LocalizedStringKey
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(minWidth: 44, minHeight: 44)   // iOS minimum touch target (FER-131 handoff · 10)
                .background(theme.surface, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(InstrumentoPressStyle())
    }
}

#if DEBUG
#Preview("Instrumento · scaffold") {
    ScreenScaffold(title: "Hoy", overline: "Martes 16 jun") {
        VStack(alignment: .leading, spacing: 4) {
            Text("RECUPERACIÓN").instrumentoOverline().foregroundStyle(InstrumentoTheme.base.inkTertiary)
            Text("82").instrumentoHero(88).foregroundStyle(InstrumentoTheme.base.dataRecovery)
        }
    }
    .frame(width: 390, height: 600)
}
#endif
