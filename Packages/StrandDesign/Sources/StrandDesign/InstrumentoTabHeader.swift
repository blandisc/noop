import SwiftUI

// MARK: - InstrumentoTabHeader — the shared landing wordmark row
//
// The one header used by «Patrones», «Tendencias» and «Train» so the three tab titles are the same
// size and sit at the same height — swiping between tabs no longer makes the title jump. (FER-557 had
// each screen hand-duplicate the lockup; they drifted: different top insets, and a taller trailing
// element — Entrenar's recovery chip — pushed the title down.)
//
// Layout: a 22×22 glyph + the wordmark on the left, an optional trailing slot on the right. The trailing
// slot is an OVERLAY anchored to the title's own height, so a taller trailing (the recovery chip) centers
// on the title's baseline instead of inflating the row and shoving the title down. The title's vertical
// position depends only on the title lockup — identical on every tab. The caller still owns the screen's
// top inset (keep it the same on all tabs — 14) and any bottom spacing. Pure SwiftUI; no UIKit/AppKit.

/// The «Instrumento» tab/landing header: `glyph` (drawn at 22×22) + `title` on the left, an optional
/// `trailing` slot (date, recovery chip…) on the right. Title is `InstrumentoType.groteskTabTitle` +
/// its tracking (FER-944) in `theme.ink`. The trailing slot never moves the title.
public struct InstrumentoTabHeader<Glyph: View, Trailing: View>: View {
    @Environment(\.instrumentoTheme) private var theme
    private let title: String
    private let glyph: Glyph
    private let trailing: Trailing

    public init(_ title: String,
                @ViewBuilder glyph: () -> Glyph,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.glyph = glyph()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 9) {
            glyph.frame(width: 22, height: 22)
            Text(title)
                .font(InstrumentoType.groteskTabTitle).tracking(InstrumentoType.groteskTabTitleTracking)
                .foregroundStyle(theme.ink)
        }
        // The title lockup is one VoiceOver element labelled by the wordmark; the trailing slot keeps
        // its own (the chip stays a tappable "Recovery …" button) because the overlay is a sibling.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        // Full width so the trailing overlay lands on the right edge; the row's height stays the title's.
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) { trailing }
    }
}

#if DEBUG
#Preview("InstrumentoTabHeader · the three tabs align") {
    VStack(alignment: .leading, spacing: 28) {
        InstrumentoTabHeader("Patrones") {
            PatronesGlyph(color: InstrumentoTheme.base.ink)
        } trailing: {
            Text("THU 12 JUN").font(StrandFont.number(11, weight: .regular))
                .foregroundStyle(InstrumentoTheme.base.inkTertiary).textCase(.uppercase)
        }
        InstrumentoTabHeader("Tendencias") {
            TendenciasGlyph(color: InstrumentoTheme.base.ink)
        } trailing: {
            Text("THU 12 JUN").font(StrandFont.number(11, weight: .regular))
                .foregroundStyle(InstrumentoTheme.base.inkTertiary).textCase(.uppercase)
        }
        // A deliberately TALLER trailing (mimics the recovery chip) — the title must NOT drop.
        InstrumentoTabHeader("Train") {
            Image(systemName: "figure.strengthtraining.functional")
                .font(.system(size: 20)).foregroundStyle(InstrumentoTheme.base.ink)
        } trailing: {
            HStack(spacing: 7) {
                Circle().strokeBorder(InstrumentoTheme.base.dataRecovery, lineWidth: 4).frame(width: 22, height: 22)
                Text("68").font(StrandFont.number(17, weight: .semibold))
            }
            .padding(.leading, 8).padding(.trailing, 11).padding(.vertical, 5)
            .background(InstrumentoTheme.base.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(InstrumentoTheme.base.hairline, lineWidth: 1))
        }
    }
    .padding(.horizontal, 18).padding(.top, 14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}
#endif
