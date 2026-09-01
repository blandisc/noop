import SwiftUI

// MARK: - SheetContentHeightKey

/// Carries a sheet's measured natural content height up to size its `.presentationDetents` (FER-112).
/// `reduce` takes the max across all reporters in a frame — the canonical form used by every "size the
/// sheet to its content" caller. The one documented exception is `ReceiptPrinterScreen`'s reveal-mask
/// height, which needs the CURRENT value (not a running max) and keeps its own private key (FER-975).
public struct SheetContentHeightKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
