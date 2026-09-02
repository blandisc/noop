import SwiftUI

// MARK: - AuthoredGlyph — shared scaffold for the authored brand-mark glyphs (FER-903)
//
// The «Tendencias» and «Patrones» wordmark glyphs are the only two design-system glyphs that share a
// structure: an authored 24×24 coordinate space, scaled to fit whatever frame the caller gives it,
// decorative (no accessibility text — the label lives on the wordmark beside them). They differ ONLY
// in what they draw into that space (Tendencias strokes a polyline AND fills node dots; Patrones
// strokes a single circles-and-elbow path), so the scaffold — not the drawing — is what's shared.
//
// This wraps just that scaffold. It deliberately does NOT try to unify the drawing behind a single
// `pathBuilder`: that would force Tendencias' two-pass stroke+fill and Patrones' single stroke into a
// false common shape, adding more indirection than the ~3 lines of boilerplate it removes. The other
// three «glyphs» (`MetricGlyph` is an SF-Symbol table, `DialTabGlyph` is a `Canvas` dial, `InsightGlyph`
// is a data-driven mark) share no structure with these and stay separate. Pure SwiftUI.

/// A decorative brand-mark glyph authored in a 24×24 box and scaled to fit. The `content` closure
/// receives the scale factor `s` (points per authored unit) and draws into the scaled space.
struct AuthoredGlyph<Content: View>: View {
    private let content: (_ scale: CGFloat) -> Content

    init(@ViewBuilder content: @escaping (_ scale: CGFloat) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            content(min(geo.size.width, geo.size.height) / 24)
        }
        .accessibilityHidden(true)
    }
}
