import SwiftUI

// MARK: - Strand Typography (§9.2)
//
// SF Pro (Display ≥20pt, Text <20pt); tabular/monospaced digits everywhere for
// live values. SF Mono for raw/log views. Overline = sparing ALL-CAPS w/ tracking.
//
// All numeric styles use `.monospacedDigit()` so live values don't reflow.
//
// Dynamic Type (FER-394): the reading-text tokens are anchored to native text styles
// (`Font.system(.textStyle)`) so they scale with the user's text-size setting. The DS
// point sizes already sit on Apple's scale (28=.title, 22=.title2, 17=.headline,
// 15=.subheadline, 13=.footnote, 12=.caption, 11=.caption2) → at the default size (L)
// the rendered size is IDENTICAL to the old fixed sizes, with zero call-site changes.
// `display(_:)` / `number(_:)` / `mono(_:)` stay FIXED on purpose: they size numerals
// embedded in geometry (the recovery ring, the dial, chart-driven values), which must
// not move with Dynamic Type. The app caps the upper range at xxxLarge at the root.

public enum StrandFont {

    // MARK: Scale (§9.2)

    /// Display 64–80 / Semibold — the recovery ring number. FIXED size (geometry-driven:
    /// scales with the ring/dial diameter, NOT Dynamic Type). Tabular digits.
    public static func display(_ size: CGFloat = 72) -> Font {
        .system(size: size, weight: .semibold, design: .default).monospacedDigit()
    }

    /// Title1 28 / Bold — scales with Dynamic Type (relative to `.title`, 28pt at default).
    public static let title1 = Font.system(.title, weight: .bold)

    /// Title2 22 / Semibold (relative to `.title2`, 22pt at default).
    public static let title2 = Font.system(.title2, weight: .semibold)

    /// Tab/landing wordmark title 21 / Semibold — «Patrones», «Tendencias», «Train». FIXED (not
    /// Dynamic Type): it's chrome paired with a 22×22 glyph, so the three tab headers must stay the
    /// same size to align as you swipe between tabs. Pair with `.tracking(-0.3)` (or use
    /// `InstrumentoTabHeader`, which bakes both in).
    public static let tabTitle = Font.system(size: 21, weight: .semibold)

    /// Headline 17 / Semibold (relative to `.headline`, 17pt semibold at default).
    public static let headline = Font.system(.headline)

    /// Body 15 / Regular (relative to `.subheadline`, 15pt at default).
    public static let body = Font.system(.subheadline)

    /// Subhead 13 (relative to `.footnote`, 13pt at default).
    public static let subhead = Font.system(.footnote)

    /// Caption 12 (relative to `.caption`, 12pt at default).
    public static let caption = Font.system(.caption)

    /// Footnote 11 (relative to `.caption2`, 11pt at default).
    public static let footnote = Font.system(.caption2)

    /// Unit 13 — the small trailing unit next to a metric value (ms / bpm / %). Subordinate to the
    /// value but a step above footnote so it reads as part of the datum, not chrome.
    /// (relative to `.footnote`, 13pt at default).
    public static let unit = Font.system(.footnote)

    /// Overline 11 / Semibold, +0.8 tracking (apply `.tracking(0.8)` at use site;
    /// `overlineText(_:)` does it for you). Sparing ALL-CAPS labels.
    /// (relative to `.caption2`, 11pt at default).
    public static let overline = Font.system(.caption2, weight: .semibold)

    /// Mono 13 (SF Mono) — raw / log views. Tabular by nature.
    /// (relative to `.footnote`, 13pt at default).
    public static let mono = Font.system(.footnote, design: .monospaced)

    // MARK: Serif — in-screen headlines & verdict phrases ONLY (§2)

    /// `Instrument Serif` (Regular 400) — for in-screen headlines and verdict phrases ONLY
    /// (e.g. "Vienes recuperando mejor."). NEVER a tab name, NEVER a datum, NEVER a numeral —
    /// those stay SF (chrome) and mono (values). The face is Regular-only: don't add `.bold()`
    /// or `.fontWeight(.semibold)` at the call site (it would synthesize an ugly faux-bold).
    /// Bundled with the package (OFL) and registered on first use; scales with Dynamic Type via
    /// `relativeTo` (UIFontMetrics under the hood), so it grows with the reader's text size.
    public static func serif(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title2) -> Font {
        ensureFontsRegistered()
        return .custom("Instrument Serif", size: size, relativeTo: textStyle)
    }

    /// The «Hoy» verdict phrase — the Daily Brief titular ("Vienes recuperando mejor."). Sized a
    /// touch above the old `title2` so the airier serif reads with the same presence (scales w/ `.title2`).
    public static let serifVerdict = serif(25, relativeTo: .title2)

    // MARK: Numeric variants (tabular digits)

    /// A monospaced-digit numeric style at an arbitrary size/weight, for live values.
    public static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default).monospacedDigit()
    }

    /// Monospaced-digit body — for inline live values that should align
    /// (relative to `.subheadline`, 15pt at default; scales with Dynamic Type).
    public static let bodyNumber = Font.system(.subheadline).monospacedDigit()

    /// Monospaced-digit caption — for small live values (sparklines, chips)
    /// (relative to `.caption`, 12pt medium at default; scales with Dynamic Type).
    public static let captionNumber = Font.system(.caption, weight: .medium).monospacedDigit()

    /// Mono at an arbitrary size.
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// The recommended tracking for overline text.
    public static let overlineTracking: CGFloat = 0.8
}

// MARK: - Text helpers

public extension Text {
    /// Style as an overline label: ALL-CAPS, semibold, +0.8 tracking, tertiary text.
    func strandOverline() -> some View {
        self.font(StrandFont.overline)
            .tracking(StrandFont.overlineTracking)
            .textCase(.uppercase)
            .foregroundStyle(InstrumentoTheme.base.inkSecondary)
    }
}

public extension View {
    /// Convenience: an overline-styled label string.
    static func strandOverline(_ string: String) -> some View {
        Text(string).strandOverline()
    }
}

#if DEBUG
#Preview("Typography") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("88").font(StrandFont.display(72)).foregroundStyle(InstrumentoTheme.base.ink)
            Text("Title 1 / Bold 28").font(StrandFont.title1).foregroundStyle(InstrumentoTheme.base.ink)
            Text("Title 2 / Semibold 22").font(StrandFont.title2).foregroundStyle(InstrumentoTheme.base.ink)
            Text("Headline / Semibold 17").font(StrandFont.headline).foregroundStyle(InstrumentoTheme.base.ink)
            Text("Body / Regular 15 — the thread of you, read in full.")
                .font(StrandFont.body).foregroundStyle(InstrumentoTheme.base.ink)
            Text("Subhead 13").font(StrandFont.subhead).foregroundStyle(InstrumentoTheme.base.inkSecondary)
            Text("Caption 12").font(StrandFont.caption).foregroundStyle(InstrumentoTheme.base.inkSecondary)
            Text("Footnote 11").font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
            Text("Overline").strandOverline()
            Text("0xAA 41 00 1c crc32=f3a1  mono 13").font(StrandFont.mono).foregroundStyle(InstrumentoTheme.base.inkSecondary)
            HStack(spacing: 4) {
                Text("HRV").font(StrandFont.caption).foregroundStyle(InstrumentoTheme.base.inkSecondary)
                Text("62").font(StrandFont.bodyNumber).foregroundStyle(InstrumentoTheme.base.ink)
                Text("ms").font(StrandFont.caption).foregroundStyle(InstrumentoTheme.base.inkTertiary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 520, height: 620)
    .background(InstrumentoTheme.base.paper)
    .preferredColorScheme(.light)
}
#endif
