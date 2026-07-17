import SwiftUI

// MARK: - SheetPaper — the sheet paper background (iOS 16.4+ presentationBackground)
//
// Every «Instrumento» detail sheet paints its presentation background with the theme's warm paper.
// Before FER-757 each screen carried its own private copy of this modifier (StrainSheetPaperBackground,
// RitmoSheetPaperBackground, SleepSheetPaperBackground, …); this is the single canonical one.
// The theme is passed EXPLICITLY because `InstrumentoTheme` does not propagate through `.sheet`
// (FER-162) — the sheet root receives it from its presenter and hands it down here.
// On OSes older than iOS 16.4 / macOS 13.3 the modifier is a no-op (the system sheet background stays).

public struct SheetPaper: ViewModifier {
    public let paper: Color

    public init(paper: Color) { self.paper = paper }

    public func body(content: Content) -> some View {
        if #available(iOS 16.4, macOS 13.3, *) {
            content.presentationBackground(paper)
        } else {
            content
        }
    }
}

public extension View {
    /// Paints the sheet's presentation background with the theme's paper. Apply at the sheet's root.
    func sheetPaper(_ theme: InstrumentoTheme) -> some View {
        modifier(SheetPaper(paper: theme.paper))
    }
}

// MARK: - SheetContentHeightKey

/// Carries a sheet's measured natural content height up to size its `.presentationDetents` (FER-112).
/// `reduce` takes the max across all reporters in a frame — the canonical form used by every "size the
/// sheet to its content" caller. The one documented exception is `ReceiptPrinterScreen`'s reveal-mask
/// height, which needs the CURRENT value (not a running max) and keeps its own private key (FER-975).
public struct SheetContentHeightKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Preview

#Preview("sheetPaper") {
    Color.clear.sheet(isPresented: .constant(true)) {
        VStack(spacing: 12) {
            Text("Hoja sobre papel")
                .font(StrandFont.subhead)
                .foregroundStyle(InstrumentoTheme.base.ink)
            Text("El fondo de la presentación es theme.paper, no el gris del sistema.")
                .font(StrandFont.footnote)
                .foregroundStyle(InstrumentoTheme.base.inkSecondary)
        }
        .padding(24)
        .sheetPaper(.base)
    }
}
