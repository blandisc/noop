import SwiftUI

// MARK: - InfoAccordion — a per-block ⓘ that discloses a technical explanation (FER-220)
//
// The Detalle de Métrica explains a metric in plain language under each block's datum
// (FER-216). Some blocks also rest on a *statistical* concept — a rolling baseline, a
// coefficient of variation, a linear-regression slope — that the curious reader may want
// spelled out without it shouting at everyone else. `InfoAccordion` is that affordance: a
// discreet ⓘ glyph next to a block's title that, on tap, discloses (accordion-style) a
// quiet technical panel below the block, and collapses it again.
//
// It is a «Instrumento diurno» citizen (token-only, theme passed EXPLICITLY since sheets
// start a fresh environment — same contract as MetricDetailScreen). The look:
//   • title row — the block's overline + a trailing ⓘ (`info.circle`, tertiary ink, quiet);
//   • the block's own content (datum + plain-language reading) via the `content` closure;
//   • the disclosed panel — a left hairline rule + indented `caption` copy in secondary ink,
//     so it reads as a margin note, not another card (no card-in-card).
//
// Collapsed by default. The toggle animates with the house interactive spring. The ⓘ is a
// real `Button` carrying an accessibility label and the `.isExpanded` trait, and the block's
// own VoiceOver content is untouched.
//
// This lives in StrandDesign (not the app) so it can be rendered with `ImageRenderer` in a
// `swift test` and reused by any «Instrumento» block, while the *integration* — which blocks
// get one, and the es-MX copy — stays in `MetricDetailScreen`.

public struct InfoAccordion<Content: View>: View {

    /// The block's title (rendered as the «Instrumento» overline, tertiary ink).
    private let title: LocalizedStringKey
    /// The technical explanation disclosed below the block when expanded.
    private let explanation: LocalizedStringKey
    /// The full VoiceOver label for the ⓘ button (e.g. "Information about your normal range").
    /// Passed as a complete key — not interpolated from `title` — so it localizes cleanly.
    private let accessibilityLabel: LocalizedStringKey
    /// The active «Instrumento» theme, passed explicitly (sheets start a fresh environment).
    private let theme: InstrumentoTheme
    /// The block's own content — its datum and plain-language reading — under the title row.
    @ViewBuilder private let content: () -> Content

    /// An external binding when the parent wants to control/persist the state; `nil` means the
    /// accordion manages its own `@State` (`localExpanded`).
    private let externalExpanded: Binding<Bool>?
    @State private var localExpanded = false

    /// The live expanded state — the external binding if one was given, else the internal `@State`.
    private var isExpanded: Binding<Bool> { externalExpanded ?? $localExpanded }

    /// Bind `isExpanded` to drive the disclosure from the parent (or render a fixed state).
    public init(
        title: LocalizedStringKey,
        explanation: LocalizedStringKey,
        accessibilityLabel: LocalizedStringKey,
        theme: InstrumentoTheme,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.explanation = explanation
        self.accessibilityLabel = accessibilityLabel
        self.theme = theme
        self.externalExpanded = isExpanded
        self.content = content
    }

    /// Self-managed disclosure (the common case): the accordion owns its expanded state.
    public init(
        title: LocalizedStringKey,
        explanation: LocalizedStringKey,
        accessibilityLabel: LocalizedStringKey,
        theme: InstrumentoTheme,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.explanation = explanation
        self.accessibilityLabel = accessibilityLabel
        self.theme = theme
        self.externalExpanded = nil
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row: the quiet overline + the ⓘ button, kept together on one baseline.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                infoButton
                Spacer(minLength: 0)
            }
            content()
            if isExpanded.wrappedValue {
                explanationPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The ⓘ — a discreet, tappable `info.circle`. A real button so VoiceOver announces it and
    /// reflects whether the panel is open (`.isExpanded`).
    private var infoButton: some View {
        Button {
            withAnimation(StrandMotion.interactive) { isExpanded.wrappedValue.toggle() }
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(theme.inkTertiary)
                // A slightly larger, invisible hit target so the small glyph is easy to tap.
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
        // `.isExpanded` isn't in this SwiftUI's AccessibilityTraits, so VoiceOver hears the
        // open/closed state as the button's value ("expanded" / "collapsed") instead.
        .accessibilityValue(Text(isExpanded.wrappedValue ? "expanded" : "collapsed"))
    }

    /// The disclosed panel: a left hairline rule + indented technical copy. A margin note, not a
    /// card — `surface`-free so it never reads as card-in-card.
    private var explanationPanel: some View {
        Text(explanation)
            .font(StrandFont.caption)
            .foregroundStyle(theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .padding(.vertical, 2)
            .overlay(alignment: .leading) {
                Rectangle().fill(theme.hairlineStrong).frame(width: 2)
            }
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#if DEBUG
private struct InfoAccordionDemo: View {
    let theme = InstrumentoTheme.base
    @State private var openConsistency = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Closed by default — "Your normal range".
                InfoAccordion(
                    title: "Your normal range",
                    explanation: "Your personal baseline: a moving average of your recent nights (weighted toward the latest) ± a band of your own variation. A value outside the band is unusual for you, not for the population. It becomes reliable after about 14 nights. (Buchheit 2014)",
                    accessibilityLabel: "Information about your normal range",
                    theme: theme
                ) {
                    Text("48–62 ms · 21 nights")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(theme.ink)
                }
                Rectangle().fill(theme.hairline).frame(height: 1)
                // Bound open — "Consistency (CV)".
                InfoAccordion(
                    title: "Consistency (CV)",
                    explanation: "Coefficient of variation = standard deviation ÷ the mean of your last few weeks. It measures how spread out your values are around your average. Low = steady. In HRV, a rising CV can precede fatigue even while the value still looks high. (Plews 2013)",
                    accessibilityLabel: "Information about consistency",
                    theme: theme,
                    isExpanded: $openConsistency
                ) {
                    Text("±7% week to week · steady")
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

#Preview("InfoAccordion · Instrumento") { InfoAccordionDemo() }
#endif
