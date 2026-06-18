import SwiftUI

// MARK: - Consistency summary (FER-255)
//
// The shared content of the "Consistency" block across the HRV / Stress / Recovery detail sheets.
// The OLD block led with the jargon ("Consistency (CV)") and an abstract "±18% week to week",
// leaving the one word that actually communicates — "steady" / "variable" — demoted at the end as
// an appendage of the number.
//
// This flips the hierarchy: the WORD is the protagonist — "Steady" in verdict green, "Variable" in
// warning amber (steadier is favourable for all three metrics) — with the "±X% week to week" demoted
// quietly below. The coefficient-of-variation definition stays in the block's ⓘ, not on its face.
//
// Binary by design: CV has no calibrated universal thresholds, so a two-bucket call (≤10% = steady)
// promises only what the metric knows. The caller passes the already-rounded CV percentage and keeps
// its own plain-language reading line.

public struct ConsistencySummary: View {
    private let cvPercent: Int
    private let reading: LocalizedStringKey?
    private let theme: InstrumentoTheme

    /// - Parameters:
    ///   - cvPercent: the coefficient of variation as a whole percent (already `cv * 100`, rounded).
    ///   - reading: the screen's plain-language sentence under the datum (kept as-is per metric); nil to omit.
    ///   - theme: the active «Instrumento» theme (it does not propagate through `.sheet`, so pass it).
    public init(cvPercent: Int, reading: LocalizedStringKey? = nil, theme: InstrumentoTheme) {
        self.cvPercent = cvPercent
        self.reading = reading
        self.theme = theme
    }

    /// ≤10% reads as steady — the same threshold the three screens used before (kept deliberately).
    private var isSteady: Bool { cvPercent <= 10 }
    private var word: LocalizedStringKey { isSteady ? "Steady" : "Variable" }
    private var wordColor: Color { isSteady ? theme.verdict : theme.warning }
    /// Built from a String so the key is "%@ week to week" (which localizes) rather than an Int "%lld" key.
    private var spread: LocalizedStringKey { "\("±\(cvPercent)%") week to week" }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(word)
                .font(StrandFont.title2)
                .foregroundStyle(wordColor)
            Text(spread)
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
            if let reading {
                Text(reading)
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Consistency summary") {
    let t = InstrumentoTheme.base
    return VStack(alignment: .leading, spacing: 24) {
        // Steady — ≤10% → verdict green
        ConsistencySummary(cvPercent: 8,
                           reading: "How even it stays from one week to the next. Steadier usually means better rest.",
                           theme: t)
        // Variable — >10% → warning amber
        ConsistencySummary(cvPercent: 18,
                           reading: "How even it stays from one week to the next. Very uneven can be fatigue.",
                           theme: t)
    }
    .padding(24)
    .background(t.paper)
}
#endif
