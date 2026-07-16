import SwiftUI

// MARK: - ExerciseThumbnail — the reserved media slot for an EDB exercise (FER-751)
//
// Placeholder-first: a rounded paper-gradient tile that reserves the EXACT space the real
// exercise thumb/loop (FER-722) will fill later. Reserving the slot everywhere now means
// FER-722 changes ONE component, not N screens — and the layout never shifts when the media
// lands (same slot, same dimensions). Offline by contract: the placeholder never touches the
// network; the fill (`image`) is an optional hook FER-722 sets once media is cached.
//
// Two forms, one look — a warm `hairline → hairlineStrong` gradient (the handoff swatch), no
// play glyph: the row thumbnail reads as a still image, and the exercise sheet's video control
// (auto-play + top-right play/pause, Hevy-style) is FER-722's job, not the placeholder's.
//   • `.init(side:)` — the square row tile: 1d 40 · 1j/1k 44 · 1f 48 · 1i 54.
//   • `.init(hero:)`  — the full-width SQUARE hero on the exercise sheet (1g/1h). Square because the
//     ExerciseDB media is a square GIF; a square slot shows the whole animation with no crop (FER-790).

public struct ExerciseThumbnail: View {
    @Environment(\.instrumentoTheme) private var theme

    private enum Form {
        case tile(side: CGFloat)      // square row thumbnail; corner scales with the side
        case hero                     // full-width square banner; fixed corner
    }

    private let form: Form
    /// The cached media, once FER-722 has it. `nil` today → the paper placeholder. Filling it
    /// keeps the exact same frame, so no screen recomposes its layout.
    private let image: Image?

    /// The hero form's corner radius, exposed so a caller overlaying extra content (e.g. a playing
    /// video loop, FER-778) can clip it to the exact same shape as the reserved slot.
    public static let heroCornerRadius: CGFloat = 16

    /// The hero banner's fixed height (handoff «Detalle de Ejercicio»: 176px) — full-width but no
    /// longer a square, so the segmented control and the datum stay above the fold on a 390pt phone.
    public static let heroHeight: CGFloat = 176

    /// A square row thumbnail (1d 40 · 1j/1k 44 · 1f 48 · 1i 54 pt).
    public init(side: CGFloat, image: Image? = nil) {
        self.form = .tile(side: side)
        self.image = image
    }

    /// The full-width square hero on the exercise sheet (1g/1h).
    public init(hero image: Image? = nil) {
        self.form = .hero
        self.image = image
    }

    private var corner: CGFloat {
        switch form {
        case .tile(let side): return side * 0.22   // 40→9 · 44→10 · 48→11 · 54→12, matching the handoff
        case .hero:           return Self.heroCornerRadius
        }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        shape
            .fill(
                LinearGradient(
                    colors: [theme.hairline, theme.hairlineStrong],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay {
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(shape)
                }
            }
            .modifier(FrameForForm(form: form))
            .accessibilityHidden(true)   // decorative — the exercise name carries the meaning
    }

    private struct FrameForForm: ViewModifier {
        let form: Form
        func body(content: Content) -> some View {
            switch form {
            case .tile(let side):
                content.frame(width: side, height: side)
            case .hero:
                content.frame(maxWidth: .infinity).frame(height: ExerciseThumbnail.heroHeight)
            }
        }
    }
}

#if DEBUG
#Preview("ExerciseThumbnail · placeholder") {
    VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 12) {
            ForEach([40, 44, 48, 54] as [CGFloat], id: \.self) { side in
                VStack(spacing: 6) {
                    ExerciseThumbnail(side: side)
                    Text("\(Int(side))").font(.caption2).foregroundStyle(InstrumentoTheme.base.inkTertiary)
                }
            }
        }
        ExerciseThumbnail(hero: nil)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}
#endif
