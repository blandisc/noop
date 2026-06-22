import SwiftUI

// MARK: - DetailBlock — the shared titled-block scaffold for the «Instrumento» detail sheets (FER-…)
//
// Every detail sheet (Recovery, Metric, Sleep) is a stack of titled blocks: a quiet
// «Instrumento» overline + the block's content, with no card-in-card (surface used sparingly,
// hierarchy by space). Each screen had grown its own private `block(...)` helper that drew the
// exact same VStack — overline in tertiary ink, then the content — so this lifts that one
// scaffold into StrandDesign and lets all three sheets share it.
//
// Like `InfoAccordion`, it is a «Instrumento diurno» citizen: token-only, and the theme is
// passed EXPLICITLY because the sheets start a fresh SwiftUI environment (FER-162) — the theme
// does not propagate across a `.sheet` boundary.
//
// Most blocks have no ⓘ: after FER-476 the jargon lives once under «See the method», so only the
// hero keeps an `InfoAccordion`. The optional `info` closure covers the one exception (Sleep's
// "Last night" opens the stages explainer, FER-227): when set, the title row gains a trailing
// `info.circle` button carrying `infoAccessibilityLabel`.
//
// Living in StrandDesign means it can be rendered with `ImageRenderer` in a `swift test`, while
// the *integration* — which blocks exist and the es-MX copy — stays in each screen.

public struct DetailBlock<Content: View>: View {

    /// The block's title, rendered as the «Instrumento» overline (tertiary ink).
    private let title: LocalizedStringKey
    /// The active «Instrumento» theme, passed explicitly (sheets start a fresh environment).
    private let theme: InstrumentoTheme
    /// When set, the title row gains a trailing ⓘ button that runs this closure (e.g. open an explainer).
    private let info: (() -> Void)?
    /// The full VoiceOver label for the ⓘ button. Passed as a complete key so it localizes cleanly.
    /// Ignored when `info` is `nil`.
    private let infoAccessibilityLabel: LocalizedStringKey
    /// The block's own content under the title.
    @ViewBuilder private let content: () -> Content

    public init(
        _ title: LocalizedStringKey,
        theme: InstrumentoTheme,
        info: (() -> Void)? = nil,
        infoAccessibilityLabel: LocalizedStringKey = "",
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.theme = theme
        self.info = info
        self.infoAccessibilityLabel = infoAccessibilityLabel
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer(minLength: 8)
                    Button(action: info) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(theme.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(infoAccessibilityLabel))
                }
            } else {
                Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#if DEBUG
private struct DetailBlockDemo: View {
    let theme = InstrumentoTheme.base
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Plain block — no ⓘ (the common case).
                DetailBlock("Reference range", theme: theme) {
                    Text("48–62 ms · 21 nights")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(theme.ink)
                }
                Rectangle().fill(theme.hairline).frame(height: 1)
                // Block with a trailing ⓘ that opens an explainer.
                DetailBlock(
                    "Last night",
                    theme: theme,
                    info: {},
                    infoAccessibilityLabel: "What the stages mean"
                ) {
                    Text("7 h 12 m · 4 cycles")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(theme.ink)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
    }
}

#Preview("DetailBlock · Instrumento") { DetailBlockDemo() }
#endif
