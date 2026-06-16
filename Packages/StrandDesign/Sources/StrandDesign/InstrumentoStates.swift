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
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
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
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.paper.ignoresSafeArea())
    }
}

// MARK: - Loading

/// A calm loading state — a quiet breathing pulse and an optional line, both in
/// ink. No spinner (a generic spinner fights the language), no color: nothing
/// has been measured yet.
public struct LoadingStateView: View {
    @Environment(\.instrumentoTheme) private var theme
    private let message: LocalizedStringKey?

    public init(_ message: LocalizedStringKey? = nil) { self.message = message }

    public var body: some View {
        StateContainer {
            BreathingDots()
            if let message {
                Text(message)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message ?? "Cargando")
    }
}

/// Three ink dots that breathe in sequence — the language's quiet activity
/// indicator (physiological motion, not a mechanical spinner). Renders cleanly
/// in `ImageRenderer` (unlike an indeterminate `ProgressView`).
private struct BreathingDots: View {
    @Environment(\.instrumentoTheme) private var theme
    @State private var breathing = false
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(theme.inkSecondary)
                    .frame(width: 9, height: 9)
                    .opacity(breathing ? 0.25 : 0.9)
                    .animation(StrandMotion.breathe.delay(Double(i) * 0.2), value: breathing)
            }
        }
        .onAppear { breathing = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Empty

/// An empty state — an optional orienting glyph, one dominant title, a
/// supporting line, and an optional quiet action. All ink: an empty screen has
/// no datum, so it carries no color.
public struct EmptyStateView: View {
    @Environment(\.instrumentoTheme) private var theme

    private let systemImage: String?
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey?
    private let actionTitle: LocalizedStringKey?
    private let action: (() -> Void)?

    public init(
        systemImage: String? = nil,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        StateContainer {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 38, weight: .regular))
                    .foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(StrandFont.title2)
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                QuietButton(actionTitle, action: action)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Error

/// An error state — same shape as empty, but the glyph carries the one piece of
/// color the language allows here: `critical`, because an error is a genuine
/// alert, not chrome. Optional retry.
public struct ErrorStateView: View {
    @Environment(\.instrumentoTheme) private var theme

    private let title: LocalizedStringKey
    private let message: LocalizedStringKey?
    private let retryTitle: LocalizedStringKey?
    private let retry: (() -> Void)?

    public init(
        title: LocalizedStringKey = "Algo salió mal",
        message: LocalizedStringKey? = nil,
        retryTitle: LocalizedStringKey? = nil,
        retry: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.retry = retry
    }

    public var body: some View {
        StateContainer {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(theme.critical)
                .accessibilityHidden(true)
            Text(title)
                .font(StrandFont.title2)
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let retryTitle, let retry {
                QuietButton(retryTitle, action: retry)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Shared bits

/// Centered, paper-backed column the three states share.
private struct StateContainer<Content: View>: View {
    @Environment(\.instrumentoTheme) private var theme
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 14) {
            content()
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.paper)
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
                .background(theme.surface, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Instrumento · loading") {
    LoadingStateView("Leyendo tu strap…")
        .frame(width: 390, height: 420)
}

#Preview("Instrumento · empty") {
    EmptyStateView(
        systemImage: "bolt.heart",
        title: "Aún no hay datos de hoy",
        message: "Conecta tu strap para ver tu recuperación y esfuerzo del día.",
        actionTitle: "Conectar strap",
        action: {}
    )
    .frame(width: 390, height: 420)
}

#Preview("Instrumento · error") {
    ErrorStateView(
        message: "No pudimos leer tu strap. Revisa que esté cerca y vuelve a intentar.",
        retryTitle: "Reintentar",
        retry: {}
    )
    .frame(width: 390, height: 420)
}

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
